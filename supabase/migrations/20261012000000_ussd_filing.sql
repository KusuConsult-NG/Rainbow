-- Filing a report from a USSD session, exactly once.
--
-- ## Why the filing is here and not in the route
--
-- A USSD gateway that does not get a reply inside its window RE-POSTS the same
-- session with the same input. That is not an error condition, it is normal
-- operation on a congested network — which is precisely when people are
-- reporting emergencies. A route that files on every POST would raise the same
-- kidnapping two, three, four times, and a dispatcher would see four incidents
-- and have no way to tell them from four real reports.
--
-- Guarding that in the route means reading the session, deciding, then writing —
-- and two concurrent retries both read "not filed yet" and both file. The only
-- place that race can actually be closed is inside one statement holding the
-- session row's lock, which is here.
--
-- So `ussd_file_report()` is the whole transaction: lock the session, return the
-- report it already filed if there is one, otherwise write the alert and record
-- it against the session. A retry gets the SAME reference, which is also the
-- right answer for the caller — they are told again what they were told before,
-- instead of being handed a second reference for an incident that does not exist.
--
-- ## What is deliberately NOT here
--
-- Creating the caller's account. `profiles.id` references `auth.users`, and
-- `auth.users` is Supabase's table: its column set has changed across versions
-- and several columns are NOT NULL with no default depending on the release.
-- Hand-inserting into it from a migration is the kind of thing that works in
-- staging and fails on an upgrade, so the route uses the Admin API for that and
-- this file never touches it.

-- ── The reference a caller is read back ────────────────────────────────────

CREATE OR REPLACE FUNCTION public.ussd_reference()
RETURNS TEXT
LANGUAGE plpgsql
VOLATILE
SET search_path = public, pg_temp
AS $$
DECLARE
  -- No 0/O, 1/I/L, 5/S, 2/Z or 8/B. This reference is read off a feature-phone
  -- screen and then spoken down a phone line to a desk officer, so a character
  -- somebody can hear or see wrongly costs a real minute in an emergency.
  alphabet CONSTANT TEXT := '34679ACDEFGHJKMNPQRTUVWXY';
  candidate TEXT;
  attempt   INTEGER := 0;
BEGIN
  LOOP
    candidate := 'R';
    FOR i IN 1..5 LOOP
      candidate := candidate ||
        substr(alphabet, 1 + floor(random() * length(alphabet))::INTEGER, 1);
    END LOOP;
    -- 25^5 is about 9.7 million, and there is a unique index, so a collision is
    -- rare and cheap to walk away from. Bounded rather than looping for ever:
    -- a USSD session has seconds, and spinning here would time out the call.
    EXIT WHEN NOT EXISTS (
      SELECT 1 FROM public.alerts WHERE public_reference = candidate
    );
    attempt := attempt + 1;
    IF attempt >= 12 THEN
      -- Fall back to something guaranteed unique rather than failing the report.
      -- Uglier to read aloud, and infinitely better than losing an emergency.
      candidate := 'R' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 7));
      EXIT;
    END IF;
  END LOOP;
  RETURN candidate;
END $$;

COMMENT ON FUNCTION public.ussd_reference() IS
  'A short report reference with no visually or audibly confusable characters, '
  'because it is read off a feature phone and then spoken to a desk officer.';

-- ── Who is dialling ───────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.ussd_caller(p_msisdn TEXT)
RETURNS TABLE (user_id UUID, role TEXT, geo_lga TEXT, geo_ward TEXT, geo_pu TEXT)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
  -- Matched on the last nine digits, not on equality. The carrier may present
  -- 2348030001111, +2348030001111 or 08030001111 for the same SIM depending on
  -- the aggregator and the network, and a citizen who registered in the app
  -- typed whichever form they think of as their number. Comparing raw strings
  -- would hand a returning app user the stranger's path — six keypresses and no
  -- posting — while their profile sat right there.
  SELECT p.id, p.role, p.geo_lga, p.geo_ward, p.geo_pu
    FROM public.profiles p
   WHERE p.phone IS NOT NULL
     AND right(regexp_replace(p.phone, '\D', '', 'g'), 9)
       = right(regexp_replace(coalesce(p_msisdn, ''), '\D', '', 'g'), 9)
     AND length(regexp_replace(coalesce(p_msisdn, ''), '\D', '', 'g')) >= 9
   ORDER BY p.created_at
   LIMIT 1;
