-- ============================================================================
-- THE DELIVERY LOG OF AN INTER-AGENCY HANDOVER
-- ============================================================================
--
-- `agency_notifications` is the only durable record of whether the Police, the
-- Army or the DSS were actually told about an incident HQ handed to them.
-- `/api/notify-agency` writes one row per leg — SMS, webhook, and the legs it
-- skipped because no contact is configured.
--
-- It was created TWICE, by two migrations with different column lists and
-- `CREATE TABLE IF NOT EXISTS` on both, so the second is a no-op and the shape
-- a database ends up with depends on which file ran first:
--
--   20260722000000_v3_telemetry_geofence  detail, sent_by, target_lga,
--                                         acknowledged_at — and no created_at
--   20260812000000_agency_tables          created_at — and none of those four
--
-- The v3 era was applied to production BY HAND and is excluded from every
-- replay in this repository, so production has one shape and every database CI
-- or staging can build has the other. `agency_action_reports` and
-- `agency_deployments` are split the same way.
--
-- 20261023000000_one_table_one_shape.sql converges them. These assertions are
-- about the DATABASE rather than the migration text: every column both
-- definitions ever claimed is present, a row carrying the delivery reason
-- inserts, and reading the log is still command-only.
--
--   psql -f scripts/agency_delivery_behaviour_test.sql
--
-- Expects the full migration history. Read-write on its own rows only, inside
-- one transaction that is rolled back.
-- ============================================================================

\set ON_ERROR_STOP on
SET client_min_messages TO NOTICE;

BEGIN;

-- ── 1. both shapes converged ────────────────────────────────────────────────
--
-- Named one at a time, with the definition each came from, so a failure says
-- WHICH migration's column is missing rather than "the shapes differ".
DO $$
DECLARE
  missing TEXT[] := '{}';
  expected RECORD;
BEGIN
  FOR expected IN
    SELECT * FROM (VALUES
      -- agency_notifications: the v3 columns, then the 20260812 one.
      ('agency_notifications', 'detail'),
      ('agency_notifications', 'sent_by'),
      ('agency_notifications', 'target_lga'),
      ('agency_notifications', 'acknowledged_at'),
      ('agency_notifications', 'created_at'),
      -- agency_action_reports
      ('agency_action_reports', 'submitted_at'),
      ('agency_action_reports', 'created_at'),
      -- agency_deployments
      ('agency_deployments', 'deployed_at'),
      ('agency_deployments', 'resolved_at'),
      ('agency_deployments', 'created_at')
    ) AS t(tbl, col)
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
       WHERE table_schema = 'public'
         AND table_name = expected.tbl
         AND column_name = expected.col
    ) THEN
      missing := missing || (expected.tbl || '.' || expected.col);
    END IF;
  END LOOP;

  IF array_length(missing, 1) > 0 THEN
    RAISE EXCEPTION 'FAIL: this database is missing % — so it is one of the two '
                    'shapes rather than the converged one, and code written '
                    'against the other shape fails here only: %',
                    array_length(missing, 1), array_to_string(missing, ', ');
  END IF;
  RAISE NOTICE 'PASS: all 10 columns from both definitions are present';
END $$;

-- ── 2. the delivery REASON can be recorded ─────────────────────────────────
--
-- The route dropped `result.detail` because the column existed on production
-- and nowhere else. This is the write it now makes, in full. A failure here is
-- a 428C9/42703 from PostgREST in production, on the one path that records
-- whether an outside agency was reached.
INSERT INTO auth.users (id, email)
VALUES ('eeee0000-0000-4000-8000-00000000ad01', 'ad-hq@staging.test')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles (id, email, full_name, role, geo_lga)
VALUES ('eeee0000-0000-4000-8000-00000000ad01', 'ad-hq@staging.test',
        'HQ Operator', 'HQ_COMMAND', NULL)
ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role;

INSERT INTO public.alerts (id, type, status, description, reported_by, geo_lga)
VALUES ('eeee0000-0000-4000-8000-00000000ad10',
        'Armed Robbery - Highway', 'ESCALATED',
        'agency delivery test', NULL, 'JOS NORTH');

DO $$
DECLARE
  stored_detail TEXT;
  stored_created TIMESTAMPTZ;
BEGIN
  INSERT INTO public.agency_notifications
    (alert_id, agency, method, status, sent_at, detail, sent_by, target_lga)
  VALUES ('eeee0000-0000-4000-8000-00000000ad10', 'POLICE', 'WEBHOOK', 'FAILED',
          NOW(), 'HTTP 502', 'ad-hq@staging.test', 'JOS NORTH');

  SELECT detail, created_at INTO stored_detail, stored_created
    FROM public.agency_notifications
   WHERE alert_id = 'eeee0000-0000-4000-8000-00000000ad10';

  IF stored_detail IS DISTINCT FROM 'HTTP 502' THEN
    RAISE EXCEPTION 'FAIL: the delivery reason did not survive the write (%)',
                    coalesce(stored_detail, 'NULL');
  END IF;

  -- The default has to be on the column, not left to the caller: the route
  -- writes `sent_at` and not `created_at`, and a NULL here on every row is how
  -- a column comes to be believed unusable.
  IF stored_created IS NULL THEN
    RAISE EXCEPTION 'FAIL: created_at has no default, so every row the route '
                    'writes leaves it NULL';
  END IF;

  RAISE NOTICE 'PASS: a leg records WHY it failed, and carries a time of its own';
