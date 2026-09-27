-- ============================================================================
-- OPERATION RAINBOW — THE COMMAND CHAIN
--
-- An alert lands at the POLLING UNIT. The PU escalates to the WARD, the WARD to
-- the LGA, the LGA to HQ. HQ is the top: it overrides when the chain below it
-- is not responding.
--
-- Three things were missing for that to be true.
--
-- 1. NOTHING PUT AN ALERT AT THE PU.
--
--    `assigned_tier` was nullable with no default, so an alert arrived owned by
--    nobody. The chain had a ladder but no bottom rung. It defaults to 'UNIT'
--    now, in the DATABASE rather than in a client, because an alert inserted by
--    the mobile app, by the console, by the offline queue replaying, or by a
--    future integration must all land in the same place. A client-side default
--    is one forgotten call site away from an unowned emergency.
--
-- 2. THE TIMEOUTS WERE CONFIGURED AND DEAD.
--
--    `app_config` has seeded escalation timeouts — PU 2 minutes, WARD 5, LGA 10
--    — and the console's System Logic screen lets an operator edit them. The
--    ONLY code that touched those keys was the screen that displays and saves
--    them. Nothing ever escalated on a timeout. An operator setting "PU
--    timeout: 2 minutes" was configuring a policy that did not exist.
--
--    That is the worst kind of dead setting: it is not missing, it is
--    reassuring. `escalate_overdue_alerts()` below makes it real.
--
-- 3. THERE WAS NO CLOCK ON OWNERSHIP.
--
--    Nothing recorded WHEN a tier took an alert, so "has this tier had it too
--    long?" was unanswerable. `tier_assigned_at` starts that clock on insert
--    and restarts it on every escalation.
--
-- WHY SERVER-SIDE
--
-- A tier that is not responding is very often a tier that is offline. An
-- escalation that only runs while somebody has the console open cannot fire in
-- exactly the case it exists for. This runs in the database.
--
-- Idempotent: safe to re-run.
-- ============================================================================

-- ── Columns ─────────────────────────────────────────────────────────────────

ALTER TABLE public.alerts
  -- The rung that OWNS this alert now. 'UNIT' -> 'WARD' -> 'LGA' -> 'HQ'.
  ADD COLUMN IF NOT EXISTS assigned_tier TEXT,
  -- When the current owner took it. The timeout is measured from here, not
  -- from created_at: an alert escalated to the WARD gets the WARD's full
  -- window, not whatever is left of the PU's.
  ADD COLUMN IF NOT EXISTS tier_assigned_at TIMESTAMPTZ,
  -- Set when a responder at the owning tier acknowledges. An acknowledged
  -- alert stops climbing: somebody has it.
  ADD COLUMN IF NOT EXISTS acknowledged_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS acknowledged_by UUID;

-- New alerts land at the polling unit, and the clock starts.
ALTER TABLE public.alerts
  ALTER COLUMN assigned_tier SET DEFAULT 'UNIT';

-- Existing rows: anything still open and unowned belongs to the PU.
UPDATE public.alerts
   SET assigned_tier = 'UNIT'
 WHERE assigned_tier IS NULL
   AND status NOT IN ('RESOLVED', 'CANCELLED');

-- Backfill the clock from the row's own age, so a migration does not make
-- every historical alert look as though it just arrived — and then instantly
-- escalate the lot to HQ the first time the job runs.
UPDATE public.alerts
   SET tier_assigned_at = COALESCE(updated_at, created_at, NOW())
 WHERE tier_assigned_at IS NULL;

ALTER TABLE public.alerts
  ALTER COLUMN tier_assigned_at SET DEFAULT NOW();

-- The job scans on these two.
CREATE INDEX IF NOT EXISTS alerts_chain_idx
  ON public.alerts (assigned_tier, tier_assigned_at)
  WHERE acknowledged_at IS NULL;

-- ── The ladder, as data ─────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.next_tier(current_tier TEXT)
RETURNS TEXT
LANGUAGE sql IMMUTABLE
SET search_path = public, pg_temp
AS $$
  SELECT CASE upper(coalesce(current_tier, 'UNIT'))
           WHEN 'UNIT' THEN 'WARD'
           WHEN 'WARD' THEN 'LGA'
           WHEN 'LGA'  THEN 'HQ'
           -- HQ is the top. NULL means "nowhere left to go", which is what
           -- stops an alert cycling round the chain forever.
           ELSE NULL
         END;
$$;

COMMENT ON FUNCTION public.next_tier(TEXT) IS
  'The rung above this one. NULL at HQ: the chain terminates rather than loops.';

-- ── The timeout for a tier, from app_config ─────────────────────────────────

