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
-- 20261009000000_ward_names_compared_by_key.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261009000000_ward_names_compared_by_key.sql'; END $apply$;

-- GINDIRI  I and GINDIRI  1 are the same ward.
--
-- ## What was wrong
--
-- The app resolves an incident's ward from `assets/geo/plateau_wards.json` by
-- nearest centroid and writes that name into `alerts.geo_ward`. Officers are
-- posted from `tactical_mapping.dart`, which the console's own map is now
-- generated from. Those two files spell four Mangu wards differently:
--
--     the app WRITES        an officer is POSTED to
--     ─────────────────     ───────────────────────
--     GINDIRI  I            GINDIRI  1
--     GINDIRI  II           GINDIRI  11
--     MANGU  I              MANGU  1
--     MANGU  II             MANGU  11
--
-- Roman numerals in one file, Arabic in the other. `alert_in_my_area()`
-- compares the two columns after upper() and trim(), so for every incident in
-- those four wards:
--
--   * the ward commander posted there is REFUSED the incident, because
--     'GINDIRI  I' <> 'GINDIRI  1'. Row-level security hides an emergency from
--     the one officer whose command it is in.
--   * the console's ward filter cannot select it, because the dropdown is built
--     from the map and offers the other spelling.
--   * `escalation_push_targets()` finds nobody at WARD tier, so the escalation
--     is recorded as having no recipients — correctly, and for a reason that is
--     a typo.
--
-- Nothing errors. The ward simply has no supervision, and the screens agree
-- that everything is in order.
--
-- ## Why this is a key and not a rename
--
-- Renaming one side would need a decision about which spelling INEC blesses,
-- and an UPDATE across existing rows written under the other one. Both
-- spellings are already in the database — the app has been writing Roman
-- numerals since the ward asset landed — so a rename fixes new rows and leaves
-- the old ones orphaned in the opposite direction.
--
-- A comparison key fixes both directions at once and asserts nothing about
-- which name is correct: `geo_key()` collapses the difference, and the names
-- stay exactly as each file writes them.
--
-- The three remaining divergences are NOT handled here, because they are not
-- notation:
--
--     KADUN (GPS)   vs KADUNU (map)    — one letter; plausibly the same ward
--     DAMWAI (GPS)  vs KAMWAI (map)    — one letter; plausibly two wards
--     BWALL (GPS)   — absent from the map entirely
--
-- Folding those together in code would be guessing about Plateau's geography.
-- `scripts/sync_tactical_map.py` reports them for a human to settle.