END $$;

-- ── 3. a skipped leg is a row, not an absence ──────────────────────────────
--
-- "No contact configured for the DSS" has to be a row saying so. The route's
-- own comment: a row set that omits the channels nobody used cannot answer
-- whether the agency was told.
DO $$
DECLARE
  legs INT;
BEGIN
  INSERT INTO public.agency_notifications
    (alert_id, agency, method, status, sent_at, detail)
  VALUES ('eeee0000-0000-4000-8000-00000000ad10', 'DSS', 'SMS', 'SKIPPED',
          NOW(), 'no contact configured');

  SELECT count(*) INTO legs
    FROM public.agency_notifications
   WHERE alert_id = 'eeee0000-0000-4000-8000-00000000ad10';

  IF legs <> 2 THEN
    RAISE EXCEPTION 'FAIL: expected both legs on the record, found %', legs;
  END IF;
  RAISE NOTICE 'PASS: a skipped channel is recorded as a skipped channel';
END $$;

-- ── 4. who may read it ─────────────────────────────────────────────────────
--
-- Characterisation, so that a later widening is deliberate: 20260813000000
-- replaced the v3 policies — which keyed on `user_metadata ->> 'role'`, a
-- claim the user can write themselves — with command-only read and write.
INSERT INTO auth.users (id, email)
VALUES ('eeee0000-0000-4000-8000-00000000ad02', 'ad-liaison@staging.test'),
       ('eeee0000-0000-4000-8000-00000000ad03', 'ad-citizen@staging.test')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles (id, email, full_name, role, geo_lga)
VALUES ('eeee0000-0000-4000-8000-00000000ad02', 'ad-liaison@staging.test',
        'Police Liaison', 'POLICE_LIAISON', NULL),
       ('eeee0000-0000-4000-8000-00000000ad03', 'ad-citizen@staging.test',
        'Citizen', 'CITIZEN', 'JOS NORTH')
ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role;

-- `request.jwt.claim.sub`, SINGULAR, and `SET LOCAL ROLE authenticated`: that
-- is what the shim's `auth.uid()` reads and what every other behaviour test
-- here uses. Written with the JSON `request.jwt.claims` form first, this
-- reported that COMMAND cannot read the log it writes — `auth.uid()` was NULL,
-- so `is_command()` was false for everybody and all three counts were 0. An
-- identity test whose identity does not take holds every grant closed, which
-- passes two assertions out of three for the wrong reason.
CREATE OR REPLACE FUNCTION pg_temp.legs_visible_to(p_uid UUID)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE n INTEGER;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_uid::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM public.agency_notifications
   WHERE alert_id = 'eeee0000-0000-4000-8000-00000000ad10';
  RESET ROLE;
  RETURN n;
END $$;

DO $$
DECLARE
  as_command INT;
  as_liaison INT;
  as_citizen INT;
BEGIN
  as_command := pg_temp.legs_visible_to('eeee0000-0000-4000-8000-00000000ad01');
  as_liaison := pg_temp.legs_visible_to('eeee0000-0000-4000-8000-00000000ad02');
  as_citizen := pg_temp.legs_visible_to('eeee0000-0000-4000-8000-00000000ad03');

  IF as_command <> 2 THEN
    RAISE EXCEPTION 'FAIL: command cannot read the delivery log it writes (% of 2)',
                    as_command;
  END IF;
  IF as_liaison <> 0 THEN
    RAISE EXCEPTION 'FAIL: an agency liaison reads the delivery log (% rows). '
                    'That may be desirable, but it is not what '
                    '20260813000000 grants, and a widening must be deliberate',
                    as_liaison;
  END IF;
  IF as_citizen <> 0 THEN
    RAISE EXCEPTION 'FAIL: a citizen reads the inter-agency delivery log (% rows)',
                    as_citizen;
  END IF;
  RAISE NOTICE 'PASS: command reads the delivery log; a liaison and a citizen do not';
END $$;

-- ── 5. the handover's own columns survive a resolution ─────────────────────
DO $$
DECLARE
  resolved TIMESTAMPTZ;
BEGIN
  INSERT INTO public.agency_deployments
    (alert_id, agency, personnel_ids, personnel_count, deployment_note,
     status, deployed_by, deployed_at, resolved_at)
  VALUES ('eeee0000-0000-4000-8000-00000000ad10', 'POLICE', '{}', 0,
          'delivery test', 'RESOLVED',
          'eeee0000-0000-4000-8000-00000000ad01', NOW(), NOW());

  SELECT resolved_at INTO resolved FROM public.agency_deployments
   WHERE alert_id = 'eeee0000-0000-4000-8000-00000000ad10';

  IF resolved IS NULL THEN
    RAISE EXCEPTION 'FAIL: agency_deployments.resolved_at did not store — it is '
                    'on production and was absent from every other database';
  END IF;
  RAISE NOTICE 'PASS: a deployment can record when the agency stood down';
END $$;

ROLLBACK;

\echo 'AGENCY DELIVERY LOG: all assertions passed'
