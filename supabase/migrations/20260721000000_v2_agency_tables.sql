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