CREATE OR REPLACE FUNCTION public.tier_timeout_minutes(tier TEXT)
RETURNS INTEGER
LANGUAGE plpgsql STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  key_name TEXT;
  raw      TEXT;
  parsed   INTEGER;
BEGIN
  key_name := CASE upper(coalesce(tier, ''))
                WHEN 'UNIT' THEN 'escalation_timeout_pu'
                WHEN 'WARD' THEN 'escalation_timeout_ward'
                WHEN 'LGA'  THEN 'escalation_timeout_lga'
                ELSE NULL
              END;
  IF key_name IS NULL THEN
    RETURN NULL;  -- HQ, or an unknown tier: no timeout applies.
  END IF;

  SELECT value INTO raw FROM public.app_config WHERE key = key_name;

  -- A missing or malformed setting must not silently mean "escalate
  -- immediately" (a timeout of 0) or "never escalate" (NULL treated as
  -- infinite). Both are dangerous defaults for an emergency queue, so fall
  -- back to the seeded values.
  BEGIN
    parsed := raw::INTEGER;
  EXCEPTION WHEN others THEN
    parsed := NULL;
  END;

  IF parsed IS NULL OR parsed <= 0 THEN
    parsed := CASE upper(tier)
                WHEN 'UNIT' THEN 2
                WHEN 'WARD' THEN 5
                WHEN 'LGA'  THEN 10
              END;
  END IF;

  RETURN parsed;
END;
$$;

-- ── The job ─────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.escalate_overdue_alerts()
RETURNS TABLE (alert_id UUID, from_tier TEXT, to_tier TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN QUERY
  WITH overdue AS (
    SELECT a.id,
           upper(a.assigned_tier)               AS current_tier,
           public.next_tier(a.assigned_tier)    AS target_tier
      FROM public.alerts a
     WHERE a.status NOT IN ('RESOLVED', 'CANCELLED')
       -- Acknowledged means somebody at this tier has it. Climbing past a
       -- responder who is already on it is how you get two units dispatched
       -- to the same incident and none to the next one.
       AND a.acknowledged_at IS NULL
       AND public.next_tier(a.assigned_tier) IS NOT NULL
       AND a.tier_assigned_at IS NOT NULL
       AND a.tier_assigned_at <
             NOW() - make_interval(
               mins => public.tier_timeout_minutes(a.assigned_tier)
             )
     FOR UPDATE OF a SKIP LOCKED
  )
  UPDATE public.alerts a
     SET assigned_tier    = o.target_tier,
         tier_assigned_at = NOW(),
         status           = 'ESCALATED',
         updated_at       = NOW(),
         -- Append, never replace: the chain of custody is the point. Written
         -- in the same shape the apps write, so one reader handles both.
         escalation_log = COALESCE(a.escalation_log, '[]'::jsonb) || jsonb_build_object(
           'from_tier',  o.current_tier,
           'to_tier',    o.target_tier,
           'reason',     'TIMEOUT',
           'by',         'SYSTEM',
           'at',         to_char(NOW() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
         )
    FROM overdue o
   WHERE a.id = o.id
  RETURNING a.id, o.current_tier, o.target_tier;
END;
$$;

COMMENT ON FUNCTION public.escalate_overdue_alerts() IS
  'Climbs unacknowledged alerts one rung when their tier has held them longer '
  'than app_config allows. Returns what it moved. Idempotent per run.';

-- Only the service role runs this. It is SECURITY DEFINER and reassigns
-- ownership of emergencies; nothing signed in from a phone should call it.
REVOKE ALL ON FUNCTION public.escalate_overdue_alerts() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.escalate_overdue_alerts() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.escalate_overdue_alerts() TO service_role;

-- ── Scheduling ──────────────────────────────────────────────────────────────
--
-- pg_cron is available on Supabase but is not present in a bare PostgreSQL, so
-- this is conditional: the harness proves the FUNCTION, and the schedule is
-- attached wherever the extension exists.
DO $sched$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'pg_cron') THEN
    CREATE EXTENSION IF NOT EXISTS pg_cron;

    -- Every minute. The shortest configured timeout is two minutes, so a
    -- minute of granularity costs at most a minute of delay.
    PERFORM cron.unschedule('rainbow-escalate-overdue')
      WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'rainbow-escalate-overdue');

    PERFORM cron.schedule(
      'rainbow-escalate-overdue',
      '* * * * *',
      $job$SELECT public.escalate_overdue_alerts();$job$
    );
    RAISE NOTICE 'escalation job scheduled every minute';
  ELSE
    RAISE NOTICE 'pg_cron unavailable: escalate_overdue_alerts() must be driven externally';
  END IF;
END
$sched$;
