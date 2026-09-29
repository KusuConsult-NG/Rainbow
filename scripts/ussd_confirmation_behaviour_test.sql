-- Can a stranger's keystrokes wake a commander without a human deciding?
--
-- USSD is the cheapest way to lure responders to a chosen place: no install, no
-- data, a ₦100 SIM, and the report looks exactly like a real one. The control is
-- not a rate limit — one more SIM defeats that — it is that no TIMER may turn an
-- unconfirmed USSD report into a deployment.
--
-- Asserting the column exists would prove nothing. These checks run the real
-- escalation job against real overdue rows and watch which ones move.
--
-- Run by scripts/verify_rls_migration.sh against a real PostgreSQL.

\set ON_ERROR_STOP on
SET client_min_messages TO NOTICE;

BEGIN;

INSERT INTO auth.users (id, email) VALUES
  ('c0de0000-0000-4000-8000-00000000cd01', 'ussd-citizen@staging.test'),
  ('c0de0000-0000-4000-8000-00000000cd02', 'ussd-ward-jos@staging.test'),
  ('c0de0000-0000-4000-8000-00000000cd03', 'ussd-ward-mangu@staging.test')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles (id, email, full_name, role, geo_lga, geo_ward) VALUES
  ('c0de0000-0000-4000-8000-00000000cd01', 'ussd-citizen@staging.test',
   'USSD Citizen', 'CITIZEN', 'JOS NORTH', 'ABBA NA SHEHU'),
  ('c0de0000-0000-4000-8000-00000000cd02', 'ussd-ward-jos@staging.test',
   'Ward Jos', 'WARD_COMMAND', 'JOS NORTH', 'ABBA NA SHEHU'),
  ('c0de0000-0000-4000-8000-00000000cd03', 'ussd-ward-mangu@staging.test',
   'Ward Mangu', 'WARD_COMMAND', 'MANGU', 'AMPANG WEST')
ON CONFLICT (id) DO UPDATE
  SET role = EXCLUDED.role, geo_lga = EXCLUDED.geo_lga, geo_ward = EXCLUDED.geo_ward;

-- Three incidents, all long overdue at UNIT so the job WANTS to move all three.
-- The only difference is where they came from and whether anybody stood behind
-- them.
INSERT INTO public.alerts
  (id, type, description, status, severity, reported_by,
   geo_lga, geo_ward, arrived_via, reporter_msisdn, caller_may_be_called,
   assigned_tier, tier_assigned_at, acknowledged_at, created_at)
VALUES
  -- Filed over USSD, nobody has confirmed it. Must NOT climb.
  ('c0a10000-0000-4000-8000-00000000ca01', 'Community attack - Armed Invasion',
   'ussd unconfirmed', 'PENDING', 'CRITICAL',
   'c0de0000-0000-4000-8000-00000000cd01', 'JOS NORTH', 'ABBA NA SHEHU',
   'USSD', '+2348030007001', true,
   'UNIT', NOW() - INTERVAL '6 hours', NULL, NOW() - INTERVAL '6 hours'),
  -- Filed over USSD and confirmed by an officer. MUST climb like anything else.
  ('c0a10000-0000-4000-8000-00000000ca02', 'Kidnap - Immediate Abduction',
   'ussd confirmed', 'PENDING', 'CRITICAL',
   'c0de0000-0000-4000-8000-00000000cd01', 'JOS NORTH', 'ABBA NA SHEHU',
   'USSD', '+2348030007002', false,
   'UNIT', NOW() - INTERVAL '6 hours', NULL, NOW() - INTERVAL '6 hours'),
  -- From the app. Unaffected by any of this.
  ('c0a10000-0000-4000-8000-00000000ca03', 'Fire - Building Fire',
   'app report', 'PENDING', 'HIGH',
   'c0de0000-0000-4000-8000-00000000cd01', 'JOS NORTH', 'ABBA NA SHEHU',
   NULL, NULL, NULL,
   'UNIT', NOW() - INTERVAL '6 hours', NULL, NOW() - INTERVAL '6 hours')
ON CONFLICT (id) DO NOTHING;

UPDATE public.alerts
   SET ussd_confirmed_at = NOW() - INTERVAL '5 hours',
       ussd_confirmed_by = 'c0de0000-0000-4000-8000-00000000cd02',
       tier_assigned_at  = NOW() - INTERVAL '5 hours'
 WHERE id = 'c0a10000-0000-4000-8000-00000000ca02';

-- ── The control ────────────────────────────────────────────────────────────

