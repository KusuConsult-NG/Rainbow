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
-- The two writers disagree. The mobile agent dashboard wrote a TIER ('HQ',
-- 'LGA') here — its own comment said "tier label for filtering" — so a mobile
-- escalation was invisible to every agency portal while still showing as
-- ESCALATED on the HQ board. That has since been given its own column,
-- `assigned_tier`, and the mobile side writes it there.
--
-- CORRECTION, 2026-10-07. This comment used to say the console writes an agency
-- code, 'POLICE' or 'ARMY', "which is what AgencyPortal filters on". It did not.
-- The console's escalation menu was built from the list that badges Operation
-- Rainbow's own staff, so it wrote 'NPF', 'MILITARY', 'RAINBOW' or 'VGN' —
-- codes no liaison role, portal or contact variable knows. An incident handed
-- to the Police was stored as 'NPF' and the Police portal, which asks for
-- 'POLICE', never showed it. Fixed on the console side; the column stays free
-- text because production holds rows written before any of this was settled.
-- Recorded in E2E_AUDIT_REPORT.md.
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
