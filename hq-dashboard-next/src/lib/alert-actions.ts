import { supabase } from '@/lib/supabase';

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
export async function escalateAlert(
  alertIds: AlertIds,
  options: EscalateOptions,
  actor: Actor,
): Promise<ActionResult<{ commanderName: string; agency: string }>> {
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

    // Fire agency notification if a specific external agency was selected.
    // Deliberately not awaited and never fatal: the escalation is already
    // committed, and a failed notification must not report it as failed.
    if (agencyTarget !== 'ALL' && agencyTarget !== 'HQ') {
      fetch('/api/notify-agency', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          alertId: ids[0],
          alertIds: ids,
          agency: agencyTarget,
          targetLga: lgaTarget,
          reason,
          sentBy: byEmail,
        }),
      }).catch(err => console.warn('[HQ_AGENCY_NOTIFY_WARN]', err));
    }

    return { ok: true, value: { commanderName: targetCommanderName, agency: agencyTarget } };
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
): Promise<ActionResult<{ count: number }>> {
  const ids = idsOf(alertIds);
  const uids = Array.isArray(responderUids) ? responderUids : [responderUids];
  if (uids.length === 0) return { ok: false, error: 'No responders selected' };

  try {
    const leadId = uids[0];
    const nowIso = new Date().toISOString();
    const { error } = await supabase.from('alerts').update({
      status: 'DISPATCHED',
      assigned_to: leadId,
      assigned_responders: uids,
      updated_at: nowIso,
    }).in('id', ids);
    if (error) throw error;

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

    return { ok: true, value: { count: uids.length } };
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
