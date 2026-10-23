#!/usr/bin/env python3
"""No screen may put a person at a coordinate nobody measured.

    python3 scripts/check_no_invented_coordinates.py

## What went wrong

`safe_zone_screen.dart` showed a citizen the shelters to run to. When the
query failed it returned three hardcoded ones from a bare `catch (_)` —
"JOS SOUTH COMMAND HQ" at 9.9285, 8.8921, "BUKURU TACTICAL OUTPOST" at
9.8000, 8.8700, "JOS NORTH POLICE DIVISION" at 9.9333, 8.8833 — with invented
capacities, and the screen then drew a ROUTE to the nearest.

Any failure reached that catch: no network, a refused row, a missing table.
And the provider THREW on a successful empty result, so a correctly configured
project with no shelters recorded yet showed the same three. A person fleeing
an armed attack was given directions to a position produced by a literal in a
catch block, with nothing on screen to say so.

A zone whose latitude was null became `0.0, 0.0` — the Gulf of Guinea, 700km
offshore — drawn on the map as somewhere to go.

This is C-5 one screen further out. `AlertService` was fixed long ago to leave
coordinates NULL rather than default to the centre of Jos, and
`check_no_invented_places.py` holds every screen that NAMES a place it never
measured. Neither looks at a coordinate LITERAL standing in for data.

## What this checks

No coordinate-shaped literal in `lib/` sits where a position for a person or
a place is produced — a data fallback, a `??` default, a model constructor.

A MAP VIEWPORT is exempt and named as such: `agent_dashboard_screen.dart`
centres an empty tactical map on Plateau State rather than on a street in Jos,
which is where the camera starts and is never attached to a report. The file
says so in six lines of comment. The distinction this check enforces is
exactly that one: a camera may have a default, a position may not.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
LIB = REPO / 'lib'

# THE APP WAS NOT THE ONLY PLACE THAT COULD INVENT A POSITION.
#
# This gate read `lib/` and nothing else, because the app is where C-5 and T-74
# were found. Two other trees write and draw positions:
#
#   supabase/functions/   Deno edge functions, which INSERT into alerts
#   hq-dashboard-next/src the console, which draws them
#
# `ai-triage/index.ts` had `latitude: latitude || 9.9167` in the INSERT. Not a
# display fallback — it wrote the centre of Jos into `alerts` as the position of
# a report that had no fix, permanently, for every consumer downstream. Strictly
# worse than C-5, in the one tree this check could not see. T-84.
EXTRA_TREES = [
    (REPO / 'supabase/functions', ('*.ts',)),
    (REPO / 'hq-dashboard-next/src', ('*.ts', '*.tsx')),
]

# AND NEITHER TREE WAS WHERE THE COORDINATES WERE.
#
# This check exists because `safe_zone_screen.dart` routed a fleeing citizen to
# three shelters produced by a literal in a `catch` block. The fix made the
# screen return nothing when the query fails, and the screen now reads the real
# `safe_zones` table.
#
# `phase1_foundation.sql` fills that table:
#
#   ('JOS SOUTH COMMAND HQ',      ..., 9.8965, 8.8583, 'COMMAND_HQ', 'JOS SOUTH'),
#   ('BUKURU TACTICAL OUTPOST',   ..., 9.7952, 8.8521, 'OUTPOST',    'JOS SOUTH'),
#   ('JOS NORTH POLICE DIVISION', ..., 9.9281, 8.8921, 'POLICE',     'JOS NORTH'),
#   ('PLATEAU STATE HQ',          ..., 9.9167, 8.8917, 'COMMAND_HQ', 'JOS NORTH'),
#   ('BARKIN LADI SAFE POINT',    ..., 9.5167, 8.9167, 'SAFE_POINT', 'BARKIN LADI'),
#   ('MANGU COMMAND POST',        ..., 9.7167, 9.0500, 'COMMAND_HQ', 'MANGU'),
#   ('JOS EAST TACTICAL OUTPOST', ..., 9.9500, 8.9600, 'OUTPOST',    'JOS EAST'),
#
# Seven positions people are told to run to, and the numbers say where they came
# from. `9.9167, 8.8917` is the centroid of Jos — the same literal this project
# removed from `ai-triage/index.ts`, where it was writing the centre of the city
# into `alerts` as the position of a report with no fix. `9.5167` is 9°31'00",
# `9.7167` is 9°43'00", `9.0500` is 9°03'00": round to the arc-minute, which is
# what a gazetteer gives for a TOWN, not what a survey gives for a building.
# And the fallback this check was written to delete had `JOS SOUTH COMMAND HQ`
# at 9.9285, 8.8921 while the seed has it at 9.8965, 8.8583 — two positions,
# 3.6km apart, for one place. Neither was measured; that is why they differ.
#
# So the literal moved out of the catch block and into the table the catch block
# was standing in for, and this check could not see it, because it read code and
# the data is in SQL. The same shape as every other gap found in this audit: a
# check reading a subset of its subject. T-93.
SQL_TREES = [
    (REPO / 'supabase/migrations', ('*.sql',)),
    (REPO / 'scripts', ('*.sql',)),
]

# Generated concatenations of the migrations. Reading them would report every
# finding twice and point at a file nobody edits.
SQL_GENERATED = re.compile(
    r'apply_in_parts/|apply_all_migrations\.sql$|bootstrap_staging\.sql$'
    r'|rainbow_full_migration\.sql$')

# A behaviour test's fixture coordinates are the point of the test, exactly as
# for a .test.ts. And `seed_demo_incidents.sql` is named: it writes positions
# for incidents that do not exist, is headed STAGING OR LOCAL ONLY in a box,
# prefixes every row `[DEMO]`, and deletes exactly what it added. Invented
# coordinates are its PURPOSE, declared where anybody reading it will see it.
SQL_SKIP = re.compile(
    r'_behaviour_test\.sql$|^scripts/test_rls_migration\.sql$'
    r'|^scripts/signup_role_escalation_test\.sql$'
    r'|^scripts/seed_demo_incidents\.sql$')

# What makes a stored position honest: the row says whether anybody stood at it.
# A coordinate written into `safe_zones` without `verified_at` in the same
# statement is a guess presented as a survey, and a citizen in an emergency is
# routed to it. With the column named, the author had to decide, and the app can
# tell the citizen which it is.
SQL_PROVENANCE = 'verified_at'

# A range test, not a placement. `BETWEEN 8.3 AND 10.4` bounds what the table
# will accept; it never puts anybody anywhere.
SQL_BOUND = re.compile(r'\bCHECK\b|\bBETWEEN\b|\bNOT\s+BETWEEN\b', re.I)

# A test's own fixture coordinates are the point of the test.
SKIP_FILE = re.compile(r'\.(test|spec)\.(ts|tsx|dart)$|/__tests__/')

# Reference geography, not an invented position: the ward centroids are real
# surveyed points, generated as data, and `check_ward_centroids`-style parity
# against the app's copy is asserted by its own step in CI. A coordinate that
# IS the data cannot be a coordinate standing in for missing data.
EXEMPT_DATA = ('ward_centroids.ts', 'plateau_wards.ts', 'plateau_lgas.ts')

# Plateau sits near 9°N, 9°E, so a decimal in these ranges with three or more
# places is a coordinate rather than a size, an opacity or a version.
COORD = re.compile(r'(?<![\w.])(?:[4-9]|1[0-4])\.\d{3,}(?![\w])')

# Where a camera is allowed to start. Each is a viewport, not a position, and
# each says so where it is written.
EXEMPT_VIEWPORT = re.compile(
    r'\b(initialCenter|center|initialZoom|zoom|cameraPosition)\s*[:=]')


def live(path: Path) -> str:
    """The file with its comments blanked, line positions kept."""
    src = re.sub(r'/\*.*?\*/', lambda m: re.sub(r'[^\n]', ' ', m.group(0)),
                 path.read_text(), flags=re.S)
    # `--` in SQL, `//` everywhere else. A comment explaining why a coordinate
    # is wrong must not itself read as a coordinate standing in for data.
    opener = ('--',) if path.suffix == '.sql' else ('//', '///')
    return '\n'.join(
        '' if line.lstrip().startswith(opener) else line
        for line in src.split('\n'))


def statement_around(text: str, pos: int) -> str:
    """The SQL statement containing `pos`, by semicolon."""
    start = text.rfind(';', 0, pos) + 1
    end = text.find(';', pos)
    return text[start:end if end >= 0 else len(text)]


def files_to_read():
    """Every file that could place somebody somewhere, in every tree."""
    for path in sorted(LIB.rglob('*.dart')):
        yield path
    for root, patterns in EXTRA_TREES:
        if not root.is_dir():
            continue
        for pattern in patterns:
            for path in sorted(root.rglob(pattern)):
                rel = str(path.relative_to(REPO))
                if SKIP_FILE.search(rel) or '/node_modules/' in rel:
                    continue
                if '/.next/' in rel or path.name in EXEMPT_DATA:
                    continue
                yield path
    for root, patterns in SQL_TREES:
        if not root.is_dir():
            continue
        for pattern in patterns:
            for path in sorted(root.rglob(pattern)):
                rel = str(path.relative_to(REPO))
                if SQL_GENERATED.search(rel) or SQL_SKIP.search(rel):
                    continue
                yield path


findings: list[str] = []
checked = 0

for path in files_to_read():
    code = live(path)
    checked += 1
    for match in COORD.finditer(code):
        line_no = code[:match.start()].count('\n')
        lines = code.split('\n')
        line = lines[line_no]
        # The viewport keyword may be a few lines above the literal: an empty
        # map's centre is written as a ternary, so `center:` sits above
        # `? const LatLng(…)` with its explanation in between. Reading only
        # the literal's own line reported the one documented exception in the
        # codebase as a fault, which is how this window got here.
        #
        # Counted in NON-EMPTY lines, because `live()` blanks comments while
        # keeping the line numbers: a raw window of three covered three blank
        # comment lines and stopped one short of the `center:` it was looking
        # for. Widening the raw number would have worked and would also have
        # reached further into unrelated code every time a comment was added.
        window, back = [line], line_no - 1
        while back >= 0 and len(window) < 4:
            if lines[back].strip():
                window.append(lines[back])
            back -= 1
        window = '\n'.join(window)
        if path.suffix == '.sql':
            # No such thing as a viewport in SQL: every coordinate here is
            # STORED, which is worse than a display fallback — it is the
            # position of that place for every consumer, for ever. The only
            # thing that makes one honest is the row saying whether anybody
            # stood at it.
            statement = statement_around(code, match.start())
            if SQL_PROVENANCE in statement:
                continue
            # A BOUND is not a position, which is the same distinction as a
            # viewport having a default while a position may not. The CHECK on
            # safe_zones refuses a row outside Plateau State, and the extent it
            # names is the extent of the 207 surveyed ward centroids: no row is
            # ever placed at one of these numbers.
            if SQL_BOUND.search(statement):
                continue
        elif EXEMPT_VIEWPORT.search(window):
            continue
        where = f'{path.relative_to(REPO)}:{line_no + 1}'
        if any(item.startswith(f'{where}  ') for item in findings):
            continue  # one line, one finding, however many numbers are on it
        # `LatLng(a, b)` built from variables is fine; a literal inside one is
        # only a problem when it is not a viewport, which the line above
        # already decided.
        findings.append(f'{where}  {line.strip()[:96]}')

if findings:
    print('A coordinate literal stands where a measured position belongs:\n')
    for item in findings:
        print(f'  {item}')
    print()
    print('A person cannot be sent to a number somebody typed. If the real')
    print('position is missing, return nothing and let the screen say so —')
    print('every one of these screens already has an empty state. A map')
    print('VIEWPORT may have a default; a position may not.')
    print()
    print('In SQL the position is STORED, so there is no empty state to fall')
    print('back to and no screen that can tell. Name `verified_at` in the same')
    print(f'statement: NULL for a position nobody has stood at yet, which is')
    print('what the seeded shelters are, and the app then says so to the')
    print('citizen instead of drawing a route as though it were surveyed.')
    print('See E2E_AUDIT_REPORT.md T-93.')
    sys.exit(1)

print('OK: no screen places anybody at a coordinate nobody measured.')
print(f'  * {checked} file(s) read across lib/, supabase/functions/, the '
      'console and the migrations, comments excluded')
print('  * a stored position must name verified_at in its own statement, '
      'because there is no screen to say it is a guess')
print('  * a map viewport centre is exempt and must say so on its own line')
print(f'  * {len(EXEMPT_DATA)} reference-geography file(s) exempt by name, '
      'because there the coordinates ARE the data')
