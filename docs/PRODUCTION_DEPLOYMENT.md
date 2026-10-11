# Deploying Operation Rainbow to production

Three deliverables ship independently: the **database** (Supabase), the **HQ
console** (Next.js) and the **mobile app** (Flutter). Do them in that order —
the console and the app both expect the migrations to be in place.

Nothing in this document needs a credential pasted into a chat, a ticket or a
log. Where a secret is involved, it is set in a hosting provider's environment
UI or a local `.env.local` that is never committed.

> **`scripts/verify_rls.js` INSERTs probe rows. Never run it against
> production** — a throwaway staging project only. `docs/STAGING.md` stands one
> up in about ten minutes, and it is the only place the deployed system's RLS
> can actually be tested rather than reasoned about.

---

## 0. Before anything: shut down the orphaned backend

Settle **C-6**: `firebase functions:list
--project rainbow-97f1e`. If `smsWebhook` or `seedMockData` is listed, an
unauthenticated stranger can inject `DURESS`-flagged emergencies today. Delete
the deployment — nothing in either client calls any of those 25 functions. Do
**not** `curl seedMockData` to find out; the probe itself writes ten fabricated
emergencies. The full instructions are in `E2E_AUDIT_REPORT.md`.

---

## 1. Database

**Applied to the production project on 2026-09-28: 25/25 PASS.** What follows is
for a new project — staging, DR, or a second deployment — and as the record of what
each file does.

Thirty-one migrations, in filename order. The fastest route is one paste of
`scripts/apply_all_migrations.sql`, which contains all thirty-one in order and
ends in a 34-row PASS/FAIL table; `scripts/apply_in_parts/` is the same SQL split
into 32 numbered files for an editor that will not take 5,900 lines at once.
`docs/APPLYING_THE_MIGRATIONS.md` is the step-by-step runbook, including the
mandatory read-only dry run; do not apply the RLS migration without it.

**Check the first row of the verdict table before you read the rest.** It is not
a check — it is the script's own version:

```
 PASS   | script version: 31 outstanding migrations, fingerprint f57e16f5be90
```

Compare it with `python3 scripts/migration_sets.py --fingerprint`. If they
differ, the file you pasted is from a working copy behind the repository and
every row below it describes a different set of migrations. This exists because
it has already happened twice — a pasted inventory three migrations stale that
reported "nothing to apply" (T-21), and a pasted verdict table from before the
anon/public check learned to name the policy it objects to, which read
`*** FAIL *** | no policy grants anon or public anything` and named nothing.

