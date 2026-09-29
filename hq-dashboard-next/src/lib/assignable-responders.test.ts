import { describe, expect, it } from 'vitest';

import {
  assignableResponders,
  commandsWholeState,
  emptyRosterReason,
  isUnderCommand,
  type Posting,
} from './assignable-responders';

const hq: Posting & { id: string } = { id: 'hq', role: 'HQ_COMMAND' };

const lgaJos: Posting & { id: string } = {
  id: 'lga-jos', role: 'LGA_COMMAND', geo_lga: 'JOS NORTH',
};

const wardNaraguta: Posting & { id: string } = {
  id: 'ward-nar', role: 'WARD_COMMAND', geo_lga: 'JOS NORTH', geo_ward: 'NARAGUTA',
};

const officerNaraguta = {
  id: 'o1', role: 'RESPONDER', geo_lga: 'JOS NORTH', geo_ward: 'NARAGUTA', geo_pu: 'PU-01',
};
const officerGangare = {
  id: 'o2', role: 'RESPONDER', geo_lga: 'JOS NORTH', geo_ward: 'GANGARE', geo_pu: 'PU-09',
};
const officerMangu = {
  id: 'o3', role: 'RESPONDER', geo_lga: 'MANGU', geo_ward: 'PANYAM', geo_pu: 'PU-11',
};
const citizen = {
  id: 'c1', role: 'CITIZEN', geo_lga: 'JOS NORTH', geo_ward: 'NARAGUTA',
};

const everyone = [officerNaraguta, officerGangare, officerMangu, citizen];

describe('who commands the whole state', () => {
  it('is HQ and administrators, and nobody else', () => {
    expect(commandsWholeState('HQ_COMMAND')).toBe(true);
    expect(commandsWholeState('HQ_OFFICER')).toBe(true);
    expect(commandsWholeState('ADMIN')).toBe(true);
    // LGA_COMMAND is inside is_command() for broadcasting. It is not inside
    // this — that conflation is what the database migration separated.
    expect(commandsWholeState('LGA_COMMAND')).toBe(false);
    expect(commandsWholeState('WARD_COMMAND')).toBe(false);
    expect(commandsWholeState(null)).toBe(false);
  });
});

describe('a ward commander', () => {
  it('may send officers in their own ward', () => {
    expect(isUnderCommand(officerNaraguta, wardNaraguta)).toBe(true);
  });

  it('may not send an officer in another ward of their own LGA', () => {
    expect(isUnderCommand(officerGangare, wardNaraguta)).toBe(false);
  });

  it('may not send an officer in another LGA', () => {
    // What the picker allowed: every profile with a role, statewide. The
    // officer would get a push for an incident their own commander knows
    // nothing about.
    expect(isUnderCommand(officerMangu, wardNaraguta)).toBe(false);
  });

  it('is offered exactly their ward', () => {
    expect(assignableResponders(everyone, wardNaraguta).map(o => o.id))
      .toEqual(['o1']);
  });
});

describe('an LGA commander', () => {
  it('may send anyone in their LGA, across wards', () => {
    expect(assignableResponders(everyone, lgaJos).map(o => o.id))
      .toEqual(['o1', 'o2']);
  });

  it('stops at the LGA boundary', () => {
    expect(isUnderCommand(officerMangu, lgaJos)).toBe(false);
  });
});

describe('HQ', () => {
  it('may send anyone, anywhere', () => {
    expect(assignableResponders(everyone, hq).map(o => o.id))
      .toEqual(['o1', 'o2', 'o3']);
  });
});

describe('a polling-unit officer', () => {
  it('commands nobody, because they are the field unit', () => {
    // canDispatchFrom already refuses them the control. This makes the list
    // agree with that rather than offering names behind a button they do not
    // have.
    const unit: Posting = {
      role: 'UNIT_COMMAND', geo_lga: 'JOS NORTH', geo_ward: 'NARAGUTA', geo_pu: 'PU-01',
    };
    expect(assignableResponders(everyone, unit)).toEqual([]);
  });
});

describe('an account with no posting', () => {
  it('commands nobody rather than everybody', () => {
    // geo_lga is self-writable — only role is guarded by the escalation
    // trigger — so an empty posting must be the weakest, never a way to reach
    // the state. Same reasoning as the database policy.
    const unposted: Posting = { role: 'WARD_COMMAND' };
    expect(assignableResponders(everyone, unposted)).toEqual([]);
  });
});

describe('who is never offered', () => {
  it('citizens', () => {
    expect(assignableResponders([citizen], hq)).toEqual([]);
  });

  it('a profile with no role at all', () => {
    expect(assignableResponders([{ id: 'x', role: '' }], hq)).toEqual([]);
    expect(assignableResponders([{ id: 'y', role: null }], hq)).toEqual([]);
  });

  it('the dispatcher themselves', () => {
    // Self-dispatch is what ENGAGE is for. Offering it here produced an
    // incident assigned to the person who assigned it.
    const self = { id: 'lga-jos', role: 'LGA_COMMAND', geo_lga: 'JOS NORTH' };
    expect(assignableResponders([self, officerNaraguta], lgaJos).map(o => o.id))
      .toEqual(['o1']);
  });
});

describe('comparing postings', () => {
  it('ignores case and stray spacing, as the database does', () => {
    expect(isUnderCommand(
      { role: 'RESPONDER', geo_lga: ' jos north ', geo_ward: 'naraguta' },
      wardNaraguta,
    )).toBe(true);
  });
});

describe('when the list comes back empty', () => {
  it('says so differently for an unposted account than an empty command', () => {
    // An empty picker with no explanation reads as "the system is broken"
    // during an emergency, and the two causes need different actions.
    expect(emptyRosterReason({ role: 'WARD_COMMAND' }))
      .toMatch(/no posting/i);
    expect(emptyRosterReason(wardNaraguta))
      .toMatch(/NARAGUTA/);
    expect(emptyRosterReason(lgaJos))
      .toMatch(/JOS NORTH/);
  });

  it('tells HQ the plain truth instead', () => {
    expect(emptyRosterReason(hq)).toMatch(/no officers are registered/i);
  });
});
