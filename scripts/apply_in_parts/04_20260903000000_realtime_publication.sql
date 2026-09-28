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
-- 20260903000000_realtime_publication.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20260903000000_realtime_publication.sql'; END $apply$;

-- ============================================================================
-- OPERATION RAINBOW — REALTIME PUBLICATION
--
-- The HQ console subscribes to postgres_changes on three tables that were never
-- added to the supabase_realtime publication by any migration:
--
--   agency_action_reports   dashboard unread-report badge, agency portal
--   agency_deployments      agency portal
--   uninstall_requests      uninstall-request queue
--
-- A subscription on a table outside the publication does not error. It simply
-- never fires, so the badge and the portal only refresh on page reload. On the
-- dashboard the unread-report count is what tells HQ an agency has filed an
-- after-action report; silently stale is the worst kind of wrong for it.
--
-- Idempotent: each table is added only if present and not already published.
-- ALTER PUBLICATION ... ADD TABLE raises if the table is already a member, and
-- the initial schema added the first five tables unconditionally, so this must
-- check pg_publication_tables rather than repeat that pattern.
-- ============================================================================

DO $realtime$
DECLARE
  t TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    RAISE NOTICE 'no supabase_realtime publication in this database; nothing to do';
    RETURN;
  END IF;

  FOREACH t IN ARRAY ARRAY[
    'alerts', 'telemetry', 'chat_messages', 'system_alerts', 'profiles',
    'agency_action_reports', 'agency_deployments', 'uninstall_requests'
  ] LOOP
    IF to_regclass('public.' || t) IS NULL THEN
      RAISE NOTICE 'skipping %: table not present in this database', t;
      CONTINUE;
    END IF;
    IF EXISTS (
      SELECT 1 FROM pg_publication_tables
       WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = t
    ) THEN
      CONTINUE;
    END IF;
    EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
    RAISE NOTICE 'added % to supabase_realtime', t;
  END LOOP;
END $realtime$;

