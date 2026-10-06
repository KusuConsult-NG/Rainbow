-- ============================================================================
-- The hand-applied era, asserted as BEHAVIOUR rather than as column names
--
-- 20261017000000 brings the v2–v6 objects into the migration history so that a
-- database this repository builds matches the live one.
-- scripts/check_schema_convergence.py proves the migrations DECLARE them; this
-- proves the database then DOES the right thing with them, which is a different
-- claim and the one that was costing us.
-- ============================================================================

\set ON_ERROR_STOP on
SET client_min_messages TO NOTICE;

-- ── 1. updated_at moves on its own ──────────────────────────────────────────
--
-- Production maintains alerts.updated_at with a BEFORE UPDATE trigger. A
-- repo-built database had the column and no trigger, so "when did this incident
-- last change" answered differently on the two. Asserted by UPDATING a row and
-- reading the column back, not by looking for the trigger's name — a trigger
-- that exists and does nothing would pass that.
DO $$
DECLARE
  before_ts TIMESTAMPTZ;
  after_ts  TIMESTAMPTZ;
BEGIN
  INSERT INTO public.alerts (id, type, status, description, reported_by)
  VALUES ('eeee0000-0000-4000-8000-00000000e001', 'Flood - Riverbank', 'OPEN',
          'convergence test', NULL);

  -- The first version of this test back-dated updated_at with a plain UPDATE and
  -- failed its own guard: `could not back-date updated_at`. Of course — the
  -- BEFORE UPDATE trigger stamps NOW() over whatever the statement sets, which
  -- is the behaviour being tested. The planting has to bypass the trigger, so
  -- the assertion that follows is about the trigger and not about the planting.
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
     WHERE c.relname = 'alerts' AND t.tgname = 'trg_alerts_updated_at'
       AND NOT t.tgisinternal
  ) THEN
    RAISE EXCEPTION 'FAIL: trg_alerts_updated_at does not exist, so '
                    'alerts.updated_at only moves where a caller assigns it — '
                    'which is not what production does';
  END IF;

  EXECUTE 'ALTER TABLE public.alerts DISABLE TRIGGER trg_alerts_updated_at';
  UPDATE public.alerts SET updated_at = NOW() - INTERVAL '1 day'
   WHERE id = 'eeee0000-0000-4000-8000-00000000e001';
  EXECUTE 'ALTER TABLE public.alerts ENABLE TRIGGER trg_alerts_updated_at';

  SELECT updated_at INTO before_ts FROM public.alerts
   WHERE id = 'eeee0000-0000-4000-8000-00000000e001';
  IF before_ts > NOW() - INTERVAL '1 hour' THEN
    RAISE EXCEPTION 'FAIL: could not plant an old updated_at (%) even with the '
                    'trigger disabled, so the next assertion proves nothing',
                    before_ts;
  END IF;

  -- An ordinary field change. The trigger must stamp updated_at even though
  -- this statement never mentions it. Same transaction is fine: NOW() is the
  -- transaction timestamp, and NOW() is an hour-and-a-day ahead of the planted
  -- value either way.
  UPDATE public.alerts SET description = 'convergence test, edited'
   WHERE id = 'eeee0000-0000-4000-8000-00000000e001';

  SELECT updated_at INTO after_ts FROM public.alerts
   WHERE id = 'eeee0000-0000-4000-8000-00000000e001';

  IF after_ts <= before_ts THEN
    RAISE EXCEPTION 'FAIL: updated_at did not move on an UPDATE (% -> %). '
                    'trg_alerts_updated_at exists but is inert.',
                    before_ts, after_ts;
  END IF;
  RAISE NOTICE 'PASS: updated_at is stamped by the database, not by the caller';
END $$;

-- ── 2. The generated mirrors are GONE ───────────────────────────────────────
--
-- This section used to assert the opposite: that alerts.lga/ward/pu exist,
-- mirror geo_*, and are unwritable. 20261018000000 drops them — converging
-- DOWNWARD on the decision that geo_lga/geo_ward/geo_pu are the only place the
-- geography should live, which is what every app already reads.
--
-- Asserted as absence rather than deleted, because a mirror quietly coming back
-- is exactly the shape of the problem these sections were written for.
DO $$
DECLARE still_here TEXT;
BEGIN
  SELECT string_agg(c.relname || '.' || a.attname, ', ') INTO still_here
    FROM pg_attribute a
    JOIN pg_class c     ON c.oid = a.attrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public'
     AND ((c.relname = 'alerts'   AND a.attname IN ('lga', 'ward', 'pu'))
       OR (c.relname = 'profiles' AND a.attname IN ('lga', 'ward')))
     AND a.attnum > 0 AND NOT a.attisdropped;

  IF still_here IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: the generated mirrors are back (%). 20261018000000 '
                    'drops them; something re-added them after it ran.', still_here;
  END IF;
  RAISE NOTICE 'PASS: no generated mirrors on alerts or profiles';
END $$;

