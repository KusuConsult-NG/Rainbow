#!/usr/bin/env python3
"""Nothing from the hand-applied era may exist only on production.

    python3 scripts/check_schema_convergence.py

The v2–v6 migrations (20260721 … 20260725) were applied to production by hand
and written down afterwards. They cannot be replayed from zero — v2 calls
auth.jwt() before the shim defines it, v5 builds a policy on
profiles.badge_number which arrives eleven migrations later — so
bootstrap_staging.sql and verify_rls_migration.sh exclude them, and the live
database has therefore had objects no database this repository can build has.

That is not a tidiness problem. It decided three things before anyone noticed:

  * a 428C9 error named `lga` on production and `category` in the harness, for
    the same statement, because the first generated column in ordinal order
    differs;
  * `telemetry_select_geo_lga_scoped` sat on production as TO PUBLIC for weeks
    while the harness asserted no policy reaches anon or public — and passed,
    because that policy is not in the schema it replays;
  * a code comment in dashboard/page.tsx states that profiles.lga, ward and
    sector_id are not columns. They are, on production. The conclusion was
    checked against the repository instead of the database.

20261017000000 brings the era's behaviour-affecting objects into the history.
This check keeps it that way: every object those five files create must either
be creatable by the migrations a repo-built database actually applies, or appear
in KNOWN_DIFFERENCES below with a reason.

## Its own bug, which is the reason it is written this way

The first version of this analysis extracted policies with

    CREATE\\s+POLICY\\s+"?([^"\\s]+)"?\\s+ON\\s+...(.{0,500}?)(?=;)

to capture the TO clause alongside the name. v6 creates its two policies inside
`EXECUTE $pol$ … $pol$` with USING clauses longer than 500 characters, so there
was no `;` inside the window, the match failed, and BOTH policies were silently
absent from the result — including the one that was live on production as TO
PUBLIC. The script reported "0 survive" and was believed for several minutes.

So the name and the TO clause are extracted SEPARATELY here, and the counts are
asserted: if the number of policies found in a file changes, that is a parser
failure, not a schema change.
"""
from __future__ import annotations

import importlib.util
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / 'scripts'))
import migration_sets as ms  # noqa: E402

_spec = importlib.util.spec_from_file_location(
    'smi', REPO / 'scripts' / 'sync_migration_inventory.py')
_smi = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_smi)
strip_noise = _smi.strip_noise

MIGRATIONS = REPO / 'supabase' / 'migrations'

# How many policies each era file creates. A parser that stops finding one must
# fail loudly rather than report a converged schema.
# Cross-checked against `grep -ci "CREATE POLICY"` on each file, which agrees
# exactly — so the extraction is not silently dropping one and no file mentions
# CREATE POLICY in a comment.
EXPECTED_POLICY_COUNTS = {
    '20260721000000_v2_agency_tables.sql': 11,
    '20260722000000_v3_telemetry_geofence.sql': 2,
    '20260723000000_v4_mesh_broadcast.sql': 6,
    '20260724000000_v5_rls_security.sql': 17,
    '20260725000000_v6_geo_lga_scoping_staging.sql': 2,
}

# Era objects that are allowed to exist on production and not in the schema this
# repository builds. Each needs a reason, and "it is only on production" is not
# one.
# The authoritative list of era objects a later migration removes lives in
# sync_migration_inventory.py, because that module generates the operator
# diagnostic which has to assert those objects are ABSENT, and this module
# already imports it for strip_noise — so the dependency runs one way.
# Re-exported here under its original name: check_generated_column_inserts.py
# reads `csc.DROPPED_BY_LATER`, and _verify_dropped_by_later() below is what
# checks each entry against the migration that claims to drop it.
DROPPED_BY_LATER: dict[str, str] = _smi.DROPPED_BY_LATER

