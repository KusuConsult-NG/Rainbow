const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

initializeApp({
  projectId: 'rainbow-97f1e',
});

const db = getFirestore();

const ACCESS_CODES = [
  {
    code: 'RB-ALPHA-2026',
    role: 'LGA_OFFICER',
    lga: 'Jos North',
    ward: 'Tudun Wada',
    pu: 'PU-001',
    isUsed: false,
    maxUses: 10,
    expiresAt: new Date('2026-12-31'),
  },
  {
    code: 'RB-BETA-2026',
    role: 'WARD_OFFICER',
    lga: 'Jos South',
    ward: 'Bukuru',
    pu: 'PU-014',
    isUsed: false,
    maxUses: 5,
    expiresAt: new Date('2026-12-31'),
  },
  {
    code: 'RB-PU-2026',
    role: 'POLLING_UNIT_OFFICER',
    lga: 'Jos North',
    ward: 'Naraguta',
    pu: 'PU-001',
    isUsed: false,
    multiUse: true,
    expiresAt: new Date('2026-12-31'),
    name: 'PU Agent 001',
    badgeId: 'PU-001'
  },
  {
    code: 'RB-LGA-COMMAND-2026',
    role: 'LGA_COMMAND',
    lga: 'Jos North',
    ward: 'ALL',
    pu: 'ALL',
    isUsed: false,
    multiUse: true,
    expiresAt: new Date('2026-12-31'),
    name: 'Jos North LGA Commander',
    badgeId: 'LGA-001'
  }
];

async function seed() {
  console.log('[SEED] Provisioning tactical access codes...');
  const batch = db.batch();

  for (const code of ACCESS_CODES) {
    const docRef = db.collection('access_codes').doc(code.code);
    batch.set(docRef, {
      ...code,
      createdAt: new Date().toISOString(),
    });
    console.log(`  -> Provisioned: ${code.code} (${code.role})`);
  }

  await batch.commit();
  console.log('[SEED] Provisioning complete.');
  process.exit(0);
}

seed().catch(console.error);
