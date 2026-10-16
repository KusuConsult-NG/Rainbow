-- ============================================================================
-- A NEW EMERGENCY QUEUES A NOTICE, AND CANNOT BE REFUSED BECAUSE OF ONE
-- ============================================================================
--
-- `20261022000000_a_new_emergency_tells_the_unit.sql`. The outbox was built for
-- the TIMEOUT escalation; nothing queued anything when an alert was INSERTED,
-- so a citizen's SOS reached a responder only if that responder had the app
-- open. The system announced that it had given up waiting for you, and not that
-- the emergency had arrived.
--
-- Its own file because `notification_outbox_behaviour_test.sql` runs earlier in
-- the replay, before this migration exists.
--
--   psql -f scripts/new_incident_notice_behaviour_test.sql
--
-- One transaction, rolled back.
-- ============================================================================

\set ON_ERROR_STOP on

BEGIN;

INSERT INTO auth.users (id, email) VALUES
  ('a9990000-0000-4000-8000-00000000a901', 'ni-citizen@staging.test')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles (id, email, full_name, role, geo_lga, geo_ward, geo_pu)
VALUES
  ('a9990000-0000-4000-8000-00000000a901', 'ni-citizen@staging.test',
   'Reporter', 'CITIZEN', 'JOS NORTH', 'NARAGUTA', 'PU-01')
ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role;

DO $$
DECLARE
  reporter UUID := 'a9990000-0000-4000-8000-00000000a901';
  a_id     UUID;
  n        INTEGER;
  tier     TEXT;
  pu       TEXT;
