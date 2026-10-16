#!/usr/bin/env python3
"""Generate the "which migrations are applied?" diagnostic from the migrations.

    python3 scripts/sync_migration_inventory.py            # write the .sql
    python3 scripts/sync_migration_inventory.py --check     # fail if it drifted

Twice now an operational failure has come down to a migration that was never
applied, and both times it presented as something else:

  * the agency tables and their generated `lga`/`ward`/`pu` mirrors existed in
    production because someone created them by hand, and not in the harness —
    which is why a 428C9 error names `category` on one database and `lga` on
    another, for the same statement
  * `route_oversight_to_hq_trg` was absent from a live database while every
    console screen that calls `audit_trail()` and `latest_ai_report()` had
    already shipped, so the console was calling functions that did not exist

Neither is visible from the application. A missing function is a failed RPC at
the moment somebody opens a screen during an incident, and a missing column is
an insert rejected in full. So the question "which migrations has this database
actually had?" needs an answer that does not depend on anybody's memory of what
they ran.

The inventory is EXTRACTED, not written by hand. A diagnostic listing objects
from memory drifts the moment a migration is added, and drifts silently — it
would report every object present and be wrong about the ones it never learned
about. `--check` in CI is what keeps it honest.

What is extracted, per migration file:

    CREATE TABLE [IF NOT EXISTS] public.x       -> table x
    ALTER TABLE public.x ADD COLUMN [...] y     -> column x.y
    CREATE [OR REPLACE] FUNCTION public.f(...)  -> function f

Columns declared inside a CREATE TABLE body are deliberately not listed: if the
table is there, they came with it, and listing them would triple the output for
no new information.

A migration that REMOVES an object is handled the other way round: the object
becomes a must-be-ABSENT assertion attributed to the migration that drops it.
Without that this diagnostic actively misleads. Before this change all seven
objects 20261018000000 drops were must-be-present rows inherited from v2 and v5,
so the moment an operator applied 20261018 the output would report seven missing
objects and point them at
`20260721000000_v2_agency_tables` / `20260724000000_v5_rls_security` — files
whose re-application would recreate the generated mirrors that migration exists
to remove, putting back the ordinal divergence behind the 428C9 difference. A
drop-only migration was also invisible here, since it creates nothing; now it
reads `0 of 7 removed — NEVER APPLIED` before and `7 of 7 removed` after, which
is the only way this script can answer "did it land?" for such a file.

Known limitation: object existence cannot see every migration. One that only
creates or replaces a POLICY contributes nothing
(20261016000000_telemetry_policy_is_not_public.sql is exactly that shape), and
neither does one whose every object an earlier migration already created
(20261017000000, whose purpose is to put the hand-applied era into the history,
is a no-op on the production database that already has it). Those files are no
longer silently missing from the output: they are listed under `not detectable`
with the reason, so nobody reads a clean report as proof they were applied.
Policies are covered instead by the end-of-replay sweep in
verify_rls_migration.sh, which fails if any policy in `public` reaches anon or
public, and by scripts/rls_inventory.sql against a live database.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
MIGRATIONS = REPO / 'supabase' / 'migrations'
OUT = REPO / 'scripts' / 'which_migrations_are_applied.sql'

# The v2–v5 era. These four were applied by hand to production before the
# project kept a migration history, and verify_rls_migration.sh deliberately
# does not replay them — 20260812000000_agency_tables.sql is the file that
# creates those tables on a database that lacks them.
#
# So their objects are present on production and absent from the harness, which
# is a real difference and not a fault on either side. It is also why the same
# bad INSERT reports a different column name on each: production has
# alerts.lga/ward/pu generated at ordinals 28–30, ahead of category at 38, and
# PostgreSQL names the first generated column in the target list.
#
# Named here so the diagnostic says that, instead of reporting five migrations
# missing and sending someone to apply files that would conflict.
HAND_MADE = {
    '20260721000000_v2_agency_tables',
    '20260722000000_v3_telemetry_geofence',
    '20260723000000_v4_mesh_broadcast',
    '20260724000000_v5_rls_security',
}

# Era objects a later migration removes with a plpgsql `EXECUTE format(...)`
# rather than literal SQL, so no regex over the migration text can see them.
# Listed explicitly because the alternative is a regex that parses plpgsql,
# which would be a worse bet than a short list kept next to the migration that
# owns it.
#
# 20261018000000 drops all seven: the five generated mirrors of geo_*, which
# hold no information of their own, and the two v5 functions whose only callers
# were the v5-era policies that 20260813 drops by name.
#
# This is the one definition. check_schema_convergence.py re-exports it and
# verifies every entry against the migration that claims to drop it, and
# check_generated_column_inserts.py reads it from there — so one list is checked
# and the others cannot drift from it. It lives HERE rather than there because
# check_schema_convergence.py already imports this module for strip_noise, and
# the dependency has to run one way.
DROPPED_BY_LATER: dict[str, str] = {
    'column:alerts.lga': '20261018000000',
    'column:alerts.ward': '20261018000000',
    'column:alerts.pu': '20261018000000',
    'column:profiles.lga': '20261018000000',
    'column:profiles.ward': '20261018000000',
    'function:is_hq_or_admin': '20261018000000',
    'function:is_responder': '20261018000000',
}


def strip_noise(sql: str) -> str:
    """Blank comments and single-quoted literals, keeping line positions."""
    out, i, n = [], 0, len(sql)
    while i < n:
        two = sql[i:i + 2]
        if two == '--':
            j = sql.find('\n', i)
            j = n if j < 0 else j
            out.append(' ' * (j - i)); i = j
        elif two == '/*':
            j = sql.find('*/', i + 2)
            j = n if j < 0 else j + 2
            out.append(''.join(c if c == '\n' else ' ' for c in sql[i:j])); i = j
        elif sql[i] == "'":
            j = i + 1
            while j < n:
                if sql[j] == "'":
                    if sql[j + 1:j + 2] == "'":
                        j += 2; continue
                    j += 1; break
                j += 1
            out.append(''.join(c if c == '\n' else ' ' for c in sql[i:j])); i = j
        else:
            out.append(sql[i]); i += 1
    return ''.join(out)


TABLE = re.compile(
    r'(?is)\bCREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:public\.)?"?(\w+)"?')
FUNCTION = re.compile(
    r'(?is)\bCREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+(?:public\.)?"?(\w+)"?\s*\(')
ALTER = re.compile(
    r'(?is)\bALTER\s+TABLE\s+(?:IF\s+EXISTS\s+)?(?:public\.)?"?(\w+)"?')
ADD_COLUMN = re.compile(
    r'(?is)\bADD\s+COLUMN\s+(?:IF\s+NOT\s+EXISTS\s+)?"?(\w+)"?')


POLICY = re.compile(r'(?is)\bCREATE\s+POLICY\b')


def extract(sql: str) -> list[tuple[str, str]]:
    """[(kind, object), ...] created by one migration's text."""
    found: list[tuple[str, str]] = []
    for m in TABLE.finditer(sql):
        found.append(('table', m.group(1).lower()))
    for m in FUNCTION.finditer(sql):
        found.append(('function', m.group(1).lower()))
    # ADD COLUMN belongs to whichever ALTER TABLE precedes it, and one ALTER
    # can add several — so walk the statement, not the file.
    for stmt in sql.split(';'):
        a = ALTER.search(stmt)
        if not a:
            continue
        table = a.group(1).lower()
        for c in ADD_COLUMN.finditer(stmt):
            found.append(('column', f'{table}.{c.group(1).lower()}'))
    return found


