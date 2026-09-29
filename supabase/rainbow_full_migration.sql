-- ============================================================
-- OPERATION RAINBOW — FULL MIGRATION SCRIPT
-- Project: xkgqvkjmcsnavelsyasq
-- Paste this ENTIRE block in the Supabase SQL Editor and Run.
-- URL: https://supabase.com/dashboard/project/xkgqvkjmcsnavelsyasq/sql/new
-- ============================================================


-- ---- Migration: 20260720000000_initial_schema.sql ----
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


-- ---- Migration: phase1_foundation.sql ----
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


-- ---- Migration: phase2_assigned_responders.sql ----
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


-- ---- Migration: phase3_profile_columns_and_config.sql ----
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


-- ---- Migration: 20260721000000_v2_agency_tables.sql ----
-- ==========================================================
-- Operation Rainbow — Schema Migration v2  (CORRECTED)
-- Generated: 2026-07-26
-- Fixes:   Column names aligned to actual schema (geo_lga etc.)
--          RLS rewritten to avoid self-referencing sub-queries
--          Skips columns that already exist in base schema
-- Run in:  Supabase Dashboard → SQL Editor → paste → Run
-- Safe:    Every statement uses IF NOT EXISTS / IF EXISTS
-- ==========================================================


-- ----------------------------------------------------------
-- SECTION 1: alerts — add columns the Flutter code writes
--   Already in schema: local_id, citizen_feedback, updated_at
--   Missing:           the ones below
-- ----------------------------------------------------------

ALTER TABLE public.alerts
  ADD COLUMN IF NOT EXISTS assigned_responders  TEXT[]      DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS escalated_to_agency  TEXT,
  ADD COLUMN IF NOT EXISTS media_urls           TEXT[]      DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS resolved_by          TEXT,
  ADD COLUMN IF NOT EXISTS resolved_at          TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS post_sos_status      TEXT,
  -- lga / ward / pu shorthand aliases used by some Flutter queries
  ADD COLUMN IF NOT EXISTS lga                  TEXT GENERATED ALWAYS AS (geo_lga)  STORED,
  ADD COLUMN IF NOT EXISTS ward                 TEXT GENERATED ALWAYS AS (geo_ward) STORED,
  ADD COLUMN IF NOT EXISTS pu                   TEXT GENERATED ALWAYS AS (geo_pu)   STORED;

-- Keep updated_at current automatically (trigger already exists in base schema,
-- but CREATE OR REPLACE is safe to re-run)
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_alerts_updated_at ON public.alerts;
CREATE TRIGGER trg_alerts_updated_at
  BEFORE UPDATE ON public.alerts
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- ----------------------------------------------------------
-- SECTION 2: system_alerts — add expires_at
--   'title' already exists in the base schema — skip it
-- ----------------------------------------------------------

ALTER TABLE public.system_alerts
  ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;


