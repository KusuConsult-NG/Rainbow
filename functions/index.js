const functions = require("firebase-functions");
const admin = require("firebase-admin");
const { VertexAI } = require("@google-cloud/vertexai");

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

  const oldTier = currentAssigned;
  const timelineEvent = {
    type: "SLA_AUTO_ESCALATION",
    actor: "SYSTEM_AUTO_ESCALATION",
    role: "SYSTEM",
    timestamp: new Date().toISOString(),
    reason: "SLA Threshold Exceeded",
    notes: `Automatically escalated from ${oldTier} to ${targetTier} due to SLA timeout.`
  };

  await alertRef.update({
    assigned_to: targetTier,
    last_edited_by: "SYSTEM_AUTO_ESCALATION",
    escalated_at: admin.firestore.FieldValue.serverTimestamp(),
    timeline: admin.firestore.FieldValue.arrayUnion(timelineEvent)
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
  const assignedLevel = alertData.assignedToTier || alertData.assigned_to || "POLLING_UNIT";
  const priority = alertData.priority || "HIGH";
  const assignedUid = alertData.assignedToUid;

  console.log(`[PUSH] Dispatching notification for alert ${alertId} to ${assignedUid ? 'UID:' + assignedUid : assignedLevel}`);

  const tokens = [];
  
  if (assignedUid) {
    // 1. Direct Assignment Notification
    const userSnap = await db.collection("users").doc(assignedUid).get();
    if (userSnap.exists && userSnap.data().fcmToken) {
      tokens.push(userSnap.data().fcmToken);
    }
  } else {
    // 2. Jurisdictional Tier Notification
    let query = db.collection("users");
    
    if (assignedLevel === "HQ") {
      query = query.where("role", "==", "HQ_OFFICER");
    } else if (assignedLevel === "LGA") {
      query = query.where("role", "==", "LGA_OFFICER").where("lga", "==", alertData.geo_lga);
    } else if (assignedLevel === "WARD") {
      query = query.where("role", "==", "WARD_OFFICER").where("ward", "==", alertData.geo_ward);
    } else {
      query = query.where("role", "==", "POLLING_UNIT_OFFICER").where("pu", "==", alertData.geo_pu);
    }

    const staffSnapshot = await query.get();
    staffSnapshot.forEach(doc => {
      const data = doc.data();
      if (data.fcmToken) tokens.push(data.fcmToken);
    });

    // Also notify HQ officers for AI voice reports or high/critical priority alerts
    if (alertData.ai_triage || priority === "CRITICAL" || priority === "HIGH") {
      const hqSnap = await db.collection("users").where("role", "==", "HQ_OFFICER").get();
      hqSnap.forEach(doc => {
        const data = doc.data();
        if (data.fcmToken && !tokens.includes(data.fcmToken)) {
          tokens.push(data.fcmToken);
        }
      });
    }
  }

  if (tokens.length === 0) return;

  const payload = {
    notification: {
      title: assignedUid ? `🎯 MISSION ASSIGNED` : `🚨 ${priority} ALERT DETECTED`,
      body: assignedUid 
        ? `HQ has dispatched you to Incident ${alertId.substring(0,6)}. Acknowledge immediately.`
        : `Alert ${alertId.substring(0,6)} requires attention at ${assignedLevel} tier!`,
      sound: "default",
      android: {
        priority: "high",
        vibrateTimings: [200, 500, 200, 500],
      }
    },
    data: { alertId, type: assignedUid ? "ASSIGNMENT" : "ALERT", click_action: "FLUTTER_NOTIFICATION_CLICK" }
  };

  try {
    await admin.messaging().sendToDevice(tokens, payload);
    console.log(`[PUSH_SENT] Dispatched to ${tokens.length} recipients.`);
  } catch (err) {
    console.error("[PUSH_ERR] Failed:", err);
  }
};

exports.onAlertCreatedGIS = functions.firestore
  .document("alerts/{alertId}")
  .onCreate(async (snap, context) => {
    const data = snap.data();
    const alertId = context.params.alertId;
    const lat = data.lat;
    const lng = data.lng;

    if (!lat || !lng) return null;

    try {
      console.log(`[GIS_ASYNC] Resolving jurisdiction for alert ${alertId} at (${lat}, ${lng})...`);
      const geoMapped = await resolveJurisdiction(lat, lng);

      const timelineEvent = {
        type: "GIS_RESOLVED",
        actor: "SYSTEM_GIS",
        role: "SYSTEM",
        timestamp: new Date().toISOString(),
        reason: "Geospatial boundary lookup complete.",
        notes: `Mapped to LGA: ${geoMapped.lga}, Ward: ${geoMapped.ward}, PU: ${geoMapped.pu}`
      };

      await snap.ref.update({
        geo_lga: geoMapped.lga,
        geo_ward: geoMapped.ward,
        geo_pu: geoMapped.pu,
        timeline: admin.firestore.FieldValue.arrayUnion(timelineEvent)
      });

      console.log(`[GIS_ASYNC] Successfully updated alert ${alertId} with geo mapping.`);

      // Notify the correct responders now that geographic mapping has completed
      const updatedSnap = await snap.ref.get();
      await sendPushToTier(alertId, updatedSnap.data());

    } catch (err) {
      console.error(`[GIS_ASYNC_ERR] Failed to resolve alert ${alertId}:`, err);
    }
    return null;
});

exports.logAlertChanges = functions.firestore
  .document("alerts/{alertId}")
  .onUpdate(async (change, context) => {
    const newData = change.after.data();
    const oldData = change.before.data();
    const alertId = context.params.alertId;
    const auditRef = db.collection("audit_logs");
    const timestamp = admin.firestore.FieldValue.serverTimestamp();

    // 1. Log Escalations (Tier Handoff)
    if (newData.assigned_to !== oldData.assigned_to || newData.assignedToTier !== oldData.assignedToTier) {
      await auditRef.add({
        action: "TIER_HANDOFF",
        alert_id: alertId,
        from_tier: oldData.assignedToTier || oldData.assigned_to,
        to_tier: newData.assignedToTier || newData.assigned_to,
        actor: newData.last_edited_by || "SYSTEM",
        timestamp
      });
      return sendPushToTier(alertId, newData);
    }

    // 2. Log State Transitions (Mission Lifecycle)
    if (newData.status !== oldData.status) {
      await auditRef.add({
        action: `STATE_CHANGE_${newData.status}`,
        alert_id: alertId,
        from_status: oldData.status,
        to_status: newData.status,
        actor: newData.last_edited_by || "AGENT",
        timestamp
      });
      
      // If status changed to DISPATCHED or assignedToUid was set, notify responder
      if (newData.status === 'DISPATCHED' || (newData.assignedToUid && newData.assignedToUid !== oldData.assignedToUid)) {
        return sendPushToTier(alertId, newData);
      }
    }

    return null;
  });

/**
 * SHARED UTILITY: Point-in-Polygon (PiP) Resolver
 * Supports coordinate arrays stored as [{lng, lat}] objects in Firestore.
 */
const isPointInPolygon = (lng, lat, vs) => {
  // vs can be [{lng, lat}] objects (Firestore format) or [[lng, lat]] arrays
  let inside = false;
  const n = vs.length;
  for (let i = 0, j = n - 1; i < n; j = i++) {
    const xi = vs[i].lng !== undefined ? vs[i].lng : vs[i][0];
    const yi = vs[i].lat !== undefined ? vs[i].lat : vs[i][1];
    const xj = vs[j].lng !== undefined ? vs[j].lng : vs[j][0];
    const yj = vs[j].lat !== undefined ? vs[j].lat : vs[j][1];
    const intersect = ((yi > lat) !== (yj > lat)) && (lng < (xj - xi) * (lat - yi) / (yj - yi) + xi);
    if (intersect) inside = !inside;
  }
  return inside;
};

/**
 * MISSION ROUTING ENGINE
 * Maps coordinates to LGA/Ward/PU hierarchies using real Plateau State boundary polygons.
 * Boundary data sourced from: HDX/UN OCHA Nigeria COD-AB (Admin Level 2)
 */
const resolveJurisdiction = async (latitude, longitude) => {
  try {
    const jurisSnap = await db.collection("jurisdictions").get();
    // Deduplicate by LGA polygon (all wards in same LGA share boundary)
    const seen = new Set();
    for (const doc of jurisSnap.docs) {
      const data = doc.data();
      if (data.coordinates && !seen.has(data.lga_pcode)) {
        if (isPointInPolygon(longitude, latitude, data.coordinates)) {
          console.log(`[JURISDICTION] Resolved: LGA=${data.lga}, Ward=${data.ward}, PU=${data.pu}`);
          return { lga: data.lga, ward: data.ward, pu: data.pu };
        }
        seen.add(data.lga_pcode);
      }
    }
    console.warn(`[JURISDICTION] No match for (${latitude}, ${longitude}). Defaulting to HQ.`);
  } catch (e) {
    console.error("[SYS_ERR] Jurisdictional lookup failed:", e);
  }
  return { lga: "PLATEAU_HQ", ward: "STATEWIDE", pu: "HQ-000" };
};



const crypto = require("crypto");

async function verifyRequestAuthenticity(data, context) {
  // 1. If App Check passes, request is verified
  if (context.app !== undefined) {
    return true;
  }

  // 2. Fallback: Verify HMAC signature
  const hmacData = data._hmac;
  if (!hmacData) {
    throw new functions.https.HttpsError("failed-precondition", "App Check verification failed, and no HMAC signature fallback was provided.");
  }

  const { signature, timestamp, badgeId, uid } = hmacData;
  if (!signature || !timestamp || !badgeId || !uid) {
    throw new functions.https.HttpsError("invalid-argument", "Invalid HMAC payload format.");
  }

  // Prevent Replay Attacks: Signature must be fresh (within 5 minutes / 300 seconds)
  const currentSeconds = Math.floor(Date.now() / 1000);
  if (Math.abs(currentSeconds - timestamp) > 300) {
    throw new functions.https.HttpsError("deadline-exceeded", "HMAC signature has expired (timestamp skew too high).");
  }

  // 3. Retrieve user profile from Firestore to verify badge association
  const userSnap = await db.collection("users").doc(uid).get();
  if (!userSnap.exists) {
    throw new functions.https.HttpsError("unauthenticated", "User profile not found.");
  }
  const profile = userSnap.data();
  if (profile.badgeId !== badgeId) {
    throw new functions.https.HttpsError("permission-denied", "Badge verification mismatch.");
  }

  // 4. Derive signature key and verify hash
  const sharedSecret = "RAINBOW_PLATEAU_SECURE_HMAC_GATEWAY_KEY_2026";
  const keySource = `${sharedSecret}:${uid}:${badgeId}`;
  
  // Exclude _hmac field from the payload sorting to match client computation
  const payload = { ...data };
  delete payload._hmac;
  
  const sortMap = (map) => {
    const sorted = {};
    Object.keys(map).sort().forEach(key => {
      const val = map[key];
      if (val && typeof val === "object" && !Array.isArray(val)) {
        sorted[key] = sortMap(val);
      } else {
        sorted[key] = val;
      }
    });
    return sorted;
  };

  const sortedPayload = sortMap(payload);
  const payloadString = JSON.stringify(sortedPayload);
  const signText = `${payloadString}:${timestamp}`;

  const hmac = crypto.createHmac("sha256", keySource);
  hmac.update(signText);
  const computedSignature = hmac.digest("hex");

  if (computedSignature !== signature) {
    throw new functions.https.HttpsError("permission-denied", "App Check signature failed verification.");
  }

  return true;
}

// ============================================================
// 2. API: CREATE ALERT (BACKEND FIRST FLOW)
// Ensures 100% success/failure tracking and logs every alert request.
// ============================================================
exports.createAlert = functions.https.onCall(async (data, context) => {
  console.log(`[ALERT_CREATED] Received createAlert payload: ${JSON.stringify(data)}`);

  await verifyRequestAuthenticity(data, context);

  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated.');
  }

  try {
    const { type, description, lat, lng, priority, attachments } = data;
    const userId = context.auth.uid;

    // Rate limiting (5 per hour)
    const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000);
    const recentSnap = await db.collection("alerts")
      .where("reportedBy", "==", userId)
      .where("reportedAt", ">=", admin.firestore.Timestamp.fromDate(oneHourAgo))
      .get();
    
    if (recentSnap.size >= 5) {
      throw new functions.https.HttpsError("resource-exhausted", "Rate limit exceeded.");
    }

    const finalLat = lat || 9.9167;
    const finalLng = lng || 8.8917;

    const alertData = {
      type: type || "UNKNOWN",
      description: description || "",
      lat: finalLat,
      lng: finalLng,
      geo_lga: "RESOLVING",
      geo_ward: "RESOLVING",
      geo_pu: "RESOLVING",
      reportedBy: userId,
      status: "OPEN", // Normalized: OPEN replaces ACTIVE
      priority: priority || "HIGH",
      assigned_to: "POLLING_UNIT",
      reportedAt: admin.firestore.FieldValue.serverTimestamp(),
      attachments: attachments || [],
      sync_status: "COMPLETED",
      timeline: [
        {
          type: "CREATED",
          actor: userId,
          role: "CITIZEN",
          timestamp: new Date().toISOString(),
          reason: "SOS Distress Signal Initiated",
          notes: "Incident reported, geoscope resolving..."
        }
      ]
    };

    const docRef = await db.collection("alerts").add(alertData);
    
    // Initial Escalation Task
    const configSnap = await db.collection("system").doc("config").get();
    const thresholds = configSnap.exists ? (configSnap.data().escalation_thresholds || {}) : { POLLING_UNIT: 2 };
    const waitMinutes = thresholds.POLLING_UNIT || 2;

    const queue = getFunctions().taskQueue("escalateTask");
    await queue.enqueue({ alertId: docRef.id, targetTier: "WARD" }, {
      scheduleDelaySeconds: waitMinutes * 60 
    });

    return { success: true, alertId: docRef.id };
  } catch (error) {
    console.error(`[ALERT_ERROR]`, error);
    throw new functions.https.HttpsError('internal', 'Deployment failed');
  }
});

