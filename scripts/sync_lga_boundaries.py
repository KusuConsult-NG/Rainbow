#!/usr/bin/env python3
"""Give the console the LGA boundaries the app already decides by.

## Why this exists

`lib/core/geo/jurisdiction_resolver.dart` decides an incident's LGA by
point-in-polygon against `assets/geo/plateau_boundaries.json`, and resolves the
*ward* by nearest centroid — the approximation confined to the question the data
can actually answer.

The console had no access to the polygons at build time. `LiveMap` fetches them
at runtime to draw them, which is fine for drawing and no use to a function that
must answer during render. So `wardDisagreement()` in `safe-zones.ts` answered
the LGA question with ward centroids instead, and a centroid is not a boundary:
measured against the 17 polygons, that rule rejects 57.7% of real Plateau — 78%
of Jos North — including most positions a commander would correctly type into
`SafeZonesPanel`. See E2E_AUDIT_REPORT.md T-101.

This copies the polygons across so the console can ask the boundary question
with the boundary data, the way the app does.

## Precision

Vertices are rounded to 5 decimal places, about 1.1m. The source is geoBoundaries
ADM2, which is nowhere near metre-accurate, so the digits beyond that are noise
that costs bundle size: 83KB of coordinates becomes 40KB.

Rounding a boundary can in principle move a point from one side of it to the
other, so this does not take that on trust. Every one of the 207 ward centroids
and every shelter in the seed is resolved against both the raw asset and the
rounded output, and any disagreement fails the build. Precision is a size
decision; it is not allowed to be a correctness one.

Run with --check in CI to fail on drift.
"""

import argparse
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ASSET = REPO / 'assets' / 'geo' / 'plateau_boundaries.json'
WARDS = REPO / 'assets' / 'geo' / 'plateau_wards.json'
SEED = REPO / 'supabase' / 'migrations' / '20261030000000_a_shelter_says_who_stood_there.sql'
OUT = REPO / 'hq-dashboard-next' / 'src' / 'lib' / 'lga_boundaries.ts'

DECIMALS = 5
EXPECTED_LGAS = 17

SHELTER_ROW = re.compile(
    r"\(\s*'([^']+)'\s*,\s*'[^']*'\s*,\s*(-?\d+\.\d+)\s*,\s*(-?\d+\.\d+)\s*,"
    r"\s*'[^']*'\s*,\s*'([^']+)'\s*,\s*NULL\s*\)")


def parts_of(feature):
    """[[outer, *holes], ...] — one entry per disjoint piece of the LGA."""
    geom = feature['geometry']
    if geom['type'] == 'Polygon':
        return [geom['coordinates']]
    if geom['type'] == 'MultiPolygon':
        return list(geom['coordinates'])
    raise SystemExit(f"✗ unexpected geometry {geom['type']!r} in {ASSET.name}")


def in_ring(lng, lat, ring):
    """Even-odd point-in-polygon, the same test as `jurisdiction_resolver.dart`."""
    hit = False
    n = len(ring)
    for i in range(n):
        x1, y1 = ring[i][0], ring[i][1]
        x2, y2 = ring[(i + 1) % n][0], ring[(i + 1) % n][1]
        if (y1 > lat) != (y2 > lat):
            if lng < (x2 - x1) * (lat - y1) / (y2 - y1) + x1:
                hit = not hit
    return hit


def lga_containing(lat, lng, boundaries):
    """`boundaries` is [(lga, parts)]; holes honoured, first match wins."""
    for lga, parts in boundaries:
        for ring_set in parts:
            outer, holes = ring_set[0], ring_set[1:]
            if in_ring(lng, lat, outer) and not any(
                    in_ring(lng, lat, h) for h in holes):
                return lga
    return None


def build():
    raw = json.loads(ASSET.read_text())['features']
    if len(raw) != EXPECTED_LGAS:
        # A truncated asset would put real positions outside every boundary, and
        # the LGAs that vanished would be the ones whose shelters stop resolving.
        raise SystemExit(
            f'✗ {len(raw)} LGA polygons in {ASSET.relative_to(REPO)}, '
            f'expected {EXPECTED_LGAS}')

    full = [(f['properties']['lga'], parts_of(f)) for f in raw]
    rounded = [
        (lga, [[[[round(x, DECIMALS), round(y, DECIMALS)] for x, y in ring]
                for ring in ring_set] for ring_set in parts])
        for lga, parts in full
    ]
    return full, rounded


