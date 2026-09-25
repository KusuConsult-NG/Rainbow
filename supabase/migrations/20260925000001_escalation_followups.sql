-- ─── Oversight routing, evidential retention, schema follow-ups ──────────────
--
-- Four things, all follow-ups to gaps found after the escalation engine landed:
--
--   1. Reports accusing security personnel no longer route to the tier that
--      contains the accused. They enter at HQ and are readable only by
--      oversight roles.
--   2. Responder position is retained as a track, so a closed incident can be
--      reconstructed geographically. Previously telemetry held one current row
--      per user and the history was thrown away on every update.
--   3. A mission debrief gets its own column instead of being appended into
--      `ai_summary`, which mixed officer testimony with machine output.
--   4. `telemetry.user_id` is guaranteed unique, because two earlier migrations
--      define the table differently and the client upserts on that column.
--
-- Apply after 20260925000000_escalation_engine.sql. Idempotent; safe to re-run.

-- ─── 0. Oversight role helper ────────────────────────────────────────────────
-- Deliberately narrow: state-level command and a dedicated oversight role only.
-- An LGA, ward or unit commander is NOT oversight — the whole point is that a
-- complaint about local officers does not land with their own chain.
CREATE OR REPLACE FUNCTION public.is_oversight() RETURNS BOOLEAN
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT COALESCE(
    public.auth_role() IN ('HQ_COMMAND', 'HQ_OFFICER', 'ADMIN', 'OVERSIGHT'),
    false
  );
$$;

REVOKE EXECUTE ON FUNCTION public.is_oversight() FROM anon;

-- ─── 1. Oversight routing ────────────────────────────────────────────────────
ALTER TABLE public.alerts
  ADD COLUMN IF NOT EXISTS oversight_only BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN public.alerts.oversight_only IS
  'Report accusing security personnel. Enters at HQ tier; readable and '
  'actionable only by oversight roles and the reporter.';