// ============================================================
// 3. OFFLINE SMS WEBHOOK
// ============================================================
exports.smsWebhook = functions.https.onRequest(async (req, res) => {
  if (req.method !== 'POST') return res.status(405).send('Method Not Allowed');

  const messageBody = req.body.Body || req.body.text || req.body.message || "";
  if (!messageBody.startsWith("ALERT|")) return res.status(200).send('Format ignored.');

  try {
    const segments = messageBody.split('|');
    const reporterPhone = segments[1];
    const typeCode = segments[2];
    const lat = parseFloat(segments[3]?.replace('LAT:', '')) || 9.9167;
    const lng = parseFloat(segments[4]?.replace('LNG:', '')) || 8.8917;

    const typeMap = { 'KD': 'Kidnap', 'FR': 'Fire', 'DA': 'Drug abuse', 'CM': 'Attack', 'OT': 'Other' };
    const alertType = typeMap[typeCode] || 'Unknown';

    const docRef = await db.collection("alerts").add({
      type: alertType,
      description: `[OFFLINE_SMS] Reported via SMS gateway.`,
      lat, lng,
      geo_lga: "RESOLVING",
      geo_ward: "RESOLVING",
      geo_pu: "RESOLVING",
      reportedBy: reporterPhone,
      status: "OPEN",
      priority: "CRITICAL",
      assigned_to: "POLLING_UNIT", 
      reportedAt: admin.firestore.FieldValue.serverTimestamp(),
      isOffline: true,
      via: "SMS_GATEWAY",
      timeline: [
        {
          type: "CREATED",
          actor: reporterPhone || "OFFLINE_SMS_GATEWAY",
          role: "CITIZEN",
          timestamp: new Date().toISOString(),
          reason: "SOS Distress Signal via SMS Gateway",
          notes: "Incident reported, geoscope resolving..."
        }
      ]
    });

    const queue = getFunctions().taskQueue("escalateTask");
    await queue.enqueue({ alertId: docRef.id, targetTier: "WARD" }, { scheduleDelaySeconds: 120 });

    return res.status(200).send({ success: true, alertId: docRef.id });
  } catch (error) {
    return res.status(500).send({ error: "Processing malfunction" });
  }
});

