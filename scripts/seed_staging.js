#!/usr/bin/env node
/**
 * Populate a STAGING project with one user per role, and incidents to look at.
 *
 * A bootstrapped project has the right schema and nothing in it, which is
 * enough to prove anon is locked out and not enough to see whether the console
 * works. Every role in this system sees a different slice — a citizen sees
 * their own alerts, a responder sees dispatches, a liaison sees one agency, a
 * commander sees everything — so testing any of that needs an account of each
 * kind, and creating them by hand is where staging setups quietly go stale.
 *
 * Auth users cannot be created in SQL: Supabase hashes passwords in the Auth
 * service, so a row poked into `auth.users` cannot log in. This uses the admin
 * API, which is why it is JavaScript and not another .sql file.
 *
 *   SUPABASE_URL=https://<ref>.supabase.co \
 *   SUPABASE_SERVICE_ROLE_KEY=<staging service key> \
 *   RAINBOW_ENV=staging \
 *   node scripts/seed_staging.js
 *
 * REFUSES TO RUN WITHOUT `RAINBOW_ENV=staging`. It creates accounts with known
 * passwords and writes fabricated emergencies; on a real deployment that is a
 * back door and a false dispatch. The variable has no other purpose than to
 * make running this an explicit act rather than a command-history accident —
 * the same reasoning as `scripts/verify_rls.js`, which INSERTs probe rows and
 * carries its own warning.
 *
 * Idempotent: re-running updates the same accounts and re-seeds the same
 * incidents by fixed id rather than piling up duplicates.
 */
'use strict';

const path = require('path');

// ── Guards ──────────────────────────────────────────────────────────────────
if (process.env.RAINBOW_ENV !== 'staging') {
  console.error(
    'REFUSING TO RUN.\n\n' +
      'This creates accounts with known passwords and writes fabricated\n' +
      'emergencies. Set RAINBOW_ENV=staging to confirm the target is a\n' +
      'throwaway project, not a live one.'
  );
  process.exit(2);
}

const URL = process.env.SUPABASE_URL;
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!URL || !KEY) {
  console.error(
    'Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY (the STAGING ones).\n' +
      'Neither is read from a file, and neither is printed by this script.'
  );
  process.exit(2);
}

// supabase-js lives in the dashboard workspace; resolve from there rather than
// carrying a second install just for this.
let createClient;
try {
  ({ createClient } = require('@supabase/supabase-js'));
} catch {
  try {
    ({ createClient } = require(path.join(
      __dirname, '..', 'hq-dashboard-next', 'node_modules', '@supabase', 'supabase-js'
    )));
  } catch {
    console.error('Could not resolve @supabase/supabase-js. Run `npm install` in hq-dashboard-next/.');
    process.exit(2);
  }
}

const db = createClient(URL, KEY, { auth: { persistSession: false } });

// ── What gets created ───────────────────────────────────────────────────────
//
// One account per role the console and app actually branch on. The password is
// the same for all of them and is deliberately not a secret: this is a
// throwaway project, and a seeded password that has to be looked up somewhere
// is a seeded password nobody uses.
const PASSWORD = 'staging-only-not-a-secret';
const DOMAIN = 'staging.invalid'; // reserved TLD — cannot receive mail

const USERS = [
  { key: 'citizen',   role: 'CITIZEN',        name: 'Amina Bello',        lga: 'JOS NORTH', ward: 'NARAGUTA', pu: 'PU-01' },
  { key: 'responder', role: 'RESPONDER',      name: 'Sgt. Danjuma Yusuf', lga: 'JOS NORTH', ward: 'NARAGUTA', pu: 'PU-01', badge: 'RSP-014' },
  { key: 'lga',       role: 'LGA_COMMAND',    name: 'Insp. Grace Pam',    lga: 'JOS NORTH', ward: 'NARAGUTA', pu: 'PU-01', badge: 'LGA-002' },
  { key: 'hq',        role: 'HQ_COMMAND',     name: 'ACP Musa Ibrahim',   lga: 'JOS NORTH', ward: 'NARAGUTA', pu: 'PU-01', badge: 'HQ-001' },
  { key: 'police',    role: 'POLICE_LIAISON', name: 'DSP Audu Bala',      lga: 'JOS NORTH', ward: 'NARAGUTA', pu: 'PU-01', badge: 'NP/JOS/001', agency: 'POLICE' },
  { key: 'army',      role: 'ARMY_LIAISON',   name: 'Capt. Ruth Achi',    lga: 'MANGU',     ward: 'PANYAM',   pu: 'PU-11', badge: 'NA/PL/007',  agency: 'ARMY' },
];

