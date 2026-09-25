-- ─── Regression tests for the SLA escalation engine ──────────────────────────
--
-- Plain SQL assertions — no pgTAP needed. Run against a database that already
-- has every migration applied:
--
--     psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/escalation_engine_test.sql
--
-- Any failed assertion raises, which makes psql exit non-zero. The whole run
-- happens inside a transaction that is rolled back, so it leaves no residue and
-- is safe against a scratch or staging database.
--
-- NOTE: do not point this at production. It inserts alerts and runs the engine.

BEGIN;

-- Fixed ids so assertions can address rows directly.
\set pu_alert    '''e5ca1a7e-0000-0000-0000-000000000001'''
\set fresh_alert '''e5ca1a7e-0000-0000-0000-000000000002'''
\set lga_alert   '''e5ca1a7e-0000-0000-0000-000000000003'''
\set done_alert  '''e5ca1a7e-0000-0000-0000-000000000004'''
\set sla_alert   '''e5ca1a7e-0000-0000-0000-000000000005'''

CREATE OR REPLACE FUNCTION pg_temp.assert(p_cond BOOLEAN, p_what TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  IF p_cond IS NOT TRUE THEN
    RAISE EXCEPTION 'ASSERTION FAILED: %', p_what;
  END IF;
  RAISE NOTICE '  ok  %', p_what;
END;
$$;

-- Known thresholds regardless of what the deployment has configured.
UPDATE public.app_config SET value = '2'  WHERE key = 'escalation_timeout_pu';
UPDATE public.app_config SET value = '5'  WHERE key = 'escalation_timeout_ward';
UPDATE public.app_config SET value = '10' WHERE key = 'escalation_timeout_lga';
UPDATE public.app_config SET value = '15' WHERE key = 'escalation_response_sla';
UPDATE public.app_config SET value = 'true' WHERE key = 'escalation_enabled';

INSERT INTO public.alerts (id, type, status, description, latitude, longitude, geo_lga,
                           severity, assigned_tier, tier_entered_at, created_at)
VALUES
  (:pu_alert::uuid,   'PANIC SOS','PENDING', 'stale at PU',   9.9,8.9,'JOS NORTH','HIGH',  'POLLING_UNIT', now() - interval '10 minutes', now() - interval '10 minutes'),
  (:fresh_alert::uuid,'INCIDENT', 'ACTIVE',  'fresh at PU',   9.9,8.9,'JOS NORTH','MEDIUM','POLLING_UNIT', now(),                          now()),
  (:lga_alert::uuid,  'INCIDENT', 'ACTIVE',  'stale at LGA',  9.9,8.9,'JOS NORTH','HIGH',  'LGA',          now() - interval '30 minutes', now() - interval '60 minutes'),
  (:done_alert::uuid, 'INCIDENT', 'RESOLVED','closed & stale',9.9,8.9,'JOS NORTH','LOW',   'POLLING_UNIT', now() - interval '5 hours',    now() - interval '5 hours');

\echo ''
\echo '── tier escalation ──'
DO $$
DECLARE v JSONB;
BEGIN
  v := public.run_escalation_cycle();
  PERFORM pg_temp.assert((v->>'skipped')::BOOLEAN IS FALSE, 'cycle ran');
  PERFORM pg_temp.assert((v->>'escalated')::INT = 2,        'exactly the two overdue alerts escalated');
END $$;

DO $$
BEGIN
  PERFORM pg_temp.assert(
    (SELECT assigned_tier FROM public.alerts WHERE id = 'e5ca1a7e-0000-0000-0000-000000000001') = 'WARD',
    'overdue POLLING_UNIT alert moved up exactly one tier, to WARD');
  PERFORM pg_temp.assert(
    (SELECT assigned_tier FROM public.alerts WHERE id = 'e5ca1a7e-0000-0000-0000-000000000002') = 'POLLING_UNIT',
    'alert still inside its SLA was left alone');
  PERFORM pg_temp.assert(
    (SELECT assigned_tier FROM public.alerts WHERE id = 'e5ca1a7e-0000-0000-0000-000000000003') = 'HQ',
    'overdue LGA alert reached HQ');
  PERFORM pg_temp.assert(
    (SELECT severity FROM public.alerts WHERE id = 'e5ca1a7e-0000-0000-0000-000000000003') = 'CRITICAL',
    'reaching HQ forces severity to CRITICAL');
  PERFORM pg_temp.assert(
    (SELECT assigned_tier FROM public.alerts WHERE id = 'e5ca1a7e-0000-0000-0000-000000000004') = 'POLLING_UNIT',
    'a RESOLVED alert is never escalated no matter how stale');
END $$;

\echo ''
\echo '── idempotency ──'
DO $$
DECLARE v JSONB;
BEGIN
  v := public.run_escalation_cycle();
  PERFORM pg_temp.assert((v->>'escalated')::INT = 0,
    'a second cycle immediately after escalates nothing');
END $$;

\echo ''
\echo '── HQ is terminal ──'
DO $$
DECLARE v JSONB;
BEGIN
  UPDATE public.alerts SET tier_entered_at = now() - interval '6 hours'
   WHERE id = 'e5ca1a7e-0000-0000-0000-000000000003';
  v := public.run_escalation_cycle();
  PERFORM pg_temp.assert((v->>'escalated')::INT = 0, 'nothing escalates past HQ');
  PERFORM pg_temp.assert(
    (SELECT assigned_tier FROM public.alerts WHERE id = 'e5ca1a7e-0000-0000-0000-000000000003') = 'HQ',
    'the HQ alert stayed at HQ');
END $$;

\echo ''
\echo '── audit trail ──'
DO $$
BEGIN
  PERFORM pg_temp.assert(
    (SELECT count(*) FROM public.alert_timeline
      WHERE alert_id = 'e5ca1a7e-0000-0000-0000-000000000001'
        AND event_type = 'SLA_AUTO_ESCALATION') = 1,
    'the escalation wrote exactly one timeline event');
  PERFORM pg_temp.assert(
    (SELECT count(*) FROM public.audit_logs
      WHERE alert_id = 'e5ca1a7e-0000-0000-0000-000000000001'
        AND action = 'AUTO_ESCALATION') = 1,
    'the escalation wrote exactly one audit row');
  PERFORM pg_temp.assert(
    (SELECT jsonb_array_length(escalation_log) FROM public.alerts
      WHERE id = 'e5ca1a7e-0000-0000-0000-000000000001') = 1,
    'escalation_log gained one entry for the clients that read it');
  PERFORM pg_temp.assert(
    (SELECT count(*) FROM public.notification_outbox
      WHERE alert_id = 'e5ca1a7e-0000-0000-0000-000000000001' AND status = 'PENDING') = 1,
    'the escalation queued exactly one notification');
END $$;

\echo ''
\echo '── response-SLA breach detection ──'
INSERT INTO public.alerts (id, type, status, description, latitude, longitude, geo_lga,
                           assigned_tier, tier_entered_at, created_at, dispatched_at)
VALUES (:sla_alert::uuid, 'INCIDENT','DISPATCHED','responder never arrived',9.9,8.9,'JOS NORTH',
        'WARD', now(), now() - interval '40 minutes', now() - interval '40 minutes');

DO $$
DECLARE v JSONB;
BEGIN
  v := public.run_escalation_cycle();
  PERFORM pg_temp.assert((v->>'breached')::INT = 1, 'the overdue dispatch was flagged');
  PERFORM pg_temp.assert(
    (SELECT sla_breached FROM public.alerts WHERE id = 'e5ca1a7e-0000-0000-0000-000000000005'),
    'sla_breached was set');
  PERFORM pg_temp.assert(
    (SELECT sla_breached_at IS NOT NULL FROM public.alerts WHERE id = 'e5ca1a7e-0000-0000-0000-000000000005'),
    'sla_breached_at was stamped');

  v := public.run_escalation_cycle();
  PERFORM pg_temp.assert((v->>'breached')::INT = 0,
    'an already-flagged breach is not re-reported on the next cycle');
END $$;

\echo ''
\echo '── status timestamps are stamped automatically ──'
DO $$
DECLARE v_id UUID;
BEGIN
  INSERT INTO public.alerts (type, status, description, latitude, longitude, assigned_tier)
  VALUES ('INCIDENT','PENDING','status walk',9.9,8.9,'POLLING_UNIT')
  RETURNING id INTO v_id;

  UPDATE public.alerts SET status = 'DISPATCHED'   WHERE id = v_id;
  UPDATE public.alerts SET status = 'ACKNOWLEDGED' WHERE id = v_id;
  UPDATE public.alerts SET status = 'RESOLVED'     WHERE id = v_id;

  PERFORM pg_temp.assert(
    (SELECT dispatched_at IS NOT NULL AND acknowledged_at IS NOT NULL AND resolved_at IS NOT NULL
       FROM public.alerts WHERE id = v_id),
    'dispatched_at, acknowledged_at and resolved_at were all stamped by the trigger');
END $$;

\echo ''
\echo '── configuration is read live ──'
DO $$
DECLARE v JSONB;
BEGIN
  UPDATE public.alerts SET tier_entered_at = now() - interval '6 minutes'
   WHERE id = 'e5ca1a7e-0000-0000-0000-000000000001';   -- now at WARD

  UPDATE public.app_config SET value = '60' WHERE key = 'escalation_timeout_ward';
  v := public.run_escalation_cycle();
  PERFORM pg_temp.assert((v->>'escalated')::INT = 0,
    'raising the WARD timeout to 60m keeps a 6m-old alert in place');

  UPDATE public.app_config SET value = '5' WHERE key = 'escalation_timeout_ward';
  v := public.run_escalation_cycle();
  PERFORM pg_temp.assert((v->>'escalated')::INT = 1,
    'lowering it back to 5m escalates the same alert');
  PERFORM pg_temp.assert(
    (SELECT assigned_tier FROM public.alerts WHERE id = 'e5ca1a7e-0000-0000-0000-000000000001') = 'LGA',
    'it moved WARD -> LGA');
END $$;

\echo ''
\echo '── a malformed threshold falls back instead of throwing ──'
DO $$
BEGIN
  UPDATE public.app_config SET value = 'not-a-number' WHERE key = 'escalation_timeout_pu';
  PERFORM pg_temp.assert(public.escalation_timeout_minutes('POLLING_UNIT') = 2,
    'a non-numeric threshold falls back to the built-in default');
  UPDATE public.app_config SET value = '2' WHERE key = 'escalation_timeout_pu';
END $$;

\echo ''
\echo '── kill switch ──'
DO $$
DECLARE v JSONB;
BEGIN
  UPDATE public.app_config SET value = 'false' WHERE key = 'escalation_enabled';
  UPDATE public.alerts SET tier_entered_at = now() - interval '2 hours'
   WHERE id = 'e5ca1a7e-0000-0000-0000-000000000001';
  v := public.run_escalation_cycle();
  PERFORM pg_temp.assert((v->>'escalated')::INT = 0, 'the engine escalates nothing while disabled');
  PERFORM pg_temp.assert((v->>'enabled')::BOOLEAN IS FALSE,
    'the cycle reports enabled:false, so a disabled engine is not mistaken for a quiet minute');

  UPDATE public.app_config SET value = 'true' WHERE key = 'escalation_enabled';
  v := public.run_escalation_cycle();
  PERFORM pg_temp.assert((v->>'escalated')::INT = 1, 'it resumes once re-enabled');
  PERFORM pg_temp.assert((v->>'enabled')::BOOLEAN IS TRUE, 'and reports enabled:true');
END $$;

\echo ''
\echo '── tier ladder ──'
DO $$
BEGIN
  PERFORM pg_temp.assert(public.next_escalation_tier('POLLING_UNIT') = 'WARD', 'POLLING_UNIT -> WARD');
  PERFORM pg_temp.assert(public.next_escalation_tier('WARD') = 'LGA',          'WARD -> LGA');
  PERFORM pg_temp.assert(public.next_escalation_tier('LGA') = 'HQ',            'LGA -> HQ');
  PERFORM pg_temp.assert(public.next_escalation_tier('HQ') IS NULL,            'HQ is terminal');
  PERFORM pg_temp.assert(public.next_escalation_tier(NULL) = 'WARD',           'a null tier is treated as POLLING_UNIT');
  PERFORM pg_temp.assert(public.escalation_tier_rank('MOON') = 0,              'an unknown tier ranks 0');
END $$;

\echo ''
\echo '── manual escalation refuses a backwards jump ──'
DO $$
DECLARE v BOOLEAN;
BEGIN
  v := public.apply_escalation(
    'e5ca1a7e-0000-0000-0000-000000000003'::uuid, 'WARD',
    'test', 'SYSTEM', 'downgrade attempt', NULL, 'MANUAL_ESCALATION', 'MANUAL_ESCALATION');
  PERFORM pg_temp.assert(v IS FALSE, 'escalating an HQ alert down to WARD is refused');
  PERFORM pg_temp.assert(
    (SELECT assigned_tier FROM public.alerts WHERE id = 'e5ca1a7e-0000-0000-0000-000000000003') = 'HQ',
    'the alert stayed at HQ');
END $$;

\echo ''
\echo '── a closed alert cannot be escalated ──'
DO $$
DECLARE v BOOLEAN;
BEGIN
  v := public.apply_escalation(
    'e5ca1a7e-0000-0000-0000-000000000004'::uuid, 'HQ',
    'test', 'SYSTEM', 'reopen attempt', NULL, 'MANUAL_ESCALATION', 'MANUAL_ESCALATION');
  PERFORM pg_temp.assert(v IS FALSE, 'a RESOLVED alert is refused');
END $$;

\echo ''
\echo '✓ escalation engine: all assertions passed'

ROLLBACK;