exports.massBroadcast = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Auth required.");
  }

  const { title, body, priority, targetType, targetValue, targetAudience } = data;
  if (!title || !body) {
    throw new functions.https.HttpsError("invalid-argument", "Missing broadcast title or body.");
  }

  try {
    const audience = targetAudience || 'all';
    const type = targetType || 'ALL';
    const value = targetValue || 'STATEWIDE';

    // 1. Log the broadcast to Firestore (Audit Compliance)
    await db.collection("broadcasts").add({
      title,
      body,
      priority: priority || "NORMAL",
      targetType: type,
      targetValue: value,
      targetAudience: audience,
      senderId: context.auth.uid,
      sentAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 1.5. Write to system_alerts for real-time in-app UI listeners (Mobile + Web)
    await db.collection("system_alerts").add({
      active: true,
      message: body,
      severity: priority || "INFO",
      target_type: type,
      target_value: value,
      target_audience: audience,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 2. Tactical Topic Resolution
    // Hierarchy: audience_jurisdiction (e.g., staff_lga_jos_north)
    let topic = "all_citizens";
    const cleanValue = value.toLowerCase().replace(/\s+/g, '_');

    if (audience === 'citizens' || audience === 'all') {
      if (type === "LGA") topic = `lga_${cleanValue}`;
      else if (type === "WARD") topic = `ward_${cleanValue}`;
      else if (type === "PU") topic = `pu_${cleanValue}`;
      else topic = "all_citizens";
    } else {
      // Staff-specific topics
      const roleMap = {
        hq_command: 'hq_officer',
        lga_command: 'lga_officer',
        ward_command: 'ward_officer',
        unit_command: 'polling_officer'
      };
      
      const rolePrefix = roleMap[audience] || 'staff';
      
      if (type === "LGA") topic = `staff_lga_${cleanValue}`;
      else if (type === "WARD") topic = `staff_ward_${cleanValue}`;
      else topic = `staff_${rolePrefix}`;
    }

    const message = {
      notification: { title, body },
      data: { 
        priority: priority || "NORMAL", 
        type: "BROADCAST", 
        targetType: type,
        targetAudience: audience
      },
      topic: topic
    };

    const response = await admin.messaging().send(message);
    console.log(`[BROADCAST] Tactical signal dispatched: ${topic}. Response: ${response}`);

    return { success: true, topicUsed: topic };
  } catch (error) {
    console.error("[BROADCAST_ERR] Engine failure:", error);
    throw new functions.https.HttpsError("internal", "Mass broadcast engine failed.");
  }
});

// PRD: High-Assurance Manual Escalation
// Synchronizes manual intervention with the automated Task Queue and records auditable timelines
exports.adminEscalateAlert = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Auth required.");
  
  // Enforce staff/agent permissions
  const role = context.auth.token.role || "";
  const isAuthorized = context.auth.token.isStaff || role === "HQ_COMMAND" || role === "HQ_OFFICER" || role === "LGA_COMMAND" || role === "WARD_COMMAND";
  if (!isAuthorized) {
    throw new functions.https.HttpsError("permission-denied", "Only tactical agents can manually escalate alerts.");
  }

  const { alertId, targetTier, reason, notes } = data;
  if (!alertId || !targetTier) {
    throw new functions.https.HttpsError("invalid-argument", "alertId and targetTier are required.");
  }

  const alertRef = db.collection("alerts").doc(alertId);

  await db.runTransaction(async (transaction) => {
    const alertSnap = await transaction.get(alertRef);
    if (!alertSnap.exists) throw new functions.https.HttpsError("not-found", "Alert not found.");
    
    const alertData = alertSnap.data();
    const oldTier = alertData.assigned_to || "POLLING_UNIT";

    const timelineEvent = {
      type: "ESCALATION",
      actor: context.auth.token.email || context.auth.uid,
      role: role || "RESPONDER",
      timestamp: new Date().toISOString(),
      reason: reason || "Tactical Escalation",
      notes: notes || `Manual escalation from ${oldTier} to ${targetTier}.`
    };

    transaction.update(alertRef, {
      assigned_to: targetTier,
      last_edited_by: context.auth.token.email || context.auth.uid,
      escalated_at: admin.firestore.FieldValue.serverTimestamp(),
      timeline: admin.firestore.FieldValue.arrayUnion(timelineEvent)
    });

    const auditRef = db.collection("audit_logs").doc();
    transaction.set(auditRef, {
      action: "MANUAL_ESCALATION",
      alert_id: alertId,
      from_tier: oldTier,
      to_tier: targetTier,
      actor: context.auth.token.email || context.auth.uid,
      reason: reason || "Tactical Escalation",
      timestamp: admin.firestore.FieldValue.serverTimestamp()
    });
  });

  // Schedule task queue outside transaction
  try {
    const nextTier = targetTier === "POLLING_UNIT" ? "WARD" : targetTier === "WARD" ? "LGA" : "PLATEAU_HQ";
    if (nextTier !== "PLATEAU_HQ") {
      const thresholds = { WARD: 5, LGA: 10 };
      const waitMinutes = thresholds[targetTier] || (targetTier === "WARD" ? 5 : 10);

      const queue = getFunctions().taskQueue("escalateTask");
      await queue.enqueue({ alertId, targetTier: nextTier }, {
        scheduleDelaySeconds: waitMinutes * 60
      });
    }
  } catch (err) {
    console.warn("[ESCALATE_QUEUE] Failed to enqueue next task queue:", err);
  }

  return { success: true };
});

exports.adminResolveAlert = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Auth required.");
  const { alertId } = data;
  
  const alertRef = db.collection("alerts").doc(alertId);

  await db.runTransaction(async (transaction) => {
    const alertSnap = await transaction.get(alertRef);
    if (!alertSnap.exists) throw new functions.https.HttpsError("not-found", "Alert not found.");

    const timelineEvent = {
      type: "RESOLVED",
      actor: context.auth.token.email || context.auth.uid,
      role: context.auth.token.role || "RESPONDER",
      timestamp: new Date().toISOString(),
      reason: "Incident Resolved",
      notes: `Incident marked as resolved by ${context.auth.token.email || context.auth.uid}`
    };

    transaction.update(alertRef, {
      status: "RESOLVED",
      resolved_by: context.auth.token.email || context.auth.uid,
      last_edited_by: context.auth.token.email || context.auth.uid,
      resolved_at: admin.firestore.FieldValue.serverTimestamp(),
      timeline: admin.firestore.FieldValue.arrayUnion(timelineEvent)
    });
  });

  return { success: true };
});

