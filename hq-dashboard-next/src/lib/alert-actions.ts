import { supabase } from '@/lib/supabase';
import { standDownList } from '@/lib/dispatch-changes';

/**
 * What HQ *does* — the four writes that change an incident.
 *
 * Extracted verbatim from dashboard/page.tsx, where they had no tests. These
 * assign responders, hand incidents to outside agencies and close them out, so
 * a silent failure here is not a cosmetic bug: a dispatch that does not happen
 * looks exactly like a dispatch that did.
 *
 * Toasts stay in the page. These return a result instead, so the outcome can be
 * asserted without rendering a 3,000-line component.
 */

/**
 * One alert, or every member of a clustered card.
 *
 * A cluster stands for several reports of one event. Acting on the card must
 * act on all of them — resolving only the first report used to leave the rest
 * open and invisible, since the board no longer showed them.
 */
import type { UssdCredibility } from './ussd-provenance';

export type AlertIds = string | string[];

export function idsOf(ids: AlertIds): string[] {
  return Array.isArray(ids) ? ids : [ids];
}

/** The signed-in HQ operator. */
export interface Actor {
  id?: string;
  email?: string;
}

export type ActionResult<T = void> =
  | ({ ok: true } & (T extends void ? object : { value: T }))
  | { ok: false; error: string };

function failed(e: unknown, fallback: string): { ok: false; error: string } {
  const message = (e as { message?: string } | null)?.message;
  return { ok: false, error: message || fallback };
}

export interface EscalateOptions {
  targetLga?: string;
  reason?: string;
  targetAgency?: string;
}

/**
 * Whether the outside agency was actually told, and what to say if it was not.
 *
 * Separate from the escalation's own result on purpose. The escalation is
 * committed to `alerts` before the notification is attempted, so a notification
 * failure must not report the escalation as failed — an operator who is told
 * "Escalation Failed" escalates again, and the incident collects duplicate
 * handovers in its chain of custody.
 *
 * But it must not be swallowed either, and it was: the POST was fired and
 * discarded with a `.catch(console.warn)`, so when it answered
 * `400 Unknown agency 'NPF'` — which it did for four of the six destinations
 * the menu offered — nothing on screen or in the record said the agency had
 * not been reached. Two facts, reported separately.
 */
export interface AgencyDelivery {
  delivered: boolean;
  detail: string;
}

/**
 * Hands an incident to an LGA command and optionally an outside agency.
 *
 * Two invariants here were previously fixed bugs, both marked in the original
 * source, and both are now covered by tests:
 *
 *   * The incident is assigned to the TARGET LGA commander's UUID — never the
 *     HQ operator's. Getting that wrong routes an escalation back to the person
 *     escalating it.
 *   * `geo_lga` is never written. The incident's location is where it happened,
 *     not who is now handling it; overwriting it moves the emergency on the map.
 *
 * The escalation log and the notes are APPENDED to, never replaced — this is
 * the chain of custody for an incident.
 */
/**
 * Asks the server to reach an agency, and reports whether it did.
 *
 * A network failure here is "we do not know whether they were told", which is
 * operationally the same as "they were not" — so it reads as undelivered rather
 * than throwing into the escalation's own error path.
 */
async function notifyAgency(payload: {
  alertIds: string[];
  agency: string;
  targetLga: string;
  reason: string;
  sentBy: string;
}): Promise<AgencyDelivery> {
  try {
    const res = await fetch('/api/notify-agency', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      // BOUNDED, because this is now awaited before the operator is told
      // anything. The notification reaches Termii and an agency's own webhook
      // endpoint, neither of which this console controls, and a dispatcher
      // watching a spinner during an escalation is its own kind of failure.
      // On a timeout the catch below reports "could not tell", which is the
      // honest answer and the one that gets them to pick up the phone.
      signal: AbortSignal.timeout(20_000),
      body: JSON.stringify({
        alertId: payload.alertIds[0],
        alertIds: payload.alertIds,
        agency: payload.agency,
        targetLga: payload.targetLga,
        reason: payload.reason,
        sentBy: payload.sentBy,
      }),
    });
    // The body is the point. `res.ok` alone cannot tell a delivery from a
    // skipped channel, and reading the status code instead of the verdict is
    // how this went unnoticed for fifty merges.
    const body = await res.json().catch(() => null) as
      { delivered?: boolean; detail?: string; error?: string } | null;
    if (body && typeof body.delivered === 'boolean') {
      return {
        delivered: body.delivered,
        detail: body.detail || (body.delivered ? 'Agency notified.' : 'Agency was not notified.'),
      };
    }
    return {
      delivered: false,
      detail: body?.error
        ? `${payload.agency} was NOT notified: ${body.error}`
        : `${payload.agency} was NOT notified: the notification endpoint answered ${res.status}.`,
    };
  } catch (e) {
    console.warn('[HQ_AGENCY_NOTIFY_WARN]', e);
    const message = (e as { message?: string } | null)?.message || 'the request did not complete';
    return {
      delivered: false,
      detail: `Could not tell whether ${payload.agency} was notified: ${message}.`,
    };
  }
}

