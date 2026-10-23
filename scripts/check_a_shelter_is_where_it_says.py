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

This is the correctness one, and it is answerable. The repository already holds
207 SURVEYED ward centroids with an honest radius each
(`hq-dashboard-next/src/lib/ward_centroids.ts`, generated from the app's own
ward asset and kept in parity by its own CI step). Measured against the LGA each
shelter row claims, three of the seven were outside every ward of it:

    JOS SOUTH COMMAND HQ       11.24 km from JOS SOUTH/GIRING (r=1.7km)
    MANGU COMMAND POST          9.69 km from MANGU/KADUNU     (r=4.2km)
    JOS EAST TACTICAL OUTPOST   4.59 km from JOS EAST/SHERE WEST (r=4.0km)

A citizen in Jos South, fleeing, was given turn directions to a point eleven
kilometres away in Jos North, labelled as the Jos South command HQ.

## What this checks

Every shelter this repository stores falls within a surveyed ward of the LGA its
row names — or is explicitly deactivated, so the citizen app never routes to it.
The radius used is that ward centroid's own, which is half the distance to its
nearest neighbour in the same LGA, clamped to [800m, 25km]: a ward in Jos North
is a few streets and one in Wase is a large piece of countryside, and a single
tolerance would flatter the first and lie about the second.

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

# ('NAME', 'description', lat, lon, 'TYPE', 'LGA', NULL)
ROW = re.compile(
    r"\(\s*'([^']+)'\s*,\s*'[^']*'\s*,\s*(-?\d+\.\d+)\s*,\s*(-?\d+\.\d+)\s*,"
    r"\s*'[^']*'\s*,\s*'([^']+)'\s*,\s*NULL\s*\)")
# ('NAME',  lat, lon)  — the deactivation list
HIDDEN = re.compile(
    r"\(\s*'([^']+)'\s*,\s*(-?\d+\.\d+)\s*,\s*(-?\d+\.\d+)\s*\)")

faults: list[str] = []


def haversine_km(a_lat: float, a_lon: float, b_lat: float, b_lon: float) -> float:
    r = 6371.0088
    p1, p2 = math.radians(a_lat), math.radians(b_lat)
    dp, dl = p2 - p1, math.radians(b_lon - a_lon)
    h = (math.sin(dp / 2) ** 2
         + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2)
    return 2 * r * math.asin(math.sqrt(h))


def load_centroids() -> list[dict]:
    text = CENTROIDS.read_text(encoding='utf-8')
    marker = 'wardCentroids: WardCentroid[] = '
    if marker not in text:
        raise SystemExit(
            f'✗ {CENTROIDS.relative_to(REPO)} has no `{marker.strip()}`; this '
            f'check cannot read the surveyed geography it depends on.')
    body = text[text.index(marker) + len(marker):]
    return json.loads(body[:body.rindex(']') + 1])


for path in (SEED, CENTROIDS):
    if not path.is_file():
        raise SystemExit(f'✗ {path.relative_to(REPO)} is missing')

centroids = load_centroids()
if len(centroids) < 100:
    raise SystemExit(
        f'✗ only {len(centroids)} ward centroids read; this check compares '
        f'against surveyed geography and a short list would pass everything.')

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
    by_lga.setdefault(c['lga'].upper(), []).append(c)

checked = 0
for name, lat_s, lon_s, lga in shelters:
    lat, lon = float(lat_s), float(lon_s)
    wards = by_lga.get(lga.upper())
    if not wards:
        faults.append(
            f'{name} claims LGA {lga!r}, which is not one of the '
            f'{len(by_lga)} LGAs in the surveyed ward data. Either the name is '
            f'wrong or the geography is, and the citizen app scopes shelters '
            f'by this field.')
        continue
    checked += 1
    near = min(wards, key=lambda w: haversine_km(lat, lon, w['lat'], w['lng']))
    km = haversine_km(lat, lon, near['lat'], near['lng'])
    inside = km * 1000 <= near['radiusM']
    if inside and name in hidden:
        faults.append(
            f'{name} is inside {lga}/{near["ward"]} '
            f'({km:.2f} km, r={near["radiusM"] / 1000:.1f} km) and is still in '
            f'the deactivation list. A shelter that is where it says it is '
            f'should be shown; hiding it leaves a citizen with one fewer place '
            f'to run to for no reason.')
    elif not inside and name not in hidden:
        faults.append(
            f'{name} is {km:.2f} km from the nearest surveyed ward of the LGA '
            f'it claims ({lga}/{near["ward"]}, r={near["radiusM"] / 1000:.1f} '
            f'km) — {km * 1000 - near["radiusM"]:.0f} m outside it. The citizen '
            f'screen routes a fleeing person to the nearest shelter, so this '
            f'sends them somewhere its own row says it is not. Either correct '
            f'the position or add it to the deactivation list with a reason.')

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

print(f'OK: {checked} stored shelter(s) checked against {len(centroids)} '
      f'surveyed ward centroids.')
print(f'  * {checked - len(hidden)} inside a surveyed ward of the LGA they claim')
print(f'  * {len(hidden)} outside one, and deactivated so no citizen is routed '
      f'to them')
for name, lat_s, lon_s, lga in shelters:
    wards = by_lga.get(lga.upper(), [])
    if not wards:
        continue
    near = min(wards, key=lambda w: haversine_km(
        float(lat_s), float(lon_s), w['lat'], w['lng']))
    km = haversine_km(float(lat_s), float(lon_s), near['lat'], near['lng'])
    mark = 'hidden ' if name in hidden else 'shown  '
    print(f'  {mark} {name:28} {km:5.2f} km from {lga}/{near["ward"]}')
