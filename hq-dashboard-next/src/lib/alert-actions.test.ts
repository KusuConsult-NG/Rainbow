// What HQ *does* to an incident.
//
// These four writes were extracted verbatim from dashboard/page.tsx, where they
// had no coverage. They assign responders, hand incidents to outside agencies
// and close them out. A silent failure here is not cosmetic: a dispatch that
// did not happen looks exactly like one that did.
//
// Two of the assertions below correspond to comments in the original source
// marking bugs that were already fixed once ("do NOT use the HQ operator's own
// ID", "Do NOT overwrite geo_lga"). A comment cannot stop a regression; these
// can.
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { makeSupabaseStub, type SupabaseStub } from '@/test/supabase-stub';

let db: SupabaseStub;

vi.mock('@/lib/supabase', () => ({
  get supabase() {
    return db.client;
  },
}));

const HQ = { id: 'hq-operator-uuid', email: 'hq@operationrainbow.plateau.gov.ng' };

const ALERT = {
  id: 'alert-1',
  status: 'PENDING',
  geo_lga: 'JOS NORTH',
  ai_summary: '',
  escalation_log: [],
};

const COMMANDER = {
  id: 'lga-commander-uuid',
  full_name: 'ACP Ibrahim Sule',
  role: 'LGA_COMMAND',
  geo_lga: 'JOS SOUTH',
};

async function actions() {
  return import('./alert-actions');
}

/** The single `alerts` update a test performed. */
const alertUpdate = () => db.updates.find(u => u.table === 'alerts')!;

