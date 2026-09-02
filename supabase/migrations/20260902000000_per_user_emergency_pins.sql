-- ============================================================================
-- Per-user, server-verified emergency PINs
-- ============================================================================
--
-- WHAT THIS REPLACES
--
-- SAFE_PIN and DURESS_PIN were build-time constants in the mobile app's `.env`,
-- which pubspec.yaml declares as a Flutter ASSET — so they shipped verbatim
-- inside every APK and extracted with `unzip`. Every install shared the same
-- two codes, and anyone who downloaded the app could read the duress code.
-- A duress PIN that a captor can look up is worse than none: it tells them
-- exactly which code NOT to let the victim enter.
--
-- THE DESIGN
--
--  * Each user sets their own safe PIN and duress PIN. Only bcrypt hashes are
--    stored (pgcrypto `crypt`, cost 10), in a table NOBODY can read through the
--    API: RLS is enabled with no policies, and all privileges are revoked from
--    the API roles. The only way in is through the functions below.
--
--  * Verification happens here, in SECURITY DEFINER functions, never on the
--    device. The client learns only the outcome. A short numeric PIN would be
--    brute-forceable offline from its hash, so the hash never leaves the
--    database, and online guessing is rate-limited: five failures lock the
--    account's PIN entry for fifteen minutes.
--
--  * `resolve_emergency` verifies the PIN and closes the alert in ONE call,
--    server-side, recording who did it. This is the follow-up the RLS
--    migration's own comment asked for ("moving resolution behind an RPC that
--    records WHO resolved it"). The status written — RESOLVED or DURESS — is
--    the only thing that differs between the two codes; the app's screen looks
--    identical either way, which is the point of a duress code.
--
-- OFFLINE
--
-- Verification needs the server. This is NOT a regression: the previous
-- client-side check also awaited a database update and returned false when
-- that failed, so an offline cancellation already did not succeed. What it
-- does change is that no PIN material exists on the device at all.
--
-- Idempotent: safe to re-run.
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ────────────────────────────────────────────────────────────────────────────
-- 1. STORAGE — write-only from the API's point of view
-- ────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.emergency_pins (
  user_id         uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  safe_hash       text NOT NULL,
  duress_hash     text NOT NULL,
  failed_attempts integer NOT NULL DEFAULT 0,
  locked_until    timestamptz,
  updated_at      timestamptz NOT NULL DEFAULT now()
);

-- RLS on, and deliberately NO policies: with row security enabled and nothing
-- granting access, every direct read or write through PostgREST is denied for
-- anon and authenticated alike. Belt and braces with the REVOKEs below.
ALTER TABLE public.emergency_pins ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.emergency_pins FROM anon, authenticated;

