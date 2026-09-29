-- Does a gateway retry raise the same emergency twice?
--
-- A USSD gateway that does not get a reply inside its window re-POSTs the same
-- session with the same input. On a congested network that is normal operation
-- — which is exactly when people report emergencies. If filing is not idempotent
-- per session, one kidnapping becomes four incidents and a dispatcher cannot
-- tell them from four real reports.
--
-- Run by scripts/verify_rls_migration.sh against a real PostgreSQL.

\set ON_ERROR_STOP on
SET client_min_messages TO NOTICE;

BEGIN;

INSERT INTO auth.users (id, email, phone) VALUES
  ('f11e0000-0000-4000-8000-00000000f101', 'ussd-known@staging.test', '+2348031110001')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles (id, email, phone, full_name, role, geo_lga, geo_ward, geo_pu) VALUES
  ('f11e0000-0000-4000-8000-00000000f101', 'ussd-known@staging.test', '+2348031110001',
   'Known Caller', 'CITIZEN', 'JOS NORTH', 'ABBA NA SHEHU', 'BAUCHI ROAD I')
ON CONFLICT (id) DO UPDATE SET phone = EXCLUDED.phone, geo_lga = EXCLUDED.geo_lga;

-- ── Recognising the caller ────────────────────────────────────────────────

DO $$
DECLARE c RECORD; n INTEGER;
BEGIN
  SELECT * INTO c FROM public.ussd_caller('+2348031110001');
  IF c.user_id IS NULL OR c.geo_lga <> 'JOS NORTH' THEN
    RAISE EXCEPTION 'FAIL: a registered number was not recognised';
  END IF;
  RAISE NOTICE 'PASS: a registered number is recognised, with its posting';

  -- The forms a carrier or an app user may present for the SAME SIM. Comparing
  -- raw strings would hand a returning app user the stranger's path — six
  -- keypresses and no posting — while their profile sat right there.
  FOR c IN SELECT * FROM public.ussd_caller('2348031110001') LOOP
    IF c.user_id <> 'f11e0000-0000-4000-8000-00000000f101' THEN
      RAISE EXCEPTION 'FAIL: the no-plus form matched the wrong profile';
    END IF;
  END LOOP;
  SELECT count(*) INTO n FROM public.ussd_caller('2348031110001');
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL: 2348... did not match'; END IF;
  SELECT count(*) INTO n FROM public.ussd_caller('08031110001');
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL: the local 080... form did not match'; END IF;
  SELECT count(*) INTO n FROM public.ussd_caller('+234 803 111 0001');
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL: a spaced form did not match'; END IF;
  RAISE NOTICE 'PASS: +234…, 234…, 080… and a spaced form all find the same SIM';

  SELECT count(*) INTO n FROM public.ussd_caller('+2348039999999');
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL: an unknown number matched somebody'; END IF;
  -- A short or empty MSISDN must match NOBODY. Nine digits of nothing would
  -- otherwise match every profile whose number ends the same way.
  SELECT count(*) INTO n FROM public.ussd_caller('');
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL: an empty MSISDN matched a profile'; END IF;
  SELECT count(*) INTO n FROM public.ussd_caller('0001');
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL: a four-digit fragment matched a profile'; END IF;
  RAISE NOTICE 'PASS: an unknown, empty or too-short number matches nobody';
END $$;

-- ── The reference ────────────────────────────────────────────────────────

DO $$
DECLARE r TEXT; seen TEXT[] := '{}';
BEGIN
  FOR i IN 1..40 LOOP
    r := public.ussd_reference();
    IF r !~ '^R[34679ACDEFGHJKMNPQRTUVWXY]{5}$' THEN
      RAISE EXCEPTION 'FAIL: reference % is not in the expected shape', r;
    END IF;
    -- No character anybody can mishear or misread down a phone line.
    IF r ~ '[01258OILSZB]' THEN
      RAISE EXCEPTION 'FAIL: reference % contains a confusable character', r;
    END IF;
    seen := seen || r;
  END LOOP;
  IF (SELECT count(DISTINCT u) FROM unnest(seen) u) < 38 THEN
    RAISE EXCEPTION 'FAIL: 40 references produced only % distinct values',
      (SELECT count(DISTINCT u) FROM unnest(seen) u);
  END IF;
  RAISE NOTICE 'PASS: references are readable aloud and do not collide';
END $$;

-- ── Filing once ──────────────────────────────────────────────────────────

