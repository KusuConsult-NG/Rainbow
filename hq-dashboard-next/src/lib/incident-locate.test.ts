// Where to draw an incident, and how certain to look about it.
//
// A USSD report has no GPS and cannot have one. LiveMap skips anything without
// finite coordinates — correctly, because the alternative is the C-5 defect where
// a missing fix fell back to central Jos and drew a confident pin. The
// consequence was that a USSD emergency appeared in the list and NOWHERE on the
// map.
//
// These tests pin the line this module walks: draw what is known, at the
// precision it is known to, and never let an area be mistaken for a fix.
import { describe, expect, it } from 'vitest';

import {
  approxRadiusLabel,
  isSendable,
  locateIncident,
} from './incident-locate';
import { wardCentroids } from './ward_centroids';

describe('a real GPS fix', () => {
  it('is a point with no radius', () => {
    const loc = locateIncident({ lat: 9.9285, lng: 8.8921, geo_lga: 'JOS NORTH' });
    expect(loc.precision).toBe('GPS');
    expect(loc.lat).toBe(9.9285);
    expect(loc.radiusM).toBe(0);
  });

  it('is read from latitude/longitude as well as lat/lng', () => {
    // The DATABASE columns are the long names and the console maps them across.
    // A locator that knew only one spelling would silently downgrade every GPS
    // report read straight from PostgREST to a ward circle.
    const loc = locateIncident({ latitude: 9.9285, longitude: 8.8921 });
    expect(loc.precision).toBe('GPS');
    expect(loc.lng).toBe(8.8921);
  });

  it('accepts a coordinate of exactly zero', () => {
    // 0 is a coordinate. A falsy check on a number is the habit that produced
    // C-5, and it would push a real fix down to a ward circle.
    const loc = locateIncident({ lat: 0, lng: 0 });
    expect(loc.precision).toBe('GPS');
  });

  it('is the only precision good enough to drive to', () => {
    expect(isSendable(locateIncident({ lat: 9.9, lng: 8.9 }))).toBe(true);
  });
});

describe('a ward but no fix — the USSD case', () => {
  const REAL = wardCentroids[0];

  it('draws an area at the ward centroid', () => {
    const loc = locateIncident({ geo_lga: REAL.lga, geo_ward: REAL.ward });
    expect(loc.precision).toBe('WARD');
    expect(loc.lat).toBe(REAL.lat);
    expect(loc.lng).toBe(REAL.lng);
    expect(loc.radiusM).toBe(REAL.radiusM);
  });

  it('is NOT sendable — a circle is not a destination', () => {
    // Treating an area as an address is how a team searches 3km of countryside
    // while the dispatcher believes they handed over a place.
    const loc = locateIncident({ geo_lga: REAL.lga, geo_ward: REAL.ward });
    expect(isSendable(loc)).toBe(false);
  });

  it('says in words that it is approximate, and how approximate', () => {
    const loc = locateIncident({ geo_lga: REAL.lga, geo_ward: REAL.ward });
    expect(loc.label).toContain('Somewhere in');
    expect(loc.label).toContain(REAL.ward);
    expect(loc.label).toMatch(/\d/);
  });

  it('matches a ward on geoKey, not on the raw string', () => {
    // The app writes 'GINDIRI  I' from the GPS asset; an officer may be posted
    // from the tactical map as 'GINDIRI  1'. A raw comparison drops the ward and
    // falls through to the whole LGA — a circle ten times too big, for a
    // difference of notation.
    const roman = locateIncident({ geo_lga: 'MANGU', geo_ward: 'GINDIRI  I' });
    const arabic = locateIncident({ geo_lga: 'MANGU', geo_ward: 'GINDIRI  1' });
    expect(roman.precision).toBe('WARD');
    expect(arabic.precision).toBe('WARD');
    expect(arabic.lat).toBe(roman.lat);
  });

  it('is case- and spacing-insensitive', () => {
    const loc = locateIncident({
      geo_lga: REAL.lga.toLowerCase(),
      geo_ward: `  ${REAL.ward.toLowerCase()} `,
    });
    expect(loc.precision).toBe('WARD');
    expect(loc.lat).toBe(REAL.lat);
  });

  it('does not accept a ward name from the wrong LGA', () => {
    // Two LGAs can carry a similar ward name. Matching on the ward alone would
    // put an incident in the wrong half of the state.
    const other = wardCentroids.find(w => w.lga !== REAL.lga)!;
    const loc = locateIncident({ geo_lga: REAL.lga, geo_ward: other.ward });
    expect(loc.precision).not.toBe('WARD');
  });
});