export async function escalateAlert(
  alertIds: AlertIds,
  options: EscalateOptions,
  actor: Actor,
): Promise<ActionResult<{ commanderName: string; agency: string; notified: AgencyDelivery | null }>> {
  const ids = idsOf(alertIds);
  const lgaTarget = options.targetLga || 'ALL';
  const agencyTarget = options.targetAgency || 'ALL';
  const reason = options.reason || 'High Threat Escalation';
  const byEmail = actor.email || 'HQ_OFFICER';

  try {
    // Resolve the target LGA commander UUID — do NOT use the HQ operator's own ID
    let targetCommanderId: string | null = null;
    let targetCommanderName = `${agencyTarget} Command`;
    if (lgaTarget && lgaTarget !== 'ALL') {
      const { data: commander } = await supabase
        .from('profiles')
        .select('id, full_name')
        .eq('role', 'LGA_COMMAND')
        .eq('geo_lga', lgaTarget)
        .limit(1)
        .maybeSingle();
      if (commander) {
        targetCommanderId = commander.id;
        targetCommanderName = commander.full_name || targetCommanderName;
      }
    }

    const escNote = `[HQ ESCALATION → ${agencyTarget} | ${lgaTarget}] ${reason} (by ${byEmail})`;
    const at = new Date().toISOString();
    const logEntry = {
      from_tier: 'HQ',
      // A RUNG, NOT A PLACE.
      //
      // This wrote `lgaTarget` — an LGA NAME such as 'JOS SOUTH'. The mobile
      // app and the database's timeout job both write a tier LABEL here
      // ('UNIT', 'WARD', 'LGA', 'HQ'), and the agency portal renders the field
      // as `from_tier → to_tier`. So one entry in the same timeline read
      // "HQ → LGA" and the next read "HQ → JOS SOUTH", and nothing said which
      // kind of thing either was. The place has its own key now, so both facts
      // survive and the column has one meaning.
      to_tier: lgaTarget && lgaTarget !== 'ALL' ? 'LGA' : agencyTarget,
      to_lga: lgaTarget,
      to_agency: agencyTarget,
      to_officer_id: targetCommanderId,
      to_officer_name: targetCommanderName,
      reason,
      by_email: byEmail,
      at,
    };

    // One row at a time, on purpose: each report keeps ITS OWN escalation log
    // and notes. A single multi-row update would stamp the first report's
    // history onto every member of the cluster.
    for (const alertId of ids) {
      const { data: existing } = await supabase
        .from('alerts')
        .select('ai_summary, escalation_log, geo_lga')
        .eq('id', alertId)
        .single();
      const existingNotes = existing?.ai_summary || '';
      const existingLog = existing?.escalation_log || [];

      const updateData: Record<string, unknown> = {
        severity: 'CRITICAL',
        status: 'ESCALATED',
        escalated_to_agency: agencyTarget,
        // IMPORTANT: Do NOT overwrite geo_lga — incident location must stay intact
        escalation_log: [...existingLog, logEntry],
        ai_summary: existingNotes ? `${existingNotes}\n${escNote}` : escNote,
        updated_at: at,
      };

      // HAND THE TIER DOWN, NOT JUST THE OFFICER.
      //
      // This wrote `assigned_to` and `escalated_to_agency` and left
      // `assigned_tier` alone, so an incident HQ handed to an LGA commander was
      // still owned by tier HQ. The responder app shows an officer the alerts of
      // their own tier and above, so the LGA commander's whole team could not
      // see it — only the one named officer, and only through the "assigned to
      // me" rule. Everyone else at that LGA was looking at a queue the incident
      // had been removed from.
      //
      // `tier_assigned_at` restarts with it, because the server-side timeout is
      // measured from there and the LGA needs its own window rather than
      // whatever is left of HQ's. `acknowledged_*` clears: nobody at the new
      // tier has acknowledged anything yet.
      //
      // Only when a TIER is the target. Escalating to an outside agency is a
      // different axis — `escalated_to_agency` — and must not move the incident
      // down the internal chain.
      if (lgaTarget && lgaTarget !== 'ALL') {
        updateData.assigned_tier = 'LGA';
        updateData.tier_assigned_at = at;
        updateData.acknowledged_at = null;
        updateData.acknowledged_by = null;
      }

      // Assign to the resolved commander UUID — NOT the HQ operator's own ID
      if (targetCommanderId) {
        updateData.assigned_to = targetCommanderId;
      } else if (actor.id) {
        // Fallback: assign to HQ operator only if no commander found
        updateData.assigned_to = actor.id;
      }

      const { error } = await supabase.from('alerts').update(updateData).eq('id', alertId);
      if (error) throw error;
    }

    // Notify the outside agency if a specific one was selected.
    //
    // AWAITED, AND THE ANSWER IS READ. Still never fatal to the escalation —
    // see `AgencyDelivery` — but the outcome travels back to the caller so the
    // operator can be told that the Police were not reached, which is a
    // different thing from the escalation failing and needs a different action
    // from them: pick up the phone.
    let notified: AgencyDelivery | null = null;
    if (agencyTarget !== 'ALL' && agencyTarget !== 'HQ') {
      notified = await notifyAgency({
        alertIds: ids,
        agency: agencyTarget,
        targetLga: lgaTarget,
        reason,
        sentBy: byEmail,
      });
    }

    return {
      ok: true,
      value: { commanderName: targetCommanderName, agency: agencyTarget, notified },
    };
  } catch (e) {
    console.error('[HQ_ESCALATE_ERR]', e);
    return failed(e, 'Unknown error');
  }
}

