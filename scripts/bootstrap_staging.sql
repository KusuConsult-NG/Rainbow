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
DROP POLICY IF EXISTS "Allow public read access to profiles" ON public.profiles;
CREATE POLICY "Allow public read access to profiles" ON public.profiles FOR SELECT USING (true);
DROP POLICY IF EXISTS "Allow individual insert/update to own profile" ON public.profiles;
CREATE POLICY "Allow individual insert/update to own profile" ON public.profiles FOR ALL USING (auth.uid() = id);

-- Alerts RLS
DROP POLICY IF EXISTS "Allow authenticated users to read alerts" ON public.alerts;
CREATE POLICY "Allow authenticated users to read alerts" ON public.alerts FOR SELECT USING (auth.role() = 'authenticated' OR auth.role() = 'service_role');
DROP POLICY IF EXISTS "Allow authenticated users to insert alerts" ON public.alerts;
CREATE POLICY "Allow authenticated users to insert alerts" ON public.alerts FOR INSERT WITH CHECK (true);
DROP POLICY IF EXISTS "Allow authenticated users to update alerts" ON public.alerts;
CREATE POLICY "Allow authenticated users to update alerts" ON public.alerts FOR UPDATE USING (true);

-- Telemetry RLS
DROP POLICY IF EXISTS "Allow reading telemetry" ON public.telemetry;
CREATE POLICY "Allow reading telemetry" ON public.telemetry FOR SELECT USING (true);
DROP POLICY IF EXISTS "Allow users to update own telemetry" ON public.telemetry;
CREATE POLICY "Allow users to update own telemetry" ON public.telemetry FOR ALL USING (true);

-- Chat Messages RLS
DROP POLICY IF EXISTS "Allow reading chat messages" ON public.chat_messages;
CREATE POLICY "Allow reading chat messages" ON public.chat_messages FOR SELECT USING (true);
DROP POLICY IF EXISTS "Allow inserting chat messages" ON public.chat_messages;
CREATE POLICY "Allow inserting chat messages" ON public.chat_messages FOR INSERT WITH CHECK (true);

-- System Alerts RLS
DROP POLICY IF EXISTS "Allow reading system alerts" ON public.system_alerts;
CREATE POLICY "Allow reading system alerts" ON public.system_alerts FOR SELECT USING (true);
DROP POLICY IF EXISTS "Allow service role to manage system alerts" ON public.system_alerts;
CREATE POLICY "Allow service role to manage system alerts" ON public.system_alerts FOR ALL USING (true);

-- Enable Realtime for Alerts, Telemetry & Chat (idempotent)
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.alerts;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.telemetry;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_messages;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.system_alerts;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

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
  FOR SELECT TO authenticated USING (TRUE);

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
  DROP POLICY IF EXISTS "app_config_read" ON public.app_config;
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

-- ----------------------------------------------------------------------------
-- 20261002000000_sim_channel_events.sql  (outstanding)
-- ----------------------------------------------------------------------------
DO $b$ BEGIN RAISE NOTICE 'applying 20261002000000_sim_channel_events.sql'; END $b$;

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
-- 20261003000000_liaisons_are_not_staff.sql  (outstanding)
-- ----------------------------------------------------------------------------
DO $b$ BEGIN RAISE NOTICE 'applying 20261003000000_liaisons_are_not_staff.sql'; END $b$;