describe('escalateAlert', () => {
  beforeEach(() => {
    db = makeSupabaseStub();
    db.setRows('alerts', [ALERT]);
    db.setRows('profiles', [COMMANDER]);
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response('{}', { status: 200 }));
  });

  it('escalates to CRITICAL/ESCALATED and records the agency', async () => {
    const { escalateAlert } = await actions();
    const res = await escalateAlert('alert-1', { targetAgency: 'POLICE' }, HQ);

    expect(res.ok).toBe(true);
    expect(alertUpdate().values).toMatchObject({
      severity: 'CRITICAL',
      status: 'ESCALATED',
      escalated_to_agency: 'POLICE',
    });
    expect(alertUpdate().eq).toEqual(['id', 'alert-1']);
  });

  // Each member keeps its OWN log and notes: one write per row, not one
  // multi-row write that stamps the first report's history on every member.
  it('escalates every member of a cluster, appending to each row separately', async () => {
    db.setRows('alerts', [
      { ...ALERT, id: 'a', escalation_log: [{ reason: 'a-history' }] },
      { ...ALERT, id: 'b', escalation_log: [{ reason: 'b-history' }] },
    ]);
    const { escalateAlert } = await actions();
    const res = await escalateAlert(['a', 'b'], { targetAgency: 'POLICE' }, HQ);

    expect(res.ok).toBe(true);
    const writes = db.updates.filter(u => u.table === 'alerts');
    expect(writes.map(w => w.eq)).toEqual([['id', 'a'], ['id', 'b']]);
    expect((writes[0].values.escalation_log as any[])[0]).toEqual({ reason: 'a-history' });
    expect((writes[1].values.escalation_log as any[])[0]).toEqual({ reason: 'b-history' });
    // one notification for the event, not one per report
    expect(globalThis.fetch).toHaveBeenCalledTimes(1);
  });

  // The bug the source comment warns about. Assigning the HQ operator routes
  // the escalation straight back to the person escalating it.
  it('assigns the TARGET LGA commander, not the HQ operator', async () => {
    const { escalateAlert } = await actions();
    await escalateAlert('alert-1', { targetLga: 'JOS SOUTH', targetAgency: 'POLICE' }, HQ);

    expect(alertUpdate().values.assigned_to).toBe('lga-commander-uuid');
    expect(alertUpdate().values.assigned_to).not.toBe(HQ.id);
  });

  it('falls back to the HQ operator only when no commander exists', async () => {
    db.setRows('profiles', []);
    const { escalateAlert } = await actions();
    await escalateAlert('alert-1', { targetLga: 'NOWHERE' }, HQ);

    expect(alertUpdate().values.assigned_to).toBe(HQ.id);
  });

  it('assigns nobody when there is no commander and no signed-in operator', async () => {
    db.setRows('profiles', []);
    const { escalateAlert } = await actions();
    await escalateAlert('alert-1', { targetLga: 'NOWHERE' }, {});

    expect(alertUpdate().values).not.toHaveProperty('assigned_to');
  });

  // The other comment-marked bug. An incident's location is where it happened,
  // not who is handling it; writing geo_lga moves the emergency on the map.
  it('never writes geo_lga', async () => {
    const { escalateAlert } = await actions();
    await escalateAlert('alert-1', { targetLga: 'JOS SOUTH', targetAgency: 'ARMY' }, HQ);

    expect(alertUpdate().values).not.toHaveProperty('geo_lga');
  });

  // THE TIER, NOT JUST THE OFFICER.
  //
  // The responder app shows an officer the alerts of their own tier and above.
  // This write left `assigned_tier` at 'HQ', so an incident handed to an LGA
  // commander stayed owned by the tier above them: their whole team could not
  // see it, and only the one named officer could, and only through the
  // "assigned to me" rule.
  it('hands the TIER down to the LGA, not only the named commander', async () => {
    const { escalateAlert } = await actions();
    await escalateAlert('alert-1', { targetLga: 'JOS SOUTH' }, HQ);

    expect(alertUpdate().values.assigned_tier).toBe('LGA');
  });

  // The timeout is measured from `tier_assigned_at`. Leaving HQ's timestamp on
  // an incident handed to an LGA gives that LGA whatever is left of somebody
  // else's window — often none of it.
  it('restarts the ownership clock for the tier taking it', async () => {
    const { escalateAlert } = await actions();
    await escalateAlert('alert-1', { targetLga: 'JOS SOUTH' }, HQ);

    const at = alertUpdate().values.tier_assigned_at as string;
    expect(at).toBeTypeOf('string');
    expect(Date.now() - Date.parse(at)).toBeLessThan(60_000);
    expect(alertUpdate().values.acknowledged_at).toBeNull();
    expect(alertUpdate().values.acknowledged_by).toBeNull();
  });

  // An outside agency is a different axis from the internal chain. Handing an
  // incident to the police does not move it down to an LGA desk.
  it('leaves the tier alone when only an external agency is targeted', async () => {
    const { escalateAlert } = await actions();
    await escalateAlert('alert-1', { targetAgency: 'POLICE' }, HQ);

    expect(alertUpdate().values).not.toHaveProperty('assigned_tier');
    expect(alertUpdate().values).not.toHaveProperty('tier_assigned_at');
    expect(alertUpdate().values.escalated_to_agency).toBe('POLICE');
  });

  it('APPENDS to the escalation log rather than replacing it', async () => {
    const prior = { from_tier: 'LGA', to_tier: 'HQ', reason: 'earlier handover' };
    db.setRows('alerts', [{ ...ALERT, escalation_log: [prior] }]);

    const { escalateAlert } = await actions();
    await escalateAlert('alert-1', { targetLga: 'JOS SOUTH', reason: 'riot spreading' }, HQ);

    const log = alertUpdate().values.escalation_log as unknown[];
    expect(log).toHaveLength(2);
    expect(log[0]).toEqual(prior);
    expect(log[1]).toMatchObject({
      from_tier: 'HQ',
      // A rung, matching what the mobile app and the timeout job write into
      // this field. The LGA is the destination PLACE and has its own key.
      to_tier: 'LGA',
      to_lga: 'JOS SOUTH',
      to_officer_id: 'lga-commander-uuid',
      to_officer_name: 'ACP Ibrahim Sule',
      reason: 'riot spreading',
      by_email: HQ.email,
    });
  });

  // One timeline, one vocabulary. The agency portal renders this field as
  // `from_tier → to_tier`, and a place sitting where every other writer puts a
  // rung made two adjacent entries unreadable side by side.
  it('never writes a place name into to_tier', async () => {
    const { escalateAlert } = await actions();
    await escalateAlert('alert-1', { targetLga: 'JOS SOUTH', targetAgency: 'POLICE' }, HQ);

    const log = alertUpdate().values.escalation_log as Array<Record<string, unknown>>;
    expect(['UNIT', 'WARD', 'LGA', 'HQ', 'POLICE', 'ARMY', 'ALL'])
      .toContain(log[log.length - 1].to_tier);
    expect(log[log.length - 1].to_tier).not.toBe('JOS SOUTH');
  });

  it('APPENDS to the notes rather than overwriting them', async () => {
    db.setRows('alerts', [{ ...ALERT, ai_summary: 'Existing forensic summary.' }]);

    const { escalateAlert } = await actions();
    await escalateAlert('alert-1', { targetAgency: 'DSS', reason: 'needs intel' }, HQ);

    const notes = alertUpdate().values.ai_summary as string;
    expect(notes.startsWith('Existing forensic summary.')).toBe(true);
    expect(notes).toContain('[HQ ESCALATION → DSS | ALL] needs intel');
  });

  it('uses a default reason when none is given', async () => {
    const { escalateAlert } = await actions();
    await escalateAlert('alert-1', {}, HQ);

    expect(alertUpdate().values.ai_summary).toContain('High Threat Escalation');
  });

  it('notifies an external agency', async () => {
    const { escalateAlert } = await actions();
    await escalateAlert('alert-1', { targetAgency: 'NSCDC', targetLga: 'JOS SOUTH' }, HQ);

    expect(globalThis.fetch).toHaveBeenCalledWith(
      '/api/notify-agency',
      expect.objectContaining({ method: 'POST' }),
    );
  });

  it.each(['ALL', 'HQ'])('does not fire an agency notification for %s', async (agency) => {
    const { escalateAlert } = await actions();
    await escalateAlert('alert-1', { targetAgency: agency }, HQ);

    expect(globalThis.fetch).not.toHaveBeenCalled();
  });

  // The escalation is already committed when the notification is attempted.
  // Reporting failure would invite the operator to escalate a second time.
  it('still succeeds when the agency notification fails', async () => {
    vi.spyOn(globalThis, 'fetch').mockRejectedValue(new Error('network down'));
    const { escalateAlert } = await actions();

    const res = await escalateAlert('alert-1', { targetAgency: 'POLICE' }, HQ);
    expect(res.ok).toBe(true);
  });

  // ── Whether the agency was actually told ────────────────────────────────
  //
  // The escalation and the notification are two facts, and only one of them
  // used to reach the operator. The POST was fired and discarded, so a route
  // answering `400 Unknown agency 'NPF'` — which is what the console's own
  // escalation menu produced for the Police — looked exactly like a delivered
  // handover.
  it('reports that the agency was reached when the endpoint says it was', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(
      JSON.stringify({ delivered: true, detail: 'Nigeria Police Force notified by SMS.' }),
      { status: 200 },
    ));
    const { escalateAlert } = await actions();

    const res = await escalateAlert('alert-1', { targetAgency: 'POLICE' }, HQ);
    expect(res.ok && res.value.notified).toEqual({
      delivered: true,
      detail: 'Nigeria Police Force notified by SMS.',
    });
  });

  it('reports that it was NOT reached when the endpoint says nothing was sent', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(
      JSON.stringify({ delivered: false, detail: 'Nigeria Police Force was NOT notified: no contact configured.' }),
      { status: 503 },
    ));
    const { escalateAlert } = await actions();

    const res = await escalateAlert('alert-1', { targetAgency: 'POLICE' }, HQ);
    expect(res.ok).toBe(true);
    expect(res.ok && res.value.notified?.delivered).toBe(false);
    expect(res.ok && res.value.notified?.detail).toContain('NOT notified');
  });

  // The exact shape of the original defect: the endpoint refused the code the
  // menu submitted, and the escalation still read as a completed handover.
  it('reports NOT reached when the endpoint refuses the agency code', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(
      JSON.stringify({ error: "Unknown agency 'NPF'. Expected one of: POLICE, ARMY, DSS, NSCDC, FRSC, OPSH" }),
      { status: 400 },
    ));
    const { escalateAlert } = await actions();

    const res = await escalateAlert('alert-1', { targetAgency: 'NPF' }, HQ);
    expect(res.ok).toBe(true);
    expect(res.ok && res.value.notified?.delivered).toBe(false);
    expect(res.ok && res.value.notified?.detail).toContain("Unknown agency 'NPF'");
  });

  it('reports NOT reached — not a thrown escalation — when the request dies', async () => {
    vi.spyOn(globalThis, 'fetch').mockRejectedValue(new Error('network down'));
    const { escalateAlert } = await actions();

    const res = await escalateAlert('alert-1', { targetAgency: 'ARMY' }, HQ);
    expect(res.ok).toBe(true);
    expect(res.ok && res.value.notified?.delivered).toBe(false);
    expect(res.ok && res.value.notified?.detail).toContain('network down');
  });

  it.each(['ALL', 'HQ'])('has nothing to report about delivery for %s', async (agency) => {
    const { escalateAlert } = await actions();
    const res = await escalateAlert('alert-1', { targetAgency: agency }, HQ);
    expect(res.ok && res.value.notified).toBeNull();
  });

  it('reports failure when the update is rejected', async () => {
    db.setUpdateError('alerts', { message: 'permission denied for table alerts' });
    const { escalateAlert } = await actions();

    const res = await escalateAlert('alert-1', { targetAgency: 'POLICE' }, HQ);
    expect(res).toEqual({ ok: false, error: 'permission denied for table alerts' });
  });
});

