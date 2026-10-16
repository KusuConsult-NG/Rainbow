-- ============================================================================
-- A REPORT THAT IS NOT AN EMERGENCY, AND A VOICE NOTE
-- ============================================================================
--
-- `20261024000000` adds two things an operator asked for: a voice note from
-- somebody who cannot type, and a general report about government property.
--
-- The second one is dangerous in a system built to treat everything as a
-- kidnapping. These assertions are about the two mechanisms that would
-- otherwise pick it up and run with it:
--
--   * `queue_new_incident_notice()` announces every INSERT to the tier it
--     landed at, and the drain widens a UNIT notice to the field responders.
--     A culvert filed at 02:00 must not reach their handsets.
--   * `escalate_overdue_alerts()` climbs anything unacknowledged. A street
--     light nobody looked at overnight must not be an HQ-tier incident by
--     morning, with three escalations against it, among the night's real
--     emergencies.
--
--   psql -f scripts/non_emergency_behaviour_test.sql
--
-- Expects the full migration history. Read-write on its own rows only, inside
-- one transaction that is rolled back.
-- ============================================================================

\set ON_ERROR_STOP on
SET client_min_messages TO NOTICE;

BEGIN;

INSERT INTO auth.users (id, email)
VALUES ('eeee0000-0000-4000-8000-0000000000e1', 'ne-citizen@staging.test')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles (id, email, full_name, role, geo_lga, geo_ward, geo_pu)
VALUES ('eeee0000-0000-4000-8000-0000000000e1', 'ne-citizen@staging.test',
        'Citizen', 'CITIZEN', 'JOS NORTH', 'NARAGUTA', 'PU-01')
ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role;

-- ── 1. which categories the database holds back ────────────────────────────
DO $$
BEGIN
  -- Matched on the CATEGORY, so every subtype is covered without listing them.
  IF NOT public.is_non_emergency('Public property - Abandoned or derelict') THEN
    RAISE EXCEPTION 'FAIL: a public property report is not recognised as a '
                    'non-emergency, so it will be paged out and climbed';
  END IF;
  IF NOT public.is_non_emergency('Public service - Street light out') THEN
    RAISE EXCEPTION 'FAIL: a public service report is not recognised';
  END IF;
  -- A subtype nobody has written yet. The whole point of matching on the
  -- category is that the app can add one without a migration.
  IF NOT public.is_non_emergency('Public property - Something nobody has thought of yet') THEN
    RAISE EXCEPTION 'FAIL: a NEW subtype of an existing category is not covered, '
                    'so adding one to the app silently makes it an emergency';
  END IF;

  -- And an emergency is still an emergency.
  IF public.is_non_emergency('Kidnap - Immediate Abduction') THEN
    RAISE EXCEPTION 'FAIL: a kidnapping is held out of the escalation ladder';
  END IF;
  IF public.is_non_emergency('PANIC SOS') THEN
    RAISE EXCEPTION 'FAIL: a panic SOS is held out of the escalation ladder';
  END IF;
  -- The empty and null cases, which a citizen's app can produce when a
  -- category is missing. Treating those as non-emergencies would hold a real
  -- report back, so they must NOT match.
  IF public.is_non_emergency('') OR public.is_non_emergency(NULL) THEN
    RAISE EXCEPTION 'FAIL: a report with no type is treated as a non-emergency';
  END IF;
  RAISE NOTICE 'PASS: the category decides, and only those two categories';
END $$;

-- ── 2. it lands at the LGA, not in a patrol's pocket ──────────────────────
DO $$
DECLARE
  tier     TEXT;
  assignee TEXT;
  routed   JSONB;
