-- ============================================================================
-- PRODUCTION DRY RUN — generated file, do not edit by hand.
--   Regenerate with: python3 scripts/build_rls_dryrun.py
--
--   Paste the WHOLE of this file into the Supabase dashboard -> SQL Editor and
--   run it. It ends in ROLLBACK. Nothing it does is kept.
--
-- WHY THIS EXISTS
--
-- The migration is proven correct against a replica rebuilt from this repo's
-- migration files. That replica cannot contain policies somebody created by hand
-- in the Supabase dashboard -- and the migration drops prior policies BY EXACT
-- NAME, so a hand-made policy survives it. PostgreSQL combines PERMISSIVE
-- policies with OR, so one surviving `USING (true)` re-opens the table and the
-- migration becomes decorative. That is exactly how phase1_foundation.sql failed.
-- It is finding C-3, and with no staging project this is how you find out.
--
-- WHAT IT DOES
--
-- PostgreSQL has transactional DDL, so the policies really are created, the
-- assertions really do run against your real rows and real roles, and then all
-- of it is discarded. It INSERTS NOTHING and DELETES NOTHING. Every assertion is
-- a SELECT, or an UPDATE that is expected to be blocked.
--
-- THE ONE THING THAT COULD GO WRONG, AND THE GUARD FOR IT
--
-- The migration ships its own BEGIN/COMMIT. A nested COMMIT would end the outer
-- transaction and make this permanent. Its transaction control has been stripped
-- during generation, AND a temp marker created with ON COMMIT DROP is checked
-- afterwards: if anything committed, the marker is gone and the script aborts.
--
-- HOW TO READ THE OUTPUT
--
-- Read the NOTICE messages. `>>> SAFE TO APPLY` at the end means the migration
-- did the right thing against your real data. `>>> PROBLEM` means do not apply
-- it yet. The final SELECT must match the BEFORE numbers, proving nothing stuck.
-- ============================================================================

BEGIN;

-- Tripwire. ON COMMIT DROP means this disappears the instant anything commits.
CREATE TEMP TABLE _dryrun_marker(ok boolean) ON COMMIT DROP;
INSERT INTO _dryrun_marker VALUES (true);

-- ── 1. What is there right now ──────────────────────────────────────────────
-- Read this in the results pane. Any policy name you do not recognise from
-- supabase/migrations/ was made by hand, and is the risk this script exists for.
SELECT tablename, policyname, cmd, roles,
       CASE WHEN qual = 'true' OR with_check = 'true'
            THEN '*** WIDE OPEN ***' ELSE '' END AS warning
FROM pg_policies WHERE schemaname = 'public'
ORDER BY warning DESC, tablename, policyname;

DO $dryrun$
DECLARE n_open INT; n_total INT;
BEGIN
  SELECT count(*) INTO n_total FROM pg_policies WHERE schemaname='public';
  SELECT count(*) INTO n_open  FROM pg_policies
   WHERE schemaname='public' AND (qual='true' OR with_check='true');
  RAISE NOTICE 'BEFORE: % policies on public, % of them USING(true)/WITH CHECK(true)',
    n_total, n_open;
END $dryrun$;

-- ============================================================================
-- 2. THE MIGRATION (transaction control stripped during generation)
-- ============================================================================
-- ============================================================================
-- OPERATION RAINBOW — RLS LEAST-PRIVILEGE REMEDIATION
-- Addresses E2E_AUDIT_REPORT.md finding C-3 (critical).
--
-- WHY THIS EXISTS
-- ---------------
-- `20260720000000_initial_schema.sql` created policies with `USING (true)`, which
-- grants the `anon` role unrestricted access. Because the anon key is public by
-- design (it ships in the mobile app and the web bundle), the entire database was
-- readable and writable by anyone on the internet: citizen PII, live GPS telemetry
-- of people who had pressed SOS, dispatcher chat logs, and alert status.
--
-- `phase1_foundation.sql` LOOKS like it fixed this. It does not. It adds strict
-- policies under NEW names (chat_read, telemetry_own_upsert, ...) but only drops
-- policies by those same new names. The permissive originals survive, and
-- PostgreSQL combines multiple PERMISSIVE policies with OR — so the wide-open
-- policy still grants access and the strict one is a no-op. This migration drops
-- every prior policy BY ITS EXACT ORIGINAL NAME before re-issuing.
--
-- It also closes a privilege-escalation path that defeats the API-route
-- authorisation added in `hq-dashboard-next/src/lib/supabase-server.ts`:
-- the old profiles policy was `FOR ALL USING (auth.uid() = id)` with no column
-- restriction, so any authenticated citizen could set their own `role` to
-- 'HQ_COMMAND' and pass a server-side role check.
--
-- BEFORE RUNNING
-- --------------
--   1. Run on STAGING first, then run `scripts/verify_rls.js` against it.
--   2. This migration was written from the migration files in this repo, NOT from
--      a live `pg_policies` dump. If policies were ever created by hand in the
--      Supabase dashboard they will NOT be dropped here. Verify with:
--         SELECT tablename, policyname, cmd, qual, with_check
--         FROM pg_policies WHERE schemaname = 'public' ORDER BY tablename;
--      and add any unexpected names to the DROP section below.
--   3. Idempotent: safe to re-run.
-- ============================================================================

