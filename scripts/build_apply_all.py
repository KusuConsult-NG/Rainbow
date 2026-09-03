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

# In order. The four historical files (initial schema, phase1-3) are NOT here:
# they are already applied on production, and re-running them would re-create
# the permissive policies that 20260813 exists to remove.
MIGRATIONS = [
    "20260812000000_agency_tables.sql",
    "20260813000000_rls_least_privilege.sql",
    "20260902000000_per_user_emergency_pins.sql",
    "20260903000000_realtime_publication.sql",
    "20260903000001_incident_media_storage.sql",
    "20260903000002_system_alerts_broadcast.sql",
    "20260903000003_alert_escalation_columns.sql",
    "20260903000004_profiles_badge_number.sql",
    "20260903000005_alerts_assigned_tier.sql",
]

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
          WHERE escalated_to_agency IN ('POLLING_UNIT','PU','WARD','LGA','HQ')))
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