-- ── The comparison key ──────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.geo_key(p_name TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = pg_catalog, pg_temp
AS $$
  SELECT nullif(
    regexp_replace(
      -- Trailing Roman numerals to Arabic, longest first so 'III' is not read
      -- as 'I' followed by 'II'. Anchored at the end: a ward called
      -- "VICTORIA II" keeps its name and only the numeral is rewritten, and a
      -- ward with an I in the middle of a word is untouched.
      regexp_replace(
        regexp_replace(
          regexp_replace(
            upper(trim(coalesce(p_name, ''))),
            '\s+', ' ', 'g'),
          '\s+III$', ' 111'),
        '\s+II$', ' 11'),
      '\s+I$', ' 1'),
    '');
$$;

COMMENT ON FUNCTION public.geo_key(TEXT) IS
  'The form two place names are compared in: upper-cased, runs of whitespace '
  'collapsed, and a trailing Roman numeral written in the Arabic form the '
  'tactical map uses. GINDIRI  I and GINDIRI  1 are the same ward; the app and '
  'the map spell four Mangu wards differently and RLS compared them raw.';

-- ── Area scoping, on the key ────────────────────────────────────────────────
--
-- Same rules as 20261006000000_alerts_scoped_to_posting.sql, which the header
-- of that file explains at length. Only the comparison changes: geo_key() in
-- place of nullif(upper(trim(...))). Restated in full rather than patched so
-- the whole predicate is readable in one place.

CREATE OR REPLACE FUNCTION public.alert_in_my_area(p_alert public.alerts)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
  WITH me AS (
    SELECT upper(coalesce(role, ''))      AS role,
           public.geo_key(geo_lga)        AS lga,
           public.geo_key(geo_ward)       AS ward,
           public.geo_key(geo_pu)         AS pu
      FROM public.profiles
     WHERE id = auth.uid()
  ),
  it AS (
    SELECT public.geo_key(p_alert.geo_lga)  AS lga,
           public.geo_key(p_alert.geo_ward) AS ward,
           public.geo_key(p_alert.geo_pu)   AS pu
  )
  SELECT CASE
    -- Unlocated incidents fail OPEN: an emergency nobody can see is worse than
    -- one seen too widely.
    WHEN (SELECT lga FROM it) IS NULL THEN true

    -- No posting: no area. geo_lga is self-writable, so blank must never mean
    -- "everywhere".
    WHEN (SELECT lga FROM me) IS NULL THEN false

    WHEN (SELECT role FROM me) LIKE 'WARD%' THEN
      (SELECT lga FROM it) = (SELECT lga FROM me)
      AND (SELECT ward FROM me) IS NOT NULL
      AND (SELECT ward FROM it) = (SELECT ward FROM me)

    WHEN (SELECT role FROM me) LIKE 'UNIT%'
      OR (SELECT role FROM me) LIKE 'POLLING%' THEN
      (SELECT lga FROM it) = (SELECT lga FROM me)
      AND (SELECT pu FROM me) IS NOT NULL
      AND (SELECT pu FROM it) = (SELECT pu FROM me)

    ELSE (SELECT lga FROM it) = (SELECT lga FROM me)
  END;
$$;

CREATE OR REPLACE FUNCTION public.alert_delegated_to_my_lga(p_alert public.alerts)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT COALESCE(
    public.geo_key(
      (p_alert.escalation_log -> jsonb_array_length(p_alert.escalation_log) - 1)
        ->> 'to_lga')
    = (SELECT public.geo_key(geo_lga) FROM public.profiles WHERE id = auth.uid()),
    false
  );
$$;

-- ── Escalation recipients, on the key ───────────────────────────────────────
--
-- 20261008000000_escalation_push_targets.sql matches an officer's posting
-- against the queued notice's geography with the same raw comparison, so a
-- WARD escalation in GINDIRI  I reached nobody and the outbox row was recorded
-- as having no recipients. Same rule, same key.

CREATE OR REPLACE FUNCTION public.escalation_push_targets(p_outbox_id BIGINT)
RETURNS TABLE (user_id UUID, player_id TEXT, role TEXT)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
  WITH notice AS (
    SELECT o.payload
      FROM public.notification_outbox o
     WHERE o.id = p_outbox_id
       AND o.kind = 'TIER_ESCALATION'
  ),
  want AS (
    SELECT upper(coalesce(payload ->> 'to_tier', ''))  AS tier,
           public.geo_key(payload ->> 'geo_lga')       AS lga,
           public.geo_key(payload ->> 'geo_ward')      AS ward,
           public.geo_key(payload ->> 'geo_pu')        AS pu
      FROM notice
  )
  SELECT p.id, p.onesignal_player_id, p.role
    FROM public.profiles p, want w
   WHERE p.onesignal_player_id IS NOT NULL
     AND length(p.onesignal_player_id) > 5
     AND upper(coalesce(p.role, '')) = ANY (
           CASE w.tier
             WHEN 'UNIT' THEN ARRAY['UNIT_COMMAND','POLLING_UNIT_OFFICER','POLLING_OFFICER']
             WHEN 'WARD' THEN ARRAY['WARD_COMMAND','WARD_OFFICER']
             WHEN 'LGA'  THEN ARRAY['LGA_COMMAND','LGA_OFFICER']
             WHEN 'HQ'   THEN ARRAY['HQ_COMMAND','HQ_OFFICER','ADMIN']
             -- A tier nobody holds addresses nobody. Failing open here would
             -- page the whole state on a malformed payload.
             ELSE ARRAY[]::TEXT[]
           END
         )
     AND (
       w.tier = 'HQ'
       OR w.lga IS NULL
       OR (
         public.geo_key(p.geo_lga) = w.lga
         AND (w.tier <> 'WARD' OR w.ward IS NULL
              OR public.geo_key(p.geo_ward) = w.ward)
         AND (w.tier <> 'UNIT' OR w.pu IS NULL
              OR public.geo_key(p.geo_pu) = w.pu)
       )
     );
$$;

-- ── Indexes ─────────────────────────────────────────────────────────────────
--
-- alerts_geo_idx indexes the raw columns, which the area test no longer reads.
-- geo_key() is IMMUTABLE so it can be indexed; the raw index is left in place
-- because the console still orders and groups by the unmodified names.

CREATE INDEX IF NOT EXISTS alerts_geo_key_idx
  ON public.alerts (public.geo_key(geo_lga), public.geo_key(geo_ward), public.geo_key(geo_pu));

CREATE INDEX IF NOT EXISTS profiles_geo_key_idx
  ON public.profiles (public.geo_key(geo_lga), public.geo_key(geo_ward), public.geo_key(geo_pu));

REVOKE ALL ON FUNCTION public.geo_key(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.geo_key(TEXT) TO anon, authenticated, service_role;

