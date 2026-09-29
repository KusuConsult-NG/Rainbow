/**
 * Applying the AI's triage to an incident.
 *
 * ## What the button did
 *
 * `APPLY AI CLASSIFICATIONS` had four defects, and every one of them ended with
 * the operator believing something had happened.
 *
 * **1. It applied no classification.** The only thing it wrote was
 * `status: 'DISPATCHED'`. The recommended type and priority were never written
 * anywhere.
 *
 * **2. It marked the incident DISPATCHED with nobody assigned.** No
 * `assigned_to`, no `assigned_responders`. A dispatcher scanning the board for
 * incidents that still need a unit skips anything that says DISPATCHED — so
 * pressing a classification button quietly removed the incident from the list of
 * things needing attention, while no unit had been sent.
 *
 * **3. It could not tell whether it had worked.** The Supabase client returns
 * `{ data, error }`; it does not throw. So the `catch` never fired, and a refused
 * or failed update still produced "Classifications Applied". Same defect as the
 * feed that said ALL SECTORS CLEAR on an unread query.
 *
 * **4. It could not detect its own success.** The button was hidden behind
 * `alert.type === triage.recommended_type`, comparing
 * `'Kidnap - Immediate Abduction'` to `'CRIME'` — values that can never be equal.
 * So the button was always shown, including immediately after being pressed.
 *
 * ## What it does now
 *
 * Applies the SEVERITY, records the recommendation in the audit log, and leaves
 * status alone.
 *
 * `type` is deliberately NOT overwritten. `recommended_type` is a category label
 * — CRIME, DANGER, SUSPICIOUS, ENVIRONMENT — and `alerts.type` holds
 * `'<category> - <subtype>'`, which the generated `category` column is derived
 * from. Writing 'CRIME' into it would destroy the subtype the reporter chose AND
 * break the console's own category filter for that row. The recommendation is
 * recorded rather than imposed.
 *
 * Status is left alone because dispatch is a different decision, made with an
 * actual responder. A classification is not a deployment.
 */

/** The fields of an alert this module reads. */
export interface TriageTarget {
  type?: string | null;
  severity?: string | null;
  /** The console's derived field; `severity` is the column. */
  priority?: string | null;
}

/** What `generateAISummary` produces. */
export interface TriageRecommendation {
  recommended_type?: string | null;
  recommended_priority?: string | null;
  justification?: string | null;
  weapons_detected?: boolean | null;
  crowd_size?: string | null;
}

/** The severities this system grades on, weakest first. */
const SEVERITIES = ['LOW', 'MEDIUM', 'HIGH', 'CRITICAL'] as const;
export type Severity = (typeof SEVERITIES)[number];

function asSeverity(v: unknown): Severity | null {
  const s = String(v ?? '').trim().toUpperCase();
  return (SEVERITIES as readonly string[]).includes(s) ? (s as Severity) : null;
}

/** The severity an alert currently carries, whichever field it arrived in. */
export function currentSeverity(alert: TriageTarget): Severity | null {
  return asSeverity(alert.severity) ?? asSeverity(alert.priority);
}

/**
 * Whether applying the recommendation would change anything.
 *
 * Compares severity to severity. The old test compared `alert.type` — a
 * '<category> - <subtype>' string — to `recommended_type`, a bare category, so it
 * was false for every incident ever graded and the button never went away.
 */
export function alreadyApplied(
  alert: TriageTarget,
  triage: TriageRecommendation,
): boolean {
  const want = asSeverity(triage.recommended_priority);
  if (!want) {
    // Nothing gradeable was recommended, so there is nothing to apply and the
    // control should not be offered.
    return true;
  }
  return currentSeverity(alert) === want;
}

export interface TriageChange {
  /** The columns to write. Empty when there is nothing to do. */
  patch: Record<string, string>;
  /** One line for the audit log, naming what changed and on whose authority. */
  note: string;
  /** Whether this raises the grading, lowers it, or sets one that was missing. */
  direction: 'raised' | 'lowered' | 'set' | 'none';
}

/**
 * What applying this recommendation actually writes.
 *
 * The direction is reported because raising and lowering a grading are different
 * acts. Lowering CRITICAL to MEDIUM on an AI's word is the one that deserves a
 * second look, and an operator should be told which they are about to do rather
 * than reading two severity codes and working it out.
 */
export function triageChanges(
  alert: TriageTarget,
  triage: TriageRecommendation,
  actor: { email?: string | null; id?: string | null },
): TriageChange {
  const want = asSeverity(triage.recommended_priority);
  const have = currentSeverity(alert);

  if (!want || have === want) {
    return { patch: {}, note: '', direction: 'none' };
  }

  const direction: TriageChange['direction'] =
    have === null
      ? 'set'
      : SEVERITIES.indexOf(want) > SEVERITIES.indexOf(have)
        ? 'raised'
        : 'lowered';

  const who = actor.email || actor.id || 'an HQ operator';
  // The recommended TYPE goes in the note, not into the column. See the header:
  // overwriting `type` with a bare category destroys the subtype and breaks the
  // generated category this row is filtered by.
  const recType = String(triage.recommended_type ?? '').trim();
  const note =
    `[AI CLASSIFICATION APPLIED] severity ${have ?? 'not set'} → ${want}, `
    + `applied by ${who}.`
    + (recType ? ` AI also suggested the category ${recType}; the reported type was left as recorded.` : '')
    + ' Status not changed — dispatch is a separate decision.';

  return { patch: { severity: want }, note, direction };
}

/** What to show on the control, so an operator knows which way it goes. */
export function applyButtonLabel(change: TriageChange): string {
  switch (change.direction) {
    case 'raised':
      return 'RAISE SEVERITY TO MATCH AI';
    case 'lowered':
      return 'LOWER SEVERITY TO MATCH AI';
    case 'set':
      return 'SET SEVERITY FROM AI';
    case 'none':
      return 'ALREADY MATCHES';
  }
}
