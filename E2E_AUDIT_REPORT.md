# Operation Rainbow — End-to-End Audit & Test Report

**Date:** 2026-08-13
**Scope:** Flutter mobile app (`lib/`), HQ Next.js dashboard (`hq-dashboard-next/`), legacy dashboard (`hq-dashboard/`), Supabase schema & RLS, Firebase remnants (`functions/`, `firestore.rules`), build/deploy/CI.
**Branch audited:** `claude/e2e-audit-test-3c6xfl` @ `f62ac83`

## Executive summary

The system does not currently meet a deployable security bar. Five findings are
**critical**. C-1 to C-4, in combination, mean the entire production database —
including citizen PII and live GPS telemetry of victims and officers — is readable
and writable by anyone on the internet, with no credentials required. C-5 is not a
security hole but a safety-of-life one: an SOS with no GPS fix is reported to
dispatch at a fabricated location.

This is a public-safety / emergency-response system handling location data for
people in danger. **Recommendation: treat the current Supabase project as
compromised, rotate all keys, and do not deploy until C-1 through C-4 are fixed.
C-5 needs an operational decision before it can be fixed correctly — see that
section.**

| Severity | Count |
|---|---|
| Critical | 5 |
| High | 8 |
| Medium | 10 |

### What was actually executed (not just read)

| Check | Result |
|---|---|
| `npm install` (hq-dashboard-next) | ✅ pass |
| `tsc --noEmit` | ✅ pass, 0 errors |
| `eslint` | ❌ 21 errors, 4 warnings |
| `next build` (no env) | ❌ **FAILS** — release blocker |
| `next build` (with env) | ✅ pass |
| Client bundle secret scan | ❌ **service_role key found in public bundle** |
| Runtime auth-guard probe (`curl`) | ❌ **bypassed with forged cookie** |
| Unauthenticated API probe (`curl`) | ❌ **both routes execute** |
| Flutter `flutter test` | ⚠️ **not run — Flutter SDK not installed in this environment** |

> The Flutter suite could not be executed here. Its findings below are from static
> review and are flagged as such. Running `flutter test` remains an open action.

---

## CRITICAL

### C-1. Supabase `service_role` key is hardcoded and shipped to every browser

**File:** `hq-dashboard-next/src/lib/supabase.ts:7`

```ts
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || 'sb_secret_nMYk3r8...';
export const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {...});
```

`SUPABASE_SERVICE_ROLE_KEY` is not a `NEXT_PUBLIC_*` variable, so in the browser
`process.env.SUPABASE_SERVICE_ROLE_KEY` is `undefined` and **the hardcoded literal
becomes the operative value**. Because `supabase.ts` is imported by ten `'use client'`
components (including `login/page.tsx`), the whole module — `supabaseAdmin` included —
is bundled for the client.

**Verified empirically.** After `next build` with a *placeholder* service-role env var set:

```
$ grep -rl "***REMOVED-SECRET***" .next/static/
.next/static/chunks/05kdwa1hd5e_h.js
.next/static/chunks/03ai.01t02ymy.js

$ grep -o '05kdwa1hd5e_h' .next/server/app/login.html
05kdwa1hd5e_h          # ← chunk is loaded by the PUBLIC, UNAUTHENTICATED login page
```

Bundle content: `sh=w.default.env.SUPABASE_SERVICE_ROLE_KEY||"sb_secret_nMYk3r8..."`

The placeholder env value did **not** appear in the bundle — the hardcoded literal did.
Setting the env var correctly in production does **not** fix this.

**Impact:** `service_role` bypasses all RLS. Any visitor to `/login` can extract it from
JavaScript and gain full read/write on every table: citizen identities, phone numbers,
live GPS telemetry, chat logs, alerts. Total database compromise.

**Fix:**
1. Rotate the Supabase `service_role` key immediately — assume it is burned.
2. Delete `supabaseAdmin` from `src/lib/supabase.ts`. It is not referenced anywhere else
   in the codebase, so removal is non-breaking.