describe('hqOverride', () => {
  beforeEach(() => {
    db = makeSupabaseStub();
    db.setRows('alerts', [ALERT]);
  });

  it('takes command: CRITICAL, IN_PROGRESS, assigned to the operator', async () => {
    const { hqOverride } = await actions();
    const res = await hqOverride('alert-1', HQ);

    expect(res.ok).toBe(true);
    expect(alertUpdate().values).toMatchObject({
      severity: 'CRITICAL',
      status: 'IN_PROGRESS',
      assigned_to: HQ.id,
    });
    expect(alertUpdate().in).toEqual(['id', ['alert-1']]);
  });

  // HQ TAKING COMMAND HAS TO STOP THE CLOCK.
  //
  // An override is most often used on an incident nobody below answered, so its
  // `assigned_tier` is typically still 'UNIT'. Writing only status and assignee
  // left the server-side escalation job free to keep climbing it — HQ took
  // command and the timeout then escalated the incident onward from under HQ.
  it('owns the top rung and records the acknowledgement', async () => {
    const { hqOverride } = await actions();
    await hqOverride('alert-1', HQ);

    const v = alertUpdate().values;
    expect(v.assigned_tier).toBe('HQ');
    expect(Date.now() - Date.parse(v.tier_assigned_at as string)).toBeLessThan(60_000);
    expect(Date.now() - Date.parse(v.acknowledged_at as string)).toBeLessThan(60_000);
    expect(v.acknowledged_by).toBe(HQ.id);
  });

  it('records the acknowledgement even with no operator to attribute it to', async () => {
    const { hqOverride } = await actions();
    await hqOverride('alert-1', {});

    // Somebody at HQ pressed the button; we just cannot name them. The
    // timestamp is what the escalation job reads, so it must still be set.
    expect(alertUpdate().values.acknowledged_at).toBeTypeOf('string');
    expect(alertUpdate().values).not.toHaveProperty('acknowledged_by');
  });

  it('overrides every member of a cluster in one write', async () => {
    const { hqOverride } = await actions();
    await hqOverride(['a', 'b', 'c'], HQ);
    expect(alertUpdate().in).toEqual(['id', ['a', 'b', 'c']]);
  });

  it('omits the assignment when there is no signed-in operator', async () => {
    const { hqOverride } = await actions();
    await hqOverride('alert-1', {});

    expect(alertUpdate().values).not.toHaveProperty('assigned_to');
  });

  it('reports failure when the update is rejected', async () => {
    db.setUpdateError('alerts', { message: 'row level security' });
    const { hqOverride } = await actions();

    expect(await hqOverride('alert-1', HQ)).toEqual({ ok: false, error: 'row level security' });
  });
});

