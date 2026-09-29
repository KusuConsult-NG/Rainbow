-- Demonstration incidents, so the console has something to be looked at with.
--
-- ############################################################################
-- #                                                                          #
-- #  STAGING OR LOCAL ONLY. NEVER RUN THIS AGAINST PRODUCTION.               #
-- #                                                                          #
-- #  It inserts CRITICAL alerts and a DURESS alarm. Against a live database   #
-- #  those are indistinguishable from real emergencies: they would reach the  #
-- #  duress counter, the escalation job, the agency portal and — once the     #
-- #  notification worker is running — somebody's phone at two in the morning. #
-- #                                                                          #
-- ############################################################################
--
-- Everything it writes is prefixed `dddd0000-` / `cccc0000-` and every
-- description begins with [DEMO], so the cleanup at the bottom of this file
-- removes exactly what this file added and nothing else.
--
-- ## What it is built to show
--
-- Not twenty rows of the same shape. Each incident exists to make one part of
-- the console show something:
--
--   * ten reporting categories, so the category filter has a real spread
--   * four severities, INCLUDING a row with none — it must read UNKNOWN and
--     stay out of the CRITICAL filter rather than being coloured red
--   * one with no coordinates, so the map's UNLOCATED callout has a subject
--   * one DURESS, which is its own counter and its own colour
--   * one escalated to the ARMY and one to the POLICE, so each agency portal
--     has an incident and neither can see the other's
--   * three sitting unacknowledged past their tier timeout, so
--     escalate_overdue_alerts() has something to climb and the notification
--     outbox has something to queue
--   * one already resolved, so Mission History is not empty
--   * incidents in seven LGAs, so the LGA/ward filters do something
--
-- Names are ordinary Nigerian names and the places are real Plateau
-- jurisdictions taken from tactical_mapping.ts, because a console full of
-- "Test User 1" teaches nobody what it looks like in use.

-- \set ON_ERROR_STOP on
SET client_min_messages TO NOTICE;

BEGIN;

-- ── The people who reported them ────────────────────────────────────────────
--
-- profiles.id references auth.users, so the accounts have to exist there
-- first. All CITIZEN: these are members of the public, not staff.

INSERT INTO auth.users (id, email, raw_user_meta_data) VALUES
  ('cccc0000-0000-4000-8000-00000000c001', 'demo.amina@example.test',   '{"full_name":"Amina Bello"}'::jsonb),
  ('cccc0000-0000-4000-8000-00000000c002', 'demo.danjuma@example.test', '{"full_name":"Danjuma Yakubu"}'::jsonb),
  ('cccc0000-0000-4000-8000-00000000c003', 'demo.ladi@example.test',    '{"full_name":"Ladi Dashe"}'::jsonb),
  ('cccc0000-0000-4000-8000-00000000c004', 'demo.ruth@example.test',    '{"full_name":"Ruth Gyang"}'::jsonb),
  ('cccc0000-0000-4000-8000-00000000c005', 'demo.musa@example.test',    '{"full_name":"Musa Adamu"}'::jsonb)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles (id, email, phone, full_name, role, geo_lga, geo_ward, geo_pu) VALUES
  ('cccc0000-0000-4000-8000-00000000c001', 'demo.amina@example.test',   '+2348030010001', 'Amina Bello',    'CITIZEN', 'JOS NORTH',    'ABBA NA SHEHU',      'BAUCHI ROAD I'),
  ('cccc0000-0000-4000-8000-00000000c002', 'demo.danjuma@example.test', '+2348030010002', 'Danjuma Yakubu', 'CITIZEN', 'JOS SOUTH',    'BUKURU',             'BAPTIST PRIMARY SCHOOL'),
  ('cccc0000-0000-4000-8000-00000000c003', 'demo.ladi@example.test',    '+2348030010003', 'Ladi Dashe',     'CITIZEN', 'MANGU',        'AMPANG WEST',      'AMPANG 1'),
  ('cccc0000-0000-4000-8000-00000000c004', 'demo.ruth@example.test',    '+2348030010004', 'Ruth Gyang',     'CITIZEN', 'BARKIN LADI',  'BARAKIN LADI','KATAKO'),
  ('cccc0000-0000-4000-8000-00000000c005', 'demo.musa@example.test',    '+2348030010005', 'Musa Adamu',     'CITIZEN', 'BOKKOS',       'BOKKOS',     'SHUKUR  I')
