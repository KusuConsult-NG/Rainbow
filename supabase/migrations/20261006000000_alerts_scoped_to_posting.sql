-- An officer's authority ends at their command.
--
-- ## What was wrong
--
-- The command chain had real structure for ROUTING — `assigned_tier`, the
-- escalation ladder, the per-tier timeout job — and none at all for AUTHORITY.
-- Every tier rule lived in a Dart function in the app (`canDispatchFrom`) or a
-- dropdown in the console. The database's rule was `alert_is_ours()`, whose
-- staff clause read:
--
--     public.is_staff() AND NOT public.is_liaison()
--
-- and `is_staff()` means only "role is not CITIZEN". So every Operation
-- Rainbow account, at any tier, in any LGA, could SELECT every incident in
-- Plateau State — and the identical predicate guards UPDATE, so they could
-- resolve one, reassign it, re-grade it, or clear a duress alarm 80km outside
-- their command.
--
-- The geography the product is built around existed only in the console's
-- filter dropdowns and the responder app's client-side list filter. Both narrow
-- what is SHOWN. Neither narrows what is PERMITTED, and anyone calling
-- PostgREST with their own token got the state.
--
-- This is the same defect as the agency liaisons one migration ago, one layer
-- in: `is_staff()` was written to mean "not a member of the public", and every
-- role that arrived later fell inside it.
--
-- ## The rule
--
--   HQ_COMMAND / HQ_OFFICER / ADMIN  the whole state
--   LGA_*                            their LGA
--   WARD_*                           their ward, within their LGA
--   UNIT_* / POLLING_*               their polling unit
--   RESPONDER / AGENT                their LGA — a field unit needs to see the
--                                    ground around it, not one polling unit
--
-- plus, for everyone, the incidents they reported, are assigned to, or are on
-- the team for; and for a liaison, what was escalated to their agency.
--
-- ## Four decisions that are not obvious, and are the whole safety of this
--
-- **An incident with no location stays visible to all staff.** Scoping by
-- geography means a row whose `geo_lga` is NULL matches nobody's area — so the
-- strict reading would hide it from everyone but HQ. Those rows are real: the
-- console already reports an "UNLOCATED" count for SOS reports that reached us
-- without a GPS fix. An emergency nobody can see is a worse outcome than one
-- seen too widely, so these fail OPEN, deliberately.
--
-- **The whole dispatched team is matched, not just the lead.** `dispatchAlert`
-- writes `assigned_to` (the lead) AND `assigned_responders` (the team), and the
-- responder app lists an officer's work by the array. The old policy only ever
-- mentioned `assigned_to`, which did not matter while every staff account could
-- see everything. The moment area scoping arrives it matters enormously: every
-- non-lead officer dispatched outside their own area would have lost the
-- incident they were sent to. `assigned_responders` is TEXT[], so the uid is
-- compared as text.
--
-- **An officer with no posting is narrowed, never widened.** A staff account
-- with a NULL `geo_lga` matches no area and keeps only what it reported, is
-- assigned to, or is on the team for. `profiles.geo_lga` is self-writable —
-- only `role` is guarded by the privilege-escalation trigger — so if an empty
-- posting meant "everywhere", a ward commander could clear their own LGA and
-- take the state. Blank must be the weakest posting, not the strongest.
--
-- **A delegated incident reaches the team it was delegated to.** HQ handing an
-- incident down to an LGA sets `assigned_tier = 'LGA'` and deliberately does
-- NOT rewrite `geo_lga`, because the incident's location is a fact about the
-- incident. So for an LGA other than the one it was reported in, area matching
-- alone would show it to the named commander (via `assigned_to`) and to nobody
-- else on their team — the delegation would arrive at one person's screen. The
-- last `escalation_log` entry carries `to_lga`, and that is read here.

-- ── Who commands the whole state ────────────────────────────────────────────
--
-- Narrower than `is_command()`, which includes LGA_COMMAND — correct for
-- broadcasting, wrong for "sees everything".

CREATE OR REPLACE FUNCTION public.commands_whole_state()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT COALESCE(
    (SELECT upper(coalesce(role, '')) FROM public.profiles WHERE id = auth.uid())
      IN ('HQ_COMMAND', 'HQ_OFFICER', 'ADMIN'),
    false
  );
$$;

COMMENT ON FUNCTION public.commands_whole_state() IS
  'HQ and administrators. Narrower than is_command(), which includes LGA_COMMAND.';

-- ── Is this incident inside my command ──────────────────────────────────────

