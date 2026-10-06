#!/usr/bin/env python3
"""Generate scripts/apply_all_migrations.sql — every unapplied migration,
in order, as one paste, with a pass/fail readout at the end.

WHY THIS IS GENERATED RATHER THAN HAND-WRITTEN
----------------------------------------------
The same reason as scripts/rls_production_dryrun.sql: a file that gets pasted
into a production SQL editor must never drift from the migrations it claims to
contain. A stale copy is worse than no copy, because it looks authoritative.
`check_apply_all_fresh` in CI fails the build if this output does not match the
migration files byte for byte.

WHAT IT DOES NOT DO
-------------------
It does not replace the dry run. `20260813000000_rls_least_privilege.sql` drops
prior policies BY EXACT NAME, and a policy created by hand in the Supabase
dashboard survives it — PostgreSQL ORs permissive policies together, so one
survivor re-opens the table and the migration becomes decorative. Only
`scripts/rls_production_dryrun.sql`, run against the real database, can tell you
whether that is the case. Run it, read its verdict, and only then paste this.

Regenerate after any migration change:
    python3 scripts/build_apply_all.py
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "scripts/apply_all_migrations.sql"

# ── The outstanding migrations, DERIVED from the directory ──────────────────
#
# This used to be a hand-maintained list, and that is a trap rather than a
# chore. Adding a migration and running this generator produced no diff, no
# warning and a successful exit — while the script an operator pastes into
# production silently lacked the new file. The CI check only diffs this
# script's OUTPUT against the committed copy, so a migration that was never in
# the list was never in the diff either, and nothing anywhere said so.
#
# It is derived now, and the exclusion list lives in ONE place —
# scripts/migration_sets.py — because it existed in three copies here, in
# build_apply_in_parts.py and in build_bootstrap.py, and all three listed only
# the original four. When the v2–v5 era was written down as migration files on
# 2026-09-29, every generator silently pulled five already-applied files into
# the script an operator pastes into production, one of which calls auth.jwt()
# before that function exists and fails outright. See migration_sets.py.
import migration_sets  # noqa: E402  (sibling module; scripts/ is sys.path[0])

MIGRATIONS = migration_sets.outstanding()

HEADER = f"""-- ============================================================================
-- APPLY ALL OUTSTANDING MIGRATIONS — generated file, do not edit by hand.
--   Regenerate with: python3 scripts/build_apply_all.py
--
-- Paste the WHOLE of this file into the Supabase dashboard -> SQL Editor and
-- run it. It applies the {len(MIGRATIONS)} outstanding migrations in order and finishes by
-- SELECTing a pass/fail table, so one paste in gives you one answer out.
--
-- ---------------------------------------------------------------------------
-- RUN THE DRY RUN FIRST. THIS IS NOT OPTIONAL.
--
--   scripts/rls_production_dryrun.sql
--
-- 20260813000000_rls_least_privilege.sql drops prior policies BY EXACT NAME.
-- A policy somebody created by hand in the dashboard is not in that list, so it
-- survives — and PostgreSQL combines PERMISSIVE policies with OR, meaning one
-- surviving `USING (true)` re-opens the table and the migration becomes
-- decorative. That is exactly how phase1_foundation.sql already failed once.
-- The dry run is read-only, rolls everything back, and prints a verdict:
--
--   ===== RLS DRY RUN — >>> SAFE TO APPLY =====   -> paste this file
--   ===== RLS DRY RUN — >>> DO NOT APPLY =====    -> stop; it names the policy
-- ---------------------------------------------------------------------------
--
-- SAFE TO RE-RUN — but "idempotent" is not quite the right word, and the
-- difference shows up if you run this file twice.
--
-- Most of these migrations ARE idempotent: they use IF NOT EXISTS / OR REPLACE
-- and a second run changes nothing and says nothing.
--
-- `20260813000000_rls_least_privilege.sql` is ATOMIC instead. It drops the old
-- policy set by name and creates a new one, inside its own BEGIN/COMMIT, so it
-- applies completely or not at all. Running it a SECOND time therefore reports
--
--     ERROR: policy "profiles_select_self_or_staff" for table "profiles"
--            already exists
--
-- and rolls itself back. That message means THE POLICIES ARE ALREADY IN PLACE.
-- It is not a failure to fix, nothing is left half-applied, and the verification
-- at the end of this file will still report every row PASS. Read the verdict
-- table, not the error.
--
-- So: an interrupted run can simply be re-run, and the state you end up with is
-- correct either way.
--
-- Expect a few `NOTICE: skipping ...` lines. They are the guards that let these
-- files run against a database that does not have a given table yet.
-- ============================================================================

