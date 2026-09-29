-- What `alerts.category` must actually do.
--
-- The column is STORED GENERATED over `split_part(type, ' - ', 1)`. That choice
-- carries three promises, and each of them is the reason a writable column was
-- rejected. Asserting the column exists would prove none of them.
--
--   1. It is DERIVED — the database computes it, so it can never disagree with
--      `type`, whichever of the four write paths filed the report.
--   2. It is BACKFILLED — every incident already in the table became sortable
--      the moment the migration ran, with no data migration.
--   3. It is UNWRITABLE — an INSERT that tries to set it is refused rather than
--      quietly accepted, which is what stops a second source of truth
--      appearing later.
--
-- Run by scripts/verify_rls_migration.sh against a real PostgreSQL.

\set ON_ERROR_STOP on
-- NOTICE, not WARNING: the PASS lines below are RAISE NOTICE, and a test whose
-- output is suppressed cannot be told apart from a test that never ran.
SET client_min_messages TO NOTICE;

BEGIN;

-- A reporter for the rows below. `profiles.id` references `auth.users`, so the
-- account has to exist there first; a profile row is created by the signup
-- trigger, so it is upserted rather than assumed either way.
INSERT INTO auth.users (id, email, raw_user_meta_data)
VALUES ('cccc3333-0000-4000-8000-0000000000c1',
        'category-test@staging.operationrainbow.test',
        '{"full_name": "Category Test Reporter"}'::jsonb)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles (id, email, full_name, role)
VALUES ('cccc3333-0000-4000-8000-0000000000c1',
        'category-test@staging.operationrainbow.test',
        'Category Test Reporter', 'CITIZEN')
ON CONFLICT (id) DO NOTHING;

-- ── 2. Backfill ────────────────────────────────────────────────────────────
--
-- Inserted BEFORE anything else is asserted, standing in for the incidents
-- that were already in the table when the migration ran. A generated column is
-- computed for existing rows as part of ADD COLUMN, so if this reads NULL the
-- historical board is unsortable and the migration bought nothing.

INSERT INTO public.alerts (id, type, description, status, severity, reported_by)
VALUES
  ('dddd4444-0000-4000-8000-0000000000d1',
   'Kidnap - Immediate Abduction', 'historical row', 'OPEN', 'CRITICAL',
   'cccc3333-0000-4000-8000-0000000000c1'),
  ('dddd4444-0000-4000-8000-0000000000d2',
   'Community attack - Armed Invasion', 'historical row', 'OPEN', 'CRITICAL',
   'cccc3333-0000-4000-8000-0000000000c1'),
  ('dddd4444-0000-4000-8000-0000000000d3',
   'PANIC SOS', 'no subtype', 'OPEN', 'CRITICAL',
   'cccc3333-0000-4000-8000-0000000000c1');

DO $$
DECLARE got TEXT;
BEGIN
  SELECT category INTO got FROM public.alerts
   WHERE id = 'dddd4444-0000-4000-8000-0000000000d1';
  IF got IS DISTINCT FROM 'Kidnap' THEN
    RAISE EXCEPTION 'FAIL: category of a two-part type is %, expected Kidnap', got;
  END IF;
  RAISE NOTICE 'PASS: the category is the part of type before the separator';

  SELECT category INTO got FROM public.alerts
   WHERE id = 'dddd4444-0000-4000-8000-0000000000d2';
  IF got IS DISTINCT FROM 'Community attack' THEN
    RAISE EXCEPTION 'FAIL: a multi-word category came back as %', got;
  END IF;
  RAISE NOTICE 'PASS: a category with a space in it survives intact';

  -- split_part returns the whole string when the separator is absent. A panic
  -- press is stored as 'PANIC SOS' and IS its own category; returning empty
  -- here would file every panic button press as uncategorised.
  SELECT category INTO got FROM public.alerts
   WHERE id = 'dddd4444-0000-4000-8000-0000000000d3';
  IF got IS DISTINCT FROM 'PANIC SOS' THEN
    RAISE EXCEPTION 'FAIL: a type with no subtype gave category %, expected PANIC SOS', got;
  END IF;
  RAISE NOTICE 'PASS: a type with no subtype is kept whole as its own category';
END $$;

-- ── 1. Derived, and cannot drift ───────────────────────────────────────────

DO $$
DECLARE got TEXT;
BEGIN
  UPDATE public.alerts
     SET type = 'Flood - Rising Water'
   WHERE id = 'dddd4444-0000-4000-8000-0000000000d1';

  SELECT category INTO got FROM public.alerts
   WHERE id = 'dddd4444-0000-4000-8000-0000000000d1';
  IF got IS DISTINCT FROM 'Flood' THEN
    RAISE EXCEPTION 'FAIL: type changed but category stayed %, so the two can drift', got;
  END IF;
  RAISE NOTICE 'PASS: changing the type moves the category with it';
END $$;

-- ── 3. Unwritable ──────────────────────────────────────────────────────────
--
-- The whole argument for GENERATED over a column the app writes is that a row
-- where type says Kidnap and category says Flood cannot be created. Prove the
-- database refuses it rather than trusting that no caller will try.

DO $$
BEGIN
  BEGIN
    -- generated-column-insert: deliberate — this statement MUST be refused;
    -- scripts/check_generated_column_inserts.py skips it for that reason.
    INSERT INTO public.alerts (id, type, description, status, severity,
                               reported_by, category)
    VALUES ('dddd4444-0000-4000-8000-0000000000d9',
            'Kidnap - Held Hostage', 'a lying row', 'OPEN', 'CRITICAL',
            'cccc3333-0000-4000-8000-0000000000c1', 'Flood');
    RAISE EXCEPTION
      'FAIL: a caller was allowed to write a category that contradicts type';
  EXCEPTION
    WHEN generated_always THEN
      RAISE NOTICE 'PASS: writing the category directly is refused';
    WHEN others THEN
      IF SQLSTATE = '42601' OR SQLERRM ILIKE '%generated%' THEN
        RAISE NOTICE 'PASS: writing the category directly is refused (%)', SQLSTATE;
      ELSE
        RAISE;
      END IF;
  END;
END $$;

-- ── The query the console actually runs ────────────────────────────────────
--
-- Sorting by category is the point of all of the above. If this cannot be
-- expressed as a plain WHERE, the console is back to filtering a page of rows
-- in the browser and answering from a subset.

DO $$
DECLARE n INTEGER;
BEGIN
  SELECT count(*) INTO n
    FROM public.alerts
   WHERE category = 'Community attack'
     AND status NOT IN ('RESOLVED', 'CANCELLED');
  IF n < 1 THEN
    RAISE EXCEPTION 'FAIL: the database cannot answer "open incidents of one category"';
  END IF;
  RAISE NOTICE 'PASS: the database can be asked for open incidents by category';
END $$;

-- And that the index the console will lean on is actually there.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
     WHERE schemaname = 'public' AND tablename = 'alerts'
       AND indexdef ILIKE '%category%'
  ) THEN
    RAISE EXCEPTION 'FAIL: nothing indexes alerts.category';
  END IF;
  RAISE NOTICE 'PASS: alerts.category is indexed';
END $$;

ROLLBACK;
