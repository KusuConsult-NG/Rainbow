// The statewide ward grid. It replaced squares drawn only over Jos, so the
// first thing it must do is see an incident anywhere in the state.
import { describe, expect, it } from 'vitest';

import type { Alert } from '@/app/dashboard/types';
import type { Corroboration } from './corroboration';
import { CRITICAL_AT, ELEVATED_AT, heatOf, wardGrid } from './ward-grid';
import { wardCentroids } from './ward_centroids';

let n = 0;
const card = (lga: string, ward: string, over: Partial<Alert> = {}): Alert =>
  ({
    id: `c${++n}`,
    type: 'Kidnap - Abduction',
    status: 'PENDING',
    severity: 'HIGH',
    geo_lga: lga,
    geo_ward: ward,
    ...over,
  }) as Alert;

const level = (l: Corroboration['level']): Corroboration =>
  ({ level: l, sources: 1, unconfirmedSources: 0, reports: 1, channels: ['APP'] });

describe('wardGrid', () => {
  it('covers the whole state: all 207 wards, not just Jos', () => {
    expect(wardCentroids).toHaveLength(207);
    const far = wardCentroids.find((w) => w.lat < 9.0)!; // well south of Jos
    const grid = wardGrid([card(far.lga, far.ward)]);
    expect(grid.cells).toHaveLength(1);
    expect(grid.cells[0].ward).toBe(far);
    expect(grid.unplaced).toBe(0);
  });

  it('counts open incidents per ward, ignoring resolved and cancelled ones', () => {
    const w = wardCentroids[0];
    const grid = wardGrid([
      card(w.lga, w.ward),
      card(w.lga, w.ward),
      card(w.lga, w.ward, { status: 'RESOLVED' }),
      card(w.lga, w.ward, { status: 'CANCELLED' }),
    ]);
    expect(grid.cells[0].open).toBe(2);
    expect(grid.cells[0].heat).toBe('ELEVATED');
  });

  it('matches ward names regardless of case and spacing', () => {
    const w = wardCentroids[1];
    const grid = wardGrid([card(` ${w.lga.toLowerCase()} `, w.ward.toLowerCase())]);
    expect(grid.cells).toHaveLength(1);
  });

  it('places a ward however its spaces and numerals are written', () => {
    // The ward file says "GINDIRI  II" (two spaces); a USSD menu says
    // "GINDIRI  11"; a person types "Gindiri II".
    const grid = wardGrid([
      card('MANGU', 'GINDIRI  II'),
      card('MANGU', 'GINDIRI  11'),
      card('mangu', 'Gindiri II'),
    ]);
    expect(grid.cells).toHaveLength(1);
    expect(grid.cells[0].open).toBe(3);
    expect(grid.unplaced).toBe(0);
  });

  it('says how many open incidents it could not place, rather than dropping them', () => {
    const grid = wardGrid([
      card('NOWHERE', 'NO WARD'),
      card('', ''),
      card('NOWHERE', 'NO WARD', { status: 'RESOLVED' }),
    ]);
    expect(grid.cells).toHaveLength(0);
    expect(grid.unplaced).toBe(2);
  });

  it('carries the best corroboration in the ward', () => {
    const w = wardCentroids[2];
    const grid = wardGrid([
      card(w.lga, w.ward, { corroboration: level('UNCONFIRMED') }),
      card(w.lga, w.ward, { corroboration: level('STRONG') }),
      card(w.lga, w.ward, { corroboration: level('CORROBORATED') }),
    ]);
    expect(grid.cells[0].strongest).toBe('STRONG');
    expect(grid.cells[0].corroborated).toBe(2);
  });

  it('draws the busiest ward last, on top', () => {
    const [a, b] = wardCentroids;
    const grid = wardGrid([card(a.lga, a.ward), card(b.lga, b.ward), card(b.lga, b.ward), card(b.lga, b.ward)]);
    expect(grid.cells.map((c) => c.open)).toEqual([1, 3]);
  });
});

describe('heatOf', () => {
  it('reads one open incident as moderate, then elevated, then critical', () => {
    expect(heatOf(1)).toBe('MODERATE');
    expect(heatOf(ELEVATED_AT)).toBe('ELEVATED');
    expect(heatOf(CRITICAL_AT)).toBe('CRITICAL');
  });
});
