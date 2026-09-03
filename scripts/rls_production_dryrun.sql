-- ============================================================================
-- PRODUCTION DRY RUN — generated file, do not edit by hand.
--   Regenerate with: python3 scripts/build_rls_dryrun.py
--
--   Paste the WHOLE of this file into the Supabase dashboard -> SQL Editor and
--   run it. It ends by raising an error ON PURPOSE — that error is the
--   result. Nothing it does is kept.
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
-- **THIS SCRIPT ENDS IN AN ERROR, AND THAT IS THE SUCCESS CASE.** The findings
-- are the error message. Read it; the verdict is on its first line:
--
--   ===== RLS DRY RUN — >>> SAFE TO APPLY =====   the migration did the right
--                                                 thing on your data
--   ===== RLS DRY RUN — >>> DO NOT APPLY =====    PROBLEM lines follow — send them
--
-- WHY AN ERROR AND NOT A RESULT SET
--
-- The first version returned the findings as rows and ended with ROLLBACK. Run
-- against the real database it came back as three column headers and ZERO ROWS:
-- no error, no findings, nothing to act on — indistinguishable from "all clear"
-- on a script whose entire job is to answer "is this safe to apply". Two causes,
-- both fixed here:
--
--   1. A result set is transactional. If the client has not materialised the
--      rows before the ROLLBACK lands, there is nothing left to hand back. An
--      error message is delivered out of band and cannot be rolled back.
--   2. Any unhandled error inside the script aborts the whole transaction and
--      takes every finding with it. Reproduced deliberately: with `authenticated`
--      lacking SELECT on `profiles`, the old script emitted `ERROR: permission
--      denied` and nothing else. The assertion sections are now individually
--      guarded, so a failure is RECORDED as a PROBLEM and the rest still runs.
--
-- Raising also makes the rollback intrinsic rather than a trailing statement
-- that has to survive whatever the client does with the batch: the transaction
-- is aborted by the RAISE itself, so this cannot commit even in principle.
--
-- To confirm nothing persisted afterwards, re-run scripts/rls_inventory.sql and
-- check the policy count is unchanged.
--
-- RUN scripts/rls_inventory.sql FIRST. It is read-only and lists every policy
-- this repository does not create — the ones this migration will not drop.
-- ============================================================================

BEGIN;

-- Tripwire. ON COMMIT DROP means this disappears the instant anything commits.
CREATE TEMP TABLE _dryrun_marker(ok boolean) ON COMMIT DROP;
INSERT INTO _dryrun_marker VALUES (true);

-- Findings are collected as ROWS, not RAISE NOTICE. The Supabase SQL Editor does
-- not surface notices at all — the first version of this script reported its
-- entire verdict through NOTICE and the operator saw none of it. The last
-- row-returning statement is what the editor displays, so that is the verdict.
CREATE TEMP TABLE _findings(
  seq    serial,
  status text,
  check_ text,
  detail text
) ON COMMIT DROP;

-- The assertions impersonate anon and authenticated via SET LOCAL ROLE, and those
-- roles cannot write to a table owned by the session user. Without these grants
-- the first anon assertion dies with "permission denied for table _findings" and
-- the whole transaction aborts. It is a temp table inside a transaction that is
-- always rolled back, so granting broadly here costs nothing.
GRANT ALL ON _findings TO PUBLIC;
GRANT ALL ON SEQUENCE _findings_seq_seq TO PUBLIC;

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
  INSERT INTO _findings(status, check_, detail) VALUES ('BEFORE', 'policies on public', n_total || ' total, ' || n_open || ' with USING(true)/WITH CHECK(true)');
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

-- The agency an outside-agency liaison belongs to, or NULL for everyone else.
--
-- Liaisons are the actual users of the agency portal: the console registers
-- them with role `<AGENCY>_LIAISON` (POLICE_LIAISON, ARMY_LIAISON, ...) and
-- derives their agency from that role. This does the same, from the same
-- column, and NOT from `profiles.agency`: that column is self-writable, while
-- `role` is guarded by the trigger in section 4. A liaison who could rewrite
-- their own agency could read another agency's deployments.
CREATE OR REPLACE FUNCTION public.liaison_agency()
RETURNS TEXT
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT CASE
           WHEN role LIKE '%\_LIAISON' THEN left(role, length(role) - length('_LIAISON'))
         END
    FROM public.profiles WHERE id = auth.uid();
$$;

