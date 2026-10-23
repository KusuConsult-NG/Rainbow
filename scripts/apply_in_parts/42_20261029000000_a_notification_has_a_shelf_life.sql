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
-- 20261029000000_a_notification_has_a_shelf_life.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261029000000_a_notification_has_a_shelf_life.sql'; END $apply$;

-- Four hundred and twelve emergency notices, the oldest from July, all due now.
--
-- ## What the live project looks like
--
--     outbox_rows 412 | outbox_pending 412 | outbox_erroring 0 | max attempts 0
--
-- Four hundred and twelve queued notifications, none ever attempted, going back
-- three months. The drain worker was never scheduled, so the queue simply
-- filled. That part is a deployment step, and it is the operator's to take.
--
-- The part that is this file's is what happens when they take it.
--
-- `claim_notifications` takes the oldest undelivered rows whose
-- `next_attempt_at` has passed, twenty at a time, and there is no upper bound on
-- age anywhere — not in the function, not in either of the two drainers. So the
-- first thing a newly scheduled worker does is deliver July. Every officer whose
-- geography matched an incident that timed out in July gets
--
--     INCIDENT NOW AT LGA
--     Incident #a3f2b118 in JOS SOUTH was not acknowledged in time and has come
--     up to LGA. Open the console to take it.
--
-- for incidents that are closed, about positions people are no longer at, at
-- twenty a minute for twenty-one minutes. The notices are indistinguishable from
-- live ones, because that is what the text is for.
--
-- ## Why this is the queue's problem and not the worker's
--
-- A notification about an emergency is not like a notification about an invoice.
-- It is an instruction to go somewhere, and it decays: a tier escalation says
-- "nobody answered, it is yours now", which is false ten minutes later and
-- dangerous three months later. There is no arrangement of retries under which
-- delivering it is better than dropping it.
--
-- So the rule belongs where the work is handed out, not in each worker. There
-- are two drainers — `supabase/functions/drain-outbox/index.ts` and the
-- console's `/api/notify/drain` — and a rule written twice drifts; this project
-- has already had that exact bug, in the OneSignal auth scheme, where the two
-- halves disagreed and at most one of them ever authenticated. `escalation_push
-- _targets()` was moved into SQL for the same reason. One claim function, one
-- shelf life, and any worker anybody writes next inherits it.
--
-- ## An expired row is not a delivered row
--
-- The obvious shortcut is to set `delivered_at` and move on. That writes a lie
-- into the one table whose honesty this mechanism exists for: the whole reason
-- the outbox was built was that the old worker marked escalations delivered with
-- nobody told. `expired_at` with a reason is the truthful record, and it keeps
-- the "did anybody get told?" question answerable afterwards.

-- ── The two terminal states ─────────────────────────────────────────────────

ALTER TABLE public.notification_outbox
  ADD COLUMN IF NOT EXISTS expired_at TIMESTAMPTZ;
ALTER TABLE public.notification_outbox
  ADD COLUMN IF NOT EXISTS expiry_reason TEXT;

COMMENT ON COLUMN public.notification_outbox.expired_at IS
  'Set when this notice was dropped undelivered because its moment had passed. '
  'Distinct from delivered_at on purpose: nobody was told, and the table has to '
  'say so.';
COMMENT ON COLUMN public.notification_outbox.expiry_reason IS
  'Why it was dropped. Not last_error, which is a delivery failure and is '
  'retried; an expiry is final.';

-- The drain query reads undelivered AND unexpired. The old partial index was
-- `WHERE delivered_at IS NULL`, which after this change covers every retired row
-- for ever — the backlog this migration exists to retire would stay in the hot
-- path of the one query that runs every minute.
DROP INDEX IF EXISTS public.notification_outbox_pending_idx;
CREATE INDEX IF NOT EXISTS notification_outbox_pending_idx
  ON public.notification_outbox (next_attempt_at)
  WHERE delivered_at IS NULL AND expired_at IS NULL;

