import { wardCentroids } from './ward_centroids';
import { metresBetween } from './incident-locate';
import { supabase } from './supabase';

/**
 * Shelters: reading them, publishing one, and confirming where it is.
 *
 * ## Why this module exists
 *
 * `safe_zones` is what `safe_zone_screen.dart` draws a fleeing citizen a route
 * to. Until T-94 nothing in either app could write it: the RLS policy allowing
 * command to do so had existed since August and **nothing had ever called it**,
 * which is why nobody noticed that only 2 of the project's 22 staff accounts
 * satisfied `is_command()` at all. The seven shelters in the table came from a
 * seed, at coordinates nobody measured, and three of them were outside every
 * surveyed ward of the LGA their own row claimed — the worst by 9.6km.
 *
 * So the table needs a screen, and the screen needs to be unable to repeat
 * that. Two things do that here:
 *
 *   * `publish`/`verify`/`retire` go through the SQL functions, so the position
 *     is checked and the actor is recorded in one place whatever calls them. A
 *     direct table write would skip both.
 *   * `wardDisagreement()` measures a position against the LGA it claims BEFORE
 *     it is stored, using the same 207 surveyed ward centroids and the same
 *     per-ward radius that `check_a_shelter_is_where_it_says.py` uses on the
 *     seed. The check that found the three bad rows now runs where the data is
 *     entered.
 *
 * It is a WARNING and not a refusal. A shelter can legitimately sit just over a
 * ward boundary, the centroids are points rather than polygons, and an operator
 * standing at the building knows more than this does. What it must not do is
 * let somebody store a position eleven kilometres into the next LGA without
 * being told.
 *
 * See E2E_AUDIT_REPORT.md T-93, T-94, T-98.
 */

export interface SafeZone {
  id: string;
  name: string;
  description: string | null;
  latitude: number;
  longitude: number;
  type: string;
  geo_lga: string | null;
  geo_ward: string | null;
  capacity: number | null;
  is_active: boolean;
  verified_at: string | null;
  verified_by: string | null;
}

/** What `safe_zones.type` carries, and what each is in plain words. */
export const ZONE_TYPES: ReadonlyArray<{ value: string; label: string }> = [
  { value: 'POLICE', label: 'Police station / division' },
  { value: 'OUTPOST', label: 'Security outpost' },
  { value: 'COMMAND_HQ', label: 'Command HQ' },
  { value: 'SAFE_POINT', label: 'Civilian assembly point' },
  { value: 'MEDICAL', label: 'Clinic / hospital' },
];

/** Plateau State's extent, from the surveyed ward centroids. */
const BOUNDS = { minLat: 8.3, maxLat: 10.4, minLng: 8.4, maxLng: 10.6 };

export interface PositionProblem {
  kind: 'outside-state' | 'null-island' | 'outside-lga' | 'no-such-lga';
  message: string;
}

/** Every LGA the surveyed geography knows, for the form's own list. */
export function knownLgas(): string[] {
  return Array.from(new Set(wardCentroids.map((w) => w.lga))).sort();
}

/**
 * Why this position does not look like the place it claims to be, or null.
 *
 * The same question `check_a_shelter_is_where_it_says.py` asks of the seeded
 * rows, asked of a row somebody is about to add. The radius is that ward
 * centroid's own — half the distance to its nearest neighbour in the same LGA,
 * clamped to [800m, 25km] — because a ward in Jos North is a few streets and
 * one in Wase is a large piece of countryside, and a single tolerance would
 * flatter the first and lie about the second.
 */
export function wardDisagreement(
  lat: number,
  lng: number,
  lga: string | null | undefined,
): PositionProblem | null {
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  if (lat === 0 && lng === 0) {
    return {
      kind: 'null-island',
      message:
        '0, 0 is a point in the Gulf of Guinea, about 700km off the coast. ' +
        'This project has already drawn it on a map as somewhere to run to.',
    };
  }
  if (
    lat < BOUNDS.minLat || lat > BOUNDS.maxLat ||
    lng < BOUNDS.minLng || lng > BOUNDS.maxLng
  ) {
    return {
      kind: 'outside-state',
      message:
        'That position is outside Plateau State. The database will refuse it.',
    };
  }

  const want = (lga ?? '').trim().toUpperCase();
  if (!want) return null;      // no LGA claimed, nothing to disagree with
  const wards = wardCentroids.filter((w) => w.lga.toUpperCase() === want);
  if (wards.length === 0) {
    return {
      kind: 'no-such-lga',
      message:
        `${want} is not one of the ${knownLgas().length} LGAs in the ` +
        'surveyed ward data, so the citizen app cannot scope a shelter to it.',
    };
  }

  let nearest = wards[0];
  let best = Infinity;
  for (const w of wards) {
    const d = metresBetween({ lat, lng }, { lat: w.lat, lng: w.lng });
    if (d < best) { best = d; nearest = w; }
  }
  if (best <= nearest.radiusM) return null;

  const over = Math.round(best - nearest.radiusM);
  const elsewhere = nearestLgaTo(lat, lng);
  return {
    kind: 'outside-lga',
    message:
      `That position is ${(best / 1000).toFixed(2)}km from the nearest ` +
      `surveyed ward of ${want} (${nearest.ward}), which is ` +
      `${over >= 1000 ? `${(over / 1000).toFixed(1)}km` : `${over}m`} ` +
      `outside it` +
      (elsewhere && elsewhere !== want ? ` — it looks like ${elsewhere}.` : '.') +
      ' A citizen in this LGA would be sent there.',
  };
}

