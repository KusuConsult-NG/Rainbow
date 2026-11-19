import { wardCentroids } from './ward_centroids';
import { boundaryLgaNames, lgaContaining, lgaKey } from './lga-boundaries';
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
 *     it is stored, by point-in-polygon against the real boundary — the same
 *     test `check_a_shelter_is_where_it_says.py` applies to the seed and the
 *     same one `jurisdiction_resolver.dart` applies to an incident. The check
 *     that found the three bad rows now runs where the data is entered.
 *
 * It is a WARNING and not a refusal. The ADM2 dataset leaves slivers between
 * neighbours — two of the 207 surveyed ward centroids fall inside no LGA at
 * all — a building can stand on a boundary, and an operator at the door knows
 * more than this does. What it must not do is let somebody store a position in
 * the next LGA without being told.
 *
 * See E2E_AUDIT_REPORT.md T-93, T-94, T-98, T-101.
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
 * rows, asked of a row somebody is about to add — and asked the way the app
 * decides an incident's LGA: point-in-polygon against the real boundary.
 *
 * It used to measure to the nearest ward centroid of the claimed LGA and
 * compare against that centroid's radius. Those radii are half the distance to
 * the nearest neighbouring centroid and discs do not tile a plane, so the rule
 * rejected 57.7% of real Plateau and 78% of Jos North: a commander entering a
 * correct position was told it was in the wrong LGA more often than not, on
 * the screen built so they could fix the three that genuinely were. See
 * E2E_AUDIT_REPORT.md T-101.
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

  const claimed = (lga ?? '').trim();
  if (!claimed) return null;      // no LGA claimed, nothing to disagree with
  const key = lgaKey(claimed);
  const names = boundaryLgaNames();
  if (!names.some((n) => lgaKey(n) === key)) {
    return {
      kind: 'no-such-lga',
      message:
        `${claimed.toUpperCase()} is not one of the ${names.length} LGAs of ` +
        'Plateau, so the citizen app cannot scope a shelter to it.',
    };
  }

  const actual = lgaContaining(lat, lng);
  if (actual === null) {
    // Inside the state's extent but inside no polygon. The ADM2 dataset leaves
    // gaps between neighbours — two surveyed ward centroids land in one — so
    // this is worth saying and not worth refusing.
    return {
      kind: 'outside-lga',
      message:
        'That position is inside Plateau but not inside any LGA boundary. ' +
        'The boundary data leaves slivers between neighbours, so this may be ' +
        'one of them — worth checking before a citizen is routed here.',
    };
  }
  if (lgaKey(actual) === key) return null;

  const ward = nearestWardIn(lat, lng, actual);
  return {
    kind: 'outside-lga',
    message:
      `That position is in ${actual}${ward ? ` (nearest ward ${ward})` : ''}, ` +
      `not ${claimed.toUpperCase()}. A citizen in ${claimed.toUpperCase()} ` +
      'would be sent across the boundary to it.',
  };
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