BEGIN
  -- ── An ordinary SOS ───────────────────────────────────────────────────────
  INSERT INTO public.alerts
    (type, status, severity, description, reported_by, geo_lga, geo_ward, geo_pu)
  VALUES ('SOS', 'PENDING', 'CRITICAL', 'armed men at the junction', reporter,
          'JOS NORTH', 'NARAGUTA', 'PU-01')
  RETURNING id INTO a_id;

  SELECT count(*) INTO n FROM public.notification_outbox
   WHERE alert_id = a_id AND kind = 'NEW_INCIDENT';
  IF n <> 1 THEN
    RAISE EXCEPTION 'FAIL: filing an SOS queued % NEW_INCIDENT notices, not 1 '
                    '— a report that tells nobody is the gap this closes', n;
  END IF;
  RAISE NOTICE 'PASS: filing an emergency queues a notice';

  SELECT payload ->> 'to_tier', payload ->> 'geo_pu'
    INTO tier, pu
    FROM public.notification_outbox
   WHERE alert_id = a_id AND kind = 'NEW_INCIDENT';

  IF tier <> 'UNIT' THEN
    RAISE EXCEPTION 'FAIL: a new SOS was addressed to tier %, not the unit it '
                    'landed in', tier;
  END IF;
  IF pu <> 'PU-01' THEN
    RAISE EXCEPTION 'FAIL: the notice carries polling unit %, so the console '
                    'cannot scope it to the officers who are there', pu;
  END IF;
  RAISE NOTICE 'PASS: it is addressed to the unit the incident landed in';

  -- ── A COMPLAINT ABOUT SECURITY PERSONNEL ─────────────────────────────────
  --
  -- The BEFORE INSERT trigger routes it to HQ. The notice reads
  -- `NEW.assigned_tier` rather than hardcoding 'UNIT', so it goes to HQ too —
  -- hardcoding would have been a way around the oversight rule through a door
  -- nobody was watching.
  INSERT INTO public.alerts
    (type, status, severity, description, reported_by, geo_lga, geo_ward, geo_pu)
  -- The CATEGORY is what `is_oversight_matter()` matches — the part before
  -- ' - ' — so a subtype is used here deliberately: a made-up type string
  -- ('Misconduct by security personnel') matched nothing, the complaint was
  -- announced to the unit, and this assertion was what said so.
  VALUES ('Security Personnel Misconduct - Assault at a checkpoint', 'PENDING',
          'HIGH', 'an officer at the checkpoint', reporter,
          'JOS NORTH', 'NARAGUTA', 'PU-01')
  RETURNING id INTO a_id;

  SELECT payload ->> 'to_tier' INTO tier
    FROM public.notification_outbox
   WHERE alert_id = a_id AND kind = 'NEW_INCIDENT';

  IF tier IS NULL THEN
    RAISE EXCEPTION 'FAIL: a complaint queued no notice at all';
  END IF;
  IF tier <> 'HQ' THEN
    RAISE EXCEPTION 'FAIL: a complaint about security personnel was announced '
                    'to tier %, which is the local command it is about', tier;
  END IF;
  RAISE NOTICE 'PASS: a complaint is announced to HQ, not to the local command';

  -- ── AND FILING WINS OVER NOTIFYING ───────────────────────────────────────
  --
  -- The hot path of the one thing this system exists to do. With the outbox
  -- unreachable the INSERT must still succeed: an emergency that reaches the
  -- database silently beats one refused because a notice could not be written.
  ALTER TABLE public.notification_outbox RENAME TO notification_outbox_hidden;

  INSERT INTO public.alerts
    (type, status, severity, description, reported_by, geo_lga, geo_ward, geo_pu)
  VALUES ('SOS', 'PENDING', 'CRITICAL', 'filed while the outbox was gone',
          reporter, 'JOS NORTH', 'NARAGUTA', 'PU-01')
  RETURNING id INTO a_id;

  ALTER TABLE public.notification_outbox_hidden RENAME TO notification_outbox;

  IF a_id IS NULL THEN
    RAISE EXCEPTION 'FAIL: the emergency was not filed';
  END IF;
  SELECT count(*) INTO n FROM public.alerts WHERE id = a_id;
  IF n <> 1 THEN
    RAISE EXCEPTION 'FAIL: an SOS was refused because its notice could not be '
                    'queued — the trigger must swallow its own failure';
  END IF;
  RAISE NOTICE 'PASS: an SOS is filed even when no notice can be queued';

  -- And nothing was queued for it, which is the cost and is the right cost.
  SELECT count(*) INTO n FROM public.notification_outbox WHERE alert_id = a_id;
  IF n <> 0 THEN
    RAISE EXCEPTION 'FAIL: a notice appeared for an insert made while the '
                    'outbox was unreachable, so this test proves nothing';
  END IF;
  RAISE NOTICE 'PASS: the notice is lost and the report is not';

  -- ── AND IT WORKS ON THE PATH THAT ACTUALLY HAPPENS ──────────────────────
  --
  -- Every insert above was made as the owner. The real one is a CITIZEN, and
  -- `notification_outbox` is `REVOKE ALL ... FROM anon, authenticated` with RLS
  -- on and no policy for them — "every row is invisible and unwritable to
  -- them". That is why the trigger is SECURITY DEFINER, and this is the
  -- assertion that proves the grants line up rather than assuming they do: the
  -- table, and the sequence behind its BIGSERIAL, are both owner-only.
  PERFORM set_config('request.jwt.claim.sub', reporter::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  SET LOCAL ROLE authenticated;

  INSERT INTO public.alerts
    (type, status, severity, description, reported_by, geo_lga, geo_ward, geo_pu)
  VALUES ('SOS', 'PENDING', 'CRITICAL', 'filed by the citizen themselves',
          reporter, 'JOS NORTH', 'NARAGUTA', 'PU-01')
  RETURNING id INTO a_id;

  RESET ROLE;

  SELECT count(*) INTO n FROM public.notification_outbox
   WHERE alert_id = a_id AND kind = 'NEW_INCIDENT';
  IF n <> 1 THEN
    RAISE EXCEPTION 'FAIL: a citizen filing their own SOS queued % notices, '
                    'not 1 — the trigger needs SECURITY DEFINER because the '
                    'outbox is revoked from authenticated', n;
  END IF;
  RAISE NOTICE 'PASS: a citizen filing their own SOS queues the notice';

  -- And they still cannot read it.
  PERFORM set_config('request.jwt.claim.sub', reporter::text, true);
  SET LOCAL ROLE authenticated;
  BEGIN
    SELECT count(*) INTO n FROM public.notification_outbox;
    RESET ROLE;
    IF n <> 0 THEN
      RAISE EXCEPTION 'FAIL: a citizen can read % outbox row(s) — the notices '
                      'name incidents and tiers that are not theirs', n;
    END IF;
  EXCEPTION WHEN insufficient_privilege THEN
    RESET ROLE;
    -- Refused outright by the REVOKE, which is the stronger of the two.
    n := 0;
  END;
  RAISE NOTICE 'PASS: writing the notice did not make it readable to them';

  RAISE NOTICE 'ALL NEW INCIDENT NOTICE ASSERTIONS PASSED';
END $$;

ROLLBACK;
