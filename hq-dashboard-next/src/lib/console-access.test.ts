import { describe, expect, it } from 'vitest';

import {
  AGENCY_CODES,
  agencyOf,
  canOpen,
  consoleAccess,
} from './console-access';

describe('an agency liaison', () => {
  it('is recognised for each of the six agencies', () => {
    for (const code of AGENCY_CODES) {
      expect(agencyOf(`${code}_LIAISON`)).toBe(code);
    }
  });

  it('does not get the statewide command console', () => {
    // What they had. The browser harness signed in as the Police liaison and
    // counted five screens: map, feed, history, broadcast, agency. Four of
    // those are Operation Rainbow's, not theirs.
    const access = consoleAccess('POLICE_LIAISON');
    expect(access.tabs).not.toContain('map');
    expect(access.tabs).not.toContain('history');
    expect(access.tabs).not.toContain('admin');
    expect(access.tabs).not.toContain('audit');
    expect(access.tabs).not.toContain('sim');
  });

  it('is not offered the broadcast button the database will refuse', () => {
    // `system_alerts` INSERT requires is_command(), which a _LIAISON role is
    // not. So this was a control that let an officer compose a statewide
    // advisory and then be told no — after writing it.
    expect(canOpen('ARMY_LIAISON', 'broadcast')).toBe(false);
  });

  it('lands on their own desk', () => {
    expect(consoleAccess('DSS_LIAISON').landing).toBe('agency');
  });

  it('keeps the incidents handed to their agency', () => {
    // The point of giving them an account at all.
    expect(canOpen('NSCDC_LIAISON', 'agency')).toBe(true);
    expect(canOpen('NSCDC_LIAISON', 'alerts')).toBe(true);
  });

  it('is told whose console this is, by name', () => {
    // It said "COMMAND HQ — TACTICAL MONITOR" to an officer of the Nigeria
    // Police Force. Identity confusion in a console that hands out orders
    // between organisations is not cosmetic.
    const access = consoleAccess('POLICE_LIAISON');
    expect(access.title).toBe('Nigeria Police Force');
    expect(access.subtitle).toBe('LIAISON DESK');
    expect(access.administration).toBe(false);
  });

  it('names Operation Enduring Peace, not Amotekun', () => {
    // Amotekun is a South-West outfit — Ondo, Ekiti, Oyo, Ogun, Osun — with no
    // presence in Plateau. OPSH is the joint task force that covers this
    // state.
    // The CODE stays OPSH: it is stored in `escalated_to_agency`, in the role
    // name, and in three agency tables. See agencies.ts.
    expect(consoleAccess('OPSH_LIAISON').title).toBe('Operation Enduring Peace');
  });

  it('is not invented from a role that merely ends in _LIAISON', () => {
    // A role is a database value. A console that derived an agency from any
    // string ending in _LIAISON would give a desk to `CATERING_LIAISON`.
    expect(agencyOf('CATERING_LIAISON')).toBeNull();
    expect(consoleAccess('CATERING_LIAISON').agency).toBeNull();
  });
});

describe('Operation Rainbow command', () => {
  it('HQ keeps everything, including the administration section', () => {
    const access = consoleAccess('HQ_COMMAND');
    for (const tab of ['map', 'alerts', 'history', 'broadcast', 'agency', 'admin', 'audit', 'settings', 'uninstall', 'sim'] as const) {
      expect(access.tabs).toContain(tab);
    }
    expect(access.administration).toBe(true);
  });

  it('a sector commander keeps their operational screens but not administration', () => {
    const access = consoleAccess('LGA_COMMAND', { sector: 'Jos North' });
    expect(access.tabs).toContain('map');
    expect(access.tabs).toContain('broadcast');
    expect(access.administration).toBe(false);
    expect(access.tabs).not.toContain('admin');
    expect(access.title).toBe('LGA Command');
    expect(access.subtitle).toBe('JOS NORTH');
  });

  it('names each sector tier for itself', () => {
    expect(consoleAccess('WARD_COMMAND').title).toBe('Ward Command');
    expect(consoleAccess('UNIT_COMMAND').title).toBe('PU Command');
  });
});

describe('a field responder', () => {
  it('keeps operational awareness', () => {
    const access = consoleAccess('RESPONDER');
    expect(access.tabs).toContain('map');
    expect(access.tabs).toContain('alerts');
    expect(access.tabs).toContain('history');
  });

  it('is not offered the two screens the database refuses them', () => {
    // `system_alerts` INSERT requires is_command(), which a RESPONDER is not,
    // so the broadcast composer could only ever end in a refusal. And the
    // agency rosters are scoped to liaisons and command — the production
    // behaviour test asserts "responders cannot read agency rosters" — so the
    // portal opened empty for them.
    expect(canOpen('RESPONDER', 'broadcast')).toBe(false);
    expect(canOpen('RESPONDER', 'agency')).toBe(false);
  });

  it('is not mistaken for an unresolved role', () => {
    // It fell into the unknown bucket when this function was introduced, which
    // narrowed a responder to two screens and labelled the console "RESOLVING
    // ACCESS". Caught by the browser harness counting screens per role.
    expect(consoleAccess('RESPONDER').subtitle).not.toBe('RESOLVING ACCESS');
    expect(consoleAccess('RESPONDER').title).toBe('Field Unit');
  });
});

describe('a role that has not resolved yet', () => {
  it('gets the smallest console, not the largest', () => {
    // This branch was correct and UNREACHABLE for its whole life, which these
    // assertions could not tell. The comment here used to say "`userRole` is ''
    // while the profile loads"; it was `useState('HQ_OFFICER')` — a command
    // role — so the caller never once handed this function an unknown role and
    // the flash it exists to prevent happened on every page load (T-35). The
    // role is `null` until the `profiles` read lands now, which is what makes
    // the rest of this block something that actually runs.
    const access = consoleAccess('');
    expect(access.tabs).not.toContain('admin');
    expect(access.tabs).not.toContain('broadcast');
    // Not `agency` either. An agency tab clicked before the role resolved
    // mounted the portal with `isHq` true and no agency, which froze an Army
    // liaison on the Police desk for the life of the mount.
    expect(access.tabs).not.toContain('agency');
    expect(access.administration).toBe(false);
    expect(consoleAccess(undefined).tabs).toEqual(access.tabs);
    expect(consoleAccess(null).tabs).toEqual(access.tabs);
  });

  it('says so rather than claiming to be Command HQ', () => {
    expect(consoleAccess('').subtitle).toBe('RESOLVING ACCESS');
  });
});