ON CONFLICT (id) DO UPDATE
  SET full_name = EXCLUDED.full_name,
      phone     = EXCLUDED.phone,
      geo_lga   = EXCLUDED.geo_lga,
      geo_ward  = EXCLUDED.geo_ward,
      geo_pu    = EXCLUDED.geo_pu;

-- ── The incidents ───────────────────────────────────────────────────────────
--
-- `type` is '<category> - <subtype>', which is the shape the app writes and
-- which `alerts.category` is generated from. Coordinates are real points in
-- each LGA so the map spreads rather than stacking one pin on Jos.

INSERT INTO public.alerts
  (id, type, description, status, severity, reported_by,
   geo_lga, geo_ward, geo_pu, latitude, longitude,
   assigned_tier, tier_assigned_at, acknowledged_at, created_at)
VALUES
  -- CRITICAL, unacknowledged, and long past the unit's two minutes: the
  -- escalation job should climb this one on its next run.
  ('dddd0000-0000-4000-8000-00000000d001',
   'Kidnap - Immediate Abduction',
   '[DEMO] Three men took a trader from the motor park in a grey pickup heading north.',
   'OPEN', 'CRITICAL', 'cccc0000-0000-4000-8000-00000000c001',
   'JOS NORTH', 'ABBA NA SHEHU', 'BAUCHI ROAD I',
   9.9285, 8.8921, 'UNIT', NOW() - INTERVAL '40 minutes', NULL, NOW() - INTERVAL '42 minutes'),

  ('dddd0000-0000-4000-8000-00000000d002',
   'Community attack - Armed Invasion',
   '[DEMO] Gunfire reported at the edge of the village; families moving towards the main road.',
   'OPEN', 'CRITICAL', 'cccc0000-0000-4000-8000-00000000c005',
   'BOKKOS', 'BOKKOS', 'SHUKUR  I',
   9.3006, 9.0028, 'WARD', NOW() - INTERVAL '25 minutes', NULL, NOW() - INTERVAL '50 minutes'),

  ('dddd0000-0000-4000-8000-00000000d003',
   'Fire - Building Fire',
   '[DEMO] Lock-up shops alight beside the market; smoke visible from the junction.',
   'DISPATCHED', 'HIGH', 'cccc0000-0000-4000-8000-00000000c002',
   'JOS SOUTH', 'BUKURU', 'BAPTIST PRIMARY SCHOOL',
   9.7896, 8.8608, 'UNIT', NOW() - INTERVAL '12 minutes', NOW() - INTERVAL '10 minutes', NOW() - INTERVAL '18 minutes'),

  -- No severity at all. Must read UNKNOWN and stay OUT of the CRITICAL filter:
  -- an ungraded report is not a red one.
  ('dddd0000-0000-4000-8000-00000000d004',
   'Flood - Rising Water',
   '[DEMO] Water across the road after last night''s rain; one culvert blocked.',
   'OPEN', NULL, 'cccc0000-0000-4000-8000-00000000c004',
   'BARKIN LADI', 'BARAKIN LADI', 'KATAKO',
   9.5361, 8.9003, 'UNIT', NOW() - INTERVAL '6 minutes', NULL, NOW() - INTERVAL '8 minutes'),

  -- No coordinates: the map must call this out as UNLOCATED rather than
  -- inventing a position for it.
  ('dddd0000-0000-4000-8000-00000000d005',
   'PANIC SOS',
   '[DEMO] Panic button pressed. No GPS fix was available on the handset.',
   'OPEN', 'CRITICAL', 'cccc0000-0000-4000-8000-00000000c003',
   'MANGU', 'AMPANG WEST', 'AMPANG 1',
   NULL, NULL, 'UNIT', NOW() - INTERVAL '3 minutes', NULL, NOW() - INTERVAL '3 minutes'),

  -- DURESS: its own counter and its own colour on the board.
  ('dddd0000-0000-4000-8000-00000000d006',
   'Kidnap - Held Hostage',
   '[DEMO] Duress PIN entered when closing an alert. Treat as still in progress.',
   'DURESS', 'CRITICAL', 'cccc0000-0000-4000-8000-00000000c003',
   'MANGU', 'AMPANG WEST', 'AMPANG 1',
   9.5228, 9.1003, 'LGA', NOW() - INTERVAL '15 minutes', NULL, NOW() - INTERVAL '35 minutes'),

  -- Handed to the ARMY. The Army liaison sees this and the Police liaison
  -- must not.
  ('dddd0000-0000-4000-8000-00000000d007',
   'Cattle rustling - Herd Taken',
   '[DEMO] Herd driven off overnight towards the hills; tracks visible at the stream.',
   'ESCALATED', 'HIGH', 'cccc0000-0000-4000-8000-00000000c005',
   'BOKKOS', 'BOKKOS', 'SHUKUR  I',
   9.2978, 9.0112, 'HQ', NOW() - INTERVAL '20 minutes', NOW() - INTERVAL '19 minutes', NOW() - INTERVAL '90 minutes'),

  -- Handed to the POLICE, for the other side of the same test.
  ('dddd0000-0000-4000-8000-00000000d008',
   'Police brutality - Assault In Custody',
   '[DEMO] Complaint of assault during an arrest at the checkpoint.',
   'ESCALATED', 'HIGH', 'cccc0000-0000-4000-8000-00000000c002',
   'JOS SOUTH', 'BUKURU', 'BAPTIST PRIMARY SCHOOL',
   9.7812, 8.8701, 'HQ', NOW() - INTERVAL '30 minutes', NOW() - INTERVAL '28 minutes', NOW() - INTERVAL '2 hours'),

  ('dddd0000-0000-4000-8000-00000000d009',
   'Domestic violence - Ongoing Assault',
   '[DEMO] Neighbour reports shouting and a struggle in the compound behind the school.',
   'OPEN', 'HIGH', 'cccc0000-0000-4000-8000-00000000c001',
   'JOS NORTH', 'ABBA NA SHEHU', 'BAUCHI ROAD I',
   9.9401, 8.8802, 'UNIT', NOW() - INTERVAL '30 minutes', NULL, NOW() - INTERVAL '31 minutes'),

  ('dddd0000-0000-4000-8000-00000000d010',
   'Drug abuse - Distribution',
   '[DEMO] Selling to schoolchildren reported behind the motor park at closing time.',
   'OPEN', 'MEDIUM', 'cccc0000-0000-4000-8000-00000000c004',
   'BARKIN LADI', 'BARAKIN LADI', 'KATAKO',
   9.5402, 8.9108, 'UNIT', NOW() - INTERVAL '4 minutes', NULL, NOW() - INTERVAL '5 minutes'),

  ('dddd0000-0000-4000-8000-00000000d011',
   'Child abuse - Neglect',
   '[DEMO] Two children left unattended overnight; reported by a neighbour.',
   'OPEN', 'MEDIUM', 'cccc0000-0000-4000-8000-00000000c003',
   'MANGU', 'AMPANG WEST', 'AMPANG 1',
   9.5301, 9.0955, 'UNIT', NOW() - INTERVAL '2 minutes', NULL, NOW() - INTERVAL '2 minutes'),

  ('dddd0000-0000-4000-8000-00000000d012',
   'Cyber crime - Financial Fraud',
   '[DEMO] Trader reports money moved from their account after a call asking for a code.',
   'OPEN', 'LOW', 'cccc0000-0000-4000-8000-00000000c002',
   'JOS SOUTH', 'BUKURU', 'BAPTIST PRIMARY SCHOOL',
   9.7901, 8.8555, 'UNIT', NOW() - INTERVAL '1 minute', NULL, NOW() - INTERVAL '1 minute'),

  -- Resolved, so Mission History is not an empty screen.
  ('dddd0000-0000-4000-8000-00000000d013',
   'Fire - Bush Fire',
   '[DEMO] Bush fire near the farms. Contained by the community with the fire service.',
   'RESOLVED', 'MEDIUM', 'cccc0000-0000-4000-8000-00000000c005',
   'BOKKOS', 'BOKKOS', 'SHUKUR  I',
   9.2890, 9.0201, 'UNIT', NOW() - INTERVAL '3 hours', NOW() - INTERVAL '3 hours', NOW() - INTERVAL '4 hours')