| Order | File | What it does |
|---|---|---|
| 1 | `20260812000000_agency_tables.sql` | Creates the four `agency_*` tables and `profiles.agency`. |
| 2 | `20260813000000_rls_least_privilege.sql` | Closes C-3/C-4/H-7. Needs the dry run first. |
| 3 | `20260902000000_per_user_emergency_pins.sql` | Per-user, server-verified duress PINs. Until it runs the duress PIN does not work at all. |
| 4 | `20260903000000_realtime_publication.sql` | Adds the three tables the console subscribes to that were never published. A subscription outside the publication does not error — it silently never fires. |
| 5 | `20260903000001_incident_media_storage.sql` | Creates and secures the `incident-media` bucket. |
| 6 | `20260903000002_system_alerts_broadcast.sql` | Makes mass broadcast work. Until it runs, every broadcast fails on a NOT NULL `title` and six non-existent columns. |
| 7 | `20260903000003_alert_escalation_columns.sql` | Adds `alerts.escalated_to_agency` and `escalation_log`. |
| 8 | `20260903000004_profiles_badge_number.sql` | Adds `profiles.badge_number`, the label both apps show for an officer. Without it the mobile responder list comes back empty and an agent cannot dispatch anyone. |
| 9 | `20260903000005_alerts_assigned_tier.sql` | Adds `alerts.assigned_tier` and moves tier labels out of `escalated_to_agency`. Until it runs, a mobile escalation with no named commander is **rejected in full**. |
| 10 | `20260927000000_signup_cannot_choose_role.sql` | **Closes a privilege escalation.** `handle_new_user()` copied `raw_user_meta_data->>'role'` onto the new profile, so anyone holding the anon key — which ships in the APK and the browser — could sign up as `HQ_COMMAND`. Apply this one first if you apply nothing else. |
| 11 | `20260928000000_command_chain_escalation.sql` | Makes the command chain real: an alert lands at the **polling unit**, and unacknowledged alerts climb UNIT→WARD→LGA→HQ on the timeouts `app_config` has always held and nothing has ever enforced. Schedules the job with pg_cron where available. |
| 12 | `20260929000000_telemetry_is_not_a_standing_feed.sql` | A citizen's live position stops being readable by every staff account and starts being deleted. Also scopes chat writes to a thread you are part of. |
| 13 | `20260930000000_sms_device_keys.sql` | The per-device key the encrypted SMS fallback authenticates with, plus `alerts.arrived_via`. |
| 14 | `20261001000000_mesh_ingest.sql` | The mesh envelope-dedup table, so one alert flooded by several relays is one incident. |
| 15 | `20261002000000_sim_channel_events.sql` | Lets a handset report that its SMS channel died. The phone number is the identity here — it is what the account was made with, what HQ rings back, and what the encrypted SMS fallback rides on. Reports go to command only, and carry no position. |
| 16 | `20261003000000_liaisons_are_not_staff.sql` | An agency liaison is an officer of another organisation, not Operation Rainbow staff. Until it runs, the statewide alert policies rest on `is_staff()` alone and a liaison sees every incident in Plateau State. |
| 17 | `20261004000000_incident_tracks.sql` | Keeps the route somebody took during one emergency. Before it, the trail existed only while an operator was watching live; after the incident there was nothing to review. |
| 18 | `20261005000000_alert_category.sql` | Adds the generated `alerts.category`. Note this is the column a bad INSERT names in a 428C9 error — see C-4 and `scripts/why_did_my_insert_fail.sql`. |
| 19 | `20261006000000_alerts_scoped_to_posting.sql` | An officer's authority ends at their command. The chain had real structure for routing and none for authority: every tier rule lived in a Dart function or a console dropdown. |
| 20 | `20261007000000_notification_outbox.sql` | The automatic escalation moved incidents and told nobody. `escalate_overdue_alerts()` runs under pg_cron — it cannot live in an app that only runs when somebody has it open. |
| 21 | `20261008000000_escalation_push_targets.sql` | Decides in the database who a queued escalation is for. Nothing wrote PUSH/SMS/WEBHOOK rows, and `drain-outbox` marked unknown kinds delivered. |
| 22 | `20261009000000_ward_names_compared_by_key.sql` | `GINDIRI  I` and `GINDIRI  1` are the same ward. Four Mangu wards were spelled differently in the app's geo assets and the console's map, so officers and incidents did not match. |
| 23 | `20261010000000_append_alert_media_atomically.sql` | Appends evidence URLs in the database. Three code paths did read-modify-write on `alerts.media_urls`, so simultaneous uploads lost each other's media. |
| 24 | `20261011000000_ussd_reports_are_unconfirmed.sql` | A stranger's keystrokes must not become armed officers at a chosen place. USSD is the cheapest possible way to lure responders into an ambush, so USSD-filed reports start unconfirmed. |
| 25 | `20261012000000_ussd_filing.sql` | Files a USSD report exactly once. A gateway that gets no reply in its window re-POSTs the same session — normal on a congested network, which is when people report emergencies. |
| 26 | `20261013000000_ussd_landmark.sql` | The nearest landmark, typed by a caller with no GPS. USSD cannot carry coordinates, so without it the console can only draw a circle the size of the ward — 16km across in parts of Wase. |
| 27 | `20261014000000_ai_reports_are_kept.sql` | Stores the AI forensic debrief. It lived in React state only: close the dossier and it was gone, reopen it and the console billed another Gemini call. |
| 28 | `20261015000000_oversight_and_debrief.sql` | A complaint about an officer must not be delivered to that officer. The app offers **Police brutality** as a category, and those reports were routed down the normal chain. |
| 29 | `20261016000000_telemetry_policy_is_not_public.sql` | Recreates `telemetry_select_geo_lga_scoped` as `TO authenticated`. It sat on production as `TO PUBLIC` for weeks. **This is the migration behind a `*** FAIL *** \| no policy grants anon or public anything` row.** Policy-only, so no object-existence check can see it — confirm with `scripts/rls_inventory.sql`. |
| 30 | `20261017000000_the_hand_applied_era_is_in_the_history.sql` | Writes the v2–v5 era down as a migration. A no-op on production, which already has those objects; it exists so a database built from zero matches. |
| 31 | `20261018000000_the_mirrors_and_two_dead_functions_are_gone.sql` | Drops the five generated `geo_*` mirrors and two uncalled v5 functions, converging production downward. Every drop is `RESTRICT`, in its own sub-transaction. Confirm with the `7 of 7 removed` row in `scripts/which_migrations_are_applied.sql`. |
| 32 | `20261019000000_the_audit_trail_names_who_acted.sql` | `audit_trail()` read the actor from `by` only, which nothing a PERSON does writes — both the console and the app write `by_email`. So every escalation an officer performed was attributed to SYSTEM, and the only accurate attributions on the Audit History screen were the machine's own. Reads `by` then `by_email`; both shapes exist on production and the log is append-only, so neither can be rewritten. `CREATE OR REPLACE` only — no data is touched. |
| 33 | `20261020000000_a_handset_that_leaves_mid_emergency.sql` | `signOut()` stopped location tracking first, on the reasoning that signing out is the clearest statement a person can make that they are done being observed. True of their own phone; wrong in the one case the duress design exists for — a duress PIN keeps tracking running because the person may still be in danger, and the lock screen's sign-out needs no code, so whoever held the phone could end a live duress trail without knowing any PIN. A responder's patrol track still stops on sign-out; an SOS track now runs until the incident closes or the twelve-hour ceiling expires. Adds `alerts.device_signed_out_at` so the loss of the app is a fact an operator can read rather than a gap they have to infer. One nullable column, `ADD COLUMN IF NOT EXISTS`; no data is touched. |
| 34 | `20261021000000_an_lga_can_hand_an_incident_to_a_ward.sql` | The command chain only ever climbed: `next_tier()` is UNIT -> WARD -> LGA -> HQ and the escalate sheet offered no choice of target, so an LGA commander's only escalation was upward to HQ. The one sideways move was HQ handing an incident down to an LGA by name (`to_lga`), and there was no `to_ward` anywhere in the codebase — so a commander who judged that a neighbouring ward should take an incident could assign individual responders but could not give that ward's COMMANDER the incident. Adds `alert_delegated_to_my_ward()`, the same shape as the LGA one but comparing the LGA as well, because ward names are not unique across LGAs, and restates `alert_is_ours()` to consult it. `CREATE OR REPLACE` only; no data is touched. |