"""

VERIFY = f"""

-- ============================================================================
-- DID IT WORK?
--
-- One row per thing that had to be true. `result` is PASS or FAIL; nothing here
-- writes. If every row says PASS, the {len(MIGRATIONS)} migrations are applied.
--
-- These check BEHAVIOUR-ADJACENT FACTS, not just that statements ran: that anon
-- holds no policy at all, that the escalation columns exist (their absence made
-- every escalation fail in full), that the tier has its own column, and that the
-- realtime publication covers what both apps subscribe to.
-- ============================================================================

WITH checks(ord, name, ok) AS (
  VALUES
    -- Not a check: the stamp that says WHICH version of this script produced
    -- the output below. A pasted result used to carry nothing identifying its
    -- version, so a run from a stale working copy read exactly like a current
    -- one. Compare with: python3 scripts/migration_sets.py --fingerprint
    (0, 'script version: {len(MIGRATIONS)} outstanding migrations, '
        'fingerprint {migration_sets.fingerprint(MIGRATIONS)}', true),
    (1, 'agency tables exist (4)',
        (SELECT count(*) = 4 FROM information_schema.tables
          WHERE table_schema = 'public'
            AND table_name IN ('agency_personnel','agency_deployments',
                               'agency_action_reports','agency_notifications'))),
    (2, 'no policy grants anon or public anything'
          || coalesce(' — ' || (SELECT string_agg(tablename || '.' || policyname, ', '
                                                  ORDER BY tablename, policyname)
                                  FROM pg_policies
                                 WHERE schemaname = 'public'
                                   AND ('anon' = ANY(roles) OR 'public' = ANY(roles))), ''),
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
    -- Asserted on the POLICY'S CONDITION, not on its name. This check used to
    -- name `telemetry_select_self_or_responding_staff`, and a later migration
    -- that renamed the policy while keeping the behaviour broke the check and
    -- proved nothing about the database. What has to stay true is that a
    -- position is tied to an OPEN incident — so the clause has to mention the
    -- alerts table and exclude a resolved one.
    (19, 'a citizen''s position is not a standing staff feed',
        (SELECT count(*) = 1 FROM pg_policies
          WHERE schemaname = 'public' AND tablename = 'telemetry'
            AND cmd = 'SELECT'
            AND qual LIKE '%alerts%'
            AND qual LIKE '%RESOLVED%')),
    (20, 'stale positions are purged, and only by the service role',
        (SELECT NOT has_function_privilege('authenticated',
                  'public.purge_stale_telemetry()', 'EXECUTE')
           FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'purge_stale_telemetry')),
    (21, 'chat writes are restricted to a participant of the thread',
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
          WHERE oid = 'public.mesh_envelopes_seen'::regclass)),
    -- A handset whose SIM has gone can no longer be reached by SMS, and the
    -- alert queue keeps queueing with nowhere to go. HQ is told.
    (26, 'a handset can report that its SMS channel changed',
        (SELECT to_regclass('public.sim_channel_events') IS NOT NULL)),
    -- And that report must not be readable by every staff account. A
    -- polling-unit officer, and every agency liaison, are staff; neither has a
    -- reason to see which citizens changed SIM. This is the same mistake the
    -- telemetry work was written to undo.
    (27, 'SIM reports are limited to command, not all staff',
        (SELECT relrowsecurity
            AND EXISTS (SELECT 1 FROM pg_policies
                         WHERE schemaname = 'public'
                           AND tablename = 'sim_channel_events'
                           AND policyname = 'sim_events_select_self_or_command')
           FROM pg_class
          WHERE oid = 'public.sim_channel_events'::regclass)),
    -- There is no column for a position on that table, and there must not be:
    -- with one it stops being a channel board and becomes a movement log on
    -- private citizens.
    (28, 'SIM reports carry no position',
        (SELECT count(*) = 0 FROM information_schema.columns
          WHERE table_schema = 'public'
            AND table_name = 'sim_channel_events'
            AND column_name IN ('latitude','longitude','lat','lng','location'))),
    -- An agency liaison is an officer of ANOTHER organisation. is_staff() is
    -- "role is not CITIZEN", so they were staff — and the alerts policies were
    -- "... OR is_staff()". Every liaison could read AND WRITE every incident
    -- in Plateau.
    (29, 'a liaison is recognised as an outside agency',
        (SELECT EXISTS (SELECT 1 FROM pg_proc p
                          JOIN pg_namespace n ON n.oid = p.pronamespace
                         WHERE n.nspname = 'public' AND p.proname = 'is_liaison'))),
    (30, 'the statewide alert policies no longer rest on is_staff alone',
        (SELECT NOT EXISTS (SELECT 1 FROM pg_policies
                             WHERE schemaname = 'public'
                               AND tablename = 'alerts'
                               AND policyname IN ('alerts_select_own_or_staff',
                                                  'alerts_update_own_or_staff'))
            AND EXISTS (SELECT 1 FROM pg_policies
                         WHERE schemaname = 'public'
                           AND tablename = 'alerts'
                           AND policyname = 'alerts_select_own_or_ours'))),
    -- An SOS started a track and the database kept only the latest point, so
    -- the trail lived in one browser tab's memory: a refresh lost it, and
    -- anybody reviewing the incident afterwards saw no movement at all.
    (31, 'the route taken during an incident is kept',
        (SELECT to_regclass('public.incident_tracks') IS NOT NULL)),
    -- And it expires, which is the whole reason keeping it does not undo the
    -- work that made location borrowed rather than kept.
    (32, 'routes expire, and only the service role can expire them',
        (SELECT NOT has_function_privilege('authenticated',
                  'public.purge_stale_incident_tracks()', 'EXECUTE')
           FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'purge_stale_incident_tracks')),
    -- A route is a record. One that can be rewritten is worth less than none,
    -- because it can be made to say something else.
    (33, 'a route cannot be rewritten or deleted through the API',
        (SELECT NOT EXISTS (SELECT 1 FROM pg_policies
                             WHERE schemaname = 'public'
                               AND tablename = 'incident_tracks'
                               AND cmd IN ('UPDATE', 'DELETE'))))
)
SELECT
  CASE WHEN ok THEN 'PASS' ELSE '*** FAIL ***' END AS result,
  name
FROM checks
ORDER BY ok, ord;
"""


# The rule and the reasoning now live in scripts/label_guard.py, because
# bootstrap_staging.sql and scripts/apply_in_parts/ are pasted into the same
# editor and this guard covered only this one file.
from label_guard import check_labels  # noqa: E402


def main() -> int:
    parts = [HEADER]
    for filename in MIGRATIONS:
        path = ROOT / "supabase/migrations" / filename
        if not path.exists():
            print(f"missing migration: {filename}", file=sys.stderr)
            return 1
        banner = "-" * 76
        parts.append(
            f"-- {banner}\n"
            f"-- {filename}\n"
            f"-- {banner}\n"
            f"DO $apply$ BEGIN RAISE NOTICE 'applying {filename}'; END $apply$;\n\n"
        )
        parts.append(path.read_text().rstrip() + "\n\n")
    parts.append(VERIFY)

    check_labels(VERIFY)
    OUT.write_text("".join(parts))
    print(f"wrote {OUT.relative_to(ROOT)} "
          f"({len(MIGRATIONS)} migrations, {OUT.read_text().count(chr(10))} lines)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
