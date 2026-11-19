import { describe, expect, it } from 'vitest';

import {
  boundaryLgaNames, lgaContaining, lgaContainingIn, lgaKey,
} from './lga-boundaries';
import type { LgaBoundary } from './lga_boundaries';
import { wardCentroids } from './ward_centroids';

/**
 * The console's half of the boundary test.
 *
 * `check_a_shelter_is_where_it_says.py` asks this question of the seed and
 * `jurisdiction_resolver.dart` asks it of an incident. This asserts the browser
 * gets the same answer, because the one that runs at entry time is the one an
 * operator will believe.
 */
describe('lgaContaining', () => {
  it('has all 17 LGAs of Plateau', () => {
    expect(boundaryLgaNames()).toHaveLength(17);
    expect(boundaryLgaNames()).toContain('Jos North');
    expect(boundaryLgaNames()).toContain("Qua'an Pan");
  });

  /**
   * The coordinate order, asserted from the console's side.
   *
   * The polygons are GeoJSON, so a vertex is [longitude, latitude]. Plateau
   * spans 8.3-10.4 N and 8.5-10.6 E — the ranges overlap, so a flipped asset
   * would not look obviously wrong, it would just move every verdict. The ward
   * centroids are the independent witness: nearly all of them must land inside
   * some polygon.
   *
   * 205 of 207 do. The two that do not are KANAM/DUGUB and KANKE/NEMEL, real
   * wards whose centroids fall in a gap because the ward list and the ADM2 map
   * come from different datasets.
   */
  it('places almost every surveyed ward centroid inside some LGA', () => {
    const placed = wardCentroids.filter(
      (w) => lgaContaining(w.lat, w.lng) !== null,
    );
    expect(placed.length).toBeGreaterThanOrEqual(
      Math.floor(wardCentroids.length * 0.95),
    );
  });

  it.each([
    ['JOS SOUTH COMMAND HQ', 9.8965, 8.8583, 'Jos North'],
    ['BUKURU TACTICAL OUTPOST', 9.7952, 8.8521, 'Jos South'],
    ['JOS NORTH POLICE DIVISION', 9.9281, 8.8921, 'Jos North'],
    ['PLATEAU STATE HQ', 9.9167, 8.8917, 'Jos North'],
    ['JOS EAST TACTICAL OUTPOST', 9.95, 8.96, 'Jos North'],
    ['BARKIN LADI SAFE POINT', 9.5167, 8.9167, 'Barkin Ladi'],
    ['MANGU COMMAND POST', 9.7167, 9.05, 'Mangu->Barkin Ladi'],
  ])('resolves %s', (_name, lat, lng, expected) => {
    const want = (expected as string).includes('->')
      ? (expected as string).split('->')[1]
      : (expected as string);
    expect(lgaContaining(lat as number, lng as number)).toBe(want);
  });

  it('returns null outside Plateau rather than guessing the nearest', () => {
    // Abuja, about 250km away. A nearest-centroid rule would confidently name
    // an LGA here; that is the C-5 defect in a different column.
    expect(lgaContaining(9.0579, 7.4951)).toBeNull();
  });

  it('returns null for a non-finite coordinate', () => {
    expect(lgaContaining(Number.NaN, 8.8921)).toBeNull();
    expect(lgaContaining(9.9281, Number.POSITIVE_INFINITY)).toBeNull();
  });

  // Two of the 207 ward centroids land in no polygon at all. null is a real
  // answer for them, not an error, and the caller must not turn it into a guess.
  it('returns null in the gaps the ADM2 dataset leaves', () => {
    expect(lgaContaining(9.742695, 9.946832)).toBeNull();  // KANAM/DUGUB
    expect(lgaContaining(9.476583, 9.471614)).toBeNull();  // KANKE/NEMEL
  });
});

describe('lgaKey', () => {
  // The three assets spell the same place three ways, and an operator a fourth.
  it('matches the same LGA across the spellings in use', () => {
    expect(lgaKey("Qua'an Pan")).toBe(lgaKey("QUA'AN PAN"));
    expect(lgaKey('Jos North')).toBe(lgaKey('JOS NORTH'));
    expect(lgaKey('barkin-ladi')).toBe(lgaKey('BARKIN LADI'));
    expect(lgaKey('  Jos   South  ')).toBe(lgaKey('JOS SOUTH'));
  });

  it('does not collapse two different LGAs onto one key', () => {
    const keys = boundaryLgaNames().map(lgaKey);
    expect(new Set(keys).size).toBe(keys.length);
  });
});

/**
 * The hole branch, which the real data cannot exercise.
 *
 * Plateau's 17 ADM2 polygons have no interior rings, so a test over the real
 * asset runs this branch zero times and would pass with hole handling deleted —
 * which it did, until this was added. `jurisdiction_resolver.dart` honours
 * holes, so dropping it here would make the console and the app disagree the
 * day the boundary file gains one.
 */
describe('holes', () => {
  // A square with a square hole punched through the middle.
  const doughnut: LgaBoundary[] = [{
    lga: 'Doughnut',
    parts: [[
      [[0, 0], [0, 10], [10, 10], [10, 0]],      // outer
      [[4, 4], [4, 6], [6, 6], [6, 4]],          // hole
    ]],
  }];

  it('places a point in the ring', () => {
    expect(lgaContainingIn(1, 1, doughnut)).toBe('Doughnut');   // lat 1, lng 1
    expect(lgaContainingIn(9, 9, doughnut)).toBe('Doughnut');
  });

  it('does NOT place a point inside the hole', () => {
    expect(lgaContainingIn(5, 5, doughnut)).toBeNull();
  });

  it('does not place a point outside the outer ring', () => {
    expect(lgaContainingIn(11, 11, doughnut)).toBeNull();
  });
});