Every one of them is proven on a real PostgreSQL by the `rls-migration` CI job
before it reaches you.

**"Idempotent" is not quite right, and the difference shows if you re-run.** Most
of these are: `IF NOT EXISTS` / `OR REPLACE`, and a second run says nothing.
`20260813000000_rls_least_privilege.sql` is **atomic** instead — it drops the old
policy set by name and creates a new one inside its own BEGIN/COMMIT — so a second
run reports

```
ERROR: policy "profiles_select_self_or_staff" for table "profiles" already exists
```

and rolls itself back. That means **the policies are already in place**. Nothing is
half-applied, the verification will still report every row PASS, and the thing to
read is the verdict table rather than the error.

### Then make the first staff account, once, out of band

`/api/admin/provision` is the only thing that may set `profiles.role` — and it
opens with `requireRole(COMMAND_ROLES)`. On a database with no staff that refuses
everyone, because nobody holds a role yet. It is a real bootstrap deadlock and it
appears the first time anybody stands the system up from nothing; at that moment it
looks like the console is broken.

Create the auth user in the Supabase dashboard (Authentication → Users → Add user),
then:

```sql
update public.profiles
   set role = 'HQ_COMMAND', full_name = 'Real Name', badge_number = 'HQ-001'
 where email = 'the-account@example.gov.ng';

select id, email, role, badge_number from public.profiles where role <> 'CITIZEN';
```

This works because `profiles_no_privilege_escalation` exempts a caller with no
`auth.uid()`, which is what the SQL editor is. Every account after the first goes
through the route, which enforces the hierarchy.

