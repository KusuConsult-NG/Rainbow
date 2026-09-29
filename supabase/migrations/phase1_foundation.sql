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