ON CONFLICT (id) DO NOTHING;

-- The two escalations, written the way the console writes them so the agency
-- portals filter on exactly what they filter on in use.
UPDATE public.alerts
   SET escalated_to_agency = 'ARMY',
       escalation_log = '[{"from_tier":"LGA","to_tier":"HQ","reason":"Needs a military response","by":"SYSTEM","at":"2026-09-29T05:00:00Z"},
                          {"from_tier":"HQ","to_tier":"ARMY","to_agency":"ARMY","reason":"Handed to the Nigerian Army","by":"SYSTEM","at":"2026-09-29T05:05:00Z"}]'::jsonb
 WHERE id = 'dddd0000-0000-4000-8000-00000000d007';

UPDATE public.alerts
   SET escalated_to_agency = 'POLICE',
       escalation_log = '[{"from_tier":"LGA","to_tier":"HQ","reason":"Complaint against an officer","by":"SYSTEM","at":"2026-09-29T04:30:00Z"},
                          {"from_tier":"HQ","to_tier":"POLICE","to_agency":"POLICE","reason":"Handed to the Nigeria Police Force","by":"SYSTEM","at":"2026-09-29T04:35:00Z"}]'::jsonb
 WHERE id = 'dddd0000-0000-4000-8000-00000000d008';

