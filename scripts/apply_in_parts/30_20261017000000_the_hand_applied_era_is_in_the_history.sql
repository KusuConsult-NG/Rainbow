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
-- 20261017000000_the_hand_applied_era_is_in_the_history.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261017000000_the_hand_applied_era_is_in_the_history.sql'; END $apply$;

-- ============================================================================
-- Production has objects this repository cannot build. Close that.
--
-- The v2–v6 era (20260721 … 20260725) was applied to production BY HAND, before
-- the project kept a migration history, and written down as files afterwards.
-- Those files cannot be replayed from zero — v2 calls auth.jwt() before the
-- shim defines it, and v5 builds a policy on profiles.badge_number, a column
-- 20260903000004 adds eleven migrations later — so scripts/bootstrap_staging.sql
-- and scripts/verify_rls_migration.sh deliberately exclude them.
--
-- The consequence is that the live database and every database this repository
-- can build have different schemas, and the difference is invisible until it
-- decides something.
--
-- ## Three times it already has
--
-- 1. A 428C9 error. `INSERT INTO alerts` with no column list is refused at the
--    FIRST generated column in ordinal order. On production that is `lga` at
--    28; on a repo-built database `category` at 33 was the only one. The same
--    statement reports a different column name on each, which is a diagnosis
--    sent in the wrong direction.
--
--    This migration does NOT fix that, and an earlier draft of this comment
--    claimed it did. It converges the column SET, not the ordinal ORDER:
--    attribute numbers are assigned when a column is added, so the mirrors land
--    after `category` here and before it on production. The behaviour test
--    prints which column comes first precisely so nobody re-derives the wrong
--    expectation — it still reads `category` on a fresh database.
--
--    What actually closes that defect is
--    scripts/check_generated_column_inserts.py, which refuses any insert into a
--    table with a generated column that has no explicit column list. The error
--    cannot be reached from this repository at all, so which name it would have
--    reported stops mattering.
--
-- 2. `telemetry_select_geo_lga_scoped` sat on production as TO PUBLIC for weeks
--    while verify_rls_migration.sh asserted no policy reaches anon or public —
--    and passed, because the policy does not exist in the schema it replays.
--    Fixed in 20261016000000; the assertion now also runs after the full
--    replay.
--
-- 3. dashboard/page.tsx carries a comment stating that `lga`, `ward` and
--    `sector_id` are not columns on profiles and that PostgREST therefore
--    rejected a query naming them. All three exist on production — v2 adds
--    them. The query it describes would have worked there. The fix was right
--    for other reasons (it was missing fields its consumers read), but the
--    reasoning written into the file is wrong, and it was wrong because it was
--    checked against the repository rather than the database.
--
-- ## What this adds, and why each one
--
-- Everything from that era that can CHANGE BEHAVIOUR or MISLEAD A DIAGNOSIS.
-- Non-destructive: every statement is guarded, so on production this migration
-- is a no-op that prints what it found.
--
--   set_updated_at() + trg_alerts_updated_at
--       Production maintains alerts.updated_at automatically. A repo-built
--       database has the COLUMN (base schema, DEFAULT NOW()) and no trigger, so
--       updated_at only moves where code assigns it. "When did this incident
--       last change" answers differently on the two, which is the sort of thing
--       an inquiry asks.
--
--   normalise_lga(text)
--       Compares LGA strings case- and whitespace-insensitively. Referenced by
--       the telemetry policy below and by 20261016000000's guard.
--
--   telemetry_select_geo_lga_scoped
--       An officer may read the positions of citizens posted to their own LGA.
--       This is an access-control rule: a staging database without it refuses
--       reads production allows, so any test of who-can-see-what is answering
--       about a different system. Created TO authenticated, never without a TO
--       clause — without one PostgreSQL records TO PUBLIC, which includes anon,
--       which is exactly what 20261016000000 had to repair.
--
--   alerts.lga / ward / pu, profiles.lga / ward
--       Generated mirrors of the geo_* columns, from v2 ("shorthand aliases
--       used by some Flutter queries"). Nothing in either app reads them today
--       — checked — but they are what makes ordinal 28 generated on production,
--       and defect 1 above is what that costs.
--
--   alerts.assigned_to_uid, alerts.post_sos_status, profiles.sector_id
--       Plain columns from the same era. Unused, and added for the same reason:
--       a column that exists on one side and not the other turns `SELECT *`
--       into two different queries.
--
-- ## What this deliberately does NOT add
--
-- `is_hq_or_admin()` and `is_responder()`, from v5. They exist on production and
-- are referenced by NOTHING — their only callers were the v5-era policies, and
-- 20260813000000_rls_least_privilege.sql drops all of those by name. Adding dead
-- SECURITY DEFINER functions to the canonical schema to match dead functions on
-- production is not convergence, it is propagation.
--
-- They are recorded as a known difference in scripts/check_schema_convergence.py
-- so the gate does not fail on them, and they are safe to drop on production
-- whenever somebody is confident nothing outside this repository calls them:
--
--     DROP FUNCTION IF EXISTS public.is_hq_or_admin();
--     DROP FUNCTION IF EXISTS public.is_responder();
--
-- That is left for a human, because "nothing in the repository calls it" and
-- "nothing calls it" are different claims while the legacy Firebase functions
-- are still deployed.
--
-- ## The alternative, not taken
--
-- Converging DOWNWARD — dropping the five generated mirrors and three plain
-- columns from production — gives a smaller schema and removes the ordinal
-- hazard outright. It is not done here because dropping columns from a live
-- emergency database on the strength of "nothing in this repository reads them"
-- is not a call to make on a migration's own authority, and the same legacy
-- deployment that blocks the DROP above blocks this one.
-- ============================================================================

-- ── updated_at, maintained by the database ──────────────────────────────────

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.set_updated_at() IS
  'BEFORE UPDATE: stamps updated_at. From the hand-applied v2 era; brought into '
  'the migration history by 20261017000000 so a repo-built database maintains '
  'updated_at the way production does.';

DROP TRIGGER IF EXISTS trg_alerts_updated_at ON public.alerts;
CREATE TRIGGER trg_alerts_updated_at
  BEFORE UPDATE ON public.alerts
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ── LGA comparison helper ───────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.normalise_lga(lga TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT LOWER(TRIM(lga));
$$;

COMMENT ON FUNCTION public.normalise_lga(TEXT) IS
  'Lowercase and trim, so "Jos North" and "jos north " compare equal. Not the '
  'same as public.geo_key(), which additionally folds trailing Roman numerals '
  'and is what ward names are compared on.';

-- ── The era's columns ───────────────────────────────────────────────────────
--
-- IF NOT EXISTS throughout: on production every one of these is already there
-- and this is a no-op. The generated mirrors cannot be added by a plain ALTER
-- on a table that already has them, which is the whole reason for the guard.

ALTER TABLE public.alerts
  ADD COLUMN IF NOT EXISTS assigned_to_uid UUID,
  ADD COLUMN IF NOT EXISTS post_sos_status TEXT,
  ADD COLUMN IF NOT EXISTS lga  TEXT GENERATED ALWAYS AS (geo_lga)  STORED,
  ADD COLUMN IF NOT EXISTS ward TEXT GENERATED ALWAYS AS (geo_ward) STORED,
  ADD COLUMN IF NOT EXISTS pu   TEXT GENERATED ALWAYS AS (geo_pu)   STORED;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS sector_id TEXT,
  ADD COLUMN IF NOT EXISTS lga  TEXT GENERATED ALWAYS AS (geo_lga)  STORED,
  ADD COLUMN IF NOT EXISTS ward TEXT GENERATED ALWAYS AS (geo_ward) STORED;

COMMENT ON COLUMN public.alerts.lga IS
  'Generated mirror of geo_lga, from the hand-applied v2 era. Read by nothing '
  'in either app. Present so that production and a repo-built database agree: a '
  'generated column changes which name a 428C9 error reports, because PostgreSQL '
  'names the FIRST generated column in an insert''s target list.';

-- ── The officer-scoped telemetry read ───────────────────────────────────────
--
-- Guarded so this does not fight 20261016000000, which repairs the TO PUBLIC
-- version on databases that have it. Here the job is the opposite: create it,
-- correctly, where it is absent.

DO $mig$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_policies
     WHERE schemaname = 'public'
       AND tablename  = 'telemetry'
       AND policyname = 'telemetry_select_geo_lga_scoped'
  ) THEN
    RAISE NOTICE 'telemetry_select_geo_lga_scoped already exists — left alone '
                 '(20261016000000 owns its scoping)';
    RETURN;
  END IF;

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
  RAISE NOTICE 'Created telemetry_select_geo_lga_scoped, scoped TO authenticated';
END $mig$;

-- ── Say what converged ──────────────────────────────────────────────────────

DO $$
DECLARE
  cols INTEGER;
  reaches_public INTEGER;
  has_trigger BOOLEAN;
BEGIN
  SELECT count(*) INTO cols
    FROM pg_attribute a
    JOIN pg_class c     ON c.oid = a.attrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public'
     AND ((c.relname = 'alerts'   AND a.attname IN ('lga','ward','pu','assigned_to_uid','post_sos_status'))
       OR (c.relname = 'profiles' AND a.attname IN ('lga','ward','sector_id')))
     AND a.attnum > 0 AND NOT a.attisdropped;

  SELECT EXISTS (
    SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
     WHERE c.relname = 'alerts' AND t.tgname = 'trg_alerts_updated_at'
  ) INTO has_trigger;

  SELECT count(*) INTO reaches_public
    FROM pg_policies
   WHERE schemaname = 'public'
     AND ('anon' = ANY(roles) OR 'public' = ANY(roles));

  RAISE NOTICE 'era columns present: % of 8; updated_at trigger: %; policies reaching anon/public: %',
    cols, has_trigger, reaches_public;

  IF cols <> 8 OR NOT has_trigger THEN
    RAISE EXCEPTION 'convergence incomplete: % of 8 columns, trigger %', cols, has_trigger;
  END IF;
  IF reaches_public <> 0 THEN
    RAISE WARNING '% policy/policies reach anon or public — run scripts/rls_inventory.sql', reaches_public;
  END IF;
END $$;

