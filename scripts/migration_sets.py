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

import hashlib
import os
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

NOT_IN_THE_PASTE = set(ORIGINAL_SCHEMA) | set(HAND_APPLIED_ERA) | set(STAGING_ONLY)


def all_files() -> list[str]:
    names = sorted(p.name for p in MIGRATIONS.glob('*.sql'))
    if not names:
        raise SystemExit('no migrations found — is supabase/migrations present?')
    return names


def in_the_paste() -> list[str]:
    """Every migration the production paste carries, in apply order.

    THIS IS NOT A LIST OF WHAT A DATABASE STILL NEEDS, and it used to say it
    was: the docstring read "what a production database still needs". It is
    computed from filenames minus an exclusion set, and nothing updates it when
    a migration is applied somewhere — so it answered a question about a
    DATABASE with a fact about this DIRECTORY.

    That wrong answer travelled. Both runbooks opened with "N migrations are
    proven in CI and not yet applied to the production Supabase project", a
    gate enforced that wording, and the number was repeated to the operator as
    the top blocker for the whole deployment. Then
    `scripts/which_migrations_are_applied.sql` was run against the database and
    reported 32 of those 38 already present, including every one up to
    20261015. Six were genuinely missing.

    No file in this repository can know what a database has. The paste is
    idempotent precisely so that it does not need to: every statement is
    `IF NOT EXISTS`/`OR REPLACE`, the verifiers apply the whole bundle twice to
    prove it, and pasting a migration a database already has is a no-op.

    So this names the paste, which is a fact about the repository and is
    checkable here. What a given database still needs is answered by querying
    that database, and `which_migrations_are_applied.sql` is the query.
    """
    names = [n for n in all_files() if n not in NOT_IN_THE_PASTE]
    if not names:
        raise SystemExit('the paste is empty — the exclusion set is wrong')
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
    """Every migration in the paste reaches both paste scripts; no excluded one does.

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
    for name in in_the_paste():
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
    print(f'✓ {len(in_the_paste())} migrations reach both paste scripts; '
          f'the {len(HAND_APPLIED_ERA) + len(STAGING_ONLY)} already-applied ones '
          f'reach neither; {len(from_zero())} build a project from zero')
    return 0


def from_zero() -> list[str]:
    """Every file a fresh staging database needs, in the order it needs them.

    The original schema first, in its own order, then the paste's migrations
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
    return ORIGINAL_SCHEMA + in_the_paste()


def fingerprint(files: list[str]) -> str:
    """A short content hash of a migration set, for stamping paste scripts.

    Why this exists: twice an operator pasted a script from a working copy days
    behind the repository, and both times the output was reassuring rather than
    obviously stale.

      * scripts/which_migrations_are_applied.sql ran three migrations out of
        date and reported `every object in every migration exists — nothing to
        apply` (T-21);
      * apply_all_migrations.sql's anon/public check came back
        `*** FAIL *** | no policy grants anon or public anything` naming no
        policy at all — a version from before the check learned to name the
        offender, which cost a round trip to find out which policy it meant.

    Nothing in either output said which version produced it. Stamping the set's
    fingerprint into the verdict table means any pasted result identifies itself,
    and `--fingerprint` prints what the repository currently expects.

    Hashed over the file NAMES and CONTENTS, never the clock: a timestamp would
    change on every regeneration and make CI's generated-file diff fail for no
    reason. Identical migrations give an identical stamp.
    """
    h = hashlib.sha256()
    for name in files:
        h.update(name.encode('utf-8'))
        h.update(b'\0')
        h.update((MIGRATIONS / name).read_bytes())
        h.update(b'\0')
    return h.hexdigest()[:12]


if __name__ == '__main__':
    import sys
    if '--assert-coverage' in sys.argv:
        sys.exit(assert_coverage())
    if '--fingerprint' in sys.argv:
        # Two lines, so `| head -1` is a natural thing for an operator to type
        # — and Python's default response to a closed pipe is a traceback on
        # stderr after the line they asked for.
        try:
            print(f'the paste ({len(in_the_paste())} migrations): '
                  f'{fingerprint(in_the_paste())}')
            print(f'from zero   ({len(from_zero())} migrations): '
                  f'{fingerprint(from_zero())}')
            sys.stdout.flush()
        except BrokenPipeError:
            os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
        sys.exit(0)
    print(f'{len(all_files())} migration files; {len(in_the_paste())} in the paste; '
          f'{len(from_zero())} from zero')
