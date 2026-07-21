const admin = require("firebase-admin");
admin.initializeApp({
  projectId: "rainbow-97f1e"
});
const db = admin.firestore();

async function run() {
  const userRef = db.collection("users").doc("agent_BADGE-LGA-001");
  await userRef.update({
    lga: "Jos North",
    geo_lga: "Jos North"
  });
  console.log("Successfully updated user lga to standard mixed case.");
}
run().catch(console.error);
