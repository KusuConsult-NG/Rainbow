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
-- 20261002000000_sim_channel_events.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261002000000_sim_channel_events.sql'; END $apply$;

-- ============================================================================
-- OPERATION RAINBOW — WHEN A HANDSET'S SMS CHANNEL DIES
--
-- WHAT THIS IS ABOUT
--
-- In this system the phone number is the identity. It is what the account was
-- created with, what `profiles.phone` holds, what HQ rings back, and what the
-- encrypted SMS fallback rides on. When the SIM leaves a handset:
--
--   * the offline alert channel stops working and nothing else notices;
--   * a sign-in or re-entry code cannot arrive, so the holder will be locked
--     out the next time they come back to the app;
--   * a stolen handset usually gets a new SIM within the hour.
--
-- So HQ is told. What HQ is told is that A CHANNEL IS DOWN.
--
-- WHAT THIS IS DELIBERATELY NOT
--
-- It is not a movement log and must never become one. There is no location
-- column here and none may be added: this app is used in a conflict zone by
-- people who report things they can be harmed for reporting, and a government
-- console that quietly accumulated their SIM and location history would be a
-- reason not to install it — which costs more lives than it saves.
--
-- The holder is told on the handset, in one line, each time a row is written
-- here. Reporting to a state console without telling the person is
-- surveillance; reporting it and saying so is operations.
--
-- WHAT IT CAN AND CANNOT SEE
--
-- Android reports SIM present/absent and the NETWORK (MCC+MNC) with no
-- permission at all. The values that identify a particular CARD — the ICCID
-- and the IMSI — have required READ_PRIVILEGED_PHONE_STATE since Android 10,
-- which no ordinary app can hold. So one MTN SIM swapped for another MTN SIM
-- is invisible. On iOS 16+ nothing is visible at all: the carrier API is
-- deprecated and returns a placeholder. Both limits are stated in
-- lib/core/device/sim_fingerprint.dart and asserted in its tests.
--
-- Idempotent: safe to re-run.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.sim_channel_events (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,

  -- REMOVED, INSERTED, REPLACED. Never a free-text description from the
  -- handset: the words HQ reads are composed by the console from this code, so
  -- a compromised handset cannot write prose onto an operator's screen.
  change        TEXT NOT NULL CHECK (change IN ('REMOVED', 'INSERTED', 'REPLACED')),

  -- The NETWORK the handset is on now, for an operator deciding whether the
  -- registered number still reaches this person. Null when it could not be
  -- read. Not the card, not the number.
  operator_name TEXT,
  operator_code TEXT,

  -- When the handset noticed. Set by the handset, so it survives a report that
  -- is queued while offline and delivered later.
  noticed_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Cleared by an operator who has dealt with it.
  acknowledged_at TIMESTAMPTZ,
  acknowledged_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS sim_channel_events_open_idx
  ON public.sim_channel_events (created_at DESC)
  WHERE acknowledged_at IS NULL;

CREATE INDEX IF NOT EXISTS sim_channel_events_user_idx
  ON public.sim_channel_events (user_id, created_at DESC);

COMMENT ON TABLE public.sim_channel_events IS
  'A handset reporting that its SMS channel changed: SIM removed, inserted or '
  'replaced. About the channel, never about a location. The holder is told on '
  'the handset each time a row is written.';

-- ── Row level security ──────────────────────────────────────────────────────

ALTER TABLE public.sim_channel_events ENABLE ROW LEVEL SECURITY;

-- A handset writes its OWN events and nobody else's. `user_id = auth.uid()` is
-- the whole check: without it, any signed-in account could manufacture a "SIM
-- REMOVED" for any other person, which is a cheap way to get somebody's
-- account looked at by the state.
DROP POLICY IF EXISTS "sim_events_insert_self" ON public.sim_channel_events;
CREATE POLICY "sim_events_insert_self" ON public.sim_channel_events
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

-- The holder can see what was reported about their own handset. Somebody who
-- cannot see what was said about them cannot challenge it.
DROP POLICY IF EXISTS "sim_events_select_self_or_command" ON public.sim_channel_events;
CREATE POLICY "sim_events_select_self_or_command" ON public.sim_channel_events
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_command());

-- Only command acknowledges, and only the acknowledgement fields move —
-- nothing here may be rewritten after the fact.
DROP POLICY IF EXISTS "sim_events_ack_command" ON public.sim_channel_events;
CREATE POLICY "sim_events_ack_command" ON public.sim_channel_events
  FOR UPDATE TO authenticated
  USING (public.is_command())
  WITH CHECK (public.is_command());

-- NOT `is_staff()`. A polling-unit officer in Wase, and every agency liaison,
-- are staff; neither has a reason to see which citizens changed SIM. This is
-- the same mistake the telemetry migration was written to undo.

-- ── Retention ───────────────────────────────────────────────────────────────
--
-- These rows answer "is this handset reachable by SMS today". A year-old one
-- answers nothing and is only a history of somebody's phone. Ninety days, and
-- acknowledged ones go sooner.

CREATE OR REPLACE FUNCTION public.purge_stale_sim_events()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  DELETE FROM public.sim_channel_events
   WHERE created_at < NOW() - INTERVAL '90 days'
      OR (acknowledged_at IS NOT NULL
          AND acknowledged_at < NOW() - INTERVAL '30 days');
$$;

REVOKE EXECUTE ON FUNCTION public.purge_stale_sim_events() FROM anon;
REVOKE EXECUTE ON FUNCTION public.purge_stale_sim_events() FROM authenticated;

DO $cron$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('purge-stale-sim-events')
      WHERE EXISTS (
        SELECT 1 FROM cron.job WHERE jobname = 'purge-stale-sim-events'
      );
    PERFORM cron.schedule(
      'purge-stale-sim-events',
      '30 3 * * *',
      $job$SELECT public.purge_stale_sim_events();$job$
    );
  ELSE
    RAISE NOTICE
      'pg_cron is not installed; run public.purge_stale_sim_events() on a schedule yourself';
  END IF;
END $cron$;

-- ── Realtime ────────────────────────────────────────────────────────────────
--
-- The console badges this live. A subscription to a table outside the
-- publication does not error; it simply never fires, which is how the agency
-- portal's badge came to refresh only on reload.

DO $realtime$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    RAISE NOTICE 'no supabase_realtime publication in this database; nothing to do';
    RETURN;
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_publication_tables
     WHERE pubname = 'supabase_realtime'
       AND schemaname = 'public'
       AND tablename = 'sim_channel_events'
  ) THEN
    RETURN;
  END IF;
  ALTER PUBLICATION supabase_realtime ADD TABLE public.sim_channel_events;
END $realtime$;

