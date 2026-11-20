// When a fire seen from space backs up an incident, and, as importantly, when
// it does not. Dry-season farm burning puts some fire near many incidents by
// chance; each rule below is there so that chance is not read as evidence.
import { describe, expect, it } from 'vitest';

import type { Alert } from '@/app/dashboard/types';
import { clusterAlerts } from './alert-display';
import { corroborate, corroborationLine, withCorroboration } from './corroboration';
import { distanceKm, firesBacking, FIRE_LINK_KM, type FireRow } from './fire-corroboration';

const AT = '2026-11-18T22:00:00Z';
const HERE = { lat: 9.6243, lng: 10.4787 };

let n = 0;
const incident = (over: Partial<Alert> = {}): Alert =>
  ({
    id: `i${++n}`,
    type: 'Community attack - Armed Invasion',
    status: 'PENDING',
    severity: 'CRITICAL',
    geo_lga: 'WASE',
    geo_ward: 'BASHAR',
    lat: HERE.lat,
    lng: HERE.lng,
    created_at: AT,
    reported_by: 'p1',
    ...over,
  }) as Alert;

const fire = (over: Partial<FireRow> = {}): FireRow => ({
  id: `f${++n}`,
  latitude: HERE.lat + 0.005, // about 550 m north
  longitude: HERE.lng,
  observed_at: '2026-11-18T23:40:00Z',
  confidence: 'nominal',
  daynight: 'N',
  frp_mw: 18,
  satellite: 'N20',
  geo_lga: 'WASE',
  geo_ward: 'BASHAR',
  ...over,
});

describe('firesBacking', () => {
  it('links a nearby, timely, credible fire to a community attack', () => {
    expect(firesBacking([incident()], [fire()])).toHaveLength(1);
  });

  it('does not link a fire to a kind of incident fire says nothing about', () => {
    expect(firesBacking([incident({ type: 'Kidnap - Abduction' })], [fire()])).toEqual([]);
    expect(firesBacking([incident({ type: 'Fire - Building Fire' })], [fire()])).toHaveLength(1);
    expect(firesBacking([incident({ type: 'ENVIRONMENT - Fire / Hazard' })], [fire()])).toHaveLength(1);
  });

  it('ignores a low-confidence detection', () => {
    expect(firesBacking([incident()], [fire({ confidence: 'low' })])).toEqual([]);
  });

  it(`ignores a fire more than ${FIRE_LINK_KM} km away`, () => {
    const far = fire({ latitude: HERE.lat + 0.03 }); // about 3.3 km
    expect(distanceKm(HERE.lat, HERE.lng, far.latitude, far.longitude)).toBeGreaterThan(FIRE_LINK_KM);
    expect(firesBacking([incident()], [far])).toEqual([]);
  });

  it('accepts a fire up to 12 h before the report and 24 h after, and nothing outside that', () => {
    const at = (h: number) => new Date(Date.parse(AT) + h * 3_600_000).toISOString();
    expect(firesBacking([incident()], [fire({ observed_at: at(-11) })])).toHaveLength(1);
    expect(firesBacking([incident()], [fire({ observed_at: at(23) })])).toHaveLength(1);
    expect(firesBacking([incident()], [fire({ observed_at: at(-13) })])).toEqual([]);
    expect(firesBacking([incident()], [fire({ observed_at: at(25) })])).toEqual([]);
  });

  it('gives a ward-only incident no satellite link: a ward can be 25 km across', () => {
    expect(firesBacking([incident({ lat: undefined, lng: undefined })], [fire()])).toEqual([]);
    expect(firesBacking([incident({ lat: 0, lng: 0 })], [fire()])).toEqual([]);
  });

  it('reads the database spelling of the coordinates too', () => {
    const a = incident({ lat: undefined, lng: undefined, latitude: HERE.lat, longitude: HERE.lng });
    expect(firesBacking([a], [fire()])).toHaveLength(1);
  });
});

describe('the satellite in the corroboration score', () => {
  it('many detections are one source, the satellite', () => {
    const c = corroborate([incident()], 7);
    expect(c.sources).toBe(2);
    expect(c.channels).toEqual(['APP', 'SATELLITE']);
    expect(c.fireDetections).toBe(7);
  });

  it('one person and the satellite corroborate; with a second channel and person, strong', () => {
    expect(corroborate([incident()], 1).level).toBe('CORROBORATED');
    expect(corroborate([incident(), incident({ reported_by: 'p2', arrived_via: 'SMS' })], 1).level).toBe('STRONG');
  });

  it('no fire, no satellite', () => {
    const c = corroborate([incident()], 0);
    expect(c.channels).toEqual(['APP']);
    expect(c.sources).toBe(1);
  });

  it('says how many detections back it', () => {
    expect(corroborationLine(corroborate([incident()], 3))).toBe(
      '2 independent sources · 2 channels (APP, SATELLITE) · 3 fire detections from space',
    );
  });

  it('withCorroboration links fires to clustered cards', () => {
    const raw = [incident(), incident({ reported_by: 'p2' })];
    const cards = withCorroboration(clusterAlerts(raw, true), raw, [fire(), fire({ id: 'other', confidence: 'high' })]);
    expect(cards[0].corroboration).toMatchObject({ sources: 3, fireDetections: 2, level: 'STRONG' });
  });
});
