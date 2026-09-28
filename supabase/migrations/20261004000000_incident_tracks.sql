-- ============================================================================
-- OPERATION RAINBOW — WHERE SOMEBODY WENT DURING ONE EMERGENCY
--
-- THE GAP
--
-- An SOS starts a track. `background_tracking_service.dart` reports a position
-- every few seconds, the console draws a trail, and an operator watching at the
-- time can follow the person.
--
-- Except nothing was kept. `telemetry` has `user_id` as its PRIMARY KEY and is
-- UPSERTED, so the database holds exactly one row per person: the CURRENT
-- position, overwritten each time. The trail existed only in the browser tab's
-- memory — `agentPathsRef`, capped at thirty points — so:
--
--   * refreshing the console lost the trail;
--   * a second operator opening the console mid-incident saw a dot, not a path;
--   * anybody reviewing the incident afterwards saw no movement at all, and
--     the incident replay panel replayed the alert and the chat with no
--     positions in it.
--
-- For a kidnapping — the case this system exists for — "which way did they go"
-- is the question, and the answer was being thrown away several times a minute.
--
-- HOW THIS DOES NOT UNDO 20260929000000
--
-- That migration's thesis is that location is BORROWED, NOT KEPT, and it is
-- right. What it removed was a standing feed: one row per person, no link to
-- any incident, readable by every staff account in the state, kept forever,
-- still being written after the emergency ended.
--
-- This table is the opposite of each of those:
--
--   * every row belongs to ONE incident (`alert_id` is NOT NULL). No incident,
--     no track — an officer on ordinary patrol writes nothing here.
--   * it stops when the incident does, because the app stops reporting.
--   * it is readable only by people with a part in THAT incident, through the
--     same `alert_is_ours()` the alerts policies use — so an agency liaison
--     sees the route on an incident handed to their agency and on no other.
--   * it expires. A track is deleted seven days after its incident closes.
--
-- SEVEN DAYS, AND WHY THAT NUMBER
--
-- Long enough for the after-action review that is the point of keeping it at
-- all — reviews happen days later, not hours. Short enough that this never
-- becomes a location history: at any moment the table holds the open
-- incidents and one week of closed ones, and nothing else. If somebody wants
-- longer, that is a decision to argue for explicitly, which is why it is one
-- named interval and not a scatter of conditions.
--
-- Idempotent: safe to re-run.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.incident_tracks (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  alert_id    UUID NOT NULL REFERENCES public.alerts(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  latitude    DOUBLE PRECISION NOT NULL,
  longitude   DOUBLE PRECISION NOT NULL,
  accuracy    DOUBLE PRECISION,
  speed       DOUBLE PRECISION,
  -- The handset's clock, so a point queued offline and delivered later sits in
  -- the right place on the route rather than at the moment it arrived.
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Drawing one incident's route is the only read this table has.
CREATE INDEX IF NOT EXISTS incident_tracks_route_idx
  ON public.incident_tracks (alert_id, recorded_at);

COMMENT ON TABLE public.incident_tracks IS
  'The route a person took during ONE incident. Written only while that '
  'incident is open, readable only by people with a part in it, deleted seven '
  'days after it closes. Not a standing location feed — see '
  '20260929000000_telemetry_is_not_a_standing_feed.sql.';

-- ── Row level security ──────────────────────────────────────────────────────

ALTER TABLE public.incident_tracks ENABLE ROW LEVEL SECURITY;

-- A handset writes its OWN points, for an OPEN incident it has a part in.
--
-- All three clauses matter. Without `user_id = auth.uid()` anyone could write a
-- route for anybody. Without the incident check they could attach it to any
-- incident in the state. Without the open check a closed incident could be
-- re-written days later, which is the difference between a record and a story.
DROP POLICY IF EXISTS "incident_tracks_insert_own_open" ON public.incident_tracks;
CREATE POLICY "incident_tracks_insert_own_open" ON public.incident_tracks
  FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.alerts a
       WHERE a.id = incident_tracks.alert_id
         AND a.status NOT IN ('RESOLVED', 'CANCELLED')
         AND (a.reported_by = auth.uid() OR a.assigned_to = auth.uid())
    )
  );

-- Read follows the incident, through the same function the alerts policies
-- use. So: command sees it, the person whose route it is sees it, the assignee
-- sees it, and an agency liaison sees it only on an incident escalated to
-- their agency.
DROP POLICY IF EXISTS "incident_tracks_select_with_incident" ON public.incident_tracks;
CREATE POLICY "incident_tracks_select_with_incident" ON public.incident_tracks
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.alerts a
       WHERE a.id = incident_tracks.alert_id
         AND public.alert_is_ours(a)
    )
  );

-- No UPDATE and no DELETE for anybody signed in. A route is a record of what
-- happened; an editable one is worth less than none, because it can be made to
-- say something else. Deletion is the retention job's alone.

-- ── Retention ───────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.purge_stale_incident_tracks()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  removed INTEGER;
BEGIN
  -- Seven days after the incident closed. An OPEN incident is never purged on
  -- age, however old — an unresolved emergency is exactly the case where the
  -- route still matters.
  DELETE FROM public.incident_tracks t
   USING public.alerts a
   WHERE a.id = t.alert_id
     AND a.status IN ('RESOLVED', 'CANCELLED')
     AND COALESCE(a.updated_at, a.created_at) < NOW() - INTERVAL '7 days';
  GET DIAGNOSTICS removed = ROW_COUNT;

  -- And a point whose incident has vanished entirely. The foreign key cascades
  -- on delete, so this only catches anything that slipped in before it.
  DELETE FROM public.incident_tracks t
   WHERE NOT EXISTS (SELECT 1 FROM public.alerts a WHERE a.id = t.alert_id);

  RETURN removed;
END;
$$;

COMMENT ON FUNCTION public.purge_stale_incident_tracks() IS
  'Deletes the routes of incidents that closed more than seven days ago.';

REVOKE ALL ON FUNCTION public.purge_stale_incident_tracks() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.purge_stale_incident_tracks() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.purge_stale_incident_tracks() TO service_role;

DO $cron$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('purge-stale-incident-tracks')
      WHERE EXISTS (
        SELECT 1 FROM cron.job WHERE jobname = 'purge-stale-incident-tracks'
      );
    PERFORM cron.schedule(
      'purge-stale-incident-tracks',
      '45 3 * * *',
      $job$SELECT public.purge_stale_incident_tracks();$job$
    );
  ELSE
    RAISE NOTICE
      'pg_cron is not installed; run public.purge_stale_incident_tracks() on a schedule yourself';
  END IF;
END $cron$;
