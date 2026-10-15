import { describe, expect, it } from 'vitest';

import {
  deliveryEvents,
  entryActor,
  entryNotes,
  escalationEvents,
  eventStamp,
  inOrder,
  timelineFromAlert,
  type TimelineAlert,
} from './incident-timeline';

const alert = (over: Partial<TimelineAlert> = {}): TimelineAlert => ({
  id: '7f3c9a10-1111-2222-3333-444455556666',
  type: 'ARMED_ROBBERY',
  description: 'Three men, one vehicle, Naraguta junction.',
  status: 'ESCALATED',
  reported_by: 'bbbb2222-0000-4000-8000-00000000b001',
  created_at: '2026-09-28T11:45:00.000Z',
  updated_at: '2026-09-28T12:30:00.000Z',
  ...over,
});

// What the SQL sweep writes: `at`, `by`, `from_tier`, `to_tier`, `reason`.
// `escalate_overdue_alerts()` appends exactly this and touches no prose.
const AUTOMATIC = {
  at: '2026-09-28T12:00:00.000Z',
  from_tier: 'UNIT',
  to_tier: 'WARD',
  by: 'SYSTEM',
  reason: 'SLA breach: unacknowledged for 10 minutes',
};

// What the console writes: `by_email`, and a named officer when one was picked.
const MANUAL = {
  at: '2026-09-28T12:15:00.000Z',
  from_tier: 'WARD',
  to_tier: 'LGA',
  by_email: 'ward.commander@operationrainbow.test',
  reason: 'No unit free in the ward',
  to_officer_name: 'ASP Danjuma Iliya',
};

describe('escalationEvents', () => {
  it('finds an escalation that only the log records', () => {
    // THE DEFECT. The panel read `ai_summary` for escalations, and the
    // automatic sweep writes none: an incident that climbed at 02:00 because
    // nobody answered showed on the Audit History screen and NOT on the replay
    // of the incident it happened to.
    const events = escalationEvents(alert({ escalation_log: [AUTOMATIC], ai_summary: null }));

    expect(events).toHaveLength(1);
    expect(events[0].type).toBe('ESCALATION');
    expect(events[0].timestamp).toBe('2026-09-28T12:00:00.000Z');
    expect(events[0].notes).toContain('UNIT → WARD');
    expect(events[0].notes).toContain('SLA breach');
  });

  it('gives each escalation its own time instead of one updated_at for all', () => {
    const events = escalationEvents(alert({ escalation_log: [AUTOMATIC, MANUAL] }));

    expect(events.map((e) => e.timestamp)).toEqual([
      '2026-09-28T12:00:00.000Z',
      '2026-09-28T12:15:00.000Z',
    ]);
    // Three events carrying one timestamp cannot be ordered, which also put
    // chat messages sent between them in the wrong place.
    expect(new Set(events.map((e) => e.timestamp)).size).toBe(2);
  });

  it('names who escalated, from the entry, never a literal', () => {
    const events = escalationEvents(alert({ escalation_log: [AUTOMATIC, MANUAL] }));

    expect(events[0].actor).toBe('SYSTEM');
    expect(events[1].actor).toBe('ward.commander@operationrainbow.test');
    expect(events.map((e) => e.actor)).not.toContain('Tactical Command');
  });

  it('says a ward hand-down went to a named ward', () => {
    const events = escalationEvents(alert({
      escalation_log: [{
        at: '2026-09-28T12:20:00.000Z',
        from_tier: 'LGA',
        to_tier: 'WARD',
        to_ward: 'Naraguta B',
        to_lga: 'Jos North',
        by_email: 'lga@operationrainbow.test',
      }],
    }));

    // "LGA → WARD" does not say which ward, and that is the whole content of
    // a hand-down.
    expect(events[0].notes).toContain('Naraguta B');
  });

  it('keeps an entry whose time was never recorded, and says so', () => {
    const events = escalationEvents(alert({
      escalation_log: [{ from_tier: 'UNIT', to_tier: 'WARD', by: 'SYSTEM' }],
    }));

    expect(events).toHaveLength(1);
    expect(events[0].timestamp).toBe('2026-09-28T12:30:00.000Z');
    expect(events[0].notes).toContain('time not recorded');
  });

  it('reads nothing out of a log that is not a list', () => {
    expect(escalationEvents(alert({ escalation_log: null }))).toEqual([]);
    expect(escalationEvents(alert({ escalation_log: '[]' }))).toEqual([]);
    expect(escalationEvents(alert({ escalation_log: { at: 'x' } }))).toEqual([]);
    // A null or a bare string INSIDE the log is skipped, and the entries
    // either side of it are still read.
    const events = escalationEvents(alert({ escalation_log: [null, AUTOMATIC, 'junk', MANUAL] }));
    expect(events).toHaveLength(2);
  });

  it('gives every event an id of its own', () => {
    const events = escalationEvents(alert({ escalation_log: [AUTOMATIC, MANUAL] }));
    expect(new Set(events.map((e) => e.id)).size).toBe(2);
  });
});

