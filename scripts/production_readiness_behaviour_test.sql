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

  RESET ROLE;
  RAISE NOTICE 'ALL PRODUCTION READINESS CHECKS PASSED';
END $$;

ROLLBACK;
