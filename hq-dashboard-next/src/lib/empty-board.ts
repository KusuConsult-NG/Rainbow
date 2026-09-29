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
  /**
   * The read SUCCEEDED and returned nothing, and the database does not
   * recognise this session. See the note below — this is the empty board that
   * looks most like good news and is not.
   */
  | 'SESSION_NOT_RECOGNISED'
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
  /**
   * Whether the DATABASE agrees it knows who is asking.
   *
   * ## Why checking `error` is not enough
   *
   * Row-level security is not an error. When a request reaches PostgREST
   * without a usable token — an expired session the client still holds a `user`
   * object for, an anon key belonging to a different project, a token the
   * browser dropped — every policy's `auth.uid()` is NULL, so nothing is
   * admitted and the response is a perfectly successful `200` with `[]`.
   *
   * `error` is null. `data` is an empty array. It is byte-for-byte the response
   * an empty Plateau would give, and the board would say ALL SECTORS CLEAR on
   * the strength of a request that was never authenticated.
   *
   * So when the board comes back empty and somebody IS signed in, the console
   * asks the database to confirm it: select the caller's own `profiles` row,
   * which `profiles_select_self_or_staff` admits on `id = auth.uid()`. A row
   * back means the token arrived and the emptiness is real. No row back, with
   * no error, means the token did not arrive and the emptiness means nothing.
   *
   * null when the question was not asked — the board had rows to draw, or
   * nobody is signed in yet.
   */
  identityConfirmed?: boolean | null;
}

/**
 * A failed read never yields ALL_CLEAR, whatever else is true. It is checked
 * first and unconditionally: a stale `alerts` array from a previous successful
 * poll must not let a refusal borrow the last good answer's confidence.
 *
 * An unrecognised session is checked before the filter explanation for the same
 * reason — "your filters hide everything" invites the operator to clear the
 * filters, see nothing, and conclude the state is quiet.
 */
export function emptyBoardMeaning(
  { feedError, loaded, visible, identityConfirmed }: BoardState,
): EmptyBoardMeaning {
  if (feedError) return 'READ_FAILED';
  if (identityConfirmed === false) return 'SESSION_NOT_RECOGNISED';
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
    case 'SESSION_NOT_RECOGNISED':
      return {
        heading: 'SESSION NOT RECOGNISED',
        detail:
          'The incident feed returned nothing, and the database did not recognise '
          + 'this session — so an empty board proves nothing about Plateau. Sign out '
          + 'and sign in again. If it persists, the console is using credentials for '
          + 'a different project.',
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
