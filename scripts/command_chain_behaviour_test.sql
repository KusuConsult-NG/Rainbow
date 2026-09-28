-- ============================================================================
-- OPERATION RAINBOW — DOES THE COMMAND CHAIN ACTUALLY CLIMB?
--
-- UNIT -> WARD -> LGA -> HQ, on a timeout, in the database.
--
-- The assertions are about the things that would hurt:
--   * a new alert lands at the PU, not nowhere
--   * it does NOT move before its tier's window is up
--   * it moves exactly ONE rung when the window passes
--   * an ACKNOWLEDGED alert never moves — somebody has it
--   * a RESOLVED alert never moves
--   * HQ is terminal: the chain stops rather than looping
--   * the chain of custody is appended, not replaced
--   * a broken app_config value cannot mean "escalate everything now"
--   * a MANUAL escalation from the app restarts the clock for the tier taking
--     it, so a hand-escalated alert does not cascade straight to HQ
--   * acknowledging a mission from the app actually sets `acknowledged_at`, so
--     the guard above can fire at all
--
-- Run inside scripts/verify_rls_migration.sh, after the migrations.
-- ============================================================================

\set ON_ERROR_STOP on

DO $test$
DECLARE
  reporter UUID := '77770000-0000-4000-8000-000000007001';
  a_fresh  UUID;
  a_over   UUID;
  a_ack    UUID;
  a_done   UUID;
  a_hq     UUID;
  a_manual  UUID;
  a_manual2 UUID;
  a_accept  UUID;
  got      TEXT;
  ts       TIMESTAMPTZ;
  n        INT;
  failures INT := 0;