DO $$
DECLARE moved INTEGER; unconfirmed_tier TEXT; confirmed_tier TEXT; app_tier TEXT;
BEGIN
  IF NOT public.awaiting_human_confirmation(
       (SELECT a FROM public.alerts a WHERE a.id = 'c0a10000-0000-4000-8000-00000000ca01')) THEN
    RAISE EXCEPTION 'FAIL: an unconfirmed USSD report is not recognised as awaiting confirmation';
  END IF;
  IF public.awaiting_human_confirmation(
       (SELECT a FROM public.alerts a WHERE a.id = 'c0a10000-0000-4000-8000-00000000ca02')) THEN
    RAISE EXCEPTION 'FAIL: a CONFIRMED USSD report still reads as awaiting confirmation';
  END IF;
  IF public.awaiting_human_confirmation(
       (SELECT a FROM public.alerts a WHERE a.id = 'c0a10000-0000-4000-8000-00000000ca03')) THEN
    RAISE EXCEPTION 'FAIL: an app report reads as awaiting USSD confirmation';
  END IF;
  RAISE NOTICE 'PASS: only an unconfirmed USSD report awaits confirmation';

  SELECT count(*) INTO moved FROM public.escalate_overdue_alerts();

  SELECT assigned_tier INTO unconfirmed_tier FROM public.alerts
   WHERE id = 'c0a10000-0000-4000-8000-00000000ca01';
  SELECT assigned_tier INTO confirmed_tier FROM public.alerts
   WHERE id = 'c0a10000-0000-4000-8000-00000000ca02';
  SELECT assigned_tier INTO app_tier FROM public.alerts
   WHERE id = 'c0a10000-0000-4000-8000-00000000ca03';

  -- THE POINT OF THE WHOLE MIGRATION.
  IF upper(unconfirmed_tier) <> 'UNIT' THEN
    RAISE EXCEPTION 'FAIL: an unconfirmed USSD report climbed to % on a timer, '
                    'with no human having judged it', unconfirmed_tier;
  END IF;
  RAISE NOTICE 'PASS: an unconfirmed USSD report does not climb on a timer';

  IF upper(confirmed_tier) = 'UNIT' THEN
    RAISE EXCEPTION 'FAIL: a CONFIRMED USSD report is stuck at UNIT — confirmation '
                    'must put it back in the ladder, or the control has become a hole';
  END IF;
  RAISE NOTICE 'PASS: a confirmed USSD report climbs like any other incident';

  IF upper(app_tier) = 'UNIT' THEN
    RAISE EXCEPTION 'FAIL: an ordinary app report stopped escalating';
  END IF;
  RAISE NOTICE 'PASS: ordinary reports are untouched by this change';
END $$;

-- The notice for the one that moved is still owed, and the one held back must
-- not have queued anything — a notice for an unconfirmed report would page the
-- commander the hold exists to protect.
DO $$
DECLARE held INTEGER; sent INTEGER;
BEGIN
  SELECT count(*) INTO held FROM public.notification_outbox
   WHERE alert_id = 'c0a10000-0000-4000-8000-00000000ca01';
  SELECT count(*) INTO sent FROM public.notification_outbox
   WHERE alert_id = 'c0a10000-0000-4000-8000-00000000ca02';
  IF held <> 0 THEN
    RAISE EXCEPTION 'FAIL: an unconfirmed USSD report queued % notification(s)', held;
  END IF;
  IF sent = 0 THEN
    RAISE EXCEPTION 'FAIL: the confirmed report escalated without queueing a notice';
  END IF;
  RAISE NOTICE 'PASS: no notice is owed for a report nobody has stood behind';
END $$;

-- The escalation the original function performed must still be intact. A
-- CREATE OR REPLACE in a migration about something else is how a working
-- mechanism gets quietly reverted.
DO $$
DECLARE st TEXT; log JSONB;
BEGIN
  SELECT status, escalation_log INTO st, log FROM public.alerts
   WHERE id = 'c0a10000-0000-4000-8000-00000000ca02';
  IF upper(st) <> 'ESCALATED' THEN
    RAISE EXCEPTION 'FAIL: escalation no longer sets status=ESCALATED (got %)', st;
  END IF;
  IF NOT (log -> jsonb_array_length(log) - 1 ? 'from_tier') THEN
    RAISE EXCEPTION 'FAIL: the escalation log lost its from_tier key: %', log;
  END IF;
  IF (log -> jsonb_array_length(log) - 1 ->> 'reason') <> 'TIMEOUT' THEN
    RAISE EXCEPTION 'FAIL: the escalation log lost reason=TIMEOUT';
  END IF;
  RAISE NOTICE 'PASS: the original escalation behaviour survived the rewrite';
END $$;

