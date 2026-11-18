#!/usr/bin/env python3
"""A shelter's position must be inside the LGA its own row claims.

    python3 scripts/check_a_shelter_is_where_it_says.py

## What went wrong

`safe_zone_screen.dart` shows a citizen where to run and draws a route to the
nearest shelter. The shelters come from `public.safe_zones`, seeded with seven
rows whose coordinates nobody measured — `PLATEAU STATE HQ` sat at the centroid
of Jos to four decimal places, `BARKIN LADI SAFE POINT` at 9°31'00" 8°55'00",
and the deleted catch-block fallback had `JOS SOUTH COMMAND HQ` 3.6km from where
the seed puts it. Two positions for one place is what an unmeasured coordinate
looks like from outside.

`check_no_invented_coordinates.py` now requires a stored position to name
`verified_at`, so the row has to say whether anybody stood there. That is the
honesty requirement, and it is not the same as being right.

## The rule this check used to apply, and why it was replaced

T-94 asked whether a shelter is inside the LGA it claims, and answered it with
the 207 surveyed ward centroids: a position passed if it fell within the radius
of the nearest centroid of that LGA. It reached the right verdict on all seven
seeded rows — but the rule itself does not work.

Those radii are half the distance to the nearest neighbouring centroid, median
3.5km, and discs do not tile a plane. Sampling 400 points inside each of the 17
LGA polygons — real territory, every point correctly placed by the app's own
rule — the centroid rule rejects **57.7% of them**: 78% of Jos North, 70% of
Barkin Ladi, 66% of Jos South. A correctly sited shelter added to the seed would
have failed this check more often than it passed.

It also made the fault sound larger than it is. "11.24km from the nearest JOS
SOUTH ward centroid" is a distance to the middle of a ward, and the median gap
between neighbouring centroids statewide is 6.84km — so 11km is ordinary
spacing, not displacement. `JOS SOUTH COMMAND HQ` is under 900m outside Jos
South's boundary. It is in the wrong LGA, which is the finding; it is not eleven
kilometres adrift, which is what the old wording implied.

## The rule now

`assets/geo/plateau_boundaries.json` holds the 17 real ADM2 polygons, and
point-in-polygon against them is a boundary test with no approximation in it.
That is already how `lib/core/geo/jurisdiction_resolver.dart` decides an
incident's LGA, so a shelter and an incident are now judged by one rule instead
of two that disagree across most of the state.

**Still on the old rule:** `wardDisagreement()` in
`hq-dashboard-next/src/lib/safe-zones.ts`, which warns a commander as they type
a position into `SafeZonesPanel` and flags stored rows in the list. It applies
the centroid test this check just stopped applying, so it raises a false warning
on most of real Jos North — on the very screen built for command to CORRECT the
three bad shelters. That is a user-facing fault and the larger half of this
defect; it is not fixed here because the console has no synchronous access to
the polygons (`LiveMap` fetches `/plateau_boundaries.json` at runtime) and
giving it one is a design decision, not a rewrite of a rule.

Ward centroids are still read, but only to NAME the nearest ward in the output,
never to decide pass or fail. Naming a ward from a centroid is an approximation
the app makes too, and it is fine for a message; it was never fit to carry a
verdict.

The three seeded rows T-94 deactivated fail the boundary test as well, each in a
different LGA from the one it claims:

    JOS SOUTH COMMAND HQ       claims JOS SOUTH  -> Jos North
    JOS EAST TACTICAL OUTPOST  claims JOS EAST   -> Jos North
    MANGU COMMAND POST         claims MANGU      -> Barkin Ladi

and the other four pass. The verdict is unchanged; the reasoning behind it is
now sound.

## What this checks

Every shelter this repository stores sits inside the LGA polygon its row names —
or is explicitly deactivated, so the citizen app never routes to it. Both
directions are enforced: a position that is right must not be hidden, and a
position that is wrong must not be shown.

This cannot check what `publish_safe_zone()` stores at runtime — only what is in
the repository. That is what `verified_by` is for: the database cannot know
whether a coordinate is real, so it insists somebody's id is against it.
"""
from __future__ import annotations

import json
import math
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SEED = REPO / 'supabase/migrations/20261030000000_a_shelter_says_who_stood_there.sql'
CENTROIDS = REPO / 'hq-dashboard-next/src/lib/ward_centroids.ts'
BOUNDARIES = REPO / 'assets/geo/plateau_boundaries.json'
RESOLVER = REPO / 'lib/core/geo/jurisdiction_resolver.dart'

# ('NAME', 'description', lat, lon, 'TYPE', 'LGA', NULL)
ROW = re.compile(
    r"\(\s*'([^']+)'\s*,\s*'[^']*'\s*,\s*(-?\d+\.\d+)\s*,\s*(-?\d+\.\d+)\s*,"
    r"\s*'[^']*'\s*,\s*'([^']+)'\s*,\s*NULL\s*\)")
