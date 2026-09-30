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
-- 20261015000000_oversight_and_debrief.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261015000000_oversight_and_debrief.sql'; END $apply$;

-- A complaint about an officer must not be delivered to that officer.
--
-- ## Item 1: oversight routing
--
-- `alert_categories.dart` offers **Police brutality** as a reportable category,
-- with the subtypes Physical Assault, Extortion and Unlawful Arrest. A citizen
-- can file one from the app and, as of this migration's parent, over USSD.
--
-- It then routed exactly like a flood.
--
-- `alert_is_ours()` admits Operation Rainbow staff within their command, so a
-- complaint filed in Jos North reached Jos North ward command, Jos North LGA
-- command, and every RESPONDER posted to that LGA — which may include the
-- officer complained about. The responder picker offered them. The escalation
-- ladder climbed it rung by rung through the accused's own chain. And the
-- reporter's name and phone number travelled with it, because
-- `resolveReporterDetails()` puts them on the dossier.
--
-- So the system took a citizen's allegation that an officer assaulted them and
-- handed it to that officer's colleagues, with the complainant's number attached.
-- That is not a process defect. In Plateau State it is a safety problem for the
-- person who reported it.
--
-- ### The rule
--
-- An oversight matter is visible to HQ, to ADMIN, and to the person who reported
-- it. Nobody else — not the local ward, not the LGA, not a responder in the area,
-- and not an outside agency liaison, whose own personnel may be the subject.
--
-- It is also held out of the escalation ladder. Climbing UNIT → WARD → LGA is
-- precisely the wrong direction for this one kind of report: each rung is closer
-- to the accused. HQ owns it from the moment it arrives.
--
-- ### What this deliberately does NOT do
--
-- It does not hide the incident from the reporter, and it does not delete or
-- anonymise anything. The complaint is on the record, with the complainant's
-- details, available to HQ. Oversight requires knowing who complained; the
-- control is WHO can see it, not whether it exists.
--
-- ## Item 2: the debrief gets its own column
--
-- `mission_resolution_screen.dart` appended the responder's after-action notes
-- to `alerts.ai_summary`, tagged `[RESOLVED DEBRIEF]`. That column now carries
-- three unrelated kinds of content: AI triage notes, the
-- `[AI CLASSIFICATION APPLIED]` lines, and human debriefs. None of them can be
-- read back without string-parsing, and "what did the responder say happened"
-- is the one an inquiry asks.
--
-- A debrief is a person's account of what they did. It gets a column.

-- ── Which reports are oversight matters ────────────────────────────────────

CREATE OR REPLACE FUNCTION public.is_oversight_matter(p_type TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  -- Matched on the CATEGORY — the part of `type` before ' - ' — so every
  -- subtype is covered without listing them, and a new subtype added to
  -- alert_categories.dart is covered the day it ships rather than the day
  -- somebody remembers this function.
  SELECT upper(trim(split_part(coalesce(p_type, ''), ' - ', 1)))
         IN ('POLICE BRUTALITY', 'SECURITY PERSONNEL MISCONDUCT');
$$;

COMMENT ON FUNCTION public.is_oversight_matter(TEXT) IS
  'A complaint against security personnel. Matched on the category so new '
  'subtypes are covered automatically. These are routed to HQ only: every rung '
  'of the normal ladder is closer to the person complained about.';

-- ── Who may see one ───────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.alert_is_ours(p_alert public.alerts)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
  SELECT CASE
    -- A complaint about security personnel goes to HQ and the person who made
    -- it. Checked FIRST and exclusively: the clauses below would otherwise hand
    -- it to the accused's own command, which is the defect.
    WHEN public.is_oversight_matter(p_alert.type) THEN
      public.commands_whole_state()
      OR p_alert.reported_by = auth.uid()

    ELSE
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
          AND upper(COALESCE(p_alert.escalated_to_agency, '')) = public.liaison_agency())
  END;
$$;

COMMENT ON FUNCTION public.alert_is_ours(public.alerts) IS
  'Whether the calling account has a part in this incident: HQ sees the state, '
  'everyone else sees their command plus their own work — EXCEPT a complaint '
  'against security personnel, which only HQ and the complainant may see.';

