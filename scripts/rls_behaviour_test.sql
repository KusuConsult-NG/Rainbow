-- ============================================================================
-- Behavioural proof for 20260813000000_rls_least_privilege.sql.
--
-- Structure (which policies exist) is not the same as behaviour (what a caller
-- can actually do). These assertions impersonate anon, a citizen and a command
-- user the way PostgREST does — SET ROLE plus the request.jwt.claim.* GUCs —
-- and fail loudly if any of them can do something they should not.
--
-- Any RAISE EXCEPTION here means the migration is NOT safe to run.
-- ============================================================================

\set ON_ERROR_STOP on

-- Fixtures, inserted as superuser (bypasses RLS).
INSERT INTO auth.users (id, email) VALUES
  ('11111111-1111-4111-8111-111111111111', 'citizen@test'),
  ('22222222-2222-4222-8222-222222222222', 'commander@test'),
  ('33333333-3333-4333-8333-333333333333', 'other@test')
ON CONFLICT DO NOTHING;

INSERT INTO public.profiles (id, email, full_name, role) VALUES
  ('11111111-1111-4111-8111-111111111111', 'citizen@test',   'A Citizen',   'CITIZEN'),
  ('22222222-2222-4222-8222-222222222222', 'commander@test', 'A Commander', 'HQ_COMMAND'),
  ('33333333-3333-4333-8333-333333333333', 'other@test',     'Other Person','CITIZEN')
ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role;

INSERT INTO public.telemetry (user_id, latitude, longitude, mode) VALUES
  ('11111111-1111-4111-8111-111111111111', 9.89, 8.85, 'sos'),
  ('33333333-3333-4333-8333-333333333333', 9.50, 8.50, 'sos')
ON CONFLICT (user_id) DO NOTHING;

INSERT INTO public.alerts (id, type, status, severity, description, reported_by) VALUES
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'SOS', 'PENDING', 'CRITICAL',
   'citizen SOS', '11111111-1111-4111-8111-111111111111')
ON CONFLICT DO NOTHING;

GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO authenticated;

DO $$
DECLARE n INT; ok BOOLEAN;
BEGIN
  -- ── 1. anon is locked out entirely ────────────────────────────────────────
  SET LOCAL ROLE anon;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', 'anon', true);

  BEGIN
    SELECT count(*) INTO n FROM public.profiles;
    IF n > 0 THEN RAISE EXCEPTION 'FAIL: anon read % profile rows', n; END IF;
  EXCEPTION WHEN insufficient_privilege THEN NULL;  -- denied outright: also fine
  END;

  BEGIN
    SELECT count(*) INTO n FROM public.telemetry;
    IF n > 0 THEN RAISE EXCEPTION 'FAIL: anon read % telemetry rows (live GPS)', n; END IF;
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    SELECT count(*) INTO n FROM public.alerts;
    IF n > 0 THEN RAISE EXCEPTION 'FAIL: anon read % alert rows', n; END IF;
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  RAISE NOTICE 'PASS: anon cannot read profiles, telemetry or alerts';

  -- ── 2. a citizen sees only themselves ─────────────────────────────────────
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

  SELECT count(*) INTO n FROM public.profiles;
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL: citizen saw % profiles, expected only their own', n; END IF;

  SELECT count(*) INTO n FROM public.telemetry;
  IF n <> 1 THEN
    RAISE EXCEPTION 'FAIL: citizen saw % telemetry rows — must not see another persons live GPS', n;
  END IF;
  RAISE NOTICE 'PASS: citizen sees only their own profile and telemetry';

  -- ── 3. PRIVILEGE ESCALATION — the check C-4 depends on ────────────────────
  -- Before the migration, `FOR ALL USING (auth.uid() = id)` let any citizen set
  -- their own role to HQ_COMMAND and pass the API layer's requireRole().
  ok := false;
  BEGIN
    UPDATE public.profiles
       SET role = 'HQ_COMMAND'
     WHERE id = '11111111-1111-4111-8111-111111111111';
  EXCEPTION WHEN OTHERS THEN
    ok := true;
    RAISE NOTICE 'PASS: self role escalation blocked (%)', SQLERRM;
  END;
  IF NOT ok THEN
    RAISE EXCEPTION 'FAIL: a citizen escalated their own role to HQ_COMMAND';
  END IF;

  -- A benign self-update on a non-privileged column must still work.
  UPDATE public.profiles
     SET full_name = 'A Citizen Renamed'
   WHERE id = '11111111-1111-4111-8111-111111111111';
  RAISE NOTICE 'PASS: benign self-update still permitted';

  -- ── 4. a citizen cannot write someone else's telemetry ────────────────────
  ok := false;
  BEGIN
    UPDATE public.telemetry SET latitude = 0, longitude = 0
     WHERE user_id = '33333333-3333-4333-8333-333333333333';
    GET DIAGNOSTICS n = ROW_COUNT;
    IF n = 0 THEN ok := true; END IF;
  EXCEPTION WHEN OTHERS THEN ok := true;
  END;
  IF NOT ok THEN
    RAISE EXCEPTION 'FAIL: a citizen falsified another users GPS position';
  END IF;
  RAISE NOTICE 'PASS: citizen cannot falsify another users telemetry';

  -- ── 5. command staff can still do their job ───────────────────────────────
  PERFORM set_config('request.jwt.claim.sub', '22222222-2222-4222-8222-222222222222', true);

  SELECT count(*) INTO n FROM public.telemetry;
  IF n < 2 THEN
    RAISE EXCEPTION 'FAIL: command user saw only % telemetry rows — dispatch needs all', n;
  END IF;

  SELECT count(*) INTO n FROM public.alerts;
  IF n < 1 THEN RAISE EXCEPTION 'FAIL: command user cannot see alerts'; END IF;

  SELECT count(*) INTO n FROM public.profiles;
  IF n < 3 THEN RAISE EXCEPTION 'FAIL: command user saw only % profiles', n; END IF;
  RAISE NOTICE 'PASS: command staff retain full operational visibility';

  -- ── 6. a citizen cannot push a state-wide advisory ────────────────────────
  PERFORM set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', true);
  ok := false;
  BEGIN
    INSERT INTO public.system_alerts (title, message) VALUES ('FAKE', 'state-wide panic');
  EXCEPTION WHEN OTHERS THEN
    ok := true;
    RAISE NOTICE 'PASS: citizen cannot broadcast a system alert (%)', SQLERRM;
  END;
  IF NOT ok THEN
    RAISE EXCEPTION 'FAIL: a citizen pushed a state-wide system alert';
  END IF;

  RESET ROLE;
  RAISE NOTICE '=== ALL RLS BEHAVIOURAL ASSERTIONS PASSED ===';
END $$;