-- ── Who may confirm ───────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION pg_temp.as_user(p_uid UUID)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_uid::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
END $$;

INSERT INTO public.alerts
  (id, type, description, status, severity, reported_by,
   geo_lga, geo_ward, arrived_via, reporter_msisdn,
   assigned_tier, tier_assigned_at, created_at)
VALUES
  ('c0a10000-0000-4000-8000-00000000ca04', 'Community attack - Armed Invasion',
   'ussd for confirmation', 'PENDING', 'CRITICAL',
   'c0de0000-0000-4000-8000-00000000cd01', 'JOS NORTH', 'ABBA NA SHEHU',
   'USSD', '+2348030007004',
   'UNIT', NOW() - INTERVAL '10 minutes', NOW() - INTERVAL '10 minutes')
ON CONFLICT (id) DO NOTHING;

DO $$
DECLARE n INTEGER;
BEGIN
  -- A ward commander in MANGU has no part in a JOS NORTH incident.
  PERFORM pg_temp.as_user('c0de0000-0000-4000-8000-00000000cd03');
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM public.confirm_ussd_report(
    'c0a10000-0000-4000-8000-00000000ca04');
  RESET ROLE;
  IF n <> 0 THEN
    RAISE EXCEPTION 'FAIL: an officer outside the command confirmed a USSD report';
  END IF;
  IF (SELECT ussd_confirmed_at FROM public.alerts
       WHERE id = 'c0a10000-0000-4000-8000-00000000ca04') IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: the refused confirmation was written anyway';
  END IF;
  RAISE NOTICE 'PASS: an officer outside the command cannot confirm, and gets no row';
END $$;

DO $$
DECLARE r RECORD; who UUID;
BEGIN
  PERFORM pg_temp.as_user('c0de0000-0000-4000-8000-00000000cd02');
  SET LOCAL ROLE authenticated;
  SELECT * INTO r FROM public.confirm_ussd_report(
    'c0a10000-0000-4000-8000-00000000ca04');
  RESET ROLE;
  IF r.confirmed IS NOT TRUE THEN
    RAISE EXCEPTION 'FAIL: the ward commander of that ward could not confirm';
  END IF;
  SELECT ussd_confirmed_by INTO who FROM public.alerts
   WHERE id = 'c0a10000-0000-4000-8000-00000000ca04';
  IF who <> 'c0de0000-0000-4000-8000-00000000cd02' THEN
    RAISE EXCEPTION 'FAIL: the confirmation did not record WHO stood behind it (%)', who;
  END IF;
  RAISE NOTICE 'PASS: confirmation is attributed to the officer who gave it';
END $$;

DO $$
DECLARE n INTEGER;
BEGIN
  -- Confirming twice must not re-stamp the clock: a second confirmation would
  -- hand anybody a way to keep resetting an incident's escalation timer.
  PERFORM pg_temp.as_user('c0de0000-0000-4000-8000-00000000cd02');
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM public.confirm_ussd_report(
    'c0a10000-0000-4000-8000-00000000ca04');
  RESET ROLE;
  IF n <> 0 THEN
    RAISE EXCEPTION 'FAIL: a second confirmation was accepted';
  END IF;
  RAISE NOTICE 'PASS: confirming twice is refused, so the clock cannot be re-stamped';
END $$;

DO $$
DECLARE n INTEGER;
BEGIN
  -- An app report is not a USSD report and there is nothing to confirm.
  PERFORM pg_temp.as_user('c0de0000-0000-4000-8000-00000000cd02');
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM public.confirm_ussd_report(
    'c0a10000-0000-4000-8000-00000000ca03');
  RESET ROLE;
  IF n <> 0 THEN
    RAISE EXCEPTION 'FAIL: an app report was "confirmed" as a USSD one';
  END IF;
  RAISE NOTICE 'PASS: only a USSD report can be confirmed';
END $$;

-- ── A false report, and what it does to a number's history ─────────────────

DO $$
DECLARE ok BOOLEAN; st TEXT;
BEGIN
  PERFORM pg_temp.as_user('c0de0000-0000-4000-8000-00000000cd02');
  SET LOCAL ROLE authenticated;
  ok := public.mark_false_report('c0a10000-0000-4000-8000-00000000ca04',
                                 'called the number back, nothing happening');
  RESET ROLE;
  IF NOT ok THEN
    RAISE EXCEPTION 'FAIL: an officer could not mark a report false';
  END IF;
  SELECT status INTO st FROM public.alerts
   WHERE id = 'c0a10000-0000-4000-8000-00000000ca04';
  IF st <> 'FALSE_REPORT' THEN
    RAISE EXCEPTION 'FAIL: status is % rather than FALSE_REPORT', st;
  END IF;
  -- Distinct from CANCELLED, which is a reporter standing themselves down and
  -- carries no accusation.
  IF st = 'CANCELLED' THEN
    RAISE EXCEPTION 'FAIL: a false report was recorded as a cancellation';
  END IF;
  RAISE NOTICE 'PASS: an officer can record that a report was untrue';