3. If admin access is needed later, construct the client **inside** a route handler /
   server action file only, never in a module reachable from a client component.
4. Remove all hardcoded credential fallbacks; fail loudly on missing env instead.
5. Add a CI gate: `grep -r "sb_secret" .next/static/` must return nothing.

---

### C-2. Authentication bypass via forged `__session` cookie

**Files:** `hq-dashboard-next/src/proxy.ts:26,45,49`, `src/app/login/page.tsx:60`

The middleware accepts an unsigned, client-set cookie as proof of authentication:

```ts
const hasSessionCookie = request.cookies.get('__session')?.value === 'true';
const { data: { user } } = await supabase.auth.getUser();
if (user || hasSessionCookie) { return response; }   // ← OR
```

The cookie is written by client-side JS (`document.cookie = '__session=true'`), so it is
not `HttpOnly`, not `Secure`, and carries no signature or expiry binding.

**Verified empirically** against a production build on `localhost:3010`:

```
GET /dashboard                          → 307 redirect to /login   ✅
GET /dashboard  -H 'Cookie: __session=true'  → 200 OK              ❌ BYPASS
```

**Impact:** Anyone can reach the full HQ command dashboard by typing one line into the
browser console. Combined with C-3, the dashboard then renders real operational data.

**Fix:** Delete the `hasSessionCookie` fallback entirely and rely solely on
`supabase.auth.getUser()`. Delete the `document.cookie` write in `login/page.tsx`
(`@supabase/ssr` already manages session cookies). Fail closed in the `catch` block —
it currently also honours the forged cookie.

---

### C-3. Row Level Security is effectively disabled

**File:** `supabase/migrations/20260720000000_initial_schema.sql:124-142`

```sql
CREATE POLICY "Allow public read access to profiles" ON public.profiles FOR SELECT USING (true);
CREATE POLICY "Allow reading telemetry"  ON public.telemetry FOR SELECT USING (true);
CREATE POLICY "Allow users to update own telemetry" ON public.telemetry FOR ALL USING (true);
CREATE POLICY "Allow authenticated users to insert alerts" ON public.alerts FOR INSERT WITH CHECK (true);
CREATE POLICY "Allow authenticated users to update alerts" ON public.alerts FOR UPDATE USING (true);
CREATE POLICY "Allow reading chat messages" ON public.chat_messages FOR SELECT USING (true);
CREATE POLICY "Allow service role to manage system alerts" ON public.system_alerts FOR ALL USING (true);
```

`USING (true)` grants the `anon` role unrestricted access. The anon key is public by
design (it ships in the mobile app and the web bundle), so these policies expose:

- **`profiles`** — every citizen and officer: name, email, phone, role, LGA/ward/PU.
- **`telemetry`** — `FOR ALL USING (true)`: read **and write** live GPS coordinates of
  every user. For an emergency system this means an attacker can locate a person who
  has pressed SOS, or falsify responder positions.
- **`alerts`** — inject fake emergencies or silently close real ones (`UPDATE USING (true)`).
- **`chat_messages`** — read all dispatcher↔citizen conversations.
- **`system_alerts`** — `FOR ALL USING (true)` despite the name mentioning service role;
  the policy has no role restriction, so anon can push state-wide alerts.

**The hardening migration does not fix this.** `supabase/migrations/phase1_foundation.sql`
adds correct strict policies (`chat_read`, `telemetry_own_upsert`, …) but only drops
policies *by those new names*. The permissive originals — `"Allow reading telemetry"`,
`"Allow reading chat messages"`, etc. — are never dropped. **PostgreSQL combines
multiple PERMISSIVE policies with `OR`**, so the wide-open policy still grants access
and the strict policy is a no-op.

**Fix:**
1. Write a migration that explicitly `DROP POLICY`s every `USING (true)` policy by its
   exact original name.
2. Rewrite per table with least privilege: `profiles` readable only by self or command
   roles; `telemetry` insert/update restricted to `auth.uid() = user_id`, readable only
   by command roles; `alerts` update restricted to assigned responders/command.
