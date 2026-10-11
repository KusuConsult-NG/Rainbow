// Who a mass advisory is for, on a console.
//
// `SystemAlertListener` docked the newest live advisory and applied no
// targeting at all, so an advisory addressed to citizens of one ward showed up
// under the HQ header and one addressed to the Police showed up on the Army
// liaison's screen. These are the rules it should have had, and they mirror
// `broadcastReaches` in the app so the composer means one thing on both.
import { describe, expect, it } from 'vitest';

import { advisoryAudience, advisoryReaches, type AdvisoryViewer } from './advisory-targeting';

const HQ: AdvisoryViewer = { agency: null, isCommand: true };
const LGA: AdvisoryViewer = { agency: null, isCommand: false, geoLga: 'JOS NORTH', geoWard: 'NARAGUTA' };
const POLICE: AdvisoryViewer = { agency: 'POLICE', isCommand: false };
const ARMY: AdvisoryViewer = { agency: 'ARMY', isCommand: false };

/** A row as MassBroadcast inserts one. */
const advisory = (over: Record<string, unknown> = {}) => ({
  id: 'c1',
  title: 'ADVISORY',
  message: 'Avoid the Naraguta junction.',
  severity: 'CRITICAL',
  target_audience: 'ALL',
  target_agency: 'ALL',
  target_lga: 'ALL',
  target_ward: 'ALL',
  target_pu: 'ALL',
  is_active: true,
  expires_at: null,
  ...over,
});

describe('withdrawn and expired', () => {
  it('a withdrawn advisory reaches nobody, not even command', () => {
    expect(advisoryReaches(advisory({ is_active: false }), HQ)).toBe(false);
  });

  it('an expired advisory reaches nobody', () => {
    expect(advisoryReaches(advisory({ expires_at: '2020-01-01T00:00:00Z' }), HQ)).toBe(false);
  });

  it('a future expiry still stands', () => {
    expect(advisoryReaches(advisory({ expires_at: '2099-01-01T00:00:00Z' }), LGA)).toBe(true);
  });

  // The reason the expiry check is client-side: rows written before the column
  // existed have it NULL, and NULL fails every SQL comparison, so a `.lt()`
  // would have hidden exactly the standing advisories that have no end date.
  it('an advisory with no expiry stands until it is withdrawn', () => {
    expect(advisoryReaches(advisory({ expires_at: null }), LGA)).toBe(true);
  });

  it('an unparseable expiry stands rather than being dropped', () => {
    expect(advisoryReaches(advisory({ expires_at: 'not a date' }), LGA)).toBe(true);
  });
});

describe('the audience', () => {
  it('a CITIZENS advisory reaches no console user', () => {
    expect(advisoryReaches(advisory({ target_audience: 'CITIZENS' }), LGA)).toBe(false);
    expect(advisoryReaches(advisory({ target_audience: 'CITIZENS' }), POLICE)).toBe(false);
  });

  // Command composes them and withdraws them, so they see every one.
  it('command still sees a CITIZENS advisory', () => {
    expect(advisoryReaches(advisory({ target_audience: 'CITIZENS' }), HQ)).toBe(true);
  });

  it.each(['AGENTS', 'RESPONDERS', 'ALL'])('an %s advisory reaches staff', (audience) => {
    expect(advisoryReaches(advisory({ target_audience: audience }), LGA)).toBe(true);
  });

  // An advisory that reaches too many people is recoverable; one lost to a typo
  // in a dropdown is not.
  it('an audience nobody recognises is treated as ALL, not dropped', () => {
    expect(advisoryReaches(advisory({ target_audience: 'EVERYBODY' }), LGA)).toBe(true);
  });

  it('falls back to the legacy target_type when the canonical column is empty', () => {
    expect(advisoryAudience({ target_type: 'citizens' })).toBe('CITIZENS');
    expect(advisoryAudience({ target_audience: '', target_type: 'AGENTS' })).toBe('AGENTS');
    expect(advisoryAudience({})).toBe('ALL');
    // The canonical column wins when both are present.
    expect(advisoryAudience({ target_audience: 'AGENTS', target_type: 'CITIZENS' })).toBe('AGENTS');
  });

  it('honours a legacy CITIZENS row for a console user', () => {
    const legacy = { id: 'c9', target_type: 'CITIZENS', is_active: true };
    expect(advisoryReaches(legacy, LGA)).toBe(false);
  });
});

