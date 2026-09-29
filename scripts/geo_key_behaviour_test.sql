-- Can the officer posted to GINDIRI  1 see the incident filed in GINDIRI  I?
--
-- The app resolves a ward from the GPS centroid asset and writes Roman
-- numerals; officers are posted from the tactical map, which uses Arabic. Four
-- Mangu wards are spelled differently in the two files, and `alert_in_my_area()`
-- compared the columns raw — so row-level security hid every incident in those
-- wards from the one officer whose command it was in, silently.
--
-- Asserting that geo_key() exists would prove nothing. Every check below signs
-- in as a real account through `authenticated` with RLS on.
--
-- Run by scripts/verify_rls_migration.sh against a real PostgreSQL.

\set ON_ERROR_STOP on
SET client_min_messages TO NOTICE;

BEGIN;

-- ── The key itself ─────────────────────────────────────────────────────────

DO $$
BEGIN
  IF public.geo_key('GINDIRI  I') IS DISTINCT FROM public.geo_key('GINDIRI  1') THEN
    RAISE EXCEPTION 'FAIL: GINDIRI  I and GINDIRI  1 do not share a key';
  END IF;
  RAISE NOTICE 'PASS: GINDIRI  I and GINDIRI  1 are the same ward';

  IF public.geo_key('MANGU  II') IS DISTINCT FROM public.geo_key('MANGU  11') THEN
    RAISE EXCEPTION 'FAIL: MANGU  II and MANGU  11 do not share a key';
  END IF;
  RAISE NOTICE 'PASS: MANGU  II and MANGU  11 are the same ward';

  -- Longest numeral first: 'III' must not be read as 'I' then 'II'.
  IF public.geo_key('SOMEWHERE III') IS DISTINCT FROM 'SOMEWHERE 111' THEN
    RAISE EXCEPTION 'FAIL: a trailing III became %', public.geo_key('SOMEWHERE III');
  END IF;
  RAISE NOTICE 'PASS: III is rewritten as 111, not as 1 followed by 11';

  -- Case and whitespace, the part that already worked and must keep working.
  IF public.geo_key('  jos   north ') IS DISTINCT FROM 'JOS NORTH' THEN
    RAISE EXCEPTION 'FAIL: case and whitespace are not normalised: %',
      public.geo_key('  jos   north ');
  END IF;
  RAISE NOTICE 'PASS: case is folded and runs of whitespace collapsed';

  -- Blank is NULL, so "no posting" stays distinguishable from "some posting".
  -- alert_in_my_area() turns on exactly this: a NULL area matches nothing.
  IF public.geo_key('   ') IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: a blank name produced a non-null key';
  END IF;
  IF public.geo_key(NULL) IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: a NULL name produced a non-null key';
  END IF;
  RAISE NOTICE 'PASS: blank and NULL both key to NULL';

  -- A numeral in the MIDDLE of a name is not a trailing numeral.
  IF public.geo_key('IKOT IDEM') IS DISTINCT FROM 'IKOT IDEM' THEN
    RAISE EXCEPTION 'FAIL: an interior I was rewritten: %', public.geo_key('IKOT IDEM');
  END IF;
  -- Nor is a quoted letter, which is how the map spells GYEL 'A' and GYEL 'B'.
  IF public.geo_key('GYEL ''A''') IS DISTINCT FROM 'GYEL ''A''' THEN
    RAISE EXCEPTION 'FAIL: GYEL ''A'' was rewritten: %', public.geo_key('GYEL ''A''');
  END IF;
  RAISE NOTICE 'PASS: only a trailing Roman numeral is rewritten';

  -- Two genuinely different wards must NOT collide. This is the failure
  -- direction that matters: a key too aggressive would give a ward commander
  -- the ward next door, which is the authority leak the scoping migration
  -- exists to close.
  IF public.geo_key('GINDIRI  I') = public.geo_key('GINDIRI  II') THEN
    RAISE EXCEPTION 'FAIL: GINDIRI  I and GINDIRI  II collided';
  END IF;
  IF public.geo_key('NARAGUTA') = public.geo_key('GANGARE') THEN
    RAISE EXCEPTION 'FAIL: two unrelated wards collided';
  END IF;
  -- KADUN / KADUNU are deliberately NOT folded: one letter apart is a question
  -- about Plateau's geography, not a notation difference, and guessing would
  -- hand an officer a ward that may not be theirs.
  IF public.geo_key('KADUN') = public.geo_key('KADUNU') THEN
    RAISE EXCEPTION 'FAIL: KADUN and KADUNU were folded together by guesswork';
  END IF;
  RAISE NOTICE 'PASS: different wards keep different keys';
END $$;