END $$;

-- ── What the dispatcher is shown ──────────────────────────────────────────
--
-- Its own LGA, ward and category, deliberately used nowhere else in this file.
-- The first version reused JOS NORTH / ABBA NA SHEHU / Community attack and
-- counted 3 corroborators instead of 2, because a fixture created 80 lines
-- earlier for the confirmation checks matched the window too. The function was
-- right and the test was wrong — and a corroboration count that silently picks
-- up unrelated rows is exactly the bug this assertion exists to catch, so the
-- fixture has to be isolated rather than the expectation adjusted.

INSERT INTO public.alerts
  (id, type, description, status, severity, reported_by, geo_lga, geo_ward,
   arrived_via, reporter_msisdn, caller_may_be_called, created_at, tier_assigned_at)
VALUES
  -- Same ward, same category, inside the window, from two OTHER numbers.
  ('c0a10000-0000-4000-8000-00000000cb01', 'Flood - Rising Water',
   'corroborating 1', 'PENDING', 'HIGH', 'c0de0000-0000-4000-8000-00000000cd01',
   'BOKKOS', 'BOKKOS', 'USSD', '+2348030008001', true, NOW(), NOW()),
  ('c0a10000-0000-4000-8000-00000000cb02', 'Flood - Rising Water',
   'corroborating 2', 'PENDING', 'HIGH', 'c0de0000-0000-4000-8000-00000000cd01',
   'BOKKOS', 'BOKKOS', 'USSD', '+2348030008002', true, NOW(), NOW()),
  ('c0a10000-0000-4000-8000-00000000cb03', 'Flood - Rising Water',
   'the one under inspection', 'PENDING', 'HIGH',
   'c0de0000-0000-4000-8000-00000000cd01',
   'BOKKOS', 'BOKKOS', 'USSD', '+2348030008003', true, NOW(), NOW()),
  -- A different ward in the same LGA: must NOT corroborate.
  ('c0a10000-0000-4000-8000-00000000cb04', 'Flood - Rising Water',
   'different ward', 'PENDING', 'HIGH', 'c0de0000-0000-4000-8000-00000000cd01',
   'BOKKOS', 'DAFFO', 'USSD', '+2348030008004', true, NOW(), NOW()),
  -- Same ward, DIFFERENT category, inside the window: a flood and a fire in one
  -- ward are two events, and folding them together would invent corroboration.
  ('c0a10000-0000-4000-8000-00000000cb05', 'Fire - Building Fire',
   'different category', 'PENDING', 'HIGH', 'c0de0000-0000-4000-8000-00000000cd01',
   'BOKKOS', 'BOKKOS', 'USSD', '+2348030008005', true, NOW(), NOW()),
  -- Same ward and category but SIX HOURS ago: outside the window.
  ('c0a10000-0000-4000-8000-00000000cb06', 'Flood - Rising Water',
   'hours earlier', 'PENDING', 'HIGH', 'c0de0000-0000-4000-8000-00000000cd01',
   'BOKKOS', 'BOKKOS', 'USSD', '+2348030008006', true,
   NOW() - INTERVAL '6 hours', NOW() - INTERVAL '6 hours')
ON CONFLICT (id) DO NOTHING;

DO $$
DECLARE c RECORD;
BEGIN
  SELECT * INTO c FROM public.ussd_report_credibility(
    'c0a10000-0000-4000-8000-00000000cb03');

  IF NOT c.first_time_caller THEN
    RAISE EXCEPTION 'FAIL: a number never heard from before is not flagged as such';
  END IF;
  IF c.corroborating_reports <> 2 THEN
    RAISE EXCEPTION 'FAIL: corroborating reports counted % (expected exactly the 2 '
                    'in the same ward, same category, inside the window)',
                    c.corroborating_reports;
  END IF;
  IF c.corroborating_numbers <> 2 THEN
    RAISE EXCEPTION 'FAIL: corroborating NUMBERS counted %', c.corroborating_numbers;
  END IF;
  IF NOT c.callback_offered THEN
    RAISE EXCEPTION 'FAIL: the callback consent was not surfaced';
  END IF;
  RAISE NOTICE 'PASS: corroboration counts the same ward, same category, inside '
               'the window — and nothing else';
END $$;

