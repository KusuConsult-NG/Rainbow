/**
 * The dataset the local end-to-end run serves.
 *
 * Deliberately the SAME people and the SAME five incidents that
 * `scripts/seed_staging.js` writes into a real staging project, with the same
 * uuids. That is the point: a screenshot taken here and a screenshot taken
 * against staging are comparable, and a defect that shows up in one should show
 * up in the other. If you change a fixture here, change it there.
 *
 * Every column below is checked against `supabase/migrations/` at startup by
 * `schema.js` — a fixture naming a column that does not exist fails the run
 * rather than quietly serving a field the real database could never return.
 *
 * Four of the five incidents exist to make a previously-real defect visible:
 *
 *   a003  SOS with no coordinates   -> must read UNLOCATED, not a pin in Jos (C-5)
 *   a004  incident with no severity -> must read UNKNOWN and stay out of CRITICAL
 *   a005  escalated to ARMY, MANGU  -> must appear in the ARMY portal and no other
 *   sys   broadcast scoped JOS NORTH-> must not reach the MANGU-based liaison
 */

const DOMAIN = 'staging.operationrainbow.test';
// No HYPHEN in this, deliberately, and it cost six wrong theories to learn why.
//
// Puppeteer's US keyboard layout maps `-` to `NumpadSubtract` and then emits an
// INCONSISTENT location for it: keydown arrives with location 3 (numpad) and
// keyup with location 1 (left modifier). Flutter's web engine looks up
// `kWebLogicalLocationMap['-'][1]`, finds no entry for a left-modifier hyphen,
// and the unmappable-location path in KeyboardConverter._handleEvent throws
// `Cannot read properties of null (reading 'toString')`. A real keyboard never
// sends that pair, so no user can hit it.
//
// With `staging-only-password` the two hyphens produced exactly two engine
// errors per run, which failed mobile_capture.js and mobile_interact.js — both
// of which fail on console errors matching /cannot read/ — on the staff
// sign-in screens only. The citizen phone, the OTP `123456` and the badge
// `responder@staging.operationrainbow.test` contain no hyphen and never threw,
// which is why only the password step looked cursed.
//
// Resolved by building with --source-maps and mapping the frames: every one
// landed in lib/_engine/engine/keyboard_binding.dart, none in this repository.
// See scripts/local_e2e/resolve_dart_frames.js.
//
// The fixture password is arbitrary test data, so removing the character that
// trips a known automation bug costs nothing and keeps the harnesses' error
// detection fully armed — unlike widening their filters, which would have hidden
// every future engine error too.
const PASSWORD = 'stagingOnlyPassword77';

/**
 * One account per role the console and the app actually branch on.
 *
 * Each carries its own phone number. A citizen has no email and no password in
 * production — the number IS the identity, and it is what `profiles.phone`
 * holds under a UNIQUE constraint — so sharing one number across the fixtures
 * was both unseedable against a real database and untestable as a sign-in.
 */
