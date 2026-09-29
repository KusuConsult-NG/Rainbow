-- Behaviour test for the production-readiness migrations:
--
--   20260812000000_agency_tables.sql          (tables the console needs exist)
--   20260813000000 section 9                  (who may touch them)
--   20260903000000_realtime_publication.sql   (the console's subscriptions fire)
--   20260903000001_incident_media_storage.sql (field media can be uploaded,
--                                              never altered, not enumerated)
--
-- Runs inside scripts/verify_rls_migration.sh after every migration has been
-- applied. Same technique as the other two behaviour tests: impersonate roles
-- the way PostgREST does and assert what they can DO, not what exists.
--
-- Any FAIL raises, which fails the CI job. Everything is rolled back.

\set ON_ERROR_STOP on
BEGIN;

RESET ROLE;
INSERT INTO auth.users (id, email) VALUES
  ('dddddddd-dddd-4ddd-8ddd-ddddddddddd1', 'police-liaison@test'),
  ('dddddddd-dddd-4ddd-8ddd-ddddddddddd2', 'army-liaison@test'),
  ('dddddddd-dddd-4ddd-8ddd-ddddddddddd3', 'responder@test'),
  ('dddddddd-dddd-4ddd-8ddd-ddddddddddd4', 'hq@test'),
  ('dddddddd-dddd-4ddd-8ddd-ddddddddddd5', 'citizen2@test')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles (id, role, full_name) VALUES
  ('dddddddd-dddd-4ddd-8ddd-ddddddddddd1', 'POLICE_LIAISON', 'Police Liaison'),
  ('dddddddd-dddd-4ddd-8ddd-ddddddddddd2', 'ARMY_LIAISON',   'Army Liaison'),
  ('dddddddd-dddd-4ddd-8ddd-ddddddddddd3', 'RESPONDER',      'A Responder'),
  ('dddddddd-dddd-4ddd-8ddd-ddddddddddd4', 'HQ_COMMAND',     'HQ'),
  ('dddddddd-dddd-4ddd-8ddd-ddddddddddd5', 'CITIZEN',        'A Citizen')
ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role;

-- Supabase grants the API roles table privileges by default; RLS is the gate.
GRANT SELECT, INSERT, UPDATE, DELETE ON
  public.agency_personnel, public.agency_deployments,
  public.agency_action_reports, public.agency_notifications
TO authenticated;

-- Same for the newer tables. Granted DELETE and UPDATE deliberately, even
-- though `incident_tracks` has no policy for either: the point of the
-- assertions below is that the POLICY refuses them, and a grant-level refusal
-- would pass the test while proving nothing about the policy.
GRANT SELECT, INSERT, UPDATE, DELETE ON
  public.incident_tracks, public.sim_channel_events
TO authenticated;

-- Seed one officer per agency with full privileges.
INSERT INTO public.agency_personnel (id, agency, name) VALUES
  ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1', 'POLICE', 'Insp. Police'),
  ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee2', 'ARMY',   'Capt. Army')
ON CONFLICT (id) DO NOTHING;

CREATE OR REPLACE FUNCTION pg_temp.become(uid uuid, r text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub', COALESCE(uid::text, ''), true);
  PERFORM set_config('request.jwt.claim.role', r, true);
  EXECUTE format('SET LOCAL ROLE %I', r);
END $$;

DO $$
DECLARE
  police constant uuid := 'dddddddd-dddd-4ddd-8ddd-ddddddddddd1';
  army   constant uuid := 'dddddddd-dddd-4ddd-8ddd-ddddddddddd2';
  resp   constant uuid := 'dddddddd-dddd-4ddd-8ddd-ddddddddddd3';
  hq     constant uuid := 'dddddddd-dddd-4ddd-8ddd-ddddddddddd4';
  cit    constant uuid := 'dddddddd-dddd-4ddd-8ddd-ddddddddddd5';
  n int;
  missing text;
BEGIN
  -- ═══ 1. Agency tables: the schema the console expects is present ══════════
  RESET ROLE;
  SELECT string_agg(t, ', ') INTO missing FROM unnest(ARRAY[
    'agency_personnel', 'agency_deployments', 'agency_action_reports', 'agency_notifications'
  ]) t WHERE to_regclass('public.' || t) IS NULL;
  IF missing IS NOT NULL THEN RAISE EXCEPTION 'FAIL: agency tables missing: %', missing; END IF;
  PERFORM 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'agency';
  IF NOT FOUND THEN RAISE EXCEPTION 'FAIL: profiles.agency missing'; END IF;
  RAISE NOTICE 'PASS: agency tables and profiles.agency exist';

  -- ═══ 2. Agency access ═════════════════════════════════════════════════════
  -- A liaison sees only their own agency's roster.
  PERFORM pg_temp.become(police, 'authenticated');
  SELECT count(*) INTO n FROM public.agency_personnel;
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL: police liaison sees % personnel rows, expected 1 (own agency)', n; END IF;
  SELECT count(*) INTO n FROM public.agency_personnel WHERE agency = 'ARMY';
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL: police liaison can read the army roster'; END IF;
  RAISE NOTICE 'PASS: a liaison reads only their own agency';

  -- A liaison may register officers, deploy them and file reports for THEIR agency.
  INSERT INTO public.agency_personnel (agency, name, created_by) VALUES ('POLICE', 'Sgt. New', police);
  INSERT INTO public.agency_deployments (agency, personnel_ids, personnel_count, deployed_by)
    VALUES ('POLICE', ARRAY['eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1'::uuid], 1, police);
  INSERT INTO public.agency_action_reports (agency, narrative, submitted_by, submitted_by_name)
    VALUES ('POLICE', 'Area secured.', police, 'Police Liaison');
  UPDATE public.agency_personnel SET status = 'DEPLOYED' WHERE id = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1';
  IF NOT FOUND THEN RAISE EXCEPTION 'FAIL: police liaison could not update own officer'; END IF;
  RAISE NOTICE 'PASS: a liaison writes personnel, deployments and reports for their agency';

  -- ...but nothing tagged with another agency, and cannot retag rows either.
  BEGIN
    INSERT INTO public.agency_personnel (agency, name) VALUES ('ARMY', 'Impostor');
    RAISE EXCEPTION 'FAIL: police liaison inserted an ARMY officer';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'PASS: a liaison cannot write another agency''s rows';
  END;
  UPDATE public.agency_personnel SET status = 'OFF_DUTY' WHERE id = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee2';
  IF FOUND THEN RAISE EXCEPTION 'FAIL: police liaison updated an ARMY officer'; END IF;
  BEGIN
    UPDATE public.agency_personnel SET agency = 'ARMY' WHERE id = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1';
    RAISE EXCEPTION 'FAIL: police liaison moved an officer to ARMY';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'PASS: a liaison cannot retag rows into another agency';
  END;

  -- Agency is derived from the ROLE, so rewriting profiles.agency changes nothing.
  UPDATE public.profiles SET agency = 'ARMY' WHERE id = police;
  SELECT count(*) INTO n FROM public.agency_personnel WHERE agency = 'ARMY';
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL: setting profiles.agency granted access to another agency'; END IF;
  RAISE NOTICE 'PASS: profiles.agency is display-only; access follows the role';

  -- Escalation delivery log: not for liaisons.
  SELECT count(*) INTO n FROM public.agency_notifications;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL: liaison read agency_notifications'; END IF;
  BEGIN
    INSERT INTO public.agency_notifications (agency, method, status) VALUES ('POLICE', 'SMS', 'SENT');
    RAISE EXCEPTION 'FAIL: liaison wrote agency_notifications';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  RAISE NOTICE 'PASS: liaisons cannot see or forge the escalation delivery log';

  -- The other agency's liaison sees their own row and none of police's.
  PERFORM pg_temp.become(army, 'authenticated');
  SELECT count(*) INTO n FROM public.agency_action_reports;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL: army liaison read % police report(s)', n; END IF;
  RAISE NOTICE 'PASS: reports are invisible across agencies';

  -- ═══ 2b. A liaison is not Operation Rainbow staff ════════════════════════
  --
  -- `is_staff()` is "role is not CITIZEN", so a POLICE_LIAISON was staff — and
  -- the alerts policies were `... OR is_staff()`. Every liaison could READ and
  -- WRITE every incident in Plateau: resolve one in an LGA their agency was
  -- never called to, reassign it, clear a duress alarm. Nobody decided that;
  -- the agency roles simply arrived after is_staff() was written.
  --
  -- Two incidents: one escalated to the POLICE, one to the ARMY.
  PERFORM pg_temp.become(hq, 'authenticated');
  INSERT INTO public.alerts (id, reported_by, status, type, severity, escalated_to_agency)
  VALUES ('cccccccc-cccc-4ccc-8ccc-ccccccccca01', cit, 'PENDING', 'SOS', 'HIGH', 'POLICE'),
         ('cccccccc-cccc-4ccc-8ccc-ccccccccca02', cit, 'PENDING', 'SOS', 'HIGH', 'ARMY'),
         ('cccccccc-cccc-4ccc-8ccc-ccccccccca03', cit, 'PENDING', 'SOS', 'HIGH', NULL),
         -- OPEN, and nothing to do with the citizen: reported by a responder.
         -- The route assertions below need an incident that is open, so that
         -- an attempt to attach a route to it is refused for the right
         -- reason — the first version used a RESOLVED incident and passed
         -- whatever the ownership clause said.
         ('cccccccc-cccc-4ccc-8ccc-ccccccccca04', resp, 'PENDING', 'SOS', 'HIGH', NULL)
  ON CONFLICT (id) DO NOTHING;

  PERFORM pg_temp.become(police, 'authenticated');

  SELECT count(*) INTO n FROM public.alerts
   WHERE id = 'cccccccc-cccc-4ccc-8ccc-ccccccccca01';
  IF n <> 1 THEN
    RAISE EXCEPTION 'FAIL: police liaison cannot see the incident escalated to them';
  END IF;

  SELECT count(*) INTO n FROM public.alerts
   WHERE id = 'cccccccc-cccc-4ccc-8ccc-ccccccccca02';
  IF n <> 0 THEN
    RAISE EXCEPTION 'FAIL: police liaison reads an incident escalated to the ARMY';
  END IF;

  SELECT count(*) INTO n FROM public.alerts
   WHERE id = 'cccccccc-cccc-4ccc-8ccc-ccccccccca03';
  IF n <> 0 THEN
    RAISE EXCEPTION 'FAIL: police liaison reads an incident escalated to nobody';
  END IF;
  RAISE NOTICE 'PASS: a liaison reads only the incidents handed to their agency';

  -- ...and cannot WRITE to one that was not. This is the half that mattered
  -- most: reading the board is a confidentiality problem, but resolving
  -- somebody else's live emergency is an operational one.
  UPDATE public.alerts SET status = 'RESOLVED'
   WHERE id = 'cccccccc-cccc-4ccc-8ccc-ccccccccca02';
  IF FOUND THEN
    RAISE EXCEPTION 'FAIL: police liaison resolved an ARMY incident';
  END IF;
  UPDATE public.alerts SET status = 'RESOLVED'
   WHERE id = 'cccccccc-cccc-4ccc-8ccc-ccccccccca03';
  IF FOUND THEN
    RAISE EXCEPTION 'FAIL: police liaison resolved an unescalated incident';
  END IF;
  RAISE NOTICE 'PASS: a liaison cannot act on another agency''s incident';

  -- But CAN act on their own, or the handover is ceremonial.
  UPDATE public.alerts SET status = 'DISPATCHED'
   WHERE id = 'cccccccc-cccc-4ccc-8ccc-ccccccccca01';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'FAIL: police liaison cannot act on their own incident';
  END IF;
  RAISE NOTICE 'PASS: a liaison can act on the incident handed to them';

  -- Operation Rainbow's own staff keep the statewide board.
  PERFORM pg_temp.become(hq, 'authenticated');
  SELECT count(*) INTO n FROM public.alerts
   WHERE id IN ('cccccccc-cccc-4ccc-8ccc-ccccccccca01',
                'cccccccc-cccc-4ccc-8ccc-ccccccccca02',
                'cccccccc-cccc-4ccc-8ccc-ccccccccca03');
  IF n <> 3 THEN
    RAISE EXCEPTION 'FAIL: this narrowed the board for HQ too (sees %, expected 3)', n;
  END IF;
  RAISE NOTICE 'PASS: command still sees the whole state';

  -- ═══ 2c. The route is kept, and only for the incident it belongs to ══════
  --
  -- `telemetry` holds one row per person, upserted, so the trail the console
  -- drew lived only in a browser tab's memory: a refresh lost it, and anybody
  -- reviewing the incident afterwards saw no movement at all. `incident_tracks`
  -- keeps the points — and the whole reason that does not undo the "location is
  -- borrowed, not kept" work is the scoping asserted here.
  PERFORM pg_temp.become(cit, 'authenticated');
  INSERT INTO public.incident_tracks (alert_id, user_id, latitude, longitude, accuracy)
  VALUES ('cccccccc-cccc-4ccc-8ccc-ccccccccca01', cit, 9.8965, 8.8583, 8),
         ('cccccccc-cccc-4ccc-8ccc-ccccccccca01', cit, 9.8991, 8.8620, 8);
  RAISE NOTICE 'PASS: a reporter records their own route on their own incident';

  -- Not somebody else's route.
  BEGIN
    INSERT INTO public.incident_tracks (alert_id, user_id, latitude, longitude)
    VALUES ('cccccccc-cccc-4ccc-8ccc-ccccccccca01', hq, 9.9, 8.9);
    RAISE EXCEPTION 'FAIL: a citizen wrote a route for somebody else';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'PASS: a route cannot be written for another person';
  END;

  -- And not onto an incident they have no part in. ...ca04 is OPEN and
  -- reported by somebody else.
  --
  -- Refused TWICE over, and the distinction is worth writing down because the
  -- first version of this test did not make it: the policy's own ownership
  -- clause refuses it, and so does the EXISTS subquery, which runs as the
  -- calling user and therefore cannot see an alert that user has no part in.
  -- For a CITIZEN the second mechanism alone is enough — mutating the
  -- ownership clause away leaves this assertion passing. The assertion that
  -- actually pins the clause is the staff one below.
  BEGIN
    INSERT INTO public.incident_tracks (alert_id, user_id, latitude, longitude)
    VALUES ('cccccccc-cccc-4ccc-8ccc-ccccccccca04', cit, 9.9, 8.9);
    RAISE EXCEPTION 'FAIL: a citizen attached a route to an unrelated incident';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'PASS: a route cannot be attached to an unrelated incident';
  END;

  -- THE ONE THAT PINS THE OWNERSHIP CLAUSE.
  --
  -- A responder is staff, so `alert_is_ours()` lets them SEE every incident in
  -- the state — which means the EXISTS subquery succeeds for all of them and
  -- the only thing standing between a staff account and writing a route onto
  -- somebody else's incident is the ownership clause itself. Mutate that
  -- clause to `true` and this assertion is what fails.
  PERFORM pg_temp.become(resp, 'authenticated');
  BEGIN
    INSERT INTO public.incident_tracks (alert_id, user_id, latitude, longitude)
    VALUES ('cccccccc-cccc-4ccc-8ccc-ccccccccca01', resp, 9.9, 8.9);
    RAISE EXCEPTION 'FAIL: a responder wrote a route onto an incident they are not on';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'PASS: being staff does not let you write a route onto any incident';
  END;
  PERFORM pg_temp.become(cit, 'authenticated');

  -- Nor onto a CLOSED incident of their own: a route that can be added days
  -- later is a story, not a record.
  PERFORM pg_temp.become(hq, 'authenticated');
  UPDATE public.alerts SET status = 'RESOLVED'
   WHERE id = 'cccccccc-cccc-4ccc-8ccc-ccccccccca03';
  PERFORM pg_temp.become(cit, 'authenticated');
  BEGIN
    INSERT INTO public.incident_tracks (alert_id, user_id, latitude, longitude)
    VALUES ('cccccccc-cccc-4ccc-8ccc-ccccccccca03', cit, 9.9, 8.9);
    RAISE EXCEPTION 'FAIL: a route was added to a closed incident';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'PASS: a closed incident cannot gain a route afterwards';
  END;

  -- A route is a record. An editable one is worth less than none, because it
  -- can be made to say something else.
  UPDATE public.incident_tracks SET latitude = 0 WHERE user_id = cit;
  IF FOUND THEN RAISE EXCEPTION 'FAIL: a route point was rewritten'; END IF;
  DELETE FROM public.incident_tracks WHERE user_id = cit;
  IF FOUND THEN RAISE EXCEPTION 'FAIL: a route point was deleted by hand'; END IF;
  RAISE NOTICE 'PASS: a route cannot be rewritten or deleted through the API';

  -- Read follows the incident. The POLICE liaison holds ...ca01; the ARMY one
  -- does not, and must not see the route on it either.
  -- Counted on THIS incident, not across the table. These read
  -- `FROM public.incident_tracks` with no WHERE, so any row anyone else added
  -- — a later fixture, a demonstration seed — broke an assertion about
  -- row-level security, which is a confusing way to be told about a defect
  -- that is not there.
  PERFORM pg_temp.become(police, 'authenticated');
  SELECT count(*) INTO n FROM public.incident_tracks
   WHERE alert_id = 'cccccccc-cccc-4ccc-8ccc-ccccccccca01';
  IF n <> 2 THEN
    RAISE EXCEPTION 'FAIL: police liaison sees % route points on their own incident, expected 2', n;
  END IF;

  PERFORM pg_temp.become(army, 'authenticated');
  SELECT count(*) INTO n FROM public.incident_tracks
   WHERE alert_id = 'cccccccc-cccc-4ccc-8ccc-ccccccccca01';
  IF n <> 0 THEN
    RAISE EXCEPTION 'FAIL: army liaison reads % route point(s) from a POLICE incident', n;
  END IF;
  RAISE NOTICE 'PASS: a route is readable only by people with a part in that incident';

  PERFORM pg_temp.become(hq, 'authenticated');
  SELECT count(*) INTO n FROM public.incident_tracks
   WHERE alert_id = 'cccccccc-cccc-4ccc-8ccc-ccccccccca01';
  IF n <> 2 THEN RAISE EXCEPTION 'FAIL: HQ cannot read the route'; END IF;
  RAISE NOTICE 'PASS: command can review the route';

  -- A field responder is staff but has no business here.
  PERFORM pg_temp.become(resp, 'authenticated');
  SELECT count(*) INTO n FROM public.agency_personnel;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL: responder read % agency personnel rows', n; END IF;
  RAISE NOTICE 'PASS: responders cannot read agency rosters';

  -- A citizen sees nothing.
  PERFORM pg_temp.become(cit, 'authenticated');
  SELECT count(*) INTO n FROM public.agency_deployments;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL: citizen read agency deployments'; END IF;
  RAISE NOTICE 'PASS: citizens cannot read agency deployments';

  -- Command sees and acknowledges everything.
  PERFORM pg_temp.become(hq, 'authenticated');
  SELECT count(*) INTO n FROM public.agency_personnel;
  IF n <> 3 THEN RAISE EXCEPTION 'FAIL: HQ sees % personnel rows, expected 3', n; END IF;
  UPDATE public.agency_action_reports SET read_by_hq = true, hq_acknowledged_by = 'hq@test';
  IF NOT FOUND THEN RAISE EXCEPTION 'FAIL: HQ could not acknowledge a report'; END IF;
  RAISE NOTICE 'PASS: command reads every agency and acknowledges reports';

  -- ═══ 3. Realtime: the console's subscriptions are on published tables ═════
  RESET ROLE;
  SELECT string_agg(t, ', ') INTO missing FROM unnest(ARRAY[
    'alerts', 'telemetry', 'chat_messages', 'system_alerts', 'profiles',
    'agency_action_reports', 'agency_deployments', 'uninstall_requests'
  ]) t WHERE NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
     WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = t);
  IF missing IS NOT NULL THEN RAISE EXCEPTION 'FAIL: not in supabase_realtime: %', missing; END IF;
  RAISE NOTICE 'PASS: every table the apps subscribe to is in supabase_realtime';

  -- ═══ 4. Storage: incident-media ═══════════════════════════════════════════
  PERFORM 1 FROM storage.buckets
    WHERE id = 'incident-media' AND public
      AND file_size_limit = 52428800 AND 'audio/*' = ANY(allowed_mime_types);
  IF NOT FOUND THEN RAISE EXCEPTION 'FAIL: incident-media bucket missing or misconfigured'; END IF;
  RAISE NOTICE 'PASS: incident-media bucket exists, public, 50 MB, image/video/audio only';

  -- anon cannot upload.
  PERFORM pg_temp.become(NULL, 'anon');
  BEGIN
    INSERT INTO storage.objects (bucket_id, name) VALUES ('incident-media', 'anon/x.jpg');
    RAISE EXCEPTION 'FAIL: anon uploaded to incident-media';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'PASS: anon cannot upload';
  END;

  -- A citizen (the usual reporter) can upload, to this bucket only.
  PERFORM pg_temp.become(cit, 'authenticated');
  INSERT INTO storage.objects (bucket_id, name, owner)
    VALUES ('incident-media', 'incident_media/1700000000000_abcde.jpg', cit);
  BEGIN
    INSERT INTO storage.objects (bucket_id, name, owner) VALUES ('avatars', 'x.jpg', cit);
    RAISE EXCEPTION 'FAIL: citizen wrote to a bucket other than incident-media';
  EXCEPTION WHEN insufficient_privilege OR foreign_key_violation THEN NULL;
  END;
  RAISE NOTICE 'PASS: a signed-in reporter can upload evidence, only to incident-media';

  -- ...but cannot list the bucket, nor alter or remove what is there.
  SELECT count(*) INTO n FROM storage.objects WHERE bucket_id = 'incident-media';
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL: citizen listed % object(s) in incident-media', n; END IF;
  UPDATE storage.objects SET name = 'renamed.jpg' WHERE bucket_id = 'incident-media';
  IF FOUND THEN RAISE EXCEPTION 'FAIL: citizen renamed an evidence object'; END IF;
  DELETE FROM storage.objects WHERE bucket_id = 'incident-media';
  IF FOUND THEN RAISE EXCEPTION 'FAIL: citizen deleted an evidence object'; END IF;
  RAISE NOTICE 'PASS: uploads are append-only and the bucket cannot be enumerated by reporters';

  -- Staff can list; staff still cannot alter or delete.
  PERFORM pg_temp.become(hq, 'authenticated');
  SELECT count(*) INTO n FROM storage.objects WHERE bucket_id = 'incident-media';
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL: HQ sees % object(s), expected 1', n; END IF;
  DELETE FROM storage.objects WHERE bucket_id = 'incident-media';
  IF FOUND THEN RAISE EXCEPTION 'FAIL: HQ deleted an evidence object through the API role'; END IF;
  RAISE NOTICE 'PASS: staff can list evidence; nobody deletes it through the API roles';

  -- ═══ 5. Mass broadcast: the row the console writes must actually insert ══
  --
  -- Every broadcast used to fail. The console named six columns that existed in
  -- no migration and omitted `title`, which is NOT NULL — so the statewide
  -- warning mechanism was dead, and the operator saw a raw PostgREST error.
  -- This inserts the EXACT payload MassBroadcast.tsx now sends.
  PERFORM pg_temp.become(hq, 'authenticated');
  INSERT INTO public.system_alerts
    (title, message, severity, target_audience, target_agency,
     target_lga, target_ward, target_pu, is_active, expires_at)
  VALUES
    ('CRITICAL ADVISORY — JOS NORTH LGA', 'Avoid Terminus junction.', 'CRITICAL',
     'CITIZENS', 'ALL', 'JOS NORTH', 'ALL', 'ALL', true, NOW() + INTERVAL '24 hours');
  RAISE NOTICE 'PASS: the console broadcast payload inserts';

  -- `title` has a default now, so a writer that forgets it cannot fail the
  -- insert the way both writers used to.
  INSERT INTO public.system_alerts (message, severity) VALUES ('No title given.', 'INFO');
  RAISE NOTICE 'PASS: a titleless broadcast no longer violates NOT NULL';

  -- Broadcasting stays command-only. Fixing delivery must not have widened who
  -- can address the entire state.
  PERFORM pg_temp.become(cit, 'authenticated');
  BEGIN
    INSERT INTO public.system_alerts (title, message) VALUES ('FAKE', 'Evacuate immediately.');
    RAISE EXCEPTION 'FAIL: a citizen broadcast to the whole state';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'PASS: citizens still cannot broadcast';
  END;

  -- ...and a citizen can still RECEIVE one. `system_alerts` being command-write
  -- is only correct if it stays everyone-read; a policy mistake here silently
  -- stops warnings reaching the public.
  SELECT count(*) INTO n FROM public.system_alerts WHERE severity = 'CRITICAL';
  IF n < 1 THEN RAISE EXCEPTION 'FAIL: a citizen cannot read the advisory addressed to them'; END IF;
  RAISE NOTICE 'PASS: citizens receive broadcasts';

  -- ═══ 6. Escalation: the update the console sends must actually apply ═════
  --
  -- escalated_to_agency and escalation_log are written by both apps and read by
  -- the agency portal, and neither existed in this repository's schema — so on
  -- a rebuilt database every escalation failed IN FULL, taking the status,
  -- severity and assignment with it.
  RESET ROLE;
  INSERT INTO public.alerts (id, reported_by, status, type)
  VALUES ('cccccccc-cccc-4ccc-8ccc-cccccccccce1',
          'dddddddd-dddd-4ddd-8ddd-ddddddddddd5', 'PENDING', 'SOS')
  ON CONFLICT (id) DO NOTHING;

  PERFORM pg_temp.become(hq, 'authenticated');
  UPDATE public.alerts SET
    severity            = 'CRITICAL',
    status              = 'ESCALATED',
    escalated_to_agency = 'POLICE',
    escalation_log      = escalation_log || jsonb_build_array(
                            jsonb_build_object('from_tier', 'HQ', 'to_agency', 'POLICE')),
    ai_summary          = 'escalated',
    updated_at          = NOW()
  WHERE id = 'cccccccc-cccc-4ccc-8ccc-cccccccccce1';
  IF NOT FOUND THEN RAISE EXCEPTION 'FAIL: HQ could not escalate an incident'; END IF;
  RAISE NOTICE 'PASS: the escalation update applies';

  -- The log is a chain of custody: appending must not replace what is there.
  UPDATE public.alerts SET
    escalation_log = escalation_log || jsonb_build_array(
                       jsonb_build_object('from_tier', 'POLICE', 'to_agency', 'ARMY'))
  WHERE id = 'cccccccc-cccc-4ccc-8ccc-cccccccccce1';
  SELECT jsonb_array_length(escalation_log) INTO n
    FROM public.alerts WHERE id = 'cccccccc-cccc-4ccc-8ccc-cccccccccce1';
  IF n <> 2 THEN RAISE EXCEPTION 'FAIL: escalation_log holds % entries, expected 2', n; END IF;
  RAISE NOTICE 'PASS: escalation_log appends rather than replaces';

  -- The agency portal's entire feed is this filter.
  --
  -- Asserted on THE ROW, not on a count of the whole table. It used to say
  -- `count(*) = 1`, which made it a test of how many fixtures the file happens
  -- to contain: adding one more escalated incident anywhere above broke it
  -- while saying nothing about the filter.
  SELECT count(*) INTO n FROM public.alerts
   WHERE escalated_to_agency = 'POLICE'
     AND id = 'cccccccc-cccc-4ccc-8ccc-cccccccccce1';
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL: the agency portal filter misses the escalated incident (% rows)', n; END IF;
  SELECT count(*) INTO n FROM public.alerts
   WHERE escalated_to_agency = 'POLICE'
     AND id = 'cccccccc-cccc-4ccc-8ccc-ccccccccca02';
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL: the agency portal filter picks up an ARMY incident'; END IF;
  RAISE NOTICE 'PASS: escalated incidents are visible to the agency they went to';

  -- ═══ 7. The board's profile lookup must actually return rows ═════════════
  --
  -- This select asked for `lga, ward, sector_id` — none of them columns — so
  -- PostgREST rejected it in full and the console's usersMap stayed empty:
  -- every officer rendered as `TACTICAL SQUAD #A1B2C3` and every reporter as
  -- "No Phone Registered", with nothing logged. It also omitted the fields its
  -- consumers read. This is the corrected list.
  PERFORM pg_temp.become(hq, 'authenticated');
  PERFORM id, full_name, email, phone, role, badge_number, geo_lga, geo_ward, geo_pu
     FROM public.profiles LIMIT 1000;
  RAISE NOTICE 'PASS: the board profile lookup selects only real columns';

  -- The mobile names badge_number explicitly when listing responders to
  -- dispatch, so without the column that query fails and the list is empty.
  PERFORM id, full_name, badge_number, role, geo_lga, geo_ward FROM public.profiles;
  RAISE NOTICE 'PASS: the responder picker selects only real columns';

  -- ═══ 8. Tier escalation: the payload the mobile sends must apply ═════════
  --
  -- `assigned_to` is uuid. The mobile sent `targetCommanderId ?? targetTier`,
  -- so with no specific commander chosen it put 'LGA' in a uuid column —
  -- rejected, and since it is one UPDATE the whole escalation went with it.
  PERFORM pg_temp.become(hq, 'authenticated');
  BEGIN
    UPDATE public.alerts SET assigned_to = 'LGA'
     WHERE id = 'cccccccc-cccc-4ccc-8ccc-cccccccccce1';
    RAISE EXCEPTION 'FAIL: a tier label was accepted into the assigned_to uuid column';
  EXCEPTION WHEN invalid_text_representation THEN
    RAISE NOTICE 'PASS: a tier label in assigned_to is still rejected — hence its own column';
  END;

  -- The corrected payload: nobody specific yet, but the tier owns it.
  UPDATE public.alerts SET
    status        = 'ESCALATED',
    severity      = 'HIGH',
    assigned_to   = NULL,
    assigned_tier = 'LGA',
    updated_at    = NOW()
  WHERE id = 'cccccccc-cccc-4ccc-8ccc-cccccccccce1';
  IF NOT FOUND THEN RAISE EXCEPTION 'FAIL: the tier escalation payload did not apply'; END IF;
  RAISE NOTICE 'PASS: an escalation with no named commander now applies';

  -- The board's tier filter, and the agency portal's, must not see each other.
  SELECT count(*) INTO n FROM public.alerts WHERE assigned_tier = 'LGA';
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL: tier filter returns % rows', n; END IF;
  SELECT count(*) INTO n FROM public.alerts WHERE escalated_to_agency = 'LGA';
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL: a tier leaked into the agency portal filter'; END IF;
  RAISE NOTICE 'PASS: tiers and agencies no longer share a column';

  RESET ROLE;
  RAISE NOTICE 'ALL PRODUCTION READINESS CHECKS PASSED';
END $$;

ROLLBACK;
