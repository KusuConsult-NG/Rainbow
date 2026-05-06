/**
 * provision-hq-002.js
 * Creates the HQ-002 access code account using REST API for Auth to bypass ADC quota issues.
 */
const admin = require('firebase-admin');

const API_KEY = '***REMOVED-SECRET***';

admin.initializeApp({
  projectId: 'rainbow-97f1e',
});

const db = admin.firestore();

const USERS = [
  {
    badgeId: 'HQ-002',
    password: 'hq-002', 
    role: 'HQ_OFFICER',
    displayName: 'HQ Command Officer 002',
  },
];

async function main() {
  for (const user of USERS) {
    const email = `${user.badgeId.toLowerCase()}@operationrainbow.plateau.gov.ng`;
    try {
      console.log(`Attempting to create Auth user for ${email}...`);
      
      const authRes = await fetch(
        `https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${API_KEY}`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ email, password: user.password, returnSecureToken: true }),
        }
      );
      
      const authData = await authRes.json();
      
      if (!authRes.ok) {
        if (authData.error?.message === 'EMAIL_EXISTS') {
          console.log(`⚠️  Auth user already exists: ${email}`);
          // We still try to update Firestore in case it's missing
        } else {
          throw new Error(authData.error?.message || 'Auth creation failed');
        }
      } else {
        console.log(`✅ Auth user created: ${email} (uid: ${authData.localId})`);
      }

      const uid = authData.localId || (await admin.auth().getUserByEmail(email)).uid;

      // Write Firestore profile
      await db.collection('users').doc(uid).set({
        email,
        badgeId: user.badgeId,
        role: user.role,
        displayName: user.displayName,
        createdAt: new Date().toISOString(),
      }, { merge: true });

      console.log(`✅ Firestore profile synced for ${user.badgeId}`);
      console.log(`🔑 Access Code: ${user.badgeId}`);
    } catch (err) {
      console.error(`❌ Failed for ${email}:`, err.message);
    }
  }
  console.log('\nDone!');
  process.exit(0);
}

main();