const PEOPLE = [
  { key: 'citizen',   id: 'bbbb2222-0000-4000-8000-00000000b001', phone: '+2348030001111', role: 'CITIZEN',        full_name: 'Amina Bello',        geo_lga: 'JOS NORTH', geo_ward: 'NARAGUTA', geo_pu: 'PU-01', badge_number: null,         agency: null, tier: null },
  { key: 'responder', id: 'bbbb2222-0000-4000-8000-00000000b002', phone: '+2348030002222', role: 'RESPONDER',      full_name: 'Sgt. Danjuma Yusuf', geo_lga: 'JOS NORTH', geo_ward: 'NARAGUTA', geo_pu: 'PU-01', badge_number: 'RSP-014',    agency: null, tier: 'POLLING_UNIT' },
  // The command chain has four rungs and only three were ever seeded, so the
  // polling-unit and ward tiers had never been rendered or exercised.
  { key: 'unit',      id: 'bbbb2222-0000-4000-8000-00000000b007', phone: '+2348030003333', role: 'UNIT_COMMAND',    full_name: 'Sgt. Bitrus Gyang',   geo_lga: 'JOS NORTH', geo_ward: 'NARAGUTA', geo_pu: 'PU-01', badge_number: 'PU-014',     agency: null, tier: 'POLLING_UNIT' },
  { key: 'ward',      id: 'bbbb2222-0000-4000-8000-00000000b008', phone: '+2348030004444', role: 'WARD_COMMAND',    full_name: 'Insp. Ladi Dung',     geo_lga: 'JOS NORTH', geo_ward: 'NARAGUTA', geo_pu: 'PU-01', badge_number: 'WRD-007',    agency: null, tier: 'WARD' },
  { key: 'lga',       id: 'bbbb2222-0000-4000-8000-00000000b003', phone: '+2348030005555', role: 'LGA_COMMAND',    full_name: 'Insp. Grace Pam',    geo_lga: 'JOS NORTH', geo_ward: 'NARAGUTA', geo_pu: 'PU-01', badge_number: 'LGA-002',    agency: null, tier: 'LGA' },
  { key: 'hq',        id: 'bbbb2222-0000-4000-8000-00000000b004', phone: '+2348030006666', role: 'HQ_COMMAND',     full_name: 'ACP Musa Ibrahim',   geo_lga: 'JOS NORTH', geo_ward: 'NARAGUTA', geo_pu: 'PU-01', badge_number: 'HQ-001',     agency: null, tier: 'HQ' },
  { key: 'police',    id: 'bbbb2222-0000-4000-8000-00000000b005', phone: '+2348030007777', role: 'POLICE_LIAISON', full_name: 'DSP Audu Bala',      geo_lga: 'JOS NORTH', geo_ward: 'NARAGUTA', geo_pu: 'PU-01', badge_number: 'NP/JOS/001', agency: 'POLICE', tier: null },
  { key: 'army',      id: 'bbbb2222-0000-4000-8000-00000000b006', phone: '+2348030008888', role: 'ARMY_LIAISON',   full_name: 'Capt. Ruth Achi',    geo_lga: 'MANGU',     geo_ward: 'PANYAM',   geo_pu: 'PU-11', badge_number: 'NA/PL/007',  agency: 'ARMY',   tier: null },
];

const byKey = (k) => PEOPLE.find((p) => p.key === k);

const NOW = '2026-09-26T21:55:00.000Z';

const profiles = PEOPLE.map((p) => ({
  id: p.id,
  email: `${p.key}@${DOMAIN}`,
  full_name: p.full_name,
  role: p.role,
  badge_number: p.badge_number,
  agency: p.agency,
  tier: p.tier,
  geo_lga: p.geo_lga,
  geo_ward: p.geo_ward,
  geo_pu: p.geo_pu,
  // Each person's own number. They all shared +2348000000000, and
  // `profiles.phone` is UNIQUE — a real database refuses that seed, and a
  // citizen signing in by phone could not be told apart from anybody else.
  phone: p.phone,
  fcm_token: null,
  push_enabled: true,
  profile_complete: true,
  is_active: true,
  last_seen: NOW,
  created_at: '2026-09-01T08:00:00.000Z',
  updated_at: '2026-09-01T08:00:00.000Z',
}));

const ALERT_DEFAULTS = {
  local_id: null,
  sub_type: null,
  assigned_to: null,
  assigned_responders: null,
  assigned_tier: null,
  escalated_to_agency: null,
  ai_summary: null,
  ai_triage: null,
  citizen_feedback: null,
  feedback_at: null,
  media_urls: [],
  updated_at: NOW,
};

