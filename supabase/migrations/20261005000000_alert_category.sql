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
