-- ============================================================================
-- STEP 1 of 2 — RLS POLICY INVENTORY.  READ ONLY.  Generated file, do not edit.
--   Regenerate with: python3 scripts/build_rls_inventory.py
--
--   Paste into the Supabase dashboard -> SQL Editor and run. It is one SELECT.
--   It changes nothing, writes nothing, and takes no locks.
--
-- WHY THIS IS SEPARATE FROM THE DRY RUN
--
-- The Supabase SQL Editor shows the result of the LAST row-returning statement
-- and does not surface `RAISE NOTICE` output at all. The first version of the
-- dry run reported everything through NOTICE, so the operator saw one summary
-- row and none of the findings. Anything that must be read has to come back as
-- a result set, and only one of them survives — hence two separate scripts.
--
-- WHAT IT IS FOR
--
-- 20260813000000_rls_least_privilege.sql drops prior policies BY EXACT NAME,
-- from a list built by reading this repo's migration files. A policy created by
-- hand in the dashboard is not in that list, so the migration leaves it in
-- place — and because PostgreSQL combines PERMISSIVE policies with OR, one
-- surviving `USING (true)` re-opens the table and the migration becomes
-- decorative. That is exactly how phase1_foundation.sql already failed once.
--
-- HOW TO READ IT
--
-- `source` is the column that matters. Every `NOT-IN-REPO` row is a policy this
-- repository does not create and the migration will not drop; each has to be
-- accounted for before applying. `reach` separates the two very different kinds
-- of `USING (true)`: one granted to anon/public is an open door, one granted
-- only to `authenticated` is not (the migration deliberately creates one such
-- policy on app_config).
--
-- Send the whole result back.
-- ============================================================================

WITH known(policyname) AS (
  SELECT unnest(ARRAY[
    'Allow authenticated users to insert alerts',
    'Allow authenticated users to read alerts',
    'Allow authenticated users to update alerts',
    'Allow individual insert/update to own profile',
    'Allow inserting chat messages',
    'Allow public read access to profiles',
    'Allow reading chat messages',
    'Allow reading system alerts',
    'Allow reading telemetry',
    'Allow service role to manage system alerts',
    'Allow users to update own telemetry',
    'agency_action_reports_command_write',
    'agency_action_reports_liaison_read',
    'agency_action_reports_liaison_write',
    'agency_action_reports_staff_read',
    'agency_deployments_command_write',
    'agency_deployments_liaison_read',
    'agency_deployments_liaison_write',
    'agency_deployments_read',
    'agency_deployments_staff_read',
    'agency_deployments_write',
    'agency_notifications_command_read',
    'agency_notifications_command_write',
    'agency_notifications_insert',
    'agency_notifications_read',
    'agency_personnel_command_write',
    'agency_personnel_liaison_read',
    'agency_personnel_liaison_write',
    'agency_personnel_read',
    'agency_personnel_staff_read',
    'agency_personnel_write',
    'agency_reports_read',
    'agency_reports_write',
    'alert_timeline_read',
    'alerts_delete_hq_only',
    'alerts_insert_as_self',
    'alerts_insert_authenticated',
    'alerts_read_authenticated',
    'alerts_select_own',
    'alerts_select_own_or_staff',
    'alerts_select_responders',
    'alerts_update_authenticated',
    'alerts_update_own_or_staff',
    'alerts_update_responders_only',
    'app_config_read',
    'app_config_read_authenticated',
    'app_config_write_service_role',
    'audit_logs_read_command',
    'chat_insert',
    'chat_insert_as_self',
    'chat_insert_authenticated',
    'chat_read',
    'chat_read_authenticated',
    'chat_select_own_alerts',
    'chat_select_participant_or_staff',
    'chat_select_responders',
    'incident_media_staff_list',
    'incident_media_upload',
    'profiles_delete_hq',
    'profiles_insert_own',
    'profiles_insert_self',
    'profiles_read_all',
    'profiles_select_own',
    'profiles_select_responders',
    'profiles_select_self_or_staff',
    'profiles_update_own',
    'profiles_update_self',
    'profiles_write_own',
    'safe_zones_read',
    'safe_zones_write_command',
    'sysalerts_read_authenticated',
    'sysalerts_write_hq',
    'system_alerts_delete_command',
    'system_alerts_manage_hq',
    'system_alerts_read',
    'system_alerts_select_all_authenticated',
    'system_alerts_update_command',
    'system_alerts_write_command',
    'telemetry_history_read',
    'telemetry_insert_own',
    'telemetry_own_upsert',
    'telemetry_read_all',
    'telemetry_read_authenticated',
    'telemetry_select_responders',
    'telemetry_select_self_or_staff',
    'telemetry_update_own',
    'telemetry_upsert_own',
    'telemetry_write_own',
    'uninstall_insert',
    'uninstall_insert_own',
    'uninstall_read',
    'uninstall_read_own_or_staff',
    'uninstall_update_command'
  ]::text[])
)
SELECT
  p.tablename,
  p.policyname,
  p.cmd,
  p.roles::text AS granted_to,
  CASE
    WHEN (p.qual = 'true' OR p.with_check = 'true')
         AND ('anon' = ANY(p.roles) OR 'public' = ANY(p.roles))
      THEN '*** OPEN TO ANON ***'
    WHEN (p.qual = 'true' OR p.with_check = 'true')
      THEN 'permissive (authenticated only)'
    ELSE 'scoped'
  END AS reach,
  CASE WHEN k.policyname IS NULL
       THEN '*** NOT-IN-REPO — hand created ***'
       ELSE 'in repo'
  END AS source,
  p.qual,
  p.with_check
FROM pg_policies p
LEFT JOIN known k ON k.policyname = p.policyname
WHERE p.schemaname = 'public'
ORDER BY
  (k.policyname IS NULL) DESC,
  ((p.qual = 'true' OR p.with_check = 'true')
     AND ('anon' = ANY(p.roles) OR 'public' = ANY(p.roles))) DESC,
  (p.qual = 'true' OR p.with_check = 'true') DESC,
  p.tablename,
  p.policyname;
