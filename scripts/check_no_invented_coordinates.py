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
    src = re.sub(r'/\*.*?\*/', lambda m: re.sub(r'[^\n]', ' ', m.group(0)),
                 path.read_text(), flags=re.S)
    return '\n'.join(
        '' if line.lstrip().startswith(('//', '///')) else line
        for line in src.split('\n'))


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
        if EXEMPT_VIEWPORT.search(window):
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
    sys.exit(1)

print('OK: no screen places anybody at a coordinate nobody measured.')
print(f'  * {checked} file(s) read across lib/, supabase/functions/ and the '
      'console, comments excluded')
print('  * a map viewport centre is exempt and must say so on its own line')
print(f'  * {len(EXEMPT_DATA)} reference-geography file(s) exempt by name, '
      'because there the coordinates ARE the data')
