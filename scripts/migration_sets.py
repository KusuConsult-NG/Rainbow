"""Which migration files belong in an operator's paste script, and which do not.

One definition, imported by build_apply_all.py, build_apply_in_parts.py and
build_bootstrap.py, because three copies of this list is how the copies drifted.

## What went wrong

`scripts/apply_all_migrations.sql` is what a person pastes into a production SQL
editor. It was last generated on 2026-09-28 with 17 migrations, starting at
20260812000000_agency_tables. On 2026-09-29 five more files were added to
supabase/migrations/ — 20260721000000_v2_agency_tables through
20260725000000_v6_geo_lga_scoping_staging — recording an era that had been
applied to production BY HAND, long before it had migration files.

Every generator derived its list as "every file except the original schema and
the three phase files". So those five were silently pulled into the paste
script. Re-running them is not a no-op:

  * 20260721000000_v2_agency_tables.sql calls auth.jwt(), which did not exist
    at that point in the history — `ERROR: function auth.jwt() does not exist`
  * the whole point of adding them was to RECORD what production already has,
    not to hand somebody a script that applies them again

CI has a gate for exactly this ("Regenerate and diff", plus "Assert every
migration reaches the apply scripts"). It never fired, because no runner has
picked up a job on this repository — every job in every run since at least
2026-09-29 completed in two seconds with runner_id 0 and no logs, which is an
Actions/billing condition on the account rather than a failing test. So the
generators drifted for a day and nothing said so.

## The sets

Deriving from the directory is still right — a hand-maintained list of what to
INCLUDE omits any migration nobody remembers to add, and the in-sync diff cannot
see the omission because the missing file was never in the output to differ
against. What has to be hand-maintained is the much shorter list of what to
EXCLUDE, which is closed: no new file will ever join the already-applied era.
"""
from __future__ import annotations

import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
MIGRATIONS = ROOT / 'supabase' / 'migrations'

# The original schema. phase1 drops each policy before creating it, so on a
# fresh database it supersedes the initial schema's permissive versions rather
# than colliding with them — which is why these four apply in this order and not
# in filename order.
ORIGINAL_SCHEMA = [
    '20260720000000_initial_schema.sql',
    'phase1_foundation.sql',
    'phase2_assigned_responders.sql',
    'phase3_profile_columns_and_config.sql',
]

# The v2–v5 era: applied to production by hand before the project kept a
# migration history, and written down afterwards. Present on production, absent
# from verify_rls_migration.sh (20260812000000_agency_tables.sql is the file
# that creates those tables on a database that lacks them).
#
# This is also why the same bad INSERT reports a different column name on
# different databases: v2 declares alerts.lga/ward/pu generated at ordinals
# 28–30, ahead of category at 38, and PostgreSQL names the FIRST generated
# column in an insert's target list.
HAND_APPLIED_ERA = [
    '20260721000000_v2_agency_tables.sql',
    '20260722000000_v3_telemetry_geofence.sql',
    '20260723000000_v4_mesh_broadcast.sql',
    '20260724000000_v5_rls_security.sql',
]

# Staging only, by its own name and contents. It must never reach a script
# aimed at production.
STAGING_ONLY = [
    '20260725000000_v6_geo_lga_scoping_staging.sql',
]

NOT_OUTSTANDING = set(ORIGINAL_SCHEMA) | set(HAND_APPLIED_ERA) | set(STAGING_ONLY)


def all_files() -> list[str]:
    names = sorted(p.name for p in MIGRATIONS.glob('*.sql'))
    if not names:
        raise SystemExit('no migrations found — is supabase/migrations present?')
    return names


def outstanding() -> list[str]:
    """What a production database still needs, in filename (timestamp) order."""
    names = [n for n in all_files() if n not in NOT_OUTSTANDING]
    if not names:
        raise SystemExit('no outstanding migrations — the exclusion set is wrong')
    return names


# phase1_foundation.sql creates seven policies with NO `TO` clause, which in
# PostgreSQL means TO PUBLIC — and PUBLIC includes anon:
#
#   chat_read, chat_insert                 on chat_messages
#   telemetry_own_upsert, telemetry_read_all on telemetry
#   safe_zones_read                        on safe_zones
#   uninstall_insert, uninstall_read       on uninstall_requests
#
# 20260813000000_rls_least_privilege.sql drops all seven by name and creates
# scoped replacements. So the ORDER of these two files in a bundle decides
# whether a database ends up locked down or re-opened, and a bundle that puts
# phase1 last silently undoes the migration whose entire purpose is to close it.
#
# supabase/rainbow_full_migration.sql does exactly that: 20260813 at section 7,
# phase1 at section 28. It is hand-assembled, has no generator, and was not
# covered by any check. Pasting it leaves chat_messages, telemetry, safe_zones
# and uninstall_requests carrying TO PUBLIC policies. What stops that being an
# open database today is only that 20260813 also REVOKEs the table privileges
# from anon — so it survives on one layer, and a single GRANT (or one click in
# the dashboard's table editor) exposes citizens' position history.
PERMISSIVE_SOURCE = 'phase1_foundation.sql'
LEAST_PRIVILEGE = '20260813000000_rls_least_privilege.sql'
BUNDLES = [
    'scripts/apply_all_migrations.sql',
    'scripts/bootstrap_staging.sql',
    'supabase/rainbow_full_migration.sql',
]