INSERT INTO public.ussd_sessions (session_id, msisdn, state)
VALUES ('sess-known-001', '+2348031110001', '{}'::jsonb)
ON CONFLICT (session_id) DO NOTHING;

DO $$
DECLARE r RECORD; a RECORD;
BEGIN
  SELECT * INTO r FROM public.ussd_file_report(
    'sess-known-001', '+2348031110001', 'f11e0000-0000-4000-8000-00000000f101',
    'Community attack - Armed Invasion', true, 'JOS NORTH', 'ABBA NA SHEHU', true);

  IF r.reference IS NULL OR r.already_filed THEN
    RAISE EXCEPTION 'FAIL: the first filing reported already_filed=%', r.already_filed;
  END IF;

  SELECT * INTO a FROM public.alerts WHERE id = r.alert_id;
  IF a.arrived_via <> 'USSD' THEN
    RAISE EXCEPTION 'FAIL: arrived_via is % rather than USSD', a.arrived_via;
  END IF;
  IF a.severity <> 'CRITICAL' THEN
    RAISE EXCEPTION 'FAIL: an emergency-branch report is graded %, not CRITICAL', a.severity;
  END IF;
  IF a.reporter_msisdn <> '+2348031110001' THEN
    RAISE EXCEPTION 'FAIL: the carrier-asserted number was not recorded';
  END IF;
  IF NOT a.caller_may_be_called THEN
    RAISE EXCEPTION 'FAIL: the callback consent was not recorded';
  END IF;
  IF a.ussd_confirmed_at IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: a freshly filed report is already confirmed';
  END IF;
  -- The provenance has to be readable without clicking anything.
  IF a.description NOT LIKE '%[USSD]%' OR a.description NOT LIKE '%Not yet confirmed%' THEN
    RAISE EXCEPTION 'FAIL: the description does not say where it came from: %', a.description;
  END IF;
  -- The category the console filters on is generated from `type`, so a USSD
  -- report that skipped the '<category> - <subtype>' shape would be
  -- uncategorised on the board.
  IF a.category IS NULL THEN
    RAISE EXCEPTION 'FAIL: the report has no category, so no filter will select it';
  END IF;
  RAISE NOTICE 'PASS: a filed report carries its provenance, grading and category';
END $$;

-- ── Filing twice: the whole point ────────────────────────────────────────

DO $$
DECLARE first RECORD; again RECORD; n INTEGER;
BEGIN
  SELECT public_reference, id INTO first FROM public.alerts
   WHERE id = (SELECT filed_alert FROM public.ussd_sessions WHERE session_id = 'sess-known-001');

  -- The gateway did not get our reply and sent the same thing again.
  SELECT * INTO again FROM public.ussd_file_report(
    'sess-known-001', '+2348031110001', 'f11e0000-0000-4000-8000-00000000f101',
    'Community attack - Armed Invasion', true, 'JOS NORTH', 'ABBA NA SHEHU', true);

  IF NOT again.already_filed THEN
    RAISE EXCEPTION 'FAIL: a retry was not recognised as one';
  END IF;
  IF again.reference <> first.public_reference THEN
    RAISE EXCEPTION 'FAIL: a retry produced a DIFFERENT reference (% then %)',
      first.public_reference, again.reference;
  END IF;
  IF again.alert_id <> first.id THEN
    RAISE EXCEPTION 'FAIL: a retry produced a second alert';
  END IF;

  SELECT count(*) INTO n FROM public.alerts WHERE reporter_msisdn = '+2348031110001';
  IF n <> 1 THEN
    RAISE EXCEPTION 'FAIL: % alerts exist for one session — the retry raised the '
                    'same emergency again', n;
  END IF;
  RAISE NOTICE 'PASS: a retry returns the SAME reference and files nothing new';
END $$;

DO $$
DECLARE again RECORD; n INTEGER;
BEGIN
  -- Four retries, which is what a badly congested network actually produces.
  FOR i IN 1..4 LOOP
    SELECT * INTO again FROM public.ussd_file_report(
      'sess-known-001', '+2348031110001', 'f11e0000-0000-4000-8000-00000000f101',
      'Community attack - Armed Invasion', true, 'JOS NORTH', 'ABBA NA SHEHU', true);
  END LOOP;
  SELECT count(*) INTO n FROM public.alerts WHERE reporter_msisdn = '+2348031110001';
  IF n <> 1 THEN
    RAISE EXCEPTION 'FAIL: four retries produced % alerts', n;
  END IF;
  RAISE NOTICE 'PASS: repeated retries stay at one incident';
