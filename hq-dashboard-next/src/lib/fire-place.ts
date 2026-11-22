/**
 * Where in Plateau a fire detection is: its LGA, by the LGA polygons, and its
 * ward, by the nearest ward centroid inside that LGA.
 *
 * The same two steps the app takes for an incident
 * (lib/core/geo/jurisdiction_resolver.dart): polygon for the LGA, nearest
 * centroid for the ward, because the open ward data is one point per ward and
 * not a polygon. So a fire and an incident in the same place get the same
 * ward name, and the ward grid and the baselines compare like with like.
 *
 * Server only: it imports the LGA boundaries (about 90 KB), which the browser
 * fetches separately for drawing and must not also get in its bundle.
 */

import boundaries from '../../public/plateau_boundaries.json';
import { geoKey } from './geo-key';
import { wardCentroids, type WardCentroid } from './ward_centroids';

type Ring = number[][];
interface Lga {
  name: string;
  /** Outer rings only; Plateau's LGA polygons have no holes. */
  rings: Ring[];
  bbox: [number, number, number, number];
}

function ringsOf(geometry: { type: string; coordinates: unknown }): Ring[] {
  if (geometry.type === 'Polygon') return [(geometry.coordinates as Ring[])[0]];
  if (geometry.type === 'MultiPolygon') return (geometry.coordinates as Ring[][]).map((p) => p[0]);
  return [];
}

const LGAS: Lga[] = (boundaries as { features: { properties: { lga: string }; geometry: { type: string; coordinates: unknown } }[] }).features
  .map((f) => {
    const rings = ringsOf(f.geometry);
    const xs = rings.flat().map((p) => p[0]);
    const ys = rings.flat().map((p) => p[1]);
    return {
      name: geoKey(f.properties.lga),
      rings,
      bbox: [Math.min(...xs), Math.min(...ys), Math.max(...xs), Math.max(...ys)] as [number, number, number, number],
    };
  });

/** west, south, east, north: the box FIRMS is asked about. */
export const PLATEAU_BBOX: readonly number[] = (() => {
  const b = LGAS.map((l) => l.bbox);
  const r = (n: number) => Math.round(n * 1000) / 1000;
  return [
    r(Math.min(...b.map((x) => x[0])) - 0.01),
    r(Math.min(...b.map((x) => x[1])) - 0.01),
    r(Math.max(...b.map((x) => x[2])) + 0.01),
    r(Math.max(...b.map((x) => x[3])) + 0.01),
  ];
})();

/** Ray casting: is (lng, lat) inside the ring? */
function inRing(lng: number, lat: number, ring: Ring): boolean {
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const [xi, yi] = ring[i];
    const [xj, yj] = ring[j];
    if ((yi > lat) !== (yj > lat) && lng < ((xj - xi) * (lat - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}

/** The LGA a point is in, or null outside Plateau. */
export function lgaAt(lat: number, lng: number): string | null {
  for (const l of LGAS) {
    const [w, s, e, n] = l.bbox;
    if (lng < w || lng > e || lat < s || lat > n) continue;
    if (l.rings.some((r) => inRing(lng, lat, r))) return l.name;
  }
  return null;
}

const WARDS_BY_LGA = new Map<string, WardCentroid[]>();
for (const w of wardCentroids) {
  const k = geoKey(w.lga);
  WARDS_BY_LGA.set(k, [...(WARDS_BY_LGA.get(k) ?? []), w]);
}

/** The nearest ward centroid in that LGA. */
export function nearestWard(lga: string, lat: number, lng: number): WardCentroid | null {
  const wards = WARDS_BY_LGA.get(geoKey(lga)) ?? [];
  const cos = Math.cos((lat * Math.PI) / 180);
  let best: WardCentroid | null = null;
  let bestD = Infinity;
  for (const w of wards) {
    const d = (w.lat - lat) ** 2 + ((w.lng - lng) * cos) ** 2;
    if (d < bestD) {
      bestD = d;
      best = w;
    }
  }
  return best;
}

/** LGA and ward for a point in Plateau, or null for a point outside it. */
export function placeInPlateau(lat: number, lng: number): { lga: string; ward: string | null } | null {
  const lga = lgaAt(lat, lng);
  if (!lga) return null;
  const ward = nearestWard(lga, lat, lng);
  return { lga: ward?.lga ?? lga, ward: ward?.ward ?? null };
}
