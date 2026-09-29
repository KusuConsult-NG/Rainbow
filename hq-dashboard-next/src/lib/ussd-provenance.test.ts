// What a dispatcher is told about a report that arrived from a keypad.
//
// The database holds an unconfirmed USSD report out of the escalation ladder so
// that no timer can turn a stranger's keypresses into a deployment. This is the
// other half of that control — what the officer sees when they make the decision
// instead — and these tests pin the two judgements that matter: that acting is
// never BLOCKED, and that corroboration is never invented.
import { describe, expect, it } from 'vitest';

import {
  type UssdCredibility,
  arrivedByKeypad,
  awaitingConfirmation,
  credibilityConcerns,
  dispatchImpliesConfirmation,
  holdExplanation,
  provenanceBadge,
  warrantsCaution,
} from './ussd-provenance';

const cred = (over: Partial<UssdCredibility> = {}): UssdCredibility => ({
  first_time_caller: true,
  caller_report_count: 0,
  caller_false_reports: 0,
  caller_known_days: 0,
  callback_offered: true,
  corroborating_reports: 0,
  corroborating_numbers: 0,
  ...over,
});

const KEYPAD_NEW = { arrived_via: 'USSD', ussd_confirmed_at: null };
const KEYPAD_OK = { arrived_via: 'USSD', ussd_confirmed_at: '2026-09-29T10:00:00Z' };
const FROM_APP = { arrived_via: null, ussd_confirmed_at: null };

describe('recognising a keypad report', () => {
  it('reads arrived_via, case-insensitively', () => {
    expect(arrivedByKeypad({ arrived_via: 'USSD' })).toBe(true);
    expect(arrivedByKeypad({ arrived_via: 'ussd' })).toBe(true);
    expect(arrivedByKeypad(FROM_APP)).toBe(false);
    expect(arrivedByKeypad({ arrived_via: 'SMS' })).toBe(false);
    expect(arrivedByKeypad({})).toBe(false);
  });

  it('mirrors awaiting_human_confirmation() exactly', () => {
    // If these two disagree the console shows a CONFIRM control on something
    // already in the ladder, or no control on something being held back with
    // nobody told.
    expect(awaitingConfirmation(KEYPAD_NEW)).toBe(true);
    expect(awaitingConfirmation(KEYPAD_OK)).toBe(false);
    expect(awaitingConfirmation(FROM_APP)).toBe(false);
    expect(awaitingConfirmation({ arrived_via: 'SMS', ussd_confirmed_at: null })).toBe(false);
  });

  it('badges the card only for a keypad report', () => {
    expect(provenanceBadge(KEYPAD_NEW)).toBe('KEYPAD · UNCONFIRMED');
    expect(provenanceBadge(KEYPAD_OK)).toBe('KEYPAD · CONFIRMED');
    expect(provenanceBadge(FROM_APP)).toBeNull();
  });
});

describe('acting on an unconfirmed report', () => {
  it('is never blocked — dispatching confirms it', () => {
    // A disabled DISPATCH costs seconds in an armed attack and buys nothing,
    // because the officer was always going to click CONFIRM first.
    expect(dispatchImpliesConfirmation(KEYPAD_NEW)).toBe(true);
  });

  it('does not re-confirm something already confirmed', () => {
    expect(dispatchImpliesConfirmation(KEYPAD_OK)).toBe(false);
  });

  it('never applies to a report from the app', () => {
    expect(dispatchImpliesConfirmation(FROM_APP)).toBe(false);
  });

  it('explains the hold in words, and says the consequence of acting', () => {
    const s = holdExplanation(KEYPAD_NEW)!;
    expect(s).toContain('not yet confirmed');
    expect(s).toContain('will not escalate');
    // The officer has to know their name goes on it.
    expect(s).toContain('in your name');
  });

  it('says nothing about a hold that is not happening', () => {
    expect(holdExplanation(KEYPAD_OK)).toBeNull();
    expect(holdExplanation(FROM_APP)).toBeNull();
  });
});