### And confirm the scheduled jobs attached

pg_cron exists on Supabase but is not enabled by default, and the escalation
timeouts are worthless without it — the failure mode the command-chain migration
was written to fix is a timeout that is configured and never fires.

```sql
select jobname, schedule, active from cron.job order by jobname;
```

Three rows: `rainbow-escalate-overdue` (`* * * * *`), `rainbow-purge-telemetry`
(`17 * * * *`), `purge-stale-mesh-envelopes` (`17 * * * *`). If `cron.job` does not
exist, enable `pg_cron` under Database → Extensions and re-run migrations 11, 12
and 14 — each attaches its schedule wherever the extension is present.

### After applying migration 10, audit who is already staff

The migration stops new accounts choosing a role. It cannot tell an account
that was legitimately provisioned as `HQ_COMMAND` from one that asked to be, so
the existing roster needs a human who knows who is supposed to be staff:

```sql
-- Everyone who is not a plain citizen, oldest first. Anyone here who is not a
-- real officer was able to give themselves that role at signup.
select p.id, p.email, p.full_name, p.role, p.agency, p.created_at
  from public.profiles p
 where p.role <> 'CITIZEN'
 order by p.created_at;
```

Demote anything unexpected with `update public.profiles set role = 'CITIZEN'
where id = '…';` — run as the service role, which the escalation trigger
exempts.

### After applying, verify (read-only)

```sql
-- Expect 8 rows: the tables both apps subscribe to for realtime.
select tablename from pg_publication_tables
 where pubname = 'supabase_realtime' and schemaname = 'public' order by 1;

-- Expect 1 row, public = true, file_size_limit = 52428800.
select id, public, file_size_limit, allowed_mime_types
  from storage.buckets where id = 'incident-media';

-- Expect the two incident_media_* rows: upload (INSERT) and staff list
-- (SELECT). No UPDATE and no DELETE policy — evidence is append-only.
select policyname, cmd, roles from pg_policies
 where schemaname = 'storage' and tablename = 'objects' order by policyname;
```

If that last query returns other policies on `storage.objects` — ones created by
hand in the dashboard for this bucket — they are additional PERMISSIVE grants
and OR together with these. Drop them, or the append-only guarantee is not one.

---

## 2. HQ console

### Railway  ← current target

`docs/RAILWAY.md` is the runbook and `hq-dashboard-next/railway.json` carries the
build and deploy config. Four settings in the Railway UI and three variables; the
only one that is easy to get wrong is **Root Directory = `hq-dashboard-next`**,
because this repository holds the Flutter app at its root.

One thing worth knowing before choosing Railway over App Hosting: App Hosting can
mark the service role key **RUNTIME only**, so it is not present during
`next build` at all. Railway exposes every service variable to the build, so that
structural protection is gone and only the code-level ones remain — `server-only`
on `supabase-server.ts`, and the CI job that greps `.next/static` for key
material. That CI job is now the thing standing between this deployment and
finding C-1 recurring. Keep it green.

It runs a **Node server, not a static export**. That is not a preference:
`output: 'export'` was removed because the auth guard is Next.js middleware, and
a static export silently drops middleware — the console would serve every page
to anonymous visitors with no error anywhere. `railway.json` sets
`startCommand: npm run start` for that reason.

There is **no deploy command**. Railway builds on push to the tracked branch.
`./deploy.sh` runs before the push and does the three things worth knowing
early — the environment values the build needs, the build exactly as Railway
runs it, and the client-bundle secret scan — locally, where a failure costs
seconds instead of a remote build and a rollback.

### Firebase App Hosting — removed

The previous target. `firebase.json`, `.firebaserc` and
`hq-dashboard-next/apphosting.yaml` are gone, and `deploy.sh` no longer invokes
`firebase deploy --only apphosting`.

Worth recording why, because the failure mode was not obvious: both
configurations were present at once for a month, and both were documented as
live — this file said "Railway ← current target" twenty lines above a complete
App Hosting runbook, while README.md said App Hosting and `deploy.sh`, the script
named "production deploy", pushed to App Hosting. Anyone told to redeploy had
even odds of shipping to the abandoned backend, and a stale console answering
requests looks exactly like a deploy that worked.

