-- Does an officer's authority actually end at their command?
--
-- Asserting the policy exists would prove nothing: the previous policy existed
-- too, and granted the whole state. Every check below signs in as a real
-- account, through `authenticated` with RLS on, and asserts what that account
-- can and cannot see and change.
--
-- Run by scripts/verify_rls_migration.sh against a real PostgreSQL.

\set ON_ERROR_STOP on
-- NOTICE, not WARNING: the PASS lines are RAISE NOTICE, and a test whose output
-- is suppressed cannot be told apart from a test that never ran.
SET client_min_messages TO NOTICE;

BEGIN;

-- ── The cast ───────────────────────────────────────────────────────────────
--
-- Two LGAs. JOS NORTH has a ward commander, a unit officer and a responder;
-- MANGU has an incident that none of them has any part in.

INSERT INTO auth.users (id, email) VALUES
  ('aaaa0000-0000-4000-8000-00000000aa01', 'scope-citizen@staging.test'),
  ('aaaa0000-0000-4000-8000-00000000aa02', 'scope-ward-jos@staging.test'),
  ('aaaa0000-0000-4000-8000-00000000aa03', 'scope-lga-jos@staging.test'),
  ('aaaa0000-0000-4000-8000-00000000aa04', 'scope-hq@staging.test'),
  ('aaaa0000-0000-4000-8000-00000000aa05', 'scope-unit-jos@staging.test'),
  ('aaaa0000-0000-4000-8000-00000000aa06', 'scope-responder-jos@staging.test'),
  ('aaaa0000-0000-4000-8000-00000000aa07', 'scope-unposted@staging.test')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles (id, email, full_name, role, geo_lga, geo_ward, geo_pu) VALUES
  ('aaaa0000-0000-4000-8000-00000000aa01', 'scope-citizen@staging.test',
   'Scope Citizen',   'CITIZEN',      'MANGU',     'PANYAM',   'PU-11'),
  ('aaaa0000-0000-4000-8000-00000000aa02', 'scope-ward-jos@staging.test',
   'Ward Jos North',  'WARD_COMMAND', 'JOS NORTH', 'NARAGUTA', 'PU-01'),
  ('aaaa0000-0000-4000-8000-00000000aa03', 'scope-lga-jos@staging.test',
   'LGA Jos North',   'LGA_COMMAND',  'JOS NORTH', NULL,       NULL),
  ('aaaa0000-0000-4000-8000-00000000aa04', 'scope-hq@staging.test',
   'HQ Command',      'HQ_COMMAND',   NULL,        NULL,       NULL),
  ('aaaa0000-0000-4000-8000-00000000aa05', 'scope-unit-jos@staging.test',
   'Unit Jos North',  'UNIT_COMMAND', 'JOS NORTH', 'NARAGUTA', 'PU-01'),
  ('aaaa0000-0000-4000-8000-00000000aa06', 'scope-responder@staging.test',
   'Responder Jos',   'RESPONDER',    'JOS NORTH', 'NARAGUTA', 'PU-02'),
  ('aaaa0000-0000-4000-8000-00000000aa07', 'scope-unposted@staging.test',
   'Unposted Officer','WARD_COMMAND', NULL,        NULL,       NULL)
ON CONFLICT (id) DO UPDATE
  SET role = EXCLUDED.role, geo_lga = EXCLUDED.geo_lga,
      geo_ward = EXCLUDED.geo_ward, geo_pu = EXCLUDED.geo_pu;

INSERT INTO public.alerts
  (id, type, description, status, severity, reported_by, geo_lga, geo_ward, geo_pu)
VALUES
  -- Far away, and nobody in Jos North has any part in it.
  ('bbbb0000-0000-4000-8000-00000000bb01', 'Kidnap - Held Hostage',
   'mangu incident', 'OPEN', 'CRITICAL',
   'aaaa0000-0000-4000-8000-00000000aa01', 'MANGU', 'PANYAM', 'PU-11'),
  -- In the ward commander's own ward.
  ('bbbb0000-0000-4000-8000-00000000bb02', 'Fire - Structure',
   'naraguta incident', 'OPEN', 'HIGH',
   'aaaa0000-0000-4000-8000-00000000aa01', 'JOS NORTH', 'NARAGUTA', 'PU-01'),
  -- Same LGA, a DIFFERENT ward.
  ('bbbb0000-0000-4000-8000-00000000bb03', 'Flood - Rising Water',
   'other ward incident', 'OPEN', 'HIGH',
   'aaaa0000-0000-4000-8000-00000000aa01', 'JOS NORTH', 'GANGARE', 'PU-09'),
  -- No location at all: the UNLOCATED case.
  ('bbbb0000-0000-4000-8000-00000000bb04', 'PANIC SOS',
   'no gps fix', 'OPEN', 'CRITICAL',
   'aaaa0000-0000-4000-8000-00000000aa01', NULL, NULL, NULL)
ON CONFLICT (id) DO NOTHING;

