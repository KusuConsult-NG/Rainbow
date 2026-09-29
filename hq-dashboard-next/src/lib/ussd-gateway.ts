/**
 * Translating what a USSD aggregator sends into what the menu needs.
 *
 * ## Why there is an adapter at all
 *
 * Every aggregator invents its own callback shape, and the differences are not
 * cosmetic:
 *
 *   * **Field names.** `sessionId` / `session_id` / `sessionID`, `phoneNumber` /
 *     `msisdn` / `MSISDN` / `from`.
 *   * **Whether input accumulates.** Africa's Talking sends the WHOLE `*`-joined
 *     path so far (`"1*2*4"`); most carrier-direct integrations send only the
 *     latest keypress (`"4"`). Feeding an accumulated string to a reducer that
 *     expects one keypress makes every screen after the first behave as a
 *     mis-key — and it does so only in production, because a unit test naturally
 *     sends one key at a time.
 *   * **The reply format.** Plain text prefixed `CON `/`END `, or JSON with a
 *     continue flag.
 *
 * The shortcode for this system is going through Interswitch or a direct carrier
 * arrangement, whose exact payload has not been seen. So the contract is stated
 * here explicitly and the mapping is one small function: `normalise()` accepts
 * the field names every aggregator I can actually verify uses, and anything
 * unrecognised is REJECTED rather than guessed at. An adapter that silently
 * reads `undefined` as an empty keypress restarts the menu on every screen.
 *
 * ## The accumulated-input problem
 *
 * `latestKeypress()` handles both conventions without being told which one is in
 * use: if the input contains `*` it is a path and only the final segment is the
 * new keypress. That is safe in both directions, because a single keypress never
 * contains `*` — the menu is digits only, and `*` is not a valid choice on any
 * screen.
 */

/** What the menu needs, whatever the aggregator called it. */
export interface UssdRequest {
  sessionId: string;
  msisdn: string;
  /** The latest keypress. Empty string when the session has just opened. */
  input: string;
  /** The shortcode dialled, when the aggregator sends it. Logged, not trusted. */
  serviceCode?: string;
}

export type NormaliseResult =
  | { ok: true; request: UssdRequest }
  | { ok: false; reason: string };

const FIRST = (...vals: unknown[]): string | undefined => {
  for (const v of vals) {
    if (typeof v === 'string' && v.trim() !== '') return v.trim();
    if (typeof v === 'number' && Number.isFinite(v)) return String(v);
  }
  return undefined;
};

/**
 * The latest keypress, whether the aggregator accumulates input or not.
 *
 * `"1*2*4"` → `"4"`, `"4"` → `"4"`, `""` → `""`. A trailing `*` — which some
 * gateways send when the user presses send on an empty screen — yields `""`,
 * which the reducer treats as "show me this screen again" rather than as a
 * choice.
 */
export function latestKeypress(raw: string | undefined): string {
  if (!raw) return '';
  const trimmed = raw.trim();
  if (trimmed === '') return '';
  if (!trimmed.includes('*')) return trimmed;
  const parts = trimmed.split('*');
  return parts[parts.length - 1].trim();
}

/**
 * An MSISDN in a single comparable form.
 *
 * Kept as the carrier sent it for the record, but a Nigerian number arrives as
 * `08030001111`, `2348030001111` or `+2348030001111` depending on the carrier
 * and the aggregator. `ussd_caller()` and `ussd_last_report()` match on the last
 * nine digits for that reason; this only tidies it for storage and display so
 * the same SIM does not appear three ways on a dispatcher's board.
 */
export function canonicalMsisdn(raw: string): string {
  const digits = raw.replace(/\D/g, '');
  if (digits.length < 9) return raw.trim();
  // Nigerian MSISDNs: 080…/081…/070…/090…/091… locally, 234… internationally.
  if (digits.startsWith('234')) return `+${digits}`;
  if (digits.startsWith('0')) return `+234${digits.slice(1)}`;
  if (digits.length === 10) return `+234${digits}`;
  return `+${digits}`;
}

/**
 * Map an aggregator's callback onto {@link UssdRequest}.
 *
 * Accepts the field names used by the aggregators whose contracts are
 * verifiable; anything else is refused with a reason, because guessing a field
 * name produces a menu that restarts on every screen and an operator who cannot
 * tell why.
 */
export function normalise(body: Record<string, unknown>): NormaliseResult {
  const sessionId = FIRST(
    body.sessionId, body.session_id, body.sessionID, body.sessionid,
  );
  if (!sessionId) {
    return { ok: false, reason: 'no session id in the callback' };
  }

  const msisdn = FIRST(
    body.phoneNumber, body.msisdn, body.MSISDN, body.msisdn_number,
    body.from, body.subscriberNumber,
  );
  if (!msisdn) {
    // Without the MSISDN there is no reporter, no callback channel and no way
    // to read the report back. The session cannot usefully continue.
    return { ok: false, reason: 'no msisdn in the callback' };
  }

  // Absent input is a session opening, which is legitimate and common — so
  // this one does NOT reject. `userInput`/`text`/`input`/`message` all appear
  // in the wild; a missing key and an empty string mean the same thing here.
  const rawInput = FIRST(
    body.text, body.userInput, body.input, body.message, body.ussdString,
  );

  return {
    ok: true,
    request: {
      sessionId,
      msisdn: canonicalMsisdn(msisdn),
      input: latestKeypress(rawInput),
      serviceCode: FIRST(body.serviceCode, body.service_code, body.shortCode),
    },
  };
}

/** How the aggregator wants the reply. */
export type ReplyFormat = 'AT_TEXT' | 'JSON';

/**
 * Render a reply in the aggregator's expected form.
 *
 * `AT_TEXT` is the Africa's Talking convention and the one several
 * carrier-direct integrations copied: plain text, `CON ` to keep the session
 * open and `END ` to close it. `JSON` is for aggregators that expect an object;
 * the field names here are the common ones and are the single place to change
 * when the live contract is confirmed.
 */
export function renderReply(
  screen: string,
  terminal: boolean,
  format: ReplyFormat,
): { body: string; contentType: string } {
  if (format === 'JSON') {
    return {
      body: JSON.stringify({
        sessionState: terminal ? 'END' : 'CONTINUE',
        message: screen,
      }),
      contentType: 'application/json',
    };
  }
  return {
    body: `${terminal ? 'END' : 'CON'} ${screen}`,
    contentType: 'text/plain; charset=utf-8',
  };
}
