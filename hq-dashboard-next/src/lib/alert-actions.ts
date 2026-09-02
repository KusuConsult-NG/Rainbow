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
  alertId: string,
  options: EscalateOptions,
  actor: Actor,
): Promise<ActionResult<{ commanderName: string; agency: string }>> {
  const lgaTarget = options.targetLga || 'ALL';
  const agencyTarget = options.targetAgency || 'ALL';
  const reason = options.reason || 'High Threat Escalation';
  const byEmail = actor.email || 'HQ_OFFICER';

  try {
    const { data: existing } = await supabase
      .from('alerts')
      .select('ai_summary, escalation_log, geo_lga')
      .eq('id', alertId)
      .single();
    const existingNotes = existing?.ai_summary || '';
    const existingLog = existing?.escalation_log || [];

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
    const logEntry = {
      from_tier: 'HQ',
      to_tier: lgaTarget,
      to_agency: agencyTarget,
      to_officer_id: targetCommanderId,
      to_officer_name: targetCommanderName,
      reason,
      by_email: byEmail,
      at: new Date().toISOString(),
    };

    const updateData: Record<string, unknown> = {
      severity: 'CRITICAL',
      status: 'ESCALATED',
      escalated_to_agency: agencyTarget,
      // IMPORTANT: Do NOT overwrite geo_lga — incident location must stay intact
      escalation_log: [...existingLog, logEntry],
      ai_summary: existingNotes ? `${existingNotes}\n${escNote}` : escNote,
      updated_at: new Date().toISOString(),
    };

    // Assign to the resolved commander UUID — NOT the HQ operator's own ID
    if (targetCommanderId) {
      updateData.assigned_to = targetCommanderId;
    } else if (actor.id) {
      // Fallback: assign to HQ operator only if no commander found
      updateData.assigned_to = actor.id;
    }

    const { error } = await supabase.from('alerts').update(updateData).eq('id', alertId);
    if (error) throw error;

    // Fire agency notification if a specific external agency was selected.
    // Deliberately not awaited and never fatal: the escalation is already
    // committed, and a failed notification must not report it as failed.
    if (agencyTarget !== 'ALL' && agencyTarget !== 'HQ') {
      fetch('/api/notify-agency', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          alertId,
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

/** HQ takes command of an incident itself. */
export async function hqOverride(alertId: string, actor: Actor): Promise<ActionResult> {
  try {
    const updateData: Record<string, unknown> = {
      severity: 'CRITICAL',
      status: 'IN_PROGRESS',
    };
    if (actor.id) {
      updateData.assigned_to = actor.id;
    }
    const { error } = await supabase.from('alerts').update(updateData).eq('id', alertId);
    if (error) throw error;
    return { ok: true };
  } catch (e) {
    console.error('[HQ_OVERRIDE_ERR]', e);
    return failed(e, 'Override failed');
  }
}

/** Closes an incident, recording who closed it. */
export async function resolveAlert(alertId: string, actor: Actor): Promise<ActionResult> {
  try {
    const resolver = actor.email || actor.id || 'HQ_OFFICER';
    const nowIso = new Date().toISOString();
    const { error } = await supabase.from('alerts').update({
      status: 'RESOLVED',
      resolved_by: resolver,
      resolved_at: nowIso,
      updated_at: nowIso,
    }).eq('id', alertId);
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
  alertId: string,
  responderUids: string[] | string,
): Promise<ActionResult<{ count: number }>> {
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
    }).eq('id', alertId);
    if (error) throw error;

    // Secure server-side push notification dispatch
    try {
      await fetch('/api/push/dispatch', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ alertId, responderUids: uids }),
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
