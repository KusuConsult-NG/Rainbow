const admin = require("firebase-admin");
admin.initializeApp();
const db = admin.firestore();

async function getCodes() {
  const snapshot = await db.collection("access_codes").limit(10).get();
  if (snapshot.empty) {
    console.log("No access codes found in live database.");
    return;
  }
  snapshot.forEach(doc => {
    console.log(doc.id, "=>", doc.data());
  });
}
getCodes().catch(console.error);
