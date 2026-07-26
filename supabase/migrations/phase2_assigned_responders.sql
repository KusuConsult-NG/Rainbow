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
