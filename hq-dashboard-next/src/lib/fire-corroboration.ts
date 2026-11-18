/**
 * When a fire seen from space backs up an incident.
 *
 * Phase 2 of the intelligence layer. A NASA FIRMS detection near an incident,
 * close in time, is evidence from a source no attacker controls: one more
 * INDEPENDENT source in the corroboration score (lib/corroboration.ts).
 *
 * The danger is false corroboration. In one November week NOAA-20 alone saw
 * about 2,000 hot pixels in a box around Plateau, almost all of it farm
 * burning. Some fire will be near many incidents by chance, and a burning field
 * a kilometre from a kidnapping says nothing about the kidnapping. So a fire
 * counts only when every one of these holds:
 *
 *  - the incident is a kind where fire is part of the event: FIRE, COMMUNITY
 *    ATTACK (villages are burned), and the voice report's ENVIRONMENT (Fire /
 *    Hazard). Not a kidnap, a road crash or a robbery;
 *  - FIRMS rated the detection nominal or high, not low;
 *  - the incident has a GPS fix, and the fire is within FIRE_LINK_KM of it.
 *    A ward-only incident gets no satellite link: a ward can be 25 km across;
 *  - the fire was seen from FIRE_BEFORE_H before the report to FIRE_AFTER_H
 *    after it. Before: the fire may be why somebody reported. After: FIRMS
 *    is about three hours behind the satellite, and passes are hours apart.
 *
 * However many detections match, they are ONE source: the satellite. Twenty
 * hot pixels from one burning compound are one observer, not twenty.
 */

import type { Alert } from '@/app/dashboard/types';
import { categoryOf } from './alert-category';

export const FIRE_LINK_KM = 2;
export const FIRE_BEFORE_H = 12;
export const FIRE_AFTER_H = 24;

/** Categories (as categoryOf spells them) where a fire is part of the event. */
export const FIRE_CATEGORIES: ReadonlySet<string> = new Set(['FIRE', 'COMMUNITY ATTACK', 'ENVIRONMENT']);

/** A `fire_detections` row as the console reads it. */
export interface FireRow {
  id: string;
  latitude: number;
  longitude: number;
  observed_at: string;
  confidence: 'low' | 'nominal' | 'high';
  daynight: 'D' | 'N';
  frp_mw: number | null;
  satellite: string;
  geo_lga: string | null;
  geo_ward: string | null;
}

/** Great-circle distance in km. */
export function distanceKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const r = (d: number) => (d * Math.PI) / 180;
  const a =
    Math.sin(r(lat2 - lat1) / 2) ** 2 +
    Math.cos(r(lat1)) * Math.cos(r(lat2)) * Math.sin(r(lng2 - lng1) / 2) ** 2;
  return 6371 * 2 * Math.asin(Math.min(1, Math.sqrt(a)));
}

function fixOf(a: Alert): { lat: number; lng: number } | null {
  const lat = a.lat ?? a.latitude;
  const lng = a.lng ?? a.longitude;
  return Number.isFinite(lat) && Number.isFinite(lng) && !(lat === 0 && lng === 0)
    ? { lat: lat as number, lng: lng as number }
    : null;
}

/** Whether fire evidence can bear on this kind of incident at all. */
export function fireCanCorroborate(a: Pick<Alert, 'type'> & { category?: string | null }): boolean {
  return FIRE_CATEGORIES.has(categoryOf(a));
}

/**
 * The fires that back up an incident, from any of its reports. Empty for a
 * kind of incident fire says nothing about, and for one with no GPS fix.
 */
export function firesBacking(reports: Alert[], fires: FireRow[]): FireRow[] {
  const linked = new Map<string, FireRow>();
  for (const r of reports) {
    if (!fireCanCorroborate(r)) continue;
    const fix = fixOf(r);
    const at = r.created_at ? Date.parse(r.created_at) : NaN;
    if (!fix || Number.isNaN(at)) continue;
    for (const f of fires) {
      if (f.confidence === 'low') continue;
      const seen = Date.parse(f.observed_at);
      if (seen < at - FIRE_BEFORE_H * 3_600_000 || seen > at + FIRE_AFTER_H * 3_600_000) continue;
      if (distanceKm(fix.lat, fix.lng, f.latitude, f.longitude) > FIRE_LINK_KM) continue;
      linked.set(f.id, f);
    }
  }
  return [...linked.values()];
}
