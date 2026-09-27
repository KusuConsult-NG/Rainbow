# Operation Rainbow

Emergency security response for Plateau State, Nigeria. A citizen and responder
mobile app, a command console for HQ, and a Supabase backend they share.

When someone presses SOS, an alert reaches the HQ board with their live
location; HQ dispatches responders, escalates up the command chain or hands the
incident to an outside agency, and the citizen can cancel with a PIN — or with
a *different* PIN that cancels the visible alarm while quietly keeping HQ
tracking them.

That last detail is the shape of the whole system: **the difference between
"nothing is happening" and "something is broken" has to be visible.** A blank
board, an empty feed and a quiet night must never look alike. Most of the
engineering below exists to keep that true.

---

## The three pieces

| | | |
|---|---|---|
| **Mobile app** | `lib/`, Flutter 3 / Dart 3 | Citizens report incidents and raise SOS; responders receive dispatches, run missions and stream live video |
| **HQ console** | `hq-dashboard-next/`, Next.js 16 + React 19 | The operations board: live map, incident feed, dispatch, escalation, agency portal, mass broadcast |
| **Backend** | `supabase/migrations/` | PostgreSQL with row-level security, realtime subscriptions, storage for incident media, and SECURITY DEFINER functions for the duress PINs |

There is no other backend. A Firebase/Firestore stack preceded this one and was
deleted once confirmed orphaned; if you find a reference to it, it is a leftover
and should go too.

## Layout

```
lib/                      Flutter app
test/                     23 Flutter test files
hq-dashboard-next/        Next.js console (its own package.json)
  src/app/                routes, API handlers, error boundaries
  src/components/         board widgets, map, agency portal
  src/lib/                pure logic — extracted so it can be tested
supabase/migrations/      the schema, in filename order
scripts/                  migration harness, generators, drift checker
docs/                     runbooks
E2E_AUDIT_REPORT.md       findings, fixes, and what remains
```

---

## Running it

### Mobile

```bash
cp .env.example .env       # required: pubspec declares .env as a Flutter ASSET,
                           # so the build fails outright without it
flutter pub get
flutter test               # 23 test files
flutter analyze            # warnings fail CI, so keep it clean
flutter run
```

**Nothing secret goes in `.env`.** Flutter assets ship verbatim inside the
APK and extract with `unzip`. That file once held the SMS provider key, the
Cloudinary secret and the shared duress PIN; all of them are gone, and a CI gate
stops them coming back.

### HQ console

```bash
cd hq-dashboard-next
cp .env.example .env.local # fill in before building, not after
npm ci
npm run dev
npm test                   # 118 tests
npx tsc --noEmit && npx eslint
```

`NEXT_PUBLIC_*` values are inlined **at build time**. A missing one is not a
runtime warning — the app crashes on first render and serves
`<html id="__next_error__">`.

### Database

Nine migrations. Applying them is two pastes into the Supabase SQL editor —
`scripts/rls_production_dryrun.sql` (read-only, prints a verdict), then
`scripts/apply_all_migrations.sql` (all nine, finishing with a PASS/FAIL table).
Both are generated from the migrations, CI fails if either drifts, and the
second is executed against a production-shaped PostgreSQL on every push.

**Read `docs/APPLYING_THE_MIGRATIONS.md` before the first one** — the RLS migration drops prior
policies by exact name, and a policy someone created in the Supabase dashboard
survives it. PostgreSQL ORs permissive policies together, so one survivor
re-opens the table and the migration becomes decorative. The runbook's dry run
is how you find that out without a staging project.

To prove the migrations against a real PostgreSQL, with no credentials and no
live data:

```bash
sudo ./scripts/verify_rls_migration.sh
```

It builds a throwaway database, replays the history, applies every migration
twice to prove idempotence, and runs 36 behavioural assertions — what anon, a
citizen, a responder, an agency liaison and a commander can each actually *do*.

> `scripts/verify_rls.js` INSERTs probe rows. **Never run it against
> production.** Staging only.

### Staging

`docs/STAGING.md` — one free Supabase project, about ten minutes. It is the only
way to test what a local replica cannot: a real PostgREST, a real Auth service,
and the policies somebody added by hand in a dashboard. Production had 44
policies where a replica rebuilt from this repo had 21.

```bash
# 1. paste scripts/bootstrap_staging.sql into a NEW project
# 2. seed one account per role, plus incidents chosen to expose old defects
RAINBOW_ENV=staging SUPABASE_URL=… SUPABASE_SERVICE_ROLE_KEY=… node scripts/seed_staging.js
# 3. the point of the exercise
NEXT_PUBLIC_SUPABASE_URL=… NEXT_PUBLIC_SUPABASE_ANON_KEY=… node scripts/verify_rls.js
```

---

### Every screen, in a real browser

```bash
./scripts/local_e2e/run.sh      # ~2 minutes, no credentials, no network
```

A stand-in Supabase, a production build of the console, a real Chromium, and a
screenshot of every screen for every role — 51 of them, into
`local_e2e_screenshots/`, with `report.json` beside them.

