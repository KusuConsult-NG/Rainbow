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
-- 20261024000000_a_voice_note_and_a_report_that_is_not_an_emergency.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261024000000_a_voice_note_and_a_report_that_is_not_an_emergency.sql'; END $apply$;

-- ============================================================================
-- OPERATION RAINBOW — A VOICE NOTE, AND A REPORT THAT IS NOT AN EMERGENCY
--
-- Two things an operator asked for, and they meet in the same place: a report
-- from somebody who cannot type, about something that is not an emergency.
--
-- ## 1. THE REPORTER'S OWN VOICE
--
-- The app can already record. `report_details_screen.dart` holds an
-- `AudioRecorder`, writes an `.m4a` to the temporary directory, and uploads it
-- with the photographs — so the audio reaches Cloudinary and lands in
-- `media_urls` beside them.
--
-- Which is the problem. `media_urls` is EVIDENCE: the photograph of the
-- vehicle, the video of the roadblock. The reporter's own voice, left because
-- they could not type, is not one of several attachments — it is the report.
-- Nothing downstream could tell the difference:
--
--   * a responder's incident card said "3 attachments" and an operator had to
--     open each to find out that one of them was somebody speaking;
--   * the console's dossier rendered it as a 72px thumbnail with a musical
--     note on it, among the photographs;
--   * and the one path built for a person who cannot type — the AI voice
--     dialog — runs speech-to-text and files the TRANSCRIPT. The audio is
--     discarded. So if the recogniser mangles Hausa, or there is no network to
--     reach it, what the person actually said is gone. For a report that
--     exists BECAUSE they could not type, that is the whole content.
--
-- `voice_note_url` is therefore its own column: one per report, the reporter
-- speaking. `voice_note_seconds` is beside it because a responder on a metered
-- or weak connection needs to know whether they are about to pull eight
-- seconds or two minutes before they press play.
--
-- ## 2. A REPORT THAT MUST NOT WAKE ANYBODY
--
-- The second ask is a general report: government property mismanaged,
-- vandalised, abandoned, unsafe, in need of repair. A street light is not a
-- kidnapping, and this system is built to treat everything as a kidnapping:
--
--   * `queue_new_incident_notice()` (20261022000000) announces every INSERT to
--     the tier it landed at, and the drain widens a UNIT notice to the field
--     responders — the people who physically go. A broken culvert filed at
--     02:00 would push to their handsets.
--   * `escalate_overdue_alerts()` climbs anything unacknowledged one rung per
--     timeout. Nobody acknowledges a street light at 02:00, so by morning it
--     would be an HQ-tier incident with three escalations against it, sitting
--     among the night's actual emergencies.
--
-- Both are right for an emergency and wrong for this. The mechanism for
-- "handle this differently" already exists twice — `is_oversight_matter()`
-- routes a complaint about an officer to HQ, and `awaiting_human_confirmation()`
-- holds an unconfirmed keypad report out of the ladder — and this is the same
-- shape, so it is built the same way rather than a third way:
--
--   * `is_non_emergency(type)` matches on the CATEGORY, the part of `type`
--     before ' - ', so every subtype is covered and a new one added to the app
--     needs no migration;
--   * a BEFORE INSERT trigger lands it at the LGA — the local authority whose
--     property it is — and not at the polling unit, so the notice goes to a
--     desk rather than to a patrol's pocket;
--   * `escalate_overdue_alerts()` leaves it alone. It waits for somebody to
--     look at it, which is what it is for.
--
-- WHAT THIS DELIBERATELY DOES NOT DO: hide it. The report is a normal row on
-- the board, in the feed, on the map, with its own category — an operator can
-- see it, filter to it and act on it. "Not an emergency" means not paged and
-- not climbed; it does not mean not seen. Something nobody is shown is
-- something nobody fixes, which is how a thing ends up abandoned.
-- ============================================================================

BEGIN;

-- ── 1. the reporter's voice ────────────────────────────────────────────────
ALTER TABLE public.alerts
  ADD COLUMN IF NOT EXISTS voice_note_url     TEXT,
  ADD COLUMN IF NOT EXISTS voice_note_seconds INTEGER;

COMMENT ON COLUMN public.alerts.voice_note_url IS
  'The reporter speaking, when they could not or did not type. Its own column '
  'and not one of media_urls: that list is evidence — photographs, video — and '
  'a voice note is the report itself. One per report; a second recording '
  'replaces it.';

COMMENT ON COLUMN public.alerts.voice_note_seconds IS
  'How long the voice note runs. A responder on a metered or weak connection '
  'is told what they are about to pull before they press play.';