describe('entryActor', () => {
  it('prefers `by`, then `by_email`, then says SYSTEM', () => {
    expect(entryActor({ by: 'SYSTEM', by_email: 'a@b.test' })).toBe('SYSTEM');
    expect(entryActor({ by_email: 'a@b.test' })).toBe('a@b.test');
    expect(entryActor({})).toBe('SYSTEM');
  });

  it('treats a blank actor as unrecorded rather than as a name', () => {
    expect(entryActor({ by: '   ', by_email: 'a@b.test' })).toBe('a@b.test');
    expect(entryActor({ by: '', by_email: '' })).toBe('SYSTEM');
    expect(entryActor({ by: 42 })).toBe('SYSTEM');
  });
});

describe('entryNotes', () => {
  it('reads an oversight entry that moved no tier', () => {
    expect(entryNotes({ action: 'ROUTED_TO_OVERSIGHT', reason: 'Complaint names a serving officer' }))
      .toContain('ROUTED TO OVERSIGHT');
  });

  it('says where an agency hand-off went', () => {
    expect(entryNotes({ from_tier: 'HQ', to_tier: 'HQ', to_agency: 'DSS' })).toContain('DSS');
  });

  it('says a statewide escalation in words, not as an LGA called ALL', () => {
    // `to_lga: 'ALL'` is the documented fail-open for an incident with no
    // measured LGA. Plateau has seventeen LGAs and none of them is ALL.
    const notes = entryNotes({ from_tier: 'LGA', to_tier: 'HQ', to_lga: 'ALL' });
    expect(notes).toContain('every LGA');
    expect(notes).not.toContain('LGA ALL');
  });

  it('never returns an empty line for an entry it cannot read', () => {
    expect(entryNotes({})).toBe('Escalation recorded');
  });
});

describe('timelineFromAlert', () => {
  it('counts a manual escalation once, not twice', () => {
    // Both clients write the log AND append a line to `ai_summary` for the
    // same escalation. Reading both shows every manual escalation twice.
    const events = timelineFromAlert(alert({
      escalation_log: [MANUAL],
      ai_summary: '[COMMAND ESCALATION] WARD -> LGA by ward.commander@operationrainbow.test\n'
        + '[ESCALATED TO LGA] No unit free in the ward',
    }));

    expect(events.filter((e) => e.type === 'ESCALATION')).toHaveLength(1);
  });

  it('still reads a multi-unit dispatch out of the summary', () => {
    // A dispatch has no structured log of its own. Inventing a record for it
    // here would be worse than reading the prose; the gap is worth closing
    // separately.
    const events = timelineFromAlert(alert({
      ai_summary: '[MULTI-UNIT DISPATCH] 3 units assigned',
    }));

    const dispatch = events.filter((e) => e.type === 'DISPATCH');
    expect(dispatch).toHaveLength(1);
    expect(dispatch[0].notes).toContain('3 units');
  });

  it('opens with the report and closes with the resolution', () => {
    const events = inOrder(timelineFromAlert(alert({
      status: 'RESOLVED',
      resolved_at: '2026-09-28T13:00:00.000Z',
      resolved_by: 'Insp. Bature Musa',
      escalation_log: [AUTOMATIC, MANUAL],
    })));

    expect(events[0].type).toBe('INITIAL_REPORT');
    expect(events[events.length - 1].type).toBe('RESOLUTION');
    expect(events.map((e) => e.type)).toEqual([
      'INITIAL_REPORT', 'ESCALATION', 'ESCALATION', 'RESOLUTION',
    ]);
  });

  it('does not invent a resolver nobody recorded', () => {
    // The panel said 'Field Commander'. T-32 was this exact fault: a screen
    // whose purpose is saying who did what, stating a fact about an actor the
    // record does not name.
    const events = timelineFromAlert(alert({ status: 'RESOLVED', resolved_at: '2026-09-28T13:00:00.000Z' }));
    const resolution = events.find((e) => e.type === 'RESOLUTION');

    expect(resolution?.actor).toBe('UNKNOWN');
  });

  it('puts the handset leaving on the timeline', () => {
    const events = timelineFromAlert(alert({ device_signed_out_at: '2026-09-28T12:05:00.000Z' }));
    const signout = events.find((e) => e.role === 'DEVICE');

    expect(signout?.timestamp).toBe('2026-09-28T12:05:00.000Z');
    expect(signout?.notes).toContain('tracking');
  });

  it('reads an alert that carries almost nothing', () => {
    const events = timelineFromAlert({});
    expect(events).toHaveLength(1);
    expect(events[0].type).toBe('INITIAL_REPORT');
    expect(events[0].actor).toBe('Citizen');
  });
});

