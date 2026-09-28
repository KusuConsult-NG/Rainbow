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
-- Nothing is half-applied, and part 15 will still report every row PASS. If you
-- are unsure whether a part landed, run part 15 — it writes nothing and tells
-- you the truth about the whole set.
--
-- The LAST part writes nothing. It returns one row per thing that had to be
-- true, and every one of them must read PASS.
--
-- If you can paste the whole of apply_all_migrations.sql in one go, do that
-- instead: one paste cannot be run out of order or stopped halfway by accident.
--

-- ============================================================================
-- DID IT WORK?
--
-- One row per thing that had to be true. `result` is PASS or FAIL; nothing here
-- writes. If every row says PASS, the 14 migrations are applied.
--
-- These check BEHAVIOUR-ADJACENT FACTS, not just that statements ran: that anon
-- holds no policy at all, that the escalation columns exist (their absence made
-- every escalation fail in full), that the tier has its own column, and that the
-- realtime publication covers what both apps subscribe to.
-- ============================================================================

WITH checks(ord, name, ok) AS (
  VALUES
    (1, 'agency tables exist (4)',
        (SELECT count(*) = 4 FROM information_schema.tables
          WHERE table_schema = 'public'
            AND table_name IN ('agency_personnel','agency_deployments',
                               'agency_action_reports','agency_notifications'))),
    (2, 'no policy grants anon or public anything',
        (SELECT count(*) = 0 FROM pg_policies
          WHERE schemaname = 'public'
            AND ('anon' = ANY(roles) OR 'public' = ANY(roles)))),
    (3, 'role-escalation trigger installed',
        (SELECT count(*) = 1 FROM pg_trigger
          WHERE tgname = 'profiles_no_privilege_escalation')),
    (4, 'emergency PIN functions exist (4)',
        (SELECT count(*) = 4 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public'
            AND p.proname IN ('set_emergency_pins','has_emergency_pins',
                              'verify_emergency_pin','resolve_emergency'))),
    (5, 'PIN hashes unreadable by the API roles',
        (SELECT count(*) = 0 FROM information_schema.role_table_grants
          WHERE table_schema = 'public' AND table_name = 'emergency_pins'
            AND grantee IN ('anon','authenticated'))),
    (6, 'realtime publication covers all 8 subscribed tables',
        (SELECT count(*) = 8 FROM pg_publication_tables
          WHERE pubname = 'supabase_realtime' AND schemaname = 'public'
            AND tablename IN ('alerts','telemetry','chat_messages','system_alerts',
                              'profiles','agency_action_reports',
                              'agency_deployments','uninstall_requests'))),
    (7, 'incident-media bucket configured',
        (SELECT count(*) = 1 FROM storage.buckets
          WHERE id = 'incident-media' AND public
            AND file_size_limit = 52428800)),
    (8, 'incident media is append-only (no UPDATE/DELETE policy)',
        (SELECT count(*) = 0 FROM pg_policies
          WHERE schemaname = 'storage' AND tablename = 'objects'
            AND policyname LIKE 'incident_media%' AND cmd IN ('UPDATE','DELETE'))),
    (9, 'broadcast scoping columns exist (6)',
        (SELECT count(*) = 6 FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'system_alerts'
            AND column_name IN ('target_audience','target_agency','target_lga',
                                'target_ward','target_pu','expires_at'))),
    (10, 'system_alerts.title has a default, so a broadcast cannot fail on it',
        (SELECT column_default IS NOT NULL FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'system_alerts'
            AND column_name = 'title')),
    (11, 'escalation columns exist',
        (SELECT count(*) = 2 FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'alerts'
            AND column_name IN ('escalated_to_agency','escalation_log'))),
    (12, 'profiles.badge_number exists',
        (SELECT count(*) = 1 FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'profiles'
            AND column_name = 'badge_number')),
    (13, 'alerts.assigned_tier exists',
        (SELECT count(*) = 1 FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'alerts'
            AND column_name = 'assigned_tier')),
    (14, 'no tier label left in the agency column',
        (SELECT count(*) = 0 FROM public.alerts
          WHERE escalated_to_agency IN ('POLLING_UNIT','PU','WARD','LGA','HQ'))),
    -- The signup path must not read a role out of client-supplied metadata.
    -- Anyone holding the anon key could otherwise enrol themselves as
    -- HQ_COMMAND, and every policy in the system trusts profiles.role.
    (15, 'a signup cannot choose its own role',
        (SELECT pg_get_functiondef(p.oid) NOT LIKE '%raw_user_meta_data->>''role''%'
           FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'handle_new_user')),
    -- The chain: an alert must land at the PU, and the timeouts that were
    -- configured and dead must now be enforced by something.
    (16, 'new alerts land at the polling unit',
        (SELECT column_default LIKE '%UNIT%' FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'alerts'
            AND column_name = 'assigned_tier')),
    (17, 'the escalation job exists and is service-role only',
        (SELECT NOT has_function_privilege('authenticated',
                  'public.escalate_overdue_alerts()', 'EXECUTE')
           FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'escalate_overdue_alerts')),
    (18, 'the chain terminates at HQ',
        (SELECT public.next_tier('HQ') IS NULL AND public.next_tier('UNIT') = 'WARD')),
    -- Location is borrowed, not kept. A citizen's position must stop being
    -- readable by staff once their emergency closes, nothing may be kept
    -- forever, and a message must not be injectable into somebody else's
    -- channel.
    (19, 'a citizen''s position is not a standing staff feed',
        EXISTS (SELECT 1 FROM pg_policies
                 WHERE schemaname = 'public' AND tablename = 'telemetry'
                   AND policyname = 'telemetry_select_self_or_responding_staff')),
    (20, 'stale positions are purged, and only by the service role',
        (SELECT NOT has_function_privilege('authenticated',
                  'public.purge_stale_telemetry()', 'EXECUTE')
           FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'purge_stale_telemetry')),
    (21, 'a message can only be written into your own channel',
        EXISTS (SELECT 1 FROM pg_policies
                 WHERE schemaname = 'public' AND tablename = 'chat_messages'
                   AND policyname = 'chat_insert_participant')),
    -- The SMS fallback's per-device key. It can both decrypt and forge that
    -- citizen's emergency traffic, so nothing but the service role may reach
    -- it, and the table must not be selectable at all.
    (22, 'SMS device keys exist and are unreadable through the API',
        (SELECT relrowsecurity FROM pg_class
          WHERE oid = 'public.sms_device_keys'::regclass)
        AND NOT EXISTS (SELECT 1 FROM pg_policies
                         WHERE schemaname = 'public'
                           AND tablename = 'sms_device_keys')),
    (23, 'only the service role can resolve an SMS key for ingest',
        (SELECT NOT has_function_privilege('authenticated',
                  'public.sms_key_for_ingest(bytea)', 'EXECUTE')
           FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'sms_key_for_ingest')),
    -- Without this, one mesh alert flooded by several relays becomes several
    -- incidents and several units sent to one place.
    (24, 'the mesh can recognise the same envelope arriving twice',
        (SELECT to_regclass('public.mesh_envelopes_seen') IS NOT NULL
            AND EXISTS (SELECT 1 FROM pg_proc p
                          JOIN pg_namespace n ON n.oid = p.pronamespace
                         WHERE n.nspname = 'public'
                           AND p.proname = 'mesh_note_envelope'))),
    -- And it must not become a record of which handset carried whose emergency.
    (25, 'mesh traffic is not readable through the API',
        (SELECT relrowsecurity
            AND NOT EXISTS (SELECT 1 FROM pg_policies
                             WHERE schemaname = 'public'
                               AND tablename = 'mesh_envelopes_seen')
           FROM pg_class
          WHERE oid = 'public.mesh_envelopes_seen'::regclass))
)
SELECT
  CASE WHEN ok THEN 'PASS' ELSE '*** FAIL ***' END AS result,
  name
FROM checks
ORDER BY ok, ord;