exports.adminDispatchAlert = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Auth required.");
  const { alertId, responderUid } = data;
  
  if (!alertId || !responderUid) {
    throw new functions.https.HttpsError("invalid-argument", "Missing alertId or responderUid.");
  }

  const alertRef = db.collection("alerts").doc(alertId);
  const responderRef = db.collection("users").doc(responderUid);
  
  await db.runTransaction(async (transaction) => {
    const alertSnap = await transaction.get(alertRef);
    if (!alertSnap.exists) throw new functions.https.HttpsError("not-found", "Alert not found.");
    
    const responderSnap = await transaction.get(responderRef);
    if (!responderSnap.exists) throw new functions.https.HttpsError("not-found", "Responder not found.");

    const timelineEvent = {
      type: "DISPATCHED",
      actor: context.auth.token.email || context.auth.uid,
      role: context.auth.token.role || "RESPONDER",
      timestamp: new Date().toISOString(),
      reason: "Unit Dispatched",
      notes: `Dispatched tactical unit ${responderSnap.data().displayName || responderUid} to incident site.`
    };

    transaction.update(alertRef, {
      status: "DISPATCHED",
      assignedToUid: responderUid,
      last_edited_by: context.auth.token.email || context.auth.uid,
      dispatched_at: admin.firestore.FieldValue.serverTimestamp(),
      timeline: admin.firestore.FieldValue.arrayUnion(timelineEvent)
    });

    const auditRef = db.collection("audit_logs").doc();
    transaction.set(auditRef, {
      action: "ADMIN_DISPATCH",
      alert_id: alertId,
      actor: context.auth.token.email || context.auth.uid,
      target_uid: responderUid,
      timestamp: admin.firestore.FieldValue.serverTimestamp()
    });
  });

  return { success: true };
});

exports.agentUpdateMissionStatus = functions.https.onCall(async (data, context) => {
  await verifyRequestAuthenticity(data, context);
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Auth required.");
  
  const { alertId, nextStatus } = data;
  const uid = context.auth.uid;
  const alertRef = db.collection("alerts").doc(alertId);

  return db.runTransaction(async (transaction) => {
    const alertSnap = await transaction.get(alertRef);
    if (!alertSnap.exists) {
      throw new functions.https.HttpsError("not-found", "Alert not found.");
    }
    
    const alertData = alertSnap.data();

    // Security: Only assigned responder or open self-deploy can update
    if (alertData.status !== "OPEN" && alertData.assignedToUid !== uid) {
      throw new functions.https.HttpsError("permission-denied", "You are not assigned to this mission.");
    }

    const timelineEvent = {
      type: nextStatus,
      actor: context.auth.token.email || uid,
      role: context.auth.token.role || "RESPONDER",
      timestamp: new Date().toISOString(),
      reason: `Agent updated mission state to ${nextStatus}`,
      notes: nextStatus === "ACKNOWLEDGED" ? "Agent successfully self-deployed to emergency." : ""
    };

    const updateData = {
      status: nextStatus,
      last_edited_by: context.auth.token.email || uid,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      timeline: admin.firestore.FieldValue.arrayUnion(timelineEvent)
    };

    if (alertData.status === "OPEN") {
      updateData.assignedToUid = uid;
    }

    if (nextStatus === "ACKNOWLEDGED") updateData.acknowledgedAt = admin.firestore.FieldValue.serverTimestamp();
    if (nextStatus === "RESOLVED") {
      updateData.resolvedAt = admin.firestore.FieldValue.serverTimestamp();
      updateData.resolved_by = context.auth.token.email || uid;
    }

    transaction.update(alertRef, updateData);

    // Sync with RTDB if possible (using admin SDK)
    try {
      const rtdbStatus = nextStatus === "RESOLVED" ? "PATROLLING" : "BUSY";
      await admin.database().ref(`responder_telemetry/${uid}/status`).set(rtdbStatus);
    } catch (err) {
      console.warn("[RTDB_TELEMETRY] Failed to sync status in RTDB:", err);
    }

    return { success: true };
  });
});

