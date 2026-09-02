-- Behaviour test for 20260902000000_per_user_emergency_pins.sql.
--
-- Runs inside scripts/verify_rls_migration.sh against a real PostgreSQL, after
-- the migration is applied. Impersonates users the way PostgREST does — SET
-- ROLE plus the request.jwt.claim.* GUCs — and asserts the properties that
-- matter, not just that the SQL parsed:
--
--   * the hashes are unreadable through the API, even by their owner
--   * wrong PINs are rejected and lock out after five attempts
--   * the safe PIN resolves the alert; the duress PIN marks it DURESS
--   * nobody can close someone else's alert, PIN or not
--
-- Any FAIL raises, which fails the CI job.

\set ON_ERROR_STOP on

-- Everything below runs in ONE transaction that is rolled back at the end, so
-- the test is idempotent and leaves nothing behind for the RLS behaviour test
-- that runs after it. A RAISE EXCEPTION still aborts psql with a non-zero
-- exit (ON_ERROR_STOP), which is what fails the CI job.
BEGIN;

-- Two users and an alert, created with full privileges.
RESET ROLE;
INSERT INTO auth.users (id, email) VALUES
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'pin-owner@test'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'someone-else@test')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles (id, role, full_name) VALUES
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'CITIZEN', 'PIN Owner'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'CITIZEN', 'Someone Else')
ON CONFLICT (id) DO NOTHING;

DO $$
DECLARE
  owner  constant uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  other  constant uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  alert1 constant uuid := 'cccccccc-cccc-4ccc-8ccc-ccccccccccc1';
  alert2 constant uuid := 'cccccccc-cccc-4ccc-8ccc-ccccccccccc2';
  r text;
  st text;
  i int;