-- ── How long a notice is worth sending ──────────────────────────────────────
--
-- Same shape as `tier_timeout_minutes()`, and for the same reason: a missing or
-- malformed setting must not mean something dangerous. Here the dangerous
-- readings are a shelf life of 0 (drop everything, the queue silently delivers
-- nothing) and NULL read as infinite (the behaviour this file is fixing). Both
-- fall back to the default.
--
-- 60 minutes, because the shortest escalation timeout in `app_config` is
-- measured in minutes and the longest is well under an hour: a notice still
-- undelivered an hour after it was queued has been overtaken by the incident it
-- describes.

INSERT INTO public.app_config (key, value)
VALUES ('notification_shelf_life_minutes', '60')
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.notification_shelf_life_minutes()
RETURNS INTEGER
LANGUAGE plpgsql STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  raw    TEXT;
  parsed INTEGER;
BEGIN
  SELECT value INTO raw FROM public.app_config
   WHERE key = 'notification_shelf_life_minutes';

  BEGIN
    parsed := raw::INTEGER;
  EXCEPTION WHEN others THEN
    RETURN 60;
  END;

  IF parsed IS NULL OR parsed <= 0 THEN
    RETURN 60;
  END IF;
  RETURN parsed;
END;
$$;

COMMENT ON FUNCTION public.notification_shelf_life_minutes() IS
  'Minutes a queued notification is still worth delivering. Refuses 0, NULL '
  'and anything unparseable, because each of those readings silently empties '
  'or never empties the queue.';

-- ── Which rows have had their moment ────────────────────────────────────────
--
-- Two conditions, and the second is the one that matters even with the worker
-- running every minute:
--
--   age   queued longer ago than the shelf life.
--   over  the incident it is about is closed. A dispatcher resolving an alert
--         ten seconds after the tier timed out leaves a queued notice that
--         sends a unit to a finished incident. That race exists at any drain
--         frequency, and no retry policy fixes it.
--
-- Rows with no `alert_id` (a plain SMS, PUSH or WEBHOOK) are judged on age
-- alone; there is no incident to ask about.

CREATE OR REPLACE FUNCTION public.notification_is_stale(
  p_row public.notification_outbox)
RETURNS TEXT
LANGUAGE sql STABLE
SET search_path = public, pg_temp
AS $$
  SELECT CASE
    WHEN p_row.created_at <
           NOW() - make_interval(mins => public.notification_shelf_life_minutes())
      THEN format('queued %s ago, past the %s minute shelf life',
                  justify_interval(date_trunc('minute', NOW() - p_row.created_at)),
                  public.notification_shelf_life_minutes())
    WHEN p_row.alert_id IS NOT NULL AND EXISTS (
           SELECT 1 FROM public.alerts a
            WHERE a.id = p_row.alert_id
              AND a.status IN ('RESOLVED', 'CANCELLED'))
      THEN 'the incident it is about is closed'
    ELSE NULL
  END;
$$;

COMMENT ON FUNCTION public.notification_is_stale(public.notification_outbox) IS
  'Why this notice is no longer worth sending, or NULL if it still is. One '
  'definition, so the claim path and the operator sweep cannot disagree.';

-- ── Retiring them ───────────────────────────────────────────────────────────
--
-- Callable on its own, because an operator about to schedule the drainer for the
-- first time should be able to see what the queue is holding and retire it
-- deliberately, with a count in front of them, rather than discover it as
-- traffic. It returns what it retired and why.

CREATE OR REPLACE FUNCTION public.expire_stale_notifications()
RETURNS TABLE (kind TEXT, reason TEXT, retired BIGINT)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH stale AS (
    SELECT o.id, public.notification_is_stale(o) AS why
      FROM public.notification_outbox o
     WHERE o.delivered_at IS NULL
       AND o.expired_at IS NULL
  ),
  retired AS (
    UPDATE public.notification_outbox o
       SET expired_at    = NOW(),
           expiry_reason = s.why
      FROM stale s
     WHERE o.id = s.id AND s.why IS NOT NULL
    RETURNING o.kind, o.expiry_reason
  )
  SELECT r.kind, r.expiry_reason, count(*)
    FROM retired r
   GROUP BY r.kind, r.expiry_reason
   ORDER BY count(*) DESC;
