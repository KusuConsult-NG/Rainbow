/**
 * What a dispatcher is told about a report that arrived from a keypad.
 *
 * ## The decision this encodes
 *
 * A USSD report is held out of the escalation ladder until a named officer
 * stands behind it (`awaiting_human_confirmation()`, migration 20261011000000),
 * because USSD is the cheapest way to lure responders to a chosen place and no
 * TIMER may make that decision. This module is the other half: what the officer
 * sees when they make it.
 *
 * ## Dispatch is not blocked — it confirms
 *
 * The obvious design is to grey out DISPATCH until somebody clicks CONFIRM. It is
 * the wrong one. In a real armed attack those seconds are the whole point of the
 * system, and a dispatcher who believes the report should not have to click twice
 * to act on it.
 *
 * So dispatching an unconfirmed USSD report CONFIRMS it, in the same action, and
 * records who did so. Nothing is blocked, nothing is slowed, and the thing that
 * was actually wrong is fixed: no incident reaches a responder without a named
 * officer's decision behind it. `dispatchImpliesConfirmation()` is that rule.
 *
 * ## Concerns, not a score
 *
 * `credibilityConcerns()` returns ordered sentences rather than a number. A score
 * invites the reader to stop thinking — and the failure mode of a confidence
 * percentage on an emergency console is an officer who trusts 82% and does not
 * read the four facts behind it. The facts are short, they are specific, and the
 * strongest is first.
 */

/** The shape `ussd_report_credibility()` returns. */
export interface UssdCredibility {
  first_time_caller: boolean;
  caller_report_count: number;
  caller_false_reports: number;
  caller_known_days: number;
  callback_offered: boolean;
  corroborating_reports: number;
  corroborating_numbers: number;
}

/** The fields of an alert this module reads. */
export interface ProvenanceAlert {
  arrived_via?: string | null;
  ussd_confirmed_at?: string | null;
  ussd_confirmed_by?: string | null;
  reporter_msisdn?: string | null;
  caller_may_be_called?: boolean | null;
  public_reference?: string | null;
  /**
   * The nearest landmark as the reporter typed it.
   *
   * The most navigable thing on a keypad report: a USSD alert has no GPS, so the
   * map can only draw a circle the size of the ward. This is what a driver can
   * actually go to. It is text for a person to read and never becomes
   * coordinates — see migration 20261013000000.
   */
  reporter_landmark?: string | null;
}

export function arrivedByKeypad(alert: ProvenanceAlert): boolean {
  return (alert.arrived_via ?? '').toUpperCase() === 'USSD';
}

/**
 * True when this report is on the board but out of the escalation ladder.
 *
 * Mirrors `awaiting_human_confirmation()` exactly. If these two ever disagree the
 * console will show a CONFIRM control on something already in the ladder, or —
 * worse — no control on something that is being held back with nobody told.
 */
export function awaitingConfirmation(alert: ProvenanceAlert): boolean {
  return arrivedByKeypad(alert) && !alert.ussd_confirmed_at;
}

/**
 * Whether acting on this report also constitutes standing behind it.
 *
 * See the note above: dispatch is never blocked, it confirms. The alternative —
 * a disabled button — costs seconds in an armed attack and buys nothing, because
 * the officer was always going to click CONFIRM first.
 */
export function dispatchImpliesConfirmation(alert: ProvenanceAlert): boolean {
  return awaitingConfirmation(alert);
}

/** The short label for the card. */
export function provenanceBadge(alert: ProvenanceAlert): string | null {
  if (!arrivedByKeypad(alert)) return null;
  return awaitingConfirmation(alert) ? 'KEYPAD · UNCONFIRMED' : 'KEYPAD · CONFIRMED';
}

/**
 * The one line that explains why this report is not climbing.
 *
 * Written for somebody who has never read a migration: the reason is that nobody
 * has confirmed it, and the consequence is that no timer will act on it.
 */
export function holdExplanation(alert: ProvenanceAlert): string | null {
  if (!awaitingConfirmation(alert)) return null;
  return 'Reported from a keypad and not yet confirmed, so it will not escalate '
    + 'on its own. Dispatching it confirms it in your name.';
}

/** A concern a dispatcher should read before committing officers. */
export interface Concern {
  /** How much weight to give it. 'high' is drawn in the duress colour. */
  level: 'high' | 'medium' | 'low' | 'good';
  text: string;
}

/**
 * What is known about the number behind this report, strongest first.
 *
 * Ordered by how much it should change a decision, not by how bad it sounds. A
 * prior false report from this very number is the strongest thing on the list and
 * comes first; corroboration from other numbers is the strongest thing in the
 * other direction and is stated just as plainly, because a dispatcher hesitating
 * over four independent reports of a village attack is its own kind of failure.
 */
export function credibilityConcerns(c: UssdCredibility): Concern[] {
  const out: Concern[] = [];

  if (c.caller_false_reports > 0) {
    out.push({
      level: 'high',
      text: c.caller_false_reports === 1
        ? 'This number has filed 1 report an officer marked FALSE.'
        : `This number has filed ${c.caller_false_reports} reports officers marked FALSE.`,
    });
  }

  // Corroboration from OTHER numbers is the single strongest reason to act.
  if (c.corroborating_numbers > 0) {
    out.push({
      level: 'good',
      text: `${c.corroborating_reports} other report${c.corroborating_reports === 1 ? '' : 's'} `
        + `from ${c.corroborating_numbers} other number${c.corroborating_numbers === 1 ? '' : 's'} `
        + 'in this ward, within the hour.',
    });
  } else if (c.corroborating_reports > 0) {
    // Reports exist but all from the same number as this one. Stated as an
    // absence of corroboration, because counting them as support is exactly how
    // one person pressing keys looks like a village.
    out.push({
      level: 'medium',
      text: 'No other number is reporting this. The repeats are from this number.',
    });
  } else {
    out.push({ level: 'medium', text: 'Nobody else is reporting this.' });
  }

  if (c.first_time_caller) {
    out.push({
      level: 'medium',
      text: 'First time this number has ever contacted Plateau Eye.',
    });
  } else {
    out.push({
      level: 'low',
      text: `Known ${c.caller_known_days} day${c.caller_known_days === 1 ? '' : 's'}, `
        + `${c.caller_report_count} previous report${c.caller_report_count === 1 ? '' : 's'}.`,
    });
  }

  out.push(
    c.callback_offered
      ? { level: 'good', text: 'Reporter agreed to be called back.' }
      : { level: 'low', text: 'Reporter declined a callback.' },
  );

  return out;
}

/**
 * Whether anything here should make an officer pause before deploying.
 *
 * Deliberately narrow. It is true for a number with a prior false report and no
 * independent corroboration — the actual ambush shape — and false for a
 * first-time caller who is one of four numbers reporting the same thing, which is
 * what a real village attack looks like.
 *
 * Declining a callback is NOT on this list. A witness to a militia attack has
 * excellent reasons not to want their phone ringing, and treating that as
 * suspicion would punish exactly the people this channel is for.
 */
export function warrantsCaution(c: UssdCredibility): boolean {
  if (c.corroborating_numbers > 0) return false;
  return c.caller_false_reports > 0;
}