Two live configs also mean two sets of variables and two secret stores, so
"what is running right now?" had no answer in the repository.
`scripts/check_one_deploy_target.py` now fails CI on a second target, on a
`firebase deploy`/`vercel deploy`/`netlify deploy` invocation in any script or
workflow, and on the Railway config going missing.

Prose may still discuss App Hosting — the paragraph above about the RUNTIME-only
secret is the reason the client-bundle scan is now the only line of defence, and
that is worth keeping. The check looks at config files and commands, not
sentences.

**Nothing in the application code is host-specific**, so the choice stays
reversible: a different provider needs the same three variables, root directory
`hq-dashboard-next`, and a Node server rather than a static export.

### Environment

Every key is documented in `hq-dashboard-next/.env.example`. The ones that must
be set for the console to work at all:

```
NEXT_PUBLIC_SUPABASE_URL          public, baked into the bundle at build time
NEXT_PUBLIC_SUPABASE_ANON_KEY     public, same
SUPABASE_SERVICE_ROLE_KEY         SECRET, server only — never NEXT_PUBLIC_
```

`NEXT_PUBLIC_*` values are inlined **at build time**, so a missing one is not a
runtime warning: the app crashes on first render and serves
`<html id="__next_error__">`. Set them before the build, not after.

**`NEXT_PUBLIC_DEV_DEMO_PIN` must be unset in production.** The quick-fill login
presets are already compiled out (`NODE_ENV !== 'production'`), and CI asserts
the demo credentials are absent from the production bundle, but leaving a real
PIN in the environment of a non-production build re-publishes it.

`deploy.sh` also fails if `NEXT_PUBLIC_DEV_DEMO_PIN` is set at all, and scans the
built client bundle for server secrets — the same scan CI runs. Since Railway
deploys on push and nothing can gate that from here, those checks are advisory:
run them before pushing, and keep the CI job green, because on Railway there is
no second line of defence behind it.

---

## 2b. Citizen sign-in needs an SMS provider — nothing works until it does

**This is a blocker, not a checklist item.** A citizen signs in with their phone
number and a code sent to it. There is no email path and no password. The app
calls `supabase.auth.signInWithOtp(phone: …)`, and Supabase refuses that call
outright unless the project has an SMS provider configured — so until this is
done, **every citizen sign-in fails**, and the app is an emergency service that
nobody can get into.

Termii, which this deployment already uses for outbound alerts, is **not** one
of Supabase's built-in providers (Twilio, MessageBird, Vonage, TextLocal). So it
has to be attached the other way:

The hook is written and in the repository: `supabase/functions/send-sms`. What
is left is four dashboard settings and one deploy flag.

### Do it with one command

```bash
SUPABASE_PROJECT_REF=<your 20-char ref> \
SUPABASE_ACCESS_TOKEN=<personal access token, auth_config_write> \
TERMII_API_KEY=<key> TERMII_SENDER_ID='OE Alert' \
  ./scripts/wire_up_sms_provider.sh --commit
```

It generates the signing secret, stores the three function secrets, deploys with
`--no-verify-jwt`, enables the hook pointed at the function, turns
`sms_autoconfirm` off, reads the configuration back and asserts it, then probes
the live endpoint. No secret value is printed — only its length and first few
characters.

**Diagnosing it needs no credentials and sends no SMS:**

```bash
SUPABASE_PROJECT_REF=<ref> ./scripts/wire_up_sms_provider.sh --check
```

Two unauthenticated requests separate the four failure modes, because this
function's error bodies are distinguishable from the platform's. The one that
matters is the pair of 401s: a 401 with no `error.http_code` field is the
**platform** refusing the call because the function was deployed with JWT
verification on — the hook can then never work — while a 401 carrying that field
is **our own code** rejecting a bad signature, which is the healthy state.
`scripts/wire_up_sms_provider_test.sh` asserts that distinction, and the other
twelve response shapes, with no network.

### Or by hand

1. **Authentication → Providers → Phone** — enable it, and make sure
   **automatic phone confirmation is OFF** (`sms_autoconfirm` in the API). With
   it on, Auth confirms the number without ever sending a code: the hook never
   fires, every other step here silently achieves nothing, and no error appears
   anywhere.