-- [dry run] stripped: BEGIN;

-- ────────────────────────────────────────────────────────────────────────────
-- 1. HELPERS
--
-- SECURITY DEFINER so they can read `profiles` without being subject to the
-- policies we are about to put ON `profiles` — otherwise a policy that consults
-- profiles to decide access to profiles recurses infinitely.
-- `SET search_path` prevents search_path hijacking of a SECURITY DEFINER function.
-- ────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.auth_role()
RETURNS TEXT
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT role FROM public.profiles WHERE id = auth.uid();
$$;

-- Any operational (non-citizen) user: responders and all command tiers.
CREATE OR REPLACE FUNCTION public.is_staff()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT role FROM public.profiles WHERE id = auth.uid())
      NOT IN ('CITIZEN', 'USER'),
    false
  );
$$;

-- Command tiers only — may broadcast, manage config, and escalate to agencies.
CREATE OR REPLACE FUNCTION public.is_command()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT role FROM public.profiles WHERE id = auth.uid())
      IN ('HQ_COMMAND', 'HQ_OFFICER', 'ADMIN', 'LGA_COMMAND'),
    false
  );
$$;

REVOKE EXECUTE ON FUNCTION public.auth_role()  FROM anon;
REVOKE EXECUTE ON FUNCTION public.is_staff()   FROM anon;
REVOKE EXECUTE ON FUNCTION public.is_command() FROM anon;

-- ────────────────────────────────────────────────────────────────────────────
-- 2. DROP EVERY PRE-EXISTING POLICY BY EXACT NAME
--    (the step phase1_foundation.sql omitted)
-- ────────────────────────────────────────────────────────────────────────────

-- from 20260720000000_initial_schema.sql / supabase_schema_setup.sql
DROP POLICY IF EXISTS "Allow public read access to profiles"          ON public.profiles;
DROP POLICY IF EXISTS "Allow individual insert/update to own profile" ON public.profiles;
DROP POLICY IF EXISTS "Allow authenticated users to read alerts"      ON public.alerts;
DROP POLICY IF EXISTS "Allow authenticated users to insert alerts"    ON public.alerts;
DROP POLICY IF EXISTS "Allow authenticated users to update alerts"    ON public.alerts;
DROP POLICY IF EXISTS "Allow reading telemetry"                       ON public.telemetry;
DROP POLICY IF EXISTS "Allow users to update own telemetry"           ON public.telemetry;
DROP POLICY IF EXISTS "Allow reading chat messages"                   ON public.chat_messages;
DROP POLICY IF EXISTS "Allow inserting chat messages"                 ON public.chat_messages;
DROP POLICY IF EXISTS "Allow reading system alerts"                   ON public.system_alerts;
DROP POLICY IF EXISTS "Allow service role to manage system alerts"    ON public.system_alerts;

-- from phase1_foundation.sql / phase3_profile_columns_and_config.sql
DROP POLICY IF EXISTS "chat_read"                        ON public.chat_messages;
DROP POLICY IF EXISTS "chat_insert"                      ON public.chat_messages;
DROP POLICY IF EXISTS "telemetry_own_upsert"             ON public.telemetry;
DROP POLICY IF EXISTS "telemetry_read_all"               ON public.telemetry;
DROP POLICY IF EXISTS "safe_zones_read"                  ON public.safe_zones;
DROP POLICY IF EXISTS "uninstall_insert"                 ON public.uninstall_requests;
DROP POLICY IF EXISTS "uninstall_read"                   ON public.uninstall_requests;
DROP POLICY IF EXISTS "app_config_read"                  ON public.app_config;
DROP POLICY IF EXISTS "app_config_read_authenticated"    ON public.app_config;
DROP POLICY IF EXISTS "app_config_write_service_role"    ON public.app_config;

