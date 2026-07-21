/**
 * seed-safe-zones.js
 * Seeds authoritative safe zone locations for Plateau State into Firestore.
 * Locations are real known civil/emergency facilities within Plateau State LGAs.
 * Run: node scripts/seed-safe-zones.js
 */

const admin = require('firebase-admin');

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  projectId: process.env.GCLOUD_PROJECT || 'rainbow-97f1e',
});

const db = admin.firestore();

const safeZones = [
  // ── JOS NORTH ──────────────────────────────────────────────────
  {
    id: 'sz_jos_north_tafawa_police',
    name: 'Tafawa Balewa Square Police Post',
    type: 'POLICE',
    lga: 'Jos North',
    address: 'Tafawa Balewa Way, Jos',
    lat: 9.9317,
    lng: 8.8942,
    capacity: 50,
    contact: '080000000001',
    active: true,
  },
  {
    id: 'sz_jos_north_plateau_hospital',
    name: 'Plateau State Specialist Hospital',
    type: 'HOSPITAL',
    lga: 'Jos North',
    address: 'Hospital Road, Jos',
    lat: 9.9213,
    lng: 8.8898,
    capacity: 200,
    contact: '080000000002',
    active: true,
  },
  {
    id: 'sz_jos_north_statehs',
    name: 'Jos North LGA Secretariat (Shelter)',
    type: 'SHELTER',
    lga: 'Jos North',
    address: 'LGA Secretariat, Jos',
    lat: 9.9350,
    lng: 8.8880,
    capacity: 150,
    contact: '080000000003',
    active: true,
  },

  // ── JOS SOUTH ──────────────────────────────────────────────────
  {
    id: 'sz_jos_south_police_hq',
    name: 'Jos South Area Command Police HQ',
    type: 'POLICE',
    lga: 'Jos South',
    address: 'Bukuru, Jos South',
    lat: 9.7976,
    lng: 8.8647,
    capacity: 60,
    contact: '080000000004',
    active: true,
  },
  {
    id: 'sz_jos_south_statehs',
    name: 'Bukuru General Hospital',
    type: 'HOSPITAL',
    lga: 'Jos South',
    address: 'Hospital Road, Bukuru',
    lat: 9.7910,
    lng: 8.8703,
    capacity: 120,
    contact: '080000000005',
    active: true,
  },

  // ── JOS EAST ───────────────────────────────────────────────────
  {
    id: 'sz_jos_east_police',
    name: 'Jos East Divisional Police',
    type: 'POLICE',
    lga: 'Jos East',
    address: 'Heipang, Jos East',
    lat: 9.9560,
    lng: 9.0012,
    capacity: 40,
    contact: '080000000006',
    active: true,
  },

  // ── BARKIN LADI ─────────────────────────────────────────────────
  {
    id: 'sz_barkinladi_police',
    name: 'Barkin Ladi Divisional Police',
    type: 'POLICE',
    lga: 'Barkin Ladi',
    address: 'Barkin Ladi Town',
    lat: 9.5240,
    lng: 8.9025,
    capacity: 40,
    contact: '080000000007',
    active: true,
  },
  {
    id: 'sz_barkinladi_hospital',
    name: 'Barkin Ladi General Hospital',
    type: 'HOSPITAL',
    lga: 'Barkin Ladi',
    address: 'Hospital Road, Barkin Ladi',
    lat: 9.5218,
    lng: 8.9047,
    capacity: 80,
    contact: '080000000008',
    active: true,
  },

  // ── RIYOM ───────────────────────────────────────────────────────
  {
    id: 'sz_riyom_police',
    name: 'Riyom Divisional Police Post',
    type: 'POLICE',
    lga: 'Riyom',
    address: 'Riyom Town Center',
    lat: 9.5978,
    lng: 8.7892,
    capacity: 35,
    contact: '080000000009',
    active: true,
  },

  // ── MANGU ────────────────────────────────────────────────────────
  {
    id: 'sz_mangu_hospital',
    name: 'Mangu General Hospital',
    type: 'HOSPITAL',
    lga: 'Mangu',
    address: 'Mangu Town',
    lat: 9.7243,
    lng: 9.0523,
    capacity: 100,
    contact: '080000000010',
    active: true,
  },
  {
    id: 'sz_mangu_police',
    name: 'Mangu Divisional Police',
    type: 'POLICE',
    lga: 'Mangu',
    address: 'Police Barracks, Mangu',
    lat: 9.7290,
    lng: 9.0489,
    capacity: 45,
    contact: '080000000011',
    active: true,
  },

  // ── PANKSHIN ─────────────────────────────────────────────────────
  {
    id: 'sz_pankshin_hospital',
    name: 'Pankshin General Hospital',
    type: 'HOSPITAL',
    lga: 'Pankshin',
    address: 'Pankshin Town',
    lat: 9.3603,
    lng: 9.4300,
    capacity: 90,
    contact: '080000000012',
    active: true,
  },

  // ── KANAM ─────────────────────────────────────────────────────────
  {
    id: 'sz_kanam_hospital',
    name: 'Kanam General Hospital',
    type: 'HOSPITAL',
    lga: 'Kanam',
    address: 'Shendam Road, Kanam',
    lat: 9.0432,
    lng: 9.5879,
    capacity: 70,
    contact: '080000000013',
    active: true,
  },

  // ── SHENDAM ───────────────────────────────────────────────────────
  {
    id: 'sz_shendam_police',
    name: 'Shendam Area Command',
    type: 'POLICE',
    lga: 'Shendam',
    address: 'Police HQ, Shendam',
    lat: 8.8841,
    lng: 9.5342,
    capacity: 55,
    contact: '080000000014',
    active: true,
  },
  {
    id: 'sz_shendam_hospital',
    name: 'Shendam General Hospital',
    type: 'HOSPITAL',
    lga: 'Shendam',
    address: 'Hospital Street, Shendam',
    lat: 8.8812,
    lng: 9.5370,
    capacity: 80,
    contact: '080000000015',
    active: true,
  },

  // ── QUAT PAN ──────────────────────────────────────────────────────
  {
    id: 'sz_quatpan_shelter',
    name: 'Quat Pan Civic Center (Shelter)',
    type: 'SHELTER',
    lga: 'Quat Pan',
    address: 'Shendam-Langtang Road, Quat Pan',
    lat: 8.9850,
    lng: 9.3310,
    capacity: 60,
    contact: '080000000016',
    active: true,
  },

  // ── LANGTANG NORTH ────────────────────────────────────────────────
  {
    id: 'sz_langtangnorth_hospital',
    name: 'Langtang North General Hospital',
    type: 'HOSPITAL',
    lga: 'Langtang North',
    address: 'Langtang Town',
    lat: 8.7421,
    lng: 9.8004,
    capacity: 100,
    contact: '080000000017',
    active: true,
  },

  // ── LANGTANG SOUTH ────────────────────────────────────────────────
  {
    id: 'sz_langtangsouth_police',
    name: 'Langtang South Divisional Police',
    type: 'POLICE',
    lga: 'Langtang South',
    address: 'Namu Town',
    lat: 8.6130,
    lng: 9.8640,
    capacity: 35,
    contact: '080000000018',
    active: true,
  },

  // ── WASE ─────────────────────────────────────────────────────────
  {
    id: 'sz_wase_hospital',
    name: 'Wase General Hospital',
    type: 'HOSPITAL',
    lga: 'Wase',
    address: 'Hospital Road, Wase',
    lat: 8.9922,
    lng: 10.0842,
    capacity: 80,
    contact: '080000000019',
    active: true,
  },

  // ── MIKANG ───────────────────────────────────────────────────────
  {
    id: 'sz_mikang_shelter',
    name: 'Mikang LGA Secretariat (Shelter)',
    type: 'SHELTER',
    lga: 'Mikang',
    address: 'Mikang LGA HQ, Shendam Road',
    lat: 8.9303,
    lng: 9.2148,
    capacity: 70,
    contact: '080000000020',
    active: true,
  },

  // ── BOKKOS ───────────────────────────────────────────────────────
  {
    id: 'sz_bokkos_police',
    name: 'Bokkos Divisional Police',
    type: 'POLICE',
    lga: 'Bokkos',
    address: 'Bokkos Town',
    lat: 9.2811,
    lng: 9.0009,
    capacity: 40,
    contact: '080000000021',
    active: true,
  },

  // ── HQ COMMAND ───────────────────────────────────────────────────
  {
    id: 'sz_hq_command',
    name: 'Operation Rainbow HQ Command Post',
    type: 'MILITARY',
    lga: 'Jos North',
    address: 'HQ Command, Jos',
    lat: 9.9285,
    lng: 8.8921,
    capacity: 300,
    contact: '080000000000',
    active: true,
  },
];

async function seedSafeZones() {
  console.log(`\n🛡️  SAFE ZONE SEEDER — ${safeZones.length} locations\n`);
  const batch = db.batch();

  for (const zone of safeZones) {
    const ref = db.collection('safe_zones').doc(zone.id);
    batch.set(ref, {
      ...zone,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    console.log(`  ✅ ${zone.name} (${zone.lga}) — [${zone.lat}, ${zone.lng}]`);
  }

  await batch.commit();
  console.log('\n✅ All safe zones written to Firestore.\n');
  process.exit(0);
}

seedSafeZones().catch((err) => {
  console.error('❌ Seeder failed:', err);
  process.exit(1);
});
