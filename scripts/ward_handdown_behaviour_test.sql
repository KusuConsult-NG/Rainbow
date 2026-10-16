-- ============================================================================
-- AN LGA COMMANDER HANDS AN INCIDENT ACROSS TO A WARD
-- ============================================================================
--
-- `20261021000000_an_lga_can_hand_an_incident_to_a_ward.sql` added `to_ward`
-- and `alert_delegated_to_my_ward()`. Before it, the chain only climbed:
-- `next_tier()` is UNIT -> WARD -> LGA -> HQ and the escalate sheet offered no
-- choice of target, so an LGA commander who judged that a neighbouring ward
-- should take an incident could assign individual responders but could not give
-- that ward's COMMANDER the incident.
--
-- Its own file rather than an addition to alert_scoping_behaviour_test.sql,
-- because that one runs at an earlier point in the replay — before this
-- migration exists. Added there, the assertions passed for the wrong reason
-- (the LGA clause) and then failed with "function does not exist", which is how
-- this file came to be.
--
--   psql -f scripts/ward_handdown_behaviour_test.sql
--
-- Expects the full migration history. Read-write on its own rows only, inside
-- one transaction that is rolled back.
-- ============================================================================

\set ON_ERROR_STOP on

BEGIN;

INSERT INTO auth.users (id, email) VALUES
  ('eeee0000-0000-4000-8000-00000000ee01', 'wh-lga-jos@staging.test'),
  ('eeee0000-0000-4000-8000-00000000ee02', 'wh-ward-naraguta@staging.test'),
  ('eeee0000-0000-4000-8000-00000000ee03', 'wh-ward-gangare@staging.test'),
  ('eeee0000-0000-4000-8000-00000000ee04', 'wh-ward-naraguta-bokkos@staging.test'),
  ('eeee0000-0000-4000-8000-00000000ee05', 'wh-responder-gangare@staging.test'),
  ('eeee0000-0000-4000-8000-00000000ee06', 'wh-citizen@staging.test')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles (id, email, full_name, role, geo_lga, geo_ward, geo_pu)
VALUES
  ('eeee0000-0000-4000-8000-00000000ee01', 'wh-lga-jos@staging.test',
   'LGA Jos North',  'LGA_COMMAND',  'JOS NORTH', NULL,       NULL),
  ('eeee0000-0000-4000-8000-00000000ee02', 'wh-ward-naraguta@staging.test',
   'Ward Naraguta',  'WARD_COMMAND', 'JOS NORTH', 'NARAGUTA', 'PU-01'),
  ('eeee0000-0000-4000-8000-00000000ee03', 'wh-ward-gangare@staging.test',
   'Ward Gangare',   'WARD_COMMAND', 'JOS NORTH', 'GANGARE',  'PU-07'),
  -- THE SAME WARD NAME, IN ANOTHER LGA. Ward names are not unique across
  -- Plateau's seventeen LGAs, and this account is why the hand-down compares
  -- the LGA as well.
  ('eeee0000-0000-4000-8000-00000000ee04', 'wh-ward-naraguta-bokkos@staging.test',
   'Ward Naraguta B','WARD_COMMAND', 'BOKKOS',    'NARAGUTA', 'PU-03'),
  ('eeee0000-0000-4000-8000-00000000ee05', 'wh-responder-gangare@staging.test',
   'Responder',      'RESPONDER',    'JOS NORTH', 'GANGARE',  'PU-07'),
  ('eeee0000-0000-4000-8000-00000000ee06', 'wh-citizen@staging.test',
   'Citizen',        'CITIZEN',      'MANGU',     'PANYAM',   'PU-11')
ON CONFLICT (id) DO UPDATE
  SET role = EXCLUDED.role, geo_lga = EXCLUDED.geo_lga,
      geo_ward = EXCLUDED.geo_ward, geo_pu = EXCLUDED.geo_pu;

-- The incident is in MANGU. Nobody in Jos North has any part in it by
-- geography, which is what makes the hand-down the only thing that can deliver
-- it — and is the ordinary case, since an incident is handed across a boundary
-- precisely because of where it is.
INSERT INTO public.alerts
  (id, type, description, status, severity, reported_by, geo_lga, geo_ward, geo_pu)