-- ────────────────────────────────────────────────────────────────────────────
-- 3. ENABLE RLS EVERYWHERE (no-op where already on)
-- ────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.profiles           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.alerts             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.telemetry          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_messages      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.system_alerts      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.safe_zones         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.uninstall_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_config         ENABLE ROW LEVEL SECURITY;

-- ────────────────────────────────────────────────────────────────────────────
-- 4. PROFILES
--    Citizens see only themselves. Staff see the directory (the dashboard needs
--    reporter and officer names). Nobody may change their own role/tier.
-- ────────────────────────────────────────────────────────────────────────────

CREATE POLICY "profiles_select_self_or_staff" ON public.profiles
  FOR SELECT TO authenticated
  USING (id = auth.uid() OR public.is_staff());

CREATE POLICY "profiles_insert_self" ON public.profiles
  FOR INSERT TO authenticated
  WITH CHECK (id = auth.uid());

CREATE POLICY "profiles_update_self" ON public.profiles
  FOR UPDATE TO authenticated
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

-- Privilege-escalation guard.
--
-- A WITH CHECK clause cannot reference the OLD row, so column immutability is
-- enforced with a trigger instead. Without this, `profiles_update_self` would let
-- any citizen run:
--     update profiles set role = 'HQ_COMMAND' where id = auth.uid();
-- and then pass every server-side role check in the HQ dashboard.
CREATE OR REPLACE FUNCTION public.prevent_profile_privilege_escalation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- service_role (backend / admin tooling) may legitimately change roles.
  IF current_setting('request.jwt.claim.role', true) = 'service_role'
     OR auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.role IS DISTINCT FROM OLD.role THEN
    RAISE EXCEPTION
      'Changing profiles.role is not permitted (uid=%, % -> %)',
      auth.uid(), OLD.role, NEW.role
      USING ERRCODE = '42501';
  END IF;

  IF NEW.tier IS DISTINCT FROM OLD.tier THEN
    RAISE EXCEPTION
      'Changing profiles.tier is not permitted (uid=%)', auth.uid()
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS profiles_no_privilege_escalation ON public.profiles;
CREATE TRIGGER profiles_no_privilege_escalation
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.prevent_profile_privilege_escalation();

-- ────────────────────────────────────────────────────────────────────────────
-- 5. TELEMETRY — the most sensitive table in the system.
--    Live GPS of citizens who have pressed SOS and of officers on patrol.
--    Was `FOR ALL USING (true)`: anyone could read AND falsify positions.
-- ────────────────────────────────────────────────────────────────────────────

CREATE POLICY "telemetry_select_self_or_staff" ON public.telemetry
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_staff());

CREATE POLICY "telemetry_insert_own" ON public.telemetry
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "telemetry_update_own" ON public.telemetry
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- ────────────────────────────────────────────────────────────────────────────
-- 6. ALERTS
-- ────────────────────────────────────────────────────────────────────────────

CREATE POLICY "alerts_select_own_or_staff" ON public.alerts
  FOR SELECT TO authenticated
  USING (
    reported_by = auth.uid()
    OR assigned_to = auth.uid()
    OR public.is_staff()
  );

CREATE POLICY "alerts_insert_as_self" ON public.alerts
  FOR INSERT TO authenticated
  WITH CHECK (reported_by = auth.uid() OR public.is_staff());

-- NOTE: the reporter is intentionally allowed to update their own alert, because
-- the mobile duress/safe-PIN flow resolves an alert client-side
-- (emergency_provider.dart::verifyCancellation). Residual risk: someone holding a
-- victim's unlocked phone can mark the SOS resolved. Moving resolution behind an
-- RPC that records WHO resolved it is the follow-up.
CREATE POLICY "alerts_update_own_or_staff" ON public.alerts
  FOR UPDATE TO authenticated
  USING (
    reported_by = auth.uid()
    OR assigned_to = auth.uid()
    OR public.is_staff()
  );

-- ────────────────────────────────────────────────────────────────────────────
-- 7. CHAT MESSAGES
-- ────────────────────────────────────────────────────────────────────────────

