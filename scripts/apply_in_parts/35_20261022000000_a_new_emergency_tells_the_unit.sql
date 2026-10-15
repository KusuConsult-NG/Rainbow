--
-- ONE PART OF scripts/apply_all_migrations.sql — generated, do not edit by hand.
--   Regenerate with: python3 scripts/build_apply_in_parts.py
--
-- Run the parts IN NUMBER ORDER, each on its own, letting each finish before the
-- next. The order is not cosmetic: part 02 drops the permissive policy set BY
-- NAME, and several later parts assume columns an earlier part adds.
--
-- Expect `NOTICE: skipping ...` lines — they are the guards that let these files
-- run against a database that does not have a given table yet.
--
-- ONE PART BEHAVES DIFFERENTLY IF YOU RUN IT TWICE. Part 02, the RLS policy
-- migration, is ATOMIC rather than idempotent: it drops the old policy set by
-- name and creates a new one inside its own BEGIN/COMMIT. Run it a second time
-- and it says
--
--     ERROR: policy "profiles_select_self_or_staff" for table "profiles"
--            already exists
--
-- and rolls itself back. That message means THE POLICIES ARE ALREADY IN PLACE.
-- Nothing is half-applied, and part 15 will still report every row PASS.
--
-- Part 15 is the readout: it writes nothing and tells you the truth about the
-- whole set. It needs parts 01-14 applied first, because it checks work they do;
-- run it early and it says so plainly rather than failing on a missing function.
--
-- The LAST part writes nothing. It returns one row per thing that had to be
-- true, and every one of them must read PASS.
--
-- If you can paste the whole of apply_all_migrations.sql in one go, do that
-- instead: one paste cannot be run out of order or stopped halfway by accident.
--

-- ----------------------------------------------------------------------------
-- 20261022000000_a_new_emergency_tells_the_unit.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261022000000_a_new_emergency_tells_the_unit.sql'; END $apply$;

-- ============================================================================
-- A NEW EMERGENCY TELLS THE UNIT IT LANDED IN
-- ============================================================================
--
-- `notification_outbox` was built for the TIMEOUT escalation, and its own
-- header says why that mattered:
--
--     an incident that climbed to the LGA at 02:00 because nobody at the ward
--     answered was moved into another tier's queue in complete silence, and
--     was only seen if somebody happened to have the console open. The whole
--     point of the timeout is the case where nobody is watching.
--
-- Every word of that applies more strongly to the FIRST report. Nothing queued
-- a notice when an alert was INSERTED. The only paths that reached a phone
-- were a human pressing DISPATCH or ESCALATE on the console, and the timeout
-- job two minutes later. So a citizen's SOS reached a responder only if that
-- responder happened to have the app open and in the foreground; a phone in a
-- pocket learned nothing until a dispatcher acted or the unit's window expired.
--
-- The irony is the shape of the gap: the system notified you when it gave up
-- waiting for you, and not when the emergency arrived.
--
-- WHO IS TOLD
--
-- The tier the row lands at, which is `NEW.assigned_tier` — not a hardcoded
-- 'UNIT'. That matters for one case and it is the important one: the BEFORE
-- INSERT trigger `route_oversight_to_hq_trg` sets `assigned_tier := 'HQ'` for a
-- complaint against security personnel, so reading the column means a complaint
-- is never announced to the local command it is about. Hardcoding the unit
-- would have been a way around the oversight rule, through a door nobody was
-- watching.
--
-- The console's drain then widens the UNIT audience for this kind to the field
-- responders as well as the unit's desk, because the responders are who go. An
-- officer who would be refused the row by RLS is never sent a push about it:
-- `alert_in_my_area()` gives a field responder their whole LGA, so their own
-- polling unit is well inside it.
--
-- WHY FILING THE EMERGENCY WINS
--
-- This is the hot path of the one thing the system exists to do. The trigger
-- therefore catches its own failure: if the notice cannot be queued, the SOS is
-- still filed and a WARNING goes to the PostgreSQL log. An emergency that
-- reaches the database silently beats one refused because a notice could not be
-- written. SECURITY DEFINER for the same reason — the outbox is not readable or
-- writable by a citizen, and the insert must not depend on that changing.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.queue_new_incident_notice()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  BEGIN
    INSERT INTO public.notification_outbox (alert_id, kind, payload)
    VALUES (
      NEW.id,
      'NEW_INCIDENT',
      jsonb_build_object(
        'alert_id',  NEW.id,
        -- No `from_tier`: nothing moved. A new incident is not an escalation,
        -- and the notice must not read like one.
        'to_tier',   coalesce(NEW.assigned_tier, 'UNIT'),
        'geo_lga',   NEW.geo_lga,
        'geo_ward',  NEW.geo_ward,
        'geo_pu',    NEW.geo_pu,
        'severity',  NEW.severity,
        'type',      NEW.type,
        'reason',    'REPORTED'
      )
    );
  EXCEPTION WHEN OTHERS THEN
    -- The SOS is already written; this is the notice about it. Losing the
    -- notice is bad and losing the report is worse.
    RAISE WARNING '[NEW_INCIDENT_NOTICE] could not queue a notice for %: %',
      NEW.id, SQLERRM;
  END;
  RETURN NULL;  -- AFTER trigger: the return value is discarded.
END $$;

COMMENT ON FUNCTION public.queue_new_incident_notice() IS
  'AFTER INSERT on alerts: queues a NEW_INCIDENT notice for the tier the row '
  'landed at, so the first report is announced and not only the timeout that '
  'follows it. Swallows its own failure: the emergency is filed either way.';

DROP TRIGGER IF EXISTS queue_new_incident_notice_trg ON public.alerts;
CREATE TRIGGER queue_new_incident_notice_trg
  AFTER INSERT ON public.alerts
  FOR EACH ROW EXECUTE FUNCTION public.queue_new_incident_notice();

COMMIT;

