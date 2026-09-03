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