describe('only an LGA', () => {
  it('draws a much bigger area covering it', () => {
    const loc = locateIncident({ geo_lga: 'JOS NORTH' });
    expect(loc.precision).toBe('LGA');
    expect(loc.radiusM).toBeGreaterThan(4000);
    expect(loc.label).toContain('Only the LGA is known');
  });

  it('is bigger than any of its wards, so the circle actually contains them', () => {
    const loc = locateIncident({ geo_lga: 'JOS NORTH' });
    const wards = wardCentroids.filter(w => w.lga === 'JOS NORTH');
    expect(loc.radiusM).toBeGreaterThan(Math.max(...wards.map(w => w.radiusM)));
  });

  it('is not sendable either', () => {
    expect(isSendable(locateIncident({ geo_lga: 'JOS NORTH' }))).toBe(false);
  });

  it('falls through to nothing for an LGA that is not in Plateau', () => {
    // Inventing a centre for a place this system has no data about would put a
    // circle somewhere arbitrary and label it with confidence.
    const loc = locateIncident({ geo_lga: 'LAGOS ISLAND' });
    expect(loc.precision).toBe('NONE');
  });
});

describe('nothing at all', () => {
  it('is NONE, with no coordinates invented', () => {
    for (const alert of [
      {},
      { geo_lga: null, geo_ward: null },
      { geo_lga: '', geo_ward: '   ' },
      { lat: null, lng: null, geo_lga: null },
    ]) {
      const loc = locateIncident(alert);
      expect(loc.precision, JSON.stringify(alert)).toBe('NONE');
      expect(loc.lat).toBeUndefined();
      expect(loc.lng).toBeUndefined();
    }
  });

  it('tells the dispatcher to chase it rather than wait', () => {
    const loc = locateIncident({});
    expect(loc.label).toContain('No location at all');
    expect(loc.label).toContain('ring the reporter');
  });

  it('never claims a precision it does not have', () => {
    // The whole file in one assertion: a half-known location must not round up.
    // GPS is only ever returned for a real fix.
    expect(locateIncident({ geo_lga: 'JOS NORTH', geo_ward: 'ABBA NA SHEHU' }).precision)
      .not.toBe('GPS');
    expect(locateIncident({ geo_lga: 'JOS NORTH' }).precision).not.toBe('WARD');
    expect(locateIncident({}).precision).not.toBe('LGA');
  });
});

describe('the radius label', () => {
  it('reads in metres below a kilometre, rounded to something honest', () => {
    expect(approxRadiusLabel(800)).toBe('800m');
    expect(approxRadiusLabel(950)).toBe('1000m');
  });

  it('reads in kilometres above it', () => {
    expect(approxRadiusLabel(3547)).toBe('3.5km');
    expect(approxRadiusLabel(16560)).toBe('17km');
  });
});

describe('the centroid data itself', () => {
  it('covers all 207 wards', () => {
    // A truncated asset would silently shrink the map's coverage, and the wards
    // that vanished would be the ones whose incidents stop appearing.
    expect(wardCentroids).toHaveLength(207);
  });

  it('is all inside Plateau State', () => {
    // Plateau sits roughly between 8.3–10.5N and 8.3–10.3E. A centroid outside
    // that is a data error that would draw an incident in another state.
    for (const w of wardCentroids) {
      expect(w.lat, `${w.ward}: ${w.lat}`).toBeGreaterThan(8);
      expect(w.lat, `${w.ward}: ${w.lat}`).toBeLessThan(11);
      expect(w.lng, `${w.ward}: ${w.lng}`).toBeGreaterThan(8);
      expect(w.lng, `${w.ward}: ${w.lng}`).toBeLessThan(11);
    }
  });

  it('has a radius in the clamped range for every ward', () => {
    for (const w of wardCentroids) {
      expect(w.radiusM, w.ward).toBeGreaterThanOrEqual(800);
      expect(w.radiusM, w.ward).toBeLessThanOrEqual(25_000);
    }
  });

  it('covers every LGA the tactical map knows', async () => {
    // A USSD caller picks their LGA from the tactical map. An LGA present there
    // and absent here is one whose reports cannot be drawn at all.
    const { plateauTacticalMap } = await import('./tactical_mapping');
    const { geoKey } = await import('./geo-key');
    const known = new Set(wardCentroids.map(w => geoKey(w.lga)));
    const missing = plateauTacticalMap
      .map(l => l.name)
      .filter(n => !known.has(geoKey(n)));
    expect(missing).toEqual([]);
  });
});
