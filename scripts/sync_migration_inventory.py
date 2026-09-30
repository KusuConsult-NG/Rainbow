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


def inventory() -> list[tuple[str, str, str]]:
    """[(migration stem, kind, object), ...] in migration order."""
    rows: list[tuple[str, str, str]] = []
    seen: set[tuple[str, str]] = set()
    for path in sorted(MIGRATIONS.glob('*.sql')):
        stem = path.stem
        sql = strip_noise(path.read_text(encoding='utf-8'))
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
        for kind, obj in found:
            # An object created in one migration and replaced in a later one is
            # listed against the FIRST, which is the migration whose absence
            # explains it being missing.
            if (kind, obj) in seen:
                continue
            seen.add((kind, obj))
            rows.append((stem, kind, obj))
    return rows


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
-- objects exist. A migration reading `0 of N` was never applied; `N of N` was.
-- Anything in between is a migration that failed partway, which is the worst
-- case and the one worth looking at first.
--
-- Then the `missing` rows name each absent table, column and function. These
-- are not cosmetic: the console calls these functions by name over PostgREST,
-- so a missing one is a failed RPC at the moment somebody opens a screen, and a
-- missing column is an insert the database rejects in full.
--
-- One migration is expected to be absent on some databases: the agency tables
-- were created by hand in production before they had a migration, so
-- 20260721000000_v2_agency_tables is marked `by hand` rather than counted as a
-- fault either way.
-- ============================================================================

WITH expected(migration, kind, obj) AS (VALUES
{values}
),
resolved AS (
  SELECT e.migration, e.kind, e.obj,
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
       format('%s of %s present%s', count(*) FILTER (WHERE present), count(*),
              CASE
                WHEN migration IN ({hand_made}) THEN ' — by hand in production, absence is not a fault'
                WHEN count(*) FILTER (WHERE present) = 0 THEN ' — NEVER APPLIED'
                WHEN count(*) FILTER (WHERE present) < count(*) THEN ' — APPLIED PARTWAY, look here first'
                ELSE ''
              END) AS detail
  FROM resolved
 GROUP BY migration
UNION ALL
SELECT 2, 'missing', format('%s %s', kind, obj), migration
  FROM resolved
 WHERE NOT present
UNION ALL
SELECT 3, 'all present', 'every object in every migration exists', 'nothing to apply'
 WHERE NOT EXISTS (SELECT 1 FROM resolved WHERE NOT present)
 ORDER BY ord, name;
"""


def render(rows: list[tuple[str, str, str]]) -> str:
    values = ',\n'.join(
        f"  ('{m}', '{k}', '{o}')" for m, k, o in rows)
    hand = ', '.join(f"'{h}'" for h in sorted(HAND_MADE))
    return HEADER.format(values=values, hand_made=hand)


def main() -> int:
    rows = inventory()
    if not rows:
        print('✗ no objects extracted from supabase/migrations/', file=sys.stderr)
        return 2
    want = render(rows)
    if '--check' in sys.argv:
        have = OUT.read_text(encoding='utf-8') if OUT.exists() else ''
        if have != want:
            print('✗ scripts/which_migrations_are_applied.sql is out of date.\n'
                  '  Run: python3 scripts/sync_migration_inventory.py',
                  file=sys.stderr)
            return 1
        print(f'✓ the migration inventory matches: {len(rows)} objects across '
              f'{len({r[0] for r in rows})} migrations')
        return 0
    OUT.write_text(want, encoding='utf-8')
    print(f'✓ wrote {OUT.relative_to(REPO)}: {len(rows)} objects across '
          f'{len({r[0] for r in rows})} migrations')
    return 0


if __name__ == '__main__':
    sys.exit(main())
