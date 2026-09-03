# Operation Rainbow — End-to-End Audit & Test Report

**Date:** 2026-08-13
**Scope:** Flutter mobile app (`lib/`), HQ Next.js dashboard (`hq-dashboard-next/`), legacy dashboard (`hq-dashboard/`), Supabase schema & RLS, Firebase remnants (`functions/`, `firestore.rules`), build/deploy/CI.
**Branch audited:** `claude/e2e-audit-test-3c6xfl` @ `f62ac83`

## Executive summary

The system does not currently meet a deployable security bar. Six findings are
**critical**. C-1 to C-4, in combination, mean the entire production database —
including citizen PII and live GPS telemetry of victims and officers — is readable
and writable by anyone on the internet, with no credentials required. C-5 is not a
security hole but a safety-of-life one: an SOS with no GPS fix is reported to
dispatch at a fabricated location. C-6 was found last and is the only one that
cannot be settled from inside this repository: the abandoned Firebase backend
exposes two **unauthenticated** public HTTP endpoints running with admin
privileges, one of which injects `DURESS`-flagged emergencies. Whether that is a
live hole or a non-issue depends entirely on whether those functions are still
deployed — a two-minute check that needs the Firebase console.

This is a public-safety / emergency-response system handling location data for
people in danger. **Recommendation: treat the current Supabase project as
compromised, rotate all keys, and do not deploy until C-1 through C-4 are fixed.**

**Current position:** C-1, C-2, C-4 and C-5 are fixed and verified. **Two need a
human, for different reasons.**

**C-3** is addressed in code and no longer unverified: the migration has been proven
correct against a real PostgreSQL 16 (`./scripts/verify_rls_migration.sh`, also a CI
job). It just has not been *run* on your database, which needs credentials this audit
does not have.

**C-6** cannot be addressed in code at all. Deleting `functions/` does not undeploy
anything, so the only action that closes it is `firebase functions:list` against
project `rainbow-97f1e` followed by deleting whatever is still there. Do that
**before** deleting the source — `functions/index.js` is the last remaining record
of what that backend exposes, and removing it first destroys the list of names you
need to audit the console against.

The harness replays the real migration history, confirms the baseline (**12
permissive `USING (true)` policies survive all three existing "hardening"
migrations** — empirical proof of the finding below), applies the fix, and then
asserts behaviour rather than structure:

| Assertion | Result |
|---|---|
| anon cannot read `profiles`, `telemetry` or `alerts` | ✅ |
| a citizen sees only their own profile and telemetry | ✅ |
| a citizen **cannot escalate their own role to `HQ_COMMAND`** | ✅ blocked by trigger |
| a benign self-update still succeeds | ✅ |
| a citizen cannot falsify another user's GPS | ✅ |
| command staff retain full operational visibility | ✅ |
| a citizen cannot broadcast a state-wide advisory | ✅ |

The third row is the one C-4 depends on: before the migration, `FOR ALL USING
(auth.uid() = id)` let any citizen set their own role and pass the API layer's
`requireRole()`.