def dropping_stems() -> dict[str, str]:
    """{'column:alerts.lga': '20261018000000_the_mirrors_...'}

    Resolves each DROPPED_BY_LATER prefix to the real file stem, and refuses to
    generate anything if one names a migration that does not exist — otherwise a
    typo would quietly drop the object from BOTH halves of the output: no
    must-be-present row, and a must-be-absent row filed under a migration nobody
    can apply.
    """
    out: dict[str, str] = {}
    for key, prefix in sorted(DROPPED_BY_LATER.items()):
        matches = sorted(MIGRATIONS.glob(f'{prefix}*.sql'))
        if not matches:
            raise SystemExit(
                f'✗ DROPPED_BY_LATER says {key} is dropped by migration '
                f'{prefix}, and no such file exists in supabase/migrations/.')
        out[key] = matches[0].stem
    return out


def inventory() -> tuple[list[tuple[str, str, str, bool]], list[tuple[str, str]]]:
    """(rows, undetectable).

    rows is [(migration stem, kind, object, must_be_present), ...]; undetectable
    is [(migration stem, why object existence cannot see it), ...].
    """
    drops = dropping_stems()
    rows: list[tuple[str, str, str, bool]] = []
    seen: set[tuple[str, str]] = set()
    undetectable: list[tuple[str, str]] = []
    dropped_were_created: set[str] = set()

    for path in sorted(MIGRATIONS.glob('*.sql')):
        stem = path.stem
        sql = strip_noise(path.read_text(encoding='utf-8'))
        found = extract(sql)
        contributed = 0
        for kind, obj in found:
            # An object created in one migration and replaced in a later one is
            # listed against the FIRST, which is the migration whose absence
            # explains it being missing.
            if (kind, obj) in seen:
                continue
            seen.add((kind, obj))
            key = f'{kind}:{obj}'
            if key in drops:
                # Emitted below as a must-be-ABSENT row against the migration
                # that removes it, instead of a must-be-present row here.
                dropped_were_created.add(key)
                continue
            rows.append((stem, kind, obj, True))
            contributed += 1
        if contributed:
            continue
        if stem in drops.values():
            continue   # it gets its must-be-absent rows below
        undetectable.append((stem, _why_invisible(path, sql, found)))

    missing_creator = sorted(set(drops) - dropped_were_created)
    if missing_creator:
        raise SystemExit(
            '✗ DROPPED_BY_LATER lists object(s) that no migration in '
            'supabase/migrations/ creates, so the must-be-absent assertion is '
            'vacuous and the name is probably a typo:\n  '
            + '\n  '.join(missing_creator))

    for key, stem in sorted(drops.items(), key=lambda kv: (kv[1], kv[0])):
        kind, obj = key.split(':', 1)
        rows.append((stem, kind, obj, False))
    return rows, undetectable


