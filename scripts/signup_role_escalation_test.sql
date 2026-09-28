-- ============================================================================
-- OPERATION RAINBOW — CAN A STRANGER MAKE THEMSELVES A COMMANDER?
--
-- The security model in README.md says:
--
--   "Roles come from `profiles.role`, which a database trigger makes
--    non-self-writable. Nothing reads `user_metadata`, which the client can
--    set."
--
-- The second sentence is true of the POLICIES. It is not true of the trigger
-- that creates the profile in the first place:
--
--   handle_new_user()  AFTER INSERT ON auth.users   (SECURITY DEFINER)
--     role := COALESCE(NEW.raw_user_meta_data->>'role', 'CITIZEN')
--
-- `raw_user_meta_data` is exactly `options.data` from `supabase.auth.signUp`,
-- written by whoever is signing up, using the anon key — which ships inside the
-- APK and inside the browser bundle, by design.
--
-- Meanwhile the guard that enforces "non-self-writable":
--
--   profiles_no_privilege_escalation  BEFORE UPDATE ON public.profiles
--
-- only fires on UPDATE. The escalation does not need an update: the role is
-- chosen at INSERT, by the signup itself, before any of it applies.
--
-- This file asserts the behaviour both ways round, so the fix is provable
-- rather than argued:
--
--   1. a signup asking for HQ_COMMAND must NOT become HQ_COMMAND
--   2. a signup asking for nothing must still become CITIZEN
--   3. a legitimate provisioning path (service_role) must still be able to set
--      a real role, or the console cannot create staff at all
--   4. the existing UPDATE guard must still refuse a self-promotion
--
-- Run inside scripts/verify_rls_migration.sh, after the migrations.
-- ============================================================================

\set ON_ERROR_STOP on

DO $test$
DECLARE
  stranger  UUID := '99990000-0000-4000-8000-000000009001';
  plain     UUID := '99990000-0000-4000-8000-000000009002';
  staff     UUID := '99990000-0000-4000-8000-000000009003';
  got       TEXT;
  failures  INT := 0;
BEGIN
  -- ── 1. The attack ────────────────────────────────────────────────────────
  -- A stranger signs up with the public anon key and asks to be a commander.
  INSERT INTO auth.users (id, email, raw_user_meta_data)
  VALUES (
    stranger,
    'stranger@example.test',
    '{"full_name": "A Stranger", "role": "HQ_COMMAND"}'::jsonb
  );

  SELECT role INTO got FROM public.profiles WHERE id = stranger;

  IF got = 'HQ_COMMAND' THEN
    RAISE WARNING 'FAIL  a signup that asked for HQ_COMMAND got HQ_COMMAND';
    failures := failures + 1;
  ELSIF got = 'CITIZEN' THEN
    RAISE NOTICE 'PASS  a signup asking for HQ_COMMAND is created as CITIZEN';
  ELSE
    RAISE WARNING 'FAIL  a signup asking for HQ_COMMAND became %', got;
    failures := failures + 1;
  END IF;

  -- ── 2. The ordinary case still works ─────────────────────────────────────
  INSERT INTO auth.users (id, email, raw_user_meta_data)
  VALUES (plain, 'plain@example.test', '{"full_name": "Ordinary Citizen"}'::jsonb);

  SELECT role INTO got FROM public.profiles WHERE id = plain;
  IF got = 'CITIZEN' THEN
    RAISE NOTICE 'PASS  an ordinary signup is a CITIZEN';
  ELSE
    RAISE WARNING 'FAIL  an ordinary signup became % instead of CITIZEN', got;
    failures := failures + 1;
  END IF;

  -- The display name must still survive; the fix must narrow role only.
  SELECT full_name INTO got FROM public.profiles WHERE id = plain;
  IF got = 'Ordinary Citizen' THEN
    RAISE NOTICE 'PASS  full_name from the signup is still honoured';
  ELSE
    RAISE WARNING 'FAIL  full_name was % , expected "Ordinary Citizen"', got;
    failures := failures + 1;
  END IF;

  -- ── 3. Real provisioning must still be possible ──────────────────────────
  -- Staff are created by an operator holding the service key, which is what
  -- `supabase.auth.admin` and any server-side route use. That path sets the
  -- role on the PROFILE, not through client metadata.
  INSERT INTO auth.users (id, email, raw_user_meta_data)
  VALUES (staff, 'officer@example.test', '{"full_name": "Sgt. Real Officer"}'::jsonb);

  UPDATE public.profiles SET role = 'RESPONDER' WHERE id = staff;

  SELECT role INTO got FROM public.profiles WHERE id = staff;
  IF got = 'RESPONDER' THEN
    RAISE NOTICE 'PASS  a privileged caller can still provision a RESPONDER';
  ELSE
    RAISE WARNING 'FAIL  privileged provisioning produced %', got;
    failures := failures + 1;
  END IF;

  -- ── 4. The existing UPDATE guard is untouched ────────────────────────────
  -- Self-promotion by an authenticated user must still be refused. auth.uid()
  -- is NULL in this session, which the guard treats as a privileged caller, so
  -- impersonate the stranger first.
  --
  -- The target role is computed, not hardcoded. An earlier version promoted to
  -- 'HQ_COMMAND' unconditionally — and while the signup hole was open the
  -- stranger was ALREADY HQ_COMMAND, so the UPDATE changed nothing, the guard
  -- had nothing to refuse, and this assertion reported a second vulnerability
  -- that did not exist. A test that only works when the bug above is fixed is
  -- not a test.
  SELECT role INTO got FROM public.profiles WHERE id = stranger;
  PERFORM set_config('request.jwt.claim.sub', stranger::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

  BEGIN
    UPDATE public.profiles
       SET role = CASE WHEN got = 'HQ_COMMAND' THEN 'LGA_COMMAND' ELSE 'HQ_COMMAND' END
     WHERE id = stranger;
    RAISE WARNING 'FAIL  a user promoted themselves by UPDATE (from %)', got;
    failures := failures + 1;
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'PASS  self-promotion by UPDATE is still refused';
  END;

  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', '', true);

  -- ── Clean up, so the file can run twice ──────────────────────────────────
  DELETE FROM public.profiles WHERE id IN (stranger, plain, staff);
  DELETE FROM auth.users      WHERE id IN (stranger, plain, staff);

  IF failures > 0 THEN
    RAISE EXCEPTION 'SIGNUP ROLE ESCALATION TEST FAILED (% assertion(s))', failures;
  END IF;
  RAISE NOTICE 'ALL SIGNUP ROLE ASSERTIONS PASSED';
END
$test$;
