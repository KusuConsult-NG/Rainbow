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
-- 20261031000000_a_ward_is_not_called_ward.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261031000000_a_ward_is_not_called_ward.sql'; END $apply$;

-- A ward officer posted to "BUKURU WARD" never sees an incident in BUKURU.
--
-- ## What the live project has
--
-- Section 4 of `why_is_the_board_empty.sql` lists the geographies incidents are
-- filed under. The operator's run came back with, among others:
--
--     JOS SOUTH / BUKURU           n incident(s)
--     JOS SOUTH / BUKURU WARD      n incident(s)
--
-- and `BUKURU WARD` appearing under SIX different LGAs.
--
-- `assets/geo/plateau_wards.json` has 207 wards across the 17 LGAs of Plateau
-- State. `BUKURU` is one of them, in JOS SOUTH, and in no other LGA. **Not one
-- of the 207 ward names ends in " WARD", and not one of the 17 LGA names ends
-- in " LGA".** So the suffix is never part of a real name: it is a word somebody
-- typed into a form that already said "Ward".
--
-- ## Why that is not cosmetic
--
-- `alert_in_my_area()` decides whether a staff account sees an incident, and
-- since 20261009000000 it compares place names through `geo_key()`:
--
--     public.geo_key(a.geo_lga) = public.geo_key(p.geo_lga)
--     AND public.geo_key(a.geo_ward) = public.geo_key(p.geo_ward)
--
-- `geo_key` upper-cases, collapses whitespace and rewrites a trailing Roman
-- numeral — which is what it was written for, because the app and the tactical
-- map spell four Mangu wards differently. It does not touch a trailing " WARD".
--
--     geo_key('BUKURU')       -> 'BUKURU'
--     geo_key('BUKURU WARD')  -> 'BUKURU WARD'
--
-- Different keys. So a ward commander posted to `JOS SOUTH / BUKURU WARD` is
-- refused every incident filed at `JOS SOUTH / BUKURU`, and the other way
-- round. Their board is empty and the rows are right there. That is the same
-- failure 20261009000000 fixed for Roman numerals, in the suffix it did not
-- know about — and this time it is both halves of the comparison, because the
-- posting and the report are typed by different people into different forms.
--
-- The six-LGA `BUKURU WARD` is the other half of it: a ward that exists only in
-- Jos South was recorded as the posting of staff in five LGAs that do not have
-- it. Those accounts match no incident under the ward branch at all. That is an
-- operator data problem and not something a migration can fix — but
-- `scripts/which_geography_is_real.sql` now names every such row, which it
-- could not before.
--
-- ## Why stripping the suffix is safe, and not a guess
--
-- Zero of the 207 surveyed ward names end in " WARD" and zero of the 17 LGA
-- names end in " LGA". So this strip cannot merge two distinct real places: it
-- has nothing to collide with. `check_a_ward_name_resolves.py` asserts exactly
-- that against the asset, so the day a ward called "X WARD" is added, CI says
-- so instead of two wards quietly becoming one.
--
-- Only those two tokens, and only trailing. "DISTRICT", "LGC" and the rest are
-- not stripped because none has been observed, and an unobserved strip is a
-- guess with somebody's board on the other end of it.

-- ── The hazard this migration has to handle ─────────────────────────────────
--
-- `geo_key()` is IMMUTABLE and 20261009000000 INDEXES it:
--
--     CREATE INDEX alerts_geo_key_idx
--       ON public.alerts (geo_key(geo_lga), geo_key(geo_ward), geo_key(geo_pu));
--     CREATE INDEX profiles_geo_key_idx ON public.profiles (...);
--
-- IMMUTABLE is a promise that the same input always gives the same output, and
-- PostgreSQL believes it: the index holds values computed under the OLD body and
-- is not rebuilt when the function is replaced. An index scan would then look up
-- 'BUKURU' among keys computed as 'BUKURU WARD' and find nothing — so replacing
-- the function WITHOUT reindexing would leave the bug in place for exactly the
-- queries that use the index, while a sequential scan returned the right answer.
-- Intermittent, by query plan.
--
-- So both indexes are rebuilt below, and the replay asserts the lookup works
-- with `enable_seqscan = off`, which is the only way to prove the index itself
-- carries the new keys rather than the planner having stepped around it.
--
-- ── Rebuild what believed the old body ─────────────────────────────────────

