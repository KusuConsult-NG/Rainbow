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
-- 20261016000000_telemetry_policy_is_not_public.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261016000000_telemetry_policy_is_not_public.sql'; END $apply$;

-- ============================================================================
-- The one policy on this database that PUBLIC could reach
--
-- A production paste reported:
--
--   *** FAIL *** | no policy grants anon or public anything
--
-- and it was this, alone:
--
--   telemetry | telemetry_select_geo_lga_scoped | SELECT | {public}
--
-- `{public}` is not a role somebody chose. It is what PostgreSQL records when a
-- CREATE POLICY has no `TO` clause, and PUBLIC includes `anon` — so the policy
-- was reachable, in principle, by anyone holding the anonymous key.
--
-- ## Why it survived the migration that exists to prevent this
--
-- 20260813000000_rls_least_privilege.sql drops prior policies BY EXACT NAME, and
-- `telemetry_select_geo_lga_scoped` is not in its list — it cannot be, because
-- the policy is created by 20260725000000_v6_geo_lga_scoping_staging.sql, which
-- is a file 20260813 had no reason to know about. Checked: 0 occurrences of the
-- name in that migration.
--
-- ## Why no test caught it
--
-- verify_rls_migration.sh asserts that no policy grants anon or public — and it
-- passes. The assertion sits immediately after 20260813 is applied, which is
-- eleven migrations before 20260725 is applied, so at the moment it looks the
-- policy does not exist yet. A check at one point in the history cannot answer a
-- question about the end state. That gate now also runs at the END of the
-- replay, after every migration, which is where it would have been found.
--
-- ## What was actually at risk
--
-- Less than the shape suggests, and more than nothing. `telemetry` is where
-- citizens' positions are written. The policy's own qualifier opens with
-- `auth.role() = 'authenticated'`, and 20260813 separately REVOKEs telemetry's
-- table privileges from anon — on the live database, `has_table_privilege('anon',
-- 'telemetry', 'SELECT')` is false. So two independent things had to be true
-- before this leaked, and only one of them was.
--
-- But the privilege half is one `GRANT` away from being untrue: a click in the
-- dashboard's table editor, a migration written in a hurry, a restore from a
-- backup taken before 20260813. Defence in depth means the policy layer has to
-- hold on its own, and this one was relying on the layer beneath it.
--
-- ## What this changes
--
-- `TO authenticated`, and nothing else. The qualifier is copied across verbatim,
-- including the `auth.role() = 'authenticated'` test that is now redundant — a
-- redundant condition is cheaper than a behaviour change nobody asked for, and
-- the two express the same intent at different layers.
--
-- For a legitimate caller this is identical: the policy already demanded an
-- authenticated role. For anon it changes from "refused by the qualifier, if the
-- qualifier is reached" to "not applicable at all".
--
-- 20260725 itself is fixed in the same commit, so a staging database built after
-- today does not inherit it. This file is what repairs the databases that
-- already have it, because that file's guard is `IF NOT EXISTS` and correctly
-- does nothing where the policy is already present.
-- ============================================================================

-- ## Only where there is something to repair
--
-- A first version of this did an unconditional DROP ... IF EXISTS followed by a
-- plain CREATE, and broke every database that had never applied 20260725:
--
--   ERROR:  function public.normalise_lga(text) does not exist
--
-- `normalise_lga` comes from 20260725 as well, and scripts/bootstrap_staging.sql
-- deliberately excludes that file (it is staging-only and does not replay from
-- zero). So the CREATE referenced a function that was not there, the bootstrap
-- is one transaction, and the whole thing rolled back.
--
-- The policy and the function arrive together, so the policy's presence is the
-- right condition: where it exists there is something to fix and the function is
-- there to fix it with, and where it does not, this migration has no work.
DO $mig$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
     WHERE schemaname = 'public'
       AND tablename  = 'telemetry'
       AND policyname = 'telemetry_select_geo_lga_scoped'
  ) THEN
    RAISE NOTICE
      'telemetry_select_geo_lga_scoped is not on this database (20260725 was '
      'never applied here) — nothing to repair';
    RETURN;
  END IF;

  -- Defensive, and it raises rather than warns on purpose: the two came from one
  -- file, so their absence together is an inconsistency worth stopping on, and
  -- dropping a policy this cannot then recreate would leave telemetry with no
  -- read path at all.
  IF to_regprocedure('public.normalise_lga(text)') IS NULL THEN
    RAISE EXCEPTION
      'telemetry_select_geo_lga_scoped exists but public.normalise_lga(text) '
      'does not — refusing to drop a policy I cannot recreate';
  END IF;

  DROP POLICY "telemetry_select_geo_lga_scoped" ON public.telemetry;

  EXECUTE $pol$
    CREATE POLICY "telemetry_select_geo_lga_scoped"
      ON public.telemetry
      FOR SELECT
      TO authenticated
      USING (
        auth.role() = 'authenticated'
        AND EXISTS (
          SELECT 1 FROM public.profiles caller
          WHERE caller.id = auth.uid()
            AND caller.role IN ('FIELD_OFFICER', 'WARD_OFFICER', 'LGA_OFFICER')
            AND caller.geo_lga IS NOT NULL
            AND TRIM(caller.geo_lga) <> ''
            AND EXISTS (
              SELECT 1 FROM public.profiles target
              WHERE target.id = telemetry.user_id
                AND public.normalise_lga(target.geo_lga)
                  = public.normalise_lga(caller.geo_lga)
            )
        )
      )
  $pol$;

  -- Inside the guard too. Left outside it, this failed with `policy
  -- "telemetry_select_geo_lga_scoped" for table "telemetry" does not exist` on
  -- every database the guard had just correctly skipped.
  EXECUTE $cmt$
    COMMENT ON POLICY "telemetry_select_geo_lga_scoped" ON public.telemetry IS
      'An officer may read the positions of citizens posted to their own LGA. '
      'Scoped TO authenticated: the same policy without a TO clause was recorded '
      'as TO PUBLIC, which includes anon, and 20260813 could not drop it by name '
      'because it comes from a file that migration predates.'
  $cmt$;

  RAISE NOTICE 'telemetry_select_geo_lga_scoped is now scoped TO authenticated';
END $mig$;

-- Say so in the log, because a policy replacement leaves no other trace and the
-- operator running this is doing it in response to a failed check. Reports on
-- the whole schema, so it is useful whether or not the guard above did anything.
DO $$
DECLARE reaches_public INTEGER;
BEGIN
  SELECT count(*) INTO reaches_public
    FROM pg_policies
   WHERE schemaname = 'public'
     AND ('anon' = ANY(roles) OR 'public' = ANY(roles));

  IF reaches_public = 0 THEN
    RAISE NOTICE 'telemetry_select_geo_lga_scoped is now TO authenticated; no policy in public reaches anon or public';
  ELSE
    RAISE WARNING 'telemetry_select_geo_lga_scoped fixed, but % other policy/policies still reach anon or public — run scripts/rls_inventory.sql', reaches_public;
  END IF;
END $$;

