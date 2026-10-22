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
-- 20261025000000_the_other_policy_public_could_reach.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261025000000_the_other_policy_public_could_reach.sql'; END $apply$;

-- ============================================================================
-- The OTHER policy PUBLIC could reach
--
-- A production policy query came back with two rows:
--
--   alerts_select_geo_lga_scoped    | alerts    | SELECT
--   telemetry_select_geo_lga_scoped | telemetry | SELECT
--
-- The second is known. 20261016000000_telemetry_policy_is_not_public.sql exists
-- because a production paste reported it as the one policy reaching PUBLIC, and
-- that migration drops and recreates it TO authenticated.
--
-- The first is its TWIN, and nothing had looked at it.
--
-- Both are created by 20260725000000_v6_geo_lga_scoping_staging.sql, twelve
-- lines apart. The telemetry one is written `TO authenticated`. The alerts one
-- is written:
--
--     CREATE POLICY "alerts_select_geo_lga_scoped"
--       ON public.alerts
--       FOR SELECT
--       USING ( … )          -- no TO clause
--
-- and PostgreSQL records a policy with no TO clause as **TO PUBLIC**, which
-- includes `anon`. So the lesson had already been learned, written down, and
-- committed as a comment IN THAT FILE, directly below a policy carrying the
-- same defect — and the sibling was never fixed.
--
-- ## What it exposes
--
-- `alerts` is the incident table: the reporter's name and phone number, what
-- they said, where they are. `telemetry` is position history. Neither should be
-- reachable by the anonymous key under any circumstances.
--
-- What stops this being an open database today is only that
-- 20260813000000_rls_least_privilege.sql REVOKEs the table privileges from
-- `anon`, so the policy has nothing to permit. That is one layer. A single
-- GRANT, or one click in the dashboard's table editor, and the policy is the
-- only thing standing between the anonymous key and every incident on the
-- board — and it says yes.
--
-- ## Why neither the migration nor the tests caught it
--
-- Three reasons, and they are the same three that hid the telemetry twin:
--
--   * 20260813 drops prior policies BY EXACT NAME, 98 of them, and neither v6
--     policy is in the list — it cannot be, because 20260725 is a file that
--     migration had no reason to know about. Checked: 0 occurrences of
--     `geo_lga_scoped` in it.
--   * `20260725…_staging.sql` is STAGING_ONLY, so it is not in the production
--     paste at all. Production has these two policies because the v6 era was
--     applied BY HAND. A file excluded from the paste still shaped the database
--     the paste runs against.
--   * verify_rls_migration.sh asserts no policy reaches anon or public at the
--     END of the full replay, and passes — because 20261006000000 drops
--     `alerts_select_geo_lga_scoped` on its way to the posting-scoped policy.
--     The end state is clean. Production is sitting in the MIDDLE, where the
--     policy exists and the drop has not been applied, and no assertion in this
--     repository describes the middle.
--
-- ## What this does
--
-- `ALTER POLICY … TO authenticated`, which changes the policy's ROLES and
-- nothing else. No officer loses a row they could read before; `anon` and
-- PUBLIC lose a policy that should never have named them.
--
-- Deliberately NOT a drop-and-recreate, which is what the first draft of this
-- file did and what 20261016 does for the twin. Production's copy of this
-- policy was applied BY HAND. Recreating it from the expression in this
-- repository would impose this repository's text on a database whose version
-- may differ — and that expression decides which officer may read which
-- incident. ALTER POLICY leaves the body exactly as it is, and leaves no
-- window in which the table carries no policy at all.
--
-- Idempotent, and a no-op in two different ways on purpose:
--
--   * on a database built from this repository the policy is already gone,
--     dropped by 20261006000000 eleven files earlier, and this says so;
--   * on a database where it is already TO authenticated, nothing changes.
--
-- 20261006000000 still drops it later in the paste, in favour of
-- `alerts_select_own_or_ours`. This exists so that a production database is
-- safe the moment it is pasted, on its own, before the other thirty-six.
-- ============================================================================

DO $$
DECLARE
  current_roles NAME[];
  reaches_public INTEGER;
BEGIN
  SELECT roles INTO current_roles
    FROM pg_policies
   WHERE schemaname = 'public'
     AND tablename  = 'alerts'
     AND policyname = 'alerts_select_geo_lga_scoped';

  IF current_roles IS NULL THEN
    RAISE NOTICE
      'alerts_select_geo_lga_scoped is not on this database — either '
      '20260725 (staging-only) never ran here, or 20261006 has already '
      'replaced it with alerts_select_own_or_ours. Nothing to repair.';

  ELSIF NOT ('public' = ANY(current_roles) OR 'anon' = ANY(current_roles)) THEN
    RAISE NOTICE
      'alerts_select_geo_lga_scoped is already scoped to % — left alone',
      current_roles;

  ELSE
    -- ALTER POLICY, NOT DROP AND RECREATE.
    --
    -- The first version of this migration dropped the policy and recreated it
    -- from the expression in 20260725000000_v6_geo_lga_scoping_staging.sql.
    -- That is wrong here, and quietly so: production's copy of this policy was
    -- applied BY HAND, so the only thing known about its body is that it was
    -- once pasted from that file. Recreating it imposes THIS repository's text
    -- on a database whose version may differ by a character — and the thing
    -- being rewritten decides which officer may read which incident.
    --
    -- `ALTER POLICY … TO authenticated` changes only the roles. The USING
    -- expression on that database is left exactly as it is, whatever it is.
    -- There is also no window in which the table has no policy, which a drop
    -- followed by a failing recreate would leave behind.
    RAISE NOTICE
      'alerts_select_geo_lga_scoped is TO % — scoping it TO authenticated, '
      'leaving its USING expression untouched', current_roles;

    ALTER POLICY "alerts_select_geo_lga_scoped" ON public.alerts TO authenticated;

    COMMENT ON POLICY "alerts_select_geo_lga_scoped" ON public.alerts IS
      'An officer may read incidents in their own LGA. Scoped TO authenticated '
      'by 20261025000000: created by 20260725 with no TO clause, which '
      'PostgreSQL records as TO PUBLIC — and PUBLIC includes anon. 20260813 '
      'could not drop it by name because that migration predates the file. Its '
      'telemetry twin had the same defect and was repaired by 20261016000000; '
      'this is the one beside it that was missed. Only the roles were changed: '
      'the expression is whatever this database already had.';

    RAISE NOTICE 'alerts_select_geo_lga_scoped is now scoped TO authenticated';
  END IF;

  -- Both known offenders are now closed. Anything else reaching PUBLIC is new
  -- information and is named, loudly, rather than left for the next person to
  -- find on a live database.
  SELECT count(*) INTO reaches_public
    FROM pg_policies
   WHERE schemaname = 'public'
     AND ('anon' = ANY(roles) OR 'public' = ANY(roles));

  IF reaches_public = 0 THEN
    RAISE NOTICE 'No policy in schema public reaches anon or public.';
  ELSE
    RAISE WARNING
      '% policy/policies in schema public still reach anon or public. Run '
      'scripts/rls_inventory.sql and read the roles column — a policy with no '
      'TO clause is recorded as TO PUBLIC.', reaches_public;
  END IF;
END $$;

