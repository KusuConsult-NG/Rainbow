-- Does a complaint about an officer reach that officer?
--
-- 'Police brutality' is a reportable category in the app, with the subtypes
-- Physical Assault, Extortion and Unlawful Arrest. It used to route like a flood:
-- to the local ward, the local LGA, and every responder posted there — which may
-- include the person complained about — with the complainant's number on the
-- dossier.
--
-- Run by scripts/verify_rls_migration.sh against a real PostgreSQL.

\set ON_ERROR_STOP on
SET client_min_messages TO NOTICE;

BEGIN;

INSERT INTO auth.users (id, email) VALUES
  ('0ee50000-0000-4000-8000-00000000c001', 'oversight-citizen@staging.test'),
  ('0ee50000-0000-4000-8000-00000000c002', 'oversight-ward@staging.test'),
  ('0ee50000-0000-4000-8000-00000000c003', 'oversight-lga@staging.test'),
  ('0ee50000-0000-4000-8000-00000000c004', 'oversight-responder@staging.test'),
  ('0ee50000-0000-4000-8000-00000000c005', 'oversight-hq@staging.test'),
  ('0ee50000-0000-4000-8000-00000000c006', 'oversight-liaison@staging.test')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles (id, email, full_name, role, geo_lga, geo_ward) VALUES
  ('0ee50000-0000-4000-8000-00000000c001', 'oversight-citizen@staging.test',
   'Complainant', 'CITIZEN', 'JOS NORTH', 'ABBA NA SHEHU'),
  ('0ee50000-0000-4000-8000-00000000c002', 'oversight-ward@staging.test',
   'Ward Jos North', 'WARD_COMMAND', 'JOS NORTH', 'ABBA NA SHEHU'),
  ('0ee50000-0000-4000-8000-00000000c003', 'oversight-lga@staging.test',
   'LGA Jos North', 'LGA_COMMAND', 'JOS NORTH', NULL),
  -- The officer who might BE the subject of the complaint.
  ('0ee50000-0000-4000-8000-00000000c004', 'oversight-responder@staging.test',
   'Responder Jos North', 'RESPONDER', 'JOS NORTH', 'ABBA NA SHEHU'),
  ('0ee50000-0000-4000-8000-00000000c005', 'oversight-hq@staging.test',
   'HQ Command', 'HQ_COMMAND', NULL, NULL),
  ('0ee50000-0000-4000-8000-00000000c006', 'oversight-liaison@staging.test',
   'Police Liaison', 'POLICE_LIAISON', NULL, NULL)
ON CONFLICT (id) DO UPDATE
  SET role = EXCLUDED.role, geo_lga = EXCLUDED.geo_lga, geo_ward = EXCLUDED.geo_ward;

CREATE OR REPLACE FUNCTION pg_temp.as_user(p_uid UUID)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_uid::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
END $$;

CREATE OR REPLACE FUNCTION pg_temp.visible_to(p_uid UUID, p_alert UUID)
RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE n INTEGER;
BEGIN
  PERFORM pg_temp.as_user(p_uid);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM public.alerts WHERE id = p_alert;
  RESET ROLE;
  RETURN n;
END $$;

-- ── Recognising one ───────────────────────────────────────────────────────

DO $$
BEGIN
  IF NOT public.is_oversight_matter('Police brutality - Physical Assault') THEN
    RAISE EXCEPTION 'FAIL: a police brutality report is not an oversight matter';
  END IF;
  -- Matched on the CATEGORY, so every subtype is covered without listing them.
  IF NOT public.is_oversight_matter('Police brutality - Extortion')
     OR NOT public.is_oversight_matter('Police brutality - Unlawful Arrest')
     OR NOT public.is_oversight_matter('police brutality - anything at all') THEN
    RAISE EXCEPTION 'FAIL: a subtype of police brutality was missed';
  END IF;
  IF public.is_oversight_matter('Kidnap - Immediate Abduction')
     OR public.is_oversight_matter('Fire - Building Fire')
     OR public.is_oversight_matter(NULL)
     OR public.is_oversight_matter('') THEN
    RAISE EXCEPTION 'FAIL: an ordinary incident was treated as an oversight matter';
  END IF;
  RAISE NOTICE 'PASS: every subtype of the complaint category is recognised, and nothing else';
