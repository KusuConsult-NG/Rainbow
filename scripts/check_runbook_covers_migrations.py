#!/usr/bin/env python3
"""The deployment runbook's migration table must list every outstanding migration.

    python3 scripts/check_runbook_covers_migrations.py

docs/PRODUCTION_DEPLOYMENT.md carries a numbered table — Order | File | What it
does — that is the operator's map of the paste. The "What it does" column is
hand-written and worth keeping that way: it says what BREAKS until each file
runs, which is not derivable from the SQL.

Hand-written and unchecked is a different matter. The table stopped at
`20261001000000_mesh_ingest.sql` while the repository had thirty-one outstanding
migrations, so it was seventeen short, and its prose still read "Fourteen
migrations ... ends in a 25-row PASS/FAIL table ... 2,300 lines" against a file
of 5,935 lines ending in 34 rows. An operator following it would have applied
the right script and then checked its output against the wrong description.

This is the same class of defect as T-21 and is checked the same way: the list
is derived from supabase/migrations/, and anything the table omits is named.
Adding a migration now fails CI until the runbook describes it.

## The second runbook, which this check could not see

It watched ONE file. `docs/APPLYING_THE_MIGRATIONS.md` is the step-by-step
runbook — the one README tells an operator to read **before the first paste** —
and it opened with "Nine migrations are proven in CI and not yet applied",
named those nine, and said the single-paste script applies "all nine, in order,
finishing with a 14-row PASS/FAIL table". There were thirty-seven outstanding
and the script ends in thirty-four rows. Every migration from the last fortnight
of this audit — voice notes, non-emergency routing, one table one shape — was
absent from the document an operator is sent to first.

Two documents describing one list, and the gate guarding one of them. So this
now reads every doc that names migration files: one of them must carry the
complete table, and any other that names a SUBSET must say so and point at the
complete one, in wording this check can find. A count in prose is checked
against the generated script wherever it appears.

What is deliberately NOT checked: the wording of a description. A gate that
diffed prose would be satisfied by a placeholder, and a placeholder in this
column is worse than a gap, because a gap is visible.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / 'scripts'))
import migration_sets as ms  # noqa: E402

RUNBOOK = REPO / 'docs' / 'PRODUCTION_DEPLOYMENT.md'

# A table row: | <n> | `<file>.sql` | <prose> |
ROW = re.compile(r'^\|\s*(\d+)\s*\|\s*`([^`]+\.sql)`\s*\|(.*)\|\s*$', re.M)

# The prose figures that go stale together with the table.
CLAIMS = {
    'migration count': (
        re.compile(r'\bends in a (\d+)-row PASS/FAIL table'),
        lambda: _verdict_rows()),
}

# Every other doc that names migration files. Each must declare itself partial
# and point at the file that carries the complete table — the stale one claimed
# to be the whole list.
OTHER_DOCS = [REPO / 'docs' / 'APPLYING_THE_MIGRATIONS.md']

# "…finishing with a 34-row PASS/FAIL table", in the partial docs' wording.
ROW_CLAIM = re.compile(r'(\d+)-row PASS/FAIL table')
# "all 37" / "**37 migrations**" — a count of the outstanding set in prose.
COUNT_CLAIM = re.compile(r'\ball (\d+), in order\b|\*\*(\d+) migrations\*\*')

# A count SPELLED OUT is a count this check cannot verify, and the stale claim
# was spelled out: "Nine migrations are proven in CI and not yet applied". So
# the word form is refused outright rather than parsed — a number nothing can
# check against the repository is a number that goes stale silently.
WORD_COUNT = re.compile(
    r'\b(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|'
    r'thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|'
    r'thirty|forty|fifty)([ -](one|two|three|four|five|six|seven|eight|nine))?'
    r'\s+migrations\b', re.I)


def _verdict_rows() -> int:
    """How many rows apply_all_migrations.sql's verdict table actually has."""
    sql = (REPO / 'scripts' / 'apply_all_migrations.sql').read_text(
        encoding='utf-8')
    return len(re.findall(r"^    \(\d+, '", sql, re.M))