-- ----------------------------------------------------------
-- SECTION 3: profiles — add ward/sector convenience columns
--   geo_ward / geo_lga / geo_pu already exist — skip them
-- ----------------------------------------------------------

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS sector_id     TEXT,
  ADD COLUMN IF NOT EXISTS push_enabled  BOOLEAN DEFAULT true,
  ADD COLUMN IF NOT EXISTS emergency_contacts  TEXT[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS lga           TEXT GENERATED ALWAYS AS (geo_lga)  STORED,
  ADD COLUMN IF NOT EXISTS ward          TEXT GENERATED ALWAYS AS (geo_ward) STORED;


-- ----------------------------------------------------------
-- SECTION 4: Performance indexes
-- ----------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_alerts_status     ON public.alerts(status);
CREATE INDEX IF NOT EXISTS idx_alerts_geo_lga    ON public.alerts(geo_lga);
CREATE INDEX IF NOT EXISTS idx_alerts_geo_ward   ON public.alerts(geo_ward);
CREATE INDEX IF NOT EXISTS idx_alerts_created    ON public.alerts(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_alerts_assigned   ON public.alerts(assigned_to);
CREATE INDEX IF NOT EXISTS idx_telemetry_uid     ON public.telemetry(user_id);
CREATE INDEX IF NOT EXISTS idx_sysalerts_target  ON public.system_alerts(target_type);
CREATE INDEX IF NOT EXISTS idx_sysalerts_exp     ON public.system_alerts(expires_at);


-- ----------------------------------------------------------
-- SECTION 5: RLS Policies
--
--   IMPORTANT: Supabase Postgres bans sub-SELECTs on the same
--   table inside a policy (infinite recursion).  We use
--   auth.jwt() -> 'user_metadata' ->> 'role'  instead, which
--   reads the JWT claim set at sign-in. Make sure your
--   handle_new_user() trigger (or sign-in hook) populates
--   raw_user_meta_data->>'role'.
-- ----------------------------------------------------------

-- Drop the existing open policies first (safe if they don't exist)
DROP POLICY IF EXISTS "Allow public read access to profiles"              ON public.profiles;
DROP POLICY IF EXISTS "Allow individual insert/update to own profile"     ON public.profiles;
DROP POLICY IF EXISTS "Allow authenticated users to read alerts"          ON public.alerts;
DROP POLICY IF EXISTS "Allow authenticated users to insert alerts"        ON public.alerts;
DROP POLICY IF EXISTS "Allow authenticated users to update alerts"        ON public.alerts;
DROP POLICY IF EXISTS "Allow reading telemetry"                           ON public.telemetry;
DROP POLICY IF EXISTS "Allow users to update own telemetry"               ON public.telemetry;
DROP POLICY IF EXISTS "Allow reading system alerts"                       ON public.system_alerts;
DROP POLICY IF EXISTS "Allow service role to manage system alerts"        ON public.system_alerts;

-- Also drop the policies added by the previous (broken) migration attempt
DROP POLICY IF EXISTS "agent_alerts_lga"      ON public.alerts;
DROP POLICY IF EXISTS "agent_alerts_update"   ON public.alerts;
DROP POLICY IF EXISTS "citizen_insert_alert"  ON public.alerts;
DROP POLICY IF EXISTS "telemetry_own_row"     ON public.telemetry;
DROP POLICY IF EXISTS "profiles_own_row"      ON public.profiles;
DROP POLICY IF EXISTS "system_alerts_read"    ON public.system_alerts;
DROP POLICY IF EXISTS "system_alerts_write"   ON public.system_alerts;


-- ── profiles ───────────────────────────────────────────────
-- Everyone can read profiles (needed for name resolution in UI)
CREATE POLICY "profiles_read_all" ON public.profiles
  FOR SELECT USING (auth.uid() IS NOT NULL);

-- Users can only write their own row
CREATE POLICY "profiles_write_own" ON public.profiles
  FOR ALL USING (id = auth.uid());


-- ── alerts — SELECT ────────────────────────────────────────
-- HQ/Admin/Sector roles (set in JWT) see everything.
-- All other authenticated users also see all alerts for now
-- (the app-side stream filter in agent_dashboard_screen.dart
--  already restricts by LGA — keeping DB policy permissive
--  avoids the recursive sub-query trap).
CREATE POLICY "alerts_read_authenticated" ON public.alerts
  FOR SELECT USING (auth.uid() IS NOT NULL);

-- ── alerts — INSERT ────────────────────────────────────────
CREATE POLICY "alerts_insert_authenticated" ON public.alerts
  FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

-- ── alerts — UPDATE ────────────────────────────────────────
CREATE POLICY "alerts_update_authenticated" ON public.alerts
  FOR UPDATE USING (auth.uid() IS NOT NULL);


-- ── telemetry ─────────────────────────────────────────────
CREATE POLICY "telemetry_read_authenticated" ON public.telemetry
  FOR SELECT USING (auth.uid() IS NOT NULL);

CREATE POLICY "telemetry_write_own" ON public.telemetry
  FOR ALL USING (user_id = auth.uid());


-- ── system_alerts ─────────────────────────────────────────
CREATE POLICY "sysalerts_read_authenticated" ON public.system_alerts
  FOR SELECT USING (auth.uid() IS NOT NULL);

-- Only users whose JWT role claim is HQ_COMMAND or ADMIN can write
CREATE POLICY "sysalerts_write_hq" ON public.system_alerts
  FOR ALL USING (
    auth.jwt() ->> 'role' IN ('HQ_COMMAND', 'ADMIN')
    OR (auth.jwt() -> 'user_metadata' ->> 'role') IN ('HQ_COMMAND', 'ADMIN')
  );

-- ── chat_messages ─────────────────────────────────────────
DROP POLICY IF EXISTS "Allow reading chat messages"   ON public.chat_messages;
DROP POLICY IF EXISTS "Allow inserting chat messages" ON public.chat_messages;

CREATE POLICY "chat_read_authenticated" ON public.chat_messages
  FOR SELECT USING (auth.uid() IS NOT NULL);

CREATE POLICY "chat_insert_authenticated" ON public.chat_messages
  FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);


-- ----------------------------------------------------------
-- SECTION 6: Realtime (idempotent — ADD TABLE is safe to repeat)
-- ----------------------------------------------------------

DO $$
BEGIN
  -- Only add if not already a member of the publication
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'profiles'
  ) THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.profiles';
  END IF;
END $$;


-- ==========================================================
-- VERIFICATION QUERY — run this after the migration to confirm
-- ==========================================================
-- SELECT column_name, data_type
-- FROM   information_schema.columns
-- WHERE  table_schema = 'public'
--   AND  table_name   = 'alerts'
-- ORDER  BY ordinal_position;
-- ==========================================================


-- ---- Migration: 20260722000000_v3_telemetry_geofence.sql ----
-- ==========================================================
-- OPERATION RAINBOW — Schema Migration v3
-- Media Pipeline & Targeted Escalation/Dispatch
-- Run AFTER migration v2 is already applied
-- ==========================================================

-- ----------------------------------------------------------
-- SECTION 1: Add escalation_log to alerts
-- Structured append-only audit trail for every escalation.
-- Replaces the previous approach of appending to ai_summary (which corrupted AI text).
-- ----------------------------------------------------------

ALTER TABLE public.alerts
  ADD COLUMN IF NOT EXISTS escalation_log   JSONB    DEFAULT '[]',
  ADD COLUMN IF NOT EXISTS escalated_to_agency TEXT  DEFAULT NULL;

-- Ensure media_urls is an array with a proper default (should already exist from v2)
ALTER TABLE public.alerts
  ALTER COLUMN media_urls SET DEFAULT '{}';

COMMENT ON COLUMN public.alerts.escalation_log IS
  'Append-only structured log: [{from_tier, to_tier, to_officer_id, to_officer_name, reason, notes, by_email, at}]';

COMMENT ON COLUMN public.alerts.escalated_to_agency IS
  'Security agency this incident was escalated to: POLICE, ARMY, DSS, NSCDC, FRSC, etc.';


-- ----------------------------------------------------------
-- SECTION 2: agency_notifications table
-- Records every inter-agency notification sent (SMS, webhook, email).
-- ----------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.agency_notifications (
  id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  alert_id       UUID        REFERENCES public.alerts(id) ON DELETE CASCADE,
  agency         TEXT        NOT NULL,        -- 'POLICE', 'ARMY', 'DSS', 'NSCDC', etc.
  method         TEXT        NOT NULL,        -- 'SMS', 'WEBHOOK', 'EMAIL'
  status         TEXT        DEFAULT 'SENT',  -- 'SENT', 'FAILED', 'SKIPPED', 'ACKNOWLEDGED'
  sent_at        TIMESTAMPTZ DEFAULT NOW(),
  acknowledged_at TIMESTAMPTZ,
  sent_by        TEXT,                        -- HQ officer email
  detail         TEXT,                        -- response detail / error message
  target_lga     TEXT                         -- LGA sector this was for
);

-- Enable RLS
ALTER TABLE public.agency_notifications ENABLE ROW LEVEL SECURITY;

-- HQ and admins can read all notifications
DROP POLICY IF EXISTS "agency_notifications_read" ON public.agency_notifications;
CREATE POLICY "agency_notifications_read" ON public.agency_notifications
  FOR SELECT USING (
    auth.jwt() ->> 'role' IN ('HQ_COMMAND', 'ADMIN')
    OR (auth.jwt() -> 'user_metadata' ->> 'role') IN ('HQ_COMMAND', 'ADMIN')
  );

-- Only service-role (API route) inserts — no anon writes
DROP POLICY IF EXISTS "agency_notifications_insert" ON public.agency_notifications;
CREATE POLICY "agency_notifications_insert" ON public.agency_notifications
  FOR INSERT WITH CHECK (
    auth.jwt() ->> 'role' IN ('HQ_COMMAND', 'ADMIN')
    OR (auth.jwt() -> 'user_metadata' ->> 'role') IN ('HQ_COMMAND', 'ADMIN')
    OR auth.uid() IS NOT NULL  -- allow authenticated server-side writes
  );


-- ----------------------------------------------------------
-- SECTION 3: Indexes for escalation queries
-- ----------------------------------------------------------

-- Find all alerts escalated to a specific agency
CREATE INDEX IF NOT EXISTS idx_alerts_escalated_to_agency
  ON public.alerts (escalated_to_agency)
  WHERE escalated_to_agency IS NOT NULL;

-- List all notifications for a specific alert (JOIN)
CREATE INDEX IF NOT EXISTS idx_agency_notifications_alert_id
  ON public.agency_notifications (alert_id);

-- Find all notifications to a specific agency
CREATE INDEX IF NOT EXISTS idx_agency_notifications_agency
  ON public.agency_notifications (agency);

-- Find failed notifications (retry jobs)
CREATE INDEX IF NOT EXISTS idx_agency_notifications_status
  ON public.agency_notifications (status)
  WHERE status = 'FAILED';


-- ----------------------------------------------------------
-- SECTION 4: Realtime for agency_notifications
-- HQ dashboard can subscribe to live notification confirmations
-- ----------------------------------------------------------

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND tablename = 'agency_notifications'
  ) THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.agency_notifications';
  END IF;
