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


def geo_key(name: str) -> str:
    """The comparison key, mirroring public.geo_key() and geo-key.ts.

    Four of the seven wards this check used to report were not missing at all:
    the GPS asset spells them with Roman numerals (GINDIRI  I) and the map with
    Arabic (GINDIRI  1). Listing those beside a genuinely absent ward made the
    report worth less than it should have been — the real gaps were buried in
    notation noise, and the notation ones looked like work nobody could do.

    They are now folded everywhere a place name is compared, so this check
    folds them too and reports only what a human still has to settle.
    """
    s = ' '.join(name.strip().upper().split())
    for roman, arabic in ((' III', ' 111'), (' II', ' 11'), (' I', ' 1')):
        if s.endswith(roman):
            return s[: -len(roman)] + arabic
    return s


def gps_wards_missing_from_map(lgas):
    """Wards the app can resolve a coordinate to, but that the map does not list.

    The app resolves an incident's ward from assets/geo/plateau_wards.json by
    nearest centroid. If a name there is absent from tactical_mapping.dart —
    and so from the console — an incident can be FILED in that ward while no
    officer can be posted to it and no filter can select it.

    Compared on geo_key(), so a difference of notation is not reported as a
    missing ward. What survives is a real divergence: a ward the map does not
    have under any spelling this code is willing to guess at.

    Reported rather than repaired: inventing the missing entries would put
    wards in the console that nobody has confirmed exist under those names.
    """
    asset = REPO / 'assets' / 'geo' / 'plateau_wards.json'
    if not asset.exists():
        return []
    known = {geo_key(w['name']) for l in lgas for w in l['wards']}
    gps = {geo_key(w['ward']): w['ward']
           for w in json.loads(asset.read_text())['wards']}
    return sorted(original for key, original in gps.items() if key not in known)


SEED = REPO / 'scripts' / 'seed_demo_incidents.sql'


def sql_values_rows(src: str, table: str):
    """Yield (column name -> literal) for each VALUES row of one INSERT.

    By column name, not by position. A regex sweep for adjacent quoted
    place-like strings was tried first and matched one column too early on the
    profiles insert — it read `'CITIZEN', 'JOS NORTH', 'ABBA NA SHEHU'` as an
    LGA, a ward and a polling unit, and reported the role as a missing LGA.
    Anything that guesses where the geography sits will find something; this
    reads the column list the statement declares.
    """
    at = src.find(f'INSERT INTO public.{table}')
    if at == -1:
        return

    open_paren = src.index('(', at)
    close_paren = src.index(')', open_paren)
    cols = [c.strip() for c in src[open_paren + 1:close_paren].split(',')]

    values_at = src.index('VALUES', close_paren)
    # The statement ends at its semicolon, or at ON CONFLICT if it has one.
    stop = min(x for x in (src.find(';', values_at),
                          src.find('ON CONFLICT', values_at),
                          len(src)) if x != -1)
    body = src[values_at + len('VALUES'):stop]

    # Split into top-level tuples, tracking quotes so a ')' or ',' inside a
    # string literal is not read as structure.
    depth, in_str, start = 0, False, None
    for i, ch in enumerate(body):
        if in_str:
            in_str = ch != "'"
            continue
        if ch == "'":
            in_str = True
        elif ch == '(':
            if depth == 0:
                start = i + 1
            depth += 1
        elif ch == ')':
            depth -= 1
            if depth == 0 and start is not None:
                yield dict(zip(cols, split_tuple(body[start:i])))
                start = None


def split_tuple(row: str):
    """The literals of one VALUES tuple, quotes stripped, commas respected."""
    out, buf, in_str = [], '', False
    for ch in row:
        if in_str:
            if ch == "'":
                in_str = False
            else:
                buf += ch
        elif ch == "'":
            in_str = True
        elif ch == ',':
            out.append(buf.strip())
            buf = ''
        else:
            buf += ch
    out.append(buf.strip())
    return out


def seed_geography_not_in_map(lgas):
    """Place names the demo seed writes that the tactical map does not know.

    ## Why this is checked and not merely synced

    The seed was written with the console's OLD invented geography — wards
    called "Bokkos Central" and "Mangu Central", polling units called
    "BEAT-MANGU-11" — none of which exist in `tactical_mapping.dart` or in the
    INEC ward list the app resolves coordinates against.

    Seeded rows carrying those names are worse than useless for a demo, because
    they look right and behave wrong in two places at once:

      * The console's ward and polling-unit filters cannot select them. The
        dropdowns are built from the map, so an operator narrowing to a ward
        sees the board go empty and has no way to tell that from quiet.

      * `alert_in_my_area()` compares `alerts.geo_ward` against
        `profiles.geo_ward`. A ward officer posted to a real ward is refused
        every seeded incident in it — so a demo of ward-level command shows an
        officer who can see nothing, which is indistinguishable from the
        scoping being broken.

    This is the same class of defect this file exists to prevent, arriving
    through the seed instead of through the console, so it is checked in the
    same place and in CI.
    """
    if not SEED.exists():
        return []

    lga_names = {l['name'].upper() for l in lgas}
    ward_names = {w['name'].upper() for l in lgas for w in l['wards']}
    pu_names = {p.upper() for l in lgas for w in l['wards'] for p in w['pollingUnits']}

    src = SEED.read_text()
    rows = list(sql_values_rows(src, 'profiles')) + list(sql_values_rows(src, 'alerts'))
    if not rows:
        print('  note: no INSERT rows parsed out of the demo seed; the geography '
              'check did not run', file=sys.stderr)
        return []

    bad = []
    for row in rows:
        for column, known, kind in (
            ('geo_lga', lga_names, 'LGA'),
            ('geo_ward', ward_names, 'ward'),
            ('geo_pu', pu_names, 'polling unit'),
        ):
            value = row.get(column, '')
            # NULL geography is legitimate: the console reports an UNLOCATED
            # count for SOS reports that reached us without a GPS fix, and the
            # seed carries some deliberately.
            if not value or value.upper() == 'NULL':
                continue
            # A collapsed run of spaces is the map's own quirk ('SHUKUR  I'),
            # not a different place; compare on a single-spaced form as well.
            squashed = {' '.join(k.split()) for k in known}
            if value.upper() not in known and ' '.join(value.upper().split()) not in squashed:
                bad.append(f'{kind} "{value}"')
    return sorted(set(bad))


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
        bad = seed_geography_not_in_map(lgas)
        if bad:
            print('✗ seed_demo_incidents.sql names places the tactical map does not '
                  'have, so the console cannot filter them and ward scoping refuses '
                  f'them:\n    {chr(10).join("    " + b for b in bad).strip()}',
                  file=sys.stderr)
            return 1
        print('✓ the app and the console agree about Plateau')
        print('✓ the demo seed names only places that exist in the map')
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
              f'not in the map under any spelling, so an incident can be filed '
              f'there while no officer can be posted to it and no filter can '
              f'select it: {", ".join(missing)}')
        print('        These need a human who knows Plateau, not a code change. '
              'KADUN/KADUNU and DAMWAI/KAMWAI are one letter apart and may or '
              'may not be the same ward; BWALL is absent outright.')


if __name__ == '__main__':
    sys.exit(main())