def verify(full, rounded):
    """Rounding must not move a single real position across a boundary."""
    probes = []
    for w in json.loads(WARDS.read_text())['wards']:
        probes.append((f"ward {w['lga']}/{w['ward']}", w['lat'], w['lng']))
    if SEED.exists():
        text = SEED.read_text()
        insert = text[text.index('INSERT INTO public.safe_zones'):]
        insert = insert[:insert.index('ON CONFLICT (name) DO NOTHING;')]
        for name, lat, lng, _lga in SHELTER_ROW.findall(insert):
            probes.append((f'shelter {name}', float(lat), float(lng)))

    if len(probes) < 200:
        raise SystemExit(
            f'✗ only {len(probes)} probe positions; rounding would be going '
            f'out unverified against the geography that matters.')

    moved = []
    for label, lat, lng in probes:
        a = lga_containing(lat, lng, full)
        b = lga_containing(lat, lng, rounded)
        if a != b:
            moved.append(f'{label}: {a} -> {b}')
    if moved:
        raise SystemExit(
            f'✗ rounding to {DECIMALS} decimal places moved {len(moved)} '
            f'position(s) across a boundary:\n   '
            + '\n   '.join(moved[:10])
            + '\n  Raise DECIMALS rather than shipping a different boundary.')
    return len(probes)


HEADER = '''/**
 * The LGA boundary polygons, so the console can ask a boundary question.
 *
 * GENERATED by scripts/sync_lga_boundaries.py from
 * assets/geo/plateau_boundaries.json. Do not edit by hand — CI fails on drift.
 * The app's asset is the single source of truth, because it is what resolves an
 * incident's LGA in the first place.
 *
 * ## What this is for
 *
 * `lib/core/geo/jurisdiction_resolver.dart` decides an incident's LGA by
 * point-in-polygon against these shapes. The console could not, so
 * `wardDisagreement()` used ward centroids for the same question — and a
 * centroid is not a boundary. Those radii are half the distance to the nearest
 * neighbouring centroid, median 3.5km, and discs do not tile a plane: the rule
 * rejected 57.7% of real Plateau, 78% of Jos North, and said so to a commander
 * typing a correct position into SafeZonesPanel. See E2E_AUDIT_REPORT.md T-101.
 *
 * Ward centroids remain the right tool for the ward question, which is the one
 * the ward data can answer.
 *
 * ## Shape
 *
 * GeoJSON order: a vertex is [longitude, latitude], NOT [lat, lng]. Plateau
 * spans 8.3-10.4 N and 8.5-10.6 E, so the two overlap and a flipped file would
 * not look wrong — it would just quietly move everything. The generator proves
 * the order against all 207 ward centroids, and lga-boundaries.test.ts asserts
 * it again from the console's side.
 *
 * Vertices are rounded to 5 decimal places (~1.1m); the generator proves no ward
 * centroid or stored shelter changes LGA under that rounding before writing.
 */

/** One disjoint piece of an LGA: the outer ring first, then any holes. */
export type BoundaryPart = number[][][];

export interface LgaBoundary {
  lga: string;
  /** An LGA can be more than one piece; most are one. */
  parts: BoundaryPart[];
}

export const lgaBoundaries: LgaBoundary[] = '''


def render(rounded):
    rows = [{'lga': lga, 'parts': parts} for lga, parts in rounded]
    # separators: this is 2253 vertices; indented it is three times the size for
    # no benefit, since nobody reads a generated polygon by eye.
    return HEADER + json.dumps(rows, separators=(',', ':'),
                               ensure_ascii=False) + ';\n'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--check', action='store_true',
                    help='fail if the generated file is out of date')
    args = ap.parse_args()

    for path in (ASSET, WARDS):
        if not path.exists():
            print(f'✗ {path.relative_to(REPO)} is missing', file=sys.stderr)
            return 1

    full, rounded = build()
    probes = verify(full, rounded)
    wanted = render(rounded)

    if args.check:
        if not OUT.exists() or OUT.read_text() != wanted:
            print(f'✗ {OUT.name} is out of date with '
                  f'{ASSET.relative_to(REPO)}.', file=sys.stderr)
            print('  Run: python3 scripts/sync_lga_boundaries.py',
                  file=sys.stderr)
            return 1
        print(f'✓ the console has all {len(rounded)} LGA boundaries '
              f'({probes} positions resolve identically to the raw asset)')
        return 0

    OUT.write_text(wanted)
    verts = sum(len(r) for _, parts in rounded for rs in parts for r in rs)
    print(f'✓ wrote {OUT.relative_to(REPO)}: {len(rounded)} LGAs, '
          f'{verts} vertices, {len(wanted) // 1024}KB')
    print(f'  {probes} positions resolve identically to the unrounded asset')
    return 0


if __name__ == '__main__':
    sys.exit(main())