REVOKE EXECUTE ON FUNCTION public.auth_role()      FROM anon;
REVOKE EXECUTE ON FUNCTION public.is_staff()       FROM anon;
REVOKE EXECUTE ON FUNCTION public.is_command()     FROM anon;
REVOKE EXECUTE ON FUNCTION public.liaison_agency() FROM anon;

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
-- 2b. DROP THE POLICIES THAT WERE CREATED BY HAND IN THE SUPABASE DASHBOARD
--
--     Added after reading a real `pg_policies` dump from production, which is
--     the only way these could ever have been known. The dump showed 44 live
--     policies where a replica rebuilt from this repo's migrations has 21:
--     the 34 below exist ONLY in production and are not created by any file
--     here.
--
--     Without this section the migration was very nearly decorative. It would
--     have dropped 10 policies, created its own strict ones, and left these 34
--     untouched — and because PostgreSQL combines PERMISSIVE policies with OR,
--     survivors like `profiles_read_all` (USING auth.uid() IS NOT NULL) would
--     have kept granting every authenticated user read access to every profile,
--     defeating `profiles_select_self_or_staff` entirely. Exactly the failure
--     that made phase1_foundation.sql a no-op.
-- ────────────────────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "agency_reports_read"  ON public.agency_action_reports;
DROP POLICY IF EXISTS "agency_reports_write" ON public.agency_action_reports;

DROP POLICY IF EXISTS "agency_deployments_read"  ON public.agency_deployments;
DROP POLICY IF EXISTS "agency_deployments_write" ON public.agency_deployments;

DROP POLICY IF EXISTS "agency_notifications_insert" ON public.agency_notifications;
DROP POLICY IF EXISTS "agency_notifications_read"   ON public.agency_notifications;

DROP POLICY IF EXISTS "agency_personnel_read"  ON public.agency_personnel;
DROP POLICY IF EXISTS "agency_personnel_write" ON public.agency_personnel;

DROP POLICY IF EXISTS "alerts_delete_hq_only"         ON public.alerts;
DROP POLICY IF EXISTS "alerts_insert_authenticated"   ON public.alerts;
DROP POLICY IF EXISTS "alerts_read_authenticated"     ON public.alerts;
DROP POLICY IF EXISTS "alerts_select_own"             ON public.alerts;
DROP POLICY IF EXISTS "alerts_select_responders"      ON public.alerts;
DROP POLICY IF EXISTS "alerts_update_authenticated"   ON public.alerts;
DROP POLICY IF EXISTS "alerts_update_responders_only" ON public.alerts;

DROP POLICY IF EXISTS "chat_insert_authenticated" ON public.chat_messages;
DROP POLICY IF EXISTS "chat_read_authenticated"   ON public.chat_messages;
DROP POLICY IF EXISTS "chat_select_own_alerts"    ON public.chat_messages;
DROP POLICY IF EXISTS "chat_select_responders"    ON public.chat_messages;

DROP POLICY IF EXISTS "profiles_delete_hq"         ON public.profiles;
DROP POLICY IF EXISTS "profiles_insert_own"        ON public.profiles;
DROP POLICY IF EXISTS "profiles_read_all"          ON public.profiles;
DROP POLICY IF EXISTS "profiles_select_own"        ON public.profiles;
DROP POLICY IF EXISTS "profiles_select_responders" ON public.profiles;
DROP POLICY IF EXISTS "profiles_write_own"         ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_own"        ON public.profiles;

DROP POLICY IF EXISTS "sysalerts_read_authenticated"           ON public.system_alerts;
DROP POLICY IF EXISTS "sysalerts_write_hq"                     ON public.system_alerts;
DROP POLICY IF EXISTS "system_alerts_select_all_authenticated" ON public.system_alerts;
DROP POLICY IF EXISTS "system_alerts_manage_hq"                ON public.system_alerts;

DROP POLICY IF EXISTS "telemetry_read_authenticated" ON public.telemetry;
DROP POLICY IF EXISTS "telemetry_select_responders"  ON public.telemetry;
DROP POLICY IF EXISTS "telemetry_write_own"          ON public.telemetry;
DROP POLICY IF EXISTS "telemetry_upsert_own"         ON public.telemetry;

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

