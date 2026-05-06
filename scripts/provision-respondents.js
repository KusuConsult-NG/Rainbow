#!/usr/bin/env node
/**
 * provision-respondents.js
 * Operation Rainbow — Respondent Account Provisioning
 *
 * Creates Firebase Auth + Firestore profiles for all field respondents.
 * Each account has:
 *   - Email   : {badgeId}@operationrainbow.plateau.gov.ng
 *   - Password: Their assigned ACCESS CODE (printed at end of script)
 *   - Role    : HQ_OFFICER | LGA_OFFICER | WARD_OFFICER | POLLING_OFFICER
 *
 * Prerequisites:
 *   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json
 *   node scripts/provision-respondents.js
 */

const admin = require('../functions/node_modules/firebase-admin');

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: 'rainbow-97f1e',
  });
}

const auth = admin.auth();
const db = admin.firestore();

// ─────────────────────────────────────────────────────────────
// RESPONDENT ROSTER — Edit access codes before first provisioning
// ─────────────────────────────────────────────────────────────
const RESPONDENTS = [
  // ── HQ Officers ──────────────────────────────────────────
  { badgeId: 'hq-001', role: 'HQ_OFFICER',       displayName: 'HQ Command Officer 001', accessCode: 'RbwHQ001#2026', geo_lga: 'ALL', geo_ward: 'ALL', geo_pu: 'ALL' },
  { badgeId: 'hq-002', role: 'HQ_OFFICER',       displayName: 'HQ Command Officer 002', accessCode: 'RbwHQ002#2026', geo_lga: 'ALL', geo_ward: 'ALL', geo_pu: 'ALL' },

  // ── LGA Officers ─────────────────────────────────────────
  { badgeId: 'lga-001', role: 'LGA_OFFICER',     displayName: 'LGA Officer — Jos North',   accessCode: 'RbwLGA001#2026', geo_lga: 'Jos North', geo_ward: 'ALL', geo_pu: 'ALL' },
  { badgeId: 'lga-002', role: 'LGA_OFFICER',     displayName: 'LGA Officer — Jos South',   accessCode: 'RbwLGA002#2026', geo_lga: 'Jos South', geo_ward: 'ALL', geo_pu: 'ALL' },
  { badgeId: 'lga-003', role: 'LGA_OFFICER',     displayName: 'LGA Officer — Barkin Ladi', accessCode: 'RbwLGA003#2026', geo_lga: 'Barkin Ladi', geo_ward: 'ALL', geo_pu: 'ALL' },

  // ── Ward Officers ─────────────────────────────────────────
  { badgeId: 'wd-001', role: 'WARD_OFFICER',     displayName: 'Ward Officer 001', accessCode: 'RbwWD001#2026', geo_lga: 'Jos North', geo_ward: 'Tudun Wada', geo_pu: 'ALL' },
  { badgeId: 'wd-002', role: 'WARD_OFFICER',     displayName: 'Ward Officer 002', accessCode: 'RbwWD002#2026', geo_lga: 'Jos North', geo_ward: 'Kabong', geo_pu: 'ALL' },
  { badgeId: 'wd-003', role: 'WARD_OFFICER',     displayName: 'Ward Officer 003', accessCode: 'RbwWD003#2026', geo_lga: 'Jos South', geo_ward: 'Bukuru', geo_pu: 'ALL' },
  { badgeId: 'wd-004', role: 'WARD_OFFICER',     displayName: 'Ward Officer 004', accessCode: 'RbwWD004#2026', geo_lga: 'Jos South', geo_ward: 'Du', geo_pu: 'ALL' },
  { badgeId: 'wd-005', role: 'WARD_OFFICER',     displayName: 'Ward Officer 005', accessCode: 'RbwWD005#2026', geo_lga: 'Barkin Ladi', geo_ward: 'Gashish', geo_pu: 'ALL' },

  // ── Polling Unit Officers ─────────────────────────────────
  { badgeId: 'pu-001', role: 'POLLING_OFFICER',  displayName: 'PU Officer 001', accessCode: 'RbwPU001#2026', geo_lga: 'Jos North', geo_ward: 'Tudun Wada', geo_pu: 'Unit 001' },
  { badgeId: 'pu-002', role: 'POLLING_OFFICER',  displayName: 'PU Officer 002', accessCode: 'RbwPU002#2026', geo_lga: 'Jos North', geo_ward: 'Tudun Wada', geo_pu: 'Unit 004' },
  { badgeId: 'pu-003', role: 'POLLING_OFFICER',  displayName: 'PU Officer 003', accessCode: 'RbwPU003#2026', geo_lga: 'Jos North', geo_ward: 'Kabong', geo_pu: 'Unit 001' },
  { badgeId: 'pu-004', role: 'POLLING_OFFICER',  displayName: 'PU Officer 004', accessCode: 'RbwPU004#2026', geo_lga: 'Jos South', geo_ward: 'Bukuru', geo_pu: 'Unit 001' },
  { badgeId: 'pu-005', role: 'POLLING_OFFICER',  displayName: 'PU Officer 005', accessCode: 'RbwPU005#2026', geo_lga: 'Jos South', geo_ward: 'Bukuru', geo_pu: 'Unit 002' },
  { badgeId: 'pu-006', role: 'POLLING_OFFICER',  displayName: 'PU Officer 006', accessCode: 'RbwPU006#2026', geo_lga: 'Jos South', geo_ward: 'Du', geo_pu: 'Unit 001' },
  { badgeId: 'pu-007', role: 'POLLING_OFFICER',  displayName: 'PU Officer 007', accessCode: 'RbwPU007#2026', geo_lga: 'Barkin Ladi', geo_ward: 'Gashish', geo_pu: 'Unit 001' },
  { badgeId: 'pu-008', role: 'POLLING_OFFICER',  displayName: 'PU Officer 008', accessCode: 'RbwPU008#2026', geo_lga: 'Barkin Ladi', geo_ward: 'Gashish', geo_pu: 'Unit 002' },
  { badgeId: 'pu-009', role: 'POLLING_OFFICER',  displayName: 'PU Officer 009', accessCode: 'RbwPU009#2026', geo_lga: 'Jos North', geo_ward: 'Kabong', geo_pu: 'Unit 002' },
  { badgeId: 'pu-010', role: 'POLLING_OFFICER',  displayName: 'PU Officer 010', accessCode: 'RbwPU010#2026', geo_lga: 'Jos South', geo_ward: 'Du', geo_pu: 'Unit 002' },
];

