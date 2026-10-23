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
-- 20261026000000_safe_zones_capacity.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261026000000_safe_zones_capacity.sql'; END $apply$;

-- ============================================================================
-- A shelter's capacity, which the app has been reading all along
--
-- `safe_zone_screen.dart` is what a citizen opens to find out where to run. Its
-- card reads:
--
--     capacity: (e['capacity'] as num?)?.toInt() ?? 0,
--     ...
--     if (_selected!.capacity > 0) ...[
--       Text('${sz_capacity}: ${_selected!.capacity} ${sz_persons}')
--
-- `public.safe_zones` was created in phase1_foundation.sql with id, name,
-- description, latitude, longitude, type, geo_lga, geo_ward, is_active and
-- created_at. There is no capacity column, and no migration has ever added
-- one. So the read returned null, the model stored 0, and the `> 0` guard
-- meant the line was never drawn for a real shelter.
--
-- ## Why nobody noticed
--
-- The screen had a fallback. When the query failed — and it threw on a
-- SUCCESSFUL EMPTY RESULT too — it returned three shelters hardcoded in the
-- Dart, with capacities of 500, 250 and 350. Those are the only capacities
-- this app has ever displayed. The fallback is removed in T-74; taking it away
-- is what made the absence visible.
--
-- The schema-drift gate did not catch it either, and could not have: the query
-- is `select()` with no column list, so nothing in the app NAMES `capacity` in
-- a way that could be compared against the schema. It reads a key out of a map
-- that came back, and an absent key is indistinguishable from a null one.
--
-- ## What this adds
--
-- A nullable INTEGER. Nullable on purpose: "we have not recorded how many this
-- holds" is a true and common state for a shelter that has just been added,
-- and it is not the same as zero. The app's `> 0` guard already draws nothing
-- in that case, which is the correct behaviour and now means what it says.
--
-- A CHECK keeps it sane. A negative capacity is not a missing one, and a
-- shelter recorded as holding 2,000,000 people is a typo that would send a
-- commander to the wrong place in an emergency.
--
-- No backfill. There is no honest value to backfill WITH — inventing one here
-- would be the same fault this migration exists to clean up, written in SQL
-- instead of Dart.
--
-- Idempotent: safe to re-run.
-- ============================================================================

ALTER TABLE public.safe_zones
  ADD COLUMN IF NOT EXISTS capacity INTEGER;

DO $capacity_check$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conname = 'safe_zones_capacity_sane'
       AND conrelid = 'public.safe_zones'::regclass
  ) THEN
    ALTER TABLE public.safe_zones
      ADD CONSTRAINT safe_zones_capacity_sane
      CHECK (capacity IS NULL OR (capacity >= 0 AND capacity <= 100000));
  END IF;
END
$capacity_check$;

COMMENT ON COLUMN public.safe_zones.capacity IS
  'How many people this shelter holds. NULL means it has not been recorded, '
  'which is not the same as zero: the app draws the line only when it is set.';