describe('resolveAlert', () => {
  beforeEach(() => {
    db = makeSupabaseStub();
    db.setRows('alerts', [ALERT]);
  });

  it('closes the incident with attribution', async () => {
    const { resolveAlert } = await actions();
    const res = await resolveAlert('alert-1', HQ);

    expect(res.ok).toBe(true);
    expect(alertUpdate().values).toMatchObject({
      status: 'RESOLVED',
      resolved_by: HQ.email,
    });
    expect(alertUpdate().values.resolved_at).toEqual(expect.any(String));
    expect(alertUpdate().in).toEqual(['id', ['alert-1']]);
  });

  // The bug this exists for: resolving a clustered card used to close the
  // first report only, leaving the rest open and no longer on the board.
  it('resolves every member of a cluster, not just the first', async () => {
    const { resolveAlert } = await actions();
    await resolveAlert(['first', 'second', 'third'], HQ);

    expect(alertUpdate().in).toEqual(['id', ['first', 'second', 'third']]);
    expect(alertUpdate().values.status).toBe('RESOLVED');
  });

  // Who closed an incident is the audit trail for it. Falling back to the id,
  // then to a marker, means the field is never silently empty.
  it.each([
    [{ id: 'only-an-id' }, 'only-an-id'],
    [{}, 'HQ_OFFICER'],
  ])('attributes the resolution even with a partial actor (%o)', async (actor, expected) => {
    const { resolveAlert } = await actions();
    await resolveAlert('alert-1', actor);

    expect(alertUpdate().values.resolved_by).toBe(expected);
  });

  it('reports failure when the update is rejected', async () => {
    db.setUpdateError('alerts', { message: 'connection lost' });
    const { resolveAlert } = await actions();

    expect(await resolveAlert('alert-1', HQ)).toEqual({ ok: false, error: 'connection lost' });
  });
});