-- Helper: run a count as a given account, with RLS enforced.
--
-- `request.jwt.claim.sub` — singular, dotted — is what the auth.uid() shim in
-- test_rls_migration.sql reads, matching PostgREST's older claim form. The JSON
-- `request.jwt.claims` object is a different setting and leaves auth.uid() NULL,
-- which makes every account look like an anonymous one and every assertion pass
-- or fail for the wrong reason.
CREATE OR REPLACE FUNCTION pg_temp.visible_to(p_uid UUID, p_alert UUID)
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

-- ── A ward commander ───────────────────────────────────────────────────────

DO $$
BEGIN
  IF pg_temp.visible_to('aaaa0000-0000-4000-8000-00000000aa02',
                        'bbbb0000-0000-4000-8000-00000000bb02') <> 1 THEN
    RAISE EXCEPTION 'FAIL: a ward commander cannot see an incident in their own ward';
  END IF;
  RAISE NOTICE 'PASS: a ward commander sees their own ward';

  -- The whole point. This was readable AND writable before.
  IF pg_temp.visible_to('aaaa0000-0000-4000-8000-00000000aa02',
                        'bbbb0000-0000-4000-8000-00000000bb01') <> 0 THEN
    RAISE EXCEPTION 'FAIL: a ward commander in JOS NORTH can read an incident in MANGU';
  END IF;
  RAISE NOTICE 'PASS: a ward commander cannot read another LGA''s incident';

  IF pg_temp.visible_to('aaaa0000-0000-4000-8000-00000000aa02',
                        'bbbb0000-0000-4000-8000-00000000bb03') <> 0 THEN
    RAISE EXCEPTION 'FAIL: a ward commander can read another WARD in their own LGA';
  END IF;
  RAISE NOTICE 'PASS: a ward commander is scoped to their ward, not their LGA';
END $$;

-- ── Writing is refused too, not just reading ───────────────────────────────
--
-- The same predicate guards UPDATE. An officer who cannot see an incident must
-- not be able to resolve it, reassign it or clear its duress flag.

DO $$
DECLARE touched INTEGER;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',
                     'aaaa0000-0000-4000-8000-00000000aa02', true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  SET LOCAL ROLE authenticated;

  UPDATE public.alerts SET status = 'RESOLVED'
   WHERE id = 'bbbb0000-0000-4000-8000-00000000bb01';
  GET DIAGNOSTICS touched = ROW_COUNT;

  RESET ROLE;

  IF touched <> 0 THEN
    RAISE EXCEPTION
      'FAIL: a ward commander resolved an incident 80km outside their command';
  END IF;
  RAISE NOTICE 'PASS: a ward commander cannot resolve another LGA''s incident';
END $$;

-- ── An LGA commander, and HQ ───────────────────────────────────────────────

DO $$
BEGIN
  IF pg_temp.visible_to('aaaa0000-0000-4000-8000-00000000aa03',
                        'bbbb0000-0000-4000-8000-00000000bb03') <> 1 THEN
    RAISE EXCEPTION 'FAIL: an LGA commander cannot see a ward in their own LGA';
  END IF;
  RAISE NOTICE 'PASS: an LGA commander sees every ward in their LGA';

  IF pg_temp.visible_to('aaaa0000-0000-4000-8000-00000000aa03',
                        'bbbb0000-0000-4000-8000-00000000bb01') <> 0 THEN
    RAISE EXCEPTION 'FAIL: an LGA commander can read another LGA''s incident';
  END IF;
  RAISE NOTICE 'PASS: an LGA commander stops at their LGA boundary';

  IF pg_temp.visible_to('aaaa0000-0000-4000-8000-00000000aa04',
                        'bbbb0000-0000-4000-8000-00000000bb01') <> 1 THEN
    RAISE EXCEPTION 'FAIL: HQ cannot see an incident in MANGU';
  END IF;
  RAISE NOTICE 'PASS: HQ still sees the whole state';
END $$;

-- ── A unit officer ─────────────────────────────────────────────────────────

DO $$
BEGIN
  IF pg_temp.visible_to('aaaa0000-0000-4000-8000-00000000aa05',
                        'bbbb0000-0000-4000-8000-00000000bb02') <> 1 THEN
    RAISE EXCEPTION 'FAIL: a unit officer cannot see their own polling unit';
  END IF;
  RAISE NOTICE 'PASS: a unit officer sees their own polling unit';

  IF pg_temp.visible_to('aaaa0000-0000-4000-8000-00000000aa05',
                        'bbbb0000-0000-4000-8000-00000000bb03') <> 0 THEN
    RAISE EXCEPTION 'FAIL: a unit officer can read a different polling unit';
  END IF;
  RAISE NOTICE 'PASS: a unit officer stops at their polling unit';
END $$;

-- ── The unlocated incident must not disappear ──────────────────────────────
--
-- Fails OPEN on purpose. A row with no geo_lga matches nobody's area, so the
-- strict reading would hide an SOS that arrived without a GPS fix from everyone
-- but HQ.

