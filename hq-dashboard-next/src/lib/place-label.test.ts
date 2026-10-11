// What the console may say about where an incident is.
//
// The dossier rendered `LGA / Sector: STATE HQ` for an incident whose
// jurisdiction the app had deliberately left NULL, three lines above a guard
// that drops an absent ward. These are the rules it should have had, and they
// mirror `lib/services/place_label.dart` so one incident reads the same on a
// handset and at HQ.
import { describe, expect, it } from 'vitest';

import {
  incidentPlace,
  knownSegments,
  NOT_RECORDED,
  placeField,
} from './place-label';

describe('a place field on its own', () => {
  it('reads what is recorded', () => {
    expect(placeField('JOS NORTH', 'lga')).toBe('JOS NORTH');
    expect(placeField('  MANGU  ', 'lga')).toBe('MANGU');
  });

  it('says it is not recorded rather than naming a place', () => {
    expect(placeField(null, 'lga')).toBe('LGA NOT RECORDED');
    expect(placeField(undefined, 'ward')).toBe('WARD NOT RECORDED');
    expect(placeField('', 'pu')).toBe('PU NOT RECORDED');
    expect(placeField('   ', 'pu')).toBe('PU NOT RECORDED');
  });

  it('uses N/A where the lines around it do', () => {
    // The AI prompt's Type, Ward and Description lines all say N/A or "No
    // description provided"; the LGA line said STATE HQ.
    expect(placeField(null)).toBe('N/A');
  });

  it('never answers with the name of a real place', () => {
    const invented = ['STATE HQ', 'SECTOR HQ', 'STATEWIDE HQ', 'PLATEAU', 'JOS'];
    for (const kind of ['jurisdiction', 'lga', 'ward', 'pu', 'field'] as const) {
      for (const absent of [null, undefined, '', '  ']) {
        expect(invented).not.toContain(placeField(absent, kind));
      }
    }
  });
});

describe('an incident place', () => {
  it('reads all three when all three are recorded', () => {
    expect(incidentPlace({ geo_lga: 'JOS NORTH', geo_ward: 'NARAGUTA', geo_pu: 'PU 014' }))
      .toBe('JOS NORTH · NARAGUTA · PU 014');
  });

  it('drops the polling unit rather than inventing one', () => {
    // The ordinary case: there is no polling unit from coordinates.
    expect(incidentPlace({ geo_lga: 'JOS NORTH', geo_ward: 'NARAGUTA' }))
      .toBe('JOS NORTH · NARAGUTA');
  });

  it('says the jurisdiction is unresolved when nothing is recorded', () => {
    expect(incidentPlace({})).toBe(NOT_RECORDED.jurisdiction);
    expect(incidentPlace({ geo_lga: null, geo_ward: '', geo_pu: undefined }))
      .toBe(NOT_RECORDED.jurisdiction);
  });

  it('agrees with the app, which is the point of having two copies', () => {
    // `incidentPlace` in lib/services/place_label.dart, same rows. If these
    // drift, one incident reads two ways.
    expect(incidentPlace({ geo_lga: 'BOKKOS' })).toBe('BOKKOS');
    expect(incidentPlace({ geo_ward: 'NARAGUTA', geo_pu: 'PU 014' }))
      .toBe('NARAGUTA · PU 014');
    expect(incidentPlace({})).toBe('JURISDICTION NOT RESOLVED');
  });
});

describe('knownSegments', () => {
  it('joins only what is there', () => {
    expect(knownSegments(['A', null, 'C'], 'NONE')).toBe('A · C');
    expect(knownSegments([null, undefined, ''], 'NONE')).toBe('NONE');
    expect(knownSegments(['A'], 'NONE', ' / ')).toBe('A');
    expect(knownSegments(['A', 'B'], 'NONE', ' / ')).toBe('A / B');
  });

  it('does not treat a zero or a false as absent', () => {
    // A polling unit can be numbered, and `0` is a value somebody recorded.
    expect(knownSegments([0], 'NONE')).toBe('0');
    expect(knownSegments([false], 'NONE')).toBe('false');
  });
});
