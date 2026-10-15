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
-- Repairs the policy in place, the same way 20261016 repaired its twin: same
-- name, same USING expression to the character, `TO authenticated` added. No
-- officer loses a row they could read before; `anon` and PUBLIC lose a policy
-- that should never have named them.
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
    -- The policy's USING expression references this. It must exist, or the
    -- recreate fails AFTER the drop and the table loses the policy entirely —
    -- which on production would quietly narrow what officers can read.
    IF NOT EXISTS (
      SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'public' AND p.proname = 'normalise_lga'
    ) THEN
      RAISE EXCEPTION
        'alerts_select_geo_lga_scoped exists but public.normalise_lga(text) '
        'does not. Apply 20261017000000_the_hand_applied_era_is_in_the_history.sql '
        'first — it creates the function this policy reads.';
    END IF;

    RAISE NOTICE
      'alerts_select_geo_lga_scoped is TO % — recreating it TO authenticated',
      current_roles;

    DROP POLICY "alerts_select_geo_lga_scoped" ON public.alerts;

    -- Same expression as 20260725000000_v6_geo_lga_scoping_staging.sql, with
    -- the TO clause the telemetry policy twelve lines below it already had.
    CREATE POLICY "alerts_select_geo_lga_scoped"
      ON public.alerts
      FOR SELECT
      TO authenticated
      USING (
        auth.role() = 'authenticated'
        AND EXISTS (
          SELECT 1 FROM public.profiles p
          WHERE p.id = auth.uid()
            AND p.role IN ('FIELD_OFFICER', 'WARD_OFFICER', 'LGA_OFFICER')
            AND p.geo_lga IS NOT NULL
            AND TRIM(p.geo_lga) <> ''
            AND public.normalise_lga(p.geo_lga) = public.normalise_lga(alerts.geo_lga)
        )
      );

    COMMENT ON POLICY "alerts_select_geo_lga_scoped" ON public.alerts IS
      'An officer may read incidents in their own LGA. Scoped TO authenticated '
      'by 20261025000000: created by 20260725 with no TO clause, which '
      'PostgreSQL records as TO PUBLIC — and PUBLIC includes anon. 20260813 '
      'could not drop it by name because that migration predates the file. Its '
      'telemetry twin had the same defect and was repaired by 20261016000000; '
      'this is the one beside it that was missed.';

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
