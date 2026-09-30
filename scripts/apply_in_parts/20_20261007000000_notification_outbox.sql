--
-- ONE PART OF scripts/apply_all_migrations.sql — generated, do not edit by hand.
--   Regenerate with: python3 scripts/build_apply_in_parts.py
--
-- Run the parts IN NUMBER ORDER, each on its own, letting each finish before the
-- next. The order is not cosmetic: part 02 drops the permissive policy set BY
-- NAME, and several later parts assume columns an earlier part adds.
--
-- Expect `NOTICE: skipping ...` lines — they are the guards that let these files
-- run against a database that does not have a given table yet.
--
-- ONE PART BEHAVES DIFFERENTLY IF YOU RUN IT TWICE. Part 02, the RLS policy
-- migration, is ATOMIC rather than idempotent: it drops the old policy set by
-- name and creates a new one inside its own BEGIN/COMMIT. Run it a second time
-- and it says
--
--     ERROR: policy "profiles_select_self_or_staff" for table "profiles"
--            already exists
--
-- and rolls itself back. That message means THE POLICIES ARE ALREADY IN PLACE.
-- Nothing is half-applied, and part 15 will still report every row PASS.
--
-- Part 15 is the readout: it writes nothing and tells you the truth about the
-- whole set. It needs parts 01-14 applied first, because it checks work they do;
-- run it early and it says so plainly rather than failing on a missing function.
--
-- The LAST part writes nothing. It returns one row per thing that had to be
-- true, and every one of them must read PASS.
--
-- If you can paste the whole of apply_all_migrations.sql in one go, do that
-- instead: one paste cannot be run out of order or stopped halfway by accident.
--

-- ----------------------------------------------------------------------------
-- 20261007000000_notification_outbox.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261007000000_notification_outbox.sql'; END $apply$;

-- The automatic escalation moved the incident and told nobody.
--
-- ## The gap
--
-- `escalate_overdue_alerts()` runs every minute under pg_cron and climbs any
-- unacknowledged incident one rung when its tier has held it too long. It is in
-- the right place — the app only runs when a citizen has it open and the
-- console only when a dispatcher does, so a timeout that must fire at 02:00
-- cannot live in either.
--
-- But it only ever UPDATED the row. Every notification in this system is sent
-- from `hq-dashboard-next/src/lib/alert-actions.ts`, which runs when a human
-- presses ESCALATE or DISPATCH. So an incident that climbed to the LGA at 02:00
-- because nobody at the ward answered was moved into another tier's queue in
-- complete silence, and was only seen if somebody happened to have the console
-- open. The whole point of the timeout is the case where nobody is watching.
--
-- ## Why an outbox, and not an HTTP call from the function
--
-- `pg_net` can post from inside PostgreSQL, and it is the wrong tool here. An
-- HTTP call made inside a transaction cannot be rolled back: if the escalation
-- is rolled back after the call, the notification has already gone, and if the
-- call fails there is nowhere for the failure to live. Delivery would be
-- invisible and unretryable.
--
-- A row is transactional. The escalation and its notification are written in
-- ONE statement, so it is not possible to escalate an incident without queueing
-- the notice — which is the property actually worth having. A worker then
-- drains the queue and calls the notification endpoints that already exist and
-- are already tested, and its failures are rows anyone can look at.

