-- The shelter a fleeing citizen is routed to is 11km away, in another LGA.
--
-- ## What `safe_zones` actually contains
--
-- `safe_zone_screen.dart` shows a citizen where to run and draws a route to the
-- nearest one. It used to invent three shelters in a `catch` block; that was
-- fixed, and the screen now reads this table. `phase1_foundation.sql` fills it
-- with seven rows, and the numbers say where they came from:
--
--   PLATEAU STATE HQ          9.9167, 8.8917   the centroid of Jos, to 4dp —
--                                              the same literal this project
--                                              deleted from ai-triage, where it
--                                              was being written into `alerts`
--                                              as the position of a report with
--                                              no fix
--   BARKIN LADI SAFE POINT    9.5167, 8.9167   9°31'00", 8°55'00"
--   MANGU COMMAND POST        9.7167, 9.0500   9°43'00", 9°03'00"
--
-- Round to the arc-minute is what a gazetteer gives for a TOWN. And the
-- fallback that was deleted had `JOS SOUTH COMMAND HQ` at 9.9285, 8.8921 while
-- this seed has it at 9.8965, 8.8583 — two positions, 3.6km apart, for one
-- place. Neither was measured; that is why they disagree.
--
-- ## Three of them are in the wrong LGA, and that is checkable
--
-- `hq-dashboard-next/src/lib/ward_centroids.ts` holds 207 surveyed ward
-- centroids with an honest radius each, generated from the app's own ward
-- asset. Measured against the LGA each shelter row CLAIMS:
--
--   JOS SOUTH COMMAND HQ       11.24 km from the nearest JOS SOUTH ward
--                              centroid (GIRING, r=1.7km) — 9.6km outside it.
--                              The position is in Jos North.
--   MANGU COMMAND POST          9.69 km from the nearest MANGU ward centroid
--                              (KADUNU, r=4.2km) — 5.5km outside it. The
--                              position is in Barkin Ladi.
--   JOS EAST TACTICAL OUTPOST   4.59 km from SHERE WEST (r=4.0km) — 635m
--                              outside it. Marginal, and still not inside.
--
-- So a citizen in Jos South, fleeing, is given turn directions to a point
-- eleven kilometres away in a different local government area, labelled as the
-- Jos South command HQ. The other four are at least internally consistent.
--
-- ## What this migration does about it
--
-- It does NOT invent better coordinates. Nobody here has stood at these places,
-- and replacing one guess with another is how there came to be two positions
-- for Jos South Command HQ in the first place.
--
-- Instead:
--
--   * `verified_at` / `verified_by` — the row records whether a person put
--     their name to the position. All seven start unverified, because none was
--     measured. The app can then tell the citizen which it is, the way USSD
--     reports carry `is_confirmed`.
--   * the three whose position contradicts their own LGA are DEACTIVATED, not
--     deleted. `is_active = false` is this table's own mechanism and the
--     citizen screen already filters on it, so the dangerous route stops
--     without destroying a row command may want to correct. They are real
--     places — a police division and two outposts exist — and what is wrong is
--     the number, which only somebody there can fix.
--   * `publish_safe_zone()` / `verify_safe_zone()` / `retire_safe_zone()`, so
--     command can enter a real one and say who confirmed it. There was no way
--     to add or correct a shelter at all before this: the policy to write one
--     has existed since 20260813000000 and nothing has ever called it.
--
-- A database cannot know whether a coordinate is real. What it can insist on is
-- that somebody's id is against it.

-- ── One shelter, one row ────────────────────────────────────────────────────
--
-- The seed ends `ON CONFLICT DO NOTHING` with no conflict target, and the
-- primary key is `gen_random_uuid()`. A generated key never conflicts, so the
-- clause matches nothing and re-running phase1_foundation.sql inserts all seven
-- AGAIN — the citizen screen would list each shelter twice, and route to
-- whichever copy sorted first. Deduplicate before the constraint, oldest kept.

DELETE FROM public.safe_zones z
 WHERE EXISTS (
   SELECT 1 FROM public.safe_zones keep
    WHERE keep.name = z.name
      AND (keep.created_at, keep.id) < (z.created_at, z.id));

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conname = 'safe_zones_name_unique'
       AND conrelid = 'public.safe_zones'::regclass
  ) THEN
    ALTER TABLE public.safe_zones
      ADD CONSTRAINT safe_zones_name_unique UNIQUE (name);
  END IF;
END $$;

-- ── Did anybody stand here? ─────────────────────────────────────────────────

ALTER TABLE public.safe_zones
  ADD COLUMN IF NOT EXISTS verified_at TIMESTAMPTZ;
ALTER TABLE public.safe_zones
  ADD COLUMN IF NOT EXISTS verified_by UUID REFERENCES public.profiles(id);

COMMENT ON COLUMN public.safe_zones.verified_at IS
  'When somebody confirmed this position on the ground. NULL means the '
  'coordinates are a guess and the app must say so before routing anybody.';