describe('the agency', () => {
  // The defect that gave `target_agency` its first reader.
  it('an advisory for the Police does not reach the Army liaison', () => {
    expect(advisoryReaches(advisory({ target_agency: 'POLICE' }), ARMY)).toBe(false);
  });

  it('and does reach the Police liaison', () => {
    expect(advisoryReaches(advisory({ target_agency: 'POLICE' }), POLICE)).toBe(true);
  });

  it('is not case-sensitive about the code', () => {
    expect(advisoryReaches(advisory({ target_agency: 'police' }), POLICE)).toBe(true);
  });

  // It was addressed to an outside agency, not to us.
  it('does not reach Operation Rainbow staff below command', () => {
    expect(advisoryReaches(advisory({ target_agency: 'POLICE' }), LGA)).toBe(false);
  });

  it('but command sees it', () => {
    expect(advisoryReaches(advisory({ target_agency: 'POLICE' }), HQ)).toBe(true);
  });

  it('an unscoped agency reaches everybody', () => {
    for (const viewer of [LGA, POLICE, ARMY, HQ]) {
      expect(advisoryReaches(advisory({ target_agency: 'ALL' }), viewer)).toBe(true);
      expect(advisoryReaches(advisory({ target_agency: '' }), viewer)).toBe(true);
    }
  });
});

describe('the place', () => {
  it('an LGA advisory does not reach another LGA', () => {
    const viewer = { ...LGA, geoLga: 'MANGU', geoWard: 'PANYAM' };
    expect(advisoryReaches(advisory({ target_lga: 'JOS NORTH' }), viewer)).toBe(false);
  });

  it('an LGA advisory reaches that LGA', () => {
    expect(advisoryReaches(advisory({ target_lga: 'JOS NORTH' }), LGA)).toBe(true);
  });

  it('a ward advisory does not reach another ward', () => {
    const viewer = { ...LGA, geoWard: 'GINDIRI' };
    expect(advisoryReaches(advisory({ target_ward: 'NARAGUTA' }), viewer)).toBe(false);
  });

  it('matches place names loosely, as the rest of the system does', () => {
    const viewer = { ...LGA, geoLga: 'Jos North LGA' };
    expect(advisoryReaches(advisory({ target_lga: 'JOS NORTH' }), viewer)).toBe(true);
  });

  // Deliberate, and the same rule the app applies: withholding a warning from
  // somebody inside the affected area costs more than showing it to somebody
  // outside it.
  it('a scoped advisory still reaches a viewer whose own place is unknown', () => {
    expect(advisoryReaches(advisory({ target_lga: 'JOS NORTH' }), POLICE)).toBe(true);
  });

  it('a polling-unit advisory is scoped too', () => {
    const viewer = { ...LGA, geoPu: 'PU-02' };
    expect(advisoryReaches(advisory({ target_pu: 'PU-01' }), viewer)).toBe(false);
    expect(advisoryReaches(advisory({ target_pu: 'PU-02' }), viewer)).toBe(true);
  });
});

describe('the whole thing together', () => {
  // The two shapes the browser fixtures seed, checked from the console's side.
  it('a ward-scoped statewide advisory reaches the ward and not the next one', () => {
    const row = advisory({ target_lga: 'JOS NORTH', target_ward: 'NARAGUTA' });
    expect(advisoryReaches(row, LGA)).toBe(true);
    expect(advisoryReaches(row, { ...LGA, geoWard: 'PANYAM' })).toBe(false);
  });

  it('an agency advisory for one ward needs both to match', () => {
    const row = advisory({ target_agency: 'POLICE', target_ward: 'NARAGUTA' });
    expect(advisoryReaches(row, { ...POLICE, geoWard: 'NARAGUTA' })).toBe(true);
    expect(advisoryReaches(row, { ...POLICE, geoWard: 'PANYAM' })).toBe(false);
    expect(advisoryReaches(row, { ...ARMY, geoWard: 'NARAGUTA' })).toBe(false);
  });
});
