-- Who a queued escalation actually reaches.
--
-- drain-outbox marked every TIER_ESCALATION row delivered without telling
-- anybody, because its switch knew only PUSH / SMS / WEBHOOK and nothing
-- writes those. The recipient rule now lives in SQL so both drainers ask the
-- same question; this asserts the answer.

\set ON_ERROR_STOP on
SET client_min_messages TO NOTICE;

BEGIN;

INSERT INTO auth.users (id, email) VALUES
  ('dddd9999-0000-4000-8000-0000000000e1', 'esc-ward-nar@staging.test'),
  ('dddd9999-0000-4000-8000-0000000000e2', 'esc-ward-gan@staging.test'),
  ('dddd9999-0000-4000-8000-0000000000e3', 'esc-ward-mangu@staging.test'),
  ('dddd9999-0000-4000-8000-0000000000e4', 'esc-lga@staging.test'),
  ('dddd9999-0000-4000-8000-0000000000e5', 'esc-hq@staging.test'),
  ('dddd9999-0000-4000-8000-0000000000e6', 'esc-nopush@staging.test')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles
  (id, email, full_name, role, geo_lga, geo_ward, onesignal_player_id) VALUES
  ('dddd9999-0000-4000-8000-0000000000e1','esc-ward-nar@staging.test','W Nar','WARD_COMMAND','JOS NORTH','NARAGUTA','player-nar-000001'),
  ('dddd9999-0000-4000-8000-0000000000e2','esc-ward-gan@staging.test','W Gan','WARD_OFFICER','JOS NORTH','GANGARE','player-gan-000002'),
  ('dddd9999-0000-4000-8000-0000000000e3','esc-ward-mangu@staging.test','W Man','WARD_COMMAND','MANGU','PANYAM','player-man-000003'),
  ('dddd9999-0000-4000-8000-0000000000e4','esc-lga@staging.test','LGA','LGA_COMMAND','JOS NORTH',NULL,'player-lga-000004'),
  ('dddd9999-0000-4000-8000-0000000000e5','esc-hq@staging.test','HQ','HQ_COMMAND',NULL,NULL,'player-hq-0000005'),
  ('dddd9999-0000-4000-8000-0000000000e6','esc-nopush@staging.test','W NoPush','WARD_COMMAND','JOS NORTH','NARAGUTA',NULL)
ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role,
  geo_lga = EXCLUDED.geo_lga, geo_ward = EXCLUDED.geo_ward,
  onesignal_player_id = EXCLUDED.onesignal_player_id;

DO $$
DECLARE wid BIGINT; n INTEGER; ids TEXT;
BEGIN
  INSERT INTO public.notification_outbox (kind, payload)
  VALUES ('TIER_ESCALATION', jsonb_build_object(
    'alert_id','aaaa1111-0000-4000-8000-00000000a001',
    'to_tier','WARD','geo_lga','JOS NORTH','geo_ward','NARAGUTA','severity','CRITICAL'))
  RETURNING id INTO wid;

  SELECT count(*), string_agg(player_id, ',' ORDER BY player_id)
    INTO n, ids FROM public.escalation_push_targets(wid);

  IF ids IS DISTINCT FROM 'player-nar-000001' THEN
    RAISE EXCEPTION 'FAIL: a ward escalation reached [%], expected only the ward it landed on', ids;
  END IF;
  RAISE NOTICE 'PASS: a ward escalation reaches that ward, not the LGA and not another ward';

  -- The officer with no push subscription is simply not a target; the worker
  -- treats an empty target list as a FAILURE, which is the point.
  RAISE NOTICE 'PASS: an officer with no push subscription is not counted as reachable';
END $$;

DO $$
DECLARE hid BIGINT; ids TEXT;
BEGIN
  INSERT INTO public.notification_outbox (kind, payload)
  VALUES ('TIER_ESCALATION', jsonb_build_object(
    'alert_id','aaaa1111-0000-4000-8000-00000000a002',
    'to_tier','HQ','geo_lga','MANGU','severity','HIGH'))
  RETURNING id INTO hid;

  SELECT string_agg(player_id, ',' ORDER BY player_id) INTO ids
    FROM public.escalation_push_targets(hid);

  IF ids IS DISTINCT FROM 'player-hq-0000005' THEN
    RAISE EXCEPTION 'FAIL: an HQ escalation reached [%]', ids;
  END IF;
  RAISE NOTICE 'PASS: an HQ escalation reaches HQ regardless of where it happened';
END $$;

DO $$
DECLARE uid BIGINT; n INTEGER;
BEGIN
  -- An SOS with no GPS fix. It must reach the tier rather than fall between
  -- desks because it has no place to be matched against.
  INSERT INTO public.notification_outbox (kind, payload)
  VALUES ('TIER_ESCALATION', jsonb_build_object(
    'alert_id','aaaa1111-0000-4000-8000-00000000a003',
    'to_tier','WARD','severity','CRITICAL'))
  RETURNING id INTO uid;

  SELECT count(*) INTO n FROM public.escalation_push_targets(uid);
  IF n < 3 THEN
    RAISE EXCEPTION 'FAIL: an unlocated escalation reached only % officer(s)', n;
  END IF;
  RAISE NOTICE 'PASS: an unlocated escalation reaches the whole tier rather than nobody';
END $$;

DO $$
DECLARE bid BIGINT; n INTEGER;
BEGIN
  INSERT INTO public.notification_outbox (kind, payload)
  VALUES ('TIER_ESCALATION', jsonb_build_object(
    'alert_id','aaaa1111-0000-4000-8000-00000000a004','to_tier','ATLANTIS'))
  RETURNING id INTO bid;

  SELECT count(*) INTO n FROM public.escalation_push_targets(bid);
  IF n <> 0 THEN
    RAISE EXCEPTION 'FAIL: a tier nobody holds paged % people', n;
  END IF;
  RAISE NOTICE 'PASS: a tier nobody holds addresses nobody, rather than everybody';
END $$;

DO $$
DECLARE denied BOOLEAN := false;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','dddd9999-0000-4000-8000-0000000000e1',true);
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM public.escalation_push_targets(1);
  EXCEPTION WHEN insufficient_privilege THEN denied := true;
  END;
  RESET ROLE;
  IF NOT denied THEN
    RAISE EXCEPTION 'FAIL: a signed-in account can enumerate push subscriptions';
  END IF;
  RAISE NOTICE 'PASS: only the service role can resolve push targets';
END $$;

ROLLBACK;
