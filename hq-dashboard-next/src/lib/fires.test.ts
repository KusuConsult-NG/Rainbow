// Reading the NASA FIRMS feed, and placing a detection in Plateau.
//
// The header and the first rows below are copied from the live NOAA-20 feed
// (J1_VIIRS_C2_Global_7d.csv, fetched 2026-11-18): this is what FIRMS sends.
import { describe, expect, it } from 'vitest';

import { PLATEAU_BBOX, lgaAt, nearestWard, placeInPlateau } from './fire-place';
import { firmsAreaUrl, observedAt, parseFirmsCsv, redactKey } from './fires';
import { wardCentroids } from './ward_centroids';

const HEADER = 'latitude,longitude,bright_ti4,scan,track,acq_date,acq_time,satellite,confidence,version,bright_ti5,frp,daynight';
const LIVE = [
  HEADER,
  '9.54134,10.6025,339.18,0.38,0.36,2026-11-11,1244,N20,low,2.0NRT,310.7,3,D',
  '9.62432,10.47875,353.53,0.38,0.36,2026-11-11,1244,N20,nominal,2.0NRT,311.56,28.31,D',
  '9.62378,10.47527,345.35,0.38,0.36,2026-11-11,0022,N20,high,2.0NRT,310.54,10.2,N',
].join('\n');

describe('parseFirmsCsv', () => {
  it('reads the live feed', () => {
    const { detections, rejected } = parseFirmsCsv(LIVE, 'VIIRS_NOAA20_NRT');
    expect(rejected).toBe(0);
    expect(detections).toHaveLength(3);
    expect(detections[2]).toEqual({
      source: 'VIIRS_NOAA20_NRT',
      satellite: 'N20',
      latitude: 9.62378,
      longitude: 10.47527,
      observed_at: '2026-11-11T00:22:00Z',
      confidence: 'high',
      frp_mw: 10.2,
      daynight: 'N',
    });
  });

  it('finds columns by name, so a reordered or extended header still reads', () => {
    const csv = 'daynight,confidence,acq_time,acq_date,longitude,latitude,new_column\nN,nominal,130,2026-11-12,9.1,9.9,x';
    const { detections } = parseFirmsCsv(csv, 'VIIRS_SNPP_NRT');
    expect(detections[0]).toMatchObject({ latitude: 9.9, longitude: 9.1, observed_at: '2026-11-12T01:30:00Z', frp_mw: null });
  });

  it('counts bad rows instead of guessing at them', () => {
    const csv = [HEADER, '9.5,10.6,0,0,0,2026-11-11,2575,N20,low,v,0,3,D', '9.5,10.6,0,0,0,2026-11-11,1244,N20,certain,v,0,3,D', 'garbage'].join('\n');
    expect(parseFirmsCsv(csv, 'VIIRS_NOAA20_NRT')).toEqual({ detections: [], rejected: 3 });
  });

  it('a header with no rows is no fires, not an error', () => {
    expect(parseFirmsCsv(HEADER, 'VIIRS_NOAA21_NRT')).toEqual({ detections: [], rejected: 0 });
  });

  it('a response that is not the CSV throws, so a bad key never reads as a quiet night', () => {
    expect(() => parseFirmsCsv('Invalid MAP_KEY.', 'VIIRS_SNPP_NRT')).toThrow(/not the expected CSV/);
    expect(() => parseFirmsCsv('', 'VIIRS_SNPP_NRT')).toThrow(/empty/);
  });
});

describe('observedAt', () => {
  it('reads HHMM in UTC, including a short time', () => {
    expect(observedAt('2026-11-11', '1244')).toBe('2026-11-11T12:44:00Z');
    expect(observedAt('2026-11-11', '5')).toBe('2026-11-11T00:05:00Z');
    expect(observedAt('2026-11-11', '2400')).toBeNull();
    expect(observedAt('11/11/2026', '1244')).toBeNull();
  });
});

describe('the FIRMS URL and its key', () => {
  it('asks for one day of the Plateau box', () => {
    expect(firmsAreaUrl('abc123', 'VIIRS_NOAA20_NRT', [8.5, 8.3, 10.7, 10.4])).toBe(
      'https://firms.modaps.eosdis.nasa.gov/api/area/csv/abc123/VIIRS_NOAA20_NRT/8.5,8.3,10.7,10.4/1',
    );
  });

  it('redacts the key from anything that might be logged or stored', () => {
    expect(redactKey('fetch failed: https://x/api/area/csv/abc123/VIIRS', 'abc123')).toBe(
      'fetch failed: https://x/api/area/csv/[MAP_KEY]/VIIRS',
    );
  });
});

describe('placing a detection in Plateau', () => {
  it('covers the whole state in the box FIRMS is asked about', () => {
    const [w, s, e, n] = PLATEAU_BBOX;
    for (const ward of wardCentroids) {
      expect(ward.lng).toBeGreaterThan(w);
      expect(ward.lng).toBeLessThan(e);
      expect(ward.lat).toBeGreaterThan(s);
      expect(ward.lat).toBeLessThan(n);
    }
  });

  it('records the 13 ward centroids that lie outside their own LGA polygon', () => {
    // The ward centroids and the LGA polygons come from different datasets
    // (assets/geo/plateau_wards.json says which), and they disagree here. A
    // fire is placed the way the app places an incident (jurisdiction_resolver
    // .dart): polygon for the LGA, then the nearest ward inside it. So a fire
    // and an incident at the same spot still get the same ward, which is what
    // corroboration needs. The list is pinned so the disagreement stays
    // visible, and any change to either dataset shows up here.
    const outside = wardCentroids
      .filter((w) => lgaAt(w.lat, w.lng) !== w.lga.toUpperCase().replace(/\s+/g, ' '))
      .map((w) => `${w.lga} / ${w.ward.replace(/\s+/g, ' ')} -> ${lgaAt(w.lat, w.lng) ?? 'no LGA'}`);
    expect(outside).toEqual([
      'BOKKOS / MANGUNA -> BARKIN LADI',
      "JOS EAST / FOBUR 'B' -> JOS NORTH",
      'JOS NORTH / JENTA ADAMU -> JOS SOUTH',
      'JOS NORTH / TUDUN WADA - KABONG -> JOS SOUTH',
      'JOS SOUTH / VWANG -> RIYOM',
      'KANAM / DUGUB -> no LGA',
      'KANKE / AMPANG-EAST -> PANKSHIN',
      'KANKE / NEMEL -> no LGA',
      'LANGTANG NORTH / MBAN/ZAMKO -> MIKANG',
      'LANGTANG NORTH / PISHE/YASHI -> KANAM',
      'MIKANG / GARKAWA CENTRAL -> SHENDAM',
      "MIKANG / KOENOEM 'A' -> SHENDAM",
      'WASE / KUMBONG -> LANGTANG NORTH',
    ]);
  });

  it('gives a fire at a ward centroid that ward', () => {
    const w = wardCentroids.find((x) => x.lga === 'WASE')!;
    expect(placeInPlateau(w.lat, w.lng)).toEqual({ lga: 'WASE', ward: w.ward });
  });

  it('drops a fire outside Plateau', () => {
    expect(placeInPlateau(10.31, 9.84)).toBeNull(); // Bauchi
    expect(placeInPlateau(9.06, 7.49)).toBeNull(); // Abuja
  });

  it('chooses the nearest ward inside the LGA, not across a border', () => {
    const w = nearestWard('JOS NORTH', 9.8965, 8.8583);
    expect(w?.lga).toBe('JOS NORTH');
  });
});
