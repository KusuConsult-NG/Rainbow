-- Can somebody put words in the model's mouth?
--
-- The forensic summary used to live in React state and nowhere else. It is now
-- written by the server that actually called Gemini, and the control that makes
-- that worth anything is that NOBODY signed in from a browser or a phone can
-- write one. Otherwise an operator could record "the AI concluded the responders
-- acted correctly" and nothing downstream could tell that from a real completion.
--
-- Asserting the table exists would prove nothing. Every check below runs as a
-- real account through `authenticated` with RLS on.
--
-- Run by scripts/verify_rls_migration.sh against a real PostgreSQL.

\set ON_ERROR_STOP on
SET client_min_messages TO NOTICE;

BEGIN;

INSERT INTO auth.users (id, email) VALUES
  ('a1a10000-0000-4000-8000-00000000a101', 'ai-citizen@staging.test'),
  ('a1a10000-0000-4000-8000-00000000a102', 'ai-ward-jos@staging.test'),
  ('a1a10000-0000-4000-8000-00000000a103', 'ai-ward-mangu@staging.test'),
  ('a1a10000-0000-4000-8000-00000000a104', 'ai-hq@staging.test'),
  ('a1a10000-0000-4000-8000-00000000a105', 'ai-police-liaison@staging.test')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles (id, email, full_name, role, geo_lga, geo_ward) VALUES
  ('a1a10000-0000-4000-8000-00000000a101', 'ai-citizen@staging.test',
   'AI Citizen', 'CITIZEN', 'JOS NORTH', 'ABBA NA SHEHU'),
  ('a1a10000-0000-4000-8000-00000000a102', 'ai-ward-jos@staging.test',
   'Ward Jos', 'WARD_COMMAND', 'JOS NORTH', 'ABBA NA SHEHU'),
  ('a1a10000-0000-4000-8000-00000000a103', 'ai-ward-mangu@staging.test',
   'Ward Mangu', 'WARD_COMMAND', 'MANGU', 'AMPANG WEST'),
  ('a1a10000-0000-4000-8000-00000000a104', 'ai-hq@staging.test',
   'AI HQ', 'HQ_COMMAND', NULL, NULL),
  ('a1a10000-0000-4000-8000-00000000a105', 'ai-police-liaison@staging.test',
   'Police Liaison', 'POLICE_LIAISON', NULL, NULL)
ON CONFLICT (id) DO UPDATE
  SET role = EXCLUDED.role, geo_lga = EXCLUDED.geo_lga, geo_ward = EXCLUDED.geo_ward;

INSERT INTO public.alerts
  (id, type, description, status, severity, reported_by, geo_lga, geo_ward,
   escalated_to_agency)
VALUES
  ('a1e10000-0000-4000-8000-00000000ae01', 'Kidnap - Immediate Abduction',
   'ai report subject', 'RESOLVED', 'CRITICAL',
   'a1a10000-0000-4000-8000-00000000a101', 'JOS NORTH', 'ABBA NA SHEHU', 'POLICE')
ON CONFLICT (id) DO NOTHING;

-- Written the way the route writes it: service role, with the model and the
-- officer who asked recorded.
INSERT INTO public.incident_ai_reports (alert_id, kind, body, model, requested_by)
VALUES
  ('a1e10000-0000-4000-8000-00000000ae01', 'summary',
   'POST-ACTION SUMMARY: the abduction was reported at 14:02 and units reached the scene at 14:31.',
   'gemini-1.5-flash-latest', 'a1a10000-0000-4000-8000-00000000a102');

CREATE OR REPLACE FUNCTION pg_temp.as_user(p_uid UUID)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_uid::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
END $$;

-- ── Nobody signed in may write one ─────────────────────────────────────────

DO $$
DECLARE blocked BOOLEAN := false; n INTEGER;
BEGIN
  -- The whole control. If this succeeds, an operator can record whatever they
  -- like as the model's conclusion.
  PERFORM pg_temp.as_user('a1a10000-0000-4000-8000-00000000a104');  -- HQ, the most privileged
  SET LOCAL ROLE authenticated;
  BEGIN
    INSERT INTO public.incident_ai_reports (alert_id, kind, body)
    VALUES ('a1e10000-0000-4000-8000-00000000ae01', 'summary',
            'The AI concluded the responders acted correctly.');
  EXCEPTION
    WHEN insufficient_privilege THEN blocked := true;
    WHEN OTHERS THEN blocked := true;  -- an RLS refusal is also fine
  END;
  RESET ROLE;

  SELECT count(*) INTO n FROM public.incident_ai_reports
   WHERE body LIKE '%acted correctly%';
  IF NOT blocked OR n <> 0 THEN
    RAISE EXCEPTION 'FAIL: HQ COMMAND wrote an AI report — an operator can put '
                    'words in the model''s mouth in the audit record';
  END IF;
  RAISE NOTICE 'PASS: not even HQ can write an AI report; only the server that called the model';