def assert_no_bundle_reopens_the_database() -> list[str]:
    """No bundle may apply phase1 after the least-privilege migration."""
    import re
    problems: list[str] = []
    for rel in BUNDLES:
        path = ROOT / rel
        if not path.is_file():
            continue
        order = re.findall(r'^-- Migration: (.+?)\s*$',
                           path.read_text(encoding='utf-8'), re.M)
        if PERMISSIVE_SOURCE not in order or LEAST_PRIVILEGE not in order:
            continue
        if order.index(PERMISSIVE_SOURCE) > order.index(LEAST_PRIVILEGE):
            problems.append(
                f'{rel} applies {PERMISSIVE_SOURCE} (section '
                f'{order.index(PERMISSIVE_SOURCE) + 1}) AFTER {LEAST_PRIVILEGE} '
                f'(section {order.index(LEAST_PRIVILEGE) + 1}), which re-creates '
                f'the TO PUBLIC policies that migration exists to remove')
    return problems


def assert_coverage() -> int:
    """Every outstanding migration reaches both paste scripts; no excluded one does.

    Both halves matter and they fail differently. A missing migration means an
    operator pastes a script that silently lacks it — and the "regenerate and
    diff" check cannot see that, because a file that was never in the list was
    never in the output to differ against. An EXCLUDED migration that got in is
    the defect this module was written for: a script that re-runs an era
    production already has.

    Run as: python3 scripts/migration_sets.py --assert-coverage
    """
    apply_all = (ROOT / 'scripts' / 'apply_all_migrations.sql').read_text(encoding='utf-8')
    bootstrap = (ROOT / 'scripts' / 'bootstrap_staging.sql').read_text(encoding='utf-8')
    parts_dir = ROOT / 'scripts' / 'apply_in_parts'
    parts = sorted(p.name for p in parts_dir.glob('*.sql')) if parts_dir.is_dir() else []

    problems: list[str] = []
    for name in outstanding():
        if name not in apply_all:
            problems.append(f'{name} is missing from scripts/apply_all_migrations.sql')
        if not any(name in p for p in parts):
            problems.append(f'{name} has no part in scripts/apply_in_parts/')
    for name in from_zero():
        if name not in bootstrap:
            problems.append(f'{name} is missing from scripts/bootstrap_staging.sql')

    # `-- Migration: <name>` is the section header the generator writes. Matching
    # on that and not on a bare mention is deliberate: a migration's own comments
    # legitimately refer to an earlier file by name, and 20261006 refers to
    # 20260725000000_v6 in exactly that way.
    for name in sorted(set(HAND_APPLIED_ERA) | set(STAGING_ONLY)):
        if f'-- Migration: {name}' in apply_all:
            problems.append(
                f'{name} is APPLIED by scripts/apply_all_migrations.sql — it is '
                f'already on production and re-running it is not a no-op')
        if any(name in p for p in parts):
            problems.append(f'{name} has a part in scripts/apply_in_parts/')

    problems += assert_no_bundle_reopens_the_database()

    for p in problems:
        print(f'✗ {p}')
    if problems:
        print(f'\n{len(problems)} problem(s) in the generated apply scripts.')
        return 1
    print(f'✓ {len(outstanding())} outstanding migrations reach both paste scripts; '
          f'the {len(HAND_APPLIED_ERA) + len(STAGING_ONLY)} already-applied ones '
          f'reach neither; {len(from_zero())} build a project from zero')
    return 0


def from_zero() -> list[str]:
    """Every file a fresh staging database needs, in the order it needs them.

    The original schema first, in its own order, then the outstanding migrations
    by timestamp — which is the set the bootstrap has always built, and the same
    schema verify_rls_migration.sh replays and asserts against.

    The v2–v6 era is NOT included, and the reason is not tidiness: those files do
    not apply in timestamp order on an empty database.

      * v2 calls auth.jwt(), which the test shim lacked until today
      * v5 builds a policy on profiles.badge_number, a column that
        20260903000004 adds eleven migrations later — `ERROR: column
        "badge_number" does not exist`

    They were applied to production by hand, in whatever order the person ran
    them, against a database that had already drifted. Making them replay from
    zero would mean rewriting historical DDL to fit an order it never ran in,
    which is a worse lie than leaving them out.

    So there is a real, KNOWN divergence: production has the generated mirrors
    alerts.lga/ward/pu and profiles.lga/ward, and a database built from this
    bootstrap does not. That is the same divergence that made one 428C9 error
    name `category` and another name `lga`, and it is why
    scripts/which_migrations_are_applied.sql marks that era `by hand` rather than
    reporting it missing. Closing it properly means a NEW forward migration that
    adds those columns idempotently — not a re-run of five files from July.
    """
    return ORIGINAL_SCHEMA + outstanding()


if __name__ == '__main__':
    import sys
    if '--assert-coverage' in sys.argv:
        sys.exit(assert_coverage())
    print(f'{len(all_files())} migration files; {len(outstanding())} outstanding; '
          f'{len(from_zero())} from zero')