-- A negative or absurd duration is a bug in whatever wrote it, and a column
-- that accepts one makes the screen that renders it lie.
ALTER TABLE public.alerts
  DROP CONSTRAINT IF EXISTS alerts_voice_note_seconds_sane;
ALTER TABLE public.alerts
  ADD CONSTRAINT alerts_voice_note_seconds_sane
  CHECK (voice_note_seconds IS NULL
         OR (voice_note_seconds > 0 AND voice_note_seconds <= 600));

-- ── 2. which categories are not emergencies ───────────────────────────────
--
-- One name, matched on the category exactly as `is_oversight_matter()` does.
-- The labels are the app's, from lib/core/constants/alert_categories.dart;
-- `scripts/check_non_emergency_categories_agree.py` fails if the two lists
-- drift, because a category the app can file and the database does not know
-- about would be paged out to responders at 02:00.
CREATE OR REPLACE FUNCTION public.is_non_emergency(p_type TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
  SELECT upper(trim(split_part(coalesce(p_type, ''), ' - ', 1)))
         IN ('PUBLIC PROPERTY', 'PUBLIC SERVICE');
$$;

COMMENT ON FUNCTION public.is_non_emergency(TEXT) IS
  'A report about government property or a public service: mismanaged, '
  'vandalised, abandoned, unsafe, needing repair. Matched on the category — '
  'the part of type before " - " — so every subtype is covered. These are '
  'filed at the LGA and never climb the escalation ladder: a street light does '
  'not page a patrol at 02:00 and must not be an HQ-tier incident by morning. '
  'They are still on the board, in the feed and on the map.';

-- ── 3. land it at the local authority, not in a patrol's pocket ───────────
CREATE OR REPLACE FUNCTION public.route_non_emergency_to_lga()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- An oversight matter has already been sent to HQ by its own trigger, and
  -- that decision wins: a complaint about an officer is not a street light,
  -- whatever else it is. Checked rather than assumed, because trigger order is
  -- alphabetical by name and that is a thin thread to hang a routing rule on.
  IF public.is_non_emergency(NEW.type)
     AND NOT public.is_oversight_matter(NEW.type) THEN
    NEW.assigned_tier    := 'LGA';
    NEW.tier_assigned_at := NOW();
    -- Not pre-assigned to a responder. The app's own default would hand it to
    -- whoever is posted where it was filed, which for a culvert means an
    -- officer gets a dispatch for something no officer can fix.
    NEW.assigned_to         := NULL;
    NEW.assigned_responders := NULL;
    NEW.escalation_log := coalesce(NEW.escalation_log, '[]'::jsonb) || jsonb_build_object(
      'at',     to_char(NOW() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
      'by',     'SYSTEM',
      'action', 'NON_EMERGENCY_ROUTED',
      'reason', 'a report about public property is filed at the LGA and does not climb'
    );
  END IF;
  RETURN NEW;
END $$;

COMMENT ON FUNCTION public.route_non_emergency_to_lga() IS
  'BEFORE INSERT: files a report about government property at the LGA, clears '
  'any responder assignment, and records why. Defers to the oversight router: '
  'a complaint against security personnel goes to HQ even if it also mentions '
  'property.';

-- `z_` so it sorts AFTER route_oversight_to_hq_trg: PostgreSQL fires BEFORE
-- triggers in alphabetical order by name, and this one must see whatever the
-- oversight router decided rather than race it. The guard above makes the
-- order not matter; the name makes it not matter twice.
DROP TRIGGER IF EXISTS z_route_non_emergency_to_lga_trg ON public.alerts;
CREATE TRIGGER z_route_non_emergency_to_lga_trg
  BEFORE INSERT ON public.alerts
  FOR EACH ROW EXECUTE FUNCTION public.route_non_emergency_to_lga();

-- ── 4. the ladder leaves it alone ─────────────────────────────────────────
--
-- RESTATED IN FULL from 20261011000000_ussd_reports_are_unconfirmed.sql, which
-- is the latest generation, with ONE line added. Restating a function from the
-- wrong generation is how `alert_is_ours()` lost its oversight branch in this
-- repository — every Dart and console test still passed and only a SQL
-- behaviour test on a real PostgreSQL caught it. Everything below except the
-- marked line is that file's text.
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
       -- THE ONE NEW LINE. A street light does not become an HQ-tier incident
       -- because nobody looked at it overnight.
       AND NOT public.is_non_emergency(a.type)
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

COMMENT ON FUNCTION public.escalate_overdue_alerts() IS
  'The timeout sweep. Climbs an unacknowledged incident one rung when its tier '
  'has held it too long, and queues a TIER_ESCALATION notice. Skips an '
  'unconfirmed keypad report (awaiting_human_confirmation) and a report about '
  'public property (is_non_emergency), neither of which should be moved by a '
  'clock.';

COMMIT;

