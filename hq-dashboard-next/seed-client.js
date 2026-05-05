require('dotenv').config({ path: '.env.local' });
const { initializeApp } = require('firebase/app');
const { getAuth, signInWithEmailAndPassword } = require('firebase/auth');
const { getFirestore, collection, addDoc, Timestamp } = require('firebase/firestore');

const firebaseConfig = {
  apiKey: process.env.NEXT_PUBLIC_FIREBASE_API_KEY,
  authDomain: process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN,
  projectId: process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID,
};

const app = initializeApp(firebaseConfig);
const auth = getAuth(app);
const db = getFirestore(app);

const randomLat = () => 9.9167 + (Math.random() - 0.5) * 0.4;
const randomLng = () => 8.8917 + (Math.random() - 0.5) * 0.4;

const MOCK_ALERTS = [
  { type: 'Electoral Violence', description: 'Armed individuals attempting to hijack ballot boxes at Polling Unit 004.', status: 'ACTIVE', priority: 'CRITICAL', assigned_to: 'POLLING_UNIT', isCritical: true, reportedBy: '+2348012345678' },
  { type: 'Voter Intimidation', description: 'Group of men preventing citizens from voting based on ethnicity.', status: 'ACTIVE', priority: 'HIGH', assigned_to: 'WARD', isCritical: false, reportedBy: 'wd-012@operationrainbow.plateau.gov.ng' },
  { type: 'Logistics Failure', description: 'INEC materials have not arrived at Ward Center after 4 hours.', status: 'ACTIVE', priority: 'MEDIUM', assigned_to: 'LGA', isCritical: false, reportedBy: 'lga-003@operationrainbow.plateau.gov.ng' },
  { type: 'Medical Emergency', description: 'An elderly voter collapsed in the queue and requires immediate medical evacuation.', status: 'RESOLVED', priority: 'HIGH', assigned_to: 'POLLING_UNIT', isCritical: true, reportedBy: 'pu-099@operationrainbow.plateau.gov.ng' },
  { type: 'Riot / Protest', description: 'A protest has turned violent outside the LGA collation center. Tear gas deployed.', status: 'ACTIVE', priority: 'CRITICAL', assigned_to: 'HQ', isCritical: true, reportedBy: 'hq-005@operationrainbow.plateau.gov.ng' },
  { type: 'Suspicious Activity', description: 'Unmarked vehicles circling the perimeter of the ward collation center.', status: 'RESOLVED', priority: 'MEDIUM', assigned_to: 'WARD', isCritical: false, reportedBy: 'Anonymous Citizen' },
  { type: 'DURESS ACTIVATION', description: 'Agent initiated panic protocol via long-press. No verbal communication established.', status: 'DURESS', priority: 'CRITICAL', assigned_to: 'HQ', isCritical: true, reportedBy: 'pu-011@operationrainbow.plateau.gov.ng' },
  { type: 'Cyber / Disinformation', description: 'Fake election results being broadcast on local unlicensed radio station.', status: 'ACTIVE', priority: 'MEDIUM', assigned_to: 'HQ', isCritical: false, reportedBy: 'hq-intel@operationrainbow.plateau.gov.ng' },
  { type: 'Bribe / Vote Buying', description: 'Party agents distributing cash openly near PU 018.', status: 'ACTIVE', priority: 'HIGH', assigned_to: 'WARD', isCritical: false, reportedBy: '+2349098765432' },
  { type: 'DURESS ACTIVATION', description: 'Agent initiated duress pin during login. Situation likely compromised.', status: 'DURESS', priority: 'CRITICAL', assigned_to: 'LGA', isCritical: true, reportedBy: 'lga-002@operationrainbow.plateau.gov.ng' }
];

async function seed() {
  console.log('Logging in as HQ-002...');
  await signInWithEmailAndPassword(auth, 'hq-002@operationrainbow.plateau.gov.ng', '12345Gg!');
  console.log('Login successful. Seeding mock alerts...');
  
  for (const alert of MOCK_ALERTS) {
    const timeOffsetMinutes = Math.floor(Math.random() * 600);
    const reportedAt = Timestamp.fromDate(new Date(Date.now() - timeOffsetMinutes * 60000));
    
    await addDoc(collection(db, 'alerts'), {
      ...alert,
      lat: randomLat(),
      lng: randomLng(),
      reportedAt: reportedAt
    });
  }

  console.log(`✅ Successfully seeded ${MOCK_ALERTS.length} mock alerts using Client SDK.`);
  process.exit(0);
}

seed().catch(err => {
  console.error('❌ Error seeding data:', err);
  process.exit(1);
});
