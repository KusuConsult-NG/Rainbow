const admin = require("firebase-admin");

// Initialize Firebase Admin with default credentials
admin.initializeApp({
  credential: admin.credential.applicationDefault()
});

const db = admin.firestore();

const mockAlerts = [
  {
    type: "Kidnap - Attempted Kidnap",
    description: "Suspicious individuals monitoring school bus route near Mangu.",
    lat: 9.5133,
    lng: 9.0967,
    reportedBy: "+2348001112222",
    isCritical: true,
    status: "ACTIVE",
    priority: "CRITICAL",
    assigned_to: "WARD",
    reportedAt: admin.firestore.FieldValue.serverTimestamp()
  },
  {
    type: "Fire - Bush Fire",
    description: "Large bush fire spreading towards residential area in Jos South.",
    lat: 9.7716,
    lng: 8.8681,
    reportedBy: "anonymous",
    isCritical: true,
    status: "ACTIVE",
    priority: "CRITICAL",
    assigned_to: "LGA",
    reportedAt: admin.firestore.FieldValue.serverTimestamp()
  },
  {
    type: "Police brutality - Extortion",
    description: "Officers setting up illegal checkpoint near Barkin Ladi.",
    lat: 9.5375,
    lng: 8.8958,
    reportedBy: "+2347012345678",
    isCritical: false,
    status: "ACTIVE",
    priority: "HIGH",
    assigned_to: "POLLING_UNIT",
    reportedAt: admin.firestore.FieldValue.serverTimestamp()
  },
  {
    type: "Community attack - Armed Invasion",
    description: "Gunshots heard on the outskirts of Riyom.",
    lat: 9.6333,
    lng: 8.7667,
    reportedBy: "anonymous",
    isCritical: true,
    status: "DURESS",
    priority: "CRITICAL",
    assigned_to: "HQ",
    reportedAt: admin.firestore.FieldValue.serverTimestamp()
  },
  {
    type: "Flood - Submerged Property",
    description: "Heavy rain causing severe flooding in Jos North.",
    lat: 9.9248,
    lng: 8.8920,
    reportedBy: "+2349098765432",
    isCritical: false,
    status: "ACTIVE",
    priority: "MEDIUM",
    assigned_to: "WARD",
    reportedAt: admin.firestore.FieldValue.serverTimestamp()
  },
  {
    type: "Drug abuse - Public Drug Use",
    description: "Group of youths taking illicit substances in public park.",
    lat: 9.8965,
    lng: 8.8583,
    reportedBy: "anonymous",
    isCritical: false,
    status: "ACTIVE",
    priority: "MEDIUM",
    assigned_to: "POLLING_UNIT",
    reportedAt: admin.firestore.FieldValue.serverTimestamp()
  },
  {
    type: "Cyber crime - Online Fraud",
    description: "Scammer cafe operating out of a local plaza.",
    lat: 9.9322,
    lng: 8.8922,
    reportedBy: "+2348123456789",
    isCritical: false,
    status: "RESOLVED",
    priority: "MEDIUM",
    assigned_to: "WARD",
    reportedAt: admin.firestore.FieldValue.serverTimestamp()
  },
  {
    type: "Domestic violence - Trapped",
    description: "Neighbor is locked in house and calling for help.",
    lat: 9.8600,
    lng: 8.8800,
    reportedBy: "anonymous",
    isCritical: true,
    status: "DURESS",
    priority: "HIGH",
    assigned_to: "POLLING_UNIT",
    reportedAt: admin.firestore.FieldValue.serverTimestamp()
  },
  {
    type: "Kidnap - Immediate Abduction",
    description: "A child was just taken into an unmarked black vehicle.",
    lat: 9.8755,
    lng: 8.8522,
    reportedBy: "+2348033334444",
    isCritical: true,
    status: "DURESS",
    priority: "CRITICAL",
    assigned_to: "LGA",
    reportedAt: admin.firestore.FieldValue.serverTimestamp()
  },
  {
    type: "Cattle rustling - Armed Rustling",
    description: "Herd stolen at gunpoint in Wase.",
    lat: 9.1000,
    lng: 9.9667,
    reportedBy: "+2347076543210",
    isCritical: true,
    status: "ACTIVE",
    priority: "HIGH",
    assigned_to: "WARD",
    reportedAt: admin.firestore.FieldValue.serverTimestamp()
  }
];

async function seed() {
  console.log("Seeding mock alerts...");
  const batch = db.batch();
  
  mockAlerts.forEach(alert => {
    const docRef = db.collection("alerts").doc();
    batch.set(docRef, alert);
  });

  await batch.commit();
  console.log("Successfully seeded 10 mock alerts to Firestore.");
  process.exit(0);
}

seed().catch(console.error);