describe('dispatchAlert', () => {
  beforeEach(() => {
    db = makeSupabaseStub();
    db.setRows('alerts', [ALERT]);
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response('{}', { status: 200 }));
  });

  it('assigns the first responder as lead and records them all', async () => {
    const { dispatchAlert } = await actions();
    const res = await dispatchAlert('alert-1', ['lead-uid', 'second-uid', 'third-uid']);

    expect(res.ok).toBe(true);
    expect(alertUpdate().values).toMatchObject({
      status: 'DISPATCHED',
      assigned_to: 'lead-uid',
      assigned_responders: ['lead-uid', 'second-uid', 'third-uid'],
    });
    expect(alertUpdate().in).toEqual(['id', ['alert-1']]);
  });

  it('dispatches the same team to every member of a cluster', async () => {
    const { dispatchAlert } = await actions();
    await dispatchAlert(['a', 'b'], ['lead']);
    expect(alertUpdate().in).toEqual(['id', ['a', 'b']]);
    expect(globalThis.fetch).toHaveBeenCalledWith('/api/push/dispatch', expect.objectContaining({
      body: JSON.stringify({ alertId: 'a', alertIds: ['a', 'b'], responderUids: ['lead'] }),
    }));
  });

  it('accepts a single uid as well as a list', async () => {
    const { dispatchAlert } = await actions();
    await dispatchAlert('alert-1', 'solo-uid');

    expect(alertUpdate().values).toMatchObject({
      assigned_to: 'solo-uid',
      assigned_responders: ['solo-uid'],
    });
  });

  it('writes nothing when no responders were selected', async () => {
    const { dispatchAlert } = await actions();
    const res = await dispatchAlert('alert-1', []);

    expect(res.ok).toBe(false);
    expect(db.updates).toHaveLength(0);
  });

  it('stands down an officer taken off the incident', async () => {
    // The gap this closes. assigned_responders is REPLACED, and only the new
    // uids were ever notified — so reassigning removed officers in silence.
    // The responder app lists work by this column, so the incident vanished
    // from their screen; if they were already driving to it, nothing said stop.
    db.setRows('alerts', [{ ...ALERT, assigned_responders: ['a', 'b', 'c'] }]);

    const { dispatchAlert } = await actions();
    const res = await dispatchAlert('alert-1', ['a']);

    expect(res.ok).toBe(true);
    expect(globalThis.fetch).toHaveBeenCalledWith(
      '/api/push/dispatch',
      expect.objectContaining({
        body: JSON.stringify({
          alertId: 'alert-1',
          alertIds: ['alert-1'],
          responderUids: ['b', 'c'],
          kind: 'STAND_DOWN',
        }),
      }),
    );
  });

  it('does not stand anybody down on a first dispatch', async () => {
    // A stand-down to nobody is a wasted call; a stand-down to the officers
    // just dispatched would cancel the deployment outright.
    db.setRows('alerts', [{ ...ALERT, assigned_responders: [] }]);

    const { dispatchAlert } = await actions();
    await dispatchAlert('alert-1', ['a', 'b']);

    const calls = (globalThis.fetch as unknown as { mock: { calls: unknown[][] } }).mock.calls;
    const standDowns = calls.filter(c => String((c[1] as RequestInit)?.body).includes('STAND_DOWN'));
    expect(standDowns).toHaveLength(0);
  });

  it('does not stand down an officer who is still on the incident', async () => {
    db.setRows('alerts', [{ ...ALERT, assigned_responders: ['a', 'b'] }]);

    const { dispatchAlert } = await actions();
    await dispatchAlert('alert-1', ['a', 'b', 'c']);

    const calls = (globalThis.fetch as unknown as { mock: { calls: unknown[][] } }).mock.calls;
    const standDowns = calls.filter(c => String((c[1] as RequestInit)?.body).includes('STAND_DOWN'));
    expect(standDowns).toHaveLength(0);
  });

  it('pushes a notification to the assigned responders', async () => {
    const { dispatchAlert } = await actions();
    await dispatchAlert('alert-1', ['a', 'b']);

    expect(globalThis.fetch).toHaveBeenCalledWith(
      '/api/push/dispatch',
      expect.objectContaining({
        method: 'POST',
        body: JSON.stringify({ alertId: 'alert-1', alertIds: ['alert-1'], responderUids: ['a', 'b'] }),
      }),
    );
  });

  // The assignment is already committed when the push is attempted. Reporting
  // failure would invite the operator to dispatch a second team.
  it('still reports success when the push notification fails', async () => {
    vi.spyOn(globalThis, 'fetch').mockRejectedValue(new Error('push gateway down'));
    const { dispatchAlert } = await actions();

    const res = await dispatchAlert('alert-1', ['a']);
    expect(res.ok).toBe(true);
    expect(alertUpdate().values.status).toBe('DISPATCHED');
  });

  it('reports failure when the assignment itself is rejected', async () => {
    db.setUpdateError('alerts', { message: 'permission denied' });
    const { dispatchAlert } = await actions();

    expect(await dispatchAlert('alert-1', ['a'])).toEqual({
      ok: false,
      error: 'permission denied',
    });
  });
});

