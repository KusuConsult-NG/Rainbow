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
