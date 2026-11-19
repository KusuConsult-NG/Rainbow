import { lgaBoundaries, type LgaBoundary } from './lga_boundaries';

/**
 * Which LGA a position is in — the boundary question, asked of the boundary.
 *
 * ## Why this is not ward centroids
 *
 * `wardDisagreement()` used to answer "is this position in the LGA it claims?"
 * by measuring to the nearest ward centroid of that LGA and comparing against
 * that centroid's radius. Those radii are half the distance to the nearest
 * neighbouring centroid — median 3.5km — and discs do not tile a plane.
 *
 * Measured against these 17 polygons, that rule rejects **57.7% of real
 * Plateau**: 78% of Jos North, 70% of Barkin Ladi, 66% of Jos South. A point
 * 2.21km from ALI KAZAURE (r=800m), in the middle of Jos, is rejected by it. So
 * a commander typing a correct position into SafeZonesPanel was told it was
 * outside its own LGA more often than not — on the screen built so they could
 * correct the three shelters that genuinely were.
 *
 * `lib/core/geo/jurisdiction_resolver.dart` has always decided an incident's
 * LGA this way. One rule, in both places, so an incident and a shelter at the
 * same coordinates are judged the same.
 *
 * See E2E_AUDIT_REPORT.md T-101.
 */

/**
 * Even-odd ray casting, the same test as `jurisdiction_resolver.dart`.
 *
 * Ring vertices are GeoJSON [longitude, latitude].
 */
function inRing(lng: number, lat: number, ring: number[][]): boolean {
  let hit = false;
  const n = ring.length;
  for (let i = 0; i < n; i += 1) {
    const [x1, y1] = ring[i];
    const [x2, y2] = ring[(i + 1) % n];
    if ((y1 > lat) !== (y2 > lat)) {
      if (lng < ((x2 - x1) * (lat - y1)) / (y2 - y1) + x1) hit = !hit;
    }
  }
  return hit;
}

/**
 * The LGA whose boundary contains this position, or `null` if none does —
 * which means outside Plateau, or in one of the slivers the ADM2 dataset
 * leaves between neighbours.
 *
 * `null` is a real answer and not an error. The caller decides what to say
 * about it; what it must not do is guess an LGA, which is how a position ends
 * up labelled with somewhere nobody checked.
 */
export function lgaContaining(lat: number, lng: number): string | null {
  return lgaContainingIn(lat, lng, lgaBoundaries);
}

/**
 * The same thing against a boundary list you supply.
 *
 * Exported so the hole branch can be exercised. Plateau's ADM2 polygons have
 * no interior rings today — which means that branch has nothing to run against
 * and a test over the real data cannot tell whether it works. Deleting it is
 * not the answer either: `jurisdiction_resolver.dart` honours holes, and a
 * boundary file that gains one later would silently put positions in the wrong
 * LGA here while the app got it right. So it stays, and it is tested against a
 * shape that has one.
 */
export function lgaContainingIn(
  lat: number,
  lng: number,
  boundaries: LgaBoundary[],
): string | null {
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  for (const { lga, parts } of boundaries) {
    for (const ringSet of parts) {
      const [outer, ...holes] = ringSet;
      if (inRing(lng, lat, outer) && !holes.some((h) => inRing(lng, lat, h))) {
        return lga;
      }
    }
  }
  return null;
}

/** Whether a position is inside the LGA it claims. Case and punctuation differ
 *  between the boundary file ("Qua'an Pan"), the ward data ("QUA'AN PAN") and
 *  whatever an operator types, so compare on a key rather than the string. */
export function lgaKey(name: string): string {
  return name.toUpperCase().replace(/'/g, '').replace(/-/g, ' ').replace(/\s+/g, ' ').trim();
}

/** Every LGA of Plateau, as the boundary file names them. */
export function boundaryLgaNames(): string[] {
  return lgaBoundaries.map((b) => b.lga);
}
