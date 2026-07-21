const admin = require("firebase-admin");
admin.initializeApp({
  projectId: "rainbow-97f1e"
});
const db = admin.firestore();

async function run() {
  const snapshot = await db.collection("alerts").limit(5).get();
  console.log("Found", snapshot.size, "alerts:");
  snapshot.forEach(doc => {
    console.log(doc.id, "=>", doc.data());
  });
}
run().catch(console.error);
