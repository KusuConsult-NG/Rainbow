#!/usr/bin/env node
process.env.GOOGLE_CLOUD_QUOTA_PROJECT = 'rainbow-97f1e';

/**
 * provision-respondents.js
 * Operation Rainbow — Respondent Account Provisioning (REST Workaround)
 *
 * Creates Firebase Auth (via REST API) + Firestore profiles for all field respondents.
 * Bypasses Admin SDK 403 quota errors.
 */

const admin = require('../functions/node_modules/firebase-admin');
const fetch = require('../functions/node_modules/node-fetch');
const fs = require('fs');
const path = require('path');

// Load API Key from .env.local
const envPath = path.join(__dirname, '../hq-dashboard-next/.env.local');
let API_KEY = '';
try {
    const envContent = fs.readFileSync(envPath, 'utf8');
    const apiKeyMatch = envContent.match(/NEXT_PUBLIC_FIREBASE_API_KEY=(.+)/);
    API_KEY = apiKeyMatch ? apiKeyMatch[1].trim() : '';
} catch (e) {
    console.warn('⚠️  Could not read .env.local, checking process.env...');
}

if (!API_KEY) {
    API_KEY = process.env.FIREBASE_API_KEY || '***REMOVED-SECRET***';
}

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: 'rainbow-97f1e',
  });
}

const db = admin.firestore();

/**
 * REST API Helper to create/update user
 */
