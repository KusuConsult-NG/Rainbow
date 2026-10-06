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
exposes **unauthenticated** public HTTP endpoints running with admin
privileges, one of which injects `DURESS`-flagged emergencies. Whether that is a
live hole or a non-issue depends entirely on whether those functions are still
deployed — a two-minute check that needs the Firebase console.

This is a public-safety / emergency-response system handling location data for
people in danger. **Recommendation: treat the current Supabase project as
compromised, rotate all keys, and do not deploy until C-1 through C-4 are fixed.**

**Current position:** C-1, C-2, C-4 and C-5 are fixed and verified. **Two need a
human, for different reasons.**

**C-3 is CLOSED, on the live database, 2026-09-28.** All fourteen outstanding
migrations were applied to the production Supabase project and its own verification
reported **25/25 PASS**. The permissive policy set is gone: 44 policies became 29,
and `no policy grants anon or public anything` passes.

What that run closed, measured on the real database rather than argued from the
migration text:

| was true before | now |
|---|---|
| any citizen could `update profiles set role='ADMIN' where id=auth.uid()` and become HQ | `profiles_no_privilege_escalation` blocks it |
| any authenticated account could update **any** alert — resolve somebody else's emergency | responders only |
| every signed-in account could read every citizen's live GPS, kept forever | only while that citizen has an open emergency, purged after 24h |
| every alert, profile and incident chat readable by every account | scoped |
| any account could write the four agency tables | scoped |
| `app_config` readable by `anon` | scoped |

The database was empty when this ran — zero users, zero alerts — so none of the
above was ever exploited. It was applied before the first citizen existed, which is
the only comfortable time to do it.

Also now live: the command chain's timeouts, which had been *configured and dead*
since the beginning (`rainbow-escalate-overdue`, every minute), the telemetry purge,
and the mesh envelope purge. All three confirmed active in `cron.job`.

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

### C-6. A whole second backend may still be deployed — unauthenticated, admin-privileged, and writing to a database nothing reads

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

**Deleting `functions/` does not undeploy anything.**

If these were ever pushed to `rainbow-97f1e` they are serving right now, and the
watchdog is running every five minutes. `pubspec.yaml` has no Firebase
dependency and no file under `lib/` or `hq-dashboard-next/src/` imports Firebase,
which is exactly why nobody would think to look.

**Correction, 2026-10-06 — the severity above is overstated, and the reason
matters.** This section describes `seedMockData` as "a one-request
false-emergency injector" and `smsWebhook` as giving "attribution and dispatch,
both attacker-controlled". Both write to **Firestore**. A sweep of the shipping
code on 2026-10-06 found **thirteen** mentions of Firebase or Firestore across
all of `lib/` and `hq-dashboard-next/src/`, every one of them a comment, and
**no `import` of Firebase anywhere**. Neither manifest declares the dependency.

So nothing reads the database these functions write to. Fabricated alerts would
land in a collection no app and no console queries: no responder is dispatched,
no operator sees them, nothing appears on the board. The same applies to
`validateAgentAccessCode` — it mints accounts in *Firebase Auth*, which nothing
authenticates against any more. The attacker-controlled dispatch described above
dispatches into a void.

What is still genuinely true, and is the actual reason to finish this:

* **Cost.** Publicly invokable endpoints in a billed project, plus a `pubsub`
  watchdog on `every 5 minutes` running forever. `seedMockData` writes ten
  documents per request to anyone who asks.
* **Data at rest.** If these functions ever ran against real traffic, Firestore
  holds a copy of citizen reports — locations, and possibly duress events —
  under rules `admin.initializeApp()` bypasses entirely. That exposure does not
  depend on anyone reading it.
* **It is unmonitored.** Nobody is watching logs for a backend everyone believes
  is gone.

That makes this **cleanup with a privacy and billing tail, not a live hole in
the running system**. It was ranked alongside the published staff password
(T-20) and the SMS blocker (T-18); it does not belong there. One
`gcloud functions list` and, if anything is listed, one `gcloud functions
delete` closes it whenever someone is next at a terminal.

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


#### Enumeration, 2026-10-06 — it is FOUR unauthenticated endpoints, not two, and the C-6 fix closed the wrong two

The deployment state is still unknown; both routes above are still closed
(re-checked today: the proxy answers `403` to the `CONNECT` for
`cloudfunctions.net`, and there is no Firebase or gcloud CLI and no credential
in the container). What changed is the source analysis. `functions/index.js` was
recovered from git — it is deleted from the working tree but intact at
`c66fc0f^` — and every export enumerated rather than only the two that were
originally read.

**25 exports.** 3 `https.onRequest`, 15 `https.onCall`, 2 `pubsub.schedule`,
4 `firestore` triggers, 1 `tasks.taskQueue`. The original write-up looked at
`onRequest` only. That was the mistake: **a callable is also a public HTTPS
endpoint.** `functions.https.onCall` does not authenticate anything by itself —
it decodes a Firebase Auth token *if one is sent* and leaves `context.auth`
undefined if not. Unless the handler checks it, the function is open.

Four do not check it:

| export | kind | what it does with no credential |
|---|---|---|
| `smsWebhook` | onRequest | hardened by `b2df3fd` — now requires `X-Rainbow-Gateway-Auth` |
| `seedMockData` | onRequest | hardened by `b2df3fd` — now requires `RAINBOW_ALLOW_SEED=true` **and** `X-Rainbow-Seed-Auth` |
| **`validateAgentAccessCode`** | **onCall** | **never hardened — see below** |
| **`triggerSLASweep`** | **onCall** | **never hardened** — iterates every alert with status OPEN or ACTIVE and escalates each one a tier. Anyone who can reach the endpoint can force a mass escalation of every open incident in the state, notifying responders for all of them. Its default thresholds are 2/4/6 minutes, commented "for rapid testing" |

`b2df3fd` is the commit titled *"C-6: make the legacy Firebase endpoints fail
closed, and prove it"*. It touched `smsWebhook` and `seedMockData` and **zero
lines** of the other two — verified by diff. The remediation was scoped to the
finding instead of to the class, and the finding had enumerated one trigger type.

#### `validateAgentAccessCode` is an unauthenticated staff-account factory

This is the worst thing in the file and it was not in the original write-up.
Unauthenticated — `context` is never consulted. Given an access code it:

* creates or updates a Firebase Auth user `agent_<badgeId>`;
* sets its password to **`${accessCode.toUpperCase()}_sec_${new Date().getFullYear()}`**;
* sets custom claims `role`, `lga`, `ward`, `pu`, `badgeId` and **`isStaff: true`**;
* writes a `users` document with `isVerified: true`;
* and **returns the email and password to the caller** —
  `return { success: true, fallbackAuth: true, email, password }`.

Three consequences, none of which need a credential:

1. **The password is derivable without calling anything.** Anyone who sees an
   access code — on paper, in a screenshot, forwarded in a chat — can compute
   `CODE_sec_2026` and sign in as that agent. The code *is* the password.
2. **It is account takeover, repeatedly.** For a uid that already exists it calls
   `updateUser(uid, { password })`, so holding an agent's code lets you reset
   that agent's password at will, including after they change it.
3. **It is a brute-force oracle.** Invalid, already-used and expired codes each
   throw a *different* message, with no `context.auth`, no App Check and no rate
   limit — so the endpoint grades guesses for you.

`createAlert`, by contrast, calls `verifyRequestAuthenticity(data, context)` and
then checks `context.auth` explicitly. The protection existed in the file; these
four exports simply never got it.

#### What to run, and what the answer means

Still two minutes with credentials. The full export list is needed because the
original one named eight:

```bash
firebase functions:list --project rainbow-97f1e
# or, without the Firebase CLI:
gcloud functions list --project rainbow-97f1e
```

Being *listed* is not the same as being *reachable*. This is the check that
distinguishes them — a Cloud Function is public only if `allUsers` holds the
invoker role:

```bash
gcloud functions get-iam-policy validateAgentAccessCode \
  --project rainbow-97f1e --region us-central1
# allUsers + roles/cloudfunctions.invoker  =  reachable by anyone on the internet
```

And if anything is listed, the deployed code is **whatever was last pushed**,
which may predate `b2df3fd` — hardening the source no more changes a deployment
than deleting it does. Assume the unhardened `smsWebhook` and `seedMockData`
until the deployed version is known.

The remedy is deletion, not hardening: there is no `functions/` directory left
to patch, and nothing in either app has called any of this since the move to
Supabase.

```bash
firebase functions:delete smsWebhook seedMockData validateAgentAccessCode \
  triggerSLASweep escalationWatchdog --project rainbow-97f1e
```

`escalationWatchdog` is in that list because it is the `every 5 minutes`
schedule: it is not reachable from outside, but it is the one that keeps running
on its own and writing to a datastore nothing backs.

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

