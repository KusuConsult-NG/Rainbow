/**
 * The USSD menu, as a pure function.
 *
 * ## Why USSD exists here at all
 *
 * A citizen with no data, no smartphone, or no credit still has USSD: it rides
 * the signalling channel, works on a ₦3,000 handset, and costs the user nothing
 * on most Nigerian networks. In Plateau State that is not an edge case — it is
 * the majority of the people this system is supposed to protect. It also works
 * when a call cannot be made, which is the case this was asked for: the network
 * is congested, or the person cannot be heard speaking.
 *
 * ## Why a pure reducer and not a handler
 *
 * USSD has constraints that are unusual, unforgiving, and invisible until
 * something breaks in the field:
 *
 *   * **182 characters per screen.** A GSM USSD response longer than that is
 *     truncated or dropped by the network — silently, and differently on each
 *     carrier. A screen that grew by one menu item during a refactor is an
 *     emergency path that fails on MTN and works on Airtel. `SCREEN_LIMIT`
 *     below is asserted for EVERY reachable screen in the tests, including
 *     every page of every paginated picker.
 *   * **The session dies in seconds.** Gateways commonly allow 10–20s per
 *     screen and kill the whole session after 60–180s. There is no room for a
 *     round trip that might be slow, so the reducer does no I/O: it decides,
 *     and hands the caller an action to perform.
 *   * **Retries are indistinguishable from input.** Aggregators re-POST on
 *     timeout with the same session and the same text. A reducer that is a pure
 *     function of (state, input) makes that harmless to reason about, and the
 *     route dedupes on the session row.
 *
 * Keeping it pure also means the entire menu — every path a frightened person
 * might take at 2am — is testable without a gateway, a phone or a network.
 *
 * ## The one design rule that matters
 *
 * The emergency path is FIRST and SHORTEST. A person being attacked presses 1,
 * then what is happening, then confirms where — and for a number already known
 * to the system, where is pre-filled from their profile, so it is three
 * keypresses after dialling. Everything else on this menu is secondary to not
 * making that person navigate.
 *
 * And they can always send with no location at all. Somebody in danger must not
 * be held at a ward list: the database deliberately treats an unlocated
 * incident as visible to every staff account (see
 * 20261006000000_alerts_scoped_to_posting.sql), precisely so this can fail open.
 */

/**
 * The hard limit on one USSD screen, in characters.
 *
 * 182 is the GSM 03.38 7-bit payload of a single USSD message. Longer replies
 * are truncated by some networks and dropped by others, so this is treated as a
 * correctness bound, not a style guideline.
 */
export const SCREEN_LIMIT = 182;

/** Where the caller is in the menu. */
export type UssdStep =
  | 'ROOT'
  | 'EMERGENCY_KIND'
  | 'INCIDENT_KIND'
  | 'CONFIRM_PLACE'
  | 'PICK_LGA'
  | 'PICK_WARD'
  | 'CALLBACK'
  | 'LAST_REPORT'
  | 'MY_DETAILS'
  | 'DONE';

/** What the caller knows about the number that dialled in. */
export interface UssdCaller {
  /** E.164 MSISDN, as the carrier asserted it. */
  msisdn: string;
  /** True when this number already has a profile. */
  known: boolean;
  /** Their stored posting, if any — used to skip the location screens. */
  geoLga?: string | null;
  geoWard?: string | null;
}

export interface UssdState {
  step: UssdStep;
  /** True on the emergency branch: the report is graded CRITICAL. */
  emergency: boolean;
  /** The `type` string written to the alert, e.g. 'Armed attack'. */
  kind?: string;
  lga?: string;
  ward?: string;
  /** Which page of a paginated picker is showing, zero-based. */
  page: number;
  /** Whether the reporter consented to being rung back. */
  callback?: boolean;
}

export const INITIAL_STATE: UssdState = { step: 'ROOT', emergency: false, page: 0 };