exports.seedMockData = functions.https.onRequest(async (req, res) => {
  const mockAlerts = [
    { type: "Kidnap - Attempted Kidnap", description: "Suspicious individuals monitoring school bus route near Mangu.", lat: 9.5133, lng: 9.0967, reportedBy: "+2348001112222", status: "OPEN", priority: "CRITICAL", assigned_to: "WARD", reportedAt: admin.firestore.FieldValue.serverTimestamp() },
    { type: "Fire - Bush Fire", description: "Large bush fire spreading towards residential area in Jos South.", lat: 9.7716, lng: 8.8681, reportedBy: "anonymous", status: "OPEN", priority: "CRITICAL", assigned_to: "LGA", reportedAt: admin.firestore.FieldValue.serverTimestamp() },
    { type: "Police brutality - Extortion", description: "Officers setting up illegal checkpoint near Barkin Ladi.", lat: 9.5375, lng: 8.8958, reportedBy: "+2347012345678", status: "OPEN", priority: "HIGH", assigned_to: "POLLING_UNIT", reportedAt: admin.firestore.FieldValue.serverTimestamp() },
    { type: "Community attack - Armed Invasion", description: "Gunshots heard on the outskirts of Riyom.", lat: 9.6333, lng: 8.7667, reportedBy: "anonymous", status: "DURESS", priority: "CRITICAL", assigned_to: "HQ", reportedAt: admin.firestore.FieldValue.serverTimestamp() },
    { type: "Flood - Submerged Property", description: "Heavy rain causing severe flooding in Jos North.", lat: 9.9248, lng: 8.8920, reportedBy: "+2349098765432", status: "OPEN", priority: "MEDIUM", assigned_to: "WARD", reportedAt: admin.firestore.FieldValue.serverTimestamp() },
    { type: "Drug abuse - Public Drug Use", description: "Group of youths taking illicit substances in public park.", lat: 9.8965, lng: 8.8583, reportedBy: "anonymous", status: "OPEN", priority: "MEDIUM", assigned_to: "POLLING_UNIT", reportedAt: admin.firestore.FieldValue.serverTimestamp() },
    { type: "Cyber crime - Online Fraud", description: "Scammer cafe operating out of a local plaza.", lat: 9.9322, lng: 8.8922, reportedBy: "+2348123456789", status: "RESOLVED", priority: "MEDIUM", assigned_to: "WARD", reportedAt: admin.firestore.FieldValue.serverTimestamp() },
    { type: "Domestic violence - Trapped", description: "Neighbor is locked in house and calling for help.", lat: 9.8600, lng: 8.8800, reportedBy: "anonymous", status: "DURESS", priority: "HIGH", assigned_to: "POLLING_UNIT", reportedAt: admin.firestore.FieldValue.serverTimestamp() },
    { type: "Kidnap - Immediate Abduction", description: "A child was just taken into an unmarked black vehicle.", lat: 9.8755, lng: 8.8522, reportedBy: "+2348033334444", status: "DURESS", priority: "CRITICAL", assigned_to: "LGA", reportedAt: admin.firestore.FieldValue.serverTimestamp() },
    { type: "Cattle rustling - Armed Rustling", description: "Herd stolen at gunpoint in Wase.", lat: 9.1000, lng: 9.9667, reportedBy: "+2347076543210", status: "OPEN", priority: "HIGH", assigned_to: "WARD", reportedAt: admin.firestore.FieldValue.serverTimestamp() }
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

  // SLA Watchdog: Check for responders stuck en route (exceeding 15 mins response SLA)
  const responseLimit = 15; // 15 minutes SLA
  const responseThreshold = new Date(Date.now() - responseLimit * 60 * 1000);

  const delayedAlerts = await db.collection("alerts")
    .where("status", "in", ["DISPATCHED", "ACKNOWLEDGED", "ON_ROUTE"])
    .get();

  for (const doc of delayedAlerts.docs) {
    const data = doc.data();
    const startTimestamp = data.dispatched_at || data.acknowledgedAt || data.reportedAt;
    if (startTimestamp && startTimestamp.toDate() <= responseThreshold) {
      if (!data.sla_breached) {
        console.warn(`[SLA_BREACH] Alert ${doc.id} breached response SLA of ${responseLimit} minutes!`);
        
        const timelineEvent = {
          type: "SLA_BREACH_ALERT",
          actor: "SYSTEM_WATCHDOG",
          role: "SYSTEM",
          timestamp: new Date().toISOString(),
          reason: "Responder failed to arrive on site within response threshold.",
          notes: `Incident has been in ${data.status} state since ${startTimestamp.toDate().toISOString()}`
        };

        batch.update(doc.ref, {
          sla_breached: true,
          timeline: admin.firestore.FieldValue.arrayUnion(timelineEvent)
        });

        // Trigger push notification to LGA/Ward commanders notifying them of SLA breach
        await sendPushToTier(doc.id, {
          ...data,
          status: "SLA_BREACH",
          title: "SLA RESPONSE BREACH ALERT",
          body: `Emergency in ${data.geo_pu || 'Polling Unit'} has exceeded the 15-minute response SLA. Immediate review required.`
        });
      }
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

// ============================================================
// 8. SECURE AGENT AUTHENTICATION
// Validates provisioned access codes and issues custom tokens 
// with embedded role/jurisdiction claims.
// ============================================================
exports.validateAgentAccessCode = functions.https.onCall(async (data, context) => {
  const { accessCode } = data;
  if (!accessCode) {
    throw new functions.https.HttpsError('invalid-argument', 'Missing access code.');
  }

  console.log(`[AUTH] Validating access code: ${accessCode.substring(0, 4)}****`);

  try {
    const codeSnap = await db.collection("access_codes").doc(accessCode.toUpperCase()).get();
    
    if (!codeSnap.exists) {
      console.warn(`[AUTH_FAILED] Invalid access code attempt: ${accessCode}`);
      throw new functions.https.HttpsError('permission-denied', 'Invalid or expired access code.');
    }

    const codeData = codeSnap.data();
    if (codeData.isUsed && codeData.multiUse !== true) {
      throw new functions.https.HttpsError('permission-denied', 'This access code has already been utilized.');
    }

    if (codeData.expiresAt && codeData.expiresAt.toDate() < new Date()) {
      throw new functions.https.HttpsError('permission-denied', 'Access code has expired.');
    }

    const { role, jurisdiction, badgeId, name, unit } = codeData;
    const uid = `agent_${badgeId || accessCode.toLowerCase()}`;
    
    const customClaims = {
      role: role || 'AGENT',
      lga: jurisdiction?.lga || '',
      ward: jurisdiction?.ward || '',
      pu: jurisdiction?.pu || '',
      badgeId: badgeId || '',
      isStaff: true
    };

    const email = `${uid}@operationrainbow.plateau.gov.ng`;
    const password = `${accessCode.toUpperCase()}_sec_${new Date().getFullYear()}`;

    try {
      await admin.auth().getUser(uid);
      await admin.auth().updateUser(uid, { password });
    } catch (e) {
      if (e.code === 'auth/user-not-found') {
        await admin.auth().createUser({
          uid,
          email,
          password,
        });
      } else {
        throw e;
      }
    }
    
    // Set custom claims so the user has the right permissions
    await admin.auth().setCustomUserClaims(uid, customClaims);

    await db.collection("users").doc(uid).set({
      uid,
      email,
      role: customClaims.role,
      lga: customClaims.lga,
      ward: customClaims.ward,
      pu: customClaims.pu,
      badgeId: customClaims.badgeId,
      name: name || "Field Agent",
      unit: unit || "UNASSIGNED",
      lastLogin: admin.firestore.FieldValue.serverTimestamp(),
      authType: "ACCESS_CODE",
      isVerified: true
    }, { merge: true });

    if (codeData.multiUse !== true) {
      await codeSnap.ref.update({ 
        isUsed: true, 
        utilizedBy: uid,
        utilizedAt: admin.firestore.FieldValue.serverTimestamp() 
      });
    }

    await db.collection("audit_logs").add({
      action: "AGENT_AUTH_SUCCESS",
      actor: uid,
      role: customClaims.role,
      timestamp: admin.firestore.FieldValue.serverTimestamp()
    });

    // Return the email/password fallback instead of custom token
    return { success: true, fallbackAuth: true, email, password };

  } catch (error) {
    if (error instanceof functions.https.HttpsError) throw error;
    console.error(`[AUTH_FATAL] Access code validation failed:`, error);
    throw new functions.https.HttpsError('internal', `Internal security gate failure: ${error.message}`);
  }
});

// ============================================================
// 9. SCHEDULED TELEMETRY PATH PRUNER
// Runs every 24 hours (midnight) to automatically purge live location 
// tracking histories to save RTDB bandwidth and storage.
// ============================================================
exports.pruneTrackingPaths = functions.pubsub.schedule('0 0 * * *').onRun(async (context) => {
  console.log('[TELEMETRY_PRUNER] Commencing scheduled 24-hour cleanup of responder and citizen paths...');
  try {
    const trackingRef = admin.database().ref('tracking');
    const snapshot = await trackingRef.get();
    
    if (!snapshot.exists()) {
      console.log('[TELEMETRY_PRUNER] No tracking telemetry nodes found.');
      return null;
    }

    const updates = {};
    snapshot.forEach(child => {
      const userId = child.key;
      // Wipe the historical coordinates path node to prevent infinite bloat
      updates[`${userId}/path`] = null;
    });

    if (Object.keys(updates).length > 0) {
      await trackingRef.update(updates);
      console.log(`[TELEMETRY_PRUNER] Successfully wiped path history for ${Object.keys(updates).length} active tracking nodes.`);
    }
  } catch (error) {
    console.error('[TELEMETRY_PRUNER_ERR] Failed to prune tracking paths:', error);
  }
  return null;
});

// ============================================================
// 10. APP DEACTIVATION & UNINSTALL GOVERNANCE
// ============================================================

exports.requestAppUninstall = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Auth required.");
  
  const { reason, remarks } = data;
  if (!reason) {
    throw new functions.https.HttpsError("invalid-argument", "Deactivation reason is required.");
  }

  const uid = context.auth.uid;
  const email = context.auth.token.email || "";
  const role = context.auth.token.role || "RESPONDER";

  // Check if responder has active assigned missions
  const activeAlerts = await db.collection("alerts")
    .where("assignedToUid", "==", uid)
    .where("status", "in", ["ACKNOWLEDGED", "ON_ROUTE", "ON_SITE", "DURESS"])
    .get();

  if (!activeAlerts.empty) {
    throw new functions.https.HttpsError("failed-precondition", "You have active assigned missions. Resolve or escalate them before deactivation.");
  }

  const requestRef = db.collection("uninstall_requests").doc(uid);
  await requestRef.set({
    uid,
    email,
    role,
    reason,
    remarks: remarks || "",
    status: "PENDING",
    createdAt: admin.firestore.FieldValue.serverTimestamp()
  });

  await db.collection("audit_logs").add({
    action: "UNINSTALL_REQUESTED",
    actor: email || uid,
    reason,
    timestamp: admin.firestore.FieldValue.serverTimestamp()
  });

  return { success: true };
});

exports.approveAppUninstall = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Auth required.");
  
  // Enforce HQ Command / HQ Officer permissions
  const role = context.auth.token.role || "";
  const isHq = role === "HQ_COMMAND" || role === "HQ_OFFICER";
  if (!isHq) {
    throw new functions.https.HttpsError("permission-denied", "Only HQ Command can approve app uninstall requests.");
  }

  const { targetUid } = data;
  if (!targetUid) {
    throw new functions.https.HttpsError("invalid-argument", "Target UID is required.");
  }

  const requestRef = db.collection("uninstall_requests").doc(targetUid);
  const requestSnap = await requestRef.get();
  if (!requestSnap.exists) {
    throw new functions.https.HttpsError("not-found", "Uninstall request not found.");
  }

  // Cryptographically generate 6-digit unique time-bound removal code using Node.js crypto CSPRNG
  const crypto = require("crypto");
  const code = "RMV-" + crypto.randomInt(100000, 1000000).toString();
  
  await requestRef.update({
    status: "APPROVED",
    removalCode: code,
    approvedBy: context.auth.token.email || context.auth.uid,
    approvedAt: admin.firestore.FieldValue.serverTimestamp(),
    expiresAt: new Date(Date.now() + 2 * 60 * 60 * 1000) // 2 hours expiration
  });

  await db.collection("audit_logs").add({
    action: "UNINSTALL_APPROVED",
    actor: context.auth.token.email || context.auth.uid,
    target_uid: targetUid,
    removal_code: code,
    timestamp: admin.firestore.FieldValue.serverTimestamp()
  });

  return { success: true, removalCode: code };
});

exports.validateRemovalCode = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Auth required.");
  
  const { removalCode } = data;
  if (!removalCode) {
    throw new functions.https.HttpsError("invalid-argument", "Removal code is required.");
  }

  const uid = context.auth.uid;
  const requestRef = db.collection("uninstall_requests").doc(uid);
  const requestSnap = await requestRef.get();
  
  if (!requestSnap.exists) {
    throw new functions.https.HttpsError("failed-precondition", "No deactivation request found.");
  }

  const requestData = requestSnap.data();
  if (requestData.status !== "APPROVED") {
    throw new functions.https.HttpsError("failed-precondition", "Request is not approved by HQ yet.");
  }

  if (requestData.removalCode !== removalCode.toUpperCase().trim()) {
    throw new functions.https.HttpsError("permission-denied", "Invalid removal code.");
  }

  if (requestData.expiresAt && requestData.expiresAt.toDate() < new Date()) {
    throw new functions.https.HttpsError("permission-denied", "Removal code has expired.");
  }

  // Set status as completed and deactivate the user
  await requestRef.update({
    status: "COMPLETED",
    completedAt: admin.firestore.FieldValue.serverTimestamp()
  });

  // Mark the user as deactivated in Firestore
  await db.collection("users").doc(uid).update({
    status: "deactivated",
    deactivatedAt: admin.firestore.FieldValue.serverTimestamp(),
    deactivationReason: requestData.reason
  });

  // Disable user in Firebase Auth
  try {
    await admin.auth().updateUser(uid, { disabled: true });
    console.log(`[AUTH] Successfully disabled auth user account: ${uid}`);
  } catch (e) {
    console.error(`[AUTH_ERR] Failed to disable auth user account: ${uid}`, e);
  }

  await db.collection("audit_logs").add({
    action: "UNINSTALL_COMPLETED",
    actor: requestData.email || uid,
    timestamp: admin.firestore.FieldValue.serverTimestamp()
  });

  return { success: true };
});