3. Verify with an `anon`-key script asserting each table returns 0 rows / permission
   denied. Add it to CI.
4. Audit Supabase logs for prior anon access to `profiles` and `telemetry`.

---

### C-4. Both API routes accept unauthenticated requests

**Files:** `src/app/api/notify-agency/route.ts`, `src/app/api/push/dispatch/route.ts`

Neither handler checks a session, and the middleware explicitly excludes them:

```ts
if (pathname.startsWith('/api')) { return NextResponse.next(); }   // proxy.ts:14
```

**Verified empirically** (no credentials of any kind):

```
POST /api/notify-agency  → 200 {"success":true,"results":[{"method":"SMS","status":"SKIPPED",...}]}
POST /api/push/dispatch  → 500 (reached the DB layer; SKIPPED only because this test env had no Termii/OneSignal creds)
```

The handlers ran their full business logic. In production with credentials configured,
an unauthenticated attacker can:
- Blast SMS to Police / Army / DSS / NSCDC / FRSC / Amotekun liaison numbers with
  attacker-controlled `reason` and `sentBy` text (`/api/notify-agency`).
- Fire "TACTICAL MISSION DISPATCH" push notifications to any officer (`/api/push/dispatch`).
- Write arbitrary rows into `agency_notifications`.

This is a false-dispatch / inter-agency-panic vector against a live security operation.

**Fix:** Authenticate every route handler server-side (`createServerClient` +
`auth.getUser()`), then authorize by role (HQ command only). Add rate limiting.
Validate `agency` against the allowlist and reject unknown values (currently an unknown
agency silently yields `SKIPPED` + `200 success:true`). Do not let the middleware
blanket-skip `/api`.

---

### C-5. An SOS with no GPS fix is reported at a fabricated location (safety-critical)

**Files:** `lib/services/alert_service.dart:45-46`, `hq-dashboard-next/src/app/dashboard/page.tsx:559-560`

Two independent layers each invent plausible coordinates when the real ones are
missing, and neither marks them as invented.

```dart
// mobile — alert_service.dart
var finalLat = latitude ?? 9.9167;   // Fallback Jos loc
var finalLng = longitude ?? 8.8917;
```

```ts
// dashboard — page.tsx
lat: d.latitude || d.lat || 9.9285,
lng: d.longitude || d.lng || 8.8921,
```

**Effect:** a citizen presses SOS somewhere the GPS cannot get a fix. The alert
arrives at the command dashboard as a **confident pin in central Jos**. There is
nothing in the record distinguishing it from a real fix, so responders are
dispatched to a location that was fabricated by a `??` operator.

This is the same "plausible default preferred to an honest error" pattern as
C-3 and the auth fail-open, but here the consequence is physical: armed
responders sent to the wrong place during an emergency.

Two aggravating details:

* The dashboard uses `||`, not `??`, so a legitimate `0` coordinate would also
  be replaced.
* The **telemetry** path in the same file already does the right thing
  (`page.tsx:593`: `t.latitude ?? t.lat ?? null`). Only the alerts path
  fabricates. The correct behaviour is already present next to the defect.

**Why this was not fixed in this pass.** Removing the fallback alone makes the
problem worse, not better. `LiveMap.tsx:314` skips any alert without
coordinates (`if (!alert.lat || !alert.lng) return;`), and `sectorAlerts`
(`page.tsx:961`) feeds only counters — there is no list view. Alerts reach HQ
*through the map*, so a null-coordinate alert would become **invisible**: a
silently dropped emergency, which is worse than a wrong pin.

A correct fix therefore needs a decision about how unlocated alerts are
surfaced to dispatch. That is an operational question about the dispatch
workflow, not a code question. Options, roughly in order of preference:

1. **Distinct marker at jurisdiction centroid.** Mobile sends
   `latitude`/`longitude` as null plus `geo_lga`/`geo_ward`; the dashboard plots
   at the LGA or ward centroid with a visually distinct "LOCATION UNVERIFIED"
   marker and popup. Stays visible to dispatch, removes the false precision, and
   degrades to the accuracy actually available.
