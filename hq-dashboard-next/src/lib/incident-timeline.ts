/**
 * One incident's history, for the forensic replay.
 *
 * ## The defect this closes
 *
 * `IncidentReplayPanel` built its escalation events by string-matching the
 * `ai_summary` column:
 *
 * ```ts
 * if (line.includes('[ESCALATED TO') || line.includes('[COMMAND ESCALATION]')) {
 *   combined.push({ type: 'ESCALATION', actor: 'Tactical Command',
 *                   timestamp: alert.updated_at || alert.created_at, notes: line });
 * }
 * ```
 *
 * Three things follow from reading prose instead of the record:
 *
 *   * **Every automatic escalation was missing.** `escalate_overdue_alerts()`
 *     appends to `escalation_log` and does not touch `ai_summary`, so an
 *     incident that climbed at 02:00 because nobody answered — the escalations
 *     nobody chose, and the ones a review most wants to see — appeared nowhere
 *     on the timeline. The Audit History screen showed them, because
 *     `audit_trail()` reads the log; the per-incident replay did not.
 *   * **Every timestamp was `updated_at`.** An incident escalated UNIT → WARD →
 *     LGA → HQ produced three events carrying one time, so the chronological
 *     sort could not order them, and chat messages sent between them landed in
 *     the wrong place.
 *   * **The actor was a literal.** `'Tactical Command'` for every escalation,
 *     while the log records who did it. T-32 was this exact fault in
 *     `audit_trail()` — it attributed every human action to SYSTEM — and the
 *     fix there was to read the actor out of the entry. This screen never got
 *     the same treatment.
 *
 * ## Why the prose parse had to GO, not be added to
 *
 * The console and the app both write `escalation_log` **and** append a line to
 * `ai_summary` for the same escalation. Reading both would show every manual
 * escalation twice, which is how a timeline stops being evidence. The log is
 * the record; the summary line is a rendering of it.
 *
 * `[MULTI-UNIT DISPATCH]` stays parsed from `ai_summary`, because a dispatch
 * has no structured log of its own — that is a gap worth closing separately,
 * and inventing a record for it here would be worse than reading the prose.
 */

/** One thing that happened to an incident. */
export interface TimelineEvent {
  id: string;
  type:
    | 'INITIAL_REPORT'
    | 'DISPATCH'
    | 'ESCALATION'
    | 'AGENCY_DELIVERY'
    | 'RESOLUTION'
    | 'COMMUNICATION';
  actor: string;
  role: string;
  timestamp: string;
  notes?: string;
}

/** The alert columns this reads. */
export interface TimelineAlert {
  id?: string;
  type?: string | null;
  description?: string | null;
  status?: string | null;
  reported_by?: string | null;
  resolved_by?: string | null;
  resolved_at?: string | null;
  created_at?: string | null;
  updated_at?: string | null;
  ai_summary?: string | null;
  escalation_log?: unknown;
  device_signed_out_at?: string | null;
  escalated_to_agency?: string | null;
}

/** One row of `agency_notifications`: one channel, one attempt. */
export interface DeliveryRow {
  id?: string | null;
  agency?: string | null;
  method?: string | null;
  status?: string | null;
  detail?: string | null;
  sent_at?: string | null;
  sent_by?: string | null;
}

function text(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  return trimmed === '' ? null : trimmed;
}

/**
 * Who performed an entry.
 *
 * `by` then `by_email` then SYSTEM — the same order, and for the same reason,
 * as `audit_trail()` after T-32: the SQL writers set `by`, both clients set
 * `by_email`, and reading only one of them attributed half the history to the
 * wrong party. SYSTEM is the truth for a timeout, not a placeholder: nobody
 * decided it.
 */
export function entryActor(entry: Record<string, unknown>): string {
  return text(entry.by) ?? text(entry.by_email) ?? 'SYSTEM';
}