# ('NAME',  lat, lon)  — the deactivation list
HIDDEN = re.compile(
    r"\(\s*'([^']+)'\s*,\s*(-?\d+\.\d+)\s*,\s*(-?\d+\.\d+)\s*\)")

faults: list[str] = []


def key(name: str) -> str:
    """LGA names across the three assets differ only in case and punctuation.

    "Qua'an Pan" in the boundary file is "QUA'AN PAN" in the ward data and
    "QUAAN PAN" if somebody types it. Parity between the assets is asserted
    below, so this cannot quietly paper over a genuinely different name.
    """
    return name.upper().replace("'", '').replace('-', ' ').replace('  ', ' ').strip()


def haversine_km(a_lat: float, a_lon: float, b_lat: float, b_lon: float) -> float:
    r = 6371.0088
    p1, p2 = math.radians(a_lat), math.radians(b_lat)
    dp, dl = p2 - p1, math.radians(b_lon - a_lon)
    h = (math.sin(dp / 2) ** 2
         + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2)
    return 2 * r * math.asin(math.sqrt(h))


def parts(feature: dict) -> list[tuple[list, list]]:
    """[(outer_ring, [hole, ...]), ...] for Polygon and MultiPolygon alike."""
    geom = feature['geometry']
    polys = ([geom['coordinates']] if geom['type'] == 'Polygon'
             else geom['coordinates'])
    return [(p[0], p[1:]) for p in polys]


def in_ring(lng: float, lat: float, ring: list) -> bool:
    """Even-odd point-in-polygon, as `jurisdiction_resolver.dart` does it."""
    hit = False
    n = len(ring)
    for i in range(n):
        x1, y1 = ring[i][0], ring[i][1]
        x2, y2 = ring[(i + 1) % n][0], ring[(i + 1) % n][1]
        if (y1 > lat) != (y2 > lat):
            if lng < (x2 - x1) * (lat - y1) / (y2 - y1) + x1:
                hit = not hit
    return hit


def lga_containing(lat: float, lng: float, features: list) -> str | None:
    """The LGA whose polygon contains this point, holes honoured."""
    for f in features:
        for outer, holes in parts(f):
            if in_ring(lng, lat, outer) and not any(
                    in_ring(lng, lat, h) for h in holes):
                return f['properties']['lga']
    return None


def load_centroids() -> list[dict]:
    text = CENTROIDS.read_text(encoding='utf-8')
    marker = 'wardCentroids: WardCentroid[] = '
    if marker not in text:
        raise SystemExit(
            f'✗ {CENTROIDS.relative_to(REPO)} has no `{marker.strip()}`; this '
            f'check cannot read the surveyed geography it depends on.')
    body = text[text.index(marker) + len(marker):]
    return json.loads(body[:body.rindex(']') + 1])


for path in (SEED, CENTROIDS, BOUNDARIES, RESOLVER):
    if not path.is_file():
        raise SystemExit(f'✗ {path.relative_to(REPO)} is missing')

features = json.load(BOUNDARIES.open(encoding='utf-8'))['features']
centroids = load_centroids()

# ── Guards, so this cannot pass by reading nothing ──────────────────────────
if len(centroids) < 100:
    raise SystemExit(
        f'✗ only {len(centroids)} ward centroids read; this check names wards '
        f'from them and a short list would mislabel every shelter.')
if len(features) < 17:
    raise SystemExit(
        f'✗ only {len(features)} LGA polygons read from '
        f'{BOUNDARIES.relative_to(REPO)}; Plateau has 17, and a short list '
        f'would put real shelters outside every boundary.')

# The boundary file is GeoJSON, so vertices are [lng, lat]. Plateau spans
# 8.3-10.4 N and 8.5-10.6 E — the ranges overlap, so a flipped file would not
# look obviously wrong, it would just move every shelter. The ward centroids
# are the independent witness: nearly all of them must land inside some
# polygon. They do (205 of 207; the 13 that do not are ward-data drift, not a
# coordinate-order fault). If somebody flips the order or replaces the polygons
# with bounding boxes, this collapses.
landed = sum(1 for c in centroids
             if lga_containing(c['lat'], c['lng'], features) is not None)
if landed < 0.9 * len(centroids):
    raise SystemExit(
        f'✗ only {landed} of {len(centroids)} surveyed ward centroids fall '
        f'inside any LGA polygon. Either {BOUNDARIES.relative_to(REPO)} has '
        f'its coordinates the wrong way round ([lat,lng] instead of GeoJSON '
        f'[lng,lat]), or the polygons are no longer the real boundaries. '
        f'Every verdict below would be meaningless.')