describe('inOrder', () => {
  it('sorts oldest first', () => {
    const sorted = inOrder([
      { id: 'b', type: 'COMMUNICATION', actor: 'a', role: 'r', timestamp: '2026-09-28T12:10:00.000Z' },
      { id: 'a', type: 'INITIAL_REPORT', actor: 'a', role: 'r', timestamp: '2026-09-28T11:45:00.000Z' },
    ]);
    expect(sorted.map((e) => e.id)).toEqual(['a', 'b']);
  });

  it('puts an event with no time last, not first', () => {
    // `new Date('').getTime()` is NaN, and a NaN comparison sorts by accident.
    // A timeline that opens with the one event it could not place reads as if
    // that event happened first.
    const sorted = inOrder([
      { id: 'untimed', type: 'ESCALATION', actor: 'a', role: 'r', timestamp: '' },
      { id: 'timed', type: 'INITIAL_REPORT', actor: 'a', role: 'r', timestamp: '2026-09-28T11:45:00.000Z' },
    ]);
    expect(sorted.map((e) => e.id)).toEqual(['timed', 'untimed']);
  });

  it('leaves the list it was given alone', () => {
    const events = [
      { id: 'b', type: 'COMMUNICATION' as const, actor: 'a', role: 'r', timestamp: '2026-09-28T12:10:00.000Z' },
      { id: 'a', type: 'INITIAL_REPORT' as const, actor: 'a', role: 'r', timestamp: '2026-09-28T11:45:00.000Z' },
    ];
    inOrder(events);
    expect(events.map((e) => e.id)).toEqual(['b', 'a']);
  });
});

describe('eventStamp', () => {
  it('says the time was not recorded instead of "Invalid Date"', () => {
    const untimed = { id: 'x', type: 'ESCALATION' as const, actor: 'a', role: 'r', timestamp: '' };
    expect(eventStamp(untimed)).toBe('TIME NOT RECORDED');
    expect(eventStamp({ ...untimed, timestamp: 'last tuesday' })).toBe('TIME NOT RECORDED');
  });

  it('gives a real time for a real timestamp', () => {
    const stamp = eventStamp({
      id: 'x', type: 'ESCALATION', actor: 'a', role: 'r',
      timestamp: '2026-09-28T12:00:00.000Z',
    });
    expect(stamp).not.toBe('TIME NOT RECORDED');
    expect(stamp).toMatch(/\d/);
  });
});

describe('deliveryEvents', () => {
  const leg = (over: Record<string, unknown> = {}) => ({
    id: 'd-1',
    agency: 'POLICE',
    method: 'SMS',
    status: 'SENT',
    detail: null,
    sent_at: '2026-09-28T12:40:00.000Z',
    sent_by: 'hq@operationrainbow.test',
    ...over,
  });

  it('says what came back from each channel', () => {
    const events = deliveryEvents([
      leg({ id: 'd-1', method: 'SMS', status: 'FAILED', detail: 'HTTP 502' }),
      leg({ id: 'd-2', method: 'WEBHOOK', status: 'SKIPPED', detail: 'no POLICE_WEBHOOK_URL' }),
    ]);

    expect(events).toHaveLength(2);
    expect(events[0].notes).toContain('SMS FAILED');
    expect(events[0].notes).toContain('HTTP 502');
    // SKIPPED is not a delivery, and the wording has to keep saying so.
    expect(events[1].notes).toContain('WEBHOOK NOT USED');
    expect(events[1].notes).toContain('no POLICE_WEBHOOK_URL');
  });

  it('names the agency and who handed it over', () => {
    const [event] = deliveryEvents([leg()]);
    expect(event.actor).toBe('POLICE');
    expect(event.notes).toContain('hq@operationrainbow.test');
    expect(event.timestamp).toBe('2026-09-28T12:40:00.000Z');
  });

  it('reports a handover with NO delivery record as an event of its own', () => {
    // The silence is the finding. `escalated_to_agency` is set the moment an
    // operator presses escalate, so a timeline with no delivery line reads as
    // a handover that went perfectly.
    const events = deliveryEvents([], alert({ escalated_to_agency: 'ARMY' }));

    expect(events).toHaveLength(1);
    expect(events[0].actor).toBe('ARMY');
    expect(events[0].notes).toContain('NO delivery attempt');
  });

  it('says nothing about delivery when nothing was handed over', () => {
    expect(deliveryEvents([], alert())).toEqual([]);
    expect(deliveryEvents([], {})).toEqual([]);
  });

  it('does not invent a channel or a status it was not given', () => {
    const [event] = deliveryEvents([{ id: 'd-9', agency: null, method: null, status: null }]);
    expect(event.actor).toBe('AGENCY');
    expect(event.notes).toContain('CHANNEL UNKNOWN');
    expect(event.timestamp).toBe('');
  });

  it('places a delivery leg in order with the escalation that caused it', () => {
    const events = inOrder([
      ...escalationEvents(alert({ escalation_log: [AUTOMATIC] })),
      ...deliveryEvents([leg({ sent_at: '2026-09-28T12:40:00.000Z' })]),
    ]);
    expect(events.map((e) => e.type)).toEqual(['ESCALATION', 'AGENCY_DELIVERY']);
  });
});
