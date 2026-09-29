import { describe, expect, it } from 'vitest';

import { describeStandDown, standDownList, teamChange } from './dispatch-changes';

describe('what changed when a team was reassigned', () => {
  it('names who joined, who left and who stayed', () => {
    expect(teamChange(['a', 'b'], ['b', 'c'])).toEqual({
      added: ['c'],
      removed: ['a'],
      unchanged: ['b'],
    });
  });

  it('an officer still on the incident is not notified again', () => {
    // Re-dispatching the same team should not send everyone a fresh "you have
    // been dispatched" — during an incident that is noise at the worst moment.
    expect(teamChange(['a', 'b'], ['a', 'b'])).toEqual({
      added: [],
      removed: [],
      unchanged: ['a', 'b'],
    });
  });

  it('a first dispatch removes nobody', () => {
    expect(teamChange([], ['a', 'b']).removed).toEqual([]);
    expect(teamChange(null, ['a']).removed).toEqual([]);
    expect(teamChange(undefined, ['a']).added).toEqual(['a']);
  });

  it('clearing the team stands everyone down', () => {
    expect(standDownList(['a', 'b'], [])).toEqual(['a', 'b']);
  });

  it('ignores blanks and duplicates on both sides', () => {
    // assigned_responders is a free TEXT[]. An empty string in it must not
    // become an officer counted as removed on every single dispatch.
    expect(teamChange(['a', '', '  ', 'a'], ['a'])).toEqual({
      added: [],
      removed: [],
      unchanged: ['a'],
    });
    expect(standDownList(['a', 'b', 'b'], ['a'])).toEqual(['b']);
  });

  it('is not confused by ordering', () => {
    expect(standDownList(['a', 'b', 'c'], ['c', 'b', 'a'])).toEqual([]);
  });
});

describe('the list of officers to stand down', () => {
  it('is exactly those taken off the incident', () => {
    // The gap: dispatchAlert replaced assigned_responders and notified only
    // the new uids, so an officer removed from an incident was never told —
    // it just disappeared from their list while they were driving to it.
    expect(standDownList(['a', 'b', 'c'], ['a'])).toEqual(['b', 'c']);
  });

  it('is empty when the team only grew', () => {
    expect(standDownList(['a'], ['a', 'b'])).toEqual([]);
  });
});

describe('what the incident records about it', () => {
  it('names a single officer plainly', () => {
    expect(describeStandDown(['Sgt. Bitrus Gyang'], 'hq@rainbow.test'))
      .toBe('[STOOD DOWN] Sgt. Bitrus Gyang removed from this incident by hq@rainbow.test');
  });

  it('counts a group rather than running one long line', () => {
    const line = describeStandDown(['A', 'B', 'C'], 'hq@rainbow.test');
    expect(line).toContain('3 officers');
    expect(line).toContain('A, B, C');
  });

  it('records nothing when nobody was removed', () => {
    // So the caller appends nothing, rather than an empty entry in a log that
    // is read as a chain of custody.
    expect(describeStandDown([], 'hq@rainbow.test')).toBeNull();
    expect(describeStandDown(['  '], 'hq@rainbow.test')).toBeNull();
  });
});
