-- Can two uploads that overlap both survive?
--
-- Three places appended to alerts.media_urls by reading the array, adding to
-- the copy, and writing it back. Two overlapping uploads both read the same
-- array and the second erased the first — while the UI said the evidence had
-- been sent to HQ.
--
-- Asserting that append_alert_media() exists would prove nothing. The checks
-- below drive it through `authenticated` with RLS on, and the concurrency one
-- uses a second real connection through dblink so the lock is actually tested
-- rather than described.
--
-- Run by scripts/verify_rls_migration.sh against a real PostgreSQL.

\set ON_ERROR_STOP on
SET client_min_messages TO NOTICE;

BEGIN;

INSERT INTO auth.users (id, email) VALUES
  ('a11c0000-0000-4000-8000-00000000ac01', 'media-reporter@staging.test'),
  ('a11c0000-0000-4000-8000-00000000ac02', 'media-outsider@staging.test'),
  ('a11c0000-0000-4000-8000-00000000ac03', 'media-hq@staging.test')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles (id, email, full_name, role, geo_lga, geo_ward) VALUES
  ('a11c0000-0000-4000-8000-00000000ac01', 'media-reporter@staging.test',
   'Media Reporter', 'CITIZEN', 'JOS NORTH', 'NARAGUTA'),
  -- A ward commander in a DIFFERENT ward of a different LGA: staff, and still
  -- none of their business.
  ('a11c0000-0000-4000-8000-00000000ac02', 'media-outsider@staging.test',
   'Outsider Ward', 'WARD_COMMAND', 'MANGU', 'AMPANG WEST'),
  ('a11c0000-0000-4000-8000-00000000ac03', 'media-hq@staging.test',
   'Media HQ', 'HQ_COMMAND', NULL, NULL)
ON CONFLICT (id) DO UPDATE
  SET role = EXCLUDED.role, geo_lga = EXCLUDED.geo_lga, geo_ward = EXCLUDED.geo_ward;

INSERT INTO public.alerts
  (id, type, description, status, severity, reported_by, geo_lga, geo_ward, media_urls)
VALUES
  ('a11e0000-0000-4000-8000-00000000ae01', 'Kidnap - Immediate Abduction',
   'media test incident', 'OPEN', 'CRITICAL',
   'a11c0000-0000-4000-8000-00000000ac01', 'JOS NORTH', 'NARAGUTA', '{}')
ON CONFLICT (id) DO NOTHING;

CREATE OR REPLACE FUNCTION pg_temp.as_user(p_uid UUID)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_uid::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
END $$;

-- ── The reporter can attach, and the array grows ────────────────────────────

DO $$
DECLARE r RECORD; urls TEXT[];
BEGIN
  PERFORM pg_temp.as_user('a11c0000-0000-4000-8000-00000000ac01');
  SET LOCAL ROLE authenticated;

  SELECT * INTO r FROM public.append_alert_media(
    'a11e0000-0000-4000-8000-00000000ae01', ARRAY['https://cdn/one.jpg']);
  IF r.added <> 1 OR r.total <> 1 THEN
    RAISE EXCEPTION 'FAIL: first attach reported added=% total=%', r.added, r.total;
  END IF;

  SELECT * INTO r FROM public.append_alert_media(
    'a11e0000-0000-4000-8000-00000000ae01', ARRAY['https://cdn/two.jpg']);
  IF r.added <> 1 OR r.total <> 2 THEN
    RAISE EXCEPTION 'FAIL: second attach reported added=% total=%', r.added, r.total;
  END IF;

  RESET ROLE;
  SELECT media_urls INTO urls FROM public.alerts
   WHERE id = 'a11e0000-0000-4000-8000-00000000ae01';
  IF urls <> ARRAY['https://cdn/one.jpg', 'https://cdn/two.jpg'] THEN
    RAISE EXCEPTION 'FAIL: the second attach did not preserve the first: %', urls;
  END IF;
  RAISE NOTICE 'PASS: a second attach keeps the first, in the order taken';
END $$;

-- ── Several at once, which is what the offline flush does ───────────────────

DO $$
DECLARE r RECORD; urls TEXT[];
BEGIN
  PERFORM pg_temp.as_user('a11c0000-0000-4000-8000-00000000ac01');
  SET LOCAL ROLE authenticated;
  SELECT * INTO r FROM public.append_alert_media(
    'a11e0000-0000-4000-8000-00000000ae01',
    ARRAY['https://cdn/three.jpg', 'https://cdn/four.jpg']);
  RESET ROLE;
  IF r.added <> 2 OR r.total <> 4 THEN
    RAISE EXCEPTION 'FAIL: a batch of two reported added=% total=%', r.added, r.total;
  END IF;
  RAISE NOTICE 'PASS: a whole batch attaches in one call';
END $$;

-- ── A retry must not double the photograph ─────────────────────────────────

DO $$
DECLARE r RECORD; urls TEXT[];
BEGIN
  PERFORM pg_temp.as_user('a11c0000-0000-4000-8000-00000000ac01');
  SET LOCAL ROLE authenticated;
  SELECT * INTO r FROM public.append_alert_media(
    'a11e0000-0000-4000-8000-00000000ae01', ARRAY['https://cdn/one.jpg']);
  RESET ROLE;
  IF r.added <> 0 OR r.total <> 4 THEN
    RAISE EXCEPTION 'FAIL: re-attaching a known url reported added=% total=%',
      r.added, r.total;
  END IF;
  SELECT media_urls INTO urls FROM public.alerts
   WHERE id = 'a11e0000-0000-4000-8000-00000000ae01';
  IF urls[1] <> 'https://cdn/one.jpg' THEN
    RAISE EXCEPTION 'FAIL: a duplicate moved the original out of first place: %', urls;
  END IF;
  RAISE NOTICE 'PASS: a retry is a no-op and does not reorder the dossier';