-- ============================================================================
-- OPERATION RAINBOW — AN AGENCY LIAISON IS NOT OPERATION RAINBOW STAFF
--
-- THE HOLE
--
-- Six agencies send liaison officers to this console: the Police, the Army,
-- the DSS, the NSCDC, the FRSC and Operation Safe Haven. They are officers of
-- OTHER organisations, given an account so that an incident handed to their
-- agency reaches them.
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
-- 20261004000000_incident_tracks.sql  (outstanding)
-- ----------------------------------------------------------------------------
DO $b$ BEGIN RAISE NOTICE 'applying 20261004000000_incident_tracks.sql'; END $b$;

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
-- 20261005000000_alert_category.sql  (outstanding)
-- ----------------------------------------------------------------------------
DO $b$ BEGIN RAISE NOTICE 'applying 20261005000000_alert_category.sql'; END $b$;

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
-- 20261006000000_alerts_scoped_to_posting.sql  (outstanding)
-- ----------------------------------------------------------------------------
DO $b$ BEGIN RAISE NOTICE 'applying 20261006000000_alerts_scoped_to_posting.sql'; END $b$;

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
-- 20261007000000_notification_outbox.sql  (outstanding)
-- ----------------------------------------------------------------------------
DO $b$ BEGIN RAISE NOTICE 'applying 20261007000000_notification_outbox.sql'; END $b$;

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
-- 20261008000000_escalation_push_targets.sql  (outstanding)
-- ----------------------------------------------------------------------------
DO $b$ BEGIN RAISE NOTICE 'applying 20261008000000_escalation_push_targets.sql'; END $b$;

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
-- 20261009000000_ward_names_compared_by_key.sql  (outstanding)
-- ----------------------------------------------------------------------------
DO $b$ BEGIN RAISE NOTICE 'applying 20261009000000_ward_names_compared_by_key.sql'; END $b$;

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
-- 20261010000000_append_alert_media_atomically.sql  (outstanding)
-- ----------------------------------------------------------------------------
DO $b$ BEGIN RAISE NOTICE 'applying 20261010000000_append_alert_media_atomically.sql'; END $b$;

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
-- 20261011000000_ussd_reports_are_unconfirmed.sql  (outstanding)
-- ----------------------------------------------------------------------------
DO $b$ BEGIN RAISE NOTICE 'applying 20261011000000_ussd_reports_are_unconfirmed.sql'; END $b$;

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
-- 20261012000000_ussd_filing.sql  (outstanding)
-- ----------------------------------------------------------------------------
DO $b$ BEGIN RAISE NOTICE 'applying 20261012000000_ussd_filing.sql'; END $b$;

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
-- 20261013000000_ussd_landmark.sql  (outstanding)
-- ----------------------------------------------------------------------------
DO $b$ BEGIN RAISE NOTICE 'applying 20261013000000_ussd_landmark.sql'; END $b$;

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
-- 20261014000000_ai_reports_are_kept.sql  (outstanding)
-- ----------------------------------------------------------------------------
DO $b$ BEGIN RAISE NOTICE 'applying 20261014000000_ai_reports_are_kept.sql'; END $b$;

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
-- 20261015000000_oversight_and_debrief.sql  (outstanding)
-- ----------------------------------------------------------------------------
DO $b$ BEGIN RAISE NOTICE 'applying 20261015000000_oversight_and_debrief.sql'; END $b$;

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
-- 20261016000000_telemetry_policy_is_not_public.sql  (outstanding)
-- ----------------------------------------------------------------------------
DO $b$ BEGIN RAISE NOTICE 'applying 20261016000000_telemetry_policy_is_not_public.sql'; END $b$;

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
-- 20261017000000_the_hand_applied_era_is_in_the_history.sql  (outstanding)
-- ----------------------------------------------------------------------------
DO $b$ BEGIN RAISE NOTICE 'applying 20261017000000_the_hand_applied_era_is_in_the_history.sql'; END $b$;

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
--    28; on a repo-built database `category` at 33 is the only one. The same
--    statement reports a different column name on each, which is a diagnosis
--    sent in the wrong direction.
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
    (3, 'no policy grants anon or public anything'
          || coalesce(' — ' || (SELECT string_agg(tablename || '.' || policyname, ', '
                                                  ORDER BY tablename, policyname)
                                  FROM pg_policies
                                 WHERE schemaname = 'public'
                                   AND ('anon' = ANY(roles) OR 'public' = ANY(roles))), ''),
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