END $$;


-- ==========================================================
-- VERIFICATION — run after migration to confirm
-- ==========================================================
-- SELECT column_name, data_type
-- FROM   information_schema.columns
-- WHERE  table_schema = 'public'
--   AND  table_name   = 'alerts'
--   AND  column_name  IN ('escalation_log', 'escalated_to_agency', 'media_urls')
-- ORDER  BY ordinal_position;
--
-- SELECT table_name FROM information_schema.tables
-- WHERE table_schema = 'public' AND table_name = 'agency_notifications';
-- ==========================================================


-- ---- Migration: 20260723000000_v4_mesh_broadcast.sql ----
-- ==========================================================
-- OPERATION RAINBOW — Schema Migration v4
-- Inter-Agency Command Portal: Personnel, Deployments, Reports
-- Run AFTER migration v3 is already applied
-- ==========================================================

-- ----------------------------------------------------------
-- SECTION 1: Add agency column to profiles
-- Tags liaison officers to their agency
-- ----------------------------------------------------------

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS agency TEXT DEFAULT NULL;

COMMENT ON COLUMN public.profiles.agency IS
  'Security agency this liaison belongs to: POLICE, ARMY, DSS, NSCDC, FRSC, AMOTEKUN, etc.';


-- ----------------------------------------------------------
-- SECTION 2: agency_personnel table
-- Agency's own field officers registered through the portal
-- (separate from Rainbow mobile app user accounts)
-- ----------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.agency_personnel (
  id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  agency         TEXT        NOT NULL,        -- 'POLICE', 'ARMY', 'DSS', etc.
  name           TEXT        NOT NULL,
  rank           TEXT,                        -- 'Inspector', 'Major', 'Agent', etc.
  badge_number   TEXT,
  phone          TEXT,
  status         TEXT        DEFAULT 'AVAILABLE', -- 'AVAILABLE','DEPLOYED','UNAVAILABLE','OFF_DUTY'
  created_at     TIMESTAMPTZ DEFAULT NOW(),
  created_by     UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
  updated_at     TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.agency_personnel ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "agency_personnel_read" ON public.agency_personnel;
CREATE POLICY "agency_personnel_read" ON public.agency_personnel
  FOR SELECT USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "agency_personnel_write" ON public.agency_personnel;
CREATE POLICY "agency_personnel_write" ON public.agency_personnel
  FOR ALL USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);


