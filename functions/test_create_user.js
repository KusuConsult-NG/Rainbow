const admin = require("firebase-admin");
admin.initializeApp({ projectId: "rainbow-97f1e" });
const db = admin.firestore();

async function run() {
  const uid = "agent_test_123";
  const email = `agent_test_123@operationrainbow.plateau.gov.ng`;
  const password = "tactical_secure_password";
  
  try {
    let userRecord;
    try {
      userRecord = await admin.auth().getUser(uid);
      await admin.auth().updateUser(uid, { password });
      console.log("Updated existing user");
    } catch (e) {
      if (e.code === 'auth/user-not-found') {
        userRecord = await admin.auth().createUser({
          uid,
          email,
          password,
        });
        console.log("Created new user");
      } else {
        throw e;
      }
    }
    
    // Also we need to set Custom Claims for roles since createCustomToken also embedded claims!
    await admin.auth().setCustomUserClaims(uid, {
      role: 'AGENT',
      isStaff: true
    });
    console.log("Claims set successfully");
    
  } catch(e) {
    console.error("Auth Admin Error:", e);
  }
}

run();
