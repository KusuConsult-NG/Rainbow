const admin = require("firebase-admin");
admin.initializeApp({
  projectId: "rainbow-97f1e"
});
const db = admin.firestore();

async function run() {
  // Update a few alerts to Jos North sector so LGA/Ward/PU commanders can test them
  const alertIds = ["0ljn3lK7f1QJueYgFcbJ", "2ynpQUIcjC9bs8AcOakB", "5gKaFG0VmJZTlXJHuFyK"];
  
  for (const id of alertIds) {
    const ref = db.collection("alerts").doc(id);
    const doc = await ref.get();
    if (doc.exists) {
      await ref.update({
        geo_lga: "Jos North",
        geo_ward: "Tudun Wada",
        geo_pu: "PU-001"
      });
      console.log(`Updated alert ${id} to Jos North sector.`);
    }
  }
}
run().catch(console.error);