CREATE POLICY "chat_select_participant_or_staff" ON public.chat_messages
  FOR SELECT TO authenticated
  USING (
    sender_id = auth.uid()
    OR public.is_staff()
    OR EXISTS (
      SELECT 1 FROM public.alerts a
      WHERE a.id = chat_messages.alert_id
        AND (a.reported_by = auth.uid() OR a.assigned_to = auth.uid())
    )
  );

CREATE POLICY "chat_insert_as_self" ON public.chat_messages
  FOR INSERT TO authenticated
  WITH CHECK (sender_id = auth.uid());

-- ────────────────────────────────────────────────────────────────────────────
-- 8. SYSTEM ALERTS — state-wide advisories. Was `FOR ALL USING (true)`, so anon
--    could push a state-wide emergency broadcast.
-- ────────────────────────────────────────────────────────────────────────────

CREATE POLICY "system_alerts_read" ON public.system_alerts
  FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "system_alerts_write_command" ON public.system_alerts
  FOR INSERT TO authenticated
  WITH CHECK (public.is_command());

CREATE POLICY "system_alerts_update_command" ON public.system_alerts
  FOR UPDATE TO authenticated
  USING (public.is_command());

CREATE POLICY "system_alerts_delete_command" ON public.system_alerts
  FOR DELETE TO authenticated
  USING (public.is_command());

-- ────────────────────────────────────────────────────────────────────────────
-- 9. SAFE ZONES / UNINSTALL REQUESTS / APP CONFIG
-- ────────────────────────────────────────────────────────────────────────────

CREATE POLICY "safe_zones_read" ON public.safe_zones
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "safe_zones_write_command" ON public.safe_zones
  FOR ALL TO authenticated
  USING (public.is_command()) WITH CHECK (public.is_command());

CREATE POLICY "uninstall_insert_own" ON public.uninstall_requests
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());

CREATE POLICY "uninstall_read_own_or_staff" ON public.uninstall_requests
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_staff());

CREATE POLICY "uninstall_update_command" ON public.uninstall_requests
  FOR UPDATE TO authenticated USING (public.is_command());

CREATE POLICY "app_config_read_authenticated" ON public.app_config
  FOR SELECT TO authenticated USING (true);
-- Writes intentionally have NO policy: only service_role (which bypasses RLS)
-- may mutate app_config.

-- ────────────────────────────────────────────────────────────────────────────
-- 10. REVOKE THE ANON ROLE
--     Nothing in this system should be reachable with the public anon key alone.
-- ────────────────────────────────────────────────────────────────────────────

REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon;

-- [dry run] stripped: COMMIT;
-- ============================================================================
-- 3. TRIPWIRE — did anything commit while applying the migration?
-- ============================================================================
DO $dryrun$
BEGIN
  PERFORM 1 FROM _dryrun_marker;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ABORT: the marker table is empty — a COMMIT occurred and this is no longer a dry run.';
  END IF;
  RAISE NOTICE 'OK: still inside the dry-run transaction, nothing has been committed';
EXCEPTION WHEN undefined_table THEN
  RAISE EXCEPTION 'ABORT: the marker table is GONE — a COMMIT occurred. Changes may be PERMANENT. Stop and check pg_policies.';
END $dryrun$;

-- ============================================================================
-- 4. Assert behaviour against REAL rows and REAL roles
-- ============================================================================
DO $dryrun$
DECLARE
  n INT; n_before INT;
  cmd_id UUID; cit_id UUID;
  escalated BOOLEAN;
  problems INT := 0;
