#!/usr/bin/env python3
"""A ward's centroid must lie inside the LGA its own row claims.

    python3 scripts/check_a_ward_centroid_is_in_its_own_lga.py

## What went wrong

The ward centroids and the LGA polygons are independently published datasets,
and on 13 of the 207 Plateau wards they disagreed: the published centroid fell
inside a different LGA's polygon, or inside none at all.

That is not cosmetic. `jurisdiction_resolver.dart` resolves an incident's LGA by
polygon and then its ward from the centroids registered to that LGA, so a ward
whose centroid sits across the line is absent from the candidate list wherever
it actually is. An incident in JENTA ADAMU (Jos North) was filed as Jos South /
GIRING, ten kilometres away and under the wrong commander. KANAM/DUGUB and
KANKE/NEMEL fell inside no polygon at all.

## Which dataset was wrong

GRID3 NGA Operational Wards v4.0 settled it. It is a third dataset, published
independently and consulted after both of ours were already chosen, so it can
say which of the two is the outlier. On all 13 it agreed with the LGA polygons
and with the register's LGA LABEL — it files each of those wards under exactly
the LGA the row claims. So the label was right and the coordinate was wrong.

Eleven were replaced with the area-weighted centroid of the GRID3 polygon(s)
carrying that ward's name inside that LGA, each accepted only after it resolved
INTO the claimed LGA. `assets/geo/plateau_wards.json` records every one under
`corrections`, with the point it replaced.

GRID3's "operational wards" are NOT INEC's electoral wards — 325 against 207 for
Plateau, and only 134 names match — so the polygons are not a drop-in
replacement for this system's ward list and are not used as one. They are used
only to adjudicate, and only where a name and an LGA both agree.

## What this checks

1. Every ward centroid is inside the LGA its row claims, except the two named
   below, which are listed with the reason no position could be derived.
2. Every recorded correction is still TRUE: the point it replaced is still
   outside the claimed LGA, and the point that replaced it is still inside. A
   correction that stops being either is a record that has drifted from the
   data, and the record is what a reader trusts.
3. The two unresolved wards are still unresolved. If a later import fixes one,
   this fails and says to drop it from the list rather than leave a stale
   exemption behind — the T-100 lesson, a check that tests its own premise.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
WARDS = REPO / 'assets/geo/plateau_wards.json'
BOUNDS = REPO / 'assets/geo/plateau_boundaries.json'

# GRID3 carries no ward named Garkawa anywhere in Plateau — not in Mikang,
# not in Shendam where the polygons place this point — so there is nothing to
# derive a position from. A guess is not an improvement, so this one keeps its
# published coordinate and is known to be wrong. It needs INEC or PLASIEC.
UNRESOLVED = {
    ('MIKANG', 'GARKAWA CENTRAL'),
}

faults: list[str] = []


def key(name: str) -> str:
    return (name or '').upper().replace("'", '').replace('-', ' ').replace('  ', ' ').strip()


def parts(feature: dict):
    geom = feature['geometry']
    polys = ([geom['coordinates']] if geom['type'] == 'Polygon'
             else geom['coordinates'])
    return [(p[0], p[1:]) for p in polys]


def in_ring(lng: float, lat: float, ring: list) -> bool:
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
    for f in features:
        for outer, holes in parts(f):
            if in_ring(lng, lat, outer) and not any(
                    in_ring(lng, lat, h) for h in holes):
                return f['properties']['lga']
    return None


for path in (WARDS, BOUNDS):
    if not path.is_file():
        raise SystemExit(f'✗ {path.relative_to(REPO)} is missing')

doc = json.loads(WARDS.read_text(encoding='utf-8'))
wards = doc['wards']
features = json.loads(BOUNDS.read_text(encoding='utf-8'))['features']

if len(wards) < 200:
    raise SystemExit(
        f'✗ only {len(wards)} wards read; this check measures every ward '
        f'against its LGA and a short list would pass on almost nothing.')
if len(features) < 17:
    raise SystemExit(
        f'✗ only {len(features)} LGA polygons read; Plateau has 17, and a '
        f'short list would put real wards outside every boundary.')

# ── 1. every centroid inside the LGA it claims ──────────────────────────────
outside = []
for w in wards:
    got = lga_containing(w['lat'], w['lng'], features)
    if got is None or key(got) != key(w['lga']):
        outside.append((w, got))

unexpected = [(w, g) for w, g in outside
              if (key(w['lga']), key(w['ward'])) not in
              {(key(a), key(b)) for a, b in UNRESOLVED}]
for w, got in unexpected:
    where = f'is in {got}' if got else 'is inside no LGA of Plateau'
    faults.append(
        f'{w["lga"]}/{w["ward"]} claims {w["lga"]} but its centroid {where}. '
        f'An incident there resolves to that LGA and then looks for a ward '
        f'among the wrong LGA\'s centroids, so this ward is unreachable where '
        f'it actually sits. Correct the coordinate and record it under '
        f'`corrections`, or add it to UNRESOLVED here with the reason none '
        f'could be derived.')

# ── 3. the exemptions must still be needed ─────────────────────────────────
still_bad = {(key(w['lga']), key(w['ward'])) for w, _ in outside}
for lga, ward in sorted(UNRESOLVED):
    if (key(lga), key(ward)) not in still_bad:
        faults.append(
            f'{lga}/{ward} is listed here as impossible to place, but its '
            f'centroid now resolves into {lga} correctly. Remove it from '
            f'UNRESOLVED: a stale exemption hides the next ward that breaks.')

# ── 2. every recorded correction still says something true ─────────────────
corrections = doc.get('corrections', [])
if not corrections:
    faults.append(
        'assets/geo/plateau_wards.json records no `corrections`. Eleven '
        'centroids were replaced; if that block is gone the file no longer '
        'says which points are upstream\'s and which are this repository\'s.')

by_name = {(key(w['lga']), key(w['ward'])): w for w in wards}
for c in corrections:
    k = (key(c['lga']), key(c['ward']))
    w = by_name.get(k)
    if w is None:
        faults.append(
            f'`corrections` names {c["lga"]}/{c["ward"]}, which is not a ward '
            f'in this file.')
        continue
    was = lga_containing(c['was']['lat'], c['was']['lng'], features)
    now = lga_containing(c['now']['lat'], c['now']['lng'], features)
    if was is not None and key(was) == key(c['lga']):
        faults.append(
            f'`corrections` says {c["lga"]}/{c["ward"]} was moved because its '
            f'published point fell outside {c["lga"]}, but that point resolves '
            f'into {was} now. Either the boundaries changed or the record is '
            f'wrong; a reader trusts this block, so it cannot be stale.')
    if now is None or key(now) != key(c['lga']):
        faults.append(
            f'`corrections` says {c["lga"]}/{c["ward"]} was moved INTO '
            f'{c["lga"]}, but the replacement point is in '
            f'{now or "no LGA at all"}.')
    if (abs(w['lat'] - c['now']['lat']) > 1e-6
            or abs(w['lng'] - c['now']['lng']) > 1e-6):
        faults.append(
            f'{c["lga"]}/{c["ward"]} sits at {w["lat"]}, {w["lng"]} but '
            f'`corrections` says it was set to {c["now"]["lat"]}, '
            f'{c["now"]["lng"]}. Somebody moved a corrected ward without '
            f'updating the record of why it moved.')

if faults:
    print('FAIL: a ward centroid is not inside the LGA its row claims.\n')
    for f in faults:
        print(f'  - {f}\n')
    print('See E2E_AUDIT_REPORT.md T-102.')
    sys.exit(1)

placed = len(wards) - len(outside)
print(f'OK: {placed} of {len(wards)} ward centroids are inside the LGA they '
      f'claim.')
print(f'  * {len(corrections)} corrected from GRID3 and recorded, each verified '
      f'to resolve into its own LGA')
print(f'  * {len(UNRESOLVED)} left as published, with no source to derive a '
      f'position from:')
for lga, ward in sorted(UNRESOLVED):
    print(f'      {lga}/{ward}')
