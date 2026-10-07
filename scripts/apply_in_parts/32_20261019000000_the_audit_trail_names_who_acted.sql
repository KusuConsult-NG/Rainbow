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
-- 20261019000000_the_audit_trail_names_who_acted.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261019000000_the_audit_trail_names_who_acted.sql'; END $apply$;

-- ============================================================================
-- OPERATION RAINBOW — THE AUDIT TRAIL NAMES WHO ACTED
--
-- `audit_trail()` reads the actor out of each escalation_log entry as
--
--     coalesce(nullif(e.entry ->> 'by', ''), 'SYSTEM')
--
-- and NOTHING A PERSON DOES WRITES 'by'.
--
--   writer                                        key          actor shown
--   ------------------------------------------    ----------   -----------
--   escalate_overdue_alerts()  (the timeout job)  'by'         SYSTEM      ✓
--   the notification outbox trigger               'by'         SYSTEM      ✓
--   confirm_ussd_report() / mark_false_report()   'by'         the uuid    ✓
--   alert-actions.ts escalateAlert  (HQ console)  'by_email'   SYSTEM      ✗
--   agent_dashboard_screen.dart     (a handset)   'by_email'   SYSTEM      ✗
--
-- So the audit trail inverted responsibility. Every escalation an officer
-- performed — from the HQ console or from their own handset — was attributed to
-- the system, and the only accurate attributions in the list were the machine's
-- own. On a screen whose entire purpose is to say who did what, that is worse
-- than showing nothing: a reader cannot tell an automatic timeout from a
-- commander's decision, and the commander's decision is the one somebody will
-- later be asked to account for.
--
-- The column comment on `alerts.escalation_log`, written in 20260722000000, has
-- said `by_email` since the beginning:
--
--     'Append-only structured log: [{from_tier, to_tier, to_officer_id,
--      to_officer_name, reason, notes, by_email, at}]'
--
-- so the reader is what disagreed with the documented shape, not the writers.
--
-- WHY THIS IS NOT FIXED BY CHANGING THE WRITERS
--
-- Production holds entries of both shapes, written over this schema's whole
-- life, and the log is append-only: a chain of custody that is rewritten is not
-- one. Both keys therefore have to be readable, forever. `by` is tried first so
-- the SQL writers' explicit value keeps precedence.
--
-- WHY THE BEHAVIOUR TEST DID NOT CATCH IT
--
-- `scripts/oversight_behaviour_test.sql` plants its fixture entry as
-- `{"from_tier":"UNIT","to_tier":"WARD","reason":"TIMEOUT","by":"SYSTEM",…}` —
-- the machine's shape, the one key that worked. It asserted the action and the
-- tiers and never the actor. Both shapes are now planted and the actor is
-- asserted for each.
--
-- Idempotent: CREATE OR REPLACE, no data is touched.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.audit_trail(p_limit INTEGER DEFAULT 100)
RETURNS TABLE (
  alert_id   UUID,
  reference  TEXT,
  incident   TEXT,
  at         TIMESTAMPTZ,
  action     TEXT,
  actor      TEXT,
  detail     TEXT
)
LANGUAGE sql
SECURITY INVOKER
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT a.id,
         coalesce(a.public_reference, left(a.id::text, 8)),
         a.type,
         -- Entries have been written with two different key names over this
         -- schema's life ('at' as a formatted string, and an ISO timestamp), and
         -- a row whose timestamp cannot be parsed must still appear — an audit
         -- entry dropped for a formatting reason is the worst possible thing for
         -- this list to do quietly. Falls back to the incident's own time.
         coalesce(
           nullif(e.entry ->> 'at', '')::timestamptz,
           a.updated_at,
           a.created_at
         ),
         upper(coalesce(
           nullif(e.entry ->> 'action', ''),
           -- A tier move has no 'action' key; it is identified by carrying a
           -- from_tier. Without this, every automatic escalation in the system
           -- would read as 'UNKNOWN'.
           CASE WHEN e.entry ? 'from_tier' THEN 'ESCALATED' END,
           'UPDATED'
         )),
         -- WHO. `by` is what the SQL writers set, explicitly, to 'SYSTEM' or to
         -- auth.uid(); `by_email` is what both apps set, and is the key the
         -- column's own comment has always documented. Reading only the first
         -- attributed every human action to the system — see the header.
         coalesce(
           nullif(e.entry ->> 'by', ''),
           nullif(e.entry ->> 'by_email', ''),
           'SYSTEM'
         ),
         -- For a tier move, BOTH the tiers and the reason. The first version
         -- coalesced the reason first, so an automatic escalation read simply
         -- "TIMEOUT" — the word without the movement, which is the half that
         -- tells a reader nothing. Where an incident WENT is the point of the
         -- entry; why is the qualifier.
         CASE
           WHEN e.entry ? 'from_tier' THEN
             (e.entry ->> 'from_tier') || ' → ' || (e.entry ->> 'to_tier')
             || coalesce(' (' || nullif(e.entry ->> 'reason', '') || ')', '')
           ELSE coalesce(nullif(e.entry ->> 'reason', ''), '')
         END
    FROM public.alerts a
    CROSS JOIN LATERAL jsonb_array_elements(
           CASE WHEN jsonb_typeof(a.escalation_log) = 'array'
                THEN a.escalation_log ELSE '[]'::jsonb END
         ) AS e(entry)
   ORDER BY 4 DESC
   LIMIT greatest(1, least(coalesce(p_limit, 100), 500));
$$;

COMMENT ON FUNCTION public.audit_trail(INTEGER) IS
  'What was actually DONE to incidents, flattened out of alerts.escalation_log. '
  'The console previously showed chat_messages under this heading, which '
  'contained no action anybody had taken. SECURITY INVOKER so alert_is_ours() '
  'scopes it — including keeping oversight matters out of it. The actor is read '
  'from `by` then `by_email`: the SQL writers set the first, both apps set the '
  'second, and reading only `by` attributed every human action to SYSTEM.';



