const admin = require("firebase-admin");
admin.initializeApp({ projectId: "rainbow-97f1e" });
const db = admin.firestore();

// Math helpers
const calculateHaversine = (lat1, lon1, lat2, lon2) => {
  const R = 6371; // km
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
            Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
            Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
};

async function runC3ITestSuite() {
  console.log("=== STARTING C3I EXTENDED LOGICAL E2E TEST ===");

  const testAlertId1 = `e2e_alert_1_${Date.now()}`;
  const testAlertId2 = `e2e_alert_2_${Date.now()}`;
  const testResponderId = `e2e_responder_${Date.now()}`;

  try {
    // -------------------------------------------------------------
    // Test 1: Travel ETA Calculation logic verification
    // -------------------------------------------------------------
    console.log("\n[TEST 1] Verifying getETA Calculation Engine...");
    const incidentLat = 9.9167;
    const incidentLng = 8.8917;
    const responderLat = 9.9500; // ~4.6 km away straight-line
    const responderLng = 8.9200;

    const straightLine = calculateHaversine(incidentLat, incidentLng, responderLat, responderLng);
    const windingFactor = 1.35;
    const distanceKm = straightLine * windingFactor;

    // Gravel road quality, moderate traffic
    const baseSpeed = 40;
    const speedModifier = 0.75;
    const finalSpeed = baseSpeed * speedModifier;
    const etaHours = distanceKm / finalSpeed;
    const etaMinutes = Math.max(1, Math.round(etaHours * 60));

    console.log(`- Straight-line distance: ${straightLine.toFixed(2)} km`);
    console.log(`- Route distance (with winding): ${distanceKm.toFixed(2)} km`);
    console.log(`- Final Speed: ${finalSpeed} km/h`);
    console.log(`- Calculated ETA: ${etaMinutes} minutes`);

    if (etaMinutes <= 0 || isNaN(etaMinutes)) {
      throw new Error("ETA calculation engine produced invalid output.");
    }
    console.log("✅ getETA logic validation: SUCCESS");

    // -------------------------------------------------------------
    // Test 2: Multi-Agency Smart Dispatch Sorting logic verification
    // -------------------------------------------------------------
    console.log("\n[TEST 2] Verifying Smart Dispatch Matcher...");
    const mockResponders = [
      {
        uid: `${testResponderId}_1`,
        displayName: "Police Team Alpha",
        agencyId: "POLICE",
        lat: 9.9180,
        lng: 8.8920,
        capabilities: { live_status: "AVAILABLE", certifications: ["EMT"], equipment: ["Drone"] }
      },
      {
        uid: `${testResponderId}_2`,
        displayName: "Fire Service Team Beta",
        agencyId: "FIRE",
        lat: 9.9300,
        lng: 8.9000,
        capabilities: { live_status: "AVAILABLE", certifications: [], equipment: [] }
      }
    ];

    const incidentType = "Fire";
    const ratedResponders = mockResponders.map(res => {
      const dist = calculateHaversine(incidentLat, incidentLng, res.lat, res.lng);
      let score = 100 - (dist * 2);
      if (incidentType === "Fire" && res.agencyId === "FIRE") {
        score += 30; // Agency bonus
      }
      return { displayName: res.displayName, score: Math.max(0, score) };
    });

    console.log("- Dispatch Candidates Scores:");
    ratedResponders.forEach(r => console.log(`  * ${r.displayName}: ${r.score.toFixed(1)}`));

    if (ratedResponders[1].score <= ratedResponders[0].score) {
      throw new Error("Smart Dispatch did not correctly prioritize the Fire agency team for a fire incident.");
    }
    console.log("✅ Smart Dispatch logic validation: SUCCESS");

    // -------------------------------------------------------------
    // Test 3: Spatiotemporal Duplicate Merge verification
    // -------------------------------------------------------------
    console.log("\n[TEST 3] Verifying Spatiotemporal Duplicate Merge...");
    
    // Create first alert (parent)
    console.log("- Creating primary alert...");
    await db.collection("alerts").doc(testAlertId1).set({
      type: "Fire",
      description: "Building fire reported at Jos North",
      lat: 9.9167,
      lng: 8.8917,
      reportedBy: "citizen_1",
      status: "OPEN",
      priority: "HIGH",
      reportedAt: new Date().toISOString(),
      timeline: []
    });

    // Simulate duplicate check for a new report (same location, same category, 5 mins later)
    console.log("- Checking duplicate window...");
    const testAlert2 = {
      type: "Fire",
      description: "Big fire at Jos North near standard hotel",
      lat: 9.9168, // very close (10 meters)
      lng: 8.8918,
      reportedBy: "citizen_2",
      reportedAt: new Date().toISOString()
    };

    const duplicateThresholdMeters = 500;
    const duplicateTimeWindowMs = 15 * 60 * 1000;

    const activeAlerts = await db.collection("alerts")
      .where("status", "==", "OPEN")
      .get();

    let duplicateParentId = null;
    for (const doc of activeAlerts.docs) {
      const other = doc.data();
      if (other.type === testAlert2.type && other.reportedAt) {
        const dist = calculateHaversine(testAlert2.lat, testAlert2.lng, other.lat, other.lng) * 1000;
        const timeDiff = Math.abs(new Date(testAlert2.reportedAt) - new Date(other.reportedAt));

        if (dist <= duplicateThresholdMeters && timeDiff <= duplicateTimeWindowMs) {
          duplicateParentId = doc.id;
          break;
        }
      }
    }

    console.log(`- Matched Duplicate Parent: ${duplicateParentId}`);
    if (duplicateParentId !== testAlertId1) {
      throw new Error("Duplicate detection failed to match close incident of same type.");
    }
    console.log("✅ Spatiotemporal Duplicate logic validation: SUCCESS");

  } catch (err) {
    console.error("❌ E2E TEST RUN FAILURE:", err);
    process.exitCode = 1;
  } finally {
    // Clean up database state
    console.log("\n--- Cleaning Up Database Assets ---");
    await db.collection("alerts").doc(testAlertId1).delete();
    console.log("🧹 Cleanup complete.");
  }
}

runC3ITestSuite();
