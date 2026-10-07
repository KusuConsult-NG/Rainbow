// The agency vocabulary.
//
// Six codes, one list. These assertions are cheap and they are the ones that
// were missing: every test in this suite was already written in the canonical
// vocabulary, so the console offering a different one was invisible to all of
// them. `scripts/check_one_agency_vocabulary.py` holds the cross-file half —
// the menu, the env template and the configuration report.
import { describe, expect, it } from 'vitest';

import {
  AGENCY_CHROME,
  AGENCY_CODES,
  AGENCY_LIST,
  AGENCY_NAMES,
  AGENCY_TARGET_ALL,
  isAgencyCode,
} from './agencies';
import { agencyOf } from './console-access';

describe('the agency list', () => {
  it('is the six agencies that send liaison officers', () => {
    expect([...AGENCY_CODES]).toEqual(['POLICE', 'ARMY', 'DSS', 'NSCDC', 'FRSC', 'OPSH']);
  });

  it('names and draws every one of them', () => {
    for (const code of AGENCY_CODES) {
      expect(AGENCY_NAMES[code]).toBeTruthy();
      expect(AGENCY_CHROME[code].color).toMatch(/^#[0-9a-f]{6}$/i);
      expect(AGENCY_CHROME[code].icon).toBeTruthy();
    }
  });

  it('builds AGENCY_LIST from the codes, in order and once each', () => {
    expect(AGENCY_LIST.map(a => a.code)).toEqual([...AGENCY_CODES]);
    expect(new Set(AGENCY_LIST.map(a => a.label)).size).toBe(AGENCY_CODES.length);
  });

  // Every code must be reachable as an account, or an incident can be handed to
  // an agency that cannot sign in to collect it.
  it('has a liaison role for every code', () => {
    for (const code of AGENCY_CODES) {
      expect(agencyOf(`${code}_LIAISON`)).toBe(code);
    }
  });
});

describe('what is not an agency', () => {
  // The four the escalation menu used to offer. 'NPF' is the one that mattered:
  // it is the Police, under a name nothing else in the system answers to.
  it.each(['NPF', 'MILITARY', 'RAINBOW', 'VGN', 'AMOTEKUN', 'HQ', 'ALL', '', 'police'])(
    'rejects %s',
    (value) => {
      expect(isAgencyCode(value)).toBe(false);
    },
  );

  it.each([...AGENCY_CODES])('accepts %s', (code) => {
    expect(isAgencyCode(code)).toBe(true);
  });

  it('rejects anything that is not a string', () => {
    for (const value of [null, undefined, 0, {}, ['POLICE']]) {
      expect(isAgencyCode(value)).toBe(false);
    }
  });

  // `ALL` is a broad escalation and deliberately notifies nobody, so it must
  // never be mistaken for an agency with contact details.
  it('does not treat the broad-escalation target as an agency', () => {
    expect(isAgencyCode(AGENCY_TARGET_ALL)).toBe(false);
  });
});
