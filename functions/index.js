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
// ============================================================
// 1. DISTRIBUTED ESCALATION HANDLER (Task Queue)
// Processes deferred escalation jumps to move incidents up the 
// hierarchy automatically if they remain unresolved.
// ============================================================
exports.escalateTask = functions.tasks.taskQueue('escalateTask').onDispatch(async (data) => {
  const { alertId, targetTier } = data;
  console.log(`[TASK_ESCALATION] Evaluating ${alertId} for escalation to ${targetTier}`);

  const alertRef = db.collection("alerts").doc(alertId);
  const alertSnap = await alertRef.get();
  
  if (!alertSnap.exists) return;
  const alertData = alertSnap.data();
  
  if (alertData.status === "RESOLVED") {
    console.log(`[TASK_ESCALATION] Alert ${alertId} already resolved. Aborting.`);
    return;
  }
  
  const currentAssigned = alertData.assigned_to;
  const tierOrder = { "POLLING_UNIT": 1, "WARD": 2, "LGA": 3, "HQ": 4 };
  if (tierOrder[currentAssigned] >= tierOrder[targetTier]) {
    console.log(`[TASK_ESCALATION] Alert ${alertId} is currently at ${currentAssigned}. Target was ${targetTier}. Aborting.`);
    return;
  }

  console.log(`[TASK_ESCALATION] Escalating ${alertId} to ${targetTier}`);

  await alertRef.update({
    assigned_to: targetTier,
    last_edited_by: "SYSTEM_AUTO_ESCALATION",
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
  if (targetTier === "WARD") nextTier = "LGA";
  else if (targetTier === "LGA") nextTier = "HQ";

  if (nextTier) {
    const configSnap = await db.collection("system").doc("config").get();
    const thresholds = configSnap.exists ? (configSnap.data().escalation_thresholds || {}) : {};
    const waitMinutes = thresholds[targetTier] || (targetTier === "WARD" ? 5 : 10);

    const queue = getFunctions().taskQueue("escalateTask");
    await queue.enqueue({ alertId, targetTier: nextTier }, {
      scheduleDelaySeconds: waitMinutes * 60
    });
    console.log(`[TASK_ESCALATION] Enqueued next jump for ${alertId} to ${nextTier} in ${waitMinutes}m`);
  }
});

// ============================================================
// 2. PUSH NOTIFICATION TRIGGER (MULTI-TIER)
// Listens for new alerts and updates to route FCM push notifications 
// to the relevant jurisdictional tier.
// ============================================================
const sendPushToTier = async (alertId, alertData) => {
  const assignedLevel = alertData.assigned_to || "POLLING_UNIT";
  const priority = alertData.priority || "HIGH";

  console.log(`[PUSH] Dispatching notification for alert ${alertId} to ${assignedLevel}`);

  let requiredRole = "POLLING_UNIT_OFFICER";
  if (assignedLevel === "WARD") requiredRole = "WARD_OFFICER";
  if (assignedLevel === "LGA") requiredRole = "LGA_OFFICER";
  if (assignedLevel === "HQ") requiredRole = "HQ_OFFICER";

  const staffSnapshot = await db.collection("users").where("role", "==", requiredRole).get();

  if (staffSnapshot.empty) {
    console.log(`[PUSH] No staff currently on-duty in tier: ${requiredRole}`);
    return;
  }

  const tokens = [];
  staffSnapshot.forEach(doc => {
    const data = doc.data();
    if (data.fcmToken) tokens.push(data.fcmToken);
  });

  if (tokens.length === 0) return;

  const payload = {
    notification: {
      title: `🚨 ${priority} ALERT DETECTED`,
      body: `Alert ${alertId} requires immediate attention at ${assignedLevel} tier!`,
      sound: "default",
    },
    data: { alertId, click_action: "FLUTTER_NOTIFICATION_CLICK" }
  };

  try {
    await admin.messaging().sendToDevice(tokens, payload);
    console.log(`[ALERT_DELIVERED] Notification dispatched to ${tokens.length} ${requiredRole} officers.`);
  } catch (err) {
    console.error("[SYS_ERR] Failed to send push dispatch:", err);
  }
};

exports.notifyStaffOnAlert = functions.firestore
  .document("alerts/{alertId}")
  .onCreate(async (snap, context) => {
    return sendPushToTier(context.params.alertId, snap.data());
});

exports.logAlertChanges = functions.firestore
  .document("alerts/{alertId}")
  .onUpdate(async (change, context) => {
    const newData = change.after.data();
    const oldData = change.before.data();
    const alertId = context.params.alertId;

    const auditRef = db.collection("audit_logs");
    const timestamp = admin.firestore.FieldValue.serverTimestamp();

    // 1. Log Escalations (Assigned Tier Changed)
    if (newData.assigned_to !== oldData.assigned_to) {
      await auditRef.add({
        action: "TIER_HANDOFF",
        alert_id: alertId,
        from_tier: oldData.assigned_to,
        to_tier: newData.assigned_to,
        actor: newData.last_edited_by || "AGENT_OR_SYSTEM",
        timestamp
      });
    }

    // 2. Log Acknowledgments (Responder Assigned)
    if (newData.responder && !oldData.responder) {
      await auditRef.add({
        action: "AGENT_ACKNOWLEDGED",
        alert_id: alertId,
        actor: newData.responder,
        timestamp
      });
    }

    // 3. Log Resolutions
    if (newData.status === "RESOLVED" && oldData.status !== "RESOLVED") {
      await auditRef.add({
        action: "INCIDENT_RESOLVED",
        alert_id: alertId,
        actor: newData.resolved_by || newData.responder || "HQ_COMMAND",
        timestamp
      });
    }

    // PUSH NOTIFICATION LOGIC (Existing)
    if (newData.assigned_to !== oldData.assigned_to && newData.status !== "RESOLVED") {
      console.log(`[ESCALATION_PUSH] Alert ${alertId} moved from ${oldData.assigned_to} to ${newData.assigned_to}`);
      return sendPushToTier(alertId, newData);
    }
    return null;
});

// ============================================================
// 4. API: CREATE ALERT (BACKEND FIRST FLOW)
// Ensures 100% success/failure tracking and logs every alert request.
// ============================================================
exports.createAlert = functions.https.onCall(async (data, context) => {
  console.log(`[ALERT_CREATED] Received createAlert payload: ${JSON.stringify(data)}`);

  if (context.app === undefined) {
    throw new functions.https.HttpsError('failed-precondition', 'The function must be called from an App Check verified app.');
  }

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
      // Point-in-Polygon helper for production-grade spatial routing
      const isPointInPolygon = (point, vs) => {
        const x = point[0], y = point[1];
        let inside = false;
        for (let i = 0, j = vs.length - 1; i < vs.length; j = i++) {
          const xi = vs[i][0], yi = vs[i][1];
          const xj = vs[j][0], yj = vs[j][1];
          const intersect = ((yi > y) !== (yj > y)) && (x < (xj - xi) * (y - yi) / (yj - yi) + xi);
          if (intersect) inside = !inside;
        }
        return inside;
      };

      // Tactical Boundaries (Simplified for demonstration, should be loaded from plateau_boundaries.json in prod)
      const boundaries = [
        {
          lga: "Jos North",
          ward: "Tudun Wada",
          pu: "PU-001",
          coords: [[8.85, 9.95], [8.95, 9.95], [8.95, 9.85], [8.85, 9.85]]
        },
        {
          lga: "Jos South",
          ward: "Bukuru",
          pu: "PU-014",
          coords: [[8.80, 9.85], [8.95, 9.85], [8.95, 9.70], [8.80, 9.70]]
        },
        {
          lga: "Mangu",
          ward: "Mangu Halle",
          pu: "PU-042",
          coords: [[8.90, 9.60], [9.30, 9.60], [9.30, 9.20], [8.90, 9.20]]
        }
      ];

      for (const boundary of boundaries) {
        if (isPointInPolygon([longitude, latitude], boundary.coords)) {
          return { lga: boundary.lga, ward: boundary.ward, pu: boundary.pu };
        }
      }

      return { lga: "Statewide HQ", ward: "General Dispatch", pu: "HQ-000" };
    };
    
    const geoMapped = (data.geo_lga && data.geo_ward && data.geo_pu)
      ? { lga: data.geo_lga, ward: data.geo_ward, pu: data.geo_pu }
      : getJurisdiction(finalLat, finalLng);

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

    // PRD: Dynamic Thresholds from System Config
    const configSnap = await db.collection("system").doc("config").get();
    const thresholds = configSnap.exists ? (configSnap.data().escalation_thresholds || {}) : { POLLING_UNIT: 2 };
    const waitMinutes = thresholds.POLLING_UNIT || 2;

    // Dynamically enqueue the first Escalation Task
    try {
      const queue = getFunctions().taskQueue("escalateTask");
      await queue.enqueue({ alertId: docRef.id, targetTier: "WARD" }, {
        scheduleDelaySeconds: waitMinutes * 60 
      });
      console.log(`[ESCALATE_QUEUED] Task queued for ${docRef.id} -> WARD in ${waitMinutes}m`);
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
    const typeCode = segments[2];
    const latSegment = segments[3];
    const lngSegment = segments[4];
    
    const lat = parseFloat(latSegment.replace('LAT:', '')) || 9.9167;
    const lng = parseFloat(lngSegment.replace('LNG:', '')) || 8.8917;

    // Reverse mapping for SMS types
    const typeMap = {
      'KD': 'Kidnap', 'FR': 'Fire', 'DA': 'Drug abuse', 'PB': 'Police brutality',
      'FL': 'Flood', 'CC': 'Cyber crime', 'CA': 'Child abuse', 
      'DV': 'Domestic violence', 'CR': 'Cattle rustling', 'CM': 'Community attack',
      'OT': 'Other'
    };
    const alertType = typeMap[typeCode] || 'Unknown Incident';

    // PRD: Duplicate alert prevention
    const fiveMinutesAgo = new Date(Date.now() - 5 * 60000);
    const duplicates = await db.collection("alerts")
      .where("reportedBy", "==", reporterPhone)
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
      const isPointInPolygon = (point, vs) => {
        const x = point[0], y = point[1];
        let inside = false;
        for (let i = 0, j = vs.length - 1; i < vs.length; j = i++) {
          const xi = vs[i][0], yi = vs[i][1];
          const xj = vs[j][0], yj = vs[j][1];
          const intersect = ((yi > y) !== (yj > y)) && (x < (xj - xi) * (y - yi) / (yj - yi) + xi);
          if (intersect) inside = !inside;
        }
        return inside;
      };

      const boundaries = [
        { lga: "Jos North", ward: "Tudun Wada", pu: "PU-001", coords: [[8.85, 9.95], [8.95, 9.95], [8.95, 9.85], [8.85, 9.85]] },
        { lga: "Jos South", ward: "Bukuru", pu: "PU-014", coords: [[8.80, 9.85], [8.95, 9.85], [8.95, 9.70], [8.80, 9.70]] },
        { lga: "Mangu", ward: "Mangu Halle", pu: "PU-042", coords: [[8.90, 9.60], [9.30, 9.60], [9.30, 9.20], [8.90, 9.20]] }
      ];

      for (const boundary of boundaries) {
        if (isPointInPolygon([longitude, latitude], boundary.coords)) {
          return { lga: boundary.lga, ward: boundary.ward, pu: boundary.pu };
        }
      }
      return { lga: "Statewide HQ", ward: "General Dispatch", pu: "HQ-000" };
    };
    const geoMapped = getJurisdiction(lat, lng);

    const docRef = await db.collection("alerts").add({
      type: alertType,
      description: `[OFFLINE_SMS] ${alertType} reported via SMS gateway.`,
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
      rawSmsPayload: messageBody,
      via: "SMS_GATEWAY"
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

    // 2. Scalable FCM Topic Dispatch
    let topic = "all_citizens";
    if (targetType === "LGA" && targetValue) topic = `lga_${targetValue.toLowerCase().replace(/\s+/g, '_')}`;
    if (targetType === "WARD" && targetValue) topic = `ward_${targetValue.toLowerCase().replace(/\s+/g, '_')}`;
    if (targetType === "PU" && targetValue) topic = `pu_${targetValue.toLowerCase().replace(/\s+/g, '_')}`;

    const message = {
      notification: { title, body },
      data: { priority: priority || "NORMAL", type: "BROADCAST", targetType: targetType || "ALL" },
      topic: topic
    };

    const response = await admin.messaging().send(message);
    console.log(`[BROADCAST] Scalable message dispatched to topic: ${topic}. Response: ${response}`);

    return { success: true, topicUsed: topic };
  } catch (error) {
    console.error("[BROADCAST] Failed to send broadcast", error);
    throw new functions.https.HttpsError("internal", "Mass broadcast engine failed.");
  }
});

// PRD: High-Assurance Manual Escalation
// Synchronizes manual intervention with the automated Task Queue
exports.adminEscalateAlert = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Auth required.");
  
  const { alertId, targetTier } = data;
  const alertRef = db.collection("alerts").doc(alertId);
  const alertSnap = await alertRef.get();
  if (!alertSnap.exists) throw new functions.https.HttpsError("not-found", "Alert not found.");
  
  const oldTier = alertSnap.data().assigned_to;
  
  await alertRef.update({
    assigned_to: targetTier,
    last_edited_by: context.auth.token.email || context.auth.uid,
    escalated_at: admin.firestore.FieldValue.serverTimestamp()
  });

  // Schedule the NEXT jump if we are not yet at HQ
  let nextTier = null;
  if (targetTier === "WARD") nextTier = "LGA";
  else if (targetTier === "LGA") nextTier = "HQ";

  if (nextTier) {
    const configSnap = await db.collection("system").doc("config").get();
    const thresholds = configSnap.exists ? (configSnap.data().escalation_thresholds || {}) : {};
    const waitMinutes = thresholds[targetTier] || (targetTier === "WARD" ? 5 : 10);

    const queue = getFunctions().taskQueue("escalateTask");
    await queue.enqueue({ alertId, targetTier: nextTier }, {
      scheduleDelaySeconds: waitMinutes * 60
    });
  }

  return { success: true };
});