END $$;

-- A DIFFERENT session from the same number is a different report. Somebody who
-- dials again ten minutes later because nothing happened must not be silently
-- deduplicated into the first one.
DO $$
DECLARE r RECORD; n INTEGER;
BEGIN
  INSERT INTO public.ussd_sessions (session_id, msisdn, state)
  VALUES ('sess-known-002', '+2348031110001', '{}'::jsonb);
  SELECT * INTO r FROM public.ussd_file_report(
    'sess-known-002', '+2348031110001', 'f11e0000-0000-4000-8000-00000000f101',
    'Kidnap - Immediate Abduction', true, 'JOS NORTH', 'ABBA NA SHEHU', false);
  IF r.already_filed THEN
    RAISE EXCEPTION 'FAIL: a new session was treated as a retry of the old one';
  END IF;
  SELECT count(*) INTO n FROM public.alerts WHERE reporter_msisdn = '+2348031110001';
  IF n <> 2 THEN
    RAISE EXCEPTION 'FAIL: a second dialogue produced % alerts in total', n;
  END IF;
  RAISE NOTICE 'PASS: dialling again is a new report, not a duplicate';
END $$;

-- Age the FIRST report so "most recent" means something here. Every insert in
-- this file shares one `NOW()` — it is the transaction timestamp, not the wall
-- clock — so without this the two reports tie and the status-screen assertion
-- below is decided by whichever uuid happened to sort higher. That tie is also a
-- real possibility in production, which is why ussd_last_report() breaks it on
-- `id` rather than trusting created_at to be unique.
UPDATE public.alerts
   SET created_at = NOW() - INTERVAL '20 minutes'
 WHERE public_reference = (
   SELECT a.public_reference FROM public.alerts a
    WHERE a.type = 'Community attack - Armed Invasion'
      AND a.reporter_msisdn = '+2348031110001');

-- ── A session that was never opened ─────────────────────────────────────

DO $$
DECLARE n INTEGER;
BEGIN
  SELECT count(*) INTO n FROM public.ussd_file_report(
    'sess-never-opened', '+2348031110001', NULL,
    'Fire - Building Fire', false, 'JOS NORTH', NULL, false);
  IF n <> 0 THEN
    RAISE EXCEPTION 'FAIL: filing against an unopened session produced a row';
  END IF;
  -- An alert with no dialogue behind it could never be deduplicated on a retry,
  -- so refusing is the safe direction.
  IF EXISTS (SELECT 1 FROM public.alerts WHERE type = 'Fire - Building Fire'
              AND arrived_via = 'USSD') THEN
    RAISE EXCEPTION 'FAIL: an alert was written for a session that does not exist';
  END IF;
  RAISE NOTICE 'PASS: filing without a session is refused and writes nothing';
END $$;

-- ── A report with no location at all ────────────────────────────────────

INSERT INTO auth.users (id, email) VALUES
  ('f11e0000-0000-4000-8000-00000000f1aa', 'ussd-ward-mangu@staging.test')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.profiles (id, email, full_name, role, geo_lga, geo_ward) VALUES
  ('f11e0000-0000-4000-8000-00000000f1aa', 'ussd-ward-mangu@staging.test',
   'Ward Mangu', 'WARD_COMMAND', 'MANGU', 'AMPANG WEST')
ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role, geo_lga = EXCLUDED.geo_lga;