def _why_invisible(path: Path, sql: str, found: list[tuple[str, str]]) -> str:
    """Why a migration contributes no row, in the operator's terms."""
    if found:
        return ('every object it declares is already created by an earlier '
                'migration, so it is a no-op on a database that has them')
    if POLICY.search(sql):
        return ('it only creates policies, which object existence cannot see — '
                'use scripts/rls_inventory.sql')
    return 'it declares no table, column or function'


HEADER = """\
-- ============================================================================
-- Which migrations has this database actually had?
--
-- READ-ONLY. Safe on production. ONE statement, because the Supabase SQL editor
-- shows only the last result set of a multi-statement run.
--
-- GENERATED by scripts/sync_migration_inventory.py — do not edit by hand. CI
-- fails if it drifts from supabase/migrations/.
--
-- Read the `summary` rows first: one per migration, with how many of its
-- objects are as that migration leaves them. A migration reading `0 of N` was
-- never applied; `N of N` was. Anything in between is a migration that failed
-- partway, which is the worst case and the one worth looking at first.
--
-- "Partly present" has TWO readings and the summary line no longer picks one.
-- A migration that failed halfway is the alarming case. But a CONVERGENCE
-- migration — `20261023000000_one_table_one_shape`, which exists because two
-- databases had the same table with different columns — adds columns with
-- `ADD COLUMN IF NOT EXISTS`, and on a database that already had some of them
-- it reads `5 of 8` while never having been applied at all. That is the file
-- written to handle exactly this, reported as the worst case. The `missing`
-- rows tell them apart: a partial failure leaves an arbitrary subset, while a
-- convergence migration leaves the objects that database never had.
--
-- Most migrations CREATE, and read `N of N present`. One REMOVES, and reads
-- `N of N removed` — for those the assertion is that the object is gone, so
-- `0 of 7 removed` means that migration has not been applied yet, not that
-- something is broken.
--
-- Then the `missing` rows name each absent table, column and function. These
-- are not cosmetic: the console calls these functions by name over PostgREST,
-- so a missing one is a failed RPC at the moment somebody opens a screen, and a
-- missing column is an insert the database rejects in full. The `still present`
-- rows are the mirror image: an object a migration should have removed.
--
-- The `not detectable` rows name migrations this diagnostic CANNOT see, with
-- the reason. A clean report is not evidence that those were applied.
--
-- One migration is expected to be absent on some databases: the agency tables
-- were created by hand in production before they had a migration, so
-- 20260721000000_v2_agency_tables is marked `by hand` rather than counted as a
-- fault either way.
-- ============================================================================

WITH expected(migration, kind, obj, want) AS (VALUES
{values}
),
resolved AS (
  SELECT e.migration, e.kind, e.obj, e.want,
         CASE e.kind
           WHEN 'table' THEN
             to_regclass('public.' || quote_ident(e.obj)) IS NOT NULL
           WHEN 'function' THEN
             EXISTS (SELECT 1 FROM pg_proc p
                       JOIN pg_namespace n ON n.oid = p.pronamespace
                      WHERE n.nspname = 'public' AND p.proname = e.obj)
           WHEN 'column' THEN
             EXISTS (SELECT 1 FROM pg_attribute a
                       JOIN pg_class c     ON c.oid = a.attrelid
                       JOIN pg_namespace n ON n.oid = c.relnamespace
                      WHERE n.nspname = 'public'
                        AND c.relname = split_part(e.obj, '.', 1)
                        AND a.attname = split_part(e.obj, '.', 2)
                        AND a.attnum > 0 AND NOT a.attisdropped)
         END AS present
    FROM expected e
)
SELECT 1 AS ord, 'summary' AS section, migration AS name,
       format('%s of %s %s%s',
              count(*) FILTER (WHERE present = want), count(*),
              CASE
                WHEN bool_and(want)     THEN 'present'
                WHEN bool_and(NOT want) THEN 'removed'
                ELSE 'as expected'
              END,
              CASE
                WHEN migration IN ({hand_made}) THEN ' — by hand in production, absence is not a fault'
                WHEN count(*) FILTER (WHERE present = want) = 0 THEN ' — NEVER APPLIED'
                WHEN count(*) FILTER (WHERE present = want) < count(*) THEN ' — PARTLY PRESENT: either applied partway, or a convergence migration whose objects already existed here. Read its `missing` rows below'
                ELSE ''
              END) AS detail
  FROM resolved
 GROUP BY migration
UNION ALL
SELECT 2, 'missing', format('%s %s', kind, obj), migration
  FROM resolved
 WHERE want AND NOT present
UNION ALL
SELECT 2, 'still present', format('%s %s', kind, obj),
       format('%s removes this and has not been applied', migration)
  FROM resolved
 WHERE present AND NOT want
{undetectable}UNION ALL
SELECT 4, 'as expected', 'every object in every migration is as it should be',
       '{nothing_to_apply}'
 WHERE NOT EXISTS (SELECT 1 FROM resolved WHERE present <> want)
 ORDER BY ord, name;
"""

