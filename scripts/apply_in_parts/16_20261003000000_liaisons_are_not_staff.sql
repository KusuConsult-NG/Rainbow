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
-- 20261003000000_liaisons_are_not_staff.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261003000000_liaisons_are_not_staff.sql'; END $apply$;

-- ============================================================================
-- OPERATION RAINBOW — AN AGENCY LIAISON IS NOT OPERATION RAINBOW STAFF
--
-- THE HOLE
--
-- Six agencies send liaison officers to this console: the Police, the Army,
-- the DSS, the NSCDC, the FRSC and Operation Safe Haven. They are officers of
-- OTHER organisations, given an account so that an incident handed to their
-- agency reaches them.
--
-- `is_staff()` is:
--
--     (SELECT role FROM profiles WHERE id = auth.uid()) NOT IN ('CITIZEN', 'USER')
--
-- A `POLICE_LIAISON` is therefore staff. And the alerts policies are:
--
--     alerts_select_own_or_staff   USING (... OR is_staff())
--     alerts_update_own_or_staff   USING (... OR is_staff())
--
-- So every liaison could READ every incident in Plateau State, and WRITE to
-- every incident in Plateau State: resolve one in an LGA their agency was
-- never called to, reassign it, change its severity, clear a duress alarm.
-- Nothing scoped any of it to the agency, and nothing recorded that an outside
-- officer had done it.
--
-- The same sentence applies to `telemetry`: a liaison could read the live
-- position of every Operation Rainbow officer on duty in the state, and of
-- every citizen with an open emergency — including emergencies their agency
-- has no part in.
--
-- This was not a decision anyone made. `is_staff()` was written to mean "not a
-- member of the public", and the agency roles arrived later and fell inside
-- it.
--
-- WHAT THIS DOES
--
-- Scopes a liaison to their own agency's work:
--
--   * incidents escalated to their agency, or assigned to them personally;
--   * the positions of people tied to one of those incidents;
--   * the chat on one of those incidents.
--
-- And nothing else. Their own agency tables are unchanged — those were already
-- scoped by `liaison_agency()`, which is where this migration takes its lead.
--
-- WHAT IT DELIBERATELY DOES NOT DO
--
-- It does not narrow anything for Operation Rainbow's own staff. A polling-unit
-- officer still sees what they saw; this is about accounts belonging to another
-- organisation.
--
-- It does not remove a liaison's ability to ACT on an incident handed to them.
-- Handing an incident to an agency and then refusing them the ability to
-- update it would make the handover ceremonial.
--
-- Idempotent: safe to re-run.
-- ============================================================================

-- ── Is this account an outside agency's? ────────────────────────────────────

CREATE OR REPLACE FUNCTION public.is_liaison()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT role FROM public.profiles WHERE id = auth.uid()) LIKE '%\_LIAISON',
    false
  );
$$;

REVOKE EXECUTE ON FUNCTION public.is_liaison() FROM anon;

COMMENT ON FUNCTION public.is_liaison() IS
  'True for an officer of an outside agency (POLICE_LIAISON, ARMY_LIAISON, …). '
  'They are staff by is_staff(), which is why every alerts policy has to ask '
  'this as well.';

-- ── Which incidents belong to an outside agency ─────────────────────────────

CREATE OR REPLACE FUNCTION public.alert_is_ours(p_alert public.alerts)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
  SELECT
    -- Operation Rainbow's own staff: unchanged.
    (public.is_staff() AND NOT public.is_liaison())
    -- The reporter and the assignee, whoever they are.
    OR p_alert.reported_by = auth.uid()
    OR p_alert.assigned_to = auth.uid()
    -- An outside agency: only what was handed to them.
    OR (public.is_liaison()
        AND upper(COALESCE(p_alert.escalated_to_agency, '')) = public.liaison_agency());
$$;

COMMENT ON FUNCTION public.alert_is_ours(public.alerts) IS
  'Whether the calling account has a part in this incident. The whole point is '
  'the last clause: an agency liaison sees what was escalated to their agency, '
  'not the state.';