> **⚠️ Escalated — see [C-6](#c-6-a-whole-second-backend-may-still-be-deployed--unauthenticated-admin-privileged-and-writing-to-a-database-nothing-reads).**
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

## Status as of PR #69 (2026-10-06)

> Was "as of PR #1" until 2026-10-06, fifty-three merges later. Four rows below
> were materially wrong by then — C-3 read **NOT RUN** after it had been applied
> to production, and C-4 and H-7 read as waiting on it. Anyone reading this
> document for the system's security posture got a picture a month out of date,
> which is worse than no document. The newer findings are in
> [What the next fifty merges found](#what-the-next-fifty-merges-found).

Everything below was executed, not asserted. Flutter 3.47.0 — the version CI
uses — is installed locally, so the Dart results are reproducible with
`export PATH="/opt/flutter/bin:$PATH"` and do not depend on CI.

### Now executed (was "not run")

| Check | Result |
|---|---|
| `flutter analyze` | ✅ **0 errors, 0 warnings** (was 39 errors / 54 warnings) — **warnings now blocking**; 9 info rules promoted to `error`; 551 infos remain behind three documented exemptions |
| `flutter test` | ✅ **571 passed** as of 2026-10-06 (was 77 at PR #1; 51 passed / 1 skipped at audit) |
| `tsc --noEmit` | ✅ pass |
| `vitest` (HQ console) | ✅ **654 passed**, 5 skipped — the console had no test suite at audit |
| SQL behaviour harness | ✅ green against real PostgreSQL 16 — `scripts/verify_rls_migration.sh`, 238+ assertions |
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
| C-3 | RLS `USING (true)` | ✅ **applied to production** (2026-09-28, 25/25 PASS; re-verified 2026-10-05 — the dry run reports SAFE TO APPLY and anon is refused on profiles, telemetry and alerts). One policy escaped it: see T-1 below |
| C-4 | unauthenticated API routes | ✅ fixed in code, and C-3 is now applied, so no longer conditional |
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
| H-7 | role source user-writable | ✅ landed — C-3 is applied and the live verdict table reports `PASS role-escalation trigger installed` |
| H-3 | `.env` bundled into the APK | ✅ server secrets removed + 2 CI gates; **shared PIN constants remain** |
| H-9 | Gemini key inlined into the client bundle | ✅ moved to `/api/ai/analyze`; `AIza…` added to the bundle scan |
| M-3 | shallow tier E2E | ✅ replaced with mutation-tested tier assertions |
| — | notification tap navigated nowhere | ✅ **fixed 2026-09-02** — see the post-audit findings; was dead in three independent ways |
| M-7 | dead Firebase stack | ⏳ **partially closed.** The repository no longer carries any Firebase config: `firebase.json`, `.firebaserc` and `apphosting.yaml` were removed with the move to Railway (PR #53), the `firebase` npm dependency is gone, and `functions/` is not in the tree. The **deployment** is still unconfirmed — `firebase functions:list --project rainbow-97f1e` is the one command that settles it. Do not `curl` `seedMockData`: the probe writes ten fabricated emergencies |
| — | CSP `script-src` carried `'unsafe-inline'` | ✅ **fixed 2026-09-02** — nonce-based via `proxy.ts`; injected script now provably blocked, and the authenticated map page finally exercised under the policy |
| **C-6** | **unauthenticated Cloud Functions** | 🔴 **still unknown, and the scope was wrong: FOUR unauthenticated endpoints, not two.** `b2df3fd` hardened the two that had been enumerated and never touched `validateAgentAccessCode` — an unauthenticated staff-account factory that returns working credentials and derives the password from the access code — or `triggerSLASweep`. Deployment state remains unverifiable from here: no Google credential, neither CLI installed, and the environment's network policy denies `us-central1-rainbow-97f1e.cloudfunctions.net` (403 on CONNECT), which blocks even the unauthenticated existence probe. **Downgraded to 🟠 on 2026-10-06**: every one of these writes to Firestore, and nothing in the shipping code reads it, so the fabricated dispatch lands in a void. See the correction under C-6. |
| — | per-user server-verified duress PIN | ✅ **fixed 2026-09-02** — `emergency_pins` table nobody can read, bcrypt via pgcrypto, lockout after 5, `resolve_emergency` RPC records who resolved; no PIN material on the device at all |

## What the next fifty merges found

Everything above is the audit and the work to PR #1. What follows was found
between PR #2 and PR #54, almost all of it by **running the system against a
real PostgreSQL and a real browser** rather than by reading it. They are
numbered separately (T-n, "after the audit") so the original findings keep their
identifiers.

Each one is recorded with what it would have done in use, because that is the
only thing that distinguishes a defect from a preference.

### Safety and truthfulness of what the console says

| # | Finding | Status |
|---|---|---|
| T-1 | **`telemetry_select_geo_lga_scoped` was `TO PUBLIC` on production.** `20260725` created it with no `TO` clause; PostgreSQL records that as `TO PUBLIC`, and PUBLIC includes `anon`. `20260813` drops prior policies by exact name and could not drop this one — it predates the file. `telemetry` is where citizens' positions are written. Nothing leaked: the policy's own qualifier requires `authenticated` and `20260813` separately revokes anon's table privileges — but the policy layer was relying on the layer beneath it, one `GRANT` away. | ✅ fixed, `20261016000000`; the harness now also asserts this **after the full replay**, and plants a `TO PUBLIC` policy to prove the assertion can fail |
| T-2 | **The console reported "ALL SECTORS CLEAR" when the read had been refused.** `fetchAlertsData` destructured `{ data, count }` and never looked at `error`. A refused read returns `data: null`, which skipped the mapping block and left `alerts` empty — rendering an affirmative claim about the safety of Plateau State. An empty table and a refusal were indistinguishable. Two more paths made the same claim: filters hiding every loaded row, and the situational feed's "NO ACTIVE THREATS". | ✅ fixed — three distinct states (`FEED UNAVAILABLE`, `NO MATCH FOR THESE FILTERS`, genuine all-clear), 18 tests, and an exhaustive check that all-clear is unreachable for any state carrying an error or a loaded row |
| T-3 | **Four Mangu wards had no supervision.** The app writes `GINDIRI  I` from the GPS asset; officers are posted from the tactical map as `GINDIRI  1`. Compared as raw strings, so for every incident in those wards RLS refused it to the ward commander whose command it was in — read *and* write — the ward filter could not select it, and `escalation_push_targets()` found nobody. Nothing errored; the ward simply had no supervision. | ✅ fixed with a comparison key (`public.geo_key()` plus mirrors in TS and Dart), not a rename — both spellings are already in the database |
| T-4 | **An SOS with no GPS appeared in the list and nowhere on the map.** The C-5 fix correctly stopped fabricating a location, but left USSD and no-fix reports undrawable. | ✅ `locateIncident()` draws GPS / ward / LGA at the precision actually known, and `isSendable()` is true only for a real fix — a circle is not a destination |
| T-5 | **The map's info card blinked on every refresh.** `Marker.setIcon` replaces the DOM element and re-binds the popup; `Popup.setContent` reuses the node but destroys its children. Both fired on data the operator had not changed. | ✅ fixed by tracking what each marker and area was drawn from; the regression tests watch `firstElementChild` identity, because node identity cannot see `setContent` |
| T-6 | **Evidence captured after a report was filed could be lost.** The media append was read-modify-write, so two concurrent attachments dropped one. | ✅ `append_alert_media()` — one locked statement, `FOR UPDATE`, dedupe by `min(ord)`; plus a single-flight pending-evidence flush that drops a path only on confirmation |
| T-7 | **`APPLY AI CLASSIFICATION` applied no classification** and marked the incident `DISPATCHED` with no assignee. The forensic AI summary lived only in React state and was never persisted, so there was nowhere for an admin to see a report that had been generated. | ✅ `applyTriage()` applies it; `incident_ai_reports` keeps it, readable by command and **not** by the reporter — an early version admitted the reporter via `alert_is_ours()`, which would have shown a citizen the forensic debrief of their own kidnapping |
| T-8 | **A complaint against security personnel routed to the officer complained about.** `Police brutality` is a reportable category and escalated like a flood: to the local ward, the local LGA, and every responder posted there, with the complainant's number on the dossier. | ✅ `route_oversight_to_hq()` sends it to HQ on arrival and clears any assignment; it is held out of the escalation ladder entirely, because every rung is closer to the accused |

### Things that were green and should not have been

| # | Finding | Status |
|---|---|---|
| T-9 | **Push notifications sent the same credential under two different schemes** across three call sites — `Basic` twice, `Key` once — so at least one had never authenticated. The one most likely to be broken reported `success: true` without looking at `response.ok`, so a 401 read as *N* notifications delivered. A CI gate added for it found a **fourth** call site on its first run. | ✅ one module, retries the other scheme once on 401/403, and never reports ok for a non-2xx |
| T-10 | **All five generated operator SQL scripts were a day stale**, including the one a person pastes into a production SQL editor — missing eleven migrations. Regenerating produced a script that *did not work*: the generators had silently absorbed the hand-applied v2–v5 era, one of which calls `auth.jwt()` before it exists. | ✅ one exclusion list (`scripts/migration_sets.py`) instead of four copies, asserted in both directions |
| T-11 | **Two complete deploy configurations, both documented as live**, for a month: Firebase App Hosting and Railway. `deploy.sh` pushed to the one that had been abandoned. A stale console answering requests is indistinguishable from a deploy that worked. | ✅ Railway only; `scripts/check_one_deploy_target.py` fails CI on a second target |
| T-12 | **`verify_apply_all.sh` and `verify_bootstrap.sh` reported success over SQL errors.** psql runs without `ON_ERROR_STOP` and the files are not single transactions, so a statement could fail, the rest succeed, the verdict print 33/33 PASS, and the process exit 0. Both scripts only looked for `ERROR` when the exit code was non-zero. | ✅ both now fail on an error anywhere in the buffer; the bootstrap also fails on zero passes, which is the shape of a rolled-back run |
| T-13 | **`supabase/rainbow_full_migration.sql` applied `phase1_foundation` twenty-one sections after the least-privilege migration**, re-creating seven `TO PUBLIC` policies on `chat_messages`, `telemetry`, `safe_zones` and `uninstall_requests`. | ✅ reordered; `migration_sets.py --assert-coverage` refuses any bundle that applies phase1 after `20260813`, and fired on the real file before the fix |
| T-14 | **The repository and production had different schemas.** The v2–v6 era was applied by hand and cannot be replayed, so no database this repository could build had `alerts.lga/ward/pu`, `profiles.lga/ward/sector_id`, `normalise_lga()`, the `updated_at` trigger, or the telemetry policy. It decided a 428C9 column name, hid T-1 from a passing assertion, and put a **wrong conclusion into a code comment** in `dashboard/page.tsx` — which stated three columns do not exist when all three do on production. | ✅ `20261017000000` brings the behaviour-affecting objects into the history; `scripts/check_schema_convergence.py` keeps them there, with two unreferenced v5 functions recorded as known differences rather than propagated |
| T-15 | **Adding a Dart comment above a ward's `id:` silently removed that ward from the generated tactical map.** The sync script's regex was not comment-tolerant and reported no error. | ✅ regexes fixed and a 207-ward count assertion added |
| T-16 | **The demonstration seed used invented geography** — "Bokkos Central", "Mangu Central" — which exist in no INEC ward list and in neither of the project's own files. Rows that look right and behave wrong: unselectable by the ward filter, refused by RLS to the commander whose area they were in. | ✅ real INEC names; `sync_tactical_map.py --check` fails CI on any place the seed names that the map lacks. The three genuinely orphaned wards (BWALL, DAMWAI, KADUNU) were resolved against INEC sources, not guessed |

### T-20. One published password for every staff account — LIVE, not legacy

Found on 2026-10-06 while answering "rotate the access codes". It is the most
serious thing in this document that was still live when it was found, and it is
in the **current Supabase system**, not the orphaned Firebase stack.

`AuthService.signInWithAccessCode(code)` did this:

```dart
final agentPass = dotenv.env['AGENT_DEFAULT_PASS'] ?? '';
return signInWithBadge('$code@operationrainbow.plateau.gov.ng', agentPass);
```

Three facts, each individually known and documented, which had not been put
together:

1. `pubspec.yaml` declares `.env` as a **Flutter asset** (line 80). H-3 already
   established what that means: the file ships verbatim inside the APK and
   extracts with `unzip`.
2. `.env` carried `AGENT_DEFAULT_PASS` — **one password, shared by every staff
   account**.
3. The "access code" was only the email local-part. It is a **username**.

So the access code was never the secret. Anyone with the APK — which is to say
anyone who has been given the app — could read the shared password, and sign in
as any officer whose badge or code they knew or could guess. `login_screen.dart`
routed every non-phone input straight down that path, and **there was no
password field on the login screen at all**.

This is why "rotate the access codes" does not fix it. Rotating them changes the
usernames and leaves the one password readable in every copy of the app ever
distributed.

**Fixed:**

* `signInWithAccessCode` is deleted. Staff authenticate with
  `signInWithBadge(badgeOrEmail, password)` and their own password.
* The login screen has a password step — a non-phone identifier now reveals an
  obscured field and signs in only when it is filled. 7 widget tests, with the
  first one mutation-checked: restoring the old one-shared-password behaviour
  fails it.
* `AGENT_DEFAULT_PASS` is gone from `app_config.dart` and from `.env.example`,
  and so is `DEMO_CITIZEN_PASS`.
* A failed sign-in says `BADGE OR PASSWORD NOT RECOGNISED` rather than naming
  which half was wrong — otherwise the screen is a roster of who works here.

**The CI gate that existed for this class did not cover it.** The H-3 guard
scanned `lib/` and `.env.example` for a *list of names* —
`TERMII_API_KEY|CLOUDINARY_API_SECRET|HMAC_SECRET` — so a shared credential
under a different name passed. It now fails on any name in the mobile template
matching `PASS|PASSWORD|PIN|SECRET|TOKEN`, with **no exclusions**: the two that
used to need one, `DURESS_PIN` and `SAFE_PIN`, are already gone, replaced by the
per-user `emergency_pins` table. Naming the shapes instead of the names is the
difference between a gate and a list.

**Still to do, and it needs doing:** every existing staff password must be
rotated, because the one they shared is in every copy of the app.
`scripts/rotate_staff_passwords.js` does it through the Supabase admin API —
dry-run by default, 24 random bytes per account, touches only profiles whose
role is staff, and continues past a failure while naming every account it could
not rotate, because stopping early leaves the rest on the published password.
Officers then need their new passwords out of band.

### T-21. The "which migrations are applied?" diagnostic told the operator to undo the fix

Found on 2026-10-06 from a pasted run of `scripts/which_migrations_are_applied.sql`
that ended `every object in every migration exists — nothing to apply`. The
database it ran against was missing three migrations.

Two separate faults, and the reassuring output is what both produced.

**It was three migrations stale, because its own staleness gate was never
wired.** The file is generated by `scripts/sync_migration_inventory.py`, whose
docstring says `--check` in CI is what keeps it honest. It was not in CI. The
`dryrun-fresh` job regenerates five operator scripts and diffs them, and this
was the one left out of the `GEN` list. So the inventory covered 32 migrations
while the repository had 35, and reported a clean bill of health for a schema it
had never heard of — the exact failure a staleness check exists to prevent. Both
doors are shut now: the file is in the diff list, and `--check` runs as a step
of its own.

**It asserted existence only, which made it dangerous about the one migration
that removes things.** `20261018000000` drops the five generated `geo_*` mirrors
and two dead v5 functions. All seven were must-be-present rows inherited from
v2 and v5, so the moment an operator applied that migration the diagnostic would
have reported **seven missing objects** and named
`20260721000000_v2_agency_tables` and `20260724000000_v5_rls_security` as the
files to apply. Applying those recreates the mirrors — putting back the ordinal
divergence that made one bad INSERT report `lga` on production and `category` in
the harness (C-4). The diagnostic would have walked the operator into undoing
the migration they had just applied, and the instruction would have looked
routine.

A drop-only migration was also invisible, since it creates nothing to count.
Objects a later migration removes are now **must-be-absent** assertions filed
against the migration that removes them, so it reads `0 of 7 removed — NEVER
APPLIED` before and `7 of 7 removed` after. That is the only way this script can
answer "did it land?" for such a file, and it is how the question that found
this gets answered.

**Seven migrations were invisible, not three.** Rebuilding it surfaced five more
the diagnostic silently omitted: `20260812000000_agency_tables`,
`20260903000000_realtime_publication`, `20260903000001_incident_media_storage`,
`20260903000003_alert_escalation_columns` and
`20260927000000_signup_cannot_choose_role`. Object existence genuinely cannot
see them — one creates only policies, one creates no object at all, and the rest
are no-ops on a database that already has what they declare. They now appear
under a `not detectable` section naming the reason, so a clean report is no
longer read as proof they were applied. The object count is unchanged at 123
(116 must exist, 7 must be gone), which is how I know the rebuild moved rows
rather than losing any.

`verify_rls_migration.sh` asserts the drops after the full replay and then
**plants all seven back** and requires the diagnostic to name every one and flip
to `NEVER APPLIED` — the same self-proving shape as the planted `TO PUBLIC`
policy probe. Stripping the must-be-absent rows from the generated file takes
the planted run from 7 named objects to 0, and the probe fails, which is what
that probe is for. `DROPPED_BY_LATER` now lives in one module, and the
generator refuses to emit anything if an entry names a migration that does not
exist or an object no migration creates — either of which would make the
assertion vacuous while looking like a check.

### T-22. A pasted script carried nothing saying which version it was

Found on 2026-10-06 from a pasted verdict table whose only failing row read
`*** FAIL *** | no policy grants anon or public anything` — naming no policy.
That check has named the offender since PR #50; the paste came from a working
copy predating it, which cost a round trip to establish what the output already
knew. Verified on PostgreSQL 16.13: against a clean schema the current check
returns `PASS`, and with the policy live as `TO PUBLIC` it returns
`*** FAIL *** ... — telemetry.telemetry_select_geo_lga_scoped`.

That is the second stale paste in two turns — T-21 was an inventory three
migrations behind that reported "nothing to apply" — and in both cases nothing
in the output identified its own version. The verdict table of
`apply_all_migrations.sql`, `bootstrap_staging.sql` and
`scripts/apply_in_parts/32_VERIFY.sql` now opens with a row that is not a check:

```
 PASS   | script version: 31 outstanding migrations, fingerprint f57e16f5be90
```

Compared against `python3 scripts/migration_sets.py --fingerprint`. Hashed over
the migration file names and contents, never the clock — a timestamp would
change on every regeneration and make CI's generated-file diff fail for no
reason. Confirmed idempotent across a re-run of all six generators, and
confirmed to move when a migration's bytes change.

Four related gaps closed while doing it:

* **The label guard covered one of three paste scripts.** `build_apply_all.py`
  forbids `into`/`from`/`join`/`table` in a label because Supabase's editor
  lints the buffer before running it and reads a relation name after those
  keywords — a label saying "written into your own channel" made it warn about
  a table called `your` and made another path fail `42P01`. My first draft of
  the stamp said "generated from N migrations" and that guard caught it, which
  is the guard working. `bootstrap_staging.sql` and `apply_in_parts/` are pasted
  into the same editor and had no guard at all. It now lives in
  `scripts/label_guard.py` and both builders call it.
* **`scripts/apply_in_parts/` — 32 tracked files — was outside CI's
  generated-file diff**, so a stale set of parts could be committed unnoticed.
* **`verify_bootstrap.sh` printed a floor as a denominator.** Adding one check
  made it report `20/19 PASS`, a ratio above one, which reads as a defect in the
  thing being verified. The count is derived from the generated file now; 19
  stays as a floor only.
* **The deployment runbook's migration table stopped at `20261001000000`** while
  thirty-one were outstanding — seventeen missing — and its prose still said
  "Fourteen migrations ... a 25-row PASS/FAIL table ... 2,300 lines" for a file
  of 5,935 lines ending in 34 rows. The seventeen rows are written, and
  `scripts/check_runbook_covers_migrations.py` derives the coverage, the order
  and the row-count claim from the migrations while leaving the descriptions
  hand-written, because those say what breaks until each file runs and the SQL
  does not. Five mutations were each caught: a dropped row, a stale row count,
  two files transposed, an emptied description, and a listed file that does not
  exist.

### T-23. A diagnostic from outside the repository reported 24 objects missing. None of them exist.

Found on 2026-10-06 from a pasted migration-status table reporting twenty-four
objects `MISSING from public schema` — among them the three mesh tables, the
emergency-PIN functions and the SMS device-key functions — and concluding that
nine migrations were `NOT APPLIED` or `PARTIAL`.

A verdict table from the same database, pasted beside it, said the opposite:
`emergency PIN functions exist (4)`, `SMS device keys exist and are unreadable
through the API`, `the mesh can recognise the same envelope arriving twice`,
`mesh traffic is not readable through the API`, `a handset can report that its
SMS channel changed`, `a liaison is recognised as an outside agency` — PASS,
every one.

**All twenty-four names appear in no migration in this repository.** They are
near-misses for the real objects:

| it reported missing | what this project actually creates |
|---|---|
| `set_emergency_pin` | `set_emergency_pins` |
| `provision_default_pins_for_existing_users` | — (`has_emergency_pins`, `_check_emergency_pin`, `verify_emergency_pin`, `resolve_emergency`) |
| `profiles.pin_salt`, `.safe_pin_hash`, `.duress_pin_hash`, `.pins_configured` | the `emergency_pins` **table** |
| `mesh_messages`, `mesh_nodes`, `mesh_sync_log` | one table, `mesh_envelopes_seen` |
| `ingest_mesh_message`, `ingest_mesh_batch`, `purge_stale_mesh_data` | `mesh_note_envelope`, `purge_stale_mesh_envelopes` |
| `register_sms_device_key`, `verify_sms_report_signature`, `cleanup_expired_sms_nonces` | `register_sms_device`, `has_sms_device_key`, `revoke_sms_device_keys`, `sms_key_for_ingest` |
| `ingest_sim_event`, `archive_old_sim_events` | `purge_stale_sim_events` + table `sim_channel_events` |
| `is_agency_liaison`, `user_agency_code` | `is_liaison`, `alert_is_ours`, `liaison_agency` |
| `tier_timeout` | `tier_timeout_minutes` |
| `audit_log_authenticated_action` | — (`auth_role`, `is_staff`, `is_command`, `prevent_profile_privilege_escalation`) |
| `handle_new_user_role_safely` | — (the trigger is `profiles_no_privilege_escalation`) |
| `append_alert_media_url`, attributed to `20260903000001_incident_media_storage` | `append_alert_media`, from `20261010000000` — `20260903000001` creates a bucket and policies, no function |
| `alerts.escalated_at`, attributed to `20260903000003` | that migration adds `escalated_to_agency` and `escalation_log`; the timestamps are `tier_assigned_at` / `acknowledged_at` from `20260928000000` |

The PIN row is the giveaway. Those hashes were deliberately moved **off**
`profiles` into their own table precisely so the API roles cannot read them —
that is the `PIN hashes unreadable by the API roles` check. A diagnostic looking
for them as `profiles` columns is describing a schema this project considered
and rejected.

It is also structurally incomplete: it covers 25 of 35 migrations, omitting
`20260812000000`, `20260903000000`, `20260903000002` and every migration from
`20261010000000` onward.

No script in this repository emits that wording, so it was written from memory
of what the schema probably contains rather than extracted from the files —
the same failure recorded inside `check_schema_convergence.py`, whose first
hand-written policy list "invented names and missed real ones". Acting on it
meant re-applying nine already-applied migrations: the T-21 trap arriving from
outside.

`scripts/is_this_object_real.py` is the cheap rebuttal — no database, no
credentials, no network. It takes object names in any of the shapes a pasted
diagnostic uses (`function foo`, `column alerts.bar`, `public.baz`), says which
migration creates each, and for one that does not exist offers the closest real
name. It also distinguishes a third case the claim did not consider: an object a
later migration **drops**, which *should* be absent. It is explicit about what
it cannot tell you — whether the object is in your database, which is
`which_migrations_are_applied.sql`'s job, run against the database.

Both verdict tables in that paste were also still the 33-row version, with no
`script version:` row and a FAIL naming no policy — so T-22's stamp would have
flagged them as stale before any of this was read.

### T-24. Three migrations applied to production and reported nothing an operator could read

Found on 2026-10-06, immediately after `20261016000000`, `20261017000000` and
`20261018000000` were applied to production. All three report what they did with
`RAISE NOTICE`. The Supabase SQL editor discards `NOTICE` output, so the
operator saw three identical `Success. No rows returned` results and had no
evidence any of them had done anything.

`docs/APPLYING_THE_MIGRATIONS.md` had already recorded this — the RLS dry run
signals its verdict by raising an error **because** the editor hides notices —
and I handed over these three telling the operator which notices to watch for.
The same document then contradicted itself twenty lines later by calling a few
`NOTICE: skipping …` lines "expected". Both are fixed: the limitation is stated
where it bites, with `psql` named as the way to read notices.

The 34-row verdict table only half-closes the gap:

* it **does** prove `20261016` landed — the telemetry policy was the only thing
  failing its anon/public check, which turned PASS;
* it **cannot see `20261018` at all**. Not one of its 34 checks looks for the
  absence of the five generated mirrors or the two dropped functions, and
  absence is the only evidence a drop-only migration can leave;
* `20261017` is a no-op on a database that already holds the era objects, which
  production does, so nothing observable changes there by design.

`scripts/did_the_convergence_land.sql` answers it in rows: one statement, three
verdicts plus the generated columns `alerts` now has, which is the column a
428C9 error would name on that database. Each failing row says what the
consequence is rather than only that a check failed.

It is proven able to fail, inside the resume rehearsal added to
`verify_apply_in_parts.sh` the same day (PR #66): asked before the three parts
are applied it must report `20261016` and `20261018` as not applied, and after
them all three as applied.

**Building that exposed a defect in my own rehearsal.** The first version of the
check passed trivially: the fixture replays parts 1–28, the mirrors are created
by part 30, so "all 5 generated mirrors are gone" was already true before
`20261018` ran — true of a database that never had them. The assertion was
therefore testing a condition that could not fail. Production *does* carry those
mirrors, from the hand-applied era, at ordinals 28–30 on `alerts` — which is why
a 428C9 there names `lga` where the harness names `category`. The fixture now
plants the full era residue (five generated mirrors and both v5 functions), and
the before-state correctly reports `20261018` as unapplied. I fixed the fixture
rather than weakening the assertion, because the fixture was the thing that was
wrong.

The honest limit, stated in the file: the `20261017` row cannot distinguish
"applied" from "was already true", because on production it is a no-op. Nothing
can, from the schema alone.

### T-25. The SMS blocker was five dashboard steps with no way to check them

T-18 records the blocker: `signInWithOtp` is refused outright by a project with
no SMS provider, so until one is attached **no citizen can sign in**. PR #59 put
the hook in the repository with 25 unit tests. What was left was five dashboard
settings performed by hand, described in prose, with no way to verify the result
short of asking a real person to request a real code — and a provider that is
configured but broken looks identical to one that is not configured, from every
screen in the app.

`scripts/wire_up_sms_provider.sh` closes both halves.

**`--check` needs no credentials and sends no SMS.** Two unauthenticated
requests to the function's public URL separate the four failure modes, because
this function's own error bodies carry `error.http_code` and the platform's do
not:

| request | answer | meaning |
|---|---|---|
| `GET` | 401 **without** `error.http_code` | the platform refused it: deployed with JWT verification on, so the hook can never reach it |
| `GET` | 405 **with** `error.http_code` | our code answered — deployed correctly |
| `GET` | 404 | not deployed |
| `POST`, bad signature | 503 `hook is not configured` | deployed, secret unset |
| `POST`, bad signature | 503 `old name` | only the legacy `HOOK_SECRET` is set |
| `POST`, bad signature | 401 | secret set and verification works — healthy |
| `POST`, bad signature | 200 | it accepts unsigned requests, which is a hole |

Neither request can send a message: the 405 path returns before reading a body,
and the 401 path fails verification before Termii is called.

**`--commit`** generates the signing secret, stores the three function secrets,
deploys with `--no-verify-jwt`, enables the hook pointed at the function, reads
the configuration back and asserts it, then runs the probes. No secret value is
printed — only length and first characters.

**A step nobody had written down.** `sms_autoconfirm` must be OFF. With it on,
Auth confirms the phone without ever sending a code: the hook never fires, every
other step achieves nothing, and no error appears anywhere. §2b said "enable the
Phone provider" and stopped. `--commit` now sets it false explicitly and the
read-back fails if it is still true.

**What is asserted, and what is honestly not.** The Management API shapes were
checked against the Supabase documentation on 2026-10-06 rather than written
from memory — `hook_send_sms_enabled`, `hook_send_sms_uri`,
`hook_send_sms_secrets`, `sms_autoconfirm` on
`PATCH /v1/projects/{ref}/config/auth`; `POST /v1/projects/{ref}/secrets`
taking `[{name,value}]`; the `v1,whsec_<base64>` secret format; an empty JSON
200 as success. `external_phone_enabled` appears in no documentation I could
confirm, so it is **not** asserted — a guessed field name would fail against a
correctly configured project. The read-back prints every phone/sms/hook field
the API returns, so the real names are visible.

The script also cannot prove Termii will deliver. That needs a real handset and
credit on an approved sender ID, and the file says so rather than implying the
green run means messages arrive.

`scripts/wire_up_sms_provider_test.sh` asserts the classifier against all
thirteen response shapes with no network, and asserts directly that the two
401s do not collapse into one verdict — the distinction the whole diagnostic
rests on. It runs in CI as an ordinary gate.

### T-26. C-6 was ranked as a live security hole. It writes to a database nothing reads.

Found on 2026-10-06 by being asked the obvious question — *why are we still
checking Firebase when we are on Supabase?* — which this report had never
answered properly.

The factual half of C-6 is right: deleting `functions/` does not undeploy
anything, and if those 26 functions were ever pushed to `rainbow-97f1e` they are
serving now with admin credentials. That remains unverified, and the reason is
now precise: no Google credential in the audit container, neither CLI installed,
and the environment's network policy denies
`us-central1-rainbow-97f1e.cloudfunctions.net` with a 403 on CONNECT — which
blocks even the unauthenticated existence probe that needs no credentials at all.

**The severity was wrong.** C-6 described `seedMockData` as "a one-request
false-emergency injector" and `smsWebhook` as giving "attribution and dispatch,
both attacker-controlled". Both write to **Firestore**. Sweeping the shipping
code found **thirteen** mentions of Firebase or Firestore across all of `lib/`
and `hq-dashboard-next/src/` — every one a comment — and **no `import` of
Firebase anywhere**; neither manifest declares the dependency.

Nothing reads that database. Fabricated alerts land in a collection no app and
no console queries: no responder is dispatched, no operator sees them, nothing
reaches the board. `validateAgentAccessCode` mints accounts in Firebase Auth,
which nothing authenticates against. The attacker-controlled dispatch dispatches
into a void.

What survives the correction, and is the real reason to finish it: **cost**
(publicly invokable endpoints in a billed project, plus a `pubsub` watchdog on
`every 5 minutes` forever), **data at rest** (if those functions ever ran against
real traffic, Firestore holds citizen reports, locations and possibly duress
events under rules `admin.initializeApp()` bypasses — an exposure that does not
depend on anyone reading it), and the fact that nobody watches logs for a
backend everyone believes is gone.

So it is cleanup with a privacy and billing tail, not a live hole in the running
system. It had been sitting beside the published staff password (T-20) and the
SMS blocker (T-18), which are different in kind. C-6's heading, its summary rows
and the status table now say so, and the anchor link that pointed at the old
heading was repaired.

The lesson is narrower than "check severity". Every fact in C-6 was correct and
independently verified; the error was in never asking what *reads* the thing
being written to. A finding about a write path is only as severe as its readers,
and nothing in the original analysis looked for them.

### Open, and not closeable from the repository

| # | Finding | Status |
|---|---|---|
| T-17 | **GitHub Actions has not run since 2026-09-29.** Every job in every run completes in about two seconds with `runner_id: 0`, no runner name and no logs — nothing picks the jobs up. Not a failing test: an Actions or billing condition on the account. | 🔴 **open, and now load-bearing.** Moving to Railway removed the one structural protection App Hosting gave (a secret marked RUNTIME-only, absent during `next build`). The CI job that greps `.next/static` for key material is what remains between this deployment and C-1 recurring, and it is switched off. Fifty merges landed with every gate unexercised, which is how T-10, T-11, T-12 and T-13 survived |
| C-6 | an abandoned second backend, if still deployed | 🟠 unchanged, and **downgraded 2026-10-06**: it writes to Firestore, which nothing in the shipping code reads (13 mentions across `lib/` and `hq-dashboard-next/src/`, all comments, no imports). Cleanup with a billing and data-at-rest tail, not a live hole. `gcloud functions list --project rainbow-97f1e` settles it |
| T-18 | **Citizen sign-in has no SMS provider.** `signInWithOtp` is refused outright unless the Supabase project has one, so every citizen sign-in fails. | 🔴 open — a blocker, not a checklist item. `docs/PRODUCTION_DEPLOYMENT.md` §2b |
| T-19 | **One staff account exists**, so dispatch has nobody to send. The nine unacknowledged incidents on the live board are an empty roster, not a broken pipeline. | 🔴 open |

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

---

## The read side drifts too

`check_schema_drift.py` only looked at writes. PostgREST rejects a **select**
naming an unknown column just as completely, so the same fault hides on the
read side — and it was there.

`dashboard/page.tsx` loaded the console's profile map with
`select('id, full_name, role, lga, ward, sector_id')`. None of `lga`, `ward` or
`sector_id` is a column: the schema has `geo_lga`, `geo_ward` and `geo_pu`, and
`sector_id` appears nowhere else in either app. So the query was rejected, the
map stayed empty, and nothing was logged.

What that map does is resolve people. With it empty:

* every officer on the board renders as `TACTICAL SQUAD #A1B2C3` instead of a
  name and badge, and
* every incident dossier shows "Registered Citizen" and **"No Phone
  Registered"** — so HQ cannot ring back the person who raised the SOS.

The select was also missing the fields its own consumers read. `badge_number`,
`email` and `phone` are read off that map in eight places and were never
selected into it, so they were undefined even on the rows that did arrive.
Corrected to `id, full_name, email, phone, role, badge_number, geo_lga,
geo_ward, geo_pu`.

`badge_number` is not in any migration either, and the mobile responder picker
names it explicitly — so on a database without it that query fails outright and
an agent has nobody to dispatch. `20260903000004_profiles_badge_number.sql` adds
it; on production it exists already and the migration is a no-op. It is a label,
not a credential: the login screen derives an email from the badge an operator
types and reads nothing from this column.

### The gate had to be fixed twice more to find this

Extending the checker to selects did not work first time, and both failures are
worth recording because both were the gate lying rather than the code being
clean.

The pattern allowed 300 characters between `from('x')` and `.select(...)`. The
explanatory comment written above the corrected select was longer than that, so
the check passed on code that still had the bug — the comment about the fault
hid the fault. Widening to 2000 then walked past the *next* `from(` and reported
three false positives, blaming `telemetry` and `agency_deployments` for columns
belonging to queries beside them.

A character budget was simply the wrong constraint. The rule is that **no other
`from(` may intervene**, which is now what the patterns say, and comments are
blanked to spaces before matching so they can never hide a call again — spaces,
not deletion, so reported line numbers stay true.

All three detection paths are mutation-checked: a bad select behind a long
comment, a TypeScript payload passed by name, and a Dart inline literal. Each
one fails the gate.

---

## Nothing left on the reader's desk

Three items had been written up as decisions for whoever owns the system. Each
turned out to have a defensible answer, so each is now made.

### The tier had no column, and escalation was failing outright

This was recorded as "a semantic collision, narrowing it belongs with whoever
owns the escalation model". Looking properly, it was not a naming argument. It
was two bugs.

`alerts.assigned_to` is `UUID REFERENCES profiles(id)`. The mobile escalation
wrote `targetCommanderId ?? targetTier` — so whenever the agent did not pick a
specific commander, it sent the string `'LGA'` to a uuid column. PostgreSQL
rejects that, and because the escalation is a single `UPDATE`, **the whole thing
went with it**: status, severity, the escalation log and the audit note. The
agent saw a failure with nothing to indicate the tier was the cause.

The tier was also written into `escalated_to_agency`, which is the column the
agency portal filters on, so an internal escalation to LGA sat in the same field
as a handover to the police.

And the HQ board's tier filter compared `assigned_to` — the uuid column —
against `'WARD'`/`'LGA'`/`'HQ'`. It could only ever have matched rows the
database refuses to store, so **that filter has never selected anything**.

One column per concept now: `assigned_to` is who owns it, `assigned_tier` is
which tier owns it, `escalated_to_agency` is which outside agency it went to.
The migration moves existing tier labels out of the agency column, touching only
values that are unambiguously tiers and leaving real agencies where the portal
expects them. The mobile sends `assigned_to: null` when nobody specific is
taking it, which is the honest answer.

### An ungraded alert is no longer drawn as HIGH

`priority: d.severity || 'HIGH'` invented a severity for a row that has none —
the same move as the fabricated coordinates in C-5, one field over. An alert
nobody had graded was drawn in the same red as one graded HIGH by the person who
reported it, with no way to tell them apart.

It is `UNKNOWN` now: muted, because the colour maps have no entry for it and
fall through to `var(--text-muted)`, and not matched by the CRITICAL filter,
which is correct — we do not know that it is.

### The console has a deploy target

`firebase.json` and `hq-dashboard-next/apphosting.yaml` are in the repository
and `deploy.sh` runs `firebase deploy --only apphosting`. Firebase App Hosting
was chosen because the project already exists (`.firebaserc` → rainbow-97f1e):
it adds no vendor account and no procurement step for a state agency, and
nothing in the application code is Firebase-specific, so the choice is
reversible — the Vercel alternative is one paragraph in the runbook.

Every environment value comes from Secret Manager, **including the two public
ones**. A `value:` in that file would be project configuration committed to git,
and the last time that happened it took a history purge to undo. `deploy.sh`
checks all three secrets are readable before spending a build, so a missing
grant fails in seconds naming the secret rather than as an opaque remote build
error.

`NEXT_PUBLIC_*` carry BUILD availability because Next inlines them at build
time; the service key is RUNTIME only, since BUILD availability is exactly how a
server secret reaches a client chunk — finding C-1.

**Not deploy-verified**: written from the Next.js deployment guide and the App
Hosting schema, and nothing in this container can run `firebase deploy`. The
first deploy is the test.

### Still genuinely not mine

Three things need credentials this container does not have and must not have:
rotating the six leaked secrets, running `firebase functions:list` to settle
C-6, and asking GitHub Support to purge the 19 `refs/pull/*` refs. Probing
production from here is forbidden for good reasons, and a rotation performed by
an agent is a rotation nobody can audit.


### The third leg: RPC calls

Tables and columns were gated; the functions behind `.rpc()` were not. PostgREST
answers 404 for a function no migration defines, which fails the same silent way
— and the three the mobile calls (`resolve_emergency`, `verify_emergency_pin`,
`set_emergency_pins`) are the entire server-side duress-PIN path, so a rename
that missed a call site would leave an SOS uncancellable.

All three resolve today. The check is in CI so they keep doing so. Worth noting
how nearly this was missed: the calls are written `.rpc<dynamic>('name', ...)`,
and a first pattern without the type argument matched nothing and reported
success — the same under-reporting failure as the earlier two, caught only
because the count was zero when three were known to exist. The pattern now
allows the type argument, and the summary line prints the number of functions
checked rather than just saying OK.

---

## M-7 closed: the legacy Firebase backend is deleted

`functions/` is gone — 19 files, 25 Cloud Functions, confirmed dead in both
clients (no Firebase package in `pubspec.yaml`, no `httpsCallable` anywhere, no
call site in the console).

Deleting it was held back until now for one reason: that source was the last
written record of what the deployed backend exposes, and C-6 — whether any of
it is still live — is unsettled. **The record is therefore transcribed here
before the code goes.** This inventory is what you need in the Firebase console;
you no longer need the directory for it.

### What that backend exposed

| function | trigger |
|---|---|
| `adminDispatchAlert` | callable |
| `adminEscalateAlert` | callable |
| `adminResolveAlert` | callable |
| `agentUpdateMissionStatus` | callable |
| `approveAppUninstall` | callable |
| `calculateSafetyIndex` | callable |
| `createAlert` | callable |
| `escalateTask` | task queue |
| `escalationWatchdog` | scheduled, every 5 minutes |
| `findBestResponders` | callable |
| `getETA` | callable |
| `logAlertChanges` | firestore onUpdate `alerts/{alertId}` |
| `massBroadcast` | callable |
| `migrateLegacyIncidents` | callable |
| `onAlertCreatedGIS` | firestore onCreate `alerts/{alertId}` |
| `processAudioIncidentReport` | firestore onUpdate `alerts/{alertId}` |
| `pruneTrackingPaths` | scheduled, `0 0 * * *` |
| `requestAppUninstall` | callable |
| **`seedMockData`** | **HTTP, public URL** |
| **`smsWebhook`** | **HTTP, public URL** |
| `syncUserCustomClaims` | firestore onWrite `users/{userId}` |
| `triageAndCreateVoiceAlert` | callable |
| `triggerSLASweep` | callable |
| `validateAgentAccessCode` | callable |
| `validateRemovalCode` | callable |

The two in bold are the C-6 finding: `https.onRequest`, so they answer on a
public URL with no Firebase auth in front of them. The scheduled and Firestore
triggers matter for a different reason — **they run whether or not anything
calls them**, so an `escalationWatchdog` firing every five minutes against a
Firestore that no longer backs the app is a live process acting on stale data.

### Closing it

```bash
firebase functions:list --project rainbow-97f1e     # what is actually deployed
firebase functions:delete smsWebhook seedMockData --project rainbow-97f1e --force
# then the remaining 23, from the table above, once no external caller is confirmed
```

Do **not** `curl seedMockData` to find out whether it is there. The pre-guard
version has no method check, so the probe itself writes ten fabricated
`CRITICAL`/`DURESS` emergencies. `smsWebhook` is inert on anything that is not a
well-formed POST and is safe to probe; the exact command is in the C-6 section
above.

### Also removed

The `functions-guards` CI job, which existed to assert those endpoints rejected
unauthenticated callers. It was already written to skip cleanly once the
directory went, but a job that can never do anything is dead weight rather than
a safety net.

Four scripts imported firebase-admin through `../functions/node_modules/`.
That path has been broken on every fresh clone since `node_modules` was
untracked (M-6), so they were already dead on arrival; they now use the plain
specifier and resolve from `scripts/package.json`, which declares the dependency.

**Still Firestore-era, still in the tree:** eleven scripts under `scripts/`
seed and provision *Firestore*, not Supabase — access codes, jurisdictions,
safe zones, HQ accounts. They are the same generation as the code just deleted
and are the obvious next removal, but unlike `functions/` they describe data
rather than a live attack surface, so they are left until the Firestore project
itself is decommissioned.

### And the Firestore-era scripts

Eighteen more files, leaving fourteen in `scripts/` — every one of them either
exercised by CI or part of the Supabase migration tooling.

**Twelve seeded or provisioned Firestore**: access codes, jurisdictions, safe
zones, mock alerts, HQ and responder accounts, user segments. They are the same
generation as the Cloud Functions and address a datastore neither app has used
since the move to Supabase.

**`reset-hq-password.js`** went with them, and it is the one worth naming
separately: a Firebase Auth REST script carrying `NEW_PASSWORD = '12345Gg!'` in
plain text — the shared demo credential from H-2, still sitting in the tree
under a different filename after the login page was cleaned up. It matched no
pattern in the credential scan because a password is just a string; nothing
about it looks like a key. That is a limit of the scan worth remembering: it
catches credential *shapes*, and a weak shared password has none.

**`scripts/package.json` and its lockfile** declared exactly one dependency,
`firebase-admin`, for those twelve scripts. `verify_rls.js` resolves
`@supabase/supabase-js` from the dashboard workspace instead, so with the
Firestore scripts gone the manifest had no purpose.

**Three one-off tools** — `fix_siec.js`, `remove_alpha.py`, `resize_ipad.py` —
were deleted on different grounds. Each hardcodes an absolute path under
`/Users/mac/RainBow/`, so none of them can run for anybody but the machine they
were written on. That is precisely the defect that made the original `deploy.sh`
undeployable (M-5). A script that cannot execute anywhere is not tooling.

Nothing referenced any of the eighteen — no workflow, no shell script, no
documentation. What remains: the RLS harness and its generators, the drift
checker, `verify_rls.js`, `build_web.sh` and the UI automation runner. The
generated SQL still regenerates byte-identical, and the credential scan is
clean.

---

## Applying the migrations, in two pastes

Fourteen migrations would mean fourteen trips to the SQL editor, each with its own
verification snippet to run and read — fourteen chances to skip one, apply them out
of order, or believe a step worked because no error appeared.

`scripts/apply_all_migrations.sql` is generated from the migration files and
contains all of them in order, ending in a 25-row PASS/FAIL table. One paste in,
one answer out. `scripts/apply_in_parts/` is the same SQL split for an editor that
will not take 2,300 lines at once, and CI proves the parts land the same database
as the whole.

**Counts in this file are derived now, not written.** An earlier version of the
generated header said "the nine outstanding migrations" while the file applied
fourteen — on a file an operator pastes into production, a header that miscounts by
five costs its reader's trust in everything under it.

It does **not** replace the dry run, and says so in its own header. The RLS
migration drops prior policies by exact name, a hand-made dashboard policy
survives it, and PostgreSQL ORs permissive policies together — so one survivor
re-opens the table and the migration becomes decorative. Only the dry run, run
against the real database, can detect that.

### Why the verification is part of the file

The runbook's per-step checks were correct and nobody would run all of them.
Folding them into the script makes verification the default rather than an act
of diligence, and it checks facts that matter rather than that statements ran:
that **no policy grants anon or public anything**, that the escalation columns
exist — their absence made every escalation fail in full — that the tier has its
own column, that no tier label is left in the agency column, and that incident
media has no UPDATE or DELETE policy.

### Proven as a paste, not as a concatenation

`scripts/verify_apply_all.sh` builds a production-shaped database — the four
historical migrations production already has — then runs the generated file
exactly as pasted, top to bottom, and asserts on its own verdict table. Then
runs it **again**, because the file claims idempotence and a partial run must be
safe to repeat. Both are a CI job.

Mutation-checked: removing one migration from the generator turns the matching
row into `*** FAIL ***` and fails the build. A verdict table that could only
ever say PASS would be worse than no verdict table, since it would convert "not
checked" into "checked and fine".

### What this does not do

It cannot be run from here. This container holds no database credentials — the
local `.env.local` carries placeholders written for a test build — and applying
schema changes to a live emergency-response system is not something to do
without the operator reading the dry run's verdict first. The work that could be
done here was making the operator's part one paste instead of nine, and proving
the paste works.

---

## A staging project, and the gap it closes

Everything in this repository is proven against a throwaway PostgreSQL. That
harness has one blind spot, and it is the one that has cost the most here: **it
cannot see what a live Supabase does.** No PostgREST, no Auth service, no
Storage service — and, decisively, none of the policies somebody created by hand
in the dashboard. Production held 44 policies where a replica rebuilt from these
files held 21. Twenty-three existed only where no test could look.

`docs/STAGING.md` closes that for the cost of one free project.

### Three artefacts

**`scripts/bootstrap_staging.sql`** — all thirteen migrations, generated, ending
in a fifteen-row PASS/FAIL table. Not the same file as
`apply_all_migrations.sql`, and the difference matters in both directions: this
one includes the four historical migrations because a fresh project has nothing,
and that one omits them because production already has them and re-running the
initial schema would re-create the `USING (true)` policies the RLS migration
exists to remove.

**`scripts/seed_staging.js`** — one account per role the apps branch on, and
five incidents chosen so that previously-real defects are visible rather than
described: an SOS with no coordinates that must read UNLOCATED rather than a pin
in central Jos, an ungraded incident that must read UNKNOWN and stay out of the
CRITICAL filter, a JOS NORTH broadcast that must not reach a Mangu-based
liaison, and an escalation that must appear in one agency's portal and no
other. Auth users cannot be seeded in SQL — Supabase hashes passwords in the
Auth service, so a row poked into `auth.users` cannot log in — which is why this
one is JavaScript.

**`scripts/verify_bootstrap.sh`** — a CI job, because a bootstrap that has never
been run is a hypothesis.

### The guard was wrong twice, and both are recorded

The bootstrap must refuse a database that already holds data, because its path
to a correct end state runs *through* the original schema's open policies. The
first version only `RAISE`d an exception. That aborts the buffer in the Supabase
SQL editor — the documented route — but under plain `psql` the error prints and
**execution continues**, applying every migration anyway. A guard that warns
while the damage proceeds is worse than none.

The fix is structural: the whole file is one transaction, with the RLS
migration's own `BEGIN`/`COMMIT` stripped during generation so a nested `COMMIT`
cannot end it early. A tripped guard now rolls back whole.

The test was wrong in a matching way — it asserted on psql's exit code, which is
`0` for a rolled-back run, so it would have passed the very version that applied
the migrations anyway. It now asserts by outcome: after a refused run, the
column added by the last migration must not exist.

### One check that was wrong about the schema, not the schema

The verdict table originally asserted that *no* permissive `USING (true)` policy
survives. Three do, and all three are correct — `system_alerts_read`,
`safe_zones_read` and `app_config_read_authenticated`, each granted to
`authenticated` only. Advisories, safe zones and app config are meant to reach
every signed-in user.

That check confused a *shape* with the risk. The risk is who can reach it, which
is a separate check and which passes. This repository's own
`scripts/rls_inventory.sql` already drew that distinction in its `reach` column;
the check did not. It now pins the exact set of three, which is stricter than
deleting it: a new permissive policy fails here even when granted only to
`authenticated`, which the anon check would let through.

### What it still cannot tell you

Stated plainly, because the point of staging is to stop guessing: it does not
test the deployment (the App Hosting config has still never been executed), the
mobile release builds (no Android or iOS SDK here), or behaviour under load.

## Every screen, rendered

Until this pass, **no console screen in this repository had ever been
rendered.** Every console finding above came from reading code, or from unit
tests of logic deliberately lifted out of the components so it could be tested
at all. That was an honest limit — a widget test cannot build a screen that
touches the database — but it left the wiring between logic and screen
completely unexercised, and that is where this system's worst defects have
lived.

`scripts/local_e2e/run.sh` closes it. A stand-in Supabase, a production build of
the console, a real Chromium, 51 screenshots and 32 assertions, in about two
minutes, needing no credentials and no network.

The stand-in is the part that matters. Its tables are built from
`supabase/migrations/`, so a query naming a column no migration defines is
rejected exactly as PostgREST rejects it — in full, taking the select, the
filters and the order with it. A tolerant fake would have turned this system's
most expensive defect class into a pass.

**What it proves, and what it does not.** It proves the screens. It does not
prove row-level security and cannot: the fake answers every query as the
service role would. Policies are still only provable against a real PostgREST,
which is `scripts/verify_rls.js` against a staging project.

### What the first run found

**The Uninstall Requests panel had never worked.** `UninstallRequests.tsx` asked
for:

```ts
.select('*, profiles(full_name, role, geo_lga)')
.order('created_at', { ascending: false })
```

Both halves are refused by PostgREST, each on its own sufficient to kill the
query:

* `uninstall_requests` has no `created_at`. Its timestamp is `submitted_at`,
  and has been since the table was created in `phase1_foundation.sql`.
* Embedding needs a declared foreign key. `user_id` references `auth.users`,
  not `public.profiles`, so there is no relationship to travel: PGRST200.

`loadRequests()` therefore returned `null` on every call, and the panel showed
its could-not-load state to every operator, permanently. Nobody could authorise
an uninstall request through this console.

The fail-closed design is the only reason this was survivable rather than a
lie — the panel distinguishes "the query failed" from "there is nothing here",
so it never claimed an empty queue. That distinction is the README's first
principle, and it held.

Fixed by ordering on `submitted_at` and fetching the reporter's name in a second
query. A foreign key to `profiles` would have saved the round trip, but
`user_id` is nullable `ON DELETE SET NULL` and rows may reference users with no
profile row — a migration that can fail on real data is a bad trade for one
request.

### Why three gates had all passed it

* **`check_schema_drift.py` exempted `id`, `created_at` and `updated_at`** on
  every table, on the reasoning that a migration might not spell them out. It
  does spell them out. The exemption was shaped exactly like the most common
  column names in the codebase, and `created_at` walked straight through it.
  The exemption set is now empty.
* **The same script skipped any select containing `(`, `*` or `:`** as not a
  plain column list. `'*, profiles(full_name, role, geo_lga)'` contains all
  three. Skipping the awkward shape meant skipping the query most likely to be
  wrong. Embedded resources are now parsed, their columns checked against the
  embedded table, and the relationship checked against the foreign keys.
* **`.order()` was never examined at all.** It is the easiest place for a bad
  column name to hide, because the select list beside it can be perfectly
  correct and the query still dies. Now gated.

Both new gates were verified by restoring the original query and watching the
checker fail on each half, then restoring the fix.

### Three failures in the first run that were the harness, not the app

Recorded because the difference is the whole value of the exercise, and because
each one nearly became a false finding in this report.

* **The ARMY portal looked empty.** The migration parser read only the first
  clause of `ALTER TABLE … ADD COLUMN a, ADD COLUMN b`, so it never saw
  `alerts.escalation_log`, so the fake rejected the portal's query, so the
  portal correctly showed its empty state. The portal was fine. Worse, the
  matching assertion on the POLICE portal *passed* for the same broken reason —
  a green check produced by a broken harness.
* **C-5 appeared to have regressed.** It had not: the unlocated callout is on
  the map, which is where a fabricated pin would have been, and the assertion
  was looking at the incident feed. The map states it twice — a `1 UNLOCATED`
  counter and an amber `NO GPS FIX — NOT ON MAP` badge on the card.
* **Every screen failed at once**, showing the console's error boundary. The
  previous `next start` was still holding port 3000, so the browser loaded the
  old build's HTML against the new build's chunk names. An environment mistake.
  It did demonstrate the error boundary working on a real `ChunkLoadError`,
  which no test had shown before.

### What the run confirms still works

Recorded because several of these were repairs made earlier in this audit on
reasoning alone, and this is the first time any of them has been observed:

| | |
|---|---|
| the proxy guard | an anonymous `/dashboard` lands on `/login` |
| C-5 | the SOS with null coordinates is counted as `1 UNLOCATED` and badged `NO GPS FIX — NOT ON MAP`, not pinned in central Jos |
| ungraded severity | reads `UNKNOWN` in the dossier, and the CRITICAL filter drops it — severity is not assumed |
| the CRITICAL filter | keeps both CRITICAL incidents, drops the two HIGH ones and the ungraded one |
| mass broadcast | inserts into `system_alerts` with all eleven columns accepted, and a derived non-null `title` — the `NOT NULL` that used to fail |
| the agency portal | the ARMY-escalated incident appears in the ARMY portal and in no other |
| login failure | a wrong password reads as a credential error, never as `Failed to fetch` |
| the error boundary | catches a real chunk failure and says the board is offline rather than showing a blank page |

32 of 32 assertions pass. The screenshots are kept by CI as a build artifact on
every run, pass or fail — a failure is exactly when somebody wants to see the
screen.

### Still not covered by any of this

* **Row-level security as deployed.** Only staging can show it.
* **The mobile app on a device.** Its test suite runs in CI; no screen has been
  rendered on a handset or an emulator, and no release build has been produced.
* **The deploy.** The App Hosting config has still never been executed.

## Pressing the buttons

Rendering a screen and using one are different claims. The pass above proved
the first. This one presses every control a commander or an agency liaison can
reach and checks each action against the database write it is supposed to
cause — because a button that looks right, logs nothing and writes nothing is
invisible to a screenshot.

`scripts/local_e2e/interact.js`: sixteen named flows asserted against their
writes, then a sweep that clicks the remaining sixty-odd controls and records
what each one did — a request, a DOM change, a navigation, or nothing at all.
The last is what it is hunting.

### The map was never actually tested

The first pass reported "the map renders". It did not. OpenStreetMap — and
CARTO's dark basemap, which the console switches to in dark mode — are both
refused by the egress policy here and on any CI runner, so every map screenshot
was markers floating on an empty grey page. "The map renders" meant nothing.

Tiles are now served locally from a generated PNG and every request recorded,
which is better evidence than the real endpoint rather than worse:

* the base layer is visibly present, so a screenshot shows a map;
* the run asserts the tiles the app asks for are **over Plateau State** — 24
  of 24 inside the state's bounding box, first corner 10.49°N 9.14°E, all at
  zoom 9 — rather than trusting the centre it was configured with;
* switching theme is asserted to repoint the base layer at the dark basemap,
  not merely recolour the chrome around it;
* it does not depend on a third party's uptime.

It does **not** prove OpenStreetMap's own tiles render. That needs the real
endpoint and a network that allows it.

### What pressing the buttons found: anyone could become a commander

The Agent Directory provisions staff accounts. It did it like this:

```ts
supabase.auth.signUp({ email, password,
  options: { data: { role: 'HQ_COMMAND', agency, geo_lga, ... } } })
```

and `handle_new_user()`, unchanged since the initial schema, did this:

```sql
role := COALESCE(NEW.raw_user_meta_data->>'role', 'CITIZEN')
```

`raw_user_meta_data` **is** `options.data`. It is written by whoever is signing
up, with the anon key — which ships inside the APK and inside the browser
bundle, by design, because row-level security is meant to be the whole access
model. So this was enough, from anywhere:

```ts
supabase.auth.signUp({ email, password,
  options: { data: { role: 'HQ_COMMAND' } } })
```

`is_staff()` and `is_command()` read `profiles.role`, so that account then
passes every policy in the RLS migration: the full incident board, live
telemetry for every citizen who has pressed SOS, dispatch, escalation, and mass
broadcast to the whole state.

**Why the existing guard did not cover it.** `profiles_no_privilege_escalation`
is `BEFORE UPDATE`. The escalation is not an update — the role is chosen at
INSERT, by the signup itself. README.md said "nothing reads `user_metadata`",
which was true of the policies and not true of the trigger that creates the row
the policies read. The security model was correct about itself one layer up
from where the hole was.

**Proven, not argued.** `scripts/signup_role_escalation_test.sql` runs in the
existing throwaway-PostgreSQL harness. Before the fix:

```
WARNING:  FAIL  a signup that asked for HQ_COMMAND got HQ_COMMAND
```

**The fix.** `20260927000000_signup_cannot_choose_role.sql` makes every signup a
CITIZEN whatever it asks for; `full_name` and `phone` are still honoured,
because they are not privileges. The function also gains `SET search_path`,
which a SECURITY DEFINER function should always pin.

That closes the hole and breaks the console's provisioning, which depended on
it — so provisioning moved to `/api/admin/provision`: it authenticates the
caller, refuses anyone who is not command, refuses an unknown role by name,
refuses a non-HQ commander minting an `HQ_COMMAND` or `ADMIN` peer, creates the
account with the service key, sets the role on the profile, and deletes the
account if the role write fails — an account that exists with no role is a
citizen holding staff credentials, which is worse than no account.

The run asserts the whole of it end to end: the form posts to the route, the
route answers 201, the profile comes back `UNIT_COMMAND` rather than `CITIZEN`,
and **every write that touches `profiles.role` arrived with the service key,
never from the browser.** The stand-in records which key each write came with,
so that last claim is checkable rather than assumed.

**Still outstanding, and it needs a human.** The migration cannot tell an
account legitimately provisioned as `HQ_COMMAND` from one that asked to be.
`docs/PRODUCTION_DEPLOYMENT.md` carries the audit query for the existing roster.
On the project this was applied to on 2026-09-28 the answer was easy — there were
zero accounts of any kind — but that will not be true of a project that has been
running.

**And one thing this fix created, found while using it.** `/api/admin/provision`
opens with `requireRole(COMMAND_ROLES)`, and the migration makes every signup a
CITIZEN. So on a database with no staff, **there is no way in**: the only route
that can set a role refuses everyone, because nobody holds a role yet. It is a
genuine bootstrap deadlock, not a misconfiguration, and it appeared the first time
anybody stood the system up from nothing.

The first account therefore has to be made out of band, once, per deployment:

```sql
-- after creating the auth user in the Supabase dashboard
update public.profiles
   set role = 'HQ_COMMAND', full_name = '...', badge_number = 'HQ-001'
 where email = '...';
```

That works because `profiles_no_privilege_escalation` exempts a caller with no
`auth.uid()`, which is what the SQL editor is. Every account after the first goes
through the route. Written down here because the deadlock is invisible until the
moment it blocks you, and at that moment it looks like the console is broken.

### Six more harness faults, again not app faults

Every one of these first presented as a defect in the console:

* **`DISPATCH` "wrote nothing".** It opens a responder picker, and the confirm
  button stays disabled until somebody is selected. Dispatching to nobody is
  correctly refused; the harness had not selected anyone.
* **"Filing an action report wrote nothing".** The pattern `report` matched the
  **Action Reports tab** rather than `FILE REPORT TO HQ` on the card, so the
  run navigated to the list and then complained the list did not write.
* **`DEPLOY` "was missing".** It is on the expanded incident card, and the card
  collapses when the deployment modal closes.
* **"The browser writes `profiles.role`".** It does not — that write is the
  server route's, through the same stand-in. The fake now records which key
  each write arrived with, which is what makes the claim meaningful.
* **"`🚔 POLICE` is a dead control".** The sweep compared `innerHTML.length`,
  and selecting a different agency swapped text of the same length. It hashes
  the content now.
* **"`Provision Security Personnel Account` is a dead control".** Three of its
  fields are `required`, so clicking submit on an empty form is refused by the
  browser with no DOM change. The sweep now treats failed field validation as
  the control working, which it is.

### What now passes

21 of 21 interaction assertions, 62 controls exercised, no dead control, nothing
thrown, and no query naming a column the migrations do not define:

| | |
|---|---|
| map | 24/24 tiles over Plateau at zoom 9; markers drawn; theme switch repoints the basemap |
| dispatch | picks a responder, writes `DISPATCHED` with `assigned_to` and `assigned_responders` |
| escalate | writes status, agency and an appended `escalation_log` entry |
| resolve | writes `RESOLVED` with `resolved_by` and `resolved_at` |
| broadcast | inserts into `system_alerts` with a derived non-null title |
| provisioning | 201 from the server route; role set with the service key, never from the browser |
| uninstall queue | `APPROVE` writes status and `reviewed_at` |
| agency portal | add officer, change status, deploy personnel, file a report — all four insert |
| HQ ↔ agency | HQ acknowledging a report writes `read_by_hq` and who acknowledged it |
| sign out | returns to the login screen |

## The mobile app, rendered and used

No screen of the mobile app had ever been rendered either: there is no emulator
here, and for most of this audit there was no Flutter SDK, so "it builds and its
tests pass" was the whole of the evidence.

Flutter's web target builds the same widget tree from the same Dart, so the
screens can be rendered and the buttons pressed. `scripts/local_e2e/`:

* `mobile_capture.js` — every route at phone size (390×844), screenshotted
* `mobile_interact.js` — SOS both ways, the AI report, all ten reporting
  categories end to end, emergency PINs, the uninstall request, and a sweep of
  every remaining button

**What that is and is not.** It is the real screens, the real router, the real
state, against the stand-in backend. It is **not** an Android or iOS build:
platform plugins behave differently or not at all on web. It does not prove
row-level security.

### Every SOS this app has ever sent was refused by the database

`AlertService.submitAlert` built its insert payload with both of these:

```dart
'reported_by': reportedBy,
'reportedBy': reportedBy,      // not a column
```

PostgREST rejects an insert naming an unknown column **in full**. So every alert
the mobile app submitted — every SOS, every incident report, from every
citizen — was refused.

It was invisible because the failure path is a *fallback*, not an error: the
catch enqueues the alert into offline SQLite and the UI reports the alert sent.
It looked like an app with good offline support. It was an app that was always
offline.

**Why the drift gate missed it.** `check_schema_drift.py` matched Dart payload
keys with `[a-z_][a-z0-9_]*` and no `IGNORECASE`, so `'reportedBy'` did not
match the pattern at all and was skipped in silence — and a camelCase key is
precisely what a wrong column name looks like when the surrounding code is
Dart. The pattern now accepts any identifier, and the gate reports
`alerts.reportedby` on the original code.

### Every panic SOS was filed as MEDIUM

`submitAlert` took an `isCritical` flag and never read it. The body graded
alerts from `priority`, which defaults to `AlertPriority.medium`. So
`EmergencyNotifier.startEmergency()` — which passes `isCritical: true` and no
`priority` — filed every PANIC SOS at MEDIUM.

On the HQ board that put the most urgent thing a citizen can do below a report
of a blocked drain, and outside the CRITICAL filter entirely. The console-side
work earlier in this audit *verified* that the CRITICAL filter correctly drops
anything not graded CRITICAL; this is what was arriving mis-graded.

Nothing caught it. `sos_orchestration_test.dart` verifies the provider *passes*
`isCritical: true`, which it did — the parameter is right there in the call and
looks like it works. It was found by pressing the button in a browser and
reading the row that came out: `severity: MEDIUM`.

Fixed by honouring the flag, and pinned by three tests in
`offline_queue_test.dart` that go through the real `submitAlert` (its offline
fallback writes the same severity the insert would). Restoring the bug makes
them fail with `Expected: 'CRITICAL'  Actual: 'MEDIUM'`. The browser run now
reports `type=PANIC SOS severity=CRITICAL`.

### What the mobile run now proves

16 of 16 assertions:

| | |
|---|---|
| silent SOS (tap) | inserts `EMERGENCY - Silent SOS` with reporter and real coordinates |
| panic SOS (long press) | inserts `PANIC SOS` at **CRITICAL**, and opens the emergency screen |
| AI report | opens, listens, and produces a transcript |
| all ten categories | Kidnap … Community attack, each through category → subtype → dossier → transmit, **10/10 inserted**, each carrying its own type and severity (e.g. `Kidnap - Immediate Abduction` / `CRITICAL`) |
| emergency PIN | the four-step wizard reaches `rpc/set_emergency_pins` — the device never stores PIN material |
| uninstall request | inserts into `uninstall_requests` |
| incident history, safe zones | read the tables they display |
| every other button | 13 exercised, none dead |

### One error that is NOT the app's

An uncaught `TypeError: Cannot read properties of null (reading 'toString')`
fires 22 times, whenever the harness synthesises a keystroke. Resolved through
`main.dart.js.map`, its stack is entirely inside
`org-dartlang-sdk:///lib/_engine/engine/keyboard_binding.dart` — Flutter's own
web keyboard binding — with no frame in `lib/`, and that binding does not exist
on Android or iOS. It is excluded by stack rather than by message, so an app
error with the same wording would still be reported.

### Two more harness faults worth recording

* **"Login is broken."** It was not. The fake appended on `upsert` instead of
  merging, so `profiles` held two rows for one id; the app's own profile lookup
  uses `.single()`, got "Results contain 2 rows", left the role unknown and
  parked the user on the login screen. An hour of it looking like an auth bug.
* **"Nine of ten categories are broken."** The report flow is three screens —
  category, subtype, dossier — and the harness had collapsed the middle one,
  typing a narrative into a screen with no narrative field and then looking for
  a button that lives on the screen after it.

### Still not covered

* **A real device.** Web is the same Dart, not the same platform.
* **Row-level security**, which only a staging project can show.
* **The release build and the store artefacts**, which are gated statically only.

## The command chain

The intended model, stated by the system's owner: **an alert reaches the
polling unit; the PU escalates to the ward, the ward to the LGA, the LGA to
HQ; and HQ overrides where the chain below it is not accessible.**

Three things had to be true for that, and none of them were.

### The timeouts were configured, visible, and dead

`app_config` has seeded escalation timeouts — PU 2 minutes, WARD 5, LGA 10 —
and the console's System Logic screen lets an operator edit and save them. The
only code that touched those keys was the screen that displays and saves them.
**Nothing ever escalated on a timeout.**

That is the worst kind of dead setting. It is not missing, it is reassuring: an
operator who sets "PU timeout: 2 minutes" comes away believing unanswered
alerts climb the chain, and nothing tells them otherwise. It is also exactly
the mechanism the owner's model needs, since a tier that is "not accessible" is
detected by a clock.

`escalate_overdue_alerts()` now enforces them, in the database, on a pg_cron
schedule. Server-side because a tier that is not responding is very often a
tier that is offline — an escalation that only runs while somebody has the
console open cannot fire in the case it exists for.

### Nothing put an alert at the bottom of the chain

`assigned_tier` was nullable with no default, so an alert arrived owned by
nobody. The ladder existed with no bottom rung. The default is now `'UNIT'`,
set in the DATABASE rather than in a client, because an alert inserted by the
mobile app, the console, the offline queue replaying, or any future integration
must all land in the same place. A client-side default is one forgotten call
site away from an unowned emergency.

### There was no clock on ownership

Nothing recorded *when* a tier took an alert, so "has this tier had it too
long?" could not be asked. `tier_assigned_at` starts on insert and restarts on
every escalation, so an alert escalated to the ward gets the ward's full window
rather than whatever was left of the PU's.

### What the chain now does, proven on real PostgreSQL

14 assertions in `scripts/command_chain_behaviour_test.sql`:

| | |
|---|---|
| a new alert lands at the polling unit, with the clock started |
| an alert inside its window is left alone |
| an overdue UNIT alert climbs to WARD |
| it climbs **one rung per timeout**, never straight to the top |
| the move is appended to `escalation_log` with `reason: TIMEOUT` |
| an **acknowledged** alert never moves — somebody has it |
| a resolved alert never moves |
| **HQ is terminal**: `next_tier('HQ')` is NULL, so the chain stops rather than looping |
| a malformed timeout falls back to the seeded value, not to zero |
| a zero timeout is refused rather than escalating everything instantly |
| the job is service-role only — no signed-in client can reassign every emergency |

The two dangerous defaults are deliberate. A missing or malformed
`app_config` value must not mean "escalate immediately" (timeout 0) or "never
escalate" (NULL read as infinite); both are silent, and both are wrong in an
emergency queue.

### Still missing: alerts do not reach the RIGHT polling unit

They now reach *a* tier. They do not reach the *correct* PU, because nothing
populates the geography an alert would be routed by:

* a citizen incident report attaches **no** `geo_lga`, `geo_ward` or `geo_pu`
  at all unless the reporter ticks "manual override";
* the panic SOS attaches `geo_lga` and `geo_ward` from the reporter's profile
  and **never `geo_pu`**, though the profile has one;
* the unit filter's PU comparison is therefore never reached, and the
  `geo_pu IS NULL` fail-open shows every alert to every unit in the state.

The decision taken was to resolve the incident's **GPS coordinates** to a
PU/ward/LGA, which is the right answer — it reflects where the incident is
rather than where the reporter is registered. **The data to do it does not
exist in this repository:**

* all 17 "LGA boundaries" in `plateau_boundaries.json` are axis-aligned
  rectangles — placeholders, not real shapes;
* `TacticalWard` carries `id`, `name` and `pollingUnits: List<String>`. There
  are **no coordinates for any ward or polling unit anywhere**.

Resolving against the rectangles would confidently route an SOS to the wrong
LGA, which is worse than not routing it. Real INEC ward and polling-unit
geometry is a prerequisite, and it is an input this repository has to be given.

Also noted: the dashboard prefers plural `geo_lgas` / `geo_wards` / `geo_pus`
columns for an officer covering several patches, falling back to the singular.
None of those three columns exist in any migration, so the fallback is the only
path that ever runs and a multi-ward officer cannot be expressed.

## Two of Plateau's seventeen LGAs could not be matched

The two apps each carry their own copy of the state's jurisdiction map, and
they disagreed.

| | console | mobile app |
|---|---|---|
| | `Barkin Ladi` | `BARIKIN LADI` |
| | `Qua'an Pan` | `BWALL` |

`BARIKIN LADI` is a transposition of Barkin Ladi. `BWALL` is not a local
government area at all — Bwall is a district *inside* Qua'an Pan, and Qua'an
Pan was missing from the mobile app entirely.

**Why it matters.** The console matches an alert to an LGA with `geoMatches`,
which lowercases both sides and accepts a substring in either direction. That
generosity absorbs `JOS NORTH` vs `Jos North` — it cannot rescue a name that is
simply different. `barikin ladi` is not a substring of `barkin ladi`, and
`bwall` shares nothing with `qua'an pan`. So an incident tagged by the mobile
app in either of those two LGAs could not be matched to them: not by the
console's LGA filter, and not by the dashboard scope of the commander
responsible for that ground. A citizen in Qua'an Pan also could not select
their own LGA, because the app did not list it.

Two of seventeen LGAs, and the reason both apps looked correct in isolation is
that each was self-consistent. Only comparing them shows it.

Fixed in the mobile map, and pinned by `test/jurisdiction_names_test.dart`,
which asserts the app knows exactly the seventeen real LGAs — no extras, none
missing — and that every name survives the console's own matching function.

## The map boundaries were rectangles

`plateau_boundaries.json` held 17 features. All 17 were **axis-aligned
rectangles**: four corners, two distinct longitudes, two distinct latitudes.
They are the dashed grid visible behind the markers in every map screenshot,
and they are not the shape of anything.

That is why resolving an incident's GPS to an LGA was refused earlier in this
audit: a point-in-polygon test against a rectangle returns an answer with total
confidence and no relationship to where the boundary actually runs.

Replaced with the real ADM2 polygons for all seventeen Plateau LGAs, extracted
from **geoBoundaries gbOpen NGA ADM2 (CC BY 4.0, www.geoboundaries.org)** —
92 KB, attribution carried inside the file. The names are the same seventeen
the test above pins, which is what lets a resolved polygon be matched back to a
jurisdiction the apps understand.

### Wards and polling units are still missing

geoBoundaries publishes no ADM3 for Nigeria, so ward polygons are not available
from that source, and polling units are points that no open release in reach
provides. The chain can therefore resolve an incident to its **LGA**, and no
finer. Routing an alert to the correct *polling unit* — the bottom rung, and
the one the whole chain hangs off — still needs INEC ward and PU geometry as an
input.

## Deep search for ward and polling-unit geometry

The routing decision was GPS → polling unit. This is what is actually
obtainable, after searching the open sources reachable from here. Most are
not: HDX, geoboundaries.org, Overpass and Nominatim are all refused by the
egress policy. `raw.githubusercontent.com` is open, which is what made the
rest possible.

| layer | status | source |
|---|---|---|
| **LGA polygons** | **obtained, integrated** | geoBoundaries gbOpen NGA ADM2, CC BY 4.0 — 774 national, 17 extracted for Plateau |
| **Ward centroids** | **obtained, added** | `temikeezy/nigeria-geojson-data`, MIT — 8,809 national, 207 for Plateau, all 17 LGAs |
| **PU list** (names, codes, ward) | available, not taken | `sadiqsalau/inec-ng-data` — 35 MB, complete, but see below |
| **PU coordinates** | **does not exist openly** | — |

### Wards are centroids, not boundaries

The ward data is one lat/long per ward, not a polygon. A point can therefore be
resolved to the **nearest ward centroid inside its LGA polygon** — an
approximation, and it will be wrong near a boundary between two wards of very
different size. That is honest routing with a stated error mode, which is a
different thing from the rectangles it replaces: those were wrong everywhere
and said so nowhere.

`public/plateau_wards.json` carries the 207 centroids and states this limit in
the file itself.

### Polling-unit coordinates are not open data

`sadiqsalau/inec-ng-data` has the complete INEC hierarchy — every state, LGA,
ward and polling unit — and each unit carries only `name` and `abbreviation`.
No coordinates. The geocoded polling-unit sets that do exist are per-state
research datasets for election analysis (Lagos, Abia, Anambra), built by
geocoding unit names after the fact; none covers Plateau and none is
authoritative. INEC's own per-unit coordinates sit behind a single-voter lookup
on the CVR portal, not a bulk download.

**So GPS cannot resolve a polling unit, and the bottom rung of the chain
cannot be reached from coordinates alone.** What is achievable today is
GPS → LGA (real polygons) → nearest ward centroid. Assigning an alert to a
specific PU requires either the reporter selecting it, or INEC PU geometry
supplied as an input.

### A ward-list discrepancy that was not one

An initial comparison suggested the app was missing five Mangu wards. It is
not. The app writes `GINDIRI 1`, `GINDIRI 11`, `MANGU 1`, `MANGU 11` where the
official list writes `Gindiri I`, `Gindiri II`, `Mangu I`, `Mangu II`, and a
normaliser that strips non-letters collapsed each pair to one key. The app's
ward list is complete at 207.

Worth noting for a future reader rather than as a defect: `GINDIRI 11` and
`MANGU 11` are Arabic-numeral renderings of the Roman `II`, so they read as
eleven. They match nothing in the official list except by the numeral-stripping
comparison above, which is the kind of near-miss that produced the two real LGA
mismatches.

---

## Driving one incident the whole length of the chain

The command chain had been proven a rung at a time: the database climbs on a
timeout (real PostgreSQL, 19 assertions), each tier's dashboard renders and
names itself (8 roles, 203 screenshots), each control does something (62
controls). What none of those could see is the **handover** — and that is where
the remaining defects were.

`scripts/local_e2e/chain_lifecycle.js` follows one incident from a citizen's
phone to a dispatched officer, in a browser, taking a screenshot and reading the
database at every hop. 51 assertions, 26 screenshots:

| | |
|---|---|
| a citizen reports in all 10 categories | each row written, each landing at `assigned_tier = 'UNIT'` |
| the jurisdiction on each report | resolved from the reporter's GPS — e.g. `JOS NORTH / TUDUN WADA - KABONG` |
| UNIT → WARD → LGA → HQ | ENGAGE, the action sheet, the authorization fallback, the SITREP and CONFIRM ESCALATION, photographed at each rung |
| after each hop | `assigned_tier`, `status`, the named commander, the restarted clock and the cleared acknowledgement, read back by id |
| the tier below | no longer sees what it handed up |
| HQ | offered no escalation — there is nothing above it |
| HQ overriding | DISPATCH UNIT → the responder picker → a polling-unit officer, three rungs down |
| that officer | can see the mission |

### Four more real defects, all in the handover

**`alert['assignedToUid']` — a key PostgREST never returns.** Read in three
places on rows that come straight from the database, where the key is the
column: `assigned_to`. Every one of those reads was a constant `null` and every
comparison against them a constant `false`, silently.

The worse half is the first: the visibility filter opens with *"if this alert is
assigned to me, show it"*, and that is the **only** rule that can put an
incident on the screen of an officer outside its tier. It is what an HQ override
*is*. So HQ reaching down to a polling-unit officer produced a mission that
officer could not see. The other half: the tactical action sheet gates EN ROUTE,
ON SITE, RESOLVE MISSION, MISSION INTEL and SECURE CHAT on `isAssignedToMe`, so
an officer holding a mission was offered a generic DEPLOY button forever and
could not advance or resolve it from the feed.

Fixed in `lib/features/agent/alert_row.dart`, one function so there is one
answer, and it refuses to read an unknown session as "this is mine".

**HQ had no way to send anyone.** `DISPATCH UNIT` was gated on
`assignedTier == 'WARD' || == 'LGA'`, and the whole action row on
`assignedTier != 'HQ'`. The one rung whose purpose is to override when nobody
below responds was the one rung with no dispatch control: an incident that
climbed the entire chain *because it was ignored* arrived at the only desk that
could not answer it. Dispatch is now gated on `canDispatchFrom`, escalation on
there being a rung above at all — so HQ keeps dispatch and correctly loses the
up-arrow that would have escalated HQ to itself.

**Neither clock the escalation job reads was ever written.**
`escalate_overdue_alerts()` measures a tier's window from `tier_assigned_at` and
stops climbing when `acknowledged_at` is set. Nothing in either app wrote either
column.

* A manual escalation left `tier_assigned_at` at the insert time, so the WARD
  was handed an alert whose WARD window had already expired — and cron moved it
  to the LGA, then to HQ, within a minute or two. One hand escalation of an
  alert older than ten minutes landed at HQ having visibly skipped every rung it
  was meant to climb.
* Accepting a mission never set `acknowledged_at`, so the guard that exists to
  stop an alert being taken off the responder who has it could not fire.

Both are now written by the app and by the console, and asserted against real
PostgreSQL: `command_chain_behaviour_test.sql` replays the app's **old** payload
to demonstrate the cascade, then the new one to show the WARD gets its full
window and still climbs when *that* window passes.

**The console handed the officer down but not the tier.** HQ escalating to an
LGA commander wrote `assigned_to` and `escalated_to_agency` and left
`assigned_tier` at `'HQ'`. Since the responder app shows an officer their own
tier and above, the LGA commander's whole team could not see it — only the one
named officer, and only through the "assigned to me" rule that was itself dead.
`hqOverride` had the mirror problem: HQ took command without owning the rung or
stopping the clock, so the timeout escalated the incident onward from under HQ
minutes later.

Two smaller things fell out of the same read: the console wrote an LGA **name**
into `escalation_log.to_tier`, where the app and the database job both write a
tier **label**, so one timeline rendered `HQ → LGA` and the next `HQ → JOS
SOUTH` with nothing to say which was which; and the portal rendering that
timeline read `by_email`, which the database job does not write, so every
automatic escalation was attributed to `undefined`.

### The override assertion, mutation-tested

"The officer HQ dispatched can see the mission" is the assertion carrying the
whole override claim, so it was worth checking that it fails for the reason
stated rather than passing for some other one. The fix was reverted — a single
line, back to `alert['assignedToUid']` — the app rebuilt, and the run repeated:

```
FAIL  the officer HQ dispatched (UNIT_COMMAND) can see the mission
50/51 checks passed
```

Exactly one assertion flips, which is the right shape. The chain still climbs,
HQ still dispatches, the database still records the assignment correctly. The
only thing that breaks is the officer at the bottom being able to SEE the
mission HQ reached down to give them — which is what the defect was, and it is
worth being precise about how it would have presented in the field: the console
and the database would both show the incident correctly assigned, and the
officer's phone would show nothing.

The picker deliberately selects the POLLING-UNIT officer rather than the first
row offered. The incident is owned by tier HQ and a unit officer is three rungs
below it, so tier visibility cannot explain the pass — only the assignee rule
can. Picking any higher-tier officer would have made the assertion pass whether
the rule worked or not.

### The drift gate could not see the first class at all

It reads select lists and insert/update payloads — where a bad column name fails
loudly. A camelCase key read off a row fails *silently*, which is the worse
half, and that is how `alert['assignedToUid']` survived in three places.
`check_schema_drift.py` now flags camelCase subscripts in Dart files that query
Supabase, with the four maps that legitimately are not database rows named and
explained (a GoRouter `extra`, an FCM payload, a WebRTC ICE candidate, a
background-service message). Verified by restoring the bug and watching the gate
fail.

### Four harness faults, caught before any of them was reported as a defect

Worth recording, because each one produced a run that read exactly like a broken
app:

1. **The followed alert was the oldest.** Kidnap was submitted first; the feed
   sorts newest-first; Flutter web only builds semantics nodes for widgets it
   actually renders. So the followed card was not in the page, and the run
   reported that no tier could see its own incidents.
2. **A wheel event went to the app bar**, because the pointer had never moved
   from (0, 0). Nothing below the fold could ever be reached.
3. **Semantics leaves carry their text in `aria-label`, not `textContent`.**
   Reading only the latter found no incident on any card.
4. **"The first ENGAGE below the incident text" picked a neighbouring card**,
   because the incident type also appears above the feed in the map markers and
   the critical-incident summary. The whole chain then ran *correctly* on a
   different alert while every by-id assertion failed. The button is now located
   structurally, by the card that contains the incident.

The stand-in also had to learn column `DEFAULT`s, **with their types**:
`'[]'::jsonb` is an empty list and `'{}'` on a `TEXT[]` is an empty array, and
getting that wrong made the chain of custody read as empty at every hop.

### And the eight-role capture no longer dies on the eighth

One CanvasKit browser, eight accounts, twenty-four routes each, exhausted the
container on the last role: the process died mid-screenshot and the run ended on
a `TargetCloseError` with no report written — a partial run that looks like a
crash rather than like missing coverage. The browser is now replaced between
roles, with the tile log and the error log kept across the restart since those
are the evidence. 8/8 roles, 203 screenshots, 15/15 checks.

---

## Offline, and the question of a mesh network

Asked whether the app works without internet, and whether mesh networking would
help. Three separate answers, and they are not the same.

### There is no mesh network, and nothing resembling one

No Bluetooth, no Wi-Fi Direct, no Nearby Connections, no peer-to-peer of any
kind, in the Dart, the Android project or the iOS project. This is worth being
plain about because the app's vocabulary suggests otherwise — "UPLINK",
"RELAY", "TRANSMISSION" — and none of that is a radio. Every byte this app
moves goes over IP to Supabase.

### The offline QUEUE is real and well built

`SqliteService` holds an on-device queue; `SyncService` watches
`Connectivity().onConnectivityChanged` and replays it when the network returns.
It is the most carefully tested part of this codebase — thirteen unit tests,
including a regression for a fault where **every alert queued while offline
reached HQ with no coordinates**, in exactly the no-signal scenario the queue
exists for.

So: a report written with no signal is not lost. It is held, and it goes when
the phone can reach the network again.

### But the "emergency cellular relay" did not exist

`offline_overlay.dart` showed "UPLINK DISRUPTED — Initiating emergency cellular
relay…", ran a progress bar, and finished on a green tick reading **SIGNAL
TRANSMITTED**. It is a four-second animation on a timer. Its own doc comment
says so: *"Simulates a resilient offline dispatch … falls back to a simulated
localized SMS burst."*

There is no cellular relay to initiate. The app has no SMS capability at all —
no `SEND_SMS` permission in the manifest, no telephony plugin, nothing. The one
SMS path in the system is `POST /api/sos/dispatch-sms`, which asks the HQ
backend to send one via Termii — over the internet. It is an out-of-band way to
reach a commander who is not watching the dashboard. It is not a fallback for a
handset with no signal, and it cannot be: it needs exactly the connectivity
that is missing.

The overlay was never mounted, so it was telling nobody this. It has been
deleted rather than left for somebody to wire up, because "SIGNAL TRANSMITTED"
shown to a person with no signal is the most dangerous sentence this app could
contain.

### And the success screen was reading the radio, not the outcome

The report flow decided between **REPORT TRANSMITTED** and **REPORT QUEUED
LOCALLY** from `connectivityResult.contains(ConnectivityResult.none)` — a
reading of the radio, taken BEFORE the submit.

That answers "does this phone have a network interface up". The question is
"did the report arrive", and the two come apart in every case that matters: a
captive portal, DNS failure, an expired token, a row-level-security refusal, a
column the schema does not have, or the backend being down. In all of them the
radio says connected, the insert fails, the alert lands in the local queue —
and the person was shown a green REPORT TRANSMITTED with a shield on it.

This is the same failure mode that hid `alerts.reportedBy` for months: an
insert the database refused looked exactly like one that succeeded, because the
queue caught it. `AlertService.wasQueuedOffline` reads the returned id, which
already carried the truth — a uuid when it arrived, `OFFLINE_…` when it did
not — and the screen now reports what happened rather than what was predicted.

### Would a mesh actually help here?

Honestly assessed, rather than as a feature wish:

It would help in the one scenario this system is most likely to face — a
deliberate network shutdown during unrest, where handsets still have power and
each other but no tower. A store-and-forward mesh would let a report hop
between phones until one of them reaches a working uplink.

It is also a large piece of work with sharp edges that matter for this
particular app: peers would relay alerts they can read, which is a privacy
question the current RLS model has no answer for; a duress alert must not be
readable by the phone carrying it; and range is tens of metres, so it helps a
crowd and not a farmstead. None of that is a reason against it. It is a reason
it cannot be bolted on, and should be designed with the threat model in front
of it.

What can be said today: the queue means nothing is lost, the app is now honest
about when a report is still on the phone, and there is no second channel of
any kind. A phone alone with no uplink reaches nobody until it has one.

## The marker was a label, not an incident

HQ watches one screen. On it, the thing an operator clicks first is a pin. What
the pin gave them was the incident type, a status word, the description, and two
buttons. Everything needed to act on an emergency was in the row and none of it
reached the card: not who reported it, not a number to ring them on, not how
long it had been waiting, not whether anybody had taken it, not which tier owned
it, not whether the report had come in over SMS because the reporter had no data
connection at all.

Four separate defects, three of them silent.

### The map was reading Firebase field names

`LiveMap.tsx` declared its own alert interface, and in it:

```ts
reportedBy?: string;
reportedAt?: { seconds: number };
```

Those are Firestore shapes. PostgREST returns `reported_by` and `created_at`,
and it never returns a camelCase key — so both fields were `undefined` for every
alert that has ever been drawn, and would have stayed `undefined` if the popup
had tried to render them. Nothing errored. This is the same defect class as
`alert['assignedToUid']` and the `profiles` query that named three columns which
do not exist: a read that cannot succeed, on a path with no test, producing an
absence that looks like an empty field.

The local interface is gone. The component imports the canonical `Alert` from
`src/app/dashboard/types.ts`, so a field the database does not have is now a
type error rather than a silent `undefined`, and a column the schema gains is
available to the map the day the type learns about it.

`reportedBy` and `reportedAt` have been removed from that canonical type as
well, along with the two `created_at || reportedAt` fallbacks that read them.
A fallback that can never fire makes the real source look optional.

### The map was never given the profiles

Reporter and officer names come from `usersMap`, which the dashboard fills from
`profiles`. `LiveMap` was not passed it and had no prop for it, so even with the
right column names it could not have named anybody.

It is passed now — and the lookup was widened at the same time, because the
profile query is `limit(1000)`. That is fine for a staff directory and wrong for
reporters: this is a citizen app in a state of about four million people, so the
1001st citizen to raise an alert would render as an unidentified reporter
forever, on a query that succeeded. The alerts fetch now also loads the profiles
that the alerts on screen actually name — bounded by what is displayed, at most
500 rows — and merges them in. Both effects merge rather than replace, because
they race and whichever finished last used to win.

### A newly reported emergency could not be dispatched from the map

The DISPATCH button rendered only when:

```ts
alert.status === 'OPEN' || alert.status === 'ACTIVE'
```

Neither is a status this database produces. `alerts.status` defaults to
`'PENDING'`, and the values written anywhere in this system are PENDING,
DISPATCHED, ACKNOWLEDGED, IN_PROGRESS, ON_ROUTE, ON_SITE, ESCALATED, RESOLVED,
DURESS and CANCELLED. So every incident in the state at which dispatching
matters most — one just reported, nobody sent — offered RESOLVE and no way to
send anyone. The operator had to leave the map, find the same incident in the
feed, and dispatch from there.

The fixtures agreed with the bug: `LiveMap.test.tsx` built its alerts with
`status: 'ACTIVE'`, which is the one value that made the button appear. They now
say PENDING, which is what the database writes.

While confirming this, two statuses the console itself writes —
`ESCALATED` and `IN_PROGRESS`, both from `src/lib/alert-actions.ts` — turned out
to be missing from the `Alert['status']` union. They have been added. The status
colour table in the old popup had no entry for `PENDING` either; it fell through
to the same orange as an open incident, which was right by luck.

### A citizen's description was executed as HTML

The popup is built by string concatenation, because Leaflet's `bindPopup` takes
HTML, and the description went in raw:

```ts
<p ...>${alert.description || 'No additional details'}</p>
```

A report whose description contains `<img src=x onerror=…>` runs that script in
the authenticated session of whoever clicks the pin — in the console that holds
the service-role-backed admin endpoints. It was reachable from the mobile app
before; since the SMS channel opened it is reachable by anyone holding a device
key, and since the mesh ingest is unauthenticated by design, by anyone at all
who can seal a frame.

Every value interpolated into the card now passes through `escapeHtml`,
including the incident id inside the `onclick` attributes.

### What the card carries now

One tested module, `src/lib/incident-dossier.ts`, builds it — shared with the
incident feed and the dossier modal, which had their own copy of the reporter
resolution 200 lines into a 3,000-line component where the map could not reach
it. The card states, in the order a dispatcher needs them: how long ago it was
raised and at what time; whether it has been acknowledged and for how long it
has not; severity; which command tier owns it and since when; who it is assigned
to; the agency it was escalated to; the channel it arrived over; the reporter,
their badge if they are staff, their contact, and what kind of reporter they are;
the LGA, ward and polling unit; the coordinates; how many reports the marker
stands for if it is a cluster; attached media; the device reference for an
offline-queued report; and the incident id. Then the description, the triage
summary if there is one, and four actions — DOSSIER, DISPATCH, RESOLVE and, when
there is a number, CALL.

The rule it follows is the one C-5 established: **absence is rendered as
absence**. A report with no reporter says so. A report the reporter filed
anonymously says *that*, distinctly, because the offline ingest writes
`reported_by: NULL` deliberately and "unidentified" would send an operator
looking for a name the server was asked never to keep. A missing severity reads
NOT GRADED, not HIGH. A missing timestamp reads TIME NOT RECORDED — the dossier
modal used to read `JUST NOW`, which asserts a brand-new emergency on the
strength of an empty column. A report with no GPS fix says NO GPS FIX ON THIS
REPORT rather than showing a coordinate.

### Live, and visibly unclaimed

Reports already reach the map without a reload: `alerts` is in the
`supabase_realtime` publication and the dashboard subscribes to it, refetching
on any change. What was missing was that an operator could not tell, at a
glance, which pins were nobody's.

An incident with `acknowledged_at IS NULL` — the exact condition the escalation
cron watches before climbing a tier — now pulses, and is drawn slightly larger.
That is the state where a clock is running and no human has taken the incident,
and it is the one thing on the map worth an operator's attention before they
click anything.

### Two more defects found in the same file

Neither is about the popup, and both were live.

**Every theme toggle threw.** The tile-filter effect called
`mapInstanceRef.current.getPane('tilePane')`. That ref holds `{ map, L }`, not
the map, so it was `undefined('tilePane')` — inside an effect, which takes the
render with it. Introduced by the fix that moved the tiles off CARTO, and caught
by adding a test that toggles the theme.

**Two effects were fighting over the popup's globals.** `_hqResolve` and
`_hqShowDispatch` were installed by two different effects 200 lines apart, and
they disagreed: the first called `onEscalate(id, 'DISPATCH')`, the second raised
an `hq-show-dispatch` event for the page to catch. React runs effects in order,
so the second silently won and the first was dead code that still owned the
cleanup — so on unmount, two of the four globals were removed and two were left
pointing at a dead component. One effect now installs all four and removes all
four.

### What is proven, and how

`src/lib/incident-dossier.test.ts` covers the string builder and every decision
in it — 44 assertions, including the XSS cases, the PENDING dispatch
regression, anonymous versus unknown reporters, and clock skew on a phone's
timestamp. `src/components/LiveMap.test.tsx` drives the real component under
jsdom with real Leaflet: it opens a marker's popup and reads the reporter's name
and number out of the DOM, asserts the injected `<img>` is not in it, toggles
the theme without throwing, and proves the popup is rebuilt when the profiles
arrive after the alerts — which is the dependency that, left out, would have
made the reporter's name load into state and never reach the screen.

The browser harness clicks a pin in Chromium and asserts on the rendered card
(`scripts/local_e2e/capture.js`, screen `31-hq-map-incident-card`), because the
popup is HTML inserted by Leaflet outside React and a real click is the only
thing that proves the wiring end to end.

One honest limitation: the jsdom test asserts the DOSSIER button's `onclick`
attribute and calls the handler directly rather than clicking it, because jsdom
evaluates an inline `onclick` in a global scope that is not the one vitest hands
the test. The real click is covered in Chromium by the harness.

## The map had no basemap at all, and our own policy was why

Moving the tiles off CARTO replaced a watermarked map with a blank one, and
nothing in the map code could have shown it. `src/lib/csp.ts` allowed:

```
img-src ... https://*.basemaps.cartocdn.com https://*.tile.openstreetmap.org
```

and the map now requests `https://tile.openstreetmap.org/{z}/{x}/{y}.png`. A
CSP wildcard matches a **subdomain of** a host, never the host itself, so every
tile in the command console was refused:

```
Loading the image 'https://tile.openstreetmap.org/9/269/241.png' violates the
following Content Security Policy directive: "img-src ..."
```

Grey map, markers floating on nothing, one console message per tile and no
other symptom. This is the third time in this audit that a correct-looking
change has been undone by a second file that had to agree with it — the tile
URL that diverged between the initial layer and the theme effect, the profile
query that named columns the schema does not have, and now the policy that
decides whether the provider may be reached at all.

Both spellings are allowed now, and the configured provider's origin is derived
from `NEXT_PUBLIC_MAP_TILE_URL`, so moving to a keyed or self-hosted tile server
does not silently reproduce the blank map. Leaflet's `{s}` subdomain
placeholder becomes a wildcard; a non-https URL widens nothing. CARTO is gone
from the policy, because nothing requests it.

Seven tests in `src/lib/csp.test.ts` — there were none — and the browser
harness now fails the run on any `img-src` refusal, because that is the only
place this was ever visible.

## Clicking a pin and changing tab threw, twice, every time

The harness reported two uncaught `TypeError: Cannot read properties of
undefined (reading 'classList')` on the screen after the map. The stack is
Leaflet's:

```
_onPanTransitionEnd -> DomUtil.removeClass(this._mapPane, 'leaflet-pan-anim')
```

Opening a popup near an edge starts an autoPan, which runs on
`requestAnimationFrame`. `map.remove()` deletes `_mapPane`. So an operator who
clicks a pin and switches tab within a quarter of a second unmounts the map
mid-animation, and the next frame reads `classList` off nothing. Reachable
before this work and much more reachable after it, because a dossier-sized card
autopans almost every time.

Two obvious fixes both make it worse, and the tests say so: `map.stop()` runs
`setZoom` first, which can begin a fresh animation, and ending the pan by any
route fires `moveend` — which the popup itself listens to, and whose handler
`_adjustPan` starts another pan on a map that is about to lose its panes.
Detaching the animation's listeners before `remove()` is the only step that
cannot restart anything.

Worth recording as a testing lesson: vitest reported these as "unhandled
errors" beside a green suite, and a green suite is what a reader takes away.
`LiveMap.test.tsx` now registers an `uncaughtException` listener, unmounts with
a popup open, waits for the frames to run against the dead map, and fails on
anything that arrives.
