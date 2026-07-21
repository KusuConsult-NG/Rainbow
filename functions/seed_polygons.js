const admin = require('firebase-admin');

// Note: Replace this with your actual GeoJSON mapping of Plateau State
const MOCK_GEOJSON = {
  features: [
    {
      type: "Feature",
      properties: {
        lga: "JOS NORTH",
        ward: "ALL",
        pu: "ALL",
        lga_pcode: "JOSN-01"
      },
      geometry: {
        type: "Polygon",
        coordinates: [
          [
            [8.8, 9.8],
            [8.9, 9.8],
            [8.9, 9.9],
            [8.8, 9.9],
            [8.8, 9.8]
          ]
        ]
      }
    }
  ]
};

if (!admin.apps.length) {
  try {
    admin.initializeApp({ projectId: "rainbow-97f1e" });
  } catch (e) {
    console.error("Please run via 'firebase-admin' context");
    process.exit(1);
  }
}

const db = admin.firestore();

async function seedPolygons() {
  console.log('--- Seeding Jurisdictional Polygons ---');
  let count = 0;
  
  for (const feature of MOCK_GEOJSON.features) {
    // Transform GeoJSON coordinates to the {lat, lng} array expected by the backend
    const coords = feature.geometry.coordinates[0].map(coord => ({
      lng: coord[0],
      lat: coord[1]
    }));
    
    const docRef = db.collection('jurisdictions').doc(feature.properties.lga_pcode);
    await docRef.set({
      ...feature.properties,
      coordinates: coords,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });
    
    console.log(`Seeded polygon for LGA: ${feature.properties.lga}`);
    count++;
  }
  
  console.log(`\nSuccessfully seeded ${count} jurisdiction polygons.`);
}

seedPolygons().then(() => {
  console.log('Done.');
  process.exit(0);
}).catch(err => {
  console.error('Error seeding polygons:', err);
  process.exit(1);
});