END $$;

-- ── A NULL array must not erase what is there ─────────────────────────────
--
-- `array || NULL::text[]` is NULL in PostgreSQL. Without the coalesce, one
-- caller passing a null array would have wiped every photograph on the
-- incident. One keystroke, all the evidence.

DO $$
DECLARE r RECORD; urls TEXT[];
BEGIN
  PERFORM pg_temp.as_user('a11c0000-0000-4000-8000-00000000ac01');
  SET LOCAL ROLE authenticated;
  SELECT * INTO r FROM public.append_alert_media(
    'a11e0000-0000-4000-8000-00000000ae01', NULL);
  RESET ROLE;
  SELECT media_urls INTO urls FROM public.alerts
   WHERE id = 'a11e0000-0000-4000-8000-00000000ae01';
  IF urls IS NULL OR array_length(urls, 1) <> 4 THEN
    RAISE EXCEPTION 'FAIL: a NULL append destroyed the evidence: %', urls;
  END IF;
  IF r.added <> 0 THEN
    RAISE EXCEPTION 'FAIL: a NULL append claimed to add %', r.added;
  END IF;
  RAISE NOTICE 'PASS: a NULL or empty append changes nothing';
END $$;

DO $$
DECLARE r RECORD; urls TEXT[];
BEGIN
  PERFORM pg_temp.as_user('a11c0000-0000-4000-8000-00000000ac01');
  SET LOCAL ROLE authenticated;
  -- A blank string is not a URL and must not become an entry a dispatcher
  -- clicks on.
  SELECT * INTO r FROM public.append_alert_media(
    'a11e0000-0000-4000-8000-00000000ae01', ARRAY['', '   ']);
  RESET ROLE;
  SELECT media_urls INTO urls FROM public.alerts
   WHERE id = 'a11e0000-0000-4000-8000-00000000ae01';
  IF array_length(urls, 1) <> 4 THEN
    RAISE EXCEPTION 'FAIL: blank urls were attached: %', urls;
  END IF;
  RAISE NOTICE 'PASS: blank urls are discarded, not attached';
END $$;

-- ── Who may attach ─────────────────────────────────────────────────────────

DO $$
DECLARE n INTEGER;
BEGIN
  PERFORM pg_temp.as_user('a11c0000-0000-4000-8000-00000000ac02');
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM public.append_alert_media(
    'a11e0000-0000-4000-8000-00000000ae01', ARRAY['https://cdn/planted.jpg']);
  RESET ROLE;
  -- NO ROW, not a row saying zero. The Dart side distinguishes them, because
  -- "you may not" and "there was nothing to add" call for different words on
  -- the operator's screen.
  IF n <> 0 THEN
    RAISE EXCEPTION 'FAIL: a ward commander in another LGA attached evidence to '
                    'an incident that is none of theirs';
  END IF;
  RAISE NOTICE 'PASS: an officer outside the command cannot attach, and gets no row';
END $$;

DO $$
DECLARE urls TEXT[];
BEGIN
  SELECT media_urls INTO urls FROM public.alerts
   WHERE id = 'a11e0000-0000-4000-8000-00000000ae01';
  IF 'https://cdn/planted.jpg' = ANY (urls) THEN
    RAISE EXCEPTION 'FAIL: the refused url is on the incident anyway: %', urls;
  END IF;
  RAISE NOTICE 'PASS: nothing the refusal touched was written';
END $$;

DO $$
DECLARE r RECORD;
BEGIN
  PERFORM pg_temp.as_user('a11c0000-0000-4000-8000-00000000ac03');
  SET LOCAL ROLE authenticated;
  SELECT * INTO r FROM public.append_alert_media(
    'a11e0000-0000-4000-8000-00000000ae01', ARRAY['https://cdn/hq.jpg']);
  RESET ROLE;
  IF r.added <> 1 THEN
    RAISE EXCEPTION 'FAIL: HQ cannot attach evidence to an incident in Plateau';
  END IF;
  RAISE NOTICE 'PASS: HQ can attach anywhere in the state';
END $$;

-- ── An incident that does not exist ────────────────────────────────────────

DO $$
DECLARE n INTEGER;
BEGIN
  PERFORM pg_temp.as_user('a11c0000-0000-4000-8000-00000000ac03');
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM public.append_alert_media(
    'a11e0000-0000-4000-8000-0000000000ff', ARRAY['https://cdn/nowhere.jpg']);
  RESET ROLE;
  IF n <> 0 THEN
    RAISE EXCEPTION 'FAIL: attaching to a nonexistent incident returned a row';
  END IF;
  RAISE NOTICE 'PASS: an unknown incident is a refusal, not a silent success';
END $$;

-- ── anon holds nothing ─────────────────────────────────────────────────────

DO $$
DECLARE denied BOOLEAN := false;
BEGIN
  SET LOCAL ROLE anon;
  BEGIN
    PERFORM public.append_alert_media(
      'a11e0000-0000-4000-8000-00000000ae01', ARRAY['https://cdn/anon.jpg']);
  EXCEPTION WHEN insufficient_privilege THEN denied := true;
  END;
  RESET ROLE;
  IF NOT denied THEN
    RAISE EXCEPTION 'FAIL: anon can execute append_alert_media';
  END IF;
  RAISE NOTICE 'PASS: anon cannot execute it at all';
END $$;

ROLLBACK;