BEGIN
  INSERT INTO public.alerts
    (id, type, status, description, reported_by, geo_lga, geo_ward, geo_pu,
     severity, assigned_tier, assigned_to)
  VALUES ('eeee0000-0000-4000-8000-0000000000f0',
          'Public service - Street light out', 'PENDING',
          'The light at the junction has been out for a week.',
          'eeee0000-0000-4000-8000-0000000000e1',
          'JOS NORTH', 'NARAGUTA', 'PU-01', 'LOW',
          -- As the app files it: at the unit, assigned to whoever is posted
          -- there. The trigger has to undo both.
          'UNIT', 'eeee0000-0000-4000-8000-0000000000e1');

  SELECT assigned_tier, assigned_to, escalation_log
    INTO tier, assignee, routed
    FROM public.alerts WHERE id = 'eeee0000-0000-4000-8000-0000000000f0';

  IF tier IS DISTINCT FROM 'LGA' THEN
    RAISE EXCEPTION 'FAIL: a street light landed at tier % — at UNIT the drain '
                    'widens the notice to the field responders'' handsets', tier;
  END IF;
  IF assignee IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: a street light is assigned to a responder (%), who '
                    'cannot fix it and now has a dispatch for it', assignee;
  END IF;
  IF NOT (routed @> '[{"action": "NON_EMERGENCY_ROUTED"}]'::jsonb) THEN
    RAISE EXCEPTION 'FAIL: nothing on the record says why this was routed to '
                    'the LGA: %', coalesce(routed::text, 'null');
  END IF;
  RAISE NOTICE 'PASS: it is filed at the LGA, assigned to nobody, and says why';
END $$;

-- ── 3. the notice goes out, addressed to the LGA ──────────────────────────
--
-- Not silence: something nobody is shown is something nobody fixes, which is
-- how a thing ends up abandoned. What must not happen is the UNIT addressing
-- that the drain widens to field responders.
DO $$
DECLARE
  notices INT;
  to_tier TEXT;
BEGIN
  SELECT count(*), max(payload ->> 'to_tier')
    INTO notices, to_tier
    FROM public.notification_outbox
   WHERE alert_id = 'eeee0000-0000-4000-8000-0000000000f0';

  IF notices <> 1 THEN
    RAISE EXCEPTION 'FAIL: expected exactly one notice for this report, found %',
                    notices;
  END IF;
  IF to_tier IS DISTINCT FROM 'LGA' THEN
    RAISE EXCEPTION 'FAIL: the notice is addressed to % — at UNIT it reaches '
                    'the handsets of the officers who go', to_tier;
  END IF;
  RAISE NOTICE 'PASS: one notice, addressed to the LGA desk and not to a patrol';
END $$;

-- ── 4. the clock does not move it ─────────────────────────────────────────
DO $$
DECLARE
  climbed INT;
  tier    TEXT;
BEGIN
  -- Back-date it well past every tier timeout. An emergency in this state
  -- would climb on the next sweep.
  UPDATE public.alerts
     SET tier_assigned_at = NOW() - INTERVAL '3 days',
         updated_at       = NOW() - INTERVAL '3 days'
   WHERE id = 'eeee0000-0000-4000-8000-0000000000f0';

  SELECT count(*) INTO climbed
    FROM public.escalate_overdue_alerts() e
   WHERE e.alert_id = 'eeee0000-0000-4000-8000-0000000000f0';

  SELECT assigned_tier INTO tier
    FROM public.alerts WHERE id = 'eeee0000-0000-4000-8000-0000000000f0';

  IF climbed <> 0 OR tier IS DISTINCT FROM 'LGA' THEN
    RAISE EXCEPTION 'FAIL: the timeout sweep moved a street light (% move(s), '
                    'now at %). By morning it would be an HQ-tier incident '
                    'with three escalations against it', climbed, tier;
  END IF;
  RAISE NOTICE 'PASS: three days overdue and the sweep leaves it where it is';
END $$;

-- ── 5. an emergency filed the same minute still climbs ────────────────────
--
-- The negative half. A rule that holds everything back would be indisputably
-- safe and completely useless, and this test would pass.
DO $$
DECLARE
  climbed INT;
