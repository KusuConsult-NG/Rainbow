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
