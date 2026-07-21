const admin = require("firebase-admin");
admin.initializeApp({ projectId: "rainbow-97f1e" });
const db = admin.firestore();

async function run() {
  const snap = await db.collection("jurisdictions").limit(1).get();
  console.log("Jurisdictions empty?", snap.empty);
  const snap2 = await db.collection("siec_wards").limit(1).get();
  console.log("siec_wards empty?", snap2.empty);
}
run();