END $$;

-- ── An ordinary incident is unaffected ────────────────────────────────────

INSERT INTO public.alerts
  (id, type, description, status, severity, reported_by, geo_lga, geo_ward)
VALUES
  ('0eea0000-0000-4000-8000-00000000a001', 'Kidnap - Immediate Abduction',
   'ordinary incident', 'PENDING', 'CRITICAL',
   '0ee50000-0000-4000-8000-00000000c001', 'JOS NORTH', 'ABBA NA SHEHU');

DO $$
BEGIN
  IF pg_temp.visible_to('0ee50000-0000-4000-8000-00000000c002',
                        '0eea0000-0000-4000-8000-00000000a001') <> 1 THEN
    RAISE EXCEPTION 'FAIL: the ward commander lost an ordinary incident in their ward';
  END IF;
  IF pg_temp.visible_to('0ee50000-0000-4000-8000-00000000c004',
                        '0eea0000-0000-4000-8000-00000000a001') <> 1 THEN
    RAISE EXCEPTION 'FAIL: the responder lost an ordinary incident in their LGA';
  END IF;
  RAISE NOTICE 'PASS: an ordinary incident still reaches the local command';
END $$;

-- ── The complaint ─────────────────────────────────────────────────────────

INSERT INTO public.alerts
  (id, type, description, status, severity, reported_by, geo_lga, geo_ward,
   assigned_tier, assigned_to, assigned_responders)
VALUES
  ('0eea0000-0000-4000-8000-00000000a002', 'Police brutality - Physical Assault',
   'an officer beat me at the checkpoint', 'PENDING', 'HIGH',
   '0ee50000-0000-4000-8000-00000000c001', 'JOS NORTH', 'ABBA NA SHEHU',
   -- Filed as though it were an ordinary report, pre-assigned to the very
   -- responder it may be about. The trigger must undo all of this.
   'UNIT', '0ee50000-0000-4000-8000-00000000c004',
   ARRAY['0ee50000-0000-4000-8000-00000000c004']);

DO $$
DECLARE a RECORD;
BEGIN
  SELECT * INTO a FROM public.alerts
   WHERE id = '0eea0000-0000-4000-8000-00000000a002';

  IF upper(a.assigned_tier) <> 'HQ' THEN
    RAISE EXCEPTION 'FAIL: the complaint sits at tier % — in the accused''s own chain',
      a.assigned_tier;
  END IF;
  -- The most important line in this file. A complaint must never arrive
  -- pre-assigned to a responder in the area it was filed in.
  IF a.assigned_to IS NOT NULL OR a.assigned_responders IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: the complaint is assigned to % — possibly the person '
                    'complained about', a.assigned_to;
  END IF;
  IF a.escalation_log::text NOT LIKE '%OVERSIGHT_ROUTED%' THEN
    RAISE EXCEPTION 'FAIL: the routing was not recorded';
  END IF;
  RAISE NOTICE 'PASS: a complaint is routed to HQ and any assignment is cleared';
END $$;

-- ── Who can see it ────────────────────────────────────────────────────────

DO $$
BEGIN
  -- THE DEFECT. Each of these could see it before, and each is closer to the
  -- accused than the last.
  IF pg_temp.visible_to('0ee50000-0000-4000-8000-00000000c002',
                        '0eea0000-0000-4000-8000-00000000a002') <> 0 THEN
    RAISE EXCEPTION 'FAIL: the WARD COMMAND of the ward it was filed in can read '
                    'a complaint about security personnel';
  END IF;
  RAISE NOTICE 'PASS: the local ward command cannot see it';

  IF pg_temp.visible_to('0ee50000-0000-4000-8000-00000000c003',
                        '0eea0000-0000-4000-8000-00000000a002') <> 0 THEN
    RAISE EXCEPTION 'FAIL: the LGA COMMAND can read a complaint about security '
                    'personnel in their LGA';
  END IF;
  RAISE NOTICE 'PASS: the local LGA command cannot see it';

  IF pg_temp.visible_to('0ee50000-0000-4000-8000-00000000c004',
                        '0eea0000-0000-4000-8000-00000000a002') <> 0 THEN
    RAISE EXCEPTION 'FAIL: a RESPONDER in the LGA — possibly the person '
                    'complained about — can read the complaint';
  END IF;
  RAISE NOTICE 'PASS: a responder in the area cannot see it';

  IF pg_temp.visible_to('0ee50000-0000-4000-8000-00000000c006',
                        '0eea0000-0000-4000-8000-00000000a002') <> 0 THEN
    RAISE EXCEPTION 'FAIL: a POLICE LIAISON can read a complaint about police';
  END IF;
  RAISE NOTICE 'PASS: an outside agency liaison cannot see it either';