# Each entry must name a migration that actually contains the drop, or this list
# becomes a way to silence the check by assertion.
def _verify_dropped_by_later() -> list[str]:
    problems = []
    for key, mig in DROPPED_BY_LATER.items():
        kind, obj = key.split(':', 1)
        matches = sorted(MIGRATIONS.glob(f'{mig}*.sql'))
        if not matches:
            problems.append(f'{key} names migration {mig}, which does not exist')
            continue
        body = matches[0].read_text(encoding='utf-8')
        needle = obj.split('.')[-1]
        if needle not in body:
            problems.append(
                f'{key} is listed as dropped by {mig}, but {matches[0].name} '
                f'does not mention {needle}')
    return problems


KNOWN_DIFFERENCES: dict[str, str] = {
}


def era_objects() -> dict[str, set[str]]:
    """{kind: {name}} created by the five hand-applied files."""
    out: dict[str, set[str]] = {
        'table': set(), 'column': set(), 'function': set(), 'policy': set()}
    for name in ms.HAND_APPLIED_ERA + ms.STAGING_ONLY:
        sql = strip_noise((MIGRATIONS / name).read_text(encoding='utf-8'))

        for m in re.finditer(
                r'(?is)CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?'
                r'(?:public\.)?"?(\w+)"?', sql):
            out['table'].add(m.group(1).lower())

        for m in re.finditer(
                r'(?is)CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+'
                r'(?:public\.)?"?(\w+)"?\s*\(', sql):
            out['function'].add(m.group(1).lower())

        # Name and table only — nothing greedy, no window, no lookahead. The
        # TO clause is a separate question and asking it here is what broke.
        policies = re.findall(
            r'(?is)CREATE\s+POLICY\s+"?([^"\s]+)"?\s+ON\s+(?:public\.)?"?(\w+)"?',
            sql)
        expected = EXPECTED_POLICY_COUNTS.get(name)
        if expected is not None and len(policies) != expected:
            raise SystemExit(
                f'✗ parser: found {len(policies)} policies in {name}, expected '
                f'{expected}. Fix the extraction before trusting this check — '
                f'under-counting here reads as a converged schema.')
        for policy, table in policies:
            out['policy'].add(f'{table.lower()}.{policy}')

        for stmt in sql.split(';'):
            a = re.search(r'(?is)\bALTER\s+TABLE\s+(?:IF\s+EXISTS\s+)?'
                          r'(?:public\.)?"?(\w+)"?', stmt)
            if not a:
                continue
            table = a.group(1).lower()
            for c in re.finditer(
                    r'(?is)\bADD\s+COLUMN\s+(?:IF\s+NOT\s+EXISTS\s+)?"?(\w+)"?',
                    stmt):
                out['column'].add(f'{table}.{c.group(1).lower()}')
    return out


