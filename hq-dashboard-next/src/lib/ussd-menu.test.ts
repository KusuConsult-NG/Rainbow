// The USSD menu, walked the way a frightened person would walk it.
//
// Two classes of assertion here, and the second is the one that catches the
// defects that only appear in the field:
//
//   * the paths — that pressing 1 gets you to help in as few keypresses as
//     possible, that a mis-key does not lose the session, that refusing a
//     callback does not block the report;
//   * the 182-CHARACTER LIMIT, on every reachable screen, including every page
//     of every ward picker for all 17 LGAs. A screen over the limit is
//     truncated by some networks and dropped by others — silently, and
//     differently per carrier — so a menu item added in a refactor can break
//     the emergency path on MTN while it still works on Airtel.
import { describe, expect, it } from 'vitest';

import {
  EMERGENCY_KINDS,
  INCIDENT_KINDS,
  INITIAL_STATE,
  SCREEN_LIMIT,
  type UssdCaller,
  type UssdState,
  dialogueEndScreen,
  filedScreen,
  filingFailedScreen,
  readLandmark,
  lastReportScreen,
  ussdTurn,
} from './ussd-menu';
import { plateauTacticalMap } from './tactical_mapping';

const LGAS = plateauTacticalMap.map(l => l.name);
const wardsFor = (lga: string) =>
  plateauTacticalMap.find(l => l.name === lga)?.wards.map(w => w.name) ?? [];
const PLACES = { lgas: LGAS, wardsFor };

const STRANGER: UssdCaller = { msisdn: '+2348030001111', known: false };
const KNOWN: UssdCaller = {
  msisdn: '+2348030002222',
  known: true,
  geoLga: 'JOS NORTH',
  geoWard: 'ABBA NA SHEHU',
};

/** Walk a sequence of keypresses from a fresh session. */
function walk(inputs: string[], caller: UssdCaller) {
  let state: UssdState = INITIAL_STATE;
  let turn = ussdTurn(state, '', caller, PLACES);
  const screens = [turn.screen];
  for (const input of inputs) {
    turn = ussdTurn(turn.state, input, caller, PLACES);
    state = turn.state;
    screens.push(turn.screen);
  }
  return { turn, screens };
}

