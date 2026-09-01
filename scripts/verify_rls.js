#!/usr/bin/env node
/**
 * RLS verification — proves finding C-3 is actually closed.
 *
 * Connects with the PUBLIC anon key (the one shipped in the mobile app and the
 * web bundle) and asserts that every sensitive table refuses access. This is the
 * check that would have caught the original wide-open policies.
 *
 * Usage:
 *   NEXT_PUBLIC_SUPABASE_URL=... NEXT_PUBLIC_SUPABASE_ANON_KEY=... \
 *     node scripts/verify_rls.js
 *
 * Exit code 0 = locked down, 1 = at least one table is exposed.
 *
 * SAFETY: read-only probes plus write probes that are EXPECTED to be rejected.
 * Run against staging first. Write probes use an obviously-fake UUID and, if the
 * database is misconfigured such that they succeed, the script reports a CRITICAL
 * failure — inspect and clean up that row manually.
 */

const path = require('path');

const URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const ANON = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

if (!URL || !ANON) {
  console.error(
    'Missing NEXT_PUBLIC_SUPABASE_URL / NEXT_PUBLIC_SUPABASE_ANON_KEY.\n' +
    'Usage: NEXT_PUBLIC_SUPABASE_URL=... NEXT_PUBLIC_SUPABASE_ANON_KEY=... \\\n' +
    '         node scripts/verify_rls.js'
  );
  process.exit(2);
}

// supabase-js lives in the dashboard workspace; resolve from there so this runs
// from the repo root (as CI does) without a duplicate install.
let createClient;
try {
  ({ createClient } = require('@supabase/supabase-js'));
} catch {
  const vendored = path.join(__dirname, '..', 'hq-dashboard-next', 'node_modules', '@supabase', 'supabase-js');
  try {
    ({ createClient } = require(vendored));
  } catch {
    console.error(
      'Could not resolve @supabase/supabase-js.\n' +
      'Run `npm install` in hq-dashboard-next/ first.'
    );
    process.exit(2);
  }
}

const supabase = createClient(URL, ANON, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const PROBE_UUID = '00000000-0000-4000-8000-0000deadbeef';
const results = [];

function record(name, status, detail) {
  results.push({ name, status, detail });
  const tag = {
    pass: '\x1b[32mPASS\x1b[0m',
    fail: '\x1b[31mFAIL\x1b[0m',
    inconclusive: '\x1b[33m????\x1b[0m',
  }[status];
  console.log(`  ${tag}  ${name}${detail ? ` — ${detail}` : ''}`);
}

/**
 * A transport failure is NOT a policy denial.
 *
 * Without this distinction the whole script fails open: a wrong URL, DNS failure
 * or dropped network would report every table as locked down. PostgREST denials
 * carry a code (`42501`, `PGRST...`); fetch failures do not.
 */
function isTransportError(error) {
  if (!error) return false;
  if (error.code && !/^(TypeError|ENOTFOUND|ECONNREFUSED|ETIMEDOUT|EAI_AGAIN)$/.test(error.code)) {
    return false; // has a real PostgREST/Postgres error code → genuine denial
  }
  const m = `${error.message || ''}`.toLowerCase();
  return (
    !error.code ||
    m.includes('fetch failed') ||
    m.includes('network') ||
    m.includes('enotfound') ||
    m.includes('econnrefused') ||
    m.includes('timeout') ||
    m.includes('getaddrinfo')
  );
}

/** Anonymous SELECT must return zero rows or a genuine denial. */
async function expectNoRead(table) {
  const { data, error } = await supabase.from(table).select('*').limit(1);
  if (error) {
    return isTransportError(error)
      ? record(`anon cannot read ${table}`, 'inconclusive', `unreachable: ${error.message}`)
      : record(`anon cannot read ${table}`, 'pass', error.code);
  }
  const n = (data || []).length;
  record(`anon cannot read ${table}`, n === 0 ? 'pass' : 'fail',
    n === 0 ? 'empty' : `LEAKED ${n} row(s)`);
}

/** Anonymous INSERT must be rejected. */
async function expectNoWrite(table, row) {
  const { error } = await supabase.from(table).insert(row);
  if (error) {
    return isTransportError(error)
      ? record(`anon cannot write ${table}`, 'inconclusive', `unreachable: ${error.message}`)
      : record(`anon cannot write ${table}`, 'pass', error.code);
  }
  record(`anon cannot write ${table}`, 'fail',
    'CRITICAL: insert SUCCEEDED — remove the probe row manually');
}

/** Confirm the target is actually reachable before trusting any denial. */
async function preflight() {
  try {
    const res = await fetch(`${URL}/rest/v1/`, { headers: { apikey: ANON } });
    console.log(`  reachable — REST root returned HTTP ${res.status}\n`);
    return true;
  } catch (e) {
    console.error(`\n  \x1b[31mUNREACHABLE\x1b[0m: ${e.message}`);
    console.error('  Refusing to report "locked down" for a host we cannot reach.\n');
    return false;
  }
}

async function main() {
  console.log('='.repeat(64));
  console.log('  RLS VERIFICATION — anonymous (public anon key) access probes');
  console.log(`  target: ${URL}`);
  console.log('='.repeat(64) + '\n');

  if (!(await preflight())) process.exit(2);

  console.log('[READ] sensitive tables must return nothing to anon:');
  for (const t of [
    'profiles',        // citizen + officer PII
    'telemetry',       // live GPS of SOS victims and officers
    'alerts',
    'chat_messages',
    'system_alerts',
    'safe_zones',
    'uninstall_requests',
    'app_config',
  ]) {
    await expectNoRead(t);
  }

  console.log('\n[WRITE] anon must not be able to inject data:');
  await expectNoWrite('alerts', {
    type: 'INCIDENT', status: 'PENDING', description: 'rls-probe',
  });
  await expectNoWrite('telemetry', {
    user_id: PROBE_UUID, latitude: 0, longitude: 0, mode: 'sos',
  });
  await expectNoWrite('system_alerts', {
    title: 'rls-probe', message: 'rls-probe',
  });

  const failed = results.filter((r) => r.status === 'fail');
  const unknown = results.filter((r) => r.status === 'inconclusive');

  console.log('\n' + '='.repeat(64));
  if (failed.length) {
    console.log(`  ❌ ${failed.length}/${results.length} PROBES FAILED — DATABASE IS EXPOSED`);
    failed.forEach((f) => console.log(`     - ${f.name}: ${f.detail}`));
    console.log('='.repeat(64));
    process.exit(1);
  }
  if (unknown.length) {
    console.log(`  ⚠️  INCONCLUSIVE — ${unknown.length}/${results.length} probes could not reach the database.`);
    console.log('     Not reporting success: a network failure is not a policy denial.');
    console.log('='.repeat(64));
    process.exit(2);
  }
  console.log(`  ✅ ALL ${results.length} PROBES PASSED — anon access is locked down.`);
  console.log('='.repeat(64));
  process.exit(0);
}

main().catch((e) => {
  console.error('verify_rls crashed:', e);
  process.exit(2);
});
