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
