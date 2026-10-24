/**
 * Where to draw an incident, and how certain to look about it.
 *
 * ## The problem this solves
 *
 * A report that arrives over USSD has **no GPS and cannot have one**. USSD rides
 * the signalling channel; it has no access to the handset's location, and no
 * amount of engineering changes that. What it has is the ward the caller chose on
 * a menu.
 *
 * `LiveMap` skips any alert whose coordinates are not finite. That is correct —
 * the alternative is the C-5 defect this codebase already fixed once, where a
 * missing fix fell back to central Jos and an alert with no location rendered as
 * a confident pin, and responders were dispatched to a coordinate produced by a
 * `||` operator.
 *
 * But the consequence was that a USSD emergency appeared in the incident list and
 * **nowhere on the map the operator is actually watching**. An emergency that
 * exists and cannot be seen is the failure this whole audit keeps finding.
 *
 * ## So: an area, never a pin
 *
 * The fix is not to invent coordinates. It is to draw what is known at the
 * precision it is known to. A GPS fix is a point. A ward is a circle the size of
 * the ward. An LGA is a much bigger circle. Nothing is nothing, and stays off the
 * map with the console's UNLOCATED counter reporting it.
 *
 * The distinction has to survive contact with an operator under pressure, which
 * means it cannot be a subtle styling difference — see `LiveMap`, where an
 * approximate location is a translucent circle with a dashed edge and no pin at
 * its centre. A dispatcher must never be able to mistake one for the other,
 * because the difference is whether a vehicle can be sent to it.
 */

import { geoKey } from './geo-key';
import { wardCentroids } from './ward_centroids';

/** How well this incident's position is actually known. */
export type LocationPrecision =
  /** A real fix from a handset. A point. */
  | 'GPS'
  /** The ward is known. A circle the size of that ward. */
  | 'WARD'
  /** Only the LGA is known. A circle covering it. */
  | 'LGA'
  /** Nothing is known. Not drawn, and counted as UNLOCATED. */
  | 'NONE';

export interface IncidentLocation {
  precision: LocationPrecision;
  lat?: number;
  lng?: number;
  /** Radius in metres. Zero for a GPS fix. */
  radiusM: number;
  /** What to show a dispatcher about how much to trust it. */
  label: string;
}

export interface LocatableAlert {
  lat?: number | null;
  lng?: number | null;
  latitude?: number | null;
  longitude?: number | null;
  geo_lga?: string | null;
  geo_ward?: string | null;
}

/**
 * Metres between two points. Haversine — Plateau spans about two degrees.
 *
 * Exported because `safe-zones.ts` needs the same measurement to tell an
 * operator whether a shelter position they are entering falls inside a
 * surveyed ward of the LGA they have chosen. A third copy of a haversine in
 * this repository would be one more place for a mistake to live; there are
 * already two (`incident-track.ts` keeps its own because it works in a hot
 * loop over a track and uses a different earth radius).
 */
