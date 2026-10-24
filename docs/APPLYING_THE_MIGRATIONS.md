# Applying the migrations to production

**The paste carries 38 migrations.** That is a count of this repository, not of
your database — and the difference matters, because this file used to open with
`38 migrations … are not yet applied to the production Supabase project`,
which is a claim no file here can make. When that was finally checked
against a real database, **32 of them were already applied** and six were not.

So, before anything else:

### Which migrations does YOUR database still need?

Paste `scripts/which_migrations_are_applied.sql`. It is **read-only**, safe on
production, and one statement because the Supabase SQL editor shows only the
last result set. It checks every table, column and function the migrations
declare and returns one `summary` row each:

```
20261015000000_oversight_and_debrief     | 6 of 6 present
20261024000000_a_voice_note_…            | 0 of 4 present — NEVER APPLIED
20261023000000_one_table_one_shape       | 5 of 8 present — partly present
```

`N of N` is applied. `0 of N` was never applied. Anything between is either a
migration that failed partway — the worst case, worth looking at first — or a
CONVERGENCE migration whose columns already existed on that database, which is
what `20261023000000` is for and why it reads 5 of 8 on a database that has
production's own `detail`/`sent_by` columns and not its own `created_at` ones.
The `missing` rows below the summary name each absent object, so the two cases
are easy to tell apart.

### Then paste what it says you need — or all of it

Both are correct. Every statement in every migration is `IF NOT EXISTS`,
`OR REPLACE` or guarded by an explicit existence check, and
`scripts/verify_apply_all.sh` applies the whole bundle **twice** on every push
to prove it. So pasting a migration a database already has is a no-op, and
pasting all 46 is always safe. The reason to know which ones are missing is
not safety — it is being able to tell, afterwards, whether anything changed.

The complete table of all 46, in apply order, with what breaks until each one
runs, is in `docs/PRODUCTION_DEPLOYMENT.md`, and
`scripts/check_runbook_covers_migrations.py` fails CI if a migration is added
and that table does not describe it.

This file is the **step-by-step** runbook, and the steps below cover the first
nine — the C-3 least-privilege era, where the order has dependencies and a
failure needs a human decision. Read it before the first paste either way: the
RLS migration drops prior policies by exact name, and a policy made by hand in
the dashboard survives it.

The nine covered one at a time below:

| Order | File | Closes |
|---|---|---|
| 1 | `supabase/migrations/20260812000000_agency_tables.sql` | the `agency_*` tables existing only in production |
| 2 | `supabase/migrations/20260813000000_rls_least_privilege.sql` | C-3 (and with it C-4, H-7) |
| 3 | `supabase/migrations/20260902000000_per_user_emergency_pins.sql` | the shared duress PIN (H-3 residual) |
| 4 | `supabase/migrations/20260903000000_realtime_publication.sql` | subscriptions on unpublished tables |
| 5 | `supabase/migrations/20260903000001_incident_media_storage.sql` | the undocumented media bucket |
| 6 | `supabase/migrations/20260903000002_system_alerts_broadcast.sql` | mass broadcast, which never worked at all |
| 7 | `supabase/migrations/20260903000003_alert_escalation_columns.sql` | escalation columns that live only in production |
| 8 | `supabase/migrations/20260903000004_profiles_badge_number.sql` | the officer badge label both apps display |
| 9 | `supabase/migrations/20260903000005_alerts_assigned_tier.sql` | tier escalation, which was rejected outright |

Apply them in that order. Number 3 depends on the `alerts.resolved_by` /
`resolved_at` columns and on `auth.users`. Number 1 must precede number 2, which
puts policies on the tables it creates — on production those tables already
exist and number 1 does nothing, which is the point: it makes a rebuilt staging
or disaster-recovery project match production instead of silently lacking the
agency portal's entire backend.

For the deployment around these — hosting, environment, signing — see
`docs/PRODUCTION_DEPLOYMENT.md`.

## The short way

Two pastes, in this order:

1. **`scripts/rls_production_dryrun.sql`** — read-only, rolls everything back,
   prints a verdict. If it says `>>> DO NOT APPLY`, stop: the PROBLEM lines name
   a hand-made policy that would survive the migration and re-open a table.
2. **`scripts/apply_all_migrations.sql`** — all 46, in order, finishing with a
   34-row PASS/FAIL table. Every row PASS means you are done. Both numbers are
   generated and gated, so if the table you get is a different size, you are
   not running the file this repository builds.

Both are generated from the migrations and CI fails if either drifts. The
`apply-all` job runs the second one against a production-shaped PostgreSQL on
every push — the whole buffer, top to bottom, twice, asserting on its own
verdict table — so what you paste is a script that has been executed, not just
concatenated.

