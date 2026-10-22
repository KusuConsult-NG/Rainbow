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
const PASSWORD = 'staging-only-password';

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
    // A HISTORY, BECAUSE AN ESCALATED INCIDENT HAS ONE.
    //
    // Every fixture alert carried an empty escalation_log, so `audit_trail()` —
    // which exists to flatten exactly this — had nothing to return and the Audit
    // Logs screen was photographed empty in every run. It was ALSO being refused
    // with a 400 by a stand-in that implemented no RPC at all, and an empty
    // screen looks the same either way; that is what let the refusal sit there.
    // This row is now coherent with its own status, and the screen has rows to
    // render, so the two states are distinguishable.
    //
    // Shaped exactly as alert-actions.ts escalateAlert writes an entry: the
    // tier move in `from_tier`/`to_tier`, the place in its own key, and `at` as
    // an ISO timestamp.
    escalation_log: [
      {
        from_tier: 'UNIT', to_tier: 'WARD',
        reason: 'No acknowledgement within the unit window',
        by_email: 'SYSTEM', at: '2026-09-26T17:22:00.000Z',
      },
      {
        from_tier: 'WARD', to_tier: 'LGA',
        reason: 'Roadblock spans two wards',
        by_email: 'ward@staging.operationrainbow.test',
        at: '2026-09-26T17:41:00.000Z',
      },
      {
        from_tier: 'HQ', to_tier: 'LGA', to_lga: 'MANGU', to_agency: 'ARMY',
        reason: 'Armed and beyond local capacity',
        by_email: 'hq@staging.operationrainbow.test',
        at: '2026-09-26T18:05:00.000Z',
      },
    ],
    created_at: '2026-09-26T17:14:00.000Z',
  },
  {
    // HANDED TO AN AGENCY, OUTSIDE THAT LIAISON'S OWN POSTING.
    //
    // a005 above is escalated to the ARMY and happens to sit in MANGU/PANYAM/
    // PU-11, which is exactly where the Army liaison is posted — so the
    // handset's old place-based filter admitted it by coincidence and the
    // missing liaison rule was invisible. This one is handed to the POLICE and
    // is in BOKKOS, while the Police liaison is posted to JOS NORTH, so only a
    // filter that reads `escalated_to_agency` can deliver it.
    //
    // It is the normal case, not a corner: a liaison is based somewhere
    // specific and incidents happen across the state.
    ...ALERT_DEFAULTS,
    id: 'aaaa1111-0000-4000-8000-00000000a006',
    type: 'INCIDENT', status: 'ESCALATED', severity: 'HIGH',
    description: 'Convoy stopped at Mushere.',
    latitude: 9.3012, longitude: 9.2411,
    geo_lga: 'BOKKOS', geo_ward: 'MUSHERE', geo_pu: 'PU-03',
    reported_by: byKey('citizen').id,
    assigned_tier: 'LGA',
    escalated_to_agency: 'POLICE',
    escalation_log: [
      {
        from_tier: 'LGA', to_tier: 'LGA', to_lga: 'BOKKOS', to_agency: 'POLICE',
        reason: 'Handed to the Police for traffic control',
        by_email: 'hq@staging.operationrainbow.test',
        at: '2026-09-26T16:50:00.000Z',
      },
    ],
    created_at: '2026-09-26T16:44:00.000Z',
  },
];