/** What the route must DO after rendering this screen. The reducer does no I/O. */
export type UssdAction =
  | { type: 'none' }
  /** File the report. The route writes the alert and substitutes the reference. */
  | {
      type: 'file';
      kind: string;
      emergency: boolean;
      lga?: string;
      ward?: string;
      callback: boolean;
    }
  /** Read back the caller's most recent report for the LAST_REPORT screen. */
  | { type: 'lookup_last' };

export interface UssdTurn {
  /** The text to send back, already under SCREEN_LIMIT. */
  screen: string;
  /** True when the session ends here (`END`), false when it continues (`CON`). */
  terminal: boolean;
  state: UssdState;
  action: UssdAction;
}

/**
 * What can be reported.
 *
 * Two lists, because the emergency branch is about DANGER NOW and the incident
 * branch is about things that need a response but not a rescue. Mixing them
 * would put "bad road" one keypress from "armed attack" on a menu operated by
 * someone under stress.
 *
 * The strings become `alerts.type`, whose '<category> - <subtype>' shape the
 * generated `category` column is derived from — so they are written in the same
 * form the app writes.
 */
export const EMERGENCY_KINDS: readonly string[] = [
  'Community attack - Armed Invasion',
  'Kidnap - Immediate Abduction',
  'Fire - Building Fire',
  'Medical - Urgent Casualty',
  'Other danger - Immediate Threat',
];

export const INCIDENT_KINDS: readonly string[] = [
  'Suspicious activity - Sighting',
  'Communal tension - Rising Dispute',
  'Missing person - Unaccounted',
  'Theft - Property Crime',
  'Infrastructure - Damage',
];

/** Short labels for the screens; the full strings above are too long for 182. */
const EMERGENCY_LABELS = ['Armed attack', 'Kidnapping', 'Fire', 'Medical', 'Other danger'];
const INCIDENT_LABELS = ['Suspicious activity', 'Communal tension', 'Missing person', 'Theft', 'Damage'];

/**
 * How many place names fit on one screen.
 *
 * Six, not "as many as fit": the longest ward name in
 * lib/core/constants/tactical_mapping.dart is 25 characters, and a page sized
 * for average names overflows on the LGA whose wards happen to be long. Fixed
 * and small is the only version that is safe on every page, and the tests walk
 * every page of every LGA to prove it.
 */
const PAGE_SIZE = 6;

function truncate(s: string, max: number): string {
  return s.length <= max ? s : `${s.slice(0, max - 1)}…`;
}

/**
 * Render one page of a place picker.
 *
 * `99` is next and `0` is back, on every page, because a caller cannot see a
 * scrollbar and must not have to guess. `#` sends with no location — the
 * fail-open escape for somebody who cannot wait.
 */
function pickerScreen(
  title: string,
  names: readonly string[],
  page: number,
  opts: { allowSkip: boolean },
): string {
  const start = page * PAGE_SIZE;
  const slice = names.slice(start, start + PAGE_SIZE);
  const lines = slice.map((n, i) => `${i + 1} ${truncate(n, 22)}`);
  const more = start + PAGE_SIZE < names.length;
  const tail: string[] = [];
  if (more) tail.push('99 More');
  if (page > 0) tail.push('98 Back');
  if (opts.allowSkip) tail.push('0 Send now, no place');
  return [title, ...lines, ...tail].join('\n');
}

function pageOf(names: readonly string[], page: number): readonly string[] {
  return names.slice(page * PAGE_SIZE, page * PAGE_SIZE + PAGE_SIZE);
}

const ROOT_SCREEN = [
  'Operation Rainbow',
  '1. EMERGENCY - send help',
  '2. Report an incident',
  '3. My last report',
  '4. My details',
].join('\n');

function kindScreen(emergency: boolean): string {
  const labels = emergency ? EMERGENCY_LABELS : INCIDENT_LABELS;
  const head = emergency ? 'EMERGENCY. What is happening?' : 'What do you want to report?';
  return [head, ...labels.map((l, i) => `${i + 1} ${l}`), '0 Back'].join('\n');
}

