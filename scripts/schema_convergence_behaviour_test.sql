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

-- ── 2. The generated mirrors track geo_* ────────────────────────────────────
--
-- Not "the column exists": that it is GENERATED and follows its source. A plain
-- TEXT column of the same name would satisfy a catalogue check and then drift
-- the first time geo_lga changed.
DO $$
DECLARE got TEXT;
BEGIN
  UPDATE public.alerts
     SET geo_lga = 'JOS NORTH', geo_ward = 'ABBA NA SHEHU', geo_pu = 'BAUCHI ROAD I'
   WHERE id = 'eeee0000-0000-4000-8000-00000000e001';

  SELECT lga || '/' || ward || '/' || pu INTO got FROM public.alerts
   WHERE id = 'eeee0000-0000-4000-8000-00000000e001';
  IF got <> 'JOS NORTH/ABBA NA SHEHU/BAUCHI ROAD I' THEN
    RAISE EXCEPTION 'FAIL: the mirrors do not follow geo_* — got %', got;
  END IF;

  -- And they must be unwritable, which is what GENERATED buys over a trigger.
  BEGIN
    EXECUTE 'UPDATE public.alerts SET lga = ''LAGOS'' WHERE id = '
            '''eeee0000-0000-4000-8000-00000000e001''';
    RAISE EXCEPTION 'FAIL: alerts.lga was writable, so it can contradict geo_lga';
  EXCEPTION
    WHEN generated_always THEN NULL;
    WHEN others THEN
      IF SQLSTATE <> '428C9' AND SQLERRM NOT ILIKE '%generated%' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'PASS: alerts.lga/ward/pu mirror geo_* and cannot be written';
END $$;

-- ── 3. `category` is no longer the first generated column ───────────────────
--
-- An INSERT with no column list is refused at the FIRST generated column in
-- ordinal order. Production reported `lga`; a repo-built database reported
-- `category`; the same statement, two different diagnoses.
--
-- This asserts the SET, and prints the ORDER without asserting it, because the
-- order does not converge and cannot: attribute numbers are assigned when a
-- column is added, so the mirrors land after `category` here (33) and before it
-- on production (28–30). Asserting `lga` here would fail; asserting `category`
-- would encode a difference from production as if it were correct.
--
-- The defect itself is closed elsewhere, by
-- scripts/check_generated_column_inserts.py refusing a column-list-less insert
-- outright — so the error is unreachable and the name it would report is moot.
DO $$
DECLARE first_generated TEXT;
BEGIN
  SELECT a.attname INTO first_generated
    FROM pg_attribute a
    JOIN pg_class c     ON c.oid = a.attrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relname = 'alerts'
     AND a.attgenerated <> '' AND a.attnum > 0 AND NOT a.attisdropped
   ORDER BY a.attnum
   LIMIT 1;

  IF first_generated IS NULL THEN
    RAISE EXCEPTION 'FAIL: alerts has no generated column at all';
  END IF;
  RAISE NOTICE 'NOTE: the first generated column on alerts is %, which is the '
               'name a 428C9 error will report here and on production',
               first_generated;

  -- Four, not one: category plus the three mirrors.
  IF (SELECT count(*) FROM pg_attribute a
        JOIN pg_class c     ON c.oid = a.attrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname = 'public' AND c.relname = 'alerts'
         AND a.attgenerated <> '' AND a.attnum > 0 AND NOT a.attisdropped) <> 4 THEN
    RAISE EXCEPTION 'FAIL: expected 4 generated columns on alerts '
                    '(category, lga, ward, pu)';
  END IF;
  RAISE NOTICE 'PASS: alerts carries all four generated columns production has';
END $$;

-- ── 4. profiles.lga / ward / sector_id exist ────────────────────────────────
--
-- The console carried a comment saying these are not columns, and that
-- PostgREST rejected a query naming them. They exist on production; the
-- conclusion was checked against the repository instead of the database.
DO $$
DECLARE missing TEXT;
BEGIN
  SELECT string_agg(want, ', ') INTO missing
    FROM (VALUES ('lga'), ('ward'), ('sector_id')) AS v(want)
   WHERE NOT EXISTS (
     SELECT 1 FROM pg_attribute a
       JOIN pg_class c     ON c.oid = a.attrelid
       JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relname = 'profiles'
        AND a.attname = v.want AND a.attnum > 0 AND NOT a.attisdropped);
  IF missing IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: profiles is missing %', missing;
  END IF;
  RAISE NOTICE 'PASS: profiles.lga, ward and sector_id exist, as on production';
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
