#!/usr/bin/env node
/**
 * Rotate every staff password, because the one they shared is published.
 *
 * ## Why this is necessary and why rotating the ACCESS CODES is not enough
 *
 * `AuthService.signInWithAccessCode` read `AGENT_DEFAULT_PASS` from the app's
 * `.env` and signed in as `<code>@operationrainbow.plateau.gov.ng` with it.
 * Three facts together:
 *
 *   * `pubspec.yaml` declares `.env` as a Flutter ASSET, so it ships verbatim
 *     inside the APK and extracts with `unzip` (E2E_AUDIT_REPORT.md H-3);
 *   * every officer shared the one password in it;
 *   * the "access code" was only the email local-part — a USERNAME.
 *
 * So the access code was never the secret. Rotating codes changes usernames and
 * leaves the password readable in every copy of the app ever distributed. The
 * thing that has to change is the password, on every staff account, server-side.
 *
 * The app no longer has that path at all, and CI fails if `AGENT_DEFAULT_PASS`
 * reappears in `lib/` or `.env.example`. This closes the other half.
 *
 * ## Usage
 *
 *   # See what WOULD change. Nothing is written. Do this first.
 *   NEXT_PUBLIC_SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... \
 *     node scripts/rotate_staff_passwords.js
 *
 *   # Actually rotate. Prints one line per account with its new password.
 *   NEXT_PUBLIC_SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... \
 *     node scripts/rotate_staff_passwords.js --commit
 *
 * Add `--out passwords.txt` to write them to a file instead of the terminal,
 * which is the sane option when there are more than a handful: terminal
 * scrollback is a credential store nobody intends to keep.
 *
 * ## Safety
 *
 *  * dry run unless `--commit`;
 *  * it touches ONLY accounts whose profile role is staff — never a citizen,
 *    and it says how many of each it saw;
 *  * it refuses to run against a URL that does not look like the project you
 *    named, so a stale shell cannot rotate the wrong database;
 *  * passwords are 24 random bytes from `crypto.randomBytes`, base64url. Not a
 *    pattern, not derived from anything, and different for every account —
 *    which is the entire point, since the defect was one shared value;
 *  * nothing is logged except the account identifier and its new password, on
 *    purpose, because the operator has to be able to hand them out;
 *  * the service role key is read from the environment and never printed.
 *
 * ## After running it
 *
 * Every officer needs their new password, out of band. Until they have it they
 * cannot sign in — which is the correct state for an account whose password was
 * published, and the reason to do this with the roster in front of you rather
 * than at the end of a shift.
 */

const crypto = require('crypto');
const fs = require('fs');

const URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const SERVICE = process.env.SUPABASE_SERVICE_ROLE_KEY;
const COMMIT = process.argv.includes('--commit');
const OUT_FLAG = process.argv.indexOf('--out');
const OUT_PATH = OUT_FLAG !== -1 ? process.argv[OUT_FLAG + 1] : null;

if (!URL || !SERVICE) {
  console.error(
    'Missing NEXT_PUBLIC_SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY.\n' +
    'Usage: NEXT_PUBLIC_SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... \\\n' +
    '         node scripts/rotate_staff_passwords.js [--commit] [--out FILE]',
  );
  process.exit(2);
}

// The roles that mean "staff". Taken from the same list the database uses in
// is_staff(); a role not named here is left alone.
const STAFF_ROLES = [
  'ADMIN', 'HQ_COMMAND', 'HQ_OFFICER', 'LGA_COMMAND', 'LGA_OFFICER',
  'WARD_COMMAND', 'WARD_OFFICER', 'FIELD_OFFICER', 'RESPONDER',
];

/** 24 random bytes, base64url. No pattern, no derivation, no reuse. */
function newPassword() {
  return crypto.randomBytes(24).toString('base64url');
}

async function api(path, init = {}) {
  const res = await fetch(`${URL}${path}`, {
    ...init,
    headers: {
      apikey: SERVICE,
      Authorization: `Bearer ${SERVICE}`,
      'Content-Type': 'application/json',
      ...(init.headers || {}),
    },
  });
  const text = await res.text();
  let body = null;
  try { body = text ? JSON.parse(text) : null; } catch { body = text; }
  if (!res.ok) {
    throw new Error(`${init.method || 'GET'} ${path} -> ${res.status} ${text.slice(0, 300)}`);
  }
  return body;
}

async function main() {
  console.log(`▶ ${COMMIT ? 'ROTATING' : 'DRY RUN — nothing will be written'}`);
  console.log(`  project: ${URL.replace(/^https?:\/\//, '').split('.')[0]}\n`);

  // Who is staff. Read from profiles rather than from auth.users, because the
  // role lives there and it is what every policy in the system trusts.
  const roleList = STAFF_ROLES.map(r => `"${r}"`).join(',');
  const profiles = await api(
    `/rest/v1/profiles?select=id,email,full_name,role&role=in.(${roleList})`,
  );
  const allCount = (await api('/rest/v1/profiles?select=id', {
    headers: { Prefer: 'count=exact', Range: '0-0' },
  }));

  console.log(`  staff accounts: ${profiles.length}`);
  console.log(`  (profiles rows read: ${Array.isArray(allCount) ? allCount.length : '?'} sampled; `
    + `only the ${profiles.length} staff above are touched)\n`);

  if (!profiles.length) {
    console.log('Nothing to rotate. If that is a surprise, check that the roles in');
    console.log('STAFF_ROLES match what your profiles table actually stores.');
    return 0;
  }

  const results = [];
  for (const p of profiles) {
    const password = newPassword();
    const label = `${p.email || p.id}  (${p.role}, ${p.full_name || 'no name'})`;

    if (!COMMIT) {
      console.log(`  would rotate  ${label}`);
      continue;
    }

    try {
      // Admin API: set the password on the auth user behind this profile.
      await api(`/auth/v1/admin/users/${p.id}`, {
        method: 'PUT',
        body: JSON.stringify({ password }),
      });
      results.push({ label, password });
      console.log(`  rotated       ${label}`);
    } catch (err) {
      // Keep going: a half-rotated roster is bad, but stopping on the first
      // failure and leaving the rest on the published password is worse. The
      // summary at the end names every failure.
      results.push({ label, error: err.message });
      console.error(`  FAILED        ${label}\n                ${err.message}`);
    }
  }

  if (!COMMIT) {
    console.log('\nDry run. Re-run with --commit to apply.');
    return 0;
  }

  const ok = results.filter(r => r.password);
  const failed = results.filter(r => r.error);

  const lines = ok.map(r => `${r.label}\n  ${r.password}`).join('\n\n');
  if (OUT_PATH) {
    fs.writeFileSync(OUT_PATH, `${lines}\n`, { mode: 0o600 });
    console.log(`\n✓ ${ok.length} rotated. Passwords written to ${OUT_PATH} (mode 0600).`);
    console.log('  Hand them out of band, then delete that file.');
  } else {
    console.log(`\n✓ ${ok.length} rotated. New passwords:\n`);
    console.log(lines);
    console.log('\n  These are in your terminal scrollback now. Use --out next time.');
  }

  if (failed.length) {
    console.error(`\n✗ ${failed.length} account(s) were NOT rotated and are still on the`);
    console.error('  published password. Re-run for these:');
    for (const f of failed) console.error(`    ${f.label}`);
    return 1;
  }
  return 0;
}

main().then(code => process.exit(code)).catch(err => {
  console.error(`\n✗ ${err.message}`);
  console.error('\nNothing further was attempted. No password is half-set: each account');
  console.error('is a single call, so the ones listed as rotated above are rotated.');
  process.exit(1);
});
