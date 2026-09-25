BEGIN;

-- ============================================================================
-- BOOTSTRAP A STAGING PROJECT — generated file, do not edit by hand.
--   Regenerate with: python3 scripts/build_bootstrap.py
--
-- >>> THIS IS FOR AN EMPTY PROJECT. DO NOT RUN IT ON PRODUCTION. <<<
--
-- It applies all thirteen migrations, starting with the initial schema — whose
-- policies are `USING (true)`, i.e. wide open to the anon role. A later
-- migration removes them, so a fresh project ends up correct; a database that
-- ALREADY has data would be briefly re-opened on the way through, and any
-- hand-made policy would be dropped.
--
-- The guard below refuses to run if it finds existing data, and it refuses
-- STRUCTURALLY: the whole file is one transaction, so the guard's exception
-- rolls back everything after it. An earlier version only RAISEd, which aborts
-- the buffer in the Supabase SQL editor but NOT under plain psql — there the
-- error printed and the migrations applied anyway. A guard that warns while the
-- damage proceeds is worse than none.
--
-- For a database that already has the original schema — production — use
-- scripts/apply_all_migrations.sql instead. That one omits the historical four.
--
-- WHAT YOU GET
--
-- A project whose schema matches what production will look like after the
-- outstanding migrations are applied: the same tables, the same policies, the
-- same functions. That is the point of it. `scripts/verify_rls.js` can then be
-- pointed at this project — and ONLY at a project like this, since it INSERTs
-- probe rows — to confirm anon really is locked out of a live Supabase, which
-- no local replica can prove.
--
-- Expect `NOTICE: skipping ...` lines. They are the guards that let these files
-- run against a database that does not have a given table yet.
-- ============================================================================

-- ── Refuse to run on a database that already holds anything ─────────────────
--
-- A staging bootstrap pasted into the wrong tab is the failure this exists to
-- prevent. `alerts` is the table that would hurt most, so its presence WITH
-- ROWS is the signal that this is not an empty project.
DO $guard$
DECLARE
  n bigint;
BEGIN
  IF to_regclass('public.alerts') IS NOT NULL THEN
    EXECUTE 'SELECT count(*) FROM public.alerts' INTO n;
    IF n > 0 THEN
      RAISE EXCEPTION
        'REFUSING TO RUN: public.alerts already holds % row(s). This script is '
        'for an EMPTY staging project and would re-open the database on its way '
        'through. For an existing database use scripts/apply_all_migrations.sql.', n;
    END IF;
  END IF;
END $guard$;

-- ----------------------------------------------------------------------------
-- 20260720000000_initial_schema.sql  (historical)
-- ----------------------------------------------------------------------------
DO $b$ BEGIN RAISE NOTICE 'applying 20260720000000_initial_schema.sql'; END $b$;

-- ==============================================================================
-- OPERATION RAINBOW — SUPABASE POSTGRESQL SCHEMA MIGRATION
-- Copy and paste this script into your Supabase Dashboard -> SQL Editor -> Run
-- ==============================================================================

-- 1. PROFILES TABLE (Linked 1-to-1 with auth.users)
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT,
  phone TEXT UNIQUE,
  full_name TEXT,
  role TEXT NOT NULL DEFAULT 'CITIZEN', -- CITIZEN, RESPONDER, LGA_COMMAND, WARD_COMMAND, HQ_COMMAND
  tier TEXT DEFAULT 'UNKNOWN',          -- pu, ward, lga, unknown
  geo_lga TEXT,
  geo_ward TEXT,
  geo_pu TEXT,
  profile_complete BOOLEAN DEFAULT false,
  is_active BOOLEAN DEFAULT true,
  last_seen TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Automatic Profile Creation Trigger on Auth Signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $func$
BEGIN
  INSERT INTO public.profiles (id, email, phone, full_name, role)
  VALUES (
    NEW.id,
    NEW.email,
    NEW.phone,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', 'User'),
    COALESCE(NEW.raw_user_meta_data->>'role', 'CITIZEN')
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    phone = EXCLUDED.phone,
    updated_at = NOW();
  RETURN NEW;
END;
$func$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 2. ALERTS TABLE
CREATE TABLE IF NOT EXISTS public.alerts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  local_id TEXT,
  type TEXT NOT NULL,                  -- SOS, INCIDENT, AI_VOICE_REPORT
  sub_type TEXT,
  status TEXT NOT NULL DEFAULT 'PENDING', -- PENDING, DISPATCHED, ON_SITE, RESOLVED, CANCELLED
  severity TEXT DEFAULT 'MEDIUM',      -- LOW, MEDIUM, HIGH, CRITICAL
  description TEXT,
  reported_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  assigned_to UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  geo_lga TEXT,
  geo_ward TEXT,
  geo_pu TEXT,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  ai_summary TEXT,
  citizen_feedback TEXT,
  feedback_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. TELEMETRY TABLE (Live Responder & SOS GPS)
CREATE TABLE IF NOT EXISTS public.telemetry (
  user_id UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  mode TEXT NOT NULL,                   -- sos, responder
  status TEXT DEFAULT 'PATROLLING',
  battery INTEGER,
  network TEXT,
  accuracy DOUBLE PRECISION,
  speed DOUBLE PRECISION,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. CHAT MESSAGES TABLE
CREATE TABLE IF NOT EXISTS public.chat_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  alert_id UUID REFERENCES public.alerts(id) ON DELETE CASCADE,
  sender_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  sender_name TEXT,
  sender_role TEXT,
  message TEXT NOT NULL,
  media_url TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. SYSTEM ALERTS TABLE (Tactical Advisories)
CREATE TABLE IF NOT EXISTS public.system_alerts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  message TEXT NOT NULL,
  severity TEXT DEFAULT 'HIGH',
  target_type TEXT DEFAULT 'ALL',
  target_value TEXT,
  is_active BOOLEAN DEFAULT true,
  created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ==============================================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ==============================================================================
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.telemetry ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.system_alerts ENABLE ROW LEVEL SECURITY;

-- Profiles RLS
CREATE POLICY "Allow public read access to profiles" ON public.profiles FOR SELECT USING (true);
CREATE POLICY "Allow individual insert/update to own profile" ON public.profiles FOR ALL USING (auth.uid() = id);

-- Alerts RLS
CREATE POLICY "Allow authenticated users to read alerts" ON public.alerts FOR SELECT USING (auth.role() = 'authenticated' OR auth.role() = 'service_role');
CREATE POLICY "Allow authenticated users to insert alerts" ON public.alerts FOR INSERT WITH CHECK (true);
CREATE POLICY "Allow authenticated users to update alerts" ON public.alerts FOR UPDATE USING (true);

-- Telemetry RLS
CREATE POLICY "Allow reading telemetry" ON public.telemetry FOR SELECT USING (true);
CREATE POLICY "Allow users to update own telemetry" ON public.telemetry FOR ALL USING (true);

-- Chat Messages RLS
CREATE POLICY "Allow reading chat messages" ON public.chat_messages FOR SELECT USING (true);
CREATE POLICY "Allow inserting chat messages" ON public.chat_messages FOR INSERT WITH CHECK (true);

-- System Alerts RLS
CREATE POLICY "Allow reading system alerts" ON public.system_alerts FOR SELECT USING (true);
CREATE POLICY "Allow service role to manage system alerts" ON public.system_alerts FOR ALL USING (true);

-- Enable Realtime for Alerts, Telemetry & Chat
ALTER PUBLICATION supabase_realtime ADD TABLE public.alerts;
ALTER PUBLICATION supabase_realtime ADD TABLE public.telemetry;
ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_messages;
ALTER PUBLICATION supabase_realtime ADD TABLE public.system_alerts;

-- ----------------------------------------------------------------------------
-- phase1_foundation.sql  (historical)
-- ----------------------------------------------------------------------------
DO $b$ BEGIN RAISE NOTICE 'applying phase1_foundation.sql'; END $b$;

-- ============================================================
-- Operation Rainbow — Phase 1 Database Migrations
-- Run this in Supabase Dashboard → SQL Editor
-- ============================================================

-- ─── 1. Enable Realtime on existing tables ────────────────────
DO $$
BEGIN
  IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'profiles') THEN
    BEGIN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.profiles;
    EXCEPTION WHEN duplicate_object THEN NULL; WHEN OTHERS THEN NULL;
    END;
  END IF;

  IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'alerts') THEN
    BEGIN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.alerts;
    EXCEPTION WHEN duplicate_object THEN NULL; WHEN OTHERS THEN NULL;
    END;
  END IF;

  IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'system_alerts') THEN
    BEGIN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.system_alerts;
    EXCEPTION WHEN duplicate_object THEN NULL; WHEN OTHERS THEN NULL;
    END;
  END IF;
