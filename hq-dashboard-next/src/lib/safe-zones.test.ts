import { describe, expect, it, vi } from 'vitest';

vi.mock('./supabase', () => ({ supabase: {} }));

import {
  knownLgas,
  nearestWardIn,
  wardDisagreement,
} from './safe-zones';

/**
 * The three seeded shelters T-94 found, and the four it left alone.
 *
 * These are the real coordinates from `phase1_foundation.sql`, so this test is
 * the browser-side half of `check_a_shelter_is_where_it_says.py`: the same
 * question, asked of a position somebody is entering rather than of one already
 * stored. If the two ever disagree, one of them is wrong about which shelters
 * are in the wrong LGA, and the one that runs at entry time is the one an
 * operator will believe.
 */
describe('wardDisagreement', () => {
  it.each([
    ['JOS SOUTH COMMAND HQ', 9.8965, 8.8583, 'JOS SOUTH', 'Jos North'],
    ['MANGU COMMAND POST', 9.7167, 9.05, 'MANGU', 'Barkin Ladi'],
    ['JOS EAST TACTICAL OUTPOST', 9.95, 8.96, 'JOS EAST', 'Jos North'],
  ])('rejects %s, which is inside a different LGA', (
    _name, lat, lng, lga, actually,
  ) => {
    const problem = wardDisagreement(lat as number, lng as number, lga as string);
    expect(problem?.kind).toBe('outside-lga');
    // Naming where it REALLY is, is the whole value of the warning: it tells an
    // operator they picked the wrong LGA rather than mistyped a digit.
    expect(problem?.message).toContain(actually as string);
    expect(problem?.message).toContain(lga as string);
  });

  it.each([
    ['BUKURU TACTICAL OUTPOST', 9.7952, 8.8521, 'JOS SOUTH'],
    ['JOS NORTH POLICE DIVISION', 9.9281, 8.8921, 'JOS NORTH'],
    ['PLATEAU STATE HQ', 9.9167, 8.8917, 'JOS NORTH'],
    ['BARKIN LADI SAFE POINT', 9.5167, 8.9167, 'BARKIN LADI'],
  ])('accepts %s, which is inside one', (_name, lat, lng, lga) => {
    expect(wardDisagreement(lat as number, lng as number, lga as string)).toBeNull();
  });

  // 0,0 is not merely "outside the state": it is the value a null latitude
  // becomes, and this project has drawn it on a map as a shelter.
  it('names 0,0 as its own kind of wrong', () => {
    expect(wardDisagreement(0, 0, 'JOS NORTH')?.kind).toBe('null-island');
  });

  it('rejects a position outside Plateau State', () => {
    // Abuja, about 250km away.
    expect(wardDisagreement(9.0579, 7.4951, 'JOS NORTH')?.kind)
      .toBe('outside-state');
  });

  it('says so when the LGA is not one the ward data knows', () => {
    const problem = wardDisagreement(9.9281, 8.8921, 'JOS SOUTH WEST');
    expect(problem?.kind).toBe('no-such-lga');
  });

  // No LGA claimed is not a disagreement — there is nothing to disagree with.
  // The database still refuses a position outside the state.
  it('passes a position with no LGA claimed', () => {
    expect(wardDisagreement(9.9281, 8.8921, null)).toBeNull();
    expect(wardDisagreement(9.9281, 8.8921, '  ')).toBeNull();
  });

  it('passes a non-finite coordinate to the form to complain about', () => {
    expect(wardDisagreement(Number.NaN, 8.8921, 'JOS NORTH')).toBeNull();
  });

  /**
   * The regression this module was rewritten for.
   *
   * 9.9543, 8.8971 is 5.83km inside Jos North — not a marginal position — and
   * 2.21km from the nearest Jos North ward centroid, ALI KAZAURE, whose radius
   * is 800m. The old centroid rule therefore called it "1.4km outside JOS
   * NORTH" and said so to whoever was typing it in.
   *
   * It is not one awkward point. Sampling 400 positions inside each of the 17
   * LGA polygons, the centroid rule rejects 57.7% of them — 78% of Jos North.
   * A commander correcting a shelter was warned off correct positions more
   * often than not, on the screen built for exactly that. See T-101.
   */
  it('accepts a correct position that the old centroid rule rejected', () => {
    expect(wardDisagreement(9.9543, 8.8971, 'JOS NORTH')).toBeNull();
  });

  /**
   * Inside the state, inside no polygon.
   *
   * 9.742695, 9.946832 is the surveyed centroid of KANAM/DUGUB — a real ward of
   * a real LGA — and it falls inside no LGA boundary, because the ward list and
   * the ADM2 map come from different datasets. KANKE/NEMEL is the same. So this
   * is not a hypothetical sliver; it is where two of the 207 wards actually sit.
   *
   * It must warn and not block: refusing would make it impossible to enter a
   * shelter in a place the boundary data has a hole over.
   */
  it('warns rather than blocks when a position is in no LGA at all', () => {
    const problem = wardDisagreement(9.742695, 9.946832, 'KANAM');
    expect(problem).not.toBeNull();
    expect(problem?.kind).toBe('outside-lga');
    expect(problem?.message).toMatch(/not inside any LGA boundary/);
  });
});

describe('the surveyed geography it reads', () => {
  it('knows the 17 LGAs of Plateau State', () => {
    const lgas = knownLgas();
    expect(lgas).toHaveLength(17);
    expect(lgas).toContain('JOS SOUTH');
    expect(lgas).toContain("QUA'AN PAN");
  });

  it('pre-fills the nearest ward within the chosen LGA', () => {
    expect(nearestWardIn(9.7952, 8.8521, 'JOS SOUTH')).toBe('GIRING');
    expect(nearestWardIn(9.9281, 8.8921, 'jos north')).toBe('IBRAHIM KATSINA');
  });

  it('returns no ward for an LGA it does not know', () => {
    expect(nearestWardIn(9.9281, 8.8921, 'NOWHERE')).toBeNull();
  });
});