# The two assets must name the same 17 places, or `key()` is hiding a rename.
poly_lgas = {key(f['properties']['lga']) for f in features}
ward_lgas = {key(c['lga']) for c in centroids}
if poly_lgas != ward_lgas:
    raise SystemExit(
        f'✗ the LGA names in {BOUNDARIES.relative_to(REPO)} and '
        f'{CENTROIDS.relative_to(REPO)} disagree.\n'
        f'   only in boundaries: {sorted(poly_lgas - ward_lgas)}\n'
        f'   only in ward data : {sorted(ward_lgas - poly_lgas)}')

# One rule, not two. If the app stops deciding an incident's LGA by the
# boundary, a shelter and an incident are judged differently again — which is
# the defect this rewrite exists to close.
resolver = RESOLVER.read_text(encoding='utf-8')
if 'plateau_boundaries.json' not in resolver:
    raise SystemExit(
        f'✗ {RESOLVER.relative_to(REPO)} no longer reads '
        f'plateau_boundaries.json. This check judges a shelter by the LGA '
        f'boundary because that is how the app judges an incident. If the app '
        f'has changed rule, the two have diverged and this check is enforcing '
        f'something the product no longer does.')

seed = SEED.read_text(encoding='utf-8')
insert = seed[seed.index('INSERT INTO public.safe_zones'):]
insert = insert[:insert.index('ON CONFLICT (name) DO NOTHING;')]
shelters = ROW.findall(insert)
if not shelters:
    raise SystemExit(
        '✗ no shelter rows parsed out of the seed. If the INSERT changed shape '
        'this check is reading nothing and would pass on anything.')

deactivation = seed[seed.index('SET is_active = false,'):]
deactivation = deactivation[:deactivation.index(';')]
hidden = {name for name, _, _ in HIDDEN.findall(deactivation)}

by_lga: dict[str, list[dict]] = {}
for c in centroids:
    by_lga.setdefault(key(c['lga']), []).append(c)


def nearest_ward(lat: float, lng: float, lga: str) -> str:
    """Only ever used to name a place in a message, never to decide."""
    wards = by_lga.get(key(lga), [])
    if not wards:
        return '?'
    near = min(wards, key=lambda w: haversine_km(lat, lng, w['lat'], w['lng']))
    return near['ward']


rows, checked = [], 0
for name, lat_s, lon_s, lga in shelters:
    lat, lon = float(lat_s), float(lon_s)
    if key(lga) not in poly_lgas:
        faults.append(
            f'{name} claims LGA {lga!r}, which is not one of the '
            f'{len(poly_lgas)} LGAs of Plateau. Either the name is wrong or '
            f'the geography is, and the citizen app scopes shelters by this '
            f'field.')
        continue
    checked += 1
    actual = lga_containing(lat, lon, features)
    agrees = actual is not None and key(actual) == key(lga)
    rows.append((name, lga, actual, agrees))

    if agrees and name in hidden:
        faults.append(
            f'{name} is inside {lga} — the boundary agrees with its own row — '
            f'and is still in the deactivation list. A shelter that is where '
            f'it says it is should be shown; hiding it leaves a citizen with '
            f'one fewer place to run to for no reason.')
    elif not agrees and name not in hidden:
        where = (f'is in {actual}' if actual
                 else 'is outside every LGA of Plateau')
        faults.append(
            f'{name} claims {lga} but {where}. The citizen screen routes a '
            f'fleeing person to the nearest shelter, so this sends them to a '
            f'place its own row says it is not. Either correct the position '
            f'or add it to the deactivation list with a reason.')

for name in sorted(hidden):
    if name not in {s[0] for s in shelters}:
        faults.append(
            f'{name} is deactivated and is not one of the seeded shelters, so '
            f'that statement does nothing.')

if faults:
    print('FAIL: a shelter is not where its row says it is.\n')
    for f in faults:
        print(f'  - {f}\n')
    print('See E2E_AUDIT_REPORT.md T-94.')
    sys.exit(1)

print(f'OK: {checked} stored shelter(s) checked against {len(features)} LGA '
      f'boundary polygons.')
print(f'  * {checked - len(hidden)} inside the LGA they claim')
print(f'  * {len(hidden)} in a different one, and deactivated so no citizen is '
      f'routed to them')
for name, lga, actual, agrees in rows:
    mark = 'hidden ' if name in hidden else 'shown  '
    ward = nearest_ward(
        *[float(s) for s in next((la, lo) for n, la, lo, _ in shelters
                                 if n == name)], lga)
    seen = actual or 'OUTSIDE PLATEAU'
    note = f'{lga}/{ward}' if agrees else f'claims {lga}, is in {seen}'
    print(f'  {mark} {name:28} {note}')