def repo_objects() -> tuple[dict[str, set[str]], set[str]]:
    """What a repo-built database gets, plus every policy name it DROPs.

    The drops matter: an era policy that a later migration deliberately removes
    is not a divergence. 20261006 drops alerts_select_geo_lga_scoped for exactly
    that reason, which is why only the telemetry one survived on production.
    """
    out: dict[str, set[str]] = {
        'table': set(), 'column': set(), 'function': set(), 'policy': set()}
    dropped: set[str] = set()
    for name in ms.ORIGINAL_SCHEMA + ms.in_the_paste():
        sql = strip_noise((MIGRATIONS / name).read_text(encoding='utf-8'))
        for m in re.finditer(
                r'(?is)CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?'
                r'(?:public\.)?"?(\w+)"?', sql):
            out['table'].add(m.group(1).lower())
        for m in re.finditer(
                r'(?is)CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+'
                r'(?:public\.)?"?(\w+)"?\s*\(', sql):
            out['function'].add(m.group(1).lower())
        for policy, table in re.findall(
                r'(?is)CREATE\s+POLICY\s+"?([^"\s]+)"?\s+ON\s+(?:public\.)?"?(\w+)"?',
                sql):
            out['policy'].add(f'{table.lower()}.{policy}')
        for m in re.finditer(
                r'(?is)DROP\s+POLICY\s+(?:IF\s+EXISTS\s+)?"?([^"\s;]+)"?', sql):
            dropped.add(f'policy:{m.group(1)}')
        # A later migration may also REMOVE an era object, which is a decision
        # and not a divergence. 20261018000000 drops the five generated mirrors
        # and the two uncalled v5 functions; without this the check would demand
        # them back and the only way to satisfy it would be to undo the drop.
        #
        # ALTER TABLE ... DROP COLUMN is matched per statement so the table name
        # comes from the same statement, and the drops inside 20261018's plpgsql
        # are EXECUTE format(...) with %I rather than literal SQL, so they are
        # matched from the VALUES list instead — see DROPPED_BY_LATER below.
        for stmt in sql.split(';'):
            a = re.search(r'(?is)\bALTER\s+TABLE\s+(?:IF\s+EXISTS\s+)?'
                          r'(?:public\.)?"?(\w+)"?', stmt)
            if a:
                for c in re.finditer(
                        r'(?is)\bDROP\s+COLUMN\s+(?:IF\s+EXISTS\s+)?"?(\w+)"?',
                        stmt):
                    dropped.add(f'column:{a.group(1).lower()}.{c.group(1).lower()}')
        for m in re.finditer(
                r'(?is)DROP\s+FUNCTION\s+(?:IF\s+EXISTS\s+)?(?:public\.)?"?(\w+)"?',
                sql):
            dropped.add(f'function:{m.group(1).lower()}')
        for stmt in sql.split(';'):
            a = re.search(r'(?is)\bALTER\s+TABLE\s+(?:IF\s+EXISTS\s+)?'
                          r'(?:public\.)?"?(\w+)"?', stmt)
            if not a:
                continue
            table = a.group(1).lower()
            for c in re.finditer(
                    r'(?is)\bADD\s+COLUMN\s+(?:IF\s+NOT\s+EXISTS\s+)?"?(\w+)"?',
                    stmt):
                out['column'].add(f'{table}.{c.group(1).lower()}')
    return out, dropped


def main() -> int:
    era = era_objects()
    repo, dropped = repo_objects()

    diverged: list[str] = []
    for kind in ('table', 'column', 'function', 'policy'):
        for obj in sorted(era[kind] - repo[kind]):
            # An era object a later migration drops by name is gone on both
            # sides, so it is not a divergence.
            if kind == 'policy' and f'policy:{obj.split(".", 1)[1]}' in dropped:
                continue
            if f'{kind}:{obj}' in dropped or f'{kind}:{obj}' in DROPPED_BY_LATER:
                continue
            if f'{kind}:{obj}' in KNOWN_DIFFERENCES:
                continue
            diverged.append(f'{kind} {obj}')

    bad_list = _verify_dropped_by_later()

    stale = [k for k in KNOWN_DIFFERENCES
             if k.split(':', 1)[0] in era
             and k.split(':', 1)[1] in repo[k.split(':', 1)[0]]]

    # Printed with their own wording. An earlier version appended these to
    # `diverged`, so a DROPPED_BY_LATER error came out glued to the
    # "exists on production" template and read as two sentences run together.
    for b in bad_list:
        print(f'✗ {b}', file=sys.stderr)
    for d in diverged:
        print(f'✗ {d} exists on production and in no migration this repository '
              f'applies. Add it to 20261017000000, or record it in '
              f'KNOWN_DIFFERENCES with a reason.', file=sys.stderr)
    for s in stale:
        print(f'✗ {s} is listed as a known difference but the repository now '
              f'creates it — remove the entry.', file=sys.stderr)

    if diverged or stale or bad_list:
        print(f'\n{len(diverged) + len(stale) + len(bad_list)} problem(s).',
              file=sys.stderr)
        return 1

    counted = sum(len(v) for v in era.values())
    print(f'✓ all {counted} objects from the hand-applied era are either in the '
          f'migration history, dropped by a later migration, or recorded as a '
          f'known difference ({len(KNOWN_DIFFERENCES)})')
    return 0


if __name__ == '__main__':
    sys.exit(main())