describe('the screen limit', () => {
  it('holds for the root menu', () => {
    const { turn } = walk([], STRANGER);
    expect(turn.screen.length).toBeLessThanOrEqual(SCREEN_LIMIT);
    expect(turn.terminal).toBe(false);
  });

  it('holds for both kind menus', () => {
    for (const first of ['1', '2']) {
      const { turn } = walk([first], STRANGER);
      expect(turn.screen.length, turn.screen).toBeLessThanOrEqual(SCREEN_LIMIT);
    }
  });

  it('holds for every page of the LGA picker', () => {
    // ['1','1'] — emergency, then a kind — is what reaches the picker. The
    // first version of this walked ['1'], which stops at the KIND menu; that
    // screen has no '99 More', so the loop exited immediately and the test
    // asserted a single screen while appearing to assert every page.
    let turn = walk(['1', '1'], STRANGER).turn;
    expect(turn.state.step).toBe('PICK_LGA');
    let pages = 0;
    for (;;) {
      expect(turn.screen.length, turn.screen).toBeLessThanOrEqual(SCREEN_LIMIT);
      pages += 1;
      if (!turn.screen.includes('99 More')) break;
      turn = ussdTurn(turn.state, '99', STRANGER, PLACES);
      expect(pages).toBeLessThan(20);
    }
    // 17 LGAs at 6 per page.
    expect(pages).toBe(3);
  });

  it('holds for every page of every ward picker, in all 17 LGAs', () => {
    // The one that matters. The longest ward name in tactical_mapping.dart is
    // 25 characters, so a page size chosen against average names overflows on
    // whichever LGA happens to have long ones — and that LGA's emergency path
    // is the one that breaks.
    let checked = 0;
    for (const lga of plateauTacticalMap) {
      // Find the keypresses that reach this LGA: page, then index on the page.
      const idx = LGAS.indexOf(lga.name);
      const page = Math.floor(idx / 6);
      const onPage = (idx % 6) + 1;
      const inputs = ['1', '1', ...Array<string>(page).fill('99'), String(onPage)];
      let turn = walk(inputs, STRANGER).turn;
      expect(turn.state.lga, `did not reach ${lga.name}`).toBe(lga.name);

      let guard = 0;
      for (;;) {
        expect(turn.screen.length, `${lga.name}: ${turn.screen}`)
          .toBeLessThanOrEqual(SCREEN_LIMIT);
        checked += 1;
        if (!turn.screen.includes('99 More')) break;
        turn = ussdTurn(turn.state, '99', STRANGER, PLACES);
        expect((guard += 1)).toBeLessThan(20);
      }
    }
    // 17 LGAs, every one with at least one page.
    expect(checked).toBeGreaterThanOrEqual(17);
  });

  it('holds for the confirm, callback and terminal screens', () => {
    const confirm = walk(['1', '1'], KNOWN).turn;
    expect(confirm.screen.length, confirm.screen).toBeLessThanOrEqual(SCREEN_LIMIT);
    const cb = ussdTurn(confirm.state, '1', KNOWN, PLACES);
    expect(cb.screen.length, cb.screen).toBeLessThanOrEqual(SCREEN_LIMIT);
    expect(filedScreen('R4K2M9', true).length).toBeLessThanOrEqual(SCREEN_LIMIT);
    expect(filedScreen('R4K2M9', false).length).toBeLessThanOrEqual(SCREEN_LIMIT);
    expect(dialogueEndScreen('R4K2M9', true).length).toBeLessThanOrEqual(SCREEN_LIMIT);
    expect(dialogueEndScreen('R4K2M9', false).length).toBeLessThanOrEqual(SCREEN_LIMIT);
    expect(filingFailedScreen().length).toBeLessThanOrEqual(SCREEN_LIMIT);
    expect(lastReportScreen({
      reference: 'R4K2M9',
      kind: 'Community attack - Armed Invasion',
      status: 'AWAITING DISPATCH',
      ageMinutes: 42,
    }).length).toBeLessThanOrEqual(SCREEN_LIMIT);
  });

  it('holds for every invalid-input screen, which are the longest', () => {
    // A rejection prepends a line to a menu that was already near the limit, so
    // these are exactly where an overflow hides.
    const paths: string[][] = [['9'], ['1', '9'], ['2', '9'], ['1', '7'], ['1', '1', '9']];
    for (const p of paths) {
      const { turn } = walk(p, STRANGER);
      expect(turn.screen.length, `${p.join('*')}: ${turn.screen}`)
        .toBeLessThanOrEqual(SCREEN_LIMIT);
    }
    const known = walk(['1', '1', '9'], KNOWN).turn;
    expect(known.screen.length, known.screen).toBeLessThanOrEqual(SCREEN_LIMIT);
  });
});

