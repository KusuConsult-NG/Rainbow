#!/usr/bin/env node
/**
 * scripts/set-hq-password.js
 *
 * Uses firebase-admin with Application Default Credentials (from `firebase login`)
 * to forcibly reset the HQ admin password WITHOUT needing the old password.
 *
 * Run: node scripts/set-hq-password.js
 */

const admin = require('firebase-admin');

const PROJECT_ID = 'rainbow-97f1e';
const TARGET_EMAIL = 'hq-001@operationrainbow.plateau.gov.ng';
const NEW_PASSWORD = '12345Gg!';

// Initialise using Application Default Credentials.
// These are automatically populated when `firebase login --reauth` has been run.
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: PROJECT_ID,
  });
}

async function main() {
  console.log('\n🔐  Operation Rainbow — HQ Password Reset');
  console.log('   Target :', TARGET_EMAIL);
  console.log('   Project:', PROJECT_ID);
  console.log('');

  try {
    // Look up the user by email
    const user = await admin.auth().getUserByEmail(TARGET_EMAIL);
    console.log('   Found UID:', user.uid);

    // Force-update the password
    await admin.auth().updateUser(user.uid, { password: NEW_PASSWORD });
    
    // PRD: Enforce Custom Claims for Dashboard RBAC
    await admin.auth().setCustomUserClaims(user.uid, { 
      isStaff: true, 
      role: 'HQ_OFFICER',
      badgeId: 'HQ-001'
    });

    console.log('\n✅  Password and Claims updated successfully.');
    console.log('   Login  : http://localhost:3001/login');
    console.log('   Badge  : HQ-001');
    console.log('   Password:', NEW_PASSWORD);
  } catch (err) {
    if (err.code === 'auth/user-not-found') {
      console.log('   User not found — creating account...');
      const newUser = await admin.auth().createUser({
        email: TARGET_EMAIL,
        password: NEW_PASSWORD,
        displayName: 'HQ Command Officer 001',
      });

      // PRD: Enforce Custom Claims for Dashboard RBAC
      await admin.auth().setCustomUserClaims(newUser.uid, { 
        isStaff: true, 
        role: 'HQ_OFFICER',
        badgeId: 'HQ-001'
      });

      // Also write Firestore profile
      await admin.firestore().collection('users').doc(newUser.uid).set({
        uid: newUser.uid,
        email: TARGET_EMAIL,
        badgeId: 'HQ-001',
        role: 'HQ_OFFICER',
        displayName: 'HQ Command Officer 001',
        isStaff: true,
        createdAt: new Date().toISOString(),
      });
      console.log('\n✅  Account created, Claims set, and password set.');
      console.log('   UID    :', newUser.uid);
      console.log('   Login  : http://localhost:3001/login');
      console.log('   Badge  : HQ-001');
      console.log('   Password:', NEW_PASSWORD);
    } else {
      console.error('\n❌  Error:', err.message);
      console.error('');
      console.error('   If you see "Could not load the default credentials", run:');
      console.error('     gcloud auth application-default login');
      console.error('   OR download a service account key from Firebase Console →');
      console.error('   Project Settings → Service Accounts → Generate new private key');
      console.error('   Then: export GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json');
      console.error('   Then re-run: node scripts/set-hq-password.js');
      process.exit(1);
    }
  }

  process.exit(0);
}

main();
