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
