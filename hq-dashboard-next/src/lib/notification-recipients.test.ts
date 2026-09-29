import { describe, expect, it } from 'vitest';

import {
  escalationMessage,
  officerShouldHear,
  recipientsFor,
  rolesForTier,
  type OfficerRow,
  type OutboxRow,
} from './notification-recipients';

function notice(over: Partial<OutboxRow['payload']> = {}): OutboxRow {
  return {
    id: 1,
    alert_id: 'aaaaaaaa-1111-4111-8111-111111111111',
    kind: 'TIER_ESCALATION',
    payload: {
      alert_id: 'aaaaaaaa-1111-4111-8111-111111111111',
      from_tier: 'UNIT',
      to_tier: 'WARD',
      geo_lga: 'JOS NORTH',
      geo_ward: 'NARAGUTA',
      geo_pu: 'PU-01',
      severity: 'CRITICAL',
      reason: 'TIMEOUT',
      ...over,
    },
  };
}

const wardNaraguta: OfficerRow = {
  id: 'w1', role: 'WARD_COMMAND', geo_lga: 'JOS NORTH', geo_ward: 'NARAGUTA',
};
const wardGangare: OfficerRow = {
  id: 'w2', role: 'WARD_COMMAND', geo_lga: 'JOS NORTH', geo_ward: 'GANGARE',
};
const wardMangu: OfficerRow = {
  id: 'w3', role: 'WARD_COMMAND', geo_lga: 'MANGU', geo_ward: 'PANYAM',
};
const wardOfficer: OfficerRow = {
  id: 'w4', role: 'WARD_OFFICER', geo_lga: 'JOS NORTH', geo_ward: 'NARAGUTA',
};
const lgaJos: OfficerRow = {
  id: 'l1', role: 'LGA_COMMAND', geo_lga: 'JOS NORTH',
};
const hq: OfficerRow = { id: 'h1', role: 'HQ_COMMAND' };
const citizen: OfficerRow = {
  id: 'c1', role: 'CITIZEN', geo_lga: 'JOS NORTH', geo_ward: 'NARAGUTA',
};

const everyone = [wardNaraguta, wardGangare, wardMangu, wardOfficer, lgaJos, hq, citizen];

describe('which roles hold a tier', () => {
  it('includes the officer form, not only the commander', () => {
    // An escalation is addressed to a desk, not a person. At two in the
    // morning the commander is not necessarily the one awake.
    expect(rolesForTier('WARD')).toContain('WARD_COMMAND');
    expect(rolesForTier('WARD')).toContain('WARD_OFFICER');
  });

  it('knows nothing about a tier that does not exist', () => {
    expect(rolesForTier('REGIONAL')).toEqual([]);
    expect(rolesForTier(null)).toEqual([]);
  });
});

describe('who hears about an escalation to a ward', () => {
  it('the ward it landed on', () => {
    expect(officerShouldHear(wardNaraguta, notice())).toBe(true);
    expect(officerShouldHear(wardOfficer, notice())).toBe(true);
  });

  it('not a different ward in the same LGA', () => {
    // Too wide and every escalation in Plateau wakes every commander; people
    // then turn off the notifications they do need.
    expect(officerShouldHear(wardGangare, notice())).toBe(false);
  });

  it('not a ward in another LGA', () => {
    expect(officerShouldHear(wardMangu, notice())).toBe(false);
  });

  it('not the tier below or above it', () => {
    // The notice is for the rung that now OWNS the incident.
    expect(officerShouldHear(lgaJos, notice())).toBe(false);
  });

  it('never a citizen', () => {
    expect(officerShouldHear(citizen, notice())).toBe(false);
  });

  it('is exactly two people here, not the state', () => {
    expect(recipientsFor(everyone, notice()).map(o => o.id)).toEqual(['w1', 'w4']);
  });
});

describe('an escalation to HQ', () => {
  it('reaches HQ regardless of posting, because HQ is the whole state', () => {
    const n = notice({ to_tier: 'HQ' });
    expect(officerShouldHear(hq, n)).toBe(true);
    expect(recipientsFor(everyone, n).map(o => o.id)).toEqual(['h1']);
  });
});

describe('an incident with no location', () => {
  it('still reaches the tier, rather than falling between desks', () => {
    // These are the SOS reports that arrived without a GPS fix. Filtering them
    // by a place they do not have would deliver them to nobody, and the row
    // would be marked sent.
    const n = notice({ geo_lga: null, geo_ward: null, geo_pu: null });
    expect(recipientsFor(everyone, n).map(o => o.id)).toEqual(['w1', 'w2', 'w3', 'w4']);
  });
});

describe('a notice for a tier nobody holds', () => {
  it('reaches nobody rather than everybody', () => {
    // Failing open here would page the entire state on a malformed payload.
    expect(recipientsFor(everyone, notice({ to_tier: 'ATLANTIS' }))).toEqual([]);
  });
});

describe('what the notification says', () => {
  it('names the tier it has landed on', () => {
    expect(escalationMessage(notice()).heading).toContain('WARD');
  });

  it('says it was not acknowledged, because nobody decided this', () => {
    // "Escalated" on its own reads as somebody having made a call. A timeout
    // is the absence of one, and the person picking it up should know which.
    expect(escalationMessage(notice()).body).toContain('not acknowledged');
  });

  it('marks a critical one as critical', () => {
    expect(escalationMessage(notice()).heading).toContain('CRITICAL');
    expect(escalationMessage(notice({ severity: 'MEDIUM' })).heading)
      .not.toContain('CRITICAL');
  });

  it('carries a reference short enough to read on a lock screen', () => {
    expect(escalationMessage(notice()).body).toContain('#aaaaaaaa');
  });
});
