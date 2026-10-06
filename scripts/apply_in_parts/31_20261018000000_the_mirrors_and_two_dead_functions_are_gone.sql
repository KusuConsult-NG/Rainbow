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
-- 20261018000000_the_mirrors_and_two_dead_functions_are_gone.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261018000000_the_mirrors_and_two_dead_functions_are_gone.sql'; END $apply$;

-- ============================================================================
-- Converge DOWNWARD: drop the generated mirrors and the two uncalled functions
--
-- 20261017000000 brought the hand-applied v2–v6 era into the migration history
-- so that production and a repo-built database agree. It converged UPWARD —
-- adding to the repository what production happened to have — and said so:
--
--   > Converging DOWNWARD … gives a smaller schema and removes the ordinal
--   > hazard outright. It is not done here because dropping columns from a live
--   > emergency database on the strength of "nothing in this repository reads
--   > them" is not a call to make on a migration's own authority.
--
-- It has now been made. This drops them.
--
--   alerts.lga, alerts.ward, alerts.pu        GENERATED mirrors of geo_*
--   profiles.lga, profiles.ward               GENERATED mirrors of geo_*
--   public.is_hq_or_admin()                   no callers
--   public.is_responder()                     no callers
--
-- ## Why this loses nothing
--
-- All five columns are `GENERATED ALWAYS AS (geo_x) STORED`. They hold no
-- information of their own — every value is `geo_lga`, `geo_ward` or `geo_pu`
-- copied verbatim. Dropping them destroys no data that is not still sitting in
-- the column beside it, and re-adding them is one ALTER if anything turns out to
-- want them.
--
-- The two functions were last called by the v5-era policies, and
-- 20260813000000_rls_least_privilege.sql drops all of those by name. Checked
-- file against file: nothing in any migration this repository applies references
-- either one.
--
-- ## Why this is safe to run, and what it will refuse to do
--
-- Every drop is RESTRICT — PostgreSQL's default, stated here because it is the
-- whole safety argument and `CASCADE` is one word away. RESTRICT means that if
-- anything at all depends on one of these — a view, an index, a policy, another
-- function — the drop FAILS and this migration aborts. CASCADE would succeed by
-- silently deleting that dependent, which on a database whose policies decide
-- who may read a kidnapping report is not a trade worth making.
--
-- Each drop is attempted in its own sub-transaction so that a refusal is
-- reported with the object's name and the migration stops, rather than leaving
-- the schema half-converged.
--
-- ## The risk that is NOT closed by this file
--
-- The legacy Firebase deployment. Two Cloud Functions still answer on public
-- URLs (finding C-6), nobody has confirmed what they read, and they are
-- Firebase-era code from exactly the period that created these columns — v2's
-- own comment calls them "shorthand aliases used by some Flutter queries".
--
-- If one of them selects `lga`, it will break: PostgREST rejects a query naming
-- a column that does not exist **in full**, so the function gets an error rather
-- than a row with a missing field. That is a real possibility and this migration
-- cannot test it from here.
--
-- It is also, on the evidence, an acceptable one: those functions are orphaned,
-- fire against a datastore nothing backs, and are slated for deletion
-- (README.md "Outstanding" #1). A dead function failing more loudly is not a
-- regression. But it is the reason the earlier migration would not do this
-- unasked, and if the console or the mobile app ever starts rejecting a profiles
-- or alerts query after this is applied, this file is the first place to look.
--
-- Nothing in the current apps reads them — checked across every .dart, .ts and
-- .tsx file, and across every policy, index and view in the migrations.
--
-- ## One wart, deliberately left
--
-- 20261017000000 still ADDs these columns, and this file drops them again. On a
-- fresh database that is an add-then-drop; on a re-paste of
-- scripts/apply_all_migrations.sql it happens once per paste.
--
-- The alternative is editing 20261017000000 to stop adding them, which is
-- rewriting a migration that is already merged and may already have been
-- applied — and if it HAS been applied, editing it leaves the columns on that
-- database for ever, because nothing would then remove them. The add-then-drop
-- is honest about the order the decisions were made in, and it costs one ALTER
-- on `alerts` per paste. Worth collapsing once production has this applied and
-- the history can be flattened safely; not worth the ambiguity before then.
-- ============================================================================

DO $mig$
DECLARE
  target  RECORD;
  dropped INTEGER := 0;
  absent  INTEGER := 0;
BEGIN
  -- ── The generated mirrors ─────────────────────────────────────────────────
  FOR target IN
    SELECT * FROM (VALUES
      ('alerts',   'lga'),
      ('alerts',   'ward'),
      ('alerts',   'pu'),
      ('profiles', 'lga'),
      ('profiles', 'ward')
    ) AS t(tbl, col)
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_attribute a
        JOIN pg_class c     ON c.oid = a.attrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname = 'public' AND c.relname = target.tbl
         AND a.attname = target.col AND a.attnum > 0 AND NOT a.attisdropped
    ) THEN
      absent := absent + 1;
      CONTINUE;
    END IF;

    -- Refuse to drop anything that is NOT a generated mirror. If a column of
    -- this name is holding independent values, it is not the column this
    -- migration is about and dropping it would destroy data.
    IF NOT EXISTS (
      SELECT 1 FROM pg_attribute a
        JOIN pg_class c     ON c.oid = a.attrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname = 'public' AND c.relname = target.tbl
         AND a.attname = target.col AND a.attgenerated = 's'
    ) THEN
      RAISE EXCEPTION
        'public.%.% exists but is NOT a stored generated column. This migration '
        'drops mirrors of geo_*, which hold no information of their own. A plain '
        'column of this name holds data and is not dropped by this file.',
        target.tbl, target.col;
    END IF;

    BEGIN
      EXECUTE format('ALTER TABLE public.%I DROP COLUMN %I RESTRICT',
                     target.tbl, target.col);
      dropped := dropped + 1;
    EXCEPTION
      WHEN dependent_objects_still_exist THEN
        RAISE EXCEPTION
          'public.%.% cannot be dropped: something depends on it (%). Nothing '
          'has been changed. Find the dependent with the query at the bottom of '
          'this file; CASCADE would delete it silently, which is why this is '
          'RESTRICT.', target.tbl, target.col, SQLERRM;
    END;
  END LOOP;

  RAISE NOTICE 'generated mirrors: % dropped, % already absent', dropped, absent;

  -- ── The two uncalled functions ────────────────────────────────────────────
  --
  -- RESTRICT again, and it matters more here: DROP FUNCTION ... CASCADE deletes
  -- every policy whose expression calls the function. If one of these turns out
  -- to still back a policy, this must fail, not quietly remove the policy and
  -- leave the table readable by whatever remains.
  FOR target IN
    SELECT * FROM (VALUES ('is_hq_or_admin'), ('is_responder')) AS t(fn)
  LOOP
    IF to_regprocedure(format('public.%s()', target.fn)) IS NULL THEN
      RAISE NOTICE 'public.%() is already absent', target.fn;
      CONTINUE;
    END IF;
    BEGIN
      EXECUTE format('DROP FUNCTION public.%I() RESTRICT', target.fn);
      RAISE NOTICE 'dropped public.%()', target.fn;
    EXCEPTION
      WHEN dependent_objects_still_exist THEN
        RAISE EXCEPTION
          'public.%() cannot be dropped: something still depends on it (%). '
          'Nothing has been changed — and this is the case the RESTRICT exists '
          'for, because CASCADE here would delete a POLICY.', target.fn, SQLERRM;
    END;
  END LOOP;
