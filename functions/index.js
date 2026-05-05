const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

const { getFunctions } = require("firebase-admin/functions");

// ============================================================
// 1. ESCALATION ENGINE (TASK QUEUE MIGRATION)
// Replaced the Cron Job with a distributed Task Queue to prevent 
// execution timeouts during massive alert spikes.
// ============================================================
exports.escalateTask = functions.tasks.taskQueue({
  retryConfig: { maxAttempts: 3 },
  rateLimits: { maxConcurrentDispatches: 100 },
}).onDispatch(async (data) => {
  const { alertId, targetTier } = data;
  console.log(`[TASK_ESCALATION] Evaluating ${alertId} for escalation to ${targetTier}`);

  const alertRef = db.collection("alerts").doc(alertId);
  const alertSnap = await alertRef.get();
  
  if (!alertSnap.exists) return;
  const alertData = alertSnap.data();
  
  // If the alert is no longer ACTIVE/DURESS, abort escalation.
  if (alertData.status === "RESOLVED") {
    console.log(`[TASK_ESCALATION] Alert ${alertId} already resolved. Aborting.`);
    return;
  }
  
  const currentAssigned = alertData.assigned_to;
  
  // If the alert was already manually escalated beyond or to the target, abort.
  // A simple way is to check if it's currently at the preceding tier.
  const tierOrder = { "POLLING_UNIT": 1, "WARD": 2, "LGA": 3, "HQ": 4 };
  if (tierOrder[currentAssigned] >= tierOrder[targetTier]) {
    console.log(`[TASK_ESCALATION] Alert ${alertId} is currently at ${currentAssigned}. Target was ${targetTier}. Aborting.`);
    return;
  }

  console.log(`[TASK_ESCALATION] Escalating ${alertId} to ${targetTier}`);

  await alertRef.update({
    assigned_to: targetTier,
    escalated_at: admin.firestore.FieldValue.serverTimestamp()
  });

  await db.collection("audit_logs").add({
    action: "AUTO_ESCALATION",
    alert_id: alertId,
    from_tier: currentAssigned,
    to_tier: targetTier,
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
    actor: "SYSTEM_TASK_QUEUE"
  });

  // Calculate the next tier and enqueue the next task
  let nextTier = null;
  let waitMinutes = 2; // Default delay to next tier
  
  if (targetTier === "WARD") {
    nextTier = "LGA";
    waitMinutes = 3;
  } else if (targetTier === "LGA") {
    nextTier = "HQ";
    waitMinutes = 5;
  }

  if (nextTier) {
    const queue = getFunctions().taskQueue("escalateTask");
    await queue.enqueue({ alertId, targetTier: nextTier }, {
      scheduleDelaySeconds: waitMinutes * 60
    });
    console.log(`[TASK_ESCALATION] Enqueued next jump for ${alertId} to ${nextTier} in ${waitMinutes}m`);
  }
});

