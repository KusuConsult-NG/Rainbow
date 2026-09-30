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
-- 20260929000000_telemetry_is_not_a_standing_feed.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20260929000000_telemetry_is_not_a_standing_feed.sql'; END $apply$;

-- ============================================================================
-- OPERATION RAINBOW — LOCATION IS BORROWED, NOT KEPT
--
-- Three things were true of `telemetry` at once, and together they made this
-- table a standing surveillance feed on private citizens rather than a live
-- picture of an emergency in progress.
--
-- 1. EVERY STAFF ACCOUNT COULD READ EVERY ROW.
--
--    `telemetry_select_self_or_staff` was `user_id = auth.uid() OR
--    is_staff()`. `is_staff()` is true for a polling-unit officer in Wase as
--    readily as for the HQ commander, and it is not scoped to an incident, a
--    jurisdiction, or a shift. So the live position of any citizen who had
--    ever pressed the panic button was readable by every operational account
--    in the state, for as long as the row existed.
--
-- 2. NOTHING DELETED ANYTHING.
--
--    One row per user, updated in place, kept forever. The last known position
--    of every person who has ever used the panic button sits in this table
--    indefinitely — long after the emergency, and long after any purpose that
--    could justify holding it.
--
-- 3. THE ROW OUTLIVED THE EMERGENCY.
--
--    Nothing linked a track to the incident it was for, and nothing stopped
--    writing when the incident closed.
--
-- The app side of (3) is fixed in `background_tracking_service.dart`, which
-- now carries `alert_id`, honours an expiry, stops when the alert is resolved
-- and stops on sign-out. This file fixes the database side, because a client
-- that stops asking is not the same as a server that stops answering — and it
-- is the server that decides who may look.
--
-- WHAT THIS DELIBERATELY DOES NOT DO
--
-- It does not restrict a responder's own operational visibility, and it does
-- not touch the duress path. A duress PIN keeps a track running on purpose:
-- the person may still be in danger, and HQ must be able to follow. That stays
-- true. What changes is that the track now ends, and that only people with a
-- reason to look can look while it runs.
--
-- Idempotent: safe to re-run.
-- ============================================================================

-- ── Who may read a position ─────────────────────────────────────────────────

DROP POLICY IF EXISTS "telemetry_select_self_or_staff" ON public.telemetry;
DROP POLICY IF EXISTS "telemetry_select_self_or_responding_staff" ON public.telemetry;

-- A staff member sees another STAFF member's position freely: that is the
-- movement board, it is what `MOVEMENT` shows, and officers on duty being
-- visible to each other is the point of it.
--
-- A CITIZEN's position is visible only while they have an emergency open — and
-- then to any staff member, deliberately, because whoever is nearest may not
-- be whoever it was assigned to. Once the incident is resolved or cancelled,
-- the row stops being readable by anyone but its owner.
DROP POLICY IF EXISTS "telemetry_select_self_or_responding_staff" ON public.telemetry;
CREATE POLICY "telemetry_select_self_or_responding_staff" ON public.telemetry
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR (
      public.is_staff()
      AND (
        -- the subject is themselves on duty
        EXISTS (
          SELECT 1 FROM public.profiles p
           WHERE p.id = telemetry.user_id
             AND p.role NOT IN ('CITIZEN', 'USER')
        )
        -- or the subject has a live emergency right now
        OR EXISTS (
          SELECT 1 FROM public.alerts a
           WHERE a.reported_by = telemetry.user_id
             AND a.status NOT IN ('RESOLVED', 'CANCELLED')
        )
      )
    )
  );

COMMENT ON POLICY "telemetry_select_self_or_responding_staff" ON public.telemetry IS
  'Own position always; a colleague''s position if you are staff; a citizen''s '
  'position only while they have an emergency open.';

-- ── Nothing is kept forever ─────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.purge_stale_telemetry()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  removed INTEGER;
BEGIN
  -- A position older than a day is of no operational use to anybody: the
  -- emergency is over, and the person has moved. Keeping it is a liability
  -- with no matching benefit.
  --
  -- A row belonging to a CURRENTLY OPEN alert is never purged on age, however
  -- old, because an unresolved emergency is exactly the case where the last
  -- known position still matters.
  DELETE FROM public.telemetry t
   WHERE t.updated_at < NOW() - INTERVAL '24 hours'
     AND NOT EXISTS (
       SELECT 1 FROM public.alerts a
        WHERE a.reported_by = t.user_id
          AND a.status NOT IN ('RESOLVED', 'CANCELLED')
     );
  GET DIAGNOSTICS removed = ROW_COUNT;
  RETURN removed;
END;
$$;

COMMENT ON FUNCTION public.purge_stale_telemetry() IS
  'Deletes positions older than 24h that do not belong to an open emergency.';

REVOKE ALL ON FUNCTION public.purge_stale_telemetry() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.purge_stale_telemetry() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.purge_stale_telemetry() TO service_role;

-- Same conditional shape as the escalation job: pg_cron exists on Supabase and
-- not in a bare PostgreSQL, so the harness proves the FUNCTION and the schedule
-- attaches wherever the extension is available.
DO $sched$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'pg_cron') THEN
    CREATE EXTENSION IF NOT EXISTS pg_cron;
    PERFORM cron.unschedule('rainbow-purge-telemetry')
      WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'rainbow-purge-telemetry');
    PERFORM cron.schedule(
      'rainbow-purge-telemetry',
      '17 * * * *',
      $job$SELECT public.purge_stale_telemetry();$job$
    );
    RAISE NOTICE 'telemetry purge scheduled hourly';
  ELSE
    RAISE NOTICE 'pg_cron unavailable: purge_stale_telemetry() must be driven externally';
  END IF;
END
$sched$;

-- ============================================================================
-- CHAT: YOU MAY ONLY WRITE INTO A CONVERSATION YOU ARE PART OF
--
-- `chat_select_participant_or_staff` is careful: you read a thread if you sent
-- the message, or you are staff, or you are the alert's reporter or assignee.
--
-- `chat_insert_as_self` checked one thing — `sender_id = auth.uid()` — which
-- says you cannot forge somebody else's name. It says nothing about WHICH
-- conversation you may write into. So any authenticated account could post
-- into any incident's tactical channel, including incidents they cannot read,
-- given an alert id. On a channel that responders act on, injecting messages
-- into somebody else's emergency is the whole attack.
--
-- The asymmetry is the bug: reading was scoped to participation and writing
-- was not. Now both are.
-- ============================================================================

DROP POLICY IF EXISTS "chat_insert_as_self" ON public.chat_messages;
DROP POLICY IF EXISTS "chat_insert_participant" ON public.chat_messages;

CREATE POLICY "chat_insert_participant" ON public.chat_messages
  FOR INSERT TO authenticated
  WITH CHECK (
    sender_id = auth.uid()
    AND (
      public.is_staff()
      OR EXISTS (
        SELECT 1 FROM public.alerts a
         WHERE a.id = chat_messages.alert_id
           AND (a.reported_by = auth.uid() OR a.assigned_to = auth.uid())
      )
    )
  );

COMMENT ON POLICY "chat_insert_participant" ON public.chat_messages IS
  'Write as yourself, and only into a thread you are a participant in. Mirrors '
  'chat_select_participant_or_staff, which was already scoped this way.';