DO $$
BEGIN
  IF pg_temp.visible_to('aaaa0000-0000-4000-8000-00000000aa02',
                        'bbbb0000-0000-4000-8000-00000000bb04') <> 1 THEN
    RAISE EXCEPTION 'FAIL: an SOS with no GPS fix is invisible to a ward commander';
  END IF;
  IF pg_temp.visible_to('aaaa0000-0000-4000-8000-00000000aa05',
                        'bbbb0000-0000-4000-8000-00000000bb04') <> 1 THEN
    RAISE EXCEPTION 'FAIL: an SOS with no GPS fix is invisible to a unit officer';
  END IF;
  RAISE NOTICE 'PASS: an unlocated SOS stays visible to staff rather than vanishing';
END $$;

-- ── The dispatched team, not just the lead ─────────────────────────────────
--
-- dispatchAlert writes assigned_to (lead) AND assigned_responders (team). The
-- old policy mentioned only assigned_to, which did not matter while everyone
-- saw everything. Now it decides whether an officer sent outside their own area
-- can see the incident they were sent to.

DO $$
BEGIN
  -- The Jos North responder is put on the MANGU incident as a team member, but
  -- is NOT the lead.
  UPDATE public.alerts
     SET assigned_to = 'aaaa0000-0000-4000-8000-00000000aa03',
         assigned_responders = ARRAY['aaaa0000-0000-4000-8000-00000000aa06']::text[]
   WHERE id = 'bbbb0000-0000-4000-8000-00000000bb01';

  IF pg_temp.visible_to('aaaa0000-0000-4000-8000-00000000aa06',
                        'bbbb0000-0000-4000-8000-00000000bb01') <> 1 THEN
    RAISE EXCEPTION
      'FAIL: an officer dispatched outside their area cannot see the incident they were sent to';
  END IF;
  RAISE NOTICE 'PASS: every officer on the dispatched team keeps the incident, not just the lead';
END $$;

-- ── A blank posting is the weakest posting, never the strongest ────────────
--
-- profiles.geo_lga is self-writable; only `role` is guarded by the
-- privilege-escalation trigger. If an empty posting meant "everywhere", a ward
-- commander could clear their own LGA and take the state.

DO $$
BEGIN
  IF pg_temp.visible_to('aaaa0000-0000-4000-8000-00000000aa07',
                        'bbbb0000-0000-4000-8000-00000000bb02') <> 0 THEN
    RAISE EXCEPTION
      'FAIL: clearing your own posting grants the state — a privilege escalation';
  END IF;
  RAISE NOTICE 'PASS: an officer with no posting gains nothing by having none';
END $$;

-- ── A delegation reaches the team it was delegated to ──────────────────────
--
-- HQ hands the MANGU incident down to JOS NORTH. geo_lga stays MANGU, because
-- that is where it happened; the target LGA is in the escalation log.

DO $$
BEGIN
  UPDATE public.alerts
     SET assigned_tier = 'LGA',
         assigned_to = NULL,
         assigned_responders = '{}'::text[],
         escalation_log = '[{"from_tier":"HQ","to_tier":"LGA","to_lga":"JOS NORTH"}]'::jsonb
   WHERE id = 'bbbb0000-0000-4000-8000-00000000bb01';

  IF pg_temp.visible_to('aaaa0000-0000-4000-8000-00000000aa03',
                        'bbbb0000-0000-4000-8000-00000000bb01') <> 1 THEN
    RAISE EXCEPTION
      'FAIL: an incident delegated to an LGA is invisible to that LGA''s commander';
  END IF;
  RAISE NOTICE 'PASS: an incident delegated to an LGA reaches that LGA';

  -- And it does not leak to an LGA it was NOT delegated to. The ward commander
  -- of JOS NORTH is in the receiving LGA but a different ward, so the ward rule
  -- still applies to the incident's own geography (MANGU) — they get it via the
  -- delegation clause, which is LGA-level. What must NOT happen is an unrelated
  -- LGA seeing it; there is no third LGA account here, so assert the clause is
  -- keyed on the log rather than granting everyone.
  UPDATE public.alerts
     SET escalation_log = '[{"from_tier":"HQ","to_tier":"LGA","to_lga":"BOKKOS"}]'::jsonb
   WHERE id = 'bbbb0000-0000-4000-8000-00000000bb01';

  IF pg_temp.visible_to('aaaa0000-0000-4000-8000-00000000aa03',
                        'bbbb0000-0000-4000-8000-00000000bb01') <> 0 THEN
    RAISE EXCEPTION
      'FAIL: a delegation to another LGA is visible to an LGA it was not sent to';
  END IF;
  RAISE NOTICE 'PASS: the delegation clause names one LGA, not all of them';
END $$;

-- ── A citizen is unchanged ─────────────────────────────────────────────────

DO $$
BEGIN
  IF pg_temp.visible_to('aaaa0000-0000-4000-8000-00000000aa01',
                        'bbbb0000-0000-4000-8000-00000000bb02') <> 1 THEN
    RAISE EXCEPTION 'FAIL: a citizen cannot see the incident they reported';
  END IF;
  RAISE NOTICE 'PASS: a citizen still sees their own report';
END $$;

ROLLBACK;