/** The LGA whose nearest ward centroid this position is closest to. */
export function nearestLgaTo(lat: number, lng: number): string | null {
  let best = Infinity;
  let lga: string | null = null;
  for (const w of wardCentroids) {
    const d = metresBetween({ lat, lng }, { lat: w.lat, lng: w.lng });
    if (d < best) { best = d; lga = w.lga; }
  }
  return lga;
}

/** The ward of `lga` this position falls nearest to, for pre-filling. */
export function nearestWardIn(
  lat: number,
  lng: number,
  lga: string | null | undefined,
): string | null {
  const want = (lga ?? '').trim().toUpperCase();
  const wards = wardCentroids.filter((w) => w.lga.toUpperCase() === want);
  if (wards.length === 0) return null;
  let best = Infinity;
  let ward: string | null = null;
  for (const w of wards) {
    const d = metresBetween({ lat, lng }, { lat: w.lat, lng: w.lng });
    if (d < best) { best = d; ward = w.ward; }
  }
  return ward;
}

export type LoadResult =
  | { ok: true; zones: SafeZone[] }
  | { ok: false; error: string };

/**
 * Every shelter, hidden ones included.
 *
 * Deliberately NOT filtered to `is_active`: the three hidden by T-94 are the
 * ones that need correcting, and a screen that cannot see them cannot be used
 * to fix them. The citizen app filters; command does not.
 *
 * Returns an error rather than an empty list on failure, so "the query failed"
 * cannot read as "there are no shelters" — the same reasoning as the provider
 * in `safe_zone_screen.dart`, which used to throw on an empty result and hand
 * back three invented ones.
 */
export async function loadSafeZones(): Promise<LoadResult> {
  const { data, error } = await supabase
    .from('safe_zones')
    .select(
      'id, name, description, latitude, longitude, type, geo_lga, geo_ward, ' +
      'capacity, is_active, verified_at, verified_by',
    )
    .order('is_active', { ascending: false })
    .order('name');

  if (error) return { ok: false, error: error.message };
  return { ok: true, zones: (data ?? []) as unknown as SafeZone[] };
}

export interface PublishInput {
  name: string;
  latitude: number;
  longitude: number;
  type: string;
  geoLga: string | null;
  geoWard: string | null;
  capacity: number | null;
  description: string | null;
  /** The caller is attesting they know where this is. */
  verified: boolean;
}

export type WriteResult =
  | { ok: true; zone: SafeZone }
  | { ok: false; error: string };

/** Adds or corrects a shelter. Command only — the function enforces it. */
export async function publishSafeZone(input: PublishInput): Promise<WriteResult> {
  const { data, error } = await supabase.rpc('publish_safe_zone', {
    p_name: input.name.trim(),
    p_latitude: input.latitude,
    p_longitude: input.longitude,
    p_type: input.type,
    p_geo_lga: input.geoLga,
    p_geo_ward: input.geoWard,
    p_capacity: input.capacity,
    p_description: input.description,
    p_verified: input.verified,
  });
  if (error) return { ok: false, error: error.message };
  return { ok: true, zone: data as SafeZone };
}

/** Records that somebody has confirmed this position, and who. */
export async function verifySafeZone(id: string): Promise<WriteResult> {
  const { data, error } = await supabase.rpc('verify_safe_zone', { p_id: id });
  if (error) return { ok: false, error: error.message };
  return { ok: true, zone: data as SafeZone };
}

/** Hides a shelter from the citizen app. Never deletes it. */
export async function retireSafeZone(
  id: string,
  why: string | null,
): Promise<WriteResult> {
  const { data, error } = await supabase.rpc('retire_safe_zone', {
    p_id: id,
    p_why: why,
  });
  if (error) return { ok: false, error: error.message };
  return { ok: true, zone: data as SafeZone };
}