COMMENT ON COLUMN public.safe_zones.verified_by IS
  'Who confirmed it. A position with nobody against it is not confirmed.';

-- A position outside Plateau State is a typo or a 0,0, and 0,0 is the Gulf of
-- Guinea — a point this project has already drawn on a map as a shelter. The
-- bounds are the extent of the 207 surveyed ward centroids in
-- hq-dashboard-next/src/lib/ward_centroids.ts (lat 8.4501-10.2802,
-- lon 8.5861-10.4651), rounded outward by a tenth of a degree. They are a
-- BOUND, not a position: no row is ever placed at one.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conname = 'safe_zones_within_plateau'
       AND conrelid = 'public.safe_zones'::regclass
  ) THEN
    ALTER TABLE public.safe_zones
      ADD CONSTRAINT safe_zones_within_plateau CHECK (
        latitude  BETWEEN 8.3 AND 10.4
        AND longitude BETWEEN 8.4 AND 10.6
      ) NOT VALID;
  END IF;
END $$;
-- NOT VALID, then validated separately: on a database whose existing rows
-- somehow fall outside, the ALTER would fail and take the whole migration with
-- it. This way the constraint applies to every new row immediately and the
-- validation of the old ones reports rather than aborts.
DO $$
BEGIN
  ALTER TABLE public.safe_zones VALIDATE CONSTRAINT safe_zones_within_plateau;
EXCEPTION WHEN check_violation THEN
  RAISE WARNING
    'safe_zones holds row(s) outside Plateau State. New rows are now refused; '
    'the existing ones need looking at: select id, name, latitude, longitude '
    'from public.safe_zones where latitude not between 8.3 and 10.4 or '
    'longitude not between 8.4 and 10.6;';
END $$;

-- ── The seven, where they came from, and what is wrong with three ───────────
--
-- Moved here from phase1_foundation.sql so that `verified_at` is named in the
-- same statement as the coordinates. That is what
-- scripts/check_no_invented_coordinates.py now requires of any stored
-- position: in SQL there is no empty state to fall back to and no screen that
-- can tell, so the row itself has to carry its provenance.
--
-- ON CONFLICT (name) now has a target that exists, so this is genuinely
-- idempotent and a production database that already has these seven is
-- untouched by it.

INSERT INTO public.safe_zones
  (name, description, latitude, longitude, type, geo_lga, verified_at)
VALUES
  ('JOS SOUTH COMMAND HQ',      'Primary tactical operations centre',  9.8965, 8.8583, 'COMMAND_HQ', 'JOS SOUTH',   NULL),
  ('BUKURU TACTICAL OUTPOST',   'Forward operating base, Bukuru',      9.7952, 8.8521, 'OUTPOST',    'JOS SOUTH',   NULL),
  ('JOS NORTH POLICE DIVISION', 'Jos North Police Headquarters',       9.9281, 8.8921, 'POLICE',     'JOS NORTH',   NULL),
  ('PLATEAU STATE HQ',          'State Government HQ Command Centre',  9.9167, 8.8917, 'COMMAND_HQ', 'JOS NORTH',   NULL),
  ('JOS EAST TACTICAL OUTPOST', 'Jos East forward operating base',     9.9500, 8.9600, 'OUTPOST',    'JOS EAST',    NULL),
  ('BARKIN LADI SAFE POINT',    'Barkin Ladi civilian safe assembly',  9.5167, 8.9167, 'SAFE_POINT', 'BARKIN LADI', NULL),
  ('MANGU COMMAND POST',        'Mangu LGA tactical command post',     9.7167, 9.0500, 'COMMAND_HQ', 'MANGU',       NULL)
ON CONFLICT (name) DO NOTHING;

-- The three whose position is outside every ward of the LGA they claim. Matched
-- on the exact coordinates as well as the name, so a row command has since
-- corrected is left alone — this must not reach in and switch off a shelter
-- somebody has fixed and verified.
UPDATE public.safe_zones
   SET is_active = false,
       description = description || ' [POSITION NOT CONFIRMED: this point is '
                     || 'outside every surveyed ward of ' || geo_lga
                     || '. Hidden from the citizen app until somebody confirms '
                     || 'where it is. Use publish_safe_zone() to correct it.]'
 WHERE is_active IS NOT false
   AND verified_at IS NULL
   AND (name, latitude, longitude) IN (
     ('JOS SOUTH COMMAND HQ',      9.8965, 8.8583),
     ('JOS EAST TACTICAL OUTPOST', 9.9500, 8.9600),
     ('MANGU COMMAND POST',        9.7167, 9.0500)
   );

-- ── Command can enter a real one ────────────────────────────────────────────
--
-- `safe_zones_write_command` has allowed this since 20260813000000 and nothing
-- has ever written a row — which is why nobody noticed that, until
-- 20261028000000, only 2 of the project's 22 staff accounts satisfied
-- `is_command()` at all.
--
-- These are functions rather than a bare table write so that the position is
-- checked and the actor is recorded in one place, whichever screen calls them.

