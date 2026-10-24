-- ============================================================================
-- APPLY ALL OUTSTANDING MIGRATIONS — generated file, do not edit by hand.
--   Regenerate with: python3 scripts/build_apply_all.py
--
-- Paste the WHOLE of this file into the Supabase dashboard -> SQL Editor and
-- run it. It applies the 46 outstanding migrations in order and finishes by
-- SELECTing a pass/fail table, so one paste in gives you one answer out.
--
-- ---------------------------------------------------------------------------
-- RUN THE DRY RUN FIRST. THIS IS NOT OPTIONAL.
--
--   scripts/rls_production_dryrun.sql
--
-- 20260813000000_rls_least_privilege.sql drops prior policies BY EXACT NAME.
-- A policy somebody created by hand in the dashboard is not in that list, so it
-- survives — and PostgreSQL combines PERMISSIVE policies with OR, meaning one
-- surviving `USING (true)` re-opens the table and the migration becomes
-- decorative. That is exactly how phase1_foundation.sql already failed once.
-- The dry run is read-only, rolls everything back, and prints a verdict:
--
--   ===== RLS DRY RUN — >>> SAFE TO APPLY =====   -> paste this file
--   ===== RLS DRY RUN — >>> DO NOT APPLY =====    -> stop; it names the policy
-- ---------------------------------------------------------------------------
--
-- SAFE TO RE-RUN — but "idempotent" is not quite the right word, and the
-- difference shows up if you run this file twice.
--
-- Most of these migrations ARE idempotent: they use IF NOT EXISTS / OR REPLACE
-- and a second run changes nothing and says nothing.
--
-- `20260813000000_rls_least_privilege.sql` is ATOMIC instead. It drops the old
-- policy set by name and creates a new one, inside its own BEGIN/COMMIT, so it
-- applies completely or not at all. Running it a SECOND time therefore reports
--
--     ERROR: policy "profiles_select_self_or_staff" for table "profiles"
--            already exists
--
-- and rolls itself back. That message means THE POLICIES ARE ALREADY IN PLACE.
-- It is not a failure to fix, nothing is left half-applied, and the verification
-- at the end of this file will still report every row PASS. Read the verdict
-- table, not the error.
--
-- So: an interrupted run can simply be re-run, and the state you end up with is
-- correct either way.
--
-- Expect a few `NOTICE: skipping ...` lines. They are the guards that let these
-- files run against a database that does not have a given table yet.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 20260812000000_agency_tables.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20260812000000_agency_tables.sql'; END $apply$;

-- ============================================================================
-- OPERATION RAINBOW — INTER-AGENCY TABLES
--
-- WHY THIS EXISTS
-- ---------------
-- The HQ console reads and writes four tables that no migration in this
-- repository ever created: agency_personnel, agency_deployments,
-- agency_action_reports and agency_notifications. They were made by hand in the
-- Supabase dashboard, and so was profiles.agency. That meant:
--
--   * a staging or disaster-recovery project rebuilt from these files was
--     missing the agency portal's entire backend, and
--   * the RLS migration that follows (20260813) had to SKIP securing them on
--     any database where they were absent — so the replica CI proves the
--     migration against never exercised the agency policies at all.
--
-- This file is dated BEFORE the RLS migration on purpose. On production, where
-- the tables already exist, every statement is a no-op (IF NOT EXISTS). On a
-- fresh project it creates them, and the RLS migration then secures them
-- exactly as it secures production — no skipped section, no drift.
--
-- Column shapes are taken from the console's inserts and selects
-- (hq-dashboard-next/src/components/AgencyPortal.tsx, api/notify-agency/route.ts).
-- If production has extra columns, IF NOT EXISTS keeps production's shape and
-- nothing here narrows it.
--
-- Idempotent: safe to re-run.
-- ============================================================================

-- The console stores a liaison's agency on their profile for display. Access is
-- NOT decided from this column (it is self-writable); it is derived from the
-- role, which the RLS migration makes non-self-writable. See liaison_agency().
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS agency TEXT;

-- Officers an agency liaison has registered for their agency.
CREATE TABLE IF NOT EXISTS public.agency_personnel (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  agency        TEXT NOT NULL,                 -- POLICE, ARMY, DSS, NSCDC, FRSC, OPSH
  name          TEXT NOT NULL,
  rank          TEXT,
  badge_number  TEXT,
  phone         TEXT,
  status        TEXT NOT NULL DEFAULT 'AVAILABLE', -- AVAILABLE, DEPLOYED, UNAVAILABLE, OFF_DUTY
  created_by    UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS agency_personnel_agency_idx ON public.agency_personnel (agency);

-- A deployment of one or more officers to an escalated incident.
CREATE TABLE IF NOT EXISTS public.agency_deployments (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  alert_id        UUID REFERENCES public.alerts(id) ON DELETE CASCADE,
  agency          TEXT NOT NULL,
  personnel_ids   UUID[] NOT NULL DEFAULT '{}',
  personnel_count INTEGER NOT NULL DEFAULT 0,
  deployment_note TEXT,
  status          TEXT NOT NULL DEFAULT 'EN_ROUTE', -- EN_ROUTE, ON_SITE, WITHDRAWN, COMPLETE
  deployed_by     UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  deployed_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS agency_deployments_agency_status_idx
  ON public.agency_deployments (agency, status);

-- After-action reports filed by an agency; HQ acknowledges them.
CREATE TABLE IF NOT EXISTS public.agency_action_reports (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  alert_id           UUID REFERENCES public.alerts(id) ON DELETE SET NULL,
  agency             TEXT NOT NULL,
  report_type        TEXT,
  narrative          TEXT,
  outcome            TEXT,
  personnel_count    INTEGER,
  casualties         INTEGER,
  submitted_by       UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  submitted_by_name  TEXT,
  submitted_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  read_by_hq         BOOLEAN NOT NULL DEFAULT false,
  hq_acknowledged_by TEXT,
  hq_acknowledged_at TIMESTAMPTZ,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS agency_action_reports_unread_idx
  ON public.agency_action_reports (read_by_hq) WHERE read_by_hq = false;

-- Delivery log for escalations sent to an outside agency (SMS / webhook).
-- Written only by the console's server-side API route with the service key.
CREATE TABLE IF NOT EXISTS public.agency_notifications (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  alert_id   UUID REFERENCES public.alerts(id) ON DELETE SET NULL,
  agency     TEXT NOT NULL,
  method     TEXT NOT NULL,      -- SMS, WEBHOOK
  status     TEXT NOT NULL,      -- SENT, FAILED, SKIPPED
  sent_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- RLS is enabled here so that even on a database where the following migration
-- has not yet run, a freshly created table is never open. With no policies this
-- is deny-all for the API roles; 20260813 adds the policies.
ALTER TABLE public.agency_personnel      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agency_deployments    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agency_action_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agency_notifications  ENABLE ROW LEVEL SECURITY;

-- ----------------------------------------------------------------------------
-- 20260813000000_rls_least_privilege.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20260813000000_rls_least_privilege.sql'; END $apply$;

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

BEGIN;

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

-- from 20260720000000_initial_schema.sql (and its byte-identical root-level
-- copy `supabase_schema_setup.sql`, since deleted — two files declaring the
-- same schema is two sources of truth for it)
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

DROP POLICY IF EXISTS "profiles_select_self_or_staff" ON public.profiles;
CREATE POLICY "profiles_select_self_or_staff" ON public.profiles
  FOR SELECT TO authenticated
  USING (id = auth.uid() OR public.is_staff());

DROP POLICY IF EXISTS "profiles_insert_self" ON public.profiles;
CREATE POLICY "profiles_insert_self" ON public.profiles
  FOR INSERT TO authenticated
  WITH CHECK (id = auth.uid());

DROP POLICY IF EXISTS "profiles_update_self" ON public.profiles;
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

DROP POLICY IF EXISTS "telemetry_select_self_or_staff" ON public.telemetry;
CREATE POLICY "telemetry_select_self_or_staff" ON public.telemetry
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_staff());

DROP POLICY IF EXISTS "telemetry_insert_own" ON public.telemetry;
CREATE POLICY "telemetry_insert_own" ON public.telemetry
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "telemetry_update_own" ON public.telemetry;
CREATE POLICY "telemetry_update_own" ON public.telemetry
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- ────────────────────────────────────────────────────────────────────────────
-- 6. ALERTS
-- ────────────────────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "alerts_select_own_or_staff" ON public.alerts;
CREATE POLICY "alerts_select_own_or_staff" ON public.alerts
  FOR SELECT TO authenticated
  USING (
    reported_by = auth.uid()
    OR assigned_to = auth.uid()
    OR public.is_staff()
  );

DROP POLICY IF EXISTS "alerts_insert_as_self" ON public.alerts;
CREATE POLICY "alerts_insert_as_self" ON public.alerts
  FOR INSERT TO authenticated
  WITH CHECK (reported_by = auth.uid() OR public.is_staff());

-- NOTE: the reporter is intentionally allowed to update their own alert, because
-- the mobile duress/safe-PIN flow resolves an alert client-side
-- (emergency_provider.dart::verifyCancellation). Residual risk: someone holding a
-- victim's unlocked phone can mark the SOS resolved. Moving resolution behind an
-- RPC that records WHO resolved it is the follow-up.
DROP POLICY IF EXISTS "alerts_update_own_or_staff" ON public.alerts;
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

DROP POLICY IF EXISTS "chat_select_participant_or_staff" ON public.chat_messages;
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

DROP POLICY IF EXISTS "chat_insert_as_self" ON public.chat_messages;
CREATE POLICY "chat_insert_as_self" ON public.chat_messages
  FOR INSERT TO authenticated
  WITH CHECK (sender_id = auth.uid());

-- ────────────────────────────────────────────────────────────────────────────
-- 8. SYSTEM ALERTS — state-wide advisories. Was `FOR ALL USING (true)`, so anon
--    could push a state-wide emergency broadcast.
-- ────────────────────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "system_alerts_read" ON public.system_alerts;
CREATE POLICY "system_alerts_read" ON public.system_alerts
  FOR SELECT TO authenticated
  USING (true);

DROP POLICY IF EXISTS "system_alerts_write_command" ON public.system_alerts;
CREATE POLICY "system_alerts_write_command" ON public.system_alerts
  FOR INSERT TO authenticated
  WITH CHECK (public.is_command());

DROP POLICY IF EXISTS "system_alerts_update_command" ON public.system_alerts;
CREATE POLICY "system_alerts_update_command" ON public.system_alerts
  FOR UPDATE TO authenticated
  USING (public.is_command());

DROP POLICY IF EXISTS "system_alerts_delete_command" ON public.system_alerts;
CREATE POLICY "system_alerts_delete_command" ON public.system_alerts
  FOR DELETE TO authenticated
  USING (public.is_command());

-- ────────────────────────────────────────────────────────────────────────────
-- 9. SAFE ZONES / UNINSTALL REQUESTS / APP CONFIG
-- ────────────────────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "safe_zones_read" ON public.safe_zones;
CREATE POLICY "safe_zones_read" ON public.safe_zones
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "safe_zones_write_command" ON public.safe_zones;
CREATE POLICY "safe_zones_write_command" ON public.safe_zones
  FOR ALL TO authenticated
  USING (public.is_command()) WITH CHECK (public.is_command());

DROP POLICY IF EXISTS "uninstall_insert_own" ON public.uninstall_requests;
CREATE POLICY "uninstall_insert_own" ON public.uninstall_requests
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "uninstall_read_own_or_staff" ON public.uninstall_requests;
CREATE POLICY "uninstall_read_own_or_staff" ON public.uninstall_requests
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_staff());

DROP POLICY IF EXISTS "uninstall_update_command" ON public.uninstall_requests;
CREATE POLICY "uninstall_update_command" ON public.uninstall_requests
  FOR UPDATE TO authenticated USING (public.is_command());

DROP POLICY IF EXISTS "app_config_read_authenticated" ON public.app_config;
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

DROP POLICY IF EXISTS "agency_personnel_liaison_read" ON public.agency_personnel;
CREATE POLICY "agency_personnel_liaison_read" ON public.agency_personnel
  FOR SELECT TO authenticated
  USING (public.is_command() OR agency = public.liaison_agency());
DROP POLICY IF EXISTS "agency_personnel_liaison_write" ON public.agency_personnel;
CREATE POLICY "agency_personnel_liaison_write" ON public.agency_personnel
  FOR ALL TO authenticated
  USING      (public.is_command() OR agency = public.liaison_agency())
  WITH CHECK (public.is_command() OR agency = public.liaison_agency());

DROP POLICY IF EXISTS "agency_deployments_liaison_read" ON public.agency_deployments;
CREATE POLICY "agency_deployments_liaison_read" ON public.agency_deployments
  FOR SELECT TO authenticated
  USING (public.is_command() OR agency = public.liaison_agency());
DROP POLICY IF EXISTS "agency_deployments_liaison_write" ON public.agency_deployments;
CREATE POLICY "agency_deployments_liaison_write" ON public.agency_deployments
  FOR ALL TO authenticated
  USING      (public.is_command() OR agency = public.liaison_agency())
  WITH CHECK (public.is_command() OR agency = public.liaison_agency());

DROP POLICY IF EXISTS "agency_action_reports_liaison_read" ON public.agency_action_reports;
CREATE POLICY "agency_action_reports_liaison_read" ON public.agency_action_reports
  FOR SELECT TO authenticated
  USING (public.is_command() OR agency = public.liaison_agency());
DROP POLICY IF EXISTS "agency_action_reports_liaison_write" ON public.agency_action_reports;
CREATE POLICY "agency_action_reports_liaison_write" ON public.agency_action_reports
  FOR ALL TO authenticated
  USING      (public.is_command() OR agency = public.liaison_agency())
  WITH CHECK (public.is_command() OR agency = public.liaison_agency());

-- Escalation delivery log. Written by the console's server-side route with the
-- service key (bypasses RLS); command may read it. Nobody else needs it.
DROP POLICY IF EXISTS "agency_notifications_command_read"  ON public.agency_notifications;
DROP POLICY IF EXISTS "agency_notifications_command_write" ON public.agency_notifications;
DROP POLICY IF EXISTS "agency_notifications_command_read" ON public.agency_notifications;
CREATE POLICY "agency_notifications_command_read" ON public.agency_notifications
  FOR SELECT TO authenticated USING (public.is_command());
DROP POLICY IF EXISTS "agency_notifications_command_write" ON public.agency_notifications;
CREATE POLICY "agency_notifications_command_write" ON public.agency_notifications
  FOR ALL TO authenticated USING (public.is_command()) WITH CHECK (public.is_command());


REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon;

COMMIT;

-- ----------------------------------------------------------------------------
-- 20260902000000_per_user_emergency_pins.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20260902000000_per_user_emergency_pins.sql'; END $apply$;

-- ============================================================================
-- Per-user, server-verified emergency PINs
-- ============================================================================
--
-- WHAT THIS REPLACES
--
-- SAFE_PIN and DURESS_PIN were build-time constants in the mobile app's `.env`,
-- which pubspec.yaml declares as a Flutter ASSET — so they shipped verbatim
-- inside every APK and extracted with `unzip`. Every install shared the same
-- two codes, and anyone who downloaded the app could read the duress code.
-- A duress PIN that a captor can look up is worse than none: it tells them
-- exactly which code NOT to let the victim enter.
--
-- THE DESIGN
--
--  * Each user sets their own safe PIN and duress PIN. Only bcrypt hashes are
--    stored (pgcrypto `crypt`, cost 10), in a table NOBODY can read through the
--    API: RLS is enabled with no policies, and all privileges are revoked from
--    the API roles. The only way in is through the functions below.
--
--  * Verification happens here, in SECURITY DEFINER functions, never on the
--    device. The client learns only the outcome. A short numeric PIN would be
--    brute-forceable offline from its hash, so the hash never leaves the
--    database, and online guessing is rate-limited: five failures lock the
--    account's PIN entry for fifteen minutes.
--
--  * `resolve_emergency` verifies the PIN and closes the alert in ONE call,
--    server-side, recording who did it. This is the follow-up the RLS
--    migration's own comment asked for ("moving resolution behind an RPC that
--    records WHO resolved it"). The status written — RESOLVED or DURESS — is
--    the only thing that differs between the two codes; the app's screen looks
--    identical either way, which is the point of a duress code.
--
-- OFFLINE
--
-- Verification needs the server. This is NOT a regression: the previous
-- client-side check also awaited a database update and returned false when
-- that failed, so an offline cancellation already did not succeed. What it
-- does change is that no PIN material exists on the device at all.
--
-- Idempotent: safe to re-run.
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ────────────────────────────────────────────────────────────────────────────
-- 1. STORAGE — write-only from the API's point of view
-- ────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.emergency_pins (
  user_id         uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  safe_hash       text NOT NULL,
  duress_hash     text NOT NULL,
  failed_attempts integer NOT NULL DEFAULT 0,
  locked_until    timestamptz,
  updated_at      timestamptz NOT NULL DEFAULT now()
);

-- RLS on, and deliberately NO policies: with row security enabled and nothing
-- granting access, every direct read or write through PostgREST is denied for
-- anon and authenticated alike. Belt and braces with the REVOKEs below.
ALTER TABLE public.emergency_pins ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.emergency_pins FROM anon, authenticated;

-- ────────────────────────────────────────────────────────────────────────────
-- 2. SETTING PINS
-- ────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.set_emergency_pins(p_safe text, p_duress text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_safe IS NULL OR p_safe !~ '^[0-9]{4,8}$' THEN
    RAISE EXCEPTION 'safe PIN must be 4 to 8 digits' USING ERRCODE = '22023';
  END IF;
  IF p_duress IS NULL OR p_duress !~ '^[0-9]{4,8}$' THEN
    RAISE EXCEPTION 'duress PIN must be 4 to 8 digits' USING ERRCODE = '22023';
  END IF;
  -- The two codes must differ, or there is no duress signal at all.
  IF p_safe = p_duress THEN
    RAISE EXCEPTION 'safe and duress PINs must be different' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.emergency_pins (user_id, safe_hash, duress_hash, failed_attempts, locked_until, updated_at)
  VALUES (
    v_uid,
    crypt(p_safe,   gen_salt('bf', 10)),
    crypt(p_duress, gen_salt('bf', 10)),
    0, NULL, now()
  )
  ON CONFLICT (user_id) DO UPDATE SET
    safe_hash       = EXCLUDED.safe_hash,
    duress_hash     = EXCLUDED.duress_hash,
    failed_attempts = 0,
    locked_until    = NULL,
    updated_at      = now();
END;
$$;

CREATE OR REPLACE FUNCTION public.has_emergency_pins()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (SELECT 1 FROM public.emergency_pins WHERE user_id = auth.uid());
$$;

-- ────────────────────────────────────────────────────────────────────────────
-- 3. VERIFYING — shared core, with lockout
-- ────────────────────────────────────────────────────────────────────────────
--
-- Returns one of: 'SAFE', 'DURESS', 'INVALID', 'LOCKED', 'UNSET'.
-- Not exposed to the API directly (see GRANTs); the two public entry points
-- below wrap it.

CREATE OR REPLACE FUNCTION public._check_emergency_pin(p_uid uuid, p_pin text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  r public.emergency_pins%ROWTYPE;
  v_kind text;
BEGIN
  SELECT * INTO r FROM public.emergency_pins WHERE user_id = p_uid FOR UPDATE;
  IF NOT FOUND THEN
    RETURN 'UNSET';
  END IF;

  IF r.locked_until IS NOT NULL AND r.locked_until > now() THEN
    RETURN 'LOCKED';
  END IF;

  IF p_pin IS NOT NULL AND crypt(p_pin, r.safe_hash) = r.safe_hash THEN
    v_kind := 'SAFE';
  ELSIF p_pin IS NOT NULL AND crypt(p_pin, r.duress_hash) = r.duress_hash THEN
    v_kind := 'DURESS';
  ELSE
    -- Five wrong guesses lock PIN entry for fifteen minutes. A 4-digit space
    -- is 10,000 codes; without this, an attacker holding the phone could walk
    -- it in an afternoon.
    UPDATE public.emergency_pins
       SET failed_attempts = failed_attempts + 1,
           locked_until = CASE WHEN failed_attempts + 1 >= 5
                               THEN now() + interval '15 minutes' ELSE NULL END
     WHERE user_id = p_uid;
    RETURN 'INVALID';
  END IF;

  UPDATE public.emergency_pins
     SET failed_attempts = 0, locked_until = NULL
   WHERE user_id = p_uid;
  RETURN v_kind;
END;
$$;

-- Check a PIN without touching any alert. Used when the app has no server-side
-- alert to close (an SOS still queued offline).
CREATE OR REPLACE FUNCTION public.verify_emergency_pin(p_pin text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING ERRCODE = '42501';
  END IF;
  RETURN public._check_emergency_pin(v_uid, p_pin);
END;
$$;

-- Verify the PIN and close the alert, in one call, recording who did it.
--
-- Returns: 'RESOLVED' (safe PIN), 'DURESS' (duress PIN — the alert is marked
-- DURESS and is NOT a normal resolution; HQ sees it as an escalation),
-- 'INVALID', 'LOCKED', 'UNSET', or 'NOT_FOUND' (no alert of that id that this
-- user reported or is assigned to).
CREATE OR REPLACE FUNCTION public.resolve_emergency(p_alert_id uuid, p_pin text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid  uuid := auth.uid();
  v_kind text;
  v_rows integer;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING ERRCODE = '42501';
  END IF;

  v_kind := public._check_emergency_pin(v_uid, p_pin);
  IF v_kind NOT IN ('SAFE', 'DURESS') THEN
    RETURN v_kind;
  END IF;

  -- Only the person who raised the alert, or the responder assigned to it, can
  -- close it with a PIN. Staff resolve from the console, not from here.
  UPDATE public.alerts
     SET status      = CASE v_kind WHEN 'SAFE' THEN 'RESOLVED' ELSE 'DURESS' END,
         resolved_by = v_uid::text,
         resolved_at = now(),
         updated_at  = now()
   WHERE id = p_alert_id
     AND (reported_by = v_uid OR assigned_to = v_uid);
  GET DIAGNOSTICS v_rows = ROW_COUNT;

  IF v_rows = 0 THEN
    RETURN 'NOT_FOUND';
  END IF;
  RETURN CASE v_kind WHEN 'SAFE' THEN 'RESOLVED' ELSE 'DURESS' END;
END;
$$;

-- ────────────────────────────────────────────────────────────────────────────
-- 4. WHO MAY CALL WHAT
-- ────────────────────────────────────────────────────────────────────────────

REVOKE ALL ON FUNCTION public._check_emergency_pin(uuid, text) FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.set_emergency_pins(text, text)   FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.has_emergency_pins()             FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.verify_emergency_pin(text)       FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.resolve_emergency(uuid, text)    FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.set_emergency_pins(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.has_emergency_pins()           TO authenticated;
GRANT EXECUTE ON FUNCTION public.verify_emergency_pin(text)     TO authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_emergency(uuid, text)  TO authenticated;

-- ----------------------------------------------------------------------------
-- 20260903000000_realtime_publication.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20260903000000_realtime_publication.sql'; END $apply$;

-- ============================================================================
-- OPERATION RAINBOW — REALTIME PUBLICATION
--
-- The HQ console subscribes to postgres_changes on three tables that were never
-- added to the supabase_realtime publication by any migration:
--
--   agency_action_reports   dashboard unread-report badge, agency portal
--   agency_deployments      agency portal
--   uninstall_requests      uninstall-request queue
--
-- A subscription on a table outside the publication does not error. It simply
-- never fires, so the badge and the portal only refresh on page reload. On the
-- dashboard the unread-report count is what tells HQ an agency has filed an
-- after-action report; silently stale is the worst kind of wrong for it.
--
-- Idempotent: each table is added only if present and not already published.
-- ALTER PUBLICATION ... ADD TABLE raises if the table is already a member, and
-- the initial schema added the first five tables unconditionally, so this must
-- check pg_publication_tables rather than repeat that pattern.
-- ============================================================================

DO $realtime$
DECLARE
  t TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    RAISE NOTICE 'no supabase_realtime publication in this database; nothing to do';
    RETURN;
  END IF;

  FOREACH t IN ARRAY ARRAY[
    'alerts', 'telemetry', 'chat_messages', 'system_alerts', 'profiles',
    'agency_action_reports', 'agency_deployments', 'uninstall_requests'
  ] LOOP
    IF to_regclass('public.' || t) IS NULL THEN
      RAISE NOTICE 'skipping %: table not present in this database', t;
      CONTINUE;
    END IF;
    IF EXISTS (
      SELECT 1 FROM pg_publication_tables
       WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = t
    ) THEN
      CONTINUE;
    END IF;
    EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
    RAISE NOTICE 'added % to supabase_realtime', t;
  END LOOP;
END $realtime$;

-- ----------------------------------------------------------------------------
-- 20260903000001_incident_media_storage.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20260903000001_incident_media_storage.sql'; END $apply$;

-- ============================================================================
-- OPERATION RAINBOW — INCIDENT MEDIA STORAGE
--
-- The mobile app uploads incident photos, video and voice reports to the
-- Supabase Storage bucket `incident-media` when Cloudinary is unavailable
-- (lib/services/alert_service.dart, lib/services/sync_service.dart), and both
-- apps display them through public URLs. Nothing in this repository created the
-- bucket or any policy on storage.objects. Storage RLS is enabled by default and
-- deny-all without policies, so on a fresh project every fallback upload fails,
-- and on production whatever was clicked together in the dashboard is
-- undocumented and unreviewed.
--
-- WHAT THIS SETS
--   * The bucket exists, is public (the apps read via getPublicUrl), accepts
--     only image/video/audio, and caps objects at 50 MB — the per-object limit
--     of the Supabase Free plan, so a larger setting would be silently lower.
--   * Any signed-in user may UPLOAD into it. Uploads are evidence from the
--     field, and the reporter is often a citizen.
--   * Nobody may UPDATE or DELETE through the API roles. Evidence is
--     append-only; removal is a service-role operation with an audit trail.
--   * Listing the bucket through the API is limited to staff. The bucket being
--     public means an object is readable BY ITS URL; it does not mean the
--     bucket may be enumerated, which would hand every piece of evidence to
--     anyone with the anon key.
--
-- Object URLs are unguessable (millisecond timestamp plus a random id) but not
-- secret: anyone who has one can open it. A private bucket with signed URLs
-- would be stronger, and is noted as a follow-up in E2E_AUDIT_REPORT.md; it
-- needs every media renderer in both apps changed first.
--
-- Guarded by existence so a vanilla PostgreSQL replica (the CI harness ships a
-- storage shim) and Supabase both accept it. Idempotent: safe to re-run.
-- ============================================================================

DO $storage$
BEGIN
  IF to_regclass('storage.buckets') IS NULL OR to_regclass('storage.objects') IS NULL THEN
    RAISE NOTICE 'no storage schema in this database; skipping incident-media setup';
    RETURN;
  END IF;

  INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  VALUES ('incident-media', 'incident-media', true, 52428800,
          ARRAY['image/*', 'video/*', 'audio/*'])
  ON CONFLICT (id) DO UPDATE
    SET public             = EXCLUDED.public,
        file_size_limit    = EXCLUDED.file_size_limit,
        allowed_mime_types = EXCLUDED.allowed_mime_types;

  -- Replace, never accumulate: PERMISSIVE policies OR together, so a stale
  -- wider policy left in place would silently win.
  DROP POLICY IF EXISTS "incident_media_upload"      ON storage.objects;
  DROP POLICY IF EXISTS "incident_media_staff_list"  ON storage.objects;

  CREATE POLICY "incident_media_upload" ON storage.objects
    FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'incident-media');

  CREATE POLICY "incident_media_staff_list" ON storage.objects
    FOR SELECT TO authenticated
    USING (bucket_id = 'incident-media' AND public.is_staff());

  -- No UPDATE / DELETE policy on purpose (see header).
END $storage$;

-- ----------------------------------------------------------------------------
-- 20260903000002_system_alerts_broadcast.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20260903000002_system_alerts_broadcast.sql'; END $apply$;

-- ============================================================================
-- OPERATION RAINBOW — MASS BROADCAST, MADE TO WORK
--
-- `system_alerts` is how HQ warns the public and its own responders. It did not
-- work. Four independent faults, none of which surfaced as anything an operator
-- would read as failure:
--
--   1. NEITHER WRITER SUPPLIED `title`, which is NOT NULL with no default. On a
--      database built from these migrations every broadcast raised a not-null
--      violation. The console printed the raw Postgres message; the mobile
--      admin screen printed "Error sending broadcast: <exception>".
--
--   2. The console wrote SIX COLUMNS THAT EXIST IN NO MIGRATION —
--      target_agency, target_sector, target_lga, target_ward, target_pu,
--      active — so PostgREST rejected the insert before the constraint could
--      even be reached.
--
--   3. Audience targeting was IGNORED. The console wrote `target_audience`;
--      the mobile reader filtered on `target_type`, which defaults to 'ALL'.
--      A "FIELD RESPONDERS ONLY" advisory therefore reached every citizen,
--      while the console reported it had gone to responders only.
--
--   4. Geographic targeting was enforced NOWHERE. The console offers LGA, ward
--      and polling-unit scoping and reports "dispatched to JOS NORTH LGA";
--      no reader ever filtered on it, so every advisory went statewide.
--
-- Faults 3 and 4 are the dangerous ones. A broadcast that fails loudly gets
-- re-sent by radio. A broadcast that reports success while going to the wrong
-- people does not — and on this system that is either a panic sent to the whole
-- state or an evacuation order that never reaches the ward it was meant for.
--
-- WHAT IS CANONICAL NOW
--
-- `lib/core/models/broadcast_alert.dart` already declared targetLga, targetWard,
-- targetPu and targetAudience: the intended design was always the wider one, and
-- only the schema never caught up. So the columns are added here, and the code
-- is changed to agree on one name per concept:
--
--   audience   target_audience     (target_type kept, read as a fallback for
--                                   rows written before this)
--   active     is_active           (the console wrote `active`; that column
--                                   never existed)
--   scope      target_lga / target_ward / target_pu / target_agency
--
-- Idempotent: safe to re-run.
-- ============================================================================

DO $broadcast$
BEGIN
  IF to_regclass('public.system_alerts') IS NULL THEN
    RAISE NOTICE 'skipping system_alerts: table not present in this database';
    RETURN;
  END IF;

  -- The scoping the console has been offering all along.
  ALTER TABLE public.system_alerts
    ADD COLUMN IF NOT EXISTS target_audience TEXT DEFAULT 'ALL',
    ADD COLUMN IF NOT EXISTS target_agency   TEXT DEFAULT 'ALL',
    ADD COLUMN IF NOT EXISTS target_lga      TEXT DEFAULT 'ALL',
    ADD COLUMN IF NOT EXISTS target_ward     TEXT DEFAULT 'ALL',
    ADD COLUMN IF NOT EXISTS target_pu       TEXT DEFAULT 'ALL',
    ADD COLUMN IF NOT EXISTS expires_at      TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '24 hours');

  -- `title` stays NOT NULL — a broadcast with no heading is a worse artefact
  -- than one with a generic heading — but it gets a default, so no writer can
  -- fail the insert on it again. Both writers now send a real one.
  ALTER TABLE public.system_alerts ALTER COLUMN title SET DEFAULT 'ADVISORY';

  -- Rows written before this migration have no audience recorded under the
  -- canonical name. Carry the legacy value across rather than leaving them to
  -- the reader's fallback forever. Only touches rows where the canonical column
  -- is genuinely empty, so re-running changes nothing.
  UPDATE public.system_alerts
     SET target_audience = COALESCE(NULLIF(target_type, ''), 'ALL')
   WHERE target_audience IS NULL;

  -- Reads are always "the live advisories for this audience", never a table
  -- scan, and this is on the path of every app launch.
  CREATE INDEX IF NOT EXISTS system_alerts_live_idx
    ON public.system_alerts (is_active, expires_at DESC);
END $broadcast$;

-- ----------------------------------------------------------------------------
-- 20260903000003_alert_escalation_columns.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20260903000003_alert_escalation_columns.sql'; END $apply$;

-- ============================================================================
-- OPERATION RAINBOW — ESCALATION COLUMNS
--
-- `alerts.escalated_to_agency` and `alerts.escalation_log` are written by BOTH
-- apps and read by the HQ console, and neither is created by any migration in
-- this repository:
--
--   written   hq-dashboard-next/src/lib/alert-actions.ts   (escalateAlert)
--             lib/features/agent/agent_dashboard_screen.dart
--   read      hq-dashboard-next/src/components/AgencyPortal.tsx
--               .eq('escalated_to_agency', agency)  ← the portal's whole feed
--               escalation_log rendered as the chain of custody
--             alert-actions.ts, to APPEND to the log rather than replace it
--
-- Unlike the columns removed in the same pass, these are not dead writes:
-- something reads them, and the agency portal is built on one of them. They are
-- production columns that were added by hand and never written down — the same
-- drift that left the four `agency_*` tables out of this repository.
--
-- So a replica rebuilt from these files could not escalate an incident at all:
-- PostgREST rejects an update naming an unknown column in full, so the whole
-- escalation — status, severity, assignment, the audit note — failed with it.
--
-- On production both columns already exist and this is a no-op.
--
-- A NOTE ON WHAT GOES IN escalated_to_agency
--
-- The two writers disagree. The mobile agent dashboard wrote a TIER ('HQ',
-- 'LGA') here — its own comment said "tier label for filtering" — so a mobile
-- escalation was invisible to every agency portal while still showing as
-- ESCALATED on the HQ board. That has since been given its own column,
-- `assigned_tier`, and the mobile side writes it there.
--
-- CORRECTION, 2026-10-07. This comment used to say the console writes an agency
-- code, 'POLICE' or 'ARMY', "which is what AgencyPortal filters on". It did not.
-- The console's escalation menu was built from the list that badges Operation
-- Rainbow's own staff, so it wrote 'NPF', 'MILITARY', 'RAINBOW' or 'VGN' —
-- codes no liaison role, portal or contact variable knows. An incident handed
-- to the Police was stored as 'NPF' and the Police portal, which asks for
-- 'POLICE', never showed it. Fixed on the console side; the column stays free
-- text because production holds rows written before any of this was settled.
-- Recorded in E2E_AUDIT_REPORT.md.
--
-- Idempotent: safe to re-run.
-- ============================================================================

DO $escalation$
BEGIN
  IF to_regclass('public.alerts') IS NULL THEN
    RAISE NOTICE 'skipping alerts: table not present in this database';
    RETURN;
  END IF;

  ALTER TABLE public.alerts
    -- Free text rather than an enum: it holds agency codes from one writer and
    -- tier labels from the other, and a constraint here would start rejecting
    -- writes that production accepts today.
    ADD COLUMN IF NOT EXISTS escalated_to_agency TEXT,
    -- Append-only chain of custody. JSONB, not JSON: both writers read the
    -- array back and append to it, and `[]` must be the default or that read
    -- returns NULL and the spread drops the history.
    ADD COLUMN IF NOT EXISTS escalation_log JSONB NOT NULL DEFAULT '[]'::jsonb;

  -- AgencyPortal's feed is `WHERE escalated_to_agency = $1` on every load and
  -- on every realtime change.
  CREATE INDEX IF NOT EXISTS alerts_escalated_to_agency_idx
    ON public.alerts (escalated_to_agency)
    WHERE escalated_to_agency IS NOT NULL;
END $escalation$;

-- ----------------------------------------------------------------------------
-- 20260903000004_profiles_badge_number.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20260903000004_profiles_badge_number.sql'; END $apply$;

-- ============================================================================
-- OPERATION RAINBOW — profiles.badge_number
--
-- Both apps read it and no migration creates it:
--
--   hq-dashboard-next/src/app/dashboard/page.tsx   formatOfficerBadge() and
--     getOfficerDisplayName() — six call sites. Every officer shown on the
--     board, on an incident card and in a dispatch list is labelled from it.
--   lib/features/agent/agent_dashboard_screen.dart  selects it explicitly when
--     listing responders to dispatch.
--
-- The mobile's select names it, so on a database without the column PostgREST
-- rejects that query in full and the responder list comes back empty — an agent
-- cannot dispatch anyone. The console reads it out of a map rather than naming
-- it in a select, so there it degrades quietly instead: officers fall back to
-- `TACTICAL SQUAD #A1B2C3`.
--
-- Operational badge identifiers ("HQ-001", "NP/JOS/001") are how officers are
-- referred to on radio, so this is display-critical rather than cosmetic: a
-- board that shows an opaque id cannot be read against what is being said.
--
-- Not used for authentication. The login screen derives an email from the badge
-- the operator types; nothing reads this column to decide access. It is a label.
--
-- On production it exists already and this is a no-op. Idempotent.
-- ============================================================================

DO $badge$
BEGIN
  IF to_regclass('public.profiles') IS NULL THEN
    RAISE NOTICE 'skipping profiles: table not present in this database';
    RETURN;
  END IF;

  ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS badge_number TEXT;

  -- Both resolvers fall back to scanning every profile for a matching badge
  -- when a lookup by id misses.
  CREATE INDEX IF NOT EXISTS profiles_badge_number_idx
    ON public.profiles (badge_number)
    WHERE badge_number IS NOT NULL;
END $badge$;

-- ----------------------------------------------------------------------------
-- 20260903000005_alerts_assigned_tier.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20260903000005_alerts_assigned_tier.sql'; END $apply$;

-- ============================================================================
-- OPERATION RAINBOW — WHICH TIER OWNS AN INCIDENT
--
-- The command chain is POLLING_UNIT → WARD → LGA → HQ, and an incident is
-- escalated up it from the mobile agent dashboard. That tier had no column.
-- It was being written into two that could not hold it:
--
--   alerts.assigned_to        is UUID REFERENCES profiles(id). The mobile wrote
--                             `targetCommanderId ?? targetTier`, so whenever no
--                             specific commander was chosen it sent the string
--                             'LGA' to a uuid column. PostgreSQL rejects that
--                             outright — `invalid input syntax for type uuid` —
--                             and since it is one UPDATE, the ENTIRE escalation
--                             went with it: status, severity, the escalation
--                             log and the audit note. The agent saw a failure
--                             with no indication that the tier was the cause.
--
--   alerts.escalated_to_agency is what the agency portal filters on
--                             (`.eq('escalated_to_agency', agency)`) with values
--                             like POLICE and ARMY. The mobile wrote the tier
--                             there too, so an internal escalation to LGA sat in
--                             the same column as a handover to the police.
--
-- And the HQ board's tier filter compared `assigned_to` — the uuid column —
-- against 'WARD'/'LGA'/'HQ', so it could only ever have matched rows that the
-- database refuses to accept. The filter has never selected anything.
--
-- One column per concept:
--
--   assigned_to           WHO owns it   — a person, by uuid
--   assigned_tier         WHICH TIER owns it
--   escalated_to_agency   WHICH OUTSIDE AGENCY it was handed to
--
-- Idempotent: safe to re-run.
-- ============================================================================

DO $tier$
BEGIN
  IF to_regclass('public.alerts') IS NULL THEN
    RAISE NOTICE 'skipping alerts: table not present in this database';
    RETURN;
  END IF;

  -- Free text, not an enum: the tier vocabulary is set by the app's routing
  -- rules, and a constraint here would reject writes production accepts today.
  ALTER TABLE public.alerts ADD COLUMN IF NOT EXISTS assigned_tier TEXT;

  -- The board's tier filter runs on every render.
  CREATE INDEX IF NOT EXISTS alerts_assigned_tier_idx
    ON public.alerts (assigned_tier)
    WHERE assigned_tier IS NOT NULL;

  -- Rows escalated before this migration carry the tier in
  -- `escalated_to_agency`, mixed in with real agency handovers. Move only the
  -- values that are unambiguously tiers; anything else is a genuine agency and
  -- is left exactly where the portal expects it.
  UPDATE public.alerts
     SET assigned_tier = escalated_to_agency,
         escalated_to_agency = NULL
   WHERE assigned_tier IS NULL
     AND escalated_to_agency IN ('POLLING_UNIT', 'PU', 'WARD', 'LGA', 'HQ');
END $tier$;

-- ----------------------------------------------------------------------------
-- 20260927000000_signup_cannot_choose_role.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20260927000000_signup_cannot_choose_role.sql'; END $apply$;

-- ============================================================================
-- OPERATION RAINBOW — A SIGNUP MAY NOT CHOOSE ITS OWN ROLE
--
-- THE HOLE
--
-- `handle_new_user()` has, since the initial schema, created the profile like
-- this:
--
--     role := COALESCE(NEW.raw_user_meta_data->>'role', 'CITIZEN')
--
-- `raw_user_meta_data` is `options.data` from `supabase.auth.signUp`, written
-- by whoever is signing up, with the anon key — which ships inside the APK and
-- inside the browser bundle, by design, because row-level security is meant to
-- be the whole access model.
--
-- So this was enough to become a commander:
--
--     supabase.auth.signUp({
--       email, password,
--       options: { data: { role: 'HQ_COMMAND' } },
--     })
--
-- and `is_command()` / `is_staff()` read `profiles.role`, so that account then
-- passes every policy in the RLS migration: the full incident board, live
-- telemetry for every citizen who has pressed SOS, dispatch, escalation, mass
-- broadcast to the whole state.
--
-- WHY THE EXISTING GUARD DID NOT COVER IT
--
-- `profiles_no_privilege_escalation` is BEFORE UPDATE. The escalation is not an
-- update — the role is chosen at INSERT, by the signup itself. README.md said
-- "nothing reads user_metadata", which was true of the policies and not true of
-- the trigger that creates the row the policies read.
--
-- THE FIX
--
-- Signup no longer reads `role` at all. Every account created through the
-- public auth endpoint is a CITIZEN, whatever it asks for, and `full_name` and
-- `phone` are still honoured because they are not privileges.
--
-- Staff are provisioned by a privileged caller instead: create the account,
-- then set `profiles.role` with the service key. That path is unaffected — the
-- UPDATE guard already exempts `service_role` — and it is what
-- `/api/admin/provision` now does. The console's "Provision Security Personnel
-- Account" form used to rely on the hole: it passed the chosen role in
-- `options.data` and the trigger obligingly applied it.
--
-- A NOTE ON WHAT IS NOT DONE HERE
--
-- Existing profiles are left alone. This migration cannot tell an account that
-- was legitimately provisioned as HQ_COMMAND from one that asked to be. That
-- audit is in E2E_AUDIT_REPORT.md as an operational step, with the query for
-- it, because it needs a human who knows who is supposed to be staff.
--
-- Idempotent: safe to re-run.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
-- SECURITY DEFINER with no search_path is how a SECURITY DEFINER function gets
-- hijacked by a schema earlier on the caller's path. Pinned.
SET search_path = public, pg_temp
AS $func$
BEGIN
  INSERT INTO public.profiles (id, email, phone, full_name, role)
  VALUES (
    NEW.id,
    NEW.email,
    NEW.phone,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', 'User'),
    -- NOT from the metadata. A signup does not get to say what it is.
    'CITIZEN'
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    phone = EXCLUDED.phone,
    updated_at = NOW();
  RETURN NEW;
END;
$func$;

-- The trigger itself is unchanged in shape; recreated so this file is complete
-- on a database that somehow lacks it.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ----------------------------------------------------------------------------
-- 20260928000000_command_chain_escalation.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20260928000000_command_chain_escalation.sql'; END $apply$;

-- ============================================================================
-- OPERATION RAINBOW — THE COMMAND CHAIN
--
-- An alert lands at the POLLING UNIT. The PU escalates to the WARD, the WARD to
-- the LGA, the LGA to HQ. HQ is the top: it overrides when the chain below it
-- is not responding.
--
-- Three things were missing for that to be true.
--
-- 1. NOTHING PUT AN ALERT AT THE PU.
--
--    `assigned_tier` was nullable with no default, so an alert arrived owned by
--    nobody. The chain had a ladder but no bottom rung. It defaults to 'UNIT'
--    now, in the DATABASE rather than in a client, because an alert inserted by
--    the mobile app, by the console, by the offline queue replaying, or by a
--    future integration must all land in the same place. A client-side default
--    is one forgotten call site away from an unowned emergency.
--
-- 2. THE TIMEOUTS WERE CONFIGURED AND DEAD.
--
--    `app_config` has seeded escalation timeouts — PU 2 minutes, WARD 5, LGA 10
--    — and the console's System Logic screen lets an operator edit them. The
--    ONLY code that touched those keys was the screen that displays and saves
--    them. Nothing ever escalated on a timeout. An operator setting "PU
--    timeout: 2 minutes" was configuring a policy that did not exist.
--
--    That is the worst kind of dead setting: it is not missing, it is
--    reassuring. `escalate_overdue_alerts()` below makes it real.
--
-- 3. THERE WAS NO CLOCK ON OWNERSHIP.
--
--    Nothing recorded WHEN a tier took an alert, so "has this tier had it too
--    long?" was unanswerable. `tier_assigned_at` starts that clock on insert
--    and restarts it on every escalation.
--
-- WHY SERVER-SIDE
--
-- A tier that is not responding is very often a tier that is offline. An
-- escalation that only runs while somebody has the console open cannot fire in
-- exactly the case it exists for. This runs in the database.
--
-- Idempotent: safe to re-run.
-- ============================================================================

-- ── Columns ─────────────────────────────────────────────────────────────────

ALTER TABLE public.alerts
  -- The rung that OWNS this alert now. 'UNIT' -> 'WARD' -> 'LGA' -> 'HQ'.
  ADD COLUMN IF NOT EXISTS assigned_tier TEXT,
  -- When the current owner took it. The timeout is measured from here, not
  -- from created_at: an alert escalated to the WARD gets the WARD's full
  -- window, not whatever is left of the PU's.
  ADD COLUMN IF NOT EXISTS tier_assigned_at TIMESTAMPTZ,
  -- Set when a responder at the owning tier acknowledges. An acknowledged
  -- alert stops climbing: somebody has it.
  ADD COLUMN IF NOT EXISTS acknowledged_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS acknowledged_by UUID;

-- New alerts land at the polling unit, and the clock starts.
ALTER TABLE public.alerts
  ALTER COLUMN assigned_tier SET DEFAULT 'UNIT';

-- Existing rows: anything still open and unowned belongs to the PU.
UPDATE public.alerts
   SET assigned_tier = 'UNIT'
 WHERE assigned_tier IS NULL
   AND status NOT IN ('RESOLVED', 'CANCELLED');

-- Backfill the clock from the row's own age, so a migration does not make
-- every historical alert look as though it just arrived — and then instantly
-- escalate the lot to HQ the first time the job runs.
UPDATE public.alerts
   SET tier_assigned_at = COALESCE(updated_at, created_at, NOW())
 WHERE tier_assigned_at IS NULL;

ALTER TABLE public.alerts
  ALTER COLUMN tier_assigned_at SET DEFAULT NOW();

-- The job scans on these two.
CREATE INDEX IF NOT EXISTS alerts_chain_idx
  ON public.alerts (assigned_tier, tier_assigned_at)
  WHERE acknowledged_at IS NULL;

-- ── The ladder, as data ─────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.next_tier(current_tier TEXT)
RETURNS TEXT
LANGUAGE sql IMMUTABLE
SET search_path = public, pg_temp
AS $$
  SELECT CASE upper(coalesce(current_tier, 'UNIT'))
           WHEN 'UNIT' THEN 'WARD'
           WHEN 'WARD' THEN 'LGA'
           WHEN 'LGA'  THEN 'HQ'
           -- HQ is the top. NULL means "nowhere left to go", which is what
           -- stops an alert cycling round the chain forever.
           ELSE NULL
         END;
$$;

COMMENT ON FUNCTION public.next_tier(TEXT) IS
  'The rung above this one. NULL at HQ: the chain terminates rather than loops.';

-- ── The timeout for a tier, from app_config ─────────────────────────────────

CREATE OR REPLACE FUNCTION public.tier_timeout_minutes(tier TEXT)
RETURNS INTEGER
LANGUAGE plpgsql STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  key_name TEXT;
  raw      TEXT;
  parsed   INTEGER;
BEGIN
  key_name := CASE upper(coalesce(tier, ''))
                WHEN 'UNIT' THEN 'escalation_timeout_pu'
                WHEN 'WARD' THEN 'escalation_timeout_ward'
                WHEN 'LGA'  THEN 'escalation_timeout_lga'
                ELSE NULL
              END;
  IF key_name IS NULL THEN
    RETURN NULL;  -- HQ, or an unknown tier: no timeout applies.
  END IF;

  SELECT value INTO raw FROM public.app_config WHERE key = key_name;

  -- A missing or malformed setting must not silently mean "escalate
  -- immediately" (a timeout of 0) or "never escalate" (NULL treated as
  -- infinite). Both are dangerous defaults for an emergency queue, so fall
  -- back to the seeded values.
  BEGIN
    parsed := raw::INTEGER;
  EXCEPTION WHEN others THEN
    parsed := NULL;
  END;

  IF parsed IS NULL OR parsed <= 0 THEN
    parsed := CASE upper(tier)
                WHEN 'UNIT' THEN 2
                WHEN 'WARD' THEN 5
                WHEN 'LGA'  THEN 10
              END;
  END IF;

  RETURN parsed;
END;
$$;

-- ── The job ─────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.escalate_overdue_alerts()
RETURNS TABLE (alert_id UUID, from_tier TEXT, to_tier TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN QUERY
  WITH overdue AS (
    SELECT a.id,
           upper(a.assigned_tier)               AS current_tier,
           public.next_tier(a.assigned_tier)    AS target_tier
      FROM public.alerts a
     WHERE a.status NOT IN ('RESOLVED', 'CANCELLED')
       -- Acknowledged means somebody at this tier has it. Climbing past a
       -- responder who is already on it is how you get two units dispatched
       -- to the same incident and none to the next one.
       AND a.acknowledged_at IS NULL
       AND public.next_tier(a.assigned_tier) IS NOT NULL
       AND a.tier_assigned_at IS NOT NULL
       AND a.tier_assigned_at <
             NOW() - make_interval(
               mins => public.tier_timeout_minutes(a.assigned_tier)
             )
     FOR UPDATE OF a SKIP LOCKED
  )
  UPDATE public.alerts a
     SET assigned_tier    = o.target_tier,
         tier_assigned_at = NOW(),
         status           = 'ESCALATED',
         updated_at       = NOW(),
         -- Append, never replace: the chain of custody is the point. Written
         -- in the same shape the apps write, so one reader handles both.
         escalation_log = COALESCE(a.escalation_log, '[]'::jsonb) || jsonb_build_object(
           'from_tier',  o.current_tier,
           'to_tier',    o.target_tier,
           'reason',     'TIMEOUT',
           'by',         'SYSTEM',
           'at',         to_char(NOW() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
         )
    FROM overdue o
   WHERE a.id = o.id
  RETURNING a.id, o.current_tier, o.target_tier;
END;
$$;

COMMENT ON FUNCTION public.escalate_overdue_alerts() IS
  'Climbs unacknowledged alerts one rung when their tier has held them longer '
  'than app_config allows. Returns what it moved. Idempotent per run.';

-- Only the service role runs this. It is SECURITY DEFINER and reassigns
-- ownership of emergencies; nothing signed in from a phone should call it.
REVOKE ALL ON FUNCTION public.escalate_overdue_alerts() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.escalate_overdue_alerts() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.escalate_overdue_alerts() TO service_role;

-- ── Scheduling ──────────────────────────────────────────────────────────────
--
-- pg_cron is available on Supabase but is not present in a bare PostgreSQL, so
-- this is conditional: the harness proves the FUNCTION, and the schedule is
-- attached wherever the extension exists.
DO $sched$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'pg_cron') THEN
    CREATE EXTENSION IF NOT EXISTS pg_cron;

    -- Every minute. The shortest configured timeout is two minutes, so a
    -- minute of granularity costs at most a minute of delay.
    PERFORM cron.unschedule('rainbow-escalate-overdue')
      WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'rainbow-escalate-overdue');

    PERFORM cron.schedule(
      'rainbow-escalate-overdue',
      '* * * * *',
      $job$SELECT public.escalate_overdue_alerts();$job$
    );
    RAISE NOTICE 'escalation job scheduled every minute';
  ELSE
    RAISE NOTICE 'pg_cron unavailable: escalate_overdue_alerts() must be driven externally';
  END IF;
END
$sched$;

-- ----------------------------------------------------------------------------
-- 20260929000000_telemetry_is_not_a_standing_feed.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20260929000000_telemetry_is_not_a_standing_feed.sql'; END $apply$;

-- ============================================================================
-- OPERATION RAINBOW — LOCATION IS BORROWED, NOT KEPT
--
-- Three things were true of `telemetry` at once, and together they made this
-- table a standing surveillance feed on private citizens rather than a live
-- picture of an emergency in progress.
--
-- 1. EVERY STAFF ACCOUNT COULD READ EVERY ROW.
--
--    `telemetry_select_self_or_staff` was `user_id = auth.uid() OR
--    is_staff()`. `is_staff()` is true for a polling-unit officer in Wase as
--    readily as for the HQ commander, and it is not scoped to an incident, a
--    jurisdiction, or a shift. So the live position of any citizen who had
--    ever pressed the panic button was readable by every operational account
--    in the state, for as long as the row existed.
--
-- 2. NOTHING DELETED ANYTHING.
--
--    One row per user, updated in place, kept forever. The last known position
--    of every person who has ever used the panic button sits in this table
--    indefinitely — long after the emergency, and long after any purpose that
--    could justify holding it.
--
-- 3. THE ROW OUTLIVED THE EMERGENCY.
--
--    Nothing linked a track to the incident it was for, and nothing stopped
--    writing when the incident closed.
--
-- The app side of (3) is fixed in `background_tracking_service.dart`, which
-- now carries `alert_id`, honours an expiry, stops when the alert is resolved
-- and stops on sign-out. This file fixes the database side, because a client
-- that stops asking is not the same as a server that stops answering — and it
-- is the server that decides who may look.
--
-- WHAT THIS DELIBERATELY DOES NOT DO
--
-- It does not restrict a responder's own operational visibility, and it does
-- not touch the duress path. A duress PIN keeps a track running on purpose:
-- the person may still be in danger, and HQ must be able to follow. That stays
-- true. What changes is that the track now ends, and that only people with a
-- reason to look can look while it runs.
--
-- Idempotent: safe to re-run.
-- ============================================================================

-- ── Who may read a position ─────────────────────────────────────────────────

DROP POLICY IF EXISTS "telemetry_select_self_or_staff" ON public.telemetry;
DROP POLICY IF EXISTS "telemetry_select_self_or_responding_staff" ON public.telemetry;

-- A staff member sees another STAFF member's position freely: that is the
-- movement board, it is what `MOVEMENT` shows, and officers on duty being
-- visible to each other is the point of it.
--
-- A CITIZEN's position is visible only while they have an emergency open — and
-- then to any staff member, deliberately, because whoever is nearest may not
-- be whoever it was assigned to. Once the incident is resolved or cancelled,
-- the row stops being readable by anyone but its owner.
DROP POLICY IF EXISTS "telemetry_select_self_or_responding_staff" ON public.telemetry;
CREATE POLICY "telemetry_select_self_or_responding_staff" ON public.telemetry
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR (
      public.is_staff()
      AND (
        -- the subject is themselves on duty
        EXISTS (
          SELECT 1 FROM public.profiles p
           WHERE p.id = telemetry.user_id
             AND p.role NOT IN ('CITIZEN', 'USER')
        )
        -- or the subject has a live emergency right now
        OR EXISTS (
          SELECT 1 FROM public.alerts a
           WHERE a.reported_by = telemetry.user_id
             AND a.status NOT IN ('RESOLVED', 'CANCELLED')
        )
      )
    )
  );

COMMENT ON POLICY "telemetry_select_self_or_responding_staff" ON public.telemetry IS
  'Own position always; a colleague''s position if you are staff; a citizen''s '
  'position only while they have an emergency open.';

-- ── Nothing is kept forever ─────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.purge_stale_telemetry()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  removed INTEGER;
BEGIN
  -- A position older than a day is of no operational use to anybody: the
  -- emergency is over, and the person has moved. Keeping it is a liability
  -- with no matching benefit.
  --
  -- A row belonging to a CURRENTLY OPEN alert is never purged on age, however
  -- old, because an unresolved emergency is exactly the case where the last
  -- known position still matters.
  DELETE FROM public.telemetry t
   WHERE t.updated_at < NOW() - INTERVAL '24 hours'
     AND NOT EXISTS (
       SELECT 1 FROM public.alerts a
        WHERE a.reported_by = t.user_id
          AND a.status NOT IN ('RESOLVED', 'CANCELLED')
     );
  GET DIAGNOSTICS removed = ROW_COUNT;
  RETURN removed;
END;
$$;

COMMENT ON FUNCTION public.purge_stale_telemetry() IS
  'Deletes positions older than 24h that do not belong to an open emergency.';

REVOKE ALL ON FUNCTION public.purge_stale_telemetry() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.purge_stale_telemetry() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.purge_stale_telemetry() TO service_role;

-- Same conditional shape as the escalation job: pg_cron exists on Supabase and
-- not in a bare PostgreSQL, so the harness proves the FUNCTION and the schedule
-- attaches wherever the extension is available.
DO $sched$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'pg_cron') THEN
    CREATE EXTENSION IF NOT EXISTS pg_cron;
    PERFORM cron.unschedule('rainbow-purge-telemetry')
      WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'rainbow-purge-telemetry');
    PERFORM cron.schedule(
      'rainbow-purge-telemetry',
      '17 * * * *',
      $job$SELECT public.purge_stale_telemetry();$job$
    );
    RAISE NOTICE 'telemetry purge scheduled hourly';
  ELSE
    RAISE NOTICE 'pg_cron unavailable: purge_stale_telemetry() must be driven externally';
  END IF;
END
$sched$;

-- ============================================================================
-- CHAT: YOU MAY ONLY WRITE INTO A CONVERSATION YOU ARE PART OF
--
-- `chat_select_participant_or_staff` is careful: you read a thread if you sent
-- the message, or you are staff, or you are the alert's reporter or assignee.
--
-- `chat_insert_as_self` checked one thing — `sender_id = auth.uid()` — which
-- says you cannot forge somebody else's name. It says nothing about WHICH
-- conversation you may write into. So any authenticated account could post
-- into any incident's tactical channel, including incidents they cannot read,
-- given an alert id. On a channel that responders act on, injecting messages
-- into somebody else's emergency is the whole attack.
--
-- The asymmetry is the bug: reading was scoped to participation and writing
-- was not. Now both are.
-- ============================================================================

DROP POLICY IF EXISTS "chat_insert_as_self" ON public.chat_messages;
DROP POLICY IF EXISTS "chat_insert_participant" ON public.chat_messages;

CREATE POLICY "chat_insert_participant" ON public.chat_messages
  FOR INSERT TO authenticated
  WITH CHECK (
    sender_id = auth.uid()
    AND (
      public.is_staff()
      OR EXISTS (
        SELECT 1 FROM public.alerts a
         WHERE a.id = chat_messages.alert_id
           AND (a.reported_by = auth.uid() OR a.assigned_to = auth.uid())
      )
    )
  );

COMMENT ON POLICY "chat_insert_participant" ON public.chat_messages IS
  'Write as yourself, and only into a thread you are a participant in. Mirrors '
  'chat_select_participant_or_staff, which was already scoped this way.';

-- ----------------------------------------------------------------------------
-- 20260930000000_sms_device_keys.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20260930000000_sms_device_keys.sql'; END $apply$;

-- ============================================================================
-- OPERATION RAINBOW — A KEY PER HANDSET, FOR THE SMS FALLBACK
--
-- The SMS fallback carries an alert as 54 encrypted bytes, so that a report
-- sent when there is cell signal but no data is readable by HQ and by nobody
-- else — not the carrier, not anyone holding the handset and reading its sent
-- folder. That needs a key, and WHICH key it is decides what the channel is
-- worth.
--
-- WHY PER-DEVICE, AND NOT ONE APP KEY
--
-- A single key compiled into the app is extracted from the APK with `unzip`,
-- as this project already learned the expensive way with the Termii
-- credential. With one shared key, anyone who pulls it can forge an emergency
-- from any citizen and read every SMS alert in the state. Per-device means a
-- compromised handset compromises that handset.
--
-- WHY SYMMETRIC, AND NOT PUBLIC-KEY
--
-- Two reasons, and the second is the binding one:
--
--   * It authenticates as well as conceals. The AES-GCM tag proves the message
--     came from that device. The `smsWebhook` this replaces accepted anything
--     that reached it, so anyone who knew the number could inject an emergency.
--   * It is 32 bytes smaller on the wire than carrying an ephemeral public
--     key, and those 32 bytes are what keep the message inside ONE segment.
--     A second segment is a second charge on every alert.
--
-- The cost is honest and worth writing down: HQ holds material that can both
-- decrypt and forge these messages. That is not a new exposure — HQ already
-- holds every alert in plaintext — but it does mean this table is as sensitive
-- as `emergency_pins`, and it is protected the same way.
--
-- THE KEY IS NEVER READABLE THROUGH THE API
--
-- Not by the API roles, not by the device's own owner, not once. It is
-- returned exactly once, by the SECURITY DEFINER function that creates it, and
-- after that the only thing that can read it is the service role during SMS
-- ingest. A device that loses its key registers again.
--
-- Idempotent: safe to re-run.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.sms_device_keys (
  -- HQ's four-byte handle for this key, sent in the clear in the message so
  -- ingest knows which key to try. Four bytes is 4.3 billion; collisions are
  -- handled by retrying on the unique constraint at registration.
  device_ref   BYTEA PRIMARY KEY,
  user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  -- 32 bytes. Never selected by anything but the service role.
  secret       BYTEA NOT NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_used_at TIMESTAMPTZ,
  -- Set rather than deleted, so an alert already in flight over a slow SMS
  -- queue can still be attributed after the device is retired.
  revoked_at   TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS sms_device_keys_user_idx
  ON public.sms_device_keys (user_id) WHERE revoked_at IS NULL;

ALTER TABLE public.sms_device_keys ENABLE ROW LEVEL SECURITY;

-- No policies at all, deliberately. With RLS enabled and nothing granted, the
-- API roles cannot read, write or even count this table. Everything legitimate
-- goes through the functions below.
REVOKE ALL ON TABLE public.sms_device_keys FROM PUBLIC, anon, authenticated;

-- ── Registration ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.register_sms_device()
RETURNS TABLE (device_ref BYTEA, secret BYTEA)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp, extensions
AS $$
DECLARE
  uid      UUID := auth.uid();
  new_ref  BYTEA;
  new_key  BYTEA;
  attempts INT := 0;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not signed in';
  END IF;

  -- One live key per user at a time. Registering again retires the old one
  -- rather than accumulating keys a stolen handset could keep using.
  UPDATE public.sms_device_keys
     SET revoked_at = NOW()
   WHERE user_id = uid AND revoked_at IS NULL;

  LOOP
    attempts := attempts + 1;
    new_ref := gen_random_bytes(4);
    EXIT WHEN NOT EXISTS (
      SELECT 1 FROM public.sms_device_keys k WHERE k.device_ref = new_ref
    );
    IF attempts > 8 THEN
      RAISE EXCEPTION 'could not allocate a device reference';
    END IF;
  END LOOP;

  new_key := gen_random_bytes(32);

  INSERT INTO public.sms_device_keys (device_ref, user_id, secret)
  VALUES (new_ref, uid, new_key);

  -- Returned ONCE. There is no function that reads it back.
  RETURN QUERY SELECT new_ref, new_key;
END;
$$;

COMMENT ON FUNCTION public.register_sms_device() IS
  'Issues a per-device key for the encrypted SMS fallback. Returns it once; '
  'nothing can read it back. Retires any previous key for the same user.';

-- ── Does this device still have a live key? ─────────────────────────────────
--
-- So the app can tell "never registered" from "registered and still valid"
-- without ever asking for the key itself.

CREATE OR REPLACE FUNCTION public.has_sms_device_key(p_ref BYTEA)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.sms_device_keys k
     WHERE k.device_ref = p_ref
       AND k.user_id = auth.uid()
       AND k.revoked_at IS NULL
  );
$$;

-- ── Retiring a key ──────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.revoke_sms_device_keys()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  n INT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not signed in';
  END IF;
  UPDATE public.sms_device_keys
     SET revoked_at = NOW()
   WHERE user_id = auth.uid() AND revoked_at IS NULL;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$$;

COMMENT ON FUNCTION public.revoke_sms_device_keys() IS
  'Retires this user''s SMS device keys. Called on sign-out and on uninstall.';

-- ── Ingest ──────────────────────────────────────────────────────────────────
--
-- Service role only. This is the one thing in the system that may read a
-- secret, and it exists so the SMS inbound endpoint can look a key up by the
-- four bytes the message carried in the clear.

CREATE OR REPLACE FUNCTION public.sms_key_for_ingest(p_ref BYTEA)
RETURNS TABLE (user_id UUID, secret BYTEA)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN QUERY
  UPDATE public.sms_device_keys k
     SET last_used_at = NOW()
   WHERE k.device_ref = p_ref
     AND k.revoked_at IS NULL
  RETURNING k.user_id, k.secret;
END;
$$;

COMMENT ON FUNCTION public.sms_key_for_ingest(BYTEA) IS
  'Service role only. Looks up a device key during SMS ingest and stamps its '
  'last use. Never reachable from a phone or a browser.';

-- ── Grants ──────────────────────────────────────────────────────────────────

REVOKE ALL ON FUNCTION public.register_sms_device()        FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.has_sms_device_key(BYTEA)    FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.revoke_sms_device_keys()     FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.sms_key_for_ingest(BYTEA)
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.register_sms_device()     TO authenticated;
GRANT EXECUTE ON FUNCTION public.has_sms_device_key(BYTEA) TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_sms_device_keys()  TO authenticated;
GRANT EXECUTE ON FUNCTION public.sms_key_for_ingest(BYTEA) TO service_role;

-- ── Where an SMS-borne alert says it came from ──────────────────────────────
--
-- A dispatcher must be able to see that this alert arrived over a degraded
-- channel. Not because the content is untrusted — it is authenticated — but
-- because a phone that could not reach the network is itself operationally
-- significant, and because an SMS can sit in a carrier queue for minutes.

ALTER TABLE public.alerts
  ADD COLUMN IF NOT EXISTS arrived_via TEXT;

COMMENT ON COLUMN public.alerts.arrived_via IS
  'NULL for the ordinary path. ''SMS'' when the report reached us over the '
  'encrypted SMS fallback, meaning the reporter had no data connection.';

-- ----------------------------------------------------------------------------
-- 20261001000000_mesh_ingest.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261001000000_mesh_ingest.sql'; END $apply$;

-- ============================================================================
-- OPERATION RAINBOW — RECOGNISING THE SAME MESH ENVELOPE TWICE
--
-- The mesh floods. That is not a flaw in it; it is how a report crosses a crowd
-- when there is no tower. Every phone that takes an envelope on offers it to
-- every phone it then meets, so the same emergency reaches HQ by several paths,
-- from several relays, minutes apart. Without a memory, one kidnapping becomes
-- six incidents and six units are dispatched to one place while the next call
-- waits.
--
-- WHY THE ENVELOPE ID AND NOT THE CONTENTS
--
-- Because this check happens BEFORE decryption and must. The envelope id is 128
-- random bits chosen by the originating handset and is the only thing a relay
-- can see, so it is also the only thing HQ can use to drop a duplicate without
-- first spending an ECDH and an AES-GCM open on it. On an unauthenticated write
-- path that ordering is the difference between a flood costing us a table lookup
-- and a flood costing us a key agreement per frame.
--
-- The second dedup key — `alerts.local_id`, from inside the ciphertext — still
-- does the other half of the job: it catches the same incident arriving by SMS,
-- by mesh, and again from the reporter's own offline queue when their phone
-- recovers. Three channels, one incident. Neither check replaces the other.
--
-- WHY THE COUNT IS KEPT
--
-- `arrivals` is the only measure of mesh health that exists. Nothing else can
-- tell us whether relaying is actually working in the field: handsets cannot
-- report on each other without identifying who carried what, which is the thing
-- the design forbids. How many times one envelope reached HQ, by how many
-- distinct uploads, is an aggregate that identifies nobody.
--
-- WHAT THIS TABLE MUST NOT BECOME
--
-- A log of who relayed what. There is no relay column, no IP, no uploader. An
-- envelope id is 128 random bits with no meaning, `first_seen_at` is coarse, and
-- rows are purged after 48 hours. If someone later adds "which relay uploaded
-- it" to make debugging easier, they will have built the surveillance tool this
-- whole channel was designed to avoid being.
--
-- Idempotent: safe to re-run.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.mesh_envelopes_seen (
  -- 16 random bytes chosen by the originating handset. Carries no meaning and
  -- is not linkable to a device: two alerts from the same phone share nothing.
  envelope_id   BYTEA PRIMARY KEY,
  first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_seen_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- How many times this envelope reached us. Mesh health, and nothing else.
  arrivals      INTEGER NOT NULL DEFAULT 1
);

CREATE INDEX IF NOT EXISTS mesh_envelopes_seen_first_idx
  ON public.mesh_envelopes_seen (first_seen_at);

ALTER TABLE public.mesh_envelopes_seen ENABLE ROW LEVEL SECURITY;

-- No policies at all, deliberately, exactly as with sms_device_keys. With RLS
-- enabled and nothing granted, the API roles cannot read, write or count this
-- table. The one thing that touches it is the function below, as service_role.
REVOKE ALL ON TABLE public.mesh_envelopes_seen FROM PUBLIC, anon, authenticated;

-- ── Note an arrival ─────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.mesh_note_envelope(p_id BYTEA)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  is_new BOOLEAN;
BEGIN
  IF p_id IS NULL OR octet_length(p_id) <> 16 THEN
    RAISE EXCEPTION 'an envelope id is 16 bytes';
  END IF;

  -- One statement, so two relays uploading the same envelope at the same instant
  -- cannot both be told they are first. A SELECT-then-INSERT here would be a
  -- race that shows up exactly when the mesh is busiest.
  INSERT INTO public.mesh_envelopes_seen AS m (envelope_id)
  VALUES (p_id)
  ON CONFLICT (envelope_id) DO UPDATE
     SET arrivals     = m.arrivals + 1,
         last_seen_at = NOW()
  -- arrivals is 1 only on the row this statement inserted; the conflict branch
  -- always increments it past 1.
  RETURNING (m.arrivals = 1) INTO is_new;

  RETURN COALESCE(is_new, TRUE);
END;
$$;

COMMENT ON FUNCTION public.mesh_note_envelope(BYTEA) IS
  'Service role only. Records that a mesh envelope arrived and returns TRUE the '
  'first time. Called before decryption, so a flood costs a lookup rather than '
  'a key agreement.';

-- ── Purge ───────────────────────────────────────────────────────────────────
--
-- 48 hours: twice the age at which any relay will still carry an envelope
-- (`meshMaxAge` is 24h), so a frame cannot outlive our memory of it and become
-- new again. Rows kept longer would be a record of mesh traffic with no purpose.

CREATE OR REPLACE FUNCTION public.purge_stale_mesh_envelopes()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  n INT;
BEGIN
  DELETE FROM public.mesh_envelopes_seen
   WHERE first_seen_at < NOW() - INTERVAL '48 hours';
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$$;

COMMENT ON FUNCTION public.purge_stale_mesh_envelopes() IS
  'Deletes envelope ids older than 48 hours — twice the longest a relay will '
  'carry one, so nothing can outlive our memory of it.';

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('purge-stale-mesh-envelopes')
      WHERE EXISTS (
        SELECT 1 FROM cron.job WHERE jobname = 'purge-stale-mesh-envelopes'
      );
    PERFORM cron.schedule(
      'purge-stale-mesh-envelopes', '17 * * * *',
      'SELECT public.purge_stale_mesh_envelopes();'
    );
  ELSE
    -- Said out loud rather than assumed. A retention policy that depends on an
    -- extension nobody enabled is not a retention policy.
    RAISE NOTICE 'pg_cron is not installed: run purge_stale_mesh_envelopes() from a scheduled job.';
  END IF;
END
$$;

-- ── Grants ──────────────────────────────────────────────────────────────────

REVOKE ALL ON FUNCTION public.mesh_note_envelope(BYTEA)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.purge_stale_mesh_envelopes()
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.mesh_note_envelope(BYTEA)      TO service_role;
GRANT EXECUTE ON FUNCTION public.purge_stale_mesh_envelopes()   TO service_role;

-- ── Where an offline alert says it came from ─────────────────────────────────
--
-- 'MESH' joins 'SMS'. Both mean the reporter could not reach the network, and a
-- dispatcher needs to know that: the handset cannot be called back through the
-- app, nothing further is coming from it, and in the mesh case the position may
-- be some minutes old because it crossed a crowd to get here.

COMMENT ON COLUMN public.alerts.arrived_via IS
  'NULL for the ordinary path. ''SMS'' when the report reached us over the '
  'encrypted SMS fallback. ''MESH'' when it was relayed through nearby phones '
  'to one that had a network. Either way the reporter had no data connection.';

-- ----------------------------------------------------------------------------
-- 20261002000000_sim_channel_events.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261002000000_sim_channel_events.sql'; END $apply$;

-- ============================================================================
-- OPERATION RAINBOW — WHEN A HANDSET'S SMS CHANNEL DIES
--
-- WHAT THIS IS ABOUT
--
-- In this system the phone number is the identity. It is what the account was
-- created with, what `profiles.phone` holds, what HQ rings back, and what the
-- encrypted SMS fallback rides on. When the SIM leaves a handset:
--
--   * the offline alert channel stops working and nothing else notices;
--   * a sign-in or re-entry code cannot arrive, so the holder will be locked
--     out the next time they come back to the app;
--   * a stolen handset usually gets a new SIM within the hour.
--
-- So HQ is told. What HQ is told is that A CHANNEL IS DOWN.
--
-- WHAT THIS IS DELIBERATELY NOT
--
-- It is not a movement log and must never become one. There is no location
-- column here and none may be added: this app is used in a conflict zone by
-- people who report things they can be harmed for reporting, and a government
-- console that quietly accumulated their SIM and location history would be a
-- reason not to install it — which costs more lives than it saves.
--
-- The holder is told on the handset, in one line, each time a row is written
-- here. Reporting to a state console without telling the person is
-- surveillance; reporting it and saying so is operations.
--
-- WHAT IT CAN AND CANNOT SEE
--
-- Android reports SIM present/absent and the NETWORK (MCC+MNC) with no
-- permission at all. The values that identify a particular CARD — the ICCID
-- and the IMSI — have required READ_PRIVILEGED_PHONE_STATE since Android 10,
-- which no ordinary app can hold. So one MTN SIM swapped for another MTN SIM
-- is invisible. On iOS 16+ nothing is visible at all: the carrier API is
-- deprecated and returns a placeholder. Both limits are stated in
-- lib/core/device/sim_fingerprint.dart and asserted in its tests.
--
-- Idempotent: safe to re-run.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.sim_channel_events (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,

  -- REMOVED, INSERTED, REPLACED. Never a free-text description from the
  -- handset: the words HQ reads are composed by the console from this code, so
  -- a compromised handset cannot write prose onto an operator's screen.
  change        TEXT NOT NULL CHECK (change IN ('REMOVED', 'INSERTED', 'REPLACED')),

  -- The NETWORK the handset is on now, for an operator deciding whether the
  -- registered number still reaches this person. Null when it could not be
  -- read. Not the card, not the number.
  operator_name TEXT,
  operator_code TEXT,

  -- When the handset noticed. Set by the handset, so it survives a report that
  -- is queued while offline and delivered later.
  noticed_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Cleared by an operator who has dealt with it.
  acknowledged_at TIMESTAMPTZ,
  acknowledged_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS sim_channel_events_open_idx
  ON public.sim_channel_events (created_at DESC)
  WHERE acknowledged_at IS NULL;

CREATE INDEX IF NOT EXISTS sim_channel_events_user_idx
  ON public.sim_channel_events (user_id, created_at DESC);

COMMENT ON TABLE public.sim_channel_events IS
  'A handset reporting that its SMS channel changed: SIM removed, inserted or '
  'replaced. About the channel, never about a location. The holder is told on '
  'the handset each time a row is written.';

-- ── Row level security ──────────────────────────────────────────────────────

ALTER TABLE public.sim_channel_events ENABLE ROW LEVEL SECURITY;

-- A handset writes its OWN events and nobody else's. `user_id = auth.uid()` is
-- the whole check: without it, any signed-in account could manufacture a "SIM
-- REMOVED" for any other person, which is a cheap way to get somebody's
-- account looked at by the state.
DROP POLICY IF EXISTS "sim_events_insert_self" ON public.sim_channel_events;
CREATE POLICY "sim_events_insert_self" ON public.sim_channel_events
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

-- The holder can see what was reported about their own handset. Somebody who
-- cannot see what was said about them cannot challenge it.
DROP POLICY IF EXISTS "sim_events_select_self_or_command" ON public.sim_channel_events;
CREATE POLICY "sim_events_select_self_or_command" ON public.sim_channel_events
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_command());

-- Only command acknowledges, and only the acknowledgement fields move —
-- nothing here may be rewritten after the fact.
DROP POLICY IF EXISTS "sim_events_ack_command" ON public.sim_channel_events;
CREATE POLICY "sim_events_ack_command" ON public.sim_channel_events
  FOR UPDATE TO authenticated
  USING (public.is_command())
  WITH CHECK (public.is_command());

-- NOT `is_staff()`. A polling-unit officer in Wase, and every agency liaison,
-- are staff; neither has a reason to see which citizens changed SIM. This is
-- the same mistake the telemetry migration was written to undo.

-- ── Retention ───────────────────────────────────────────────────────────────
--
-- These rows answer "is this handset reachable by SMS today". A year-old one
-- answers nothing and is only a history of somebody's phone. Ninety days, and
-- acknowledged ones go sooner.

CREATE OR REPLACE FUNCTION public.purge_stale_sim_events()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  DELETE FROM public.sim_channel_events
   WHERE created_at < NOW() - INTERVAL '90 days'
      OR (acknowledged_at IS NOT NULL
          AND acknowledged_at < NOW() - INTERVAL '30 days');
$$;

REVOKE EXECUTE ON FUNCTION public.purge_stale_sim_events() FROM anon;
REVOKE EXECUTE ON FUNCTION public.purge_stale_sim_events() FROM authenticated;

DO $cron$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('purge-stale-sim-events')
      WHERE EXISTS (
        SELECT 1 FROM cron.job WHERE jobname = 'purge-stale-sim-events'
      );
    PERFORM cron.schedule(
      'purge-stale-sim-events',
      '30 3 * * *',
      $job$SELECT public.purge_stale_sim_events();$job$
    );
  ELSE
    RAISE NOTICE
      'pg_cron is not installed; run public.purge_stale_sim_events() on a schedule yourself';
  END IF;
END $cron$;

-- ── Realtime ────────────────────────────────────────────────────────────────
--
-- The console badges this live. A subscription to a table outside the
-- publication does not error; it simply never fires, which is how the agency
-- portal's badge came to refresh only on reload.

DO $realtime$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    RAISE NOTICE 'no supabase_realtime publication in this database; nothing to do';
    RETURN;
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_publication_tables
     WHERE pubname = 'supabase_realtime'
       AND schemaname = 'public'
       AND tablename = 'sim_channel_events'
  ) THEN
    RETURN;
  END IF;
  ALTER PUBLICATION supabase_realtime ADD TABLE public.sim_channel_events;
END $realtime$;

-- ----------------------------------------------------------------------------
-- 20261003000000_liaisons_are_not_staff.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261003000000_liaisons_are_not_staff.sql'; END $apply$;

-- ============================================================================
-- OPERATION RAINBOW — AN AGENCY LIAISON IS NOT OPERATION RAINBOW STAFF
--
-- THE HOLE
--
-- Six agencies send liaison officers to this console: the Police, the Army,
-- the DSS, the NSCDC, the FRSC and Operation Enduring Peace. They are officers
-- of OTHER organisations, given an account so that an incident handed to their
-- agency reaches them. (Operation Enduring Peace was called Operation Safe
-- Haven when this was written; the code stays OPSH, which is what the role
-- name and `escalated_to_agency` store.)
--
-- `is_staff()` is:
--
--     (SELECT role FROM profiles WHERE id = auth.uid()) NOT IN ('CITIZEN', 'USER')
--
-- A `POLICE_LIAISON` is therefore staff. And the alerts policies are:
--
--     alerts_select_own_or_staff   USING (... OR is_staff())
--     alerts_update_own_or_staff   USING (... OR is_staff())
--
-- So every liaison could READ every incident in Plateau State, and WRITE to
-- every incident in Plateau State: resolve one in an LGA their agency was
-- never called to, reassign it, change its severity, clear a duress alarm.
-- Nothing scoped any of it to the agency, and nothing recorded that an outside
-- officer had done it.
--
-- The same sentence applies to `telemetry`: a liaison could read the live
-- position of every Operation Rainbow officer on duty in the state, and of
-- every citizen with an open emergency — including emergencies their agency
-- has no part in.
--
-- This was not a decision anyone made. `is_staff()` was written to mean "not a
-- member of the public", and the agency roles arrived later and fell inside
-- it.
--
-- WHAT THIS DOES
--
-- Scopes a liaison to their own agency's work:
--
--   * incidents escalated to their agency, or assigned to them personally;
--   * the positions of people tied to one of those incidents;
--   * the chat on one of those incidents.
--
-- And nothing else. Their own agency tables are unchanged — those were already
-- scoped by `liaison_agency()`, which is where this migration takes its lead.
--
-- WHAT IT DELIBERATELY DOES NOT DO
--
-- It does not narrow anything for Operation Rainbow's own staff. A polling-unit
-- officer still sees what they saw; this is about accounts belonging to another
-- organisation.
--
-- It does not remove a liaison's ability to ACT on an incident handed to them.
-- Handing an incident to an agency and then refusing them the ability to
-- update it would make the handover ceremonial.
--
-- Idempotent: safe to re-run.
-- ============================================================================

-- ── Is this account an outside agency's? ────────────────────────────────────

CREATE OR REPLACE FUNCTION public.is_liaison()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT role FROM public.profiles WHERE id = auth.uid()) LIKE '%\_LIAISON',
    false
  );
$$;

REVOKE EXECUTE ON FUNCTION public.is_liaison() FROM anon;

COMMENT ON FUNCTION public.is_liaison() IS
  'True for an officer of an outside agency (POLICE_LIAISON, ARMY_LIAISON, …). '
  'They are staff by is_staff(), which is why every alerts policy has to ask '
  'this as well.';

-- ── Which incidents belong to an outside agency ─────────────────────────────

CREATE OR REPLACE FUNCTION public.alert_is_ours(p_alert public.alerts)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
  SELECT
    -- Operation Rainbow's own staff: unchanged.
    (public.is_staff() AND NOT public.is_liaison())
    -- The reporter and the assignee, whoever they are.
    OR p_alert.reported_by = auth.uid()
    OR p_alert.assigned_to = auth.uid()
    -- An outside agency: only what was handed to them.
    OR (public.is_liaison()
        AND upper(COALESCE(p_alert.escalated_to_agency, '')) = public.liaison_agency());
$$;

COMMENT ON FUNCTION public.alert_is_ours(public.alerts) IS
  'Whether the calling account has a part in this incident. The whole point is '
  'the last clause: an agency liaison sees what was escalated to their agency, '
  'not the state.';

-- ── Alerts ──────────────────────────────────────────────────────────────────
--
-- REPLACED, not added. PostgreSQL ORs permissive policies together, so adding
-- a narrow one beside `... OR is_staff()` would change nothing at all.

DROP POLICY IF EXISTS "alerts_select_own_or_staff" ON public.alerts;
DROP POLICY IF EXISTS "alerts_select_own_or_ours" ON public.alerts;
CREATE POLICY "alerts_select_own_or_ours" ON public.alerts
  FOR SELECT TO authenticated
  USING (public.alert_is_ours(alerts));

DROP POLICY IF EXISTS "alerts_update_own_or_staff" ON public.alerts;
DROP POLICY IF EXISTS "alerts_update_own_or_ours" ON public.alerts;
CREATE POLICY "alerts_update_own_or_ours" ON public.alerts
  FOR UPDATE TO authenticated
  USING (public.alert_is_ours(alerts));

-- INSERT is left alone. A liaison filing an incident is filing it as
-- themselves, which `reported_by = auth.uid()` already covers.

-- ── Telemetry ───────────────────────────────────────────────────────────────
--
-- The live position of an Operation Rainbow officer is operational information
-- among colleagues. It is not information an outside agency is owed, except
-- for people working an incident that agency has been handed.

DROP POLICY IF EXISTS "telemetry_select_self_or_responding_staff" ON public.telemetry;
DROP POLICY IF EXISTS "telemetry_select_self_or_staff" ON public.telemetry;
DROP POLICY IF EXISTS "telemetry_select_scoped" ON public.telemetry;
CREATE POLICY "telemetry_select_scoped" ON public.telemetry
  FOR SELECT TO authenticated
  USING (
    -- Your own position, always.
    user_id = auth.uid()

    -- Operation Rainbow's own staff, exactly as before this migration: another
    -- STAFF member's position freely, and a CITIZEN's only while they have an
    -- emergency open.
    OR (public.is_staff() AND NOT public.is_liaison() AND (
          EXISTS (SELECT 1 FROM public.profiles p
                   WHERE p.id = telemetry.user_id
                     AND p.role NOT IN ('CITIZEN', 'USER'))
          OR EXISTS (SELECT 1 FROM public.alerts a
                      WHERE a.reported_by = telemetry.user_id
                        AND a.status NOT IN ('RESOLVED', 'CANCELLED'))
       ))

    -- An outside agency: only people tied to an incident handed to them.
    OR (public.is_liaison() AND EXISTS (
          SELECT 1 FROM public.alerts a
           WHERE upper(COALESCE(a.escalated_to_agency, '')) = public.liaison_agency()
             AND a.status NOT IN ('RESOLVED', 'CANCELLED')
             AND (a.reported_by = telemetry.user_id
                  OR a.assigned_to = telemetry.user_id)
       ))
  );

-- ── Chat ────────────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "chat_select_participant_or_staff" ON public.chat_messages;
DROP POLICY IF EXISTS "chat_select_participant_or_ours" ON public.chat_messages;
CREATE POLICY "chat_select_participant_or_ours" ON public.chat_messages
  FOR SELECT TO authenticated
  USING (
    sender_id = auth.uid()
    OR (public.is_staff() AND NOT public.is_liaison())
    OR EXISTS (
         SELECT 1 FROM public.alerts a
          WHERE a.id = chat_messages.alert_id
            AND public.alert_is_ours(a)
       )
  );

-- ── Say it out loud ─────────────────────────────────────────────────────────

COMMENT ON POLICY "alerts_select_own_or_ours" ON public.alerts IS
  'Replaces alerts_select_own_or_staff, under which every agency liaison could '
  'read every incident in the state because is_staff() means "not a citizen".';

COMMENT ON POLICY "alerts_update_own_or_ours" ON public.alerts IS
  'Replaces alerts_update_own_or_staff, under which an officer of another '
  'organisation could resolve or reassign any incident in Plateau.';

-- ----------------------------------------------------------------------------
-- 20261004000000_incident_tracks.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261004000000_incident_tracks.sql'; END $apply$;

-- ============================================================================
-- OPERATION RAINBOW — WHERE SOMEBODY WENT DURING ONE EMERGENCY
--
-- THE GAP
--
-- An SOS starts a track. `background_tracking_service.dart` reports a position
-- every few seconds, the console draws a trail, and an operator watching at the
-- time can follow the person.
--
-- Except nothing was kept. `telemetry` has `user_id` as its PRIMARY KEY and is
-- UPSERTED, so the database holds exactly one row per person: the CURRENT
-- position, overwritten each time. The trail existed only in the browser tab's
-- memory — `agentPathsRef`, capped at thirty points — so:
--
--   * refreshing the console lost the trail;
--   * a second operator opening the console mid-incident saw a dot, not a path;
--   * anybody reviewing the incident afterwards saw no movement at all, and
--     the incident replay panel replayed the alert and the chat with no
--     positions in it.
--
-- For a kidnapping — the case this system exists for — "which way did they go"
-- is the question, and the answer was being thrown away several times a minute.
--
-- HOW THIS DOES NOT UNDO 20260929000000
--
-- That migration's thesis is that location is BORROWED, NOT KEPT, and it is
-- right. What it removed was a standing feed: one row per person, no link to
-- any incident, readable by every staff account in the state, kept forever,
-- still being written after the emergency ended.
--
-- This table is the opposite of each of those:
--
--   * every row belongs to ONE incident (`alert_id` is NOT NULL). No incident,
--     no track — an officer on ordinary patrol writes nothing here.
--   * it stops when the incident does, because the app stops reporting.
--   * it is readable only by people with a part in THAT incident, through the
--     same `alert_is_ours()` the alerts policies use — so an agency liaison
--     sees the route on an incident handed to their agency and on no other.
--   * it expires. A track is deleted seven days after its incident closes.
--
-- SEVEN DAYS, AND WHY THAT NUMBER
--
-- Long enough for the after-action review that is the point of keeping it at
-- all — reviews happen days later, not hours. Short enough that this never
-- becomes a location history: at any moment the table holds the open
-- incidents and one week of closed ones, and nothing else. If somebody wants
-- longer, that is a decision to argue for explicitly, which is why it is one
-- named interval and not a scatter of conditions.
--
-- Idempotent: safe to re-run.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.incident_tracks (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  alert_id    UUID NOT NULL REFERENCES public.alerts(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  latitude    DOUBLE PRECISION NOT NULL,
  longitude   DOUBLE PRECISION NOT NULL,
  accuracy    DOUBLE PRECISION,
  speed       DOUBLE PRECISION,
  -- The handset's clock, so a point queued offline and delivered later sits in
  -- the right place on the route rather than at the moment it arrived.
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Drawing one incident's route is the only read this table has.
CREATE INDEX IF NOT EXISTS incident_tracks_route_idx
  ON public.incident_tracks (alert_id, recorded_at);

COMMENT ON TABLE public.incident_tracks IS
  'The route a person took during ONE incident. Written only while that '
  'incident is open, readable only by people with a part in it, deleted seven '
  'days after it closes. Not a standing location feed — see '
  '20260929000000_telemetry_is_not_a_standing_feed.sql.';

-- ── Row level security ──────────────────────────────────────────────────────

ALTER TABLE public.incident_tracks ENABLE ROW LEVEL SECURITY;

-- A handset writes its OWN points, for an OPEN incident it has a part in.
--
-- All three clauses matter. Without `user_id = auth.uid()` anyone could write a
-- route for anybody. Without the incident check they could attach it to any
-- incident in the state. Without the open check a closed incident could be
-- re-written days later, which is the difference between a record and a story.
DROP POLICY IF EXISTS "incident_tracks_insert_own_open" ON public.incident_tracks;
CREATE POLICY "incident_tracks_insert_own_open" ON public.incident_tracks
  FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.alerts a
       WHERE a.id = incident_tracks.alert_id
         AND a.status NOT IN ('RESOLVED', 'CANCELLED')
         AND (a.reported_by = auth.uid() OR a.assigned_to = auth.uid())
    )
  );

-- Read follows the incident, through the same function the alerts policies
-- use. So: command sees it, the person whose route it is sees it, the assignee
-- sees it, and an agency liaison sees it only on an incident escalated to
-- their agency.
DROP POLICY IF EXISTS "incident_tracks_select_with_incident" ON public.incident_tracks;
CREATE POLICY "incident_tracks_select_with_incident" ON public.incident_tracks
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.alerts a
       WHERE a.id = incident_tracks.alert_id
         AND public.alert_is_ours(a)
    )
  );

-- No UPDATE and no DELETE for anybody signed in. A route is a record of what
-- happened; an editable one is worth less than none, because it can be made to
-- say something else. Deletion is the retention job's alone.

-- ── Retention ───────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.purge_stale_incident_tracks()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  removed INTEGER;
BEGIN
  -- Seven days after the incident closed. An OPEN incident is never purged on
  -- age, however old — an unresolved emergency is exactly the case where the
  -- route still matters.
  DELETE FROM public.incident_tracks t
   USING public.alerts a
   WHERE a.id = t.alert_id
     AND a.status IN ('RESOLVED', 'CANCELLED')
     AND COALESCE(a.updated_at, a.created_at) < NOW() - INTERVAL '7 days';
  GET DIAGNOSTICS removed = ROW_COUNT;

  -- And a point whose incident has vanished entirely. The foreign key cascades
  -- on delete, so this only catches anything that slipped in before it.
  DELETE FROM public.incident_tracks t
   WHERE NOT EXISTS (SELECT 1 FROM public.alerts a WHERE a.id = t.alert_id);

  RETURN removed;
END;
$$;

COMMENT ON FUNCTION public.purge_stale_incident_tracks() IS
  'Deletes the routes of incidents that closed more than seven days ago.';

REVOKE ALL ON FUNCTION public.purge_stale_incident_tracks() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.purge_stale_incident_tracks() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.purge_stale_incident_tracks() TO service_role;

DO $cron$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('purge-stale-incident-tracks')
      WHERE EXISTS (
        SELECT 1 FROM cron.job WHERE jobname = 'purge-stale-incident-tracks'
      );
    PERFORM cron.schedule(
      'purge-stale-incident-tracks',
      '45 3 * * *',
      $job$SELECT public.purge_stale_incident_tracks();$job$
    );
  ELSE
    RAISE NOTICE
      'pg_cron is not installed; run public.purge_stale_incident_tracks() on a schedule yourself';
  END IF;
END $cron$;

-- ----------------------------------------------------------------------------
-- 20261005000000_alert_category.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261005000000_alert_category.sql'; END $apply$;

-- A column the console can sort and filter incidents by.
--
-- ## The problem
--
-- The category a citizen picked was never stored as a category. The app writes
-- `alerts.type` as `'<label> - <subtype>'` — `'Kidnap - Immediate Abduction'`,
-- `'Community attack - Armed Invasion'` — so the ten categories the reporting
-- flow offers exist only as a prefix inside a free-text column. A dispatcher
-- who wants "every kidnapping open right now" has nothing to ask for.
--
-- Filtering that prefix in the browser is not the same thing. The console reads
-- a bounded window of alerts, so a client-side filter searches only what was
-- already loaded and quietly answers from a subset. The question has to be
-- answerable by the database.
--
-- ## Why GENERATED, and not a column the app writes
--
-- The category is not independent information — it is the first field of
-- `type`, and always has been. A writable column would be a second copy of a
-- fact already recorded, and the two would drift: rows written by the SMS
-- bridge, the mesh path and the offline queue all build `type` themselves, and
-- every one of them would have to remember. A row where `type` says Kidnap and
-- `category` says Flood is worse than no column at all.
--
-- A stored generated column cannot drift. It also backfills every historical
-- row as part of this statement, so the existing incidents become sortable
-- without a data migration.
--
-- `split_part` returns the whole string when the separator is absent, which is
-- the wanted behaviour for the types that have no subtype: a panic press is
-- stored as `'PANIC SOS'` and becomes the category `PANIC SOS`, which is
-- exactly how a dispatcher thinks of it.

ALTER TABLE public.alerts
  ADD COLUMN IF NOT EXISTS category TEXT
  GENERATED ALWAYS AS (split_part(type, ' - ', 1)) STORED;

COMMENT ON COLUMN public.alerts.category IS
  'The reporting category, derived from type (the part before " - "). '
  'Generated, never written: type is the single source of truth.';

-- The console asks two questions of this: "what categories are there" for the
-- filter control, and "give me this category" once one is chosen. Both are
-- scoped to open incidents far more often than not.
CREATE INDEX IF NOT EXISTS alerts_category_idx
  ON public.alerts (category);

CREATE INDEX IF NOT EXISTS alerts_category_created_idx
  ON public.alerts (category, created_at DESC);

-- No RLS change. A generated column is part of the row and is covered by the
-- policies already on this table; adding one here would only widen what the
-- existing ones decided.

-- ----------------------------------------------------------------------------
-- 20261006000000_alerts_scoped_to_posting.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261006000000_alerts_scoped_to_posting.sql'; END $apply$;

-- An officer's authority ends at their command.
--
-- ## What was wrong
--
-- The command chain had real structure for ROUTING — `assigned_tier`, the
-- escalation ladder, the per-tier timeout job — and none at all for AUTHORITY.
-- Every tier rule lived in a Dart function in the app (`canDispatchFrom`) or a
-- dropdown in the console. The database's rule was `alert_is_ours()`, whose
-- staff clause read:
--
--     public.is_staff() AND NOT public.is_liaison()
--
-- and `is_staff()` means only "role is not CITIZEN". So every Operation
-- Rainbow account, at any tier, in any LGA, could SELECT every incident in
-- Plateau State — and the identical predicate guards UPDATE, so they could
-- resolve one, reassign it, re-grade it, or clear a duress alarm 80km outside
-- their command.
--
-- The geography the product is built around existed only in the console's
-- filter dropdowns and the responder app's client-side list filter. Both narrow
-- what is SHOWN. Neither narrows what is PERMITTED, and anyone calling
-- PostgREST with their own token got the state.
--
-- This is the same defect as the agency liaisons one migration ago, one layer
-- in: `is_staff()` was written to mean "not a member of the public", and every
-- role that arrived later fell inside it.
--
-- ## The rule
--
--   HQ_COMMAND / HQ_OFFICER / ADMIN  the whole state
--   LGA_*                            their LGA
--   WARD_*                           their ward, within their LGA
--   UNIT_* / POLLING_*               their polling unit
--   RESPONDER / AGENT                their LGA — a field unit needs to see the
--                                    ground around it, not one polling unit
--
-- plus, for everyone, the incidents they reported, are assigned to, or are on
-- the team for; and for a liaison, what was escalated to their agency.
--
-- ## Four decisions that are not obvious, and are the whole safety of this
--
-- **An incident with no location stays visible to all staff.** Scoping by
-- geography means a row whose `geo_lga` is NULL matches nobody's area — so the
-- strict reading would hide it from everyone but HQ. Those rows are real: the
-- console already reports an "UNLOCATED" count for SOS reports that reached us
-- without a GPS fix. An emergency nobody can see is a worse outcome than one
-- seen too widely, so these fail OPEN, deliberately.
--
-- **The whole dispatched team is matched, not just the lead.** `dispatchAlert`
-- writes `assigned_to` (the lead) AND `assigned_responders` (the team), and the
-- responder app lists an officer's work by the array. The old policy only ever
-- mentioned `assigned_to`, which did not matter while every staff account could
-- see everything. The moment area scoping arrives it matters enormously: every
-- non-lead officer dispatched outside their own area would have lost the
-- incident they were sent to. `assigned_responders` is TEXT[], so the uid is
-- compared as text.
--
-- **An officer with no posting is narrowed, never widened.** A staff account
-- with a NULL `geo_lga` matches no area and keeps only what it reported, is
-- assigned to, or is on the team for. `profiles.geo_lga` is self-writable —
-- only `role` is guarded by the privilege-escalation trigger — so if an empty
-- posting meant "everywhere", a ward commander could clear their own LGA and
-- take the state. Blank must be the weakest posting, not the strongest.
--
-- **A delegated incident reaches the team it was delegated to.** HQ handing an
-- incident down to an LGA sets `assigned_tier = 'LGA'` and deliberately does
-- NOT rewrite `geo_lga`, because the incident's location is a fact about the
-- incident. So for an LGA other than the one it was reported in, area matching
-- alone would show it to the named commander (via `assigned_to`) and to nobody
-- else on their team — the delegation would arrive at one person's screen. The
-- last `escalation_log` entry carries `to_lga`, and that is read here.

-- ── Who commands the whole state ────────────────────────────────────────────
--
-- Narrower than `is_command()`, which includes LGA_COMMAND — correct for
-- broadcasting, wrong for "sees everything".

CREATE OR REPLACE FUNCTION public.commands_whole_state()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT COALESCE(
    (SELECT upper(coalesce(role, '')) FROM public.profiles WHERE id = auth.uid())
      IN ('HQ_COMMAND', 'HQ_OFFICER', 'ADMIN'),
    false
  );
$$;

COMMENT ON FUNCTION public.commands_whole_state() IS
  'HQ and administrators. Narrower than is_command(), which includes LGA_COMMAND.';

-- ── Is this incident inside my command ──────────────────────────────────────

CREATE OR REPLACE FUNCTION public.alert_in_my_area(p_alert public.alerts)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
  WITH me AS (
    SELECT upper(coalesce(role, ''))                          AS role,
           nullif(upper(trim(coalesce(geo_lga,  ''))), '')    AS lga,
           nullif(upper(trim(coalesce(geo_ward, ''))), '')    AS ward,
           nullif(upper(trim(coalesce(geo_pu,   ''))), '')    AS pu
      FROM public.profiles
     WHERE id = auth.uid()
  ),
  it AS (
    SELECT nullif(upper(trim(coalesce(p_alert.geo_lga,  ''))), '') AS lga,
           nullif(upper(trim(coalesce(p_alert.geo_ward, ''))), '') AS ward,
           nullif(upper(trim(coalesce(p_alert.geo_pu,   ''))), '') AS pu
  )
  SELECT CASE
    -- Unlocated incidents fail OPEN. See the note above: an emergency nobody
    -- can see is worse than one seen too widely.
    WHEN (SELECT lga FROM it) IS NULL THEN true

    -- No posting: no area. Kept deliberately weak, because geo_lga is
    -- self-writable and blank must never mean "everywhere".
    WHEN (SELECT lga FROM me) IS NULL THEN false

    WHEN (SELECT role FROM me) LIKE 'WARD%' THEN
      (SELECT lga FROM it) = (SELECT lga FROM me)
      AND (SELECT ward FROM me) IS NOT NULL
      AND (SELECT ward FROM it) = (SELECT ward FROM me)

    WHEN (SELECT role FROM me) LIKE 'UNIT%'
      OR (SELECT role FROM me) LIKE 'POLLING%' THEN
      (SELECT lga FROM it) = (SELECT lga FROM me)
      AND (SELECT pu FROM me) IS NOT NULL
      AND (SELECT pu FROM it) = (SELECT pu FROM me)

    -- LGA command, and field responders: the LGA.
    ELSE (SELECT lga FROM it) = (SELECT lga FROM me)
  END;
$$;

COMMENT ON FUNCTION public.alert_in_my_area(public.alerts) IS
  'Whether this incident falls inside the calling account''s posting. '
  'An unlocated incident is visible to all staff; an unposted account has no area.';

-- ── Was it handed to my LGA ─────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.alert_delegated_to_my_lga(p_alert public.alerts)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT COALESCE(
    nullif(upper(trim(coalesce(
      (p_alert.escalation_log -> jsonb_array_length(p_alert.escalation_log) - 1)
        ->> 'to_lga', ''))), '')
    = (SELECT nullif(upper(trim(coalesce(geo_lga, ''))), '')
         FROM public.profiles WHERE id = auth.uid()),
    false
  );
$$;

COMMENT ON FUNCTION public.alert_delegated_to_my_lga(public.alerts) IS
  'HQ hands an incident down by setting assigned_tier and naming a target LGA, '
  'without rewriting geo_lga — the location is a fact about the incident. '
  'Without this the delegation would reach only the named commander.';

-- ── The predicate both policies use ─────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.alert_is_ours(p_alert public.alerts)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
  SELECT
    -- HQ and administrators: the state.
    public.commands_whole_state()
    -- The reporter, the lead, and every officer on the dispatched team.
    OR p_alert.reported_by = auth.uid()
    OR p_alert.assigned_to = auth.uid()
    OR auth.uid()::text = ANY (COALESCE(p_alert.assigned_responders, '{}'::text[]))
    -- Operation Rainbow staff, within their command.
    OR (public.is_staff() AND NOT public.is_liaison()
        AND (public.alert_in_my_area(p_alert)
             OR public.alert_delegated_to_my_lga(p_alert)))
    -- An outside agency: only what was handed to them.
    OR (public.is_liaison()
        AND upper(COALESCE(p_alert.escalated_to_agency, '')) = public.liaison_agency());
$$;

COMMENT ON FUNCTION public.alert_is_ours(public.alerts) IS
  'Whether the calling account has a part in this incident: HQ sees the state, '
  'everyone else sees their command plus their own work.';

-- The policies already call alert_is_ours() for SELECT and UPDATE
-- (20261003000000_liaisons_are_not_staff.sql); replacing the function is what
-- narrows them. Restated here so a replica built from these files in order gets
-- the same result whichever migration ran last.

DROP POLICY IF EXISTS "alerts_select_own_or_staff" ON public.alerts;
DROP POLICY IF EXISTS "alerts_select_own_or_ours" ON public.alerts;

-- And the separate LGA-scoping policy from
-- 20260725000000_v6_geo_lga_scoping_staging.sql.
--
-- That one ADDS a permissive policy granting FIELD_OFFICER, WARD_OFFICER and
-- LGA_OFFICER every alert in their LGA. PostgreSQL ORs permissive policies
-- together, so leaving it beside this one means a WARD_OFFICER keeps the whole
-- LGA and the ward scoping below never binds for them — the same trap this
-- file's header describes, arriving from the other direction.
--
-- Nothing is lost by dropping it: `alert_in_my_area()` covers all three of
-- those roles and covers them more precisely. WARD_OFFICER matches 'WARD%' and
-- gets their ward; LGA_OFFICER and FIELD_OFFICER fall through to the LGA rule
-- and get exactly what that policy gave them.
DROP POLICY IF EXISTS "alerts_select_geo_lga_scoped" ON public.alerts;

DROP POLICY IF EXISTS "alerts_select_own_or_ours" ON public.alerts;
CREATE POLICY "alerts_select_own_or_ours" ON public.alerts
  FOR SELECT TO authenticated
  USING (public.alert_is_ours(alerts));

DROP POLICY IF EXISTS "alerts_update_own_or_staff" ON public.alerts;
DROP POLICY IF EXISTS "alerts_update_own_or_ours" ON public.alerts;
CREATE POLICY "alerts_update_own_or_ours" ON public.alerts
  FOR UPDATE TO authenticated
  USING (public.alert_is_ours(alerts));

-- The area test reads these on every row it considers.
CREATE INDEX IF NOT EXISTS alerts_geo_idx
  ON public.alerts (geo_lga, geo_ward, geo_pu);

-- ----------------------------------------------------------------------------
-- 20261007000000_notification_outbox.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261007000000_notification_outbox.sql'; END $apply$;

-- The automatic escalation moved the incident and told nobody.
--
-- ## The gap
--
-- `escalate_overdue_alerts()` runs every minute under pg_cron and climbs any
-- unacknowledged incident one rung when its tier has held it too long. It is in
-- the right place — the app only runs when a citizen has it open and the
-- console only when a dispatcher does, so a timeout that must fire at 02:00
-- cannot live in either.
--
-- But it only ever UPDATED the row. Every notification in this system is sent
-- from `hq-dashboard-next/src/lib/alert-actions.ts`, which runs when a human
-- presses ESCALATE or DISPATCH. So an incident that climbed to the LGA at 02:00
-- because nobody at the ward answered was moved into another tier's queue in
-- complete silence, and was only seen if somebody happened to have the console
-- open. The whole point of the timeout is the case where nobody is watching.
--
-- ## Why an outbox, and not an HTTP call from the function
--
-- `pg_net` can post from inside PostgreSQL, and it is the wrong tool here. An
-- HTTP call made inside a transaction cannot be rolled back: if the escalation
-- is rolled back after the call, the notification has already gone, and if the
-- call fails there is nowhere for the failure to live. Delivery would be
-- invisible and unretryable.
--
-- A row is transactional. The escalation and its notification are written in
-- ONE statement, so it is not possible to escalate an incident without queueing
-- the notice — which is the property actually worth having. A worker then
-- drains the queue and calls the notification endpoints that already exist and
-- are already tested, and its failures are rows anyone can look at.

CREATE TABLE IF NOT EXISTS public.notification_outbox (
  id              BIGSERIAL PRIMARY KEY,
  alert_id        UUID REFERENCES public.alerts(id) ON DELETE CASCADE,
  kind            TEXT NOT NULL,
  payload         JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- Set when delivery succeeded. A delivered row is never claimed again.
  delivered_at    TIMESTAMPTZ,
  attempts        INTEGER NOT NULL DEFAULT 0,
  last_error      TEXT,
  -- When this row may next be attempted. Moved forward on failure so one
  -- unreachable recipient cannot spin the worker.
  next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.notification_outbox IS
  'Notifications owed. Written in the same transaction as the thing that owes '
  'them, so a change cannot happen without its notice being queued.';

-- The drain query: undelivered, due, oldest first.
CREATE INDEX IF NOT EXISTS notification_outbox_pending_idx
  ON public.notification_outbox (next_attempt_at)
  WHERE delivered_at IS NULL;

-- ── Nobody signed in from a phone may see this ──────────────────────────────
--
-- It names officers and incidents, and it is not operational information for
-- anyone in either app: it exists between the database and the worker.

ALTER TABLE public.notification_outbox ENABLE ROW LEVEL SECURITY;

-- No policy for `authenticated` at all. With RLS enabled and no policy, every
-- row is invisible and unwritable to them — the grants below are revoked too,
-- so this is belt and braces on purpose.
REVOKE ALL ON public.notification_outbox FROM anon, authenticated;
GRANT ALL ON public.notification_outbox TO service_role;
GRANT USAGE, SELECT ON SEQUENCE public.notification_outbox_id_seq TO service_role;

-- ── Claiming work ───────────────────────────────────────────────────────────
--
-- SKIP LOCKED so two workers running at once take different rows rather than
-- both taking the same one and sending everything twice. The same reasoning as
-- FOR UPDATE SKIP LOCKED in escalate_overdue_alerts(), and as the single-flight
-- guard on the app's offline queue flush: any queue drained from more than one
-- place needs this, or a burst is delivered twice.

CREATE OR REPLACE FUNCTION public.claim_notifications(p_limit INTEGER DEFAULT 20)
RETURNS SETOF public.notification_outbox
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN QUERY
  WITH due AS (
    SELECT o.id
      FROM public.notification_outbox o
     WHERE o.delivered_at IS NULL
       AND o.next_attempt_at <= NOW()
     ORDER BY o.next_attempt_at
     LIMIT GREATEST(COALESCE(p_limit, 20), 1)
     FOR UPDATE SKIP LOCKED
  )
  UPDATE public.notification_outbox o
     SET attempts = o.attempts + 1,
         -- Held off for a minute the moment it is claimed, so a worker that
         -- dies mid-send does not leave the row to be taken again immediately
         -- by the next tick. It returns to the queue on its own.
         next_attempt_at = NOW() + INTERVAL '1 minute'
    FROM due
   WHERE o.id = due.id
  RETURNING o.*;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_notifications(INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.claim_notifications(INTEGER) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_notifications(INTEGER) TO service_role;

CREATE OR REPLACE FUNCTION public.mark_notification_sent(p_id BIGINT)
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  UPDATE public.notification_outbox
     SET delivered_at = NOW(), last_error = NULL
   WHERE id = p_id;
$$;

CREATE OR REPLACE FUNCTION public.mark_notification_failed(p_id BIGINT, p_error TEXT)
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  UPDATE public.notification_outbox
     SET last_error = left(COALESCE(p_error, 'unknown'), 500),
         -- Back off with the attempt count, capped. An unreachable recipient
         -- must not hold the worker at one row for ever, and must not be
         -- retried for ever either.
         next_attempt_at = NOW() + make_interval(
           mins => LEAST(GREATEST(attempts, 1) * 2, 60))
   WHERE id = p_id;
$$;

REVOKE ALL ON FUNCTION public.mark_notification_sent(BIGINT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.mark_notification_failed(BIGINT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mark_notification_sent(BIGINT) TO service_role;
GRANT EXECUTE ON FUNCTION public.mark_notification_failed(BIGINT, TEXT) TO service_role;

-- ── The escalation now owes a notification ──────────────────────────────────
--
-- Same body as 20260928000000_command_chain_escalation.sql, with the outbox
-- insert in the SAME statement. Written as one CTE chain rather than a second
-- statement so there is no arrangement of failures in which the tier moves and
-- the notice does not.

CREATE OR REPLACE FUNCTION public.escalate_overdue_alerts()
RETURNS TABLE (alert_id UUID, from_tier TEXT, to_tier TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN QUERY
  WITH overdue AS (
    SELECT a.id,
           upper(a.assigned_tier)            AS current_tier,
           public.next_tier(a.assigned_tier) AS target_tier
      FROM public.alerts a
     WHERE a.status NOT IN ('RESOLVED', 'CANCELLED')
       -- Acknowledged means somebody at this tier has it. Climbing past a
       -- responder who is already on it is how you get two units dispatched
       -- to the same incident and none to the next one.
       AND a.acknowledged_at IS NULL
       AND public.next_tier(a.assigned_tier) IS NOT NULL
       AND a.tier_assigned_at IS NOT NULL
       AND a.tier_assigned_at <
             NOW() - make_interval(
               mins => public.tier_timeout_minutes(a.assigned_tier)
             )
     FOR UPDATE OF a SKIP LOCKED
  ),
  moved AS (
    UPDATE public.alerts a
       SET assigned_tier    = o.target_tier,
           tier_assigned_at = NOW(),
           status           = 'ESCALATED',
           updated_at       = NOW(),
           escalation_log = COALESCE(a.escalation_log, '[]'::jsonb) || jsonb_build_object(
             'from_tier',  o.current_tier,
             'to_tier',    o.target_tier,
             'reason',     'TIMEOUT',
             'by',         'SYSTEM',
             'at',         to_char(NOW() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
           )
      FROM overdue o
     WHERE a.id = o.id
    RETURNING a.id, o.current_tier, o.target_tier, a.geo_lga, a.geo_ward, a.geo_pu, a.severity
  ),
  queued AS (
    INSERT INTO public.notification_outbox (alert_id, kind, payload)
    SELECT m.id,
           'TIER_ESCALATION',
           jsonb_build_object(
             'alert_id',  m.id,
             'from_tier', m.current_tier,
             'to_tier',   m.target_tier,
             'geo_lga',   m.geo_lga,
             'geo_ward',  m.geo_ward,
             'geo_pu',    m.geo_pu,
             'severity',  m.severity,
             'reason',    'TIMEOUT'
           )
      FROM moved m
    -- `RETURNING alert_id` collides with this function's own OUT parameter of
    -- that name and is rejected as ambiguous. Nothing reads this CTE's output;
    -- it exists so the INSERT runs inside the same statement as the UPDATE.
    RETURNING id
  )
  SELECT m.id, m.current_tier, m.target_tier FROM moved m;
END;
$$;

COMMENT ON FUNCTION public.escalate_overdue_alerts() IS
  'Climbs unacknowledged alerts one rung when their tier has held them longer '
  'than app_config allows, and queues the notification in the same statement. '
  'Returns what it moved. Idempotent per run.';

REVOKE ALL ON FUNCTION public.escalate_overdue_alerts() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.escalate_overdue_alerts() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.escalate_overdue_alerts() TO service_role;

-- ── Is the automation actually running? ─────────────────────────────────────
--
-- The scheduling block in the escalation migration is conditional: without
-- pg_cron it raises a NOTICE and schedules NOTHING. So the entire automation
-- can be absent while every migration reports success — the worst way for it
-- to fail, because there is nothing to see.

CREATE OR REPLACE FUNCTION public.escalation_automation_status()
RETURNS TABLE (scheduled BOOLEAN, detail TEXT)
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RETURN QUERY SELECT false,
      'pg_cron is not installed: escalate_overdue_alerts() must be driven externally'::TEXT;
    RETURN;
  END IF;

  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'rainbow-escalate-overdue') THEN
    RETURN QUERY SELECT true, 'rainbow-escalate-overdue is scheduled'::TEXT;
  ELSE
    RETURN QUERY SELECT false,
      'pg_cron is installed but rainbow-escalate-overdue is NOT scheduled'::TEXT;
  END IF;
END;
$$;

COMMENT ON FUNCTION public.escalation_automation_status() IS
  'Whether the timeout escalation is actually scheduled. The scheduling block '
  'is conditional on pg_cron, so the automation can be silently absent.';

GRANT EXECUTE ON FUNCTION public.escalation_automation_status() TO service_role;

-- ----------------------------------------------------------------------------
-- 20261008000000_escalation_push_targets.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261008000000_escalation_push_targets.sql'; END $apply$;

-- Who a queued escalation is actually for, decided once, in the database.
--
-- ## The bug this is half of
--
-- `drain-outbox` handles three kinds — PUSH, SMS, WEBHOOK — and its default
-- branch logs "Unknown kind — marking delivered" and then marks the row
-- delivered.
--
-- Nothing writes PUSH, SMS or WEBHOOK rows. The only thing that writes to
-- `notification_outbox` is `escalate_overdue_alerts()`, and it writes
-- `TIER_ESCALATION`.
--
-- So every automatic escalation queued a notice, the worker did not recognise
-- it, and marked it delivered without telling anybody. That is precisely the
-- failure the outbox was built to end, reproduced in the thing built to drain
-- it — and worse than having no worker at all, because the rows are consumed:
-- `select count(*) from notification_outbox where delivered_at is null` reads
-- zero and the queue looks healthy.
--
-- ## Why the rule lives here and not in the worker
--
-- There are two drainers now — this Edge Function and
-- `/api/notify/drain` in the console — and the rule for who hears about an
-- escalation is subtle in both directions. Too narrow and an incident climbs
-- to a tier where nobody is told, which is the state being fixed. Too wide and
-- every escalation in Plateau wakes every commander, and people turn off the
-- notification they need.
--
-- Written twice it will drift. Written here, both drainers ask the same
-- question and get the same answer, and it is checkable in SQL against the
-- same database that decided the escalation.
--
-- The rule matches `alert_in_my_area()` deliberately: the tier that now owns
-- the incident, in the place the incident is. An officer row-level security
-- would refuse the row to is not sent a push about it.

CREATE OR REPLACE FUNCTION public.escalation_push_targets(p_outbox_id BIGINT)
RETURNS TABLE (user_id UUID, player_id TEXT, role TEXT)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
  WITH notice AS (
    SELECT o.payload
      FROM public.notification_outbox o
     WHERE o.id = p_outbox_id
       AND o.kind = 'TIER_ESCALATION'
  ),
  want AS (
    SELECT upper(coalesce(payload ->> 'to_tier', ''))            AS tier,
           nullif(upper(trim(coalesce(payload ->> 'geo_lga',  ''))), '') AS lga,
           nullif(upper(trim(coalesce(payload ->> 'geo_ward', ''))), '') AS ward,
           nullif(upper(trim(coalesce(payload ->> 'geo_pu',   ''))), '') AS pu
      FROM notice
  )
  SELECT p.id, p.onesignal_player_id, p.role
    FROM public.profiles p, want w
   WHERE p.onesignal_player_id IS NOT NULL
     AND length(p.onesignal_player_id) > 5
     AND upper(coalesce(p.role, '')) = ANY (
           CASE w.tier
             WHEN 'UNIT' THEN ARRAY['UNIT_COMMAND','POLLING_UNIT_OFFICER','POLLING_OFFICER']
             WHEN 'WARD' THEN ARRAY['WARD_COMMAND','WARD_OFFICER']
             WHEN 'LGA'  THEN ARRAY['LGA_COMMAND','LGA_OFFICER']
             WHEN 'HQ'   THEN ARRAY['HQ_COMMAND','HQ_OFFICER','ADMIN']
             -- A tier nobody holds addresses nobody. Failing open here would
             -- page the whole state on a malformed payload.
             ELSE ARRAY[]::TEXT[]
           END
         )
     AND (
       -- HQ is the whole state; it is the rung whose job is everything.
       w.tier = 'HQ'
       -- An incident with no location goes to the tier regardless of posting.
       -- These are the SOS reports that arrived without a GPS fix, and they
       -- must not fall silently between desks.
       OR w.lga IS NULL
       OR (
         nullif(upper(trim(coalesce(p.geo_lga, ''))), '') = w.lga
         AND (w.tier <> 'WARD' OR w.ward IS NULL
              OR nullif(upper(trim(coalesce(p.geo_ward, ''))), '') = w.ward)
         AND (w.tier <> 'UNIT' OR w.pu IS NULL
              OR nullif(upper(trim(coalesce(p.geo_pu, ''))), '') = w.pu)
       )
     );
$$;

COMMENT ON FUNCTION public.escalation_push_targets(BIGINT) IS
  'The officers a queued TIER_ESCALATION is for: the tier that now owns the '
  'incident, in the place the incident is. Mirrors alert_in_my_area() so a '
  'push is never sent to somebody RLS would refuse the incident to.';

REVOKE ALL ON FUNCTION public.escalation_push_targets(BIGINT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.escalation_push_targets(BIGINT) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.escalation_push_targets(BIGINT) TO service_role;

-- ----------------------------------------------------------------------------
-- 20261009000000_ward_names_compared_by_key.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261009000000_ward_names_compared_by_key.sql'; END $apply$;

-- GINDIRI  I and GINDIRI  1 are the same ward.
--
-- ## What was wrong
--
-- The app resolves an incident's ward from `assets/geo/plateau_wards.json` by
-- nearest centroid and writes that name into `alerts.geo_ward`. Officers are
-- posted from `tactical_mapping.dart`, which the console's own map is now
-- generated from. Those two files spell four Mangu wards differently:
--
--     the app WRITES        an officer is POSTED to
--     ─────────────────     ───────────────────────
--     GINDIRI  I            GINDIRI  1
--     GINDIRI  II           GINDIRI  11
--     MANGU  I              MANGU  1
--     MANGU  II             MANGU  11
--
-- Roman numerals in one file, Arabic in the other. `alert_in_my_area()`
-- compares the two columns after upper() and trim(), so for every incident in
-- those four wards:
--
--   * the ward commander posted there is REFUSED the incident, because
--     'GINDIRI  I' <> 'GINDIRI  1'. Row-level security hides an emergency from
--     the one officer whose command it is in.
--   * the console's ward filter cannot select it, because the dropdown is built
--     from the map and offers the other spelling.
--   * `escalation_push_targets()` finds nobody at WARD tier, so the escalation
--     is recorded as having no recipients — correctly, and for a reason that is
--     a typo.
--
-- Nothing errors. The ward simply has no supervision, and the screens agree
-- that everything is in order.
--
-- ## Why this is a key and not a rename
--
-- Renaming one side would need a decision about which spelling INEC blesses,
-- and an UPDATE across existing rows written under the other one. Both
-- spellings are already in the database — the app has been writing Roman
-- numerals since the ward asset landed — so a rename fixes new rows and leaves
-- the old ones orphaned in the opposite direction.
--
-- A comparison key fixes both directions at once and asserts nothing about
-- which name is correct: `geo_key()` collapses the difference, and the names
-- stay exactly as each file writes them.
--
-- The three remaining divergences are NOT handled here, because they are not
-- notation:
--
--     KADUN (GPS)   vs KADUNU (map)    — one letter; plausibly the same ward
--     DAMWAI (GPS)  vs KAMWAI (map)    — one letter; plausibly two wards
--     BWALL (GPS)   — absent from the map entirely
--
-- Folding those together in code would be guessing about Plateau's geography.
-- `scripts/sync_tactical_map.py` reports them for a human to settle.

-- ── The comparison key ──────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.geo_key(p_name TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = pg_catalog, pg_temp
AS $$
  SELECT nullif(
    regexp_replace(
      -- Trailing Roman numerals to Arabic, longest first so 'III' is not read
      -- as 'I' followed by 'II'. Anchored at the end: a ward called
      -- "VICTORIA II" keeps its name and only the numeral is rewritten, and a
      -- ward with an I in the middle of a word is untouched.
      regexp_replace(
        regexp_replace(
          regexp_replace(
            upper(trim(coalesce(p_name, ''))),
            '\s+', ' ', 'g'),
          '\s+III$', ' 111'),
        '\s+II$', ' 11'),
      '\s+I$', ' 1'),
    '');
$$;

COMMENT ON FUNCTION public.geo_key(TEXT) IS
  'The form two place names are compared in: upper-cased, runs of whitespace '
  'collapsed, and a trailing Roman numeral written in the Arabic form the '
  'tactical map uses. GINDIRI  I and GINDIRI  1 are the same ward; the app and '
  'the map spell four Mangu wards differently and RLS compared them raw.';

-- ── Area scoping, on the key ────────────────────────────────────────────────
--
-- Same rules as 20261006000000_alerts_scoped_to_posting.sql, which the header
-- of that file explains at length. Only the comparison changes: geo_key() in
-- place of nullif(upper(trim(...))). Restated in full rather than patched so
-- the whole predicate is readable in one place.

CREATE OR REPLACE FUNCTION public.alert_in_my_area(p_alert public.alerts)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
  WITH me AS (
    SELECT upper(coalesce(role, ''))      AS role,
           public.geo_key(geo_lga)        AS lga,
           public.geo_key(geo_ward)       AS ward,
           public.geo_key(geo_pu)         AS pu
      FROM public.profiles
     WHERE id = auth.uid()
  ),
  it AS (
    SELECT public.geo_key(p_alert.geo_lga)  AS lga,
           public.geo_key(p_alert.geo_ward) AS ward,
           public.geo_key(p_alert.geo_pu)   AS pu
  )
  SELECT CASE
    -- Unlocated incidents fail OPEN: an emergency nobody can see is worse than
    -- one seen too widely.
    WHEN (SELECT lga FROM it) IS NULL THEN true

    -- No posting: no area. geo_lga is self-writable, so blank must never mean
    -- "everywhere".
    WHEN (SELECT lga FROM me) IS NULL THEN false

    WHEN (SELECT role FROM me) LIKE 'WARD%' THEN
      (SELECT lga FROM it) = (SELECT lga FROM me)
      AND (SELECT ward FROM me) IS NOT NULL
      AND (SELECT ward FROM it) = (SELECT ward FROM me)

    WHEN (SELECT role FROM me) LIKE 'UNIT%'
      OR (SELECT role FROM me) LIKE 'POLLING%' THEN
      (SELECT lga FROM it) = (SELECT lga FROM me)
      AND (SELECT pu FROM me) IS NOT NULL
      AND (SELECT pu FROM it) = (SELECT pu FROM me)

    ELSE (SELECT lga FROM it) = (SELECT lga FROM me)
  END;
$$;

CREATE OR REPLACE FUNCTION public.alert_delegated_to_my_lga(p_alert public.alerts)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT COALESCE(
    public.geo_key(
      (p_alert.escalation_log -> jsonb_array_length(p_alert.escalation_log) - 1)
        ->> 'to_lga')
    = (SELECT public.geo_key(geo_lga) FROM public.profiles WHERE id = auth.uid()),
    false
  );
$$;

-- ── Escalation recipients, on the key ───────────────────────────────────────
--
-- 20261008000000_escalation_push_targets.sql matches an officer's posting
-- against the queued notice's geography with the same raw comparison, so a
-- WARD escalation in GINDIRI  I reached nobody and the outbox row was recorded
-- as having no recipients. Same rule, same key.

CREATE OR REPLACE FUNCTION public.escalation_push_targets(p_outbox_id BIGINT)
RETURNS TABLE (user_id UUID, player_id TEXT, role TEXT)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
  WITH notice AS (
    SELECT o.payload
      FROM public.notification_outbox o
     WHERE o.id = p_outbox_id
       AND o.kind = 'TIER_ESCALATION'
  ),
  want AS (
    SELECT upper(coalesce(payload ->> 'to_tier', ''))  AS tier,
           public.geo_key(payload ->> 'geo_lga')       AS lga,
           public.geo_key(payload ->> 'geo_ward')      AS ward,
           public.geo_key(payload ->> 'geo_pu')        AS pu
      FROM notice
  )
  SELECT p.id, p.onesignal_player_id, p.role
    FROM public.profiles p, want w
   WHERE p.onesignal_player_id IS NOT NULL
     AND length(p.onesignal_player_id) > 5
     AND upper(coalesce(p.role, '')) = ANY (
           CASE w.tier
             WHEN 'UNIT' THEN ARRAY['UNIT_COMMAND','POLLING_UNIT_OFFICER','POLLING_OFFICER']
             WHEN 'WARD' THEN ARRAY['WARD_COMMAND','WARD_OFFICER']
             WHEN 'LGA'  THEN ARRAY['LGA_COMMAND','LGA_OFFICER']
             WHEN 'HQ'   THEN ARRAY['HQ_COMMAND','HQ_OFFICER','ADMIN']
             -- A tier nobody holds addresses nobody. Failing open here would
             -- page the whole state on a malformed payload.
             ELSE ARRAY[]::TEXT[]
           END
         )
     AND (
       w.tier = 'HQ'
       OR w.lga IS NULL
       OR (
         public.geo_key(p.geo_lga) = w.lga
         AND (w.tier <> 'WARD' OR w.ward IS NULL
              OR public.geo_key(p.geo_ward) = w.ward)
         AND (w.tier <> 'UNIT' OR w.pu IS NULL
              OR public.geo_key(p.geo_pu) = w.pu)
       )
     );
$$;

-- ── Indexes ─────────────────────────────────────────────────────────────────
--
-- alerts_geo_idx indexes the raw columns, which the area test no longer reads.
-- geo_key() is IMMUTABLE so it can be indexed; the raw index is left in place
-- because the console still orders and groups by the unmodified names.

CREATE INDEX IF NOT EXISTS alerts_geo_key_idx
  ON public.alerts (public.geo_key(geo_lga), public.geo_key(geo_ward), public.geo_key(geo_pu));

CREATE INDEX IF NOT EXISTS profiles_geo_key_idx
  ON public.profiles (public.geo_key(geo_lga), public.geo_key(geo_ward), public.geo_key(geo_pu));

REVOKE ALL ON FUNCTION public.geo_key(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.geo_key(TEXT) TO anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 20261010000000_append_alert_media_atomically.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261010000000_append_alert_media_atomically.sql'; END $apply$;

-- Attaching evidence to an incident without losing any of it.
--
-- ## What was wrong
--
-- Three places append a URL to `alerts.media_urls`, and all three did it by
-- reading the array, adding to the copy, and writing the whole thing back:
--
--   lib/services/sync_service.dart                       the offline flush
--   lib/features/agent/mission_intel_screen.dart          a responder's evidence
--   lib/features/emergency/emergency_active_screen.dart   DURESS evidence
--
-- Read-modify-write over a network is lost-update by construction. Two uploads
-- that overlap both read the same array, and the second write erases the first.
-- The overlap is not hypothetical: the offline flush uploads a whole queue in a
-- loop, the duress screen fires each upload without awaiting it
-- (`unawaited(...)`), and a responder can photograph a scene twice in a few
-- seconds. Whichever upload finished second won and the other photograph was
-- gone — while the UI said "Evidence captured and sent to HQ".
--
-- `sync_service.dart` even labels its block "Atomic URL append to
-- alerts.media_urls". It is a comment, not a mechanism.
--
-- Evidence of a kidnapping that the app said it had sent is the worst thing in
-- this system to lose quietly.
--
-- ## The fix
--
-- ONE statement, and the row is locked inside it.
--
-- `FOR UPDATE` in the first CTE takes the row lock before anything is read, so
-- concurrent callers serialise rather than interleave: the second one blocks,
-- then re-reads the committed array and appends to THAT. Nothing is lost
-- whatever the ordering, and `added` is exact rather than approximate — which it
-- could not be if the old length were read in a separate statement.
--
-- Deduplicated on the way in, first occurrence winning, so retrying an upload
-- that actually succeeded does not put the same photograph in front of a
-- dispatcher twice, and does not shuffle it to the end of the dossier.
--
-- `coalesce(p_urls, '{}')` is not defensive habit. In PostgreSQL
-- `array || NULL::text[]` is NULL, so a caller passing a null array would have
-- ERASED every photograph already attached. That is a lost-evidence bug one
-- keystroke wide, and it is asserted against.
--
-- ## Why SECURITY INVOKER
--
-- Deliberately NOT a definer function. `alerts_update_own_or_ours` already says
-- who may change an incident — the reporter, the assigned team, and staff within
-- their command — and that is exactly the right rule for attaching evidence to
-- it. A definer function here would be a hole straight through the scoping
-- migration: anybody with a token could bolt media onto any incident in Plateau.
--
-- So row-level security applies, and the function returns NO ROW when the caller
-- is refused. The caller must treat an empty result as a refusal and never as
-- success — that is the one thing the Dart side has to get right, and
-- AlertMedia.append does.

CREATE OR REPLACE FUNCTION public.append_alert_media(
  p_alert_id UUID,
  p_urls     TEXT[]
)
RETURNS TABLE (added INTEGER, total INTEGER)
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  WITH locked AS (
    -- The lock, taken before the array is read. Row-level security applies to
    -- this SELECT, so an account with no part in the incident stops here and
    -- the whole statement returns nothing.
    SELECT a.id,
           coalesce(array_length(a.media_urls, 1), 0) AS before_n
      FROM public.alerts a
     WHERE a.id = p_alert_id
       FOR UPDATE
  ),
  updated AS (
    UPDATE public.alerts a
       SET media_urls = (
             -- WITH ORDINALITY so the order photographs were taken in survives,
             -- and min(ord) so a duplicate keeps its FIRST position rather than
             -- jumping to the end.
             SELECT coalesce(array_agg(d.u ORDER BY d.ord), '{}'::TEXT[])
               FROM (
                 SELECT t.u, min(t.ord) AS ord
                   FROM unnest(coalesce(a.media_urls, '{}'::TEXT[])
                               || coalesce(p_urls, '{}'::TEXT[]))
                          WITH ORDINALITY AS t(u, ord)
                  WHERE nullif(trim(t.u), '') IS NOT NULL
                  GROUP BY t.u
               ) d
           ),
           updated_at = now()
      FROM locked l
     WHERE a.id = l.id
    RETURNING coalesce(array_length(a.media_urls, 1), 0) AS after_n, l.before_n
  )
  SELECT (u.after_n - u.before_n)::INTEGER, u.after_n::INTEGER FROM updated u;
$$;

COMMENT ON FUNCTION public.append_alert_media(UUID, TEXT[]) IS
  'Append evidence URLs to an incident in ONE locked statement, so two '
  'concurrent uploads cannot erase each other. SECURITY INVOKER: '
  'alerts_update_own_or_ours decides who may attach. Returns no row when the '
  'caller is refused — a caller must not read that as success.';

REVOKE ALL ON FUNCTION public.append_alert_media(UUID, TEXT[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.append_alert_media(UUID, TEXT[]) FROM anon;
GRANT EXECUTE ON FUNCTION public.append_alert_media(UUID, TEXT[])
  TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 20261011000000_ussd_reports_are_unconfirmed.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261011000000_ussd_reports_are_unconfirmed.sql'; END $apply$;

-- A stranger's keystrokes must not become armed officers at a chosen place.
--
-- ## The threat this is about
--
-- USSD is the right channel for a citizen with no data, no smartphone and no
-- credit — in Plateau State that is most of the people this system protects. It
-- is also the cheapest possible way to lure responders into an ambush: no
-- install, no data, a ₦100 SIM, and the report is indistinguishable from a real
-- one. Security personnel in this state have been attacked after being drawn to
-- a location. This is not a theoretical risk being written up for completeness.
--
-- Two mitigations are theatre and are not implemented as if they were defences:
-- rate-limiting per number, and requiring registration. Both cost one more SIM
-- to defeat, and USSD self-registration is instant BY DESIGN — the carrier
-- asserts the MSISDN, so there is nothing to verify and nothing to slow down.
-- That openness is the point of the channel and is worth its cost; pretending a
-- rate limit closes the hole would be worse than leaving it open knowingly.
--
-- What this migration does instead is remove the AUTOMATIC path from a keypress
-- to a deployment, and give the officer who decides the provenance to decide on.
--
-- ## 1. A USSD report does not climb the ladder on its own
--
-- `escalate_overdue_alerts()` moves any unacknowledged alert up a tier on a
-- timer: UNIT after its window, then WARD, then LGA, then HQ. Every new row
-- defaults to `assigned_tier = 'UNIT'`, so a fake USSD report would page a
-- ward commander, then an LGA commander, then Command HQ, with no human having
-- ever judged whether it is real. The timers do the attacker's work.
--
-- So an unconfirmed USSD report is held out of the ladder. It is NOT hidden and
-- NOT quiet: it is on the board, it is counted, and the console shows it with
-- its provenance. What it does not do is manufacture urgency by itself.
--
-- The moment a human confirms it — `confirm_ussd_report()` — it joins the ladder
-- with a fresh clock and behaves exactly like any other incident.
--
-- ## 2. A false report becomes recordable
--
-- There was no way to say a report was a lie. `status` had RESOLVED and
-- CANCELLED, and CANCELLED is what a reporter does when they stand themselves
-- down. With no distinct outcome, no signal could ever accumulate against a
-- number, which means every other credibility measure was guesswork dressed up.
-- FALSE_REPORT is that outcome, and it is deliberately an ACTION BY AN OFFICER,
-- recorded with who said so.
--
-- ## 3. Corroboration, not a severity badge
--
-- One report of an armed attack from a number never seen before is a different
-- thing from four reports from four numbers on three carriers in the same ward
-- within twenty minutes. `ussd_report_credibility()` gives a dispatcher both
-- figures rather than a score, because a single number invites the reader to
-- stop thinking, and the shape of the corroboration is the part that matters.

-- ── Where it came from, and whether anybody has stood behind it ──────────────

ALTER TABLE public.alerts
  ADD COLUMN IF NOT EXISTS reporter_msisdn TEXT,
  ADD COLUMN IF NOT EXISTS caller_may_be_called BOOLEAN,
  ADD COLUMN IF NOT EXISTS ussd_confirmed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS ussd_confirmed_by UUID REFERENCES public.profiles(id),
  ADD COLUMN IF NOT EXISTS public_reference TEXT;

COMMENT ON COLUMN public.alerts.reporter_msisdn IS
  'The number the CARRIER asserted for a USSD session. Stronger evidence than '
  'the app''s SMS OTP — it cannot be typed, mistyped or phished — but it '
  'identifies a SIM, never a person.';

COMMENT ON COLUMN public.alerts.caller_may_be_called IS
  'Whether the USSD reporter agreed to be rung back. The ANSWER is a signal in '
  'itself; refusing never blocked the report, because a witness to an attack '
  'has good reasons not to want their phone ringing.';

COMMENT ON COLUMN public.alerts.ussd_confirmed_at IS
  'When a named officer stood behind this report. Until then it is out of the '
  'escalation ladder: no timer may turn a stranger''s keypresses into a '
  'deployment.';

COMMENT ON COLUMN public.alerts.public_reference IS
  'The short reference read back to a USSD caller. The only handle a person '
  'with no smartphone has on their own report.';

-- Looking a caller's own history up, and the corroboration window, both read
-- this constantly.
CREATE INDEX IF NOT EXISTS alerts_reporter_msisdn_idx
  ON public.alerts (reporter_msisdn, created_at DESC)
  WHERE reporter_msisdn IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS alerts_public_reference_idx
  ON public.alerts (public_reference)
  WHERE public_reference IS NOT NULL;

-- ── Holding an unconfirmed report out of the ladder ─────────────────────────
--
-- Expressed as a predicate rather than inlined, so the escalation job and the
-- console cannot drift about what "unconfirmed" means.

CREATE OR REPLACE FUNCTION public.awaiting_human_confirmation(p_alert public.alerts)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT upper(coalesce(p_alert.arrived_via, '')) = 'USSD'
     AND p_alert.ussd_confirmed_at IS NULL;
$$;

COMMENT ON FUNCTION public.awaiting_human_confirmation(public.alerts) IS
  'A USSD report nobody has stood behind yet. On the board and counted, but '
  'out of the escalation ladder, so no timer can manufacture urgency for a '
  'report that may have been filed to draw officers somewhere.';

-- Copied VERBATIM from 20261007000000_notification_outbox.sql with ONE line
-- added, and copied rather than rewritten on purpose. The first version of this
-- migration restated the function "in full for readability" and silently
-- dropped four things: status = 'ESCALATED', updated_at, the escalation_log key
-- names the console and drain-outbox read (from_tier/to_tier, not from/to), and
-- the 'reason':'TIMEOUT' in the outbox payload. A CREATE OR REPLACE that looks
-- like a tidy-up is how a working mechanism gets reverted by a migration about
-- something else.

CREATE OR REPLACE FUNCTION public.escalate_overdue_alerts()
RETURNS TABLE (alert_id UUID, from_tier TEXT, to_tier TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN QUERY
  WITH overdue AS (
    SELECT a.id,
           upper(a.assigned_tier)            AS current_tier,
           public.next_tier(a.assigned_tier) AS target_tier
      FROM public.alerts a
     WHERE a.status NOT IN ('RESOLVED', 'CANCELLED')
       -- Acknowledged means somebody at this tier has it. Climbing past a
       -- responder who is already on it is how you get two units dispatched
       -- to the same incident and none to the next one.
       AND a.acknowledged_at IS NULL
       -- A report filed over USSD that no officer has stood behind. The timers
       -- must not turn a stranger's keypresses into a deployment; see
       -- awaiting_human_confirmation() above.
       AND NOT public.awaiting_human_confirmation(a)
       AND public.next_tier(a.assigned_tier) IS NOT NULL
       AND a.tier_assigned_at IS NOT NULL
       AND a.tier_assigned_at <
             NOW() - make_interval(
               mins => public.tier_timeout_minutes(a.assigned_tier)
             )
     FOR UPDATE OF a SKIP LOCKED
  ),
  moved AS (
    UPDATE public.alerts a
       SET assigned_tier    = o.target_tier,
           tier_assigned_at = NOW(),
           status           = 'ESCALATED',
           updated_at       = NOW(),
           escalation_log = COALESCE(a.escalation_log, '[]'::jsonb) || jsonb_build_object(
             'from_tier',  o.current_tier,
             'to_tier',    o.target_tier,
             'reason',     'TIMEOUT',
             'by',         'SYSTEM',
             'at',         to_char(NOW() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
           )
      FROM overdue o
     WHERE a.id = o.id
    RETURNING a.id, o.current_tier, o.target_tier, a.geo_lga, a.geo_ward, a.geo_pu, a.severity
  ),
  queued AS (
    INSERT INTO public.notification_outbox (alert_id, kind, payload)
    SELECT m.id,
           'TIER_ESCALATION',
           jsonb_build_object(
             'alert_id',  m.id,
             'from_tier', m.current_tier,
             'to_tier',   m.target_tier,
             'geo_lga',   m.geo_lga,
             'geo_ward',  m.geo_ward,
             'geo_pu',    m.geo_pu,
             'severity',  m.severity,
             'reason',    'TIMEOUT'
           )
      FROM moved m
    -- `RETURNING alert_id` collides with this function's own OUT parameter of
    -- that name and is rejected as ambiguous. Nothing reads this CTE's output;
    -- it exists so the INSERT runs inside the same statement as the UPDATE.
    RETURNING id
  )
  SELECT m.id, m.current_tier, m.target_tier FROM moved m;
END;
$$;

-- ── An officer standing behind a report ────────────────────────────────────

CREATE OR REPLACE FUNCTION public.confirm_ussd_report(p_alert_id UUID)
RETURNS TABLE (confirmed BOOLEAN, tier TEXT)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tier TEXT;
BEGIN
  -- SECURITY INVOKER: alerts_update_own_or_ours already decides who may act on
  -- an incident, and that is exactly the right rule here. A definer function
  -- would let any account with a token confirm a report anywhere in Plateau —
  -- which is the whole control, handed away.
  UPDATE public.alerts a
     SET ussd_confirmed_at = NOW(),
         ussd_confirmed_by = auth.uid(),
         -- A fresh clock. Inheriting the age it accumulated while unconfirmed
         -- would make it overdue the instant it was confirmed and climb several
         -- tiers in one pass of the job — the cascade
         -- 20260928000000 already had to fix once for hand escalations.
         tier_assigned_at  = NOW(),
         escalation_log    = coalesce(a.escalation_log, '[]'::jsonb) || jsonb_build_object(
           'at',     NOW(),
           'by',     auth.uid(),
           'action', 'CONFIRMED',
           'reason', 'a named officer stood behind a USSD report'
         )
   WHERE a.id = p_alert_id
     AND upper(coalesce(a.arrived_via, '')) = 'USSD'
     AND a.ussd_confirmed_at IS NULL
  RETURNING a.assigned_tier INTO v_tier;

  IF v_tier IS NULL THEN
    -- Not ours, not USSD, already confirmed, or gone. No row, so a caller
    -- cannot read a refusal as a confirmation.
    RETURN;
  END IF;
  RETURN QUERY SELECT true, v_tier;
END $$;

COMMENT ON FUNCTION public.confirm_ussd_report(UUID) IS
  'A named officer stands behind a USSD report, which joins the escalation '
  'ladder with a fresh clock. Returns no row if the caller may not act on that '
  'incident, so a refusal can never read as a confirmation.';

REVOKE ALL ON FUNCTION public.confirm_ussd_report(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.confirm_ussd_report(UUID) TO authenticated, service_role;

-- ── Recording that a report was a lie ──────────────────────────────────────

CREATE OR REPLACE FUNCTION public.mark_false_report(p_alert_id UUID, p_note TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE v_id UUID;
BEGIN
  -- FALSE_REPORT, not CANCELLED. CANCELLED is what a reporter does when they
  -- stand themselves down and carries no accusation. This is an officer saying
  -- the report was untrue, and it is the ONLY thing that can ever make a
  -- number's history mean anything — without it, every credibility measure in
  -- this file would be guesswork dressed up as evidence.
  UPDATE public.alerts a
     SET status         = 'FALSE_REPORT',
         resolved_at    = NOW(),
         escalation_log = coalesce(a.escalation_log, '[]'::jsonb) || jsonb_build_object(
           'at',     NOW(),
           'by',     auth.uid(),
           'action', 'FALSE_REPORT',
           'reason', coalesce(nullif(trim(p_note), ''), 'marked false by an officer')
         )
   WHERE a.id = p_alert_id
  RETURNING a.id INTO v_id;
  RETURN v_id IS NOT NULL;
END $$;

COMMENT ON FUNCTION public.mark_false_report(UUID, TEXT) IS
  'An officer records that a report was untrue. Distinct from CANCELLED, which '
  'is a reporter standing themselves down. This is the only source of the '
  'history that makes a number''s credibility a fact rather than a guess.';

REVOKE ALL ON FUNCTION public.mark_false_report(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_false_report(UUID, TEXT) TO authenticated, service_role;

-- ── What a dispatcher should know before sending anybody ────────────────────

CREATE OR REPLACE FUNCTION public.ussd_report_credibility(p_alert_id UUID)
RETURNS TABLE (
  first_time_caller     BOOLEAN,
  caller_report_count   INTEGER,
  caller_false_reports  INTEGER,
  caller_known_days     INTEGER,
  callback_offered      BOOLEAN,
  corroborating_reports INTEGER,
  corroborating_numbers INTEGER
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
  WITH it AS (
    SELECT a.id, a.reporter_msisdn, a.created_at, a.category,
           public.geo_key(a.geo_lga)  AS lga,
           public.geo_key(a.geo_ward) AS ward,
           a.caller_may_be_called
      FROM public.alerts a
     WHERE a.id = p_alert_id
  ),
  history AS (
    SELECT count(*)::INTEGER AS n,
           count(*) FILTER (WHERE upper(coalesce(h.status, '')) = 'FALSE_REPORT')::INTEGER
             AS false_n,
           min(h.created_at) AS first_seen
      FROM public.alerts h, it
     WHERE h.reporter_msisdn IS NOT NULL
       AND h.reporter_msisdn = it.reporter_msisdn
       AND h.id <> it.id
  ),
  -- Independent reports of what may be the same event: the same ward, the same
  -- category, inside a window, from OTHER numbers. Counted two ways on purpose
  -- — four reports from one number is one person pressing keys, and four from
  -- four numbers is a village.
  nearby AS (
    SELECT count(*)::INTEGER AS n,
           count(DISTINCT coalesce(c.reporter_msisdn, c.id::text))::INTEGER AS numbers
      FROM public.alerts c, it
     WHERE c.id <> it.id
       AND c.created_at BETWEEN it.created_at - INTERVAL '45 minutes'
                           AND it.created_at + INTERVAL '45 minutes'
       AND c.category IS NOT DISTINCT FROM it.category
       AND it.lga IS NOT NULL
       AND public.geo_key(c.geo_lga) = it.lga
       AND (it.ward IS NULL OR public.geo_key(c.geo_ward) = it.ward)
       AND coalesce(c.reporter_msisdn, '') <> coalesce(it.reporter_msisdn, '')
  )
  SELECT (history.n = 0),
         history.n,
         history.false_n,
         CASE WHEN history.first_seen IS NULL THEN 0
              ELSE GREATEST(0, (EXTRACT(EPOCH FROM (NOW() - history.first_seen)) / 86400)::INTEGER)
         END,
         coalesce(it.caller_may_be_called, false),
         nearby.n,
         nearby.numbers
    FROM it, history, nearby;
$$;

COMMENT ON FUNCTION public.ussd_report_credibility(UUID) IS
  'What a dispatcher should know before committing officers on the word of a '
  'phone number: is this the first time it has ever been heard from, what has '
  'it reported before, has anything it filed been marked false, did it agree '
  'to a callback, and is anybody else saying the same thing. Figures, not a '
  'score — a single number invites the reader to stop thinking, and the shape '
  'of the corroboration is the part that matters.';

REVOKE ALL ON FUNCTION public.ussd_report_credibility(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ussd_report_credibility(UUID) TO authenticated, service_role;

-- ── The USSD session store ─────────────────────────────────────────────────
--
-- USSD is stateless HTTP per screen. Some aggregators hand over the whole
-- `*`-joined input path and some only the latest keypress, so the state has to
-- live here regardless — and it has to live here anyway for idempotency,
-- because a gateway that times out RE-POSTS the same session and the same input
-- and must not produce a second alert.

CREATE TABLE IF NOT EXISTS public.ussd_sessions (
  session_id   TEXT PRIMARY KEY,
  msisdn       TEXT NOT NULL,
  state        JSONB NOT NULL DEFAULT '{}'::jsonb,
  -- The last screen sent. A retry is answered from here rather than re-running
  -- the reducer, which is what makes a repeat POST harmless.
  last_screen  TEXT,
  last_input   TEXT,
  -- Set once a report has been filed in this session, so a retry of the final
  -- keypress returns the same reference instead of filing a second emergency.
  filed_alert  UUID REFERENCES public.alerts(id) ON DELETE SET NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.ussd_sessions IS
  'One row per USSD dialogue. Holds the menu state between screens, and the '
  'alert already filed, so a gateway retry cannot raise the same emergency '
  'twice.';

CREATE INDEX IF NOT EXISTS ussd_sessions_stale_idx
  ON public.ussd_sessions (updated_at);

-- Nobody signed in from a phone or a browser may read these: they contain the
-- MSISDNs of people who reported anonymously, and the whole point of an
-- anonymous report is that the reporter is not in a table anyone can query.
ALTER TABLE public.ussd_sessions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.ussd_sessions FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.ussd_sessions TO service_role;

COMMENT ON INDEX public.ussd_sessions_stale_idx IS
  'Sessions are short-lived; this supports the sweep that deletes finished and '
  'abandoned dialogues rather than keeping a log of who dialled what.';

-- ----------------------------------------------------------------------------
-- 20261012000000_ussd_filing.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261012000000_ussd_filing.sql'; END $apply$;

-- Filing a report from a USSD session, exactly once.
--
-- ## Why the filing is here and not in the route
--
-- A USSD gateway that does not get a reply inside its window RE-POSTS the same
-- session with the same input. That is not an error condition, it is normal
-- operation on a congested network — which is precisely when people are
-- reporting emergencies. A route that files on every POST would raise the same
-- kidnapping two, three, four times, and a dispatcher would see four incidents
-- and have no way to tell them from four real reports.
--
-- Guarding that in the route means reading the session, deciding, then writing —
-- and two concurrent retries both read "not filed yet" and both file. The only
-- place that race can actually be closed is inside one statement holding the
-- session row's lock, which is here.
--
-- So `ussd_file_report()` is the whole transaction: lock the session, return the
-- report it already filed if there is one, otherwise write the alert and record
-- it against the session. A retry gets the SAME reference, which is also the
-- right answer for the caller — they are told again what they were told before,
-- instead of being handed a second reference for an incident that does not exist.
--
-- ## What is deliberately NOT here
--
-- Creating the caller's account. `profiles.id` references `auth.users`, and
-- `auth.users` is Supabase's table: its column set has changed across versions
-- and several columns are NOT NULL with no default depending on the release.
-- Hand-inserting into it from a migration is the kind of thing that works in
-- staging and fails on an upgrade, so the route uses the Admin API for that and
-- this file never touches it.

-- ── The reference a caller is read back ────────────────────────────────────

CREATE OR REPLACE FUNCTION public.ussd_reference()
RETURNS TEXT
LANGUAGE plpgsql
VOLATILE
SET search_path = public, pg_temp
AS $$
DECLARE
  -- No 0/O, 1/I/L, 5/S, 2/Z or 8/B. This reference is read off a feature-phone
  -- screen and then spoken down a phone line to a desk officer, so a character
  -- somebody can hear or see wrongly costs a real minute in an emergency.
  alphabet CONSTANT TEXT := '34679ACDEFGHJKMNPQRTUVWXY';
  candidate TEXT;
  attempt   INTEGER := 0;
BEGIN
  LOOP
    candidate := 'R';
    FOR i IN 1..5 LOOP
      candidate := candidate ||
        substr(alphabet, 1 + floor(random() * length(alphabet))::INTEGER, 1);
    END LOOP;
    -- 25^5 is about 9.7 million, and there is a unique index, so a collision is
    -- rare and cheap to walk away from. Bounded rather than looping for ever:
    -- a USSD session has seconds, and spinning here would time out the call.
    EXIT WHEN NOT EXISTS (
      SELECT 1 FROM public.alerts WHERE public_reference = candidate
    );
    attempt := attempt + 1;
    IF attempt >= 12 THEN
      -- Fall back to something guaranteed unique rather than failing the report.
      -- Uglier to read aloud, and infinitely better than losing an emergency.
      candidate := 'R' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 7));
      EXIT;
    END IF;
  END LOOP;
  RETURN candidate;
END $$;

COMMENT ON FUNCTION public.ussd_reference() IS
  'A short report reference with no visually or audibly confusable characters, '
  'because it is read off a feature phone and then spoken to a desk officer.';

-- ── Who is dialling ───────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.ussd_caller(p_msisdn TEXT)
RETURNS TABLE (user_id UUID, role TEXT, geo_lga TEXT, geo_ward TEXT, geo_pu TEXT)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
  -- Matched on the last nine digits, not on equality. The carrier may present
  -- 2348030001111, +2348030001111 or 08030001111 for the same SIM depending on
  -- the aggregator and the network, and a citizen who registered in the app
  -- typed whichever form they think of as their number. Comparing raw strings
  -- would hand a returning app user the stranger's path — six keypresses and no
  -- posting — while their profile sat right there.
  SELECT p.id, p.role, p.geo_lga, p.geo_ward, p.geo_pu
    FROM public.profiles p
   WHERE p.phone IS NOT NULL
     AND right(regexp_replace(p.phone, '\D', '', 'g'), 9)
       = right(regexp_replace(coalesce(p_msisdn, ''), '\D', '', 'g'), 9)
     AND length(regexp_replace(coalesce(p_msisdn, ''), '\D', '', 'g')) >= 9
   ORDER BY p.created_at
   LIMIT 1;
$$;

COMMENT ON FUNCTION public.ussd_caller(TEXT) IS
  'The profile behind a dialling MSISDN, matched on the last nine digits because '
  'carriers and app users write the same number several ways.';

REVOKE ALL ON FUNCTION public.ussd_caller(TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ussd_caller(TEXT) TO service_role;

-- ── Filing, exactly once per session ──────────────────────────────────────

CREATE OR REPLACE FUNCTION public.ussd_file_report(
  p_session_id TEXT,
  p_msisdn     TEXT,
  p_reporter   UUID,
  p_type       TEXT,
  p_emergency  BOOLEAN,
  p_lga        TEXT,
  p_ward       TEXT,
  p_callback   BOOLEAN
)
RETURNS TABLE (reference TEXT, alert_id UUID, already_filed BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_existing UUID;
  v_ref      TEXT;
  v_id       UUID;
BEGIN
  -- Lock the session first. Everything below depends on being the only writer
  -- for this dialogue, and two concurrent retries are the normal case this
  -- function exists for.
  SELECT s.filed_alert INTO v_existing
    FROM public.ussd_sessions s
   WHERE s.session_id = p_session_id
     FOR UPDATE;

  IF NOT FOUND THEN
    -- The route always opens the session before filing, so this is a caller
    -- bug rather than a user one. Refuse rather than inventing a session: an
    -- alert with no dialogue behind it cannot be deduplicated on a retry.
    RETURN;
  END IF;

  IF v_existing IS NOT NULL THEN
    -- A retry. Hand back what was already filed, so the caller is told the same
    -- reference again instead of a second one for an incident that never existed.
    RETURN QUERY
      SELECT a.public_reference, a.id, true
        FROM public.alerts a
       WHERE a.id = v_existing;
    RETURN;
  END IF;

  v_ref := public.ussd_reference();

  INSERT INTO public.alerts (
    -- No `priority`: that is not a column. The console DERIVES it when it maps a
    -- row (`priority: d.severity || 'UNKNOWN'` in dashboard/page.tsx), and
    -- writing it here was rejected outright by the first harness run.
    type, description, status, severity,
    reported_by, geo_lga, geo_ward,
    arrived_via, reporter_msisdn, caller_may_be_called, public_reference,
    assigned_tier, tier_assigned_at, created_at, updated_at
  ) VALUES (
    p_type,
    -- The description is the provenance. A dispatcher reading this row has to
    -- know, without clicking anything, that it came from a keypad and that
    -- nobody has stood behind it yet.
    '[USSD] Reported by keypad from ' || coalesce(p_msisdn, 'an unknown number')
      || '. Not yet confirmed by an officer.',
    'PENDING',
    -- The emergency branch is CRITICAL whatever else is true, exactly as the
    -- offline-channel ingest treats a duress alert. A person choosing "armed
    -- attack" on a menu is not grading their own incident.
    CASE WHEN p_emergency THEN 'CRITICAL' ELSE 'MEDIUM' END,
    p_reporter,
    nullif(trim(coalesce(p_lga, '')), ''),
    nullif(trim(coalesce(p_ward, '')), ''),
    'USSD',
    p_msisdn,
    coalesce(p_callback, false),
    v_ref,
    'UNIT',
    -- The clock starts, but awaiting_human_confirmation() holds it out of the
    -- ladder until an officer confirms it (20261011000000). Both are true at
    -- once on purpose: the age is real and visible, and the timer cannot act on
    -- it. Setting this to NULL instead would make the row look ageless on the
    -- board, which is its own kind of lie.
    NOW(), NOW(), NOW()
  )
  RETURNING id INTO v_id;

  UPDATE public.ussd_sessions
     SET filed_alert = v_id, updated_at = NOW()
   WHERE session_id = p_session_id;

  RETURN QUERY SELECT v_ref, v_id, false;
END $$;

COMMENT ON FUNCTION public.ussd_file_report(TEXT, TEXT, UUID, TEXT, BOOLEAN, TEXT, TEXT, BOOLEAN) IS
  'Files one report for one USSD session, holding the session row''s lock, so a '
  'gateway retry gets the SAME reference rather than raising the same emergency '
  'twice. Returns no row if the session was never opened.';

REVOKE ALL ON FUNCTION
  public.ussd_file_report(TEXT, TEXT, UUID, TEXT, BOOLEAN, TEXT, TEXT, BOOLEAN)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION
  public.ussd_file_report(TEXT, TEXT, UUID, TEXT, BOOLEAN, TEXT, TEXT, BOOLEAN)
  TO service_role;

-- ── The caller's own last report ──────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.ussd_last_report(p_msisdn TEXT)
RETURNS TABLE (reference TEXT, kind TEXT, status TEXT, age_minutes INTEGER)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
  -- Status only, and by column rather than by `select *`, so nobody can widen
  -- this later without noticing. Whoever holds the SIM can read this screen,
  -- and somebody who filed a report to draw officers to a place must not be
  -- able to watch them come: no assigned_to, no assigned_responders, no
  -- coordinates, no tier.
  SELECT a.public_reference,
         a.type,
         a.status,
         GREATEST(0, (EXTRACT(EPOCH FROM (NOW() - a.created_at)) / 60)::INTEGER)
    FROM public.alerts a
   WHERE a.reporter_msisdn IS NOT NULL
     AND right(regexp_replace(a.reporter_msisdn, '\D', '', 'g'), 9)
       = right(regexp_replace(coalesce(p_msisdn, ''), '\D', '', 'g'), 9)
     AND length(regexp_replace(coalesce(p_msisdn, ''), '\D', '', 'g')) >= 9
   -- `id` breaks the tie. Two reports from one number can share a created_at —
   -- `NOW()` is the transaction timestamp, and a double-dial or a burst arrives
   -- inside the same second — and ordering on created_at alone would then return
   -- an arbitrary one of them. A caller reading back "my last report" and being
   -- shown a different one each time they dial is worse than useless.
   ORDER BY a.created_at DESC, a.id DESC
   LIMIT 1;
$$;

COMMENT ON FUNCTION public.ussd_last_report(TEXT) IS
  'The status of a caller''s most recent report, for the USSD status screen. '
  'Named columns only: this screen is readable by anyone holding the SIM, so it '
  'must never carry a unit, a position or a tier.';

REVOKE ALL ON FUNCTION public.ussd_last_report(TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ussd_last_report(TEXT) TO service_role;

-- ── Forgetting the dialogue ───────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.sweep_ussd_sessions(p_older_than INTERVAL DEFAULT INTERVAL '2 hours')
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE n INTEGER;
BEGIN
  -- These rows hold the MSISDNs of people who reported, including anonymously.
  -- Keeping them after the dialogue has ended would turn a session store into a
  -- log of who dialled what, which is not a thing this system should own. The
  -- ALERT keeps what it needs; the dialogue does not need to outlive the call.
  DELETE FROM public.ussd_sessions
   WHERE updated_at < NOW() - p_older_than;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END $$;

COMMENT ON FUNCTION public.sweep_ussd_sessions(INTERVAL) IS
  'Deletes finished and abandoned USSD dialogues. The session store must not '
  'become a log of who dialled what — the alert keeps what is needed.';

REVOKE ALL ON FUNCTION public.sweep_ussd_sessions(INTERVAL) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.sweep_ussd_sessions(INTERVAL) TO service_role;

-- ----------------------------------------------------------------------------
-- 20261013000000_ussd_landmark.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261013000000_ussd_landmark.sql'; END $apply$;

-- The nearest landmark, typed by somebody who has no GPS.
--
-- ## Why this is worth a column
--
-- A USSD report cannot carry coordinates. USSD rides the signalling channel with
-- no access to the handset's location, so the best the console can draw is a
-- circle the size of the ward the caller chose — 800m across in Jos North, 16km
-- in parts of Wase. That circle tells a commander which unit owns the incident.
-- It does not tell a driver where to go.
--
-- A landmark does. The polling units in the tactical map are real findable places
-- — POLICE BARRACKS, PRIM. SCHOOL DAFFO, DISPENSARY GORO, NEW MARKET SCHOOL LANE
-- — and so are the ones a caller types from their own knowledge. "Behind the
-- mosque on the Bokkos road" is worth more to a responder than a 3km circle, and
-- no list could have contained it.
--
-- It is asked AFTER the report is filed, never before. The emergency is already
-- recorded and HQ can already see it; this arrives seconds later. Asking first
-- would put another screen between a person under attack and the report landing,
-- and if the session then dropped they would have neither.
--
-- ## What it is NOT
--
-- It is not a location. It does not change `locateIncident()`'s precision, and it
-- must never be parsed into coordinates — there are no polling-unit coordinates
-- in this system, and deriving a point from a string would be the fabricated-fix
-- defect again wearing a different hat. It is text, written by a person, for a
-- person to read.

ALTER TABLE public.alerts
  ADD COLUMN IF NOT EXISTS reporter_landmark TEXT;

COMMENT ON COLUMN public.alerts.reporter_landmark IS
  'The nearest landmark as the reporter typed it, for a responder to read. NOT a '
  'location: it never becomes coordinates, because deriving a point from a '
  'string is the fabricated-fix defect wearing a different hat.';

-- ── Attaching one to the report this session already filed ─────────────────

CREATE OR REPLACE FUNCTION public.ussd_add_landmark(
  p_session_id TEXT,
  p_landmark   TEXT
)
RETURNS TABLE (reference TEXT, alert_id UUID)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_alert UUID;
  v_text  TEXT;
BEGIN
  v_text := nullif(btrim(coalesce(p_landmark, '')), '');
  IF v_text IS NULL THEN RETURN; END IF;

  -- Only ever the report THIS session filed. Taking an alert id from the caller
  -- would let anybody with the endpoint write a landmark onto any incident in
  -- Plateau — a way to redirect a response by typing, which is the same class of
  -- problem as the ambush this channel is already careful about.
  SELECT s.filed_alert INTO v_alert
    FROM public.ussd_sessions s
   WHERE s.session_id = p_session_id;
  IF v_alert IS NULL THEN RETURN; END IF;

  UPDATE public.alerts a
     SET reporter_landmark = left(v_text, 120),
         -- Appended to the description as well, because that is what a
         -- dispatcher reads first and what the SMS and push notices carry. A
         -- column nobody surfaces is a column nobody reads.
         description = coalesce(a.description, '')
                       || ' Nearest landmark: ' || left(v_text, 120) || '.',
         updated_at = NOW()
   WHERE a.id = v_alert
  RETURNING a.public_reference, a.id INTO reference, alert_id;

  IF reference IS NULL THEN RETURN; END IF;
  RETURN NEXT;
END $$;

COMMENT ON FUNCTION public.ussd_add_landmark(TEXT, TEXT) IS
  'Attaches a typed landmark to the report THIS USSD session filed. Never takes '
  'an alert id from the caller: that would let anybody write a landmark onto any '
  'incident in Plateau and redirect a response by typing.';

REVOKE ALL ON FUNCTION public.ussd_add_landmark(TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ussd_add_landmark(TEXT, TEXT) TO service_role;

-- ----------------------------------------------------------------------------
-- 20261014000000_ai_reports_are_kept.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261014000000_ai_reports_are_kept.sql'; END $apply$;

-- The forensic report the AI produced, kept.
--
-- ## What was wrong
--
-- `generateAISummary()` in the console called Gemini, put the text in React
-- state, and rendered it. Nothing wrote it anywhere. Close the dossier and the
-- forensic debrief was gone; reopen the incident and the console billed another
-- Gemini call to produce it again.
--
-- Three separate costs, and the third is the one that matters:
--
--   * There was nowhere for an administrator to see a report that had been
--     generated. That was the operator's own question — "where can admin see the
--     forensic report that was generated?" — and the answer was nowhere.
--   * Every reopen paid for the same analysis.
--   * **There was no record of what the AI said at the moment a decision was
--     made.** If an officer escalated an incident or cleared it partly on the
--     strength of an AI debrief, the text they read is part of why. A forensic
--     assessment that exists only until a browser tab closes cannot be part of an
--     audit trail, which is the entire purpose of the word forensic.
--
-- ## Why a table and not the existing ai_summary column
--
-- `alerts.ai_summary` is free text that already accumulates operator-facing
-- notes — the classification lines `[AI CLASSIFICATION APPLIED] severity ...`
-- are appended to it. Mixing a multi-paragraph forensic document into the same
-- column means neither can be read back reliably, and it makes "which report was
-- generated when, by whom, by which model" unanswerable.
--
-- A report is also not singular. One may be generated while an incident is
-- running and another after the debrief, and the earlier one does not stop being
-- evidence of what was known at the time. So: rows, with provenance, kept.
--
-- ## Why only the server may write one
--
-- This is the important rule. `/api/ai/analyze` holds the Gemini key, composes
-- the prompt from the alert row, and receives the answer. It is the only thing
-- that knows what the model actually said.
--
-- If the browser wrote the text, an operator could put words in the model's mouth
-- in the audit record — "the AI concluded the responders acted correctly" — and
-- nothing downstream could tell that from a genuine completion. So INSERT is
-- service-role only. Nobody signed in from a browser or a phone can create one,
-- and the console reads them back rather than supplying them.

CREATE TABLE IF NOT EXISTS public.incident_ai_reports (
  id           BIGSERIAL PRIMARY KEY,
  alert_id     UUID NOT NULL REFERENCES public.alerts(id) ON DELETE CASCADE,
  -- 'summary' is the forensic debrief; 'triage' is the classification
  -- recommendation. Kept apart because they are read in different places and a
  -- triage recommendation is not a report.
  kind         TEXT NOT NULL CHECK (kind IN ('summary', 'triage')),
  body         TEXT NOT NULL,
  -- Which model produced it. A debrief written by a model that has since been
  -- retired still has to be readable as such: "the AI said" is not a fact
  -- without knowing which AI.
  model        TEXT,
  -- Who asked for it. Not who wrote it — the model wrote it — but an AI
  -- assessment appearing on an incident with nobody's name against the request
  -- is an unattributed document in an audit trail.
  requested_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.incident_ai_reports IS
  'Forensic debriefs and triage recommendations as the model actually returned '
  'them. INSERT is service-role only: if a browser could write these, an operator '
  'could put words in the model''s mouth in the audit record.';

-- The console reads the newest report for one incident, constantly.
CREATE INDEX IF NOT EXISTS incident_ai_reports_alert_idx
  ON public.incident_ai_reports (alert_id, kind, created_at DESC);

ALTER TABLE public.incident_ai_reports ENABLE ROW LEVEL SECURITY;

-- ── Who may read one ───────────────────────────────────────────────────────

DROP POLICY IF EXISTS "ai_reports_select_with_alert" ON public.incident_ai_reports;
CREATE POLICY "ai_reports_select_with_alert" ON public.incident_ai_reports
  FOR SELECT TO authenticated
  USING (
    -- Operation Rainbow STAFF, within their command, and no one else.
    --
    -- Two exclusions, both for the same reason. A machine assessment is
    -- Rainbow's own working note: it may speculate about what happened and who
    -- was involved, and it may be wrong.
    --
    --   * A LIAISON sees the incidents escalated to their agency, deliberately.
    --     Handing another organisation our internal assessment of those
    --     incidents is not a decision a policy should make on a commander's
    --     behalf. If it should be shared, a person can share it.
    --
    --   * The REPORTER is excluded for the same reason, and this was a
    --     correction. The first version of this policy required only
    --     alert_is_ours(), which admits the person who reported the incident —
    --     so a citizen would have read a forensic debrief of their own
    --     kidnapping, including whatever the model speculated about suspects or
    --     about how the response went. The behaviour test caught it and recorded
    --     it as a NOTE rather than a failure; leaving it as a note would have
    --     been leaving the inconsistency in, since the liaison exclusion rests
    --     on exactly the same argument.
    --
    -- This is reversible: if Plateau decides a reporter should see the analysis
    -- of their own incident, removing is_staff() here is the whole change.
    public.is_staff()
    AND NOT public.is_liaison()
    AND EXISTS (
      SELECT 1 FROM public.alerts a
       WHERE a.id = incident_ai_reports.alert_id
         AND public.alert_is_ours(a)
    )
  );

-- No INSERT, UPDATE or DELETE policy at all, for anybody signed in. The absence
-- is the control: with RLS enabled and no permissive policy, `authenticated`
-- cannot write a row whatever it tries. Stated explicitly so a later migration
-- does not read the gap as an oversight and "fix" it.
--
-- There are in fact TWO independent blocks here, which is worth knowing before
-- anybody relaxes either one. Verifying the behaviour test by deliberately
-- adding a permissive INSERT policy AND the table grant did not break it — the
-- insert still failed, on `permission denied for sequence
-- incident_ai_reports_id_seq`, because the BIGSERIAL default needs USAGE on the
-- sequence and only service_role has it. The test only failed once all three
-- were granted.
--
-- So a future migration that adds an INSERT policy will appear to have no
-- effect, and the reason will be forty lines away in a GRANT. That is a good
-- accident to have, and a terrible one to debug blind.
REVOKE INSERT, UPDATE, DELETE ON public.incident_ai_reports FROM anon, authenticated;
GRANT SELECT ON public.incident_ai_reports TO authenticated;
GRANT ALL ON public.incident_ai_reports TO service_role;
GRANT USAGE, SELECT ON SEQUENCE public.incident_ai_reports_id_seq TO service_role;

-- ── Reading the latest one back ────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.latest_ai_report(p_alert_id UUID, p_kind TEXT)
RETURNS TABLE (body TEXT, model TEXT, requested_by UUID, created_at TIMESTAMPTZ)
LANGUAGE sql
SECURITY INVOKER
STABLE
SET search_path = public, pg_temp
AS $$
  -- SECURITY INVOKER, so the SELECT policy above decides. A definer function
  -- here would hand every authenticated account the analysis of every incident
  -- in Plateau, straight through the scoping this policy relies on.
  SELECT r.body, r.model, r.requested_by, r.created_at
    FROM public.incident_ai_reports r
   WHERE r.alert_id = p_alert_id
     AND r.kind = p_kind
   ORDER BY r.created_at DESC, r.id DESC
   LIMIT 1;
$$;

COMMENT ON FUNCTION public.latest_ai_report(UUID, TEXT) IS
  'The most recent AI report of one kind for one incident. SECURITY INVOKER so '
  'the table''s own policy decides who may read it.';

REVOKE ALL ON FUNCTION public.latest_ai_report(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.latest_ai_report(UUID, TEXT) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 20261015000000_oversight_and_debrief.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261015000000_oversight_and_debrief.sql'; END $apply$;

-- A complaint about an officer must not be delivered to that officer.
--
-- ## Item 1: oversight routing
--
-- `alert_categories.dart` offers **Police brutality** as a reportable category,
-- with the subtypes Physical Assault, Extortion and Unlawful Arrest. A citizen
-- can file one from the app and, as of this migration's parent, over USSD.
--
-- It then routed exactly like a flood.
--
-- `alert_is_ours()` admits Operation Rainbow staff within their command, so a
-- complaint filed in Jos North reached Jos North ward command, Jos North LGA
-- command, and every RESPONDER posted to that LGA — which may include the
-- officer complained about. The responder picker offered them. The escalation
-- ladder climbed it rung by rung through the accused's own chain. And the
-- reporter's name and phone number travelled with it, because
-- `resolveReporterDetails()` puts them on the dossier.
--
-- So the system took a citizen's allegation that an officer assaulted them and
-- handed it to that officer's colleagues, with the complainant's number attached.
-- That is not a process defect. In Plateau State it is a safety problem for the
-- person who reported it.
--
-- ### The rule
--
-- An oversight matter is visible to HQ, to ADMIN, and to the person who reported
-- it. Nobody else — not the local ward, not the LGA, not a responder in the area,
-- and not an outside agency liaison, whose own personnel may be the subject.
--
-- It is also held out of the escalation ladder. Climbing UNIT → WARD → LGA is
-- precisely the wrong direction for this one kind of report: each rung is closer
-- to the accused. HQ owns it from the moment it arrives.
--
-- ### What this deliberately does NOT do
--
-- It does not hide the incident from the reporter, and it does not delete or
-- anonymise anything. The complaint is on the record, with the complainant's
-- details, available to HQ. Oversight requires knowing who complained; the
-- control is WHO can see it, not whether it exists.
--
-- ## Item 2: the debrief gets its own column
--
-- `mission_resolution_screen.dart` appended the responder's after-action notes
-- to `alerts.ai_summary`, tagged `[RESOLVED DEBRIEF]`. That column now carries
-- three unrelated kinds of content: AI triage notes, the
-- `[AI CLASSIFICATION APPLIED]` lines, and human debriefs. None of them can be
-- read back without string-parsing, and "what did the responder say happened"
-- is the one an inquiry asks.
--
-- A debrief is a person's account of what they did. It gets a column.

-- ── Which reports are oversight matters ────────────────────────────────────

CREATE OR REPLACE FUNCTION public.is_oversight_matter(p_type TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  -- Matched on the CATEGORY — the part of `type` before ' - ' — so every
  -- subtype is covered without listing them, and a new subtype added to
  -- alert_categories.dart is covered the day it ships rather than the day
  -- somebody remembers this function.
  SELECT upper(trim(split_part(coalesce(p_type, ''), ' - ', 1)))
         IN ('POLICE BRUTALITY', 'SECURITY PERSONNEL MISCONDUCT');
$$;

COMMENT ON FUNCTION public.is_oversight_matter(TEXT) IS
  'A complaint against security personnel. Matched on the category so new '
  'subtypes are covered automatically. These are routed to HQ only: every rung '
  'of the normal ladder is closer to the person complained about.';

-- ── Who may see one ───────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.alert_is_ours(p_alert public.alerts)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
  SELECT CASE
    -- A complaint about security personnel goes to HQ and the person who made
    -- it. Checked FIRST and exclusively: the clauses below would otherwise hand
    -- it to the accused's own command, which is the defect.
    WHEN public.is_oversight_matter(p_alert.type) THEN
      public.commands_whole_state()
      OR p_alert.reported_by = auth.uid()

    ELSE
      -- HQ and administrators: the state.
      public.commands_whole_state()
      -- The reporter, the lead, and every officer on the dispatched team.
      OR p_alert.reported_by = auth.uid()
      OR p_alert.assigned_to = auth.uid()
      OR auth.uid()::text = ANY (COALESCE(p_alert.assigned_responders, '{}'::text[]))
      -- Operation Rainbow staff, within their command.
      OR (public.is_staff() AND NOT public.is_liaison()
          AND (public.alert_in_my_area(p_alert)
               OR public.alert_delegated_to_my_lga(p_alert)))
      -- An outside agency: only what was handed to them.
      OR (public.is_liaison()
          AND upper(COALESCE(p_alert.escalated_to_agency, '')) = public.liaison_agency())
  END;
$$;

COMMENT ON FUNCTION public.alert_is_ours(public.alerts) IS
  'Whether the calling account has a part in this incident: HQ sees the state, '
  'everyone else sees their command plus their own work — EXCEPT a complaint '
  'against security personnel, which only HQ and the complainant may see.';

-- ── And out of the escalation ladder ──────────────────────────────────────

CREATE OR REPLACE FUNCTION public.awaiting_human_confirmation(p_alert public.alerts)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT
    -- A USSD report nobody has stood behind. See 20261011000000.
    (upper(coalesce(p_alert.arrived_via, '')) = 'USSD'
     AND p_alert.ussd_confirmed_at IS NULL)
    -- OR an oversight matter, at any tier, for ever. The ladder's whole purpose
    -- is to escalate towards the local command, and for this one kind of report
    -- every rung is closer to the person complained about. HQ owns it on
    -- arrival; there is nowhere useful for it to climb to.
    OR public.is_oversight_matter(p_alert.type);
$$;

COMMENT ON FUNCTION public.awaiting_human_confirmation(public.alerts) IS
  'Held out of the escalation ladder: an unconfirmed USSD report, or a complaint '
  'against security personnel. For the latter every rung of the ladder is closer '
  'to the accused, so it does not climb at all.';

-- Route new oversight matters to HQ on arrival rather than leaving them at UNIT
-- looking unowned.
CREATE OR REPLACE FUNCTION public.route_oversight_to_hq()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF public.is_oversight_matter(NEW.type) THEN
    NEW.assigned_tier    := 'HQ';
    NEW.tier_assigned_at := NOW();
    -- Cleared, not preserved. A complaint must never arrive pre-assigned to a
    -- responder in the area it was filed in — which is what the app's own
    -- default would do if the report were raised from a responder's handset.
    NEW.assigned_to        := NULL;
    NEW.assigned_responders := NULL;
    NEW.escalation_log := coalesce(NEW.escalation_log, '[]'::jsonb) || jsonb_build_object(
      'at',     to_char(NOW() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
      'by',     'SYSTEM',
      'action', 'OVERSIGHT_ROUTED',
      'reason', 'a complaint against security personnel is routed to HQ, not to the local command'
    );
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS route_oversight_to_hq_trg ON public.alerts;
CREATE TRIGGER route_oversight_to_hq_trg
  BEFORE INSERT ON public.alerts
  FOR EACH ROW EXECUTE FUNCTION public.route_oversight_to_hq();

COMMENT ON FUNCTION public.route_oversight_to_hq() IS
  'BEFORE INSERT: sends a complaint against security personnel to HQ and clears '
  'any assignment, so it can never arrive pre-assigned to a responder in the '
  'area it was filed in.';

-- Existing rows: move any already in the local chain.
UPDATE public.alerts
   SET assigned_tier = 'HQ',
       assigned_to = NULL,
       assigned_responders = NULL
 WHERE public.is_oversight_matter(type)
   AND status NOT IN ('RESOLVED', 'CANCELLED', 'FALSE_REPORT')
   AND (upper(coalesce(assigned_tier, '')) <> 'HQ'
        OR assigned_to IS NOT NULL
        OR assigned_responders IS NOT NULL);

CREATE INDEX IF NOT EXISTS alerts_oversight_idx
  ON public.alerts (created_at DESC)
  WHERE category IN ('Police brutality', 'Security personnel misconduct');

-- ── Item 2: the debrief ───────────────────────────────────────────────────

ALTER TABLE public.alerts
  ADD COLUMN IF NOT EXISTS debrief TEXT,
  ADD COLUMN IF NOT EXISTS debrief_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS debrief_at TIMESTAMPTZ;

COMMENT ON COLUMN public.alerts.debrief IS
  'The responder''s own account of what they did, in their words. Was appended '
  'to ai_summary tagged [RESOLVED DEBRIEF], mixed in with AI triage notes and '
  'classification lines — so "what did the responder say happened", the question '
  'an inquiry asks, needed string-parsing to answer.';

-- Backfill from the tag. Safe because `[RESOLVED DEBRIEF] ` is unambiguous and
-- was written by exactly one place; anything else in ai_summary is left alone.
UPDATE public.alerts a
   SET debrief = btrim(substring(line FROM '\[RESOLVED DEBRIEF\] (.*)$'))
  FROM (
    SELECT id, unnest(string_to_array(ai_summary, E'\n')) AS line
      FROM public.alerts
     WHERE ai_summary LIKE '%[RESOLVED DEBRIEF]%'
  ) src
 WHERE a.id = src.id
   AND src.line LIKE '[RESOLVED DEBRIEF]%'
   AND a.debrief IS NULL;

CREATE INDEX IF NOT EXISTS alerts_debriefed_idx
  ON public.alerts (debrief_at DESC)
  WHERE debrief IS NOT NULL;

-- ── Item 3: a real audit trail ────────────────────────────────────────────
--
-- The console's "System Tactical Audit History" read `chat_messages` — the
-- private conversations between dispatchers and responders. It showed no action
-- anybody had taken: not a dispatch, not an escalation, not a resolution, not a
-- classification applied, not a report marked false.
--
-- Those are all in `alerts.escalation_log`, a jsonb array appended to by every
-- action in the system. PR #2 suggested reading `alert_timeline` instead, and
-- that table does not exist in any migration — so the suggested fix would have
-- produced an empty screen.
--
-- SECURITY INVOKER, so `alert_is_ours()` scopes it. That matters more here than
-- anywhere: without it this function would hand every authenticated account the
-- action history of every incident in Plateau, including the oversight matters
-- the rest of this migration exists to protect.

CREATE OR REPLACE FUNCTION public.audit_trail(p_limit INTEGER DEFAULT 100)
RETURNS TABLE (
  alert_id   UUID,
  reference  TEXT,
  incident   TEXT,
  at         TIMESTAMPTZ,
  action     TEXT,
  actor      TEXT,
  detail     TEXT
)
LANGUAGE sql
SECURITY INVOKER
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT a.id,
         coalesce(a.public_reference, left(a.id::text, 8)),
         a.type,
         -- Entries have been written with two different key names over this
         -- schema's life ('at' as a formatted string, and an ISO timestamp), and
         -- a row whose timestamp cannot be parsed must still appear — an audit
         -- entry dropped for a formatting reason is the worst possible thing for
         -- this list to do quietly. Falls back to the incident's own time.
         coalesce(
           nullif(e.entry ->> 'at', '')::timestamptz,
           a.updated_at,
           a.created_at
         ),
         upper(coalesce(
           nullif(e.entry ->> 'action', ''),
           -- A tier move has no 'action' key; it is identified by carrying a
           -- from_tier. Without this, every automatic escalation in the system
           -- would read as 'UNKNOWN'.
           CASE WHEN e.entry ? 'from_tier' THEN 'ESCALATED' END,
           'UPDATED'
         )),
         coalesce(nullif(e.entry ->> 'by', ''), 'SYSTEM'),
         -- For a tier move, BOTH the tiers and the reason. The first version
         -- coalesced the reason first, so an automatic escalation read simply
         -- "TIMEOUT" — the word without the movement, which is the half that
         -- tells a reader nothing. Where an incident WENT is the point of the
         -- entry; why is the qualifier.
         CASE
           WHEN e.entry ? 'from_tier' THEN
             (e.entry ->> 'from_tier') || ' → ' || (e.entry ->> 'to_tier')
             || coalesce(' (' || nullif(e.entry ->> 'reason', '') || ')', '')
           ELSE coalesce(nullif(e.entry ->> 'reason', ''), '')
         END
    FROM public.alerts a
    CROSS JOIN LATERAL jsonb_array_elements(
           CASE WHEN jsonb_typeof(a.escalation_log) = 'array'
                THEN a.escalation_log ELSE '[]'::jsonb END
         ) AS e(entry)
   ORDER BY 4 DESC
   LIMIT greatest(1, least(coalesce(p_limit, 100), 500));
$$;

COMMENT ON FUNCTION public.audit_trail(INTEGER) IS
  'What was actually DONE to incidents, flattened out of alerts.escalation_log. '
  'The console previously showed chat_messages under this heading, which '
  'contained no action anybody had taken. SECURITY INVOKER so alert_is_ours() '
  'scopes it — including keeping oversight matters out of it.';

REVOKE ALL ON FUNCTION public.audit_trail(INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.audit_trail(INTEGER) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 20261016000000_telemetry_policy_is_not_public.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261016000000_telemetry_policy_is_not_public.sql'; END $apply$;

-- ============================================================================
-- The one policy on this database that PUBLIC could reach
--
-- A production paste reported:
--
--   *** FAIL *** | no policy grants anon or public anything
--
-- and it was this, alone:
--
--   telemetry | telemetry_select_geo_lga_scoped | SELECT | {public}
--
-- `{public}` is not a role somebody chose. It is what PostgreSQL records when a
-- CREATE POLICY has no `TO` clause, and PUBLIC includes `anon` — so the policy
-- was reachable, in principle, by anyone holding the anonymous key.
--
-- ## Why it survived the migration that exists to prevent this
--
-- 20260813000000_rls_least_privilege.sql drops prior policies BY EXACT NAME, and
-- `telemetry_select_geo_lga_scoped` is not in its list — it cannot be, because
-- the policy is created by 20260725000000_v6_geo_lga_scoping_staging.sql, which
-- is a file 20260813 had no reason to know about. Checked: 0 occurrences of the
-- name in that migration.
--
-- ## Why no test caught it
--
-- verify_rls_migration.sh asserts that no policy grants anon or public — and it
-- passes. The assertion sits immediately after 20260813 is applied, which is
-- eleven migrations before 20260725 is applied, so at the moment it looks the
-- policy does not exist yet. A check at one point in the history cannot answer a
-- question about the end state. That gate now also runs at the END of the
-- replay, after every migration, which is where it would have been found.
--
-- ## What was actually at risk
--
-- Less than the shape suggests, and more than nothing. `telemetry` is where
-- citizens' positions are written. The policy's own qualifier opens with
-- `auth.role() = 'authenticated'`, and 20260813 separately REVOKEs telemetry's
-- table privileges from anon — on the live database, `has_table_privilege('anon',
-- 'telemetry', 'SELECT')` is false. So two independent things had to be true
-- before this leaked, and only one of them was.
--
-- But the privilege half is one `GRANT` away from being untrue: a click in the
-- dashboard's table editor, a migration written in a hurry, a restore from a
-- backup taken before 20260813. Defence in depth means the policy layer has to
-- hold on its own, and this one was relying on the layer beneath it.
--
-- ## What this changes
--
-- `TO authenticated`, and nothing else. The qualifier is copied across verbatim,
-- including the `auth.role() = 'authenticated'` test that is now redundant — a
-- redundant condition is cheaper than a behaviour change nobody asked for, and
-- the two express the same intent at different layers.
--
-- For a legitimate caller this is identical: the policy already demanded an
-- authenticated role. For anon it changes from "refused by the qualifier, if the
-- qualifier is reached" to "not applicable at all".
--
-- 20260725 itself is fixed in the same commit, so a staging database built after
-- today does not inherit it. This file is what repairs the databases that
-- already have it, because that file's guard is `IF NOT EXISTS` and correctly
-- does nothing where the policy is already present.
-- ============================================================================

-- ## Only where there is something to repair
--
-- A first version of this did an unconditional DROP ... IF EXISTS followed by a
-- plain CREATE, and broke every database that had never applied 20260725:
--
--   ERROR:  function public.normalise_lga(text) does not exist
--
-- `normalise_lga` comes from 20260725 as well, and scripts/bootstrap_staging.sql
-- deliberately excludes that file (it is staging-only and does not replay from
-- zero). So the CREATE referenced a function that was not there, the bootstrap
-- is one transaction, and the whole thing rolled back.
--
-- The policy and the function arrive together, so the policy's presence is the
-- right condition: where it exists there is something to fix and the function is
-- there to fix it with, and where it does not, this migration has no work.
DO $mig$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
     WHERE schemaname = 'public'
       AND tablename  = 'telemetry'
       AND policyname = 'telemetry_select_geo_lga_scoped'
  ) THEN
    RAISE NOTICE
      'telemetry_select_geo_lga_scoped is not on this database (20260725 was '
      'never applied here) — nothing to repair';
    RETURN;
  END IF;

  -- Defensive, and it raises rather than warns on purpose: the two came from one
  -- file, so their absence together is an inconsistency worth stopping on, and
  -- dropping a policy this cannot then recreate would leave telemetry with no
  -- read path at all.
  IF to_regprocedure('public.normalise_lga(text)') IS NULL THEN
    RAISE EXCEPTION
      'telemetry_select_geo_lga_scoped exists but public.normalise_lga(text) '
      'does not — refusing to drop a policy I cannot recreate';
  END IF;

  DROP POLICY "telemetry_select_geo_lga_scoped" ON public.telemetry;

  EXECUTE $pol$
    CREATE POLICY "telemetry_select_geo_lga_scoped"
      ON public.telemetry
      FOR SELECT
      TO authenticated
      USING (
        auth.role() = 'authenticated'
        AND EXISTS (
          SELECT 1 FROM public.profiles caller
          WHERE caller.id = auth.uid()
            AND caller.role IN ('FIELD_OFFICER', 'WARD_OFFICER', 'LGA_OFFICER')
            AND caller.geo_lga IS NOT NULL
            AND TRIM(caller.geo_lga) <> ''
            AND EXISTS (
              SELECT 1 FROM public.profiles target
              WHERE target.id = telemetry.user_id
                AND public.normalise_lga(target.geo_lga)
                  = public.normalise_lga(caller.geo_lga)
            )
        )
      )
  $pol$;

  -- Inside the guard too. Left outside it, this failed with `policy
  -- "telemetry_select_geo_lga_scoped" for table "telemetry" does not exist` on
  -- every database the guard had just correctly skipped.
  EXECUTE $cmt$
    COMMENT ON POLICY "telemetry_select_geo_lga_scoped" ON public.telemetry IS
      'An officer may read the positions of citizens posted to their own LGA. '
      'Scoped TO authenticated: the same policy without a TO clause was recorded '
      'as TO PUBLIC, which includes anon, and 20260813 could not drop it by name '
      'because it comes from a file that migration predates.'
  $cmt$;

  RAISE NOTICE 'telemetry_select_geo_lga_scoped is now scoped TO authenticated';
END $mig$;

-- Say so in the log, because a policy replacement leaves no other trace and the
-- operator running this is doing it in response to a failed check. Reports on
-- the whole schema, so it is useful whether or not the guard above did anything.
DO $$
DECLARE reaches_public INTEGER;
BEGIN
  SELECT count(*) INTO reaches_public
    FROM pg_policies
   WHERE schemaname = 'public'
     AND ('anon' = ANY(roles) OR 'public' = ANY(roles));

  IF reaches_public = 0 THEN
    RAISE NOTICE 'telemetry_select_geo_lga_scoped is now TO authenticated; no policy in public reaches anon or public';
  ELSE
    RAISE WARNING 'telemetry_select_geo_lga_scoped fixed, but % other policy/policies still reach anon or public — run scripts/rls_inventory.sql', reaches_public;
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 20261017000000_the_hand_applied_era_is_in_the_history.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261017000000_the_hand_applied_era_is_in_the_history.sql'; END $apply$;

-- ============================================================================
-- Production has objects this repository cannot build. Close that.
--
-- The v2–v6 era (20260721 … 20260725) was applied to production BY HAND, before
-- the project kept a migration history, and written down as files afterwards.
-- Those files cannot be replayed from zero — v2 calls auth.jwt() before the
-- shim defines it, and v5 builds a policy on profiles.badge_number, a column
-- 20260903000004 adds eleven migrations later — so scripts/bootstrap_staging.sql
-- and scripts/verify_rls_migration.sh deliberately exclude them.
--
-- The consequence is that the live database and every database this repository
-- can build have different schemas, and the difference is invisible until it
-- decides something.
--
-- ## Three times it already has
--
-- 1. A 428C9 error. `INSERT INTO alerts` with no column list is refused at the
--    FIRST generated column in ordinal order. On production that is `lga` at
--    28; on a repo-built database `category` at 33 was the only one. The same
--    statement reports a different column name on each, which is a diagnosis
--    sent in the wrong direction.
--
--    This migration does NOT fix that, and an earlier draft of this comment
--    claimed it did. It converges the column SET, not the ordinal ORDER:
--    attribute numbers are assigned when a column is added, so the mirrors land
--    after `category` here and before it on production. The behaviour test
--    prints which column comes first precisely so nobody re-derives the wrong
--    expectation — it still reads `category` on a fresh database.
--
--    What actually closes that defect is
--    scripts/check_generated_column_inserts.py, which refuses any insert into a
--    table with a generated column that has no explicit column list. The error
--    cannot be reached from this repository at all, so which name it would have
--    reported stops mattering.
--
-- 2. `telemetry_select_geo_lga_scoped` sat on production as TO PUBLIC for weeks
--    while verify_rls_migration.sh asserted no policy reaches anon or public —
--    and passed, because the policy does not exist in the schema it replays.
--    Fixed in 20261016000000; the assertion now also runs after the full
--    replay.
--
-- 3. dashboard/page.tsx carries a comment stating that `lga`, `ward` and
--    `sector_id` are not columns on profiles and that PostgREST therefore
--    rejected a query naming them. All three exist on production — v2 adds
--    them. The query it describes would have worked there. The fix was right
--    for other reasons (it was missing fields its consumers read), but the
--    reasoning written into the file is wrong, and it was wrong because it was
--    checked against the repository rather than the database.
--
-- ## What this adds, and why each one
--
-- Everything from that era that can CHANGE BEHAVIOUR or MISLEAD A DIAGNOSIS.
-- Non-destructive: every statement is guarded, so on production this migration
-- is a no-op that prints what it found.
--
--   set_updated_at() + trg_alerts_updated_at
--       Production maintains alerts.updated_at automatically. A repo-built
--       database has the COLUMN (base schema, DEFAULT NOW()) and no trigger, so
--       updated_at only moves where code assigns it. "When did this incident
--       last change" answers differently on the two, which is the sort of thing
--       an inquiry asks.
--
--   normalise_lga(text)
--       Compares LGA strings case- and whitespace-insensitively. Referenced by
--       the telemetry policy below and by 20261016000000's guard.
--
--   telemetry_select_geo_lga_scoped
--       An officer may read the positions of citizens posted to their own LGA.
--       This is an access-control rule: a staging database without it refuses
--       reads production allows, so any test of who-can-see-what is answering
--       about a different system. Created TO authenticated, never without a TO
--       clause — without one PostgreSQL records TO PUBLIC, which includes anon,
--       which is exactly what 20261016000000 had to repair.
--
--   alerts.lga / ward / pu, profiles.lga / ward
--       Generated mirrors of the geo_* columns, from v2 ("shorthand aliases
--       used by some Flutter queries"). Nothing in either app reads them today
--       — checked — but they are what makes ordinal 28 generated on production,
--       and defect 1 above is what that costs.
--
--   alerts.assigned_to_uid, alerts.post_sos_status, profiles.sector_id
--       Plain columns from the same era. Unused, and added for the same reason:
--       a column that exists on one side and not the other turns `SELECT *`
--       into two different queries.
--
-- ## What this deliberately does NOT add
--
-- `is_hq_or_admin()` and `is_responder()`, from v5. They exist on production and
-- are referenced by NOTHING — their only callers were the v5-era policies, and
-- 20260813000000_rls_least_privilege.sql drops all of those by name. Adding dead
-- SECURITY DEFINER functions to the canonical schema to match dead functions on
-- production is not convergence, it is propagation.
--
-- They are recorded as a known difference in scripts/check_schema_convergence.py
-- so the gate does not fail on them, and they are safe to drop on production
-- whenever somebody is confident nothing outside this repository calls them:
--
--     DROP FUNCTION IF EXISTS public.is_hq_or_admin();
--     DROP FUNCTION IF EXISTS public.is_responder();
--
-- That is left for a human, because "nothing in the repository calls it" and
-- "nothing calls it" are different claims while the legacy Firebase functions
-- are still deployed.
--
-- ## The alternative, not taken
--
-- Converging DOWNWARD — dropping the five generated mirrors and three plain
-- columns from production — gives a smaller schema and removes the ordinal
-- hazard outright. It is not done here because dropping columns from a live
-- emergency database on the strength of "nothing in this repository reads them"
-- is not a call to make on a migration's own authority, and the same legacy
-- deployment that blocks the DROP above blocks this one.
-- ============================================================================

-- ── updated_at, maintained by the database ──────────────────────────────────

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.set_updated_at() IS
  'BEFORE UPDATE: stamps updated_at. From the hand-applied v2 era; brought into '
  'the migration history by 20261017000000 so a repo-built database maintains '
  'updated_at the way production does.';

DROP TRIGGER IF EXISTS trg_alerts_updated_at ON public.alerts;
CREATE TRIGGER trg_alerts_updated_at
  BEFORE UPDATE ON public.alerts
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ── LGA comparison helper ───────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.normalise_lga(lga TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT LOWER(TRIM(lga));
$$;

COMMENT ON FUNCTION public.normalise_lga(TEXT) IS
  'Lowercase and trim, so "Jos North" and "jos north " compare equal. Not the '
  'same as public.geo_key(), which additionally folds trailing Roman numerals '
  'and is what ward names are compared on.';

-- ── The era's columns ───────────────────────────────────────────────────────
--
-- IF NOT EXISTS throughout: on production every one of these is already there
-- and this is a no-op. The generated mirrors cannot be added by a plain ALTER
-- on a table that already has them, which is the whole reason for the guard.

ALTER TABLE public.alerts
  ADD COLUMN IF NOT EXISTS assigned_to_uid UUID,
  ADD COLUMN IF NOT EXISTS post_sos_status TEXT,
  ADD COLUMN IF NOT EXISTS lga  TEXT GENERATED ALWAYS AS (geo_lga)  STORED,
  ADD COLUMN IF NOT EXISTS ward TEXT GENERATED ALWAYS AS (geo_ward) STORED,
  ADD COLUMN IF NOT EXISTS pu   TEXT GENERATED ALWAYS AS (geo_pu)   STORED;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS sector_id TEXT,
  ADD COLUMN IF NOT EXISTS lga  TEXT GENERATED ALWAYS AS (geo_lga)  STORED,
  ADD COLUMN IF NOT EXISTS ward TEXT GENERATED ALWAYS AS (geo_ward) STORED;

COMMENT ON COLUMN public.alerts.lga IS
  'Generated mirror of geo_lga, from the hand-applied v2 era. Read by nothing '
  'in either app. Present so that production and a repo-built database agree: a '
  'generated column changes which name a 428C9 error reports, because PostgreSQL '
  'names the FIRST generated column in an insert''s target list.';

-- ── The officer-scoped telemetry read ───────────────────────────────────────
--
-- Guarded so this does not fight 20261016000000, which repairs the TO PUBLIC
-- version on databases that have it. Here the job is the opposite: create it,
-- correctly, where it is absent.

DO $mig$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_policies
     WHERE schemaname = 'public'
       AND tablename  = 'telemetry'
       AND policyname = 'telemetry_select_geo_lga_scoped'
  ) THEN
    RAISE NOTICE 'telemetry_select_geo_lga_scoped already exists — left alone '
                 '(20261016000000 owns its scoping)';
    RETURN;
  END IF;

  EXECUTE $pol$
    CREATE POLICY "telemetry_select_geo_lga_scoped"
      ON public.telemetry
      FOR SELECT
      TO authenticated
      USING (
        auth.role() = 'authenticated'
        AND EXISTS (
          SELECT 1 FROM public.profiles caller
          WHERE caller.id = auth.uid()
            AND caller.role IN ('FIELD_OFFICER', 'WARD_OFFICER', 'LGA_OFFICER')
            AND caller.geo_lga IS NOT NULL
            AND TRIM(caller.geo_lga) <> ''
            AND EXISTS (
              SELECT 1 FROM public.profiles target
              WHERE target.id = telemetry.user_id
                AND public.normalise_lga(target.geo_lga)
                  = public.normalise_lga(caller.geo_lga)
            )
        )
      )
  $pol$;
  RAISE NOTICE 'Created telemetry_select_geo_lga_scoped, scoped TO authenticated';
END $mig$;

-- ── Say what converged ──────────────────────────────────────────────────────

DO $$
DECLARE
  cols INTEGER;
  reaches_public INTEGER;
  has_trigger BOOLEAN;
BEGIN
  SELECT count(*) INTO cols
    FROM pg_attribute a
    JOIN pg_class c     ON c.oid = a.attrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public'
     AND ((c.relname = 'alerts'   AND a.attname IN ('lga','ward','pu','assigned_to_uid','post_sos_status'))
       OR (c.relname = 'profiles' AND a.attname IN ('lga','ward','sector_id')))
     AND a.attnum > 0 AND NOT a.attisdropped;

  SELECT EXISTS (
    SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
     WHERE c.relname = 'alerts' AND t.tgname = 'trg_alerts_updated_at'
  ) INTO has_trigger;

  SELECT count(*) INTO reaches_public
    FROM pg_policies
   WHERE schemaname = 'public'
     AND ('anon' = ANY(roles) OR 'public' = ANY(roles));

  RAISE NOTICE 'era columns present: % of 8; updated_at trigger: %; policies reaching anon/public: %',
    cols, has_trigger, reaches_public;

  IF cols <> 8 OR NOT has_trigger THEN
    RAISE EXCEPTION 'convergence incomplete: % of 8 columns, trigger %', cols, has_trigger;
  END IF;
  IF reaches_public <> 0 THEN
    RAISE WARNING '% policy/policies reach anon or public — run scripts/rls_inventory.sql', reaches_public;
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 20261018000000_the_mirrors_and_two_dead_functions_are_gone.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261018000000_the_mirrors_and_two_dead_functions_are_gone.sql'; END $apply$;

-- ============================================================================
-- Converge DOWNWARD: drop the generated mirrors and the two uncalled functions
--
-- 20261017000000 brought the hand-applied v2–v6 era into the migration history
-- so that production and a repo-built database agree. It converged UPWARD —
-- adding to the repository what production happened to have — and said so:
--
--   > Converging DOWNWARD … gives a smaller schema and removes the ordinal
--   > hazard outright. It is not done here because dropping columns from a live
--   > emergency database on the strength of "nothing in this repository reads
--   > them" is not a call to make on a migration's own authority.
--
-- It has now been made. This drops them.
--
--   alerts.lga, alerts.ward, alerts.pu        GENERATED mirrors of geo_*
--   profiles.lga, profiles.ward               GENERATED mirrors of geo_*
--   public.is_hq_or_admin()                   no callers
--   public.is_responder()                     no callers
--
-- ## Why this loses nothing
--
-- All five columns are `GENERATED ALWAYS AS (geo_x) STORED`. They hold no
-- information of their own — every value is `geo_lga`, `geo_ward` or `geo_pu`
-- copied verbatim. Dropping them destroys no data that is not still sitting in
-- the column beside it, and re-adding them is one ALTER if anything turns out to
-- want them.
--
-- The two functions were last called by the v5-era policies, and
-- 20260813000000_rls_least_privilege.sql drops all of those by name. Checked
-- file against file: nothing in any migration this repository applies references
-- either one.
--
-- ## Why this is safe to run, and what it will refuse to do
--
-- Every drop is RESTRICT — PostgreSQL's default, stated here because it is the
-- whole safety argument and `CASCADE` is one word away. RESTRICT means that if
-- anything at all depends on one of these — a view, an index, a policy, another
-- function — the drop FAILS and this migration aborts. CASCADE would succeed by
-- silently deleting that dependent, which on a database whose policies decide
-- who may read a kidnapping report is not a trade worth making.
--
-- Each drop is attempted in its own sub-transaction so that a refusal is
-- reported with the object's name and the migration stops, rather than leaving
-- the schema half-converged.
--
-- ## The risk that is NOT closed by this file
--
-- The legacy Firebase deployment. Two Cloud Functions still answer on public
-- URLs (finding C-6), nobody has confirmed what they read, and they are
-- Firebase-era code from exactly the period that created these columns — v2's
-- own comment calls them "shorthand aliases used by some Flutter queries".
--
-- If one of them selects `lga`, it will break: PostgREST rejects a query naming
-- a column that does not exist **in full**, so the function gets an error rather
-- than a row with a missing field. That is a real possibility and this migration
-- cannot test it from here.
--
-- It is also, on the evidence, an acceptable one: those functions are orphaned,
-- fire against a datastore nothing backs, and are slated for deletion
-- (README.md "Outstanding" #1). A dead function failing more loudly is not a
-- regression. But it is the reason the earlier migration would not do this
-- unasked, and if the console or the mobile app ever starts rejecting a profiles
-- or alerts query after this is applied, this file is the first place to look.
--
-- Nothing in the current apps reads them — checked across every .dart, .ts and
-- .tsx file, and across every policy, index and view in the migrations.
--
-- ## One wart, deliberately left
--
-- 20261017000000 still ADDs these columns, and this file drops them again. On a
-- fresh database that is an add-then-drop; on a re-paste of
-- scripts/apply_all_migrations.sql it happens once per paste.
--
-- The alternative is editing 20261017000000 to stop adding them, which is
-- rewriting a migration that is already merged and may already have been
-- applied — and if it HAS been applied, editing it leaves the columns on that
-- database for ever, because nothing would then remove them. The add-then-drop
-- is honest about the order the decisions were made in, and it costs one ALTER
-- on `alerts` per paste. Worth collapsing once production has this applied and
-- the history can be flattened safely; not worth the ambiguity before then.
-- ============================================================================

DO $mig$
DECLARE
  target  RECORD;
  dropped INTEGER := 0;
  absent  INTEGER := 0;
BEGIN
  -- ── The generated mirrors ─────────────────────────────────────────────────
  FOR target IN
    SELECT * FROM (VALUES
      ('alerts',   'lga'),
      ('alerts',   'ward'),
      ('alerts',   'pu'),
      ('profiles', 'lga'),
      ('profiles', 'ward')
    ) AS t(tbl, col)
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_attribute a
        JOIN pg_class c     ON c.oid = a.attrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname = 'public' AND c.relname = target.tbl
         AND a.attname = target.col AND a.attnum > 0 AND NOT a.attisdropped
    ) THEN
      absent := absent + 1;
      CONTINUE;
    END IF;

    -- Refuse to drop anything that is NOT a generated mirror. If a column of
    -- this name is holding independent values, it is not the column this
    -- migration is about and dropping it would destroy data.
    IF NOT EXISTS (
      SELECT 1 FROM pg_attribute a
        JOIN pg_class c     ON c.oid = a.attrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname = 'public' AND c.relname = target.tbl
         AND a.attname = target.col AND a.attgenerated = 's'
    ) THEN
      RAISE EXCEPTION
        'public.%.% exists but is NOT a stored generated column. This migration '
        'drops mirrors of geo_*, which hold no information of their own. A plain '
        'column of this name holds data and is not dropped by this file.',
        target.tbl, target.col;
    END IF;

    BEGIN
      EXECUTE format('ALTER TABLE public.%I DROP COLUMN %I RESTRICT',
                     target.tbl, target.col);
      dropped := dropped + 1;
    EXCEPTION
      WHEN dependent_objects_still_exist THEN
        RAISE EXCEPTION
          'public.%.% cannot be dropped: something depends on it (%). Nothing '
          'has been changed. Find the dependent with the query at the bottom of '
          'this file; CASCADE would delete it silently, which is why this is '
          'RESTRICT.', target.tbl, target.col, SQLERRM;
    END;
  END LOOP;

  RAISE NOTICE 'generated mirrors: % dropped, % already absent', dropped, absent;

  -- ── The two uncalled functions ────────────────────────────────────────────
  --
  -- RESTRICT again, and it matters more here: DROP FUNCTION ... CASCADE deletes
  -- every policy whose expression calls the function. If one of these turns out
  -- to still back a policy, this must fail, not quietly remove the policy and
  -- leave the table readable by whatever remains.
  FOR target IN
    SELECT * FROM (VALUES ('is_hq_or_admin'), ('is_responder')) AS t(fn)
  LOOP
    IF to_regprocedure(format('public.%s()', target.fn)) IS NULL THEN
      RAISE NOTICE 'public.%() is already absent', target.fn;
      CONTINUE;
    END IF;
    BEGIN
      EXECUTE format('DROP FUNCTION public.%I() RESTRICT', target.fn);
      RAISE NOTICE 'dropped public.%()', target.fn;
    EXCEPTION
      WHEN dependent_objects_still_exist THEN
        RAISE EXCEPTION
          'public.%() cannot be dropped: something still depends on it (%). '
          'Nothing has been changed — and this is the case the RESTRICT exists '
          'for, because CASCADE here would delete a POLICY.', target.fn, SQLERRM;
    END;
  END LOOP;
END $mig$;

-- ── Report the resulting shape ──────────────────────────────────────────────

DO $$
DECLARE
  gen_cols TEXT;
  leftover INTEGER;
BEGIN
  SELECT string_agg(a.attname, ', ' ORDER BY a.attnum) INTO gen_cols
    FROM pg_attribute a
    JOIN pg_class c     ON c.oid = a.attrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relname = 'alerts'
     AND a.attgenerated <> '' AND a.attnum > 0 AND NOT a.attisdropped;

  SELECT count(*) INTO leftover
    FROM pg_attribute a
    JOIN pg_class c     ON c.oid = a.attrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public'
     AND ((c.relname = 'alerts'   AND a.attname IN ('lga','ward','pu'))
       OR (c.relname = 'profiles' AND a.attname IN ('lga','ward')))
     AND a.attnum > 0 AND NOT a.attisdropped;

  IF leftover <> 0 THEN
    RAISE EXCEPTION 'convergence incomplete: % mirror column(s) remain', leftover;
  END IF;

  RAISE NOTICE 'alerts generated columns now: %', coalesce(gen_cols, '(none)');
  RAISE NOTICE 'the mirrors are gone; geo_lga, geo_ward and geo_pu are the only '
               'place the geography lives, which is what every app already reads';
END $$;

-- ── If a drop above was refused, this names the dependent ───────────────────
--
-- Read-only. Run it, read what comes back, and decide whether the dependent
-- should be removed first or whether the column should stay.
--
--   SELECT DISTINCT
--          dependent.relname     AS dependent_object,
--          dependent.relkind     AS kind,   -- r table, v view, i index, m matview
--          a.attname             AS our_column
--     FROM pg_depend d
--     JOIN pg_rewrite r      ON r.oid = d.objid
--     JOIN pg_class dependent ON dependent.oid = r.ev_class
--     JOIN pg_attribute a    ON a.attrelid = d.refobjid AND a.attnum = d.refobjsubid
--     JOIN pg_class ours     ON ours.oid = d.refobjid
--     JOIN pg_namespace n    ON n.oid = ours.relnamespace
--    WHERE n.nspname = 'public'
--      AND ours.relname IN ('alerts', 'profiles')
--      AND a.attname IN ('lga', 'ward', 'pu');
--
-- And for the functions:
--
--   SELECT p.proname, pg_get_functiondef(p.oid)
--     FROM pg_policies pol
--     JOIN pg_proc p ON p.proname IN ('is_hq_or_admin', 'is_responder')
--    WHERE pol.qual ILIKE '%' || p.proname || '%'
--       OR pol.with_check ILIKE '%' || p.proname || '%';

-- ----------------------------------------------------------------------------
-- 20261019000000_the_audit_trail_names_who_acted.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261019000000_the_audit_trail_names_who_acted.sql'; END $apply$;

-- ============================================================================
-- OPERATION RAINBOW — THE AUDIT TRAIL NAMES WHO ACTED
--
-- `audit_trail()` reads the actor out of each escalation_log entry as
--
--     coalesce(nullif(e.entry ->> 'by', ''), 'SYSTEM')
--
-- and NOTHING A PERSON DOES WRITES 'by'.
--
--   writer                                        key          actor shown
--   ------------------------------------------    ----------   -----------
--   escalate_overdue_alerts()  (the timeout job)  'by'         SYSTEM      ✓
--   the notification outbox trigger               'by'         SYSTEM      ✓
--   confirm_ussd_report() / mark_false_report()   'by'         the uuid    ✓
--   alert-actions.ts escalateAlert  (HQ console)  'by_email'   SYSTEM      ✗
--   agent_dashboard_screen.dart     (a handset)   'by_email'   SYSTEM      ✗
--
-- So the audit trail inverted responsibility. Every escalation an officer
-- performed — from the HQ console or from their own handset — was attributed to
-- the system, and the only accurate attributions in the list were the machine's
-- own. On a screen whose entire purpose is to say who did what, that is worse
-- than showing nothing: a reader cannot tell an automatic timeout from a
-- commander's decision, and the commander's decision is the one somebody will
-- later be asked to account for.
--
-- The column comment on `alerts.escalation_log`, written in 20260722000000, has
-- said `by_email` since the beginning:
--
--     'Append-only structured log: [{from_tier, to_tier, to_officer_id,
--      to_officer_name, reason, notes, by_email, at}]'
--
-- so the reader is what disagreed with the documented shape, not the writers.
--
-- WHY THIS IS NOT FIXED BY CHANGING THE WRITERS
--
-- Production holds entries of both shapes, written over this schema's whole
-- life, and the log is append-only: a chain of custody that is rewritten is not
-- one. Both keys therefore have to be readable, forever. `by` is tried first so
-- the SQL writers' explicit value keeps precedence.
--
-- WHY THE BEHAVIOUR TEST DID NOT CATCH IT
--
-- `scripts/oversight_behaviour_test.sql` plants its fixture entry as
-- `{"from_tier":"UNIT","to_tier":"WARD","reason":"TIMEOUT","by":"SYSTEM",…}` —
-- the machine's shape, the one key that worked. It asserted the action and the
-- tiers and never the actor. Both shapes are now planted and the actor is
-- asserted for each.
--
-- Idempotent: CREATE OR REPLACE, no data is touched.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.audit_trail(p_limit INTEGER DEFAULT 100)
RETURNS TABLE (
  alert_id   UUID,
  reference  TEXT,
  incident   TEXT,
  at         TIMESTAMPTZ,
  action     TEXT,
  actor      TEXT,
  detail     TEXT
)
LANGUAGE sql
SECURITY INVOKER
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT a.id,
         coalesce(a.public_reference, left(a.id::text, 8)),
         a.type,
         -- Entries have been written with two different key names over this
         -- schema's life ('at' as a formatted string, and an ISO timestamp), and
         -- a row whose timestamp cannot be parsed must still appear — an audit
         -- entry dropped for a formatting reason is the worst possible thing for
         -- this list to do quietly. Falls back to the incident's own time.
         coalesce(
           nullif(e.entry ->> 'at', '')::timestamptz,
           a.updated_at,
           a.created_at
         ),
         upper(coalesce(
           nullif(e.entry ->> 'action', ''),
           -- A tier move has no 'action' key; it is identified by carrying a
           -- from_tier. Without this, every automatic escalation in the system
           -- would read as 'UNKNOWN'.
           CASE WHEN e.entry ? 'from_tier' THEN 'ESCALATED' END,
           'UPDATED'
         )),
         -- WHO. `by` is what the SQL writers set, explicitly, to 'SYSTEM' or to
         -- auth.uid(); `by_email` is what both apps set, and is the key the
         -- column's own comment has always documented. Reading only the first
         -- attributed every human action to the system — see the header.
         coalesce(
           nullif(e.entry ->> 'by', ''),
           nullif(e.entry ->> 'by_email', ''),
           'SYSTEM'
         ),
         -- For a tier move, BOTH the tiers and the reason. The first version
         -- coalesced the reason first, so an automatic escalation read simply
         -- "TIMEOUT" — the word without the movement, which is the half that
         -- tells a reader nothing. Where an incident WENT is the point of the
         -- entry; why is the qualifier.
         CASE
           WHEN e.entry ? 'from_tier' THEN
             (e.entry ->> 'from_tier') || ' → ' || (e.entry ->> 'to_tier')
             || coalesce(' (' || nullif(e.entry ->> 'reason', '') || ')', '')
           ELSE coalesce(nullif(e.entry ->> 'reason', ''), '')
         END
    FROM public.alerts a
    CROSS JOIN LATERAL jsonb_array_elements(
           CASE WHEN jsonb_typeof(a.escalation_log) = 'array'
                THEN a.escalation_log ELSE '[]'::jsonb END
         ) AS e(entry)
   ORDER BY 4 DESC
   LIMIT greatest(1, least(coalesce(p_limit, 100), 500));
$$;

COMMENT ON FUNCTION public.audit_trail(INTEGER) IS
  'What was actually DONE to incidents, flattened out of alerts.escalation_log. '
  'The console previously showed chat_messages under this heading, which '
  'contained no action anybody had taken. SECURITY INVOKER so alert_is_ours() '
  'scopes it — including keeping oversight matters out of it. The actor is read '
  'from `by` then `by_email`: the SQL writers set the first, both apps set the '
  'second, and reading only `by` attributed every human action to SYSTEM.';

-- ----------------------------------------------------------------------------
-- 20261020000000_a_handset_that_leaves_mid_emergency.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261020000000_a_handset_that_leaves_mid_emergency.sql'; END $apply$;

-- ============================================================================
-- A HANDSET THAT SIGNS OUT WHILE ITS EMERGENCY IS STILL OPEN
-- ============================================================================
--
-- `AuthService.signOut()` stopped location tracking first, deliberately, and
-- said why:
--
--     Signing out is the clearest statement a person can make that they are
--     done being observed, and it was the one action that did not stop it.
--
-- That is right about a person signing out of their own phone. It is wrong
-- about the one case the duress design exists for. A duress PIN tells the
-- person their alarm is cancelled and KEEPS TRACKING RUNNING, because they may
-- still be in danger — and the lock screen offers a sign-out that needs no code
-- at all. So whoever is holding the phone could end the tracking of a live
-- duress alert without knowing any PIN, and HQ saw silence indistinguishable
-- from a flat battery.
--
-- Two rules collided and nothing recorded which won. Now: signing out ends the
-- session and retires the SMS key as before, a RESPONDER's patrol track still
-- stops (they are off duty), and an SOS track keeps running until the incident
-- closes or the twelve-hour ceiling in `sosTrackingMaxAge` expires.
--
-- This column is the other half: the loss of the app has to be visible as a
-- FACT rather than inferred from a gap. An operator watching a track go quiet
-- cannot tell a captor from a dead phone; one that says "this handset signed
-- out at 19:42, tracking continues" can.
--
-- Written by the handset itself, in the window before the session is cleared,
-- so `alerts_update_own_or_ours` covers it: `reported_by = auth.uid()`.
-- Best-effort by design — a phone being switched off must not have the sign-out
-- blocked on a network write.
-- ============================================================================

BEGIN;

ALTER TABLE public.alerts
  ADD COLUMN IF NOT EXISTS device_signed_out_at TIMESTAMPTZ;

COMMENT ON COLUMN public.alerts.device_signed_out_at IS
  'When the reporting handset signed out while this incident was still open. '
  'Tracking continues regardless; this says the app is gone, so an operator can '
  'tell that from a dead battery. Written by the handset before its session '
  'ends, best-effort.';

-- The console reads it on one incident at a time, from the dossier, so no index
-- is warranted. Said out loud because the next column added here will be
-- tempted to copy an index it does not need either.

COMMIT;

-- ----------------------------------------------------------------------------
-- 20261021000000_an_lga_can_hand_an_incident_to_a_ward.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261021000000_an_lga_can_hand_an_incident_to_a_ward.sql'; END $apply$;

-- ============================================================================
-- AN LGA COMMANDER CAN HAND AN INCIDENT TO A WARD
-- ============================================================================
--
-- The chain only ever climbed. `next_tier()` is UNIT -> WARD -> LGA -> HQ and
-- `escalationTargetFor()` offers no choice of target, so an LGA commander's
-- single escalation was upward to HQ. The one sideways move that existed was
-- HQ handing an incident DOWN to an LGA by name, which `to_lga` in the last
-- escalation entry records and `alert_delegated_to_my_lga()` grants.
--
-- There was no `to_ward` anywhere in the codebase. So an LGA commander who
-- judged that a neighbouring ward should take an incident — because the
-- roadblock is on their side of the boundary, or because the ward it sits in
-- has nobody free — had no way to say so. They could assign individual
-- responders across the LGA, but the other ward's COMMANDER never owned it.
--
-- This is the LGA hand-down, one rung lower, and deliberately the same shape:
-- the target named in the last escalation entry, a function that grants it, and
-- `alert_is_ours()` consulting that function. Nothing new to learn.
--
-- WHY BOTH THE WARD AND THE LGA ARE COMPARED
--
-- `alert_delegated_to_my_lga()` compares one name, because an LGA name is
-- unique in Plateau. Ward names are not: a ward called the same thing can exist
-- in two LGAs, and granting on the ward name alone would hand the incident to a
-- commander in a different LGA who happens to share it. So the LGA must agree
-- too, unless the entry did not record one.
--
-- WHY AN EXACT COMPARISON IS ENOUGH
--
-- The Dart side compares places through `geoKey`, which collapses whitespace,
-- because the app writes a ward resolved from the GPS centroid asset
-- ('GINDIRI  I') while an officer is posted from the tactical map
-- ('GINDIRI  1'). That mismatch cannot arise here: the ward written into
-- `to_ward` is chosen from the tactical map, and the commander's `geo_ward` is
-- posted from the same tactical map. Both sides come from one source.
-- ============================================================================

BEGIN;

-- ── Was it handed to my ward ────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.alert_delegated_to_my_ward(p_alert public.alerts)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
  WITH me AS (
    SELECT nullif(upper(trim(coalesce(geo_lga,  ''))), '') AS lga,
           nullif(upper(trim(coalesce(geo_ward, ''))), '') AS ward
      FROM public.profiles
     WHERE id = auth.uid()
  ),
  handed AS (
    SELECT nullif(upper(trim(coalesce(
             (p_alert.escalation_log
                -> jsonb_array_length(p_alert.escalation_log) - 1)
               ->> 'to_ward', ''))), '') AS ward,
           nullif(upper(trim(coalesce(
             (p_alert.escalation_log
                -> jsonb_array_length(p_alert.escalation_log) - 1)
               ->> 'to_lga', ''))), '') AS lga
  )
  SELECT COALESCE(
    (SELECT ward FROM handed) IS NOT NULL
    AND (SELECT ward FROM handed) = (SELECT ward FROM me)
    -- An entry that named no LGA is trusted on the ward alone; one that named
    -- an LGA must agree with the caller's.
    AND ((SELECT lga FROM handed) IS NULL
         OR (SELECT lga FROM handed) = (SELECT lga FROM me)),
    false
  );
$$;

COMMENT ON FUNCTION public.alert_delegated_to_my_ward(public.alerts) IS
  'Whether the last escalation entry handed this incident to the calling '
  'account''s ward. The LAST entry only: the log is append-only, so an earlier '
  'handover has been superseded. The LGA must agree too, because ward names '
  'are not unique across LGAs.';

REVOKE ALL ON FUNCTION public.alert_delegated_to_my_ward(public.alerts) FROM anon;

-- ── And the one question the policies ask ───────────────────────────────────
--
-- RESTATED FROM 20261015000000, NOT FROM 20261006000000.
--
-- `alert_is_ours()` has been replaced twice. 20261006000000 restates it as a
-- flat OR and says why — "so a replica built from these files in order gets the
-- same result whichever migration ran last" — and 20261015000000 then WRAPPED
-- it in a CASE whose first branch is exclusive:
--
--     WHEN public.is_oversight_matter(p_alert.type) THEN
--       public.commands_whole_state() OR p_alert.reported_by = auth.uid()
--
-- A complaint about security personnel goes to HQ and the complainant, and to
-- nobody else, because the ordinary clauses would hand it to the accused's own
-- command.
--
-- The first version of THIS migration copied the restatement idiom from
-- 20261006000000 — the older generation — and so dropped that CASE. Every
-- client test passed. `scripts/oversight_behaviour_test.sql` caught it on a
-- real PostgreSQL: "FAIL: the WARD COMMAND of the ward it was filed in can read
-- a complaint about security personnel". Restating a function is only safe
-- against its CURRENT definition, and the only way to know which that is, is to
-- replay the history.
--
-- The one change below is the ward clause in the ELSE branch.

CREATE OR REPLACE FUNCTION public.alert_is_ours(p_alert public.alerts)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
  SELECT CASE
    -- A complaint about security personnel goes to HQ and the person who made
    -- it. Checked FIRST and exclusively: the clauses below would otherwise hand
    -- it to the accused's own command, which is the defect. A hand-down must
    -- not become a way around it either, which is why this stays first.
    WHEN public.is_oversight_matter(p_alert.type) THEN
      public.commands_whole_state()
      OR p_alert.reported_by = auth.uid()

    ELSE
      -- HQ and administrators: the state.
      public.commands_whole_state()
      -- The reporter, the lead, and every officer on the dispatched team.
      OR p_alert.reported_by = auth.uid()
      OR p_alert.assigned_to = auth.uid()
      OR auth.uid()::text = ANY (COALESCE(p_alert.assigned_responders, '{}'::text[]))
      -- Operation Rainbow staff, within their command, plus anything handed to
      -- their LGA or to their WARD by name.
      OR (public.is_staff() AND NOT public.is_liaison()
          AND (public.alert_in_my_area(p_alert)
               OR public.alert_delegated_to_my_lga(p_alert)
               OR public.alert_delegated_to_my_ward(p_alert)))
      -- An outside agency: only what was handed to them.
      OR (public.is_liaison()
          AND upper(COALESCE(p_alert.escalated_to_agency, '')) = public.liaison_agency())
  END;
$$;

COMMENT ON FUNCTION public.alert_is_ours(public.alerts) IS
  'Whether the calling account has a part in this incident: HQ sees the state, '
  'everyone else sees their command, anything handed to them by name, and '
  'their own work — EXCEPT a complaint against security personnel, which only '
  'HQ and the complainant may see.';

COMMIT;

-- ----------------------------------------------------------------------------
-- 20261022000000_a_new_emergency_tells_the_unit.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261022000000_a_new_emergency_tells_the_unit.sql'; END $apply$;

-- ============================================================================
-- A NEW EMERGENCY TELLS THE UNIT IT LANDED IN
-- ============================================================================
--
-- `notification_outbox` was built for the TIMEOUT escalation, and its own
-- header says why that mattered:
--
--     an incident that climbed to the LGA at 02:00 because nobody at the ward
--     answered was moved into another tier's queue in complete silence, and
--     was only seen if somebody happened to have the console open. The whole
--     point of the timeout is the case where nobody is watching.
--
-- Every word of that applies more strongly to the FIRST report. Nothing queued
-- a notice when an alert was INSERTED. The only paths that reached a phone
-- were a human pressing DISPATCH or ESCALATE on the console, and the timeout
-- job two minutes later. So a citizen's SOS reached a responder only if that
-- responder happened to have the app open and in the foreground; a phone in a
-- pocket learned nothing until a dispatcher acted or the unit's window expired.
--
-- The irony is the shape of the gap: the system notified you when it gave up
-- waiting for you, and not when the emergency arrived.
--
-- WHO IS TOLD
--
-- The tier the row lands at, which is `NEW.assigned_tier` — not a hardcoded
-- 'UNIT'. That matters for one case and it is the important one: the BEFORE
-- INSERT trigger `route_oversight_to_hq_trg` sets `assigned_tier := 'HQ'` for a
-- complaint against security personnel, so reading the column means a complaint
-- is never announced to the local command it is about. Hardcoding the unit
-- would have been a way around the oversight rule, through a door nobody was
-- watching.
--
-- The console's drain then widens the UNIT audience for this kind to the field
-- responders as well as the unit's desk, because the responders are who go. An
-- officer who would be refused the row by RLS is never sent a push about it:
-- `alert_in_my_area()` gives a field responder their whole LGA, so their own
-- polling unit is well inside it.
--
-- WHY FILING THE EMERGENCY WINS
--
-- This is the hot path of the one thing the system exists to do. The trigger
-- therefore catches its own failure: if the notice cannot be queued, the SOS is
-- still filed and a WARNING goes to the PostgreSQL log. An emergency that
-- reaches the database silently beats one refused because a notice could not be
-- written. SECURITY DEFINER for the same reason — the outbox is not readable or
-- writable by a citizen, and the insert must not depend on that changing.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.queue_new_incident_notice()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  BEGIN
    INSERT INTO public.notification_outbox (alert_id, kind, payload)
    VALUES (
      NEW.id,
      'NEW_INCIDENT',
      jsonb_build_object(
        'alert_id',  NEW.id,
        -- No `from_tier`: nothing moved. A new incident is not an escalation,
        -- and the notice must not read like one.
        'to_tier',   coalesce(NEW.assigned_tier, 'UNIT'),
        'geo_lga',   NEW.geo_lga,
        'geo_ward',  NEW.geo_ward,
        'geo_pu',    NEW.geo_pu,
        'severity',  NEW.severity,
        'type',      NEW.type,
        'reason',    'REPORTED'
      )
    );
  EXCEPTION WHEN OTHERS THEN
    -- The SOS is already written; this is the notice about it. Losing the
    -- notice is bad and losing the report is worse.
    RAISE WARNING '[NEW_INCIDENT_NOTICE] could not queue a notice for %: %',
      NEW.id, SQLERRM;
  END;
  RETURN NULL;  -- AFTER trigger: the return value is discarded.
END $$;

COMMENT ON FUNCTION public.queue_new_incident_notice() IS
  'AFTER INSERT on alerts: queues a NEW_INCIDENT notice for the tier the row '
  'landed at, so the first report is announced and not only the timeout that '
  'follows it. Swallows its own failure: the emergency is filed either way.';

DROP TRIGGER IF EXISTS queue_new_incident_notice_trg ON public.alerts;
CREATE TRIGGER queue_new_incident_notice_trg
  AFTER INSERT ON public.alerts
  FOR EACH ROW EXECUTE FUNCTION public.queue_new_incident_notice();

COMMIT;

-- ----------------------------------------------------------------------------
-- 20261023000000_one_table_one_shape.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261023000000_one_table_one_shape.sql'; END $apply$;

-- ============================================================================
-- OPERATION RAINBOW — ONE TABLE, ONE SHAPE
--
-- Three of the four agency tables are created TWICE in this history, by two
-- files with different column lists and `CREATE TABLE IF NOT EXISTS` on both.
-- So the second one is a no-op, and WHICH COLUMNS A DATABASE HAS DEPENDS ON
-- WHICH FILE RAN FIRST:
--
--   agency_notifications   20260722000000_v3_telemetry_geofence   10 columns
--                          20260812000000_agency_tables            7 columns
--   agency_action_reports  20260723000000_v4_mesh_broadcast       14 columns
--                          20260812000000_agency_tables           15 columns
--   agency_deployments     20260723000000_v4_mesh_broadcast       10 columns
--                          20260812000000_agency_tables           10 columns
--
-- The v2–v6 era was applied to PRODUCTION by hand and written down afterwards,
-- and `verify_rls_migration.sh`, `bootstrap_staging.sql` and
-- `apply_all_migrations.sql` all exclude it — it cannot be replayed (v2 calls
-- auth.jwt() before the shim defines it). So the split is exact and permanent:
--
--   * on PRODUCTION the v3/v4 definitions ran first, and the tables carry
--     `detail`, `sent_by`, `target_lga`, `acknowledged_at` and `resolved_at`
--     but NOT `created_at`;
--   * on every database this repository can build, only 20260812 runs, and the
--     tables carry `created_at` but NONE of those five.
--
-- Two shapes, differing in both directions, with nothing saying so. The local
-- Supabase stand-in builds its column set by UNIONING every definition it
-- finds, which is right for a fake that must not refuse a column production
-- has — and it means the harness accepts a column that exists on neither
-- database, so nothing in the run could report this.
--
-- ## What it cost
--
-- `/api/notify-agency` is the handover: HQ escalates an incident to the Police,
-- the Army or the DSS, and the route sends an SMS and/or posts a webhook, then
-- records one row per leg. Its own comment:
--
--     Every leg, including the skipped ones: this table is the only durable
--     record of whether an agency was told, and a row set that omits the
--     channels nobody used cannot answer that question later.
--
-- It writes `method` and `status` — and drops `result.detail`, which is the
-- only thing that says WHY: `HTTP 502`, a timeout's message, "no contact
-- configured". The table has that column on production and not on staging, so
-- writing it would have worked in production and failed everywhere else, and
-- the route's error path is a `console.error` in a server log nobody reads.
-- "The Army was not told, and here is what the gateway said" is the whole
-- content of this table, and it was the part being thrown away.
--
-- ## What this migration does
--
-- Adds every column one definition has and the other lacks, so both shapes
-- converge on the union. `ADD COLUMN IF NOT EXISTS` throughout: on production
-- this adds `created_at` to three tables and nothing else; on a repo-built
-- database it adds the other five.
--
-- `created_at` is BACKFILLED from the column that records the real time —
-- `sent_at`, `submitted_at`, `deployed_at` — rather than stamped with this
-- migration's clock. A delivery log whose timestamps all read "the day we
-- fixed the schema" is worse than one with a null: the null is honest.
-- ============================================================================

BEGIN;

-- ── agency_notifications: the delivery log of a handover ────────────────────
ALTER TABLE public.agency_notifications
  ADD COLUMN IF NOT EXISTS detail          TEXT,
  ADD COLUMN IF NOT EXISTS sent_by         TEXT,
  ADD COLUMN IF NOT EXISTS target_lga      TEXT,
  ADD COLUMN IF NOT EXISTS acknowledged_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS created_at      TIMESTAMPTZ;

UPDATE public.agency_notifications
   SET created_at = sent_at
 WHERE created_at IS NULL;

ALTER TABLE public.agency_notifications
  ALTER COLUMN created_at SET DEFAULT NOW();

COMMENT ON COLUMN public.agency_notifications.detail IS
  'Why this leg ended as it did: the gateway''s response, an exception message, '
  'or the reason a channel was skipped. The route recorded method and status '
  'and dropped this, because the column existed only on production.';

-- ── agency_action_reports: what the agency sent back ───────────────────────
ALTER TABLE public.agency_action_reports
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ;

UPDATE public.agency_action_reports
   SET created_at = submitted_at
 WHERE created_at IS NULL;

ALTER TABLE public.agency_action_reports
  ALTER COLUMN created_at SET DEFAULT NOW();

-- ── agency_deployments: who the agency sent ────────────────────────────────
ALTER TABLE public.agency_deployments
  ADD COLUMN IF NOT EXISTS resolved_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS created_at  TIMESTAMPTZ;

UPDATE public.agency_deployments
   SET created_at = deployed_at
 WHERE created_at IS NULL;

ALTER TABLE public.agency_deployments
  ALTER COLUMN created_at SET DEFAULT NOW();

COMMENT ON COLUMN public.agency_deployments.resolved_at IS
  'When the agency stood its personnel down. Present on production from '
  '20260723000000_v4_mesh_broadcast and absent from the 20260812000000 '
  'definition that any other database applies; nothing reads it yet.';

COMMIT;

-- ----------------------------------------------------------------------------
-- 20261024000000_a_voice_note_and_a_report_that_is_not_an_emergency.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261024000000_a_voice_note_and_a_report_that_is_not_an_emergency.sql'; END $apply$;

-- ============================================================================
-- OPERATION RAINBOW — A VOICE NOTE, AND A REPORT THAT IS NOT AN EMERGENCY
--
-- Two things an operator asked for, and they meet in the same place: a report
-- from somebody who cannot type, about something that is not an emergency.
--
-- ## 1. THE REPORTER'S OWN VOICE
--
-- The app can already record. `report_details_screen.dart` holds an
-- `AudioRecorder`, writes an `.m4a` to the temporary directory, and uploads it
-- with the photographs — so the audio reaches Cloudinary and lands in
-- `media_urls` beside them.
--
-- Which is the problem. `media_urls` is EVIDENCE: the photograph of the
-- vehicle, the video of the roadblock. The reporter's own voice, left because
-- they could not type, is not one of several attachments — it is the report.
-- Nothing downstream could tell the difference:
--
--   * a responder's incident card said "3 attachments" and an operator had to
--     open each to find out that one of them was somebody speaking;
--   * the console's dossier rendered it as a 72px thumbnail with a musical
--     note on it, among the photographs;
--   * and the one path built for a person who cannot type — the AI voice
--     dialog — runs speech-to-text and files the TRANSCRIPT. The audio is
--     discarded. So if the recogniser mangles Hausa, or there is no network to
--     reach it, what the person actually said is gone. For a report that
--     exists BECAUSE they could not type, that is the whole content.
--
-- `voice_note_url` is therefore its own column: one per report, the reporter
-- speaking. `voice_note_seconds` is beside it because a responder on a metered
-- or weak connection needs to know whether they are about to pull eight
-- seconds or two minutes before they press play.
--
-- ## 2. A REPORT THAT MUST NOT WAKE ANYBODY
--
-- The second ask is a general report: government property mismanaged,
-- vandalised, abandoned, unsafe, in need of repair. A street light is not a
-- kidnapping, and this system is built to treat everything as a kidnapping:
--
--   * `queue_new_incident_notice()` (20261022000000) announces every INSERT to
--     the tier it landed at, and the drain widens a UNIT notice to the field
--     responders — the people who physically go. A broken culvert filed at
--     02:00 would push to their handsets.
--   * `escalate_overdue_alerts()` climbs anything unacknowledged one rung per
--     timeout. Nobody acknowledges a street light at 02:00, so by morning it
--     would be an HQ-tier incident with three escalations against it, sitting
--     among the night's actual emergencies.
--
-- Both are right for an emergency and wrong for this. The mechanism for
-- "handle this differently" already exists twice — `is_oversight_matter()`
-- routes a complaint about an officer to HQ, and `awaiting_human_confirmation()`
-- holds an unconfirmed keypad report out of the ladder — and this is the same
-- shape, so it is built the same way rather than a third way:
--
--   * `is_non_emergency(type)` matches on the CATEGORY, the part of `type`
--     before ' - ', so every subtype is covered and a new one added to the app
--     needs no migration;
--   * a BEFORE INSERT trigger lands it at the LGA — the local authority whose
--     property it is — and not at the polling unit, so the notice goes to a
--     desk rather than to a patrol's pocket;
--   * `escalate_overdue_alerts()` leaves it alone. It waits for somebody to
--     look at it, which is what it is for.
--
-- WHAT THIS DELIBERATELY DOES NOT DO: hide it. The report is a normal row on
-- the board, in the feed, on the map, with its own category — an operator can
-- see it, filter to it and act on it. "Not an emergency" means not paged and
-- not climbed; it does not mean not seen. Something nobody is shown is
-- something nobody fixes, which is how a thing ends up abandoned.
-- ============================================================================

BEGIN;

-- ── 1. the reporter's voice ────────────────────────────────────────────────
ALTER TABLE public.alerts
  ADD COLUMN IF NOT EXISTS voice_note_url     TEXT,
  ADD COLUMN IF NOT EXISTS voice_note_seconds INTEGER;

COMMENT ON COLUMN public.alerts.voice_note_url IS
  'The reporter speaking, when they could not or did not type. Its own column '
  'and not one of media_urls: that list is evidence — photographs, video — and '
  'a voice note is the report itself. One per report; a second recording '
  'replaces it.';

COMMENT ON COLUMN public.alerts.voice_note_seconds IS
  'How long the voice note runs. A responder on a metered or weak connection '
  'is told what they are about to pull before they press play.';

-- A negative or absurd duration is a bug in whatever wrote it, and a column
-- that accepts one makes the screen that renders it lie.
ALTER TABLE public.alerts
  DROP CONSTRAINT IF EXISTS alerts_voice_note_seconds_sane;
ALTER TABLE public.alerts
  ADD CONSTRAINT alerts_voice_note_seconds_sane
  CHECK (voice_note_seconds IS NULL
         OR (voice_note_seconds > 0 AND voice_note_seconds <= 600));

-- ── 2. which categories are not emergencies ───────────────────────────────
--
-- One name, matched on the category exactly as `is_oversight_matter()` does.
-- The labels are the app's, from lib/core/constants/alert_categories.dart;
-- `scripts/check_non_emergency_categories_agree.py` fails if the two lists
-- drift, because a category the app can file and the database does not know
-- about would be paged out to responders at 02:00.
CREATE OR REPLACE FUNCTION public.is_non_emergency(p_type TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
  SELECT upper(trim(split_part(coalesce(p_type, ''), ' - ', 1)))
         IN ('PUBLIC PROPERTY', 'PUBLIC SERVICE');
$$;

COMMENT ON FUNCTION public.is_non_emergency(TEXT) IS
  'A report about government property or a public service: mismanaged, '
  'vandalised, abandoned, unsafe, needing repair. Matched on the category — '
  'the part of type before " - " — so every subtype is covered. These are '
  'filed at the LGA and never climb the escalation ladder: a street light does '
  'not page a patrol at 02:00 and must not be an HQ-tier incident by morning. '
  'They are still on the board, in the feed and on the map.';

-- ── 3. land it at the local authority, not in a patrol's pocket ───────────
CREATE OR REPLACE FUNCTION public.route_non_emergency_to_lga()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- An oversight matter has already been sent to HQ by its own trigger, and
  -- that decision wins: a complaint about an officer is not a street light,
  -- whatever else it is. Checked rather than assumed, because trigger order is
  -- alphabetical by name and that is a thin thread to hang a routing rule on.
  IF public.is_non_emergency(NEW.type)
     AND NOT public.is_oversight_matter(NEW.type) THEN
    NEW.assigned_tier    := 'LGA';
    NEW.tier_assigned_at := NOW();
    -- Not pre-assigned to a responder. The app's own default would hand it to
    -- whoever is posted where it was filed, which for a culvert means an
    -- officer gets a dispatch for something no officer can fix.
    NEW.assigned_to         := NULL;
    NEW.assigned_responders := NULL;
    NEW.escalation_log := coalesce(NEW.escalation_log, '[]'::jsonb) || jsonb_build_object(
      'at',     to_char(NOW() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
      'by',     'SYSTEM',
      'action', 'NON_EMERGENCY_ROUTED',
      'reason', 'a report about public property is filed at the LGA and does not climb'
    );
  END IF;
  RETURN NEW;
END $$;

COMMENT ON FUNCTION public.route_non_emergency_to_lga() IS
  'BEFORE INSERT: files a report about government property at the LGA, clears '
  'any responder assignment, and records why. Defers to the oversight router: '
  'a complaint against security personnel goes to HQ even if it also mentions '
  'property.';

-- `z_` so it sorts AFTER route_oversight_to_hq_trg: PostgreSQL fires BEFORE
-- triggers in alphabetical order by name, and this one must see whatever the
-- oversight router decided rather than race it. The guard above makes the
-- order not matter; the name makes it not matter twice.
DROP TRIGGER IF EXISTS z_route_non_emergency_to_lga_trg ON public.alerts;
CREATE TRIGGER z_route_non_emergency_to_lga_trg
  BEFORE INSERT ON public.alerts
  FOR EACH ROW EXECUTE FUNCTION public.route_non_emergency_to_lga();

-- ── 4. the ladder leaves it alone ─────────────────────────────────────────
--
-- RESTATED IN FULL from 20261011000000_ussd_reports_are_unconfirmed.sql, which
-- is the latest generation, with ONE line added. Restating a function from the
-- wrong generation is how `alert_is_ours()` lost its oversight branch in this
-- repository — every Dart and console test still passed and only a SQL
-- behaviour test on a real PostgreSQL caught it. Everything below except the
-- marked line is that file's text.
CREATE OR REPLACE FUNCTION public.escalate_overdue_alerts()
RETURNS TABLE (alert_id UUID, from_tier TEXT, to_tier TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN QUERY
  WITH overdue AS (
    SELECT a.id,
           upper(a.assigned_tier)            AS current_tier,
           public.next_tier(a.assigned_tier) AS target_tier
      FROM public.alerts a
     WHERE a.status NOT IN ('RESOLVED', 'CANCELLED')
       -- Acknowledged means somebody at this tier has it. Climbing past a
       -- responder who is already on it is how you get two units dispatched
       -- to the same incident and none to the next one.
       AND a.acknowledged_at IS NULL
       -- A report filed over USSD that no officer has stood behind. The timers
       -- must not turn a stranger's keypresses into a deployment; see
       -- awaiting_human_confirmation() above.
       AND NOT public.awaiting_human_confirmation(a)
       -- THE ONE NEW LINE. A street light does not become an HQ-tier incident
       -- because nobody looked at it overnight.
       AND NOT public.is_non_emergency(a.type)
       AND public.next_tier(a.assigned_tier) IS NOT NULL
       AND a.tier_assigned_at IS NOT NULL
       AND a.tier_assigned_at <
             NOW() - make_interval(
               mins => public.tier_timeout_minutes(a.assigned_tier)
             )
     FOR UPDATE OF a SKIP LOCKED
  ),
  moved AS (
    UPDATE public.alerts a
       SET assigned_tier    = o.target_tier,
           tier_assigned_at = NOW(),
           status           = 'ESCALATED',
           updated_at       = NOW(),
           escalation_log = COALESCE(a.escalation_log, '[]'::jsonb) || jsonb_build_object(
             'from_tier',  o.current_tier,
             'to_tier',    o.target_tier,
             'reason',     'TIMEOUT',
             'by',         'SYSTEM',
             'at',         to_char(NOW() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
           )
      FROM overdue o
     WHERE a.id = o.id
    RETURNING a.id, o.current_tier, o.target_tier, a.geo_lga, a.geo_ward, a.geo_pu, a.severity
  ),
  queued AS (
    INSERT INTO public.notification_outbox (alert_id, kind, payload)
    SELECT m.id,
           'TIER_ESCALATION',
           jsonb_build_object(
             'alert_id',  m.id,
             'from_tier', m.current_tier,
             'to_tier',   m.target_tier,
             'geo_lga',   m.geo_lga,
             'geo_ward',  m.geo_ward,
             'geo_pu',    m.geo_pu,
             'severity',  m.severity,
             'reason',    'TIMEOUT'
           )
      FROM moved m
    -- `RETURNING alert_id` collides with this function's own OUT parameter of
    -- that name and is rejected as ambiguous. Nothing reads this CTE's output;
    -- it exists so the INSERT runs inside the same statement as the UPDATE.
    RETURNING id
  )
  SELECT m.id, m.current_tier, m.target_tier FROM moved m;
END;
$$;

COMMENT ON FUNCTION public.escalate_overdue_alerts() IS
  'The timeout sweep. Climbs an unacknowledged incident one rung when its tier '
  'has held it too long, and queues a TIER_ESCALATION notice. Skips an '
  'unconfirmed keypad report (awaiting_human_confirmation) and a report about '
  'public property (is_non_emergency), neither of which should be moved by a '
  'clock.';

COMMIT;

-- ----------------------------------------------------------------------------
-- 20261025000000_the_other_policy_public_could_reach.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261025000000_the_other_policy_public_could_reach.sql'; END $apply$;

-- ============================================================================
-- The OTHER policy PUBLIC could reach
--
-- A production policy query came back with two rows:
--
--   alerts_select_geo_lga_scoped    | alerts    | SELECT
--   telemetry_select_geo_lga_scoped | telemetry | SELECT
--
-- The second is known. 20261016000000_telemetry_policy_is_not_public.sql exists
-- because a production paste reported it as the one policy reaching PUBLIC, and
-- that migration drops and recreates it TO authenticated.
--
-- The first is its TWIN, and nothing had looked at it.
--
-- Both are created by 20260725000000_v6_geo_lga_scoping_staging.sql, twelve
-- lines apart. The telemetry one is written `TO authenticated`. The alerts one
-- is written:
--
--     CREATE POLICY "alerts_select_geo_lga_scoped"
--       ON public.alerts
--       FOR SELECT
--       USING ( … )          -- no TO clause
--
-- and PostgreSQL records a policy with no TO clause as **TO PUBLIC**, which
-- includes `anon`. So the lesson had already been learned, written down, and
-- committed as a comment IN THAT FILE, directly below a policy carrying the
-- same defect — and the sibling was never fixed.
--
-- ## What it exposes
--
-- `alerts` is the incident table: the reporter's name and phone number, what
-- they said, where they are. `telemetry` is position history. Neither should be
-- reachable by the anonymous key under any circumstances.
--
-- What stops this being an open database today is only that
-- 20260813000000_rls_least_privilege.sql REVOKEs the table privileges from
-- `anon`, so the policy has nothing to permit. That is one layer. A single
-- GRANT, or one click in the dashboard's table editor, and the policy is the
-- only thing standing between the anonymous key and every incident on the
-- board — and it says yes.
--
-- ## Why neither the migration nor the tests caught it
--
-- Three reasons, and they are the same three that hid the telemetry twin:
--
--   * 20260813 drops prior policies BY EXACT NAME, 98 of them, and neither v6
--     policy is in the list — it cannot be, because 20260725 is a file that
--     migration had no reason to know about. Checked: 0 occurrences of
--     `geo_lga_scoped` in it.
--   * `20260725…_staging.sql` is STAGING_ONLY, so it is not in the production
--     paste at all. Production has these two policies because the v6 era was
--     applied BY HAND. A file excluded from the paste still shaped the database
--     the paste runs against.
--   * verify_rls_migration.sh asserts no policy reaches anon or public at the
--     END of the full replay, and passes — because 20261006000000 drops
--     `alerts_select_geo_lga_scoped` on its way to the posting-scoped policy.
--     The end state is clean. Production is sitting in the MIDDLE, where the
--     policy exists and the drop has not been applied, and no assertion in this
--     repository describes the middle.
--
-- ## What this does
--
-- `ALTER POLICY … TO authenticated`, which changes the policy's ROLES and
-- nothing else. No officer loses a row they could read before; `anon` and
-- PUBLIC lose a policy that should never have named them.
--
-- Deliberately NOT a drop-and-recreate, which is what the first draft of this
-- file did and what 20261016 does for the twin. Production's copy of this
-- policy was applied BY HAND. Recreating it from the expression in this
-- repository would impose this repository's text on a database whose version
-- may differ — and that expression decides which officer may read which
-- incident. ALTER POLICY leaves the body exactly as it is, and leaves no
-- window in which the table carries no policy at all.
--
-- Idempotent, and a no-op in two different ways on purpose:
--
--   * on a database built from this repository the policy is already gone,
--     dropped by 20261006000000 eleven files earlier, and this says so;
--   * on a database where it is already TO authenticated, nothing changes.
--
-- 20261006000000 still drops it later in the paste, in favour of
-- `alerts_select_own_or_ours`. This exists so that a production database is
-- safe the moment it is pasted, on its own, before the other thirty-six.
-- ============================================================================

DO $$
DECLARE
  current_roles NAME[];
  reaches_public INTEGER;
BEGIN
  SELECT roles INTO current_roles
    FROM pg_policies
   WHERE schemaname = 'public'
     AND tablename  = 'alerts'
     AND policyname = 'alerts_select_geo_lga_scoped';

  IF current_roles IS NULL THEN
    RAISE NOTICE
      'alerts_select_geo_lga_scoped is not on this database — either '
      '20260725 (staging-only) never ran here, or 20261006 has already '
      'replaced it with alerts_select_own_or_ours. Nothing to repair.';

  ELSIF NOT ('public' = ANY(current_roles) OR 'anon' = ANY(current_roles)) THEN
    RAISE NOTICE
      'alerts_select_geo_lga_scoped is already scoped to % — left alone',
      current_roles;

  ELSE
    -- ALTER POLICY, NOT DROP AND RECREATE.
    --
    -- The first version of this migration dropped the policy and recreated it
    -- from the expression in 20260725000000_v6_geo_lga_scoping_staging.sql.
    -- That is wrong here, and quietly so: production's copy of this policy was
    -- applied BY HAND, so the only thing known about its body is that it was
    -- once pasted from that file. Recreating it imposes THIS repository's text
    -- on a database whose version may differ by a character — and the thing
    -- being rewritten decides which officer may read which incident.
    --
    -- `ALTER POLICY … TO authenticated` changes only the roles. The USING
    -- expression on that database is left exactly as it is, whatever it is.
    -- There is also no window in which the table has no policy, which a drop
    -- followed by a failing recreate would leave behind.
    RAISE NOTICE
      'alerts_select_geo_lga_scoped is TO % — scoping it TO authenticated, '
      'leaving its USING expression untouched', current_roles;

    ALTER POLICY "alerts_select_geo_lga_scoped" ON public.alerts TO authenticated;

    COMMENT ON POLICY "alerts_select_geo_lga_scoped" ON public.alerts IS
      'An officer may read incidents in their own LGA. Scoped TO authenticated '
      'by 20261025000000: created by 20260725 with no TO clause, which '
      'PostgreSQL records as TO PUBLIC — and PUBLIC includes anon. 20260813 '
      'could not drop it by name because that migration predates the file. Its '
      'telemetry twin had the same defect and was repaired by 20261016000000; '
      'this is the one beside it that was missed. Only the roles were changed: '
      'the expression is whatever this database already had.';

    RAISE NOTICE 'alerts_select_geo_lga_scoped is now scoped TO authenticated';
  END IF;

  -- Both known offenders are now closed. Anything else reaching PUBLIC is new
  -- information and is named, loudly, rather than left for the next person to
  -- find on a live database.
  SELECT count(*) INTO reaches_public
    FROM pg_policies
   WHERE schemaname = 'public'
     AND ('anon' = ANY(roles) OR 'public' = ANY(roles));

  IF reaches_public = 0 THEN
    RAISE NOTICE 'No policy in schema public reaches anon or public.';
  ELSE
    RAISE WARNING
      '% policy/policies in schema public still reach anon or public. Run '
      'scripts/rls_inventory.sql and read the roles column — a policy with no '
      'TO clause is recorded as TO PUBLIC.', reaches_public;
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 20261026000000_safe_zones_capacity.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261026000000_safe_zones_capacity.sql'; END $apply$;

-- ============================================================================
-- A shelter's capacity, which the app has been reading all along
--
-- `safe_zone_screen.dart` is what a citizen opens to find out where to run. Its
-- card reads:
--
--     capacity: (e['capacity'] as num?)?.toInt() ?? 0,
--     ...
--     if (_selected!.capacity > 0) ...[
--       Text('${sz_capacity}: ${_selected!.capacity} ${sz_persons}')
--
-- `public.safe_zones` was created in phase1_foundation.sql with id, name,
-- description, latitude, longitude, type, geo_lga, geo_ward, is_active and
-- created_at. There is no capacity column, and no migration has ever added
-- one. So the read returned null, the model stored 0, and the `> 0` guard
-- meant the line was never drawn for a real shelter.
--
-- ## Why nobody noticed
--
-- The screen had a fallback. When the query failed — and it threw on a
-- SUCCESSFUL EMPTY RESULT too — it returned three shelters hardcoded in the
-- Dart, with capacities of 500, 250 and 350. Those are the only capacities
-- this app has ever displayed. The fallback is removed in T-74; taking it away
-- is what made the absence visible.
--
-- The schema-drift gate did not catch it either, and could not have: the query
-- is `select()` with no column list, so nothing in the app NAMES `capacity` in
-- a way that could be compared against the schema. It reads a key out of a map
-- that came back, and an absent key is indistinguishable from a null one.
--
-- ## What this adds
--
-- A nullable INTEGER. Nullable on purpose: "we have not recorded how many this
-- holds" is a true and common state for a shelter that has just been added,
-- and it is not the same as zero. The app's `> 0` guard already draws nothing
-- in that case, which is the correct behaviour and now means what it says.
--
-- A CHECK keeps it sane. A negative capacity is not a missing one, and a
-- shelter recorded as holding 2,000,000 people is a typo that would send a
-- commander to the wrong place in an emergency.
--
-- No backfill. There is no honest value to backfill WITH — inventing one here
-- would be the same fault this migration exists to clean up, written in SQL
-- instead of Dart.
--
-- Idempotent: safe to re-run.
-- ============================================================================

ALTER TABLE public.safe_zones
  ADD COLUMN IF NOT EXISTS capacity INTEGER;

DO $capacity_check$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conname = 'safe_zones_capacity_sane'
       AND conrelid = 'public.safe_zones'::regclass
  ) THEN
    ALTER TABLE public.safe_zones
      ADD CONSTRAINT safe_zones_capacity_sane
      CHECK (capacity IS NULL OR (capacity >= 0 AND capacity <= 100000));
  END IF;
END
$capacity_check$;

COMMENT ON COLUMN public.safe_zones.capacity IS
  'How many people this shelter holds. NULL means it has not been recorded, '
  'which is not the same as zero: the app draws the line only when it is set.';

-- ----------------------------------------------------------------------------
-- 20261027000000_agency_handovers_retry.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261027000000_agency_handovers_retry.sql'; END $apply$;

-- ============================================================================
-- A failed handover to an outside agency now gets retried
--
-- `20260722000000_v3_telemetry_geofence.sql` creates
--
--     idx_agency_notifications_status … WHERE status = 'FAILED'
--
-- and its comment says "(retry jobs)". There is no retry job. The index has
-- been waiting for one since July.
--
-- `agency_notifications` is the record of handing an incident to the Police or
-- the Army: the leg, the method, whether it went. When a leg fails, the row
-- says FAILED and nothing tries again. The failure IS visible to HQ on the
-- incident replay, which is the difference between a silent failure and a known
-- one — somebody can pick up a phone. But an emergency handed to an agency
-- whose channel was briefly down stays handed to nobody until a person notices.
--
-- ## What this does NOT decide
--
-- E2E_AUDIT_REPORT.md named this as "a piece of work with real decisions in it
-- (how many times do you re-send an SMS about an emergency, and to whom does it
-- escalate when the agency's own channel is down), not a line of code" — and
-- said the right move was "to drain these the way `notification_outbox` is
-- drained, with the same backoff and the same `attempts` column, rather than to
-- invent a second mechanism".
--
-- So nothing here is a new policy. Every decision is the one
-- `20261007000000_notification_outbox.sql` already made for the same question:
--
--   * claim with FOR UPDATE SKIP LOCKED, holding the row a minute, so a worker
--     that dies mid-send does not have the row taken again on the next tick;
--   * on failure, back off `attempts * 2` minutes, capped at 60;
--   * no maximum attempt count. An unreachable agency is retried hourly for as
--     long as the incident is open rather than abandoned — which is the outbox's
--     existing answer, and the safer one for an emergency. The row's
--     `attempts` and `last_error` are what tell HQ it is not getting through.
--
-- Escalation when a channel stays down is still a person reading the replay.
-- That is unchanged and deliberate: this migration makes the machine stop
-- giving up, it does not invent a second human to call.
--
-- ## Idempotent
--
-- Columns are ADD COLUMN IF NOT EXISTS; functions are CREATE OR REPLACE. Safe
-- to paste twice, which `verify_rls_migration.sh` does.
-- ============================================================================

-- ── 1. The three columns the outbox uses, and this table lacked ─────────────
ALTER TABLE public.agency_notifications
  ADD COLUMN IF NOT EXISTS attempts        INTEGER     NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS last_error      TEXT;

COMMENT ON COLUMN public.agency_notifications.attempts IS
  'How many times this leg has been attempted. Mirrors '
  'notification_outbox.attempts; drives the same backoff.';
COMMENT ON COLUMN public.agency_notifications.next_attempt_at IS
  'When this leg may be attempted again. NOW() by default so an existing '
  'FAILED row becomes due immediately on first drain rather than never.';
COMMENT ON COLUMN public.agency_notifications.last_error IS
  'Why the last attempt failed, truncated to 500 characters. What HQ reads on '
  'the incident replay to decide whether to pick up a phone.';

-- The index the retry actually needs. The 2026-07 one is on `status` alone,
-- which finds the failures and not the DUE ones.
CREATE INDEX IF NOT EXISTS idx_agency_notifications_due
  ON public.agency_notifications (next_attempt_at)
  WHERE status = 'FAILED';

-- ── 1b. `sent_at` has to mean what it says ─────────────────────────────────
--
-- Found by exercising the claim loop below, which returned nothing. The filter
-- was `sent_at IS NULL`, and `sent_at` can never be null:
--
--     sent_at TIMESTAMPTZ NOT NULL DEFAULT NOW()   -- 20260812000000
--
-- So the column records when the ROW WAS CREATED, not when the leg was sent. A
-- handover to the Police that failed, or was skipped, or has not been attempted
-- carries a send time anyway — and HQ reads that on the incident replay as a
-- delivery that happened. A timestamp that looks measured and is a default, in
-- the record of whether an emergency reached an outside agency. Same family as
-- C-5 and T-84, in a time column instead of a coordinate.
--
-- The default and the NOT NULL go, so an unsent leg has no send time. Legs
-- already marked FAILED are nulled, because that is the one case where the
-- truth is known: they were not sent. SENT and SKIPPED rows are left alone —
-- their value may be a default or may be real and nothing here can tell, and
-- inventing a null would be the same mistake with the opposite sign.
ALTER TABLE public.agency_notifications
  ALTER COLUMN sent_at DROP DEFAULT,
  ALTER COLUMN sent_at DROP NOT NULL;

UPDATE public.agency_notifications
   SET sent_at = NULL
 WHERE status = 'FAILED'
   AND sent_at IS NOT NULL;

COMMENT ON COLUMN public.agency_notifications.sent_at IS
  'When this leg actually went, or NULL when it has not. Was NOT NULL DEFAULT '
  'NOW(), which made it the row creation time and reported every failed '
  'handover as delivered. Set only by mark_agency_handover_sent. See T-89.';

-- ── 2. Claim, mark sent, mark failed — the outbox's three, same shapes ──────
CREATE OR REPLACE FUNCTION public.claim_agency_handovers(p_limit INTEGER DEFAULT 20)
RETURNS SETOF public.agency_notifications
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN QUERY
  WITH due AS (
    SELECT n.id
      FROM public.agency_notifications n
     WHERE n.status = 'FAILED'
       AND n.sent_at IS NULL
       AND n.next_attempt_at <= NOW()
     ORDER BY n.next_attempt_at
     LIMIT GREATEST(COALESCE(p_limit, 20), 1)
     FOR UPDATE SKIP LOCKED
  )
  UPDATE public.agency_notifications n
     SET attempts = n.attempts + 1,
         -- Held a minute on claim, exactly as claim_notifications does, so a
         -- worker that dies mid-send returns the row to the queue by itself.
         next_attempt_at = NOW() + INTERVAL '1 minute'
    FROM due
   WHERE n.id = due.id
  RETURNING n.*;
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_agency_handover_sent(p_id UUID)
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  UPDATE public.agency_notifications
     SET status = 'SENT', sent_at = NOW(), last_error = NULL
   WHERE id = p_id;
$$;

CREATE OR REPLACE FUNCTION public.mark_agency_handover_failed(p_id UUID, p_error TEXT)
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  UPDATE public.agency_notifications
     SET status = 'FAILED',
         last_error = left(COALESCE(p_error, 'unknown'), 500),
         -- The outbox's backoff, unchanged: attempts * 2 minutes, capped at an
         -- hour. No give-up count, because the thing not getting through is an
         -- emergency handed to the Police.
         next_attempt_at = NOW() + make_interval(
           mins => LEAST(GREATEST(attempts, 1) * 2, 60))
   WHERE id = p_id;
$$;

-- ── 3. Only the service role drains a queue ─────────────────────────────────
REVOKE ALL ON FUNCTION public.claim_agency_handovers(INTEGER)        FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.mark_agency_handover_sent(UUID)        FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.mark_agency_handover_failed(UUID, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_agency_handovers(INTEGER)        TO service_role;
GRANT EXECUTE ON FUNCTION public.mark_agency_handover_sent(UUID)        TO service_role;
GRANT EXECUTE ON FUNCTION public.mark_agency_handover_failed(UUID, TEXT) TO service_role;

COMMENT ON FUNCTION public.claim_agency_handovers(INTEGER) IS
  'Claims failed agency handover legs that are due, holding each for a minute. '
  'Same shape and same backoff as claim_notifications: the index from 2026-07 '
  'said "(retry jobs)" and there was no retry job. See T-89.';

-- ----------------------------------------------------------------------------
-- 20261028000000_command_knows_both_vocabularies.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261028000000_command_knows_both_vocabularies.sql'; END $apply$;

-- ============================================================================
-- The command tier the deployment actually has
--
-- T-85 found that `auth_provider.dart` chose an officer's rung by substring
-- test, so `STATE_COMMANDER` — the role 4 of the production project's HQ duty
-- officers carry — matched none of HQ/LGA/WARD/UNIT/POLLING and was silently
-- treated as a polling unit. That is fixed in the app.
--
-- The database has the same problem, one layer down, where the app's fix cannot
-- reach. Two functions decide what a commander may DO, and both are exact-match
-- lists of the vocabulary this repository was written against:
--
--     is_command()          IN ('HQ_COMMAND','HQ_OFFICER','ADMIN','LGA_COMMAND')
--     commands_whole_state() IN ('HQ_COMMAND','HQ_OFFICER','ADMIN')
--
-- The production project's 22 staff accounts carry `STATE_COMMANDER` (×4),
-- `LGA_COMMANDER` (×4), `WARD_COMMANDER` (×4) and `POLLING_UNIT_OFFICER` (×6).
-- Exactly TWO accounts — one HQ_COMMAND and one LGA_COMMAND — satisfy
-- `is_command()`. Every other commander is refused by every policy gated on it:
--
--   * system_alerts     write / update / delete   — THE ADVISORY BROADCAST
--   * safe_zones        write                     — publishing a shelter
--   * agency_personnel / agency_deployments /
--     agency_action_reports / agency_notifications — the whole agency portal
--   * sim_channel_events acknowledge              — a SIM swap on a handset
--   * uninstall_requests update                   — approving an uninstall
--
-- And `commands_whole_state()` is why the empty-board diagnostic reports
-- `steviekusu@gmail.com` (HQ_COMMAND) seeing "156 of 156, commands the whole
-- state" while hq-001 and hq-002 (STATE_COMMANDER) see 106: their scope falls
-- back to their posting, which is one polling unit in Bukuru.
--
-- `is_staff()` is NOT affected, because it is written as an exclusion —
-- `NOT IN ('CITIZEN','USER')` — so every staff name passes it whatever it is
-- called. That is why those accounts could READ incidents all along, and why
-- the failure looked like a filter rather than a permission.
--
-- ## Why widening these is safe
--
-- `profiles.role` cannot be chosen or changed by any authenticated user: the
-- trigger in 20260813000000 section 4 raises 42501 on ANY role change unless
-- the caller is service_role. So recognising a name grants nothing a user can
-- give themselves — the backend assigns roles, and a citizen cannot become a
-- STATE_COMMANDER to obtain these rights.
--
-- ## What is deliberately NOT added
--
-- `WARD_COMMANDER` and `POLLING_UNIT_OFFICER`. `is_command()` already excludes
-- `WARD_COMMAND` and `UNIT_COMMAND`, so their synonyms stay out too — this
-- migration teaches the database a second spelling, it does not move anybody up
-- the chain.
--
-- Idempotent: both are CREATE OR REPLACE over a pure SELECT.
-- See E2E_AUDIT_REPORT.md T-85 and T-90.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.is_command()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT upper(coalesce(role, '')) FROM public.profiles WHERE id = auth.uid())
      IN (
        -- The vocabulary this repository is written against.
        'HQ_COMMAND', 'HQ_OFFICER', 'ADMIN', 'LGA_COMMAND',
        -- The vocabulary the production project's accounts carry. Same two
        -- rungs, different spelling. T-90.
        'STATE_COMMANDER', 'LGA_COMMANDER'
      ),
    false
  );
$$;

COMMENT ON FUNCTION public.is_command() IS
  'HQ, administrators and LGA command, under either vocabulary. Was an '
  'exact-match list of HQ_COMMAND/HQ_OFFICER/ADMIN/LGA_COMMAND, which left '
  'the production project''s STATE_COMMANDER and LGA_COMMANDER accounts — 8 of '
  'its 22 staff — unable to post an advisory, publish a shelter, use the '
  'agency portal or acknowledge a SIM swap. upper() so case cannot decide a '
  'permission either. See T-90.';

CREATE OR REPLACE FUNCTION public.commands_whole_state()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT COALESCE(
    (SELECT upper(coalesce(role, '')) FROM public.profiles WHERE id = auth.uid())
      IN (
        'HQ_COMMAND', 'HQ_OFFICER', 'ADMIN',
        -- The HQ rung's other spelling. Without this an HQ duty officer's
        -- incident scope silently fell back to their posting — one polling
        -- unit — which is what the empty-board diagnostic was reporting. T-90.
        'STATE_COMMANDER'
      ),
    false
  );
$$;

COMMENT ON FUNCTION public.commands_whole_state() IS
  'HQ and administrators, under either vocabulary. Narrower than is_command(), '
  'which also includes the LGA rung. STATE_COMMANDER added by T-90: without it '
  'an HQ duty officer saw only their posting.';

-- Say what changed, loudly, because this one alters who may do what.
DO $say$
DECLARE
  n_command INTEGER;
  n_state   INTEGER;
BEGIN
  SELECT count(*) INTO n_command
    FROM public.profiles
   WHERE upper(coalesce(role, '')) IN
         ('HQ_COMMAND','HQ_OFFICER','ADMIN','LGA_COMMAND',
          'STATE_COMMANDER','LGA_COMMANDER');
  SELECT count(*) INTO n_state
    FROM public.profiles
   WHERE upper(coalesce(role, '')) IN
         ('HQ_COMMAND','HQ_OFFICER','ADMIN','STATE_COMMANDER');
  RAISE NOTICE
    'is_command() now matches % profile(s); commands_whole_state() matches %. '
    'If either number surprises you, read profiles.role before going further.',
    n_command, n_state;
END $say$;

-- ----------------------------------------------------------------------------
-- 20261029000000_a_notification_has_a_shelf_life.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261029000000_a_notification_has_a_shelf_life.sql'; END $apply$;

-- Four hundred and twelve emergency notices, the oldest from July, all due now.
--
-- ## What the live project looks like
--
--     outbox_rows 412 | outbox_pending 412 | outbox_erroring 0 | max attempts 0
--
-- Four hundred and twelve queued notifications, none ever attempted, going back
-- three months. The drain worker was never scheduled, so the queue simply
-- filled. That part is a deployment step, and it is the operator's to take.
--
-- The part that is this file's is what happens when they take it.
--
-- `claim_notifications` takes the oldest undelivered rows whose
-- `next_attempt_at` has passed, twenty at a time, and there is no upper bound on
-- age anywhere — not in the function, not in either of the two drainers. So the
-- first thing a newly scheduled worker does is deliver July. Every officer whose
-- geography matched an incident that timed out in July gets
--
--     INCIDENT NOW AT LGA
--     Incident #a3f2b118 in JOS SOUTH was not acknowledged in time and has come
--     up to LGA. Open the console to take it.
--
-- for incidents that are closed, about positions people are no longer at, at
-- twenty a minute for twenty-one minutes. The notices are indistinguishable from
-- live ones, because that is what the text is for.
--
-- ## Why this is the queue's problem and not the worker's
--
-- A notification about an emergency is not like a notification about an invoice.
-- It is an instruction to go somewhere, and it decays: a tier escalation says
-- "nobody answered, it is yours now", which is false ten minutes later and
-- dangerous three months later. There is no arrangement of retries under which
-- delivering it is better than dropping it.
--
-- So the rule belongs where the work is handed out, not in each worker. There
-- are two drainers — `supabase/functions/drain-outbox/index.ts` and the
-- console's `/api/notify/drain` — and a rule written twice drifts; this project
-- has already had that exact bug, in the OneSignal auth scheme, where the two
-- halves disagreed and at most one of them ever authenticated. `escalation_push
-- _targets()` was moved into SQL for the same reason. One claim function, one
-- shelf life, and any worker anybody writes next inherits it.
--
-- ## An expired row is not a delivered row
--
-- The obvious shortcut is to set `delivered_at` and move on. That writes a lie
-- into the one table whose honesty this mechanism exists for: the whole reason
-- the outbox was built was that the old worker marked escalations delivered with
-- nobody told. `expired_at` with a reason is the truthful record, and it keeps
-- the "did anybody get told?" question answerable afterwards.

-- ── The two terminal states ─────────────────────────────────────────────────

ALTER TABLE public.notification_outbox
  ADD COLUMN IF NOT EXISTS expired_at TIMESTAMPTZ;
ALTER TABLE public.notification_outbox
  ADD COLUMN IF NOT EXISTS expiry_reason TEXT;

COMMENT ON COLUMN public.notification_outbox.expired_at IS
  'Set when this notice was dropped undelivered because its moment had passed. '
  'Distinct from delivered_at on purpose: nobody was told, and the table has to '
  'say so.';
COMMENT ON COLUMN public.notification_outbox.expiry_reason IS
  'Why it was dropped. Not last_error, which is a delivery failure and is '
  'retried; an expiry is final.';

-- The drain query reads undelivered AND unexpired. The old partial index was
-- `WHERE delivered_at IS NULL`, which after this change covers every retired row
-- for ever — the backlog this migration exists to retire would stay in the hot
-- path of the one query that runs every minute.
DROP INDEX IF EXISTS public.notification_outbox_pending_idx;
CREATE INDEX IF NOT EXISTS notification_outbox_pending_idx
  ON public.notification_outbox (next_attempt_at)
  WHERE delivered_at IS NULL AND expired_at IS NULL;

-- ── How long a notice is worth sending ──────────────────────────────────────
--
-- Same shape as `tier_timeout_minutes()`, and for the same reason: a missing or
-- malformed setting must not mean something dangerous. Here the dangerous
-- readings are a shelf life of 0 (drop everything, the queue silently delivers
-- nothing) and NULL read as infinite (the behaviour this file is fixing). Both
-- fall back to the default.
--
-- 60 minutes, because the shortest escalation timeout in `app_config` is
-- measured in minutes and the longest is well under an hour: a notice still
-- undelivered an hour after it was queued has been overtaken by the incident it
-- describes.

INSERT INTO public.app_config (key, value)
VALUES ('notification_shelf_life_minutes', '60')
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.notification_shelf_life_minutes()
RETURNS INTEGER
LANGUAGE plpgsql STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  raw    TEXT;
  parsed INTEGER;
BEGIN
  SELECT value INTO raw FROM public.app_config
   WHERE key = 'notification_shelf_life_minutes';

  BEGIN
    parsed := raw::INTEGER;
  EXCEPTION WHEN others THEN
    RETURN 60;
  END;

  IF parsed IS NULL OR parsed <= 0 THEN
    RETURN 60;
  END IF;
  RETURN parsed;
END;
$$;

COMMENT ON FUNCTION public.notification_shelf_life_minutes() IS
  'Minutes a queued notification is still worth delivering. Refuses 0, NULL '
  'and anything unparseable, because each of those readings silently empties '
  'or never empties the queue.';

-- ── Which rows have had their moment ────────────────────────────────────────
--
-- Two conditions, and the second is the one that matters even with the worker
-- running every minute:
--
--   age   queued longer ago than the shelf life.
--   over  the incident it is about is closed. A dispatcher resolving an alert
--         ten seconds after the tier timed out leaves a queued notice that
--         sends a unit to a finished incident. That race exists at any drain
--         frequency, and no retry policy fixes it.
--
-- Rows with no `alert_id` (a plain SMS, PUSH or WEBHOOK) are judged on age
-- alone; there is no incident to ask about.

CREATE OR REPLACE FUNCTION public.notification_is_stale(
  p_row public.notification_outbox)
RETURNS TEXT
LANGUAGE sql STABLE
SET search_path = public, pg_temp
AS $$
  SELECT CASE
    WHEN p_row.created_at <
           NOW() - make_interval(mins => public.notification_shelf_life_minutes())
      THEN format('queued %s ago, past the %s minute shelf life',
                  justify_interval(date_trunc('minute', NOW() - p_row.created_at)),
                  public.notification_shelf_life_minutes())
    WHEN p_row.alert_id IS NOT NULL AND EXISTS (
           SELECT 1 FROM public.alerts a
            WHERE a.id = p_row.alert_id
              AND a.status IN ('RESOLVED', 'CANCELLED'))
      THEN 'the incident it is about is closed'
    ELSE NULL
  END;
$$;

COMMENT ON FUNCTION public.notification_is_stale(public.notification_outbox) IS
  'Why this notice is no longer worth sending, or NULL if it still is. One '
  'definition, so the claim path and the operator sweep cannot disagree.';

-- ── Retiring them ───────────────────────────────────────────────────────────
--
-- Callable on its own, because an operator about to schedule the drainer for the
-- first time should be able to see what the queue is holding and retire it
-- deliberately, with a count in front of them, rather than discover it as
-- traffic. It returns what it retired and why.

CREATE OR REPLACE FUNCTION public.expire_stale_notifications()
RETURNS TABLE (kind TEXT, reason TEXT, retired BIGINT)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH stale AS (
    SELECT o.id, public.notification_is_stale(o) AS why
      FROM public.notification_outbox o
     WHERE o.delivered_at IS NULL
       AND o.expired_at IS NULL
  ),
  retired AS (
    UPDATE public.notification_outbox o
       SET expired_at    = NOW(),
           expiry_reason = s.why
      FROM stale s
     WHERE o.id = s.id AND s.why IS NOT NULL
    RETURNING o.kind, o.expiry_reason
  )
  SELECT r.kind, r.expiry_reason, count(*)
    FROM retired r
   GROUP BY r.kind, r.expiry_reason
   ORDER BY count(*) DESC;
$$;

COMMENT ON FUNCTION public.expire_stale_notifications() IS
  'Retires every queued notice whose moment has passed, and reports what it '
  'retired. Run this before scheduling the drainer on a queue that has been '
  'standing: the alternative is delivering the backlog as live traffic.';

REVOKE ALL ON FUNCTION public.expire_stale_notifications() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.expire_stale_notifications() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.expire_stale_notifications() TO service_role;

-- ── And the claim path enforces it, so no worker has to ─────────────────────
--
-- Expiry runs FIRST and UNBOUNDED, before the LIMIT. Doing it inside the claim
-- CTE instead would mean the worker spends a tick per twenty stale rows: with
-- 412 standing, the first live notice would wait twenty-one minutes. An
-- emergency queue cannot have a warm-up period.
--
-- Same body as 20261007000000_notification_outbox.sql otherwise: the claim
-- increments `attempts` and holds the row off for a minute so a worker that
-- dies mid-send does not have it taken again immediately.

CREATE OR REPLACE FUNCTION public.claim_notifications(p_limit INTEGER DEFAULT 20)
RETURNS SETOF public.notification_outbox
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Not conditional on a backlog existing, and not something the caller can
  -- skip. A notice whose moment has passed must not be handed to a worker, and
  -- the worker is the wrong place to decide that: there are two of them.
  PERFORM public.expire_stale_notifications();

  RETURN QUERY
  WITH due AS (
    SELECT o.id
      FROM public.notification_outbox o
     WHERE o.delivered_at IS NULL
       AND o.expired_at IS NULL
       AND o.next_attempt_at <= NOW()
     ORDER BY o.next_attempt_at
     LIMIT GREATEST(COALESCE(p_limit, 20), 1)
     FOR UPDATE SKIP LOCKED
  )
  UPDATE public.notification_outbox o
     SET attempts = o.attempts + 1,
         next_attempt_at = NOW() + INTERVAL '1 minute'
    FROM due
   WHERE o.id = due.id
  RETURNING o.*;
END;
$$;

COMMENT ON FUNCTION public.claim_notifications(INTEGER) IS
  'Hands out notices still worth sending, oldest first, retiring the rest. The '
  'shelf life is enforced here rather than in each worker, because there are '
  'two workers and a rule written twice drifts.';

REVOKE ALL ON FUNCTION public.claim_notifications(INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.claim_notifications(INTEGER) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_notifications(INTEGER) TO service_role;

-- ── What the queue is holding, before anybody schedules anything ────────────

CREATE OR REPLACE FUNCTION public.notification_queue_status()
RETURNS TABLE (state TEXT, notices BIGINT, oldest TIMESTAMPTZ, newest TIMESTAMPTZ)
LANGUAGE sql STABLE
SET search_path = public, pg_temp
AS $$
  SELECT state, count(*), min(created_at), max(created_at)
    FROM (
      SELECT o.created_at,
             CASE
               WHEN o.delivered_at IS NOT NULL THEN 'delivered'
               WHEN o.expired_at   IS NOT NULL THEN 'retired undelivered'
               WHEN public.notification_is_stale(o) IS NOT NULL
                 THEN 'would be retired on the next claim'
               ELSE 'still worth sending'
             END AS state
        FROM public.notification_outbox o
    ) s
   GROUP BY state
   ORDER BY count(*) DESC;
$$;

COMMENT ON FUNCTION public.notification_queue_status() IS
  'The queue in four states, with the age range of each. Read this before '
  'scheduling the drainer on a queue that has been standing.';

GRANT EXECUTE ON FUNCTION public.notification_queue_status() TO service_role;

-- ----------------------------------------------------------------------------
-- 20261030000000_a_shelter_says_who_stood_there.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261030000000_a_shelter_says_who_stood_there.sql'; END $apply$;

-- The shelter a fleeing citizen is routed to is 11km away, in another LGA.
--
-- ## What `safe_zones` actually contains
--
-- `safe_zone_screen.dart` shows a citizen where to run and draws a route to the
-- nearest one. It used to invent three shelters in a `catch` block; that was
-- fixed, and the screen now reads this table. `phase1_foundation.sql` fills it
-- with seven rows, and the numbers say where they came from:
--
--   PLATEAU STATE HQ          9.9167, 8.8917   the centroid of Jos, to 4dp —
--                                              the same literal this project
--                                              deleted from ai-triage, where it
--                                              was being written into `alerts`
--                                              as the position of a report with
--                                              no fix
--   BARKIN LADI SAFE POINT    9.5167, 8.9167   9°31'00", 8°55'00"
--   MANGU COMMAND POST        9.7167, 9.0500   9°43'00", 9°03'00"
--
-- Round to the arc-minute is what a gazetteer gives for a TOWN. And the
-- fallback that was deleted had `JOS SOUTH COMMAND HQ` at 9.9285, 8.8921 while
-- this seed has it at 9.8965, 8.8583 — two positions, 3.6km apart, for one
-- place. Neither was measured; that is why they disagree.
--
-- ## Three of them are in the wrong LGA, and that is checkable
--
-- `hq-dashboard-next/src/lib/ward_centroids.ts` holds 207 surveyed ward
-- centroids with an honest radius each, generated from the app's own ward
-- asset. Measured against the LGA each shelter row CLAIMS:
--
--   JOS SOUTH COMMAND HQ       11.24 km from the nearest JOS SOUTH ward
--                              centroid (GIRING, r=1.7km) — 9.6km outside it.
--                              The position is in Jos North.
--   MANGU COMMAND POST          9.69 km from the nearest MANGU ward centroid
--                              (KADUNU, r=4.2km) — 5.5km outside it. The
--                              position is in Barkin Ladi.
--   JOS EAST TACTICAL OUTPOST   4.59 km from SHERE WEST (r=4.0km) — 635m
--                              outside it. Marginal, and still not inside.
--
-- So a citizen in Jos South, fleeing, is given turn directions to a point
-- eleven kilometres away in a different local government area, labelled as the
-- Jos South command HQ. The other four are at least internally consistent.
--
-- ## What this migration does about it
--
-- It does NOT invent better coordinates. Nobody here has stood at these places,
-- and replacing one guess with another is how there came to be two positions
-- for Jos South Command HQ in the first place.
--
-- Instead:
--
--   * `verified_at` / `verified_by` — the row records whether a person put
--     their name to the position. All seven start unverified, because none was
--     measured. The app can then tell the citizen which it is, the way USSD
--     reports carry `is_confirmed`.
--   * the three whose position contradicts their own LGA are DEACTIVATED, not
--     deleted. `is_active = false` is this table's own mechanism and the
--     citizen screen already filters on it, so the dangerous route stops
--     without destroying a row command may want to correct. They are real
--     places — a police division and two outposts exist — and what is wrong is
--     the number, which only somebody there can fix.
--   * `publish_safe_zone()` / `verify_safe_zone()` / `retire_safe_zone()`, so
--     command can enter a real one and say who confirmed it. There was no way
--     to add or correct a shelter at all before this: the policy to write one
--     has existed since 20260813000000 and nothing has ever called it.
--
-- A database cannot know whether a coordinate is real. What it can insist on is
-- that somebody's id is against it.

-- ── One shelter, one row ────────────────────────────────────────────────────
--
-- The seed ends `ON CONFLICT DO NOTHING` with no conflict target, and the
-- primary key is `gen_random_uuid()`. A generated key never conflicts, so the
-- clause matches nothing and re-running phase1_foundation.sql inserts all seven
-- AGAIN — the citizen screen would list each shelter twice, and route to
-- whichever copy sorted first. Deduplicate before the constraint, oldest kept.

DELETE FROM public.safe_zones z
 WHERE EXISTS (
   SELECT 1 FROM public.safe_zones keep
    WHERE keep.name = z.name
      AND (keep.created_at, keep.id) < (z.created_at, z.id));

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conname = 'safe_zones_name_unique'
       AND conrelid = 'public.safe_zones'::regclass
  ) THEN
    ALTER TABLE public.safe_zones
      ADD CONSTRAINT safe_zones_name_unique UNIQUE (name);
  END IF;
END $$;

-- ── Did anybody stand here? ─────────────────────────────────────────────────

ALTER TABLE public.safe_zones
  ADD COLUMN IF NOT EXISTS verified_at TIMESTAMPTZ;
ALTER TABLE public.safe_zones
  ADD COLUMN IF NOT EXISTS verified_by UUID REFERENCES public.profiles(id);

COMMENT ON COLUMN public.safe_zones.verified_at IS
  'When somebody confirmed this position on the ground. NULL means the '
  'coordinates are a guess and the app must say so before routing anybody.';
COMMENT ON COLUMN public.safe_zones.verified_by IS
  'Who confirmed it. A position with nobody against it is not confirmed.';

-- A position outside Plateau State is a typo or a 0,0, and 0,0 is the Gulf of
-- Guinea — a point this project has already drawn on a map as a shelter. The
-- bounds are the extent of the 207 surveyed ward centroids in
-- hq-dashboard-next/src/lib/ward_centroids.ts (lat 8.4501-10.2802,
-- lon 8.5861-10.4651), rounded outward by a tenth of a degree. They are a
-- BOUND, not a position: no row is ever placed at one.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conname = 'safe_zones_within_plateau'
       AND conrelid = 'public.safe_zones'::regclass
  ) THEN
    ALTER TABLE public.safe_zones
      ADD CONSTRAINT safe_zones_within_plateau CHECK (
        latitude  BETWEEN 8.3 AND 10.4
        AND longitude BETWEEN 8.4 AND 10.6
      ) NOT VALID;
  END IF;
END $$;
-- NOT VALID, then validated separately: on a database whose existing rows
-- somehow fall outside, the ALTER would fail and take the whole migration with
-- it. This way the constraint applies to every new row immediately and the
-- validation of the old ones reports rather than aborts.
DO $$
BEGIN
  ALTER TABLE public.safe_zones VALIDATE CONSTRAINT safe_zones_within_plateau;
EXCEPTION WHEN check_violation THEN
  RAISE WARNING
    'safe_zones holds row(s) outside Plateau State. New rows are now refused; '
    'the existing ones need looking at: select id, name, latitude, longitude '
    'from public.safe_zones where latitude not between 8.3 and 10.4 or '
    'longitude not between 8.4 and 10.6;';
END $$;

-- ── The seven, where they came from, and what is wrong with three ───────────
--
-- Moved here from phase1_foundation.sql so that `verified_at` is named in the
-- same statement as the coordinates. That is what
-- scripts/check_no_invented_coordinates.py now requires of any stored
-- position: in SQL there is no empty state to fall back to and no screen that
-- can tell, so the row itself has to carry its provenance.
--
-- ON CONFLICT (name) now has a target that exists, so this is genuinely
-- idempotent and a production database that already has these seven is
-- untouched by it.

INSERT INTO public.safe_zones
  (name, description, latitude, longitude, type, geo_lga, verified_at)
VALUES
  ('JOS SOUTH COMMAND HQ',      'Primary tactical operations centre',  9.8965, 8.8583, 'COMMAND_HQ', 'JOS SOUTH',   NULL),
  ('BUKURU TACTICAL OUTPOST',   'Forward operating base, Bukuru',      9.7952, 8.8521, 'OUTPOST',    'JOS SOUTH',   NULL),
  ('JOS NORTH POLICE DIVISION', 'Jos North Police Headquarters',       9.9281, 8.8921, 'POLICE',     'JOS NORTH',   NULL),
  ('PLATEAU STATE HQ',          'State Government HQ Command Centre',  9.9167, 8.8917, 'COMMAND_HQ', 'JOS NORTH',   NULL),
  ('JOS EAST TACTICAL OUTPOST', 'Jos East forward operating base',     9.9500, 8.9600, 'OUTPOST',    'JOS EAST',    NULL),
  ('BARKIN LADI SAFE POINT',    'Barkin Ladi civilian safe assembly',  9.5167, 8.9167, 'SAFE_POINT', 'BARKIN LADI', NULL),
  ('MANGU COMMAND POST',        'Mangu LGA tactical command post',     9.7167, 9.0500, 'COMMAND_HQ', 'MANGU',       NULL)
ON CONFLICT (name) DO NOTHING;

-- The three whose position is outside every ward of the LGA they claim. Matched
-- on the exact coordinates as well as the name, so a row command has since
-- corrected is left alone — this must not reach in and switch off a shelter
-- somebody has fixed and verified.
UPDATE public.safe_zones
   SET is_active = false,
       description = description || ' [POSITION NOT CONFIRMED: this point is '
                     || 'outside every surveyed ward of ' || geo_lga
                     || '. Hidden from the citizen app until somebody confirms '
                     || 'where it is. Use publish_safe_zone() to correct it.]'
 WHERE is_active IS NOT false
   AND verified_at IS NULL
   AND (name, latitude, longitude) IN (
     ('JOS SOUTH COMMAND HQ',      9.8965, 8.8583),
     ('JOS EAST TACTICAL OUTPOST', 9.9500, 8.9600),
     ('MANGU COMMAND POST',        9.7167, 9.0500)
   );

-- ── Command can enter a real one ────────────────────────────────────────────
--
-- `safe_zones_write_command` has allowed this since 20260813000000 and nothing
-- has ever written a row — which is why nobody noticed that, until
-- 20261028000000, only 2 of the project's 22 staff accounts satisfied
-- `is_command()` at all.
--
-- These are functions rather than a bare table write so that the position is
-- checked and the actor is recorded in one place, whichever screen calls them.

CREATE OR REPLACE FUNCTION public.publish_safe_zone(
  p_name      TEXT,
  p_latitude  DOUBLE PRECISION,
  p_longitude DOUBLE PRECISION,
  p_type      TEXT DEFAULT 'SAFE_POINT',
  p_geo_lga   TEXT DEFAULT NULL,
  p_geo_ward  TEXT DEFAULT NULL,
  p_capacity  INTEGER DEFAULT NULL,
  p_description TEXT DEFAULT NULL,
  p_verified  BOOLEAN DEFAULT false)
RETURNS public.safe_zones
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE row_out public.safe_zones;
BEGIN
  IF NOT public.is_command() THEN
    RAISE EXCEPTION 'only command may publish a shelter'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF coalesce(btrim(p_name), '') = '' THEN
    RAISE EXCEPTION 'a shelter needs a name somebody can ask directions to';
  END IF;
  IF p_latitude IS NULL OR p_longitude IS NULL THEN
    RAISE EXCEPTION
      'a shelter with no position cannot be routed to. Leave it out rather '
      'than storing a guess';
  END IF;

  INSERT INTO public.safe_zones
    (name, description, latitude, longitude, type, geo_lga, geo_ward,
     capacity, is_active, verified_at, verified_by)
  VALUES
    (btrim(p_name), p_description, p_latitude, p_longitude,
     coalesce(p_type, 'SAFE_POINT'),
     public.normalise_lga(p_geo_lga), p_geo_ward, p_capacity, true,
     -- Verified means a person is saying they know where this is. The caller
     -- has to claim it explicitly; the default is a position nobody has
     -- confirmed, which is what every row in this table was.
     CASE WHEN p_verified THEN NOW() END,
     CASE WHEN p_verified THEN auth.uid() END)
  ON CONFLICT (name) DO UPDATE
     SET description = COALESCE(EXCLUDED.description, public.safe_zones.description),
         latitude    = EXCLUDED.latitude,
         longitude   = EXCLUDED.longitude,
         type        = EXCLUDED.type,
         geo_lga     = EXCLUDED.geo_lga,
         geo_ward    = EXCLUDED.geo_ward,
         capacity    = EXCLUDED.capacity,
         is_active   = true,
         verified_at = EXCLUDED.verified_at,
         verified_by = EXCLUDED.verified_by
  RETURNING * INTO row_out;

  RETURN row_out;
END;
$$;

COMMENT ON FUNCTION public.publish_safe_zone(
  TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT, TEXT, TEXT, INTEGER, TEXT,
  BOOLEAN) IS
  'Adds or corrects a shelter. Command only. A position is unverified unless '
  'the caller claims otherwise, and then their id is stored against it.';

CREATE OR REPLACE FUNCTION public.verify_safe_zone(p_id UUID)
RETURNS public.safe_zones
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE row_out public.safe_zones;
BEGIN
  IF NOT public.is_command() THEN
    RAISE EXCEPTION 'only command may confirm a shelter position'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE public.safe_zones
     SET verified_at = NOW(), verified_by = auth.uid(), is_active = true
   WHERE id = p_id
  RETURNING * INTO row_out;
  IF row_out.id IS NULL THEN
    RAISE EXCEPTION 'no shelter with id %', p_id;
  END IF;
  RETURN row_out;
END;
$$;

COMMENT ON FUNCTION public.verify_safe_zone(UUID) IS
  'Records that this position has been confirmed on the ground, and by whom. '
  'Reactivates a shelter that was hidden for an unconfirmed position.';

CREATE OR REPLACE FUNCTION public.retire_safe_zone(p_id UUID, p_why TEXT DEFAULT NULL)
RETURNS public.safe_zones
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE row_out public.safe_zones;
BEGIN
  IF NOT public.is_command() THEN
    RAISE EXCEPTION 'only command may retire a shelter'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- Deactivated, never deleted. A shelter that was real last month is part of
  -- the record of where people were sent.
  UPDATE public.safe_zones
     SET is_active = false,
         description = CASE
           WHEN coalesce(btrim(p_why), '') = '' THEN description
           ELSE coalesce(description || ' ', '') || '[RETIRED: ' || btrim(p_why) || ']'
         END
   WHERE id = p_id
  RETURNING * INTO row_out;
  IF row_out.id IS NULL THEN
    RAISE EXCEPTION 'no shelter with id %', p_id;
  END IF;
  RETURN row_out;
END;
$$;

COMMENT ON FUNCTION public.retire_safe_zone(UUID, TEXT) IS
  'Hides a shelter from the citizen app without deleting it.';

REVOKE ALL ON FUNCTION public.publish_safe_zone(
  TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT, TEXT, TEXT, INTEGER, TEXT,
  BOOLEAN) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.verify_safe_zone(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.retire_safe_zone(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.publish_safe_zone(
  TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT, TEXT, TEXT, INTEGER, TEXT,
  BOOLEAN) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.verify_safe_zone(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.retire_safe_zone(UUID, TEXT) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 20261031000000_a_ward_is_not_called_ward.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261031000000_a_ward_is_not_called_ward.sql'; END $apply$;

-- A ward officer posted to "BUKURU WARD" never sees an incident in BUKURU.
--
-- ## What the live project has
--
-- Section 4 of `why_is_the_board_empty.sql` lists the geographies incidents are
-- filed under. The operator's run came back with, among others:
--
--     JOS SOUTH / BUKURU           n incident(s)
--     JOS SOUTH / BUKURU WARD      n incident(s)
--
-- and `BUKURU WARD` appearing under SIX different LGAs.
--
-- `assets/geo/plateau_wards.json` has 207 wards across the 17 LGAs of Plateau
-- State. `BUKURU` is one of them, in JOS SOUTH, and in no other LGA. **Not one
-- of the 207 ward names ends in " WARD", and not one of the 17 LGA names ends
-- in " LGA".** So the suffix is never part of a real name: it is a word somebody
-- typed into a form that already said "Ward".
--
-- ## Why that is not cosmetic
--
-- `alert_in_my_area()` decides whether a staff account sees an incident, and
-- since 20261009000000 it compares place names through `geo_key()`:
--
--     public.geo_key(a.geo_lga) = public.geo_key(p.geo_lga)
--     AND public.geo_key(a.geo_ward) = public.geo_key(p.geo_ward)
--
-- `geo_key` upper-cases, collapses whitespace and rewrites a trailing Roman
-- numeral — which is what it was written for, because the app and the tactical
-- map spell four Mangu wards differently. It does not touch a trailing " WARD".
--
--     geo_key('BUKURU')       -> 'BUKURU'
--     geo_key('BUKURU WARD')  -> 'BUKURU WARD'
--
-- Different keys. So a ward commander posted to `JOS SOUTH / BUKURU WARD` is
-- refused every incident filed at `JOS SOUTH / BUKURU`, and the other way
-- round. Their board is empty and the rows are right there. That is the same
-- failure 20261009000000 fixed for Roman numerals, in the suffix it did not
-- know about — and this time it is both halves of the comparison, because the
-- posting and the report are typed by different people into different forms.
--
-- The six-LGA `BUKURU WARD` is the other half of it: a ward that exists only in
-- Jos South was recorded as the posting of staff in five LGAs that do not have
-- it. Those accounts match no incident under the ward branch at all. That is an
-- operator data problem and not something a migration can fix — but
-- `scripts/which_geography_is_real.sql` now names every such row, which it
-- could not before.
--
-- ## Why stripping the suffix is safe, and not a guess
--
-- Zero of the 207 surveyed ward names end in " WARD" and zero of the 17 LGA
-- names end in " LGA". So this strip cannot merge two distinct real places: it
-- has nothing to collide with. `check_a_ward_name_resolves.py` asserts exactly
-- that against the asset, so the day a ward called "X WARD" is added, CI says
-- so instead of two wards quietly becoming one.
--
-- Only those two tokens, and only trailing. "DISTRICT", "LGC" and the rest are
-- not stripped because none has been observed, and an unobserved strip is a
-- guess with somebody's board on the other end of it.

-- ── The hazard this migration has to handle ─────────────────────────────────
--
-- `geo_key()` is IMMUTABLE and 20261009000000 INDEXES it:
--
--     CREATE INDEX alerts_geo_key_idx
--       ON public.alerts (geo_key(geo_lga), geo_key(geo_ward), geo_key(geo_pu));
--     CREATE INDEX profiles_geo_key_idx ON public.profiles (...);
--
-- IMMUTABLE is a promise that the same input always gives the same output, and
-- PostgreSQL believes it: the index holds values computed under the OLD body and
-- is not rebuilt when the function is replaced. An index scan would then look up
-- 'BUKURU' among keys computed as 'BUKURU WARD' and find nothing — so replacing
-- the function WITHOUT reindexing would leave the bug in place for exactly the
-- queries that use the index, while a sequential scan returned the right answer.
-- Intermittent, by query plan.
--
-- So both indexes are rebuilt below, and the replay asserts the lookup works
-- with `enable_seqscan = off`, which is the only way to prove the index itself
-- carries the new keys rather than the planner having stepped around it.
--
-- ── Rebuild what believed the old body ─────────────────────────────────────

CREATE OR REPLACE FUNCTION public.geo_key(p_name TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = pg_catalog, pg_temp
AS $$
  SELECT nullif(
    -- A trailing WARD or LGA is the word the form already said. Applied LAST,
    -- after the whitespace collapse, so 'BUKURU   WARD' is reduced to
    -- 'BUKURU WARD' before the suffix is looked for; and before nothing, so a
    -- ward genuinely called 'WARD' would be left alone rather than emptied —
    -- the anchor needs a space and at least one character in front of it.
    regexp_replace(
      -- Trailing Roman numerals to Arabic, longest first so 'III' is not read
      -- as 'I' followed by 'II'. Anchored at the end: a ward called
      -- "VICTORIA II" keeps its name and only the numeral is rewritten, and a
      -- ward with an I in the middle of a word is untouched.
      regexp_replace(
        regexp_replace(
          regexp_replace(
            regexp_replace(
              upper(trim(coalesce(p_name, ''))),
              '\s+', ' ', 'g'),
            '(.)\s+(WARD|LGA)$', '\1'),
          '\s+III$', ' 111'),
        '\s+II$', ' 11'),
      '\s+I$', ' 1'),
    '');
$$;

COMMENT ON FUNCTION public.geo_key(TEXT) IS
  'The form two place names are compared in: upper-cased, runs of whitespace '
  'collapsed, a trailing Roman numeral written in the Arabic form the tactical '
  'map uses, and a trailing WARD or LGA dropped. GINDIRI  I and GINDIRI  1 are '
  'the same ward; so are BUKURU and BUKURU WARD. None of the 207 surveyed ward '
  'names ends in WARD and none of the 17 LGA names ends in LGA, so the strip '
  'has no real name to collide with.';

-- ── Rebuild what believed the old body ──────────────────────────────────────
--
-- REINDEX, not DROP and CREATE: it keeps the index definition, the name and the
-- ownership, and it is the statement whose whole purpose is this situation.
-- Wrapped per index so a database that lacks one — a staging database built
-- before 20261009000000 — is not stopped by it.
-- REINDEX, not DROP and CREATE: it keeps the index definition, the name and the
-- ownership, and it is the statement whose whole purpose is this situation.
-- `REINDEX INDEX` is permitted inside a transaction block, unlike REINDEX
-- DATABASE and CONCURRENTLY, so this is safe in the one-paste bundle.
--
-- Each index named in its own statement, beside its own existence test. A loop
-- over an array of names reads better and puts the name and the REINDEX in
-- different statements, where `check_a_ward_name_resolves.py` cannot pair them
-- — and that check is the only thing standing between the next person who
-- replaces an indexed IMMUTABLE function and a bug that is right or wrong by
-- query plan. Written so it is verifiable.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
              WHERE n.nspname = 'public' AND c.relname = 'alerts_geo_key_idx'
                AND c.relkind = 'i') THEN
    EXECUTE 'REINDEX INDEX public.alerts_geo_key_idx';
    RAISE NOTICE 'rebuilt alerts_geo_key_idx, which held keys computed under the old geo_key()';
  ELSE
    RAISE NOTICE 'alerts_geo_key_idx is not on this database; nothing to rebuild';
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
              WHERE n.nspname = 'public' AND c.relname = 'profiles_geo_key_idx'
                AND c.relkind = 'i') THEN
    EXECUTE 'REINDEX INDEX public.profiles_geo_key_idx';
    RAISE NOTICE 'rebuilt profiles_geo_key_idx, which held keys computed under the old geo_key()';
  ELSE
    RAISE NOTICE 'profiles_geo_key_idx is not on this database; nothing to rebuild';
  END IF;
END $$;

-- ── What this just repaired, in rows ────────────────────────────────────────
--
-- Reported rather than asserted: the number is whatever the operator's data
-- holds, and the point is that they see it. A database with none of this is
-- told so, which is also worth knowing.
DO $$
DECLARE
  n_alerts   INTEGER;
  n_profiles INTEGER;
BEGIN
  SELECT count(*) INTO n_alerts FROM public.alerts
   WHERE upper(trim(coalesce(geo_ward, ''))) LIKE '% WARD'
      OR upper(trim(coalesce(geo_lga,  ''))) LIKE '% LGA';
  SELECT count(*) INTO n_profiles FROM public.profiles
   WHERE upper(trim(coalesce(geo_ward, ''))) LIKE '% WARD'
      OR upper(trim(coalesce(geo_lga,  ''))) LIKE '% LGA';

  IF n_alerts = 0 AND n_profiles = 0 THEN
    RAISE NOTICE
      'No incident or posting on this database carries a trailing WARD or LGA.';
  ELSE
    RAISE NOTICE
      '% incident(s) and % posting(s) carry a trailing WARD or LGA. They now '
      'compare equal to the same place without it, so a ward officer posted to '
      '"X WARD" sees incidents filed at "X". Run '
      'scripts/which_geography_is_real.sql for the ones that are still not a '
      'real place at all.', n_alerts, n_profiles;
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 20261101000000_one_rung_one_list.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261101000000_one_rung_one_list.sql'; END $apply$;

-- A ward escalation was addressed to nobody, and so was an LGA one.
--
-- ## What the deployment carries
--
-- The production project's 22 staff accounts are spelled `STATE_COMMANDER`
-- (×4), `LGA_COMMANDER` (×4), `WARD_COMMANDER` (×4) and
-- `POLLING_UNIT_OFFICER` (×6). This repository was written against
-- `HQ_COMMAND` / `LGA_COMMAND` / `WARD_COMMAND` / `UNIT_COMMAND`.
--
-- `20261028000000_command_knows_both_vocabularies` taught `is_command()` and
-- `commands_whole_state()` both spellings. It did not touch
-- `escalation_push_targets()`, which carries FOUR MORE exact-match lists of
-- its own — and that function decides whose phone an automatic escalation
-- reaches:
--
--     WHEN 'UNIT' THEN ARRAY['UNIT_COMMAND','POLLING_UNIT_OFFICER','POLLING_OFFICER']
--     WHEN 'WARD' THEN ARRAY['WARD_COMMAND','WARD_OFFICER']
--     WHEN 'LGA'  THEN ARRAY['LGA_COMMAND','LGA_OFFICER']
--     WHEN 'HQ'   THEN ARRAY['HQ_COMMAND','HQ_OFFICER','ADMIN']
--
-- Against that deployment:
--
--     WARD -> 0 recipients   (WARD_COMMANDER is not WARD_COMMAND)
--     LGA  -> 0 recipients   (LGA_COMMANDER is not LGA_COMMAND)
--     HQ   -> 1 recipient    (the single HQ_COMMAND account)
--     UNIT -> 6 recipients   — works, and only because somebody hit this for
--                              that one rung and added POLLING_UNIT_OFFICER to
--                              that one list
--
-- `deliverTierEscalation` throws "no reachable officer at that tier" on an
-- empty list — deliberately, so the notice is retried rather than recorded as
-- delivered. So every ward and LGA escalation on that project was a
-- notification that could never be delivered to anybody, for ever. The
-- automatic escalation moved the incident and told nobody, which is the exact
-- failure `20261007000000_notification_outbox` was written to end.
--
-- ## One list, derived
--
-- Adding three names to four arrays fixes today and leaves the shape that
-- produced this. `roles_for_tier()` is the only place in SQL a staff role name
-- is written against a rung, and `escalation_push_targets()` asks it. The
-- console's `src/lib/command-roles.ts` and the app's `staffRoleTiers` are the
-- same decision in the other two languages, and
-- `scripts/check_one_command_vocabulary.py` asserts all three agree — it used
-- to read two of them, which is why this survived T-85 and T-90.
--
-- See E2E_AUDIT_REPORT.md T-97.

CREATE OR REPLACE FUNCTION public.roles_for_tier(p_tier TEXT)
RETURNS TEXT[]
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = pg_catalog, pg_temp
AS $$
  SELECT CASE upper(coalesce(btrim(p_tier), ''))
    -- Both spellings of the rung, and both desk names. An escalation is
    -- addressed to a desk rather than to a person: at two in the morning the
    -- commander is not necessarily the one awake.
    WHEN 'UNIT' THEN ARRAY[
      'UNIT_COMMAND', 'POLLING_UNIT_OFFICER', 'POLLING_OFFICER']
    WHEN 'WARD' THEN ARRAY[
      'WARD_COMMAND', 'WARD_COMMANDER', 'WARD_OFFICER']
    WHEN 'LGA' THEN ARRAY[
      'LGA_COMMAND', 'LGA_COMMANDER', 'LGA_OFFICER']
    WHEN 'HQ' THEN ARRAY[
      'HQ_COMMAND', 'STATE_COMMANDER', 'HQ_OFFICER', 'ADMIN']
    -- A tier nobody holds addresses nobody. Failing open here would page the
    -- whole state on a malformed payload.
    ELSE ARRAY[]::TEXT[]
  END;
$$;

COMMENT ON FUNCTION public.roles_for_tier(TEXT) IS
  'Every staff role that holds a rung, in both the vocabulary this repository '
  'is written against and the one the deployment actually carries. The single '
  'SQL definition: escalation_push_targets() asks it rather than carrying its '
  'own lists, which is how a ward escalation came to be addressed to nobody.';

REVOKE ALL ON FUNCTION public.roles_for_tier(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.roles_for_tier(TEXT)
  TO anon, authenticated, service_role;

-- ── And the one caller asks it ──────────────────────────────────────────────
--
-- Same body as 20261009000000 otherwise: the geography branch is unchanged, HQ
-- is still statewide and unfiltered, and an incident with no location still
-- reaches the tier regardless of posting.

CREATE OR REPLACE FUNCTION public.escalation_push_targets(p_outbox_id BIGINT)
RETURNS TABLE (user_id UUID, player_id TEXT, role TEXT)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
  WITH notice AS (
    SELECT o.payload
      FROM public.notification_outbox o
     WHERE o.id = p_outbox_id
       AND o.kind = 'TIER_ESCALATION'
  ),
  want AS (
    SELECT upper(coalesce(payload ->> 'to_tier', ''))  AS tier,
           public.geo_key(payload ->> 'geo_lga')       AS lga,
           public.geo_key(payload ->> 'geo_ward')      AS ward,
           public.geo_key(payload ->> 'geo_pu')        AS pu
      FROM notice
  )
  SELECT p.id, p.onesignal_player_id, p.role
    FROM public.profiles p, want w
   WHERE p.onesignal_player_id IS NOT NULL
     AND length(p.onesignal_player_id) > 5
     AND upper(coalesce(p.role, '')) = ANY (public.roles_for_tier(w.tier))
     AND (
       w.tier = 'HQ'
       OR w.lga IS NULL
       OR (
         public.geo_key(p.geo_lga) = w.lga
         AND (w.tier <> 'WARD' OR w.ward IS NULL
              OR public.geo_key(p.geo_ward) = w.ward)
         AND (w.tier <> 'UNIT' OR w.pu IS NULL
              OR public.geo_key(p.geo_pu) = w.pu)
       )
     );
$$;

COMMENT ON FUNCTION public.escalation_push_targets(BIGINT) IS
  'Whose phone an automatic escalation is for. Roles come from '
  'roles_for_tier(); geography is compared through geo_key(), and HQ is '
  'statewide and unfiltered because its job is everything.';

REVOKE ALL ON FUNCTION public.escalation_push_targets(BIGINT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.escalation_push_targets(BIGINT)
  FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.escalation_push_targets(BIGINT) TO service_role;

-- ── What this just changed, in accounts ─────────────────────────────────────
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT t.tier,
           count(*) FILTER (
             WHERE upper(coalesce(p.role, '')) = ANY (public.roles_for_tier(t.tier))
           ) AS reachable
      FROM (VALUES ('HQ'), ('LGA'), ('WARD'), ('UNIT')) AS t(tier)
      LEFT JOIN public.profiles p ON true
     GROUP BY t.tier
     ORDER BY t.tier
  LOOP
    RAISE NOTICE 'tier % is now held by % account(s) on this database',
      r.tier, r.reachable;
  END LOOP;
  RAISE NOTICE
    'A tier reading 0 has nobody to escalate to: that is a staffing or a '
    'profiles.role spelling problem, not a code one. Run '
    'scripts/why_is_the_board_empty.sql for the role table.';
END $$;

-- ----------------------------------------------------------------------------
-- 20261102000000_one_officer_one_account.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261102000000_one_officer_one_account.sql'; END $apply$;

-- One officer, two accounts, and the posting is on the other one.
--
-- ## What the deployment has
--
-- Duplicate staff accounts across two email domains. Staff do not sign in with
-- an email — they type a badge, and the app turns it into one:
--
--     '$trimmed@operationrainbow.plateau.gov.ng'
--
-- with the console carrying its own copy of that domain. The domain is the
-- second half of the primary key of a person: provision an account under a
-- different one, or change it, and the SAME badge resolves to a DIFFERENT
-- `auth.users` row.
--
-- It is not a cosmetic duplicate:
--
--   * the posting (`geo_lga`, `geo_ward`) is set on one of the two accounts.
--     The officer signs in and lands on the other, where it is blank, so
--     `alert_in_my_area()` matches nothing and their board is empty with the
--     incidents right there. Same symptom as T-95's ward suffix and T-90's role
--     spelling, from a third cause — which is why "nothing was seen on the HQ
--     dashboard" has been three different bugs.
--   * `onesignal_player_id` is on one of them, so `escalation_push_targets()`
--     either misses that officer or, when both carry a posting, tells them
--     twice.
--   * `alerts.assigned_to_uid` points at whichever account was open when the
--     dispatch was made, so an incident can be assigned to the account its
--     owner is not signed into.
--
-- `profiles.badge_number` would have caught it, and does not. 20260903000004
-- gives it a plain index and no uniqueness, so two accounts may hold one badge
-- — and the badge is what officers are called on the radio, what every board
-- labels them with, and what `formatOfficerBadge()` falls back to SCANNING
-- every profile for, taking whichever row comes first.
--
-- ## What a migration can and cannot do here
--
-- It cannot decide which of two accounts is the real one. That is a person's
-- call: one of them has the posting, one has the password the officer actually
-- knows, and only they know which.
--
-- So this adds the three things that let somebody make that call safely — a
-- view that names the duplicates and what each side holds, a function that
-- merges one into another without deleting anything, and the uniqueness
-- constraint, attempted and reported rather than forced.

-- ── Which accounts are the same person ──────────────────────────────────────
--
-- Two keys, because the deployment has both shapes:
--
--   badge   two accounts carrying the same badge_number. The strongest signal:
--           a badge IS the officer.
--   local   the same email local-part on different domains — hq-001@a.ng and
--           hq-001@b.ng — which is precisely what "duplicates across two email
--           domains" means, and what the badge-to-email derivation produces
--           when the domain changes.
--
-- `phone` is not a key here: profiles.phone is already UNIQUE, so it cannot
-- duplicate. Which is also why this was invisible — the one identity column
-- with a constraint on it is the one that was never the problem.

CREATE OR REPLACE VIEW public.staff_account_duplicates AS
WITH staff AS (
  SELECT p.id, p.email, p.badge_number, p.role, p.full_name,
         p.geo_lga, p.geo_ward, p.geo_pu, p.onesignal_player_id,
         p.is_active, p.created_at, p.last_seen,
         nullif(upper(btrim(coalesce(p.badge_number, ''))), '')  AS badge_key,
         nullif(lower(split_part(coalesce(p.email, ''), '@', 1)), '') AS local_key,
         lower(split_part(coalesce(p.email, ''), '@', 2))        AS domain
    FROM public.profiles p
   WHERE upper(coalesce(p.role, '')) NOT IN ('CITIZEN', 'USER')
),
-- Aggregated per key in a CTE rather than with a window function:
-- `count(DISTINCT x) OVER (...)` is not implemented in PostgreSQL, and the
-- first version of this view used it and would not parse.
by_badge AS (
  SELECT badge_key, count(*) AS accounts
    FROM staff WHERE badge_key IS NOT NULL GROUP BY badge_key
),
by_local AS (
  SELECT local_key, count(*) AS accounts, count(DISTINCT domain) AS domains
    FROM staff WHERE local_key IS NOT NULL GROUP BY local_key
)
SELECT
  coalesce(
    CASE WHEN b.accounts > 1 THEN s.badge_key END,
    s.local_key)                                         AS officer_key,
  CASE WHEN b.accounts > 1 THEN 'same badge'
       ELSE 'same name, two domains' END                 AS matched_on,
  s.id, s.email, s.domain, s.badge_number, s.role, s.full_name,
  s.geo_lga, s.geo_ward, s.geo_pu,
  (s.onesignal_player_id IS NOT NULL
     AND length(s.onesignal_player_id) > 5)              AS can_be_pushed,
  s.is_active, s.created_at, s.last_seen,
  -- What this account would lose if it were the one retired. The whole point
  -- of the view: an operator picking which to keep needs to see it.
  (SELECT count(*) FROM public.alerts a
    WHERE a.assigned_to_uid = s.id)                      AS alerts_assigned,
  (SELECT count(*) FROM public.alerts a
    WHERE a.reported_by = s.id)                          AS alerts_reported
  FROM staff s
  LEFT JOIN by_badge b ON b.badge_key = s.badge_key
  LEFT JOIN by_local l ON l.local_key = s.local_key
 WHERE coalesce(b.accounts, 0) > 1
    OR (coalesce(l.accounts, 0) > 1 AND coalesce(l.domains, 0) > 1);

COMMENT ON VIEW public.staff_account_duplicates IS
  'Staff accounts that look like the same officer twice: one badge on two '
  'accounts, or one email local-part on two domains. Shows which side holds '
  'the posting, the push id and the incidents, because that is what decides '
  'which one to keep. Read it before calling merge_staff_account().';

-- A view inherits the RLS of the tables under it, and `profiles` is already
-- scoped. Granted to the roles that can read profiles at all; the citizen app
-- has no reason to select it, so authenticated gets it only because the console
-- runs as a signed-in operator.
REVOKE ALL ON public.staff_account_duplicates FROM PUBLIC, anon;
GRANT SELECT ON public.staff_account_duplicates TO authenticated, service_role;

-- ── Merging one into another, without deleting anything ────────────────────

CREATE OR REPLACE FUNCTION public.merge_staff_account(
  p_keep   UUID,
  p_retire UUID)
RETURNS TABLE (moved TEXT, detail TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  k public.profiles;
  r public.profiles;
  n INTEGER;
BEGIN
  IF NOT public.is_command() THEN
    RAISE EXCEPTION 'only command may merge staff accounts'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_keep IS NULL OR p_retire IS NULL OR p_keep = p_retire THEN
    RAISE EXCEPTION 'merge needs two different accounts';
  END IF;

  SELECT * INTO k FROM public.profiles WHERE id = p_keep;
  SELECT * INTO r FROM public.profiles WHERE id = p_retire;
  IF k.id IS NULL THEN RAISE EXCEPTION 'no profile %', p_keep; END IF;
  IF r.id IS NULL THEN RAISE EXCEPTION 'no profile %', p_retire; END IF;
  IF upper(coalesce(k.role, '')) IN ('CITIZEN', 'USER')
     OR upper(coalesce(r.role, '')) IN ('CITIZEN', 'USER') THEN
    -- A citizen's account is their own and is not a duplicate desk. Merging
    -- one would move another person's reports onto somebody else's id.
    RAISE EXCEPTION
      'merge_staff_account is for STAFF accounts. % / % includes a citizen',
      k.role, r.role;
  END IF;

  -- Incidents first, because they are the thing that must not be orphaned.
  UPDATE public.alerts SET assigned_to_uid = p_keep
   WHERE assigned_to_uid = p_retire;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN QUERY SELECT 'alerts reassigned', format('%s incident(s)', n);

  -- THE RETIRED ACCOUNT IS STOOD DOWN BEFORE THE KEPT ONE IS FILLED IN.
  --
  -- The order is not cosmetic. `profiles_badge_number_unique` covers ACTIVE
  -- rows, so setting WD-900 on the kept account while the retired one still
  -- holds it and is still active raises `23505` and the whole merge rolls back.
  -- The first version of this function did exactly that, and the replay probe
  -- is what found it — the constraint added in this same migration refusing
  -- the function added in this same migration.
  --
  -- Deactivated, never deleted: a delete cascades to `auth.users` and takes
  -- the record of who reported what with it. It also loses the things that
  -- made the row look live — the badge (so it stops matching a radio call),
  -- the posting (so it matches no incident) and the push id (so it is never
  -- told anything).
  UPDATE public.profiles
     SET is_active = false,
         badge_number = NULL,
         geo_lga = NULL, geo_ward = NULL, geo_pu = NULL,
         onesignal_player_id = NULL,
         full_name = coalesce(nullif(btrim(coalesce(r.full_name, '')), ''), '')
                     || ' [MERGED INTO ' || p_keep::text || ']',
         updated_at = NOW()
   WHERE id = p_retire;
  RETURN QUERY SELECT 'retired account stood down',
    format('%s is inactive, unbadged and unreachable; its reports stay on it',
           coalesce(r.email, p_retire::text));

  -- The posting, the badge and the push id move only when the kept account
  -- does NOT already have one. A merge must never overwrite what the surviving
  -- account knows about itself with what the abandoned one guessed: the
  -- survivor is the row somebody actually signs into.
  --
  -- Read from `r`, the snapshot taken before either UPDATE, so clearing the
  -- retired row above does not erase what we are moving across.
  UPDATE public.profiles
     SET geo_lga   = coalesce(nullif(btrim(coalesce(k.geo_lga, '')), ''), r.geo_lga),
         geo_ward  = coalesce(nullif(btrim(coalesce(k.geo_ward, '')), ''), r.geo_ward),
         geo_pu    = coalesce(nullif(btrim(coalesce(k.geo_pu, '')), ''), r.geo_pu),
         badge_number = coalesce(nullif(btrim(coalesce(k.badge_number, '')), ''),
                                 r.badge_number),
         full_name = coalesce(nullif(btrim(coalesce(k.full_name, '')), ''),
                              r.full_name),
         onesignal_player_id = coalesce(
           nullif(k.onesignal_player_id, ''), r.onesignal_player_id),
         updated_at = NOW()
   WHERE id = p_keep;
  RETURN QUERY SELECT 'kept account filled in',
    format('posting %s / %s, badge %s',
           coalesce(nullif(btrim(coalesce(k.geo_lga, '')), ''), r.geo_lga, '—'),
           coalesce(nullif(btrim(coalesce(k.geo_ward, '')), ''), r.geo_ward, '—'),
           coalesce(nullif(btrim(coalesce(k.badge_number, '')), ''),
                    r.badge_number, '—'));
END;
$$;

COMMENT ON FUNCTION public.merge_staff_account(UUID, UUID) IS
  'Moves one duplicate staff account into another: reassigns incidents, fills '
  'any blank on the kept account from the retired one, and stands the retired '
  'one down without deleting it. Command only. Read '
  'staff_account_duplicates first — this cannot decide which account is the '
  'real one.';

REVOKE ALL ON FUNCTION public.merge_staff_account(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.merge_staff_account(UUID, UUID)
  TO authenticated, service_role;

-- ── And a badge becomes an identity, if this database lets it ──────────────
--
-- Attempted, not forced. On a database that already has two accounts per
-- officer the index cannot be built, and failing the migration there would
-- block every later one — on exactly the database that needs them. So it is
-- tried, and when it cannot be had the operator is told what to do about it.

DO $$
BEGIN
  CREATE UNIQUE INDEX profiles_badge_number_unique
    ON public.profiles (upper(btrim(badge_number)))
   WHERE badge_number IS NOT NULL
     AND btrim(badge_number) <> ''
     AND is_active;
  RAISE NOTICE
    'profiles_badge_number_unique created: one active account per badge from now on';
EXCEPTION
  WHEN duplicate_table THEN
    RAISE NOTICE 'profiles_badge_number_unique already exists';
  WHEN unique_violation THEN
    RAISE WARNING
      'Could not make badge_number unique: this database has more than one '
      'ACTIVE account carrying the same badge. That is the duplicate-account '
      'problem itself. Run: select * from public.staff_account_duplicates '
      'order by officer_key; decide which account is the real one, then '
      'select * from public.merge_staff_account(''<keep>'', ''<retire>''); and '
      're-run this migration to take the constraint.';
END $$;

-- Scoped to ACTIVE accounts on purpose: a merged account keeps its history and
-- is_active = false, and the constraint must not be the reason a merge is
-- impossible. It also means re-running this file after the merges succeeds.



-- ============================================================================
-- DID IT WORK?
--
-- One row per thing that had to be true. `result` is PASS or FAIL; nothing here
-- writes. If every row says PASS, the 46 migrations are applied.
--
-- These check BEHAVIOUR-ADJACENT FACTS, not just that statements ran: that anon
-- holds no policy at all, that the escalation columns exist (their absence made
-- every escalation fail in full), that the tier has its own column, and that the
-- realtime publication covers what both apps subscribe to.
-- ============================================================================

WITH checks(ord, name, ok) AS (
  VALUES
    -- Not a check: the stamp that says WHICH version of this script produced
    -- the output below. A pasted result used to carry nothing identifying its
    -- version, so a run from a stale working copy read exactly like a current
    -- one. Compare with: python3 scripts/migration_sets.py --fingerprint
    (0, 'script version: 46 outstanding migrations, '
        'fingerprint b4a1df542198', true),
    (1, 'agency tables exist (4)',
        (SELECT count(*) = 4 FROM information_schema.tables
          WHERE table_schema = 'public'
            AND table_name IN ('agency_personnel','agency_deployments',
                               'agency_action_reports','agency_notifications'))),
    (2, 'no policy grants anon or public anything'
          || coalesce(' — ' || (SELECT string_agg(tablename || '.' || policyname, ', '
                                                  ORDER BY tablename, policyname)
                                  FROM pg_policies
                                 WHERE schemaname = 'public'
                                   AND ('anon' = ANY(roles) OR 'public' = ANY(roles))), ''),
        (SELECT count(*) = 0 FROM pg_policies
          WHERE schemaname = 'public'
            AND ('anon' = ANY(roles) OR 'public' = ANY(roles)))),
    (3, 'role-escalation trigger installed',
        (SELECT count(*) = 1 FROM pg_trigger
          WHERE tgname = 'profiles_no_privilege_escalation')),
    (4, 'emergency PIN functions exist (4)',
        (SELECT count(*) = 4 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public'
            AND p.proname IN ('set_emergency_pins','has_emergency_pins',
                              'verify_emergency_pin','resolve_emergency'))),
    (5, 'PIN hashes unreadable by the API roles',
        (SELECT count(*) = 0 FROM information_schema.role_table_grants
          WHERE table_schema = 'public' AND table_name = 'emergency_pins'
            AND grantee IN ('anon','authenticated'))),
    (6, 'realtime publication covers all 8 subscribed tables',
        (SELECT count(*) = 8 FROM pg_publication_tables
          WHERE pubname = 'supabase_realtime' AND schemaname = 'public'
            AND tablename IN ('alerts','telemetry','chat_messages','system_alerts',
                              'profiles','agency_action_reports',
                              'agency_deployments','uninstall_requests'))),
    (7, 'incident-media bucket configured',
        (SELECT count(*) = 1 FROM storage.buckets
          WHERE id = 'incident-media' AND public
            AND file_size_limit = 52428800)),
    (8, 'incident media is append-only (no UPDATE/DELETE policy)',
        (SELECT count(*) = 0 FROM pg_policies
          WHERE schemaname = 'storage' AND tablename = 'objects'
            AND policyname LIKE 'incident_media%' AND cmd IN ('UPDATE','DELETE'))),
    (9, 'broadcast scoping columns exist (6)',
        (SELECT count(*) = 6 FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'system_alerts'
            AND column_name IN ('target_audience','target_agency','target_lga',
                                'target_ward','target_pu','expires_at'))),
    (10, 'system_alerts.title has a default, so a broadcast cannot fail on it',
        (SELECT column_default IS NOT NULL FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'system_alerts'
            AND column_name = 'title')),
    (11, 'escalation columns exist',
        (SELECT count(*) = 2 FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'alerts'
            AND column_name IN ('escalated_to_agency','escalation_log'))),
    (12, 'profiles.badge_number exists',
        (SELECT count(*) = 1 FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'profiles'
            AND column_name = 'badge_number')),
    (13, 'alerts.assigned_tier exists',
        (SELECT count(*) = 1 FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'alerts'
            AND column_name = 'assigned_tier')),
    (14, 'no tier label left in the agency column',
        (SELECT count(*) = 0 FROM public.alerts
          WHERE escalated_to_agency IN ('POLLING_UNIT','PU','WARD','LGA','HQ'))),
    -- The signup path must not read a role out of client-supplied metadata.
    -- Anyone holding the anon key could otherwise enrol themselves as
    -- HQ_COMMAND, and every policy in the system trusts profiles.role.
    (15, 'a signup cannot choose its own role',
        (SELECT pg_get_functiondef(p.oid) NOT LIKE '%raw_user_meta_data->>''role''%'
           FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'handle_new_user')),
    -- The chain: an alert must land at the PU, and the timeouts that were
    -- configured and dead must now be enforced by something.
    (16, 'new alerts land at the polling unit',
        (SELECT column_default LIKE '%UNIT%' FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'alerts'
            AND column_name = 'assigned_tier')),
    (17, 'the escalation job exists and is service-role only',
        (SELECT NOT has_function_privilege('authenticated',
                  'public.escalate_overdue_alerts()', 'EXECUTE')
           FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'escalate_overdue_alerts')),
    (18, 'the chain terminates at HQ',
        (SELECT public.next_tier('HQ') IS NULL AND public.next_tier('UNIT') = 'WARD')),
    -- Location is borrowed, not kept. A citizen's position must stop being
    -- readable by staff once their emergency closes, nothing may be kept
    -- forever, and a message must not be injectable into somebody else's
    -- channel.
    -- Asserted on the POLICY'S CONDITION, not on its name. This check used to
    -- name `telemetry_select_self_or_responding_staff`, and a later migration
    -- that renamed the policy while keeping the behaviour broke the check and
    -- proved nothing about the database. What has to stay true is that a
    -- position is tied to an OPEN incident — so the clause has to mention the
    -- alerts table and exclude a resolved one.
    (19, 'a citizen''s position is not a standing staff feed',
        (SELECT count(*) = 1 FROM pg_policies
          WHERE schemaname = 'public' AND tablename = 'telemetry'
            AND cmd = 'SELECT'
            AND qual LIKE '%alerts%'
            AND qual LIKE '%RESOLVED%')),
    (20, 'stale positions are purged, and only by the service role',
        (SELECT NOT has_function_privilege('authenticated',
                  'public.purge_stale_telemetry()', 'EXECUTE')
           FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'purge_stale_telemetry')),
    (21, 'chat writes are restricted to a participant of the thread',
        EXISTS (SELECT 1 FROM pg_policies
                 WHERE schemaname = 'public' AND tablename = 'chat_messages'
                   AND policyname = 'chat_insert_participant')),
    -- The SMS fallback's per-device key. It can both decrypt and forge that
    -- citizen's emergency traffic, so nothing but the service role may reach
    -- it, and the table must not be selectable at all.
    (22, 'SMS device keys exist and are unreadable through the API',
        (SELECT relrowsecurity FROM pg_class
          WHERE oid = 'public.sms_device_keys'::regclass)
        AND NOT EXISTS (SELECT 1 FROM pg_policies
                         WHERE schemaname = 'public'
                           AND tablename = 'sms_device_keys')),
    (23, 'only the service role can resolve an SMS key for ingest',
        (SELECT NOT has_function_privilege('authenticated',
                  'public.sms_key_for_ingest(bytea)', 'EXECUTE')
           FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'sms_key_for_ingest')),
    -- Without this, one mesh alert flooded by several relays becomes several
    -- incidents and several units sent to one place.
    (24, 'the mesh can recognise the same envelope arriving twice',
        (SELECT to_regclass('public.mesh_envelopes_seen') IS NOT NULL
            AND EXISTS (SELECT 1 FROM pg_proc p
                          JOIN pg_namespace n ON n.oid = p.pronamespace
                         WHERE n.nspname = 'public'
                           AND p.proname = 'mesh_note_envelope'))),
    -- And it must not become a record of which handset carried whose emergency.
    (25, 'mesh traffic is not readable through the API',
        (SELECT relrowsecurity
            AND NOT EXISTS (SELECT 1 FROM pg_policies
                             WHERE schemaname = 'public'
                               AND tablename = 'mesh_envelopes_seen')
           FROM pg_class
          WHERE oid = 'public.mesh_envelopes_seen'::regclass)),
    -- A handset whose SIM has gone can no longer be reached by SMS, and the
    -- alert queue keeps queueing with nowhere to go. HQ is told.
    (26, 'a handset can report that its SMS channel changed',
        (SELECT to_regclass('public.sim_channel_events') IS NOT NULL)),
    -- And that report must not be readable by every staff account. A
    -- polling-unit officer, and every agency liaison, are staff; neither has a
    -- reason to see which citizens changed SIM. This is the same mistake the
    -- telemetry work was written to undo.
    (27, 'SIM reports are limited to command, not all staff',
        (SELECT relrowsecurity
            AND EXISTS (SELECT 1 FROM pg_policies
                         WHERE schemaname = 'public'
                           AND tablename = 'sim_channel_events'
                           AND policyname = 'sim_events_select_self_or_command')
           FROM pg_class
          WHERE oid = 'public.sim_channel_events'::regclass)),
    -- There is no column for a position on that table, and there must not be:
    -- with one it stops being a channel board and becomes a movement log on
    -- private citizens.
    (28, 'SIM reports carry no position',
        (SELECT count(*) = 0 FROM information_schema.columns
          WHERE table_schema = 'public'
            AND table_name = 'sim_channel_events'
            AND column_name IN ('latitude','longitude','lat','lng','location'))),
    -- An agency liaison is an officer of ANOTHER organisation. is_staff() is
    -- "role is not CITIZEN", so they were staff — and the alerts policies were
    -- "... OR is_staff()". Every liaison could read AND WRITE every incident
    -- in Plateau.
    (29, 'a liaison is recognised as an outside agency',
        (SELECT EXISTS (SELECT 1 FROM pg_proc p
                          JOIN pg_namespace n ON n.oid = p.pronamespace
                         WHERE n.nspname = 'public' AND p.proname = 'is_liaison'))),
    (30, 'the statewide alert policies no longer rest on is_staff alone',
        (SELECT NOT EXISTS (SELECT 1 FROM pg_policies
                             WHERE schemaname = 'public'
                               AND tablename = 'alerts'
                               AND policyname IN ('alerts_select_own_or_staff',
                                                  'alerts_update_own_or_staff'))
            AND EXISTS (SELECT 1 FROM pg_policies
                         WHERE schemaname = 'public'
                           AND tablename = 'alerts'
                           AND policyname = 'alerts_select_own_or_ours'))),
    -- An SOS started a track and the database kept only the latest point, so
    -- the trail lived in one browser tab's memory: a refresh lost it, and
    -- anybody reviewing the incident afterwards saw no movement at all.
    (31, 'the route taken during an incident is kept',
        (SELECT to_regclass('public.incident_tracks') IS NOT NULL)),
    -- And it expires, which is the whole reason keeping it does not undo the
    -- work that made location borrowed rather than kept.
    (32, 'routes expire, and only the service role can expire them',
        (SELECT NOT has_function_privilege('authenticated',
                  'public.purge_stale_incident_tracks()', 'EXECUTE')
           FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'purge_stale_incident_tracks')),
    -- A route is a record. One that can be rewritten is worth less than none,
    -- because it can be made to say something else.
    (33, 'a route cannot be rewritten or deleted through the API',
        (SELECT NOT EXISTS (SELECT 1 FROM pg_policies
                             WHERE schemaname = 'public'
                               AND tablename = 'incident_tracks'
                               AND cmd IN ('UPDATE', 'DELETE'))))
)
SELECT
  CASE WHEN ok THEN 'PASS' ELSE '*** FAIL ***' END AS result,
  name
FROM checks
ORDER BY ok, ord;
