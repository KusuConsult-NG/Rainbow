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
-- 20261023000000_one_table_one_shape.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261023000000_one_table_one_shape.sql'; END $apply$;

-- ============================================================================
-- OPERATION RAINBOW — ONE TABLE, ONE SHAPE
--
-- Three of the four agency tables are created TWICE in this history, by two
-- files with different column lists and `CREATE TABLE IF NOT EXISTS` on both.
-- So the second one is a no-op, and WHICH COLUMNS A DATABASE HAS DEPENDS ON
-- WHICH FILE RAN FIRST:
--
--   agency_notifications   20260722000000_v3_telemetry_geofence   10 columns
--                          20260812000000_agency_tables            7 columns
--   agency_action_reports  20260723000000_v4_mesh_broadcast       14 columns
--                          20260812000000_agency_tables           15 columns
--   agency_deployments     20260723000000_v4_mesh_broadcast       10 columns
--                          20260812000000_agency_tables           10 columns
--
-- The v2–v6 era was applied to PRODUCTION by hand and written down afterwards,
-- and `verify_rls_migration.sh`, `bootstrap_staging.sql` and
-- `apply_all_migrations.sql` all exclude it — it cannot be replayed (v2 calls
-- auth.jwt() before the shim defines it). So the split is exact and permanent:
--
--   * on PRODUCTION the v3/v4 definitions ran first, and the tables carry
--     `detail`, `sent_by`, `target_lga`, `acknowledged_at` and `resolved_at`
--     but NOT `created_at`;
--   * on every database this repository can build, only 20260812 runs, and the
--     tables carry `created_at` but NONE of those five.
--
-- Two shapes, differing in both directions, with nothing saying so. The local
-- Supabase stand-in builds its column set by UNIONING every definition it
-- finds, which is right for a fake that must not refuse a column production
-- has — and it means the harness accepts a column that exists on neither
-- database, so nothing in the run could report this.
--
-- ## What it cost
--
-- `/api/notify-agency` is the handover: HQ escalates an incident to the Police,
-- the Army or the DSS, and the route sends an SMS and/or posts a webhook, then
-- records one row per leg. Its own comment:
--
--     Every leg, including the skipped ones: this table is the only durable
--     record of whether an agency was told, and a row set that omits the
--     channels nobody used cannot answer that question later.
--
-- It writes `method` and `status` — and drops `result.detail`, which is the
-- only thing that says WHY: `HTTP 502`, a timeout's message, "no contact
-- configured". The table has that column on production and not on staging, so
-- writing it would have worked in production and failed everywhere else, and
-- the route's error path is a `console.error` in a server log nobody reads.
-- "The Army was not told, and here is what the gateway said" is the whole
-- content of this table, and it was the part being thrown away.
--
-- ## What this migration does
--
-- Adds every column one definition has and the other lacks, so both shapes
-- converge on the union. `ADD COLUMN IF NOT EXISTS` throughout: on production
-- this adds `created_at` to three tables and nothing else; on a repo-built
-- database it adds the other five.
--
-- `created_at` is BACKFILLED from the column that records the real time —
-- `sent_at`, `submitted_at`, `deployed_at` — rather than stamped with this
-- migration's clock. A delivery log whose timestamps all read "the day we
-- fixed the schema" is worse than one with a null: the null is honest.
-- ============================================================================

BEGIN;

-- ── agency_notifications: the delivery log of a handover ────────────────────
ALTER TABLE public.agency_notifications
  ADD COLUMN IF NOT EXISTS detail          TEXT,
  ADD COLUMN IF NOT EXISTS sent_by         TEXT,
  ADD COLUMN IF NOT EXISTS target_lga      TEXT,
  ADD COLUMN IF NOT EXISTS acknowledged_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS created_at      TIMESTAMPTZ;

UPDATE public.agency_notifications
   SET created_at = sent_at
 WHERE created_at IS NULL;

ALTER TABLE public.agency_notifications
  ALTER COLUMN created_at SET DEFAULT NOW();

COMMENT ON COLUMN public.agency_notifications.detail IS
  'Why this leg ended as it did: the gateway''s response, an exception message, '
  'or the reason a channel was skipped. The route recorded method and status '
  'and dropped this, because the column existed only on production.';

-- ── agency_action_reports: what the agency sent back ───────────────────────
ALTER TABLE public.agency_action_reports
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ;

UPDATE public.agency_action_reports
   SET created_at = submitted_at
 WHERE created_at IS NULL;

ALTER TABLE public.agency_action_reports
  ALTER COLUMN created_at SET DEFAULT NOW();

-- ── agency_deployments: who the agency sent ────────────────────────────────
ALTER TABLE public.agency_deployments
  ADD COLUMN IF NOT EXISTS resolved_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS created_at  TIMESTAMPTZ;

UPDATE public.agency_deployments
   SET created_at = deployed_at
 WHERE created_at IS NULL;

ALTER TABLE public.agency_deployments
  ALTER COLUMN created_at SET DEFAULT NOW();

COMMENT ON COLUMN public.agency_deployments.resolved_at IS
  'When the agency stood its personnel down. Present on production from '
  '20260723000000_v4_mesh_broadcast and absent from the 20260812000000 '
  'definition that any other database applies; nothing reads it yet.';

COMMIT;

