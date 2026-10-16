import { describe, expect, it } from 'vitest';

import {
  escalationMessage,
  officerShouldHear,
  recipientsFor,
  rolesForTier,
  rolesToNotify,
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

describe('a new incident, not an escalation', () => {
  // Nothing queued a notice when an alert was INSERTED. The only paths to a
  // phone were a human pressing DISPATCH and the timeout two minutes later, so
  // a citizen's SOS reached a responder only if that responder had the app open
  // and in the foreground. The system announced that it had given up waiting
  // for you, and not that the emergency had arrived.
  const reported = (over: Partial<OutboxRow['payload']> = {}): OutboxRow => ({
    id: 1,
    alert_id: 'aaaaaaaa-1111-4111-8111-111111111111',
    kind: 'NEW_INCIDENT',
    payload: {
      alert_id: 'aaaaaaaa-1111-4111-8111-111111111111',
      to_tier: 'UNIT',
      geo_lga: 'JOS NORTH',
      geo_ward: 'NARAGUTA',
      geo_pu: 'PU-01',
      severity: 'CRITICAL',
      type: 'SOS',
      reason: 'REPORTED',
      ...over,
    },
  });

  const inPu = (role: string, over: Partial<OfficerRow> = {}): OfficerRow => ({
    id: `o-${role}`,
    role,
    geo_lga: 'JOS NORTH',
    geo_ward: 'NARAGUTA',
    geo_pu: 'PU-01',
    onesignal_player_id: 'player-123456',
    ...over,
  });

  it('reaches the field responders, who are the ones who go', () => {
    // They hold no tier, so `rolesForTier` does not name them, and a new
    // emergency that only reaches the unit commander is waiting on one person
    // to be awake.
    const roles = rolesToNotify(reported());
    expect(roles).toContain('RESPONDER');
    expect(roles).toContain('AGENT');
    expect(officerShouldHear(inPu('RESPONDER'), reported())).toBe(true);
  });

  it('and the unit desk as well', () => {
    expect(officerShouldHear(inPu('UNIT_COMMAND'), reported())).toBe(true);
    expect(officerShouldHear(inPu('POLLING_UNIT_OFFICER'), reported())).toBe(true);
  });

  it('not a responder in another polling unit', () => {
    expect(officerShouldHear(inPu('RESPONDER', { geo_pu: 'PU-09' }), reported()))
      .toBe(false);
  });

  it('nor one in another LGA', () => {
    expect(
      officerShouldHear(
        inPu('RESPONDER', { geo_lga: 'MANGU', geo_ward: 'PANYAM', geo_pu: 'PU-11' }),
        reported(),
      ),
    ).toBe(false);
  });

  it('an unlocated report reaches the whole tier rather than nobody', () => {
    // Those are the SOS reports that arrived without a GPS fix, and they are
    // exactly the ones that must not fall silently between desks.
    const nowhere = reported({ geo_lga: null, geo_ward: null, geo_pu: null });
    expect(officerShouldHear(inPu('RESPONDER', { geo_pu: 'PU-99' }), nowhere)).toBe(true);
  });

  it('does NOT widen a timeout escalation to every responder', () => {
    // An escalation is a message to a desk. Copying every responder in the LGA
    // on it is how people turn off the notifications they do need.
    const escalated: OutboxRow = {
      ...reported(),
      kind: 'TIER_ESCALATION',
      payload: { ...reported().payload, from_tier: 'UNIT', to_tier: 'WARD' },
    };
    expect(rolesToNotify(escalated)).not.toContain('RESPONDER');
  });

  it('does not widen a new incident that landed above the unit', () => {
    // A complaint against security personnel is routed to HQ by the database
    // before this notice is queued. It must not be copied to field responders.
    const atHq = reported({ to_tier: 'HQ' });
    expect(rolesToNotify(atHq)).not.toContain('RESPONDER');
    expect(officerShouldHear(inPu('RESPONDER'), atHq)).toBe(false);
  });

  it('says it was reported, not that somebody sat on it', () => {
    // "was not acknowledged in time and has come up to" is true of a timeout
    // and false of an emergency just filed — it tells an officer that somebody
    // already had it and did nothing, which nobody did.
    const { heading, body } = escalationMessage(reported());
    expect(body).toMatch(/just been reported/i);
    expect(body).not.toMatch(/not acknowledged/i);
    expect(heading).toMatch(/SOS REPORTED/);
    expect(heading).toMatch(/CRITICAL/);
  });

  it('still says "came up to" for an actual escalation', () => {
    const escalated: OutboxRow = {
      ...reported(),
      kind: 'TIER_ESCALATION',
      payload: { ...reported().payload, from_tier: 'UNIT', to_tier: 'WARD' },
    };
    expect(escalationMessage(escalated).body).toMatch(/not acknowledged in time/i);
  });
});