END $$;

DO $$
DECLARE blocked BOOLEAN := false;
BEGIN
  -- And it cannot be edited after the fact, which would be the same problem one
  -- step later.
  PERFORM pg_temp.as_user('a1a10000-0000-4000-8000-00000000a104');
  SET LOCAL ROLE authenticated;
  BEGIN
    UPDATE public.incident_ai_reports SET body = 'rewritten'
     WHERE alert_id = 'a1e10000-0000-4000-8000-00000000ae01';
  EXCEPTION WHEN OTHERS THEN blocked := true;
  END;
  RESET ROLE;
  IF EXISTS (SELECT 1 FROM public.incident_ai_reports WHERE body = 'rewritten') THEN
    RAISE EXCEPTION 'FAIL: an AI report was rewritten after the fact';
  END IF;
  RAISE NOTICE 'PASS: an AI report cannot be rewritten';
END $$;

DO $$
BEGIN
  PERFORM pg_temp.as_user('a1a10000-0000-4000-8000-00000000a104');
  SET LOCAL ROLE authenticated;
  BEGIN
    DELETE FROM public.incident_ai_reports
     WHERE alert_id = 'a1e10000-0000-4000-8000-00000000ae01';
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  RESET ROLE;
  IF NOT EXISTS (SELECT 1 FROM public.incident_ai_reports
                  WHERE alert_id = 'a1e10000-0000-4000-8000-00000000ae01') THEN
    RAISE EXCEPTION 'FAIL: an AI report was deleted through the API';
  END IF;
  RAISE NOTICE 'PASS: an AI report cannot be deleted through the API';
END $$;

-- ── Who may read one ───────────────────────────────────────────────────────

DO $$
DECLARE n INTEGER;
BEGIN
  -- The ward commander whose ward it is.
  PERFORM pg_temp.as_user('a1a10000-0000-4000-8000-00000000a102');
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM public.latest_ai_report(
    'a1e10000-0000-4000-8000-00000000ae01', 'summary');
  RESET ROLE;
  IF n <> 1 THEN
    RAISE EXCEPTION 'FAIL: the ward commander cannot read the analysis of an '
                    'incident in their own ward';
  END IF;
  RAISE NOTICE 'PASS: an officer reads the analysis of an incident that is theirs';
END $$;

DO $$
DECLARE n INTEGER;
BEGIN
  -- A ward commander in another LGA has no part in this incident.
  PERFORM pg_temp.as_user('a1a10000-0000-4000-8000-00000000a103');
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM public.latest_ai_report(
    'a1e10000-0000-4000-8000-00000000ae01', 'summary');
  RESET ROLE;
  IF n <> 0 THEN
    RAISE EXCEPTION 'FAIL: an officer outside the command read the analysis';
  END IF;
  RAISE NOTICE 'PASS: an officer outside the command reads nothing';
END $$;

DO $$
DECLARE n INTEGER;
BEGIN
  -- A LIAISON can see the incident — it was escalated to POLICE — and must NOT
  -- see the internal machine assessment of it. That is Rainbow's own working
  -- note; it may speculate about what happened and who was involved, and handing
  -- it to another organisation automatically is not a decision a policy should
  -- make on a commander's behalf.
  PERFORM pg_temp.as_user('a1a10000-0000-4000-8000-00000000a105');
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM public.alerts
   WHERE id = 'a1e10000-0000-4000-8000-00000000ae01';
  IF n <> 1 THEN
    RESET ROLE;
    RAISE EXCEPTION 'FAIL: the liaison cannot even see the incident, so this test '
                    'is not testing what it claims';
  END IF;
  SELECT count(*) INTO n FROM public.latest_ai_report(
    'a1e10000-0000-4000-8000-00000000ae01', 'summary');
  RESET ROLE;
  IF n <> 0 THEN
    RAISE EXCEPTION 'FAIL: a liaison who can see the incident also read our '
                    'internal AI assessment of it';
  END IF;
  RAISE NOTICE 'PASS: a liaison sees the incident and NOT our analysis of it';
