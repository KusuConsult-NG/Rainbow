-- The nearest landmark, typed by somebody who has no GPS.
--
-- ## Why this is worth a column
--
-- A USSD report cannot carry coordinates. USSD rides the signalling channel with
-- no access to the handset's location, so the best the console can draw is a
-- circle the size of the ward the caller chose — 800m across in Jos North, 16km
-- in parts of Wase. That circle tells a commander which unit owns the incident.
-- It does not tell a driver where to go.
--
-- A landmark does. The polling units in the tactical map are real findable places
-- — POLICE BARRACKS, PRIM. SCHOOL DAFFO, DISPENSARY GORO, NEW MARKET SCHOOL LANE
-- — and so are the ones a caller types from their own knowledge. "Behind the
-- mosque on the Bokkos road" is worth more to a responder than a 3km circle, and
-- no list could have contained it.
--
-- It is asked AFTER the report is filed, never before. The emergency is already
-- recorded and HQ can already see it; this arrives seconds later. Asking first
-- would put another screen between a person under attack and the report landing,
-- and if the session then dropped they would have neither.
--
-- ## What it is NOT
--
-- It is not a location. It does not change `locateIncident()`'s precision, and it
-- must never be parsed into coordinates — there are no polling-unit coordinates
-- in this system, and deriving a point from a string would be the fabricated-fix
-- defect again wearing a different hat. It is text, written by a person, for a
-- person to read.

ALTER TABLE public.alerts
  ADD COLUMN IF NOT EXISTS reporter_landmark TEXT;

COMMENT ON COLUMN public.alerts.reporter_landmark IS
  'The nearest landmark as the reporter typed it, for a responder to read. NOT a '
  'location: it never becomes coordinates, because deriving a point from a '
  'string is the fabricated-fix defect wearing a different hat.';

-- ── Attaching one to the report this session already filed ─────────────────

CREATE OR REPLACE FUNCTION public.ussd_add_landmark(
  p_session_id TEXT,
  p_landmark   TEXT
)
RETURNS TABLE (reference TEXT, alert_id UUID)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_alert UUID;
  v_text  TEXT;
BEGIN
  v_text := nullif(btrim(coalesce(p_landmark, '')), '');
  IF v_text IS NULL THEN RETURN; END IF;

  -- Only ever the report THIS session filed. Taking an alert id from the caller
  -- would let anybody with the endpoint write a landmark onto any incident in
  -- Plateau — a way to redirect a response by typing, which is the same class of
  -- problem as the ambush this channel is already careful about.
  SELECT s.filed_alert INTO v_alert
    FROM public.ussd_sessions s
   WHERE s.session_id = p_session_id;
  IF v_alert IS NULL THEN RETURN; END IF;

  UPDATE public.alerts a
     SET reporter_landmark = left(v_text, 120),
         -- Appended to the description as well, because that is what a
         -- dispatcher reads first and what the SMS and push notices carry. A
         -- column nobody surfaces is a column nobody reads.
         description = coalesce(a.description, '')
                       || ' Nearest landmark: ' || left(v_text, 120) || '.',
         updated_at = NOW()
   WHERE a.id = v_alert
  RETURNING a.public_reference, a.id INTO reference, alert_id;

  IF reference IS NULL THEN RETURN; END IF;
  RETURN NEXT;
END $$;

COMMENT ON FUNCTION public.ussd_add_landmark(TEXT, TEXT) IS
  'Attaches a typed landmark to the report THIS USSD session filed. Never takes '
  'an alert id from the caller: that would let anybody write a landmark onto any '
  'incident in Plateau and redirect a response by typing.';

REVOKE ALL ON FUNCTION public.ussd_add_landmark(TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ussd_add_landmark(TEXT, TEXT) TO service_role;
