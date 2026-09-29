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