$$;

COMMENT ON FUNCTION public.ussd_caller(TEXT) IS
  'The profile behind a dialling MSISDN, matched on the last nine digits because '
  'carriers and app users write the same number several ways.';

REVOKE ALL ON FUNCTION public.ussd_caller(TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ussd_caller(TEXT) TO service_role;

-- ── Filing, exactly once per session ──────────────────────────────────────

CREATE OR REPLACE FUNCTION public.ussd_file_report(
  p_session_id TEXT,
  p_msisdn     TEXT,
  p_reporter   UUID,
  p_type       TEXT,
  p_emergency  BOOLEAN,
  p_lga        TEXT,
  p_ward       TEXT,
  p_callback   BOOLEAN
)
RETURNS TABLE (reference TEXT, alert_id UUID, already_filed BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_existing UUID;
  v_ref      TEXT;
  v_id       UUID;
BEGIN
  -- Lock the session first. Everything below depends on being the only writer
  -- for this dialogue, and two concurrent retries are the normal case this
  -- function exists for.
  SELECT s.filed_alert INTO v_existing
    FROM public.ussd_sessions s
   WHERE s.session_id = p_session_id
     FOR UPDATE;

  IF NOT FOUND THEN
    -- The route always opens the session before filing, so this is a caller
    -- bug rather than a user one. Refuse rather than inventing a session: an
    -- alert with no dialogue behind it cannot be deduplicated on a retry.
    RETURN;
  END IF;

  IF v_existing IS NOT NULL THEN
    -- A retry. Hand back what was already filed, so the caller is told the same
    -- reference again instead of a second one for an incident that never existed.
    RETURN QUERY
      SELECT a.public_reference, a.id, true
        FROM public.alerts a
       WHERE a.id = v_existing;
    RETURN;
  END IF;

  v_ref := public.ussd_reference();

  INSERT INTO public.alerts (
    -- No `priority`: that is not a column. The console DERIVES it when it maps a
    -- row (`priority: d.severity || 'UNKNOWN'` in dashboard/page.tsx), and
    -- writing it here was rejected outright by the first harness run.
    type, description, status, severity,
    reported_by, geo_lga, geo_ward,
    arrived_via, reporter_msisdn, caller_may_be_called, public_reference,
    assigned_tier, tier_assigned_at, created_at, updated_at
  ) VALUES (
    p_type,
    -- The description is the provenance. A dispatcher reading this row has to
    -- know, without clicking anything, that it came from a keypad and that
    -- nobody has stood behind it yet.
    '[USSD] Reported by keypad from ' || coalesce(p_msisdn, 'an unknown number')
      || '. Not yet confirmed by an officer.',
    'PENDING',
    -- The emergency branch is CRITICAL whatever else is true, exactly as the
    -- offline-channel ingest treats a duress alert. A person choosing "armed
    -- attack" on a menu is not grading their own incident.
    CASE WHEN p_emergency THEN 'CRITICAL' ELSE 'MEDIUM' END,
    p_reporter,
    nullif(trim(coalesce(p_lga, '')), ''),
    nullif(trim(coalesce(p_ward, '')), ''),
    'USSD',
    p_msisdn,
    coalesce(p_callback, false),
    v_ref,
    'UNIT',
    -- The clock starts, but awaiting_human_confirmation() holds it out of the
    -- ladder until an officer confirms it (20261011000000). Both are true at
    -- once on purpose: the age is real and visible, and the timer cannot act on
    -- it. Setting this to NULL instead would make the row look ageless on the
    -- board, which is its own kind of lie.
    NOW(), NOW(), NOW()
  )
  RETURNING id INTO v_id;

  UPDATE public.ussd_sessions
     SET filed_alert = v_id, updated_at = NOW()
   WHERE session_id = p_session_id;

  RETURN QUERY SELECT v_ref, v_id, false;
END $$;

COMMENT ON FUNCTION public.ussd_file_report(TEXT, TEXT, UUID, TEXT, BOOLEAN, TEXT, TEXT, BOOLEAN) IS
  'Files one report for one USSD session, holding the session row''s lock, so a '
  'gateway retry gets the SAME reference rather than raising the same emergency '
  'twice. Returns no row if the session was never opened.';

REVOKE ALL ON FUNCTION
  public.ussd_file_report(TEXT, TEXT, UUID, TEXT, BOOLEAN, TEXT, TEXT, BOOLEAN)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION
  public.ussd_file_report(TEXT, TEXT, UUID, TEXT, BOOLEAN, TEXT, TEXT, BOOLEAN)
  TO service_role;

-- ── The caller's own last report ──────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.ussd_last_report(p_msisdn TEXT)
RETURNS TABLE (reference TEXT, kind TEXT, status TEXT, age_minutes INTEGER)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
  -- Status only, and by column rather than by `select *`, so nobody can widen
  -- this later without noticing. Whoever holds the SIM can read this screen,
  -- and somebody who filed a report to draw officers to a place must not be
  -- able to watch them come: no assigned_to, no assigned_responders, no
  -- coordinates, no tier.
  SELECT a.public_reference,
         a.type,
         a.status,
         GREATEST(0, (EXTRACT(EPOCH FROM (NOW() - a.created_at)) / 60)::INTEGER)
    FROM public.alerts a
   WHERE a.reporter_msisdn IS NOT NULL
     AND right(regexp_replace(a.reporter_msisdn, '\D', '', 'g'), 9)
       = right(regexp_replace(coalesce(p_msisdn, ''), '\D', '', 'g'), 9)
     AND length(regexp_replace(coalesce(p_msisdn, ''), '\D', '', 'g')) >= 9
   -- `id` breaks the tie. Two reports from one number can share a created_at —
   -- `NOW()` is the transaction timestamp, and a double-dial or a burst arrives
   -- inside the same second — and ordering on created_at alone would then return
   -- an arbitrary one of them. A caller reading back "my last report" and being
   -- shown a different one each time they dial is worse than useless.
   ORDER BY a.created_at DESC, a.id DESC
   LIMIT 1;
$$;

COMMENT ON FUNCTION public.ussd_last_report(TEXT) IS
  'The status of a caller''s most recent report, for the USSD status screen. '
  'Named columns only: this screen is readable by anyone holding the SIM, so it '
  'must never carry a unit, a position or a tier.';

REVOKE ALL ON FUNCTION public.ussd_last_report(TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ussd_last_report(TEXT) TO service_role;

-- ── Forgetting the dialogue ───────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.sweep_ussd_sessions(p_older_than INTERVAL DEFAULT INTERVAL '2 hours')
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE n INTEGER;
BEGIN
  -- These rows hold the MSISDNs of people who reported, including anonymously.
  -- Keeping them after the dialogue has ended would turn a session store into a
  -- log of who dialled what, which is not a thing this system should own. The
  -- ALERT keeps what it needs; the dialogue does not need to outlive the call.
  DELETE FROM public.ussd_sessions
   WHERE updated_at < NOW() - p_older_than;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END $$;

COMMENT ON FUNCTION public.sweep_ussd_sessions(INTERVAL) IS
  'Deletes finished and abandoned USSD dialogues. The session store must not '
  'become a log of who dialled what — the alert keeps what is needed.';

REVOKE ALL ON FUNCTION public.sweep_ussd_sessions(INTERVAL) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.sweep_ussd_sessions(INTERVAL) TO service_role;