-- ── The cast ───────────────────────────────────────────────────────────────
--
-- A Mangu ward commander posted the way the console posts them — from the
-- tactical map, in Arabic — and an incident filed the way the app files them,
-- from the GPS asset, in Roman.

INSERT INTO auth.users (id, email) VALUES
  ('eeee0000-0000-4000-8000-00000000ee01', 'geokey-citizen@staging.test'),
  ('eeee0000-0000-4000-8000-00000000ee02', 'geokey-ward-gindiri@staging.test'),
  ('eeee0000-0000-4000-8000-00000000ee03', 'geokey-ward-gindiri2@staging.test'),
  ('eeee0000-0000-4000-8000-00000000ee04', 'geokey-unit-mangu@staging.test')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles (id, email, full_name, role, geo_lga, geo_ward, geo_pu) VALUES
  ('eeee0000-0000-4000-8000-00000000ee01', 'geokey-citizen@staging.test',
   'Geokey Citizen',  'CITIZEN',      'MANGU', 'GINDIRI  1', NULL),
  -- Posted from the map: Arabic.
  ('eeee0000-0000-4000-8000-00000000ee02', 'geokey-ward-gindiri@staging.test',
   'Ward Gindiri 1',  'WARD_COMMAND', 'MANGU', 'GINDIRI  1', NULL),
  -- The NEXT ward along, which must stay out of reach.
  ('eeee0000-0000-4000-8000-00000000ee03', 'geokey-ward-gindiri2@staging.test',
   'Ward Gindiri 11', 'WARD_COMMAND', 'MANGU', 'GINDIRI  11', NULL),
  ('eeee0000-0000-4000-8000-00000000ee04', 'geokey-unit-mangu@staging.test',
   'Unit Mangu 1',    'UNIT_COMMAND', 'MANGU', 'MANGU  1',   'KASUWA ALI  1')
ON CONFLICT (id) DO UPDATE
  SET role = EXCLUDED.role, geo_lga = EXCLUDED.geo_lga,
      geo_ward = EXCLUDED.geo_ward, geo_pu = EXCLUDED.geo_pu;

INSERT INTO public.alerts
  (id, type, description, status, severity, reported_by, geo_lga, geo_ward, geo_pu)
VALUES
  -- Filed by the app: Roman. The same ward as ee02's posting.
  ('ffff0000-0000-4000-8000-00000000ff01', 'Kidnap - Immediate Abduction',
   'gindiri i incident', 'OPEN', 'CRITICAL',
   'eeee0000-0000-4000-8000-00000000ee01', 'MANGU', 'GINDIRI  I', NULL),
  -- The ward next door, also in Roman. ee02 must NOT get this one.
  ('ffff0000-0000-4000-8000-00000000ff02', 'Fire - Building Fire',
   'gindiri ii incident', 'OPEN', 'HIGH',
   'eeee0000-0000-4000-8000-00000000ee01', 'MANGU', 'GINDIRI  II', NULL),
  -- A polling unit, for the UNIT branch of the predicate.
  ('ffff0000-0000-4000-8000-00000000ff03', 'Flood - Rising Water',
   'mangu i pu incident', 'OPEN', 'HIGH',
   'eeee0000-0000-4000-8000-00000000ee01', 'MANGU', 'MANGU  I', 'KASUWA ALI  I')
ON CONFLICT (id) DO NOTHING;

CREATE OR REPLACE FUNCTION pg_temp.geokey_visible(p_uid UUID, p_alert UUID)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE n INTEGER;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_uid::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM public.alerts WHERE id = p_alert;
  RESET ROLE;
  RETURN n;
END $$;

-- ── The defect, and the boundary beside it ─────────────────────────────────