-- A movement track on the kidnapping, so the dossier's trail is not empty.
INSERT INTO public.incident_tracks (alert_id, user_id, latitude, longitude, accuracy, recorded_at)
SELECT 'dddd0000-0000-4000-8000-00000000d001',
       -- The track belongs to the person who reported it; user_id is NOT NULL
       -- because a position with nobody attached is not evidence of anything.
       'cccc0000-0000-4000-8000-00000000c001',
       9.9285 + (i * 0.0012),
       8.8921 + (i * 0.0009),
       12,
       NOW() - make_interval(mins => 40 - i * 4)
  FROM generate_series(0, 9) AS i
 WHERE EXISTS (SELECT 1 FROM information_schema.tables
                WHERE table_schema = 'public' AND table_name = 'incident_tracks')
ON CONFLICT DO NOTHING;

DO $$
DECLARE n INTEGER; cats INTEGER;
BEGIN
  SELECT count(*) INTO n FROM public.alerts WHERE description LIKE '[DEMO]%';
  SELECT count(DISTINCT category) INTO cats FROM public.alerts WHERE description LIKE '[DEMO]%';
  RAISE NOTICE 'seeded % demonstration incidents across % categories', n, cats;
END $$;

COMMIT;

-- ── Removing them again ─────────────────────────────────────────────────────
--
-- Run this and nothing else of yours goes with it: every row this file wrote
-- is either prefixed dddd0000-/cccc0000- or described as [DEMO].
--
--   BEGIN;
--   DELETE FROM public.incident_tracks
--    WHERE alert_id IN (SELECT id FROM public.alerts WHERE description LIKE '[DEMO]%');
--   DELETE FROM public.alerts   WHERE description LIKE '[DEMO]%';
--   DELETE FROM public.profiles WHERE id::text LIKE 'cccc0000-%';
--   DELETE FROM auth.users      WHERE id::text LIKE 'cccc0000-%';
--   COMMIT;