BEGIN
  INSERT INTO public.alerts (id, reported_by, status, type)
  VALUES (alert1, owner, 'PENDING', 'SOS'), (alert2, owner, 'PENDING', 'SOS')
  ON CONFLICT (id) DO NOTHING;

  -- ── as the owner, before any PIN exists ──────────────────────────────────
  PERFORM set_config('request.jwt.claim.sub', owner::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  SET LOCAL ROLE authenticated;

  IF public.has_emergency_pins() THEN RAISE EXCEPTION 'FAIL: has_emergency_pins true before set'; END IF;
  r := public.resolve_emergency(alert1, '1234');
  IF r <> 'UNSET' THEN RAISE EXCEPTION 'FAIL: expected UNSET before pins set, got %', r; END IF;
  RAISE NOTICE 'PASS: no PIN configured reports UNSET, never resolves';

  -- ── validation ───────────────────────────────────────────────────────────
  BEGIN
    PERFORM public.set_emergency_pins('1234', '1234');
    RAISE EXCEPTION 'FAIL: identical safe and duress PINs were accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    RAISE NOTICE 'PASS: identical PINs rejected';
  END;
  BEGIN
    PERFORM public.set_emergency_pins('12', '9999');
    RAISE EXCEPTION 'FAIL: a 2-digit PIN was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    RAISE NOTICE 'PASS: too-short PIN rejected';
  END;

  PERFORM public.set_emergency_pins('1234', '9999');
  IF NOT public.has_emergency_pins() THEN RAISE EXCEPTION 'FAIL: has_emergency_pins false after set'; END IF;
  RAISE NOTICE 'PASS: PINs set';

  -- ── the hashes must be unreadable through the API, even to their owner ───
  BEGIN
    PERFORM * FROM public.emergency_pins;
    RAISE EXCEPTION 'FAIL: authenticated could SELECT from emergency_pins';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'PASS: emergency_pins is unreadable through the API (%)', SQLERRM;
  END;
  BEGIN
    PERFORM public._check_emergency_pin(owner, '1234');
    RAISE EXCEPTION 'FAIL: authenticated could call the internal checker directly';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'PASS: internal checker is not callable from the API';
  END;

  -- ── wrong PIN, and lockout after five ────────────────────────────────────
  FOR i IN 1..5 LOOP
    r := public.resolve_emergency(alert1, '0000');
    IF r <> 'INVALID' THEN RAISE EXCEPTION 'FAIL: attempt % expected INVALID, got %', i, r; END IF;
  END LOOP;
  r := public.resolve_emergency(alert1, '1234');   -- the RIGHT pin, while locked
  IF r <> 'LOCKED' THEN RAISE EXCEPTION 'FAIL: expected LOCKED after 5 failures, got %', r; END IF;
  SELECT status INTO st FROM public.alerts WHERE id = alert1;
  IF st <> 'PENDING' THEN RAISE EXCEPTION 'FAIL: alert changed while locked (%)', st; END IF;
  RAISE NOTICE 'PASS: five wrong PINs lock entry; a correct PIN does nothing while locked';

  -- clear the lock with full privileges, then continue as the owner
  RESET ROLE;
  UPDATE public.emergency_pins SET failed_attempts = 0, locked_until = NULL WHERE user_id = owner;
  PERFORM set_config('request.jwt.claim.sub', owner::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  SET LOCAL ROLE authenticated;

  -- ── duress PIN: alert becomes DURESS, attributed ─────────────────────────
  r := public.resolve_emergency(alert1, '9999');
  IF r <> 'DURESS' THEN RAISE EXCEPTION 'FAIL: duress PIN expected DURESS, got %', r; END IF;
  SELECT status INTO st FROM public.alerts WHERE id = alert1;
  IF st <> 'DURESS' THEN RAISE EXCEPTION 'FAIL: alert status after duress PIN is %', st; END IF;
  RAISE NOTICE 'PASS: duress PIN marks the alert DURESS';

  -- ── safe PIN: alert resolved, attributed ─────────────────────────────────
  r := public.resolve_emergency(alert2, '1234');
  IF r <> 'RESOLVED' THEN RAISE EXCEPTION 'FAIL: safe PIN expected RESOLVED, got %', r; END IF;
  SELECT status INTO st FROM public.alerts WHERE id = alert2;
  IF st <> 'RESOLVED' THEN RAISE EXCEPTION 'FAIL: alert status after safe PIN is %', st; END IF;
  PERFORM 1 FROM public.alerts WHERE id = alert2 AND resolved_by = owner::text AND resolved_at IS NOT NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'FAIL: resolution not attributed to the owner'; END IF;
  RAISE NOTICE 'PASS: safe PIN resolves the alert and records who did it';

  -- ── someone else cannot close the owner''s alert, even with THEIR pin ────
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub', other::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  SET LOCAL ROLE authenticated;
  PERFORM public.set_emergency_pins('5555', '6666');
  INSERT INTO public.alerts (id, reported_by, status, type)
    VALUES ('cccccccc-cccc-4ccc-8ccc-ccccccccccc3', other, 'PENDING', 'SOS')
    ON CONFLICT (id) DO NOTHING;
  -- (that insert runs under RLS as `other`, which is allowed for own alerts)
  r := public.resolve_emergency(alert1, '5555');
  IF r <> 'NOT_FOUND' THEN RAISE EXCEPTION 'FAIL: another user closed the owner alert (%)', r; END IF;
  RAISE NOTICE 'PASS: a valid PIN cannot close someone else''s alert';

  -- ── verify without an alert (offline-queued SOS path) ────────────────────
  r := public.verify_emergency_pin('6666');
  IF r <> 'DURESS' THEN RAISE EXCEPTION 'FAIL: verify_emergency_pin expected DURESS, got %', r; END IF;
  RAISE NOTICE 'PASS: verify_emergency_pin classifies without touching alerts';

  RESET ROLE;
  RAISE NOTICE 'ALL EMERGENCY PIN CHECKS PASSED';
END $$;

ROLLBACK;
