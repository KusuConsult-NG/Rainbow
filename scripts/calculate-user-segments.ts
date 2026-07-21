/**
 * scripts/calculate-user-segments.ts
 * Operation Rainbow — Tactical Audience Segmentation Audit
 * 
 * Analyzes the user database to categorize all accounts into mutually exclusive
 * command tiers and citizen segments for high-precision emergency broadcasts.
 */

const admin = require('../functions/node_modules/firebase-admin');

if (!admin.apps.length) {
    admin.initializeApp({
        credential: admin.credential.applicationDefault(),
        projectId: 'rainbow-97f1e',
    });
}

const db = admin.firestore();

function categorizeUser(data: any) {
    const role = data.role?.toUpperCase();
    if (role === 'HQ_OFFICER') return 'hq_command';
    if (role === 'LGA_OFFICER' || role === 'LGA_COMMAND') return 'lga_command';
    if (role === 'WARD_OFFICER' || role === 'WARD_COMMAND') return 'ward_command';
    if (role === 'POLLING_OFFICER' || role === 'UNIT_COMMAND') return 'unit_command';
    if (data.badgeId) return 'field_agents';
    return 'citizens';
}

async function calculateSegmentation() {
    console.log("📊 Calculating Operation Rainbow User Segmentation...");
    
    const segments: Record<string, number> = {
        hq_command: 0,
        lga_command: 0,
        ward_command: 0,
        unit_command: 0,
        field_agents: 0,
        citizens: 0
    };

    let totalAccounts = 0;

    console.log("📡 Streaming records from 'users' collection...");

    await new Promise((resolve, reject) => {
        db.collection('users').stream()
            .on("data", (doc: any) => {
                totalAccounts++;
                const data = doc.data();
                const segment = categorizeUser(data);
                segments[segment] = (segments[segment] || 0) + 1;
            })
            .on("end", resolve)
            .on("error", reject);
    });

    console.log("\n--- OPERATION RAINBOW SEGMENTATION BREAKDOWN ---");
    console.log(`Total Unique Accounts: ${totalAccounts}`);
    console.log("------------------------------------------------");

    Object.entries(segments).forEach(([name, count]) => {
        const percentage = ((count / totalAccounts) * 100).toFixed(1);
        const label = name.toUpperCase().replace('_', ' ');
        console.log(`${label.padEnd(15)}: ${count} (${percentage}%)`);
    });

    console.log("------------------------------------------------");
    process.exit(0);
}

calculateSegmentation().catch(err => {
    console.error("❌ Segmentation Audit Failed:", err);
    process.exit(1);
});