describe('the emergency path', () => {
  it('reaches a filed report in three keypresses for a known number', () => {
    // The design rule. Somebody being attacked presses 1, what is happening,
    // and confirm — their posting comes from their profile.
    const { turn } = walk(['1', '1', '1'], KNOWN);
    expect(turn.state.step).toBe('CALLBACK');
    const done = ussdTurn(turn.state, '1', KNOWN, PLACES);
    // The report is FILED on this turn — that is what matters, and it is three
    // keypresses. The session stays open for one more screen asking for a
    // landmark, which costs the caller nothing because they already have their
    // reference and the emergency is already on the board.
    expect(done.terminal).toBe(false);
    expect(done.state.step).toBe('LANDMARK');
    expect(done.action).toMatchObject({
      type: 'file',
      emergency: true,
      kind: EMERGENCY_KINDS[0],
      lga: 'JOS NORTH',
      ward: 'ABBA NA SHEHU',
      callback: true,
    });
  });

  it('grades the emergency branch as an emergency and the other as not', () => {
    const emergency = walk(['1', '2', '1', '1'], KNOWN).turn;
    expect(emergency.action).toMatchObject({ type: 'file', emergency: true });
    const routine = walk(['2', '1', '1', '1'], KNOWN).turn;
    expect(routine.action).toMatchObject({ type: 'file', emergency: false });
  });

  it('lets somebody in danger send with NO location at all', () => {
    // A person being attacked must not be held at a ward list. The database
    // deliberately shows an unlocated incident to every staff account, so this
    // fails open rather than dead-ending.
    const picker = walk(['1', '1'], STRANGER).turn;
    expect(picker.screen).toContain('0 Send now, no place');
    const cb = ussdTurn(picker.state, '0', STRANGER, PLACES);
    const done = ussdTurn(cb.state, '2', STRANGER, PLACES);
    expect(done.action).toMatchObject({ type: 'file', emergency: true });
    expect((done.action as { lga?: string }).lga).toBeUndefined();
  });

  it('does not offer the no-location escape on the routine branch', () => {
    // A report of a bad road with no location is not actionable, and offering
    // the escape there would fill the board with rows nobody can route.
    const picker = walk(['2', '1'], STRANGER).turn;
    expect(picker.screen).not.toContain('0 Send now, no place');
  });

  it('allows an LGA with no ward', () => {
    const lgaPage = walk(['1', '1'], STRANGER).turn;
    const wardPage = ussdTurn(lgaPage.state, '1', STRANGER, PLACES);
    expect(wardPage.state.step).toBe('PICK_WARD');
    const cb = ussdTurn(wardPage.state, '0', STRANGER, PLACES);
    const done = ussdTurn(cb.state, '1', STRANGER, PLACES);
    expect(done.action).toMatchObject({ type: 'file', lga: LGAS[0] });
    expect((done.action as { ward?: string }).ward).toBeUndefined();
  });
});

describe('a known number', () => {
  it('is offered its stored posting instead of the pickers', () => {
    const { turn } = walk(['1', '1'], KNOWN);
    expect(turn.state.step).toBe('CONFIRM_PLACE');
    expect(turn.screen).toContain('JOS NORTH');
  });

  it('can still choose somewhere else', () => {
    const confirm = walk(['1', '1'], KNOWN).turn;
    const picker = ussdTurn(confirm.state, '2', KNOWN, PLACES);
    expect(picker.state.step).toBe('PICK_LGA');
    expect(picker.screen).toContain('Which LGA?');
  });

  it('is sent to the pickers when it has no stored posting', () => {
    const noPosting: UssdCaller = { ...KNOWN, geoLga: null, geoWard: null };
    const { turn } = walk(['1', '1'], noPosting);
    expect(turn.state.step).toBe('PICK_LGA');
  });
});

describe('the callback question', () => {
  it('records consent when given', () => {
    const { turn } = walk(['1', '1', '1', '1'], KNOWN);
    expect(turn.action).toMatchObject({ callback: true });
  });

  it('does NOT block the report when refused', () => {
    // A witness to a militia attack has excellent reasons not to want their
    // phone ringing, and the report matters more than the verification channel.
    const { turn } = walk(['1', '1', '1', '2'], KNOWN);
    expect(turn.action).toMatchObject({ type: 'file', callback: false });
    expect(turn.state.step).toBe('LANDMARK');
  });
});

describe('getting it wrong', () => {
  it('re-shows the menu rather than ending the session', () => {
    const { turn } = walk(['7'], STRANGER);
    expect(turn.terminal).toBe(false);
    expect(turn.screen).toContain('Not a valid choice');
    expect(turn.screen).toContain('1. EMERGENCY');
  });

  it('survives letters, spaces and an empty press mid-session', () => {
    for (const junk of ['abc', '  ', '*', '1a', '-1', '999999']) {
      const { turn } = walk([junk], STRANGER);
      expect(turn.terminal, `${junk} ended the session`).toBe(false);
      expect(turn.screen.length).toBeLessThanOrEqual(SCREEN_LIMIT);
    }
  });

  it('keeps the chosen kind through a mis-key on the next screen', () => {
    // Losing the answer to "what is happening?" because of one fat-fingered
    // press means asking a person under attack the same question twice.
    const picker = walk(['1', '2'], STRANGER).turn;
    const missed = ussdTurn(picker.state, '77', STRANGER, PLACES);
    expect(missed.state.kind).toBe(EMERGENCY_KINDS[1]);
    expect(missed.state.emergency).toBe(true);
  });

  it('0 goes back from the kind menu to the root', () => {
    const { turn } = walk(['1', '0'], STRANGER);
    expect(turn.state.step).toBe('ROOT');
    expect(turn.state.emergency).toBe(false);
  });

  it('0 goes back from the callback question to the kind menu', () => {
    const cb = walk(['1', '1', '1'], KNOWN).turn;
    const back = ussdTurn(cb.state, '0', KNOWN, PLACES);
    expect(back.state.step).toBe('EMERGENCY_KIND');
  });
});