describe('what is known about the number', () => {
  it('puts a prior FALSE report first, and marks it high', () => {
    const [first] = credibilityConcerns(cred({ caller_false_reports: 2 }));
    expect(first.level).toBe('high');
    expect(first.text).toContain('2 reports');
    expect(first.text).toContain('FALSE');
  });

  it('reads correctly for exactly one prior false report', () => {
    const [first] = credibilityConcerns(cred({ caller_false_reports: 1 }));
    expect(first.text).toContain('1 report');
    expect(first.text).not.toContain('1 reports');
  });

  it('states corroboration from other numbers as a reason to act', () => {
    // A dispatcher hesitating over four independent reports of a village attack
    // is its own kind of failure.
    const cs = credibilityConcerns(cred({
      corroborating_reports: 4, corroborating_numbers: 4,
    }));
    const good = cs.find(c => c.level === 'good' && c.text.includes('other report'));
    expect(good).toBeDefined();
    expect(good!.text).toContain('4 other reports');
    expect(good!.text).toContain('4 other numbers');
  });

  it('does NOT count repeats from the same number as corroboration', () => {
    // This is how one person pressing keys looks like a village.
    const cs = credibilityConcerns(cred({
      corroborating_reports: 3, corroborating_numbers: 0,
    }));
    expect(cs.some(c => c.level === 'good' && c.text.includes('other number'))).toBe(false);
    const m = cs.find(c => c.text.includes('No other number'));
    expect(m?.level).toBe('medium');
    expect(m?.text).toContain('from this number');
  });

  it('says plainly when nobody else is reporting it', () => {
    const cs = credibilityConcerns(cred());
    expect(cs.some(c => c.text === 'Nobody else is reporting this.')).toBe(true);
  });

  it('flags a first-ever contact, and describes a known one instead', () => {
    expect(credibilityConcerns(cred()).some(c => c.text.includes('First time'))).toBe(true);
    const known = credibilityConcerns(cred({
      first_time_caller: false, caller_known_days: 1, caller_report_count: 1,
    }));
    expect(known.some(c => c.text === 'Known 1 day, 1 previous report.')).toBe(true);
  });

  it('reports the callback answer both ways', () => {
    expect(credibilityConcerns(cred({ callback_offered: true }))
      .some(c => c.level === 'good' && c.text.includes('agreed to be called'))).toBe(true);
    expect(credibilityConcerns(cred({ callback_offered: false }))
      .some(c => c.text.includes('declined a callback'))).toBe(true);
  });

  it('always returns something to read', () => {
    // An empty panel on a report nobody has confirmed reads as "nothing to see".
    expect(credibilityConcerns(cred()).length).toBeGreaterThanOrEqual(3);
  });
});

describe('when to actually pause', () => {
  it('is true for the ambush shape: a lying number and nobody else reporting', () => {
    expect(warrantsCaution(cred({ caller_false_reports: 1 }))).toBe(true);
  });

  it('is false once other numbers corroborate, even for a known liar', () => {
    // Corroboration from independent numbers outweighs a bad history: a village
    // under attack may well include somebody who cried wolf last month.
    expect(warrantsCaution(cred({
      caller_false_reports: 3, corroborating_numbers: 2, corroborating_reports: 2,
    }))).toBe(false);
  });

  it('is false for a first-time caller with corroboration', () => {
    // What a real village attack looks like.
    expect(warrantsCaution(cred({
      first_time_caller: true, corroborating_numbers: 4, corroborating_reports: 5,
    }))).toBe(false);
  });

  it('does NOT treat a declined callback as suspicion', () => {
    // A witness to a militia attack has excellent reasons not to want their
    // phone ringing. Treating that as suspicion punishes exactly the people this
    // channel exists for.
    expect(warrantsCaution(cred({ callback_offered: false }))).toBe(false);
  });

  it('does NOT treat a first-time caller as suspicion on its own', () => {
    // Almost every USSD reporter is a first-time caller. If this were enough to
    // warrant caution, the flag would be on every report and mean nothing.
    expect(warrantsCaution(cred({ first_time_caller: true }))).toBe(false);
  });
});