END $$;

DO $$
BEGIN
  IF pg_temp.visible_to('0ee50000-0000-4000-8000-00000000c005',
                        '0eea0000-0000-4000-8000-00000000a002') <> 1 THEN
    RAISE EXCEPTION 'FAIL: HQ cannot see the complaint — it has gone nowhere at all, '
                    'which is worse than going to the wrong place';
  END IF;
  RAISE NOTICE 'PASS: HQ can see it';

  -- The complainant keeps their own report. Oversight requires knowing who
  -- complained; the control is who ELSE can see it.
  IF pg_temp.visible_to('0ee50000-0000-4000-8000-00000000c001',
                        '0eea0000-0000-4000-8000-00000000a002') <> 1 THEN
    RAISE EXCEPTION 'FAIL: the complainant cannot see their own complaint';
  END IF;
  RAISE NOTICE 'PASS: the person who complained can still see their own report';
END $$;

-- ── It does not climb ─────────────────────────────────────────────────────

DO $$
DECLARE tier_before TEXT; tier_after TEXT;
BEGIN
  -- Aged well past every tier window.
  UPDATE public.alerts
     SET assigned_tier = 'UNIT', tier_assigned_at = NOW() - INTERVAL '8 hours',
         acknowledged_at = NULL
   WHERE id = '0eea0000-0000-4000-8000-00000000a002';

  SELECT assigned_tier INTO tier_before FROM public.alerts
   WHERE id = '0eea0000-0000-4000-8000-00000000a002';
  PERFORM public.escalate_overdue_alerts();
  SELECT assigned_tier INTO tier_after FROM public.alerts
   WHERE id = '0eea0000-0000-4000-8000-00000000a002';

  -- Climbing UNIT → WARD → LGA is precisely the wrong direction: each rung is
  -- closer to the person complained about.
  IF tier_after <> tier_before THEN
    RAISE EXCEPTION 'FAIL: the complaint climbed from % to % — towards the accused',
      tier_before, tier_after;
  END IF;
  IF NOT public.awaiting_human_confirmation(
       (SELECT a FROM public.alerts a WHERE a.id = '0eea0000-0000-4000-8000-00000000a002')) THEN
    RAISE EXCEPTION 'FAIL: the complaint is not held out of the ladder';
  END IF;
  RAISE NOTICE 'PASS: a complaint does not climb the ladder towards the accused';
END $$;

DO $$
DECLARE n INTEGER;
BEGIN
  SELECT count(*) INTO n FROM public.notification_outbox
   WHERE alert_id = '0eea0000-0000-4000-8000-00000000a002';
  IF n <> 0 THEN
    RAISE EXCEPTION 'FAIL: % escalation notice(s) were queued for a complaint — '
                    'they would page the accused''s own commander', n;
  END IF;
  RAISE NOTICE 'PASS: no escalation notice is queued for a complaint';
END $$;

-- ── The debrief column ────────────────────────────────────────────────────