END $$;

-- ─── 2. chat_messages ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.chat_messages (
  id           UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  alert_id     UUID         NOT NULL REFERENCES public.alerts(id) ON DELETE CASCADE,
  sender_id    UUID         NOT NULL,
  sender_name  TEXT         NOT NULL DEFAULT 'Unknown',
  sender_role  TEXT         NOT NULL DEFAULT 'CITIZEN',
  message      TEXT         NOT NULL,
  created_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "chat_read" ON public.chat_messages;
CREATE POLICY "chat_read" ON public.chat_messages
  FOR SELECT USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "chat_insert" ON public.chat_messages;
CREATE POLICY "chat_insert" ON public.chat_messages
  FOR INSERT WITH CHECK (auth.uid() = sender_id);

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_messages;
EXCEPTION WHEN duplicate_object THEN NULL; WHEN OTHERS THEN NULL;
END $$;

-- ─── 3. telemetry ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.telemetry (
  id          UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID           NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  alert_id    UUID           REFERENCES public.alerts(id) ON DELETE SET NULL,
  latitude    DOUBLE PRECISION,
  longitude   DOUBLE PRECISION,
  mode        TEXT           DEFAULT 'responder',
  status      TEXT           DEFAULT 'PATROLLING',
  battery     INTEGER,
  network     TEXT,
  accuracy    DOUBLE PRECISION,
  speed       DOUBLE PRECISION,
  updated_at  TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
  UNIQUE (user_id)
);

ALTER TABLE public.telemetry ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "telemetry_own_upsert" ON public.telemetry;
CREATE POLICY "telemetry_own_upsert" ON public.telemetry
  FOR ALL USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "telemetry_read_all" ON public.telemetry;
CREATE POLICY "telemetry_read_all" ON public.telemetry
  FOR SELECT USING (auth.uid() IS NOT NULL);

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.telemetry;
EXCEPTION WHEN duplicate_object THEN NULL; WHEN OTHERS THEN NULL;
END $$;

-- ─── 4. safe_zones ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.safe_zones (
  id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT         NOT NULL,
  description TEXT,
  latitude    DOUBLE PRECISION NOT NULL,
  longitude   DOUBLE PRECISION NOT NULL,
  type        TEXT         DEFAULT 'COMMAND_HQ',
  geo_lga     TEXT,
  geo_ward    TEXT,
  is_active   BOOLEAN      DEFAULT TRUE,
  created_at  TIMESTAMPTZ  DEFAULT NOW()
);

ALTER TABLE public.safe_zones ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "safe_zones_read" ON public.safe_zones;
CREATE POLICY "safe_zones_read" ON public.safe_zones
  FOR SELECT USING (auth.uid() IS NOT NULL);

INSERT INTO public.safe_zones (name, description, latitude, longitude, type, geo_lga) VALUES
  ('JOS SOUTH COMMAND HQ',      'Primary tactical operations centre',     9.8965,  8.8583, 'COMMAND_HQ', 'JOS SOUTH'),
  ('BUKURU TACTICAL OUTPOST',   'Forward operating base, Bukuru',          9.7952,  8.8521, 'OUTPOST',    'JOS SOUTH'),
  ('JOS NORTH POLICE DIVISION', 'Jos North Police Headquarters',           9.9281,  8.8921, 'POLICE',     'JOS NORTH'),
  ('PLATEAU STATE HQ',          'State Government HQ Command Centre',      9.9167,  8.8917, 'COMMAND_HQ', 'JOS NORTH'),
  ('JOS EAST TACTICAL OUTPOST', 'Jos East forward operating base',         9.9500,  8.9600, 'OUTPOST',    'JOS EAST'),
  ('BARKIN LADI SAFE POINT',    'Barkin Ladi civilian safe assembly',      9.5167,  8.9167, 'SAFE_POINT', 'BARKIN LADI'),
  ('MANGU COMMAND POST',        'Mangu LGA tactical command post',         9.7167,  9.0500, 'COMMAND_HQ', 'MANGU')
ON CONFLICT DO NOTHING;

-- ─── 5. uninstall_requests ────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.uninstall_requests (
  id           UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID         REFERENCES auth.users(id) ON DELETE SET NULL,
  reason       TEXT,
  remarks      TEXT,
  status       TEXT         DEFAULT 'PENDING',
  submitted_at TIMESTAMPTZ  DEFAULT NOW(),
  reviewed_by  UUID         REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_at  TIMESTAMPTZ
);

ALTER TABLE public.uninstall_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "uninstall_insert" ON public.uninstall_requests;
CREATE POLICY "uninstall_insert" ON public.uninstall_requests
  FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "uninstall_read" ON public.uninstall_requests;
CREATE POLICY "uninstall_read" ON public.uninstall_requests
  FOR SELECT USING (auth.uid() IS NOT NULL);

-- ─── 6. app_config ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.app_config (
  id         UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  key        TEXT         UNIQUE NOT NULL,
  value      TEXT         NOT NULL,
  updated_at TIMESTAMPTZ  DEFAULT NOW()
);

ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "app_config_read" ON public.app_config;
CREATE POLICY "app_config_read" ON public.app_config
  FOR SELECT USING (TRUE);

INSERT INTO public.app_config (key, value) VALUES
  ('min_version',      '1.0.0'),
  ('latest_version',   '2.0.0'),
  ('force_update',     'false'),
  ('update_url',       'https://play.google.com/store/apps/details?id=com.rainbow.app')
ON CONFLICT (key) DO NOTHING;

-- ─── 7. alerts — new columns ──────────────────────────────────
ALTER TABLE public.alerts
  ADD COLUMN IF NOT EXISTS media_urls    TEXT[]  DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS geo_siec_ward TEXT;

-- ─── 8. profiles — new columns ────────────────────────────────
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS fcm_token           TEXT,
  ADD COLUMN IF NOT EXISTS onesignal_player_id TEXT,
  ADD COLUMN IF NOT EXISTS emergency_contacts  JSONB DEFAULT '[]'::JSONB;

-- ─── 9. system_alerts — add target_audience + expires_at ──────
DO $$
BEGIN
  IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'system_alerts') THEN
    ALTER TABLE public.system_alerts
      ADD COLUMN IF NOT EXISTS target_audience TEXT        DEFAULT 'ALL',
      ADD COLUMN IF NOT EXISTS expires_at      TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '24 hours');
  END IF;
END $$;

-- ─── Done ─────────────────────────────────────────────────────
SELECT 'Phase 1 migrations complete' AS result;

-- ----------------------------------------------------------------------------
-- phase2_assigned_responders.sql  (historical)
-- ----------------------------------------------------------------------------
DO $b$ BEGIN RAISE NOTICE 'applying phase2_assigned_responders.sql'; END $b$;

-- ─── PHASE 2 MIGRATION: Multi-Unit Responder Array & Audit Trigger ─────────

-- 1. Add assigned_responders array column to alerts table
ALTER TABLE public.alerts 
  ADD COLUMN IF NOT EXISTS assigned_responders TEXT[] DEFAULT '{}';

-- 2. Add AI triage JSONB and resolution columns if missing
ALTER TABLE public.alerts 
  ADD COLUMN IF NOT EXISTS ai_triage JSONB DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS resolved_by TEXT,
  ADD COLUMN IF NOT EXISTS resolved_at TIMESTAMPTZ;