2. **Separate unlocated-alerts panel.** Stop plotting entirely; add a persistent
   panel that cannot be missed. Most honest, but it is new UI.
3. **Description marker only.** Prefix with `[LOCATION_UNVERIFIED]`, following
   the existing `[OFFLINE_SMS]`/`[SMS]` convention already used by
   `smsFallbackCount`. Smallest change, but a dispatcher may still act on the pin.

Note that option 1 requires the offline queue to accept null coordinates:
`offline_queue` currently declares `lat REAL NOT NULL, lng REAL NOT NULL`
(`sqlite_service.dart:34-35`), so it needs a schema version bump and an
`onUpgrade` path.

**Related, already fixed:** the offline replay path was separately dropping
*real* coordinates through a column-name mismatch — see the offline queue fix
and `test/offline_queue_test.dart`.


## HIGH

### H-1. Production build fails — release blocker

`next build` exits 1 on a clean checkout:

```
Error: supabaseUrl is required.
  at Object.<anonymous> (.next/server/app/api/push/dispatch/route.js:6:3)
> Build error occurred — Failed to collect page data for /api/push/dispatch
```

Cause: `src/app/api/push/dispatch/route.ts:4-6` calls `createClient()` at **module scope**
with `|| ''` fallbacks, which executes during build-time page-data collection.

This is invisible to the existing test suite because `run_all_tests.sh` only starts
`next dev` (lazy compilation) and never runs `next build`.

**Fix:** Move client construction inside the handler, validate env at startup, and add
`next build` to `run_all_tests.sh` and CI.

### H-2. Demo credentials published on the public login page

`src/app/login/page.tsx:6-10,~470` ships one-tap quick-fill buttons for `HQ-001`,
`HQ-002`, `COMMANDER-TEST` and renders the shared password `12345Gg!` in the footer of
the unauthenticated page. Combined with C-3 these are working command-level logins.

**Fix:** Remove the demo block and the footer credential line; gate behind
`NODE_ENV !== 'production'` at minimum. Rotate all three passwords. Enforce a password
policy and MFA for command accounts.

### H-3. `.env` is bundled into the shipped mobile binary

`pubspec.yaml:69` lists `.env` under `flutter: assets:`. Flutter assets are stored
verbatim in the APK/IPA and extract with `unzip`. Every secret in `.env` is therefore
public: `TERMII_API_KEY`, `CLOUDINARY_API_SECRET`, `HMAC_SECRET`, `DEMO_CITIZEN_PASS`,
`AGENT_DEFAULT_PASS`, `DURESS_PIN`, `SAFE_PIN`.

**Fix:** Remove server-side secrets from the app. Proxy SMS (Termii) and media uploads
through authenticated backend endpoints. Keep only genuinely public values (Supabase URL
and anon key) in the client. `DURESS_PIN`/`SAFE_PIN` must be per-user and server-verified,
not a build-time constant shared by every install.

### H-4. Hardcoded HMAC shared secret

`lib/services/hmac_service.dart:6` —
`dotenv.env['HMAC_SECRET'] ?? 'RAINBOW_PLATEAU_SECURE_HMAC_GATEWAY_KEY_2026'`.
If the env var is absent the app silently signs with a secret that is in public source
control, so signatures prove nothing. Note also that a client-held HMAC key is
extractable in principle (see H-3) — this scheme cannot provide integrity against a
malicious client regardless.

**Fix:** Remove the fallback and fail closed. Re-scope what HMAC is meant to protect; if
it is request integrity, enforce it server-side against a key the client never holds.

### H-5. Cloudinary credentials hardcoded; signed-upload path is dead

`lib/services/cloudinary_service.dart:16-18` hardcodes `cloudName` and
`apiKey` (`439918347355179`), and defaults `apiSecret` to `''`. With an empty secret the
SHA-1 signature at line ~35 is computed over `...timestamp` with nothing appended, so
Cloudinary rejects every signed upload and the code silently falls through to the
**unsigned preset** path. The "signed upload" is therefore never exercised, and the
unsigned preset allows anyone who reads it from the binary to upload to your account.