/** The short label for a kind string, for echoing back on the confirm screen. */
function labelFor(kind: string, emergency: boolean): string {
  const list = emergency ? EMERGENCY_KINDS : INCIDENT_KINDS;
  const labels = emergency ? EMERGENCY_LABELS : INCIDENT_LABELS;
  const i = list.indexOf(kind);
  return i === -1 ? kind : labels[i];
}

function confirmPlaceScreen(state: UssdState, caller: UssdCaller): string {
  const where = [caller.geoLga, caller.geoWard].filter(Boolean).join(' / ');
  return [
    `${labelFor(state.kind ?? '', state.emergency)} at:`,
    truncate(where, 40),
    '1 Yes, send help there',
    '2 Somewhere else',
  ].join('\n');
}

/**
 * The callback question.
 *
 * Asked because a reachable number is the one verification channel USSD hands
 * us that the app's anonymous path does not, and because the ANSWER is itself a
 * signal a dispatcher should see before sending officers somewhere on the word
 * of a number nobody has ever heard from.
 *
 * It is a question, not a condition: refusing a callback must never block the
 * report. A witness to a militia attack has excellent reasons not to want their
 * phone ringing.
 */
function callbackScreen(state: UssdState): string {
  return [
    `Send ${labelFor(state.kind ?? '', state.emergency)}?`,
    '1 Send, you may call me',
    '2 Send, do not call me',
    '0 Back',
  ].join('\n');
}

/** Is this a digits-only menu choice? Anything else is a mis-key. */
function choice(input: string): number | null {
  const t = input.trim();
  if (!/^\d{1,3}$/.test(t)) return null;
  return Number(t);
}

const INVALID = 'Not a valid choice.';

/**
 * One turn of the menu.
 *
 * [input] is the single keypress-or-number the caller just sent. Aggregators
 * differ in whether they hand over the latest input or the whole `*`-joined
 * path; the route normalises to the latest, so this reducer never has to know.
 *
 * An empty [input] means the session just opened (the caller dialled the code),
 * so the root menu is shown.
 */