export function metresBetween(
  a: { lat: number; lng: number },
  b: { lat: number; lng: number },
): number {
  const R = 6_371_000;
  const p1 = (a.lat * Math.PI) / 180;
  const p2 = (b.lat * Math.PI) / 180;
  const dp = p2 - p1;
  const dl = ((b.lng - a.lng) * Math.PI) / 180;
  const h =
    Math.sin(dp / 2) ** 2 + Math.cos(p1) * Math.cos(p2) * Math.sin(dl / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

/** A readable distance, for a label a dispatcher reads at a glance. */
export function approxRadiusLabel(radiusM: number): string {
  if (radiusM < 1000) return `${Math.round(radiusM / 100) * 100}m`;
  return `${(radiusM / 1000).toFixed(radiusM < 10_000 ? 1 : 0)}km`;
}

/**
 * The LGA's own area, derived from its wards.
 *
 * Computed rather than tabulated: a hand-written LGA centre is one more number
 * nobody checks, and the ward centroids are already the only geography this
 * system has. The radius covers the furthest ward from the mean centre, so the
 * circle genuinely contains the LGA rather than suggesting the middle of it.
 */
function lgaArea(lga: string): { lat: number; lng: number; radiusM: number } | null {
  const key = geoKey(lga);
  if (!key) return null;
  const wards = wardCentroids.filter(w => geoKey(w.lga) === key);
  if (wards.length === 0) return null;

  const lat = wards.reduce((s, w) => s + w.lat, 0) / wards.length;
  const lng = wards.reduce((s, w) => s + w.lng, 0) / wards.length;
  const furthest = wards.reduce(
    (m, w) => Math.max(m, metresBetween({ lat, lng }, w)),
    0,
  );
  // Plus the outermost ward's own radius, so the circle contains the ward rather
  // than stopping at its centre. Floored so a single-ward LGA still draws
  // something an operator can see.
  const pad = wards.reduce((m, w) => Math.max(m, w.radiusM), 0);
  return { lat, lng, radiusM: Math.max(4000, Math.round(furthest + pad)) };
}

/**
 * Where to draw this incident.
 *
 * `latitude`/`longitude` are checked as well as `lat`/`lng` because the database
 * columns are the former and the console maps them across — an alert read
 * straight from PostgREST has only the long names, and a locator that knew one
 * spelling would silently downgrade every GPS report to a ward circle.
 */
export function locateIncident(alert: LocatableAlert): IncidentLocation {
  const lat = alert.lat ?? alert.latitude;
  const lng = alert.lng ?? alert.longitude;

  // A real fix. `Number.isFinite`, not a truthiness check: 0 is a coordinate —
  // in the Gulf of Guinea, so never a real Plateau fix, but a falsy test on a
  // number is the habit that produces C-5-shaped bugs.
  if (Number.isFinite(lat) && Number.isFinite(lng)) {
    return {
      precision: 'GPS',
      lat: Number(lat),
      lng: Number(lng),
      radiusM: 0,
      label: 'GPS fix from the handset',
    };
  }

  const wardKey = geoKey(alert.geo_ward);
  const lgaKey = geoKey(alert.geo_lga);

  if (wardKey) {
    // Matched on geoKey, because the app writes a ward resolved from the GPS
    // asset ('GINDIRI  I') and an officer may have been posted from the tactical
    // map ('GINDIRI  1'). Raw comparison would drop the ward and fall through to
    // the whole LGA — a circle ten times too big, for a difference of notation.
    const ward = wardCentroids.find(
      w => geoKey(w.ward) === wardKey && (!lgaKey || geoKey(w.lga) === lgaKey),
    );
    if (ward) {
      return {
        precision: 'WARD',
        lat: ward.lat,
        lng: ward.lng,
        radiusM: ward.radiusM,
        label: `Somewhere in ${ward.ward} ward — about ${approxRadiusLabel(ward.radiusM)} across`,
      };
    }
  }

  if (lgaKey) {
    const area = lgaArea(alert.geo_lga ?? '');
    if (area) {
      return {
        precision: 'LGA',
        lat: area.lat,
        lng: area.lng,
        radiusM: area.radiusM,
        label: `Only the LGA is known — somewhere in ${alert.geo_lga}, about `
          + `${approxRadiusLabel(area.radiusM)} across`,
      };
    }
  }

  return {
    precision: 'NONE',
    radiusM: 0,
    // Said plainly, because this is the case a dispatcher must chase rather than
    // wait on. A USSD caller can be rung back; an app reporter cannot always be.
    label: 'No location at all — ring the reporter if you can',
  };
}

/** Whether this position is good enough to send a vehicle to. */
export function isSendable(loc: IncidentLocation): boolean {
  // A ward circle is not a destination. It tells a commander which unit owns the
  // incident, and that is a different question from where to drive. Treating an
  // approximate area as a destination is how a team ends up searching 3km of
  // countryside while the dispatcher believes they were given an address.
  return loc.precision === 'GPS';
}