/** What an entry did, in a sentence an operator can read. */
export function entryNotes(entry: Record<string, unknown>): string {
  const from = text(entry.from_tier);
  const to = text(entry.to_tier);
  const reason = text(entry.reason);
  const officer = text(entry.to_officer_name);
  const agency = text(entry.to_agency);
  const ward = text(entry.to_ward);
  const lga = text(entry.to_lga);
  const action = text(entry.action);

  const parts: string[] = [];
  if (action) {
    // The oversight router writes an action and no tier move.
    parts.push(action.replace(/_/g, ' '));
  } else if (from && to) {
    parts.push(`${from} → ${to}`);
  } else if (to) {
    parts.push(`to ${to}`);
  }

  // Where it was handed, when it was handed somewhere specific. Named because
  // "LGA → WARD" does not say WHICH ward, and that is the whole content of a
  // hand-down.
  //
  // `to_lga: 'ALL'` is the documented fail-open — an incident with no LGA
  // escalates to everybody — so it is said in words. "LGA ALL" reads as a
  // place called ALL, and Plateau has seventeen LGAs, none of them that
  // (`check_no_invented_places.py` is about the same mistake one layer down).
  const statewide = lga !== null && lga.toUpperCase() === 'ALL';
  const target = [
    agency ? `agency ${agency}` : null,
    ward ? `ward ${ward}` : null,
    lga && !ward ? (statewide ? 'every LGA' : `LGA ${lga}`) : null,
  ].filter(Boolean).join(', ');
  if (target) parts.push(`(${target})`);

  if (reason) parts.push(`— ${reason}`);
  if (officer) parts.push(`· taken by ${officer}`);

  return parts.length > 0 ? parts.join(' ') : 'Escalation recorded';
}

/**
 * The escalations, out of the append-only log.
 *
 * Entries with no `at` are kept and SAID to have no time, rather than dropped
 * or quietly given `updated_at` — the first loses the event, and the second is
 * what made every escalation share one timestamp.
 */
export function escalationEvents(alert: TimelineAlert): TimelineEvent[] {
  const log = alert.escalation_log;
  if (!Array.isArray(log)) return [];

  const events: TimelineEvent[] = [];
  log.forEach((raw, index) => {
    if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) return;
    const entry = raw as Record<string, unknown>;
    const at = text(entry.at);
    const timed = at !== null;
    events.push({
      id: `escalate-${alert.id ?? 'alert'}-${index}`,
      type: 'ESCALATION',
      actor: entryActor(entry),
      role: text(entry.to_tier) ?? 'COMMAND',
      timestamp: at ?? alert.updated_at ?? alert.created_at ?? '',
      notes: timed
        ? entryNotes(entry)
        : `${entryNotes(entry)} · time not recorded, placed by last update`,
    });
  });
  return events;
}

/**
 * Whether an outside agency was actually told, and what came back.
 *
 * `/api/notify-agency` writes one `agency_notifications` row per channel —
 * including the channels it SKIPPED, deliberately: "a row set that omits the
 * channels nobody used cannot answer that question later". Nothing read those
 * rows. The console showed the handover as done — `escalated_to_agency` is set
 * the moment an operator presses it — and whether the Police ever received an
 * SMS lived in a `console.error` on the server.
 *
 * The silence is an event too. A handover with `escalated_to_agency` set and
 * NO delivery row is not an absence of news: it means nothing recorded an
 * attempt, which is the answer a review needs and the one a blank timeline
 * hides.
 */
export function deliveryEvents(
  rows: DeliveryRow[],
  alert: TimelineAlert = {},
): TimelineEvent[] {
  const events: TimelineEvent[] = [];

  rows.forEach((row, index) => {
    const agency = text(row.agency) ?? 'AGENCY';
    const method = text(row.method) ?? 'CHANNEL';
    const status = (text(row.status) ?? 'UNKNOWN').toUpperCase();
    const detail = text(row.detail);
    const by = text(row.sent_by);

    // SENT is the only one of the three that is a delivery. SKIPPED means
    // nothing was sent on that channel, and the wording has to keep saying so
    // on the screen as well as in the route.
    const said = status === 'SKIPPED'
      ? `${method} NOT USED`
      : `${method} ${status}`;

    events.push({
      id: `delivery-${text(row.id) ?? `${index}`}`,
      type: 'AGENCY_DELIVERY',
      actor: agency,
      role: method,
      timestamp: row.sent_at ?? '',
      notes: [
        said,
        detail ? `— ${detail}` : null,
        by ? `· handed over by ${by}` : null,
      ].filter(Boolean).join(' '),
    });
  });

  const agency = text(alert.escalated_to_agency);
  if (agency && rows.length === 0) {
    events.push({
      id: `delivery-none-${alert.id ?? 'alert'}`,
      type: 'AGENCY_DELIVERY',
      actor: agency.toUpperCase(),
      role: 'NO RECORD',
      // Placed where the handover was last touched rather than given a time of
      // its own, and the note says which.
      timestamp: alert.updated_at ?? alert.created_at ?? '',
      notes: `Handed to ${agency.toUpperCase()} and NO delivery attempt is on `
        + 'record — not an SMS, not a webhook, not even a skipped channel. '
        + 'Either nothing was sent or the attempt was never written down.',
    });
  }

  return events;
}

