#!/usr/bin/env python3
"""Generate scripts/apply_all_migrations.sql — the nine unapplied migrations,
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
# It is derived now. HISTORICAL_FILES is the exclusion list, and it is short,
# closed and explained: those four built the original schema, they are already
# applied on production, and re-running them would re-create the permissive
# `USING (true)` policies that 20260813 exists to remove.
HISTORICAL_FILES = {
    "20260720000000_initial_schema.sql",
    "phase1_foundation.sql",
    "phase2_assigned_responders.sql",
    "phase3_profile_columns_and_config.sql",
}


def outstanding_migrations() -> list[str]:
    """Every migration that is not part of the already-applied original schema.

    Sorted by filename, which is the timestamp prefix, which is the order they
    must apply in.
    """
    names = sorted(
        p.name
        for p in (ROOT / "supabase/migrations").glob("*.sql")
        if p.name not in HISTORICAL_FILES
    )
    if not names:
        raise SystemExit("no migrations found — is supabase/migrations present?")
    return names


MIGRATIONS = outstanding_migrations()

HEADER = """-- ============================================================================
-- APPLY ALL OUTSTANDING MIGRATIONS — generated file, do not edit by hand.
--   Regenerate with: python3 scripts/build_apply_all.py
--
-- Paste the WHOLE of this file into the Supabase dashboard -> SQL Editor and
-- run it. It applies the nine outstanding migrations in order and finishes by
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
-- EVERY MIGRATION HERE IS IDEMPOTENT. Running this file twice changes nothing
-- the second time, so a partial run can simply be re-run.
--
-- ONE THING TO KNOW ABOUT TRANSACTIONS. The RLS migration carries its own
-- BEGIN/COMMIT, which is deliberate: it applies completely or not at all. The
-- others do not, and are individually idempotent. If the editor reports an
-- error partway, nothing is half-applied in a way re-running cannot fix.
--
-- Expect a few `NOTICE: skipping ...` lines. They are the guards that let these
-- files run against a database that does not have a given table yet.
-- ============================================================================

"""

VERIFY = """

-- ============================================================================
-- DID IT WORK?
--
-- One row per thing that had to be true. `result` is PASS or FAIL; nothing here
-- writes. If every row says PASS, the nine migrations are applied.
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
          WHERE n.nspname = 'public' AND p.proname = 'sms_key_for_ingest'))
)
SELECT
  CASE WHEN ok THEN 'PASS' ELSE '*** FAIL ***' END AS result,
  name
FROM checks
ORDER BY ok, ord;
"""


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

    OUT.write_text("".join(parts))
    print(f"wrote {OUT.relative_to(ROOT)} "
          f"({len(MIGRATIONS)} migrations, {OUT.read_text().count(chr(10))} lines)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
