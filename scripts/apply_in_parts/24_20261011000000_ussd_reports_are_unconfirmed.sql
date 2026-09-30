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
-- 20261011000000_ussd_reports_are_unconfirmed.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261011000000_ussd_reports_are_unconfirmed.sql'; END $apply$;

-- A stranger's keystrokes must not become armed officers at a chosen place.
--
-- ## The threat this is about
--
-- USSD is the right channel for a citizen with no data, no smartphone and no
-- credit — in Plateau State that is most of the people this system protects. It
-- is also the cheapest possible way to lure responders into an ambush: no
-- install, no data, a ₦100 SIM, and the report is indistinguishable from a real
-- one. Security personnel in this state have been attacked after being drawn to
-- a location. This is not a theoretical risk being written up for completeness.
--
-- Two mitigations are theatre and are not implemented as if they were defences:
-- rate-limiting per number, and requiring registration. Both cost one more SIM
-- to defeat, and USSD self-registration is instant BY DESIGN — the carrier
-- asserts the MSISDN, so there is nothing to verify and nothing to slow down.
-- That openness is the point of the channel and is worth its cost; pretending a
-- rate limit closes the hole would be worse than leaving it open knowingly.
--
-- What this migration does instead is remove the AUTOMATIC path from a keypress
-- to a deployment, and give the officer who decides the provenance to decide on.
--
-- ## 1. A USSD report does not climb the ladder on its own
--
-- `escalate_overdue_alerts()` moves any unacknowledged alert up a tier on a
-- timer: UNIT after its window, then WARD, then LGA, then HQ. Every new row
-- defaults to `assigned_tier = 'UNIT'`, so a fake USSD report would page a
-- ward commander, then an LGA commander, then Command HQ, with no human having
-- ever judged whether it is real. The timers do the attacker's work.
--
-- So an unconfirmed USSD report is held out of the ladder. It is NOT hidden and
-- NOT quiet: it is on the board, it is counted, and the console shows it with
-- its provenance. What it does not do is manufacture urgency by itself.
--
-- The moment a human confirms it — `confirm_ussd_report()` — it joins the ladder
-- with a fresh clock and behaves exactly like any other incident.
--
-- ## 2. A false report becomes recordable
--
-- There was no way to say a report was a lie. `status` had RESOLVED and
-- CANCELLED, and CANCELLED is what a reporter does when they stand themselves
-- down. With no distinct outcome, no signal could ever accumulate against a
-- number, which means every other credibility measure was guesswork dressed up.
-- FALSE_REPORT is that outcome, and it is deliberately an ACTION BY AN OFFICER,
-- recorded with who said so.
--
-- ## 3. Corroboration, not a severity badge
--
-- One report of an armed attack from a number never seen before is a different
-- thing from four reports from four numbers on three carriers in the same ward
-- within twenty minutes. `ussd_report_credibility()` gives a dispatcher both
-- figures rather than a score, because a single number invites the reader to
-- stop thinking, and the shape of the corroboration is the part that matters.

-- ── Where it came from, and whether anybody has stood behind it ──────────────

ALTER TABLE public.alerts
  ADD COLUMN IF NOT EXISTS reporter_msisdn TEXT,
  ADD COLUMN IF NOT EXISTS caller_may_be_called BOOLEAN,
  ADD COLUMN IF NOT EXISTS ussd_confirmed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS ussd_confirmed_by UUID REFERENCES public.profiles(id),
  ADD COLUMN IF NOT EXISTS public_reference TEXT;

COMMENT ON COLUMN public.alerts.reporter_msisdn IS
  'The number the CARRIER asserted for a USSD session. Stronger evidence than '
  'the app''s SMS OTP — it cannot be typed, mistyped or phished — but it '
  'identifies a SIM, never a person.';

COMMENT ON COLUMN public.alerts.caller_may_be_called IS
  'Whether the USSD reporter agreed to be rung back. The ANSWER is a signal in '
  'itself; refusing never blocked the report, because a witness to an attack '
  'has good reasons not to want their phone ringing.';

COMMENT ON COLUMN public.alerts.ussd_confirmed_at IS
  'When a named officer stood behind this report. Until then it is out of the '
  'escalation ladder: no timer may turn a stranger''s keypresses into a '
  'deployment.';

COMMENT ON COLUMN public.alerts.public_reference IS
  'The short reference read back to a USSD caller. The only handle a person '
  'with no smartphone has on their own report.';