async function ensureAuthUser(email, password, displayName) {
  try {
    // 1. Try to sign up
    const signupRes = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${API_KEY}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password, returnSecureToken: true })
    });

    const signupData = await signupRes.json();

    if (signupData.error) {
      if (signupData.error.message === 'EMAIL_EXISTS') {
        // Try to sign in to get the token and update profile if needed
        const signinRes = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${API_KEY}`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ email, password, returnSecureToken: true })
        });
        const signinData = await signinRes.json();
        
        if (signinData.error) {
           return { localId: null, error: `User exists but password mismatch or error: ${signinData.error.message}` };
        }
        
        // Update display name
        await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:update?key=${API_KEY}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ idToken: signinData.idToken, displayName, returnSecureToken: true })
        });

        return { localId: signinData.localId };
      }
      return { localId: null, error: signupData.error.message };
    }

    // Update display name for new user
    await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:update?key=${API_KEY}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ idToken: signupData.idToken, displayName, returnSecureToken: true })
    });

    return { localId: signupData.localId };
  } catch (err) {
    return { localId: null, error: err.message };
  }
}

const RESPONDENTS = [
  // HQ COMMAND
  { badgeId: 'hq-001', role: 'HQ_COMMAND', displayName: 'HQ Command Officer 001', accessCode: 'RbwHQ001#2026' },
  { badgeId: 'hq-002', role: 'HQ_COMMAND', displayName: 'HQ Command Officer 002', accessCode: 'RbwHQ002#2026' },
  
  // LGA COMMAND
  { badgeId: 'lga-jos-north-001', role: 'LGA_COMMAND', displayName: 'Jos North LGA Commander', accessCode: 'RbwLGA001#2026', geo_lga: 'Jos North' },
  { badgeId: 'lga-jos-south-001', role: 'LGA_COMMAND', displayName: 'Jos South LGA Commander', accessCode: 'RbwLGA002#2026', geo_lga: 'Jos South' },

  // WARD COMMAND
  { badgeId: 'wd-naraguta-001', role: 'WARD_COMMAND', displayName: 'Naraguta Ward Officer', accessCode: 'RbwWD001#2026', geo_lga: 'Jos North', geo_ward: 'Naraguta' },
  
  // PU OFFICERS (Agents)
  { badgeId: 'pu-001', role: 'POLLING_OFFICER', displayName: 'PU Agent 001', accessCode: 'RbwPU001#2026', geo_lga: 'Jos North', geo_ward: 'Naraguta', geo_pu: 'PU-001' },
  { badgeId: 'pu-002', role: 'POLLING_OFFICER', displayName: 'PU Agent 002', accessCode: 'RbwPU002#2026', geo_lga: 'Jos North', geo_ward: 'Naraguta', geo_pu: 'PU-002' },
  { badgeId: 'pu-003', role: 'POLLING_OFFICER', displayName: 'PU Agent 003', accessCode: 'RbwPU003#2026', geo_lga: 'Jos North', geo_ward: 'Naraguta', geo_pu: 'PU-003' },
  { badgeId: 'pu-004', role: 'POLLING_OFFICER', displayName: 'PU Agent 004', accessCode: 'RbwPU004#2026', geo_lga: 'Jos North', geo_ward: 'Naraguta', geo_pu: 'PU-004' },
  { badgeId: 'pu-005', role: 'POLLING_OFFICER', displayName: 'PU Agent 005', accessCode: 'RbwPU005#2026', geo_lga: 'Jos North', geo_ward: 'Naraguta', geo_pu: 'PU-005' },
  { badgeId: 'pu-006', role: 'POLLING_OFFICER', displayName: 'PU Agent 006', accessCode: 'RbwPU006#2026', geo_lga: 'Jos North', geo_ward: 'Naraguta', geo_pu: 'PU-006' },
  { badgeId: 'pu-007', role: 'POLLING_OFFICER', displayName: 'PU Agent 007', accessCode: 'RbwPU007#2026', geo_lga: 'Jos North', geo_ward: 'Naraguta', geo_pu: 'PU-007' },
  { badgeId: 'pu-008', role: 'POLLING_OFFICER', displayName: 'PU Agent 008', accessCode: 'RbwPU008#2026', geo_lga: 'Jos North', geo_ward: 'Naraguta', geo_pu: 'PU-008' },
  { badgeId: 'pu-009', role: 'POLLING_OFFICER', displayName: 'PU Agent 009', accessCode: 'RbwPU009#2026', geo_lga: 'Jos North', geo_ward: 'Naraguta', geo_pu: 'PU-009' },
  { badgeId: 'pu-010', role: 'POLLING_OFFICER', displayName: 'PU Agent 010', accessCode: 'RbwPU010#2026', geo_lga: 'Jos North', geo_ward: 'Naraguta', geo_pu: 'PU-010' },
];

const EMAIL_DOMAIN = '@operationrainbow.plateau.gov.ng';

async function main() {
  console.log('\n╔══════════════════════════════════════════════════════╗');
  console.log('║  OPERATION RAINBOW — Respondent Provisioning (REST)  ║');
  console.log('╚══════════════════════════════════════════════════════╝\n');

  console.log(`🚀 Provisioning ${RESPONDENTS.length} accounts...\n`);

  const results = [];

  for (const r of RESPONDENTS) {
    const email = `${r.badgeId}${EMAIL_DOMAIN}`.toLowerCase();
    let uid = null;
    let status = 'SUCCESS';

    try {
      // 1. Ensure Auth account exists via REST API
      const authResult = await ensureAuthUser(email, r.accessCode, r.displayName);
      
      if (authResult.error) {
        status = `AUTH_ERROR: ${authResult.error}`;
        // Fallback: Try to find existing UID from Firestore
        const userDoc = await db.collection('users').where('email', '==', email).limit(1).get();
        if (!userDoc.empty) {
            uid = userDoc.docs[0].id;
            console.log(`  Found existing Firestore record for ${r.badgeId}, using UID: ${uid}`);
        }
      } else {
        uid = authResult.localId;
      }

      if (uid) {
        // 2. Sync Firestore Record
        const userData = {
          uid,
          email,
          badgeId: r.badgeId.toUpperCase(),
          displayName: r.displayName,
          role: r.role,
          roleLabel: r.role.replace(/_/g, ' ').toLowerCase().replace(/\b\w/g, c => c.toUpperCase()),
          type: 'respondent',
          geo_lga: r.geo_lga || 'HQ',
          geo_ward: r.geo_ward || 'N/A',
          geo_pu: r.geo_pu || 'N/A',
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          status: 'active',
          profileComplete: true
        };

        await db.collection('users').doc(uid).set(userData, { merge: true });
        
        // Also map badgeId to uid for fast lookup
        await db.collection('badge_mappings').doc(r.badgeId.toUpperCase()).set({
          uid,
          email,
          role: r.role
        });
      } else if (status === 'SUCCESS') {
          status = 'FAILED: No UID';
      }
    } catch (err) {
      status = `ERROR: ${err.message}`;
    }

    results.push({ badgeId: r.badgeId, role: r.role, accessCode: r.accessCode, status });
    process.stdout.write(status === 'SUCCESS' ? '✅ ' : '❌ ');
  }

  console.log('\n\n--- PROVISIONING MANIFEST ---\n');
  console.table(results);

  console.log('\n  ⚠️  Store this manifest securely. Do NOT commit to version control.');
  console.log('\n  Login on device: Enter Badge ID → ACCESS CODE');
  console.log(`  Email domain   : ${EMAIL_DOMAIN}\n`);
  
  process.exit(0);
}

main().catch(err => {
    console.error('Fatal:', err);
    process.exit(1);
});
