const admin = require('firebase-admin');
const serviceAccount = require('../service-account.json');
const boundaries = require('../hq-dashboard-next/public/plateau_boundaries.json');

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
}

const db = admin.firestore();

async function seedJurisdictions() {
  console.log('🚀 COMMENCING JURISDICTIONAL SEED...');
  const batch = db.batch();
  
  for (const feature of boundaries.features) {
    const { lga } = feature.properties;
    const coordinates = feature.geometry.coordinates[0]; // Simplified for mock data
    
    const docRef = db.collection('jurisdictions').doc(lga.toUpperCase().replace(/\s+/g, '_'));
    batch.set(docRef, {
      lga: lga.toUpperCase(),
      ward: 'STATEWIDE',
      pu: 'HQ-001',
      coordinates: coordinates,
      type: 'LGA_BOUNDARY',
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    });
    console.log(`[SEED] Prepared ${lga}`);
  }

  await batch.commit();
  console.log('✅ JURISDICTIONAL SEED COMPLETE.');
}

seedJurisdictions().catch(console.error);