// TWO ADVISORIES, AND BOTH ARE SHAPES THE SYSTEM CAN ACTUALLY PRODUCE.
//
// There was one, and it was fiction: `target_type: 'LGA'` with
// `target_value: 'JOS NORTH'`. That encoding — the place in the legacy pair —
// has NEVER been written by anything. The only two appearances of
// `target_value` in this repository's whole history are a READER (in
// system_alert_listener.dart, removed with T-29) and a column inventory in
// MassBroadcast.test.tsx. The old mobile broadcast screen wrote an AUDIENCE
// into `target_type`; nothing has ever put a place there.
//
// So the fixture described a row no writer could create, which is worse than no
// fixture: it sent me looking for geography that had been silently dropped, when
// in fact none was ever stored. The two rows below are the two shapes that do
// exist, and each is asserted in the browser run.
const system_alerts = [
  {
    // SHAPE ONE: canonically scoped, as both composers write today. Scoped to a
    // WARD, which is the assertion T-29 needed and never had outside the widget
    // tests: every fixture person is in NARAGUTA except the ARMY liaison, who is
    // in PANYAM, so this advisory must reach seven roles and not the eighth.
    id: 'cccc3333-0000-4000-8000-00000000c001',
    title: 'CRITICAL ADVISORY — NARAGUTA WARD',
    message: 'Avoid the Naraguta junction until further notice.',
    severity: 'CRITICAL',
    target_audience: 'ALL',
    target_lga: 'JOS NORTH',
    target_ward: 'NARAGUTA',
    is_active: true,
    created_by: byKey('hq').id,
    // NEWEST, deliberately. The console's banner orders by `created_at` and
    // docks ONE advisory — the newest the viewer is addressed by — so whichever
    // row is newer is the one an assertion about that surface can see. With the
    // legacy row newer, every console role was shown IT and the ward row was
    // invisible to the test, which made "the Army was not shown the ward
    // advisory" pass for the wrong reason: absence was indistinguishable from a
    // banner that renders nothing at all.
    created_at: '2026-09-26T21:55:00.000Z',
  },
  {
    // SHAPE TWO: a genuine legacy row, exactly as the old mobile broadcast
    // screen wrote one — the audience in `target_type`, no canonical column at
    // all, no place. `broadcastAudience()` falls back to it, which is the one
    // legacy path that is real, and it had no end-to-end coverage either.
    // Addressed to responders, so a citizen must NOT see it.
    id: 'cccc3333-0000-4000-8000-00000000c002',
    title: 'HIGH ADVISORY — ALL CALL SIGNS',
    message: 'Radio discipline on the command net until the sweep ends.',
    severity: 'HIGH',
    target_type: 'AGENTS',
    is_active: true,
    created_by: byKey('hq').id,
    // Older than the ward row above, so it is what the Army liaison falls
    // through to — which is what proves their banner is alive and the ward
    // advisory's absence is a scoping decision rather than a broken surface.
    created_at: '2026-09-26T21:50:00.000Z',
  },
];

const sms_device_keys = [];

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

/**
 * The shelters a frightened citizen is routed to.
 *
 * This table had never held a row anywhere. Nothing in this repository writes
 * one — no migration INSERT, no `seed_staging.js`, no console screen, no admin
 * tool — and it was not declared here either. The only shelters this product
 * ever drew on a map were the three `safe_zone_screen.dart` invented inside a
 * `catch (_)`, which T-74 removed. These are the first real ones it has had.
 *
 *   sz1  the ordinary case: active, in the citizen's own LGA, with a capacity
 *   sz2  capacity NULL  -> must read as unstated. Not 0, and not a guess.
 *                          `capacity` was added by 20261026000000 with no
 *                          backfill on purpose, so every shelter recorded
 *                          before that migration looks exactly like this one.
 *   sz3  a second LGA   -> so "nearest" has to mean something
 *   sz4  is_active false-> must NOT appear. The screen filters on it and
 *                          nothing had ever proved the filter.
 */
const safe_zones = [
  {
    id: '55557777-0000-4000-8000-000000005001',
    name: 'NARAGUTA WARD COMMAND POST',
    description: 'Ward command post, open to the public during an incident.',
    latitude: 9.9120,
    longitude: 8.8920,
    type: 'COMMAND_POST',
    geo_lga: 'JOS NORTH',
    geo_ward: 'NARAGUTA',
    capacity: 400,
    is_active: true,
    created_at: '2026-09-01T08:00:00.000Z',
  },
  {
    id: '55557777-0000-4000-8000-000000005002',
    name: "ST. PIRAN'S PARISH HALL",
    description: 'Parish hall. Capacity was never recorded.',
    latitude: 9.9405,
    longitude: 8.8731,
    type: 'SHELTER',
    geo_lga: 'JOS NORTH',
    geo_ward: 'NARAGUTA',
    capacity: null,
    is_active: true,
    created_at: '2026-09-01T08:00:00.000Z',
  },
  {
    id: '55557777-0000-4000-8000-000000005003',
    name: 'PANYAM DISTRICT CLINIC',
    description: 'Clinic with a standing agreement to take casualties.',
    latitude: 9.5190,
    longitude: 9.0310,
    type: 'MEDICAL',
    geo_lga: 'MANGU',
    geo_ward: 'PANYAM',
    capacity: 60,
    is_active: true,
    created_at: '2026-09-01T08:00:00.000Z',
  },
  {
    id: '55557777-0000-4000-8000-000000005004',
    name: 'GADA BIU PRIMARY SCHOOL',
    description: 'Decommissioned after the roof was lost. Must not be offered.',
    latitude: 9.8870,
    longitude: 8.8640,
    type: 'SHELTER',
    geo_lga: 'JOS NORTH',
    geo_ward: 'NARAGUTA',
    capacity: 250,
    is_active: false,
    created_at: '2026-09-01T08:00:00.000Z',
  },
];

