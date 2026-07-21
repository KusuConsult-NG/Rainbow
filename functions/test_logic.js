const admin = require("firebase-admin");
admin.initializeApp({ projectId: "rainbow-97f1e" });
const db = admin.firestore();

async function testCloudFunctionLogic(accessCode) {
  try {
    const codeSnap = await db.collection("access_codes").doc(accessCode.toUpperCase()).get();
    
    if (!codeSnap.exists) {
      throw new Error('Invalid or expired access code.');
    }

    const codeData = codeSnap.data();
    if (codeData.isUsed && codeData.multiUse !== true) {
      throw new Error('This access code has already been utilized.');
    }

    if (codeData.expiresAt && codeData.expiresAt.toDate() < new Date()) {
      throw new Error('Access code has expired.');
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

    console.log("Creating token for:", uid);
    // const customToken = await admin.auth().createCustomToken(uid, customClaims);
    // console.log("Token:", customToken);

    console.log("Updating users collection...");
    await db.collection("users").doc(uid).set({
      uid,
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
      console.log("Updating access code...");
      await codeSnap.ref.update({ 
        isUsed: true, 
        utilizedBy: uid,
        utilizedAt: admin.firestore.FieldValue.serverTimestamp() 
      });
    }

    console.log("Adding audit log...");
    await db.collection("audit_logs").add({
      action: "AGENT_AUTH_SUCCESS",
      actor: uid,
      role: customClaims.role,
      timestamp: admin.firestore.FieldValue.serverTimestamp()
    });

    console.log("Success!");

  } catch (error) {
    console.error(`[AUTH_FATAL] Access code validation failed:`, error);
  }
}

testCloudFunctionLogic("RB-PU-2026");
