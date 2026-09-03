#!/usr/bin/env python3
"""Generate scripts/bootstrap_staging.sql — the whole schema, from zero.

WHY THIS IS NOT apply_all_migrations.sql
----------------------------------------
That file deliberately omits the four historical migrations, because production
already has them and re-running the initial schema would re-create the
permissive `USING (true)` policies that 20260813 exists to remove.

A fresh Supabase project has none of it. So this file is all THIRTEEN migrations
in order — the four that built the original schema, then the nine outstanding
ones — which is the only way to get a staging project that matches production's
shape rather than a subset of it.

Getting that distinction wrong in either direction is expensive: pasting this
into production would re-open the database, and pasting apply_all into a fresh
project would fail on the first missing table. Both files say which they are in
their first ten lines, and both refuse to be mistaken for the other by checking
the database they land in before doing anything.

Regenerate after any migration change:
    python3 scripts/build_bootstrap.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "scripts/bootstrap_staging.sql"

# Every migration, in order. The first four built the original schema; the rest
# are the outstanding ones. On a fresh database they apply cleanly in this
# sequence — phase1 drops each policy before creating it, so it supersedes the
# initial schema's permissive versions rather than colliding with them.
HISTORICAL = [
    "20260720000000_initial_schema.sql",
    "phase1_foundation.sql",
    "phase2_assigned_responders.sql",
    "phase3_profile_columns_and_config.sql",
]
OUTSTANDING = [
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
-- BOOTSTRAP A STAGING PROJECT — generated file, do not edit by hand.
--   Regenerate with: python3 scripts/build_bootstrap.py
--
-- >>> THIS IS FOR AN EMPTY PROJECT. DO NOT RUN IT ON PRODUCTION. <<<
--
-- It applies all thirteen migrations, starting with the initial schema — whose
-- policies are `USING (true)`, i.e. wide open to the anon role. A later
-- migration removes them, so a fresh project ends up correct; a database that
-- ALREADY has data would be briefly re-opened on the way through, and any
-- hand-made policy would be dropped.
--
-- The guard below refuses to run if it finds existing data, and it refuses
-- STRUCTURALLY: the whole file is one transaction, so the guard's exception
-- rolls back everything after it. An earlier version only RAISEd, which aborts
-- the buffer in the Supabase SQL editor but NOT under plain psql — there the
-- error printed and the migrations applied anyway. A guard that warns while the
-- damage proceeds is worse than none.
--
-- For a database that already has the original schema — production — use
-- scripts/apply_all_migrations.sql instead. That one omits the historical four.
--
-- WHAT YOU GET
--
-- A project whose schema matches what production will look like after the
-- outstanding migrations are applied: the same tables, the same policies, the
-- same functions. That is the point of it. `scripts/verify_rls.js` can then be
-- pointed at this project — and ONLY at a project like this, since it INSERTs
-- probe rows — to confirm anon really is locked out of a live Supabase, which
-- no local replica can prove.
--
-- Expect `NOTICE: skipping ...` lines. They are the guards that let these files
-- run against a database that does not have a given table yet.
-- ============================================================================

-- ── Refuse to run on a database that already holds anything ─────────────────
--
-- A staging bootstrap pasted into the wrong tab is the failure this exists to
-- prevent. `alerts` is the table that would hurt most, so its presence WITH
-- ROWS is the signal that this is not an empty project.
DO $guard$
DECLARE
  n bigint;
BEGIN
  IF to_regclass('public.alerts') IS NOT NULL THEN
    EXECUTE 'SELECT count(*) FROM public.alerts' INTO n;
    IF n > 0 THEN
      RAISE EXCEPTION
        'REFUSING TO RUN: public.alerts already holds % row(s). This script is '
        'for an EMPTY staging project and would re-open the database on its way '
        'through. For an existing database use scripts/apply_all_migrations.sql.', n;
    END IF;
  END IF;
END $guard$;

"""

# The migrations' own transaction control is stripped so the whole file can be
# ONE transaction. 20260813 ships `BEGIN;`/`COMMIT;`; a nested COMMIT would end
# the outer transaction early and leave the guard protecting only the first
# third of the file. Same reasoning as build_rls_dryrun.py, opposite intent:
# there it prevents a permanent change, here it makes the whole thing atomic.
TXN = re.compile(r"^\s*(BEGIN|COMMIT|START\s+TRANSACTION|ROLLBACK)\s*;\s*$",
                 re.IGNORECASE | re.MULTILINE)


def strip_transaction_control(sql: str) -> tuple[str, int]:
    stripped, n = TXN.subn("", sql)
    return stripped, n

