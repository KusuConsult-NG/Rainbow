/**
 * What an empty incident board is allowed to claim.
 *
 * ## The defect
 *
 * The triage board rendered one thing whenever it had nothing to draw:
 *
 *     ALL SECTORS CLEAR
 *     No active incidents require intervention at this time.
 *
 * That is an affirmative statement about the safety of Plateau State, and the
 * console made it in three completely different situations:
 *
 *   1. The read succeeded and there genuinely are no incidents. Correct.
 *   2. The read FAILED — row-level security refused this account, the socket
 *      dropped, a column does not exist. `error` was never destructured from
 *      the PostgREST response, so a refusal and an empty table were
 *      indistinguishable: `data` came back null, the mapping was skipped, and
 *      `alerts` stayed `[]`.
 *   3. The read succeeded, incidents ARE loaded, and the operator's own filter
 *      selections exclude every one of them. A ward filter left on from ten
 *      minutes ago is enough.
 *
 * In 2 the console knows nothing and says everything is fine. In 3 it is
 * holding live incidents in memory and says there are none. Both are worse
 * than an error, because an error prompts someone to look.
 *
 * The mobile app already had this rule — `mission_feed_liveness_test.dart`
 * asserts that a live, empty feed is the ONLY thing allowed to say ALL CLEAR.
 * The console never did.
 *
 * ## Why a function and not three ternaries in the JSX
 *
 * This is the one piece of console logic whose output is a safety claim, and
 * the previous version was three lines of inline JSX with no test. Pure and
 * named, the rule can be asserted directly — see empty-board.test.ts.
 */

export type EmptyBoardMeaning =
  /** The read failed. Nothing is known; say so loudly. */
  | 'READ_FAILED'
  /** Incidents are loaded; the operator's filters exclude all of them. */
  | 'HIDDEN_BY_FILTERS'
  /** A live, complete read that found nothing. The only honest all-clear. */
  | 'ALL_CLEAR'
  /** There is something to draw — the caller should not be asking. */
  | 'NOT_EMPTY';

export interface BoardState {
  /** The error message from the last read, or null if it succeeded. */
  feedError: string | null;
  /** How many incidents came back from the database. */
  loaded: number;
  /** How many survive the operator's current filter selections. */
  visible: number;
}

/**
 * A failed read never yields ALL_CLEAR, whatever else is true. It is checked
 * first and unconditionally: a stale `alerts` array from a previous successful
 * poll must not let a refusal borrow the last good answer's confidence.
 */
export function emptyBoardMeaning({ feedError, loaded, visible }: BoardState): EmptyBoardMeaning {
  if (feedError) return 'READ_FAILED';
  if (visible > 0) return 'NOT_EMPTY';
  if (loaded > 0) return 'HIDDEN_BY_FILTERS';
  return 'ALL_CLEAR';
}

/**
 * The words on screen for each case.
 *
 * `HIDDEN_BY_FILTERS` names the number being withheld, because that number is
 * the whole point: "12 incidents are loaded and your filters hide all of them"
 * tells an operator what to do, and "no incidents" tells them to relax.
 */
export function emptyBoardWording(state: BoardState): { heading: string; detail: string } {
  switch (emptyBoardMeaning(state)) {
    case 'READ_FAILED':
      return {
        heading: 'FEED UNAVAILABLE',
        detail:
          'The incident feed could not be read, so this screen is not showing the '
          + 'state of Plateau. Do not treat it as quiet.',
      };
    case 'HIDDEN_BY_FILTERS':
      return {
        heading: 'NO MATCH FOR THESE FILTERS',
        detail:
          `${state.loaded} incident${state.loaded === 1 ? '' : 's'} `
          + `${state.loaded === 1 ? 'is' : 'are'} loaded. Your current filter selections `
          + 'hide all of them. This is not an all-clear — clear the filters to see them.',
      };
    case 'ALL_CLEAR':
      return {
        heading: 'ALL SECTORS CLEAR',
        detail: 'No active incidents require intervention at this time.',
      };
    case 'NOT_EMPTY':
      // Callers render cards in this case. Returning wording rather than
      // throwing keeps the function total, but it should never reach a screen.
      return { heading: '', detail: '' };
  }
}
