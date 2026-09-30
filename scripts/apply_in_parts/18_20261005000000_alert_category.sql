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
-- 20261005000000_alert_category.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261005000000_alert_category.sql'; END $apply$;

-- A column the console can sort and filter incidents by.
--
-- ## The problem
--
-- The category a citizen picked was never stored as a category. The app writes
-- `alerts.type` as `'<label> - <subtype>'` — `'Kidnap - Immediate Abduction'`,
-- `'Community attack - Armed Invasion'` — so the ten categories the reporting
-- flow offers exist only as a prefix inside a free-text column. A dispatcher
-- who wants "every kidnapping open right now" has nothing to ask for.
--
-- Filtering that prefix in the browser is not the same thing. The console reads
-- a bounded window of alerts, so a client-side filter searches only what was
-- already loaded and quietly answers from a subset. The question has to be
-- answerable by the database.
--
-- ## Why GENERATED, and not a column the app writes
--
-- The category is not independent information — it is the first field of
-- `type`, and always has been. A writable column would be a second copy of a
-- fact already recorded, and the two would drift: rows written by the SMS
-- bridge, the mesh path and the offline queue all build `type` themselves, and
-- every one of them would have to remember. A row where `type` says Kidnap and
-- `category` says Flood is worse than no column at all.
--
-- A stored generated column cannot drift. It also backfills every historical
-- row as part of this statement, so the existing incidents become sortable
-- without a data migration.
--
-- `split_part` returns the whole string when the separator is absent, which is
-- the wanted behaviour for the types that have no subtype: a panic press is
-- stored as `'PANIC SOS'` and becomes the category `PANIC SOS`, which is
-- exactly how a dispatcher thinks of it.

ALTER TABLE public.alerts
  ADD COLUMN IF NOT EXISTS category TEXT
  GENERATED ALWAYS AS (split_part(type, ' - ', 1)) STORED;

COMMENT ON COLUMN public.alerts.category IS
  'The reporting category, derived from type (the part before " - "). '
  'Generated, never written: type is the single source of truth.';

-- The console asks two questions of this: "what categories are there" for the
-- filter control, and "give me this category" once one is chosen. Both are
-- scoped to open incidents far more often than not.
CREATE INDEX IF NOT EXISTS alerts_category_idx
  ON public.alerts (category);

CREATE INDEX IF NOT EXISTS alerts_category_created_idx
  ON public.alerts (category, created_at DESC);

-- No RLS change. A generated column is part of the row and is covered by the
-- policies already on this table; adding one here would only widen what the
-- existing ones decided.