BEGIN
  -- A reporter to hang the alerts off.
  INSERT INTO auth.users (id, email, raw_user_meta_data)
  VALUES (reporter, 'chain-test@example.test', '{"full_name": "Chain Test"}'::jsonb)
  ON CONFLICT (id) DO NOTHING;

  -- ── 1. A new alert lands at the PU ───────────────────────────────────────
  INSERT INTO public.alerts (type, status, description, reported_by)
  VALUES ('SOS', 'PENDING', 'fresh, should sit at the unit', reporter)
  RETURNING id INTO a_fresh;

  SELECT assigned_tier INTO got FROM public.alerts WHERE id = a_fresh;
  IF got = 'UNIT' THEN
    RAISE NOTICE 'PASS  a new alert lands at the polling unit';
  ELSE
    RAISE WARNING 'FAIL  a new alert landed at %, expected UNIT', coalesce(got, 'NULL');
    failures := failures + 1;
  END IF;

  SELECT tier_assigned_at INTO ts FROM public.alerts WHERE id = a_fresh;
  IF ts IS NOT NULL THEN
    RAISE NOTICE 'PASS  the ownership clock starts on insert';
  ELSE
    RAISE WARNING 'FAIL  tier_assigned_at was NULL, so no timeout can ever be measured';
    failures := failures + 1;
  END IF;

  -- ── 2. It does not move early ────────────────────────────────────────────
  PERFORM public.escalate_overdue_alerts();
  SELECT assigned_tier INTO got FROM public.alerts WHERE id = a_fresh;
  IF got = 'UNIT' THEN
    RAISE NOTICE 'PASS  an alert inside its window is left alone';
  ELSE
    RAISE WARNING 'FAIL  a fresh alert escalated immediately (now %)', got;
    failures := failures + 1;
  END IF;

  -- ── 3. It moves exactly one rung when the window passes ──────────────────
  INSERT INTO public.alerts (type, status, description, reported_by, tier_assigned_at)
  VALUES ('SOS', 'PENDING', 'overdue at the unit', reporter, NOW() - INTERVAL '30 minutes')
  RETURNING id INTO a_over;

  PERFORM public.escalate_overdue_alerts();
  SELECT assigned_tier INTO got FROM public.alerts WHERE id = a_over;
  IF got = 'WARD' THEN
    RAISE NOTICE 'PASS  an overdue UNIT alert climbs to WARD';
  ELSE
    RAISE WARNING 'FAIL  overdue UNIT alert went to %, expected WARD', coalesce(got, 'NULL');
    failures := failures + 1;
  END IF;

  -- One rung per run: the clock restarted, so a second run must not move it
  -- again. Without that, one pass would carry an alert straight to HQ and the
  -- ward and LGA would never see it.
  PERFORM public.escalate_overdue_alerts();
  SELECT assigned_tier INTO got FROM public.alerts WHERE id = a_over;
  IF got = 'WARD' THEN
    RAISE NOTICE 'PASS  it climbs ONE rung per timeout, not straight to the top';
  ELSE
    RAISE WARNING 'FAIL  a second run moved it again, to %', got;
    failures := failures + 1;
  END IF;

  -- ── 4. The chain of custody is appended ──────────────────────────────────
  SELECT jsonb_array_length(escalation_log) INTO n
    FROM public.alerts WHERE id = a_over;
  IF n = 1 THEN
    RAISE NOTICE 'PASS  the escalation is recorded in the log';
  ELSE
    RAISE WARNING 'FAIL  escalation_log holds % entries, expected 1', n;
    failures := failures + 1;
  END IF;

  SELECT escalation_log -> 0 ->> 'reason' INTO got
    FROM public.alerts WHERE id = a_over;
  IF got = 'TIMEOUT' THEN
    RAISE NOTICE 'PASS  the log says WHY it moved';
  ELSE
    RAISE WARNING 'FAIL  reason was %, expected TIMEOUT', coalesce(got, 'NULL');
    failures := failures + 1;
  END IF;

  -- ── 5. An acknowledged alert never moves ─────────────────────────────────
  INSERT INTO public.alerts (type, status, description, reported_by,
                             tier_assigned_at, acknowledged_at)
  VALUES ('SOS', 'PENDING', 'acknowledged at the unit', reporter,
          NOW() - INTERVAL '30 minutes', NOW() - INTERVAL '25 minutes')
  RETURNING id INTO a_ack;

  PERFORM public.escalate_overdue_alerts();
  SELECT assigned_tier INTO got FROM public.alerts WHERE id = a_ack;
  IF got = 'UNIT' THEN
    RAISE NOTICE 'PASS  an acknowledged alert stays with whoever took it';
  ELSE
    RAISE WARNING 'FAIL  an acknowledged alert escalated to %', got;
    failures := failures + 1;
  END IF;

  -- ── 6. A closed alert never moves ────────────────────────────────────────
  INSERT INTO public.alerts (type, status, description, reported_by, tier_assigned_at)
  VALUES ('SOS', 'RESOLVED', 'already resolved', reporter, NOW() - INTERVAL '30 minutes')
  RETURNING id INTO a_done;

  PERFORM public.escalate_overdue_alerts();
  SELECT assigned_tier INTO got FROM public.alerts WHERE id = a_done;
  IF got = 'UNIT' THEN
    RAISE NOTICE 'PASS  a resolved alert is left alone';
  ELSE
    RAISE WARNING 'FAIL  a resolved alert escalated to %', got;
    failures := failures + 1;
  END IF;

  -- ── 7. HQ is the top ─────────────────────────────────────────────────────
  INSERT INTO public.alerts (type, status, description, reported_by,
                             assigned_tier, tier_assigned_at)
  VALUES ('SOS', 'ESCALATED', 'sitting at HQ', reporter,
          'HQ', NOW() - INTERVAL '90 minutes')
  RETURNING id INTO a_hq;

  PERFORM public.escalate_overdue_alerts();
  SELECT assigned_tier INTO got FROM public.alerts WHERE id = a_hq;
  IF got = 'HQ' THEN
    RAISE NOTICE 'PASS  HQ is terminal — the chain stops rather than looping';
  ELSE
    RAISE WARNING 'FAIL  an HQ alert moved to %', coalesce(got, 'NULL');
    failures := failures + 1;
  END IF;

  IF public.next_tier('HQ') IS NULL THEN
    RAISE NOTICE 'PASS  next_tier(HQ) is NULL';
  ELSE
    RAISE WARNING 'FAIL  next_tier(HQ) returned %', public.next_tier('HQ');
    failures := failures + 1;
  END IF;

  -- ── 8. A broken setting cannot mean "escalate everything now" ────────────
  UPDATE public.app_config SET value = 'not a number'
   WHERE key = 'escalation_timeout_pu';

  IF public.tier_timeout_minutes('UNIT') = 2 THEN
    RAISE NOTICE 'PASS  a malformed timeout falls back to the seeded value';
  ELSE
    RAISE WARNING 'FAIL  a malformed timeout produced %',
      coalesce(public.tier_timeout_minutes('UNIT')::text, 'NULL');
    failures := failures + 1;
  END IF;

  UPDATE public.app_config SET value = '0'
   WHERE key = 'escalation_timeout_pu';
  IF public.tier_timeout_minutes('UNIT') = 2 THEN
    RAISE NOTICE 'PASS  a zero timeout is refused rather than escalating instantly';
  ELSE
    RAISE WARNING 'FAIL  a zero timeout produced %',
      public.tier_timeout_minutes('UNIT');
    failures := failures + 1;
  END IF;

  UPDATE public.app_config SET value = '2'
   WHERE key = 'escalation_timeout_pu';

  -- ── 9. The job is not reachable from a phone ─────────────────────────────
  IF has_function_privilege('anon', 'public.escalate_overdue_alerts()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.escalate_overdue_alerts()', 'EXECUTE') THEN
    RAISE WARNING 'FAIL  a signed-in client can reassign every emergency in the system';
    failures := failures + 1;
  ELSE
    RAISE NOTICE 'PASS  only the service role can run the escalation job';
  END IF;

  -- ── 10. A MANUAL escalation restarts the clock ───────────────────────────
  --
  -- The two sides have to agree. The job measures the window from
  -- `tier_assigned_at`; the app's escalation dialog writes the UPDATE. It wrote
  -- status, severity, assignee, tier, log and summary — and not
  -- `tier_assigned_at`. So an alert handed up by hand carried the timestamp
  -- from when it was inserted at the polling unit, and the WARD's window was
  -- already spent before the WARD ever saw it.
  --
  -- The two statements below are the app's payload, replayed. The first is what
  -- it used to send.
  INSERT INTO public.alerts (type, status, description, reported_by, tier_assigned_at)
  VALUES ('SOS', 'PENDING', 'escalated by hand, old payload', reporter,
          NOW() - INTERVAL '45 minutes')
  RETURNING id INTO a_manual;

  UPDATE public.alerts
     SET status = 'ESCALATED', severity = 'HIGH', assigned_tier = 'WARD',
         updated_at = NOW()
   WHERE id = a_manual;

  PERFORM public.escalate_overdue_alerts();
  SELECT assigned_tier INTO got FROM public.alerts WHERE id = a_manual;
  IF got = 'WARD' THEN
    RAISE WARNING 'FAIL  the old payload held at WARD — this assertion is '
                  'meant to demonstrate the cascade and no longer does';
    failures := failures + 1;
  ELSE
    RAISE NOTICE 'PASS  without the clock reset a hand escalation cascades '
                 'straight past WARD to % — which is the bug', got;
  END IF;

  -- And this is what it sends now.
  INSERT INTO public.alerts (type, status, description, reported_by, tier_assigned_at)
  VALUES ('SOS', 'PENDING', 'escalated by hand, fixed payload', reporter,
          NOW() - INTERVAL '45 minutes')
  RETURNING id INTO a_manual2;

  UPDATE public.alerts
     SET status = 'ESCALATED', severity = 'HIGH', assigned_tier = 'WARD',
         tier_assigned_at = NOW(),
         acknowledged_at = NULL, acknowledged_by = NULL,
         updated_at = NOW()
   WHERE id = a_manual2;

  PERFORM public.escalate_overdue_alerts();
  SELECT assigned_tier INTO got FROM public.alerts WHERE id = a_manual2;
  IF got = 'WARD' THEN
    RAISE NOTICE 'PASS  a hand escalation gives the WARD its full window';
  ELSE
    RAISE WARNING 'FAIL  a hand escalation still cascaded to %', got;
    failures := failures + 1;
  END IF;

  -- The clock reset must not become a way to keep an alert alive forever: the
  -- WARD's own window still has to expire.
  UPDATE public.alerts SET tier_assigned_at = NOW() - INTERVAL '20 minutes'
   WHERE id = a_manual2;
  PERFORM public.escalate_overdue_alerts();
  SELECT assigned_tier INTO got FROM public.alerts WHERE id = a_manual2;
  IF got = 'LGA' THEN
    RAISE NOTICE 'PASS  and it still climbs when THAT window passes';
  ELSE
    RAISE WARNING 'FAIL  the WARD held it past its own window, at %', got;
    failures := failures + 1;
  END IF;

  -- ── 11. Acknowledging from the app stops the clock ────────────────────────
  --
  -- Section 5 proves the job honours `acknowledged_at`. This proves the app
  -- sets it. Nothing in either app wrote the column, so the guard in section 5
  -- could not fire in production: an officer who accepted a mission and set out
  -- had it escalated out from under them, and the tier above was told nobody
  -- had responded.
  INSERT INTO public.alerts (type, status, description, reported_by, tier_assigned_at)
  VALUES ('SOS', 'PENDING', 'accepted from the feed', reporter,
          NOW() - INTERVAL '45 minutes')
  RETURNING id INTO a_accept;

  -- The tactical action sheet's UPDATE, as it now sends it.
  UPDATE public.alerts
     SET status = 'ACKNOWLEDGED', assigned_to = reporter,
         acknowledged_at = NOW(), acknowledged_by = reporter,
         updated_at = NOW()
   WHERE id = a_accept;

  PERFORM public.escalate_overdue_alerts();
  SELECT assigned_tier INTO got FROM public.alerts WHERE id = a_accept;
  IF got = 'UNIT' THEN
    RAISE NOTICE 'PASS  accepting a mission from the feed stops it climbing';
  ELSE
    RAISE WARNING 'FAIL  an accepted mission escalated to % anyway', got;
    failures := failures + 1;
  END IF;

  -- Moving on through the mission must not restart it either.
  UPDATE public.alerts SET status = 'ON_ROUTE', updated_at = NOW()
   WHERE id = a_accept;
  PERFORM public.escalate_overdue_alerts();
  SELECT assigned_tier INTO got FROM public.alerts WHERE id = a_accept;
  IF got = 'UNIT' THEN
    RAISE NOTICE 'PASS  and an officer EN ROUTE keeps it';
  ELSE
    RAISE WARNING 'FAIL  an officer en route lost the mission to %', got;
    failures := failures + 1;
  END IF;

  -- ── Clean up so the file can run twice ───────────────────────────────────
  DELETE FROM public.alerts WHERE reported_by = reporter;
  DELETE FROM public.profiles WHERE id = reporter;
  DELETE FROM auth.users WHERE id = reporter;

  IF failures > 0 THEN
    RAISE EXCEPTION 'COMMAND CHAIN TEST FAILED (% assertion(s))', failures;
  END IF;
  RAISE NOTICE 'ALL COMMAND CHAIN ASSERTIONS PASSED';
END
$test$;
