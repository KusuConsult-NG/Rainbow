-- Attaching evidence to an incident without losing any of it.
--
-- ## What was wrong
--
-- Three places append a URL to `alerts.media_urls`, and all three did it by
-- reading the array, adding to the copy, and writing the whole thing back:
--
--   lib/services/sync_service.dart                       the offline flush
--   lib/features/agent/mission_intel_screen.dart          a responder's evidence
--   lib/features/emergency/emergency_active_screen.dart   DURESS evidence
--
-- Read-modify-write over a network is lost-update by construction. Two uploads
-- that overlap both read the same array, and the second write erases the first.
-- The overlap is not hypothetical: the offline flush uploads a whole queue in a
-- loop, the duress screen fires each upload without awaiting it
-- (`unawaited(...)`), and a responder can photograph a scene twice in a few
-- seconds. Whichever upload finished second won and the other photograph was
-- gone — while the UI said "Evidence captured and sent to HQ".
--
-- `sync_service.dart` even labels its block "Atomic URL append to
-- alerts.media_urls". It is a comment, not a mechanism.
--
-- Evidence of a kidnapping that the app said it had sent is the worst thing in
-- this system to lose quietly.
--
-- ## The fix
--
-- ONE statement, and the row is locked inside it.
--
-- `FOR UPDATE` in the first CTE takes the row lock before anything is read, so
-- concurrent callers serialise rather than interleave: the second one blocks,
-- then re-reads the committed array and appends to THAT. Nothing is lost
-- whatever the ordering, and `added` is exact rather than approximate — which it
-- could not be if the old length were read in a separate statement.
--
-- Deduplicated on the way in, first occurrence winning, so retrying an upload
-- that actually succeeded does not put the same photograph in front of a
-- dispatcher twice, and does not shuffle it to the end of the dossier.
--
-- `coalesce(p_urls, '{}')` is not defensive habit. In PostgreSQL
-- `array || NULL::text[]` is NULL, so a caller passing a null array would have
-- ERASED every photograph already attached. That is a lost-evidence bug one
-- keystroke wide, and it is asserted against.
--
-- ## Why SECURITY INVOKER
--
-- Deliberately NOT a definer function. `alerts_update_own_or_ours` already says
-- who may change an incident — the reporter, the assigned team, and staff within
-- their command — and that is exactly the right rule for attaching evidence to
-- it. A definer function here would be a hole straight through the scoping
-- migration: anybody with a token could bolt media onto any incident in Plateau.
--
-- So row-level security applies, and the function returns NO ROW when the caller
-- is refused. The caller must treat an empty result as a refusal and never as
-- success — that is the one thing the Dart side has to get right, and
-- AlertMedia.append does.

CREATE OR REPLACE FUNCTION public.append_alert_media(
  p_alert_id UUID,
  p_urls     TEXT[]
)
RETURNS TABLE (added INTEGER, total INTEGER)
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  WITH locked AS (
    -- The lock, taken before the array is read. Row-level security applies to
    -- this SELECT, so an account with no part in the incident stops here and
    -- the whole statement returns nothing.
    SELECT a.id,
           coalesce(array_length(a.media_urls, 1), 0) AS before_n
      FROM public.alerts a
     WHERE a.id = p_alert_id
       FOR UPDATE
  ),
  updated AS (
    UPDATE public.alerts a
       SET media_urls = (
             -- WITH ORDINALITY so the order photographs were taken in survives,
             -- and min(ord) so a duplicate keeps its FIRST position rather than
             -- jumping to the end.
             SELECT coalesce(array_agg(d.u ORDER BY d.ord), '{}'::TEXT[])
               FROM (
                 SELECT t.u, min(t.ord) AS ord
                   FROM unnest(coalesce(a.media_urls, '{}'::TEXT[])
                               || coalesce(p_urls, '{}'::TEXT[]))
                          WITH ORDINALITY AS t(u, ord)
                  WHERE nullif(trim(t.u), '') IS NOT NULL
                  GROUP BY t.u
               ) d
           ),
           updated_at = now()
      FROM locked l
     WHERE a.id = l.id
    RETURNING coalesce(array_length(a.media_urls, 1), 0) AS after_n, l.before_n
  )
  SELECT (u.after_n - u.before_n)::INTEGER, u.after_n::INTEGER FROM updated u;
$$;

COMMENT ON FUNCTION public.append_alert_media(UUID, TEXT[]) IS
  'Append evidence URLs to an incident in ONE locked statement, so two '
  'concurrent uploads cannot erase each other. SECURITY INVOKER: '
  'alerts_update_own_or_ours decides who may attach. Returns no row when the '
  'caller is refused — a caller must not read that as success.';

REVOKE ALL ON FUNCTION public.append_alert_media(UUID, TEXT[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.append_alert_media(UUID, TEXT[]) FROM anon;
GRANT EXECUTE ON FUNCTION public.append_alert_media(UUID, TEXT[])
  TO authenticated, service_role;