-- Which report categories count. Matched case-insensitively against the start
-- of alerts.type, which the client composes as "<category> - <sub-type>".
-- Config-driven so HQ can extend the list without a migration.
INSERT INTO public.app_config (key, value, description) VALUES
  ('oversight_categories', 'police brutality',
   'Comma-separated report categories routed to oversight instead of the local command tier')
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.is_oversight_category(p_type TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_raw TEXT;
  v_cat TEXT;
BEGIN
  IF p_type IS NULL THEN
    RETURN FALSE;
  END IF;

  SELECT value INTO v_raw FROM public.app_config
   WHERE key = 'oversight_categories';

  IF v_raw IS NULL OR btrim(v_raw) = '' THEN
    RETURN FALSE;
  END IF;

  FOREACH v_cat IN ARRAY string_to_array(lower(v_raw), ',') LOOP
    IF btrim(v_cat) <> '' AND lower(p_type) LIKE btrim(v_cat) || '%' THEN
      RETURN TRUE;
    END IF;
  END LOOP;

  RETURN FALSE;
END;
$$;

-- Stamped on insert, before the escalation engine ever looks at the row, so an
-- oversight report is never briefly visible to the local tier.
CREATE OR REPLACE FUNCTION public.route_oversight_alert()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF public.is_oversight_category(NEW.type) THEN
    NEW.oversight_only  := TRUE;
    NEW.assigned_tier   := 'HQ';
    NEW.tier_entered_at := COALESCE(NEW.tier_entered_at, now());
    -- No local officer owns it, whatever the client sent.
    NEW.assigned_to     := NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_route_oversight_alert ON public.alerts;
CREATE TRIGGER trg_route_oversight_alert
  BEFORE INSERT ON public.alerts
  FOR EACH ROW EXECUTE FUNCTION public.route_oversight_alert();

-- Read: ordinary alerts stay visible to every signed-in user exactly as before;
-- an oversight report is visible only to oversight roles and its reporter.
-- These replace the two policies 20260813000000_rls_least_privilege.sql created,
-- keeping its scoping exactly (a citizen sees their own reports and the ones
-- assigned to them; staff see the rest) and adding one carve-out: an oversight
-- report is invisible to staff who are not oversight.
DROP POLICY IF EXISTS "alerts_select_own_or_staff" ON public.alerts;
CREATE POLICY "alerts_select_own_or_staff" ON public.alerts
  FOR SELECT TO authenticated
  USING (
    reported_by = auth.uid()
    OR public.is_oversight()
    OR (NOT oversight_only AND (assigned_to = auth.uid() OR public.is_staff()))
  );

-- Update: an accused officer must not be able to resolve the complaint about
-- himself. Everyone keeps their existing rights on every other incident.
DROP POLICY IF EXISTS "alerts_update_own_or_staff" ON public.alerts;
CREATE POLICY "alerts_update_own_or_staff" ON public.alerts
  FOR UPDATE TO authenticated
  USING (
    reported_by = auth.uid()
    OR public.is_oversight()
    OR (NOT oversight_only AND (assigned_to = auth.uid() OR public.is_staff()))
  );

-- ─── 2. Position history ─────────────────────────────────────────────────────
-- A track is only useful if it can be tied to the incident it was recorded for.
-- `telemetry` has carried no alert_id, so a position could be attributed to a
-- responder but not to the emergency they were attending.
ALTER TABLE public.telemetry
  ADD COLUMN IF NOT EXISTS alert_id UUID
    REFERENCES public.alerts(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_telemetry_alert
  ON public.telemetry (alert_id) WHERE alert_id IS NOT NULL;

-- telemetry holds the CURRENT position per user (the map reads it). Every write
-- also appends here, so the track survives. Written by trigger, so no client
-- change is needed and an older app build still produces history.
CREATE TABLE IF NOT EXISTS public.telemetry_history (
  id         BIGSERIAL       PRIMARY KEY,
  user_id    UUID             NOT NULL,
  alert_id   UUID,
  latitude   DOUBLE PRECISION,
  longitude  DOUBLE PRECISION,
  mode       TEXT,
  status     TEXT,
  battery    INTEGER,
  accuracy   DOUBLE PRECISION,
  speed      DOUBLE PRECISION,
  recorded_at TIMESTAMPTZ     NOT NULL DEFAULT now()
);

-- The two queries that matter: one responder's track over a window, and one
-- incident's track.
CREATE INDEX IF NOT EXISTS idx_telemetry_history_user_time
  ON public.telemetry_history (user_id, recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_telemetry_history_alert_time
  ON public.telemetry_history (alert_id, recorded_at)
  WHERE alert_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.append_telemetry_history()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  -- A repeated write with no movement is not a new track point.
  IF TG_OP = 'UPDATE'
     AND NEW.latitude  IS NOT DISTINCT FROM OLD.latitude
     AND NEW.longitude IS NOT DISTINCT FROM OLD.longitude
     AND NEW.status    IS NOT DISTINCT FROM OLD.status THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.telemetry_history
    (user_id, alert_id, latitude, longitude, mode, status, battery, accuracy, speed)
  VALUES
    (NEW.user_id, NEW.alert_id, NEW.latitude, NEW.longitude, NEW.mode,
     NEW.status, NEW.battery, NEW.accuracy, NEW.speed);

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_append_telemetry_history ON public.telemetry;
CREATE TRIGGER trg_append_telemetry_history
  AFTER INSERT OR UPDATE ON public.telemetry
  FOR EACH ROW EXECUTE FUNCTION public.append_telemetry_history();

ALTER TABLE public.telemetry_history ENABLE ROW LEVEL SECURITY;

-- A track is location data about a named person. Responders and the subject,
-- nobody else; the public role gets nothing.
DROP POLICY IF EXISTS "telemetry_history_read" ON public.telemetry_history;
CREATE POLICY "telemetry_history_read" ON public.telemetry_history
  FOR SELECT TO authenticated
  USING (public.is_staff() OR user_id = auth.uid());


-- Retention. The Firestore build pruned tracks nightly; keep that, driven by
-- config so the retention schedule is a policy decision, not a code change.
INSERT INTO public.app_config (key, value, description) VALUES
  ('telemetry_history_retention_days', '90',
   'Days of responder position history to retain before pruning')
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.prune_telemetry_history()
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_days    INT;
  v_deleted INT;
BEGIN
  v_days := public.escalation_config_int('telemetry_history_retention_days', 90);

  DELETE FROM public.telemetry_history
   WHERE recorded_at < now() - make_interval(days => v_days);

  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;

-- ─── 3. Mission debrief gets its own column ──────────────────────────────────
ALTER TABLE public.alerts
  ADD COLUMN IF NOT EXISTS debrief     TEXT,
  ADD COLUMN IF NOT EXISTS debrief_by  TEXT,
  ADD COLUMN IF NOT EXISTS debrief_at  TIMESTAMPTZ;

COMMENT ON COLUMN public.alerts.debrief IS
  'The responding officer''s closing report. Kept separate from ai_summary so '
  'officer testimony is never mixed with machine-generated text.';

-- ─── 4. telemetry.user_id uniqueness ─────────────────────────────────────────
-- The initial schema makes user_id the primary key; phase1 defines the table
-- with its own id and no uniqueness on user_id. Whichever created it, the
-- client upserts ON CONFLICT (user_id), which needs a unique index to exist.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
      FROM pg_index i
      JOIN pg_class c   ON c.oid = i.indrelid
      JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = ANY (i.indkey)
     WHERE c.relname = 'telemetry'
       AND c.relnamespace = 'public'::regnamespace
       AND i.indisunique
       AND i.indnatts = 1
       AND a.attname = 'user_id'
  ) THEN
    -- Collapse any duplicates first, newest kept, or the index cannot be built.
    DELETE FROM public.telemetry t
     WHERE EXISTS (
       SELECT 1 FROM public.telemetry n
        WHERE n.user_id = t.user_id
          AND (n.updated_at, n.ctid) > (t.updated_at, t.ctid)
     );

    CREATE UNIQUE INDEX telemetry_user_id_key
      ON public.telemetry (user_id);
    RAISE NOTICE '[MIGRATION] Added unique index on telemetry.user_id.';
  END IF;
END $$;

-- ─── 5. Jurisdiction name normalisation ──────────────────────────────────────
-- The app's tactical map spelled one LGA 'BARIKIN LADI'; the statutory name is
-- 'BARKIN LADI', which is what the dashboard offered in its filter. Any alert
-- filed from that LGA therefore could not be found by filtering for it. The map
-- is corrected in code; these rows were written before that.
UPDATE public.alerts
   SET geo_lga = 'BARKIN LADI'
 WHERE upper(btrim(geo_lga)) = 'BARIKIN LADI';

UPDATE public.profiles
   SET geo_lga = 'BARKIN LADI'
 WHERE upper(btrim(geo_lga)) = 'BARIKIN LADI';

-- ─── 6. Verification ─────────────────────────────────────────────────────────
SELECT 'Escalation follow-ups complete' AS result;
