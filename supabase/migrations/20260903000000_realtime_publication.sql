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
