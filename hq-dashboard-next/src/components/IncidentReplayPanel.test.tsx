// The forensic replay of one incident.
//
// This panel built its escalation events by string-matching `ai_summary`, so
// the timeline showed the escalations SOMEBODY TYPED and none of the ones a
// timer performed. `escalate_overdue_alerts()` appends to `escalation_log` and
// never touches the summary, so an incident that climbed at 02:00 because
// nobody answered — the escalation a review most wants to see — appeared
// nowhere on the replay of the incident it happened to. The Audit History
// screen showed it, because `audit_trail()` reads the log.
//
// Three more followed from reading prose instead of the record: every
// escalation carried `updated_at`, so an incident that climbed UNIT → WARD →
// LGA produced three events with one time and no order; the actor was the
// literal 'Tactical Command' while the log names who did it (T-32 was this
// exact fault in `audit_trail()`); and a manual escalation, which both clients
// write to the log AND append to the summary, would have shown twice if the
// prose parse had simply been added to.
//
// Six of these fail against that version.
import { render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { makeSupabaseStub, type SupabaseStub } from '@/test/supabase-stub';

let db: SupabaseStub;

vi.mock('@/lib/supabase', () => ({
  get supabase() {
    return db.client;
  },
}));

vi.mock('../lib/alert-actions', () => ({
  sendChatMessage: vi.fn().mockResolvedValue({ ok: true }),
}));

const ALERT_ID = '7f3c9a10-1111-2222-3333-444455556666';

// The row as the database holds it: `escalation_log` is jsonb, and PostgREST
// hands it back as a parsed array.
const ALERT = {
  id: ALERT_ID,
  type: 'ARMED_ROBBERY',
  description: 'Three men, one vehicle, Naraguta junction.',
  status: 'ESCALATED',
  reported_by: 'bbbb2222-0000-4000-8000-00000000b001',
  created_at: '2026-09-28T11:45:00.000Z',
  updated_at: '2026-09-28T12:30:00.000Z',
  ai_summary: null as string | null,
  escalation_log: [] as unknown[],
};

const TIMED_OUT = {
  at: '2026-09-28T12:00:00.000Z',
  from_tier: 'UNIT',
  to_tier: 'WARD',
  by: 'SYSTEM',
  reason: 'SLA breach: unacknowledged for 10 minutes',
};

const BY_HAND = {
  at: '2026-09-28T12:15:00.000Z',
  from_tier: 'WARD',
  to_tier: 'LGA',
  by_email: 'ward.commander@operationrainbow.test',
  reason: 'No unit free in the ward',
};

async function load() {
  return (await import('./IncidentReplayPanel')).default;
}

function mount(Panel: Awaited<ReturnType<typeof load>>) {
  return render(<Panel alertId={ALERT_ID} />);
}

beforeEach(() => {
  db = makeSupabaseStub();
  db.setRows('alerts', [ALERT]);
  db.setRows('chat_messages', []);
  db.setRows('agency_notifications', []);
});

describe('escalations the record holds', () => {
  it('shows an escalation that only the log records', async () => {
    db.setRows('alerts', [{ ...ALERT, escalation_log: [TIMED_OUT] }]);
    const Panel = await load();
    mount(Panel);

    expect(await screen.findByText(/SLA breach/)).toBeTruthy();
    expect(screen.getByText(/UNIT → WARD/)).toBeTruthy();
  });

  it('names who escalated instead of crediting Tactical Command', async () => {
    db.setRows('alerts', [{ ...ALERT, escalation_log: [TIMED_OUT, BY_HAND] }]);
    const Panel = await load();
    const { container } = mount(Panel);

    await screen.findByText(/SLA breach/);
    expect(container.textContent).toContain('ward.commander@operationrainbow.test');
    expect(container.textContent).not.toContain('Tactical Command');
  });

  it('gives each escalation its own clock', async () => {
    db.setRows('alerts', [{ ...ALERT, escalation_log: [TIMED_OUT, BY_HAND] }]);
    const Panel = await load();
    const { container } = mount(Panel);

    await screen.findByText(/SLA breach/);
    const stamps = [...container.querySelectorAll('span')]
      .map((s) => s.textContent ?? '')
      .filter((t) => /^\[\d/.test(t.trim()))
      .map((t) => t.trim().slice(0, t.indexOf(']') + 1));
    // Two escalations plus the initial report: three distinct times, not one
    // `updated_at` repeated.
    expect(new Set(stamps).size).toBeGreaterThanOrEqual(3);
  });

  it('counts a manual escalation once, although it is in the log AND the summary', async () => {
    db.setRows('alerts', [{
      ...ALERT,
      escalation_log: [BY_HAND],
      ai_summary: '[COMMAND ESCALATION] WARD -> LGA\n[ESCALATED TO LGA] No unit free in the ward',
    }]);
    const Panel = await load();
    mount(Panel);

    // The heading counts the events: report + one escalation.
    expect(await screen.findByText(/Incident Replay Log \(2\)/)).toBeTruthy();
  });

  it('still shows a multi-unit dispatch, which has no log of its own', async () => {
    db.setRows('alerts', [{ ...ALERT, ai_summary: '[MULTI-UNIT DISPATCH] 3 units assigned' }]);
    const Panel = await load();
    mount(Panel);

    expect(await screen.findByText(/3 units assigned/)).toBeTruthy();
  });

  it('says TIME NOT RECORDED rather than rendering "Invalid Date"', async () => {
    // An entry with no `at` and an alert with no `updated_at` leaves nothing to
    // place the event by. `new Date('').toLocaleTimeString()` is the string
    // "Invalid Date", which reads as a broken console rather than a gap in the
    // record.
    db.setRows('alerts', [{
      ...ALERT,
      created_at: null,
      updated_at: null,
      escalation_log: [{ from_tier: 'UNIT', to_tier: 'WARD', by: 'SYSTEM' }],
    }]);
    const Panel = await load();
    const { container } = mount(Panel);

    // Said twice on purpose: in the clock position, where a time would be,
    // and in the note that explains where the event was placed.
    await screen.findByText(/\[TIME NOT RECORDED\]/);
    expect(container.textContent).toContain('time not recorded, placed by last update');
    expect(container.textContent).not.toContain('Invalid Date');
  });
});

describe('the rest of the timeline', () => {
  it('keeps the chat messages, in order with the escalations', async () => {
    db.setRows('alerts', [{ ...ALERT, escalation_log: [TIMED_OUT] }]);
    db.setRows('chat_messages', [{
      id: 'chat-1',
      alert_id: ALERT_ID,
      sender_name: 'ASP Danjuma Iliya',
      sender_role: 'WARD_COMMANDER',
      message: 'Two units moving from Naraguta B.',
      created_at: '2026-09-28T12:05:00.000Z',
    }]);
    const Panel = await load();
    const { container } = mount(Panel);

    await screen.findByText(/Two units moving/);
    const order = container.textContent ?? '';
    // The escalation at 12:00 is above the message at 12:05.
    expect(order.indexOf('SLA breach')).toBeLessThan(order.indexOf('Two units moving'));
  });

  it('does not invent a resolver nobody recorded', async () => {
    db.setRows('alerts', [{
      ...ALERT,
      status: 'RESOLVED',
      resolved_at: '2026-09-28T13:00:00.000Z',
      resolved_by: null,
    }]);
    const Panel = await load();
    const { container } = mount(Panel);

    await screen.findByText(/RESOLVED and archived/);
    expect(container.textContent).not.toContain('Field Commander');
  });

  it('says so when there is nothing to show', async () => {
    db.setRows('alerts', []);
    const Panel = await load();
    mount(Panel);

    await waitFor(() => expect(screen.getByText(/No recorded timeline events/)).toBeTruthy());
  });
});

// Whether the Police, the Army or the DSS were actually told.
//
// `/api/notify-agency` writes one `agency_notifications` row per channel,
// including the ones it skipped, and NOTHING read them. The console shows a
// handover as done the moment an operator presses escalate — that is what
// `escalated_to_agency` records — so "handed to the Army" and "the Army was
// told" were the same line on the screen and different facts in the database.
describe('whether the agency was told', () => {
  const leg = (over: Record<string, unknown> = {}) => ({
    id: 'd-1',
    alert_id: ALERT_ID,
    agency: 'POLICE',
    method: 'SMS',
    status: 'SENT',
    detail: null,
    sent_at: '2026-09-28T12:40:00.000Z',
    sent_by: 'hq@operationrainbow.test',
    ...over,
  });

  it('shows a failed handover with what the gateway said', async () => {
    db.setRows('agency_notifications', [
      leg({ id: 'd-1', status: 'FAILED', detail: 'HTTP 502' }),
      leg({ id: 'd-2', method: 'WEBHOOK', status: 'SKIPPED', detail: 'no POLICE_WEBHOOK_URL' }),
    ]);
    const Panel = await load();
    const { container } = mount(Panel);

    await screen.findByText(/SMS FAILED/);
    expect(container.textContent).toContain('HTTP 502');
    expect(container.textContent).toContain('WEBHOOK NOT USED');
  });

  it('says so when a handover has no delivery record at all', async () => {
    db.setRows('alerts', [{ ...ALERT, escalated_to_agency: 'ARMY' }]);
    db.setRows('agency_notifications', []);
    const Panel = await load();
    mount(Panel);

    expect(await screen.findByText(/NO delivery attempt is on record/)).toBeTruthy();
  });

  it('says the delivery log could not be read, rather than showing none', async () => {
    // A timeline missing its delivery lines because the read was refused looks
    // exactly like a handover that went perfectly. An empty board that could
    // not ask is the same lie as an empty board.
    db.setRows('alerts', [{ ...ALERT, escalated_to_agency: 'ARMY' }]);
    db.setError('agency_notifications', { message: 'permission denied for table agency_notifications' });
    const Panel = await load();
    mount(Panel);

    const said = await screen.findByRole('status');
    expect(said.textContent).toContain('AGENCY DELIVERY LOG NOT READ');
    expect(said.textContent).toContain('permission denied');
    // And it must NOT claim the handover had no attempt, which is the opposite
    // conclusion from the same blank.
    expect(screen.queryByText(/NO delivery attempt is on record/)).toBeNull();
  });

  it('stays quiet about a refused read when nothing was handed over', async () => {
    // The read is command-only, so on a ward commander's screen it is refused
    // for EVERY incident. A warning that fires on every incident is a warning
    // people stop reading, and with no handover the refusal hides nothing.
    db.setError('agency_notifications', { message: 'permission denied' });
    const Panel = await load();
    mount(Panel);

    await screen.findByText(/Alert initiated/);
    expect(screen.queryByRole('status')).toBeNull();
  });

  it('says nothing about delivery for an incident nobody handed over', async () => {
    const Panel = await load();
    const { container } = mount(Panel);

    await screen.findByText(/Alert initiated/);
    expect(container.textContent).not.toContain('AGENCY_DELIVERY');
    expect(screen.queryByRole('status')).toBeNull();
  });
});
