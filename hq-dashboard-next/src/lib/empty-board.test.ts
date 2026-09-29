// What an empty board is allowed to claim.
//
// The claim "ALL SECTORS CLEAR" is the console's only affirmative statement
// about public safety, and it used to be made in three unrelated situations —
// including one where the database had refused the read outright. These tests
// pin the rule that the mobile app already enforced: a live, complete, empty
// read is the ONLY thing that says all clear.
import { describe, expect, it } from 'vitest';
import { emptyBoardMeaning, emptyBoardWording } from './empty-board';

describe('a live, empty read', () => {
  it('is the only thing that says ALL CLEAR', () => {
    const state = { feedError: null, loaded: 0, visible: 0 };
    expect(emptyBoardMeaning(state)).toBe('ALL_CLEAR');
    expect(emptyBoardWording(state).heading).toBe('ALL SECTORS CLEAR');
  });
});

describe('a read that failed', () => {
  it('never claims all clear', () => {
    expect(emptyBoardMeaning({
      feedError: 'permission denied for table alerts',
      loaded: 0,
      visible: 0,
    })).toBe('READ_FAILED');
  });

  it('still never claims all clear when a previous poll left rows behind', () => {
    // The dangerous case: `alerts` holds a stale board from the last
    // successful read, so `loaded` and `visible` both look healthy. The
    // refusal must not borrow the last good answer's confidence.
    expect(emptyBoardMeaning({
      feedError: 'JWT expired',
      loaded: 12,
      visible: 12,
    })).toBe('READ_FAILED');
  });

  it('tells the operator not to read the screen as quiet', () => {
    const { heading, detail } = emptyBoardWording({
      feedError: 'network error', loaded: 0, visible: 0,
    });
    expect(heading).toBe('FEED UNAVAILABLE');
    expect(detail.toLowerCase()).toContain('do not treat it as quiet');
    expect(heading).not.toContain('CLEAR');
  });

  it('is reported for a row-level security refusal, which is how this was found', () => {
    // Seeded incidents existed in the database and the board said ALL CLEAR,
    // because `error` was never destructured from the PostgREST response.
    expect(emptyBoardMeaning({
      feedError: 'new row violates row-level security policy',
      loaded: 0,
      visible: 0,
    })).toBe('READ_FAILED');
  });
});

describe('incidents loaded but filtered out', () => {
  it('is not an all-clear', () => {
    const state = { feedError: null, loaded: 13, visible: 0 };
    expect(emptyBoardMeaning(state)).toBe('HIDDEN_BY_FILTERS');
    expect(emptyBoardWording(state).heading).not.toContain('CLEAR');
  });

  it('names how many are being withheld, and says the filters are why', () => {
    const { detail } = emptyBoardWording({ feedError: null, loaded: 13, visible: 0 });
    expect(detail).toContain('13 incidents');
    expect(detail.toLowerCase()).toContain('filter');
    expect(detail.toLowerCase()).toContain('not an all-clear');
  });

  it('reads correctly for a single incident', () => {
    const { detail } = emptyBoardWording({ feedError: null, loaded: 1, visible: 0 });
    expect(detail).toContain('1 incident is loaded');
    expect(detail).not.toContain('1 incidents');
  });
});

describe('a board with something on it', () => {
  it('is not empty, and produces no empty-state wording', () => {
    const state = { feedError: null, loaded: 13, visible: 4 };
    expect(emptyBoardMeaning(state)).toBe('NOT_EMPTY');
    expect(emptyBoardWording(state).heading).toBe('');
  });

  it('is still NOT_EMPTY when every loaded incident is visible', () => {
    expect(emptyBoardMeaning({ feedError: null, loaded: 4, visible: 4 })).toBe('NOT_EMPTY');
  });
});

describe('the precedence between the three causes', () => {
  it('puts the read failure ahead of the filter explanation', () => {
    // Otherwise a refusal during a filtered session reads as "your filters
    // hide everything", and the operator clears the filters, sees nothing,
    // and concludes the state is quiet.
    expect(emptyBoardMeaning({
      feedError: 'permission denied', loaded: 13, visible: 0,
    })).toBe('READ_FAILED');
  });

  it('never returns ALL_CLEAR for any state with an error or loaded rows', () => {
    const errors = [null, 'boom'];
    for (const feedError of errors) {
      for (const loaded of [0, 1, 500]) {
        for (const visible of [0, 1]) {
          if (visible > loaded) continue;
          const meaning = emptyBoardMeaning({ feedError, loaded, visible });
          if (meaning === 'ALL_CLEAR') {
            expect(feedError).toBeNull();
            expect(loaded).toBe(0);
            expect(visible).toBe(0);
          }
        }
      }
    }
  });
});
