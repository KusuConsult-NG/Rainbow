-- ============================================================================
-- OPERATION RAINBOW — MASS BROADCAST, MADE TO WORK
--
-- `system_alerts` is how HQ warns the public and its own responders. It did not
-- work. Four independent faults, none of which surfaced as anything an operator
-- would read as failure:
--
--   1. NEITHER WRITER SUPPLIED `title`, which is NOT NULL with no default. On a
--      database built from these migrations every broadcast raised a not-null
--      violation. The console printed the raw Postgres message; the mobile
--      admin screen printed "Error sending broadcast: <exception>".
--
--   2. The console wrote SIX COLUMNS THAT EXIST IN NO MIGRATION —
--      target_agency, target_sector, target_lga, target_ward, target_pu,
--      active — so PostgREST rejected the insert before the constraint could
--      even be reached.
--
--   3. Audience targeting was IGNORED. The console wrote `target_audience`;
--      the mobile reader filtered on `target_type`, which defaults to 'ALL'.
--      A "FIELD RESPONDERS ONLY" advisory therefore reached every citizen,
--      while the console reported it had gone to responders only.
--
--   4. Geographic targeting was enforced NOWHERE. The console offers LGA, ward
--      and polling-unit scoping and reports "dispatched to JOS NORTH LGA";
--      no reader ever filtered on it, so every advisory went statewide.
--
-- Faults 3 and 4 are the dangerous ones. A broadcast that fails loudly gets
-- re-sent by radio. A broadcast that reports success while going to the wrong
-- people does not — and on this system that is either a panic sent to the whole
-- state or an evacuation order that never reaches the ward it was meant for.
--
-- WHAT IS CANONICAL NOW
--
-- `lib/core/models/broadcast_alert.dart` already declared targetLga, targetWard,
-- targetPu and targetAudience: the intended design was always the wider one, and
-- only the schema never caught up. So the columns are added here, and the code
-- is changed to agree on one name per concept:
--
--   audience   target_audience     (target_type kept, read as a fallback for
--                                   rows written before this)
--   active     is_active           (the console wrote `active`; that column
--                                   never existed)
--   scope      target_lga / target_ward / target_pu / target_agency
--
-- Idempotent: safe to re-run.
-- ============================================================================

DO $broadcast$
BEGIN
  IF to_regclass('public.system_alerts') IS NULL THEN
    RAISE NOTICE 'skipping system_alerts: table not present in this database';
    RETURN;
  END IF;

  -- The scoping the console has been offering all along.
  ALTER TABLE public.system_alerts
    ADD COLUMN IF NOT EXISTS target_audience TEXT DEFAULT 'ALL',
    ADD COLUMN IF NOT EXISTS target_agency   TEXT DEFAULT 'ALL',
    ADD COLUMN IF NOT EXISTS target_lga      TEXT DEFAULT 'ALL',
    ADD COLUMN IF NOT EXISTS target_ward     TEXT DEFAULT 'ALL',
    ADD COLUMN IF NOT EXISTS target_pu       TEXT DEFAULT 'ALL',
    ADD COLUMN IF NOT EXISTS expires_at      TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '24 hours');

  -- `title` stays NOT NULL — a broadcast with no heading is a worse artefact
  -- than one with a generic heading — but it gets a default, so no writer can
  -- fail the insert on it again. Both writers now send a real one.
  ALTER TABLE public.system_alerts ALTER COLUMN title SET DEFAULT 'ADVISORY';

  -- Rows written before this migration have no audience recorded under the
  -- canonical name. Carry the legacy value across rather than leaving them to
  -- the reader's fallback forever. Only touches rows where the canonical column
  -- is genuinely empty, so re-running changes nothing.
  UPDATE public.system_alerts
     SET target_audience = COALESCE(NULLIF(target_type, ''), 'ALL')
   WHERE target_audience IS NULL;

  -- Reads are always "the live advisories for this audience", never a table
  -- scan, and this is on the path of every app launch.
  CREATE INDEX IF NOT EXISTS system_alerts_live_idx
    ON public.system_alerts (is_active, expires_at DESC);
END $broadcast$;