def main() -> int:
    if not RUNBOOK.exists():
        print(f'✗ {RUNBOOK.relative_to(REPO)} is missing', file=sys.stderr)
        return 2

    text = RUNBOOK.read_text(encoding='utf-8')
    rows = ROW.findall(text)
    if not rows:
        print('✗ no migration table found in the runbook — has its format '
              'changed? This check greps for "| <n> | `<file>.sql` | ... |".',
              file=sys.stderr)
        return 2

    listed = [f for _, f, _ in rows]
    outstanding = ms.outstanding()
    problems: list[str] = []

    missing = [m for m in outstanding if m not in listed]
    for m in missing:
        problems.append(
            f'{m} is outstanding and the runbook table does not list it. Add a '
            f'row saying what breaks until it runs.')

    unknown = [f for f in listed if f not in set(ms.all_files())]
    for f in unknown:
        problems.append(
            f'the runbook lists `{f}`, which is not in supabase/migrations/ — '
            f'renamed or deleted?')

    # Order matters: an operator applies them top to bottom.
    in_order = [f for f in listed if f in set(outstanding)]
    if in_order != [m for m in outstanding if m in set(in_order)]:
        problems.append(
            'the runbook lists the migrations in a different order than '
            'filename (timestamp) order, which is the order they must be '
            'applied in.')

    # An empty description is a row that satisfies a coverage check and tells
    # the operator nothing.
    for n, f, prose in rows:
        if not prose.strip():
            problems.append(f'row {n} (`{f}`) has an empty description.')

    # The numbered column should read 1..N with no gaps or repeats, or the
    # operator loses their place in a 31-step paste.
    numbers = [int(n) for n, _, _ in rows]
    if numbers != list(range(1, len(numbers) + 1)):
        problems.append(
            f'the Order column is not 1..{len(numbers)} in sequence: {numbers}')

    # Prose figures that drift with the table.
    for label, (pattern, actual) in CLAIMS.items():
        m = pattern.search(text)
        if not m:
            problems.append(
                f'the runbook no longer states the {label} in the expected '
                f'wording, so it cannot be checked: /{pattern.pattern}/')
            continue
        want = actual()
        if int(m.group(1)) != want:
            problems.append(
                f'the runbook says {m.group(0)!r} but the verdict table has '
                f'{want} rows.')

    # Every other doc that names migrations must say it is partial and point
    # at the complete table, and any figure it quotes must be the real one.
    for doc in OTHER_DOCS:
        if not doc.exists():
            continue
        other = doc.read_text(encoding='utf-8')
        named = [f for _, f, _ in ROW.findall(other)]
        named += re.findall(r'`supabase/migrations/([^`]+\.sql)`', other)
        if not named:
            continue
        rel = doc.relative_to(REPO)
        covers_all = not [m for m in outstanding if m not in set(named)]
        if not covers_all:
            if RUNBOOK.name not in other:
                problems.append(
                    f'{rel} names migration files but not all '
                    f'{len(outstanding)} outstanding ones, and never mentions '
                    f'{RUNBOOK.name} — so an operator reading it believes '
                    f'{len(set(named) & set(outstanding))} is the whole list. '
                    'Either list them all or say which subset this is and '
                    'where the complete table lives.')
            if not COUNT_CLAIM.search(other):
                problems.append(
                    f'{rel} covers a subset and states no total, so nothing '
                    'tells the operator how many migrations there are. State '
                    f'it ({len(outstanding)}) in prose this check can find: '
                    '"**N migrations**" or "all N, in order".')
        for m in WORD_COUNT.finditer(other):
            problems.append(
                f'{rel} spells a migration count out in words: '
                f'{m.group(0)!r}. Nothing can check that against '
                'supabase/migrations/, and the stale claim this gate exists '
                f'for was exactly that shape. Write the digit ({len(outstanding)}).')
        for m in COUNT_CLAIM.finditer(other):
            said = int(m.group(1) or m.group(2))
            if said != len(outstanding):
                problems.append(
                    f'{rel} says {m.group(0)!r}, but {len(outstanding)} '
                    'migrations are outstanding.')
        for m in ROW_CLAIM.finditer(other):
            if int(m.group(1)) != _verdict_rows():
                problems.append(
                    f'{rel} says {m.group(0)!r}, but the verdict table has '
                    f'{_verdict_rows()} rows.')

    if problems:
        for p in problems:
            print(f'✗ {p}', file=sys.stderr)
        print(f'\n{len(problems)} problem(s). Edit '
              f'{RUNBOOK.relative_to(REPO)}.', file=sys.stderr)
        return 1

    print(f'✓ the runbook describes all {len(outstanding)} outstanding '
          f'migrations, in order, and its verdict-table row count matches '
          f'({_verdict_rows()})')
    print(f'✓ {len(OTHER_DOCS)} other doc(s) naming migrations declare which '
          'subset they cover, point at the complete table, and quote figures '
          'that match it')
    return 0


if __name__ == '__main__':
    sys.exit(main())