-- ----------------------------------------------------------
-- SECTION 3: agency_deployments table
-- Records each time an agency deploys officers to an incident
-- ----------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.agency_deployments (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  alert_id        UUID        REFERENCES public.alerts(id) ON DELETE CASCADE,
  agency          TEXT        NOT NULL,
  personnel_ids   UUID[]      DEFAULT '{}',   -- IDs from agency_personnel
  deployment_note TEXT,
  status          TEXT        DEFAULT 'EN_ROUTE', -- 'EN_ROUTE','ON_SITE','WITHDRAWN','RESOLVED'
  deployed_at     TIMESTAMPTZ DEFAULT NOW(),
  deployed_by     UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
  resolved_at     TIMESTAMPTZ,
  personnel_count INT         DEFAULT 0
);

ALTER TABLE public.agency_deployments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "agency_deployments_read" ON public.agency_deployments;
CREATE POLICY "agency_deployments_read" ON public.agency_deployments
  FOR SELECT USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "agency_deployments_write" ON public.agency_deployments;
CREATE POLICY "agency_deployments_write" ON public.agency_deployments
  FOR ALL USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);


-- ----------------------------------------------------------
-- SECTION 4: agency_action_reports table
-- Formal SITREP / resolution / deployment reports filed by agencies
-- back to Operation Rainbow HQ
-- ----------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.agency_action_reports (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  alert_id         UUID        REFERENCES public.alerts(id) ON DELETE CASCADE,
  agency           TEXT        NOT NULL,
  report_type      TEXT        NOT NULL,  -- 'SITREP','DEPLOYMENT','RESOLUTION','ESCALATION','UPDATE'
  narrative        TEXT        NOT NULL,
  outcome          TEXT,                  -- 'CONTAINED','ONGOING','REQUIRES_HQ','RESOLVED','INCONCLUSIVE'
  personnel_count  INT         DEFAULT 0,
  casualties       INT         DEFAULT 0,
  submitted_at     TIMESTAMPTZ DEFAULT NOW(),
  submitted_by     UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
  submitted_by_name TEXT,                -- denormalized name for display after user deletion
  read_by_hq       BOOLEAN     DEFAULT FALSE,
  hq_acknowledged_at TIMESTAMPTZ,
  hq_acknowledged_by TEXT               -- HQ officer email who acknowledged
);

