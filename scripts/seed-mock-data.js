const admin = require('firebase-admin');

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: 'rainbow-97f1e',
  });
}

const db = admin.firestore();

// Bounding box around Plateau State (approx 8.8 to 10.2 Lat, 8.5 to 10.0 Lng)
const randomLat = () => 9.9167 + (Math.random() - 0.5) * 0.4;
const randomLng = () => 8.8917 + (Math.random() - 0.5) * 0.4;

const MOCK_ALERTS = [
  {
    type: 'Electoral Violence',
    description: 'Armed individuals attempting to hijack ballot boxes at Polling Unit 004. Immediate backup required.',
    status: 'ACTIVE',
    priority: 'CRITICAL',
    assigned_to: 'POLLING_UNIT',
    isCritical: true,
    reportedBy: '+2348012345678',
  },
  {
    type: 'Voter Intimidation',
    description: 'Group of men preventing citizens from voting based on ethnicity.',
    status: 'ACTIVE',
    priority: 'HIGH',
    assigned_to: 'WARD',
    isCritical: false,
    reportedBy: 'wd-012@operationrainbow.plateau.gov.ng',
  },
  {
    type: 'Logistics Failure',
    description: 'INEC materials have not arrived at Ward Center after 4 hours of scheduled time.',
    status: 'ACTIVE',
    priority: 'MEDIUM',
    assigned_to: 'LGA',
    isCritical: false,
    reportedBy: 'lga-003@operationrainbow.plateau.gov.ng',
  },
  {
    type: 'Medical Emergency',
    description: 'An elderly voter collapsed in the queue and requires immediate medical evacuation.',
    status: 'RESOLVED',
    priority: 'HIGH',
    assigned_to: 'POLLING_UNIT',
    isCritical: true,
    reportedBy: 'pu-099@operationrainbow.plateau.gov.ng',
  },
  {
    type: 'Riot / Protest',
    description: 'A protest has turned violent outside the LGA collation center. Tear gas deployed.',
    status: 'ACTIVE',
    priority: 'CRITICAL',
    assigned_to: 'HQ',
    isCritical: true,
    reportedBy: 'hq-005@operationrainbow.plateau.gov.ng',
  },
  {
    type: 'Suspicious Activity',
    description: 'Unmarked vehicles circling the perimeter of the ward collation center.',
    status: 'RESOLVED',
    priority: 'MEDIUM',
    assigned_to: 'WARD',
    isCritical: false,
    reportedBy: 'Anonymous Citizen',
  },
  {
    type: 'DURESS ACTIVATION',
    description: 'Agent initiated panic protocol via long-press. No verbal communication established.',
    status: 'DURESS',
    priority: 'CRITICAL',
    assigned_to: 'HQ',
    isCritical: true,
    reportedBy: 'pu-011@operationrainbow.plateau.gov.ng',
  },
  {
    type: 'Cyber / Disinformation',
    description: 'Fake election results being broadcast on local unlicensed radio station.',
    status: 'ACTIVE',
    priority: 'MEDIUM',
    assigned_to: 'HQ',
    isCritical: false,
    reportedBy: 'hq-intel@operationrainbow.plateau.gov.ng',
  },
  {
    type: 'Bribe / Vote Buying',
    description: 'Party agents distributing cash openly near PU 018.',
    status: 'ACTIVE',
    priority: 'HIGH',
    assigned_to: 'WARD',
    isCritical: false,
    reportedBy: '+2349098765432',
  },
  {
    type: 'DURESS ACTIVATION',
    description: 'Agent initiated duress pin during login. Situation likely compromised.',
    status: 'DURESS',
    priority: 'CRITICAL',
    assigned_to: 'LGA',
    isCritical: true,
    reportedBy: 'lga-002@operationrainbow.plateau.gov.ng',
  }
];

async function seed() {
  console.log('Seeding mock alerts...');
  
  const batch = db.batch();
  
  for (const alert of MOCK_ALERTS) {
    const docRef = db.collection('alerts').doc();
    
    // Add dynamic timestamps and coordinates
    const timeOffsetMinutes = Math.floor(Math.random() * 600); // Up to 10 hours ago
    const reportedAt = admin.firestore.Timestamp.fromDate(new Date(Date.now() - timeOffsetMinutes * 60000));
    
    batch.set(docRef, {
      ...alert,
      lat: randomLat(),
      lng: randomLng(),
      reportedAt: reportedAt
    });
  }

  await batch.commit();
  console.log(`✅ Successfully seeded ${MOCK_ALERTS.length} mock alerts to Firestore.`);
  process.exit(0);
}

seed().catch(err => {
  console.error('❌ Error seeding data:', err);
  process.exit(1);
});