/**
 * HQ takes command of an incident itself.
 *
 * "HQ overrides where the chain is not accessible" is the whole point of this
 * button, and it used to write only severity, status and the operator's uuid.
 * Two consequences, both silent:
 *
 *   * `assigned_tier` stayed wherever the incident was — typically 'UNIT', since
 *     an override is most often used on something nobody below answered. So the
 *     server-side escalation job kept climbing it: HQ took command and the alert
 *     was then escalated onward from under HQ, minutes later, by a timeout.
 *   * `acknowledged_at` stayed null, which is what that job reads to mean "no
 *     one has this". HQ taking command is the clearest possible case of somebody
 *     having it.
 *
 * Taking command means owning the rung and stopping the clock.
 */
export async function hqOverride(alertIds: AlertIds, actor: Actor): Promise<ActionResult> {
  const ids = idsOf(alertIds);
  try {
    const at = new Date().toISOString();
    const updateData: Record<string, unknown> = {
      severity: 'CRITICAL',
      status: 'IN_PROGRESS',
      assigned_tier: 'HQ',
      tier_assigned_at: at,
      acknowledged_at: at,
      updated_at: at,
    };
    if (actor.id) {
      updateData.assigned_to = actor.id;
      updateData.acknowledged_by = actor.id;
    }
    const { error } = await supabase.from('alerts').update(updateData).in('id', ids);
    if (error) throw error;
    return { ok: true };
  } catch (e) {
    console.error('[HQ_OVERRIDE_ERR]', e);
    return failed(e, 'Override failed');
  }
}

/**
 * A named officer stands behind a report that arrived from a keypad.
 *
 * A USSD report is held out of the escalation ladder until this happens — no
 * timer may turn a stranger's keypresses into a deployment (migration
 * 20261011000000). This is the officer's decision, and the database records
 * whose it was.
 *
 * `confirm_ussd_report()` is SECURITY INVOKER, so
 * `alerts_update_own_or_ours` decides whether this account may act on the
 * incident at all. It returns NO ROW when refused, when the incident is not a
 * USSD one, or when it was already confirmed — and an empty result must never
 * read as success, because an officer told "confirmed" on a report still held
 * back would believe the ladder was running when it was not.
 */