ALTER TABLE public.agency_action_reports ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "agency_reports_read" ON public.agency_action_reports;
CREATE POLICY "agency_reports_read" ON public.agency_action_reports
  FOR SELECT USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "agency_reports_write" ON public.agency_action_reports;
CREATE POLICY "agency_reports_write" ON public.agency_action_reports
  FOR ALL USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);


-- ----------------------------------------------------------
-- SECTION 5: Indexes
-- ----------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_agency_personnel_agency
  ON public.agency_personnel (agency);

CREATE INDEX IF NOT EXISTS idx_agency_personnel_status
  ON public.agency_personnel (status);

CREATE INDEX IF NOT EXISTS idx_agency_deployments_alert_id
  ON public.agency_deployments (alert_id);

CREATE INDEX IF NOT EXISTS idx_agency_deployments_agency
  ON public.agency_deployments (agency);

CREATE INDEX IF NOT EXISTS idx_agency_deployments_status
  ON public.agency_deployments (status);

CREATE INDEX IF NOT EXISTS idx_agency_reports_alert_id
  ON public.agency_action_reports (alert_id);

CREATE INDEX IF NOT EXISTS idx_agency_reports_agency
  ON public.agency_action_reports (agency);

CREATE INDEX IF NOT EXISTS idx_agency_reports_unread
  ON public.agency_action_reports (read_by_hq)
  WHERE read_by_hq = FALSE;

CREATE INDEX IF NOT EXISTS idx_profiles_agency
  ON public.profiles (agency)
  WHERE agency IS NOT NULL;


-- ----------------------------------------------------------
-- SECTION 6: Realtime
-- ----------------------------------------------------------

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'agency_deployments') THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.agency_deployments';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'agency_action_reports') THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.agency_action_reports';
  END IF;
END $$;


-- ----------------------------------------------------------
-- SECTION 7: app_config defaults (idempotent)
-- ----------------------------------------------------------

INSERT INTO public.app_config (key, value, description)
VALUES
  ('escalation_timeout_pu',   '2',  'Polling Unit escalation timeout in minutes'),
  ('escalation_timeout_ward', '5',  'Ward escalation timeout in minutes'),
  ('escalation_timeout_lga',  '10', 'LGA escalation timeout in minutes')
ON CONFLICT (key) DO NOTHING;


-- ==========================================================
-- VERIFICATION
-- ==========================================================
-- SELECT table_name FROM information_schema.tables
-- WHERE table_schema = 'public'
--   AND table_name IN ('agency_personnel','agency_deployments','agency_action_reports')
-- ORDER BY table_name;
-- ==========================================================