describe('paging', () => {
  it('99 advances and 98 returns, without falling off either end', () => {
    let turn = walk(['1', '1'], STRANGER).turn;
    expect(turn.state.step).toBe('PICK_LGA');
    expect(turn.state.page).toBe(0);
    expect(turn.screen).not.toContain('98 Back');
    turn = ussdTurn(turn.state, '99', STRANGER, PLACES);
    expect(turn.state.page).toBe(1);
    expect(turn.screen).toContain('98 Back');
    turn = ussdTurn(turn.state, '98', STRANGER, PLACES);
    expect(turn.state.page).toBe(0);
    // 98 on the first page is not a valid choice, and must not go negative.
    turn = ussdTurn(turn.state, '98', STRANGER, PLACES);
    expect(turn.state.page).toBe(0);
  });

  it('99 on the last page stays on the last page', () => {
    let turn = walk(['1', '1'], STRANGER).turn;
    let guard = 0;
    while (turn.screen.includes('99 More') && guard++ < 20) {
      turn = ussdTurn(turn.state, '99', STRANGER, PLACES);
    }
    const lastPage = turn.state.page;
    turn = ussdTurn(turn.state, '99', STRANGER, PLACES);
    expect(turn.state.page).toBe(lastPage);
    expect(turn.screen.length).toBeLessThanOrEqual(SCREEN_LIMIT);
  });

  it('selects the right place from a later page', () => {
    // Off-by-one here sends officers to the wrong LGA, which is the worst
    // possible consequence for the cheapest possible bug.
    let turn = walk(['1', '1'], STRANGER).turn;
    expect(turn.state.step).toBe('PICK_LGA');
    turn = ussdTurn(turn.state, '99', STRANGER, PLACES);
    turn = ussdTurn(turn.state, '1', STRANGER, PLACES);
    // Page 1, first entry — the seventh LGA, not the first.
    expect(turn.state.lga).toBe(LGAS[6]);
  });
});

describe('what the caller is told', () => {
  it('gives a reference, because it is the only handle they have', () => {
    expect(filedScreen('R4K2M9', true)).toContain('R4K2M9');
  });

  it('does NOT claim help is on the way', () => {
    // Nobody has decided that. A USSD report enters as unconfirmed
    // intelligence and a named officer promotes it; telling a frightened person
    // units are coming when none is assigned is the same lie as an empty board
    // saying ALL SECTORS CLEAR.
    const s = filedScreen('R4K2M9', true).toLowerCase();
    expect(s).not.toContain('on the way');
    expect(s).not.toContain('help is coming');
    expect(s).not.toContain('dispatched');
    expect(s).not.toContain('en route');
  });

  it('asks for a landmark, and offers a skip', () => {
    // The filed screen now does double duty: it confirms the report and asks the
    // one question that can turn a ward circle into a findable place.
    const s = filedScreen('R4K2M9', false);
    expect(s).toContain('R4K2M9');
    expect(s.toLowerCase()).toContain('landmark');
    expect(s).toContain('0 = skip');
  });

  it('says to keep the phone on and not to reply by SMS when the dialogue ends', () => {
    for (const s of [dialogueEndScreen('R4K2M9', true), dialogueEndScreen('R4K2M9', false)]) {
      expect(s).toContain('Keep this phone on');
      expect(s.toLowerCase()).toContain('do not reply by sms');
      // Still never claims a unit is coming.
      expect(s.toLowerCase()).not.toContain('on the way');
      expect(s.toLowerCase()).not.toContain('dispatched');
    }
  });

  it('gives no reference and no reassurance when filing failed', () => {
    const s = filingFailedScreen();
    expect(s).toContain('NOT SENT');
    expect(s).toContain('112');
    expect(s.toLowerCase()).not.toContain('ref ');
  });

  it('never reveals a unit, a position or an ETA on the status screen', () => {
    // This screen is readable by anyone holding the SIM. Somebody who filed a
    // report to draw officers to a place must not be able to watch them come.
    const s = lastReportScreen({
      reference: 'R4K2M9',
      kind: 'Kidnap - Immediate Abduction',
      status: 'UNIT DISPATCHED',
      ageMinutes: 8,
    }).toLowerCase();
    expect(s).not.toContain('eta');
    expect(s).not.toContain('km');
    expect(s).not.toContain('lat');
    expect(s).not.toMatch(/\d+\.\d{3,}/); // no coordinates
  });

  it('says plainly when a number has no report', () => {
    expect(lastReportScreen(null)).toContain('No report found');
  });

  it('asks the route to look the report up rather than guessing', () => {
    const { turn } = walk(['3'], STRANGER);
    expect(turn.action).toEqual({ type: 'lookup_last' });
    expect(turn.terminal).toBe(true);
  });
});

