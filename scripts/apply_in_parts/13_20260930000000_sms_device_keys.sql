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
-- 20260930000000_sms_device_keys.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20260930000000_sms_device_keys.sql'; END $apply$;

-- ============================================================================
-- OPERATION RAINBOW — A KEY PER HANDSET, FOR THE SMS FALLBACK
--
-- The SMS fallback carries an alert as 54 encrypted bytes, so that a report
-- sent when there is cell signal but no data is readable by HQ and by nobody
-- else — not the carrier, not anyone holding the handset and reading its sent
-- folder. That needs a key, and WHICH key it is decides what the channel is
-- worth.
--
-- WHY PER-DEVICE, AND NOT ONE APP KEY
--
-- A single key compiled into the app is extracted from the APK with `unzip`,
-- as this project already learned the expensive way with the Termii
-- credential. With one shared key, anyone who pulls it can forge an emergency
-- from any citizen and read every SMS alert in the state. Per-device means a
-- compromised handset compromises that handset.
--
-- WHY SYMMETRIC, AND NOT PUBLIC-KEY
--
-- Two reasons, and the second is the binding one:
--
--   * It authenticates as well as conceals. The AES-GCM tag proves the message
--     came from that device. The `smsWebhook` this replaces accepted anything
--     that reached it, so anyone who knew the number could inject an emergency.
--   * It is 32 bytes smaller on the wire than carrying an ephemeral public
--     key, and those 32 bytes are what keep the message inside ONE segment.
--     A second segment is a second charge on every alert.
--
-- The cost is honest and worth writing down: HQ holds material that can both
-- decrypt and forge these messages. That is not a new exposure — HQ already
-- holds every alert in plaintext — but it does mean this table is as sensitive
-- as `emergency_pins`, and it is protected the same way.
--
-- THE KEY IS NEVER READABLE THROUGH THE API
--
-- Not by the API roles, not by the device's own owner, not once. It is
-- returned exactly once, by the SECURITY DEFINER function that creates it, and
-- after that the only thing that can read it is the service role during SMS
-- ingest. A device that loses its key registers again.
--
-- Idempotent: safe to re-run.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.sms_device_keys (
  -- HQ's four-byte handle for this key, sent in the clear in the message so
  -- ingest knows which key to try. Four bytes is 4.3 billion; collisions are
  -- handled by retrying on the unique constraint at registration.
  device_ref   BYTEA PRIMARY KEY,
  user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  -- 32 bytes. Never selected by anything but the service role.
  secret       BYTEA NOT NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_used_at TIMESTAMPTZ,
  -- Set rather than deleted, so an alert already in flight over a slow SMS
  -- queue can still be attributed after the device is retired.
  revoked_at   TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS sms_device_keys_user_idx
  ON public.sms_device_keys (user_id) WHERE revoked_at IS NULL;

ALTER TABLE public.sms_device_keys ENABLE ROW LEVEL SECURITY;

-- No policies at all, deliberately. With RLS enabled and nothing granted, the
-- API roles cannot read, write or even count this table. Everything legitimate
-- goes through the functions below.
REVOKE ALL ON TABLE public.sms_device_keys FROM PUBLIC, anon, authenticated;

-- ── Registration ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.register_sms_device()
RETURNS TABLE (device_ref BYTEA, secret BYTEA)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp, extensions
AS $$
DECLARE
  uid      UUID := auth.uid();
  new_ref  BYTEA;
  new_key  BYTEA;
  attempts INT := 0;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not signed in';
  END IF;

  -- One live key per user at a time. Registering again retires the old one
  -- rather than accumulating keys a stolen handset could keep using.
  UPDATE public.sms_device_keys
     SET revoked_at = NOW()
   WHERE user_id = uid AND revoked_at IS NULL;

  LOOP
    attempts := attempts + 1;
    new_ref := gen_random_bytes(4);
    EXIT WHEN NOT EXISTS (
      SELECT 1 FROM public.sms_device_keys k WHERE k.device_ref = new_ref
    );
    IF attempts > 8 THEN
      RAISE EXCEPTION 'could not allocate a device reference';
    END IF;
  END LOOP;

  new_key := gen_random_bytes(32);

  INSERT INTO public.sms_device_keys (device_ref, user_id, secret)
  VALUES (new_ref, uid, new_key);

  -- Returned ONCE. There is no function that reads it back.
  RETURN QUERY SELECT new_ref, new_key;
END;
$$;

COMMENT ON FUNCTION public.register_sms_device() IS
  'Issues a per-device key for the encrypted SMS fallback. Returns it once; '
  'nothing can read it back. Retires any previous key for the same user.';

-- ── Does this device still have a live key? ─────────────────────────────────
--
-- So the app can tell "never registered" from "registered and still valid"
-- without ever asking for the key itself.

CREATE OR REPLACE FUNCTION public.has_sms_device_key(p_ref BYTEA)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.sms_device_keys k
     WHERE k.device_ref = p_ref
       AND k.user_id = auth.uid()
       AND k.revoked_at IS NULL
  );
$$;

-- ── Retiring a key ──────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.revoke_sms_device_keys()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  n INT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not signed in';
  END IF;
  UPDATE public.sms_device_keys
     SET revoked_at = NOW()
   WHERE user_id = auth.uid() AND revoked_at IS NULL;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$$;

COMMENT ON FUNCTION public.revoke_sms_device_keys() IS
  'Retires this user''s SMS device keys. Called on sign-out and on uninstall.';

-- ── Ingest ──────────────────────────────────────────────────────────────────
--
-- Service role only. This is the one thing in the system that may read a
-- secret, and it exists so the SMS inbound endpoint can look a key up by the
-- four bytes the message carried in the clear.

CREATE OR REPLACE FUNCTION public.sms_key_for_ingest(p_ref BYTEA)
RETURNS TABLE (user_id UUID, secret BYTEA)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN QUERY
  UPDATE public.sms_device_keys k
     SET last_used_at = NOW()
   WHERE k.device_ref = p_ref
     AND k.revoked_at IS NULL
  RETURNING k.user_id, k.secret;
END;
$$;

COMMENT ON FUNCTION public.sms_key_for_ingest(BYTEA) IS
  'Service role only. Looks up a device key during SMS ingest and stamps its '
  'last use. Never reachable from a phone or a browser.';

-- ── Grants ──────────────────────────────────────────────────────────────────

REVOKE ALL ON FUNCTION public.register_sms_device()        FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.has_sms_device_key(BYTEA)    FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.revoke_sms_device_keys()     FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.sms_key_for_ingest(BYTEA)
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.register_sms_device()     TO authenticated;
GRANT EXECUTE ON FUNCTION public.has_sms_device_key(BYTEA) TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_sms_device_keys()  TO authenticated;
GRANT EXECUTE ON FUNCTION public.sms_key_for_ingest(BYTEA) TO service_role;

-- ── Where an SMS-borne alert says it came from ──────────────────────────────
--
-- A dispatcher must be able to see that this alert arrived over a degraded
-- channel. Not because the content is untrusted — it is authenticated — but
-- because a phone that could not reach the network is itself operationally
-- significant, and because an SMS can sit in a carrier queue for minutes.

ALTER TABLE public.alerts
  ADD COLUMN IF NOT EXISTS arrived_via TEXT;

COMMENT ON COLUMN public.alerts.arrived_via IS
  'NULL for the ordinary path. ''SMS'' when the report reached us over the '
  'encrypted SMS fallback, meaning the reporter had no data connection.';