export function ussdTurn(
  state: UssdState,
  input: string,
  caller: UssdCaller,
  places: { lgas: readonly string[]; wardsFor: (lga: string) => readonly string[] },
): UssdTurn {
  const keep = (screen: string, next: Partial<UssdState> = {}): UssdTurn => ({
    screen,
    terminal: false,
    state: { ...state, ...next },
    action: { type: 'none' },
  });

  // Session opening.
  if (input.trim() === '' && state.step === 'ROOT') {
    return keep(ROOT_SCREEN, { step: 'ROOT', page: 0 });
  }

  const n = choice(input);

  switch (state.step) {
    case 'ROOT': {
      if (n === 1) return keep(kindScreen(true), { step: 'EMERGENCY_KIND', emergency: true });
      if (n === 2) return keep(kindScreen(false), { step: 'INCIDENT_KIND', emergency: false });
      if (n === 3) {
        return {
          screen: '', // the route fills this in from the lookup
          terminal: true,
          state: { ...state, step: 'LAST_REPORT' },
          action: { type: 'lookup_last' },
        };
      }
      if (n === 4) {
        // Deliberately thin. This screen exists so a caller can confirm the
        // system has their number and their area; it must never grow into
        // anything that tells a caller where responders are.
        const where = [caller.geoLga, caller.geoWard].filter(Boolean).join(' / ') || 'not set';
        return {
          screen: [
            'Your details',
            truncate(caller.msisdn, 20),
            `Area: ${truncate(where, 30)}`,
            caller.known ? 'Registered' : 'Not registered',
          ].join('\n'),
          terminal: true,
          state: { ...state, step: 'MY_DETAILS' },
          action: { type: 'none' },
        };
      }
      return keep(`${INVALID}\n${ROOT_SCREEN}`);
    }

    case 'EMERGENCY_KIND':
    case 'INCIDENT_KIND': {
      const emergency = state.step === 'EMERGENCY_KIND';
      const kinds = emergency ? EMERGENCY_KINDS : INCIDENT_KINDS;
      if (n === 0) return keep(ROOT_SCREEN, { step: 'ROOT', emergency: false, page: 0 });
      if (n === null || n < 1 || n > kinds.length) {
        return keep(`${INVALID}\n${kindScreen(emergency)}`);
      }
      const kind = kinds[n - 1];
      const next: UssdState = { ...state, kind, page: 0 };
      // A known number's posting skips two screens. This is the difference
      // between three keypresses and six for somebody being attacked.
      if (caller.geoLga) {
        return {
          screen: confirmPlaceScreen(next, caller),
          terminal: false,
          state: { ...next, step: 'CONFIRM_PLACE' },
          action: { type: 'none' },
        };
      }
      return {
        screen: pickerScreen('Which LGA?', places.lgas, 0, { allowSkip: emergency }),
        terminal: false,
        state: { ...next, step: 'PICK_LGA' },
        action: { type: 'none' },
      };
    }

    case 'CONFIRM_PLACE': {
      if (n === 1) {
        const next: UssdState = {
          ...state,
          lga: caller.geoLga ?? undefined,
          ward: caller.geoWard ?? undefined,
          step: 'CALLBACK',
        };
        return { screen: callbackScreen(next), terminal: false, state: next, action: { type: 'none' } };
      }
      if (n === 2) {
        return {
          screen: pickerScreen('Which LGA?', places.lgas, 0, { allowSkip: state.emergency }),
          terminal: false,
          state: { ...state, step: 'PICK_LGA', page: 0 },
          action: { type: 'none' },
        };
      }
      return keep(`${INVALID}\n${confirmPlaceScreen(state, caller)}`);
    }

    case 'PICK_LGA': {
      // Sending with no location at all. The database treats an unlocated
      // incident as visible to every staff account, on purpose, so this is a
      // real route to help and not a dead end.
      if (n === 0 && state.emergency) {
        const next: UssdState = { ...state, lga: undefined, ward: undefined, step: 'CALLBACK' };
        return { screen: callbackScreen(next), terminal: false, state: next, action: { type: 'none' } };
      }
      if (n === 99) {
        const page = state.page + 1;
        if (page * PAGE_SIZE < places.lgas.length) {
          return keep(pickerScreen('Which LGA?', places.lgas, page, { allowSkip: state.emergency }), { page });
        }
        return keep(pickerScreen('Which LGA?', places.lgas, state.page, { allowSkip: state.emergency }));
      }
      if (n === 98 && state.page > 0) {
        const page = state.page - 1;
        return keep(pickerScreen('Which LGA?', places.lgas, page, { allowSkip: state.emergency }), { page });
      }
      const onPage = pageOf(places.lgas, state.page);
      if (n === null || n < 1 || n > onPage.length) {
        return keep(
          `${INVALID}\n${pickerScreen('Which LGA?', places.lgas, state.page, { allowSkip: state.emergency })}`,
        );
      }
      const lga = onPage[n - 1];
      const wards = places.wardsFor(lga);
      if (wards.length === 0) {
        const next: UssdState = { ...state, lga, ward: undefined, step: 'CALLBACK' };
        return { screen: callbackScreen(next), terminal: false, state: next, action: { type: 'none' } };
      }
      return {
        screen: pickerScreen(`${truncate(lga, 20)} - ward?`, wards, 0, { allowSkip: true }),
        terminal: false,
        state: { ...state, lga, step: 'PICK_WARD', page: 0 },
        action: { type: 'none' },
      };
    }

    case 'PICK_WARD': {
      const wards = places.wardsFor(state.lga ?? '');
      const title = `${truncate(state.lga ?? '', 20)} - ward?`;
      // Sending with the LGA but no ward. An LGA is enough to reach the right
      // command; holding the report for a ward nobody can name is not.
      if (n === 0) {
        const next: UssdState = { ...state, ward: undefined, step: 'CALLBACK' };
        return { screen: callbackScreen(next), terminal: false, state: next, action: { type: 'none' } };
      }
      if (n === 99) {
        const page = state.page + 1;
        if (page * PAGE_SIZE < wards.length) {
          return keep(pickerScreen(title, wards, page, { allowSkip: true }), { page });
        }
        return keep(pickerScreen(title, wards, state.page, { allowSkip: true }));
      }
      if (n === 98 && state.page > 0) {
        const page = state.page - 1;
        return keep(pickerScreen(title, wards, page, { allowSkip: true }), { page });
      }
      const onPage = pageOf(wards, state.page);
      if (n === null || n < 1 || n > onPage.length) {
        return keep(`${INVALID}\n${pickerScreen(title, wards, state.page, { allowSkip: true })}`);
      }
      const ward = onPage[n - 1];
      const next: UssdState = { ...state, ward, step: 'CALLBACK' };
      return { screen: callbackScreen(next), terminal: false, state: next, action: { type: 'none' } };
    }

    case 'CALLBACK': {
      if (n === 0) {
        return keep(kindScreen(state.emergency), {
          step: state.emergency ? 'EMERGENCY_KIND' : 'INCIDENT_KIND',
        });
      }
      if (n !== 1 && n !== 2) {
        return keep(`${INVALID}\n${callbackScreen(state)}`);
      }
      const callback = n === 1;
      return {
        // The route substitutes the reference into this; see FILED_TEMPLATE.
        screen: '',
        terminal: true,
        state: { ...state, callback, step: 'DONE' },
        action: {
          type: 'file',
          kind: state.kind ?? 'Other danger - Immediate Threat',
          emergency: state.emergency,
          lga: state.lga,
          ward: state.ward,
          callback,
        },
      };
    }

    default:
      return {
        screen: 'Session ended. Dial again to report.',
        terminal: true,
        state: INITIAL_STATE,
        action: { type: 'none' },
      };
  }
}

