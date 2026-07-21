const admin = require('firebase-admin');
admin.initializeApp({ projectId: "rainbow-97f1e" });

const db = admin.firestore();

const agentsToProvision = [
  {
    accessCode: 'HQ-COMMAND-001',
    role: 'HQ_OFFICER',
    name: 'Major General HQ',
    unit: 'Command HQ',
    jurisdiction: { lga: 'STATEWIDE', ward: 'STATEWIDE', pu: 'STATEWIDE' },
    badgeId: 'BADGE-HQ-001',
    multiUse: true
  },
  {
    accessCode: 'JOSN-LGA-001',
    role: 'LGA_OFFICER',
    name: 'Captain Jos North',
    unit: 'LGA Division',
    jurisdiction: { lga: 'JOS NORTH', ward: 'ALL', pu: 'ALL' },
    badgeId: 'BADGE-LGA-001',
    multiUse: true
  },
  {
    accessCode: 'WARD-TUDUN-001',
    role: 'WARD_OFFICER',
    name: 'Lieutenant Tudun Wada',
    unit: 'Ward Division',
    jurisdiction: { lga: 'JOS NORTH', ward: 'TUDUN WADA - KABONG', pu: 'ALL' },
    badgeId: 'BADGE-WARD-001',
    multiUse: true
  }
];

async function provisionAgents() {
  console.log('--- Initiating Agent Access Code Provisioning ---');
  let count = 0;
  
  for (const agent of agentsToProvision) {
    const docRef = db.collection('access_codes').doc(agent.accessCode);
    await docRef.set({
      ...agent,
      isUsed: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: new Date(Date.now() + 365 * 24 * 60 * 60 * 1000) // 1 year expiry
    }, { merge: true });
    
    console.log(`Provisioned access code: ${agent.accessCode} for role ${agent.role}`);
    count++;
  }
  
  console.log(`\nSuccessfully provisioned ${count} agent access codes.`);
}

provisionAgents().then(() => {
  console.log('Done.');
  process.exit(0);
}).catch(err => {
  console.error('Error provisioning agents:', err);
  process.exit(1);
});
