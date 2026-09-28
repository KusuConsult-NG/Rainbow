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
-- 20260927000000_signup_cannot_choose_role.sql  (outstanding)
-- ----------------------------------------------------------------------------
DO $b$ BEGIN RAISE NOTICE 'applying 20260927000000_signup_cannot_choose_role.sql'; END $b$;

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
-- 20260928000000_command_chain_escalation.sql  (outstanding)
-- ----------------------------------------------------------------------------
DO $b$ BEGIN RAISE NOTICE 'applying 20260928000000_command_chain_escalation.sql'; END $b$;

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
-- 20260929000000_telemetry_is_not_a_standing_feed.sql  (outstanding)
-- ----------------------------------------------------------------------------
DO $b$ BEGIN RAISE NOTICE 'applying 20260929000000_telemetry_is_not_a_standing_feed.sql'; END $b$;

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
-- 20260930000000_sms_device_keys.sql  (outstanding)
-- ----------------------------------------------------------------------------
DO $b$ BEGIN RAISE NOTICE 'applying 20260930000000_sms_device_keys.sql'; END $b$;

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
-- 20261001000000_mesh_ingest.sql  (outstanding)
-- ----------------------------------------------------------------------------
DO $b$ BEGIN RAISE NOTICE 'applying 20261001000000_mesh_ingest.sql'; END $b$;

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
            AND p.proname IN ('auth_role','is_staff','is_command','liaison_agency'))),
    -- The signup path must not read a role out of client-supplied metadata.
    -- Anyone holding the anon key could otherwise enrol themselves as
    -- HQ_COMMAND, and every policy in the system trusts profiles.role.
    (16, 'a signup cannot choose its own role',
        (SELECT pg_get_functiondef(p.oid) NOT LIKE '%raw_user_meta_data->>''role''%'
           FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'handle_new_user')),
    (17, 'new alerts land at the polling unit',
        (SELECT column_default LIKE '%UNIT%' FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'alerts'
            AND column_name = 'assigned_tier')),
    (18, 'the escalation job exists and is service-role only',
        (SELECT NOT has_function_privilege('authenticated',
                  'public.escalate_overdue_alerts()', 'EXECUTE')
           FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'escalate_overdue_alerts')),
    (19, 'the chain terminates at HQ',
        (SELECT public.next_tier('HQ') IS NULL AND public.next_tier('UNIT') = 'WARD'))
)
SELECT
  CASE WHEN ok THEN 'PASS' ELSE '*** FAIL ***' END AS result,
  name
FROM checks
ORDER BY ok, ord;