-- ── And out of the escalation ladder ──────────────────────────────────────

CREATE OR REPLACE FUNCTION public.awaiting_human_confirmation(p_alert public.alerts)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT
    -- A USSD report nobody has stood behind. See 20261011000000.
    (upper(coalesce(p_alert.arrived_via, '')) = 'USSD'
     AND p_alert.ussd_confirmed_at IS NULL)
    -- OR an oversight matter, at any tier, for ever. The ladder's whole purpose
    -- is to escalate towards the local command, and for this one kind of report
    -- every rung is closer to the person complained about. HQ owns it on
    -- arrival; there is nowhere useful for it to climb to.
    OR public.is_oversight_matter(p_alert.type);
$$;

COMMENT ON FUNCTION public.awaiting_human_confirmation(public.alerts) IS
  'Held out of the escalation ladder: an unconfirmed USSD report, or a complaint '
  'against security personnel. For the latter every rung of the ladder is closer '
  'to the accused, so it does not climb at all.';

-- Route new oversight matters to HQ on arrival rather than leaving them at UNIT
-- looking unowned.
CREATE OR REPLACE FUNCTION public.route_oversight_to_hq()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF public.is_oversight_matter(NEW.type) THEN
    NEW.assigned_tier    := 'HQ';
    NEW.tier_assigned_at := NOW();
    -- Cleared, not preserved. A complaint must never arrive pre-assigned to a
    -- responder in the area it was filed in — which is what the app's own
    -- default would do if the report were raised from a responder's handset.
    NEW.assigned_to        := NULL;
    NEW.assigned_responders := NULL;
    NEW.escalation_log := coalesce(NEW.escalation_log, '[]'::jsonb) || jsonb_build_object(
      'at',     to_char(NOW() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
      'by',     'SYSTEM',
      'action', 'OVERSIGHT_ROUTED',
      'reason', 'a complaint against security personnel is routed to HQ, not to the local command'
    );
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS route_oversight_to_hq_trg ON public.alerts;
CREATE TRIGGER route_oversight_to_hq_trg
  BEFORE INSERT ON public.alerts
  FOR EACH ROW EXECUTE FUNCTION public.route_oversight_to_hq();

COMMENT ON FUNCTION public.route_oversight_to_hq() IS
  'BEFORE INSERT: sends a complaint against security personnel to HQ and clears '
  'any assignment, so it can never arrive pre-assigned to a responder in the '
  'area it was filed in.';

-- Existing rows: move any already in the local chain.
UPDATE public.alerts
   SET assigned_tier = 'HQ',
       assigned_to = NULL,
       assigned_responders = NULL
 WHERE public.is_oversight_matter(type)
   AND status NOT IN ('RESOLVED', 'CANCELLED', 'FALSE_REPORT')
   AND (upper(coalesce(assigned_tier, '')) <> 'HQ'
        OR assigned_to IS NOT NULL
        OR assigned_responders IS NOT NULL);

CREATE INDEX IF NOT EXISTS alerts_oversight_idx
  ON public.alerts (created_at DESC)
  WHERE category IN ('Police brutality', 'Security personnel misconduct');

-- ── Item 2: the debrief ───────────────────────────────────────────────────

ALTER TABLE public.alerts
  ADD COLUMN IF NOT EXISTS debrief TEXT,
  ADD COLUMN IF NOT EXISTS debrief_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS debrief_at TIMESTAMPTZ;

COMMENT ON COLUMN public.alerts.debrief IS
  'The responder''s own account of what they did, in their words. Was appended '
  'to ai_summary tagged [RESOLVED DEBRIEF], mixed in with AI triage notes and '
  'classification lines — so "what did the responder say happened", the question '
  'an inquiry asks, needed string-parsing to answer.';

-- Backfill from the tag. Safe because `[RESOLVED DEBRIEF] ` is unambiguous and
-- was written by exactly one place; anything else in ai_summary is left alone.
UPDATE public.alerts a
   SET debrief = btrim(substring(line FROM '\[RESOLVED DEBRIEF\] (.*)$'))
  FROM (
    SELECT id, unnest(string_to_array(ai_summary, E'\n')) AS line
      FROM public.alerts
     WHERE ai_summary LIKE '%[RESOLVED DEBRIEF]%'
  ) src
 WHERE a.id = src.id
   AND src.line LIKE '[RESOLVED DEBRIEF]%'
   AND a.debrief IS NULL;

CREATE INDEX IF NOT EXISTS alerts_debriefed_idx
  ON public.alerts (debrief_at DESC)
  WHERE debrief IS NOT NULL;

-- ── Item 3: a real audit trail ────────────────────────────────────────────
--
-- The console's "System Tactical Audit History" read `chat_messages` — the
-- private conversations between dispatchers and responders. It showed no action
-- anybody had taken: not a dispatch, not an escalation, not a resolution, not a
-- classification applied, not a report marked false.
--
-- Those are all in `alerts.escalation_log`, a jsonb array appended to by every
-- action in the system. PR #2 suggested reading `alert_timeline` instead, and
-- that table does not exist in any migration — so the suggested fix would have
-- produced an empty screen.
--
-- SECURITY INVOKER, so `alert_is_ours()` scopes it. That matters more here than
-- anywhere: without it this function would hand every authenticated account the
-- action history of every incident in Plateau, including the oversight matters
-- the rest of this migration exists to protect.

CREATE OR REPLACE FUNCTION public.audit_trail(p_limit INTEGER DEFAULT 100)
RETURNS TABLE (
  alert_id   UUID,
  reference  TEXT,
  incident   TEXT,
  at         TIMESTAMPTZ,
  action     TEXT,
  actor      TEXT,
  detail     TEXT
)
LANGUAGE sql
SECURITY INVOKER
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT a.id,
         coalesce(a.public_reference, left(a.id::text, 8)),
         a.type,
         -- Entries have been written with two different key names over this
         -- schema's life ('at' as a formatted string, and an ISO timestamp), and
         -- a row whose timestamp cannot be parsed must still appear — an audit
         -- entry dropped for a formatting reason is the worst possible thing for
         -- this list to do quietly. Falls back to the incident's own time.
         coalesce(
           nullif(e.entry ->> 'at', '')::timestamptz,
           a.updated_at,
           a.created_at
         ),
         upper(coalesce(
           nullif(e.entry ->> 'action', ''),
           -- A tier move has no 'action' key; it is identified by carrying a
           -- from_tier. Without this, every automatic escalation in the system
           -- would read as 'UNKNOWN'.
           CASE WHEN e.entry ? 'from_tier' THEN 'ESCALATED' END,
           'UPDATED'
         )),
         coalesce(nullif(e.entry ->> 'by', ''), 'SYSTEM'),
         -- For a tier move, BOTH the tiers and the reason. The first version
         -- coalesced the reason first, so an automatic escalation read simply
         -- "TIMEOUT" — the word without the movement, which is the half that
         -- tells a reader nothing. Where an incident WENT is the point of the
         -- entry; why is the qualifier.
         CASE
           WHEN e.entry ? 'from_tier' THEN
             (e.entry ->> 'from_tier') || ' → ' || (e.entry ->> 'to_tier')
             || coalesce(' (' || nullif(e.entry ->> 'reason', '') || ')', '')
           ELSE coalesce(nullif(e.entry ->> 'reason', ''), '')
         END
    FROM public.alerts a
    CROSS JOIN LATERAL jsonb_array_elements(
           CASE WHEN jsonb_typeof(a.escalation_log) = 'array'
                THEN a.escalation_log ELSE '[]'::jsonb END
         ) AS e(entry)
   ORDER BY 4 DESC
   LIMIT greatest(1, least(coalesce(p_limit, 100), 500));
$$;

COMMENT ON FUNCTION public.audit_trail(INTEGER) IS
  'What was actually DONE to incidents, flattened out of alerts.escalation_log. '
  'The console previously showed chat_messages under this heading, which '
  'contained no action anybody had taken. SECURITY INVOKER so alert_is_ours() '
  'scopes it — including keeping oversight matters out of it.';

REVOKE ALL ON FUNCTION public.audit_trail(INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.audit_trail(INTEGER) TO authenticated, service_role;

