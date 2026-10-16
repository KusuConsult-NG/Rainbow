#!/usr/bin/env python3
"""One table, one shape — on production and on every database we can build.

    python3 scripts/check_one_table_one_shape.py

## What went wrong

Three of the four agency tables are created TWICE in this history, by two
migrations with different column lists and `CREATE TABLE IF NOT EXISTS` on
both. The second one is therefore a no-op, and which columns a database has
depends on which file ran first:

    agency_notifications   20260722000000_v3_telemetry_geofence   10 columns
                           20260812000000_agency_tables            7 columns
    agency_action_reports  20260723000000_v4_mesh_broadcast       14 columns
                           20260812000000_agency_tables           15 columns
    agency_deployments     20260723000000_v4_mesh_broadcast       10 columns
                           20260812000000_agency_tables           10 columns

The v2–v6 era was applied to production BY HAND and written down afterwards. It
cannot be replayed — v2 calls `auth.jwt()` before the shim defines it — so
`verify_rls_migration.sh`, `bootstrap_staging.sql` and `apply_all_migrations.sql`
all exclude it. The split is therefore exact and permanent:

  * on **production** the v3/v4 definitions ran first, so the tables carry
    `detail`, `sent_by`, `target_lga`, `acknowledged_at`, `resolved_at` and NOT
    `created_at`;
  * on **every database this repository can build**, only 20260812 runs, so
    they carry `created_at` and none of those five.

Two shapes, differing in both directions, with nothing saying so. Nothing could
say so: `scripts/check_schema_convergence.py` compares the OBJECTS the two
histories create, not their columns, and the local Supabase stand-in builds its
column set by UNIONING every definition it finds — which is right for a fake
that must not refuse a column production has, and means the harness accepts a
column that exists on neither database.

It cost the delivery log of an inter-agency handover. `/api/notify-agency`
records one row per channel in `agency_notifications` — "the only durable
record of whether an agency was told" — and dropped `result.detail`, the one
field that says WHY a leg failed, because that column existed on production and
nowhere else. `20261023000000_one_table_one_shape.sql` converges them.

## What this checks

For the two worlds that exist — production (with the hand-applied era) and a
repo-built database (without it) — it replays the migrations in apply order and
computes each table's effective shape: the FIRST `CREATE TABLE` wins, and every
later `ALTER TABLE ... ADD COLUMN` adds to it. Then:

  1. **The two worlds agree.** Any table whose effective columns differ between
     them is the defect above: code written against one shape fails on the
     other, and a test suite that only ever sees one of them cannot tell you.

  2. **No definition claims a column no database gets.** A second
     `CREATE TABLE` that lists a column the first definition lacks is a file
     describing a table that does not exist anywhere — and anybody reading it,
     or writing code against it, is reading fiction.

## What it does not model

Dynamic DDL. `20261018000000` drops the generated mirrors through
`EXECUTE format('ALTER TABLE public.%I DROP COLUMN %I …')` inside a DO block,
so no textual rule can see which columns go. That one is harmless here: it runs
in BOTH worlds, so it cannot split them. A dynamic drop that ran in only one
world would be missed, and would need its own assertion in
`scripts/schema_convergence_behaviour_test.sql`, which tests the database
rather than the text.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import migration_sets  # noqa: E402  (after sys.path)

REPO = Path(__file__).resolve().parent.parent
MIGRATIONS = REPO / 'supabase' / 'migrations'

# A definition that claims a column no database ends up with, left as it is on
# purpose. Each entry needs the second sentence: why the file is wrong and why
# correcting it would be worse.
#
#   telemetry / phase1_foundation.sql — phase1 describes a DIFFERENT design of
#   this table: a surrogate `id` with UNIQUE(user_id) and an `alert_id`, i.e. a
#   TRACK of positions. `20260720000000_initial_schema.sql` creates it first,
#   with `user_id` as the primary key — one current position per person, which
#   is what `background_tracking_service.dart` upserts into and what
#   `agent_dashboard_screen.dart` streams with `primaryKey: ['user_id']`. The
#   track arrived later as its own table, `incident_tracks` (20261004000000).
#   Adding `id` and `alert_id` to a live table to make a dead definition true
#   would be worse than leaving it; nothing reads either column.
KNOWN_FICTION = {
    ('telemetry', 'phase1_foundation.sql'): frozenset({'id', 'alert_id'}),
}

BLOCK_COMMENT = re.compile(r'/\*.*?\*/', re.S)
LINE_COMMENT = re.compile(r'--[^\n]*')
NON_COLUMN = re.compile(
    r'^(constraint|primary|unique|foreign|check|exclude|like|inherits)\b', re.I)

CREATE = re.compile(
    r'CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:public\.)?([a-z_0-9]+)\s*\(', re.I)
ADD_COLUMN = re.compile(
    r'ADD\s+COLUMN\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:public\.)?"?([a-z_0-9]+)"?', re.I)
ALTER = re.compile(r'ALTER\s+TABLE\s+(?:IF\s+EXISTS\s+)?(?:public\.)?([a-z_0-9]+)', re.I)


def decomment(sql: str) -> str:
    return LINE_COMMENT.sub('', BLOCK_COMMENT.sub(' ', sql))


def split_top_level(body: str) -> list[str]:
    out: list[str] = []
    depth = 0
    current = ''
    for char in body:
        if char == '(':
            depth += 1
        elif char == ')':
            depth -= 1
        if char == ',' and depth == 0:
            out.append(current)
            current = ''
            continue
        current += char
    if current.strip():
        out.append(current)
    return out


def balanced(sql: str, open_at: int) -> str:
    """The text inside the parentheses that start at `open_at`."""
    depth = 0
    for index in range(open_at, len(sql)):
        if sql[index] == '(':
            depth += 1
        elif sql[index] == ')':
            depth -= 1
            if depth == 0:
                return sql[open_at + 1:index]
    return ''


def definitions(name: str) -> list[tuple[str, set[str]]]:
    """Every `CREATE TABLE` in one file, as (table, columns)."""
    sql = decomment((MIGRATIONS / name).read_text())
    out: list[tuple[str, set[str]]] = []
    for match in CREATE.finditer(sql):
        body = balanced(sql, match.end() - 1)
        columns = set()
        for part in split_top_level(body):
            text = part.strip()
            if not text or NON_COLUMN.match(text):
                continue
            columns.add(text.split()[0].strip('"').lower())
        out.append((match.group(1).lower(), columns))
    return out


def added(name: str) -> list[tuple[str, str]]:
    """Every `ALTER TABLE … ADD COLUMN` in one file, as (table, column).

    One ALTER can add several columns in a comma list, which is how
    20261023000000 adds five to one table; splitting on the statement and
    taking the first match would record one of them.
    """
    sql = decomment((MIGRATIONS / name).read_text())
    out: list[tuple[str, str]] = []
    for match in ALTER.finditer(sql):
        table = match.group(1).lower()
        # To the end of the statement, so a following ALTER's columns are not
        # attributed to this one.
        end = sql.find(';', match.end())
        statement = sql[match.end():end if end != -1 else len(sql)]
        for column in ADD_COLUMN.finditer(statement):
            out.append((table, column.group(1).lower()))
    return out


def world(order: list[str]) -> tuple[dict[str, set[str]], dict[str, list[str]]]:
    """Effective shape per table, and which files created each table."""
    shape: dict[str, set[str]] = {}
    creators: dict[str, list[str]] = {}
    for name in order:
        for table, columns in definitions(name):
            creators.setdefault(table, []).append(name)
            if table not in shape:            # IF NOT EXISTS: the first wins.
                shape[table] = set(columns)
        for table, column in added(name):
            if table in shape:
                shape[table].add(column)
    return shape, creators


by_name = sorted(p.name for p in MIGRATIONS.glob('*.sql'))
rest = [
    n for n in by_name
    if n not in set(migration_sets.ORIGINAL_SCHEMA)
    and n not in set(migration_sets.HAND_APPLIED_ERA)
    and n not in set(migration_sets.STAGING_ONLY)
]

# Production: the original schema, then the era applied by hand, then the rest.
PRODUCTION = migration_sets.ORIGINAL_SCHEMA + migration_sets.HAND_APPLIED_ERA + rest
# Anything this repository builds: the era is excluded and cannot be replayed.
REPO_BUILT = migration_sets.ORIGINAL_SCHEMA + rest

prod_shape, prod_creators = world(PRODUCTION)
repo_shape, _ = world(REPO_BUILT)

failures: list[str] = []

# ---- 1. the two worlds agree ------------------------------------------------
for table in sorted(set(prod_shape) | set(repo_shape)):
    on_prod = prod_shape.get(table)
    on_repo = repo_shape.get(table)
    if on_prod is None or on_repo is None:
        # A table only one world has at all is the hand-applied era itself, and
        # is check_schema_convergence.py's subject, not this one's.
        continue
    if on_prod == on_repo:
        continue
    only_prod = sorted(on_prod - on_repo)
    only_repo = sorted(on_repo - on_prod)
    failures.append(
        f'public.{table} has a different shape on the two databases. '
        + (f'Only on production: {", ".join(only_prod)}. ' if only_prod else '')
        + (f'Only on a repo-built database: {", ".join(only_repo)}. ' if only_repo else '')
        + 'It is created by '
        + ' and '.join(prod_creators.get(table, ['?']))
        + ', both with IF NOT EXISTS, so the second is a no-op and the winner is '
        'whichever ran first. Code written against either shape fails on the '
        'other, and no test suite sees both. Converge them with '
        '`ALTER TABLE … ADD COLUMN IF NOT EXISTS` the way '
        '20261023000000_one_table_one_shape.sql does.')

# ---- 2. no definition claims a column no database gets ----------------------
for name in PRODUCTION:
    for table, columns in definitions(name):
        if len(prod_creators.get(table, [])) < 2:
            continue  # The only definition cannot disagree with itself.
        allowed = KNOWN_FICTION.get((table, name), frozenset())
        for column in sorted(columns):
            if column in allowed:
                continue
            # Present in EITHER world is rule 1's business — a split is
            # reported once, there, with both sides named. Rule 2 is for a
            # column that exists nowhere at all.
            if column in prod_shape.get(table, set()) or column in repo_shape.get(table, set()):
                continue
            failures.append(
                f'{name} declares public.{table}.{column}, which NO database '
                'ends up with, in either world: another file creates this table first and '
                'IF NOT EXISTS makes this definition a no-op. A file that '
                'describes a table nobody has is read as if it were true — add '
                'the column with ALTER TABLE, or correct the definition, or '
                'record it in KNOWN_FICTION with the reason.')

if failures:
    print('A table does not have one shape:\n')
    for message in failures:
        print(f'  * {message}\n')
    print('See scripts/check_one_table_one_shape.py for why this matters.')
    sys.exit(1)

shared = len([t for t in prod_shape if t in repo_shape])
twice = len([t for t, files in prod_creators.items() if len(files) > 1])
print('Every table has one shape:')
print(f'  * {shared} tables, identical columns on production and on a repo-built database')
print(f'  * {twice} table(s) are created more than once; every definition agrees '
      f'with what\n    a database actually gets, bar {len(KNOWN_FICTION)} recorded with a reason')