DO $$
DECLARE r RECORD; a public.alerts; seen INTEGER;
BEGIN
  INSERT INTO public.ussd_sessions (session_id, msisdn, state)
  VALUES ('sess-nowhere', '+2348031119999', '{}'::jsonb);
  SELECT * INTO r FROM public.ussd_file_report(
    'sess-nowhere', '+2348031119999', NULL,
    'Other danger - Immediate Threat', true, NULL, NULL, false);

  -- `public.alerts`, not RECORD. alert_in_my_area() takes the table's rowtype
  -- and PostgreSQL will not cast an anonymous record to it — the first version
  -- of this block failed with "cannot cast type record to alerts".
  SELECT * INTO a FROM public.alerts WHERE id = r.alert_id;
  IF a.geo_lga IS NOT NULL OR a.geo_ward IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: a placeless report invented a location';
  END IF;
  IF a.severity <> 'CRITICAL' THEN
    RAISE EXCEPTION 'FAIL: a placeless emergency lost its grading';
  END IF;

  -- Asserted as a REAL RLS read by a REAL officer, not by calling the predicate.
  -- alert_in_my_area() reads auth.uid(), which is NULL with no JWT set, so the
  -- first version of this check went down the unlocated fail-open branch and
  -- would have passed however broken the scoping was.
  --
  -- A ward commander in MANGU has no part in this incident and no ward matches
  -- it. They must still see it: an unlocated emergency is visible to every staff
  -- account by design (20261006000000), and that is what makes "send now, no
  -- place" a real route to help instead of a dead end.
  PERFORM set_config('request.jwt.claim.sub',
                     'f11e0000-0000-4000-8000-00000000f1aa', true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO seen FROM public.alerts WHERE id = r.alert_id;
  RESET ROLE;
  IF seen <> 1 THEN
    RAISE EXCEPTION 'FAIL: an unlocated USSD emergency is invisible to a ward '
                    'commander in another LGA, so nobody can act on it';
  END IF;
  RAISE NOTICE 'PASS: somebody in danger can report with no location and still be seen';
END $$;

-- ── The status screen ───────────────────────────────────────────────────

DO $$
DECLARE r RECORD;
BEGIN
  SELECT * INTO r FROM public.ussd_last_report('08031110001');
  IF r.reference IS NULL THEN
    RAISE EXCEPTION 'FAIL: the caller cannot read back their own report';
  END IF;
  -- The most recent one, which is the second dialogue.
  IF r.kind <> 'Kidnap - Immediate Abduction' THEN
    RAISE EXCEPTION 'FAIL: the status screen shows % rather than the newest report', r.kind;
  END IF;
  IF r.age_minutes < 0 THEN
    RAISE EXCEPTION 'FAIL: the report is % minutes old', r.age_minutes;
  END IF;
  RAISE NOTICE 'PASS: a caller reads back their own most recent report';
END $$;

DO $$
DECLARE n INTEGER;
BEGIN
  SELECT count(*) INTO n FROM public.ussd_last_report('+2348037777777');
  IF n <> 0 THEN
    RAISE EXCEPTION 'FAIL: a number with no reports got one';
  END IF;
  RAISE NOTICE 'PASS: a number with no reports gets nothing';
END $$;

-- The columns this function returns are the whole privacy control: whoever holds
-- the SIM can read that screen, and somebody who filed a report to draw officers
-- to a place must not be able to watch them come.
DO $$
DECLARE cols TEXT[];
BEGIN
  SELECT array_agg(lower(p.parameter_name) ORDER BY p.ordinal_position) INTO cols
    FROM information_schema.parameters p
    JOIN information_schema.routines r
      ON r.specific_name = p.specific_name
   WHERE r.routine_schema = 'public'
     AND r.routine_name = 'ussd_last_report'
     AND p.parameter_mode = 'OUT';

  IF cols IS DISTINCT FROM ARRAY['reference','kind','status','age_minutes'] THEN
    RAISE EXCEPTION 'FAIL: ussd_last_report returns %, which is not the four '
                    'columns the status screen is allowed to know', cols;
  END IF;
  RAISE NOTICE 'PASS: the status screen can only ever know reference, kind, status and age';
END $$;

-- ── Forgetting the dialogue ─────────────────────────────────────────────

DO $$
DECLARE swept INTEGER; left_over INTEGER;
BEGIN
  UPDATE public.ussd_sessions SET updated_at = NOW() - INTERVAL '3 hours'
   WHERE session_id = 'sess-known-001';
  swept := public.sweep_ussd_sessions();
  IF swept < 1 THEN
    RAISE EXCEPTION 'FAIL: the sweep removed nothing';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ussd_sessions WHERE session_id = 'sess-known-001') THEN
    RAISE EXCEPTION 'FAIL: a stale dialogue survived the sweep';
  END IF;
  -- A live dialogue must not be swept out from under a caller mid-session.
  SELECT count(*) INTO left_over FROM public.ussd_sessions WHERE session_id = 'sess-known-002';
  IF left_over <> 1 THEN
    RAISE EXCEPTION 'FAIL: the sweep removed a live session';
  END IF;
  -- The ALERT keeps what it needs; the dialogue does not outlive the call.
  IF NOT EXISTS (SELECT 1 FROM public.alerts WHERE reporter_msisdn = '+2348031110001') THEN
    RAISE EXCEPTION 'FAIL: sweeping the session took the report with it';
  END IF;
  RAISE NOTICE 'PASS: stale dialogues are forgotten, live ones are not, reports survive';
END $$;

ROLLBACK;