CREATE OR REPLACE FUNCTION public.alert_in_my_area(p_alert public.alerts)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
  WITH me AS (
    SELECT upper(coalesce(role, ''))                          AS role,
           nullif(upper(trim(coalesce(geo_lga,  ''))), '')    AS lga,
           nullif(upper(trim(coalesce(geo_ward, ''))), '')    AS ward,
           nullif(upper(trim(coalesce(geo_pu,   ''))), '')    AS pu
      FROM public.profiles
     WHERE id = auth.uid()
  ),
  it AS (
    SELECT nullif(upper(trim(coalesce(p_alert.geo_lga,  ''))), '') AS lga,
           nullif(upper(trim(coalesce(p_alert.geo_ward, ''))), '') AS ward,
           nullif(upper(trim(coalesce(p_alert.geo_pu,   ''))), '') AS pu
  )
  SELECT CASE
    -- Unlocated incidents fail OPEN. See the note above: an emergency nobody
    -- can see is worse than one seen too widely.
    WHEN (SELECT lga FROM it) IS NULL THEN true

    -- No posting: no area. Kept deliberately weak, because geo_lga is
    -- self-writable and blank must never mean "everywhere".
    WHEN (SELECT lga FROM me) IS NULL THEN false

    WHEN (SELECT role FROM me) LIKE 'WARD%' THEN
      (SELECT lga FROM it) = (SELECT lga FROM me)
      AND (SELECT ward FROM me) IS NOT NULL
      AND (SELECT ward FROM it) = (SELECT ward FROM me)

    WHEN (SELECT role FROM me) LIKE 'UNIT%'
      OR (SELECT role FROM me) LIKE 'POLLING%' THEN
      (SELECT lga FROM it) = (SELECT lga FROM me)
      AND (SELECT pu FROM me) IS NOT NULL
      AND (SELECT pu FROM it) = (SELECT pu FROM me)

    -- LGA command, and field responders: the LGA.
    ELSE (SELECT lga FROM it) = (SELECT lga FROM me)
  END;
$$;

COMMENT ON FUNCTION public.alert_in_my_area(public.alerts) IS
  'Whether this incident falls inside the calling account''s posting. '
  'An unlocated incident is visible to all staff; an unposted account has no area.';

-- ── Was it handed to my LGA ─────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.alert_delegated_to_my_lga(p_alert public.alerts)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT COALESCE(
    nullif(upper(trim(coalesce(
      (p_alert.escalation_log -> jsonb_array_length(p_alert.escalation_log) - 1)
        ->> 'to_lga', ''))), '')
    = (SELECT nullif(upper(trim(coalesce(geo_lga, ''))), '')
         FROM public.profiles WHERE id = auth.uid()),
    false
  );
$$;

COMMENT ON FUNCTION public.alert_delegated_to_my_lga(public.alerts) IS
  'HQ hands an incident down by setting assigned_tier and naming a target LGA, '
  'without rewriting geo_lga — the location is a fact about the incident. '
  'Without this the delegation would reach only the named commander.';

-- ── The predicate both policies use ─────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.alert_is_ours(p_alert public.alerts)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
  SELECT
    -- HQ and administrators: the state.
    public.commands_whole_state()
    -- The reporter, the lead, and every officer on the dispatched team.
    OR p_alert.reported_by = auth.uid()
    OR p_alert.assigned_to = auth.uid()
    OR auth.uid()::text = ANY (COALESCE(p_alert.assigned_responders, '{}'::text[]))
    -- Operation Rainbow staff, within their command.
    OR (public.is_staff() AND NOT public.is_liaison()
        AND (public.alert_in_my_area(p_alert)
             OR public.alert_delegated_to_my_lga(p_alert)))
    -- An outside agency: only what was handed to them.
    OR (public.is_liaison()
        AND upper(COALESCE(p_alert.escalated_to_agency, '')) = public.liaison_agency());
$$;

COMMENT ON FUNCTION public.alert_is_ours(public.alerts) IS
  'Whether the calling account has a part in this incident: HQ sees the state, '
  'everyone else sees their command plus their own work.';

-- The policies already call alert_is_ours() for SELECT and UPDATE
-- (20261003000000_liaisons_are_not_staff.sql); replacing the function is what
-- narrows them. Restated here so a replica built from these files in order gets
-- the same result whichever migration ran last.

DROP POLICY IF EXISTS "alerts_select_own_or_staff" ON public.alerts;
DROP POLICY IF EXISTS "alerts_select_own_or_ours" ON public.alerts;

-- And the separate LGA-scoping policy from
-- 20260725000000_v6_geo_lga_scoping_staging.sql.
--
-- That one ADDS a permissive policy granting FIELD_OFFICER, WARD_OFFICER and
-- LGA_OFFICER every alert in their LGA. PostgreSQL ORs permissive policies
-- together, so leaving it beside this one means a WARD_OFFICER keeps the whole
-- LGA and the ward scoping below never binds for them — the same trap this
-- file's header describes, arriving from the other direction.
--
-- Nothing is lost by dropping it: `alert_in_my_area()` covers all three of
-- those roles and covers them more precisely. WARD_OFFICER matches 'WARD%' and
-- gets their ward; LGA_OFFICER and FIELD_OFFICER fall through to the LGA rule
-- and get exactly what that policy gave them.
DROP POLICY IF EXISTS "alerts_select_geo_lga_scoped" ON public.alerts;

DROP POLICY IF EXISTS "alerts_select_own_or_ours" ON public.alerts;
CREATE POLICY "alerts_select_own_or_ours" ON public.alerts
  FOR SELECT TO authenticated
  USING (public.alert_is_ours(alerts));

DROP POLICY IF EXISTS "alerts_update_own_or_staff" ON public.alerts;
DROP POLICY IF EXISTS "alerts_update_own_or_ours" ON public.alerts;
CREATE POLICY "alerts_update_own_or_ours" ON public.alerts
  FOR UPDATE TO authenticated
  USING (public.alert_is_ours(alerts));

-- The area test reads these on every row it considers.
CREATE INDEX IF NOT EXISTS alerts_geo_idx
  ON public.alerts (geo_lga, geo_ward, geo_pu);