/**
 * The live route a dispatcher follows while an incident is open.
 *
 * `background_tracking_service.dart` writes one of these per position fix and
 * `hq-dashboard-next` reads them back ordered by `recorded_at` to draw the
 * trail. Neither half had ever been exercised against data: the table was in
 * neither these fixtures nor the stand-in, so every insert was answered
 * **201 Created** and dropped, and every read came back empty. That is the
 * whole point of T-7x — the responder following the device — and the harness
 * could not tell it from a feature nobody had written. See T-75.
 *
 * Four points against a002, the DISPATCHED incident, moving roughly north-east
 * away from where it was first reported. A single point proves a pin; four
 * prove a route, and prove the ordering.
 */
const incident_tracks = [
  { id: '66668888-0000-4000-8000-000000006001', alert_id: alerts[1].id, user_id: byKey('citizen').id, latitude: 9.8991, longitude: 8.8620, accuracy: 12.0, speed: 0.0, recorded_at: '2026-09-26T21:40:00.000Z', created_at: '2026-09-26T21:40:00.000Z' },
  { id: '66668888-0000-4000-8000-000000006002', alert_id: alerts[1].id, user_id: byKey('citizen').id, latitude: 9.9008, longitude: 8.8644, accuracy: 11.0, speed: 1.4, recorded_at: '2026-09-26T21:42:00.000Z', created_at: '2026-09-26T21:42:00.000Z' },
  { id: '66668888-0000-4000-8000-000000006003', alert_id: alerts[1].id, user_id: byKey('citizen').id, latitude: 9.9031, longitude: 8.8669, accuracy: 18.0, speed: 1.1, recorded_at: '2026-09-26T21:44:00.000Z', created_at: '2026-09-26T21:44:00.000Z' },
  { id: '66668888-0000-4000-8000-000000006004', alert_id: alerts[1].id, user_id: byKey('citizen').id, latitude: 9.9057, longitude: 8.8702, accuracy: 9.0, speed: 1.6, recorded_at: '2026-09-26T21:46:00.000Z', created_at: '2026-09-26T21:46:00.000Z' },
];

/**
 * A SIM change noticed on a handset, unacknowledged.
 *
 * HQ reads this to tell a stolen phone from a new one. One open event, so the
 * panel that lists them has something to list and the acknowledge control has
 * something to act on — it had neither, because the table was undeclared and
 * therefore always empty.
 */
const sim_channel_events = [
  {
    id: '77779999-0000-4000-8000-000000007001',
    user_id: byKey('citizen').id,
    change: 'SIM_REPLACED',
    operator_code: '62130',
    operator_name: 'MTN NIGERIA',
    noticed_at: '2026-09-26T20:05:00.000Z',
    acknowledged_at: null,
    acknowledged_by: null,
    created_at: '2026-09-26T20:05:00.000Z',
  },
];

/**
 * Written by the console's AI route, read by nothing yet. Declared, not seeded:
 * the point is that the INSERT lands, which it did not before — the stand-in
 * answered 201 and threw the row away.
 */
const incident_ai_reports = [];

/**
 * One row per in-progress USSD session, written and read by the console's USSD
 * endpoint. Declared and empty for the same reason: a session starts when a
 * caller dials, so a seeded one would be a session nobody is in.
 */
const ussd_sessions = [];

module.exports = {
  DOMAIN,
  PASSWORD,
  PEOPLE,
  byKey,
  tables: {
    profiles,
    alerts,
    system_alerts,
    // Empty on purpose, and DECLARED on purpose. `register_sms_device()` writes
    // here on every sign-in, and a table the fake creates at runtime has no
    // entry in PRISTINE — so the next /reset-data pushed `fresh[name]` for a
    // name that snapshot has never heard of, threw inside the control server's
    // request handler, and killed the stand-in mid-run. Forty-five minutes of
    // run, lost after the fifth harness. The reset loop is hardened too; this
    // is the half that makes the table real.
    sms_device_keys,
    chat_messages,
    telemetry,
    app_config,
    uninstall_requests,
    agency_personnel,
    agency_deployments,
    agency_action_reports,
    agency_notifications,
    // Five tables the shipped product reads that this dataset had never
    // declared. An undeclared table was served EMPTY on read and answered
    // **201 Created** on write with the row dropped, so a screen built on one
    // photographed blank and a harness could not tell that from a feature
    // nobody had written. See E2E_AUDIT_REPORT.md T-75, and
    // `scripts/check_the_harness_serves_every_table.py`, which fails if the
    // app or the console reads a table that is not in this map.
    safe_zones,
    incident_tracks,
    sim_channel_events,
    incident_ai_reports,
    ussd_sessions,
  },
};