-- Looking a caller's own history up, and the corroboration window, both read
-- this constantly.
CREATE INDEX IF NOT EXISTS alerts_reporter_msisdn_idx
  ON public.alerts (reporter_msisdn, created_at DESC)
  WHERE reporter_msisdn IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS alerts_public_reference_idx
  ON public.alerts (public_reference)
  WHERE public_reference IS NOT NULL;

-- ── Holding an unconfirmed report out of the ladder ─────────────────────────
--
-- Expressed as a predicate rather than inlined, so the escalation job and the
-- console cannot drift about what "unconfirmed" means.

CREATE OR REPLACE FUNCTION public.awaiting_human_confirmation(p_alert public.alerts)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT upper(coalesce(p_alert.arrived_via, '')) = 'USSD'
     AND p_alert.ussd_confirmed_at IS NULL;
$$;

COMMENT ON FUNCTION public.awaiting_human_confirmation(public.alerts) IS
  'A USSD report nobody has stood behind yet. On the board and counted, but '
  'out of the escalation ladder, so no timer can manufacture urgency for a '
  'report that may have been filed to draw officers somewhere.';

-- Copied VERBATIM from 20261007000000_notification_outbox.sql with ONE line
-- added, and copied rather than rewritten on purpose. The first version of this
-- migration restated the function "in full for readability" and silently
-- dropped four things: status = 'ESCALATED', updated_at, the escalation_log key
-- names the console and drain-outbox read (from_tier/to_tier, not from/to), and
-- the 'reason':'TIMEOUT' in the outbox payload. A CREATE OR REPLACE that looks
-- like a tidy-up is how a working mechanism gets reverted by a migration about
-- something else.