-- ────────────────────────────────────────────────────────────────────────────
-- 9. AGENCY TABLES — inter-agency coordination.
--
--    These four tables exist in production but no migration in this repository
--    ever created policies for them; the live ones were made by hand. Section
--    2b drops those, so this section MUST replace them or the tables become
--    deny-all (RLS enabled with no policy denies everything) and the agency
--    portal goes blank.
--
--    What was there:  ALL USING (auth.uid() IS NOT NULL)
--                     WITH CHECK (auth.uid() IS NOT NULL)
--    i.e. ANY authenticated user — and anyone can register — could read and
--    WRITE agency deployments, personnel records and action reports.
--
--    agency_notifications was worse: it checked
--      auth.jwt() -> 'user_metadata' ->> 'role'
--    and `user_metadata` is written by the CLIENT via
--    supabase.auth.updateUser({ data: { role: 'HQ_COMMAND' } }). Any user could
--    grant themselves that permission with one call and no database write at
--    all. Nothing here reads user_metadata; is_staff()/is_command() read
--    profiles.role, which the trigger in section 4 makes non-self-writable.
-- ────────────────────────────────────────────────────────────────────────────

--    WHO USES THESE TABLES. The first version of this section granted writes to
--    is_command() only. That would have broken the portal for the people it is
--    for: agency liaisons carry role `<AGENCY>_LIAISON`, which is neither a
--    command tier nor a citizen, so under that version they could read every
--    agency's records and write none of their own. Now:
--
--      command tiers          read and write every agency's rows
--      the agency's liaisons  read and write rows tagged with THEIR agency,
--                             agency taken from the role (liaison_agency())
--      other staff            nothing here — responders have no business in
--                             another agency's personnel roster
--      citizens / anon        nothing
--
--    The tables are created by 20260812000000_agency_tables.sql, which runs
--    before this file, so they exist on every database this migration meets.
--    Each policy is dropped before it is created: this migration is documented
--    as safe to re-run, and CREATE POLICY has no IF NOT EXISTS.

DROP POLICY IF EXISTS "agency_personnel_liaison_read"          ON public.agency_personnel;
DROP POLICY IF EXISTS "agency_personnel_liaison_write"         ON public.agency_personnel;
DROP POLICY IF EXISTS "agency_deployments_liaison_read"        ON public.agency_deployments;
DROP POLICY IF EXISTS "agency_deployments_liaison_write"       ON public.agency_deployments;
DROP POLICY IF EXISTS "agency_action_reports_liaison_read"     ON public.agency_action_reports;
DROP POLICY IF EXISTS "agency_action_reports_liaison_write"    ON public.agency_action_reports;
-- names used by an earlier revision of this file
DROP POLICY IF EXISTS "agency_personnel_staff_read"           ON public.agency_personnel;
DROP POLICY IF EXISTS "agency_personnel_command_write"        ON public.agency_personnel;
DROP POLICY IF EXISTS "agency_deployments_staff_read"         ON public.agency_deployments;
DROP POLICY IF EXISTS "agency_deployments_command_write"      ON public.agency_deployments;
DROP POLICY IF EXISTS "agency_action_reports_staff_read"      ON public.agency_action_reports;
DROP POLICY IF EXISTS "agency_action_reports_command_write"   ON public.agency_action_reports;

ALTER TABLE public.agency_personnel      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agency_deployments    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agency_action_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agency_notifications  ENABLE ROW LEVEL SECURITY;

CREATE POLICY "agency_personnel_liaison_read" ON public.agency_personnel
  FOR SELECT TO authenticated
  USING (public.is_command() OR agency = public.liaison_agency());
CREATE POLICY "agency_personnel_liaison_write" ON public.agency_personnel
  FOR ALL TO authenticated
  USING      (public.is_command() OR agency = public.liaison_agency())
  WITH CHECK (public.is_command() OR agency = public.liaison_agency());

CREATE POLICY "agency_deployments_liaison_read" ON public.agency_deployments
  FOR SELECT TO authenticated
  USING (public.is_command() OR agency = public.liaison_agency());
CREATE POLICY "agency_deployments_liaison_write" ON public.agency_deployments
  FOR ALL TO authenticated
  USING      (public.is_command() OR agency = public.liaison_agency())
  WITH CHECK (public.is_command() OR agency = public.liaison_agency());

CREATE POLICY "agency_action_reports_liaison_read" ON public.agency_action_reports
  FOR SELECT TO authenticated
  USING (public.is_command() OR agency = public.liaison_agency());
CREATE POLICY "agency_action_reports_liaison_write" ON public.agency_action_reports
  FOR ALL TO authenticated
  USING      (public.is_command() OR agency = public.liaison_agency())
  WITH CHECK (public.is_command() OR agency = public.liaison_agency());

