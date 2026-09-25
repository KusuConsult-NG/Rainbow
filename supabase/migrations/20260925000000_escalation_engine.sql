-- ─── PHASE 6 MIGRATION: SLA ESCALATION ENGINE (ported from Firestore) ────────
--
-- Replaces the Cloud Functions escalation engine in functions/index.js
-- (escalateTask, escalationWatchdog, triggerSLASweep, adminEscalateAlert),
-- which ran against Firestore collections no live client writes to any more.
--
-- DESIGN NOTES — where this differs from the Firestore original, and why:
--
-- 1. Sweep, not a task queue.
--    The original enqueued a Cloud Task per alert with `scheduleDelaySeconds`
--    to defer each tier jump, and needed a 5-minute "watchdog" purely to
--    recover alerts whose tasks had been lost. Here, due-ness is derived from
--    `tier_entered_at` on every cycle, so the sweep is idempotent, survives
--    restarts, cannot lose or duplicate a jump, and needs no recovery pass.
--
-- 2. The tier gets its own column.
--    In Firestore `assigned_to` held a tier string ("WARD"). In Postgres
--    `alerts.assigned_to` is a UUID foreign key to a specific officer, so
--    writing a tier into it raises `invalid input syntax for type uuid`.
--    Tier now lives in `alerts.assigned_tier`; `assigned_to` keeps meaning
--    "the individual responsible".
--
-- 3. Timeline and audit trail become tables.
--    The original appended to an `alerts.timeline` array AND a
--    `alerts/{id}/timeline` subcollection — two copies that could diverge.
--    One `alert_timeline` table now serves both readers.
--
-- 4. Notifications go through an outbox.
--    A database function must not make outbound HTTP calls, so escalations
--    enqueue into `notification_outbox`; the `escalation-worker` edge function
--    drains it. A failed push therefore never rolls back an escalation.
--
-- Idempotent; safe to re-run.

-- ─── 1. Alert columns the engine needs ───────────────────────────────────────
ALTER TABLE public.alerts
  -- Command tier currently responsible. Distinct from assigned_to (a person).
  ADD COLUMN IF NOT EXISTS assigned_tier     TEXT NOT NULL DEFAULT 'POLLING_UNIT',
  -- When the alert entered its current tier. The SLA clock reads from here, so
  -- a manual escalation correctly restarts the timer for the new tier.
  ADD COLUMN IF NOT EXISTS tier_entered_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS escalated_at      TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS dispatched_at     TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS acknowledged_at   TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS sla_breached      BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS sla_breached_at   TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS last_edited_by    TEXT;

-- Partial index: the sweep only ever looks at open work.
CREATE INDEX IF NOT EXISTS idx_alerts_escalation_sweep
  ON public.alerts (assigned_tier, tier_entered_at)
  WHERE status NOT IN ('RESOLVED', 'CANCELLED', 'MERGED', 'CLOSED');

CREATE INDEX IF NOT EXISTS idx_alerts_sla_watch
  ON public.alerts (status, sla_breached)
  WHERE sla_breached = FALSE;

