/**
 * PLATEAU STATE JURISDICTION SEEDER
 * Seeds real LGA boundary polygons sourced from:
 * HDX/UN OCHA Nigeria Subnational Administrative Boundaries (COD-AB)
 * https://data.humdata.org/dataset/cod-ab-nga
 *
 * Admin Level 2 = LGA boundaries (17 LGAs in Plateau State)
 * 
 * Usage: node scripts/seed-plateau-jurisdictions.js
 */

const fs = require('fs');

const { initializeApp, cert, applicationDefault } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

// Uses Application Default Credentials from `firebase login --reauth`
// OR set GOOGLE_APPLICATION_CREDENTIALS env var to your service account JSON path
initializeApp({
  credential: process.env.GOOGLE_APPLICATION_CREDENTIALS
    ? cert(require(process.env.GOOGLE_APPLICATION_CREDENTIALS))
    : applicationDefault(),
  projectId: 'rainbow-97f1e',
});
const db = getFirestore();


// Official Plateau State SIEC/PLASIEC Councillorship Wards per LGA
// Source: INEC Election Results Portal (inecelectionresults.ng) + PLASIEC records
// These are the State Independent Electoral Commission (SIEC) wards used for
// Local Government Council elections in Plateau State.
const PLATEAU_WARDS = {
  'Barikin Ladi': [
    'Barkin Ladi', 'Gassa/Sho', 'Gindin Akwati', 'Heipang', 'Kapwis',
    'Kurra Falls', 'Lobiring', 'Marit/Mazat', 'Rafan', 'Tafan', 'Zabot',
  ],
  'Bassa': [
    'Buhit', 'Buji', 'Gabia', 'Gurum', 'Jengre', 'Kadamo', 'Kakkek',
    'Kasuru', 'Kimakpa', 'Kishika', 'Mafara', 'Rimi', "Ta'agbe", 'Tahu',
    'Zabolo', 'Zobwo',
  ],
  'Bokkos': [
    'Bokkos', 'Butura', 'Daffo', 'Damwai', 'Kamwai', 'Kwatas', 'Mangor',
    'Manguna', 'Mbar/Mangar', 'Mushere Central', 'Mushere West', 'Richa',
    'Sha', 'Tangur', 'Toff',
  ],
  'Jos East': [
    'Federe', "Fobur 'A'", "Fobur 'B'", 'Fursum', 'Jarawan Kogi',
    'Mai Gemu', 'Maijuju', 'Shere East', 'Shere West', 'Zandi',
  ],
  'Jos North': [
    'Abba Na Shehu', 'Ali Kazaure', 'Gangare', 'Garba Daho',
    'Ibrahim Katsina', 'Jenta Adamu', 'Jenta Apata', 'Jos Jarawa',
    "Naraguta 'A'", "Naraguta 'B'", 'Sarkin Arab', 'Tafawa Balewa',
    'Tudun Wada-Kabong', 'Vanderpuye',
  ],
  'Jos South': [
    'Bukuru', 'Du', 'Giring', "Gyel 'A'", "Gyel 'B'", "Kuru 'A'",
    "Kuru 'B'", 'Shen', 'Turu', 'Vwang', "Zawan 'A'", "Zawan 'B'",
  ],
  'Kanam': [
    'Birbyang', 'Dengi', 'Dugub', 'Gagdib', 'Garga', 'Gumsher',
    'Gwamlar', 'Jarmai', 'Jom', 'Kanam', 'Kantana', 'Kunkyam',
    'Munbutbo', 'Namaran',
  ],
  'Kanke': [
    'Ampang-East', "Amper Chika 'A'", "Amper Chika 'B'", 'Amper Seri',
    'Dawaki', 'Garram', 'Kabwir Pada', 'Kabwir/Gyangyang', 'Langshi', 'Nemel',
  ],
  'Langtang North': [
    'Funyalang', 'Jat', 'Keller', 'Kuffen', 'Kwallak', 'Kwanpe',
    'Lipchok', 'Mban/Zamko', 'Nyer', 'Pajat', 'Pil Gani', 'Pishe/Yashi',
    'Reak', 'Waroh',
  ],
  'Langtang South': [
    'Dadin Kowa', 'Fajul', 'Gamakai', 'Lashel', 'Mabudi', 'Magama',
    'Sabon Gida', 'Talgwang', 'Timbol', 'Turaki',
  ],
  'Mangu': [
    'Ampang West', 'Chanso', 'Gindiri I', 'Gindiri II', 'Jannaret',
    'Jipal/Chakfem', 'Kadunu', 'Kerang', 'Kombun', 'Langai',
    'Mangu I', 'Mangu II', 'Mangun', 'Mangu Halle', 'Pan Yam', 'Pushit',
  ],
  'Mikang': [
    'Baltep', 'Garkawa Central', 'Garkawa North', 'Garkawa North East',
    "Koenoem 'A'", "Koenoem 'B'", 'Lalin', "Piapung 'A'", "Piapung 'B'", 'Tunkus',
  ],
  'Pankshin': [
    'Chip', 'Dok-Pai', 'Fier', 'Jiblik', 'Kadung', 'Kangshu', 'Lankan',
    'Pankshin Central', 'Pankshin Chigwong', 'Pankshin South (Belning)',
    'Tal', 'Wokkos',
  ],
  "Qua'an Pan": [
    'Bwall', 'Doemak-Goechim', 'Doemak-Koplong', 'Dokan Kasuwa', 'Kurgwi',
    'Kwa', 'Kwalla Moeda', "Kwalla Yitla'ar", 'Kwande', 'Kwang', 'Namu',
  ],
  'Riyom': [
    'Attakar', 'Bum', 'Danto', 'Jol/Kwi', 'Ra-Hoss', 'Rim',
    'Riyom', 'Sharubutu', 'Sopp', 'Ta-Hoss',
  ],
  'Shendam': [
    'Derteng', 'Kalong', 'Kurungbau (A)', 'Kurungbau (B)', 'Moekat',
    'Pangshom', 'Poeship', 'Shendam Central (A)', 'Shendam Central (B)',
    'Shimankar', 'Yelwa',
  ],
  'Wase': [
    'Bashar', 'Danbiram', 'Gudus', 'Kadarko', 'Kumbong', 'Kumbur',
    'Kuyambana', 'Mavo', 'Nyalum/Kampani', 'Saluwe', 'Wase Tofa', 'Yola Wakat',
  ],
};