const alerts = [
  {
    ...ALERT_DEFAULTS,
    id: 'aaaa1111-0000-4000-8000-00000000a001',
    type: 'SOS', status: 'PENDING', severity: 'CRITICAL',
    description: 'Armed men at the junction.',
    latitude: 9.8965, longitude: 8.8583,
    geo_lga: 'JOS NORTH', geo_ward: 'NARAGUTA', geo_pu: 'PU-01',
    reported_by: byKey('citizen').id,
    created_at: '2026-09-26T21:41:00.000Z',
  },
  {
    ...ALERT_DEFAULTS,
    id: 'aaaa1111-0000-4000-8000-00000000a002',
    type: 'INCIDENT', status: 'DISPATCHED', severity: 'HIGH',
    description: 'Fire spreading near the market.',
    latitude: 9.8991, longitude: 8.862,
    geo_lga: 'JOS NORTH', geo_ward: 'NARAGUTA', geo_pu: 'PU-01',
    reported_by: byKey('citizen').id,
    assigned_to: byKey('responder').id,
    created_at: '2026-09-26T20:12:00.000Z',
  },
  {
    // C-5. Null coordinates. The board must say so rather than draw a pin.
    ...ALERT_DEFAULTS,
    id: 'aaaa1111-0000-4000-8000-00000000a003',
    type: 'SOS', status: 'PENDING', severity: 'HIGH',
    description: 'Cannot say where I am.',
    latitude: null, longitude: null,
    geo_lga: 'JOS NORTH', geo_ward: 'NARAGUTA', geo_pu: 'PU-01',
    reported_by: byKey('citizen').id,
    created_at: '2026-09-26T19:05:00.000Z',
  },
  {
    // Ungraded. Must read UNKNOWN and must NOT enter the CRITICAL filter.
    ...ALERT_DEFAULTS,
    id: 'aaaa1111-0000-4000-8000-00000000a004',
    type: 'INCIDENT', status: 'PENDING', severity: null,
    description: 'Something is happening.',
    latitude: 9.893, longitude: 8.8501,
    geo_lga: 'JOS NORTH', geo_ward: 'NARAGUTA', geo_pu: 'PU-01',
    reported_by: byKey('citizen').id,
    created_at: '2026-09-26T18:30:00.000Z',
  },
  {
    // Another agency's LGA, so cross-agency and cross-tier scoping is visible.
    ...ALERT_DEFAULTS,
    id: 'aaaa1111-0000-4000-8000-00000000a005',
    type: 'INCIDENT', status: 'ESCALATED', severity: 'CRITICAL',
    description: 'Roadblock on the Mangu road.',
    latitude: 9.5231, longitude: 9.0012,
    geo_lga: 'MANGU', geo_ward: 'PANYAM', geo_pu: 'PU-11',
    reported_by: byKey('citizen').id,
    assigned_tier: 'LGA',
    escalated_to_agency: 'ARMY',
    created_at: '2026-09-26T17:14:00.000Z',
  },
];

const system_alerts = [
  {
    id: 'cccc3333-0000-4000-8000-00000000c001',
    title: 'CRITICAL ADVISORY — JOS NORTH LGA',
    message: 'Avoid the Naraguta junction until further notice.',
    severity: 'CRITICAL',
    target_audience: 'ALL',
    target_type: 'LGA',
    target_value: 'JOS NORTH',
    is_active: true,
    created_by: byKey('hq').id,
    created_at: '2026-09-26T21:50:00.000Z',
  },
];

const chat_messages = [
  {
    id: 'dddd4444-0000-4000-8000-00000000d001',
    alert_id: alerts[1].id,
    sender_id: byKey('responder').id,
    sender_name: 'Sgt. Danjuma Yusuf',
    sender_role: 'RESPONDER',
    message: 'On route, two minutes out.',
    media_url: null,
    created_at: '2026-09-26T20:15:00.000Z',
  },
  {
    id: 'dddd4444-0000-4000-8000-00000000d002',
    alert_id: alerts[1].id,
    sender_id: byKey('hq').id,
    sender_name: 'ACP Musa Ibrahim',
    sender_role: 'HQ_COMMAND',
    message: 'Acknowledged. Fire service notified.',
    media_url: null,
    created_at: '2026-09-26T20:16:00.000Z',
  },
];

const telemetry = [
  {
    id: 'eeee5555-0000-4000-8000-00000000e001',
    user_id: byKey('responder').id,
    alert_id: alerts[1].id,
    latitude: 9.8975, longitude: 8.8601,
    accuracy: 12.5,
    speed: 0,
    battery: 62,
    network: 'WIFI',
    mode: 'MISSION',
    status: 'ON_ROUTE',
    updated_at: '2026-09-26T21:45:00.000Z',
  },
];