> **This document records the audit as found.** The findings below are written in
> the present tense as they were at `f62ac83`. Several are now fixed in PR #1 —
> see [Status as of PR #1](#status-as-of-pr-1) for what is closed, what is open,
> and what still needs production access.

| Severity | Count |
|---|---|
| Critical | 6 |
| High | 9 |
| Medium | 10 |

### What was actually executed (not just read)

> Snapshot from the **original audit run**. For the current state after the fixes,
> see [Status as of PR #1](#status-as-of-pr-1) at the end of this document.

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

### C-3 UPDATE — a real `pg_policies` dump changed this finding materially

Production was finally read. **44 live policies where a replica rebuilt from this
repo's migrations has 21.** 34 of them exist only in production; no file here
creates them. That dump corrects this report in one direction and worsens it in
another.

**Correction, in your favour.** This report repeatedly said the database was
"readable and writable by anyone on the internet, with no credentials". **That is
no longer true of production.** The `USING (true)` policies on `profiles`,
`telemetry`, `alerts` and `chat_messages` are gone — somebody replaced them by
hand with `auth.uid() IS NOT NULL` variants. The claim was true of the migration
files, and I asserted it of the running system without ever having seen one.
Anon is not reading citizen PII or live GPS.

**What is actually true, and it is still bad.** The wide-open-to-anon problem was
replaced with wide-open-to-any-authenticated-user, and anyone can register:

| Policy | Effect |
|---|---|
| `profiles_read_all` | any signed-in user reads **every** profile — names, emails, phones |
| `telemetry_read_authenticated` | any signed-in user reads **everyone's live GPS** |
| `alerts_read_authenticated` | any signed-in user reads every alert |
| `chat_read_authenticated` | any signed-in user reads every dispatcher message |
| `agency_*_write` | any signed-in user **writes** agency deployments and personnel |

**Two live privilege-escalation paths, both confirmed executable.**

*First:* `profiles_write_own` is `FOR ALL USING (id = auth.uid())` and
`profiles_update_own` is `UPDATE ... WITH CHECK (auth.uid() = id)` — neither
restricts columns. A citizen can set their own `role`. Demonstrated against a
production-shaped replica: `citizen self-promoted to: HQ_COMMAND`. Since
`is_hq_or_admin()` and `is_responder()` read `profiles.role`, and the dashboard's
`requireRole()` reads the same column, this grants everything.

*Second, and worse:* `sysalerts_write_hq`, `agency_notifications_read` and
`agency_notifications_insert` authorise on
`auth.jwt() -> 'user_metadata' ->> 'role'`. In Supabase `user_metadata` is
**written by the client** — `supabase.auth.updateUser({ data: { role:
'HQ_COMMAND' } })`. Any user grants themselves those permissions with one call
and no database write at all. Nothing can defend a policy that trusts
`user_metadata`; only `app_metadata` is server-controlled.

**The migration as written would have been almost entirely decorative.** Its DROP
list names policies that mostly no longer exist. Of 44 live policies it would
have dropped 10 and left 34 — and PERMISSIVE policies combine with OR, so
`profiles_read_all` would have kept defeating `profiles_select_self_or_staff`.
The identical failure as `phase1_foundation.sql`, which is the finding this
migration exists to fix. **The dry run existed for exactly this and it was right
to insist on it.**

**Fixed.** The migration now drops all 34 by name, and adds policies for the four
`agency_*` tables it never covered — without those, dropping their policies would
leave RLS enabled with none, denying everything and blanking the agency portal.

Verified against a replica carrying production's real policy shape:

| | before | after |
|---|---|---|
| citizen sees profiles | **3 of 3** | 1 (own) |
| citizen sees telemetry | **2 of 2** | own + staff |
| citizen sets own role | **succeeds → HQ_COMMAND** | blocked |
| command staff visibility | full | full |
| anon | denied | denied |

#### The dry run came back empty — investigation, 2026-09-02

Run against the real database, `scripts/rls_production_dryrun.sql` returned its
three column headers and **zero rows**. No error, no findings, nothing to act on.
On a script whose entire job is to answer *"is this safe to apply?"*, silence is
the most dangerous output it can give: it is indistinguishable from "all clear".

Reproduced against a production-shaped PostgreSQL 16 replica — the repo's
migration history replayed, Supabase's default `anon`/`authenticated` grants
added, real profile rows seeded. **Two causes, both now fixed:**

1. **A result set is transactional.** The findings were `SELECT`ed from a temp
   table and the script then ran `ROLLBACK`. A client that has not materialised
   the rows before the rollback lands has nothing left to hand back. `psql`
   materialises eagerly and showed them, which is why this survived local
   testing; the SQL Editor evidently does not.
2. **One unhandled error destroyed every finding.** With real data present, the
   command-visibility assertion raised `permission denied for table profiles`,
   which aborted the whole transaction — so the closing `SELECT` had nothing to
   read. Any single unexpected error anywhere in the script did this.

The findings now come back as a **`RAISE EXCEPTION`**. An error message is
delivered out of band and cannot be rolled back, and raising also makes the
rollback intrinsic rather than a trailing statement that must survive whatever
the client does with the batch — the script cannot commit even in principle. The
verdict is the first line of the message so it survives truncation. Each
assertion section is individually guarded, so a failure is recorded as a
`PROBLEM` naming its own cause instead of silencing the run.

**The tool is now proven to detect the thing it exists for**, rather than
asserted to. On identical replicas differing by one hand-created policy —
`CREATE POLICY … ON profiles FOR SELECT TO authenticated USING (true)`, the kind
the migration cannot drop because it does not know the name:

| replica | verdict | citizen check |
|---|---|---|
| policy present | `>>> DO NOT APPLY` | *citizen sees too many profiles — 2, expected 1* |
| policy absent | `>>> SAFE TO APPLY` | *citizen sees only their own profile* |

`scripts/verify_dryrun_emits.sh` gates all of this in CI: a verdict is emitted, a
re-opened table is detected, an assertion failure does not silence the run, and
the policy count is unchanged afterwards. Mutation-verified — restoring the old
`SELECT`-then-`ROLLBACK` delivery fails the gate.

**This does not close C-3.** The migration still has not been run against your
database. What changed is that the instrument for deciding whether it is safe now
reports its answer instead of returning nothing.


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

**FIXED** — and one claim in the original write-up of this finding was wrong.

I first concluded that removing the fallback would make unlocated alerts
*invisible*, reasoning that `LiveMap.tsx:314` skips alerts without coordinates
and `sectorAlerts` (`page.tsx:961`) feeds only counters. That was incorrect. The
dashboard also renders a **SITUATIONAL FEED** panel beside the map
(`page.tsx:~1388`) which maps over `filtered` and lists *every* alert in scope
with its type, status, description and LGA — regardless of coordinates. Dropping
the fabrication therefore does not hide anything; it only removes a false pin.

The fix accordingly needed no new UI:

* **Mobile** (`alert_service.dart`) no longer substitutes Jos. `finalLat` /
  `finalLng` stay null when there is no fix, and the null case is logged.
* **Offline queue** (`sqlite_service.dart`) migrated v1 -> v2 to drop `NOT NULL`
  from `lat`/`lng`. SQLite cannot alter a column in place, so the table is
  rebuilt and rows copied; a queued alert is an unsent emergency and must
  survive the upgrade. Covered by a test that builds a real v1 database, runs
  the migration, and asserts the pending row is still there.
* **Dashboard** (`page.tsx:559`) uses `?? null` instead of `|| 9.9285`, matching
  what the telemetry path four lines below already did. `??` rather than `||` so
  a legitimate `0` is preserved.
* **Visibility** — the situational feed now shows a `NO GPS FIX — NOT ON MAP`
  badge (with the ward, when known) on any alert without coordinates, and the
  feed header shows an `N UNLOCATED` counter. A dispatcher can see that the map
  is under-reporting rather than having to infer it.

Residual: an unlocated alert is listed but not plotted. Plotting it at an
LGA/ward centroid would be better still, but no centroid data exists in the
repo, and hand-writing 17 LGA coordinates from memory would repeat exactly the
fabrication this finding is about. That needs a real gazetteer.

**Related, already fixed:** the offline replay path was separately dropping
*real* coordinates through a column-name mismatch — see the offline queue fix
and `test/offline_queue_test.dart`.

### C-6. Two unauthenticated Cloud Functions can inject false emergencies — **if they are still deployed**

**Files:** `functions/index.js:582` (`smsWebhook`), `functions/index.js:958` (`seedMockData`),
`.firebaserc` (project `rainbow-97f1e`)

This was originally filed under M-7 as "dead Firebase-era code". Tracing the HMAC
scheme for H-3 showed that framing is wrong, and dangerously so.

`functions/index.js` is 2,107 lines defining a **complete second backend** —
escalation task queue, Firestore triggers, admin dispatch/resolve/escalate calls,
a mass-broadcast engine, and a `pubsub` watchdog on `every 5 minutes`. It calls
`admin.initializeApp()` with default credentials, so **every function runs with
full admin privileges and bypasses `firestore.rules` entirely**. The carefully
written rules file provides no protection against any of it.

Two of the exports are `functions.https.onRequest`, which is a **public HTTP
endpoint with no authentication unless the handler adds it**. Neither does:

```js
exports.seedMockData = functions.https.onRequest(async (req, res) => {
  const mockAlerts = [ /* 10 fabricated alerts */ ];
  //  ↑ no auth check, no secret, no method check, no rate limit
  await batch.commit();
```

```js
exports.smsWebhook = functions.https.onRequest(async (req, res) => {
  if (req.method !== 'POST') return res.status(405).send('Method Not Allowed');
  const messageBody = req.body.Body || req.body.text || req.body.message || "";
  //  ↑ no signature verification, no shared secret, no sender allowlist
```

**What each does to anyone who finds the URL.**

*`seedMockData`* — one unauthenticated request writes ten `CRITICAL` alerts into
the `alerts` collection at real Plateau State coordinates. **Three are marked
`status: "DURESS"`** — the code word this system uses for *reporting under
coercion* — including `"A child was just taken into an unmarked black vehicle"`
at 9.8755, 8.8522. It is a one-request false-emergency injector, and the alerts
are indistinguishable from real ones because they are *written the same way*.

*`smsWebhook`* — `POST` a body of `ALERT|<any phone>|KD|LAT:9.9|LNG:8.9` and you
create a `CRITICAL` kidnap alert **attributed to a phone number you chose**, then
enqueue a real task-queue escalation to WARD tier 120 seconds later. Attribution
and dispatch, both attacker-controlled, with no credential.

It also carries the C-5 defect independently: `parseFloat(...) || 9.9167` /
`|| 8.8917`. The Jos fallback again, in a third layer nobody was looking at.

**The part that makes this a live finding rather than a cleanup task.**

Deleting `functions/` **does not undeploy anything.** If these were ever pushed
to `rainbow-97f1e`, they are serving right now, and the watchdog is running every
five minutes — a second unmonitored backend with admin rights, invisible because
everyone reasonably believes "the app runs on Supabase". `pubspec.yaml` has no
Firebase dependency and no file under `lib/` or `hq-dashboard-next/src/` imports
Firebase, which is exactly why nobody would think to look.

H-3 closed the loop on this. `HmacService.generateSignature` had zero callers on
the device; `functions/index.js:442` is the **server half of that same scheme**,
still checking for an HMAC fallback. The client stopped calling when the app moved
to Supabase. Nothing turned the server off. That is the shape of the whole finding.

**This report cannot tell you whether they are deployed.** That needs console
access, and probing the endpoints to find out is not an option — `seedMockData`
would write ten fake emergencies to answer the question. Two minutes, from a
machine with Firebase credentials:

```bash
firebase functions:list --project rainbow-97f1e
# Any of these still listed is live and unauthenticated:
#   smsWebhook, seedMockData, escalationWatchdog, massBroadcast,
#   adminEscalateAlert, adminDispatchAlert, adminResolveAlert, migrateLegacyIncidents

firebase functions:delete smsWebhook seedMockData --project rainbow-97f1e
```

Then check whether anything acted on injected data:

```bash
# Firestore `alerts` written outside the Supabase era, DURESS ones first.
# Any alert with via == "SMS_GATEWAY" or the seed descriptions above is suspect.
```

**Order matters, and it is the opposite of the obvious one.** Delete the *deployment*
first, then the source. Deleting `functions/` first destroys the list of function
names you need in order to know what to look for in the console — and this is the
last written record of what that backend exposes. Severity is `CRITICAL` if
deployed and `NONE` if never deployed; there is no way to be in between, and no way
to find out from inside this repository.

#### Investigation, 2026-09-02 — deployment state still unknown, but the picture changed

Two routes to an answer were tried from the audit container. Both are closed:

* **Probing the endpoints directly.** `https://us-central1-rainbow-97f1e.cloudfunctions.net/…`
  is refused by the egress policy — the proxy answers `403` to the `CONNECT`, the
  same denial that blocks Supabase.
* **The Cloud Functions admin API**, which lists deployments without invoking
  anything. `cloudfunctions.googleapis.com` *is* reachable, but there are no GCP
  credentials here: `CLOUDSDK_AUTH_ACCESS_TOKEN` is the literal string
  `proxy-injected`, and both anonymous and that value return `401`.

Note for whoever picks this up: **`seedMockData` must not be probed over HTTP at
all.** The deployed copy — if it is the pre-guard one — has no method check; it
builds the ten mock alerts and writes them before examining the request. A bare
`curl` of that URL, sent to find out whether it exists, would itself inject ten
fabricated CRITICAL/DURESS emergencies into the live system. `smsWebhook` is safe
to probe: both the old and the new version return `405` to anything that is not a
`POST`, and a `POST` whose body does not begin with `ALERT|` returns `200 Format
ignored.` without touching Firestore.

**Two findings that did come out of it.**

*The stack is fully orphaned.* Neither client can call these functions any more:
`pubspec.yaml` declares no Firebase package at all, `lib/` contains no
`httpsCallable` and no Firebase reference, the dashboard has none either, there is
no `google-services.json` or `GoogleService-Info.plist` left in the tree, and
`main.dart` initialises Supabase and nothing else. Whatever is deployed serves no
caller in this repository. The one consumer that could still exist outside it is an
SMS gateway POSTing to `smsWebhook`.

*The guards below cannot currently be deployed.* `firebase.json` was deleted in
commit `25ca6b4`, and nothing replaced it. It was the file naming `functions` as
the deploy source — along with `firestore.rules` and the database rules — so
`firebase deploy` cannot ship functions, Firestore rules or database rules from
this repository as it stands. The mitigation described below is therefore **dead
code until someone restores a deploy configuration**, and the `functions-guards`
CI job is proving the behaviour of source that has no route to production.

That inverts the remediation. Deploying the guarded version would mean first
restoring deploy config for a stack with no callers; **deleting the deployment is
both the smaller change and the correct one**, and `firebase functions:delete`
needs no `firebase.json`.

**Partial mitigation applied — read the scope carefully.** While `functions/` stays
in the tree it is *deployable source*, so anyone who restores a `firebase.json` and
runs `firebase deploy` for an unrelated reason ships whichever version is on disk.
Both endpoints now fail closed:

* `smsWebhook` requires `X-Rainbow-Gateway-Auth` to match `RAINBOW_SMS_GATEWAY_SECRET`,
  and returns `503` when that secret is unset — an SMS gateway accepting
  unauthenticated emergency reports is worse than one that is off.
* `seedMockData` refuses unless `RAINBOW_ALLOW_SEED=true` **and** `RAINBOW_SEED_SECRET`
  matches `X-Rainbow-Seed-Auth`, and rejects `GET` outright.
* The `|| 9.9167` / `|| 8.8917` fabrication is gone — C-5's third occurrence. Coordinates
  are now range-checked and stored as `null` when unusable, and a legitimate `0` survives.

`functions/test_guards.js` asserts this against the **real exported handlers** with
Firestore stubbed, so the property under test is not "the response is 401" but
"nothing reached the database" — a guard that returns 401 *after* writing the row
would pass the first check and fail this one. It runs as its own CI job, which skips
cleanly once `functions/` is deleted.

Mutation-verified: with the guards removed, 15 of the 16 assertions fail, and the
unauthenticated `seedMockData` call produces **11 writes**. That is the impact of this
finding, measured rather than asserted. The one assertion that still passes is the
deliberate control — *an authorised request is still processed* — which must hold in
both directions, or the guard is just an outage.

**This changes nothing about a deployed copy.** Source edits do not reach a live Cloud
Function until someone redeploys. It removes a trap for the future; it does not close
the finding. `firebase functions:delete` closes the finding.


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

### H-3. `.env` is bundled into the shipped mobile binary — ✅ fixed

`pubspec.yaml:69` lists `.env` under `flutter: assets:`. Flutter assets are stored
verbatim in the APK/IPA and extract with `unzip`. Every secret in `.env` was therefore
public: `TERMII_API_KEY`, `CLOUDINARY_API_SECRET`, `HMAC_SECRET`, `DEMO_CITIZEN_PASS`,
`AGENT_DEFAULT_PASS`, `DURESS_PIN`, `SAFE_PIN`.

No amount of care inside the Dart code could fix this. The credential simply cannot be
on the device; it has to move.

**What was done.** Each of the three server-side secrets was traced to its actual use,
and in two of the three cases the use turned out not to exist:

| Secret | Real usage found | Resolution |
|---|---|---|
| `TERMII_API_KEY` | **one** call site — `emergency_provider` sending the SOS escalation SMS | moved behind `POST /api/sos/dispatch-sms` |
| `HMAC_SECRET` | **zero** call sites — `HmacService.generateSignature` was never invoked | service deleted, key dropped |
| `CLOUDINARY_API_SECRET` | signed-upload branch, dead since the secret defaulted to `''` | already removed under H-5 |

`lib/services/termii_service.dart` and `lib/services/hmac_service.dart` are gone.
`SosDispatchService` replaces the first: it presents the **user's own** Supabase access
token to the HQ backend and sends structured facts — alert id and coordinates. It holds
no credential, chooses no recipient, and composes no message text.

**Why the new endpoint is not just a relocated hole.** Moving a credential server-side is
worthless if the endpoint sends anything anywhere on request. `/api/sos/dispatch-sms`
constrains all three degrees of freedom:

* the **recipient** comes from `SOS_DISPATCH_PHONE` on the server, never the request;
* the **message body** is composed server-side from validated fields — coordinates are
  range-checked numbers, the alert ref is stripped to `[A-Za-z0-9-]{0,8}`, so no
  caller-authored prose can be emitted under the HQ sender ID;
* the **caller** must present a token that Supabase's auth server verifies. The token is
  not decoded locally: a JWT this process merely parses proves nothing.

A best-effort per-user rate limit (3 per 5 min) bounds the ordinary retry case. It is
in-memory and per-instance, so it is documented in the route as what it is — a cheap
90%, not a security control. A durable limit belongs in the database or at the edge.

**Verified.** Unauthenticated `POST` → `401`; forged bearer JWT → `401`; empty bearer →
`401`; malformed JSON from an unauthenticated caller → `401`, not `400`, confirming the
auth check runs before any parsing. A production build scanned for `TERMII_API_KEY`, the
sentinel key value, `SOS_DISPATCH_PHONE` and the destination number: clean. The only
`termii` string in any client chunk is the UI label `TERMII CPaaS SMS GATEWAY`.

Two CI gates now hold this shut: the mobile job fails if any Dart source references
`termii.com`, `TERMII_API_KEY`, `HMAC_SECRET` or `CLOUDINARY_API_SECRET`, and the web
job's bundle scan gained a `TERMII_API_KEY` pattern. Both were checked in **both**
directions — silent on the fixed tree, and firing when the pre-fix files are restored.
The first attempt at the source gate was silently blind: its comment filter matched the
`//` inside `https://`, so it could not see the very endpoint it existed to find.

**Still open, and deliberately not fixed here.** `DURESS_PIN`/`SAFE_PIN` remain
build-time constants shared by every install, so they are still extractable. Per-user,
server-verified PINs are a product change — new schema, new verification flow, migration
for existing users — not a defect patch. The dangerous part (a duress PIN silently
defaulting to `9999`, a value published in this repository) is fixed; the shared-constant
design is not.

### H-4. Hardcoded HMAC shared secret

`lib/services/hmac_service.dart:6` —
`dotenv.env['HMAC_SECRET'] ?? 'RAINBOW_PLATEAU_SECURE_HMAC_GATEWAY_KEY_2026'`.
If the env var is absent the app silently signs with a secret that is in public source
control, so signatures prove nothing. Note also that a client-held HMAC key is
extractable in principle (see H-3) — this scheme cannot provide integrity against a
malicious client regardless.

**Fix:** Remove the fallback and fail closed. Re-scope what HMAC is meant to protect; if
it is request integrity, enforce it server-side against a key the client never holds.

**Update — the scheme was never running.** The first fix removed the fallback so
`generateSignature` throws when unconfigured. Tracing call sites for H-3 then showed
`HmacService.generateSignature` has **zero callers** anywhere in `lib/` or `test/`.
Nothing in this app has ever signed anything; the "HMAC gateway" is decoration.

That reframes the finding. The original risk was not that signatures could be forged —
it was that a reviewer reading `hmac_service.dart` would conclude request integrity was
handled. It was not, and no amount of fixing the fallback would have made it so.

The service is deleted and `HMAC_SECRET` is out of `AppConfig.requiredKeys`. Demanding a
secret at startup for a scheme that does not execute trains operators to dismiss the
config warning, which is how a genuinely missing key gets ignored later.

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

> **⚠️ The first fix was incomplete, and the way it failed is the point.**
>
> A later audit pass found **`android/GoogleService-Info1.plist` still tracked**,
> carrying `AIzaSyAUP9lvAX…` — a **second, different Firebase API key** this report
> never named. The original fix deleted the plist at the repository root and added
> `GoogleService-Info*.plist` to `.gitignore`.
>
> **`.gitignore` does not untrack a file that is already tracked.** The rule made
> the tree *look* clean — `git status` was quiet, the ignore rule was visibly
> present — while the file and its key stayed in the index. Deleting one file and
> adding a pattern felt like completing the task; nothing swept for other copies.
>
> Now `git rm --cached`'d, and rotation applies to this key too.
>
> A one-time cleanup cannot prevent this recurring, so the **`tracked-secrets` CI
> job** now scans every tracked file for credential-shaped material. Known legacy
> files carry a documented allowlist that may only shrink, and the job fails if an
> allowlist entry goes stale. Verified in both directions: silent on the current
> tree, and it catches the plist the moment it is re-added.

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

### H-9. Gemini API key inlined into the client bundle — ✅ fixed

**File:** `hq-dashboard-next/src/app/dashboard/page.tsx:426, 2160`

Found on a later audit pass, not in the original sweep.

```ts
'use client';
...
const apiKey = process.env.NEXT_PUBLIC_GEMINI_API_KEY || '';
const res = await fetch(
  `https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash-latest:generateContent?key=${apiKey}`, ...
```

`NEXT_PUBLIC_*` is **inlined into the client bundle at build time**, and this is a
`'use client'` component, so any deployment that actually set the variable served
a billable Google credential to every dashboard visitor. The key also travelled in
the **URL query string**, which additionally deposits it in browser history,
`Referer` headers, and any intermediate proxy or CDN log.

This is C-1's defect class — a server credential reaching the browser. It differs
in one respect that made it easy to miss: **nobody hardcoded a literal.** C-1 was
found by grepping the built bundle for a key that was sitting in the source. Here
the source is clean; the leak materialises only in a deployment where the variable
is set. Nothing in the repository, and nothing in CI (where the variable is unset),
would ever have shown it. It was found by asking a different question — *which
environment variables does the code read, and is each one safe to be public?* —
rather than by searching for known-bad strings.

**Fixed.** `POST /api/ai/analyze` holds `GEMINI_API_KEY` (no `NEXT_PUBLIC_` prefix)
and requires a command role. As with the SOS SMS route, it is not an authenticated
proxy: the client sends an **alert id and which of the two analyses it wants**, and
the server fetches that row and composes the prompt itself. No prompt text leaves
the browser, so there is no path to arbitrary billable generation. The key is sent
as an `x-goog-api-key` header rather than a query parameter.

Behaviour is preserved: the triage feature's rule-based fallback still covers the
unconfigured, failed and transport-error cases, and an unconfigured deployment now
returns an explicit `UNCONFIGURED` status so "AI is off" is distinguishable from
"AI broke" — which the old client code could not tell apart.

**Verified.** Built with a real-shaped key set (`AIzaSy…`): the bundle is clean of
`AIza[A-Za-z0-9_-]{20,}` and of the key itself. Mutation-checked by reintroducing
the defect — the scan catches it in `.next/static/chunks/`. Note that the
`GEMINI_API_KEY` *name* pattern does **not** fire, because Next.js replaces the
whole `process.env.X` expression with the literal and the name disappears; the
value pattern is the one doing the work.

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

> **⚠️ Escalated — see [C-6](#c-6-two-unauthenticated-cloud-functions-can-inject-false-emergencies--if-they-are-still-deployed).**
> Calling this "dead code" was wrong. It is dead *in this repository*; whether it is
> dead *in production* is a separate question nobody has asked. `functions/index.js`
> exposes two unauthenticated public HTTP endpoints running with admin privileges,
> one of which injects `DURESS`-flagged emergencies. **Do not delete this directory
> until the deployment has been checked** — the source is the only remaining record
> of what that backend exposes, and deleting it first destroys the list of function
> names needed to audit the console.
>
> The rest of M-7 (legacy `hq-dashboard/`, root scripts) is genuine cleanup and
> carries no such risk.
>
> **`hq-dashboard-next/verify-system.js` is deleted.** It bills itself as the
> "Comprehensive E2E System Verification Suite" and is worse than the audit first
> recorded. Two independent reasons it verifies nothing:
>
> 1. It drives Firebase — `httpsCallable('adminEscalateAlert')` — against a backend
>    the app no longer uses, so even a green run says nothing about the live system.
> 2. Line 7 is `require("/Users/mac/RainBow/scripts/node_modules/firebase-admin")`,
>    an absolute path on one developer's laptop. **It cannot execute anywhere else
>    at all** — it throws on `require` before reaching a single assertion.
>
> Nothing references it. Same class of defect as `HmacService` (H-4) and the
> `analyze` gate that was `continue-on-error`: something that reads as a safety net
> and is not one. Those are the most expensive defects in this codebase, because
> they are the reason nobody went looking.

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

## Status as of PR #1

Everything below was executed, not asserted. Flutter 3.47.0 — the version CI
uses — is installed locally, so the Dart results are reproducible with
`export PATH="/opt/flutter/bin:$PATH"` and do not depend on CI.

### Now executed (was "not run")

| Check | Result |
|---|---|
| `flutter analyze` | ✅ **0 errors, 0 warnings** (was 39 errors / 54 warnings) — **warnings now blocking**; 9 info rules promoted to `error`; 551 infos remain behind three documented exemptions |
| `flutter test` | ✅ **77 passed, 0 skipped** (was 51 passed, 1 skipped) |
| `tsc --noEmit` | ✅ pass |
| `eslint` | ✅ **0 errors**, 15 warnings (was 21 errors) |
| `next build` | ✅ pass (previously failed outright) |
| Client bundle secret scan | ✅ no service_role key, no demo password |
| `/dashboard` + forged cookie | ✅ 307 → /login (was 200) |
| Unauthenticated API POST | ✅ 401 (was 200, executed) |
| RLS anon probe | ⏸ not run — needs `STAGING_SUPABASE_*` secrets |

The original claim that the mobile suite could not be run is **superseded**.

> **A note on CI — most likely exhausted Actions minutes, not a platform outage.**
>
> Every job since 2026-08-13 15:17Z fails in 1-3 seconds with `runner_id: 0`,
> `runner_name: ""`, zero steps, and logs returning 404. The red checks on PR #1
> carry no information about the diff, so everything in the table above was
> verified locally against the toolchain versions CI pins.
>
> The run history pins the transition to a **three-minute window**:
>
> | Run | Time | Runner | Outcome |
> |---|---|---|---|
> | `dae0268` attempt 1 | 15:11:59Z | `1000002594` / `1000002595`, full step lists, 2m22s | real run — web job **passed**, Flutter job genuinely failed on a pending-timer assertion |
> | `ba81f15` attempt 2 | 15:17:05Z | `0`, no steps, 2s | never started |
>
> Everything after 15:17Z matches the second row, unchanged across 22 hours, five
> re-run attempts, both `push` and `pull_request` events, and every job in the
> workflow — including two jobs that did not exist when it began.
>
> **This repository is private**, so every runner minute bills against the account
> quota. Runs that execute normally and then switch, at a moment, to being created
> and instantly failed with no runner assigned is the signature of exhausted
> included minutes or a reached spending limit. A platform-wide Actions outage
> lasting 22 hours would be extraordinary; a billing block lasting 22 hours is
> simply what happens until someone changes a setting.
>
> **Not confirmed.** This audit cannot read the account's billing page, and
> `githubstatus.com` is unreachable from this environment, so the platform-outage
> explanation is not formally excluded — the inference rests on the timing, the
> duration, and the fact that re-running changes nothing. Check
> **Settings → Billing and plans → Actions usage / Spending limit** first.

### Finding status

| # | Finding | Status |
|---|---|---|
| C-1 | service_role key in public bundle | ✅ fixed + CI regression guard |
| C-2 | forged `__session` cookie bypass | ✅ fixed, verified by probe |
| C-3 | RLS `USING (true)` | ⚠️ **migration written, NOT RUN** — step-by-step in `docs/APPLYING_THE_MIGRATIONS.md` |
| C-4 | unauthenticated API routes | ⚠️ fixed in code, **depends on C-3** |
| C-5 | SOS reported at fabricated location | ✅ fixed, both layers + schema migration |
| H-1 | `next build` failed | ✅ fixed |
| H-2 | demo password on public login page | ✅ fixed |
| H-4 | hardcoded HMAC fallback secret | ✅ fixed — service had **zero callers**, deleted |
| H-5 | Cloudinary dead signed-upload path | ✅ removed |
| H-8 | fresh clone cannot build | ✅ `.env.example` added for both apps |
| M-2 | no mocking framework | ✅ `mocktail` + `sqflite_common_ffi` added |
| M-4 | no CI | ✅ `.github/workflows/ci.yml` |
| M-8 | ESLint errors | ✅ 21 → 0; **ratchet completed 2026-09-02** — both hooks rules are `error` project-wide with **no allowlist at all**; all 8 sites across 6 files fixed behind characterisation tests |
| M-9 | 500 on malformed JSON | ✅ 400 |
| M-1 | skipped smoke test | ✅ un-skipped; suite has 0 skips |
| M-5 | `deploy.sh` broken three ways | ✅ rewritten; validates env, scans the bundle, fails loudly |
| M-6 | committed `node_modules` | ✅ untracked; 19,000 → 378 tracked files |
| M-10 | Leaflet from a CDN | ✅ bundled locally (it was fetching JS, not just CSS) |
| H-6 | committed secrets | ✅ **history purged 2026-09-02** — every leaked value redacted from every commit, secret files and all `node_modules` removed; a normal clone now carries **0** credential-shaped blobs. Residual: GitHub's own `refs/pull/*` still hold the old commits until Support purges them — and **rotation is still required** |
| H-7 | role source user-writable | ⚠️ fixed by the C-3 migration's trigger — **lands when C-3 is run** |
| H-3 | `.env` bundled into the APK | ✅ server secrets removed + 2 CI gates; **shared PIN constants remain** |
| H-9 | Gemini key inlined into the client bundle | ✅ moved to `/api/ai/analyze`; `AIza…` added to the bundle scan |
| M-3 | shallow tier E2E | ✅ replaced with mutation-tested tier assertions |
| — | notification tap navigated nowhere | ✅ **fixed 2026-09-02** — see the post-audit findings; was dead in three independent ways |
| M-7 | dead Firebase stack | ⏳ open — confirmed dead (zero callers in either client); **still do not delete `functions/` before the deployment is checked** |
| — | CSP `script-src` carried `'unsafe-inline'` | ✅ **fixed 2026-09-02** — nonce-based via `proxy.ts`; injected script now provably blocked, and the authenticated map page finally exercised under the policy |
| **C-6** | **unauthenticated Cloud Functions** | 🔴 **still unknown — both probe routes blocked from the audit container; stack confirmed orphaned and the guards undeployable. See the investigation note.** |
| — | per-user server-verified duress PIN | ✅ **fixed 2026-09-02** — `emergency_pins` table nobody can read, bcrypt via pgcrypto, lockout after 5, `resolve_emergency` RPC records who resolved; no PIN material on the device at all |

### Found only after the audit, by adding coverage

Two defects that static review missed and running the code caught:

* **Offline SOS replay dropped GPS coordinates.** `flushOfflineQueue` read
  `row['latitude']`/`row['longitude']`; the schema stores `lat`/`lng`. Every
  alert queued while offline reached HQ with null coordinates. ✅ fixed, with a
  real-SQLite regression test.
* **C-5**, above.
* **Tier scoping failed open when the session could not be read.**
  `AuthService.currentUserId` catches every error and returns null. The
  responder dashboard's filter then evaluated
  `alert['assignedToUid'] == uid` — which with a null `uid` is `null == null`
  for any alert carrying no assignee, returning **true** and waving that row
  past all LGA/ward/PU scoping below it. A transient auth read failure would
  have shown every responder every alert in the state. The same trap sat in
  `_MissionCard`, where it highlighted every unassigned alert as the officer's
  own. ✅ fixed by guarding on `uid != null`, with mutation-verified widget
  tests.

* **Clustering can hide a live incident behind another one.** ✅ **Fixed
  2026-09-02, both halves.** The merged card now carries `member_ids`, and every
  write path — resolve, dispatch, escalate, HQ override, from the card and from
  the map popup — acts on all of them, so acting on the card can no longer
  close one report while its siblings stay open and invisible. Escalation
  writes one row at a time so each report keeps its own log. And the key
  finally has the temporal half its name claimed: reports further apart than
  `CLUSTER_WINDOW_MS` (60 min) are different events and no longer merge.
  Mutation-verified — removing the window fails a test; acting on the first
  member only fails two.

  *As originally found:* The HQ board
  folds active alerts sharing LGA + ward + polling unit + type into a single
  card carrying a `witness_count`. For many people reporting one riot that is
  exactly right. But the surviving card keeps the FIRST report's **id**, so
  dispatching or resolving it acts on that row alone — the others stay open and
  are no longer visible anywhere on the board. Two genuinely separate incidents
  that happen to share those four fields therefore collapse, and one can be
  closed without ever being seen. Severity does travel upward (a DURESS member
  promotes the card), so the board will not understate urgency — but it will
  understate *count*. ⏳ open — the fix is to carry the member ids on the
  cluster and act on all of them, which is a behavioural decision about what
  "resolve" means for a group. Pinned by tests in
  `src/lib/alert-display.test.ts` so the current behaviour is at least explicit.

* **...and every voice recording and scene video, via a different directive.**
  🔴 Found and fixed 2026-09-02, immediately after the photo bug and by
  following the same question one step further. Evidence media rides the SAME
  Supabase Storage origin, but `<audio src>` and `<video src>` are governed by
  `media-src`, which the policy did not contain at all — so it fell back to
  `default-src 'self'` and both were refused. Fixing `img-src` did nothing for
  them. A duress voice recording is often the only account of what happened;
  silently refusing to play it is the worst form of this bug. Confirmed in a
  browser before and after. The CI assertion now loops over BOTH directives,
  and fails if either is missing entirely rather than merely wrong.
  
  `LiveFeedViewer` is unaffected: it attaches a MediaStream through
  `srcObject`, which CSP does not govern.

* **The strict CSP silently blocked every incident evidence photo.** 🔴 Found
  and fixed 2026-09-02, and introduced by the nonce-based policy in the same
  session. Evidence — scene photos taken by responders and citizens — is
  uploaded to Supabase Storage and rendered straight from its public URL, but
  `img-src` allowed only `'self' data: blob:` and the two map-tile hosts. The
  Supabase origin was present in `connect-src`, which is what made this easy to
  miss: images are governed by `img-src` alone, so the data loaded and the
  pictures did not.
  
  The failure is invisible by construction — the console renders the incident
  with a blank space, and an operator reviewing a report cannot tell a blocked
  photo from one that was never taken. Confirmed in a real browser (`Refused to
  load the image ...`) before and after the fix, and a CI assertion now checks
  `img-src` carries the Supabase origin, mutation-verified.
  
  Worth noting how it surfaced: not from reading the policy, but from asking
  where the `<img>` tags behind four lint warnings actually pointed.

* **Tapping an emergency push notification navigated nowhere.** Found by a
  lint (`use_setters_to_change_properties` pointing at a setter with no
  callers), and broken three separate ways at once: the
  `GlobalKey<NavigatorState>` it routed through was never assigned by anything;
  it called `Navigator.pushNamed`, but this app routes with go_router via
  `MaterialApp.router`, which registers no named routes at all; and it passed
  only `{'alertId': id}` while the mission-intel route reads the FULL alert row
  from `extra` — type, severity, description, coordinates, media. Any one alone
  would have made the tap useless. ✅ fixed: the id is now resolved into the
  real row and opened through the router, falling back to the responder's
  dashboard when the row cannot be read. Mutation-verified — restoring the
  original id-only behaviour fails three tests.

  It was originally deferred as "needs a device to verify". A device is needed
  to confirm the notification *arrives*; it was never needed to test what
  happens when it does, which is the part that was broken.

* **A failed read renders as "nothing here" in two admin panels.** ✅ **Fixed
  2026-09-02.** `AgencyAccessManager` now reports a failed read as a failure —
  a `role="alert"` panel with the error and a RETRY — never as "No agency
  liaisons registered"; and a failed *refresh* keeps the last good roster on
  screen, marked stale, rather than blanking it. Mutation-verified: restoring
  the empty-on-error behaviour fails three tests.

  *As originally found:*
  `AgencyAccessManager` sets its liaison list to `[]` when the query fails, so
  a permissions error or a dropped connection displays "No agency liaisons
  registered" — a claim the panel cannot support. `AdminDirectory` had the same
  shape and was fixed in passing (its loader now returns null and leaves the
  roster alone). AgencyAccessManager's behaviour was **deliberately preserved**
  during the lint refactor rather than changed silently: it needs an error
  state in the UI, which is a design decision, not a lint fix. ⏳ open, low
  severity — these are admin screens, not the responder feed, but it is the
  same "absence reads as an answer" family as C-5 and the ALL CLEAR bug.

All three came from adding *positive-path* coverage. The pre-existing tests
passed only through error branches, which is why none showed up sooner — and
the tier-scoping bug specifically could not be caught at all until widget tests
could render a populated alert list (see below).

### The console had no unit tests, so its lint ratchet could not be cleared

`react-hooks/set-state-in-effect` was `error` project-wide with a six-file
allowlist. The allowlist existed for an honest reason: clearing it means
restructuring data loading in components that dispatch responders, and the
dashboard had **no unit test framework at all** — only `verify-web-routes.js`,
which drives a browser and can tell you a page returned 200, not whether a
panel silently stopped refreshing.

vitest + Testing Library were added, and each of the eight sites was fixed
behind characterisation tests written against the ORIGINAL code first, so the
tests describe behaviour that had to survive rather than behaviour invented to
match the result. 33 tests now cover panels that previously had none.

Two of the fixes are worth noting beyond the lint:

* **AgencyPortal** kept five untagged lists plus a `loading` flag. A slow
  response for a previously-selected agency could land after a switch and
  render POLICE incidents under the ARMY heading. The data is now one snapshot
  tagged with the agency it belongs to, `loading` is derived from whether that
  tag matches, and late responses are discarded.
* **The theme** was read from `localStorage` in a mount effect, so the console
  rendered light and then corrected itself. It is now a `useSyncExternalStore`
  hook with a server snapshot — right on the first paint, no hydration
  mismatch.

**A wrong assumption, corrected.** LiveMap was nearly left as a permanent
exception on the grounds that Leaflet needs real layout and so could not be
unit tested. That was wrong. Leaflet runs under jsdom once `matchMedia`,
`ResizeObserver` and element dimensions are stubbed. Without the dimension
stubs the map initialises but its marker pane stays empty — a map that looks
fine and shows no incidents, which is the exact failure the tests now guard.
With coverage in place the readiness signal was modelled as what it is (an
external system, via `useSyncExternalStore`) and the allowlist was deleted
outright.

A CI step asserts the allowlist has not returned. That needs to be separate
from the lint step: re-adding an allowlist downgrades an error to a warning, so
`npx eslint` still exits 0 and would not notice. Mutation-verified both ways.

### H-6, closed: the leaked material is out of git history

Executed 2026-09-02 with `git filter-repo`, after a full rehearsal on a
throwaway mirror. The rehearsal earned its keep: it showed the 20-character
citation of the Supabase key being redacted *before* the full 41-character
value, leaving a 21-character tail behind that the verification regex could not
see. The real run orders replacements longest-first and additionally hunts for
every secret's suffix.

**What was rewritten:** six distinct secret values (two Firebase API keys, the
Supabase secret-class key and its citations) redacted to `***REMOVED-SECRET***`
in every blob and every commit message; the two `GoogleService-Info` plists,
`hq-002-auth.json` and `hq-dashboard/dist/` removed from every commit; every
`node_modules` directory ever committed removed (which is where the
third-party test private keys lived). Verified before pushing: 0 blobs matching
the credential regex, 0 blobs containing any secret suffix, 0 `node_modules`
objects, and the rewritten `main` identical in content to the original except
for the seven files carrying a redaction. All three branches force-pushed;
verified again from a fresh clone of the remote.

**What a normal clone gets now:** 129 commits, ~34 MB (was ~95 MB), **zero**
credential-shaped material anywhere in history.

**What remains, precisely — and is not mine to fix:**

* GitHub's server-managed `refs/pull/*` (19 of them) still point at the
  pre-rewrite commits: 152 old commits stay reachable through them, and
  through direct commit-SHA URLs, until GitHub Support runs its
  "remove sensitive data" process. Those refs cannot be pushed to or deleted
  from outside; the attempt is recorded below. **Open a support request
  citing this repository.**
* **Rotate every leaked credential.** A purge protects future clones; it does
  not un-leak a key that was pushed to a remote. Both Firebase API keys and the
  Supabase secret key are compromised until rotated.
* **Every existing clone must be re-cloned.** Every SHA changed. Commit
  references in this report from before this point (e.g. `25ca6b4`) are
  pre-rewrite SHAs and no longer resolve.
* A backup of the untouched history exists **only** as a local bundle in the
  audit environment's scratch space — deliberately never pushed anywhere, since
  a backup on the same remote would defeat the purge.

The `tracked-secrets` CI gate no longer has an allowlist: the six files that
were exempted carry `***REMOVED-SECRET***` now, so any match is a new leak.

### The duress PIN was a shared constant inside the APK — now per-user, server-verified

`SAFE_PIN` and `DURESS_PIN` lived in `.env`, which `pubspec.yaml` declares as a
Flutter **asset**: shipped verbatim in every build, identical for every install,
extractable with `unzip`. A duress code a captor can look up is worse than
none — it tells them which code not to let the victim enter.

✅ **Fixed 2026-09-02** (`supabase/migrations/20260902000000_per_user_emergency_pins.sql`):

* Each user sets their own safe and duress PINs (4–8 digits, must differ), at
  onboarding and under Settings → Emergency PIN. Only bcrypt hashes are stored
  (pgcrypto, cost 10), in `emergency_pins` — RLS enabled with **no policies**
  and all API-role privileges revoked, so nothing can read it through
  PostgREST, its owner included. Asserted in the harness.
* Verification is server-side only. `resolve_emergency(alert, pin)` checks the
  PIN and closes the alert in one call, writing `resolved_by`/`resolved_at` —
  the follow-up the RLS migration's own comment asked for. Five wrong guesses
  lock entry for fifteen minutes; a *correct* PIN does nothing while locked.
  Only the reporter or the assigned responder can close an alert this way.
* The device holds no PIN material. `AppConfig.requiredKeys` is now empty, and
  a regression test asserts neither name can return.
* The screen treats the safe and duress outcomes identically — the point of a
  duress code — with one invisible difference: tracking keeps running under
  duress so HQ can follow. Mutation-verified (making duress stop tracking
  fails the test).

**Offline:** verification needs the server. This is not a regression — the old
client-side check also awaited a database update and returned false when it
failed, so an offline cancellation already did not succeed. What changed is
that nothing PIN-shaped exists on the device to extract.

**Not applied to production**, like C-3: the migration is proven against a
real PostgreSQL in CI on every push (twelve behavioural assertions, run
transactionally so the harness is idempotent). It ships with the RLS migration.

### The last unverified CSP path, closed by removing the dependency

A general browser sweep of the console reported zero violations of any
directive — but `font-src`/`style-src` were unproven rather than confirmed,
because the audit environment has no egress to Google Fonts and so the webfont
was never even requested. The same condition was a live deployment risk:
`globals.css` pulled Inter and Outfit at runtime with `@import url(...)`, and on
a restricted government network — the scenario that made Leaflet-from-unpkg a
finding (M-10) — every label silently fell back to a system font. The Flutter
web target had already been fixed for exactly this (`build_web.sh` bundles its
resources); the console never was.

✅ **Fixed 2026-09-02.** Both typefaces are now self-hosted through
`next/font/local` (`src/app/fonts.ts`), using the same SIL-OFL files the mobile
app ships in `assets/google_fonts/`, converted to WOFF2 (2.1 MB of TTF → 755 KB).
`next/font/google` was deliberately not used: it downloads at *build* time,
which only moves the network dependency from the browser to CI. The two Google
hosts are gone from the policy entirely — `font-src 'self' data:`,
`style-src 'self' 'unsafe-inline'` — and a browser check now proves the fonts
load with no request leaving the origin. Two CI gates hold it: the policy may
not name a Google Fonts host, and source may not reference one outside a
comment. Both mutation-verified.

That closes the sweep: every directive in the policy has now been exercised in
a browser, not just read.

### Widget tests could not render any screen that touches the database

`Supabase.instance` asserts that `initialize` has run, and that assertion fires
during `build()`. So any widget reaching for the client — an alert card, the
mission list, the map — could not be built in a widget test at all. Whole
screens were untestable, and the gap was invisible: tests that only ever
reached empty states passed happily, because they never built the widgets that
touch the client.

`SupabaseConfig.client` is the single path to the client anywhere in `lib/`
(all 84 call sites go through it), so one `@visibleForTesting` seam on that
getter opens every screen to testing without threading a client through the
codebase. `test/support/offline_supabase.dart` installs a **real**
`SupabaseClient` over a mock HTTP transport — keeping the genuine query
builders and types, faking only the wire. Realtime is deliberately made to
throw rather than open a socket, because a real WebSocket attempt leaves a
pending timer and *hangs* the test rather than failing it.

A CI step bans the seam from `lib/`, and asserts it still exists — a static
mutable holding the whole app's database access must never be reachable from
production code.

### `flutter analyze` is now a blocking gate

`analysis_options.yaml` promotes three lint rules to error severity
(`unawaited_futures`, `discarded_futures`, `avoid_dynamic_calls`). Those produced
39 error-severity findings across ~12 feature screens, so the job originally ran
`continue-on-error` — a gate that can never pass gets ignored.

All 39 are cleared and `continue-on-error` is gone: any new error-severity lint
now fails the build. Infos and warnings stay non-fatal (830 remain: line length,
directive ordering, unused test imports). Ratchet documented in the workflow:
clear the warnings, drop `--no-fatal-warnings`; then the infos, then
`--no-fatal-infos`.

### Still requires someone with production access

0. **`firebase functions:list --project rainbow-97f1e`** — do this first; it is two
   minutes and it is the only way to settle C-6. Both routes to an answer from the
   audit container are closed (see the C-6 investigation note above): the egress
   policy refuses `cloudfunctions.net`, and there are no GCP credentials here for
   the admin API. If `smsWebhook` or `seedMockData` is listed, an unauthenticated
   stranger can inject `DURESS`-flagged emergencies into your alert store today.

   **Do not `curl` `seedMockData` to find out whether it exists.** The pre-guard
   version has no method check — the probe itself would write ten fabricated
   emergencies. Use the list command, or, if you only have a shell, probe
   `smsWebhook` instead, which is inert on anything that is not a well-formed
   `POST`:

   ```bash
   # Safe on both the old and the new version: neither writes on this input.
   #   404 → not deployed
   #   200 "Format ignored."      → OLD, UNGUARDED code is live — treat as urgent
   #   503 "Gateway not configured." / 401 → the guarded version is live
   curl -s -o /dev/stdout -w '\nHTTP %{http_code}\n' \
     -X POST -H 'Content-Type: application/json' -d '{"Body":"probe"}' \
     https://us-central1-rainbow-97f1e.cloudfunctions.net/smsWebhook
   ```

   Then delete the deployment. Nothing in either client calls any of these 25
   functions — no Firebase package in `pubspec.yaml`, no `httpsCallable` anywhere —
   so deletion is the remediation, not deployment of the guards, which in any case
   have no route to production while `firebase.json` is missing:

   ```bash
   firebase functions:delete smsWebhook seedMockData --project rainbow-97f1e --force
   # then the remaining 23, once you have confirmed no external caller:
   #   adminDispatchAlert adminEscalateAlert adminResolveAlert agentUpdateMissionStatus
   #   approveAppUninstall calculateSafetyIndex createAlert escalateTask
   #   escalationWatchdog findBestResponders getETA logAlertChanges massBroadcast
   #   migrateLegacyIncidents onAlertCreatedGIS processAudioIncidentReport
   #   pruneTrackingPaths requestAppUninstall syncUserCustomClaims
   #   triageAndCreateVoiceAlert triggerSLASweep validateAgentAccessCode
   #   validateRemovalCode
   ```

   Delete the deployment before deleting `functions/` — the source is the last
   written record of what that backend exposes.
1. **Rotate credentials** — service_role, Firebase, Cloudinary, Termii, and the
   `HQ-001`/`HQ-002`/`COMMANDER-TEST` passwords. The code holes are shut; the
   leaked credentials are still live.
2. **Run the RLS migration on staging, then `node scripts/verify_rls.js`.**
   Written from this repo's migration files, not a live `pg_policies` dump, so
   hand-created dashboard policies will not be dropped. Not on production until
   staging is green.
3. **Review Supabase logs** for prior anonymous reads of `profiles` and `telemetry`.

---

## Production-readiness pass

The findings above are about code that was wrong. This pass asked a different
question — *if you deployed this today, what would fail?* — and found four
things, three of which are invisible until the moment they matter.

### The console's backend was never in the repository

Four tables the HQ console reads and writes every session — `agency_personnel`,
`agency_deployments`, `agency_action_reports`, `agency_notifications` — plus
`profiles.agency`, were created by hand in the Supabase dashboard. No migration
in this repository creates them.

Two consequences. A staging or disaster-recovery project rebuilt from these
files silently lacks the entire agency portal; you find out when a commander
opens the tab. And the RLS migration's agency section was written `GUARDED BY
EXISTENCE` for exactly that reason, so on every database CI could build, that
section was **skipped** — the agency policies were the only part of the C-3
remediation that had never once been executed before reaching production.

`20260812000000_agency_tables.sql` creates them, dated before the RLS migration
so the policies now apply on every database. Every statement is
`IF NOT EXISTS`, so on production it changes nothing and keeps production's
column shapes.

Writing that section down also exposed that it was **wrong**. It granted reads
to `is_staff()` and writes to `is_command()`. But the people who use the agency
portal are agency liaisons, who carry role `<AGENCY>_LIAISON` — neither command
nor citizen. Under those policies a police liaison could read *every* agency's
personnel, deployments and after-action reports, and write none of their own:
the portal was simultaneously too open and non-functional for its only users.

It is now: command sees everything; a liaison sees and writes only rows tagged
with their own agency; responders and citizens see nothing. The agency is taken
from `role` and not from `profiles.agency` — that column is self-writable, and a
liaison who could rewrite it could read another agency's deployments. There is
an assertion for precisely that.

### Three realtime subscriptions were never going to fire

The console subscribes to `postgres_changes` on `agency_action_reports`,
`agency_deployments` and `uninstall_requests`. None of the three was ever added
to the `supabase_realtime` publication.

A subscription on an unpublished table does not error. It connects, reports
success, and never delivers an event. The HQ unread-report badge — the thing
that tells command an agency has filed a report from the field — only updated on
a page reload, and nothing anywhere said so.

`20260903000000_realtime_publication.sql` adds them, and a CI gate now extracts
every table either app subscribes to (the console's `table: '…'` and the mobile
app's `from('…').stream(…)`, which is the same mechanism) and fails if one is
missing from that migration. Adding a subscription without publishing the table
is now a build failure rather than a silent dead channel.

### The evidence bucket had no policies in the repository

Both apps upload incident photos, video and voice reports to the Supabase
Storage bucket `incident-media` when Cloudinary is unavailable. Nothing in this
repository created that bucket or a single policy on `storage.objects`. Storage
RLS is deny-all without policies, so on a fresh project every fallback upload
fails; on production, whatever was clicked together in the dashboard was
undocumented and unreviewed.

`20260903000001_incident_media_storage.sql` sets it explicitly: any signed-in
user may upload (the reporter is usually a citizen), **nobody may update or
delete through the API roles** — evidence is append-only, and removal is a
service-role operation — and only staff may list the bucket. Public does not
mean enumerable: an object is readable by its URL, but handing anyone with the
anon key a directory of every piece of incident evidence is a different thing
entirely.

Residual: the bucket is public, so an object URL is unguessable but not secret.
A private bucket with signed URLs is stronger and needs every media renderer in
both apps changed first.

### The Android release build could not succeed on a clean checkout

`android/app/build.gradle.kts` applied `com.google.gms.google-services` while
`pubspec.yaml` carried no Firebase dependency at all. That plugin fails the
build outright when `android/app/google-services.json` is missing — and that
file is gitignored, because it holds an API key. So `flutter build apk
--release` could not work on a CI runner, a new laptop, or anywhere the file had
not been copied in by hand. The plugin is removed from both Gradle files, the
four `GoogleService-Info.plist` references are removed from the Xcode project,
and a CI gate keeps both out. **Not build-verified here** — this container has
no Android SDK; the gate is static.

Two related things, found while looking: `android/GoogleService-Info1.plist` was
still present in the working tree (untracked, so the tracked-secrets gate could
not see it) and is deleted. And release signing reads `key.properties` from the
repo root; if it is absent the signing config is left with null fields and the
build produces an **unsigned** artifact — no fallback to the debug key, no
warning. That is documented in the deployment runbook rather than changed,
because failing the build there would break `flutter build apk --debug` too.

### What this pass added to CI

* `20260812000000_agency_tables.sql` applied strictly (not best-effort) in the
  migration harness, so the agency policies are now exercised.
* `scripts/production_readiness_behaviour_test.sql` — 18 assertions covering
  agency access by role, cross-agency isolation, that `profiles.agency` grants
  nothing, the realtime publication, and the storage bucket's append-only
  behaviour. Both new migrations are applied twice in the harness to prove
  idempotence.
* A Supabase Storage shim in `scripts/test_rls_migration.sql` so the storage
  policies run against a real PostgreSQL.
* The realtime-subscription gate described above, and the Firebase-config gate.

Mutation-checked: reverting the agency policies to the command-only version
fails the behaviour test at the first liaison insert.

### Deployment

`docs/PRODUCTION_DEPLOYMENT.md` is new: rotation table, the five migrations in
order, the fact that **no deploy target is configured in this repository**
(`deploy.sh` runs `firebase deploy` and there is no `firebase.json`,
`apphosting.yaml` or `vercel.json` — it fails hard rather than pretending), the
console's build-time environment, mobile signing and versioning, and what to
check after the first deploy.

---

## The console had no error boundary

Continuing the production-readiness pass, and the same failure mode as the
mission-feed liveness fix, one layer up.

`hq-dashboard-next/src/app` had no `error.tsx`, no `global-error.tsx` and no
`not-found.tsx`. In production Next.js renders its own blank page for an
uncaught render error, so any crash anywhere in the 3,000-line dashboard tree —
a malformed alert row, a Leaflet failure, a null in a deeply nested card — took
out the entire board and left the operator looking at nothing.

On an emergency console, nothing is the most dangerous thing to draw. **A blank
board and a board with nothing to report are the same picture**, and at 3am the
second reading is the one that gets taken. That is precisely the defect that was
fixed on the mobile side, where a dead alerts stream used to render ALL CLEAR.

Three boundaries now exist, sharing one `ConsoleFailure` panel:

| File | Catches |
|---|---|
| `app/dashboard/error.tsx` | anything in the operations board — the one that matters, and the only one that can genuinely recover |
| `app/error.tsx` | login and any route added later that forgets its own |
| `app/global-error.tsx` | a crash in the ROOT LAYOUT, which `error.tsx` cannot catch |

The panel is loud, says CONSOLE FAILED, and — before any technical detail —
states that incidents may be arriving unseen, that the board should be treated
as offline, and that radio is the fallback. It also says the recorded data is
intact, so nobody re-reports incidents that were already logged. It carries
`role="alert"` with `aria-live="assertive"`, so it interrupts rather than
waiting to be noticed.

It shows `error.digest` and never `error.message`. Next replaces the message
with a generic string in production specifically so internals do not reach a
screen other people may be standing behind; rendering it anyway would undo
that. The digest is what makes a fault report actionable.

Recovery uses `unstable_retry()`, which is this Next version's replacement for
`reset()` (16.2.0+). The difference matters here: `reset()` only clears the
error state without re-fetching, so on a data-driven board it usually crashes
straight back; `unstable_retry()` re-fetches and re-renders the segment, so a
transient Supabase or map failure clears without the operator losing their
place. A plain reload is always offered as well.

`not-found.tsx` is deliberately plain and deliberately *not* the crash screen. A
mistyped URL is not an incident, and dressing it in the same red panel would
train operators to ignore the one that matters.

Seven tests cover it, and they are about the property rather than the markup:
softening the panel into "Nothing to display right now" and downgrading
`role="alert"` fails two of them.

### Two things found on the way

**A stale CI guard was pinning seven files in existence.** When the
tracked-secrets allowlist was removed, the loop that checked *the allowlist for
stale entries* was left behind. It asserted that seven named files still exist —
including two in the legacy console — so deleting any of them failed the build
with `Allowlist entry '…' no longer exists — remove it from the ALLOW pattern`,
naming a pattern that no longer exists. Removed.

**The legacy Vite console is deleted** (`hq-dashboard/`, 13 files). It is
referenced by no build, test or deploy script, and it talks to **Firestore**
directly — `collection(db, 'alerts')`, `collection(db, 'users')` — which is
outside every control the Supabase RLS work put in place. This is the client
half of M-7 and is not gated on C-6: the C-6 hold exists so the *deployed
backend's* source is not destroyed before the deployment is checked, and
`functions/` is untouched for exactly that reason.

That leaves a question worth settling with C-6, and it is a live-access
question rather than a cleanup one: **if the old console is still hosted
anywhere, it is a second door into the data that none of the RLS migration
reaches.** Deleting the source does not take it down. Check for it while you
are in the Firebase console.

---

## Mass broadcast never worked

`system_alerts` is how HQ warns the public and its own responders. It was broken
in four independent ways, and not one of them surfaced as something an operator
would read as failure.

**1. Every insert failed.** `title` is `NOT NULL` with no default, and neither
writer supplied it — not the console's `MassBroadcast.tsx`, not the mobile
`admin_broadcast_screen.dart`. On any database built from these migrations,
every broadcast raised a not-null violation.

**2. Six of the console's columns did not exist.** `target_agency`,
`target_sector`, `target_lga`, `target_ward`, `target_pu` and `active` appear in
no migration in this repository. PostgREST rejects an insert naming an unknown
column outright, so the write failed before the constraint was even reached. The
operator saw a raw PostgREST string where a statewide warning should have been.

**3. Audience targeting was ignored.** The console wrote `target_audience`; the
mobile reader consulted `target_type`, which defaults to `'ALL'`. So a **FIELD
RESPONDERS ONLY** advisory arrived addressed to everyone and was shown to every
citizen — while the console told the operator it had gone to responders only.

**4. Geographic targeting was enforced nowhere.** The console offers LGA, ward
and polling-unit scoping and reports *"dispatched successfully to JOS NORTH
LGA"*. No reader has ever filtered on geography. Every advisory went statewide.

Faults 3 and 4 are the dangerous ones, and they are the same class of defect as
the mission feed rendering ALL CLEAR over a dead stream: **the system reported
success for something it had not done.** A broadcast that fails loudly gets
re-sent by radio. One that reports success while reaching the wrong people does
not — and here that is either a panic pushed to an entire state, or an
evacuation order that never reaches the ward it was written for.

### One name per concept

`lib/core/models/broadcast_alert.dart` already declared `targetLga`,
`targetWard`, `targetPu` and `targetAudience`. The wider design was always the
intended one; only the schema never caught up. So
`20260903000002_system_alerts_broadcast.sql` adds the columns, and the code now
agrees on one name for each thing:

| concept | canonical | note |
|---|---|---|
| audience | `target_audience` | `target_type` still read as a fallback for rows written before this |
| live | `is_active` | the console wrote `active`, which was never a column |
| scope | `target_lga` / `target_ward` / `target_pu` / `target_agency` | new; now enforced on read |
| heading | `title` | still `NOT NULL`, but now has a default, so no writer can fail on it again |

Delivery moved out of a stream `.map()` into `lib/services/broadcast_targeting.dart`
as a pure function, because "who receives this" is the part worth testing
directly. Two judgement calls are recorded in it:

* **Missing recipient geography fails OPEN.** A citizen whose profile has no LGA
  still receives a scoped advisory. A missed evacuation order costs more than an
  irrelevant notification. Every other condition fails closed.
* **An unrecognised audience is treated as ALL**, not dropped. Over-delivery is
  recoverable; an advisory that reaches nobody because of a typo in a dropdown
  is not.

Place names are matched loosely in both directions — "Jos North", "JOS NORTH
LGA", "jos north" are one place — the same rule the HQ board already uses for
alerts. Under-matching is the expensive direction: it drops a warning for
somebody standing in the affected area.

### Also fixed

The console's own `SystemAlertListener` asked for the newest row *full stop* —
no `is_active`, no expiry — so a withdrawn or long-expired advisory stayed
docked under the header indefinitely. An advisory that is no longer true is
worse than none, because operators calibrate against it. Expiry is filtered
client-side on purpose: rows predating the `expires_at` column have it `NULL`,
and `NULL` fails every SQL comparison, so a server-side filter would have
silently hidden exactly the standing advisories that have no end date.

The console also never wrote `expires_at` at all and had no control for it. It
has one now.

### Coverage

* `test/broadcast_targeting_test.dart` — 17 assertions on delivery: audience,
  the legacy-column fallback, geography at three levels, loose place matching,
  fail-open on missing geography, withdrawal and expiry.
* `hq-dashboard-next/src/components/MassBroadcast.test.tsx` — 7 assertions on
  the payload's *shape* against the schema, including that nothing invented is
  sent, since one unknown column rejects the whole insert. Restoring the
  original payload fails 4 of them.
* `scripts/production_readiness_behaviour_test.sql` — the exact console payload
  is inserted against a real PostgreSQL; a titleless insert now succeeds;
  citizens still cannot broadcast, and can still receive. Removing the new
  columns from the migration reproduces the original production error,
  `column "target_agency" of relation "system_alerts" does not exist`.

---

## The same fault, swept for mechanically

The broadcast failure above was found by reading, months after it shipped.
Nothing about it was hard to detect: a column name is either in the schema or it
is not, and both sides live in this repository. So `scripts/check_schema_drift.py`
now extracts every column either app writes — from inline literals and from
payloads built as a variable and passed by name — and compares them against
every `CREATE TABLE` and `ADD COLUMN` in the migrations. It runs in CI.

It found three more, in two different shapes.

### Dead writes, removed

| write | read by | outcome |
|---|---|---|
| `alerts.has_live_stream` | nothing | rejected, and the rejection discarded by `catch (_) {}` |
| `profiles.last_feedback` | nothing | rejected; logged "Safety feedback write failed" for a write that had in fact succeeded |

Both are gone rather than given columns. Adding a column would only have made a
write that changes nothing succeed. The live-stream flag in particular gated
nothing: the console renders `LiveFeedViewer` for whichever incident is open,
without consulting it. If HQ should be able to see which incidents have a live
stream, that is a feature to build deliberately — the column alone would not
have given it to anyone.

Removing the first left `stopStream([String? alertId])` with a parameter that
did nothing while every caller dutifully passed one, which reads as though
teardown were scoped to that alert. It is not; the parameter is gone too.

The `safety_feedback_dialog` case had a second-order effect worth naming. The
profile write ran *after* the alert write in the same `try`, so the alert
feedback was recorded, the block then threw, and the operator-facing log said
the write had failed. A log that reports failure for a success is its own defect.

### Real columns missing from the repository

`alerts.escalated_to_agency` and `alerts.escalation_log` are a different case:
both are **read**, and the agency portal's entire incident feed is
`.eq('escalated_to_agency', agency)`. They are production columns added by hand
and never written down — the same drift that left the four `agency_*` tables
out. On a replica rebuilt from these files, escalation failed *in full*:
PostgREST rejects an update naming an unknown column outright, so the status,
severity, assignment and audit note went down with it.
`20260903000003_alert_escalation_columns.sql` adds them, with `escalation_log`
defaulting to `[]` — both writers read the array back and append to it, and a
NULL default would silently drop the history on first escalation.

Recorded but not changed: **the two writers disagree about what
`escalated_to_agency` holds.** The console writes an agency (`POLICE`), which is
what the portal filters on; the mobile agent dashboard writes a *tier* (`HQ`,
`LGA`) — its own comment says "tier label for filtering". A mobile escalation is
therefore invisible to every agency portal, though it still shows as ESCALATED
on the HQ board. That is a semantic collision in one column rather than a schema
fault, and narrowing it belongs with whoever owns the escalation model.

### The checker under-reported, and that was the point

Its first version understood only inline object literals, so it gave the console
a clean bill of health — the mass-broadcast payload is built as a `const` and
passed by name, which is exactly the shape of the bug it exists to catch. Its
second version then reported `alerts.escalated_to_agency` while missing
`alerts.escalation_log` four lines below it, because a `//` comment sat between
the two entries and the key pattern anchors on the preceding comma.

Both are fixed, and both are recorded in the script, because a gate that
under-reports is worse than no gate: it converts "nobody has checked" into
"something checked and found nothing". Re-introducing a bad column in either
language now fails the build.

### Coverage

Three new assertions in `scripts/production_readiness_behaviour_test.sql`: the
escalation update applies, `escalation_log` appends rather than replaces, and an
escalated incident is visible under the agency filter the portal uses.


---

## The CRITICAL filter, and a claim I got wrong

While sweeping the read side, `alerts.priority` looked like a live defect:
`filterAlerts` and `clusterAlerts` both tested `alert.priority === 'CRITICAL'`,
and **nothing in either codebase writes `priority` to the database** — the
mobile maps its priority enum onto `severity`
(`'severity': priority.name.toUpperCase()`) and the console's own writes set
`severity` too. On that evidence the board's CRITICAL filter appeared to match
only DURESS alerts.

It does not. `dashboard/page.tsx:537` copies the field across as rows load —
`priority: d.severity || 'HIGH'` — and that page is the only caller of either
function. **The filter works today.** The earlier claim here was wrong and is
withdrawn.

What is real is thinner, and still worth closing:

* **The coupling is invisible from the module.** `alert-display.ts` is exported
  and unit-tested on its own, with nothing in it saying the caller must map
  `severity` onto `priority` two hundred lines away. A second caller passing
  rows straight from the database gets a CRITICAL filter that silently matches
  only DURESS. `isCriticalAlert()` now reads both fields, so the module is
  correct on its own terms.

* **Reading `severity` alone would have been a regression**, which is worth
  recording because it was the first attempt. `clusterAlerts` promotes a card by
  setting `priority = 'CRITICAL'`; a severity-first rule let a MEDIUM severity
  mask that and dropped promoted clusters out of the filter — caught by two
  pre-existing tests. Either field saying CRITICAL is now enough. On a filter
  whose job is to surface the worst incidents, showing one too many costs a
  glance and dropping one costs more.

* **Cluster promotion set only `priority`.** The list read CRITICAL and the
  opened card read whatever the first report said. Both fields are promoted now.

* **`/api/ai/analyze` selected `priority` explicitly.** PostgREST rejects a
  select naming an unknown column in full, so on a database without it the
  triage endpoint returned 400 for every incident. Dropped from the select; the
  prompt already falls back to `a.severity || a.priority`.

Five tests cover it, including the shape the hidden coupling would have dropped
— a row with `severity` set and no `priority`. Reverting to the priority-only
check fails three; dropping the severity half of cluster promotion fails one.

Noted, not changed: `priority: d.severity || 'HIGH'` invents a severity for a
row that has none. HIGH over-states rather than under-states, so it fails safe,
but it is the same species as the invented coordinates in C-5 and should
eventually read as UNKNOWN.