-- 3. Create index for fast array membership queries
CREATE INDEX IF NOT EXISTS idx_alerts_assigned_responders 
  ON public.alerts USING GIN (assigned_responders);

-- 4. Grant API permissions
GRANT ALL ON TABLE public.alerts TO anon, authenticated, service_role;

-- 5. Verification query
SELECT 'Phase 2 assigned_responders & ai_triage migration complete' AS result;

-- ----------------------------------------------------------------------------
-- phase3_profile_columns_and_config.sql  (historical)
-- ----------------------------------------------------------------------------
DO $b$ BEGIN RAISE NOTICE 'applying phase3_profile_columns_and_config.sql'; END $b$;

-- ─── PHASE 3 MIGRATION: Profile columns & app_config table ─────────────────

-- 1. Add missing profile columns (push preferences + device tracking)
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS push_enabled BOOLEAN DEFAULT true,
  ADD COLUMN IF NOT EXISTS last_device_id TEXT,
  ADD COLUMN IF NOT EXISTS last_login_at TIMESTAMPTZ;

-- 2. Add reviewed_at to uninstall_requests for HQ approval tracking
ALTER TABLE public.uninstall_requests
  ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'PENDING',
  ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMPTZ;

-- 3. Create app_config table (or repair it if partially created)
CREATE TABLE IF NOT EXISTS public.app_config (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

-- Add optional columns defensively (safe to run even if table already exists)
ALTER TABLE public.app_config
  ADD COLUMN IF NOT EXISTS description TEXT,
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS updated_by TEXT;

-- 4. Seed default escalation timeouts
INSERT INTO public.app_config (key, value, description)
VALUES
  ('escalation_timeout_pu', '2', 'Polling Unit escalation timeout in minutes'),
  ('escalation_timeout_ward', '5', 'Ward escalation timeout in minutes'),
  ('escalation_timeout_lga', '10', 'LGA escalation timeout in minutes')
ON CONFLICT (key) DO NOTHING;

-- 5. RLS for app_config: readable by authenticated, writable by service_role
ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;

-- DROP first so re-runs are idempotent (CREATE POLICY has no IF NOT EXISTS in PG)
DO $$
BEGIN
  DROP POLICY IF EXISTS "app_config_read_authenticated" ON public.app_config;
  DROP POLICY IF EXISTS "app_config_write_service_role" ON public.app_config;
END $$;

CREATE POLICY "app_config_read_authenticated"
  ON public.app_config FOR SELECT
  TO authenticated USING (true);

CREATE POLICY "app_config_write_service_role"
  ON public.app_config FOR ALL
  TO service_role USING (true);

-- 6. Add status column to uninstall_requests if table exists
DO $$
BEGIN
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'uninstall_requests') THEN
    ALTER TABLE public.uninstall_requests
      ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'PENDING',
      ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMPTZ;
  END IF;
END $$;

-- 7. Grant permissions
GRANT ALL ON TABLE public.app_config TO anon, authenticated, service_role;

-- 8. Verification
SELECT 'Phase 3 profile columns & app_config migration complete' AS result;

-- ----------------------------------------------------------------------------
-- 20260812000000_agency_tables.sql  (outstanding)
-- ----------------------------------------------------------------------------
DO $b$ BEGIN RAISE NOTICE 'applying 20260812000000_agency_tables.sql'; END $b$;

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
  agency        TEXT NOT NULL,                 -- POLICE, ARMY, DSS, NSCDC, FRSC, AMOTEKUN
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
-- 20260813000000_rls_least_privilege.sql  (outstanding)
-- ----------------------------------------------------------------------------
DO $b$ BEGIN RAISE NOTICE 'applying 20260813000000_rls_least_privilege.sql'; END $b$;

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

-- ----------------------------------------------------------------------------
-- 20260902000000_per_user_emergency_pins.sql  (outstanding)
-- ----------------------------------------------------------------------------
DO $b$ BEGIN RAISE NOTICE 'applying 20260902000000_per_user_emergency_pins.sql'; END $b$;

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
-- 20260903000000_realtime_publication.sql  (outstanding)
-- ----------------------------------------------------------------------------
DO $b$ BEGIN RAISE NOTICE 'applying 20260903000000_realtime_publication.sql'; END $b$;

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
-- 20260903000001_incident_media_storage.sql  (outstanding)
-- ----------------------------------------------------------------------------
DO $b$ BEGIN RAISE NOTICE 'applying 20260903000001_incident_media_storage.sql'; END $b$;

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
-- 20260903000002_system_alerts_broadcast.sql  (outstanding)
-- ----------------------------------------------------------------------------
DO $b$ BEGIN RAISE NOTICE 'applying 20260903000002_system_alerts_broadcast.sql'; END $b$;

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
-- 20260903000003_alert_escalation_columns.sql  (outstanding)
-- ----------------------------------------------------------------------------
DO $b$ BEGIN RAISE NOTICE 'applying 20260903000003_alert_escalation_columns.sql'; END $b$;

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
-- The two writers disagree. The console writes an agency ('POLICE', 'ARMY'),
-- which is what AgencyPortal filters on. The mobile agent dashboard writes a
-- TIER ('HQ', 'LGA') — its own comment says "tier label for filtering". A
-- mobile escalation is therefore invisible to every agency portal, though it
-- still shows as ESCALATED on the HQ board. That is a semantic collision in one
-- column, not a schema fault, and it is left alone here: narrowing it belongs
-- with whoever owns the escalation model. Recorded in E2E_AUDIT_REPORT.md.
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
-- 20260903000004_profiles_badge_number.sql  (outstanding)
-- ----------------------------------------------------------------------------
DO $b$ BEGIN RAISE NOTICE 'applying 20260903000004_profiles_badge_number.sql'; END $b$;

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
-- 20260903000005_alerts_assigned_tier.sql  (outstanding)
-- ----------------------------------------------------------------------------
DO $b$ BEGIN RAISE NOTICE 'applying 20260903000005_alerts_assigned_tier.sql'; END $b$;

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
-- 20260925000000_escalation_engine.sql  (outstanding)
-- ----------------------------------------------------------------------------
DO $b$ BEGIN RAISE NOTICE 'applying 20260925000000_escalation_engine.sql'; END $b$;

-- ─── PHASE 6 MIGRATION: SLA ESCALATION ENGINE (ported from Firestore) ────────
--
-- Replaces the Cloud Functions escalation engine in functions/index.js
-- (escalateTask, escalationWatchdog, triggerSLASweep, adminEscalateAlert),
-- which ran against Firestore collections no live client writes to any more.
--
-- DESIGN NOTES — where this differs from the Firestore original, and why:
--
-- 1. Sweep, not a task queue.
--    The original enqueued a Cloud Task per alert with `scheduleDelaySeconds`
--    to defer each tier jump, and needed a 5-minute "watchdog" purely to
--    recover alerts whose tasks had been lost. Here, due-ness is derived from
--    `tier_entered_at` on every cycle, so the sweep is idempotent, survives
--    restarts, cannot lose or duplicate a jump, and needs no recovery pass.
--
-- 2. The tier gets its own column.
--    In Firestore `assigned_to` held a tier string ("WARD"). In Postgres
--    `alerts.assigned_to` is a UUID foreign key to a specific officer, so
--    writing a tier into it raises `invalid input syntax for type uuid`.
--    Tier now lives in `alerts.assigned_tier`; `assigned_to` keeps meaning
--    "the individual responsible".
--
-- 3. Timeline and audit trail become tables.
--    The original appended to an `alerts.timeline` array AND a
--    `alerts/{id}/timeline` subcollection — two copies that could diverge.
--    One `alert_timeline` table now serves both readers.
--
-- 4. Notifications go through an outbox.
--    A database function must not make outbound HTTP calls, so escalations
--    enqueue into `notification_outbox`; the `escalation-worker` edge function
--    drains it. A failed push therefore never rolls back an escalation.
--
-- Idempotent; safe to re-run.

