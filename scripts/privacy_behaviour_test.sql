-- ============================================================================
-- OPERATION RAINBOW — WHO CAN WATCH WHOM, AND FOR HOW LONG
--
-- The question these assertions answer is "how is a user monitored without
-- knowing?", and three things in this schema answered it badly.
--
--   * Every staff account could read every citizen's live position, with no
--     scope of any kind — not the incident, not the jurisdiction, not the
--     shift. `is_staff()` is as true for a polling-unit officer in Wase as for
--     the HQ commander.
--   * Nothing ever deleted a position. One row per person, updated in place,
--     kept for the life of the database.
--   * Any authenticated account could post into any incident's tactical
--     channel, because the insert policy checked only that you were not
--     forging somebody else's name — never that the conversation was yours.
--
-- Run inside scripts/verify_rls_migration.sh, after the migrations.
-- ============================================================================

\set ON_ERROR_STOP on

DO $test$
DECLARE
  citizen   UUID := '88880000-0000-4000-8000-000000008001';
  bystander UUID := '88880000-0000-4000-8000-000000008002';
  officer   UUID := '88880000-0000-4000-8000-000000008003';
  a_open    UUID;
  n         INT;
  failures  INT := 0;
BEGIN
  -- Two citizens and one officer.
  INSERT INTO auth.users (id, email) VALUES
    (citizen,   'privacy-citizen@example.test'),
    (bystander, 'privacy-bystander@example.test'),
    (officer,   'privacy-officer@example.test')
  ON CONFLICT (id) DO NOTHING;

  UPDATE public.profiles SET role = 'CITIZEN'     WHERE id IN (citizen, bystander);
  UPDATE public.profiles SET role = 'UNIT_COMMAND' WHERE id = officer;

  INSERT INTO public.telemetry (user_id, latitude, longitude, mode, updated_at)
  VALUES (citizen, 9.9, 8.9, 'sos', NOW())
  ON CONFLICT (user_id) DO UPDATE
     SET latitude = 9.9, longitude = 8.9, mode = 'sos', updated_at = NOW();

  -- ── 1. While an emergency is open, staff can see the reporter ───────────
  INSERT INTO public.alerts (type, status, description, reported_by)
  VALUES ('SOS', 'PENDING', 'privacy test, open', citizen)
  RETURNING id INTO a_open;

  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', officer::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

  SELECT count(*) INTO n FROM public.telemetry WHERE user_id = citizen;
  IF n = 1 THEN
    RAISE NOTICE 'PASS  a responder can follow a citizen with a LIVE emergency';
  ELSE
    RAISE WARNING 'FAIL  a responder cannot see a live emergency''s reporter';
    failures := failures + 1;
  END IF;

  -- ── 2. Once it is closed, they cannot ───────────────────────────────────
  RESET ROLE;
  UPDATE public.alerts SET status = 'RESOLVED' WHERE id = a_open;

  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', officer::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

  SELECT count(*) INTO n FROM public.telemetry WHERE user_id = citizen;
  IF n = 0 THEN
    RAISE NOTICE 'PASS  once the emergency is resolved the citizen stops being visible';
  ELSE
    RAISE WARNING 'FAIL  a resolved incident still exposes the reporter''s position';
    failures := failures + 1;
  END IF;

  -- ── 3. A citizen with no emergency at all is never visible ──────────────
  RESET ROLE;
  INSERT INTO public.telemetry (user_id, latitude, longitude, mode, updated_at)
  VALUES (bystander, 9.8, 8.8, 'responder', NOW())
  ON CONFLICT (user_id) DO UPDATE SET updated_at = NOW();

  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', officer::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

  SELECT count(*) INTO n FROM public.telemetry WHERE user_id = bystander;
  IF n = 0 THEN
    RAISE NOTICE 'PASS  a citizen with no emergency is not on the staff feed';
  ELSE
    RAISE WARNING 'FAIL  staff can read the position of an uninvolved citizen';
    failures := failures + 1;
  END IF;

  -- ── 4. You can always see yourself ──────────────────────────────────────
  PERFORM set_config('request.jwt.claim.sub', bystander::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

  SELECT count(*) INTO n FROM public.telemetry WHERE user_id = bystander;
  IF n = 1 THEN
    RAISE NOTICE 'PASS  you can always read your own position';
  ELSE
    RAISE WARNING 'FAIL  a user cannot see their own telemetry row';
    failures := failures + 1;
  END IF;

  -- ── 5. Officers on duty remain visible to each other ────────────────────
  RESET ROLE;
  INSERT INTO public.telemetry (user_id, latitude, longitude, mode, updated_at)
  VALUES (officer, 9.7, 8.7, 'responder', NOW())
  ON CONFLICT (user_id) DO UPDATE SET updated_at = NOW();

  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', officer::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

  SELECT count(*) INTO n FROM public.telemetry WHERE user_id = officer;
  IF n = 1 THEN
    RAISE NOTICE 'PASS  the movement board still works for staff';
  ELSE
    RAISE WARNING 'FAIL  staff can no longer see staff — MOVEMENT is now empty';
    failures := failures + 1;
  END IF;

  -- ── 6. Nothing is kept forever ──────────────────────────────────────────
  RESET ROLE;
  UPDATE public.telemetry SET updated_at = NOW() - INTERVAL '3 days'
   WHERE user_id = bystander;

  PERFORM public.purge_stale_telemetry();

  SELECT count(*) INTO n FROM public.telemetry WHERE user_id = bystander;
  IF n = 0 THEN
    RAISE NOTICE 'PASS  a stale position is deleted, not kept indefinitely';
  ELSE
    RAISE WARNING 'FAIL  a three-day-old position survived the purge';
    failures := failures + 1;
  END IF;

  -- But an OPEN emergency's track is never purged on age.
  INSERT INTO public.alerts (type, status, description, reported_by)
  VALUES ('SOS', 'PENDING', 'privacy test, still open', citizen);
  UPDATE public.telemetry SET updated_at = NOW() - INTERVAL '3 days'
   WHERE user_id = citizen;

  PERFORM public.purge_stale_telemetry();

  SELECT count(*) INTO n FROM public.telemetry WHERE user_id = citizen;
  IF n = 1 THEN
    RAISE NOTICE 'PASS  an unresolved emergency keeps its last known position';
  ELSE
    RAISE WARNING 'FAIL  the purge deleted the position of a live emergency';
    failures := failures + 1;
  END IF;

  -- ── 7. The purge is not reachable from a phone ──────────────────────────
  IF has_function_privilege('anon', 'public.purge_stale_telemetry()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.purge_stale_telemetry()', 'EXECUTE') THEN
    RAISE WARNING 'FAIL  a signed-in client can delete everyone''s location history';
    failures := failures + 1;
  ELSE
    RAISE NOTICE 'PASS  only the service role can run the purge';
  END IF;

  -- ── 8. You may only write into a conversation you are part of ───────────
  RESET ROLE;
  DELETE FROM public.alerts WHERE reported_by = citizen;
  INSERT INTO public.alerts (type, status, description, reported_by)
  VALUES ('SOS', 'PENDING', 'privacy test, chat', citizen)
  RETURNING id INTO a_open;

  -- The reporter can write into their own incident.
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', citizen::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  BEGIN
    INSERT INTO public.chat_messages (alert_id, sender_id, message)
    VALUES (a_open, citizen, 'I am hiding in the shop.');
    RAISE NOTICE 'PASS  the reporter can message their own incident';
  EXCEPTION WHEN insufficient_privilege OR others THEN
    RAISE WARNING 'FAIL  the reporter cannot message their own incident: %', SQLERRM;
    failures := failures + 1;
  END;

  -- An unrelated citizen cannot.
  PERFORM set_config('request.jwt.claim.sub', bystander::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  BEGIN
    INSERT INTO public.chat_messages (alert_id, sender_id, message)
    VALUES (a_open, bystander, 'Police are gone, come outside.');
    RAISE WARNING 'FAIL  an unrelated account injected a message into somebody '
                  'else''s emergency channel';
    failures := failures + 1;
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'PASS  an unrelated account cannot write into that channel';
  END;

  -- Staff can, because whoever responds may not be whoever it was assigned to.
  PERFORM set_config('request.jwt.claim.sub', officer::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  BEGIN
    INSERT INTO public.chat_messages (alert_id, sender_id, message)
    VALUES (a_open, officer, 'Unit on the way, stay where you are.');
    RAISE NOTICE 'PASS  a responder can still answer the channel';
  EXCEPTION WHEN insufficient_privilege OR others THEN
    RAISE WARNING 'FAIL  a responder cannot answer the channel: %', SQLERRM;
    failures := failures + 1;
  END;

  -- And nobody can post under another person's name.
  BEGIN
    INSERT INTO public.chat_messages (alert_id, sender_id, message)
    VALUES (a_open, citizen, 'Forged: it is safe now.');
    RAISE WARNING 'FAIL  an officer posted a message signed as the citizen';
    failures := failures + 1;
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'PASS  a message cannot be signed with somebody else''s name';
  END;

  RESET ROLE;

  -- ── Clean up so the file can run twice ──────────────────────────────────
  DELETE FROM public.chat_messages
   WHERE sender_id IN (citizen, bystander, officer);
  DELETE FROM public.alerts     WHERE reported_by IN (citizen, bystander);
  DELETE FROM public.telemetry  WHERE user_id IN (citizen, bystander, officer);
  DELETE FROM public.profiles   WHERE id IN (citizen, bystander, officer);
  DELETE FROM auth.users        WHERE id IN (citizen, bystander, officer);

  IF failures > 0 THEN
    RAISE EXCEPTION 'PRIVACY TEST FAILED (% assertion(s))', failures;
  END IF;
  RAISE NOTICE 'ALL PRIVACY ASSERTIONS PASSED';
END
$test$;