VALUES
  ('ffff0000-0000-4000-8000-00000000ff01', 'INCIDENT', 'Roadblock near the boundary',
   'ESCALATED', 'HIGH', 'eeee0000-0000-4000-8000-00000000ee06',
   'MANGU', 'PANYAM', 'PU-11')
ON CONFLICT (id) DO NOTHING;

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

CREATE OR REPLACE FUNCTION pg_temp.hand_to(p_ward TEXT, p_lga TEXT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE public.alerts
     SET assigned_tier = 'WARD',
         assigned_to = NULL,
         assigned_responders = '{}'::text[],
         escalation_log = jsonb_build_array(
           jsonb_build_object('from_tier', 'LGA', 'to_tier', 'WARD',
                              'to_ward', p_ward, 'to_lga', p_lga))
   WHERE id = 'ffff0000-0000-4000-8000-00000000ff01';
END $$;

DO $$
DECLARE
  lga_jos   UUID := 'eeee0000-0000-4000-8000-00000000ee01';
  naraguta  UUID := 'eeee0000-0000-4000-8000-00000000ee02';
  gangare   UUID := 'eeee0000-0000-4000-8000-00000000ee03';
  nara_bok  UUID := 'eeee0000-0000-4000-8000-00000000ee04';
  responder UUID := 'eeee0000-0000-4000-8000-00000000ee05';
  alert_id  UUID := 'ffff0000-0000-4000-8000-00000000ff01';
BEGIN
  -- ── Handed to NARAGUTA, in JOS NORTH ────────────────────────────────────
  PERFORM pg_temp.hand_to('NARAGUTA', 'JOS NORTH');

  IF pg_temp.visible_to(naraguta, alert_id) <> 1 THEN
    RAISE EXCEPTION 'FAIL: the ward it was handed to cannot see it';
  END IF;
  RAISE NOTICE 'PASS: an incident handed to a ward reaches that ward''s commander';

  IF pg_temp.visible_to(lga_jos, alert_id) <> 1 THEN
    RAISE EXCEPTION 'FAIL: the LGA command that handed it over lost it';
  END IF;
  RAISE NOTICE 'PASS: the LGA command that directed it keeps the incident';

  IF pg_temp.visible_to(nara_bok, alert_id) <> 0 THEN
    RAISE EXCEPTION 'FAIL: a ward of the same name in another LGA was handed '
                    'somebody else''s incident';
  END IF;
  RAISE NOTICE 'PASS: the hand-down needs the LGA to agree, not just the ward';

  -- ── An entry that recorded no LGA ───────────────────────────────────────
  --
  -- Trusted on the ward alone, which is what the Dart side does, so the two
  -- agree about what a row MEANS.
  UPDATE public.alerts
     SET escalation_log = jsonb_build_array(
           jsonb_build_object('from_tier', 'LGA', 'to_tier', 'WARD',
                              'to_ward', 'NARAGUTA'))
   WHERE id = alert_id;

  IF pg_temp.visible_to(naraguta, alert_id) <> 1 THEN
    RAISE EXCEPTION 'FAIL: a hand-down that named no LGA reached nobody';
  END IF;
  RAISE NOTICE 'PASS: a hand-down with no LGA recorded is trusted on the ward';

  -- ── Only the LAST entry counts ──────────────────────────────────────────
  --
  -- No `to_lga` on either entry, so the WARD clause is the only thing that can
  -- grant this. With an LGA recorded, `alert_delegated_to_my_lga()` would grant
  -- every staff account in that LGA — see the next block, which is about
  -- exactly that.
  UPDATE public.alerts
     SET escalation_log = jsonb_build_array(
           jsonb_build_object('to_tier', 'WARD', 'to_ward', 'NARAGUTA'),
           jsonb_build_object('to_tier', 'WARD', 'to_ward', 'GANGARE'))
   WHERE id = alert_id;

  IF pg_temp.visible_to(naraguta, alert_id) <> 0 THEN
    RAISE EXCEPTION 'FAIL: a superseded hand-down still reaches the ward it '
                    'used to name — the log is append-only, so only the last '
                    'entry can be current';
  END IF;
  IF pg_temp.visible_to(gangare, alert_id) <> 1 THEN
    RAISE EXCEPTION 'FAIL: the ward named by the LAST entry cannot see it';
  END IF;
  RAISE NOTICE 'PASS: only the last hand-down counts';

  -- ── THE DATABASE GRANTS THE LGA; THE CLIENT NARROWS TO THE WARD ─────────
  --
  -- A real hand-down carries both names: the LGA commander writes the ward
  -- they are directing and their own LGA. `alert_delegated_to_my_lga()` then
  -- grants every staff account in that LGA, which is what it has always done
  -- and is not changed here — so another ward's commander CAN read the row.
  --
  -- That is deliberate and it is the division of labour: RLS decides access,
  -- and the handset's `alertReaches()` narrows an LGA-wide grant to the ward it
  -- names, so the incident does not appear on every ward commander's feed. The
  -- one place the client is allowed to be stricter than RLS, because it is
  -- narrowing a GROUP grant to the member it names rather than withholding
  -- something addressed to the officer in front of it.
  --
  -- Asserted so that neither side can be "tidied" into the other without a
  -- test saying what was traded.
  PERFORM pg_temp.hand_to('NARAGUTA', 'JOS NORTH');
  IF pg_temp.visible_to(gangare, alert_id) <> 1 THEN
    RAISE EXCEPTION 'FAIL: the LGA clause no longer grants the LGA it names, '
                    'so the client narrowing it is now hiding rows nobody '
                    'granted';
  END IF;
  RAISE NOTICE 'PASS: RLS grants the named LGA; the client narrows to the ward';

  -- ── A responder in the receiving ward ───────────────────────────────────
  --
  -- RLS grants the ward, not only its commander: a responder posted there is
  -- who actually goes. The client narrows further for display; the database
  -- must not be the thing that withholds it.
  IF pg_temp.visible_to(responder, alert_id) <> 1 THEN
    RAISE EXCEPTION 'FAIL: a responder posted in the receiving ward cannot see '
                    'the incident their ward was handed';
  END IF;
  RAISE NOTICE 'PASS: the receiving ward''s responders have it too';

  -- ── And it is not a way past the agency rule ────────────────────────────
  --
  -- `alert_is_ours()` puts the delegation clauses behind
  -- `is_staff() AND NOT is_liaison()`, so a liaison cannot be handed an
  -- incident by ward. Asserted structurally here; with real liaison accounts
  -- in production_readiness_behaviour_test.sql.
  IF (SELECT prosrc FROM pg_proc WHERE proname = 'alert_is_ours')
       NOT LIKE '%NOT public.is_liaison()%' THEN
    RAISE EXCEPTION 'FAIL: alert_is_ours no longer keeps the delegation '
                    'clauses behind NOT is_liaison()';
  END IF;
  RAISE NOTICE 'PASS: a hand-down cannot reach an outside agency';

  -- ── AND IT IS NOT A WAY AROUND THE OVERSIGHT RULE ──────────────────────
  --
  -- `alert_is_ours()` has been replaced twice, and 20261015000000 wrapped it in
  -- a CASE whose first branch is exclusive: a complaint about security
  -- personnel reaches HQ and the complainant only. The first version of
  -- 20261021000000 restated the function from the OLDER generation and dropped
  -- that branch — every client test passed, and
  -- scripts/oversight_behaviour_test.sql caught it.
  --
  -- Asserted here too, structurally, because the next person to add a clause to
  -- this function will copy whichever version they happen to open.
  IF (SELECT prosrc FROM pg_proc WHERE proname = 'alert_is_ours')
       NOT LIKE '%is_oversight_matter%' THEN
    RAISE EXCEPTION 'FAIL: alert_is_ours no longer checks is_oversight_matter '
                    'first, so a complaint about security personnel reaches '
                    'the accused''s own command';
  END IF;
  RAISE NOTICE 'PASS: the oversight branch survived the restatement';

  RAISE NOTICE 'ALL WARD HAND-DOWN ASSERTIONS PASSED';
END $$;

ROLLBACK;
