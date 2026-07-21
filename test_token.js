const admin = require("firebase-admin");
admin.initializeApp();
async function run() {
  try {
    const token = await admin.auth().createCustomToken("test-uid", { role: "AGENT" });
    console.log("Token success:", token.substring(0, 20));
  } catch (e) {
    console.error("Token error:", e);
  }
}
run();