DO $$
DECLARE c RECORD;
BEGIN
  -- Four reports from ONE number is one person pressing keys, not a village.
  -- Counting reports and numbers separately is what makes that visible.
  INSERT INTO public.alerts
    (id, type, description, status, severity, reported_by, geo_lga, geo_ward,
     arrived_via, reporter_msisdn, created_at, tier_assigned_at)
  VALUES
    ('c0a10000-0000-4000-8000-00000000cc01', 'Infrastructure - Damage',
     'same number again 1', 'PENDING', 'HIGH', 'c0de0000-0000-4000-8000-00000000cd01',
     'MANGU', 'AMPANG WEST', 'USSD', '+2348030009001', NOW(), NOW()),
    ('c0a10000-0000-4000-8000-00000000cc02', 'Infrastructure - Damage',
     'same number again 2', 'PENDING', 'HIGH', 'c0de0000-0000-4000-8000-00000000cd01',
     'MANGU', 'AMPANG WEST', 'USSD', '+2348030009001', NOW(), NOW()),
    ('c0a10000-0000-4000-8000-00000000cc03', 'Infrastructure - Damage',
     'under inspection', 'PENDING', 'HIGH', 'c0de0000-0000-4000-8000-00000000cd01',
     'MANGU', 'AMPANG WEST', 'USSD', '+2348030009002', NOW(), NOW());

  SELECT * INTO c FROM public.ussd_report_credibility(
    'c0a10000-0000-4000-8000-00000000cc03');
  IF c.corroborating_reports <> 2 OR c.corroborating_numbers <> 1 THEN
    RAISE EXCEPTION 'FAIL: two reports from ONE number read as % report(s) from % '
                    'number(s)', c.corroborating_reports, c.corroborating_numbers;
  END IF;
  RAISE NOTICE 'PASS: repeated reports from one number are not mistaken for a village';
END $$;

DO $$
DECLARE c RECORD;
BEGIN
  -- A number with a FALSE_REPORT against it. Without mark_false_report() this
  -- figure could never be anything but zero, and every other signal here would
  -- be guesswork dressed up as evidence.
  INSERT INTO public.alerts
    (id, type, description, status, severity, reported_by, geo_lga, geo_ward,
     arrived_via, reporter_msisdn, created_at, tier_assigned_at)
  VALUES
    ('c0a10000-0000-4000-8000-00000000cd10', 'Kidnap - Immediate Abduction',
     'earlier lie', 'FALSE_REPORT', 'CRITICAL', 'c0de0000-0000-4000-8000-00000000cd01',
     'JOS NORTH', 'ABBA NA SHEHU', 'USSD', '+2348030010001',
     NOW() - INTERVAL '30 days', NOW() - INTERVAL '30 days'),
    ('c0a10000-0000-4000-8000-00000000cd11', 'Kidnap - Immediate Abduction',
     'now', 'PENDING', 'CRITICAL', 'c0de0000-0000-4000-8000-00000000cd01',
     'JOS NORTH', 'ABBA NA SHEHU', 'USSD', '+2348030010001', NOW(), NOW());

  SELECT * INTO c FROM public.ussd_report_credibility(
    'c0a10000-0000-4000-8000-00000000cd11');
  IF c.first_time_caller THEN
    RAISE EXCEPTION 'FAIL: a number with history reads as a first-time caller';
  END IF;
  IF c.caller_false_reports <> 1 THEN
    RAISE EXCEPTION 'FAIL: a prior false report is not counted (got %)',
      c.caller_false_reports;
  END IF;
  IF c.caller_known_days < 29 THEN
    RAISE EXCEPTION 'FAIL: how long the number has been known reads as % days',
      c.caller_known_days;
  END IF;
  RAISE NOTICE 'PASS: a number''s history, including a prior lie, reaches the dispatcher';
END $$;

-- ── The session store is not readable by anyone signed in ─────────────────

DO $$
DECLARE denied BOOLEAN := false;
BEGIN
  -- It holds the MSISDNs of people who reported anonymously. Anonymity that a
  -- table quietly undoes is worse than none, because the reporter believes they
  -- have it.
  PERFORM pg_temp.as_user('c0de0000-0000-4000-8000-00000000cd02');
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM count(*) FROM public.ussd_sessions;
  EXCEPTION WHEN insufficient_privilege THEN denied := true;
  END;
  RESET ROLE;
  IF NOT denied THEN
    RAISE EXCEPTION 'FAIL: a signed-in staff account can read ussd_sessions';
  END IF;
  RAISE NOTICE 'PASS: nobody signed in from a phone or a browser can read the sessions';
END $$;

ROLLBACK;
