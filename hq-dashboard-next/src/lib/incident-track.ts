/**
 * The route a person took during one incident.
 *
 * ## What was missing
 *
 * An SOS starts a track, the handset reports a position every few seconds, and
 * the console drew a trail. But `telemetry` has `user_id` as its primary key
 * and is upserted, so the database held the CURRENT position and nothing else.
 * The trail lived in `agentPathsRef` — a `Map` in one browser tab, capped at
 * thirty points. Refresh the console and it was gone; join mid-incident and
 * you saw a dot; review the incident afterwards and there was no movement at
 * all.
 *
 * For a kidnapping, "which way did they go" is the question.
 *
 * `incident_tracks` now keeps the points against the incident. This module is
 * what the console does with them, kept pure so the arithmetic — which decides
 * what an operator is told about distance and duration — can be tested without
 * a map.
 *
 * ## Reading a route honestly
 *
 * A GPS track is not a path somebody walked; it is a sequence of estimates,
 * each with an error radius. Two of the functions below exist because of that:
 * [summariseTrack] ignores steps shorter than the accuracy that produced them,
 * and the summary says how many points it is built from, so an operator can
 * tell a five-point sketch from a two-hundred-point route.
 */

export interface TrackPoint {
  latitude: number;
  longitude: number;
  accuracy?: number | null;
  speed?: number | null;
  recorded_at: string;
}

export interface TrackSummary {
  /** How many fixes the route is drawn from. */
  points: number;
  /** The first and last fix, or null when there are none. */
  from: string | null;
  to: string | null;
  /** Milliseconds between the first and last fix. */
  durationMs: number;
  /** Ground distance along the route, in metres. */
  distanceMetres: number;
  /** The fastest fix reported, in metres per second, or null. */
  maxSpeed: number | null;
  /** True when every fix is within a few metres of the first. */
  stationary: boolean;
}

const EARTH_RADIUS_M = 6371008.8;

/** Metres between two fixes. */
export function metresBetween(a: TrackPoint, b: TrackPoint): number {
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(b.latitude - a.latitude);
  const dLng = toRad(b.longitude - a.longitude);
  const lat1 = toRad(a.latitude);
  const lat2 = toRad(b.latitude);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.min(1, Math.sqrt(h)));
}

/** Points in the order they were recorded, with anything unusable dropped. */
export function orderTrack(points: TrackPoint[]): TrackPoint[] {
  return points
    .filter(
      (p) =>
        Number.isFinite(p.latitude) &&
        Number.isFinite(p.longitude) &&
        !Number.isNaN(Date.parse(p.recorded_at)),
    )
    .slice()
    .sort((a, b) => Date.parse(a.recorded_at) - Date.parse(b.recorded_at));
}

/**
 * What the route adds up to.
 *
 * Distance ignores a step shorter than the accuracy of the fix that produced
 * it. Without that, a handset sitting on a table reports jitter of a few metres
 * every few seconds and the console tells an operator the person walked two
 * kilometres — which is worse than saying nothing, because it is specific.
 */
export function summariseTrack(raw: TrackPoint[]): TrackSummary {
  const points = orderTrack(raw);
  if (points.length === 0) {
    return {
      points: 0,
      from: null,
      to: null,
      durationMs: 0,
      distanceMetres: 0,
      maxSpeed: null,
      stationary: true,
    };
  }

  let distance = 0;
  let maxSpeed: number | null = null;
  let spread = 0;
  const first = points[0];

  for (let i = 0; i < points.length; i += 1) {
    const p = points[i];
    if (typeof p.speed === 'number' && Number.isFinite(p.speed) && p.speed >= 0) {
      maxSpeed = maxSpeed === null ? p.speed : Math.max(maxSpeed, p.speed);
    }
    spread = Math.max(spread, metresBetween(first, p));
    if (i === 0) continue;

    const step = metresBetween(points[i - 1], p);
    // The larger of the two accuracies, floored at 5m — the distance filter the
    // handset already applies — so a step inside the error radius is noise.
    const tolerance = Math.max(
      5,
      points[i - 1].accuracy ?? 0,
      p.accuracy ?? 0,
    );
    if (step > tolerance) distance += step;
  }

  const from = points[0].recorded_at;
  const to = points[points.length - 1].recorded_at;
  return {
    points: points.length,
    from,
    to,
    durationMs: Math.max(0, Date.parse(to) - Date.parse(from)),
    distanceMetres: distance,
    maxSpeed,
    stationary: spread <= 25,
  };
}

/**
 * Thins a long route for drawing, keeping its shape.
 *
 * A two-hour SOS at one fix every five seconds is well over a thousand points,
 * and a Leaflet polyline of that redraws on every pan. Keeps the first and last
 * — losing either would move where the route starts or ends, which is the part
 * an operator reads first — and samples evenly between them.
 */
export function thinTrack(points: TrackPoint[], limit = 300): TrackPoint[] {
  const ordered = orderTrack(points);
  if (ordered.length <= limit || limit < 2) return ordered;

  const kept: TrackPoint[] = [ordered[0]];
  const step = (ordered.length - 1) / (limit - 1);
  for (let i = 1; i < limit - 1; i += 1) {
    kept.push(ordered[Math.round(i * step)]);
  }
  kept.push(ordered[ordered.length - 1]);
  return kept;
}

function describeDistance(metres: number): string {
  if (metres < 1000) return `${Math.round(metres)} m`;
  return `${(metres / 1000).toFixed(1)} km`;
}

function describeDuration(ms: number): string {
  const mins = Math.round(ms / 60000);
  if (mins < 1) return 'under a minute';
  if (mins < 60) return `${mins} min`;
  const hours = Math.floor(mins / 60);
  return `${hours}h ${mins % 60}m`;
}

/**
 * The sentence an operator reads.
 *
 * Says what is missing when it is missing. "No movement recorded" and "did not
 * move" are different facts — the first can mean the handset never reported,
 * the second that it reported and stayed put — and a dispatcher deciding
 * whether somebody is still where they said they were needs the difference.
 */
export function describeTrack(summary: TrackSummary): string {
  if (summary.points === 0) {
    return 'No movement recorded for this incident.';
  }
  if (summary.points === 1) {
    return 'One position recorded — not enough for a route.';
  }
  if (summary.stationary) {
    return `Stayed in one place for ${describeDuration(summary.durationMs)} `
      + `(${summary.points} fixes).`;
  }
  return `${describeDistance(summary.distanceMetres)} over `
    + `${describeDuration(summary.durationMs)} (${summary.points} fixes).`;
}