BEGIN
  -- Re-check the tripwire HERE too, not just above.
  --
  -- psql and some editors continue past a failed statement, so without this the
  -- block above could abort and this block would still run to completion and
  -- print '>>> SAFE TO APPLY' — a reassuring message produced by a script that
  -- had just permanently modified the database. Refuse to say anything at all
  -- unless we are certain we are still inside the throwaway transaction.
  BEGIN
    PERFORM 1 FROM _dryrun_marker;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'ABORT: marker empty — a COMMIT occurred. Not reporting a verdict.';
    END IF;
  EXCEPTION WHEN undefined_table THEN
    RAISE EXCEPTION 'ABORT: marker GONE — a COMMIT occurred and changes may be PERMANENT. No verdict is given. Check pg_policies now.';
  END;

  SELECT id INTO cmd_id FROM public.profiles
   WHERE role IN ('HQ_COMMAND','HQ_OFFICER','ADMIN','LGA_COMMAND') LIMIT 1;
  SELECT id INTO cit_id FROM public.profiles WHERE role = 'CITIZEN' LIMIT 1;
  SELECT count(*) INTO n_before FROM public.profiles;

  RAISE NOTICE 'Live data: % profiles. command sample=%, citizen sample=%',
    n_before, coalesce(cmd_id::text,'NONE'), coalesce(cit_id::text,'NONE');

  -- ── anon must be locked out ───────────────────────────────────────────────
  SET LOCAL ROLE anon;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', 'anon', true);

  BEGIN
    SELECT count(*) INTO n FROM public.profiles;
    IF n > 0 THEN
      RAISE NOTICE '>>> PROBLEM: anon can still read % profile rows', n;
      problems := problems + 1;
    ELSE RAISE NOTICE 'OK: anon cannot read profiles'; END IF;
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK: anon denied on profiles outright';
  END;

  BEGIN
    SELECT count(*) INTO n FROM public.telemetry;
    IF n > 0 THEN
      RAISE NOTICE '>>> PROBLEM: anon can still read % telemetry rows (live GPS)', n;
      problems := problems + 1;
    ELSE RAISE NOTICE 'OK: anon cannot read telemetry'; END IF;
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK: anon denied on telemetry outright';
  END;

  BEGIN
    SELECT count(*) INTO n FROM public.alerts;
    IF n > 0 THEN
      RAISE NOTICE '>>> PROBLEM: anon can still read % alert rows', n;
      problems := problems + 1;
    ELSE RAISE NOTICE 'OK: anon cannot read alerts'; END IF;
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK: anon denied on alerts outright';
  END;

  RESET ROLE;

  -- ── command staff must NOT lose visibility ───────────────────────────────
  -- The assertion that matters most for not breaking your operation.
  IF cmd_id IS NOT NULL THEN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
    PERFORM set_config('request.jwt.claim.sub', cmd_id::text, true);

    SELECT count(*) INTO n FROM public.profiles;
    IF n < n_before THEN
      RAISE NOTICE '>>> PROBLEM: command user sees only % of % profiles', n, n_before;
      problems := problems + 1;
    ELSE RAISE NOTICE 'OK: command user still sees all % profiles', n; END IF;

    SELECT count(*) INTO n FROM public.alerts;
    RAISE NOTICE 'OK: command user sees % alerts', n;
    SELECT count(*) INTO n FROM public.telemetry;
    RAISE NOTICE 'OK: command user sees % telemetry rows', n;
    RESET ROLE;
  ELSE
    RAISE NOTICE '>>> PROBLEM: no command-role profile found — cannot prove dispatch still works';
    problems := problems + 1;
  END IF;

  -- ── a citizen sees only themselves, and cannot promote themselves ────────
  IF cit_id IS NOT NULL THEN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
    PERFORM set_config('request.jwt.claim.sub', cit_id::text, true);

    SELECT count(*) INTO n FROM public.profiles;
    IF n <> 1 THEN
      RAISE NOTICE '>>> PROBLEM: citizen sees % profiles, expected 1', n;
      problems := problems + 1;
    ELSE RAISE NOTICE 'OK: citizen sees only their own profile'; END IF;

    -- The check C-4 depends on. Expected to be blocked.
    escalated := false;
    BEGIN
      UPDATE public.profiles SET role = 'HQ_COMMAND' WHERE id = cit_id;
      GET DIAGNOSTICS n = ROW_COUNT;
      IF n > 0 THEN escalated := true; END IF;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    IF escalated THEN
      RAISE NOTICE '>>> PROBLEM: a citizen escalated their own role to HQ_COMMAND';
      problems := problems + 1;
    ELSE RAISE NOTICE 'OK: self role escalation blocked'; END IF;

    RESET ROLE;
  ELSE
    RAISE NOTICE 'note: no CITIZEN profile found — citizen scoping not exercised';
  END IF;

  RESET ROLE;

  RAISE NOTICE '=========================================';
  IF problems = 0 THEN
    RAISE NOTICE '>>> SAFE TO APPLY — 0 problems found';
  ELSE
    RAISE NOTICE '>>> DO NOT APPLY — % problem(s) above', problems;
  END IF;
  RAISE NOTICE '=========================================';
END $dryrun$;

-- ============================================================================
-- 5. Throw all of it away
-- ============================================================================
ROLLBACK;

-- Must match the BEFORE numbers above. If it does not, something persisted.
SELECT count(*) FILTER (WHERE qual='true' OR with_check='true') AS still_wide_open,
       count(*) AS total_policies
FROM pg_policies WHERE schemaname='public';