2. **Authentication → Hooks → Send SMS** — set it to **Supabase Edge Function**
   → `send-sms`. Copy the **signing secret** the page shows; it looks like
   `v1,whsec_<base64>`.
3. **Secrets** — the hook needs three:

   ```bash
   supabase secrets set SEND_SMS_HOOK_SECRET='v1,whsec_…'   # from step 2
   supabase secrets set TERMII_API_KEY='…'
   supabase secrets set TERMII_SENDER_ID='OE Alert'          # as approved by Termii
   ```

   `ALLOW_UNSENT_OTP` must stay **unset**. It lets auth proceed when SMS cannot
   be sent, which means the app tells the person a code was sent when none was.

4. **Deploy with JWT verification off.** This is not optional and it is not
   obvious:

   ```bash
   supabase functions deploy send-sms --no-verify-jwt
   ```

   The hook fires *before* any JWT exists. Deployed normally, the platform
   answers **401 before the function runs** — no logs, nothing in the function's
   own output, and from the app it looks exactly like a provider that is not
   configured. The Standard Webhooks signature is what protects the endpoint
   instead, and the hook refuses to run at all if its secret is unset.

5. **OTP length 6.** The app's code field is `maxLength: 6`, so a shorter code
   cannot be typed in full.

6. **Send yourself one.** A provider that is configured but not working looks
   identical to one that is not configured, from every screen in the app. Run
   `--check` first: it rules out everything except delivery, which is the only
   part a real handset is needed for.

### The hook as committed could never have worked

Worth knowing, because the symptom was indistinguishable from "not configured
yet" and it is why this stayed a blocker. Three independent faults, each enough
on its own:

| | |
|---|---|
| It read the code from `payload.otp` | Supabase sends it at `payload.sms.otp`, so the code was always `undefined` and the hook answered `400 Missing phone or OTP` to every real request |
| It authenticated with a bearer secret | These requests carry no `Authorization` header — they are signed per Standard Webhooks (`webhook-id`, `webhook-timestamp`, `webhook-signature`, HMAC-SHA256) — so every real call was refused `401` before it reached the payload fault |
| Nothing could test it | The logic was inline in a Deno `serve()` call, unreachable from any test suite |

Both contracts are now taken from the Supabase documentation source and the
Standard Webhooks specification rather than from memory, and the logic lives in
`supabase/functions/send-sms/hook.ts` with 25 tests in
`hq-dashboard-next/src/lib/send-sms-hook.test.ts` — including one per fault,
each mutation-checked to confirm it fails against the old behaviour.

### If a code still does not arrive

The hook never answers 200 for a message it did not send. An earlier version
did, commented "so sign-in is NOT blocked" — which unblocks nothing, since a
citizen with no code has nothing to type; it only decides whether they are told
or left watching a timer. So a failure is visible, and the app says which kind
it is:

| the app says | means |
|---|---|
| `SMS SIGN-IN IS NOT SWITCHED ON` | step 1 is not done — Supabase refused `signInWithOtp` outright |
| `SMS SIGN-IN IS MISCONFIGURED` | the hook ran and failed — a missing secret, or Termii refused or was unreachable |
| `TOO MANY CODES REQUESTED` | a real rate limit |
| `NO CONNECTION` | the handset's own network |

Check the function's logs in **Edge Functions → send-sms**. It logs the reason
and a masked number, and never the code — a one-time code in a log line is a
one-time code in the hands of whoever can read logs.

The app tells the person the truth when this is missing rather than "try again":
`AuthService._describeOtpSendFailure` recognises the provider-disabled refusals
and says *"SMS sign-in is not switched on for this service yet. Report this to
HQ — it is not your phone."* That is a deployment fault, and the person holding
the handset cannot fix it by retrying.

### Costs, and who pays

Every sign-in is a paid SMS. So is every re-entry code. Two decisions belong to
whoever owns the Termii account before launch, not after the first bill:

* the per-message cost and the expected volume (one per citizen sign-in, plus
  re-entry codes);
* a rate limit, in Supabase, so a script cannot drain the account by asking for
  codes for a list of numbers.