**Fix:** Delete the signed-upload branch from the client (an API secret must never be on
a device). Issue upload signatures from an authenticated backend endpoint, or restrict
the unsigned preset with strict folder/size/format/moderation limits and rotate it.

### H-6. Plaintext credentials committed to the repository

- `hq-002-auth.json` — `"passwordHash": "hq-002"` (not a hash; a trivial password) for
  `hq-002@operationrainbow.plateau.gov.ng`.
- `GoogleService-Info (3).plist` at repo root — Firebase iOS `API_KEY`, tracked despite
  `.gitignore` covering `ios/Runner/GoogleService-Info.plist`.
- `hq-dashboard/dist/assets/index-D5vTRjzP.js` — committed build output containing the
  Firebase web API key `***REMOVED-SECRET***`, also hardcoded as a
  fallback in `hq-dashboard/src/firebase.ts:8`.

**Fix:** Delete these files, rotate the credentials, and purge them from git history
(`git filter-repo`). Add a secret-scanning pre-commit hook and enable GitHub secret scanning.

### H-7. No server-side RBAC

Role resolution in `src/app/dashboard/page.tsx` (lines 350-370, 515) happens **client-side
after render**, and line 515 defaults an unknown user to `'HQ_COMMAND'` — fail-open to the
highest privilege. The middleware checks only *that* a session exists, never *which role*.
Any authenticated account — or anyone using the C-2 bypass — reaches HQ command features.

**Fix:** Resolve role server-side in the middleware/layout, deny by default on unknown
role, and back it with RLS so a forged client cannot read data its role disallows.

### H-8. Fresh clone cannot build either app

- Mobile: `.env` is a declared asset but is untracked and there is **no `.env.example`**.
  `flutter build` fails on the missing asset.
- Web: see H-1.

**Fix:** Commit `.env.example` documenting all 12 referenced keys
(`AGENT_DEFAULT_PASS`, `CLOUDINARY_*`, `DEMO_CITIZEN_*`, `DURESS_PIN`, `HMAC_SECRET`,
`SAFE_PIN`, `SOS_PHONE`, `TERMII_API_KEY`) plus the web vars, and document setup in README.

---

## MEDIUM

### M-1. The only smoke test is disabled
`test/widget_test.dart:11` ends with `skip: true`. The single test asserting the app boots
never runs.

### M-2. Test suite has no mocking and no backend coverage
No `mockito` / `mocktail` / `http` test harness anywhere in `pubspec.yaml` or `test/`.
Consequence: no test exercises Supabase auth, alert submission, sync, or offline queueing.
`termii_service_test.dart` passes only because `dotenv` is uninitialised, which routes it
down the `MOCK_TERMII_API_KEY` simulation branch — it validates the mock, not the service.

### M-3. "E2E" tests are shallow UI probes
`integration_test/app_test.dart` pumps individual screens with fixtures and asserts a
single text label. Tests 2, 3 and 4 (PU / Ward / LGA tiers) assert the **identical**
string `'TACTICAL COMMAND'`, so they cannot detect a tier-scoping regression — the exact
thing they are named for. No test covers the real path: citizen SOS → alert row in
Supabase → HQ dashboard render → dispatch → resolution.

### M-4. No CI
No `.github/workflows/`. Nothing enforces build, lint, typecheck, or tests on push —
which is why H-1 (a hard build failure) is sitting on the branch.

### M-5. `deploy.sh` is broken in three ways
- `NODE_BIN="/Users/mac/nodejs/..."` — one developer's laptop path.
- `du -sh hq-dashboard-next/out` — `out/` is no longer produced (static export was
  removed per `next.config.ts`). Under `set -e` the script aborts here.
- No `firebase.json` exists, so `firebase deploy --only hosting|firestore:rules` cannot resolve targets.

### M-6. 116 MB of `node_modules` committed to git
13,306 tracked files under `functions/node_modules/`, plus 28 MB of `screenshots/` and
`hq-dashboard/dist/`. `.git` is 50 MB. Add to `.gitignore` and purge from history.