const EMAIL_DOMAIN = '@operationrainbow.plateau.gov.ng';

async function main() {
  console.log('\n╔══════════════════════════════════════════════════════╗');
  console.log('║  OPERATION RAINBOW — Respondent Provisioning         ║');
  console.log('╚══════════════════════════════════════════════════════╝\n');

  const results = [];

  for (const r of RESPONDENTS) {
    const email = `${r.badgeId}${EMAIL_DOMAIN}`;
    try {
      let uid;
      try {
        // Try to find existing account
        const existing = await auth.getUserByEmail(email);
        uid = existing.uid;
        // Update password to the access code
        await auth.updateUser(uid, { password: r.accessCode, displayName: r.displayName });
        console.log(`✏️  Updated  : ${r.badgeId}`);
      } catch (lookupErr) {
        if (lookupErr.code === 'auth/user-not-found') {
          // Create fresh account
          const newUser = await auth.createUser({
            email,
            password: r.accessCode,
            displayName: r.displayName,
          });
          uid = newUser.uid;
          console.log(`✅  Created  : ${r.badgeId}  (uid: ${uid})`);
        } else {
          throw lookupErr;
        }
      }

      // Upsert Firestore profile
      await db.collection('users').doc(uid).set({
        uid,
        email,
        badgeId: r.badgeId,
        role: r.role,
        roleLabel: r.role.replace('_', ' '),
        displayName: r.displayName,
        phone: '',
        profileComplete: true,
        geo_lga: r.geo_lga,
        geo_ward: r.geo_ward,
        geo_pu: r.geo_pu,
        provisionedAt: new Date().toISOString(),
      }, { merge: true });

      results.push({ badgeId: r.badgeId, email, accessCode: r.accessCode, role: r.role, status: 'OK' });
    } catch (err) {
      console.error(`❌  Failed   : ${r.badgeId} — ${err.message}`);
      results.push({ badgeId: r.badgeId, email, accessCode: r.accessCode, role: r.role, status: `ERROR: ${err.message}` });
    }
  }

  // Print credential summary table
  console.log('\n╔══════════════════════════════════════════════════════════════════════╗');
  console.log('║  CREDENTIAL MANIFEST — DISTRIBUTE SECURELY                          ║');
  console.log('╠═══════════════╦══════════════════════╦════════════════════╦══════════╣');
  console.log('║  BADGE ID     ║  ROLE                ║  ACCESS CODE       ║  STATUS  ║');
  console.log('╠═══════════════╬══════════════════════╬════════════════════╬══════════╣');
  for (const r of results) {
    const badge   = r.badgeId.padEnd(13);
    const role    = r.role.padEnd(20);
    const code    = r.accessCode.padEnd(18);
    const status  = r.status.padEnd(8);
    console.log(`║  ${badge} ║  ${role} ║  ${code} ║  ${status} ║`);
  }
  console.log('╚═══════════════╩══════════════════════╩════════════════════╩══════════╝');
  console.log('\n  ⚠️  Store this manifest securely. Do NOT commit to version control.\n');
  console.log(`  Login on device: Enter Badge ID → ACCESS CODE`);
  console.log(`  Email domain   : ${EMAIL_DOMAIN}\n`);

  process.exit(0);
}

main().catch(err => {
  console.error('\n❌ Fatal error:', err.message);
  process.exit(1);
});