-- ── Alerts ──────────────────────────────────────────────────────────────────
--
-- REPLACED, not added. PostgreSQL ORs permissive policies together, so adding
-- a narrow one beside `... OR is_staff()` would change nothing at all.

DROP POLICY IF EXISTS "alerts_select_own_or_staff" ON public.alerts;
DROP POLICY IF EXISTS "alerts_select_own_or_ours" ON public.alerts;
CREATE POLICY "alerts_select_own_or_ours" ON public.alerts
  FOR SELECT TO authenticated
  USING (public.alert_is_ours(alerts));

DROP POLICY IF EXISTS "alerts_update_own_or_staff" ON public.alerts;
DROP POLICY IF EXISTS "alerts_update_own_or_ours" ON public.alerts;
CREATE POLICY "alerts_update_own_or_ours" ON public.alerts
  FOR UPDATE TO authenticated
  USING (public.alert_is_ours(alerts));

-- INSERT is left alone. A liaison filing an incident is filing it as
-- themselves, which `reported_by = auth.uid()` already covers.

-- ── Telemetry ───────────────────────────────────────────────────────────────
--
-- The live position of an Operation Rainbow officer is operational information
-- among colleagues. It is not information an outside agency is owed, except
-- for people working an incident that agency has been handed.

DROP POLICY IF EXISTS "telemetry_select_self_or_responding_staff" ON public.telemetry;
DROP POLICY IF EXISTS "telemetry_select_self_or_staff" ON public.telemetry;
DROP POLICY IF EXISTS "telemetry_select_scoped" ON public.telemetry;
CREATE POLICY "telemetry_select_scoped" ON public.telemetry
  FOR SELECT TO authenticated
  USING (
    -- Your own position, always.
    user_id = auth.uid()

    -- Operation Rainbow's own staff, exactly as before this migration: another
    -- STAFF member's position freely, and a CITIZEN's only while they have an
    -- emergency open.
    OR (public.is_staff() AND NOT public.is_liaison() AND (
          EXISTS (SELECT 1 FROM public.profiles p
                   WHERE p.id = telemetry.user_id
                     AND p.role NOT IN ('CITIZEN', 'USER'))
          OR EXISTS (SELECT 1 FROM public.alerts a
                      WHERE a.reported_by = telemetry.user_id
                        AND a.status NOT IN ('RESOLVED', 'CANCELLED'))
       ))

    -- An outside agency: only people tied to an incident handed to them.
    OR (public.is_liaison() AND EXISTS (
          SELECT 1 FROM public.alerts a
           WHERE upper(COALESCE(a.escalated_to_agency, '')) = public.liaison_agency()
             AND a.status NOT IN ('RESOLVED', 'CANCELLED')
             AND (a.reported_by = telemetry.user_id
                  OR a.assigned_to = telemetry.user_id)
       ))
  );

-- ── Chat ────────────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "chat_select_participant_or_staff" ON public.chat_messages;
DROP POLICY IF EXISTS "chat_select_participant_or_ours" ON public.chat_messages;
CREATE POLICY "chat_select_participant_or_ours" ON public.chat_messages
  FOR SELECT TO authenticated
  USING (
    sender_id = auth.uid()
    OR (public.is_staff() AND NOT public.is_liaison())
    OR EXISTS (
         SELECT 1 FROM public.alerts a
          WHERE a.id = chat_messages.alert_id
            AND public.alert_is_ours(a)
       )
  );

-- ── Say it out loud ─────────────────────────────────────────────────────────

COMMENT ON POLICY "alerts_select_own_or_ours" ON public.alerts IS
  'Replaces alerts_select_own_or_staff, under which every agency liaison could '
  'read every incident in the state because is_staff() means "not a citizen".';

COMMENT ON POLICY "alerts_update_own_or_ours" ON public.alerts IS
  'Replaces alerts_update_own_or_staff, under which an officer of another '
  'organisation could resolve or reassign any incident in Plateau.';