END $$;

DO $$
DECLARE n INTEGER;
BEGIN
  -- The reporter. They can see their own incident; the internal assessment is
  -- staff work and is not theirs to read.
  PERFORM pg_temp.as_user('a1a10000-0000-4000-8000-00000000a101');
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM public.latest_ai_report(
    'a1e10000-0000-4000-8000-00000000ae01', 'summary');
  RESET ROLE;
  -- The first version of the policy required only alert_is_ours(), which admits
  -- the reporter — so a citizen would have read a forensic debrief of their own
  -- kidnapping, including whatever the model speculated about suspects or about
  -- how the response went. This test recorded that as a NOTE, which was the
  -- wrong call: the liaison exclusion rests on exactly the same argument, so
  -- leaving the reporter in was leaving an inconsistency in.
  IF n <> 0 THEN
    RAISE EXCEPTION 'FAIL: the person who reported the incident can read our '
                    'internal machine assessment of it';
  END IF;
  RAISE NOTICE 'PASS: the reporter sees their incident and NOT our analysis of it';
END $$;

DO $$
DECLARE denied BOOLEAN := false;
BEGIN
  SET LOCAL ROLE anon;
  BEGIN
    PERFORM count(*) FROM public.incident_ai_reports;
  EXCEPTION WHEN insufficient_privilege THEN denied := true;
  END;
  RESET ROLE;
  IF NOT denied THEN
    RAISE EXCEPTION 'FAIL: anon can read AI reports';
  END IF;
  RAISE NOTICE 'PASS: anon cannot read them at all';
END $$;

-- ── The newest one wins, and a triage is not a summary ─────────────────────

DO $$
DECLARE r RECORD;
BEGIN
  INSERT INTO public.incident_ai_reports (alert_id, kind, body, model, created_at)
  VALUES
    ('a1e10000-0000-4000-8000-00000000ae01', 'summary', 'the newer debrief',
     'gemini-1.5-flash-latest', NOW() + INTERVAL '1 minute'),
    ('a1e10000-0000-4000-8000-00000000ae01', 'triage', 'a triage recommendation',
     'gemini-1.5-flash-latest', NOW() + INTERVAL '2 minutes');

  PERFORM pg_temp.as_user('a1a10000-0000-4000-8000-00000000a104');
  SET LOCAL ROLE authenticated;
  SELECT * INTO r FROM public.latest_ai_report(
    'a1e10000-0000-4000-8000-00000000ae01', 'summary');
  RESET ROLE;

  IF r.body <> 'the newer debrief' THEN
    RAISE EXCEPTION 'FAIL: the latest summary is "%"', r.body;
  END IF;
  -- A triage recommendation is not a report and must not be returned as one,
  -- even though it is newer.
  IF r.body = 'a triage recommendation' THEN
    RAISE EXCEPTION 'FAIL: a triage recommendation was returned as the summary';
  END IF;
  IF r.model IS NULL THEN
    RAISE EXCEPTION 'FAIL: the model is not recorded — "the AI said" is not a '
                    'fact without knowing which AI';
  END IF;
  RAISE NOTICE 'PASS: the newest report of the right kind is returned, with its model';
END $$;

DO $$
DECLARE n INTEGER;
BEGIN
  -- The earlier report is still there. One written while the incident was
  -- running does not stop being evidence of what was known at the time.
  SELECT count(*) INTO n FROM public.incident_ai_reports
   WHERE alert_id = 'a1e10000-0000-4000-8000-00000000ae01' AND kind = 'summary';
  IF n <> 2 THEN
    RAISE EXCEPTION 'FAIL: a newer report replaced the earlier one (% kept)', n;
  END IF;
  RAISE NOTICE 'PASS: an earlier report is kept, not overwritten';
END $$;

-- ── Deleting the incident takes its analysis with it ───────────────────────

DO $$
DECLARE n INTEGER;
BEGIN
  DELETE FROM public.alerts WHERE id = 'a1e10000-0000-4000-8000-00000000ae01';
  SELECT count(*) INTO n FROM public.incident_ai_reports
   WHERE alert_id = 'a1e10000-0000-4000-8000-00000000ae01';
  IF n <> 0 THEN
    RAISE EXCEPTION 'FAIL: % analysis row(s) outlived the incident', n;
  END IF;
  RAISE NOTICE 'PASS: analysis does not outlive the incident it is about';
END $$;

ROLLBACK;
