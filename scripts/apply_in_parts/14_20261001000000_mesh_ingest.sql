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
-- 20261001000000_mesh_ingest.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261001000000_mesh_ingest.sql'; END $apply$;

-- ============================================================================
-- OPERATION RAINBOW — RECOGNISING THE SAME MESH ENVELOPE TWICE
--
-- The mesh floods. That is not a flaw in it; it is how a report crosses a crowd
-- when there is no tower. Every phone that takes an envelope on offers it to
-- every phone it then meets, so the same emergency reaches HQ by several paths,
-- from several relays, minutes apart. Without a memory, one kidnapping becomes
-- six incidents and six units are dispatched to one place while the next call
-- waits.
--
-- WHY THE ENVELOPE ID AND NOT THE CONTENTS
--
-- Because this check happens BEFORE decryption and must. The envelope id is 128
-- random bits chosen by the originating handset and is the only thing a relay
-- can see, so it is also the only thing HQ can use to drop a duplicate without
-- first spending an ECDH and an AES-GCM open on it. On an unauthenticated write
-- path that ordering is the difference between a flood costing us a table lookup
-- and a flood costing us a key agreement per frame.
--
-- The second dedup key — `alerts.local_id`, from inside the ciphertext — still
-- does the other half of the job: it catches the same incident arriving by SMS,
-- by mesh, and again from the reporter's own offline queue when their phone
-- recovers. Three channels, one incident. Neither check replaces the other.
--
-- WHY THE COUNT IS KEPT
--
-- `arrivals` is the only measure of mesh health that exists. Nothing else can
-- tell us whether relaying is actually working in the field: handsets cannot
-- report on each other without identifying who carried what, which is the thing
-- the design forbids. How many times one envelope reached HQ, by how many
-- distinct uploads, is an aggregate that identifies nobody.
--
-- WHAT THIS TABLE MUST NOT BECOME
--
-- A log of who relayed what. There is no relay column, no IP, no uploader. An
-- envelope id is 128 random bits with no meaning, `first_seen_at` is coarse, and
-- rows are purged after 48 hours. If someone later adds "which relay uploaded
-- it" to make debugging easier, they will have built the surveillance tool this
-- whole channel was designed to avoid being.
--
-- Idempotent: safe to re-run.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.mesh_envelopes_seen (
  -- 16 random bytes chosen by the originating handset. Carries no meaning and
  -- is not linkable to a device: two alerts from the same phone share nothing.
  envelope_id   BYTEA PRIMARY KEY,
  first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_seen_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- How many times this envelope reached us. Mesh health, and nothing else.
  arrivals      INTEGER NOT NULL DEFAULT 1
);

CREATE INDEX IF NOT EXISTS mesh_envelopes_seen_first_idx
  ON public.mesh_envelopes_seen (first_seen_at);

ALTER TABLE public.mesh_envelopes_seen ENABLE ROW LEVEL SECURITY;

-- No policies at all, deliberately, exactly as with sms_device_keys. With RLS
-- enabled and nothing granted, the API roles cannot read, write or count this
-- table. The one thing that touches it is the function below, as service_role.
REVOKE ALL ON TABLE public.mesh_envelopes_seen FROM PUBLIC, anon, authenticated;

-- ── Note an arrival ─────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.mesh_note_envelope(p_id BYTEA)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  is_new BOOLEAN;
BEGIN
  IF p_id IS NULL OR octet_length(p_id) <> 16 THEN
    RAISE EXCEPTION 'an envelope id is 16 bytes';
  END IF;

  -- One statement, so two relays uploading the same envelope at the same instant
  -- cannot both be told they are first. A SELECT-then-INSERT here would be a
  -- race that shows up exactly when the mesh is busiest.
  INSERT INTO public.mesh_envelopes_seen AS m (envelope_id)
  VALUES (p_id)
  ON CONFLICT (envelope_id) DO UPDATE
     SET arrivals     = m.arrivals + 1,
         last_seen_at = NOW()
  -- arrivals is 1 only on the row this statement inserted; the conflict branch
  -- always increments it past 1.
  RETURNING (m.arrivals = 1) INTO is_new;

  RETURN COALESCE(is_new, TRUE);
END;
$$;

COMMENT ON FUNCTION public.mesh_note_envelope(BYTEA) IS
  'Service role only. Records that a mesh envelope arrived and returns TRUE the '
  'first time. Called before decryption, so a flood costs a lookup rather than '
  'a key agreement.';

-- ── Purge ───────────────────────────────────────────────────────────────────
--
-- 48 hours: twice the age at which any relay will still carry an envelope
-- (`meshMaxAge` is 24h), so a frame cannot outlive our memory of it and become
-- new again. Rows kept longer would be a record of mesh traffic with no purpose.

CREATE OR REPLACE FUNCTION public.purge_stale_mesh_envelopes()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  n INT;
BEGIN
  DELETE FROM public.mesh_envelopes_seen
   WHERE first_seen_at < NOW() - INTERVAL '48 hours';
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$$;

COMMENT ON FUNCTION public.purge_stale_mesh_envelopes() IS
  'Deletes envelope ids older than 48 hours — twice the longest a relay will '
  'carry one, so nothing can outlive our memory of it.';

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('purge-stale-mesh-envelopes')
      WHERE EXISTS (
        SELECT 1 FROM cron.job WHERE jobname = 'purge-stale-mesh-envelopes'
      );
    PERFORM cron.schedule(
      'purge-stale-mesh-envelopes', '17 * * * *',
      'SELECT public.purge_stale_mesh_envelopes();'
    );
  ELSE
    -- Said out loud rather than assumed. A retention policy that depends on an
    -- extension nobody enabled is not a retention policy.
    RAISE NOTICE 'pg_cron is not installed: run purge_stale_mesh_envelopes() from a scheduled job.';
  END IF;
END
$$;

-- ── Grants ──────────────────────────────────────────────────────────────────

REVOKE ALL ON FUNCTION public.mesh_note_envelope(BYTEA)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.purge_stale_mesh_envelopes()
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.mesh_note_envelope(BYTEA)      TO service_role;
GRANT EXECUTE ON FUNCTION public.purge_stale_mesh_envelopes()   TO service_role;

-- ── Where an offline alert says it came from ─────────────────────────────────
--
-- 'MESH' joins 'SMS'. Both mean the reporter could not reach the network, and a
-- dispatcher needs to know that: the handset cannot be called back through the
-- app, nothing further is coming from it, and in the mesh case the position may
-- be some minutes old because it crossed a crowd to get here.

COMMENT ON COLUMN public.alerts.arrived_via IS
  'NULL for the ordinary path. ''SMS'' when the report reached us over the '
  'encrypted SMS fallback. ''MESH'' when it was relayed through nearby phones '
  'to one that had a network. Either way the reporter had no data connection.';