-- ─── 1. Alert columns the engine needs ───────────────────────────────────────
ALTER TABLE public.alerts
  -- Command tier currently responsible. Distinct from assigned_to (a person).
  ADD COLUMN IF NOT EXISTS assigned_tier     TEXT NOT NULL DEFAULT 'POLLING_UNIT',
  -- When the alert entered its current tier. The SLA clock reads from here, so
  -- a manual escalation correctly restarts the timer for the new tier.
  ADD COLUMN IF NOT EXISTS tier_entered_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS escalated_at      TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS dispatched_at     TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS acknowledged_at   TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS sla_breached      BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS sla_breached_at   TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS last_edited_by    TEXT;

-- Partial index: the sweep only ever looks at open work.
CREATE INDEX IF NOT EXISTS idx_alerts_escalation_sweep
  ON public.alerts (assigned_tier, tier_entered_at)
  WHERE status NOT IN ('RESOLVED', 'CANCELLED', 'MERGED', 'CLOSED');

CREATE INDEX IF NOT EXISTS idx_alerts_sla_watch
  ON public.alerts (status, sla_breached)
  WHERE sla_breached = FALSE;

-- ─── 2. Timeline ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.alert_timeline (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  alert_id    UUID        NOT NULL REFERENCES public.alerts(id) ON DELETE CASCADE,
  event_type  TEXT        NOT NULL,
  actor       TEXT        NOT NULL DEFAULT 'SYSTEM',
  actor_role  TEXT        NOT NULL DEFAULT 'SYSTEM',
  reason      TEXT,
  notes       TEXT,
  from_tier   TEXT,
  to_tier     TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_alert_timeline_alert
  ON public.alert_timeline (alert_id, created_at DESC);

-- ─── 3. Audit log ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.audit_logs (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  action      TEXT        NOT NULL,
  alert_id    UUID        REFERENCES public.alerts(id) ON DELETE SET NULL,
  actor       TEXT        NOT NULL DEFAULT 'SYSTEM',
  from_tier   TEXT,
  to_tier     TEXT,
  reason      TEXT,
  detail      JSONB       NOT NULL DEFAULT '{}'::JSONB,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_audit_logs_alert   ON public.audit_logs (alert_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created ON public.audit_logs (created_at DESC);

-- ─── 4. Notification outbox ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.notification_outbox (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  alert_id      UUID        REFERENCES public.alerts(id) ON DELETE CASCADE,
  target_tier   TEXT,
  target_lga    TEXT,
  target_ward   TEXT,
  target_pu     TEXT,
  title         TEXT        NOT NULL,
  body          TEXT        NOT NULL,
  payload       JSONB       NOT NULL DEFAULT '{}'::JSONB,
  status        TEXT        NOT NULL DEFAULT 'PENDING',
  attempts      INTEGER     NOT NULL DEFAULT 0,
  last_error    TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  delivered_at  TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_notification_outbox_pending
  ON public.notification_outbox (created_at)
  WHERE status = 'PENDING';

-- ─── 5. Configuration ────────────────────────────────────────────────────────
-- phase3 already seeds escalation_timeout_pu / _ward / _lga (minutes). Add the
-- response SLA used by the breach detector, plus an engine kill switch.
--
-- The engine ships OFF. This migration installs the schema and (where pg_cron
-- is available) schedules the sweep, but every cycle exits immediately until
-- someone turns it on deliberately:
--
--   UPDATE public.app_config SET value = 'true' WHERE key = 'escalation_enabled';
--
-- ON CONFLICT DO NOTHING means re-applying this migration will not switch it
-- back off once you have enabled it.
INSERT INTO public.app_config (key, value, description) VALUES
  ('escalation_timeout_pu',   '2',  'Minutes an alert may sit at POLLING_UNIT before auto-escalating'),
  ('escalation_timeout_ward', '5',  'Minutes an alert may sit at WARD before auto-escalating'),
  ('escalation_timeout_lga',  '10', 'Minutes an alert may sit at LGA before auto-escalating'),
  ('escalation_response_sla', '15', 'Minutes a dispatched responder has to reach the scene'),
  ('escalation_enabled',      'false', 'Master switch for the automatic escalation engine')
ON CONFLICT (key) DO NOTHING;

-- Reads an integer setting, falling back when absent or non-numeric.
CREATE OR REPLACE FUNCTION public.escalation_config_int(p_key TEXT, p_default INT)
RETURNS INT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_raw TEXT;
BEGIN
  SELECT value INTO v_raw FROM public.app_config WHERE key = p_key;
  IF v_raw IS NULL OR btrim(v_raw) !~ '^[0-9]+$' THEN
    RETURN p_default;
  END IF;
  RETURN v_raw::INT;
END;
$$;

-- ─── 6. Tier ladder ──────────────────────────────────────────────────────────
-- POLLING_UNIT → WARD → LGA → HQ. HQ is terminal: nothing escalates past it.
CREATE OR REPLACE FUNCTION public.next_escalation_tier(p_tier TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE upper(coalesce(p_tier, 'POLLING_UNIT'))
           WHEN 'POLLING_UNIT' THEN 'WARD'
           WHEN 'PU'           THEN 'WARD'
           WHEN 'WARD'         THEN 'LGA'
           WHEN 'LGA'          THEN 'HQ'
           ELSE NULL
         END;
$$;

-- Rank used to reject a "escalation" that would move an alert backwards.
CREATE OR REPLACE FUNCTION public.escalation_tier_rank(p_tier TEXT)
RETURNS INT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE upper(coalesce(p_tier, 'POLLING_UNIT'))
           WHEN 'POLLING_UNIT' THEN 1
           WHEN 'PU'           THEN 1
           WHEN 'WARD'         THEN 2
           WHEN 'LGA'          THEN 3
           WHEN 'HQ'           THEN 4
           ELSE 0
         END;
$$;

-- How long an alert may sit at a tier before it escalates.
CREATE OR REPLACE FUNCTION public.escalation_timeout_minutes(p_tier TEXT)
RETURNS INT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE upper(coalesce(p_tier, 'POLLING_UNIT'))
           WHEN 'POLLING_UNIT' THEN public.escalation_config_int('escalation_timeout_pu', 2)
           WHEN 'PU'           THEN public.escalation_config_int('escalation_timeout_pu', 2)
           WHEN 'WARD'         THEN public.escalation_config_int('escalation_timeout_ward', 5)
           WHEN 'LGA'          THEN public.escalation_config_int('escalation_timeout_lga', 10)
           ELSE NULL
         END;
$$;

-- Statuses that still need someone to act. An alert outside this set is not
-- swept: it is finished, merged away, or already handed to an outside agency.
CREATE OR REPLACE FUNCTION public.escalation_open_statuses()
RETURNS TEXT[]
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT ARRAY[
    'PENDING', 'OPEN', 'ACTIVE', 'DURESS',
    'DISPATCHED', 'ACKNOWLEDGED', 'ON_ROUTE', 'ON_SITE', 'IN_PROGRESS'
  ];
$$;

-- ─── 7. Single write path for a tier change ──────────────────────────────────
-- Both the automatic sweep and a manual escalation funnel through here, so the
-- timeline, audit log, escalation_log and outbox can never disagree about what
-- happened. In the Firestore original these side effects were duplicated across
-- escalateTask, triggerSLASweep and adminEscalateAlert, and had already drifted
-- apart (different actor strings, different audit action names, and only one of
-- the three touched the timeline subcollection).
CREATE OR REPLACE FUNCTION public.apply_escalation(
  p_alert_id   UUID,
  p_to_tier    TEXT,
  p_actor      TEXT,
  p_actor_role TEXT,
  p_reason     TEXT,
  p_notes      TEXT,
  p_event_type TEXT,
  p_action     TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_alert   public.alerts%ROWTYPE;
  v_from    TEXT;
  v_entry   JSONB;
BEGIN
  -- Lock the row so two cycles cannot escalate the same alert twice.
  SELECT * INTO v_alert FROM public.alerts WHERE id = p_alert_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN FALSE;
  END IF;

  v_from := coalesce(v_alert.assigned_tier, 'POLLING_UNIT');

  -- Never move an alert backwards or sideways.
  IF public.escalation_tier_rank(p_to_tier) <= public.escalation_tier_rank(v_from) THEN
    RETURN FALSE;
  END IF;

  -- Never escalate finished work.
  IF NOT (v_alert.status = ANY (public.escalation_open_statuses())) THEN
    RETURN FALSE;
  END IF;

  v_entry := jsonb_build_object(
    'from_tier', v_from,
    'to_tier',   p_to_tier,
    'reason',    coalesce(p_reason, 'SLA threshold exceeded'),
    'notes',     coalesce(p_notes, ''),
    'by_email',  p_actor,
    'at',        to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
  );

  UPDATE public.alerts
     SET assigned_tier   = p_to_tier,
         tier_entered_at = now(),
         escalated_at    = now(),
         last_edited_by  = p_actor,
         -- HQ involvement means the incident is critical by definition.
         severity        = CASE WHEN p_to_tier = 'HQ' THEN 'CRITICAL'
                                ELSE coalesce(severity, 'HIGH') END,
         escalation_log  = coalesce(escalation_log, '[]'::JSONB) || v_entry,
         updated_at      = now()
   WHERE id = p_alert_id;

  INSERT INTO public.alert_timeline
    (alert_id, event_type, actor, actor_role, reason, notes, from_tier, to_tier)
  VALUES
    (p_alert_id, p_event_type, p_actor, p_actor_role,
     coalesce(p_reason, 'SLA threshold exceeded'),
     coalesce(p_notes, format('Escalated from %s to %s.', v_from, p_to_tier)),
     v_from, p_to_tier);

  INSERT INTO public.audit_logs
    (action, alert_id, actor, from_tier, to_tier, reason, detail)
  VALUES
    (p_action, p_alert_id, p_actor, v_from, p_to_tier, p_reason,
     jsonb_build_object('status', v_alert.status, 'severity', v_alert.severity));

  -- Queued, not sent: a database function must not make outbound HTTP calls,
  -- and a failed push must never roll back the escalation itself.
  INSERT INTO public.notification_outbox
    (alert_id, target_tier, target_lga, target_ward, target_pu, title, body, payload)
  VALUES
    (p_alert_id, p_to_tier, v_alert.geo_lga, v_alert.geo_ward, v_alert.geo_pu,
     format('⚠️ ESCALATED TO %s', p_to_tier),
     format('Incident %s is unresolved and now requires %s attention.',
            upper(substring(p_alert_id::TEXT, 1, 8)), p_to_tier),
     jsonb_build_object(
       'alertId',   p_alert_id,
       'type',      'ESCALATION',
       'tier',      p_to_tier,
       'fromTier',  v_from,
       'severity',  CASE WHEN p_to_tier = 'HQ' THEN 'CRITICAL' ELSE coalesce(v_alert.severity, 'HIGH') END
     ));

  RETURN TRUE;
END;
$$;

-- ─── 8. The sweep ────────────────────────────────────────────────────────────
-- Replaces escalateTask + triggerSLASweep. Escalates every alert whose time at
-- its current tier has exceeded that tier's configured timeout.
--
-- One tier per alert per cycle, deliberately: an alert that has been ignored
-- for an hour walks POLLING_UNIT → WARD → LGA → HQ over successive cycles, so
-- each tier is given a real chance to respond and each jump is separately
-- recorded, rather than teleporting straight to HQ with no audit trail.
CREATE OR REPLACE FUNCTION public.escalate_due_alerts()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row     RECORD;
  v_next    TEXT;
  v_count   INTEGER := 0;
BEGIN
  -- The seed above ships this 'false'; flip it to 'true' to start the engine.
  -- Note the fallback is 'true': if the row is missing entirely the engine
  -- runs, because an alert that silently stops escalating is the worse
  -- failure. Disable it by setting the value to 'false', not by deleting it.
  IF lower(coalesce((SELECT value FROM public.app_config WHERE key = 'escalation_enabled'), 'true')) <> 'true' THEN
    RAISE NOTICE '[ESCALATION] Engine disabled via app_config.escalation_enabled.';
    RETURN 0;
  END IF;

  FOR v_row IN
    SELECT a.id, a.assigned_tier
      FROM public.alerts a
     WHERE a.status = ANY (public.escalation_open_statuses())
       AND public.next_escalation_tier(a.assigned_tier) IS NOT NULL
       AND a.tier_entered_at <= now() - make_interval(
             mins => public.escalation_timeout_minutes(a.assigned_tier))
     ORDER BY a.tier_entered_at
     FOR UPDATE SKIP LOCKED
  LOOP
    v_next := public.next_escalation_tier(v_row.assigned_tier);
    IF v_next IS NULL THEN
      CONTINUE;
    END IF;

    IF public.apply_escalation(
         v_row.id, v_next,
         'SYSTEM_SLA_ENGINE', 'SYSTEM',
         'SLA threshold exceeded',
         format('No response at %s within %s minutes.',
                v_row.assigned_tier,
                public.escalation_timeout_minutes(v_row.assigned_tier)),
         'SLA_AUTO_ESCALATION', 'AUTO_ESCALATION')
    THEN
      v_count := v_count + 1;
    END IF;
  END LOOP;

  RETURN v_count;
END;
$$;

-- ─── 9. Response-SLA breach detection ────────────────────────────────────────
-- The surviving half of escalationWatchdog. A responder who has accepted an
-- incident but not reached the scene within the response SLA is flagged once,
-- and command is notified. This is separate from tier escalation: the incident
-- is being worked, it is just running late.
CREATE OR REPLACE FUNCTION public.detect_sla_breaches()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row   RECORD;
  v_sla   INT := public.escalation_config_int('escalation_response_sla', 15);
  v_count INTEGER := 0;
  v_since TIMESTAMPTZ;
BEGIN
  FOR v_row IN
    SELECT a.id, a.status, a.assigned_tier, a.geo_lga, a.geo_ward, a.geo_pu,
           coalesce(a.dispatched_at, a.acknowledged_at, a.created_at) AS started_at
      FROM public.alerts a
     WHERE a.sla_breached = FALSE
       AND a.status IN ('DISPATCHED', 'ACKNOWLEDGED', 'ON_ROUTE')
       AND coalesce(a.dispatched_at, a.acknowledged_at, a.created_at)
             <= now() - make_interval(mins => v_sla)
     FOR UPDATE SKIP LOCKED
  LOOP
    v_since := v_row.started_at;

    UPDATE public.alerts
       SET sla_breached    = TRUE,
           sla_breached_at = now(),
           updated_at      = now()
     WHERE id = v_row.id;

    INSERT INTO public.alert_timeline
      (alert_id, event_type, actor, actor_role, reason, notes, from_tier, to_tier)
    VALUES
      (v_row.id, 'SLA_BREACH_ALERT', 'SYSTEM_SLA_ENGINE', 'SYSTEM',
       'Responder did not reach the scene within the response threshold.',
       format('Incident has been %s since %s (%s minute SLA).',
              v_row.status, v_since, v_sla),
       v_row.assigned_tier, v_row.assigned_tier);

    INSERT INTO public.audit_logs
      (action, alert_id, actor, from_tier, to_tier, reason, detail)
    VALUES
      ('SLA_BREACH', v_row.id, 'SYSTEM_SLA_ENGINE',
       v_row.assigned_tier, v_row.assigned_tier,
       'Response SLA exceeded',
       jsonb_build_object('status', v_row.status, 'sla_minutes', v_sla, 'since', v_since));

    INSERT INTO public.notification_outbox
      (alert_id, target_tier, target_lga, target_ward, target_pu, title, body, payload)
    VALUES
      (v_row.id, v_row.assigned_tier, v_row.geo_lga, v_row.geo_ward, v_row.geo_pu,
       '⏱️ SLA RESPONSE BREACH',
       format('Incident %s has exceeded the %s-minute response SLA. Immediate review required.',
              upper(substring(v_row.id::TEXT, 1, 8)), v_sla),
       jsonb_build_object('alertId', v_row.id, 'type', 'SLA_BREACH', 'tier', v_row.assigned_tier));

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

-- ─── 10. One cycle ───────────────────────────────────────────────────────────
-- A session-level advisory lock keeps overlapping ticks (cron plus a manual
-- run, or a slow cycle still finishing) from processing the same alerts twice.
-- If the lock is held the cycle returns immediately rather than queueing.
CREATE OR REPLACE FUNCTION public.run_escalation_cycle()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_escalated INTEGER := 0;
  v_breached  INTEGER := 0;
BEGIN
  IF NOT pg_try_advisory_xact_lock(hashtext('rainbow.escalation_cycle')) THEN
    RETURN jsonb_build_object('skipped', TRUE, 'reason', 'cycle already running');
  END IF;

  v_escalated := public.escalate_due_alerts();
  v_breached  := public.detect_sla_breaches();

  -- Report the kill switch too: without it a disabled engine and a quiet
  -- minute both come back as escalated:0, which is the one thing an operator
  -- checking on a freshly applied migration needs to tell apart.
  RETURN jsonb_build_object(
    'skipped',   FALSE,
    'enabled',   lower(coalesce(
                   (SELECT value FROM public.app_config WHERE key = 'escalation_enabled'),
                   'true')) = 'true',
    'escalated', v_escalated,
    'breached',  v_breached,
    'ran_at',    now()
  );
END;
$$;

-- ─── 11. Manual escalation (replaces adminEscalateAlert) ─────────────────────
-- Callable over PostgREST as rpc/request_escalation. Authorisation is checked
-- here rather than in the client, so the rule holds for the mobile app, the HQ
-- dashboard and anything else that reaches the API.
CREATE OR REPLACE FUNCTION public.request_escalation(
  p_alert_id UUID,
  p_to_tier  TEXT,
  p_reason   TEXT DEFAULT NULL,
  p_notes    TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid    UUID := auth.uid();
  v_role   TEXT;
  v_email  TEXT;
  v_ok     BOOLEAN;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '28000';
  END IF;

  SELECT role, coalesce(email, id::TEXT) INTO v_role, v_email
    FROM public.profiles WHERE id = v_uid;

  IF NOT public.is_command() THEN
    RAISE EXCEPTION 'Only command staff may escalate an incident (role: %)',
      coalesce(v_role, 'unknown') USING ERRCODE = '42501';
  END IF;

  IF public.escalation_tier_rank(p_to_tier) = 0 THEN
    RAISE EXCEPTION 'Unknown tier: %', p_to_tier USING ERRCODE = '22023';
  END IF;

  v_ok := public.apply_escalation(
    p_alert_id, upper(p_to_tier),
    v_email, coalesce(v_role, 'RESPONDER'),
    coalesce(p_reason, 'Tactical escalation'),
    p_notes,
    'MANUAL_ESCALATION', 'MANUAL_ESCALATION');

  IF NOT v_ok THEN
    RETURN jsonb_build_object(
      'success', FALSE,
      'reason',  'Alert is closed, missing, or already at or above that tier.');
  END IF;

  RETURN jsonb_build_object('success', TRUE, 'alert_id', p_alert_id, 'tier', upper(p_to_tier));
END;
$$;

-- ─── 12. Status timestamps ───────────────────────────────────────────────────
-- detect_sla_breaches measures from dispatched_at / acknowledged_at, but no
-- client sets them. Stamping them here means the response SLA works without
-- every caller having to remember, and keeps the value honest.
CREATE OR REPLACE FUNCTION public.stamp_alert_status_times()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF NEW.status = 'DISPATCHED' AND NEW.dispatched_at IS NULL THEN
      NEW.dispatched_at := now();
    END IF;
    IF NEW.status IN ('ACKNOWLEDGED', 'ON_ROUTE') AND NEW.acknowledged_at IS NULL THEN
      NEW.acknowledged_at := now();
    END IF;
    IF NEW.status = 'RESOLVED' AND NEW.resolved_at IS NULL THEN
      NEW.resolved_at := now();
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_stamp_alert_status_times ON public.alerts;
CREATE TRIGGER trg_stamp_alert_status_times
  BEFORE UPDATE ON public.alerts
  FOR EACH ROW EXECUTE FUNCTION public.stamp_alert_status_times();

-- ─── 13. RLS ─────────────────────────────────────────────────────────────────
-- Writes happen only through the SECURITY DEFINER functions above or the
-- service role, which bypasses RLS — so, as everywhere else in this schema,
-- there are no service_role policies. Adding them would be redundant and would
-- put `USING (true)` rows in pg_policies, which the bootstrap check treats as a
-- regression on purpose.
ALTER TABLE public.alert_timeline      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_outbox ENABLE ROW LEVEL SECURITY;

-- A timeline is readable exactly when its incident is. The subquery runs as the
-- calling user, so the policies on `alerts` apply inside it — including the
-- oversight carve-out — and this policy never has to restate them.
DROP POLICY IF EXISTS "alert_timeline_read" ON public.alert_timeline;
CREATE POLICY "alert_timeline_read" ON public.alert_timeline
  FOR SELECT TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.alerts a WHERE a.id = alert_timeline.alert_id)
  );

-- The audit trail is command-only: it records who escalated what and when.
DROP POLICY IF EXISTS "audit_logs_read_command" ON public.audit_logs;
CREATE POLICY "audit_logs_read_command" ON public.audit_logs
  FOR SELECT TO authenticated USING (public.is_command());

-- The outbox is an internal work queue. No policy at all: only the worker, on
-- the service role, ever touches it.

GRANT SELECT ON public.alert_timeline TO authenticated;
GRANT SELECT ON public.audit_logs     TO authenticated;
GRANT ALL    ON public.alert_timeline, public.audit_logs, public.notification_outbox
  TO service_role;

-- Only request_escalation is client-callable. The sweep functions are operator
-- surface and stay off the anon/authenticated API.
REVOKE ALL ON FUNCTION public.apply_escalation(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.escalate_due_alerts()  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.detect_sla_breaches()  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.run_escalation_cycle() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.run_escalation_cycle() TO service_role;
GRANT EXECUTE ON FUNCTION public.escalate_due_alerts()  TO service_role;
GRANT EXECUTE ON FUNCTION public.detect_sla_breaches()  TO service_role;
GRANT EXECUTE ON FUNCTION public.request_escalation(UUID, TEXT, TEXT, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.next_escalation_tier(TEXT),
                          public.escalation_tier_rank(TEXT),
                          public.escalation_timeout_minutes(TEXT),
                          public.escalation_open_statuses()
  TO authenticated, service_role;

-- ─── 14. Backfill ────────────────────────────────────────────────────────────
-- Existing rows default to POLLING_UNIT with tier_entered_at = NOW(), which
-- would hand every historical alert a fresh SLA clock. Seed open alerts from
-- their creation time instead, and park closed ones so the sweep skips them.
UPDATE public.alerts
   SET tier_entered_at = coalesce(created_at, now())
 WHERE tier_entered_at > coalesce(created_at, now())
   AND status = ANY (public.escalation_open_statuses());

-- ─── 15. Scheduling ──────────────────────────────────────────────────────────
-- pg_cron is available on Supabase but is not enabled by default and cannot be
-- created from a plain migration on every plan, so this is best-effort: if the
-- extension is present the job is (re)scheduled, otherwise the migration still
-- succeeds and the escalation-worker edge function can be driven by any
-- external scheduler instead.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'pg_cron') THEN
    BEGIN
      CREATE EXTENSION IF NOT EXISTS pg_cron;
      PERFORM cron.unschedule('rainbow-escalation-cycle')
        WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'rainbow-escalation-cycle');
      PERFORM cron.schedule(
        'rainbow-escalation-cycle',
        '* * * * *',
        $cron$SELECT public.run_escalation_cycle();$cron$
      );
      RAISE NOTICE '[ESCALATION] pg_cron job scheduled every minute.';
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE '[ESCALATION] Could not schedule pg_cron (%). Drive the escalation-worker edge function externally instead.', SQLERRM;
    END;
  ELSE
    RAISE NOTICE '[ESCALATION] pg_cron unavailable. Drive the escalation-worker edge function externally.';
  END IF;
END $$;

SELECT 'Phase 6 escalation engine migration complete' AS result;

-- ----------------------------------------------------------------------------
-- 20260925000001_escalation_followups.sql  (outstanding)
-- ----------------------------------------------------------------------------
DO $b$ BEGIN RAISE NOTICE 'applying 20260925000001_escalation_followups.sql'; END $b$;

-- ─── Oversight routing, evidential retention, schema follow-ups ──────────────
--
-- Four things, all follow-ups to gaps found after the escalation engine landed:
--
--   1. Reports accusing security personnel no longer route to the tier that
--      contains the accused. They enter at HQ and are readable only by
--      oversight roles.
--   2. Responder position is retained as a track, so a closed incident can be
--      reconstructed geographically. Previously telemetry held one current row
--      per user and the history was thrown away on every update.
--   3. A mission debrief gets its own column instead of being appended into
--      `ai_summary`, which mixed officer testimony with machine output.
--   4. `telemetry.user_id` is guaranteed unique, because two earlier migrations
--      define the table differently and the client upserts on that column.
--
-- Apply after 20260925000000_escalation_engine.sql. Idempotent; safe to re-run.

-- ─── 0. Oversight role helper ────────────────────────────────────────────────
-- Deliberately narrow: state-level command and a dedicated oversight role only.
-- An LGA, ward or unit commander is NOT oversight — the whole point is that a
-- complaint about local officers does not land with their own chain.
CREATE OR REPLACE FUNCTION public.is_oversight() RETURNS BOOLEAN
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT COALESCE(
    public.auth_role() IN ('HQ_COMMAND', 'HQ_OFFICER', 'ADMIN', 'OVERSIGHT'),
    false
  );
$$;

REVOKE EXECUTE ON FUNCTION public.is_oversight() FROM anon;

-- ─── 1. Oversight routing ────────────────────────────────────────────────────
ALTER TABLE public.alerts
  ADD COLUMN IF NOT EXISTS oversight_only BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN public.alerts.oversight_only IS
  'Report accusing security personnel. Enters at HQ tier; readable and '
  'actionable only by oversight roles and the reporter.';

-- Which report categories count. Matched case-insensitively against the start
-- of alerts.type, which the client composes as "<category> - <sub-type>".
-- Config-driven so HQ can extend the list without a migration.
INSERT INTO public.app_config (key, value, description) VALUES
  ('oversight_categories', 'police brutality',
   'Comma-separated report categories routed to oversight instead of the local command tier')
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.is_oversight_category(p_type TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_raw TEXT;
  v_cat TEXT;
BEGIN
  IF p_type IS NULL THEN
    RETURN FALSE;
  END IF;

  SELECT value INTO v_raw FROM public.app_config
   WHERE key = 'oversight_categories';

  IF v_raw IS NULL OR btrim(v_raw) = '' THEN
    RETURN FALSE;
  END IF;

  FOREACH v_cat IN ARRAY string_to_array(lower(v_raw), ',') LOOP
    IF btrim(v_cat) <> '' AND lower(p_type) LIKE btrim(v_cat) || '%' THEN
      RETURN TRUE;
    END IF;
  END LOOP;

  RETURN FALSE;
END;
$$;

-- Stamped on insert, before the escalation engine ever looks at the row, so an
-- oversight report is never briefly visible to the local tier.
CREATE OR REPLACE FUNCTION public.route_oversight_alert()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF public.is_oversight_category(NEW.type) THEN
    NEW.oversight_only  := TRUE;
    NEW.assigned_tier   := 'HQ';
    NEW.tier_entered_at := COALESCE(NEW.tier_entered_at, now());
    -- No local officer owns it, whatever the client sent.
    NEW.assigned_to     := NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_route_oversight_alert ON public.alerts;
CREATE TRIGGER trg_route_oversight_alert
  BEFORE INSERT ON public.alerts
  FOR EACH ROW EXECUTE FUNCTION public.route_oversight_alert();

-- Read: ordinary alerts stay visible to every signed-in user exactly as before;
-- an oversight report is visible only to oversight roles and its reporter.
-- These replace the two policies 20260813000000_rls_least_privilege.sql created,
-- keeping its scoping exactly (a citizen sees their own reports and the ones
-- assigned to them; staff see the rest) and adding one carve-out: an oversight
-- report is invisible to staff who are not oversight.
DROP POLICY IF EXISTS "alerts_select_own_or_staff" ON public.alerts;
CREATE POLICY "alerts_select_own_or_staff" ON public.alerts
  FOR SELECT TO authenticated
  USING (
    reported_by = auth.uid()
    OR public.is_oversight()
    OR (NOT oversight_only AND (assigned_to = auth.uid() OR public.is_staff()))
  );

-- Update: an accused officer must not be able to resolve the complaint about
-- himself. Everyone keeps their existing rights on every other incident.
DROP POLICY IF EXISTS "alerts_update_own_or_staff" ON public.alerts;
CREATE POLICY "alerts_update_own_or_staff" ON public.alerts
  FOR UPDATE TO authenticated
  USING (
    reported_by = auth.uid()
    OR public.is_oversight()
    OR (NOT oversight_only AND (assigned_to = auth.uid() OR public.is_staff()))
  );

-- ─── 2. Position history ─────────────────────────────────────────────────────
-- A track is only useful if it can be tied to the incident it was recorded for.
-- `telemetry` has carried no alert_id, so a position could be attributed to a
-- responder but not to the emergency they were attending.
ALTER TABLE public.telemetry
  ADD COLUMN IF NOT EXISTS alert_id UUID
    REFERENCES public.alerts(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_telemetry_alert
  ON public.telemetry (alert_id) WHERE alert_id IS NOT NULL;

-- telemetry holds the CURRENT position per user (the map reads it). Every write
-- also appends here, so the track survives. Written by trigger, so no client
-- change is needed and an older app build still produces history.
CREATE TABLE IF NOT EXISTS public.telemetry_history (
  id         BIGSERIAL       PRIMARY KEY,
  user_id    UUID             NOT NULL,
  alert_id   UUID,
  latitude   DOUBLE PRECISION,
  longitude  DOUBLE PRECISION,
  mode       TEXT,
  status     TEXT,
  battery    INTEGER,
  accuracy   DOUBLE PRECISION,
  speed      DOUBLE PRECISION,
  recorded_at TIMESTAMPTZ     NOT NULL DEFAULT now()
);

-- The two queries that matter: one responder's track over a window, and one
-- incident's track.
CREATE INDEX IF NOT EXISTS idx_telemetry_history_user_time
  ON public.telemetry_history (user_id, recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_telemetry_history_alert_time
  ON public.telemetry_history (alert_id, recorded_at)
  WHERE alert_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.append_telemetry_history()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  -- A repeated write with no movement is not a new track point.
  IF TG_OP = 'UPDATE'
     AND NEW.latitude  IS NOT DISTINCT FROM OLD.latitude
     AND NEW.longitude IS NOT DISTINCT FROM OLD.longitude
     AND NEW.status    IS NOT DISTINCT FROM OLD.status THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.telemetry_history
    (user_id, alert_id, latitude, longitude, mode, status, battery, accuracy, speed)
  VALUES
    (NEW.user_id, NEW.alert_id, NEW.latitude, NEW.longitude, NEW.mode,
     NEW.status, NEW.battery, NEW.accuracy, NEW.speed);

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_append_telemetry_history ON public.telemetry;
CREATE TRIGGER trg_append_telemetry_history
  AFTER INSERT OR UPDATE ON public.telemetry
  FOR EACH ROW EXECUTE FUNCTION public.append_telemetry_history();

ALTER TABLE public.telemetry_history ENABLE ROW LEVEL SECURITY;

-- A track is location data about a named person. Responders and the subject,
-- nobody else; the public role gets nothing.
DROP POLICY IF EXISTS "telemetry_history_read" ON public.telemetry_history;
CREATE POLICY "telemetry_history_read" ON public.telemetry_history
  FOR SELECT TO authenticated
  USING (public.is_staff() OR user_id = auth.uid());


-- Retention. The Firestore build pruned tracks nightly; keep that, driven by
-- config so the retention schedule is a policy decision, not a code change.
INSERT INTO public.app_config (key, value, description) VALUES
  ('telemetry_history_retention_days', '90',
   'Days of responder position history to retain before pruning')
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.prune_telemetry_history()
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_days    INT;
  v_deleted INT;
BEGIN
  v_days := public.escalation_config_int('telemetry_history_retention_days', 90);

  DELETE FROM public.telemetry_history
   WHERE recorded_at < now() - make_interval(days => v_days);

  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;

-- ─── 3. Mission debrief gets its own column ──────────────────────────────────
ALTER TABLE public.alerts
  ADD COLUMN IF NOT EXISTS debrief     TEXT,
  ADD COLUMN IF NOT EXISTS debrief_by  TEXT,
  ADD COLUMN IF NOT EXISTS debrief_at  TIMESTAMPTZ;

COMMENT ON COLUMN public.alerts.debrief IS
  'The responding officer''s closing report. Kept separate from ai_summary so '
  'officer testimony is never mixed with machine-generated text.';

-- ─── 4. telemetry.user_id uniqueness ─────────────────────────────────────────
-- The initial schema makes user_id the primary key; phase1 defines the table
-- with its own id and no uniqueness on user_id. Whichever created it, the
-- client upserts ON CONFLICT (user_id), which needs a unique index to exist.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
      FROM pg_index i
      JOIN pg_class c   ON c.oid = i.indrelid
      JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = ANY (i.indkey)
     WHERE c.relname = 'telemetry'
       AND c.relnamespace = 'public'::regnamespace
       AND i.indisunique
       AND i.indnatts = 1
       AND a.attname = 'user_id'
  ) THEN
    -- Collapse any duplicates first, newest kept, or the index cannot be built.
    DELETE FROM public.telemetry t
     WHERE EXISTS (
       SELECT 1 FROM public.telemetry n
        WHERE n.user_id = t.user_id
          AND (n.updated_at, n.ctid) > (t.updated_at, t.ctid)
     );

    CREATE UNIQUE INDEX telemetry_user_id_key
      ON public.telemetry (user_id);
    RAISE NOTICE '[MIGRATION] Added unique index on telemetry.user_id.';
  END IF;
END $$;

-- ─── 5. Jurisdiction name normalisation ──────────────────────────────────────
-- The app's tactical map spelled one LGA 'BARIKIN LADI'; the statutory name is
-- 'BARKIN LADI', which is what the dashboard offered in its filter. Any alert
-- filed from that LGA therefore could not be found by filtering for it. The map
-- is corrected in code; these rows were written before that.
UPDATE public.alerts
   SET geo_lga = 'BARKIN LADI'
 WHERE upper(btrim(geo_lga)) = 'BARIKIN LADI';

UPDATE public.profiles
   SET geo_lga = 'BARKIN LADI'
 WHERE upper(btrim(geo_lga)) = 'BARIKIN LADI';

-- ─── 6. Verification ─────────────────────────────────────────────────────────
SELECT 'Escalation follow-ups complete' AS result;


COMMIT;

-- ============================================================================
-- DID IT WORK?
--
-- Same verdict table as apply_all_migrations.sql, plus the checks that only
-- mean something on a project built from zero.
-- ============================================================================

WITH checks(ord, name, ok) AS (
  VALUES
    (1, 'core tables exist (9)',
        (SELECT count(*) = 9 FROM information_schema.tables
          WHERE table_schema = 'public'
            AND table_name IN ('profiles','alerts','telemetry','chat_messages',
                               'system_alerts','safe_zones','uninstall_requests',
                               'app_config','emergency_pins'))),
    (2, 'agency tables exist (4)',
        (SELECT count(*) = 4 FROM information_schema.tables
          WHERE table_schema = 'public'
            AND table_name IN ('agency_personnel','agency_deployments',
                               'agency_action_reports','agency_notifications'))),
    (3, 'no policy grants anon or public anything',
        (SELECT count(*) = 0 FROM pg_policies
          WHERE schemaname = 'public'
            AND ('anon' = ANY(roles) OR 'public' = ANY(roles)))),
    -- NOT "no USING(true) policy survives". Three do, deliberately, and all
    -- three are reads granted to `authenticated` only: system advisories, safe
    -- zones and app config are meant to reach every signed-in user. The risk
    -- was never the shape of the qualifier, it is who can reach it — which is
    -- check 3, and which is the distinction scripts/rls_inventory.sql already
    -- draws in its `reach` column. The first version of this check asserted
    -- zero and failed on correct policies.
    --
    -- Pinning the exact set is stricter than dropping the check: a NEW
    -- permissive policy still fails here, even one granted only to
    -- authenticated, which check 3 would let through.
    (4, 'the only permissive USING(true) policies are the three intended reads',
        (SELECT coalesce(array_agg(policyname::text ORDER BY policyname), ARRAY[]::text[])
                  = ARRAY['app_config_read_authenticated','safe_zones_read',
                          'system_alerts_read']::text[]
           FROM pg_policies
          WHERE schemaname = 'public' AND (qual = 'true' OR with_check = 'true'))),
    (5, 'role-escalation trigger installed',
        (SELECT count(*) = 1 FROM pg_trigger
          WHERE tgname = 'profiles_no_privilege_escalation')),
    (6, 'emergency PIN functions exist (4)',
        (SELECT count(*) = 4 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public'
            AND p.proname IN ('set_emergency_pins','has_emergency_pins',
                              'verify_emergency_pin','resolve_emergency'))),
    (7, 'PIN hashes unreadable by the API roles',
        (SELECT count(*) = 0 FROM information_schema.role_table_grants
          WHERE table_schema = 'public' AND table_name = 'emergency_pins'
            AND grantee IN ('anon','authenticated'))),
    (8, 'realtime publication covers all 8 subscribed tables',
        (SELECT count(*) = 8 FROM pg_publication_tables
          WHERE pubname = 'supabase_realtime' AND schemaname = 'public'
            AND tablename IN ('alerts','telemetry','chat_messages','system_alerts',
                              'profiles','agency_action_reports',
                              'agency_deployments','uninstall_requests'))),
    (9, 'incident-media bucket configured',
        (SELECT count(*) = 1 FROM storage.buckets
          WHERE id = 'incident-media' AND public AND file_size_limit = 52428800)),
    (10, 'incident media is append-only (no UPDATE/DELETE policy)',
        (SELECT count(*) = 0 FROM pg_policies
          WHERE schemaname = 'storage' AND tablename = 'objects'
            AND policyname LIKE 'incident_media%' AND cmd IN ('UPDATE','DELETE'))),
    (11, 'broadcast scoping columns exist (6)',
        (SELECT count(*) = 6 FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'system_alerts'
            AND column_name IN ('target_audience','target_agency','target_lga',
                                'target_ward','target_pu','expires_at'))),
    (12, 'escalation columns exist',
        (SELECT count(*) = 2 FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'alerts'
            AND column_name IN ('escalated_to_agency','escalation_log'))),
    (13, 'profiles.badge_number exists',
        (SELECT count(*) = 1 FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'profiles'
            AND column_name = 'badge_number')),
    (14, 'alerts.assigned_tier exists',
        (SELECT count(*) = 1 FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'alerts'
            AND column_name = 'assigned_tier')),
    (15, 'the helper functions exist (4)',
        (SELECT count(*) = 4 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public'
            AND p.proname IN ('auth_role','is_staff','is_command','liaison_agency')))
)
SELECT
  CASE WHEN ok THEN 'PASS' ELSE '*** FAIL ***' END AS result,
  name
FROM checks
ORDER BY ok, ord;
