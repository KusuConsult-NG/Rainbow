#!/usr/bin/env python3
"""Generate the console's tactical map from the app's, so they cannot disagree.

## Why this exists

The two maps were written separately and neither matched the other.

The app resolves an incident's ward from `assets/geo/plateau_wards.json` — the
207 real INEC wards — and its own `tactical_mapping.dart` carries the same
names plus the real polling units: BARAKIN LADI, GASSA/SHO, GINDIN AKWATI,
KATAKO, ST. MARKS PRIM. SCH. I.

The console's `tactical_mapping.ts` carried 142 invented ones in another case
entirely: "Barkin Ladi Central", "Fan", "Foron", and beats named
"BEAT-JOS_NORTH-11". No ward name in one file appears in the other.

Two things follow, and the second is the serious one:

  * The console's ward and beat filters select nothing. An alert carries
    `geo_ward = 'BARAKIN LADI'`; the dropdown offers "Barkin Ladi Central";
    `geoMatches` lowercases both and neither contains the other.

  * Row-level security compares the SAME two columns. `alert_in_my_area()`
    scopes a ward officer to alerts whose `geo_ward` matches their own, and an
    officer provisioned through the console gets a name the app never writes.
    With scoping applied, ward officers see nothing but their own reports.

The second only became true when the scoping migration landed, which is what
makes a generator worth more than a one-off correction: the two files have to
keep agreeing, and nothing was checking.

Run with --check in CI to fail on drift rather than discover it in production.
"""

import argparse
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DART = REPO / 'lib' / 'core' / 'constants' / 'tactical_mapping.dart'
TS = REPO / 'hq-dashboard-next' / 'src' / 'lib' / 'tactical_mapping.ts'


def parse_dart():
    """Read the LGAs, wards and polling units out of the Dart literal.

    A parser rather than a regex sweep over the whole file: the polling unit
    lists are long and contain apostrophes and slashes, and QUA'AN PAN is
    written with double quotes for its apostrophe — a single-quote sweep
    silently returns sixteen LGAs instead of seventeen.
    """
    src = DART.read_text()
    out = []

    for lga_match in re.finditer(
        r"TacticalJurisdiction\(\s*id:\s*'([^']+)',\s*name:\s*(?:'([^']*)'|\"([^\"]*)\")",
        src,
    ):
        lga_id = lga_match.group(1)
        lga_name = lga_match.group(2) if lga_match.group(2) is not None else lga_match.group(3)

        # Everything until the next LGA is this one's body.
        start = lga_match.end()
        nxt = src.find('TacticalJurisdiction(', start)
        body = src[start:nxt if nxt != -1 else len(src)]

        wards = []
        for w in re.finditer(
            r"TacticalWard\(\s*id:\s*'([^']+)',\s*name:\s*(?:'([^']*)'|\"([^\"]*)\")"
            r"\s*,\s*pollingUnits:\s*\[(.*?)\]",
            body,
            re.S,
        ):
            ward_name = w.group(2) if w.group(2) is not None else w.group(3)
            pus = [
                (m.group(1) if m.group(1) is not None else m.group(2))
                for m in re.finditer(r"'([^']*)'|\"([^\"]*)\"", w.group(4))
            ]
            wards.append({
                'id': w.group(1),
                'name': ward_name,
                'pollingUnits': [p for p in pus if p.strip()],
            })

        out.append({'id': lga_id, 'name': lga_name, 'wards': wards})

    return out


def render(lgas):
    """The map as a TypeScript array literal. JSON is valid TS here."""
    return json.dumps(lgas, indent=2, ensure_ascii=False)


def splice(generated_array: str) -> str:
    """Replace ONLY the plateauTacticalMap array, keeping the rest of the file.

    The first attempt regenerated the whole file and appended everything from
    STATE_SECURITY_AGENCIES onwards — but that constant is declared BEFORE the
    map, so the old map came back with it and TypeScript reported
    plateauTacticalMap declared twice. This file also holds the SecurityAgency
    interface and `siecWards` on some entries, none of which the Dart map
    knows about.

    So: find the declaration, find the end of its array by matching brackets,
    and swap that span. Everything the console defines for itself survives
    untouched.
    """
    src = TS.read_text()
    decl = src.find('export const plateauTacticalMap')
    if decl == -1:
        raise SystemExit('✗ plateauTacticalMap not found in the console map')

    # `= [`, not the first '[' after the declaration: that one is inside the
    # type annotation `TacticalJurisdiction[]`, and matching brackets from
    # there ends the array in the wrong place.
    start = src.index('[', src.index('=', decl))
    depth = 0
    for j in range(start, len(src)):
        if src[j] == '[':
            depth += 1
        elif src[j] == ']':
            depth -= 1
            if depth == 0:
                end = j + 1
                break
    else:
        raise SystemExit('✗ could not find the end of the map array')

    return src[:start] + generated_array + src[end:]


def gps_wards_missing_from_map(lgas):
    """Wards the app can resolve a coordinate to, but that the map does not list.

    The app resolves an incident's ward from assets/geo/plateau_wards.json by
    nearest centroid. If a name there is absent from tactical_mapping.dart —
    and so from the console — an incident can be FILED in that ward while no
    officer can be posted to it and no filter can select it.

    Reported rather than repaired: inventing the missing entries would put
    wards in the console that nobody has confirmed exist under those names.
    """
    asset = REPO / 'assets' / 'geo' / 'plateau_wards.json'
    if not asset.exists():
        return []
    gps = {w['ward'] for w in json.loads(asset.read_text())['wards']}
    known = {w['name'] for l in lgas for w in l['wards']}
    return sorted(gps - known)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--check', action='store_true',
                    help='fail if the generated file differs from the one on disk')
    args = ap.parse_args()

    lgas = parse_dart()
    if len(lgas) != 17:
        print(f'✗ parsed {len(lgas)} LGAs from the Dart map, expected 17', file=sys.stderr)
        return 1

    wanted = splice(render(lgas))

    if args.check:
        if TS.read_text() != wanted:
            print('✗ tactical_mapping.ts is out of date with tactical_mapping.dart.',
                  file=sys.stderr)
            print('  Run: python3 scripts/sync_tactical_map.py', file=sys.stderr)
            return 1
        print('✓ the app and the console agree about Plateau')
        report_gaps(lgas)
        return 0

    TS.write_text(wanted)
    total_wards = sum(len(l['wards']) for l in lgas)
    total_pus = sum(len(w['pollingUnits']) for l in lgas for w in l['wards'])
    print(f'✓ wrote {TS.relative_to(REPO)}: '
          f'{len(lgas)} LGAs, {total_wards} wards, {total_pus} polling units')
    report_gaps(lgas)
    return 0


def report_gaps(lgas):
    missing = gps_wards_missing_from_map(lgas)
    if missing:
        print(f'  note: {len(missing)} ward(s) exist in the GPS centroid data but '
              f'not in the map, so an incident can be filed there while no '
              f'officer can be posted to it: {", ".join(missing)}')


if __name__ == '__main__':
    sys.exit(main())
