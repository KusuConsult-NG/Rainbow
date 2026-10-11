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
-- 20261021000000_an_lga_can_hand_an_incident_to_a_ward.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261021000000_an_lga_can_hand_an_incident_to_a_ward.sql'; END $apply$;

-- ============================================================================
-- AN LGA COMMANDER CAN HAND AN INCIDENT TO A WARD
-- ============================================================================
--
-- The chain only ever climbed. `next_tier()` is UNIT -> WARD -> LGA -> HQ and
-- `escalationTargetFor()` offers no choice of target, so an LGA commander's
-- single escalation was upward to HQ. The one sideways move that existed was
-- HQ handing an incident DOWN to an LGA by name, which `to_lga` in the last
-- escalation entry records and `alert_delegated_to_my_lga()` grants.
--
-- There was no `to_ward` anywhere in the codebase. So an LGA commander who
-- judged that a neighbouring ward should take an incident — because the
-- roadblock is on their side of the boundary, or because the ward it sits in
-- has nobody free — had no way to say so. They could assign individual
-- responders across the LGA, but the other ward's COMMANDER never owned it.
--
-- This is the LGA hand-down, one rung lower, and deliberately the same shape:
-- the target named in the last escalation entry, a function that grants it, and
-- `alert_is_ours()` consulting that function. Nothing new to learn.
--
-- WHY BOTH THE WARD AND THE LGA ARE COMPARED
--
-- `alert_delegated_to_my_lga()` compares one name, because an LGA name is
-- unique in Plateau. Ward names are not: a ward called the same thing can exist
-- in two LGAs, and granting on the ward name alone would hand the incident to a
-- commander in a different LGA who happens to share it. So the LGA must agree
-- too, unless the entry did not record one.
--
-- WHY AN EXACT COMPARISON IS ENOUGH
--
-- The Dart side compares places through `geoKey`, which collapses whitespace,
-- because the app writes a ward resolved from the GPS centroid asset
-- ('GINDIRI  I') while an officer is posted from the tactical map
-- ('GINDIRI  1'). That mismatch cannot arise here: the ward written into
-- `to_ward` is chosen from the tactical map, and the commander's `geo_ward` is
-- posted from the same tactical map. Both sides come from one source.
-- ============================================================================

BEGIN;

-- ── Was it handed to my ward ────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.alert_delegated_to_my_ward(p_alert public.alerts)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
  WITH me AS (
    SELECT nullif(upper(trim(coalesce(geo_lga,  ''))), '') AS lga,
           nullif(upper(trim(coalesce(geo_ward, ''))), '') AS ward
      FROM public.profiles
     WHERE id = auth.uid()
  ),
  handed AS (
    SELECT nullif(upper(trim(coalesce(
             (p_alert.escalation_log
                -> jsonb_array_length(p_alert.escalation_log) - 1)
               ->> 'to_ward', ''))), '') AS ward,
           nullif(upper(trim(coalesce(
             (p_alert.escalation_log
                -> jsonb_array_length(p_alert.escalation_log) - 1)
               ->> 'to_lga', ''))), '') AS lga
  )
  SELECT COALESCE(
    (SELECT ward FROM handed) IS NOT NULL
    AND (SELECT ward FROM handed) = (SELECT ward FROM me)
    -- An entry that named no LGA is trusted on the ward alone; one that named
    -- an LGA must agree with the caller's.
    AND ((SELECT lga FROM handed) IS NULL
         OR (SELECT lga FROM handed) = (SELECT lga FROM me)),
    false
  );
$$;

COMMENT ON FUNCTION public.alert_delegated_to_my_ward(public.alerts) IS
  'Whether the last escalation entry handed this incident to the calling '
  'account''s ward. The LAST entry only: the log is append-only, so an earlier '
  'handover has been superseded. The LGA must agree too, because ward names '
  'are not unique across LGAs.';

REVOKE ALL ON FUNCTION public.alert_delegated_to_my_ward(public.alerts) FROM anon;

-- ── And the one question the policies ask ───────────────────────────────────
--
-- RESTATED FROM 20261015000000, NOT FROM 20261006000000.
--
-- `alert_is_ours()` has been replaced twice. 20261006000000 restates it as a
-- flat OR and says why — "so a replica built from these files in order gets the
-- same result whichever migration ran last" — and 20261015000000 then WRAPPED
-- it in a CASE whose first branch is exclusive:
--
--     WHEN public.is_oversight_matter(p_alert.type) THEN
--       public.commands_whole_state() OR p_alert.reported_by = auth.uid()
--
-- A complaint about security personnel goes to HQ and the complainant, and to
-- nobody else, because the ordinary clauses would hand it to the accused's own
-- command.
--
-- The first version of THIS migration copied the restatement idiom from
-- 20261006000000 — the older generation — and so dropped that CASE. Every
-- client test passed. `scripts/oversight_behaviour_test.sql` caught it on a
-- real PostgreSQL: "FAIL: the WARD COMMAND of the ward it was filed in can read
-- a complaint about security personnel". Restating a function is only safe
-- against its CURRENT definition, and the only way to know which that is, is to
-- replay the history.
--
-- The one change below is the ward clause in the ELSE branch.

CREATE OR REPLACE FUNCTION public.alert_is_ours(p_alert public.alerts)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
  SELECT CASE
    -- A complaint about security personnel goes to HQ and the person who made
    -- it. Checked FIRST and exclusively: the clauses below would otherwise hand
    -- it to the accused's own command, which is the defect. A hand-down must
    -- not become a way around it either, which is why this stays first.
    WHEN public.is_oversight_matter(p_alert.type) THEN
      public.commands_whole_state()
      OR p_alert.reported_by = auth.uid()

    ELSE
      -- HQ and administrators: the state.
      public.commands_whole_state()
      -- The reporter, the lead, and every officer on the dispatched team.
      OR p_alert.reported_by = auth.uid()
      OR p_alert.assigned_to = auth.uid()
      OR auth.uid()::text = ANY (COALESCE(p_alert.assigned_responders, '{}'::text[]))
      -- Operation Rainbow staff, within their command, plus anything handed to
      -- their LGA or to their WARD by name.
      OR (public.is_staff() AND NOT public.is_liaison()
          AND (public.alert_in_my_area(p_alert)
               OR public.alert_delegated_to_my_lga(p_alert)
               OR public.alert_delegated_to_my_ward(p_alert)))
      -- An outside agency: only what was handed to them.
      OR (public.is_liaison()
          AND upper(COALESCE(p_alert.escalated_to_agency, '')) = public.liaison_agency())
  END;
$$;

COMMENT ON FUNCTION public.alert_is_ours(public.alerts) IS
  'Whether the calling account has a part in this incident: HQ sees the state, '
  'everyone else sees their command, anything handed to them by name, and '
  'their own work — EXCEPT a complaint against security personnel, which only '
  'HQ and the complainant may see.';

COMMIT;