describe('the landmark, asked after the report is filed', () => {
  function atLandmark() {
    const { turn } = walk(['1', '1', '1', '1'], KNOWN);
    expect(turn.state.step).toBe('LANDMARK');
    return turn.state;
  }

  it('attaches what the caller typed', () => {
    const turn = ussdTurn(atLandmark(), 'behind Bukuru market', KNOWN, PLACES);
    expect(turn.action).toEqual({ type: 'landmark', text: 'behind Bukuru market' });
    expect(turn.terminal).toBe(true);
  });

  it('accepts a real polling-unit name, which is what the map calls a place', () => {
    const turn = ussdTurn(atLandmark(), 'POLICE BARRACKS', KNOWN, PLACES);
    expect(turn.action).toMatchObject({ type: 'landmark', text: 'POLICE BARRACKS' });
  });

  it('skips on 0, and on an empty press', () => {
    for (const input of ['0', '', '   ']) {
      const turn = ussdTurn(atLandmark(), input, KNOWN, PLACES);
      expect(turn.action, input).toEqual({ type: 'none' });
      expect(turn.terminal).toBe(true);
    }
  });

  it('treats a stray keypress as a skip rather than a landmark', () => {
    // "ok", "." and a single digit are not places. A dispatcher handed one would
    // waste the seconds this screen exists to save.
    for (const input of ['x', '7', '.', 'ok']) {
      expect(readLandmark(input).skip, input).toBe(true);
    }
  });

  it('caps a long one, because a dossier field is read by a person', () => {
    const long = 'a'.repeat(400);
    expect(readLandmark(long).text).toHaveLength(120);
  });

  it('ends the session either way', () => {
    expect(ussdTurn(atLandmark(), 'the junction', KNOWN, PLACES).terminal).toBe(true);
    expect(ussdTurn(atLandmark(), '0', KNOWN, PLACES).terminal).toBe(true);
  });
});

describe('my details', () => {
  it('shows the number and area, and says whether it is registered', () => {
    const { turn } = walk(['4'], STRANGER);
    expect(turn.screen).toContain('+2348030001111');
    expect(turn.screen).toContain('Not registered');
    const k = walk(['4'], KNOWN).turn;
    expect(k.screen).toContain('Registered');
    expect(k.screen).toContain('JOS NORTH');
  });
});

describe('the kind lists', () => {
  it('are written in the shape the category column is generated from', () => {
    // alerts.category is generated from `type`, which the app writes as
    // '<category> - <subtype>'. A USSD report that skipped that shape would be
    // uncategorised on the console's own filters.
    for (const k of [...EMERGENCY_KINDS, ...INCIDENT_KINDS]) {
      expect(k, k).toMatch(/^[^-]+ - .+$/);
    }
  });

  it('keep danger and routine reporting apart', () => {
    // "Bad road" one keypress from "armed attack" on a menu operated under
    // stress is a design defect, not a convenience.
    const overlap = EMERGENCY_KINDS.filter(k => INCIDENT_KINDS.includes(k));
    expect(overlap).toEqual([]);
  });
});