/** Everything the alert row itself says happened. */
export function timelineFromAlert(alert: TimelineAlert): TimelineEvent[] {
  const events: TimelineEvent[] = [];

  events.push({
    id: `create-${alert.id ?? 'alert'}`,
    type: 'INITIAL_REPORT',
    actor: alert.reported_by || 'Citizen',
    role: 'CITIZEN',
    timestamp: alert.created_at || new Date().toISOString(),
    notes: `Alert initiated: ${alert.type || 'EMERGENCY'}. Details: ${alert.description || 'No description'}`,
  });

  // Dispatch has no structured log of its own, so this one line is still read
  // out of the summary. Escalations are NOT: the log is the record, and the
  // summary carries a rendering of the same event.
  if (alert.ai_summary) {
    alert.ai_summary.split('\n').forEach((line, index) => {
      if (!line.includes('[MULTI-UNIT DISPATCH]')) return;
      events.push({
        id: `dispatch-${alert.id ?? 'alert'}-${index}`,
        type: 'DISPATCH',
        actor: 'Command Center',
        role: 'COMMAND',
        timestamp: alert.updated_at || alert.created_at || '',
        notes: line,
      });
    });
  }

  events.push(...escalationEvents(alert));

  // The handset left while this was open. The question a review asks is "when
  // did we lose the app", and a gap in the track cannot answer it.
  if (alert.device_signed_out_at) {
    events.push({
      id: `signout-${alert.id ?? 'alert'}`,
      type: 'ESCALATION',
      actor: 'Reporting handset',
      role: 'DEVICE',
      timestamp: alert.device_signed_out_at,
      notes: 'Signed out while this incident was open. Location tracking '
        + 'continued; the app did not.',
    });
  }

  if (alert.status === 'RESOLVED' || alert.resolved_at) {
    events.push({
      id: `resolve-${alert.id ?? 'alert'}`,
      type: 'RESOLUTION',
      actor: alert.resolved_by || 'UNKNOWN',
      role: 'OFFICER',
      timestamp: alert.resolved_at || alert.updated_at || new Date().toISOString(),
      notes: 'Incident marked as RESOLVED and archived.',
    });
  }

  return events;
}

/**
 * A recorded time, or the words for not having one.
 *
 * `new Date('').toLocaleString()` is the string "Invalid Date", which on a
 * forensic timeline reads as a bug in the console rather than as a gap in the
 * record. An entry whose time was never written says so. Both screens that
 * render an escalation entry — the replay panel and the agency desk — go
 * through this, because an entry with no `at` is a real shape: nothing
 * validates the log's keys, and `audit_trail()` already falls back for it.
 */
export function stampLabel(
  value: string | null | undefined,
  style: 'time' | 'full' = 'time',
): string {
  if (!value) return 'TIME NOT RECORDED';
  const when = new Date(value);
  if (Number.isNaN(when.getTime())) return 'TIME NOT RECORDED';
  return style === 'full' ? when.toLocaleString() : when.toLocaleTimeString();
}

/** The clock on a timeline event, for the panel's own heading. */
export function eventStamp(event: TimelineEvent): string {
  return stampLabel(event.timestamp);
}

/** Oldest first, and events with no time last rather than first. */
export function inOrder(events: TimelineEvent[]): TimelineEvent[] {
  return [...events].sort((a, b) => {
    if (!a.timestamp) return 1;
    if (!b.timestamp) return -1;
    return new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime();
  });
}