// ============================================================
// 11. AUTOMATIC SLA ESCALATION SWEEPER
// ============================================================
exports.triggerSLASweep = functions.https.onCall(async (data, context) => {
  console.log('[SLA_SWEEP] Commencing server-side automatic SLA escalation sweep...');
  let escalatedCount = 0;
  
  try {
    const activeStatuses = ['OPEN', 'ACTIVE'];
    const snapshot = await db.collection("alerts")
      .where("status", "in", activeStatuses)
      .get();
      
    if (snapshot.empty) {
      console.log('[SLA_SWEEP] No active alerts found.');
      return { success: true, escalatedCount: 0 };
    }

    const now = Date.now();
    const configSnap = await db.collection("system").doc("config").get();
    const configData = configSnap.exists ? configSnap.data() : {};
    
    // SLA Thresholds in milliseconds (default to 2 mins for PU, 4 mins for Ward, 6 mins for LGA for rapid testing)
    const thresholds = configData.escalation_thresholds_ms || {
      'POLLING_UNIT': 2 * 60 * 1000, 
      'WARD': 4 * 60 * 1000,
      'LGA': 6 * 60 * 1000
    };

    for (const doc of snapshot.docs) {
      const alertData = doc.data();
      const alertId = doc.id;
      const reportedAt = alertData.reportedAt ? alertData.reportedAt.toDate().getTime() : now;
      const elapsed = now - reportedAt;
      
      const currentTier = alertData.assigned_to || 'POLLING_UNIT';
      let targetTier = null;
      let limit = thresholds[currentTier];

      if (currentTier === 'POLLING_UNIT' && elapsed > limit) {
        targetTier = 'WARD';
      } else if (currentTier === 'WARD' && elapsed > limit) {
        targetTier = 'LGA';
      } else if (currentTier === 'LGA' && elapsed > limit) {
        targetTier = 'HQ';
      }

      if (targetTier) {
        console.log(`[SLA_SWEEP] Auto-escalating alert ${alertId} from ${currentTier} to ${targetTier} (Elapsed: ${Math.round(elapsed / 1000)}s, SLA: ${Math.round(limit / 1000)}s)`);
        
        const timelineEvent = {
          type: "SLA_AUTO_ESCALATION",
          actor: "SYSTEM_SLA_SWEEP_ENGINE",
          role: "SYSTEM",
          timestamp: new Date().toISOString(),
          reason: "SLA Threshold Exceeded",
          notes: `Automatically escalated from ${currentTier} to ${targetTier} after exceeding SLA limit.`
        };

        await doc.ref.update({
          assigned_to: targetTier,
          last_edited_by: "SYSTEM_SLA_SWEEP_ENGINE",
          escalated_at: admin.firestore.FieldValue.serverTimestamp(),
          timeline: admin.firestore.FieldValue.arrayUnion(timelineEvent)
        });

        await db.collection("audit_logs").add({
          action: "SLA_AUTO_ESCALATION",
          alert_id: alertId,
          from_tier: currentTier,
          to_tier: targetTier,
          actor: "SYSTEM_SLA_SWEEP_ENGINE",
          timestamp: admin.firestore.FieldValue.serverTimestamp()
        });

        escalatedCount++;
      }
    }
  } catch (error) {
    console.error('[SLA_SWEEP_ERR] SLA sweep failed:', error);
    throw new functions.https.HttpsError("internal", "SLA Escalation sweep engine failed.");
  }

  return { success: true, escalatedCount };
});