// The dispatcher could not reply. The console read `chat_messages` in two
// places and wrote nowhere, so the citizen's DISPATCHER CHAT had no dispatcher
// on the other end — only a responder with that incident open on a handset.
describe('sendChatMessage', () => {
  beforeEach(() => {
    db = makeSupabaseStub();
    db.setRows('alerts', [ALERT]);
  });

  const inserted = () => db.inserts.find(i => i.table === 'chat_messages')!
    .values as Record<string, unknown>;

  it('sends as the signed-in operator', async () => {
    const { sendChatMessage } = await actions();
    const res = await sendChatMessage('alert-1', 'Units are ten minutes out.', {
      ...HQ, name: 'ACP Musa Ibrahim', role: 'HQ_COMMAND',
    });

    expect(res.ok).toBe(true);
    expect(inserted()).toMatchObject({
      alert_id: 'alert-1',
      sender_id: HQ.id,
      sender_name: 'ACP Musa Ibrahim',
      sender_role: 'HQ_COMMAND',
      message: 'Units are ten minutes out.',
    });
  });

  it('trims the message', async () => {
    const { sendChatMessage } = await actions();
    await sendChatMessage('alert-1', '   hold position   ', { ...HQ });
    expect(inserted().message).toBe('hold position');
  });

  it('refuses an empty message rather than writing a blank line', async () => {
    const { sendChatMessage } = await actions();
    expect(await sendChatMessage('alert-1', '   ', { ...HQ }))
      .toEqual({ ok: false, error: 'Nothing to send' });
    expect(db.inserts.find(i => i.table === 'chat_messages')).toBeUndefined();
  });

  // `sender_id` must equal auth.uid() for the insert policy to admit it, and
  // an unattributed instruction on an emergency channel is worse than none.
  it('refuses to send with nobody signed in', async () => {
    const { sendChatMessage } = await actions();
    expect(await sendChatMessage('alert-1', 'move in', { email: 'x@y.z' }))
      .toEqual({ ok: false, error: 'Not signed in' });
    expect(db.inserts.find(i => i.table === 'chat_messages')).toBeUndefined();
  });

  it('reports a rejected insert instead of swallowing it', async () => {
    db.setInsertError('chat_messages', { message: 'row level security' });
    const { sendChatMessage } = await actions();
    expect(await sendChatMessage('alert-1', 'move in', { ...HQ }))
      .toEqual({ ok: false, error: 'row level security' });
  });
});
