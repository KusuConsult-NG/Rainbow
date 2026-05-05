/**
 * create-hq-admin.js
 * One-time script: creates the HQ admin Firebase Auth account.
 * Run: node create-hq-admin.js
 */
const { initializeApp, cert } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore } = require('firebase-admin/firestore');

// Uses Application Default Credentials (firebase login must be done)
// OR set GOOGLE_APPLICATION_CREDENTIALS env var to your service account JSON path
initializeApp({
  credential: cert(process.env.GOOGLE_APPLICATION_CREDENTIALS
    ? require(process.env.GOOGLE_APPLICATION_CREDENTIALS)
    : undefined
  ),
  projectId: 'rainbow-97f1e',
});

const auth = getAuth();
const db = getFirestore();

const ADMINS = [
  {
    badgeId: 'HQ-001',
    password: '12345Gg!',
    role: 'HQ_OFFICER',
    displayName: 'HQ Command Officer 001',
  },
];

async function main() {
  for (const admin of ADMINS) {
    const email = `${admin.badgeId.toLowerCase()}@operationrainbow.plateau.gov.ng`;
    try {
      // Create Firebase Auth user
      const userRecord = await auth.createUser({
        email,
        password: admin.password,
        displayName: admin.displayName,
      });

      // Write Firestore profile
      await db.collection('users').doc(userRecord.uid).set({
        email,
        badgeId: admin.badgeId,
        role: admin.role,
        displayName: admin.displayName,
        createdAt: new Date().toISOString(),
      });

      console.log(`✅ Created: ${email} (uid: ${userRecord.uid})`);
    } catch (err) {
      if (err.code === 'auth/email-already-exists') {
        console.log(`⚠️  Already exists: ${email} — skipping`);
      } else {
        console.error(`❌ Failed for ${email}:`, err.message);
      }
    }
  }
  console.log('\nDone!');
  process.exit(0);
}

main();