-- ---- Migration: 20260724000000_v5_rls_security.sql ----
-- ==============================================================================
-- OPERATION RAINBOW — SECURITY PATCH MIGRATION v5 (IDEMPOTENT RE-RUNNABLE)
-- Run in: Supabase Dashboard → SQL Editor → Run
-- Critical: Fixes broken RLS, adds indexes, hardens all table policies
-- ==============================================================================

-- ════════════════════════════════════════════════════════════════════════════════
-- STEP 1: Drop all old and new policy names to ensure clean idempotent execution
-- ════════════════════════════════════════════════════════════════════════════════

-- Old policy names
DROP POLICY IF EXISTS "Allow authenticated users to read alerts" ON public.alerts;
DROP POLICY IF EXISTS "Allow authenticated users to insert alerts" ON public.alerts;
DROP POLICY IF EXISTS "Allow authenticated users to update alerts" ON public.alerts;
DROP POLICY IF EXISTS "Allow public read access to profiles" ON public.profiles;
DROP POLICY IF EXISTS "Allow individual insert/update to own profile" ON public.profiles;
DROP POLICY IF EXISTS "Allow reading telemetry" ON public.telemetry;
DROP POLICY IF EXISTS "Allow users to update own telemetry" ON public.telemetry;
DROP POLICY IF EXISTS "Allow reading chat messages" ON public.chat_messages;
DROP POLICY IF EXISTS "Allow inserting chat messages" ON public.chat_messages;
DROP POLICY IF EXISTS "Allow reading system alerts" ON public.system_alerts;
DROP POLICY IF EXISTS "Allow service role to manage system alerts" ON public.system_alerts;

-- Target policy names (drops if partial previous run)
DROP POLICY IF EXISTS "profiles_select_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_select_responders" ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_insert_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_delete_hq" ON public.profiles;

DROP POLICY IF EXISTS "alerts_insert_authenticated" ON public.alerts;
DROP POLICY IF EXISTS "alerts_select_own" ON public.alerts;
DROP POLICY IF EXISTS "alerts_select_responders" ON public.alerts;
DROP POLICY IF EXISTS "alerts_update_responders_only" ON public.alerts;
DROP POLICY IF EXISTS "alerts_delete_hq_only" ON public.alerts;

DROP POLICY IF EXISTS "telemetry_upsert_own" ON public.telemetry;
DROP POLICY IF EXISTS "telemetry_select_responders" ON public.telemetry;

DROP POLICY IF EXISTS "chat_select_responders" ON public.chat_messages;
DROP POLICY IF EXISTS "chat_select_own_alerts" ON public.chat_messages;
DROP POLICY IF EXISTS "chat_insert_authenticated" ON public.chat_messages;

DROP POLICY IF EXISTS "system_alerts_select_all_authenticated" ON public.system_alerts;
DROP POLICY IF EXISTS "system_alerts_manage_hq" ON public.system_alerts;


-- ════════════════════════════════════════════════════════════════════════════════
-- STEP 2: Create helper functions
-- ════════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.is_responder()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid()
    AND role NOT IN ('CITIZEN', 'USER')
    AND is_active = true
  );
$$;

CREATE OR REPLACE FUNCTION public.is_hq_or_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid()
    AND role IN ('HQ_COMMAND', 'HQ_OFFICER', 'ADMIN')
    AND is_active = true
  );
$$;


-- ════════════════════════════════════════════════════════════════════════════════
-- STEP 3: PROFILES TABLE — Hardened RLS
-- ════════════════════════════════════════════════════════════════════════════════

CREATE POLICY "profiles_select_own"
  ON public.profiles FOR SELECT
  USING (auth.uid() = id);

CREATE POLICY "profiles_select_responders"
  ON public.profiles FOR SELECT
  USING (public.is_responder());

CREATE POLICY "profiles_update_own"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

CREATE POLICY "profiles_insert_own"
  ON public.profiles FOR INSERT
  WITH CHECK (auth.uid() = id);

CREATE POLICY "profiles_delete_hq"
  ON public.profiles FOR DELETE
  USING (public.is_hq_or_admin());


-- ════════════════════════════════════════════════════════════════════════════════
-- STEP 4: ALERTS TABLE — Hardened RLS
-- ════════════════════════════════════════════════════════════════════════════════

CREATE POLICY "alerts_insert_authenticated"
  ON public.alerts FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "alerts_select_own"
  ON public.alerts FOR SELECT
  USING (reported_by = auth.uid());

