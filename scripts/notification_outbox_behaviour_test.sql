-- Does an automatic escalation actually owe somebody a notification?
--
-- The escalation job was correct and silent: it moved the incident into another
-- tier's queue and notified nobody, because every notification in this system is
-- sent by a human pressing a button in the console. The property worth proving
-- is not that a table exists — it is that the tier CANNOT move without the
-- notice being queued, because the two are written in one statement.
--
-- Run by scripts/verify_rls_migration.sh against a real PostgreSQL.

\set ON_ERROR_STOP on
-- NOTICE, not WARNING: the PASS lines are RAISE NOTICE, and a test whose output
-- is suppressed cannot be told apart from a test that never ran.
SET client_min_messages TO NOTICE;

BEGIN;

INSERT INTO auth.users (id, email)
VALUES ('eeee5555-0000-4000-8000-0000000000e1', 'outbox-test@staging.test')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles (id, email, full_name, role, geo_lga, geo_ward, geo_pu)
VALUES ('eeee5555-0000-4000-8000-0000000000e1', 'outbox-test@staging.test',
        'Outbox Reporter', 'CITIZEN', 'JOS NORTH', 'NARAGUTA', 'PU-01')
ON CONFLICT (id) DO NOTHING;

-- Start clean: other tests in this run may have escalated things.
DELETE FROM public.notification_outbox;

-- An incident that has sat unacknowledged at the polling unit well past the
-- two-minute unit timeout.
INSERT INTO public.alerts
  (id, type, description, status, severity, reported_by,
   geo_lga, geo_ward, geo_pu, assigned_tier, tier_assigned_at, acknowledged_at)
VALUES
  ('ffff6666-0000-4000-8000-0000000000f1', 'Kidnap - Held Hostage',
   'nobody answered at the unit', 'OPEN', 'CRITICAL',
   'eeee5555-0000-4000-8000-0000000000e1',
   'JOS NORTH', 'NARAGUTA', 'PU-01', 'UNIT', NOW() - INTERVAL '30 minutes', NULL);

-- ── The escalation queues its own notice ───────────────────────────────────

DO $$
DECLARE moved INTEGER; queued INTEGER; to_tier TEXT;
BEGIN
  SELECT count(*) INTO moved FROM public.escalate_overdue_alerts();
  IF moved < 1 THEN
    RAISE EXCEPTION 'FAIL: the overdue incident was not escalated at all';
  END IF;
  RAISE NOTICE 'PASS: an unacknowledged incident past its timeout is escalated';

  SELECT count(*) INTO queued
    FROM public.notification_outbox
   WHERE alert_id = 'ffff6666-0000-4000-8000-0000000000f1'
     AND kind = 'TIER_ESCALATION';
  IF queued <> 1 THEN
    RAISE EXCEPTION
      'FAIL: the tier moved but % notifications were queued — the escalation is silent', queued;
  END IF;
  RAISE NOTICE 'PASS: escalating an incident queues the notification in the same statement';

  -- The notice has to say where it went, or the worker cannot address it.
  SELECT payload ->> 'to_tier' INTO to_tier
    FROM public.notification_outbox
   WHERE alert_id = 'ffff6666-0000-4000-8000-0000000000f1';
  IF to_tier IS DISTINCT FROM 'WARD' THEN
    RAISE EXCEPTION 'FAIL: the queued notice says to_tier=%, expected WARD', to_tier;
  END IF;
  RAISE NOTICE 'PASS: the queued notice names the tier the incident climbed to';
END $$;

-- ── An acknowledged incident is left alone, and owes nothing ───────────────

DO $$
DECLARE queued INTEGER;
BEGIN
  INSERT INTO public.alerts
    (id, type, description, status, severity, reported_by,
     geo_lga, geo_ward, geo_pu, assigned_tier, tier_assigned_at, acknowledged_at)
  VALUES
    ('ffff6666-0000-4000-8000-0000000000f2', 'Fire - Structure',
     'somebody has this one', 'OPEN', 'HIGH',
     'eeee5555-0000-4000-8000-0000000000e1',
     'JOS NORTH', 'NARAGUTA', 'PU-01', 'UNIT',
     NOW() - INTERVAL '30 minutes', NOW() - INTERVAL '25 minutes');

  PERFORM public.escalate_overdue_alerts();

  SELECT count(*) INTO queued
    FROM public.notification_outbox
   WHERE alert_id = 'ffff6666-0000-4000-8000-0000000000f2';
  IF queued <> 0 THEN
    RAISE EXCEPTION
      'FAIL: an acknowledged incident was escalated, and somebody was told about it';
  END IF;
  RAISE NOTICE 'PASS: an acknowledged incident is not escalated and owes no notice';
END $$;

-- ── Claiming ───────────────────────────────────────────────────────────────

