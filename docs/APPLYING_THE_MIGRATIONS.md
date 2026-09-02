# Applying the migrations to production

Two migrations are proven in CI on every push and **not yet applied** to the
production Supabase project:

| Order | File | Closes |
|---|---|---|
| 1 | `supabase/migrations/20260813000000_rls_least_privilege.sql` | C-3 (and with it C-4, H-7) |
| 2 | `supabase/migrations/20260902000000_per_user_emergency_pins.sql` | the shared duress PIN (H-3 residual) |

Apply them in that order. Number 2 depends on the `alerts.resolved_by` /
`resolved_at` columns and on `auth.users`; number 1 does not depend on 2.

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

## Step 2 — apply the RLS migration

Paste the whole of `supabase/migrations/20260813000000_rls_least_privilege.sql`
and run it. It carries its own `BEGIN` … `COMMIT`: it applies completely or not
at all. A few `NOTICE: skipping …: table not present` lines are expected.

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

Applying these closes C-3, C-4, H-7 and the shared-PIN finding. It does **not**
rotate anything. The credentials that were in git history remain compromised
until rotated, regardless of the purge — see H-6 in `E2E_AUDIT_REPORT.md`.