const app_config = [
  { id: '55557777-0000-4000-8000-000000005001', key: 'sos_auto_dispatch', value: 'false', description: 'Dispatch the nearest responder without a human decision.', updated_at: '2026-09-01T08:00:00.000Z' },
  { id: '55557777-0000-4000-8000-000000005002', key: 'broadcast_enabled', value: 'true',  description: 'Allow mass broadcast from the console.',                  updated_at: '2026-09-01T08:00:00.000Z' },
];

const uninstall_requests = [
  {
    id: 'ffff6666-0000-4000-8000-00000000f001',
    user_id: byKey('citizen').id,
    reason: 'Changing phones.',
    status: 'PENDING',
    remarks: null,
    reviewed_by: null,
    reviewed_at: null,
    submitted_at: '2026-09-25T10:00:00.000Z',
  },
];

const agency_personnel = [
  { id: '11116666-0000-4000-8000-000000001001', agency: 'ARMY',   name: 'Cpl. Ibrahim Sule',  rank: 'CPL', status: 'AVAILABLE', phone: '+2348000000001', badge_number: 'NA/PL/101', created_by: byKey('army').id,   created_at: '2026-09-01T08:00:00.000Z', updated_at: '2026-09-01T08:00:00.000Z' },
  { id: '11116666-0000-4000-8000-000000001002', agency: 'ARMY',   name: 'Pte. Yakubu Danjuma', rank: 'PTE', status: 'DEPLOYED',  phone: '+2348000000002', badge_number: 'NA/PL/102', created_by: byKey('army').id,   created_at: '2026-09-01T08:00:00.000Z', updated_at: '2026-09-01T08:00:00.000Z' },
  { id: '11116666-0000-4000-8000-000000001003', agency: 'POLICE', name: 'Sgt. Comfort Ada',   rank: 'SGT', status: 'AVAILABLE', phone: '+2348000000003', badge_number: 'NP/JOS/201', created_by: byKey('police').id, created_at: '2026-09-01T08:00:00.000Z', updated_at: '2026-09-01T08:00:00.000Z' },
];

const agency_deployments = [
  {
    id: '22226666-0000-4000-8000-000000002001',
    agency: 'ARMY',
    alert_id: alerts[4].id,
    personnel_ids: [agency_personnel[1].id],
    personnel_count: 1,
    status: 'ACTIVE',
    deployment_note: 'Two vehicles dispatched to the Mangu road.',
    deployed_by: byKey('army').id,
    deployed_at: '2026-09-26T17:40:00.000Z',
    created_at: '2026-09-26T17:40:00.000Z',
  },
];

const agency_action_reports = [
  {
    id: '33336666-0000-4000-8000-000000003001',
    agency: 'ARMY',
    alert_id: alerts[4].id,
    report_type: 'FINAL',
    narrative: 'Roadblock cleared, no casualties.',
    outcome: 'RESOLVED',
    casualties: 0,
    personnel_count: 2,
    submitted_by: byKey('army').id,
    submitted_by_name: 'Capt. Ruth Achi',
    submitted_at: '2026-09-26T18:05:00.000Z',
    read_by_hq: false,
    hq_acknowledged_by: null,
    hq_acknowledged_at: null,
    created_at: '2026-09-26T18:05:00.000Z',
  },
];

const agency_notifications = [
  {
    id: '44446666-0000-4000-8000-000000004001',
    agency: 'ARMY',
    alert_id: alerts[4].id,
    method: 'PUSH',
    status: 'SENT',
    sent_at: '2026-09-26T17:16:00.000Z',
    created_at: '2026-09-26T17:16:00.000Z',
  },
];

module.exports = {
  DOMAIN,
  PASSWORD,
  PEOPLE,
  byKey,
  tables: {
    profiles,
    alerts,
    system_alerts,
    chat_messages,
    telemetry,
    app_config,
    uninstall_requests,
    agency_personnel,
    agency_deployments,
    agency_action_reports,
    agency_notifications,
  },
};