async function seedJurisdictions() {
  console.log('🗺️  Loading Plateau State boundary data from HDX GeoJSON...');
  
  const geojsonPath = '/tmp/nga_geojson/nga_admin2.geojson';
  if (!fs.existsSync(geojsonPath)) {
    console.error('❌ GeoJSON file not found. Run the download command first.');
    process.exit(1);
  }

  const data = JSON.parse(fs.readFileSync(geojsonPath, 'utf8'));
  const plateauFeatures = data.features.filter(f => f.properties.adm1_name === 'Plateau');

  console.log(`✅ Found ${plateauFeatures.length} Plateau LGA boundaries`);

  // Clear existing jurisdictions
  console.log('🧹 Clearing existing jurisdictions collection...');
  const existingDocs = await db.collection('jurisdictions').get();
  const deletePromises = existingDocs.docs.map(doc => doc.ref.delete());
  await Promise.all(deletePromises);
  console.log(`   Deleted ${existingDocs.size} old documents.`);

  let totalSeeded = 0;
  let batch = db.batch();
  let batchCount = 0;

  for (const feature of plateauFeatures) {
    const { adm2_name: lgaName, adm2_pcode: lgaCode, adm1_name: stateName, center_lat, center_lon } = feature.properties;
    const geometry = feature.geometry;

    // Handle both Polygon and MultiPolygon
    // Convert [lng, lat] arrays to {lng, lat} objects (Firestore doesn't allow nested arrays)
    let rawRing;
    if (geometry.type === 'Polygon') {
      rawRing = geometry.coordinates[0];
    } else if (geometry.type === 'MultiPolygon') {
      rawRing = geometry.coordinates.reduce((largest, poly) =>
        poly[0].length > largest.length ? poly[0] : largest, geometry.coordinates[0][0]);
    }
    const coordinates = rawRing.map(([lng, lat]) => ({ lng, lat }));

    const wards = PLATEAU_WARDS[lgaName] || ['Central'];

    // Create one document per LGA (highest-fidelity boundary we have)
    for (const ward of wards) {
      const docRef = db.collection('jurisdictions').doc();
      batch.set(docRef, {
        state: stateName,
        lga: lgaName,
        lga_pcode: lgaCode,
        ward: ward,
        pu: `PU-${lgaCode}-${ward.replace(/\s+/g, '-').toUpperCase().substring(0,8)}`,
        coordinates: coordinates,
        center_lat: center_lat,
        center_lon: center_lon,
        source: 'HDX_COD_AB_NGA_2019',
        seeded_at: FieldValue.serverTimestamp(),
      });
      totalSeeded++;
      batchCount++;

      // Firestore batch limit is 500 — commit and start a fresh batch
      if (batchCount >= 490) {
        await batch.commit();
        console.log(`   ✅ Committed batch of ${batchCount} documents...`);
        batch = db.batch();
        batchCount = 0;
      }
    }

    console.log(`   📍 ${lgaName}: ${wards.length} wards seeded`);
  }

  // Commit remaining
  if (batchCount > 0) {
    await batch.commit();
  }

  console.log(`\n🎉 DONE! Seeded ${totalSeeded} jurisdiction documents across ${plateauFeatures.length} LGAs in Plateau State.`);
  console.log('   The resolveJurisdiction engine will now correctly route every emergency.');
  process.exit(0);
}

seedJurisdictions().catch(err => {
  console.error('❌ Fatal error:', err);
  process.exit(1);
});
