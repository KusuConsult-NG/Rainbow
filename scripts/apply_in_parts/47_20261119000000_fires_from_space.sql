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
-- 20261119000000_fires_from_space.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261119000000_fires_from_space.sql'; END $apply$;

-- Fires seen from space: NASA FIRMS thermal detections over Plateau.
--
-- Phase 2 of the intelligence layer ("Rainbow Intelligence Layer" draft). The
-- VIIRS instruments on three satellites (Suomi NPP, NOAA-20, NOAA-21) pass over
-- Plateau several times a day and night and report every 375 m pixel hotter
-- than its surroundings. FIRMS publishes those detections within about three
-- hours. A village set alight at night shows up there whether or not anybody
-- in it could raise an alarm.
--
-- ## What this does NOT do on its own
--
-- Raise anything. In one November week NOAA-20 alone reported about 2,000
-- detections in a box around Plateau, 409 of them at night — almost all of it
-- dry-season farm burning. A rule that turned every night fire into an alarm
-- would bury HQ. So a detection here is EVIDENCE:
--
--   * near an open incident, in time and place, it is one more independent
--     source behind that incident (the console's corroboration score);
--   * compared with what a ward normally burns at that time of year, an
--     unusual night is an advisory to HQ (a later migration, once the
--     baseline is built).
--
-- ## Who writes, who reads
--
-- Only the server, with the service role: `POST /api/intel/fires`, called by
-- a scheduler, fetches FIRMS and writes here. No client can insert, change or
-- delete a detection, so nobody can plant a fire or remove one.
--
-- Every staff account may read them, partner-agency liaisons included. They
-- are public satellite data about places, with nothing in them about any
-- person.

CREATE TABLE IF NOT EXISTS public.fire_detections (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Which FIRMS product: VIIRS_SNPP_NRT, VIIRS_NOAA20_NRT, VIIRS_NOAA21_NRT.
  source      TEXT NOT NULL,
  -- The satellite code FIRMS gives the row (N, N20, N21).
  satellite   TEXT NOT NULL,

  latitude    DOUBLE PRECISION NOT NULL CHECK (latitude BETWEEN -90 AND 90),
  longitude   DOUBLE PRECISION NOT NULL CHECK (longitude BETWEEN -180 AND 180),

  -- When the satellite saw it (UTC), from FIRMS' acq_date + acq_time.
  observed_at TIMESTAMPTZ NOT NULL,

  -- FIRMS' own confidence class for VIIRS: low, nominal, high.
  confidence  TEXT NOT NULL CHECK (confidence IN ('low', 'nominal', 'high')),
  -- Fire radiative power, megawatts.
  frp_mw      DOUBLE PRECISION,
  -- D or N, as FIRMS classifies the pass.
  daynight    TEXT NOT NULL CHECK (daynight IN ('D', 'N')),

  -- Resolved by the server from the LGA polygons and the nearest ward
  -- centroid, the same way the app resolves an incident's ward.
  geo_lga     TEXT,
  geo_ward    TEXT,

  ingested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- One satellite, one moment, one pixel: a refetch of the same window must
  -- not double the evidence.
  CONSTRAINT fire_detections_once UNIQUE (satellite, observed_at, latitude, longitude)
);

CREATE INDEX IF NOT EXISTS fire_detections_recent_idx
  ON public.fire_detections (observed_at DESC);

CREATE INDEX IF NOT EXISTS fire_detections_ward_idx
  ON public.fire_detections (geo_lga, geo_ward, observed_at DESC);

COMMENT ON TABLE public.fire_detections IS
  'NASA FIRMS VIIRS thermal detections over Plateau State. Evidence, not '
  'alarms: most are farm burning. Written only by the server.';

-- Each run of the fetch, so the console can say how fresh the fire layer is,
-- and say so honestly when the fetch has stopped.
CREATE TABLE IF NOT EXISTS public.intel_ingest_runs (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  -- What was fetched, e.g. 'FIRMS'.
  feed        TEXT NOT NULL,
  ran_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ok          BOOLEAN NOT NULL,
  -- Rows the feed returned for Plateau, and how many were new.
  seen        INTEGER NOT NULL DEFAULT 0,
  added       INTEGER NOT NULL DEFAULT 0,
  -- Why a failed run failed. Never the key or the URL that carries it.
  error       TEXT
);

CREATE INDEX IF NOT EXISTS intel_ingest_runs_feed_idx
  ON public.intel_ingest_runs (feed, ran_at DESC);

COMMENT ON TABLE public.intel_ingest_runs IS
  'One row per fetch of an outside feed (FIRMS first). The fire layer''s '
  'freshness is the last successful run, not the newest detection.';

-- ── Row level security ──────────────────────────────────────────────────────

ALTER TABLE public.fire_detections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.intel_ingest_runs ENABLE ROW LEVEL SECURITY;

-- Read by staff. No INSERT, UPDATE or DELETE policy: only the service role,
-- which bypasses RLS, writes either table.
DROP POLICY IF EXISTS "fire_detections_select_staff" ON public.fire_detections;
CREATE POLICY "fire_detections_select_staff" ON public.fire_detections
  FOR SELECT TO authenticated
  USING (public.is_staff());

DROP POLICY IF EXISTS "intel_ingest_runs_select_staff" ON public.intel_ingest_runs;
CREATE POLICY "intel_ingest_runs_select_staff" ON public.intel_ingest_runs
  FOR SELECT TO authenticated
  USING (public.is_staff());

REVOKE ALL ON public.fire_detections FROM PUBLIC, anon;
REVOKE ALL ON public.intel_ingest_runs FROM PUBLIC, anon;
GRANT SELECT ON public.fire_detections TO authenticated;
GRANT SELECT ON public.intel_ingest_runs TO authenticated;
GRANT ALL ON public.fire_detections TO service_role;
GRANT ALL ON public.intel_ingest_runs TO service_role;



