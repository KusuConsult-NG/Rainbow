-- ============================================================================
-- OPERATION RAINBOW — CAN ANYBODY GET AT AN SMS DEVICE KEY?
--
-- The key decides what the SMS fallback is worth. If it can be read through
-- the API, anyone who can read it can both forge an emergency from that
-- citizen and decrypt every alert that citizen sends over SMS.
--
-- The assertions are about the things that would hurt:
--   * a signed-in user gets a key, once, and cannot read it back
--   * nobody can read the table at all through the API roles
--   * registering again retires the old key rather than accumulating them
--   * a revoked key is not usable for ingest
--   * ingest is reachable by the service role and by nothing else
--   * an anonymous caller gets nothing
--
-- Run inside scripts/verify_rls_migration.sh, after the migrations.
-- ============================================================================

\set ON_ERROR_STOP on

DO $test$
DECLARE
  alice    UUID := '99990000-0000-4000-8000-000000009001';
  bob      UUID := '99990000-0000-4000-8000-000000009002';
  ref1     BYTEA;
  key1     BYTEA;
  ref2     BYTEA;
  key2     BYTEA;
  got_key  BYTEA;
  got_uid  UUID;
  n        INT;
  failures INT := 0;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (alice, 'sms-alice@example.test'),
    (bob,   'sms-bob@example.test')
  ON CONFLICT (id) DO NOTHING;

  -- ── 1. A signed-in user can register, and gets real material ─────────────
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', alice::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

  SELECT r.device_ref, r.secret INTO ref1, key1
    FROM public.register_sms_device() r;

  IF octet_length(ref1) = 4 AND octet_length(key1) = 32 THEN
    RAISE NOTICE 'PASS  registration issues a 4-byte ref and a 32-byte key';
  ELSE
    RAISE WARNING 'FAIL  registration returned % / % bytes',
      octet_length(ref1), octet_length(key1);
    failures := failures + 1;
  END IF;

  -- ── 2. And cannot read it back, ever ─────────────────────────────────────
  BEGIN
    SELECT k.secret INTO got_key FROM public.sms_device_keys k
     WHERE k.device_ref = ref1;
    IF got_key IS NULL THEN
      RAISE NOTICE 'PASS  the owner cannot read their own key back';
    ELSE
      RAISE WARNING 'FAIL  the key is readable through the API';
      failures := failures + 1;
    END IF;
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'PASS  the table is not even selectable by the API roles';
  END;

  -- ── 3. Nor can anybody else's ────────────────────────────────────────────
  PERFORM set_config('request.jwt.claim.sub', bob::text, true);
  BEGIN
    SELECT count(*) INTO n FROM public.sms_device_keys;
    IF n = 0 THEN
      RAISE NOTICE 'PASS  another user cannot enumerate the key table';
    ELSE
      RAISE WARNING 'FAIL  another user can see % row(s)', n;
      failures := failures + 1;
    END IF;
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'PASS  another user cannot even count the key table';
  END;

  -- ── 4. Registering again retires the old key ─────────────────────────────
  PERFORM set_config('request.jwt.claim.sub', alice::text, true);
  SELECT r.device_ref, r.secret INTO ref2, key2
    FROM public.register_sms_device() r;

  IF ref2 <> ref1 AND key2 <> key1 THEN
    RAISE NOTICE 'PASS  re-registering issues fresh material';
  ELSE
    RAISE WARNING 'FAIL  re-registering reused the previous key';
    failures := failures + 1;
  END IF;

  RESET ROLE;
  SELECT count(*) INTO n FROM public.sms_device_keys
   WHERE user_id = alice AND revoked_at IS NULL;
  IF n = 1 THEN
    RAISE NOTICE 'PASS  only one key is live per user at a time';
  ELSE
    RAISE WARNING 'FAIL  % live keys for one user — a stolen handset keeps '
                  'working after the owner re-registers', n;
    failures := failures + 1;
  END IF;

  -- ── 5. The retired key no longer opens anything ──────────────────────────
  SELECT s.user_id, s.secret INTO got_uid, got_key
    FROM public.sms_key_for_ingest(ref1) s;
  IF got_uid IS NULL THEN
    RAISE NOTICE 'PASS  a retired key is refused at ingest';
  ELSE
    RAISE WARNING 'FAIL  a retired key still resolves at ingest';
    failures := failures + 1;
  END IF;

  -- ── 6. The live one does, and its use is recorded ────────────────────────
  SELECT s.user_id, s.secret INTO got_uid, got_key
    FROM public.sms_key_for_ingest(ref2) s;
  IF got_uid = alice AND got_key = key2 THEN
    RAISE NOTICE 'PASS  ingest resolves the live key to its owner';
  ELSE
    RAISE WARNING 'FAIL  ingest could not resolve the live key';
    failures := failures + 1;
  END IF;

  SELECT count(*) INTO n FROM public.sms_device_keys
   WHERE device_ref = ref2 AND last_used_at IS NOT NULL;
  IF n = 1 THEN
    RAISE NOTICE 'PASS  ingest stamps when a key was last used';
  ELSE
    RAISE WARNING 'FAIL  key use is not recorded, so a stolen handset leaves '
                  'no trace';
    failures := failures + 1;
  END IF;

  -- ── 7. Ingest is not reachable from a phone or a browser ─────────────────
  IF has_function_privilege('anon', 'public.sms_key_for_ingest(bytea)', 'EXECUTE')
     OR has_function_privilege('authenticated',
           'public.sms_key_for_ingest(bytea)', 'EXECUTE') THEN
    RAISE WARNING 'FAIL  a signed-in client can read every SMS device key';
    failures := failures + 1;
  ELSE
    RAISE NOTICE 'PASS  only the service role can resolve a key for ingest';
  END IF;

  -- ── 8. An anonymous caller gets nothing ──────────────────────────────────
  IF has_function_privilege('anon', 'public.register_sms_device()', 'EXECUTE') THEN
    RAISE WARNING 'FAIL  anon can mint device keys';
    failures := failures + 1;
  ELSE
    RAISE NOTICE 'PASS  anon cannot mint a device key';
  END IF;

  -- ── 9. Revocation works, and is idempotent ───────────────────────────────
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', alice::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  SELECT public.revoke_sms_device_keys() INTO n;
  IF n = 1 THEN
    RAISE NOTICE 'PASS  signing out retires the live key';
  ELSE
    RAISE WARNING 'FAIL  revocation retired % keys, expected 1', n;
    failures := failures + 1;
  END IF;

  SELECT public.revoke_sms_device_keys() INTO n;
  IF n = 0 THEN
    RAISE NOTICE 'PASS  revoking again is a no-op rather than an error';
  ELSE
    RAISE WARNING 'FAIL  revocation is not idempotent';
    failures := failures + 1;
  END IF;

  RESET ROLE;
  SELECT s.user_id INTO got_uid FROM public.sms_key_for_ingest(ref2) s;
  IF got_uid IS NULL THEN
    RAISE NOTICE 'PASS  and nothing that key signed is accepted afterwards';
  ELSE
    RAISE WARNING 'FAIL  a revoked key still resolves';
    failures := failures + 1;
  END IF;

  -- ── Clean up so the file can run twice ───────────────────────────────────
  DELETE FROM public.sms_device_keys WHERE user_id IN (alice, bob);
  DELETE FROM public.profiles        WHERE id IN (alice, bob);
  DELETE FROM auth.users             WHERE id IN (alice, bob);

  IF failures > 0 THEN
    RAISE EXCEPTION 'SMS DEVICE KEY TEST FAILED (% assertion(s))', failures;
  END IF;
  RAISE NOTICE 'ALL SMS DEVICE KEY ASSERTIONS PASSED';
END
$test$;
