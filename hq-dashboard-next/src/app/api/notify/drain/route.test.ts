// Draining the notification queue.
//
// The database guarantees that an escalation cannot happen without its notice
// being queued — the UPDATE and the INSERT are one statement. This endpoint is
// the other half, and the thing it must never do is mark a row delivered when
// nobody was told: that reproduces the silence the outbox exists to end, one
// layer further out where it is harder to see.
import { beforeEach, describe, expect, it, vi } from 'vitest';

interface RpcCall { fn: string; args: Record<string, unknown> }

const rpcCalls: RpcCall[] = [];
let claimed: unknown[] = [];
let officers: unknown[] = [];

vi.mock('@/lib/supabase-server', () => ({
  getSupabaseAdmin: () => ({
    rpc: async (fn: string, args: Record<string, unknown>) => {
      rpcCalls.push({ fn, args });
      if (fn === 'claim_notifications') return { data: claimed, error: null };
      return { data: null, error: null };
    },
    from: () => ({
      select: () => ({
        in: async () => ({ data: officers, error: null }),
      }),
    }),
  }),
}));

vi.mock('@/lib/env', () => ({
  serverEnv: () => ({
    oneSignalAppId: 'app-id',
    oneSignalRestKey: 'rest-key',
  }),
}));

const SECRET = 'a-long-shared-secret-value';

async function drain(headers: Record<string, string> = { 'x-drain-secret': SECRET }) {
  const { POST } = await import('./route');
  return POST(new Request('http://localhost/api/notify/drain', { method: 'POST', headers }));
}

const NOTICE = {
  id: 7,
  alert_id: 'aaaaaaaa-1111-4111-8111-111111111111',
  kind: 'TIER_ESCALATION',
  payload: {
    alert_id: 'aaaaaaaa-1111-4111-8111-111111111111',
    from_tier: 'UNIT',
    to_tier: 'WARD',
    geo_lga: 'JOS NORTH',
    geo_ward: 'NARAGUTA',
    severity: 'CRITICAL',
  },
};

const WARD_OFFICER = {
  id: 'w1',
  role: 'WARD_COMMAND',
  geo_lga: 'JOS NORTH',
  geo_ward: 'NARAGUTA',
  onesignal_player_id: 'player-abc-123456',
};

const sentFor = (id: number) =>
  rpcCalls.filter(c => c.fn === 'mark_notification_sent' && c.args.p_id === id);
const failedFor = (id: number) =>
  rpcCalls.filter(c => c.fn === 'mark_notification_failed' && c.args.p_id === id);

beforeEach(() => {
  vi.resetModules();
  rpcCalls.length = 0;
  claimed = [];
  officers = [];
  process.env.NOTIFY_DRAIN_SECRET = SECRET;
  vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response('{}', { status: 200 }));
});

describe('getting in', () => {
  it('refuses a request with no secret', async () => {
    const res = await drain({});
    expect(res.status).toBe(401);
    expect(rpcCalls).toHaveLength(0);
  });

  it('refuses a wrong secret', async () => {
    const res = await drain({ 'x-drain-secret': 'not-the-secret-value-xx' });
    expect(res.status).toBe(401);
  });

  it('refuses to run at all when no secret is configured', async () => {
    // An open drain endpoint lets anyone empty the queue: every row marked
    // delivered, nobody notified. Refusing is the safe direction.
    delete process.env.NOTIFY_DRAIN_SECRET;
    const res = await drain();
    expect(res.status).toBe(503);
    expect(rpcCalls).toHaveLength(0);
  });

  it('lets the right secret through', async () => {
    const res = await drain();
    expect(res.status).toBe(200);
    expect(rpcCalls[0].fn).toBe('claim_notifications');
  });
});

describe('an empty queue', () => {
  it('is not an error, and sends nothing', async () => {
    const res = await drain();
    expect(await res.json()).toMatchObject({ ok: true, claimed: 0, sent: 0 });
    expect(globalThis.fetch).not.toHaveBeenCalled();
  });
});

describe('a queued escalation', () => {
  it('reaches the officers at the tier it landed on', async () => {
    claimed = [NOTICE];
    officers = [WARD_OFFICER];

    const res = await drain();

    expect(await res.json()).toMatchObject({ claimed: 1, sent: 1 });
    expect(globalThis.fetch).toHaveBeenCalledWith(
      'https://onesignal.com/api/v1/notifications',
      expect.objectContaining({ method: 'POST' }),
    );
    const body = JSON.parse(
      ((globalThis.fetch as unknown as { mock: { calls: unknown[][] } })
        .mock.calls[0][1] as RequestInit).body as string,
    );
    expect(body.include_player_ids).toEqual(['player-abc-123456']);
    expect(body.headings.en).toContain('WARD');
    expect(sentFor(7)).toHaveLength(1);
  });

  it('is not sent to an officer in a different ward', async () => {
    claimed = [NOTICE];
    officers = [{ ...WARD_OFFICER, id: 'w9', geo_ward: 'GANGARE' }];

    await drain();

    expect(globalThis.fetch).not.toHaveBeenCalled();
    expect(sentFor(7)).toHaveLength(0);
  });
});

describe('when nobody can be reached', () => {
  it('records a failure rather than marking it delivered', async () => {
    // The defect this whole mechanism exists to prevent, reproduced one layer
    // out: the row would say sent, and nobody would have been told.
    claimed = [NOTICE];
    officers = [];

    const res = await drain();

    expect(sentFor(7)).toHaveLength(0);
    expect(failedFor(7)).toHaveLength(1);
    expect(String(failedFor(7)[0].args.p_error)).toContain('WARD');
    expect(await res.json()).toMatchObject({ noRecipients: 1 });
  });

  it('says so differently when the officer exists but has no push subscription', async () => {
    // Two different problems needing two different actions: nobody is posted
    // there, or the person has not opened the app on this handset.
    claimed = [NOTICE];
    officers = [{ ...WARD_OFFICER, onesignal_player_id: null }];

    await drain();

    expect(failedFor(7)).toHaveLength(1);
    expect(String(failedFor(7)[0].args.p_error)).toContain('no push subscription');
  });
});

describe('when the send itself fails', () => {
  it("records the provider's answer and does not mark it sent", async () => {
    claimed = [NOTICE];
    officers = [WARD_OFFICER];
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      new Response('rate limited', { status: 429 }),
    );

    await drain();

    expect(sentFor(7)).toHaveLength(0);
    expect(String(failedFor(7)[0].args.p_error)).toContain('429');
  });

  it('one bad row does not abandon the rest of the batch', async () => {
    // The others are emergencies waiting to be handed on.
    claimed = [NOTICE, { ...NOTICE, id: 8 }];
    officers = [WARD_OFFICER];
    let call = 0;
    vi.spyOn(globalThis, 'fetch').mockImplementation(async () => {
      call += 1;
      if (call === 1) throw new Error('socket hang up');
      return new Response('{}', { status: 200 });
    });

    const res = await drain();

    expect(failedFor(7)).toHaveLength(1);
    expect(sentFor(8)).toHaveLength(1);
    expect(await res.json()).toMatchObject({ claimed: 2, sent: 1, failed: 1 });
  });
});

describe('a notice addressed to a tier nobody holds', () => {
  it('is recorded and stopped, not retried for ever', async () => {
    claimed = [{ ...NOTICE, payload: { ...NOTICE.payload, to_tier: 'ATLANTIS' } }];

    await drain();

    expect(globalThis.fetch).not.toHaveBeenCalled();
    expect(String(failedFor(7)[0].args.p_error)).toContain('ATLANTIS');
  });
});