exports.adminResolveAlert = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Auth required.");
  const { alertId } = data;
  
  await db.collection("alerts").doc(alertId).update({
    status: "RESOLVED",
    resolved_by: context.auth.token.email || context.auth.uid,
    last_edited_by: context.auth.token.email || context.auth.uid,
    resolved_at: admin.firestore.FieldValue.serverTimestamp()
  });

  return { success: true };
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

// ============================================================
// 5. FAIL-SAFE WATCHDOG ENGINE
// Runs every 5 minutes to detect "stale" alerts that may have missed 
// their task-queue escalation trigger due to system brownouts.
// ============================================================
exports.escalationWatchdog = functions.pubsub.schedule('every 5 minutes').onRun(async (context) => {
  console.log('[WATCHDOG] Commencing sweep for stale active incidents...');
  
  // PRD: Watchdog respects dynamic dashboard thresholds
  const configSnap = await db.collection("system").doc("config").get();
  const thresholds = configSnap.exists ? (configSnap.data().escalation_thresholds || {}) : { LGA: 10 };
  
  // Watchdog threshold is 2x the maximum configured timeout (safety margin)
  const safetyBuffer = (thresholds.LGA || 10) * 2;
  const staleThreshold = new Date(Date.now() - safetyBuffer * 60 * 1000);
  
  const staleAlerts = await db.collection("alerts")
    .where("status", "in", ["ACTIVE", "DURESS"])
    .where("reportedAt", "<=", admin.firestore.Timestamp.fromDate(staleThreshold))
    .get();

  if (staleAlerts.empty) {
    console.log('[WATCHDOG] No stale incidents detected. Cleanup complete.');
    return null;
  }

  console.log(`[WATCHDOG] Found ${staleAlerts.size} potential stale incidents. Evaluating triggers...`);
  
  const batch = db.batch();
  const queue = getFunctions().taskQueue("escalateTask");

  for (const doc of staleAlerts.docs) {
    const data = doc.data();
    
    // If it's been 10+ mins and still at Polling Unit or Ward, it's definitely stale.
    // Re-trigger the task queue to force movement.
    if (data.assigned_to === "POLLING_UNIT" || data.assigned_to === "WARD") {
      const nextTier = data.assigned_to === "POLLING_UNIT" ? "WARD" : "LGA";
      
      console.warn(`[WATCHDOG_RECOVERY] Recovering alert ${doc.id} (Stuck at ${data.assigned_to}). Jump to ${nextTier}.`);
      
      await queue.enqueue({ alertId: doc.id, targetTier: nextTier });
      
      const newAuditRef = db.collection("audit_logs").doc();
      batch.set(newAuditRef, {
        action: "WATCHDOG_RECOVERY",
        alert_id: doc.id,
        from_tier: data.assigned_to,
        to_tier: nextTier,
        minutes_elapsed: safetyBuffer,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        actor: "SYSTEM_WATCHDOG"
      });
    }
  }

  await batch.commit();
  return null;
});

// End of file

// ============================================================
// 7. MIGRATION UTILITY
// Retroactively maps legacy incidents to canonical jurisdictions.
// ============================================================
exports.migrateLegacyIncidents = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Auth required.");
  
  const snap = await db.collection("alerts")
    .where("geo_lga", "==", "Statewide HQ") // Assuming this is the placeholder for unmapped
    .get();

  const batch = db.batch();
  let count = 0;

  snap.forEach(doc => {
    const alert = doc.data();
    if (alert.lat && alert.lng) {
      // Use the internal jurisdiction mapping logic
      // In a real scenario, this would import the high-fidelity GeoJSON
      // For now, it resets them to re-trigger mapping logic if needed
      batch.update(doc.ref, { _migration_pending: true });
      count++;
    }
  });

  await batch.commit();
  return { success: true, migratedCount: count };
});