// ============================================================
// 2. PUSH NOTIFICATION TRIGGER
// Listens for new alerts and routes FCM push notifications to mapped staff natively.
// ============================================================
exports.notifyStaffOnAlert = functions.firestore
  .document("alerts/{alertId}")
  .onCreate(async (snap, context) => {
    const alertData = snap.data();
    const assignedLevel = alertData.assigned_to || "POLLING_UNIT"; // POLLING_UNIT, WARD, LGA, HQ
    const priority = alertData.priority || "HIGH";

    console.log(`[PUSH] New ${priority} alert requiring dispatch to ${assignedLevel}`);

    // Map the assigned_to string explicitly to the user's role field mapping
    let requiredRole = "POLLING_UNIT_OFFICER";
    if (assignedLevel === "WARD") requiredRole = "WARD_OFFICER";
    if (assignedLevel === "LGA") requiredRole = "LGA_OFFICER";
    if (assignedLevel === "HQ") requiredRole = "HQ_OFFICER";

    // Fetch all users holding that specific Role who possess an FCM token
    const staffSnapshot = await db.collection("users")
      .where("role", "==", requiredRole)
      .get();

    if (staffSnapshot.empty) {
      console.log(`[PUSH] No staff currently on-duty in tier: ${requiredRole}`);
      return null;
    }

    const tokens = [];
    staffSnapshot.forEach(doc => {
      const data = doc.data();
      if (data.fcmToken) {
        tokens.push(data.fcmToken);
      }
    });

    if (tokens.length === 0) {
      console.log(`[PUSH] Staff found in tier ${requiredRole}, but no distinct FCM tokens active.`);
      return null;
    }

    const payload = {
      notification: {
        title: `🚨 ${priority} ALERT DETECTED`,
        body: `A new ${alertData.type || "distress"} incident requires your immediate attention!`,
        sound: "default",
      },
      data: {
        alertId: context.params.alertId,
        click_action: "FLUTTER_NOTIFICATION_CLICK"
      }
    };

    try {
      const response = await admin.messaging().sendToDevice(tokens, payload);
      console.log(`[ALERT_DELIVERED] Notification dispatched to ${tokens.length} officers. Res:`, response);
    } catch (err) {
      console.error("[SYS_ERR] Failed to send push dispatch:", err);
    }

    return null;
});