VERIFY = """
COMMIT;

-- ============================================================================
-- DID IT WORK?
--
-- Same verdict table as apply_all_migrations.sql, plus the checks that only
-- mean something on a project built from zero.
-- ============================================================================

WITH checks(ord, name, ok) AS (
  VALUES
    (1, 'core tables exist (9)',
        (SELECT count(*) = 9 FROM information_schema.tables
          WHERE table_schema = 'public'
            AND table_name IN ('profiles','alerts','telemetry','chat_messages',
                               'system_alerts','safe_zones','uninstall_requests',
                               'app_config','emergency_pins'))),
    (2, 'agency tables exist (4)',
        (SELECT count(*) = 4 FROM information_schema.tables
          WHERE table_schema = 'public'
            AND table_name IN ('agency_personnel','agency_deployments',
                               'agency_action_reports','agency_notifications'))),
    (3, 'no policy grants anon or public anything',
        (SELECT count(*) = 0 FROM pg_policies
          WHERE schemaname = 'public'
            AND ('anon' = ANY(roles) OR 'public' = ANY(roles)))),
    -- NOT "no USING(true) policy survives". Three do, deliberately, and all
    -- three are reads granted to `authenticated` only: system advisories, safe
    -- zones and app config are meant to reach every signed-in user. The risk
    -- was never the shape of the qualifier, it is who can reach it — which is
    -- check 3, and which is the distinction scripts/rls_inventory.sql already
    -- draws in its `reach` column. The first version of this check asserted
    -- zero and failed on correct policies.
    --
    -- Pinning the exact set is stricter than dropping the check: a NEW
    -- permissive policy still fails here, even one granted only to
    -- authenticated, which check 3 would let through.
    (4, 'the only permissive USING(true) policies are the three intended reads',
        (SELECT coalesce(array_agg(policyname::text ORDER BY policyname), ARRAY[]::text[])
                  = ARRAY['app_config_read_authenticated','safe_zones_read',
                          'system_alerts_read']::text[]
           FROM pg_policies
          WHERE schemaname = 'public' AND (qual = 'true' OR with_check = 'true'))),
    (5, 'role-escalation trigger installed',
        (SELECT count(*) = 1 FROM pg_trigger
          WHERE tgname = 'profiles_no_privilege_escalation')),
    (6, 'emergency PIN functions exist (4)',
        (SELECT count(*) = 4 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public'
            AND p.proname IN ('set_emergency_pins','has_emergency_pins',
                              'verify_emergency_pin','resolve_emergency'))),
    (7, 'PIN hashes unreadable by the API roles',
        (SELECT count(*) = 0 FROM information_schema.role_table_grants
          WHERE table_schema = 'public' AND table_name = 'emergency_pins'
            AND grantee IN ('anon','authenticated'))),
    (8, 'realtime publication covers all 8 subscribed tables',
        (SELECT count(*) = 8 FROM pg_publication_tables
          WHERE pubname = 'supabase_realtime' AND schemaname = 'public'
            AND tablename IN ('alerts','telemetry','chat_messages','system_alerts',
                              'profiles','agency_action_reports',
                              'agency_deployments','uninstall_requests'))),
    (9, 'incident-media bucket configured',
        (SELECT count(*) = 1 FROM storage.buckets
          WHERE id = 'incident-media' AND public AND file_size_limit = 52428800)),
    (10, 'incident media is append-only (no UPDATE/DELETE policy)',
        (SELECT count(*) = 0 FROM pg_policies
          WHERE schemaname = 'storage' AND tablename = 'objects'
            AND policyname LIKE 'incident_media%' AND cmd IN ('UPDATE','DELETE'))),
    (11, 'broadcast scoping columns exist (6)',
        (SELECT count(*) = 6 FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'system_alerts'
            AND column_name IN ('target_audience','target_agency','target_lga',
                                'target_ward','target_pu','expires_at'))),
    (12, 'escalation columns exist',
        (SELECT count(*) = 2 FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'alerts'
            AND column_name IN ('escalated_to_agency','escalation_log'))),
    (13, 'profiles.badge_number exists',
        (SELECT count(*) = 1 FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'profiles'
            AND column_name = 'badge_number')),
    (14, 'alerts.assigned_tier exists',
        (SELECT count(*) = 1 FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'alerts'
            AND column_name = 'assigned_tier')),
    (15, 'the helper functions exist (4)',
        (SELECT count(*) = 4 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public'
            AND p.proname IN ('auth_role','is_staff','is_command','liaison_agency')))
)
SELECT
  CASE WHEN ok THEN 'PASS' ELSE '*** FAIL ***' END AS result,
  name
FROM checks
ORDER BY ok, ord;
"""


def main() -> int:
    # One transaction for the entire file, opened before the guard.
    parts = ["BEGIN;\n\n", HEADER]
    removed = 0
    for label, files in (("historical", HISTORICAL), ("outstanding", OUTSTANDING)):
        for filename in files:
            path = ROOT / "supabase/migrations" / filename
            if not path.exists():
                print(f"missing migration: {filename}", file=sys.stderr)
                return 1
            bar = "-" * 76
            parts.append(
                f"-- {bar}\n-- {filename}  ({label})\n-- {bar}\n"
                f"DO $b$ BEGIN RAISE NOTICE 'applying {filename}'; END $b$;\n\n"
            )
            body, n = strip_transaction_control(path.read_text())
            removed += n
            parts.append(body.rstrip() + "\n\n")
    parts.append(VERIFY)

    OUT.write_text("".join(parts))
    total = len(HISTORICAL) + len(OUTSTANDING)
    print(f"wrote {OUT.relative_to(ROOT)} ({total} migrations, "
          f"stripped {removed} transaction statement(s))")
    return 0


if __name__ == "__main__":
    sys.exit(main())