### Staff passwords must be rotated before launch — one was published

`AGENT_DEFAULT_PASS` was a single password shared by every staff account, read
by the app out of a `.env` that `pubspec.yaml` declares as a Flutter **asset** —
so it shipped verbatim inside the APK and extracts with `unzip`. The "access
code" officers typed was only the email local-part, i.e. a username. Anyone with
the app could sign in as any officer whose badge they knew or could guess.

The code path is gone and CI fails if it returns, but **that does not change the
passwords already set on those accounts**:

```bash
# Dry run first. Nothing is written.
NEXT_PUBLIC_SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... \
  node scripts/rotate_staff_passwords.js

# Then, with the roster in front of you:
NEXT_PUBLIC_SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... \
  node scripts/rotate_staff_passwords.js --commit --out passwords.txt
```

24 random bytes per account, different for every one — the defect was a single
shared value. It touches only profiles whose role is staff, and if an account
fails it continues and names it, because stopping early leaves the rest on the
published password.

Do it with the roster to hand, not at the end of a shift: until an officer has
their new password they cannot sign in, which is the correct state for an
account whose password was published, but it is not a surprise to spring on a
night shift. Hand them out of band and delete `passwords.txt`.

### The demo account must not ship

`DEMO_CITIZEN_EMAIL` and `DEMO_CITIZEN_PASS` in `.env` are a **real account with
a real password**, and `.env` ships inside the APK and extracts with `unzip`.
The code path that used them is compiled out of release builds now
(`AuthService.isDemoNumber` returns false under `kReleaseMode`), but the
credentials are still readable in the artifact if they are present in the file.
Leave both blank in the `.env` used for a release build, and make sure the
account itself is disabled in Supabase.

---

## 3. Mobile app

```bash
flutter build appbundle --release      # Play Store
flutter build ipa --release            # App Store
```

* **`.env` must exist at the repo root.** `pubspec.yaml` declares it as a
  Flutter *asset*, so the build fails outright without it. Copy `.env.example`
  and fill in `HQ_API_BASE_URL` and the Cloudinary values. Everything in that
  file ships inside the APK and extracts with `unzip` — it holds no secrets any
  more, and nothing secret may be added to it.
* **Signing.** `android/app/build.gradle.kts` reads `key.properties` from the
  repo root (gitignored, along with `*.jks` and `*.keystore`). If that file is
  missing the release `signingConfig` is left with null fields and the build
  produces an **unsigned** artifact that the Play Store rejects — it does not
  fall back to the debug key and it does not warn. Create it:

  ```properties
  storeFile=/absolute/path/to/upload-keystore.jks
  storePassword=…
  keyAlias=upload
  keyPassword=…
  ```

* **No Firebase config is needed.** The `com.google.gms.google-services` plugin
  was applied with no Firebase dependency in `pubspec.yaml`; it fails the build
  when `android/app/google-services.json` is missing, and that file is
  gitignored, so release builds could not succeed on a clean checkout. It has
  been removed from both Gradle files and the `GoogleService-Info.plist`
  references are gone from the Xcode project. A CI gate keeps them out.
* **Version.** `pubspec.yaml` is at `1.0.7+28`. Bump both parts before each
  store upload; the build number must increase or the store rejects the upload.
* Push notifications go through OneSignal, configured in the console's
  environment, not in the app.

---

## 4. After the first production deploy

* Sign in as a command user and confirm the board loads and the map draws — an
  RLS mistake shows up here first, as an empty board rather than an error.
* Confirm an alert raised on a phone appears on the board **without a reload**;
  that is the realtime publication working.
* Raise a test SOS with a photo and confirm the image renders in the console;
  that is the storage bucket and its policies working.
* Send a test broadcast scoped to one LGA and confirm it reaches a device in
  that LGA and **not** one outside it. Audience and geography were both silently
  ignored before; a success message from the console is not evidence.
* Set an emergency PIN under Settings → Emergency PIN on a device, then cancel a
  test SOS with it. Until a user sets one, cancellation reports `UNSET` and
  refuses — intended fail-closed behaviour, but worth seeing once.
* Review Supabase logs for anonymous reads of `profiles` and `telemetry` from
  before the RLS migration.