export async function confirmUssdReport(
  alertIds: AlertIds,
): Promise<ActionResult<{ confirmed: number; refused: number }>> {
  const ids = idsOf(alertIds);
  let confirmed = 0;
  let refused = 0;
  try {
    for (const id of ids) {
      const { data, error } = await supabase.rpc('confirm_ussd_report', { p_alert_id: id });
      if (error) throw error;
      const rows = Array.isArray(data) ? data : data ? [data] : [];
      if (rows.length > 0) confirmed += 1;
      else refused += 1;
    }
    if (confirmed === 0) {
      // Every one refused. Reported as a FAILURE rather than a quiet zero: the
      // operator needs to know their confirmation did not take, because the
      // report is still out of the ladder and nothing will chase it.
      return {
        ok: false,
        error: refused === 1
          ? 'Not confirmed — either it is not yours to confirm, or somebody already did.'
          : `None of the ${refused} were confirmed — not yours, or already confirmed.`,
      };
    }
    return { ok: true, value: { confirmed, refused } };
  } catch (e) {
    console.error('[USSD_CONFIRM_ERR]', e);
    return failed(e, 'Confirmation failed');
  }
}

/**
 * An officer records that a report was untrue.
 *
 * FALSE_REPORT, deliberately distinct from CANCELLED — which is a reporter
 * standing themselves down and carries no accusation. This is the only source of
 * the history that makes a number's credibility a fact rather than a guess, so
 * the note matters: it is what the next dispatcher reads when the same number
 * calls again.
 */
export async function markFalseReport(
  alertIds: AlertIds,
  note: string,
): Promise<ActionResult<{ marked: number }>> {
  const ids = idsOf(alertIds);
  try {
    let marked = 0;
    for (const id of ids) {
      const { data, error } = await supabase.rpc('mark_false_report', {
        p_alert_id: id,
        p_note: note,
      });
      if (error) throw error;
      if (data === true) marked += 1;
    }
    if (marked === 0) {
      return { ok: false, error: 'Not marked — this incident is not yours to close.' };
    }
    return { ok: true, value: { marked } };
  } catch (e) {
    console.error('[MARK_FALSE_ERR]', e);
    return failed(e, 'Could not mark it false');
  }
}

/**
 * What a dispatcher should know before committing officers on the word of a
 * phone number.
 *
 * Returns null rather than throwing when it cannot be read: a card that cannot
 * show the credibility panel is worse than no panel only if it also HIDES the
 * incident, so the caller falls back to showing the report without it.
 */
export async function ussdCredibility(alertId: string): Promise<UssdCredibility | null> {
  try {
    const { data, error } = await supabase.rpc('ussd_report_credibility', {
      p_alert_id: alertId,
    });
    if (error) throw error;
    const rows = Array.isArray(data) ? data : data ? [data] : [];
    return rows.length > 0 ? (rows[0] as UssdCredibility) : null;
  } catch (e) {
    console.error('[USSD_CREDIBILITY_ERR]', e);
    return null;
  }
}

/** Closes an incident, recording who closed it. */
export async function resolveAlert(alertIds: AlertIds, actor: Actor): Promise<ActionResult> {
  const ids = idsOf(alertIds);
  try {
    const resolver = actor.email || actor.id || 'HQ_OFFICER';
    const nowIso = new Date().toISOString();
    const { error } = await supabase.from('alerts').update({
      status: 'RESOLVED',
      resolved_by: resolver,
      resolved_at: nowIso,
      updated_at: nowIso,
    }).in('id', ids);
    if (error) throw error;
    return { ok: true };
  } catch (e) {
    console.error('[HQ_RESOLVE_ERR]', e);
    return failed(e, 'Resolution failed');
  }
}

/**
 * Assigns responders to an incident.
 *
 * The first uid becomes the lead (`assigned_to`); all of them are recorded in
 * `assigned_responders`. The push notification is best-effort: the assignment
 * is already committed in the database, so a push failure must not report the
 * dispatch as failed — the responders are assigned either way, and telling the
 * operator otherwise invites a second dispatch.
 */