DO $$
DECLARE d TEXT;
BEGIN
  UPDATE public.alerts
     SET ai_summary = '[AI TRIAGE ASSESSMENT] weapons reported.' || E'\n'
                   || '[RESOLVED DEBRIEF] we reached the scene at 14:31, two arrests made (by officer@test)'
   WHERE id = '0eea0000-0000-4000-8000-00000000a001';

  -- Re-run the backfill the migration performs, to prove it extracts the right
  -- line and leaves the rest of ai_summary alone.
  UPDATE public.alerts a
     SET debrief = btrim(substring(line FROM '\[RESOLVED DEBRIEF\] (.*)$'))
    FROM (
      SELECT id, unnest(string_to_array(ai_summary, E'\n')) AS line
        FROM public.alerts WHERE ai_summary LIKE '%[RESOLVED DEBRIEF]%'
    ) src
   WHERE a.id = src.id AND src.line LIKE '[RESOLVED DEBRIEF]%' AND a.debrief IS NULL;

  SELECT debrief INTO d FROM public.alerts
   WHERE id = '0eea0000-0000-4000-8000-00000000a001';

  IF d IS NULL THEN
    RAISE EXCEPTION 'FAIL: the debrief was not extracted';
  END IF;
  IF d NOT LIKE 'we reached the scene%' THEN
    RAISE EXCEPTION 'FAIL: the debrief extracted as "%"', d;
  END IF;
  -- The AI triage line must NOT have been swallowed into the debrief.
  IF d LIKE '%AI TRIAGE%' THEN
    RAISE EXCEPTION 'FAIL: the backfill took the AI triage line too: "%"', d;
  END IF;
  RAISE NOTICE 'PASS: a debrief is extracted from ai_summary without taking the AI notes';
END $$;

-- ── The audit trail ───────────────────────────────────────────────────────

DO $$
DECLARE n INTEGER; r RECORD;
BEGIN
  PERFORM pg_temp.as_user('0ee50000-0000-4000-8000-00000000c005');  -- HQ
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM public.audit_trail(100);
  RESET ROLE;
  IF n = 0 THEN
    RAISE EXCEPTION 'FAIL: the audit trail is empty, though actions have been taken';
  END IF;

  PERFORM pg_temp.as_user('0ee50000-0000-4000-8000-00000000c005');
  SET LOCAL ROLE authenticated;
  SELECT * INTO r FROM public.audit_trail(100)
   WHERE action = 'OVERSIGHT_ROUTED' LIMIT 1;
  RESET ROLE;
  IF r.action IS NULL THEN
    RAISE EXCEPTION 'FAIL: the oversight routing does not appear in the audit trail';
  END IF;
  IF r.detail = '' OR r.detail IS NULL THEN
    RAISE EXCEPTION 'FAIL: the audit entry has no reason recorded';
  END IF;
  RAISE NOTICE 'PASS: the audit trail shows what was DONE, with a reason';
END $$;

DO $$
DECLARE n INTEGER;
BEGIN
  -- And it is scoped. Without SECURITY INVOKER this would hand every account the
  -- action history of every incident in Plateau — including the oversight matters
  -- the rest of this migration exists to protect.
  PERFORM pg_temp.as_user('0ee50000-0000-4000-8000-00000000c004');  -- responder
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM public.audit_trail(100)
   WHERE alert_id = '0eea0000-0000-4000-8000-00000000a002';
  RESET ROLE;
  IF n <> 0 THEN
    RAISE EXCEPTION 'FAIL: a responder reads the audit trail of a complaint they '
                    'cannot see the incident for';
  END IF;
  RAISE NOTICE 'PASS: the audit trail is scoped by the same rule as the incidents';
END $$;

DO $$
DECLARE r RECORD;
BEGIN
  -- A tier move carries no 'action' key; it is identified by from_tier. Without
  -- that fallback every automatic escalation in the system would read 'UPDATED'.
  UPDATE public.alerts
     SET escalation_log = '[{"from_tier":"UNIT","to_tier":"WARD","reason":"TIMEOUT","by":"SYSTEM","at":"2026-09-29T10:00:00Z"}]'::jsonb
   WHERE id = '0eea0000-0000-4000-8000-00000000a001';

  PERFORM pg_temp.as_user('0ee50000-0000-4000-8000-00000000c005');
  SET LOCAL ROLE authenticated;
  SELECT * INTO r FROM public.audit_trail(100)
   WHERE alert_id = '0eea0000-0000-4000-8000-00000000a001' LIMIT 1;
  RESET ROLE;

  IF r.action <> 'ESCALATED' THEN
    RAISE EXCEPTION 'FAIL: a tier move reads as "%" rather than ESCALATED', r.action;
  END IF;
  IF r.detail NOT LIKE '%UNIT%WARD%' THEN
    RAISE EXCEPTION 'FAIL: the tier move does not say where it went: "%"', r.detail;
  END IF;
  RAISE NOTICE 'PASS: an automatic escalation reads as ESCALATED, naming both tiers';
END $$;

ROLLBACK;