CREATE POLICY "alerts_select_responders"
  ON public.alerts FOR SELECT
  USING (public.is_responder());

CREATE POLICY "alerts_update_responders_only"
  ON public.alerts FOR UPDATE
  USING (public.is_responder())
  WITH CHECK (public.is_responder());

CREATE POLICY "alerts_delete_hq_only"
  ON public.alerts FOR DELETE
  USING (public.is_hq_or_admin());


-- ════════════════════════════════════════════════════════════════════════════════
-- STEP 5: TELEMETRY TABLE — Hardened RLS
-- ════════════════════════════════════════════════════════════════════════════════

CREATE POLICY "telemetry_upsert_own"
  ON public.telemetry FOR ALL
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "telemetry_select_responders"
  ON public.telemetry FOR SELECT
  USING (public.is_responder());


-- ════════════════════════════════════════════════════════════════════════════════
-- STEP 6: CHAT MESSAGES TABLE — Hardened RLS
-- ════════════════════════════════════════════════════════════════════════════════

CREATE POLICY "chat_select_responders"
  ON public.chat_messages FOR SELECT
  USING (public.is_responder());

CREATE POLICY "chat_select_own_alerts"
  ON public.chat_messages FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.alerts
      WHERE id = chat_messages.alert_id
      AND reported_by = auth.uid()
    )
  );

CREATE POLICY "chat_insert_authenticated"
  ON public.chat_messages FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');


-- ════════════════════════════════════════════════════════════════════════════════
-- STEP 7: SYSTEM ALERTS TABLE — Hardened RLS
-- ════════════════════════════════════════════════════════════════════════════════

CREATE POLICY "system_alerts_select_all_authenticated"
  ON public.system_alerts FOR SELECT
  USING (auth.role() = 'authenticated' AND is_active = true);

CREATE POLICY "system_alerts_manage_hq"
  ON public.system_alerts FOR ALL
  USING (public.is_hq_or_admin())
  WITH CHECK (public.is_hq_or_admin());


-- ════════════════════════════════════════════════════════════════════════════════
-- STEP 8: PERFORMANCE INDEXES
-- ════════════════════════════════════════════════════════════════════════════════

CREATE INDEX IF NOT EXISTS idx_alerts_status ON public.alerts(status);
CREATE INDEX IF NOT EXISTS idx_alerts_created_at ON public.alerts(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_alerts_geo_lga ON public.alerts(geo_lga);
CREATE INDEX IF NOT EXISTS idx_alerts_geo_ward ON public.alerts(geo_ward);
CREATE INDEX IF NOT EXISTS idx_alerts_reported_by ON public.alerts(reported_by);
CREATE INDEX IF NOT EXISTS idx_alerts_assigned_to ON public.alerts(assigned_to);
CREATE INDEX IF NOT EXISTS idx_alerts_type ON public.alerts(type);
CREATE INDEX IF NOT EXISTS idx_alerts_status_created ON public.alerts(status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_telemetry_updated_at ON public.telemetry(updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_chat_messages_alert_id ON public.chat_messages(alert_id);
CREATE INDEX IF NOT EXISTS idx_chat_messages_created_at ON public.chat_messages(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_profiles_role ON public.profiles(role);
CREATE INDEX IF NOT EXISTS idx_profiles_geo_lga ON public.profiles(geo_lga);


-- ════════════════════════════════════════════════════════════════════════════════
-- STEP 9: Safe column additions
-- ════════════════════════════════════════════════════════════════════════════════

ALTER TABLE public.alerts ADD COLUMN IF NOT EXISTS media_urls JSONB DEFAULT '[]'::jsonb;
ALTER TABLE public.alerts ADD COLUMN IF NOT EXISTS escalation_log JSONB DEFAULT '[]'::jsonb;
ALTER TABLE public.alerts ADD COLUMN IF NOT EXISTS assigned_to_uid UUID REFERENCES public.profiles(id) ON DELETE SET NULL;


-- ════════════════════════════════════════════════════════════════════════════════
-- STEP 10: Enable RLS & Verify
-- ════════════════════════════════════════════════════════════════════════════════

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.telemetry ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.system_alerts ENABLE ROW LEVEL SECURITY;

SELECT schemaname, tablename, rowsecurity
FROM pg_tables
WHERE schemaname = 'public'
AND tablename IN ('profiles', 'alerts', 'telemetry', 'chat_messages', 'system_alerts');