CREATE OR REPLACE FUNCTION public.escalate_overdue_alerts()
RETURNS TABLE (alert_id UUID, from_tier TEXT, to_tier TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN QUERY
  WITH overdue AS (
    SELECT a.id,
           upper(a.assigned_tier)            AS current_tier,
           public.next_tier(a.assigned_tier) AS target_tier
      FROM public.alerts a
     WHERE a.status NOT IN ('RESOLVED', 'CANCELLED')
       -- Acknowledged means somebody at this tier has it. Climbing past a
       -- responder who is already on it is how you get two units dispatched
       -- to the same incident and none to the next one.
       AND a.acknowledged_at IS NULL
       -- A report filed over USSD that no officer has stood behind. The timers
       -- must not turn a stranger's keypresses into a deployment; see
       -- awaiting_human_confirmation() above.
       AND NOT public.awaiting_human_confirmation(a)
       AND public.next_tier(a.assigned_tier) IS NOT NULL
       AND a.tier_assigned_at IS NOT NULL
       AND a.tier_assigned_at <
             NOW() - make_interval(
               mins => public.tier_timeout_minutes(a.assigned_tier)
             )
     FOR UPDATE OF a SKIP LOCKED
  ),
  moved AS (
    UPDATE public.alerts a
       SET assigned_tier    = o.target_tier,
           tier_assigned_at = NOW(),
           status           = 'ESCALATED',
           updated_at       = NOW(),
           escalation_log = COALESCE(a.escalation_log, '[]'::jsonb) || jsonb_build_object(
             'from_tier',  o.current_tier,
             'to_tier',    o.target_tier,
             'reason',     'TIMEOUT',
             'by',         'SYSTEM',
             'at',         to_char(NOW() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
           )
      FROM overdue o
     WHERE a.id = o.id
    RETURNING a.id, o.current_tier, o.target_tier, a.geo_lga, a.geo_ward, a.geo_pu, a.severity
  ),
  queued AS (
    INSERT INTO public.notification_outbox (alert_id, kind, payload)
    SELECT m.id,
           'TIER_ESCALATION',
           jsonb_build_object(
             'alert_id',  m.id,
             'from_tier', m.current_tier,
             'to_tier',   m.target_tier,
             'geo_lga',   m.geo_lga,
             'geo_ward',  m.geo_ward,
             'geo_pu',    m.geo_pu,
             'severity',  m.severity,
             'reason',    'TIMEOUT'
           )
      FROM moved m
    -- `RETURNING alert_id` collides with this function's own OUT parameter of
    -- that name and is rejected as ambiguous. Nothing reads this CTE's output;
    -- it exists so the INSERT runs inside the same statement as the UPDATE.
    RETURNING id
  )
  SELECT m.id, m.current_tier, m.target_tier FROM moved m;
END;
$$;

-- ── An officer standing behind a report ────────────────────────────────────

CREATE OR REPLACE FUNCTION public.confirm_ussd_report(p_alert_id UUID)
RETURNS TABLE (confirmed BOOLEAN, tier TEXT)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tier TEXT;
BEGIN
  -- SECURITY INVOKER: alerts_update_own_or_ours already decides who may act on
  -- an incident, and that is exactly the right rule here. A definer function
  -- would let any account with a token confirm a report anywhere in Plateau —
  -- which is the whole control, handed away.
  UPDATE public.alerts a
     SET ussd_confirmed_at = NOW(),
         ussd_confirmed_by = auth.uid(),
         -- A fresh clock. Inheriting the age it accumulated while unconfirmed
         -- would make it overdue the instant it was confirmed and climb several
         -- tiers in one pass of the job — the cascade
         -- 20260928000000 already had to fix once for hand escalations.
         tier_assigned_at  = NOW(),
         escalation_log    = coalesce(a.escalation_log, '[]'::jsonb) || jsonb_build_object(
           'at',     NOW(),
           'by',     auth.uid(),
           'action', 'CONFIRMED',
           'reason', 'a named officer stood behind a USSD report'
         )
   WHERE a.id = p_alert_id
     AND upper(coalesce(a.arrived_via, '')) = 'USSD'
     AND a.ussd_confirmed_at IS NULL
  RETURNING a.assigned_tier INTO v_tier;

  IF v_tier IS NULL THEN
    -- Not ours, not USSD, already confirmed, or gone. No row, so a caller
    -- cannot read a refusal as a confirmation.
    RETURN;
  END IF;
  RETURN QUERY SELECT true, v_tier;
END $$;

COMMENT ON FUNCTION public.confirm_ussd_report(UUID) IS
  'A named officer stands behind a USSD report, which joins the escalation '
  'ladder with a fresh clock. Returns no row if the caller may not act on that '
  'incident, so a refusal can never read as a confirmation.';

REVOKE ALL ON FUNCTION public.confirm_ussd_report(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.confirm_ussd_report(UUID) TO authenticated, service_role;

-- ── Recording that a report was a lie ──────────────────────────────────────

CREATE OR REPLACE FUNCTION public.mark_false_report(p_alert_id UUID, p_note TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE v_id UUID;
BEGIN
  -- FALSE_REPORT, not CANCELLED. CANCELLED is what a reporter does when they
  -- stand themselves down and carries no accusation. This is an officer saying
  -- the report was untrue, and it is the ONLY thing that can ever make a
  -- number's history mean anything — without it, every credibility measure in
  -- this file would be guesswork dressed up as evidence.
  UPDATE public.alerts a
     SET status         = 'FALSE_REPORT',
         resolved_at    = NOW(),
         escalation_log = coalesce(a.escalation_log, '[]'::jsonb) || jsonb_build_object(
           'at',     NOW(),
           'by',     auth.uid(),
           'action', 'FALSE_REPORT',
           'reason', coalesce(nullif(trim(p_note), ''), 'marked false by an officer')
         )
   WHERE a.id = p_alert_id
  RETURNING a.id INTO v_id;
  RETURN v_id IS NOT NULL;
END $$;

COMMENT ON FUNCTION public.mark_false_report(UUID, TEXT) IS
  'An officer records that a report was untrue. Distinct from CANCELLED, which '
  'is a reporter standing themselves down. This is the only source of the '
  'history that makes a number''s credibility a fact rather than a guess.';

REVOKE ALL ON FUNCTION public.mark_false_report(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_false_report(UUID, TEXT) TO authenticated, service_role;

-- ── What a dispatcher should know before sending anybody ────────────────────

CREATE OR REPLACE FUNCTION public.ussd_report_credibility(p_alert_id UUID)
RETURNS TABLE (
  first_time_caller     BOOLEAN,
  caller_report_count   INTEGER,
  caller_false_reports  INTEGER,
  caller_known_days     INTEGER,
  callback_offered      BOOLEAN,
  corroborating_reports INTEGER,
  corroborating_numbers INTEGER
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
  WITH it AS (
    SELECT a.id, a.reporter_msisdn, a.created_at, a.category,
           public.geo_key(a.geo_lga)  AS lga,
           public.geo_key(a.geo_ward) AS ward,
           a.caller_may_be_called
      FROM public.alerts a
     WHERE a.id = p_alert_id
  ),
  history AS (
    SELECT count(*)::INTEGER AS n,
           count(*) FILTER (WHERE upper(coalesce(h.status, '')) = 'FALSE_REPORT')::INTEGER
             AS false_n,
           min(h.created_at) AS first_seen
      FROM public.alerts h, it
     WHERE h.reporter_msisdn IS NOT NULL
       AND h.reporter_msisdn = it.reporter_msisdn
       AND h.id <> it.id
  ),
  -- Independent reports of what may be the same event: the same ward, the same
  -- category, inside a window, from OTHER numbers. Counted two ways on purpose
  -- — four reports from one number is one person pressing keys, and four from
  -- four numbers is a village.
  nearby AS (
    SELECT count(*)::INTEGER AS n,
           count(DISTINCT coalesce(c.reporter_msisdn, c.id::text))::INTEGER AS numbers
      FROM public.alerts c, it
     WHERE c.id <> it.id
       AND c.created_at BETWEEN it.created_at - INTERVAL '45 minutes'
                           AND it.created_at + INTERVAL '45 minutes'
       AND c.category IS NOT DISTINCT FROM it.category
       AND it.lga IS NOT NULL
       AND public.geo_key(c.geo_lga) = it.lga
       AND (it.ward IS NULL OR public.geo_key(c.geo_ward) = it.ward)
       AND coalesce(c.reporter_msisdn, '') <> coalesce(it.reporter_msisdn, '')
  )
  SELECT (history.n = 0),
         history.n,
         history.false_n,
         CASE WHEN history.first_seen IS NULL THEN 0
              ELSE GREATEST(0, (EXTRACT(EPOCH FROM (NOW() - history.first_seen)) / 86400)::INTEGER)
         END,
         coalesce(it.caller_may_be_called, false),
         nearby.n,
         nearby.numbers
    FROM it, history, nearby;
$$;

COMMENT ON FUNCTION public.ussd_report_credibility(UUID) IS
  'What a dispatcher should know before committing officers on the word of a '
  'phone number: is this the first time it has ever been heard from, what has '
  'it reported before, has anything it filed been marked false, did it agree '
  'to a callback, and is anybody else saying the same thing. Figures, not a '
  'score — a single number invites the reader to stop thinking, and the shape '
  'of the corroboration is the part that matters.';

REVOKE ALL ON FUNCTION public.ussd_report_credibility(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ussd_report_credibility(UUID) TO authenticated, service_role;

-- ── The USSD session store ─────────────────────────────────────────────────
--
-- USSD is stateless HTTP per screen. Some aggregators hand over the whole
-- `*`-joined input path and some only the latest keypress, so the state has to
-- live here regardless — and it has to live here anyway for idempotency,
-- because a gateway that times out RE-POSTS the same session and the same input
-- and must not produce a second alert.

CREATE TABLE IF NOT EXISTS public.ussd_sessions (
  session_id   TEXT PRIMARY KEY,
  msisdn       TEXT NOT NULL,
  state        JSONB NOT NULL DEFAULT '{}'::jsonb,
  -- The last screen sent. A retry is answered from here rather than re-running
  -- the reducer, which is what makes a repeat POST harmless.
  last_screen  TEXT,
  last_input   TEXT,
  -- Set once a report has been filed in this session, so a retry of the final
  -- keypress returns the same reference instead of filing a second emergency.
  filed_alert  UUID REFERENCES public.alerts(id) ON DELETE SET NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.ussd_sessions IS
  'One row per USSD dialogue. Holds the menu state between screens, and the '
  'alert already filed, so a gateway retry cannot raise the same emergency '
  'twice.';

CREATE INDEX IF NOT EXISTS ussd_sessions_stale_idx
  ON public.ussd_sessions (updated_at);

-- Nobody signed in from a phone or a browser may read these: they contain the
-- MSISDNs of people who reported anonymously, and the whole point of an
-- anonymous report is that the reporter is not in a table anyone can query.
ALTER TABLE public.ussd_sessions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.ussd_sessions FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.ussd_sessions TO service_role;

COMMENT ON INDEX public.ussd_sessions_stale_idx IS
  'Sessions are short-lived; this supports the sweep that deletes finished and '
  'abandoned dialogues rather than keeping a log of who dialled what.';