DO $$
DECLARE n INTEGER; again INTEGER; tries INTEGER;
BEGIN
  SELECT count(*) INTO n FROM public.claim_notifications(10);
  IF n < 1 THEN
    RAISE EXCEPTION 'FAIL: a due notification could not be claimed';
  END IF;
  RAISE NOTICE 'PASS: a due notification can be claimed';

  SELECT attempts INTO tries FROM public.notification_outbox
   WHERE alert_id = 'ffff6666-0000-4000-8000-0000000000f1';
  IF tries <> 1 THEN
    RAISE EXCEPTION 'FAIL: claiming did not count the attempt (attempts=%)', tries;
  END IF;
  RAISE NOTICE 'PASS: claiming counts the attempt, so a row cannot retry for ever unseen';

  -- Held off for a minute on claim, so a worker that dies mid-send does not
  -- leave the row to be taken again immediately by the next tick.
  SELECT count(*) INTO again FROM public.claim_notifications(10);
  IF again <> 0 THEN
    RAISE EXCEPTION
      'FAIL: the same notification was claimed twice in a row — it would be sent twice';
  END IF;
  RAISE NOTICE 'PASS: a just-claimed notification is not handed out again immediately';
END $$;

-- ── Delivery, and failure ──────────────────────────────────────────────────

DO $$
DECLARE target BIGINT; n INTEGER;
BEGIN
  SELECT id INTO target FROM public.notification_outbox
   WHERE alert_id = 'ffff6666-0000-4000-8000-0000000000f1';

  PERFORM public.mark_notification_sent(target);

  -- Make it due again; a delivered row must still not come back.
  UPDATE public.notification_outbox SET next_attempt_at = NOW() - INTERVAL '1 hour'
   WHERE id = target;

  SELECT count(*) INTO n FROM public.claim_notifications(10);
  IF n <> 0 THEN
    RAISE EXCEPTION 'FAIL: a delivered notification was claimed again';
  END IF;
  RAISE NOTICE 'PASS: a delivered notification is never sent twice';
END $$;

DO $$
DECLARE target BIGINT; due TIMESTAMPTZ; err TEXT;
BEGIN
  INSERT INTO public.notification_outbox (alert_id, kind, payload, attempts)
  VALUES ('ffff6666-0000-4000-8000-0000000000f1', 'TIER_ESCALATION', '{}'::jsonb, 3)
  RETURNING id INTO target;

  PERFORM public.mark_notification_failed(target, 'onesignal timed out');

  SELECT next_attempt_at, last_error INTO due, err
    FROM public.notification_outbox WHERE id = target;

  IF due <= NOW() THEN
    RAISE EXCEPTION
      'FAIL: a failed notification is due immediately — one bad recipient would spin the worker';
  END IF;
  IF err IS NULL THEN
    RAISE EXCEPTION 'FAIL: the failure was not recorded, so nobody can see why';
  END IF;
  RAISE NOTICE 'PASS: a failed notification backs off and records why';
END $$;

-- ── Nobody signed in from a phone may read this ────────────────────────────
--
-- It names officers and incidents and is not operational information for either
-- app: it exists between the database and the worker.

DO $$
DECLARE denied BOOLEAN := false;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',
                     'eeee5555-0000-4000-8000-0000000000e1', true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    PERFORM count(*) FROM public.notification_outbox;
  EXCEPTION WHEN insufficient_privilege THEN
    denied := true;
  END;

  RESET ROLE;

  IF NOT denied THEN
    RAISE EXCEPTION 'FAIL: a signed-in account can read the notification outbox';
  END IF;
  RAISE NOTICE 'PASS: the outbox is unreadable from the API';
END $$;

DO $$
DECLARE denied BOOLEAN := false;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',
                     'eeee5555-0000-4000-8000-0000000000e1', true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  SET LOCAL ROLE authenticated;

  BEGIN
    PERFORM public.claim_notifications(5);
  EXCEPTION WHEN insufficient_privilege THEN
    denied := true;
  END;

  RESET ROLE;

  IF NOT denied THEN
    RAISE EXCEPTION
      'FAIL: a signed-in account can claim notifications, and so can suppress them';
  END IF;
  RAISE NOTICE 'PASS: only the service role can drain the outbox';
END $$;

-- ── Is the automation actually scheduled? ──────────────────────────────────
--
-- Reported, not asserted. pg_cron is not present in a bare PostgreSQL, so
-- failing here would only prove which database this test ran in. What matters
-- is that the question is ASKABLE in production, where it has a real answer.

DO $$
DECLARE ok BOOLEAN; detail TEXT;
BEGIN
  SELECT scheduled, escalation_automation_status.detail
    INTO ok, detail FROM public.escalation_automation_status();
  IF ok IS NULL THEN
    RAISE EXCEPTION 'FAIL: the automation status cannot be determined at all';
  END IF;
  RAISE NOTICE 'PASS: the automation status is reportable — here: %', detail;
END $$;

ROLLBACK;