-- Escalation delivery log. Written by the console's server-side route with the
-- service key (bypasses RLS); command may read it. Nobody else needs it.
DROP POLICY IF EXISTS "agency_notifications_command_read"  ON public.agency_notifications;
DROP POLICY IF EXISTS "agency_notifications_command_write" ON public.agency_notifications;
CREATE POLICY "agency_notifications_command_read" ON public.agency_notifications
  FOR SELECT TO authenticated USING (public.is_command());
CREATE POLICY "agency_notifications_command_write" ON public.agency_notifications
  FOR ALL TO authenticated USING (public.is_command()) WITH CHECK (public.is_command());


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
  INSERT INTO _findings(status, check_, detail) VALUES ('OK', 'still inside the dry-run transaction', 'nothing committed');
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

  INSERT INTO _findings(status, check_, detail) VALUES ('INFO', 'live data', n_before || ' profiles; command sample=' || coalesce(cmd_id::text,'NONE') || '; citizen sample=' || coalesce(cit_id::text,'NONE'));

  -- ── anon must be locked out ───────────────────────────────────────────────
  SET LOCAL ROLE anon;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', 'anon', true);

  BEGIN
    SELECT count(*) INTO n FROM public.profiles;
    IF n > 0 THEN
      INSERT INTO _findings(status, check_, detail) VALUES ('PROBLEM', 'anon reads profiles', n || ' rows visible');
      problems := problems + 1;
    ELSE INSERT INTO _findings(status, check_, detail) VALUES ('OK','anon cannot read profiles',''); END IF;
  EXCEPTION WHEN insufficient_privilege THEN
    INSERT INTO _findings(status, check_, detail) VALUES ('OK','anon denied on profiles','privilege denied');
  END;

  BEGIN
    SELECT count(*) INTO n FROM public.telemetry;
    IF n > 0 THEN
      INSERT INTO _findings(status, check_, detail) VALUES ('PROBLEM','anon reads telemetry (live GPS)', n || ' rows visible');
      problems := problems + 1;
    ELSE INSERT INTO _findings(status, check_, detail) VALUES ('OK','anon cannot read telemetry',''); END IF;
  EXCEPTION WHEN insufficient_privilege THEN
    INSERT INTO _findings(status, check_, detail) VALUES ('OK','anon denied on telemetry','privilege denied');
  END;

  BEGIN
    SELECT count(*) INTO n FROM public.alerts;
    IF n > 0 THEN
      INSERT INTO _findings(status, check_, detail) VALUES ('PROBLEM','anon reads alerts', n || ' rows visible');
      problems := problems + 1;
    ELSE INSERT INTO _findings(status, check_, detail) VALUES ('OK','anon cannot read alerts',''); END IF;
  EXCEPTION WHEN insufficient_privilege THEN
    INSERT INTO _findings(status, check_, detail) VALUES ('OK','anon denied on alerts','privilege denied');
  END;

  RESET ROLE;

  -- ── command staff must NOT lose visibility ───────────────────────────────
  -- The assertion that matters most for not breaking your operation.
  IF cmd_id IS NOT NULL THEN
   -- Guarded. An unhandled error anywhere in here aborts the WHOLE transaction,
   -- and every finding gathered so far dies with it — the operator then gets an
   -- empty result and no way to tell "clean" from "the script fell over".
   -- Recording the failure as a finding is strictly better than losing all of them.
   BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
    PERFORM set_config('request.jwt.claim.sub', cmd_id::text, true);

    SELECT count(*) INTO n FROM public.profiles;
    IF n < n_before THEN
      INSERT INTO _findings(status, check_, detail) VALUES ('PROBLEM','command user lost visibility', n || ' of ' || n_before || ' profiles');
      problems := problems + 1;
    ELSE INSERT INTO _findings(status, check_, detail) VALUES ('OK','command user sees all profiles', n || ' profiles'); END IF;

    SELECT count(*) INTO n FROM public.alerts;
    INSERT INTO _findings(status, check_, detail) VALUES ('OK','command user sees alerts', n || ' alerts');
    SELECT count(*) INTO n FROM public.telemetry;
    INSERT INTO _findings(status, check_, detail) VALUES ('OK','command user sees telemetry', n || ' rows');
    RESET ROLE;
   EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    INSERT INTO _findings(status, check_, detail)
      VALUES ('PROBLEM','command visibility check could not run', SQLERRM);
    problems := problems + 1;
   END;
  ELSE
    INSERT INTO _findings(status, check_, detail) VALUES ('PROBLEM','no command-role profile found','cannot prove dispatch still works');
    problems := problems + 1;
  END IF;

  -- ── a citizen sees only themselves, and cannot promote themselves ────────
  IF cit_id IS NOT NULL THEN
   BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
    PERFORM set_config('request.jwt.claim.sub', cit_id::text, true);

    SELECT count(*) INTO n FROM public.profiles;
    IF n <> 1 THEN
      INSERT INTO _findings(status, check_, detail) VALUES ('PROBLEM','citizen sees too many profiles', n || ', expected 1');
      problems := problems + 1;
    ELSE INSERT INTO _findings(status, check_, detail) VALUES ('OK','citizen sees only their own profile',''); END IF;

    -- The check C-4 depends on. Expected to be blocked.
    escalated := false;
    BEGIN
      UPDATE public.profiles SET role = 'HQ_COMMAND' WHERE id = cit_id;
      GET DIAGNOSTICS n = ROW_COUNT;
      IF n > 0 THEN escalated := true; END IF;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    IF escalated THEN
      INSERT INTO _findings(status, check_, detail) VALUES ('PROBLEM','citizen escalated to HQ_COMMAND','privilege escalation NOT blocked');
      problems := problems + 1;
    ELSE INSERT INTO _findings(status, check_, detail) VALUES ('OK','self role escalation blocked',''); END IF;

    RESET ROLE;
   EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    INSERT INTO _findings(status, check_, detail)
      VALUES ('PROBLEM','citizen scoping check could not run', SQLERRM);
    problems := problems + 1;
   END;
  ELSE
    INSERT INTO _findings(status, check_, detail) VALUES ('INFO','no CITIZEN profile found','citizen scoping not exercised');
  END IF;

  RESET ROLE;

  IF problems = 0 THEN
    INSERT INTO _findings(status, check_, detail) VALUES ('VERDICT','>>> SAFE TO APPLY','0 problems found');
  ELSE
    INSERT INTO _findings(status, check_, detail) VALUES ('VERDICT','>>> DO NOT APPLY', problems || ' problem(s) above');
  END IF;