-- ────────────────────────────────────────────────────────────────────────────
-- 2. SETTING PINS
-- ────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.set_emergency_pins(p_safe text, p_duress text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_safe IS NULL OR p_safe !~ '^[0-9]{4,8}$' THEN
    RAISE EXCEPTION 'safe PIN must be 4 to 8 digits' USING ERRCODE = '22023';
  END IF;
  IF p_duress IS NULL OR p_duress !~ '^[0-9]{4,8}$' THEN
    RAISE EXCEPTION 'duress PIN must be 4 to 8 digits' USING ERRCODE = '22023';
  END IF;
  -- The two codes must differ, or there is no duress signal at all.
  IF p_safe = p_duress THEN
    RAISE EXCEPTION 'safe and duress PINs must be different' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.emergency_pins (user_id, safe_hash, duress_hash, failed_attempts, locked_until, updated_at)
  VALUES (
    v_uid,
    crypt(p_safe,   gen_salt('bf', 10)),
    crypt(p_duress, gen_salt('bf', 10)),
    0, NULL, now()
  )
  ON CONFLICT (user_id) DO UPDATE SET
    safe_hash       = EXCLUDED.safe_hash,
    duress_hash     = EXCLUDED.duress_hash,
    failed_attempts = 0,
    locked_until    = NULL,
    updated_at      = now();
END;
$$;

CREATE OR REPLACE FUNCTION public.has_emergency_pins()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (SELECT 1 FROM public.emergency_pins WHERE user_id = auth.uid());
$$;

-- ────────────────────────────────────────────────────────────────────────────
-- 3. VERIFYING — shared core, with lockout
-- ────────────────────────────────────────────────────────────────────────────
--
-- Returns one of: 'SAFE', 'DURESS', 'INVALID', 'LOCKED', 'UNSET'.
-- Not exposed to the API directly (see GRANTs); the two public entry points
-- below wrap it.

CREATE OR REPLACE FUNCTION public._check_emergency_pin(p_uid uuid, p_pin text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  r public.emergency_pins%ROWTYPE;
  v_kind text;
BEGIN
  SELECT * INTO r FROM public.emergency_pins WHERE user_id = p_uid FOR UPDATE;
  IF NOT FOUND THEN
    RETURN 'UNSET';
  END IF;

  IF r.locked_until IS NOT NULL AND r.locked_until > now() THEN
    RETURN 'LOCKED';
  END IF;

  IF p_pin IS NOT NULL AND crypt(p_pin, r.safe_hash) = r.safe_hash THEN
    v_kind := 'SAFE';
  ELSIF p_pin IS NOT NULL AND crypt(p_pin, r.duress_hash) = r.duress_hash THEN
    v_kind := 'DURESS';
  ELSE
    -- Five wrong guesses lock PIN entry for fifteen minutes. A 4-digit space
    -- is 10,000 codes; without this, an attacker holding the phone could walk
    -- it in an afternoon.
    UPDATE public.emergency_pins
       SET failed_attempts = failed_attempts + 1,
           locked_until = CASE WHEN failed_attempts + 1 >= 5
                               THEN now() + interval '15 minutes' ELSE NULL END
     WHERE user_id = p_uid;
    RETURN 'INVALID';
  END IF;

  UPDATE public.emergency_pins
     SET failed_attempts = 0, locked_until = NULL
   WHERE user_id = p_uid;
  RETURN v_kind;
END;
$$;

-- Check a PIN without touching any alert. Used when the app has no server-side
-- alert to close (an SOS still queued offline).
CREATE OR REPLACE FUNCTION public.verify_emergency_pin(p_pin text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING ERRCODE = '42501';
  END IF;
  RETURN public._check_emergency_pin(v_uid, p_pin);
END;
$$;

-- Verify the PIN and close the alert, in one call, recording who did it.
--
-- Returns: 'RESOLVED' (safe PIN), 'DURESS' (duress PIN — the alert is marked
-- DURESS and is NOT a normal resolution; HQ sees it as an escalation),
-- 'INVALID', 'LOCKED', 'UNSET', or 'NOT_FOUND' (no alert of that id that this
-- user reported or is assigned to).
CREATE OR REPLACE FUNCTION public.resolve_emergency(p_alert_id uuid, p_pin text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid  uuid := auth.uid();
  v_kind text;
  v_rows integer;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING ERRCODE = '42501';
  END IF;

  v_kind := public._check_emergency_pin(v_uid, p_pin);
  IF v_kind NOT IN ('SAFE', 'DURESS') THEN
    RETURN v_kind;
  END IF;

  -- Only the person who raised the alert, or the responder assigned to it, can
  -- close it with a PIN. Staff resolve from the console, not from here.
  UPDATE public.alerts
     SET status      = CASE v_kind WHEN 'SAFE' THEN 'RESOLVED' ELSE 'DURESS' END,
         resolved_by = v_uid::text,
         resolved_at = now(),
         updated_at  = now()
   WHERE id = p_alert_id
     AND (reported_by = v_uid OR assigned_to = v_uid);
  GET DIAGNOSTICS v_rows = ROW_COUNT;

  IF v_rows = 0 THEN
    RETURN 'NOT_FOUND';
  END IF;
  RETURN CASE v_kind WHEN 'SAFE' THEN 'RESOLVED' ELSE 'DURESS' END;
END;
$$;

-- ────────────────────────────────────────────────────────────────────────────
-- 4. WHO MAY CALL WHAT
-- ────────────────────────────────────────────────────────────────────────────

REVOKE ALL ON FUNCTION public._check_emergency_pin(uuid, text) FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.set_emergency_pins(text, text)   FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.has_emergency_pins()             FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.verify_emergency_pin(text)       FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.resolve_emergency(uuid, text)    FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.set_emergency_pins(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.has_emergency_pins()           TO authenticated;
GRANT EXECUTE ON FUNCTION public.verify_emergency_pin(text)     TO authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_emergency(uuid, text)  TO authenticated;