// PRD: Automated Custom Claims Synchronization
// Syncs Firestore user profile role and isStaff to Firebase Auth custom claims upon creation or update
exports.syncUserCustomClaims = functions.firestore
  .document('users/{userId}')
  .onWrite(async (change, context) => {
    const userId = context.params.userId;
    
    // If the document was deleted, do nothing
    if (!change.after.exists) {
      return null;
    }

    const data = change.after.data();
    const role = data.role || '';
    const isStaff = data.isStaff || false;
    const badgeId = data.badgeId || '';
    const lga = data.geo_lga || data.lga || '';
    const ward = data.geo_ward || data.ward || '';
    const pu = data.geo_pu || data.pu || '';

    // Only sync if the role, isStaff, or geoscopes have changed to avoid loops
    const oldData = change.before.exists ? change.before.data() : null;
    if (oldData && 
        oldData.role === role && 
        oldData.isStaff === isStaff && 
        oldData.badgeId === badgeId && 
        oldData.geo_lga === lga && 
        oldData.geo_ward === ward && 
        oldData.geo_pu === pu) {
      return null;
    }

    console.log(`[SYNC_CLAIMS] Syncing custom claims for user ${userId} | role: ${role} | isStaff: ${isStaff}`);

    const customClaims = {
      role: role,
      isStaff: isStaff,
      badgeId: badgeId,
      lga: lga,
      ward: ward,
      pu: pu
    };

    try {
      await admin.auth().setCustomUserClaims(userId, customClaims);
      console.log(`[SYNC_CLAIMS] Custom claims successfully set for user ${userId}`);
    } catch (err) {
      console.error(`[SYNC_CLAIMS_ERR] Failed to set claims for user ${userId}:`, err.message);
    }
    return null;
  });

// PRD: Multimodal Audio Transcription & Triage
// Automatically transcribes and triages incident reports that include a newly uploaded audio attachment (.m4a or .wav)
exports.processAudioIncidentReport = functions.firestore
  .document("alerts/{alertId}")
  .onUpdate(async (change, context) => {
    const beforeData = change.before.data();
    const afterData = change.after.data();
    const alertId = context.params.alertId;

    // 1. Guard against infinite loops or already processed documents
    if (afterData.ai_triage && afterData.ai_triage.detected_language) {
      return null;
    }

    // 2. Identify new attachments
    const beforeUrls = beforeData.attachments || [];
    const afterUrls = afterData.attachments || [];
    const newUrls = afterUrls.filter(url => !beforeUrls.includes(url));

    // 3. Find if any of the new attachments are audio files (.m4a or .wav)
    const audioUrl = newUrls.find(url => 
      url.toLowerCase().includes(".m4a") || 
      url.toLowerCase().includes(".wav") || 
      url.toLowerCase().includes(".mp3")
    );

    if (!audioUrl) {
      return null;
    }

    console.log(`[AUDIO_TRIAGE] New audio attachment detected for alert: ${alertId}. URL: ${audioUrl}`);

    try {
      // Decode GCS path from firebasestorage download URL
      // Format: https://firebasestorage.googleapis.com/v0/b/{bucket}/o/{path}?alt=media
      const decodedUrl = decodeURIComponent(audioUrl);
      const oIndex = decodedUrl.indexOf('/o/');
      if (oIndex === -1) {
        throw new Error("Could not parse Storage path from URL");
      }
      const qIndex = decodedUrl.indexOf('?');
      const storagePath = decodedUrl.substring(oIndex + 3, qIndex !== -1 ? qIndex : decodedUrl.length);

      console.log(`[AUDIO_TRIAGE] Downloading audio file from storage path: ${storagePath}`);
      const bucket = admin.storage().bucket();
      const [fileBuffer] = await bucket.file(storagePath).download();

      console.log(`[AUDIO_TRIAGE] Initializing Vertex AI Gemini multimodal audio analysis`);
      const project = process.env.GCP_PROJECT || process.env.GCLOUD_PROJECT || "kusuconsult-rainbow";
      const vertexAI = new VertexAI({ project: project, location: "us-central1" });
      
      const responseSchema = {
        type: "OBJECT",
        properties: {
          transcription: { type: "STRING" },
          detected_language: { type: "STRING" },
          recommended_type: { type: "STRING" },
          recommended_priority: { type: "STRING" },
          justification: { type: "STRING" },
          weapons_detected: { type: "BOOLEAN" },
          crowd_size: { type: "STRING" },
          confidence_score: { type: "NUMBER" },
          extracted_intel: {
            type: "OBJECT",
            properties: {
              suspects: {
                type: "ARRAY",
                items: {
                  type: "OBJECT",
                  properties: {
                    description: { type: "STRING" },
                    weapons: { type: "ARRAY", items: { type: "STRING" } }
                  },
                  required: ["description", "weapons"]
                }
              },
              victims: {
                type: "ARRAY",
                items: {
                  type: "OBJECT",
                  properties: {
                    count: { type: "INTEGER" },
                    condition: { type: "STRING" }
                  },
                  required: ["count", "condition"]
                }
              },
              weapons: { type: "ARRAY", items: { type: "STRING" } },
              vehicles: {
                type: "ARRAY",
                items: {
                  type: "OBJECT",
                  properties: {
                    type: { type: "STRING" },
                    color: { type: "STRING" },
                    plate: { type: "STRING" }
                  },
                  required: ["type", "color", "plate"]
                }
              },
              direction: { type: "STRING" },
              injuries: { type: "ARRAY", items: { type: "STRING" } },
              buildings_affected: { type: "ARRAY", items: { type: "STRING" } },
              fires: { type: "BOOLEAN" },
              hostages: {
                type: "OBJECT",
                properties: {
                  count: { type: "INTEGER" },
                  details: { type: "STRING" }
                },
                required: ["count", "details"]
              }
            },
            required: [
              "suspects", "victims", "weapons", "vehicles", 
              "direction", "injuries", "buildings_affected", 
              "fires", "hostages"
            ]
          }
        },
        required: [
          "transcription", "detected_language", "recommended_type", 
          "recommended_priority", "justification", "weapons_detected", 
          "crowd_size", "confidence_score", "extracted_intel"
        ]
      };

      const generativeModel = vertexAI.getGenerativeModel({
        model: "gemini-1.5-flash",
        generationConfig: {
          responseMimeType: "application/json",
          responseSchema: responseSchema
        }
      });

      const audioPart = {
        inlineData: {
          data: fileBuffer.toString("base64"),
          mimeType: "audio/m4a"
        }
      };

      const prompt = `You are the Operation Rainbow Emergency Audio Transcriber & Triage AI.
Analyze the attached audio recording of a citizen reporting an emergency.

1. Transcribe the raw audio text accurately. Detect and translate to professional English if the speech is in Hausa, Nigerian Pidgin, or other local Plateau State dialects.
2. Categorize the incident, recommend priority (LOW, MEDIUM, HIGH, CRITICAL), estimate confidence score, and extract all tactical entities (weapons, crowd size, suspects, victims, vehicles, injuries, direction, buildings affected, fires, and hostages).
If any entity is not mentioned, provide an empty list, empty string, or false/zero.`;

      console.log(`[AUDIO_TRIAGE] Generating Gemini response...`);
      const responseStream = await generativeModel.generateContent({
        contents: [{ role: "user", parts: [audioPart, { text: prompt }] }]
      });

      const response = await responseStream.response;
      const responseText = response.candidates[0].content.parts[0].text;
      console.log(`[AUDIO_TRIAGE] Raw Gemini response text: ${responseText}`);

      const triageResult = JSON.parse(responseText);

      // 4. Update the Firestore alert document with the translation and triage parameters
      await db.collection("alerts").doc(alertId).update({
        description: triageResult.transcription,
        ai_triage: {
          recommended_type: triageResult.recommended_type,
          recommended_priority: triageResult.recommended_priority,
          justification: triageResult.justification,
          weapons_detected: triageResult.weapons_detected,
          crowd_size: triageResult.crowd_size,
          detected_language: triageResult.detected_language,
          translated_description: triageResult.transcription,
          confidence_score: triageResult.confidence_score || 1.0,
          extracted_intel: triageResult.extracted_intel || {}
        }
      });

      console.log(`[AUDIO_TRIAGE] Alert ${alertId} successfully updated with voice transcription and triage parameters.`);
    } catch (error) {
      console.error(`[AUDIO_TRIAGE_ERR] Failed to process audio report:`, error);
    }

    return null;
  });

