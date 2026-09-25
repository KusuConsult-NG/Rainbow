-- ─── Regression tests: oversight routing, position tracks, debrief ───────────
--
--     psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/escalation_followups_test.sql
--
-- Runs inside a transaction that is rolled back. Do not point at production.

BEGIN;

\set brutality  '''b7000000-0000-0000-0000-000000000001'''
\set ordinary   '''b7000000-0000-0000-0000-000000000002'''

CREATE OR REPLACE FUNCTION pg_temp.assert(p_cond BOOLEAN, p_what TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  IF p_cond IS NOT TRUE THEN
    RAISE EXCEPTION 'ASSERTION FAILED: %', p_what;
  END IF;
  RAISE NOTICE '  ok  %', p_what;
END;
$$;

-- Three actors. handle_new_user() creates the profile row, so roles are set by
-- UPDATE rather than INSERT.
INSERT INTO auth.users (id, email) VALUES
  ('b7000000-0000-0000-0000-0000000000c1', 'citizen@test.local'),
  ('b7000000-0000-0000-0000-0000000000a1', 'ward@test.local'),
  ('b7000000-0000-0000-0000-0000000000f1', 'hq@test.local')
ON CONFLICT DO NOTHING;

UPDATE public.profiles SET role = 'CITIZEN'
 WHERE id = 'b7000000-0000-0000-0000-0000000000c1';
UPDATE public.profiles SET role = 'WARD_COMMAND', geo_lga = 'JOS NORTH'
 WHERE id = 'b7000000-0000-0000-0000-0000000000a1';
UPDATE public.profiles SET role = 'HQ_COMMAND'
 WHERE id = 'b7000000-0000-0000-0000-0000000000f1';

\echo ''
\echo '── oversight routing on insert ──'
INSERT INTO public.alerts
  (id, type, status, description, latitude, longitude, geo_lga, severity,
   assigned_tier, assigned_to, reported_by)
VALUES
  (:brutality::uuid, 'Police brutality - Physical Assault', 'PENDING',
   'officer assaulted me', 9.9, 8.9, 'JOS NORTH', 'HIGH',
   'POLLING_UNIT', 'b7000000-0000-0000-0000-0000000000a1',
   'b7000000-0000-0000-0000-0000000000c1'),
  (:ordinary::uuid, 'Kidnap - Immediate Abduction', 'PENDING',
   'armed men took my brother', 9.9, 8.9, 'JOS NORTH', 'CRITICAL',
   'POLLING_UNIT', NULL, 'b7000000-0000-0000-0000-0000000000c1');

DO $$
DECLARE r RECORD;
BEGIN
  SELECT oversight_only, assigned_tier, assigned_to, tier_entered_at
    INTO r FROM public.alerts WHERE id = 'b7000000-0000-0000-0000-000000000001';
  PERFORM pg_temp.assert(r.oversight_only,             'a brutality report is flagged oversight_only');
  PERFORM pg_temp.assert(r.assigned_tier = 'HQ',       'it enters at HQ, not the local tier');
  PERFORM pg_temp.assert(r.assigned_to IS NULL,        'the local officer the client named is cleared');
  PERFORM pg_temp.assert(r.tier_entered_at IS NOT NULL,'its SLA clock is started');

  SELECT oversight_only, assigned_tier INTO r
    FROM public.alerts WHERE id = 'b7000000-0000-0000-0000-000000000002';
  PERFORM pg_temp.assert(r.oversight_only IS FALSE,        'an ordinary report is untouched');
  PERFORM pg_temp.assert(r.assigned_tier = 'POLLING_UNIT', 'and keeps its polling-unit tier');
END $$;

\echo ''
\echo '── the category list is config-driven ──'
DO $$
BEGIN
  PERFORM pg_temp.assert(public.is_oversight_category('Police Brutality - Extortion'),
    'matching is case-insensitive');
  PERFORM pg_temp.assert(NOT public.is_oversight_category('Flood - Flash Flood'),
    'an unrelated category is not oversight');
  PERFORM pg_temp.assert(NOT public.is_oversight_category(NULL),
    'a null type is not oversight');

  UPDATE public.app_config SET value = 'police brutality,child abuse'
   WHERE key = 'oversight_categories';
  PERFORM pg_temp.assert(public.is_oversight_category('Child abuse - Neglect'),
    'HQ can extend the list without a migration');

  UPDATE public.app_config SET value = '' WHERE key = 'oversight_categories';
  PERFORM pg_temp.assert(NOT public.is_oversight_category('Police brutality - Extortion'),
    'an empty list routes nothing to oversight');

  UPDATE public.app_config SET value = 'police brutality'
   WHERE key = 'oversight_categories';
END $$;

\echo ''
\echo '── who can read an oversight report ──'
DO $$
DECLARE v_cnt INT;
BEGIN
  -- The ward commander named as the accused.
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', 'b7000000-0000-0000-0000-0000000000a1', true);
  SELECT count(*) INTO v_cnt FROM public.alerts WHERE id = 'b7000000-0000-0000-0000-000000000001';
  PERFORM pg_temp.assert(v_cnt = 0, 'the accused ward commander cannot see the complaint');

  SELECT count(*) INTO v_cnt FROM public.alerts WHERE id = 'b7000000-0000-0000-0000-000000000002';
  PERFORM pg_temp.assert(v_cnt = 1, 'but still sees the ordinary emergency');

  -- HQ.
  PERFORM set_config('request.jwt.claim.sub', 'b7000000-0000-0000-0000-0000000000f1', true);
  SELECT count(*) INTO v_cnt FROM public.alerts WHERE id = 'b7000000-0000-0000-0000-000000000001';
  PERFORM pg_temp.assert(v_cnt = 1, 'HQ command can see it');

  -- The citizen who filed it.
  PERFORM set_config('request.jwt.claim.sub', 'b7000000-0000-0000-0000-0000000000c1', true);
  SELECT count(*) INTO v_cnt FROM public.alerts WHERE id = 'b7000000-0000-0000-0000-000000000001';
  PERFORM pg_temp.assert(v_cnt = 1, 'the reporter can still see their own complaint');

  RESET ROLE;
END $$;

\echo ''
\echo '── who can act on an oversight report ──'
DO $$
DECLARE v_status TEXT;
BEGIN
  SET LOCAL ROLE authenticated;

  -- The accused tries to close it.
  PERFORM set_config('request.jwt.claim.sub', 'b7000000-0000-0000-0000-0000000000a1', true);
  UPDATE public.alerts SET status = 'RESOLVED'
   WHERE id = 'b7000000-0000-0000-0000-000000000001';
  RESET ROLE;
  SELECT status INTO v_status FROM public.alerts
   WHERE id = 'b7000000-0000-0000-0000-000000000001';
  PERFORM pg_temp.assert(v_status = 'PENDING',
    'the accused officer cannot resolve the complaint about himself');

  -- HQ can.
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', 'b7000000-0000-0000-0000-0000000000f1', true);
  UPDATE public.alerts SET status = 'ACKNOWLEDGED'
   WHERE id = 'b7000000-0000-0000-0000-000000000001';
  RESET ROLE;
  SELECT status INTO v_status FROM public.alerts
   WHERE id = 'b7000000-0000-0000-0000-000000000001';
  PERFORM pg_temp.assert(v_status = 'ACKNOWLEDGED', 'HQ command can');

  -- A responder still works ordinary incidents.
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', 'b7000000-0000-0000-0000-0000000000a1', true);
  UPDATE public.alerts SET status = 'ACKNOWLEDGED'
   WHERE id = 'b7000000-0000-0000-0000-000000000002';
  RESET ROLE;
  SELECT status INTO v_status FROM public.alerts
   WHERE id = 'b7000000-0000-0000-0000-000000000002';
  PERFORM pg_temp.assert(v_status = 'ACKNOWLEDGED',
    'and an ordinary incident is unaffected by the new policy');
END $$;

\echo ''
\echo '── position history ──'
DO $$
DECLARE v_cnt INT;
BEGIN
  INSERT INTO public.telemetry (user_id, latitude, longitude, mode, status, battery)
  VALUES ('b7000000-0000-0000-0000-0000000000a1', 9.90, 8.90, 'responder', 'PATROLLING', 88);
  SELECT count(*) INTO v_cnt FROM public.telemetry_history
   WHERE user_id = 'b7000000-0000-0000-0000-0000000000a1';
  PERFORM pg_temp.assert(v_cnt = 1, 'the first position is recorded');

  -- Movement appends.
  INSERT INTO public.telemetry (user_id, latitude, longitude, mode, status, battery)
  VALUES ('b7000000-0000-0000-0000-0000000000a1', 9.95, 8.95, 'responder', 'PATROLLING', 86)
  ON CONFLICT (user_id) DO UPDATE SET
    latitude = EXCLUDED.latitude, longitude = EXCLUDED.longitude,
    battery = EXCLUDED.battery, updated_at = now();
  SELECT count(*) INTO v_cnt FROM public.telemetry_history
   WHERE user_id = 'b7000000-0000-0000-0000-0000000000a1';
  PERFORM pg_temp.assert(v_cnt = 2, 'movement appends a track point');

  -- A repeat with no movement does not.
  INSERT INTO public.telemetry (user_id, latitude, longitude, mode, status, battery)
  VALUES ('b7000000-0000-0000-0000-0000000000a1', 9.95, 8.95, 'responder', 'PATROLLING', 84)
  ON CONFLICT (user_id) DO UPDATE SET
    battery = EXCLUDED.battery, updated_at = now();
  SELECT count(*) INTO v_cnt FROM public.telemetry_history
   WHERE user_id = 'b7000000-0000-0000-0000-0000000000a1';
  PERFORM pg_temp.assert(v_cnt = 2, 'a stationary heartbeat does not');

  -- A status change does, even standing still.
  INSERT INTO public.telemetry (user_id, latitude, longitude, mode, status, battery)
  VALUES ('b7000000-0000-0000-0000-0000000000a1', 9.95, 8.95, 'responder', 'ON_SITE', 84)
  ON CONFLICT (user_id) DO UPDATE SET status = EXCLUDED.status, updated_at = now();
  SELECT count(*) INTO v_cnt FROM public.telemetry_history
   WHERE user_id = 'b7000000-0000-0000-0000-0000000000a1';
  PERFORM pg_temp.assert(v_cnt = 3, 'a status change is a track point even without movement');

  PERFORM pg_temp.assert(
    (SELECT count(*) FROM public.telemetry
      WHERE user_id = 'b7000000-0000-0000-0000-0000000000a1') = 1,
    'telemetry still holds exactly one current row per user');
END $$;

\echo ''
\echo '── history retention ──'
DO $$
DECLARE v_deleted INT; v_left INT;
BEGIN
  INSERT INTO public.telemetry_history (user_id, latitude, longitude, recorded_at)
  VALUES ('b7000000-0000-0000-0000-0000000000a1', 1, 1, now() - interval '200 days');

  UPDATE public.app_config SET value = '90'
   WHERE key = 'telemetry_history_retention_days';
  v_deleted := public.prune_telemetry_history();
  PERFORM pg_temp.assert(v_deleted = 1, 'pruning removes a point past the retention window');

  SELECT count(*) INTO v_left FROM public.telemetry_history
   WHERE user_id = 'b7000000-0000-0000-0000-0000000000a1';
  PERFORM pg_temp.assert(v_left = 3, 'and leaves the recent track intact');
END $$;

\echo ''
\echo '── a track is not public ──'
DO $$
DECLARE v_cnt INT;
BEGIN
  SET LOCAL ROLE anon;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  SELECT count(*) INTO v_cnt FROM public.telemetry_history;
  PERFORM pg_temp.assert(v_cnt = 0, 'anon cannot read any position history');
  RESET ROLE;

  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', 'b7000000-0000-0000-0000-0000000000c1', true);
  SELECT count(*) INTO v_cnt FROM public.telemetry_history;
  PERFORM pg_temp.assert(v_cnt = 0, 'a citizen cannot read a responder track');
  RESET ROLE;
END $$;

\echo ''
\echo '── debrief has its own column ──'
DO $$
DECLARE r RECORD;
BEGIN
  UPDATE public.alerts
     SET debrief = 'Scene secured, two arrests.',
         debrief_by = 'hq@test.local',
         debrief_at = now(),
         ai_summary = 'machine summary'
   WHERE id = 'b7000000-0000-0000-0000-000000000002';

  SELECT debrief, ai_summary INTO r FROM public.alerts
   WHERE id = 'b7000000-0000-0000-0000-000000000002';
  PERFORM pg_temp.assert(r.debrief = 'Scene secured, two arrests.',
    'the officer report is stored on its own');
  PERFORM pg_temp.assert(r.ai_summary = 'machine summary',
    'and does not overwrite the machine summary');
END $$;

\echo ''
\echo '✓ escalation follow-ups: all assertions passed'

ROLLBACK;