/**
 * What a caller is told once the report is recorded.
 *
 * Three things it says and one it refuses to.
 *
 * It gives a REFERENCE, because that is the only handle a person with no
 * smartphone has on their own report. It says to keep the phone on, because the
 * callback is how a dispatcher confirms an emergency before committing officers.
 * It says not to reply by SMS, because this shortcode is not an SMS endpoint and
 * a reply would go nowhere while the sender believed they had added something.
 *
 * It does NOT say that help is on the way. Nobody has decided that yet — a USSD
 * report enters as unconfirmed intelligence and a named officer promotes it —
 * and telling a frightened person that units are coming when no unit has been
 * assigned is the same class of lie as an empty board saying ALL SECTORS CLEAR.
 */
export function filedScreen(reference: string, emergency: boolean): string {
  const head = emergency ? 'SENT TO COMMAND.' : 'REPORT SENT.';
  return [
    head,
    `Ref ${reference}`,
    'Keep this phone on, we may call.',
    'Do not reply by SMS.',
  ].join('\n');
}

/** What a caller is told when the report could not be written. */
export function filingFailedScreen(): string {
  // No reference, and no pretence. A person who is told their report was sent
  // stops trying; a person who is told it failed can dial 112 or try again.
  return [
    'NOT SENT. Something failed.',
    'Please dial again now.',
    'If this is life-threatening, call 112.',
  ].join('\n');
}

/** The status line for "my last report", by design carrying no unit information. */
export function lastReportScreen(
  report: { reference: string; kind: string; status: string; ageMinutes: number } | null,
): string {
  if (!report) {
    return ['No report found from this number.', 'Dial again and choose 1 or 2 to report.'].join('\n');
  }
  const age =
    report.ageMinutes < 60
      ? `${Math.max(1, Math.round(report.ageMinutes))} min ago`
      : `${Math.round(report.ageMinutes / 60)} hr ago`;
  // Status only. Never a responder position, a unit name or an ETA: this screen
  // is readable by anyone holding the SIM, and somebody who filed a report to
  // draw officers to a place must not be able to watch them arrive.
  return [
    `Ref ${report.reference}`,
    truncate(report.kind, 30),
    `Status: ${truncate(report.status, 24)}`,
    `Filed ${age}`,
  ].join('\n');
}