# Rendered only when there is at least one such migration: `VALUES` with no
# rows is a syntax error, and a hard-coded empty block would make the whole
# diagnostic fail to parse on a repository where every migration is visible.
UNDETECTABLE_BLOCK = """\
UNION ALL
SELECT 3, 'not detectable', name, detail
  FROM (VALUES
{values}
       ) AS u(name, detail)
"""


def render(rows: list[tuple[str, str, str, bool]],
           undetectable: list[tuple[str, str]]) -> str:
    values = ',\n'.join(
        f"  ('{m}', '{k}', '{o}', {'true' if w else 'false'})"
        for m, k, o, w in rows)
    hand = ', '.join(f"'{h}'" for h in sorted(HAND_MADE))
    block = ''
    if undetectable:
        block = UNDETECTABLE_BLOCK.format(values=',\n'.join(
            f"         ('{m}', '{d}')" for m, d in sorted(undetectable)))
    note = ('nothing to apply — but read the `not detectable` rows'
            if undetectable else 'nothing to apply')
    return HEADER.format(values=values, hand_made=hand, undetectable=block,
                         nothing_to_apply=note)


def main() -> int:
    if '--drops' in sys.argv:
        # For verify_rls_migration.sh, so the shell gate asserting "N of N
        # removed" reads the count from this list instead of hard-coding it and
        # silently checking the wrong number the next time one is added.
        stems = sorted(set(dropping_stems().values()))
        if len(stems) != 1:
            print(f'✗ expected one dropping migration, found {len(stems)}: '
                  f'{stems}. --drops has to grow a row per migration.',
                  file=sys.stderr)
            return 2
        print(f'{stems[0]} {len(DROPPED_BY_LATER)}')
        return 0

    rows, undetectable = inventory()
    if not rows:
        print('✗ no objects extracted from supabase/migrations/', file=sys.stderr)
        return 2

    # Every literal is interpolated into single-quoted SQL. Nothing extracted
    # from a migration name or written in _why_invisible has a quote in it
    # today, and this is here so that stops being a thing anyone has to
    # remember: a quote would close the literal early and the diagnostic would
    # fail to parse against a live database, which is where it is read.
    for literal in ([r[0] for r in rows] + [r[2] for r in rows]
                    + [u for pair in undetectable for u in pair]):
        if "'" in literal or '\\' in literal:
            print(f'✗ {literal!r} would break the generated SQL literal.',
                  file=sys.stderr)
            return 2

    want = render(rows, undetectable)
    counts = (f'{sum(1 for r in rows if r[3])} objects that must exist, '
              f'{sum(1 for r in rows if not r[3])} that must be gone, across '
              f'{len({r[0] for r in rows})} migrations; '
              f'{len(undetectable)} not detectable')
    if '--check' in sys.argv:
        have = OUT.read_text(encoding='utf-8') if OUT.exists() else ''
        if have != want:
            print('✗ scripts/which_migrations_are_applied.sql is out of date.\n'
                  '  Run: python3 scripts/sync_migration_inventory.py',
                  file=sys.stderr)
            return 1
        print(f'✓ the migration inventory matches: {counts}')
        return 0
    OUT.write_text(want, encoding='utf-8')
    print(f'✓ wrote {OUT.relative_to(REPO)}: {counts}')
    for stem, why in sorted(undetectable):
        print(f'  not detectable: {stem} — {why}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