export async function dispatchAlert(
  alertIds: AlertIds,
  responderUids: string[] | string,
): Promise<ActionResult<{ count: number; stoodDown: number }>> {
  const ids = idsOf(alertIds);
  const uids = Array.isArray(responderUids) ? responderUids : [responderUids];
  if (uids.length === 0) return { ok: false, error: 'No responders selected' };

  try {
    const leadId = uids[0];
    const nowIso = new Date().toISOString();

    // WHO IS BEING TAKEN OFF THIS INCIDENT.
    //
    // `assigned_responders` is REPLACED, not merged, and only the new uids were
    // ever notified — so reassigning an incident removed officers from it in
    // silence. The responder app lists an officer's work by this column, so the
    // incident simply vanished from their screen; if they were already driving
    // to it, nothing said stand down.
    //
    // Read before the write, per incident, because each keeps its own team.
    const previousTeams = new Map<string, string[]>();
    const { data: before } = await supabase
      .from('alerts')
      .select('id, assigned_responders')
      .in('id', ids);
    for (const row of before ?? []) {
      previousTeams.set(row.id as string, (row.assigned_responders as string[]) ?? []);
    }

    const { error } = await supabase.from('alerts').update({
      status: 'DISPATCHED',
      assigned_to: leadId,
      assigned_responders: uids,
      updated_at: nowIso,
    }).in('id', ids);
    if (error) throw error;

    const standDown = [...new Set(
      ids.flatMap(id => standDownList(previousTeams.get(id) ?? [], uids)),
    )];

    // Secure server-side push notification dispatch
    try {
      await fetch('/api/push/dispatch', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ alertId: ids[0], alertIds: ids, responderUids: uids }),
      });
    } catch (pushErr) {
      console.warn('[HQ_PUSH_WARN] Notification push API failed:', pushErr);
    }

    // A separate call, deliberately: a stand-down that failed must not be
    // mistaken for a dispatch that failed, and the two carry opposite
    // instructions. Failing to reach someone being stood down is logged and
    // does not fail the dispatch — the officers being SENT have been told, and
    // that is the more urgent half.
    if (standDown.length > 0) {
      try {
        await fetch('/api/push/dispatch', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ alertId: ids[0], alertIds: ids, responderUids: standDown, kind: 'STAND_DOWN' }),
        });
      } catch (pushErr) {
        console.warn('[HQ_STANDDOWN_WARN] Stand-down notification failed:', pushErr);
      }
    }

    return { ok: true, value: { count: uids.length, stoodDown: standDown.length } };
  } catch (e) {
    console.error('[HQ_DISPATCH_ERR]', e);
    return failed(e, 'Dispatch failed');
  }
}

/**
 * Sends a message into an incident's tactical channel, as the signed-in
 * operator.
 *
 * THE DISPATCHER COULD NOT REPLY.
 *
 * The mobile app has two chat screens — the citizen's, titled DISPATCHER CHAT,
 * and the responder's SECURE CHAT — and both write and subscribe correctly.
 * The console, where the dispatcher actually sits, read `chat_messages` in two
 * places and wrote nowhere. So a citizen in an emergency could send messages to
 * a dispatcher who had no way to answer, and the only person who could reply
 * was a responder who happened to have that exact incident open on a handset.
 *
 * `actor.id` is required rather than optional: `sender_id` must equal
 * `auth.uid()` for the insert policy to admit it, and an anonymous console
 * message is not a thing we want to invent a fallback for — an unattributed
 * instruction on an emergency channel is worse than no instruction.
 */
export async function sendChatMessage(
  alertId: string,
  message: string,
  actor: Actor & { name?: string; role?: string },
): Promise<ActionResult> {
  const text = message.trim();
  if (!text) return { ok: false, error: 'Nothing to send' };
  if (!actor.id) return { ok: false, error: 'Not signed in' };

  try {
    const { error } = await supabase.from('chat_messages').insert({
      alert_id: alertId,
      sender_id: actor.id,
      sender_name: actor.name || actor.email || 'HQ DISPATCH',
      sender_role: actor.role || 'HQ_COMMAND',
      message: text,
    });
    if (error) throw error;
    return { ok: true };
  } catch (e) {
    console.error('[HQ_CHAT_ERR]', e);
    return failed(e, 'Message not sent');
  }
}