It needs nothing from outside the machine, which is the point: until it existed
**no console screen in this repository had ever been rendered.** Every console
finding came from reading code or from unit tests of logic lifted out so it
could be tested, and the wiring between them — where the worst defects lived —
was never exercised. The first run found a panel that had been broken on the
default branch the whole time.

The stand-in builds its tables from `supabase/migrations/`, so a query naming a
column no migration defines is rejected here exactly as PostgREST rejects it in
production — in full, taking the select, the filters and the order with it.

> It proves the **screens**, not the policies. The fake answers every query. Row
> level security can only be proven against a real PostgREST — `verify_rls.js`
> against a staging project.

---

## What CI enforces

Ten jobs, each tied to a defect that reached the default branch at least once.

| job | what it prevents |
|---|---|
| Flutter — analyze & test | analyzer warnings, and SMS-provider credentials returning to the handset |
| HQ dashboard | typecheck, lint, build, tests, security headers, **server secrets in the client bundle**, demo credentials in a production build |
| Repo — no credential material | any credential-shaped string in a tracked file |
| Supabase — RLS migration correctness | the migrations, proven behaviourally against real PostgreSQL |
| Supabase — dry run in sync | the generated scripts are what get pasted into a live SQL editor; a stale copy is worse than none, because it looks authoritative |
| Supabase — one-paste apply script | runs `apply_all_migrations.sql` against a production-shaped database, top to bottom, twice, and asserts on its own PASS/FAIL table |
| Supabase — staging bootstrap | builds a project from zero, checks the bootstrap refuses a database that already holds data, and proves both routes reach the same schema |
| Supabase — dry run reports something | that the dry run emits a verdict rather than silence, which on a "is this safe?" script is the most dangerous output it could give |
| HQ console — every screen, in a real browser | a screen that crashes, renders empty, or asks the database for something it does not have. Screenshots are kept as a build artifact, pass or fail |
| Supabase — anon-access probe | manual only; fails if anon can read or write a sensitive table |

Two gates worth knowing about because they catch a whole class rather than a
single bug:

- **`scripts/check_schema_drift.py`** — every column either app reads or writes,
  every column it *orders by*, every embedded resource it asks PostgREST to
  join, and every `.rpc()` function it calls, must exist in a migration.
  PostgREST rejects a query naming an unknown column *in full*, so drift here
  fails at runtime and nowhere else. It found a mass-broadcast screen writing
  six columns that did not exist, an escalation path writing two more, and a
  profile lookup selecting three.

  It also used to have two holes, both closed after the browser run found what
  they hid: it waved through `id`, `created_at` and `updated_at` on every table
  as "columns any table has" — they are not, and that exemption is shaped
  exactly like the most common column names in the codebase — and it skipped
  any select containing `(`, `*` or `:` as too awkward to parse, which meant
  skipping the queries most likely to be wrong.
- **the realtime-subscription gate** — every table either app subscribes to must
  be in the `supabase_realtime` publication. A subscription on an unpublished
  table does not error; it simply never fires.

---

## Deploying

`docs/PRODUCTION_DEPLOYMENT.md` is the runbook. In short: Firebase App Hosting
(`firebase.json` + `hq-dashboard-next/apphosting.yaml`), then `./deploy.sh`.

It must run as a **Node server, never a static export** — the auth guard is
Next.js middleware, and a static export silently drops middleware, serving every
page to anonymous visitors with no error anywhere.

Every environment value comes from Secret Manager, including the two public
ones, so no project configuration is committed to git. `deploy.sh` checks the
secrets are readable before spending a build, and re-scans the built bundle for
server secrets before it will deploy.

Mobile release builds need `key.properties` at the repo root, or the release
artefact is **unsigned** — Gradle does not fall back to the debug key and does
not warn.

---

## Security

`E2E_AUDIT_REPORT.md` is the long version: every finding, what was done, and
what was deliberately not. The parts worth knowing before you touch anything:

- **Row-level security is the whole access model.** The anon key is public by
  design — it ships in the app bundle and the browser — so a policy mistake is
  not a degraded experience, it is an open database. Nothing may be granted to
  `anon`.
- **Roles come from `profiles.role`**, which a database trigger makes
  non-self-writable. Nothing reads `user_metadata`, which the client can set.
- **Duress PINs are per-user and verified server-side**, bcrypt-hashed in a
  table no API role can read, with lockout after five failures. The device
  never sees PIN material. Under duress the alert is marked and tracking
  deliberately continues.
- **Incident media is append-only.** Any signed-in user may upload; nobody may
  update or delete through the API roles, and only staff may list the bucket.
- **Credential scanning catches credential *shapes***, not weak passwords. A
  shared demo password sat in the tree for months because a password is just a
  string. Do not assume the gate covers it.

---

## Outstanding

The code is current. These need production access and are tracked in the audit
report:

1. **`firebase functions:list --project rainbow-97f1e`, then delete the
   deployment.** Two functions answer on public URLs, and a watchdog fires every
   five minutes against a datastore nothing backs any more. Do **not** `curl`
   `seedMockData` to check — the probe itself writes ten fabricated emergencies.
2. **Apply the nine migrations** — dry run first.
3. **First deploy**, which is also the first test of the deploy config.
4. **Ask GitHub Support** to purge the `refs/pull/*` refs still holding
   pre-purge objects.
