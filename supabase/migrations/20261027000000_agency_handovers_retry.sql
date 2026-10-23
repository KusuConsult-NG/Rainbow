-- ============================================================================
-- A failed handover to an outside agency now gets retried
--
-- `20260722000000_v3_telemetry_geofence.sql` creates
--
--     idx_agency_notifications_status … WHERE status = 'FAILED'
--
-- and its comment says "(retry jobs)". There is no retry job. The index has
-- been waiting for one since July.
--
-- `agency_notifications` is the record of handing an incident to the Police or
-- the Army: the leg, the method, whether it went. When a leg fails, the row
-- says FAILED and nothing tries again. The failure IS visible to HQ on the
-- incident replay, which is the difference between a silent failure and a known
-- one — somebody can pick up a phone. But an emergency handed to an agency
-- whose channel was briefly down stays handed to nobody until a person notices.
--
-- ## What this does NOT decide
--
-- E2E_AUDIT_REPORT.md named this as "a piece of work with real decisions in it
-- (how many times do you re-send an SMS about an emergency, and to whom does it
-- escalate when the agency's own channel is down), not a line of code" — and
-- said the right move was "to drain these the way `notification_outbox` is
-- drained, with the same backoff and the same `attempts` column, rather than to
-- invent a second mechanism".
--
-- So nothing here is a new policy. Every decision is the one
-- `20261007000000_notification_outbox.sql` already made for the same question:
--
--   * claim with FOR UPDATE SKIP LOCKED, holding the row a minute, so a worker
--     that dies mid-send does not have the row taken again on the next tick;
--   * on failure, back off `attempts * 2` minutes, capped at 60;
--   * no maximum attempt count. An unreachable agency is retried hourly for as
--     long as the incident is open rather than abandoned — which is the outbox's
--     existing answer, and the safer one for an emergency. The row's
--     `attempts` and `last_error` are what tell HQ it is not getting through.
--
-- Escalation when a channel stays down is still a person reading the replay.
-- That is unchanged and deliberate: this migration makes the machine stop
-- giving up, it does not invent a second human to call.
--
-- ## Idempotent
--
-- Columns are ADD COLUMN IF NOT EXISTS; functions are CREATE OR REPLACE. Safe
-- to paste twice, which `verify_rls_migration.sh` does.
-- ============================================================================

-- ── 1. The three columns the outbox uses, and this table lacked ─────────────
ALTER TABLE public.agency_notifications
  ADD COLUMN IF NOT EXISTS attempts        INTEGER     NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS last_error      TEXT;

COMMENT ON COLUMN public.agency_notifications.attempts IS
  'How many times this leg has been attempted. Mirrors '
  'notification_outbox.attempts; drives the same backoff.';
COMMENT ON COLUMN public.agency_notifications.next_attempt_at IS
  'When this leg may be attempted again. NOW() by default so an existing '
  'FAILED row becomes due immediately on first drain rather than never.';
COMMENT ON COLUMN public.agency_notifications.last_error IS
  'Why the last attempt failed, truncated to 500 characters. What HQ reads on '
  'the incident replay to decide whether to pick up a phone.';

-- The index the retry actually needs. The 2026-07 one is on `status` alone,
-- which finds the failures and not the DUE ones.
CREATE INDEX IF NOT EXISTS idx_agency_notifications_due
  ON public.agency_notifications (next_attempt_at)
  WHERE status = 'FAILED';

-- ── 1b. `sent_at` has to mean what it says ─────────────────────────────────
--
-- Found by exercising the claim loop below, which returned nothing. The filter
-- was `sent_at IS NULL`, and `sent_at` can never be null:
--
--     sent_at TIMESTAMPTZ NOT NULL DEFAULT NOW()   -- 20260812000000
--
-- So the column records when the ROW WAS CREATED, not when the leg was sent. A
-- handover to the Police that failed, or was skipped, or has not been attempted
-- carries a send time anyway — and HQ reads that on the incident replay as a
-- delivery that happened. A timestamp that looks measured and is a default, in
-- the record of whether an emergency reached an outside agency. Same family as
-- C-5 and T-84, in a time column instead of a coordinate.
--
-- The default and the NOT NULL go, so an unsent leg has no send time. Legs
-- already marked FAILED are nulled, because that is the one case where the
-- truth is known: they were not sent. SENT and SKIPPED rows are left alone —
-- their value may be a default or may be real and nothing here can tell, and
-- inventing a null would be the same mistake with the opposite sign.
ALTER TABLE public.agency_notifications
  ALTER COLUMN sent_at DROP DEFAULT,
  ALTER COLUMN sent_at DROP NOT NULL;

UPDATE public.agency_notifications
   SET sent_at = NULL
 WHERE status = 'FAILED'
   AND sent_at IS NOT NULL;

COMMENT ON COLUMN public.agency_notifications.sent_at IS
  'When this leg actually went, or NULL when it has not. Was NOT NULL DEFAULT '
  'NOW(), which made it the row creation time and reported every failed '
  'handover as delivered. Set only by mark_agency_handover_sent. See T-89.';

-- ── 2. Claim, mark sent, mark failed — the outbox's three, same shapes ──────
CREATE OR REPLACE FUNCTION public.claim_agency_handovers(p_limit INTEGER DEFAULT 20)
RETURNS SETOF public.agency_notifications
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN QUERY
  WITH due AS (
    SELECT n.id
      FROM public.agency_notifications n
     WHERE n.status = 'FAILED'
       AND n.sent_at IS NULL
       AND n.next_attempt_at <= NOW()
     ORDER BY n.next_attempt_at
     LIMIT GREATEST(COALESCE(p_limit, 20), 1)
     FOR UPDATE SKIP LOCKED
  )
  UPDATE public.agency_notifications n
     SET attempts = n.attempts + 1,
         -- Held a minute on claim, exactly as claim_notifications does, so a
         -- worker that dies mid-send returns the row to the queue by itself.
         next_attempt_at = NOW() + INTERVAL '1 minute'
    FROM due
   WHERE n.id = due.id
  RETURNING n.*;
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_agency_handover_sent(p_id UUID)
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  UPDATE public.agency_notifications
     SET status = 'SENT', sent_at = NOW(), last_error = NULL
   WHERE id = p_id;
$$;

CREATE OR REPLACE FUNCTION public.mark_agency_handover_failed(p_id UUID, p_error TEXT)
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  UPDATE public.agency_notifications
     SET status = 'FAILED',
         last_error = left(COALESCE(p_error, 'unknown'), 500),
         -- The outbox's backoff, unchanged: attempts * 2 minutes, capped at an
         -- hour. No give-up count, because the thing not getting through is an
         -- emergency handed to the Police.
         next_attempt_at = NOW() + make_interval(
           mins => LEAST(GREATEST(attempts, 1) * 2, 60))
   WHERE id = p_id;
$$;

-- ── 3. Only the service role drains a queue ─────────────────────────────────
REVOKE ALL ON FUNCTION public.claim_agency_handovers(INTEGER)        FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.mark_agency_handover_sent(UUID)        FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.mark_agency_handover_failed(UUID, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_agency_handovers(INTEGER)        TO service_role;
GRANT EXECUTE ON FUNCTION public.mark_agency_handover_sent(UUID)        TO service_role;
GRANT EXECUTE ON FUNCTION public.mark_agency_handover_failed(UUID, TEXT) TO service_role;

COMMENT ON FUNCTION public.claim_agency_handovers(INTEGER) IS
  'Claims failed agency handover legs that are due, holding each for a minute. '
  'Same shape and same backoff as claim_notifications: the index from 2026-07 '
  'said "(retry jobs)" and there was no retry job. See T-89.';