BEGIN
  INSERT INTO public.alerts
    (id, type, status, description, reported_by, geo_lga, geo_ward, geo_pu,
     severity, assigned_tier, tier_assigned_at)
  VALUES ('eeee0000-0000-4000-8000-0000000000f1',
          'Kidnap - Immediate Abduction', 'PENDING', 'Taken at the junction.',
          'eeee0000-0000-4000-8000-0000000000e1',
          'JOS NORTH', 'NARAGUTA', 'PU-01', 'CRITICAL',
          'UNIT', NOW() - INTERVAL '3 days');

  SELECT count(*) INTO climbed
    FROM public.escalate_overdue_alerts() e
   WHERE e.alert_id = 'eeee0000-0000-4000-8000-0000000000f1';

  IF climbed <> 1 THEN
    RAISE EXCEPTION 'FAIL: an overdue KIDNAPPING did not climb (% move(s)). '
                    'The non-emergency rule has caught everything', climbed;
  END IF;
  RAISE NOTICE 'PASS: an overdue kidnapping still climbs';
END $$;

-- ── 6. a complaint about an officer still goes to HQ ─────────────────────
--
-- Two BEFORE INSERT triggers now set `assigned_tier`, and PostgreSQL fires
-- them in alphabetical order by name. The oversight decision must win.
DO $$
DECLARE
  tier TEXT;
BEGIN
  INSERT INTO public.alerts
    (id, type, status, description, reported_by, geo_lga, severity)
  VALUES ('eeee0000-0000-4000-8000-0000000000f2',
          'Security Personnel Misconduct - Assault at a checkpoint', 'PENDING',
          'An officer damaged a public building during an arrest.',
          'eeee0000-0000-4000-8000-0000000000e1', 'JOS NORTH', 'HIGH');

  SELECT assigned_tier INTO tier
    FROM public.alerts WHERE id = 'eeee0000-0000-4000-8000-0000000000f2';

  IF tier IS DISTINCT FROM 'HQ' THEN
    RAISE EXCEPTION 'FAIL: a complaint against security personnel landed at % '
                    'instead of HQ — the non-emergency router has taken '
                    'precedence over the oversight router', tier;
  END IF;
  RAISE NOTICE 'PASS: an oversight matter still goes to HQ, not to the LGA';
END $$;

-- ── 7. the voice note, and a duration that cannot lie ────────────────────
DO $$
DECLARE
  stored_url     TEXT;
  stored_seconds INT;
  refused        BOOLEAN := FALSE;
BEGIN
  UPDATE public.alerts
     SET voice_note_url = 'https://res.cloudinary.com/x/raw/upload/v1/voice.m4a',
         voice_note_seconds = 42
   WHERE id = 'eeee0000-0000-4000-8000-0000000000f0';

  SELECT voice_note_url, voice_note_seconds INTO stored_url, stored_seconds
    FROM public.alerts WHERE id = 'eeee0000-0000-4000-8000-0000000000f0';

  IF stored_url IS NULL OR stored_seconds <> 42 THEN
    RAISE EXCEPTION 'FAIL: the voice note did not store (% / %)',
                    coalesce(stored_url, 'null'), coalesce(stored_seconds, -1);
  END IF;

  -- A negative or absurd duration is a bug in whatever wrote it, and a column
  -- that accepts one makes the screen rendering it lie about what it holds.
  BEGIN
    UPDATE public.alerts SET voice_note_seconds = -5
     WHERE id = 'eeee0000-0000-4000-8000-0000000000f0';
  EXCEPTION WHEN check_violation THEN
    refused := TRUE;
  END;
  IF NOT refused THEN
    RAISE EXCEPTION 'FAIL: a voice note of -5 seconds was accepted';
  END IF;

  refused := FALSE;
  BEGIN
    UPDATE public.alerts SET voice_note_seconds = 100000
     WHERE id = 'eeee0000-0000-4000-8000-0000000000f0';
  EXCEPTION WHEN check_violation THEN
    refused := TRUE;
  END;
  IF NOT refused THEN
    RAISE EXCEPTION 'FAIL: a voice note of 100000 seconds was accepted — the '
                    'recorder stops at ten minutes, so this is a bug being '
                    'written down as a fact';
  END IF;
  RAISE NOTICE 'PASS: a voice note stores, and an impossible duration does not';
END $$;

ROLLBACK;

\echo 'NON-EMERGENCY AND VOICE NOTE: all assertions passed'
