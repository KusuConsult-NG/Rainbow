const admin = require("firebase-admin");
admin.initializeApp({
  projectId: "rainbow-app-mock"
});

const db = admin.firestore();

async function seed() {
  const code = "PU-AGENT-001";
  await db.collection("access_codes").doc(code).set({
    role: "POLLING_UNIT_OFFICER",
    jurisdiction: {
      lga: "JOS NORTH",
      ward: "NARAGUTA",
      pu: "PU-01"
    },
    badgeId: "PU-001",
    name: "John Doe",
    unit: "PATROL-ALPHA",
    multiUse: true,
    isUsed: false
  });
  console.log("Seeded access code: " + code);
}

seed().catch(console.error);