END $dryrun$;

-- ============================================================================
-- 5. THE VERDICT — delivered as an ERROR, on purpose.
--
-- This used to be `SELECT ... FROM _findings;` followed by `ROLLBACK;`, and it
-- came back from the Supabase SQL Editor as the three column headers with ZERO
-- ROWS — no error, no findings, nothing to act on. A result set is transactional:
-- if the client has not materialised the rows by the time the ROLLBACK lands,
-- there is nothing left to hand back, and the operator is told nothing at all.
-- On a script whose whole job is to answer "is this safe to apply", silence is
-- the worst possible output — it is indistinguishable from "no problems".
--
-- An error message is delivered out of band and cannot be rolled back. Raising
-- one also makes the rollback intrinsic rather than a trailing statement that
-- has to survive whatever the client does with the batch: the transaction is
-- aborted by the RAISE itself, so this script cannot commit even in principle.
--
-- So: SEEING AN ERROR HERE IS THE SUCCESS CASE. Read the message.
-- The verdict is on its first line, so it survives any truncation.
-- ============================================================================
DO $emit$
DECLARE
  verdict text;
  body    text;
BEGIN
  SELECT detail INTO verdict FROM _findings WHERE status = 'VERDICT' LIMIT 1;

  SELECT string_agg(format('%s | %s | %s', status, check_, detail), chr(10) ORDER BY seq)
    INTO body
    FROM _findings
   WHERE status <> 'VERDICT';

  RAISE EXCEPTION E'

===== RLS DRY RUN — % =====
%

(This error IS the result. Nothing was kept.)',
    COALESCE((SELECT check_ FROM _findings WHERE status = 'VERDICT' LIMIT 1), '>>> NO VERDICT — the checks did not run'),
    COALESCE(body, '(no findings recorded)')
    USING ERRCODE = 'raise_exception';
END $emit$;

-- ============================================================================
-- 6. Belt and braces. The RAISE above has already aborted the transaction, so
--    this is a no-op that exists only for the case where someone edits the
--    emit block out. To confirm nothing persisted, re-run
--    scripts/rls_inventory.sql and check the row count is unchanged.
-- ============================================================================
ROLLBACK;