CREATE OR REPLACE FUNCTION public.geo_key(p_name TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = pg_catalog, pg_temp
AS $$
  SELECT nullif(
    -- A trailing WARD or LGA is the word the form already said. Applied LAST,
    -- after the whitespace collapse, so 'BUKURU   WARD' is reduced to
    -- 'BUKURU WARD' before the suffix is looked for; and before nothing, so a
    -- ward genuinely called 'WARD' would be left alone rather than emptied —
    -- the anchor needs a space and at least one character in front of it.
    regexp_replace(
      -- Trailing Roman numerals to Arabic, longest first so 'III' is not read
      -- as 'I' followed by 'II'. Anchored at the end: a ward called
      -- "VICTORIA II" keeps its name and only the numeral is rewritten, and a
      -- ward with an I in the middle of a word is untouched.
      regexp_replace(
        regexp_replace(
          regexp_replace(
            regexp_replace(
              upper(trim(coalesce(p_name, ''))),
              '\s+', ' ', 'g'),
            '(.)\s+(WARD|LGA)$', '\1'),
          '\s+III$', ' 111'),
        '\s+II$', ' 11'),
      '\s+I$', ' 1'),
    '');
$$;

COMMENT ON FUNCTION public.geo_key(TEXT) IS
  'The form two place names are compared in: upper-cased, runs of whitespace '
  'collapsed, a trailing Roman numeral written in the Arabic form the tactical '
  'map uses, and a trailing WARD or LGA dropped. GINDIRI  I and GINDIRI  1 are '
  'the same ward; so are BUKURU and BUKURU WARD. None of the 207 surveyed ward '
  'names ends in WARD and none of the 17 LGA names ends in LGA, so the strip '
  'has no real name to collide with.';

-- ── Rebuild what believed the old body ──────────────────────────────────────
--
-- REINDEX, not DROP and CREATE: it keeps the index definition, the name and the
-- ownership, and it is the statement whose whole purpose is this situation.
-- Wrapped per index so a database that lacks one — a staging database built
-- before 20261009000000 — is not stopped by it.
-- REINDEX, not DROP and CREATE: it keeps the index definition, the name and the
-- ownership, and it is the statement whose whole purpose is this situation.
-- `REINDEX INDEX` is permitted inside a transaction block, unlike REINDEX
-- DATABASE and CONCURRENTLY, so this is safe in the one-paste bundle.
--
-- Each index named in its own statement, beside its own existence test. A loop
-- over an array of names reads better and puts the name and the REINDEX in
-- different statements, where `check_a_ward_name_resolves.py` cannot pair them
-- — and that check is the only thing standing between the next person who
-- replaces an indexed IMMUTABLE function and a bug that is right or wrong by
-- query plan. Written so it is verifiable.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
              WHERE n.nspname = 'public' AND c.relname = 'alerts_geo_key_idx'
                AND c.relkind = 'i') THEN
    EXECUTE 'REINDEX INDEX public.alerts_geo_key_idx';
    RAISE NOTICE 'rebuilt alerts_geo_key_idx, which held keys computed under the old geo_key()';
  ELSE
    RAISE NOTICE 'alerts_geo_key_idx is not on this database; nothing to rebuild';
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
              WHERE n.nspname = 'public' AND c.relname = 'profiles_geo_key_idx'
                AND c.relkind = 'i') THEN
    EXECUTE 'REINDEX INDEX public.profiles_geo_key_idx';
    RAISE NOTICE 'rebuilt profiles_geo_key_idx, which held keys computed under the old geo_key()';
  ELSE
    RAISE NOTICE 'profiles_geo_key_idx is not on this database; nothing to rebuild';
  END IF;
END $$;

-- ── What this just repaired, in rows ────────────────────────────────────────
--
-- Reported rather than asserted: the number is whatever the operator's data
-- holds, and the point is that they see it. A database with none of this is
-- told so, which is also worth knowing.
DO $$
DECLARE
  n_alerts   INTEGER;
  n_profiles INTEGER;
BEGIN
  SELECT count(*) INTO n_alerts FROM public.alerts
   WHERE upper(trim(coalesce(geo_ward, ''))) LIKE '% WARD'
      OR upper(trim(coalesce(geo_lga,  ''))) LIKE '% LGA';
  SELECT count(*) INTO n_profiles FROM public.profiles
   WHERE upper(trim(coalesce(geo_ward, ''))) LIKE '% WARD'
      OR upper(trim(coalesce(geo_lga,  ''))) LIKE '% LGA';

  IF n_alerts = 0 AND n_profiles = 0 THEN
    RAISE NOTICE
      'No incident or posting on this database carries a trailing WARD or LGA.';
  ELSE
    RAISE NOTICE
      '% incident(s) and % posting(s) carry a trailing WARD or LGA. They now '
      'compare equal to the same place without it, so a ward officer posted to '
      '"X WARD" sees incidents filed at "X". Run '
      'scripts/which_geography_is_real.sql for the ones that are still not a '
      'real place at all.', n_alerts, n_profiles;
  END IF;
END $$;