// PRD: AI Voice Triage and Classification
// Accepts transcribed voice text and uses Gemini to categorize and create the incident.
exports.triageAndCreateVoiceAlert = functions.https.onCall(async (data, context) => {
  console.log(`[AI_VOICE_TRIAGE] Received triage payload: ${JSON.stringify(data)}`);

  await verifyRequestAuthenticity(data, context);

  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated.');
  }

  try {
    const { text, lat, lng } = data;
    const userId = context.auth.uid;

    if (!text || text.trim().length === 0) {
      throw new functions.https.HttpsError('invalid-argument', 'Text description is required for triage.');
    }

    // Rate limiting (5 per hour)
    const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000);
    const recentSnap = await db.collection("alerts")
      .where("reportedBy", "==", userId)
      .where("reportedAt", ">=", admin.firestore.Timestamp.fromDate(oneHourAgo))
      .get();
    
    if (recentSnap.size >= 5) {
      throw new functions.https.HttpsError("resource-exhausted", "Rate limit exceeded.");
    }

    const finalLat = lat || 9.9167;
    const finalLng = lng || 8.8917;

    // 1. Initialize Vertex AI Gemini for Triage
    const project = process.env.GCP_PROJECT || process.env.GCLOUD_PROJECT || "kusuconsult-rainbow";
    const vertexAI = new VertexAI({ project: project, location: "us-central1" });

    const responseSchema = {
      type: "OBJECT",
      properties: {
        category: { type: "STRING" },
        priority: { type: "STRING" },
        summary: { type: "STRING" },
        confidence_score: { type: "NUMBER" },
        extracted_intel: {
          type: "OBJECT",
          properties: {
            suspects: {
              type: "ARRAY",
              items: {
                type: "OBJECT",
                properties: {
                  description: { type: "STRING" },
                  weapons: { type: "ARRAY", items: { type: "STRING" } }
                },
                required: ["description", "weapons"]
              }
            },
            victims: {
              type: "ARRAY",
              items: {
                type: "OBJECT",
                properties: {
                  count: { type: "INTEGER" },
                  condition: { type: "STRING" }
                },
                required: ["count", "condition"]
              }
            },
            weapons: { type: "ARRAY", items: { type: "STRING" } },
            vehicles: {
              type: "ARRAY",
              items: {
                type: "OBJECT",
                properties: {
                  type: { type: "STRING" },
                  color: { type: "STRING" },
                  plate: { type: "STRING" }
                },
                required: ["type", "color", "plate"]
              }
            },
            direction: { type: "STRING" },
            injuries: { type: "ARRAY", items: { type: "STRING" } },
            buildings_affected: { type: "ARRAY", items: { type: "STRING" } },
            fires: { type: "BOOLEAN" },
            hostages: {
              type: "OBJECT",
              properties: {
                count: { type: "INTEGER" },
                details: { type: "STRING" }
              },
              required: ["count", "details"]
            }
          },
          required: [
            "suspects", "victims", "weapons", "vehicles", 
            "direction", "injuries", "buildings_affected", 
            "fires", "hostages"
          ]
        }
      },
      required: ["category", "priority", "summary", "confidence_score", "extracted_intel"]
    };

    const generativeModel = vertexAI.getGenerativeModel({
      model: "gemini-1.5-flash",
      generationConfig: {
        responseMimeType: "application/json",
        responseSchema: responseSchema
      }
    });

    const prompt = `You are the Operation Rainbow Emergency Report Triage AI.
Analyze the following emergency description reported by a citizen:
"${text}"

1. Classify the incident into exactly one of these categories: "Kidnap", "Fire", "Drug abuse", "Police brutality", "Flood", "Cyber crime", "Child abuse", "Domestic violence", "Cattle rustling", "Community attack", or "Other".
2. Recommend the priority: "LOW", "MEDIUM", "HIGH", or "CRITICAL".
3. Provide a brief 1-sentence summary of the incident.
4. Extract structured intelligence details (suspects, weapons, vehicles, direction, injuries, buildings, hostages, fires, and your confidence score).
If any field is missing or not mentioned in the transcript, set it to a blank array, a blank string, or zero where appropriate.`;

    const responseStream = await generativeModel.generateContent({
      contents: [{ role: "user", parts: [{ text: prompt }] }]
    });

    const response = await responseStream.response;
    const responseText = response.candidates[0].content.parts[0].text;
    console.log(`[AI_VOICE_TRIAGE] Raw Gemini response text: ${responseText}`);

    const triageResult = JSON.parse(responseText);

    const alertData = {
      type: triageResult.category || "Other",
      description: text,
      lat: finalLat,
      lng: finalLng,
      geo_lga: "RESOLVING",
      geo_ward: "RESOLVING",
      geo_pu: "RESOLVING",
      reportedBy: userId,
      status: "OPEN",
      priority: triageResult.priority || "HIGH",
      assigned_to: "POLLING_UNIT",
      reportedAt: admin.firestore.FieldValue.serverTimestamp(),
      attachments: [],
      sync_status: "COMPLETED",
      ai_triage: {
        recommended_type: triageResult.category || "Other",
        recommended_priority: triageResult.priority || "HIGH",
        justification: triageResult.summary || "AI Triaged from voice report",
        weapons_detected: (triageResult.extracted_intel && triageResult.extracted_intel.weapons && triageResult.extracted_intel.weapons.length > 0) || false,
        crowd_size: "N/A",
        detected_language: "English",
        translated_description: text,
        confidence_score: triageResult.confidence_score || 1.0,
        extracted_intel: triageResult.extracted_intel || {}
      },
      timeline: [
        {
          type: "CREATED",
          actor: userId,
          role: "CITIZEN",
          timestamp: new Date().toISOString(),
          reason: "AI Voice Report Initiated",
          notes: `Classified by AI as ${triageResult.category} with ${triageResult.priority} priority. Summary: ${triageResult.summary}`
        }
      ]
    };

    const docRef = await db.collection("alerts").add(alertData);
    
    // Initial Escalation Task
    const configSnap = await db.collection("system").doc("config").get();
    const thresholds = configSnap.exists ? (configSnap.data().escalation_thresholds || {}) : { POLLING_UNIT: 2 };
    const waitMinutes = thresholds.POLLING_UNIT || 2;

    const queue = getFunctions().taskQueue("escalateTask");
    await queue.enqueue({ alertId: docRef.id, targetTier: "WARD" }, {
      scheduleDelaySeconds: waitMinutes * 60 
    });

    return { success: true, alertId: docRef.id, category: triageResult.category, priority: triageResult.priority };
  } catch (error) {
    console.error(`[AI_VOICE_TRIAGE_ERR]`, error);
    throw new functions.https.HttpsError('internal', error.message || 'Triage failed');
  }
});