-- ─── 2. Timeline ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.alert_timeline (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  alert_id    UUID        NOT NULL REFERENCES public.alerts(id) ON DELETE CASCADE,
  event_type  TEXT        NOT NULL,
  actor       TEXT        NOT NULL DEFAULT 'SYSTEM',
  actor_role  TEXT        NOT NULL DEFAULT 'SYSTEM',
  reason      TEXT,
  notes       TEXT,
  from_tier   TEXT,
  to_tier     TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_alert_timeline_alert
  ON public.alert_timeline (alert_id, created_at DESC);

-- ─── 3. Audit log ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.audit_logs (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  action      TEXT        NOT NULL,
  alert_id    UUID        REFERENCES public.alerts(id) ON DELETE SET NULL,
  actor       TEXT        NOT NULL DEFAULT 'SYSTEM',
  from_tier   TEXT,
  to_tier     TEXT,
  reason      TEXT,
  detail      JSONB       NOT NULL DEFAULT '{}'::JSONB,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_audit_logs_alert   ON public.audit_logs (alert_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created ON public.audit_logs (created_at DESC);

-- ─── 4. Notification outbox ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.notification_outbox (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  alert_id      UUID        REFERENCES public.alerts(id) ON DELETE CASCADE,
  target_tier   TEXT,
  target_lga    TEXT,
  target_ward   TEXT,
  target_pu     TEXT,
  title         TEXT        NOT NULL,
  body          TEXT        NOT NULL,
  payload       JSONB       NOT NULL DEFAULT '{}'::JSONB,
  status        TEXT        NOT NULL DEFAULT 'PENDING',
  attempts      INTEGER     NOT NULL DEFAULT 0,
  last_error    TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  delivered_at  TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_notification_outbox_pending
  ON public.notification_outbox (created_at)
  WHERE status = 'PENDING';

-- ─── 5. Configuration ────────────────────────────────────────────────────────
-- phase3 already seeds escalation_timeout_pu / _ward / _lga (minutes). Add the
-- response SLA used by the breach detector, plus an engine kill switch.
--
-- The engine ships OFF. This migration installs the schema and (where pg_cron
-- is available) schedules the sweep, but every cycle exits immediately until
-- someone turns it on deliberately:
--
--   UPDATE public.app_config SET value = 'true' WHERE key = 'escalation_enabled';
--
-- ON CONFLICT DO NOTHING means re-applying this migration will not switch it
-- back off once you have enabled it.
INSERT INTO public.app_config (key, value, description) VALUES
  ('escalation_timeout_pu',   '2',  'Minutes an alert may sit at POLLING_UNIT before auto-escalating'),
  ('escalation_timeout_ward', '5',  'Minutes an alert may sit at WARD before auto-escalating'),
  ('escalation_timeout_lga',  '10', 'Minutes an alert may sit at LGA before auto-escalating'),
  ('escalation_response_sla', '15', 'Minutes a dispatched responder has to reach the scene'),
  ('escalation_enabled',      'false', 'Master switch for the automatic escalation engine')
ON CONFLICT (key) DO NOTHING;

-- Reads an integer setting, falling back when absent or non-numeric.
CREATE OR REPLACE FUNCTION public.escalation_config_int(p_key TEXT, p_default INT)
RETURNS INT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_raw TEXT;
BEGIN
  SELECT value INTO v_raw FROM public.app_config WHERE key = p_key;
  IF v_raw IS NULL OR btrim(v_raw) !~ '^[0-9]+$' THEN
    RETURN p_default;
  END IF;
  RETURN v_raw::INT;
END;
$$;

-- ─── 6. Tier ladder ──────────────────────────────────────────────────────────
-- POLLING_UNIT → WARD → LGA → HQ. HQ is terminal: nothing escalates past it.
CREATE OR REPLACE FUNCTION public.next_escalation_tier(p_tier TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE upper(coalesce(p_tier, 'POLLING_UNIT'))
           WHEN 'POLLING_UNIT' THEN 'WARD'
           WHEN 'PU'           THEN 'WARD'
           WHEN 'WARD'         THEN 'LGA'
           WHEN 'LGA'          THEN 'HQ'
           ELSE NULL
         END;
$$;

-- Rank used to reject a "escalation" that would move an alert backwards.
CREATE OR REPLACE FUNCTION public.escalation_tier_rank(p_tier TEXT)
RETURNS INT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE upper(coalesce(p_tier, 'POLLING_UNIT'))
           WHEN 'POLLING_UNIT' THEN 1
           WHEN 'PU'           THEN 1
           WHEN 'WARD'         THEN 2
           WHEN 'LGA'          THEN 3
           WHEN 'HQ'           THEN 4
           ELSE 0
         END;
$$;

-- How long an alert may sit at a tier before it escalates.
CREATE OR REPLACE FUNCTION public.escalation_timeout_minutes(p_tier TEXT)
RETURNS INT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE upper(coalesce(p_tier, 'POLLING_UNIT'))
           WHEN 'POLLING_UNIT' THEN public.escalation_config_int('escalation_timeout_pu', 2)
           WHEN 'PU'           THEN public.escalation_config_int('escalation_timeout_pu', 2)
           WHEN 'WARD'         THEN public.escalation_config_int('escalation_timeout_ward', 5)
           WHEN 'LGA'          THEN public.escalation_config_int('escalation_timeout_lga', 10)
           ELSE NULL
         END;
$$;

-- Statuses that still need someone to act. An alert outside this set is not
-- swept: it is finished, merged away, or already handed to an outside agency.
CREATE OR REPLACE FUNCTION public.escalation_open_statuses()
RETURNS TEXT[]
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT ARRAY[
    'PENDING', 'OPEN', 'ACTIVE', 'DURESS',
    'DISPATCHED', 'ACKNOWLEDGED', 'ON_ROUTE', 'ON_SITE', 'IN_PROGRESS'
  ];
$$;

-- ─── 7. Single write path for a tier change ──────────────────────────────────
-- Both the automatic sweep and a manual escalation funnel through here, so the
-- timeline, audit log, escalation_log and outbox can never disagree about what
-- happened. In the Firestore original these side effects were duplicated across
-- escalateTask, triggerSLASweep and adminEscalateAlert, and had already drifted
-- apart (different actor strings, different audit action names, and only one of
-- the three touched the timeline subcollection).
CREATE OR REPLACE FUNCTION public.apply_escalation(
  p_alert_id   UUID,
  p_to_tier    TEXT,
  p_actor      TEXT,
  p_actor_role TEXT,
  p_reason     TEXT,
  p_notes      TEXT,
  p_event_type TEXT,
  p_action     TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_alert   public.alerts%ROWTYPE;
  v_from    TEXT;
  v_entry   JSONB;
BEGIN
  -- Lock the row so two cycles cannot escalate the same alert twice.
  SELECT * INTO v_alert FROM public.alerts WHERE id = p_alert_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN FALSE;
  END IF;

  v_from := coalesce(v_alert.assigned_tier, 'POLLING_UNIT');

  -- Never move an alert backwards or sideways.
  IF public.escalation_tier_rank(p_to_tier) <= public.escalation_tier_rank(v_from) THEN
    RETURN FALSE;
  END IF;

  -- Never escalate finished work.
  IF NOT (v_alert.status = ANY (public.escalation_open_statuses())) THEN
    RETURN FALSE;
  END IF;

  v_entry := jsonb_build_object(
    'from_tier', v_from,
    'to_tier',   p_to_tier,
    'reason',    coalesce(p_reason, 'SLA threshold exceeded'),
    'notes',     coalesce(p_notes, ''),
    'by_email',  p_actor,
    'at',        to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
  );

  UPDATE public.alerts
     SET assigned_tier   = p_to_tier,
         tier_entered_at = now(),
         escalated_at    = now(),
         last_edited_by  = p_actor,
         -- HQ involvement means the incident is critical by definition.
         severity        = CASE WHEN p_to_tier = 'HQ' THEN 'CRITICAL'
                                ELSE coalesce(severity, 'HIGH') END,
         escalation_log  = coalesce(escalation_log, '[]'::JSONB) || v_entry,
         updated_at      = now()
   WHERE id = p_alert_id;

  INSERT INTO public.alert_timeline
    (alert_id, event_type, actor, actor_role, reason, notes, from_tier, to_tier)
  VALUES
    (p_alert_id, p_event_type, p_actor, p_actor_role,
     coalesce(p_reason, 'SLA threshold exceeded'),
     coalesce(p_notes, format('Escalated from %s to %s.', v_from, p_to_tier)),
     v_from, p_to_tier);

  INSERT INTO public.audit_logs
    (action, alert_id, actor, from_tier, to_tier, reason, detail)
  VALUES
    (p_action, p_alert_id, p_actor, v_from, p_to_tier, p_reason,
     jsonb_build_object('status', v_alert.status, 'severity', v_alert.severity));

  -- Queued, not sent: a database function must not make outbound HTTP calls,
  -- and a failed push must never roll back the escalation itself.
  INSERT INTO public.notification_outbox
    (alert_id, target_tier, target_lga, target_ward, target_pu, title, body, payload)
  VALUES
    (p_alert_id, p_to_tier, v_alert.geo_lga, v_alert.geo_ward, v_alert.geo_pu,
     format('⚠️ ESCALATED TO %s', p_to_tier),
     format('Incident %s is unresolved and now requires %s attention.',
            upper(substring(p_alert_id::TEXT, 1, 8)), p_to_tier),
     jsonb_build_object(
       'alertId',   p_alert_id,
       'type',      'ESCALATION',
       'tier',      p_to_tier,
       'fromTier',  v_from,
       'severity',  CASE WHEN p_to_tier = 'HQ' THEN 'CRITICAL' ELSE coalesce(v_alert.severity, 'HIGH') END
     ));

  RETURN TRUE;
END;
$$;

-- ─── 8. The sweep ────────────────────────────────────────────────────────────
-- Replaces escalateTask + triggerSLASweep. Escalates every alert whose time at
-- its current tier has exceeded that tier's configured timeout.
--
-- One tier per alert per cycle, deliberately: an alert that has been ignored
-- for an hour walks POLLING_UNIT → WARD → LGA → HQ over successive cycles, so
-- each tier is given a real chance to respond and each jump is separately
-- recorded, rather than teleporting straight to HQ with no audit trail.
CREATE OR REPLACE FUNCTION public.escalate_due_alerts()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row     RECORD;
  v_next    TEXT;
  v_count   INTEGER := 0;
BEGIN
  -- The seed above ships this 'false'; flip it to 'true' to start the engine.
  -- Note the fallback is 'true': if the row is missing entirely the engine
  -- runs, because an alert that silently stops escalating is the worse
  -- failure. Disable it by setting the value to 'false', not by deleting it.
  IF lower(coalesce((SELECT value FROM public.app_config WHERE key = 'escalation_enabled'), 'true')) <> 'true' THEN
    RAISE NOTICE '[ESCALATION] Engine disabled via app_config.escalation_enabled.';
    RETURN 0;
  END IF;

  FOR v_row IN
    SELECT a.id, a.assigned_tier
      FROM public.alerts a
     WHERE a.status = ANY (public.escalation_open_statuses())
       AND public.next_escalation_tier(a.assigned_tier) IS NOT NULL
       AND a.tier_entered_at <= now() - make_interval(
             mins => public.escalation_timeout_minutes(a.assigned_tier))
     ORDER BY a.tier_entered_at
     FOR UPDATE SKIP LOCKED
  LOOP
    v_next := public.next_escalation_tier(v_row.assigned_tier);
    IF v_next IS NULL THEN
      CONTINUE;
    END IF;

    IF public.apply_escalation(
         v_row.id, v_next,
         'SYSTEM_SLA_ENGINE', 'SYSTEM',
         'SLA threshold exceeded',
         format('No response at %s within %s minutes.',
                v_row.assigned_tier,
                public.escalation_timeout_minutes(v_row.assigned_tier)),
         'SLA_AUTO_ESCALATION', 'AUTO_ESCALATION')
    THEN
      v_count := v_count + 1;
    END IF;
  END LOOP;

  RETURN v_count;
END;
$$;

-- ─── 9. Response-SLA breach detection ────────────────────────────────────────
-- The surviving half of escalationWatchdog. A responder who has accepted an
-- incident but not reached the scene within the response SLA is flagged once,
-- and command is notified. This is separate from tier escalation: the incident
-- is being worked, it is just running late.
CREATE OR REPLACE FUNCTION public.detect_sla_breaches()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row   RECORD;
  v_sla   INT := public.escalation_config_int('escalation_response_sla', 15);
  v_count INTEGER := 0;
  v_since TIMESTAMPTZ;
BEGIN
  FOR v_row IN
    SELECT a.id, a.status, a.assigned_tier, a.geo_lga, a.geo_ward, a.geo_pu,
           coalesce(a.dispatched_at, a.acknowledged_at, a.created_at) AS started_at
      FROM public.alerts a
     WHERE a.sla_breached = FALSE
       AND a.status IN ('DISPATCHED', 'ACKNOWLEDGED', 'ON_ROUTE')
       AND coalesce(a.dispatched_at, a.acknowledged_at, a.created_at)
             <= now() - make_interval(mins => v_sla)
     FOR UPDATE SKIP LOCKED
  LOOP
    v_since := v_row.started_at;

    UPDATE public.alerts
       SET sla_breached    = TRUE,
           sla_breached_at = now(),
           updated_at      = now()
     WHERE id = v_row.id;

    INSERT INTO public.alert_timeline
      (alert_id, event_type, actor, actor_role, reason, notes, from_tier, to_tier)
    VALUES
      (v_row.id, 'SLA_BREACH_ALERT', 'SYSTEM_SLA_ENGINE', 'SYSTEM',
       'Responder did not reach the scene within the response threshold.',
       format('Incident has been %s since %s (%s minute SLA).',
              v_row.status, v_since, v_sla),
       v_row.assigned_tier, v_row.assigned_tier);

    INSERT INTO public.audit_logs
      (action, alert_id, actor, from_tier, to_tier, reason, detail)
    VALUES
      ('SLA_BREACH', v_row.id, 'SYSTEM_SLA_ENGINE',
       v_row.assigned_tier, v_row.assigned_tier,
       'Response SLA exceeded',
       jsonb_build_object('status', v_row.status, 'sla_minutes', v_sla, 'since', v_since));

    INSERT INTO public.notification_outbox
      (alert_id, target_tier, target_lga, target_ward, target_pu, title, body, payload)
    VALUES
      (v_row.id, v_row.assigned_tier, v_row.geo_lga, v_row.geo_ward, v_row.geo_pu,
       '⏱️ SLA RESPONSE BREACH',
       format('Incident %s has exceeded the %s-minute response SLA. Immediate review required.',
              upper(substring(v_row.id::TEXT, 1, 8)), v_sla),
       jsonb_build_object('alertId', v_row.id, 'type', 'SLA_BREACH', 'tier', v_row.assigned_tier));

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

-- ─── 10. One cycle ───────────────────────────────────────────────────────────
-- A session-level advisory lock keeps overlapping ticks (cron plus a manual
-- run, or a slow cycle still finishing) from processing the same alerts twice.
-- If the lock is held the cycle returns immediately rather than queueing.
CREATE OR REPLACE FUNCTION public.run_escalation_cycle()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_escalated INTEGER := 0;
  v_breached  INTEGER := 0;
BEGIN
  IF NOT pg_try_advisory_xact_lock(hashtext('rainbow.escalation_cycle')) THEN
    RETURN jsonb_build_object('skipped', TRUE, 'reason', 'cycle already running');
  END IF;

  v_escalated := public.escalate_due_alerts();
  v_breached  := public.detect_sla_breaches();

  -- Report the kill switch too: without it a disabled engine and a quiet
  -- minute both come back as escalated:0, which is the one thing an operator
  -- checking on a freshly applied migration needs to tell apart.
  RETURN jsonb_build_object(
    'skipped',   FALSE,
    'enabled',   lower(coalesce(
                   (SELECT value FROM public.app_config WHERE key = 'escalation_enabled'),
                   'true')) = 'true',
    'escalated', v_escalated,
    'breached',  v_breached,
    'ran_at',    now()
  );
END;
$$;

-- ─── 11. Manual escalation (replaces adminEscalateAlert) ─────────────────────
-- Callable over PostgREST as rpc/request_escalation. Authorisation is checked
-- here rather than in the client, so the rule holds for the mobile app, the HQ
-- dashboard and anything else that reaches the API.
CREATE OR REPLACE FUNCTION public.request_escalation(
  p_alert_id UUID,
  p_to_tier  TEXT,
  p_reason   TEXT DEFAULT NULL,
  p_notes    TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid    UUID := auth.uid();
  v_role   TEXT;
  v_email  TEXT;
  v_ok     BOOLEAN;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '28000';
  END IF;

  SELECT role, coalesce(email, id::TEXT) INTO v_role, v_email
    FROM public.profiles WHERE id = v_uid;

  IF NOT public.is_command() THEN
    RAISE EXCEPTION 'Only command staff may escalate an incident (role: %)',
      coalesce(v_role, 'unknown') USING ERRCODE = '42501';
  END IF;

  IF public.escalation_tier_rank(p_to_tier) = 0 THEN
    RAISE EXCEPTION 'Unknown tier: %', p_to_tier USING ERRCODE = '22023';
  END IF;

  v_ok := public.apply_escalation(
    p_alert_id, upper(p_to_tier),
    v_email, coalesce(v_role, 'RESPONDER'),
    coalesce(p_reason, 'Tactical escalation'),
    p_notes,
    'MANUAL_ESCALATION', 'MANUAL_ESCALATION');

  IF NOT v_ok THEN
    RETURN jsonb_build_object(
      'success', FALSE,
      'reason',  'Alert is closed, missing, or already at or above that tier.');
  END IF;

  RETURN jsonb_build_object('success', TRUE, 'alert_id', p_alert_id, 'tier', upper(p_to_tier));
END;
$$;

-- ─── 12. Status timestamps ───────────────────────────────────────────────────
-- detect_sla_breaches measures from dispatched_at / acknowledged_at, but no
-- client sets them. Stamping them here means the response SLA works without
-- every caller having to remember, and keeps the value honest.
CREATE OR REPLACE FUNCTION public.stamp_alert_status_times()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF NEW.status = 'DISPATCHED' AND NEW.dispatched_at IS NULL THEN
      NEW.dispatched_at := now();
    END IF;
    IF NEW.status IN ('ACKNOWLEDGED', 'ON_ROUTE') AND NEW.acknowledged_at IS NULL THEN
      NEW.acknowledged_at := now();
    END IF;
    IF NEW.status = 'RESOLVED' AND NEW.resolved_at IS NULL THEN
      NEW.resolved_at := now();
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_stamp_alert_status_times ON public.alerts;
CREATE TRIGGER trg_stamp_alert_status_times
  BEFORE UPDATE ON public.alerts
  FOR EACH ROW EXECUTE FUNCTION public.stamp_alert_status_times();

-- ─── 13. RLS ─────────────────────────────────────────────────────────────────
-- Writes happen only through the SECURITY DEFINER functions above or the
-- service role, which bypasses RLS — so, as everywhere else in this schema,
-- there are no service_role policies. Adding them would be redundant and would
-- put `USING (true)` rows in pg_policies, which the bootstrap check treats as a
-- regression on purpose.
ALTER TABLE public.alert_timeline      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_outbox ENABLE ROW LEVEL SECURITY;

-- A timeline is readable exactly when its incident is. The subquery runs as the
-- calling user, so the policies on `alerts` apply inside it — including the
-- oversight carve-out — and this policy never has to restate them.
DROP POLICY IF EXISTS "alert_timeline_read" ON public.alert_timeline;
CREATE POLICY "alert_timeline_read" ON public.alert_timeline
  FOR SELECT TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.alerts a WHERE a.id = alert_timeline.alert_id)
  );

-- The audit trail is command-only: it records who escalated what and when.
DROP POLICY IF EXISTS "audit_logs_read_command" ON public.audit_logs;
CREATE POLICY "audit_logs_read_command" ON public.audit_logs
  FOR SELECT TO authenticated USING (public.is_command());

-- The outbox is an internal work queue. No policy at all: only the worker, on
-- the service role, ever touches it.

GRANT SELECT ON public.alert_timeline TO authenticated;
GRANT SELECT ON public.audit_logs     TO authenticated;
GRANT ALL    ON public.alert_timeline, public.audit_logs, public.notification_outbox
  TO service_role;

-- Only request_escalation is client-callable. The sweep functions are operator
-- surface and stay off the anon/authenticated API.
REVOKE ALL ON FUNCTION public.apply_escalation(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.escalate_due_alerts()  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.detect_sla_breaches()  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.run_escalation_cycle() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.run_escalation_cycle() TO service_role;
GRANT EXECUTE ON FUNCTION public.escalate_due_alerts()  TO service_role;
GRANT EXECUTE ON FUNCTION public.detect_sla_breaches()  TO service_role;
GRANT EXECUTE ON FUNCTION public.request_escalation(UUID, TEXT, TEXT, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.next_escalation_tier(TEXT),
                          public.escalation_tier_rank(TEXT),
                          public.escalation_timeout_minutes(TEXT),
                          public.escalation_open_statuses()
  TO authenticated, service_role;

-- ─── 14. Backfill ────────────────────────────────────────────────────────────
-- Existing rows default to POLLING_UNIT with tier_entered_at = NOW(), which
-- would hand every historical alert a fresh SLA clock. Seed open alerts from
-- their creation time instead, and park closed ones so the sweep skips them.
UPDATE public.alerts
   SET tier_entered_at = coalesce(created_at, now())
 WHERE tier_entered_at > coalesce(created_at, now())
   AND status = ANY (public.escalation_open_statuses());

-- ─── 15. Scheduling ──────────────────────────────────────────────────────────
-- pg_cron is available on Supabase but is not enabled by default and cannot be
-- created from a plain migration on every plan, so this is best-effort: if the
-- extension is present the job is (re)scheduled, otherwise the migration still
-- succeeds and the escalation-worker edge function can be driven by any
-- external scheduler instead.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'pg_cron') THEN
    BEGIN
      CREATE EXTENSION IF NOT EXISTS pg_cron;
      PERFORM cron.unschedule('rainbow-escalation-cycle')
        WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'rainbow-escalation-cycle');
      PERFORM cron.schedule(
        'rainbow-escalation-cycle',
        '* * * * *',
        $cron$SELECT public.run_escalation_cycle();$cron$
      );
      RAISE NOTICE '[ESCALATION] pg_cron job scheduled every minute.';
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE '[ESCALATION] Could not schedule pg_cron (%). Drive the escalation-worker edge function externally instead.', SQLERRM;
    END;
  ELSE
    RAISE NOTICE '[ESCALATION] pg_cron unavailable. Drive the escalation-worker edge function externally.';
  END IF;
END $$;

SELECT 'Phase 6 escalation engine migration complete' AS result;