### M-7. Large volume of dead Firebase-era code
The app runs on Supabase (`pubspec.yaml` has no Firebase dependency), yet the repo still
carries `functions/`, `firestore.rules`, `database.rules.json`, `firestore.indexes.json`,
the entire legacy `hq-dashboard/` (Firebase + React Router), and root scripts
`check_alerts.js`, `seed_code.js`, `get_live_codes.js`, `test_token.js`,
`update_alert_geoscope.js`, `update_user_case.js`.
`hq-dashboard-next/verify-system.js` — referenced as a system verifier — calls Firebase
`httpsCallable('adminEscalateAlert')` against functions the mobile app no longer uses, so
it validates nothing about the current system.

**Fix:** Delete or archive the Firebase stack, or document explicitly which parts remain
authoritative. Ambiguity here caused the split-brain security model (Firestore rules are
carefully written while the live Supabase RLS is wide open).

### M-8. 21 ESLint errors
```
  9  react-hooks/set-state-in-effect   [error]
  9  react/no-unescaped-entities       [error]
  2  react-hooks/immutability          [error]
  1  prefer-const                      [error]
  4  @next/next/no-img-element         [warn]
```
The 9 `set-state-in-effect` errors are cascading-render bugs, relevant on a dashboard
polling live alerts.

### M-9. API error handling returns 500 for client errors
Malformed JSON to `/api/push/dispatch` returns `500` with the raw parser message
(`"Unexpected token 'o', \"not-json\" is not valid JSON"`). Should be `400`, and internal
messages should not be echoed to callers.

### M-10. Dashboard depends on a third-party CDN at runtime
`src/app/layout.tsx:12-14` loads Leaflet and MarkerCluster CSS from `unpkg.com` with no
SRI hashes. For a command dashboard expected to work during an incident, an unpkg outage
or a restricted government network degrades the map UI; without SRI it is also a supply-chain
injection point. Bundle these locally (`leaflet` is already a dependency).

### Also noted
- `.gitignore` contains a bare `*.txt`, which will silently exclude legitimate files.
- `README.md` is still the default Flutter template — no setup, architecture, or env docs.
- `src/proxy.ts:14` skipping every path containing `.` (`pathname.includes('.')`) is a
  broad matcher worth tightening.

---

## Prioritized remediation order

**Stop-the-bleeding (do before any deploy)**
1. Rotate the Supabase `service_role` key, the Firebase API keys, Cloudinary and Termii
   keys, and all demo/command account passwords.
2. C-1 — delete `supabaseAdmin` from the client-reachable module; strip hardcoded fallbacks.
3. C-2 — remove the `__session` cookie bypass.
4. C-3 — drop every `USING (true)` policy and re-issue least-privilege RLS.
5. C-4 — authenticate and authorize both API routes.
6. Review Supabase access logs for prior anon reads of `profiles` / `telemetry`; if the
   service_role key was ever served from a public deployment, treat it as a reportable
   data-protection incident.

**Make it releasable**
7. H-1 build fix, H-2 demo credentials, H-6 committed secrets + history purge.
8. H-3/H-4/H-5 — move SMS, HMAC and media signing behind authenticated backend endpoints.
9. H-7 server-side RBAC, H-8 `.env.example` + README.

**Make it stay fixed**
10. CI running `flutter test`, `flutter analyze`, `tsc --noEmit`, `eslint`, `next build`,
    plus an anon-key RLS assertion test and a bundle secret scan.
11. Un-skip M-1, add mocking (M-2), and build one genuine E2E path: SOS → Supabase →
    dashboard → dispatch → resolve (M-3).
12. Repo cleanup: M-5 deploy script, M-6 committed `node_modules`, M-7 dead Firebase stack.

## Verification gap

`flutter test`, `flutter analyze`, and the `integration_test/` suite were **not executed** —
the Flutter SDK is not available in this environment. All mobile findings above are from
static analysis. Run the mobile suite on a machine with Flutter installed to complete
coverage; expect at minimum that `.env` must be created first (H-8).