Everything below is the first nine of those migrations one at a time, with the
reasoning for each. Use it if a step fails, or if you would rather see the C-3
era go in individually — the rest carry no ordering decision a person has to
make, and the single paste above is the way to apply them.

Everything below runs in **Supabase Dashboard → SQL Editor**, signed in as the
project owner. Nothing here needs a connection string, and none of it should be
pasted into a chat, ticket or log — the point of C-3 is that credentials have
been in the wrong places before.

> **Never run `scripts/verify_rls.js` against production.** It INSERTs probe
> rows. It is for a throwaway staging project only.

---

## Step 0 — three read-only checks (30 seconds)

Run each; every one is a `SELECT`.

```sql
-- 0a. The PIN migration needs these two columns (added by phase2). Expect 2 rows.
select column_name from information_schema.columns
 where table_schema = 'public' and table_name = 'alerts'
   and column_name in ('resolved_by', 'resolved_at');

-- 0b. Every policy that exists today. Keep this output — it is your "before".
select tablename, policyname, cmd, roles, qual, with_check
  from pg_policies where schemaname = 'public' order by tablename, policyname;

-- 0c. pgcrypto is available (Supabase ships it). Expect 1 row.
select name from pg_available_extensions where name = 'pgcrypto';
```

If 0a returns fewer than 2 rows, apply `supabase/migrations/phase2_assigned_responders.sql`
first — it is idempotent (`ADD COLUMN IF NOT EXISTS`).

## Step 1 — the dry run (read-only, mandatory)

Paste the **whole** of `scripts/rls_production_dryrun.sql` and run it.

It creates the new policies inside a transaction, runs the real assertions
against your real rows and roles, and then **rolls everything back**. It inserts
nothing and deletes nothing. It ends by raising an error **on purpose** — that
error is the result, because the SQL Editor does not show `NOTICE` output and
this is the only way to make the verdict visible. Read its first line:

```
===== RLS DRY RUN — >>> SAFE TO APPLY =====      → go to step 2
===== RLS DRY RUN — >>> DO NOT APPLY =====       → stop; PROBLEM lines follow
```

Why this exists: the migration drops prior policies **by exact name**. A policy
someone created by hand in the dashboard survives it, and PostgreSQL combines
permissive policies with OR — so one surviving `USING (true)` re-opens the
table and the migration becomes decorative. That is exactly how the previous
attempt (`phase1_foundation.sql`) failed. The dry run is how you find out
without a staging project. If it says DO NOT APPLY, the PROBLEM lines name the
policy; drop it by hand, re-run the dry run, and only then continue.