CREATE TABLE IF NOT EXISTS public.notification_outbox (
  id              BIGSERIAL PRIMARY KEY,
  alert_id        UUID REFERENCES public.alerts(id) ON DELETE CASCADE,
  kind            TEXT NOT NULL,
  payload         JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- Set when delivery succeeded. A delivered row is never claimed again.
  delivered_at    TIMESTAMPTZ,
  attempts        INTEGER NOT NULL DEFAULT 0,
  last_error      TEXT,
  -- When this row may next be attempted. Moved forward on failure so one
  -- unreachable recipient cannot spin the worker.
  next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.notification_outbox IS
  'Notifications owed. Written in the same transaction as the thing that owes '
  'them, so a change cannot happen without its notice being queued.';

-- The drain query: undelivered, due, oldest first.
CREATE INDEX IF NOT EXISTS notification_outbox_pending_idx
  ON public.notification_outbox (next_attempt_at)
  WHERE delivered_at IS NULL;

-- ── Nobody signed in from a phone may see this ──────────────────────────────
--
-- It names officers and incidents, and it is not operational information for
-- anyone in either app: it exists between the database and the worker.

ALTER TABLE public.notification_outbox ENABLE ROW LEVEL SECURITY;

-- No policy for `authenticated` at all. With RLS enabled and no policy, every
-- row is invisible and unwritable to them — the grants below are revoked too,
-- so this is belt and braces on purpose.
REVOKE ALL ON public.notification_outbox FROM anon, authenticated;
GRANT ALL ON public.notification_outbox TO service_role;
GRANT USAGE, SELECT ON SEQUENCE public.notification_outbox_id_seq TO service_role;

-- ── Claiming work ───────────────────────────────────────────────────────────
--
-- SKIP LOCKED so two workers running at once take different rows rather than
-- both taking the same one and sending everything twice. The same reasoning as
-- FOR UPDATE SKIP LOCKED in escalate_overdue_alerts(), and as the single-flight
-- guard on the app's offline queue flush: any queue drained from more than one
-- place needs this, or a burst is delivered twice.

CREATE OR REPLACE FUNCTION public.claim_notifications(p_limit INTEGER DEFAULT 20)
RETURNS SETOF public.notification_outbox
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN QUERY
  WITH due AS (
    SELECT o.id
      FROM public.notification_outbox o
     WHERE o.delivered_at IS NULL
       AND o.next_attempt_at <= NOW()
     ORDER BY o.next_attempt_at
     LIMIT GREATEST(COALESCE(p_limit, 20), 1)
     FOR UPDATE SKIP LOCKED
  )
  UPDATE public.notification_outbox o
     SET attempts = o.attempts + 1,
         -- Held off for a minute the moment it is claimed, so a worker that
         -- dies mid-send does not leave the row to be taken again immediately
         -- by the next tick. It returns to the queue on its own.
         next_attempt_at = NOW() + INTERVAL '1 minute'
    FROM due
   WHERE o.id = due.id
  RETURNING o.*;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_notifications(INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.claim_notifications(INTEGER) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_notifications(INTEGER) TO service_role;

CREATE OR REPLACE FUNCTION public.mark_notification_sent(p_id BIGINT)
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  UPDATE public.notification_outbox
     SET delivered_at = NOW(), last_error = NULL
   WHERE id = p_id;
$$;

CREATE OR REPLACE FUNCTION public.mark_notification_failed(p_id BIGINT, p_error TEXT)
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  UPDATE public.notification_outbox
     SET last_error = left(COALESCE(p_error, 'unknown'), 500),
         -- Back off with the attempt count, capped. An unreachable recipient
         -- must not hold the worker at one row for ever, and must not be
         -- retried for ever either.
         next_attempt_at = NOW() + make_interval(
           mins => LEAST(GREATEST(attempts, 1) * 2, 60))
   WHERE id = p_id;
$$;

REVOKE ALL ON FUNCTION public.mark_notification_sent(BIGINT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.mark_notification_failed(BIGINT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mark_notification_sent(BIGINT) TO service_role;
GRANT EXECUTE ON FUNCTION public.mark_notification_failed(BIGINT, TEXT) TO service_role;

-- ── The escalation now owes a notification ──────────────────────────────────
--
-- Same body as 20260928000000_command_chain_escalation.sql, with the outbox
-- insert in the SAME statement. Written as one CTE chain rather than a second
-- statement so there is no arrangement of failures in which the tier moves and
-- the notice does not.

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
           upper(a.assigned_tier)            AS current_tier,
           public.next_tier(a.assigned_tier) AS target_tier
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
  ),
  moved AS (
    UPDATE public.alerts a
       SET assigned_tier    = o.target_tier,
           tier_assigned_at = NOW(),
           status           = 'ESCALATED',
           updated_at       = NOW(),
           escalation_log = COALESCE(a.escalation_log, '[]'::jsonb) || jsonb_build_object(
             'from_tier',  o.current_tier,
             'to_tier',    o.target_tier,
             'reason',     'TIMEOUT',
             'by',         'SYSTEM',
             'at',         to_char(NOW() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
           )
      FROM overdue o
     WHERE a.id = o.id
    RETURNING a.id, o.current_tier, o.target_tier, a.geo_lga, a.geo_ward, a.geo_pu, a.severity
  ),
  queued AS (
    INSERT INTO public.notification_outbox (alert_id, kind, payload)
    SELECT m.id,
           'TIER_ESCALATION',
           jsonb_build_object(
             'alert_id',  m.id,
             'from_tier', m.current_tier,
             'to_tier',   m.target_tier,
             'geo_lga',   m.geo_lga,
             'geo_ward',  m.geo_ward,
             'geo_pu',    m.geo_pu,
             'severity',  m.severity,
             'reason',    'TIMEOUT'
           )
      FROM moved m
    -- `RETURNING alert_id` collides with this function's own OUT parameter of
    -- that name and is rejected as ambiguous. Nothing reads this CTE's output;
    -- it exists so the INSERT runs inside the same statement as the UPDATE.
    RETURNING id
  )
  SELECT m.id, m.current_tier, m.target_tier FROM moved m;
END;
$$;

COMMENT ON FUNCTION public.escalate_overdue_alerts() IS
  'Climbs unacknowledged alerts one rung when their tier has held them longer '
  'than app_config allows, and queues the notification in the same statement. '
  'Returns what it moved. Idempotent per run.';

REVOKE ALL ON FUNCTION public.escalate_overdue_alerts() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.escalate_overdue_alerts() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.escalate_overdue_alerts() TO service_role;

-- ── Is the automation actually running? ─────────────────────────────────────
--
-- The scheduling block in the escalation migration is conditional: without
-- pg_cron it raises a NOTICE and schedules NOTHING. So the entire automation
-- can be absent while every migration reports success — the worst way for it
-- to fail, because there is nothing to see.

CREATE OR REPLACE FUNCTION public.escalation_automation_status()
RETURNS TABLE (scheduled BOOLEAN, detail TEXT)
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RETURN QUERY SELECT false,
      'pg_cron is not installed: escalate_overdue_alerts() must be driven externally'::TEXT;
    RETURN;
  END IF;

  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'rainbow-escalate-overdue') THEN
    RETURN QUERY SELECT true, 'rainbow-escalate-overdue is scheduled'::TEXT;
  ELSE
    RETURN QUERY SELECT false,
      'pg_cron is installed but rainbow-escalate-overdue is NOT scheduled'::TEXT;
  END IF;
END;
$$;

COMMENT ON FUNCTION public.escalation_automation_status() IS
  'Whether the timeout escalation is actually scheduled. The scheduling block '
  'is conditional on pg_cron, so the automation can be silently absent.';

GRANT EXECUTE ON FUNCTION public.escalation_automation_status() TO service_role;