$$;

COMMENT ON FUNCTION public.expire_stale_notifications() IS
  'Retires every queued notice whose moment has passed, and reports what it '
  'retired. Run this before scheduling the drainer on a queue that has been '
  'standing: the alternative is delivering the backlog as live traffic.';

REVOKE ALL ON FUNCTION public.expire_stale_notifications() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.expire_stale_notifications() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.expire_stale_notifications() TO service_role;

-- ── And the claim path enforces it, so no worker has to ─────────────────────
--
-- Expiry runs FIRST and UNBOUNDED, before the LIMIT. Doing it inside the claim
-- CTE instead would mean the worker spends a tick per twenty stale rows: with
-- 412 standing, the first live notice would wait twenty-one minutes. An
-- emergency queue cannot have a warm-up period.
--
-- Same body as 20261007000000_notification_outbox.sql otherwise: the claim
-- increments `attempts` and holds the row off for a minute so a worker that
-- dies mid-send does not have it taken again immediately.

CREATE OR REPLACE FUNCTION public.claim_notifications(p_limit INTEGER DEFAULT 20)
RETURNS SETOF public.notification_outbox
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Not conditional on a backlog existing, and not something the caller can
  -- skip. A notice whose moment has passed must not be handed to a worker, and
  -- the worker is the wrong place to decide that: there are two of them.
  PERFORM public.expire_stale_notifications();

  RETURN QUERY
  WITH due AS (
    SELECT o.id
      FROM public.notification_outbox o
     WHERE o.delivered_at IS NULL
       AND o.expired_at IS NULL
       AND o.next_attempt_at <= NOW()
     ORDER BY o.next_attempt_at
     LIMIT GREATEST(COALESCE(p_limit, 20), 1)
     FOR UPDATE SKIP LOCKED
  )
  UPDATE public.notification_outbox o
     SET attempts = o.attempts + 1,
         next_attempt_at = NOW() + INTERVAL '1 minute'
    FROM due
   WHERE o.id = due.id
  RETURNING o.*;
END;
$$;

COMMENT ON FUNCTION public.claim_notifications(INTEGER) IS
  'Hands out notices still worth sending, oldest first, retiring the rest. The '
  'shelf life is enforced here rather than in each worker, because there are '
  'two workers and a rule written twice drifts.';

REVOKE ALL ON FUNCTION public.claim_notifications(INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.claim_notifications(INTEGER) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_notifications(INTEGER) TO service_role;

-- ── What the queue is holding, before anybody schedules anything ────────────

CREATE OR REPLACE FUNCTION public.notification_queue_status()
RETURNS TABLE (state TEXT, notices BIGINT, oldest TIMESTAMPTZ, newest TIMESTAMPTZ)
LANGUAGE sql STABLE
SET search_path = public, pg_temp
AS $$
  SELECT state, count(*), min(created_at), max(created_at)
    FROM (
      SELECT o.created_at,
             CASE
               WHEN o.delivered_at IS NOT NULL THEN 'delivered'
               WHEN o.expired_at   IS NOT NULL THEN 'retired undelivered'
               WHEN public.notification_is_stale(o) IS NOT NULL
                 THEN 'would be retired on the next claim'
               ELSE 'still worth sending'
             END AS state
        FROM public.notification_outbox o
    ) s
   GROUP BY state
   ORDER BY count(*) DESC;
$$;

COMMENT ON FUNCTION public.notification_queue_status() IS
  'The queue in four states, with the age range of each. Read this before '
  'scheduling the drainer on a queue that has been standing.';

GRANT EXECUTE ON FUNCTION public.notification_queue_status() TO service_role;

