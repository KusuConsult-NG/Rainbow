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