DO $$
BEGIN
  -- The bug. Before this migration: 0, for a difference of notation.
  IF pg_temp.geokey_visible('eeee0000-0000-4000-8000-00000000ee02',
                            'ffff0000-0000-4000-8000-00000000ff01') <> 1 THEN
    RAISE EXCEPTION 'FAIL: the commander of GINDIRI  1 cannot see the incident '
                    'filed in GINDIRI  I';
  END IF;
  RAISE NOTICE 'PASS: a ward commander sees the incident their app spelled differently';

  -- And the scoping still holds: the fix must not widen anyone's command.
  IF pg_temp.geokey_visible('eeee0000-0000-4000-8000-00000000ee02',
                            'ffff0000-0000-4000-8000-00000000ff02') <> 0 THEN
    RAISE EXCEPTION 'FAIL: the commander of GINDIRI  1 can read GINDIRI  II';
  END IF;
  RAISE NOTICE 'PASS: the ward next door is still out of reach';

  IF pg_temp.geokey_visible('eeee0000-0000-4000-8000-00000000ee03',
                            'ffff0000-0000-4000-8000-00000000ff02') <> 1 THEN
    RAISE EXCEPTION 'FAIL: the commander of GINDIRI  11 cannot see GINDIRI  II';
  END IF;
  RAISE NOTICE 'PASS: each Gindiri commander sees their own ward and only theirs';

  -- The polling-unit branch reads geo_pu, which diverges the same way.
  IF pg_temp.geokey_visible('eeee0000-0000-4000-8000-00000000ee04',
                            'ffff0000-0000-4000-8000-00000000ff03') <> 1 THEN
    RAISE EXCEPTION 'FAIL: a unit commander posted to KASUWA ALI  1 cannot see '
                    'the incident filed in KASUWA ALI  I';
  END IF;
  RAISE NOTICE 'PASS: polling units are matched on the key too';

  -- A citizen keeps only what they reported, notation or not.
  IF pg_temp.geokey_visible('eeee0000-0000-4000-8000-00000000ee01',
                            'ffff0000-0000-4000-8000-00000000ff01') <> 1 THEN
    RAISE EXCEPTION 'FAIL: a reporter lost their own report';
  END IF;
  RAISE NOTICE 'PASS: a reporter still sees what they reported';
END $$;

-- ── Writing, not just reading ──────────────────────────────────────────────
--
-- The same predicate guards UPDATE, so before this migration the commander of
-- GINDIRI  1 could not resolve, reassign or acknowledge an incident in their
-- own ward either.

DO $$
DECLARE touched INTEGER;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',
                     'eeee0000-0000-4000-8000-00000000ee02', true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  SET LOCAL ROLE authenticated;

  UPDATE public.alerts SET status = 'ACKNOWLEDGED'
   WHERE id = 'ffff0000-0000-4000-8000-00000000ff01';
  GET DIAGNOSTICS touched = ROW_COUNT;
  IF touched <> 1 THEN
    RAISE EXCEPTION 'FAIL: the commander of GINDIRI  1 cannot acknowledge an '
                    'incident in their own ward';
  END IF;

  UPDATE public.alerts SET status = 'RESOLVED'
   WHERE id = 'ffff0000-0000-4000-8000-00000000ff02';
  GET DIAGNOSTICS touched = ROW_COUNT;
  IF touched <> 0 THEN
    RAISE EXCEPTION 'FAIL: the commander of GINDIRI  1 resolved an incident in '
                    'GINDIRI  II';
  END IF;

  RESET ROLE;
  RAISE NOTICE 'PASS: the ward they command is writable, the one next door is not';
END $$;

-- ── Escalation recipients ──────────────────────────────────────────────────
--
-- escalation_push_targets() matched an officer's posting against the queued
-- notice's geography with the same raw comparison, so a WARD escalation in
-- GINDIRI  I reached nobody and the outbox row was recorded — accurately — as
-- having no recipients.

DO $$
DECLARE found INTEGER;
BEGIN
  UPDATE public.profiles
     SET onesignal_player_id = 'player-gindiri-000001'
   WHERE id = 'eeee0000-0000-4000-8000-00000000ee02';

  INSERT INTO public.notification_outbox (alert_id, kind, payload)
  VALUES ('ffff0000-0000-4000-8000-00000000ff01', 'TIER_ESCALATION',
          jsonb_build_object(
            'alert_id',  'ffff0000-0000-4000-8000-00000000ff01',
            'from_tier', 'UNIT',
            'to_tier',   'WARD',
            'geo_lga',   'MANGU',
            -- As the app filed it.
            'geo_ward',  'GINDIRI  I',
            'severity',  'CRITICAL'));

  SELECT count(*) INTO found
    FROM public.escalation_push_targets(
           (SELECT max(id) FROM public.notification_outbox))
   WHERE user_id = 'eeee0000-0000-4000-8000-00000000ee02';

  IF found <> 1 THEN
    RAISE EXCEPTION 'FAIL: a WARD escalation in GINDIRI  I does not reach the '
                    'commander posted to GINDIRI  1 (found %)', found;
  END IF;
  RAISE NOTICE 'PASS: a ward escalation reaches the commander despite the spelling';

  -- And not the ward next door, which has no push subscription here anyway —
  -- so assert on the count for the whole notice, not just one officer.
  SELECT count(*) INTO found
    FROM public.escalation_push_targets(
           (SELECT max(id) FROM public.notification_outbox));
  IF found <> 1 THEN
    RAISE EXCEPTION 'FAIL: a ward escalation addressed % officers, expected 1', found;
  END IF;
  RAISE NOTICE 'PASS: it reaches exactly the one ward it belongs to';
END $$;

ROLLBACK;
