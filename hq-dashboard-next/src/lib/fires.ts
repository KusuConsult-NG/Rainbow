/**
 * NASA FIRMS fire detections: reading the feed.
 *
 * Phase 2 of the intelligence layer. FIRMS publishes every VIIRS thermal
 * detection within about three hours of a satellite pass, as CSV. This module
 * turns that CSV into rows, and nothing else: placing a detection in an LGA
 * and ward is lib/fire-place.ts (server only, it carries the boundaries), and
 * deciding what a detection MEANS is the corroboration score and, later, the
 * ward baselines.
 *
 * The columns, as FIRMS serves them for VIIRS (checked against the live feed
 * on 2026-11-18):
 *
 *   latitude, longitude, bright_ti4, scan, track, acq_date, acq_time,
 *   satellite, confidence, version, bright_ti5, frp, daynight
 *
 * `acq_time` is HHMM in UTC, without a separator ("0022" is 00:22). VIIRS
 * `confidence` is a word: low, nominal, high.
 */

/** The FIRMS products fetched: VIIRS on all three satellites, near real time. */
export const FIRMS_SOURCES = ['VIIRS_SNPP_NRT', 'VIIRS_NOAA20_NRT', 'VIIRS_NOAA21_NRT'] as const;
export type FirmsSource = (typeof FIRMS_SOURCES)[number];

export type FireConfidence = 'low' | 'nominal' | 'high';

export interface FireDetection {
  source: FirmsSource;
  satellite: string;
  latitude: number;
  longitude: number;
  /** ISO 8601, UTC. */
  observed_at: string;
  confidence: FireConfidence;
  frp_mw: number | null;
  daynight: 'D' | 'N';
}

/**
 * The FIRMS area API URL. The key is in the PATH, so this string must never
 * be logged or stored: see `redactKey`.
 */
export function firmsAreaUrl(key: string, source: FirmsSource, bbox: readonly number[], days = 1): string {
  return `https://firms.modaps.eosdis.nasa.gov/api/area/csv/${encodeURIComponent(key)}/${source}/${bbox.join(',')}/${days}`;
}

/** Any text with the key replaced, for errors that may quote a URL. */
export function redactKey(text: string, key: string): string {
  return key ? text.split(key).join('[MAP_KEY]') : text;
}

const CONFIDENCE: Record<string, FireConfidence> = { low: 'low', nominal: 'nominal', high: 'high', l: 'low', n: 'nominal', h: 'high' };

/** "2026-11-11" + "0022" -> "2026-11-11T00:22:00Z", or null if either is malformed. */
export function observedAt(date: string, time: string): string | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return null;
  const t = time.trim().padStart(4, '0');
  if (!/^\d{4}$/.test(t)) return null;
  const hh = Number(t.slice(0, 2));
  const mm = Number(t.slice(2));
  if (hh > 23 || mm > 59) return null;
  return `${date}T${t.slice(0, 2)}:${t.slice(2)}:00Z`;
}

export interface ParseResult {
  detections: FireDetection[];
  /** Rows that were not valid detections, so a format change is noticed. */
  rejected: number;
}

/**
 * The detections in one FIRMS CSV response.
 *
 * Columns are found by name, not position, so a column FIRMS adds does not
 * shift the rest. A response that is not CSV at all (FIRMS answers an invalid
 * key with a sentence) throws, rather than reading as "no fires".
 */
export function parseFirmsCsv(text: string, source: FirmsSource): ParseResult {
  const lines = text.split(/\r?\n/).filter((l) => l.trim() !== '');
  if (lines.length === 0) throw new Error('FIRMS returned an empty response');
  const header = lines[0].split(',').map((h) => h.trim().toLowerCase());
  const col = (name: string) => header.indexOf(name);
  const need = ['latitude', 'longitude', 'acq_date', 'acq_time', 'confidence', 'daynight'];
  const missing = need.filter((n) => col(n) < 0);
  if (missing.length > 0) {
    throw new Error(`FIRMS response is not the expected CSV (missing ${missing.join(', ')}): "${lines[0].slice(0, 80)}"`);
  }

  const detections: FireDetection[] = [];
  let rejected = 0;
  for (const line of lines.slice(1)) {
    const cells = line.split(',');
    const get = (name: string) => (cells[col(name)] ?? '').trim();
    const lat = Number(get('latitude'));
    const lng = Number(get('longitude'));
    const at = observedAt(get('acq_date'), get('acq_time'));
    const confidence = CONFIDENCE[get('confidence').toLowerCase()];
    const dn = get('daynight').toUpperCase();
    const frpRaw = col('frp') >= 0 ? get('frp') : '';
    const frp = frpRaw === '' ? null : Number(frpRaw);
    if (
      !Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180 ||
      at === null || confidence === undefined || (dn !== 'D' && dn !== 'N') ||
      (frp !== null && !Number.isFinite(frp))
    ) {
      rejected++;
      continue;
    }
    detections.push({
      source,
      satellite: get('satellite') || source,
      latitude: lat,
      longitude: lng,
      observed_at: at,
      confidence,
      frp_mw: frp,
      daynight: dn,
    });
  }
  return { detections, rejected };
}
