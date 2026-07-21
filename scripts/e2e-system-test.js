const admin = require("firebase-admin");
const crypto = require("crypto");

async function runE2ESystemTest() {
  console.log("=== STARTING OPERATION RAINBOW SYSTEM E2E TEST ===");

  // 1. Initialize Admin SDK
  admin.initializeApp({ projectId: "rainbow-97f1e" });
  const db = admin.firestore();
  const auth = admin.auth();

  const testCitizenUid = "citizen_e2e_test_user";
  const testAgentUid = "agent_e2e_test_responder";
  const testAlertId = "alert_e2e_test_incident";

  try {
    // 2. Provision Test Agent in Auth and Firestore
    console.log("\n--- Phase 0: Provisioning Test Users ---");
    await db.collection("users").doc(testAgentUid).set({
      uid: testAgentUid,
      role: "AGENT",
      name: "E2E Test Agent",
      badgeId: "E2E-TEST-BADGE",
      status: "active",
      isVerified: true
    });
    console.log("Created test agent in Firestore users collection.");

    try {
      await auth.createUser({
        uid: testAgentUid,
        email: "e2e_test_agent@operationrainbow.plateau.gov.ng",
        password: "TemporaryPassword123!",
      });
      console.log("Created test agent in Firebase Authentication.");
    } catch (e) {
      if (e.code === "auth/uid-already-exists") {
        console.log("Test agent already exists in Auth. Resetting status...");
        await auth.updateUser(testAgentUid, { disabled: false });
      } else {
        throw e;
      }
    }

    // 3. Step 1: Citizen SOS Trigger (Alert Creation)
    console.log("\n--- Phase 1: Citizen SOS Trigger Simulation ---");
    const alertPayload = {
      type: "TEST EMERGENCY",
      description: "E2E Test active incident verification",
      lat: 9.9167,
      lng: 8.8917,
      geo_lga: "JOS NORTH",
      geo_ward: "TUDUN WADA",
      geo_pu: "PU-001",
      reportedBy: testCitizenUid,
      status: "OPEN",
      priority: "HIGH",
      assigned_to: "POLLING_UNIT",
      reportedAt: admin.firestore.FieldValue.serverTimestamp(),
      timeline: [
        {
          type: "REPORTED",
          actor: testCitizenUid,
          role: "CITIZEN",
          timestamp: new Date().toISOString(),
          reason: "Incident Reported",
          notes: "E2E Test active incident verification"
        }
      ]
    };
    await db.collection("alerts").doc(testAlertId).set(alertPayload);
    console.log("✅ Step 1 SUCCESS: Simulated Citizen SOS. Alert created in status OPEN.");

    // Verification: Query alert from Firestore
    const alertSnap = await db.collection("alerts").doc(testAlertId).get();
    if (!alertSnap.exists || alertSnap.data().status !== "OPEN") {
      throw new Error("Verification failed: Alert document not created correctly.");
    }
    console.log("Verification SUCCESS: Alert retrieved and confirmed in OPEN state.");

    // 4. Step 2: Admin Dashboard Dispatch Agent
    console.log("\n--- Phase 2: Command HQ Admin Dispatch Simulation ---");
    const timelineDispatchEvent = {
      type: "DISPATCHED",
      actor: "admin_e2e_test@operationrainbow.plateau.gov.ng",
      role: "HQ_COMMAND",
      timestamp: new Date().toISOString(),
      reason: "Unit Dispatched",
      notes: `Dispatched tactical unit E2E Test Agent to incident site.`
    };
    await db.collection("alerts").doc(testAlertId).update({
      status: "DISPATCHED",
      assignedToUid: testAgentUid,
      last_edited_by: "admin_e2e_test@operationrainbow.plateau.gov.ng",
      dispatched_at: admin.firestore.FieldValue.serverTimestamp(),
      timeline: admin.firestore.FieldValue.arrayUnion(timelineDispatchEvent)
    });
    console.log("✅ Step 2 SUCCESS: Simulated HQ Admin dispatching agent.");

    // Verification: Query updated alert status
    const dispatchSnap = await db.collection("alerts").doc(testAlertId).get();
    const dispatchData = dispatchSnap.data();
    if (dispatchData.status !== "DISPATCHED" || dispatchData.assignedToUid !== testAgentUid) {
      throw new Error("Verification failed: Alert dispatch state mismatch.");
    }
    if (dispatchData.timeline.length !== 2 || dispatchData.timeline[1].type !== "DISPATCHED") {
      throw new Error("Verification failed: Timeline not appended with DISPATCHED event.");
    }
    console.log("Verification SUCCESS: Alert confirmed in DISPATCHED state with correct timeline event.");

    // 5. Step 3: Agent Field Response updates (Arrived & Resolved)
    console.log("\n--- Phase 3: Agent Response & Crisis Resolution Simulation ---");
    // Arrived
    const timelineArrivedEvent = {
      type: "ARRIVED",
      actor: testAgentUid,
      role: "AGENT",
      timestamp: new Date().toISOString(),
      reason: "Agent updated mission state to ARRIVED",
      notes: "Agent arrived on site."
    };
    await db.collection("alerts").doc(testAlertId).update({
      status: "ARRIVED",
      last_edited_by: testAgentUid,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      timeline: admin.firestore.FieldValue.arrayUnion(timelineArrivedEvent)
    });
    console.log("✅ Step 3a SUCCESS: Simulated Agent arrival on site.");

    let agentUpdateSnap = await db.collection("alerts").doc(testAlertId).get();
    if (agentUpdateSnap.data().status !== "ARRIVED") {
      throw new Error("Verification failed: Alert status not set to ARRIVED.");
    }

    // Resolved
    const timelineResolvedEvent = {
      type: "RESOLVED",
      actor: testAgentUid,
      role: "AGENT",
      timestamp: new Date().toISOString(),
      reason: "Agent updated mission state to RESOLVED",
      notes: "Crisis resolved."
    };
    await db.collection("alerts").doc(testAlertId).update({
      status: "RESOLVED",
      last_edited_by: testAgentUid,
      resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
      resolved_by: testAgentUid,
      timeline: admin.firestore.FieldValue.arrayUnion(timelineResolvedEvent)
    });
    console.log("✅ Step 3b SUCCESS: Simulated Agent resolving crisis.");

    agentUpdateSnap = await db.collection("alerts").doc(testAlertId).get();
    const finalAlertData = agentUpdateSnap.data();
    if (finalAlertData.status !== "RESOLVED") {
      throw new Error("Verification failed: Alert status not set to RESOLVED.");
    }
    if (finalAlertData.timeline.length !== 4) {
      throw new Error("Verification failed: Missing events in alert timeline.");
    }
    console.log("Verification SUCCESS: Mission confirmed RESOLVED with 4 intact timeline stages.");

    // 6. Step 4: App Uninstall Governance Flow
    console.log("\n--- Phase 4: App Deactivation & Uninstall Governance Simulation ---");
    // Request Uninstall
    await db.collection("uninstall_requests").doc(testAgentUid).set({
      uid: testAgentUid,
      email: "e2e_test_agent@operationrainbow.plateau.gov.ng",
      role: "AGENT",
      reason: "Testing app removal process",
      remarks: "E2E verification",
      status: "PENDING",
      createdAt: admin.firestore.FieldValue.serverTimestamp()
    });
    console.log("✅ Step 4a SUCCESS: Simulated Agent submitting deactivation request.");

    // Approve Uninstall and Generate Code
    const mockRemovalCode = "RMV-" + crypto.randomInt(100000, 1000000).toString();
    await db.collection("uninstall_requests").doc(testAgentUid).update({
      status: "APPROVED",
      removalCode: mockRemovalCode,
      approvedBy: "admin_e2e_test@operationrainbow.plateau.gov.ng",
      approvedAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: new Date(Date.now() + 2 * 60 * 60 * 1000)
    });
    console.log(`✅ Step 4b SUCCESS: Simulated HQ Admin approving deactivation request. Removal code generated: ${mockRemovalCode}`);

    // Validate Code and Complete
    const requestSnap = await db.collection("uninstall_requests").doc(testAgentUid).get();
    const requestData = requestSnap.data();
    if (requestData.status === "APPROVED" && requestData.removalCode === mockRemovalCode) {
      await db.collection("uninstall_requests").doc(testAgentUid).update({
        status: "COMPLETED",
        completedAt: admin.firestore.FieldValue.serverTimestamp()
      });
      await db.collection("users").doc(testAgentUid).update({
        status: "deactivated",
        deactivatedAt: admin.firestore.FieldValue.serverTimestamp(),
        deactivationReason: requestData.reason
      });
      await auth.updateUser(testAgentUid, { disabled: true });
      console.log("✅ Step 4c SUCCESS: Simulated Removal Code Validation. User account successfully deactivated.");
    } else {
      throw new Error("Validation check failed: invalid status or removal code.");
    }

    // Verify deactivation in Firestore and Auth
    const userSnap = await db.collection("users").doc(testAgentUid).get();
    if (userSnap.data().status !== "deactivated") {
      throw new Error("Verification failed: User status in Firestore is not deactivated.");
    }
    const authUser = await auth.getUser(testAgentUid);
    if (!authUser.disabled) {
      throw new Error("Verification failed: Auth account was not disabled.");
    }
    console.log("Verification SUCCESS: Agent account confirmed deactivated in both database and auth registry.");

  } catch (error) {
    console.error("\n❌ E2E TEST CRITICAL FAILURE:", error);
    process.exitCode = 1;
  } finally {
    // 7. Cleanup
    console.log("\n--- Phase 5: Cleanup System State ---");
    try {
      await db.collection("alerts").doc(testAlertId).delete();
      await db.collection("uninstall_requests").doc(testAgentUid).delete();
      await db.collection("users").doc(testAgentUid).delete();
      try {
        await auth.deleteUser(testAgentUid);
      } catch (authErr) {
        if (authErr.code !== "auth/user-not-found") throw authErr;
      }
      console.log("🧹 Cleanup completed. All test assets removed successfully.");
    } catch (cleanupError) {
      console.error("⚠️ Cleanup error occurred:", cleanupError);
    }
  }

  console.log("\n=== E2E SYSTEM TEST RUN COMPLETE ===");
}

runE2ESystemTest();