If instead you see `ABORT: marker …`, stop and check `pg_policies` — it means
a COMMIT happened inside the run. This should be impossible (the generator
strips the migration's transaction control and checks a marker), but the guard
exists precisely so you would know.

## Step 1a — apply the agency-tables migration

Paste the whole of `supabase/migrations/20260812000000_agency_tables.sql` and
run it now, before the RLS migration in step 2. On production every statement is a no-op: the four
`agency_*` tables and `profiles.agency` were created by hand and already exist,
and every `CREATE` here is `IF NOT EXISTS`, so production's column shapes are
kept exactly as they are. Nothing is narrowed and nothing is dropped.

Verify, read-only:

```sql
-- Expect 4 rows.
select table_name from information_schema.tables
 where table_schema = 'public' and table_name like 'agency\_%' order by 1;
```

## Step 2 — apply the RLS migration

Paste the whole of `supabase/migrations/20260813000000_rls_least_privilege.sql`
and run it. It carries its own `BEGIN` … `COMMIT`: it applies completely or not
at all. It raises a few `NOTICE: skipping …: table not present` lines, which are
expected — but **you will not see them in the Supabase SQL editor**, which
discards `NOTICE` output and reports only `Success. No rows returned`. That is
the same reason the dry run above has to signal its verdict by raising an error.
Run it through `psql` if you want to read the notices.

**A migration whose only output is a notice therefore looks identical to one
that did nothing.** Three of them are exactly that shape — `20261016000000`,
`20261017000000` and `20261018000000` — so there is a read-only query that
answers the question in rows instead:

```
scripts/did_the_convergence_land.sql
```

One statement, three verdicts, safe on production. The 34-row verdict table
cannot replace it: not one of its checks looks for the ABSENCE of the five
generated mirrors or the two dropped functions, and absence is the only evidence
a drop-only migration can leave.

Then verify, read-only:

```sql
-- Expect 0: no permissive policy grants anon anything.
select count(*) from pg_policies
 where schemaname = 'public' and permissive = 'PERMISSIVE'
   and ('anon' = any(roles) or 'public' = any(roles));

-- Expect 1: the role-escalation trigger is installed.
select count(*) from pg_trigger where tgname = 'profiles_no_privilege_escalation';
```

## Step 3 — apply the emergency-PIN migration

Paste the whole of `supabase/migrations/20260902000000_per_user_emergency_pins.sql`
and run it. Idempotent — safe to run twice.

Verify, read-only:

```sql
-- Expect 4 rows: set_emergency_pins, has_emergency_pins, verify_emergency_pin, resolve_emergency
select proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and proname like '%emergency%' and proname not like '\_%' order by 1;

-- Expect 0 rows: the hashes table is unreadable through the API roles.
select grantee, privilege_type from information_schema.role_table_grants
 where table_schema = 'public' and table_name = 'emergency_pins'
   and grantee in ('anon', 'authenticated');
```

## Step 3a — realtime and storage

Paste and run, in this order, both idempotent:

* `supabase/migrations/20260903000000_realtime_publication.sql` — adds
  `agency_action_reports`, `agency_deployments` and `uninstall_requests` to the
  `supabase_realtime` publication. The console subscribes to all three today;
  a subscription on an unpublished table raises no error and simply never
  fires, so HQ's unread-report badge only updated on page reload.
* `supabase/migrations/20260903000001_incident_media_storage.sql` — creates the
  `incident-media` bucket the mobile app falls back to when Cloudinary is
  unavailable, and puts policies on it: any signed-in user may upload, nobody
  may update or delete through the API roles, and only staff may list it.
* `supabase/migrations/20260903000002_system_alerts_broadcast.sql` — adds the
  columns the mass-broadcast screens have always written to, gives `title` a
  default, and backfills `target_audience` from the legacy `target_type`. Until
  this runs, **every broadcast fails**: `title` is NOT NULL and neither writer
  supplied it, and six of the console's columns did not exist.
* `supabase/migrations/20260903000003_alert_escalation_columns.sql` — adds
  `alerts.escalated_to_agency` and `alerts.escalation_log`. Both are written by
  both apps and read by the agency portal, and neither was in any migration.
  **On production they already exist** (added by hand) and this is a no-op; on a
  rebuilt project, escalation fails in full without them.

Verify, read-only:

```sql
-- Expect 8 rows.
select tablename from pg_publication_tables
 where pubname = 'supabase_realtime' and schemaname = 'public' order by 1;

-- Expect 1 row: public, 52428800, {image/*,video/*,audio/*}.
select id, public, file_size_limit, allowed_mime_types
  from storage.buckets where id = 'incident-media';

-- Expect 2 rows: the escalation columns.
select column_name from information_schema.columns
 where table_schema = 'public' and table_name = 'alerts'
   and column_name in ('escalated_to_agency','escalation_log') order by 1;

-- Expect 6 rows: the broadcast scoping columns.
select column_name from information_schema.columns
 where table_schema = 'public' and table_name = 'system_alerts'
   and column_name in ('target_audience','target_agency','target_lga',
                       'target_ward','target_pu','expires_at') order by 1;

-- Expect the two incident_media_* policies and nothing else touching this
-- bucket. Anything else is an extra PERMISSIVE grant that ORs with them.
select policyname, cmd, roles from pg_policies
 where schemaname = 'storage' and tablename = 'objects' order by policyname;
```

## Step 4 — roll out the app

The migration is backward compatible: builds that still carry the old
`.env` PINs keep working (their client-side update is still permitted by the
`alerts_update_own_or_staff` policy), so you can migrate first and ship the app
second.

Ship the current mobile build. New users set their PINs at the end of
onboarding; existing users are told on the cancel sheet to set one under
**Settings → Emergency PIN** — until they do, the sheet reports `UNSET` and
cannot cancel an SOS, which is the intended fail-closed behaviour.

## Rolling back

* **Step 2** cannot half-apply. If it errors, nothing changed. To undo it
  after a successful apply, restore the policies from your step-0b listing —
  there is no automated reverse migration, by design: the previous policies
  are the vulnerability.
* **Step 3**:
  ```sql
  drop function if exists public.resolve_emergency(uuid, text),
                         public.verify_emergency_pin(text),
                         public.has_emergency_pins(),
                         public.set_emergency_pins(text, text),
                         public._check_emergency_pin(uuid, text);
  drop table if exists public.emergency_pins;
  ```

## Still outstanding after this

Applying these closes C-3, C-4, H-7 and the shared-PIN finding. It does not
settle C-6 — whether the orphaned Firebase functions are still deployed — which
is step 0 of `docs/PRODUCTION_DEPLOYMENT.md`.