-- The geography itself must of course still be there and still readable.
DO $$
DECLARE got TEXT;
BEGIN
  UPDATE public.alerts
     SET geo_lga = 'JOS NORTH', geo_ward = 'ABBA NA SHEHU', geo_pu = 'BAUCHI ROAD I'
   WHERE id = 'eeee0000-0000-4000-8000-00000000e001';

  SELECT geo_lga || '/' || geo_ward || '/' || geo_pu INTO got FROM public.alerts
   WHERE id = 'eeee0000-0000-4000-8000-00000000e001';
  IF got <> 'JOS NORTH/ABBA NA SHEHU/BAUCHI ROAD I' THEN
    RAISE EXCEPTION 'FAIL: the geo_* columns do not hold what was written — %', got;
  END IF;
  RAISE NOTICE 'PASS: geo_lga/geo_ward/geo_pu are the single place the geography lives';
END $$;

-- ── 3. `category` is the only generated column on alerts ────────────────────
--
-- Which settles the 428C9 ordinal question by removing it rather than by
-- matching it. With the mirrors gone there is exactly one generated column on
-- alerts, so the error names `category` on production and here — not because the
-- ordinals were made to agree, which is impossible (attribute numbers are
-- assigned when a column is added), but because there is nothing else it could
-- name.
--
-- The defect is still closed primarily by
-- scripts/check_generated_column_inserts.py refusing a column-list-less insert
-- outright. This is the belt to that braces.
DO $$
DECLARE gen TEXT;
BEGIN
  SELECT string_agg(a.attname, ', ' ORDER BY a.attnum) INTO gen
    FROM pg_attribute a
    JOIN pg_class c     ON c.oid = a.attrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relname = 'alerts'
     AND a.attgenerated <> '' AND a.attnum > 0 AND NOT a.attisdropped;

  IF gen <> 'category' THEN
    RAISE EXCEPTION 'FAIL: expected `category` to be the only generated column '
                    'on alerts, found: %', coalesce(gen, '(none)');
  END IF;
  RAISE NOTICE 'PASS: category is the only generated column on alerts';
END $$;

-- ── 4. The two uncalled functions are gone ──────────────────────────────────
--
-- is_hq_or_admin() and is_responder() came from v5 and lost their only callers
-- when 20260813 dropped the v5-era policies. 20261017000000 recorded them as
-- known differences rather than copying dead SECURITY DEFINER functions into the
-- canonical schema; 20261018000000 removes them from production instead.
DO $$
DECLARE still_here TEXT;
BEGIN
  SELECT string_agg(fn, ', ') INTO still_here
    FROM (VALUES ('is_hq_or_admin'), ('is_responder')) AS v(fn)
   WHERE to_regprocedure('public.' || fn || '()') IS NOT NULL;

  IF still_here IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: % still exists', still_here;
  END IF;
  RAISE NOTICE 'PASS: is_hq_or_admin() and is_responder() are gone';
END $$;

-- ── 4b. profiles keeps the columns that are NOT mirrors ─────────────────────
--
-- sector_id is a plain column from the same era, and the console carried a
-- comment claiming it is not a column at all. It stays: unlike the mirrors it
-- can hold a value nothing else holds.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_attribute a
      JOIN pg_class c     ON c.oid = a.attrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND c.relname = 'profiles'
       AND a.attname = 'sector_id' AND a.attnum > 0 AND NOT a.attisdropped
  ) THEN
    RAISE EXCEPTION 'FAIL: profiles.sector_id was dropped — only the generated '
                    'mirrors were meant to go';
  END IF;
  RAISE NOTICE 'PASS: profiles.sector_id survives; only the mirrors were dropped';
END $$;

-- ── 5. normalise_lga compares the way production compares ───────────────────
DO $$
BEGIN
  IF public.normalise_lga('  Jos North ') <> public.normalise_lga('JOS NORTH') THEN
    RAISE EXCEPTION 'FAIL: normalise_lga does not fold case and whitespace';
  END IF;
  -- Deliberately NOT geo_key(): that one also folds trailing Roman numerals,
  -- and conflating the two would silently change which wards match.
  IF public.normalise_lga('GINDIRI  I') = public.normalise_lga('GINDIRI  1') THEN
    RAISE EXCEPTION 'FAIL: normalise_lga folded a numeral — that is geo_key''s '
                    'job and the two must not converge';
  END IF;
  RAISE NOTICE 'PASS: normalise_lga folds case and space, and nothing else';
END $$;

-- ── 6. The telemetry policy exists, and is not TO PUBLIC ────────────────────
DO $$
DECLARE roles_on_it TEXT;
BEGIN
  SELECT roles::text INTO roles_on_it
    FROM pg_policies
   WHERE schemaname = 'public' AND tablename = 'telemetry'
     AND policyname = 'telemetry_select_geo_lga_scoped';

  IF roles_on_it IS NULL THEN
    RAISE EXCEPTION 'FAIL: telemetry_select_geo_lga_scoped does not exist, so '
                    'this database refuses reads production allows';
  END IF;
  IF roles_on_it <> '{authenticated}' THEN
    RAISE EXCEPTION 'FAIL: telemetry_select_geo_lga_scoped is %, expected '
                    '{authenticated}. A missing TO clause records as {public}, '
                    'and PUBLIC includes anon.', roles_on_it;
  END IF;
  RAISE NOTICE 'PASS: telemetry_select_geo_lga_scoped exists, TO authenticated';
END $$;

-- ── Clean up ────────────────────────────────────────────────────────────────
DELETE FROM public.alerts WHERE id = 'eeee0000-0000-4000-8000-00000000e001';

DO $$ BEGIN RAISE NOTICE 'ALL SCHEMA CONVERGENCE CHECKS PASSED'; END $$;
