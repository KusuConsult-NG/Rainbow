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
-- 20261008000000_escalation_push_targets.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261008000000_escalation_push_targets.sql'; END $apply$;

-- Who a queued escalation is actually for, decided once, in the database.
--
-- ## The bug this is half of
--
-- `drain-outbox` handles three kinds — PUSH, SMS, WEBHOOK — and its default
-- branch logs "Unknown kind — marking delivered" and then marks the row
-- delivered.
--
-- Nothing writes PUSH, SMS or WEBHOOK rows. The only thing that writes to
-- `notification_outbox` is `escalate_overdue_alerts()`, and it writes
-- `TIER_ESCALATION`.
--
-- So every automatic escalation queued a notice, the worker did not recognise
-- it, and marked it delivered without telling anybody. That is precisely the
-- failure the outbox was built to end, reproduced in the thing built to drain
-- it — and worse than having no worker at all, because the rows are consumed:
-- `select count(*) from notification_outbox where delivered_at is null` reads
-- zero and the queue looks healthy.
--
-- ## Why the rule lives here and not in the worker
--
-- There are two drainers now — this Edge Function and
-- `/api/notify/drain` in the console — and the rule for who hears about an
-- escalation is subtle in both directions. Too narrow and an incident climbs
-- to a tier where nobody is told, which is the state being fixed. Too wide and
-- every escalation in Plateau wakes every commander, and people turn off the
-- notification they need.
--
-- Written twice it will drift. Written here, both drainers ask the same
-- question and get the same answer, and it is checkable in SQL against the
-- same database that decided the escalation.
--
-- The rule matches `alert_in_my_area()` deliberately: the tier that now owns
-- the incident, in the place the incident is. An officer row-level security
-- would refuse the row to is not sent a push about it.

CREATE OR REPLACE FUNCTION public.escalation_push_targets(p_outbox_id BIGINT)
RETURNS TABLE (user_id UUID, player_id TEXT, role TEXT)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
  WITH notice AS (
    SELECT o.payload
      FROM public.notification_outbox o
     WHERE o.id = p_outbox_id
       AND o.kind = 'TIER_ESCALATION'
  ),
  want AS (
    SELECT upper(coalesce(payload ->> 'to_tier', ''))            AS tier,
           nullif(upper(trim(coalesce(payload ->> 'geo_lga',  ''))), '') AS lga,
           nullif(upper(trim(coalesce(payload ->> 'geo_ward', ''))), '') AS ward,
           nullif(upper(trim(coalesce(payload ->> 'geo_pu',   ''))), '') AS pu
      FROM notice
  )
  SELECT p.id, p.onesignal_player_id, p.role
    FROM public.profiles p, want w
   WHERE p.onesignal_player_id IS NOT NULL
     AND length(p.onesignal_player_id) > 5
     AND upper(coalesce(p.role, '')) = ANY (
           CASE w.tier
             WHEN 'UNIT' THEN ARRAY['UNIT_COMMAND','POLLING_UNIT_OFFICER','POLLING_OFFICER']
             WHEN 'WARD' THEN ARRAY['WARD_COMMAND','WARD_OFFICER']
             WHEN 'LGA'  THEN ARRAY['LGA_COMMAND','LGA_OFFICER']
             WHEN 'HQ'   THEN ARRAY['HQ_COMMAND','HQ_OFFICER','ADMIN']
             -- A tier nobody holds addresses nobody. Failing open here would
             -- page the whole state on a malformed payload.
             ELSE ARRAY[]::TEXT[]
           END
         )
     AND (
       -- HQ is the whole state; it is the rung whose job is everything.
       w.tier = 'HQ'
       -- An incident with no location goes to the tier regardless of posting.
       -- These are the SOS reports that arrived without a GPS fix, and they
       -- must not fall silently between desks.
       OR w.lga IS NULL
       OR (
         nullif(upper(trim(coalesce(p.geo_lga, ''))), '') = w.lga
         AND (w.tier <> 'WARD' OR w.ward IS NULL
              OR nullif(upper(trim(coalesce(p.geo_ward, ''))), '') = w.ward)
         AND (w.tier <> 'UNIT' OR w.pu IS NULL
              OR nullif(upper(trim(coalesce(p.geo_pu, ''))), '') = w.pu)
       )
     );
$$;

COMMENT ON FUNCTION public.escalation_push_targets(BIGINT) IS
  'The officers a queued TIER_ESCALATION is for: the tier that now owns the '
  'incident, in the place the incident is. Mirrors alert_in_my_area() so a '
  'push is never sent to somebody RLS would refuse the incident to.';

REVOKE ALL ON FUNCTION public.escalation_push_targets(BIGINT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.escalation_push_targets(BIGINT) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.escalation_push_targets(BIGINT) TO service_role;