// Fixed ids so re-running updates rather than duplicates.
const ALERTS = [
  { id: 'aaaa1111-0000-4000-8000-00000000a001', by: 'citizen', type: 'SOS',      status: 'PENDING',    severity: 'CRITICAL', desc: 'Armed men at the junction.',      lat: 9.8965, lng: 8.8583, lga: 'JOS NORTH', ward: 'NARAGUTA', pu: 'PU-01' },
  { id: 'aaaa1111-0000-4000-8000-00000000a002', by: 'citizen', type: 'INCIDENT', status: 'DISPATCHED', severity: 'HIGH',     desc: 'Fire spreading near the market.', lat: 9.8991, lng: 8.8620, lga: 'JOS NORTH', ward: 'NARAGUTA', pu: 'PU-01' },
  // No coordinates, on purpose: the board must show this as UNLOCATED rather
  // than pinning it somewhere plausible. That was finding C-5.
  { id: 'aaaa1111-0000-4000-8000-00000000a003', by: 'citizen', type: 'SOS',      status: 'PENDING',    severity: 'HIGH',     desc: 'Cannot say where I am.',          lat: null, lng: null, lga: 'JOS NORTH', ward: 'NARAGUTA', pu: 'PU-01' },
  // Ungraded: must render as UNKNOWN and stay out of the CRITICAL filter.
  { id: 'aaaa1111-0000-4000-8000-00000000a004', by: 'citizen', type: 'INCIDENT', status: 'PENDING',    severity: null,       desc: 'Something is happening.',         lat: 9.8930, lng: 8.8501, lga: 'JOS NORTH', ward: 'NARAGUTA', pu: 'PU-01' },
  // Another agency's ward, so cross-agency and cross-tier scoping is visible.
  { id: 'aaaa1111-0000-4000-8000-00000000a005', by: 'citizen', type: 'INCIDENT', status: 'ESCALATED',  severity: 'CRITICAL', desc: 'Roadblock on the Mangu road.',    lat: 9.5231, lng: 9.0012, lga: 'MANGU',     ward: 'PANYAM',   pu: 'PU-11' },
];

async function upsertUser(u) {
  const email = `${u.key}@${DOMAIN}`;
  // No listUsers scan: on a project with many users that is a paginated crawl.
  // Create, and fall back to updating the existing account by id if it is there.
  let { data, error } = await db.auth.admin.createUser({
    email,
    password: PASSWORD,
    email_confirm: true,
  });

  if (error && !/already|exists|registered/i.test(error.message)) throw error;

  let id = data?.user?.id;
  if (!id) {
    const { data: list, error: listErr } = await db.auth.admin.listUsers({ perPage: 200 });
    if (listErr) throw listErr;
    id = list.users.find(x => x.email === email)?.id;
    if (!id) throw new Error(`could not create or find ${email}`);
    await db.auth.admin.updateUserById(id, { password: PASSWORD, email_confirm: true });
  }

  // The signup trigger creates the profile row; this sets what it cannot know.
  // `role` is written with the service key on purpose — the escalation trigger
  // blocks a user changing their own, which is the point of it.
  const { error: pErr } = await db.from('profiles').upsert({
    id,
    email,
    full_name: u.name,
    role: u.role,
    badge_number: u.badge ?? null,
    agency: u.agency ?? null,
    geo_lga: u.lga,
    geo_ward: u.ward,
    geo_pu: u.pu,
    is_active: true,
  });
  if (pErr) throw pErr;

  return { ...u, id, email };
}

async function main() {
  console.log(`Seeding ${URL.replace(/^https:\/\/([^.]{0,6}).*/, 'https://$1…')}\n`);

  const people = {};
  for (const u of USERS) {
    const created = await upsertUser(u);
    people[u.key] = created;
    console.log(`  ${u.role.padEnd(15)} ${created.email}`);
  }

  const rows = ALERTS.map(a => ({
    id: a.id,
    type: a.type,
    status: a.status,
    severity: a.severity,
    description: a.desc,
    reported_by: people[a.by].id,
    latitude: a.lat,
    longitude: a.lng,
    geo_lga: a.lga,
    geo_ward: a.ward,
    geo_pu: a.pu,
    assigned_to: a.status === 'DISPATCHED' ? people.responder.id : null,
    assigned_tier: a.status === 'ESCALATED' ? 'LGA' : null,
    escalated_to_agency: a.status === 'ESCALATED' ? 'ARMY' : null,
  }));
  const { error: aErr } = await db.from('alerts').upsert(rows);
  if (aErr) throw aErr;
  console.log(`\n  ${rows.length} incidents`);

  const { error: sErr } = await db.from('system_alerts').upsert([{
    id: 'bbbb2222-0000-4000-8000-00000000b001',
    title: 'CRITICAL ADVISORY — JOS NORTH LGA',
    message: 'Avoid Terminus junction until further notice.',
    severity: 'CRITICAL',
    target_audience: 'ALL',
    target_lga: 'JOS NORTH',
    target_ward: 'ALL',
    target_pu: 'ALL',
    is_active: true,
    expires_at: new Date(Date.now() + 24 * 3600_000).toISOString(),
  }]);
  if (sErr) throw sErr;
  console.log('  1 broadcast, scoped to JOS NORTH');

  console.log(
    `\nDone. Every account uses the password: ${PASSWORD}\n` +
      'Sign in to the console as hq@' + DOMAIN + ' for the full board,\n' +
      'or police@' + DOMAIN + ' to see the agency portal scoped to one agency.\n\n' +
      'What to look for, since each was a real defect:\n' +
      '  * the unlocated SOS shows as UNLOCATED, not pinned to central Jos\n' +
      '  * the ungraded incident reads UNKNOWN and is absent from CRITICAL\n' +
      '  * the JOS NORTH broadcast does NOT reach the Mangu-based army liaison\n' +
      '  * the escalated incident appears in the ARMY portal and no other'
  );
}

main().catch(err => {
  console.error('\nSeeding failed:', err.message);
  process.exit(1);
});