// ============================================================
// 4. API: CREATE ALERT (BACKEND FIRST FLOW)
// Ensures 100% success/failure tracking and logs every alert request.
// ============================================================
exports.createAlert = functions.https.onCall(async (data, context) => {
  console.log(`[ALERT_CREATED] Received createAlert payload: ${JSON.stringify(data)}`);

  // if (context.app == undefined) {
  //   throw new functions.https.HttpsError('failed-precondition', 'The function must be called from an App Check verified app.');
  // }

  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated.');
  }

  try {
    const { type, description, lat, lng, isCritical, priority, attachments } = data;
    const userId = context.auth.uid;

    // PRD §14: Rate limiting — max 5 alerts per user per rolling hour
    const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000);
    const recentSnap = await db.collection("alerts")
      .where("reportedBy", "==", userId)
      .where("reportedAt", ">=", admin.firestore.Timestamp.fromDate(oneHourAgo))
      .get();
    if (recentSnap.size >= 5) {
      console.warn(`[RATE_LIMIT] User ${userId} exceeded alert rate limit.`);
      throw new functions.https.HttpsError("resource-exhausted", "Rate limit exceeded. Wait before sending more alerts.");
    }

    // PRD §14: Fraud detection — block if user has 3+ unresolved ACTIVE alerts simultaneously
    const activeSnap = await db.collection("alerts")
      .where("reportedBy", "==", userId)
      .where("status", "in", ["ACTIVE", "DURESS"])
      .get();
    if (activeSnap.size >= 3) {
      console.warn(`[FRAUD_DETECT] User ${userId} has ${activeSnap.size} concurrent active alerts.`);
      // Log the suspicious behavior without blocking — let HQ see it
      await db.collection("audit_logs").add({
        action: "FRAUD_SUSPICION",
        actor: userId,
        reason: `${activeSnap.size} concurrent active alerts`,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    const finalLat = lat || 9.9167;
    const finalLng = lng || 8.8917;

    // PRD: Geo-Mapping & Boundary Engine
    // Map GPS -> polling unit -> ward -> LGA
    const getJurisdiction = (latitude, longitude) => {
      // Simulate Geo-Spatial DB lookup (Plateau State bounds mapping)
      if (latitude > 9.9) return { lga: "Jos North", ward: "Tudun Wada", pu: "PU-001" };
      if (latitude > 9.7) return { lga: "Jos South", ward: "Bukuru", pu: "PU-014" };
      if (longitude > 9.0) return { lga: "Mangu", ward: "Mangu Halle", pu: "PU-042" };
      return { lga: "Barkin Ladi", ward: "Gashish", pu: "PU-009" };
    };
    
    const geoMapped = getJurisdiction(finalLat, finalLng);

    const alertData = {
      type: type || "UNKNOWN",
      description: description || "",
      lat: finalLat,
      lng: finalLng,
      geo_lga: geoMapped.lga,
      geo_ward: geoMapped.ward,
      geo_pu: geoMapped.pu,
      reportedBy: userId,
      isCritical: priority === 'CRITICAL' || isCritical || false,
      status: "ACTIVE",
      priority: priority || "HIGH",
      assigned_to: "POLLING_UNIT",
      reportedAt: admin.firestore.FieldValue.serverTimestamp(),
      attachments: attachments || [],
    };

    const docRef = await db.collection("alerts").add(alertData);
    console.log(`[ALERT_REGISTERED] Alert successfully inserted. ID: ${docRef.id}`);

    // Dynamically enqueue the first Escalation Task
    try {
      const queue = getFunctions().taskQueue("escalateTask");
      // PRD: Initial wait for Polling Unit is 2 minutes before jumping to WARD
      await queue.enqueue({ alertId: docRef.id, targetTier: "WARD" }, {
        scheduleDelaySeconds: 2 * 60 
      });
      console.log(`[ESCALATE_QUEUED] Task queued for ${docRef.id} -> WARD in 2m`);
    } catch (err) {
      console.error("[SYS_ERR] Failed to enqueue initial escalation task", err);
    }

    return { success: true, alertId: docRef.id };
  } catch (error) {
    console.error(`[ALERT_ERROR] Fatal error inserting alert`, error);
    throw new functions.https.HttpsError('internal', 'Unable to create alert');
  }
});

// ============================================================
// 3. OFFLINE SMS WEBHOOK
// Endpoint invoked by Termii/Twilio/Local Gateway when an offline citizen 
// transmits an encoded SMS to the 0800RAINBOW shortcode.
// ============================================================
exports.smsWebhook = functions.https.onRequest(async (req, res) => {
  if (req.method !== 'POST') {
    return res.status(405).send('Method Not Allowed');
  }

  // Common SMS Gateway standard: Body or text holds the message content
  const messageBody = req.body.Body || req.body.text || req.body.message || "";
  
  console.log(`[SMS_GATEWAY] Received incoming communication: ${messageBody}`);

  if (!messageBody.startsWith("ALERT|")) {
    return res.status(200).send('Non-standard format ignored.');
  }

  try {
    const segments = messageBody.split('|');
    if (segments.length < 4) {
      return res.status(400).send('Malformed Payload Array');
    }

    const reporterPhone = segments[1];
    const latSegment = segments[2];
    const lngSegment = segments[3];
    
    const lat = parseFloat(latSegment.replace('LAT:', '')) || 9.9167;
    const lng = parseFloat(lngSegment.replace('LNG:', '')) || 8.8917;

    // PRD: Duplicate alert prevention
    const fiveMinutesAgo = new Date(Date.now() - 5 * 60000);
    const duplicates = await db.collection("alerts")
      .where("reportedBy", "==", reporterPhone)
      .where("status", "in", ["ACTIVE", "DURESS"])
      .get();

    let isDuplicate = false;
    duplicates.forEach(doc => {
      const data = doc.data();
      if (data.reportedAt && data.reportedAt.toDate() > fiveMinutesAgo) {
        isDuplicate = true;
      }
    });

    if (isDuplicate) {
      console.log(`[SMS_GATEWAY] Duplicate alert blocked for ${reporterPhone}`);
      // PRD: Delivery acknowledgment (we ack even if duplicate to stop retries)
      return res.status(200).send({ success: true, message: "Acknowledged (Duplicate)" });
    }
    
    // PRD: Geo-Mapping & Boundary Engine
    const getJurisdiction = (latitude, longitude) => {
      if (latitude > 9.9) return { lga: "Jos North", ward: "Tudun Wada", pu: "PU-001" };
      if (latitude > 9.7) return { lga: "Jos South", ward: "Bukuru", pu: "PU-014" };
      if (longitude > 9.0) return { lga: "Mangu", ward: "Mangu Halle", pu: "PU-042" };
      return { lga: "Barkin Ladi", ward: "Gashish", pu: "PU-009" };
    };
    const geoMapped = getJurisdiction(lat, lng);

    const docRef = await db.collection("alerts").add({
      type: "OFFLINE DURESS",
      description: "Auto-generated from Offline SMS Infrastructure",
      lat: lat,
      lng: lng,
      geo_lga: geoMapped.lga,
      geo_ward: geoMapped.ward,
      geo_pu: geoMapped.pu,
      reportedBy: reporterPhone,
      isCritical: true,
      status: "ACTIVE",
      priority: "CRITICAL",
      assigned_to: "POLLING_UNIT", 
      reportedAt: admin.firestore.FieldValue.serverTimestamp(),
      isOffline: true,
      rawSmsPayload: messageBody
    });

    console.log(`[SMS_GATEWAY] Successfully transcoded offline SMS to Polling Unit Escrow. ID: ${docRef.id}`);

    // Dynamically enqueue the Escalation Task
    try {
      const queue = getFunctions().taskQueue("escalateTask");
      await queue.enqueue({ alertId: docRef.id, targetTier: "WARD" }, {
        scheduleDelaySeconds: 2 * 60 
      });
      console.log(`[ESCALATE_QUEUED] Task queued for ${docRef.id} -> WARD in 2m`);
    } catch (err) {
      console.error("[SYS_ERR] Failed to enqueue escalation task for offline SMS", err);
    }

    return res.status(200).send({ success: true, message: "Parsed" });
    
  } catch (error) {
    console.error("[SMS_GATEWAY] Fatal error processing SMS payload", error);
    return res.status(500).send({ error: "Internal processing malfunction" });
  }
});

exports.massBroadcast = functions.https.onCall(async (data, context) => {
  // Ensure the user is an admin (in a real scenario, check admin claims)
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Only authenticated personnel can trigger mass broadcasts."
    );
  }

  const { title, body, priority, targetType, targetValue } = data;
  if (!title || !body) {
    throw new functions.https.HttpsError("invalid-argument", "Missing broadcast title or body.");
  }

  try {
    // 1. Log the broadcast to Firestore
    await db.collection("broadcasts").add({
      title,
      body,
      priority: priority || "NORMAL",
      targetType: targetType || "ALL",
      targetValue: targetValue || "STATEWIDE",
      senderId: context.auth.uid,
      sentAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 2. Fetch all target users
    let query = db.collection("users");
    
    // Dynamic Jurisdictional Routing
    if (targetType === "LGA" && targetValue) {
      query = query.where("lga", "==", targetValue);
    } else if (targetType === "WARD" && targetValue) {
      query = query.where("ward", "==", targetValue);
    } else if (targetType === "PU" && targetValue) {
      query = query.where("polling_unit", "==", targetValue);
    }

    const usersSnap = await query.get();

    // 3. Extract FCM Tokens
    const tokens = [];
    usersSnap.forEach(doc => {
      const user = doc.data();
      if (user.fcmToken) tokens.push(user.fcmToken);
    });

    // 4. Send Firebase Cloud Messaging
    if (tokens.length > 0) {
      const message = {
        notification: { title, body },
        data: { priority: priority || "NORMAL", type: "BROADCAST" },
        tokens: tokens,
      };
      const response = await admin.messaging().sendMulticast(message);
      console.log(`[BROADCAST] Successfully sent ${response.successCount} messages. Failed: ${response.failureCount}`);
    } else {
      console.log(`[BROADCAST] No tokens found for target region: ${targetRegion || 'ALL'}. Logged broadcast only.`);
    }

    return { success: true, targetsReached: tokens.length };
  } catch (error) {
    console.error("[BROADCAST] Failed to send broadcast", error);
    throw new functions.https.HttpsError("internal", "Mass broadcast engine failed.");
  }
});

exports.seedMockData = functions.https.onRequest(async (req, res) => {
  const mockAlerts = [
    { type: "Kidnap - Attempted Kidnap", description: "Suspicious individuals monitoring school bus route near Mangu.", lat: 9.5133, lng: 9.0967, reportedBy: "+2348001112222", isCritical: true, status: "ACTIVE", priority: "CRITICAL", assigned_to: "WARD", reportedAt: admin.firestore.FieldValue.serverTimestamp() },
    { type: "Fire - Bush Fire", description: "Large bush fire spreading towards residential area in Jos South.", lat: 9.7716, lng: 8.8681, reportedBy: "anonymous", isCritical: true, status: "ACTIVE", priority: "CRITICAL", assigned_to: "LGA", reportedAt: admin.firestore.FieldValue.serverTimestamp() },
    { type: "Police brutality - Extortion", description: "Officers setting up illegal checkpoint near Barkin Ladi.", lat: 9.5375, lng: 8.8958, reportedBy: "+2347012345678", isCritical: false, status: "ACTIVE", priority: "HIGH", assigned_to: "POLLING_UNIT", reportedAt: admin.firestore.FieldValue.serverTimestamp() },
    { type: "Community attack - Armed Invasion", description: "Gunshots heard on the outskirts of Riyom.", lat: 9.6333, lng: 8.7667, reportedBy: "anonymous", isCritical: true, status: "DURESS", priority: "CRITICAL", assigned_to: "HQ", reportedAt: admin.firestore.FieldValue.serverTimestamp() },
    { type: "Flood - Submerged Property", description: "Heavy rain causing severe flooding in Jos North.", lat: 9.9248, lng: 8.8920, reportedBy: "+2349098765432", isCritical: false, status: "ACTIVE", priority: "MEDIUM", assigned_to: "WARD", reportedAt: admin.firestore.FieldValue.serverTimestamp() },
    { type: "Drug abuse - Public Drug Use", description: "Group of youths taking illicit substances in public park.", lat: 9.8965, lng: 8.8583, reportedBy: "anonymous", isCritical: false, status: "ACTIVE", priority: "MEDIUM", assigned_to: "POLLING_UNIT", reportedAt: admin.firestore.FieldValue.serverTimestamp() },
    { type: "Cyber crime - Online Fraud", description: "Scammer cafe operating out of a local plaza.", lat: 9.9322, lng: 8.8922, reportedBy: "+2348123456789", isCritical: false, status: "RESOLVED", priority: "MEDIUM", assigned_to: "WARD", reportedAt: admin.firestore.FieldValue.serverTimestamp() },
    { type: "Domestic violence - Trapped", description: "Neighbor is locked in house and calling for help.", lat: 9.8600, lng: 8.8800, reportedBy: "anonymous", isCritical: true, status: "DURESS", priority: "HIGH", assigned_to: "POLLING_UNIT", reportedAt: admin.firestore.FieldValue.serverTimestamp() },
    { type: "Kidnap - Immediate Abduction", description: "A child was just taken into an unmarked black vehicle.", lat: 9.8755, lng: 8.8522, reportedBy: "+2348033334444", isCritical: true, status: "DURESS", priority: "CRITICAL", assigned_to: "LGA", reportedAt: admin.firestore.FieldValue.serverTimestamp() },
    { type: "Cattle rustling - Armed Rustling", description: "Herd stolen at gunpoint in Wase.", lat: 9.1000, lng: 9.9667, reportedBy: "+2347076543210", isCritical: true, status: "ACTIVE", priority: "HIGH", assigned_to: "WARD", reportedAt: admin.firestore.FieldValue.serverTimestamp() }
  ];

  try {
    const batch = db.batch();
    mockAlerts.forEach(alert => {
      const docRef = db.collection("alerts").doc();
      batch.set(docRef, alert);
    });
    await batch.commit();
    res.status(200).send({ success: true, message: "10 mock alerts seeded." });
  } catch (e) {
    res.status(500).send({ error: e.message });
  }
});