END $mig$;

-- ── Report the resulting shape ──────────────────────────────────────────────

DO $$
DECLARE
  gen_cols TEXT;
  leftover INTEGER;
BEGIN
  SELECT string_agg(a.attname, ', ' ORDER BY a.attnum) INTO gen_cols
    FROM pg_attribute a
    JOIN pg_class c     ON c.oid = a.attrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relname = 'alerts'
     AND a.attgenerated <> '' AND a.attnum > 0 AND NOT a.attisdropped;

  SELECT count(*) INTO leftover
    FROM pg_attribute a
    JOIN pg_class c     ON c.oid = a.attrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public'
     AND ((c.relname = 'alerts'   AND a.attname IN ('lga','ward','pu'))
       OR (c.relname = 'profiles' AND a.attname IN ('lga','ward')))
     AND a.attnum > 0 AND NOT a.attisdropped;

  IF leftover <> 0 THEN
    RAISE EXCEPTION 'convergence incomplete: % mirror column(s) remain', leftover;
  END IF;

  RAISE NOTICE 'alerts generated columns now: %', coalesce(gen_cols, '(none)');
  RAISE NOTICE 'the mirrors are gone; geo_lga, geo_ward and geo_pu are the only '
               'place the geography lives, which is what every app already reads';
END $$;

-- ── If a drop above was refused, this names the dependent ───────────────────
--
-- Read-only. Run it, read what comes back, and decide whether the dependent
-- should be removed first or whether the column should stay.
--
--   SELECT DISTINCT
--          dependent.relname     AS dependent_object,
--          dependent.relkind     AS kind,   -- r table, v view, i index, m matview
--          a.attname             AS our_column
--     FROM pg_depend d
--     JOIN pg_rewrite r      ON r.oid = d.objid
--     JOIN pg_class dependent ON dependent.oid = r.ev_class
--     JOIN pg_attribute a    ON a.attrelid = d.refobjid AND a.attnum = d.refobjsubid
--     JOIN pg_class ours     ON ours.oid = d.refobjid
--     JOIN pg_namespace n    ON n.oid = ours.relnamespace
--    WHERE n.nspname = 'public'
--      AND ours.relname IN ('alerts', 'profiles')
--      AND a.attname IN ('lga', 'ward', 'pu');
--
-- And for the functions:
--
--   SELECT p.proname, pg_get_functiondef(p.oid)
--     FROM pg_policies pol
--     JOIN pg_proc p ON p.proname IN ('is_hq_or_admin', 'is_responder')
--    WHERE pol.qual ILIKE '%' || p.proname || '%'
--       OR pol.with_check ILIKE '%' || p.proname || '%';



