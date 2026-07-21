const admin = require("firebase-admin");

async function provisionHqAdmin() {
  console.log("=== PROVISIONING HQ ADMIN USER ===");
  
  if (!admin.apps.length) {
    admin.initializeApp({ projectId: "rainbow-97f1e" });
  }
  
  const db = admin.firestore();
  const auth = admin.auth();

  const badgeId = "HQ-001";
  const email = "hq-001@operationrainbow.plateau.gov.ng";
  const password = "12345Gg!";
  const role = "HQ_COMMAND"; // Give full command role
  const displayName = "HQ Command Officer 001";

  try {
    let userRecord;
    try {
      userRecord = await auth.getUserByEmail(email);
      console.log(`Found existing user account for ${email}. Resetting password...`);
      await auth.updateUser(userRecord.uid, { password });
    } catch (e) {
      if (e.code === "auth/user-not-found") {
        console.log(`Creating new user account for ${email}...`);
        userRecord = await auth.createUser({
          email,
          password,
          displayName,
        });
      } else {
        throw e;
      }
    }

    const uid = userRecord.uid;

    // Enforce custom claims for dashboard RBAC
    const customClaims = {
      role,
      isStaff: true,
      badgeId,
    };
    await auth.setCustomUserClaims(uid, customClaims);
    console.log(`Set custom claims: ${JSON.stringify(customClaims)}`);

    // Write profile to Firestore
    await db.collection("users").doc(uid).set({
      uid,
      email,
      badgeId,
      role,
      isStaff: true,
      displayName,
      status: "active",
      profileComplete: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    console.log(`✅ Successfully provisioned ${badgeId} (${email}) in Auth and Firestore!`);
  } catch (error) {
    console.error("❌ Failed to provision HQ Admin:", error);
  }
  process.exit(0);
}

provisionHqAdmin();