CREATE OR REPLACE FUNCTION public.publish_safe_zone(
  p_name      TEXT,
  p_latitude  DOUBLE PRECISION,
  p_longitude DOUBLE PRECISION,
  p_type      TEXT DEFAULT 'SAFE_POINT',
  p_geo_lga   TEXT DEFAULT NULL,
  p_geo_ward  TEXT DEFAULT NULL,
  p_capacity  INTEGER DEFAULT NULL,
  p_description TEXT DEFAULT NULL,
  p_verified  BOOLEAN DEFAULT false)
RETURNS public.safe_zones
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE row_out public.safe_zones;
BEGIN
  IF NOT public.is_command() THEN
    RAISE EXCEPTION 'only command may publish a shelter'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF coalesce(btrim(p_name), '') = '' THEN
    RAISE EXCEPTION 'a shelter needs a name somebody can ask directions to';
  END IF;
  IF p_latitude IS NULL OR p_longitude IS NULL THEN
    RAISE EXCEPTION
      'a shelter with no position cannot be routed to. Leave it out rather '
      'than storing a guess';
  END IF;

  INSERT INTO public.safe_zones
    (name, description, latitude, longitude, type, geo_lga, geo_ward,
     capacity, is_active, verified_at, verified_by)
  VALUES
    (btrim(p_name), p_description, p_latitude, p_longitude,
     coalesce(p_type, 'SAFE_POINT'),
     public.normalise_lga(p_geo_lga), p_geo_ward, p_capacity, true,
     -- Verified means a person is saying they know where this is. The caller
     -- has to claim it explicitly; the default is a position nobody has
     -- confirmed, which is what every row in this table was.
     CASE WHEN p_verified THEN NOW() END,
     CASE WHEN p_verified THEN auth.uid() END)
  ON CONFLICT (name) DO UPDATE
     SET description = COALESCE(EXCLUDED.description, public.safe_zones.description),
         latitude    = EXCLUDED.latitude,
         longitude   = EXCLUDED.longitude,
         type        = EXCLUDED.type,
         geo_lga     = EXCLUDED.geo_lga,
         geo_ward    = EXCLUDED.geo_ward,
         capacity    = EXCLUDED.capacity,
         is_active   = true,
         verified_at = EXCLUDED.verified_at,
         verified_by = EXCLUDED.verified_by
  RETURNING * INTO row_out;

  RETURN row_out;
END;
$$;

COMMENT ON FUNCTION public.publish_safe_zone(
  TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT, TEXT, TEXT, INTEGER, TEXT,
  BOOLEAN) IS
  'Adds or corrects a shelter. Command only. A position is unverified unless '
  'the caller claims otherwise, and then their id is stored against it.';

CREATE OR REPLACE FUNCTION public.verify_safe_zone(p_id UUID)
RETURNS public.safe_zones
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE row_out public.safe_zones;
BEGIN
  IF NOT public.is_command() THEN
    RAISE EXCEPTION 'only command may confirm a shelter position'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE public.safe_zones
     SET verified_at = NOW(), verified_by = auth.uid(), is_active = true
   WHERE id = p_id
  RETURNING * INTO row_out;
  IF row_out.id IS NULL THEN
    RAISE EXCEPTION 'no shelter with id %', p_id;
  END IF;
  RETURN row_out;
END;
$$;

COMMENT ON FUNCTION public.verify_safe_zone(UUID) IS
  'Records that this position has been confirmed on the ground, and by whom. '
  'Reactivates a shelter that was hidden for an unconfirmed position.';

CREATE OR REPLACE FUNCTION public.retire_safe_zone(p_id UUID, p_why TEXT DEFAULT NULL)
RETURNS public.safe_zones
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE row_out public.safe_zones;
BEGIN
  IF NOT public.is_command() THEN
    RAISE EXCEPTION 'only command may retire a shelter'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- Deactivated, never deleted. A shelter that was real last month is part of
  -- the record of where people were sent.
  UPDATE public.safe_zones
     SET is_active = false,
         description = CASE
           WHEN coalesce(btrim(p_why), '') = '' THEN description
           ELSE coalesce(description || ' ', '') || '[RETIRED: ' || btrim(p_why) || ']'
         END
   WHERE id = p_id
  RETURNING * INTO row_out;
  IF row_out.id IS NULL THEN
    RAISE EXCEPTION 'no shelter with id %', p_id;
  END IF;
  RETURN row_out;
END;
$$;

COMMENT ON FUNCTION public.retire_safe_zone(UUID, TEXT) IS
  'Hides a shelter from the citizen app without deleting it.';

REVOKE ALL ON FUNCTION public.publish_safe_zone(
  TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT, TEXT, TEXT, INTEGER, TEXT,
  BOOLEAN) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.verify_safe_zone(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.retire_safe_zone(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.publish_safe_zone(
  TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT, TEXT, TEXT, INTEGER, TEXT,
  BOOLEAN) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.verify_safe_zone(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.retire_safe_zone(UUID, TEXT) TO authenticated, service_role;
