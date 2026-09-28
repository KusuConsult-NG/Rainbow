-- ============================================================================
-- OPERATION RAINBOW — DOES THE MESH RECOGNISE A DUPLICATE, AND FORGET IN TIME?
--
-- The mesh floods on purpose, so the same emergency reaches HQ several times by
-- several paths. Two things therefore have to be true at once, and they pull in
-- opposite directions:
--
--   * HQ must REMEMBER an envelope long enough to recognise it arriving again,
--     or one kidnapping becomes six incidents and six units go to one place
--     while the next call waits;
--   * HQ must FORGET it, because a permanent record of which envelopes arrived
--     when is a record of mesh traffic that serves no operational purpose.
--
-- And one structural thing, which is the whole reason the channel is worth
-- having: this table must never learn who relayed what.
--
-- Run inside scripts/verify_rls_migration.sh, after the migrations.
-- ============================================================================

\set ON_ERROR_STOP on

DO $test$
DECLARE
  id_a     BYTEA := decode('000102030405060708090a0b0c0d0e0f', 'hex');
  id_b     BYTEA := decode('ffeeddccbbaa99887766554433221100', 'hex');
  is_new   BOOLEAN;
  n        INT;
  seen     INT;
  cols     TEXT;
  failures INT := 0;
BEGIN
  DELETE FROM public.mesh_envelopes_seen WHERE envelope_id IN (id_a, id_b);

  -- ── 1. The first arrival is the one that counts ──────────────────────────
  SELECT public.mesh_note_envelope(id_a) INTO is_new;
  IF is_new THEN
    RAISE NOTICE 'PASS  the first arrival of an envelope is reported as new';
  ELSE
    RAISE WARNING 'FAIL  the first arrival was treated as a duplicate — the '
                  'alert inside it would never be recorded';
    failures := failures + 1;
  END IF;

  -- ── 2. Every later one is a duplicate ────────────────────────────────────
  SELECT public.mesh_note_envelope(id_a) INTO is_new;
  IF NOT is_new THEN
    RAISE NOTICE 'PASS  a second arrival is recognised as the same envelope';
  ELSE
    RAISE WARNING 'FAIL  the same envelope is new twice — the mesh would '
                  'create one incident per relay that carried it';
    failures := failures + 1;
  END IF;

  PERFORM public.mesh_note_envelope(id_a);
  PERFORM public.mesh_note_envelope(id_a);
  SELECT arrivals INTO n FROM public.mesh_envelopes_seen
   WHERE envelope_id = id_a;
  IF n = 4 THEN
    RAISE NOTICE 'PASS  arrivals are counted — the only mesh health signal we have';
  ELSE
    RAISE WARNING 'FAIL  arrivals is % after four uploads', n;
    failures := failures + 1;
  END IF;

  SELECT count(*) INTO n FROM public.mesh_envelopes_seen
   WHERE envelope_id = id_a AND last_seen_at >= first_seen_at;
  IF n = 1 THEN
    RAISE NOTICE 'PASS  the last arrival is timestamped';
  ELSE
    RAISE WARNING 'FAIL  last_seen_at is not maintained';
    failures := failures + 1;
  END IF;

  -- ── 3. A different envelope is a different incident ──────────────────────
  SELECT public.mesh_note_envelope(id_b) INTO is_new;
  IF is_new THEN
    RAISE NOTICE 'PASS  a different envelope is not shadowed by the first';
  ELSE
    RAISE WARNING 'FAIL  two distinct envelopes collapsed into one';
    failures := failures + 1;
  END IF;

  -- ── 4. Something that is not an envelope id is refused ───────────────────
  --
  -- Not pedantry: a truncated id would collide with everything sharing its
  -- prefix, so every alert after the first would be silently dropped as a
  -- duplicate. That failure is invisible from outside.
  BEGIN
    PERFORM public.mesh_note_envelope(decode('0011', 'hex'));
    RAISE WARNING 'FAIL  a 2-byte id was accepted as an envelope id';
    failures := failures + 1;
  EXCEPTION WHEN raise_exception THEN
    RAISE NOTICE 'PASS  only a 16-byte id is accepted';
  END;

  -- ── 5. Nobody but the service role can reach any of this ─────────────────
  IF has_function_privilege('anon', 'public.mesh_note_envelope(bytea)', 'EXECUTE')
     OR has_function_privilege('authenticated',
           'public.mesh_note_envelope(bytea)', 'EXECUTE') THEN
    RAISE WARNING 'FAIL  a client can mark envelopes as already seen, which is '
                  'a way to make HQ drop an alert it has never received';
    failures := failures + 1;
  ELSE
    RAISE NOTICE 'PASS  only the service role can note an arrival';
  END IF;

  -- ── 6. And the table itself is not readable through the API ──────────────
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub',
                     '99990000-0000-4000-8000-00000000cafe', true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  BEGIN
    SELECT count(*) INTO seen FROM public.mesh_envelopes_seen;
    IF seen = 0 THEN
      RAISE NOTICE 'PASS  a signed-in client cannot enumerate mesh traffic';
    ELSE
      RAISE WARNING 'FAIL  a signed-in client can see % row(s) of mesh traffic', seen;
      failures := failures + 1;
    END IF;
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'PASS  a signed-in client cannot even count mesh traffic';
  END;
  RESET ROLE;

  -- ── 7. It forgets, and forgets the right rows ────────────────────────────
  UPDATE public.mesh_envelopes_seen
     SET first_seen_at = NOW() - INTERVAL '72 hours'
   WHERE envelope_id = id_a;

  SELECT public.purge_stale_mesh_envelopes() INTO n;
  IF n >= 1 THEN
    RAISE NOTICE 'PASS  envelope ids older than 48 hours are purged';
  ELSE
    RAISE WARNING 'FAIL  nothing was purged — mesh traffic is kept for ever';
    failures := failures + 1;
  END IF;

  SELECT count(*) INTO n FROM public.mesh_envelopes_seen
   WHERE envelope_id = id_b;
  IF n = 1 THEN
    RAISE NOTICE 'PASS  and a recent envelope is still remembered, so a frame '
                 'in flight cannot become new again';
  ELSE
    RAISE WARNING 'FAIL  the purge took a live envelope with it';
    failures := failures + 1;
  END IF;

  -- ── 8. The table cannot become a record of who relayed what ──────────────
  --
  -- The structural assertion. If somebody later adds "which relay uploaded it"
  -- to make debugging easier, they will have built exactly the surveillance
  -- tool this channel was designed not to be — a hostile reader with database
  -- access could see which handsets carried which emergencies. It fails here
  -- rather than in a review nobody schedules.
  SELECT string_agg(column_name, ',' ORDER BY column_name) INTO cols
    FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'mesh_envelopes_seen';
  IF cols = 'arrivals,envelope_id,first_seen_at,last_seen_at' THEN
    RAISE NOTICE 'PASS  the table knows nothing but that an envelope arrived';
  ELSE
    RAISE WARNING 'FAIL  mesh_envelopes_seen has columns [%] — anything '
                  'identifying a relay makes this a surveillance record', cols;
    failures := failures + 1;
  END IF;

  -- ── 9. A dispatcher can tell a mesh alert from an ordinary one ───────────
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'alerts'
       AND column_name = 'arrived_via'
  ) THEN
    RAISE NOTICE 'PASS  alerts.arrived_via exists, so MESH can be recorded';
  ELSE
    RAISE WARNING 'FAIL  no arrived_via column: a mesh alert would look like a '
                  'normal one, and the reporter cannot be called back';
    failures := failures + 1;
  END IF;

  DELETE FROM public.mesh_envelopes_seen WHERE envelope_id IN (id_a, id_b);

  IF failures > 0 THEN
    RAISE EXCEPTION 'MESH INGEST TEST FAILED (% assertion(s))', failures;
  END IF;
  RAISE NOTICE 'ALL MESH INGEST ASSERTIONS PASSED';
END
$test$;
