// Handing an incident to an outside agency.
//
// Two separate things had to be true for an escalation to the Police to reach
// nobody and be reported as sent, and both were:
//
//   1. the escalation menu submitted 'NPF', which this route does not know, so
//      it answered 400 — and the caller discarded the response;
//   2. with no contact details configured at all, the route's own verdict was
//      `success: true`, because it counted SKIPPED as a success.
//
// The second is the one with teeth: it is what a correctly-named escalation
// would have hit on this deployment today, where every liaison phone and
// webhook URL is blank.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { AGENCY_CODES } from '@/lib/agencies';

interface Inserted { table: string; row: Record<string, unknown> }

const inserted: Inserted[] = [];
let authorised: { ok: true; userId: string; role: string } | { ok: false; status: number; error: string } =
  { ok: true, userId: 'hq-1', role: 'HQ_COMMAND' };

vi.mock('@/lib/supabase-server', () => ({
  COMMAND_ROLES: ['HQ_COMMAND'],
  requireRole: async () => authorised,
  getSupabaseAdmin: () => ({
    from: (table: string) => ({
      insert: (row: Record<string, unknown>) => ({
        then: (resolve: (r: { error: null }) => unknown) => {
          inserted.push({ table, row });
          return Promise.resolve(resolve({ error: null }));
        },
      }),
    }),
  }),
}));

let env: Record<string, string>;
vi.mock('@/lib/env', () => ({
  serverEnv: () => ({
    termiiApiKey: env.termiiApiKey ?? '',
    termiiSenderId: 'OE Alert',
    webhookSecret: env.webhookSecret ?? '',
  }),
}));

const ALERT = 'aaaaaaaa-1111-4111-8111-111111111111';

async function notify(body: Record<string, unknown>) {
  const { POST } = await import('./route');
  const res = await POST(new Request('http://localhost/api/notify-agency', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  }) as never);
  return { res, body: await res.json() };
}

const CONTACT_VARS = AGENCY_CODES.flatMap(c => [`${c}_LIAISON_PHONE`, `${c}_WEBHOOK_URL`]);

beforeEach(() => {
  vi.resetModules();
  inserted.length = 0;
  env = {};
  authorised = { ok: true, userId: 'hq-1', role: 'HQ_COMMAND' };
  // A real deployment's variables must not decide what these assert.
  for (const v of CONTACT_VARS) delete process.env[v];
  vi.spyOn(globalThis, 'fetch').mockResolvedValue(
    new Response(JSON.stringify({ message_id: 'm-1' }), { status: 200 }),
  );
});

afterEach(() => {
  vi.restoreAllMocks();
  for (const v of CONTACT_VARS) delete process.env[v];
});

describe('which agencies exist', () => {
  // The regression that started this. 'NPF' was what the console's own
  // escalation menu submitted for the Nigeria Police Force.
  it.each(['NPF', 'MILITARY', 'RAINBOW', 'VGN', 'AMOTEKUN'])(
    'refuses %s, which is not an agency this system can reach',
    async (agency) => {
      const { res, body } = await notify({ alertId: ALERT, agency });
      expect(res.status).toBe(400);
      expect(body.error).toContain('Unknown agency');
      // And nothing was recorded as having been attempted.
      expect(inserted).toHaveLength(0);
    },
  );

  it.each([...AGENCY_CODES])('accepts %s — every code the console can escalate to', async (agency) => {
    const { res } = await notify({ alertId: ALERT, agency });
    expect(res.status).not.toBe(400);
  });

  it('reads the contact details for the agency it was given, by that code', async () => {
    process.env.FRSC_LIAISON_PHONE = '+2348000000001';
    process.env.POLICE_LIAISON_PHONE = '+2348000000002';
    env.termiiApiKey = 'termii-key';

    await notify({ alertId: ALERT, agency: 'FRSC' });

    const call = vi.mocked(globalThis.fetch).mock.calls[0];
    expect(String(call[0])).toContain('termii.com');
    expect(JSON.parse(String((call[1] as RequestInit).body)).to).toBe('+2348000000001');
  });

  it('is case-insensitive about the code, as the old route was', async () => {
    const { res } = await notify({ alertId: ALERT, agency: 'police' });
    expect(res.status).not.toBe(400);
  });
});

describe('never calling nothing a delivery', () => {
  it('reports NOT DELIVERED when the deployment has no contact details at all', async () => {
    const { res, body } = await notify({ alertId: ALERT, agency: 'POLICE' });

    expect(body.delivered).toBe(false);
    expect(res.status).toBe(503);
    expect(globalThis.fetch).not.toHaveBeenCalled();
    // The detail has to be actionable: it names the agency and the variables.
    expect(body.detail).toContain('Nigeria Police Force');
    expect(body.detail).toContain('POLICE_LIAISON_PHONE');
    expect(body.detail).toContain('POLICE_WEBHOOK_URL');
  });

  it('records BOTH skipped channels, so the audit row set says what was not used', async () => {
    await notify({ alertId: ALERT, agency: 'ARMY' });

    const methods = inserted.map(i => `${i.row.method}:${i.row.status}`);
    expect(methods).toEqual(['SMS:SKIPPED', 'WEBHOOK:SKIPPED']);
    expect(inserted.every(i => i.table === 'agency_notifications')).toBe(true);
    expect(inserted.every(i => i.row.agency === 'ARMY')).toBe(true);
  });

  it('says so when the phone is there and the Termii key is not', async () => {
    process.env.ARMY_LIAISON_PHONE = '+2348000000003';
    const { body } = await notify({ alertId: ALERT, agency: 'ARMY' });
    expect(body.results.find((r: { method: string }) => r.method === 'SMS').detail)
      .toBe('no TERMII_API_KEY');
  });

  it('says so when the Termii key is there and the phone is not', async () => {
    env.termiiApiKey = 'termii-key';
    const { body } = await notify({ alertId: ALERT, agency: 'ARMY' });
    expect(body.results.find((r: { method: string }) => r.method === 'SMS').detail)
      .toBe('no ARMY_LIAISON_PHONE');
  });

  // The contacts used to be a module-level const, so the SECOND request in one
  // server lifetime saw the first request's environment. A number added in the
  // Railway variables looked applied and was not.
  it('picks up a contact number added after the first request', async () => {
    const { body: first } = await notify({ alertId: ALERT, agency: 'FRSC' });
    expect(first.delivered).toBe(false);

    process.env.FRSC_LIAISON_PHONE = '+2348000000005';
    env.termiiApiKey = 'termii-key';
    const { body: second } = await notify({ alertId: ALERT, agency: 'FRSC' });
    expect(second.delivered).toBe(true);
  });

  it('reports DELIVERED when the one configured channel actually sent', async () => {
    process.env.POLICE_LIAISON_PHONE = '+2348000000002';
    env.termiiApiKey = 'termii-key';

    const { res, body } = await notify({ alertId: ALERT, agency: 'POLICE' });

    expect(body.delivered).toBe(true);
    expect(res.status).toBe(200);
    expect(body.detail).toContain('notified by SMS');
  });

  it('reports NOT DELIVERED when the provider refuses', async () => {
    process.env.POLICE_LIAISON_PHONE = '+2348000000002';
    env.termiiApiKey = 'termii-key';
    vi.mocked(globalThis.fetch).mockResolvedValue(
      new Response(JSON.stringify({ message: 'insufficient balance' }), { status: 402 }),
    );

    const { res, body } = await notify({ alertId: ALERT, agency: 'POLICE' });

    expect(body.delivered).toBe(false);
    expect(res.status).toBe(502);
    expect(body.detail).toContain('insufficient balance');
  });

  it('is still DELIVERED when one channel sends and the other is merely unconfigured', async () => {
    process.env.DSS_LIAISON_PHONE = '+2348000000004';
    env.termiiApiKey = 'termii-key';

    const { res, body } = await notify({ alertId: ALERT, agency: 'DSS' });

    expect(body.delivered).toBe(true);
    expect(res.status).toBe(200);
  });

  it('is PARTIAL — not success — when one channel sends and the other fails', async () => {
    process.env.DSS_LIAISON_PHONE = '+2348000000004';
    process.env.DSS_WEBHOOK_URL = 'https://dss.example.test/hook';
    env.termiiApiKey = 'termii-key';
    env.webhookSecret = 'a-shared-secret';
    vi.mocked(globalThis.fetch).mockImplementation(async (input) =>
      String(input).includes('termii')
        ? new Response(JSON.stringify({ message_id: 'm-1' }), { status: 200 })
        : new Response('nope', { status: 500 }));

    const { res, body } = await notify({ alertId: ALERT, agency: 'DSS' });

    expect(body.delivered).toBe(true);
    expect(res.status).toBe(207);
    expect(body.detail).toContain('WEBHOOK failed');
  });
});

describe('the webhook is signed or it is not sent', () => {
  it('refuses to POST an escalation with no shared secret', async () => {
    process.env.OPSH_WEBHOOK_URL = 'https://opsh.example.test/hook';

    const { res, body } = await notify({ alertId: ALERT, agency: 'OPSH' });

    expect(globalThis.fetch).not.toHaveBeenCalled();
    expect(body.delivered).toBe(false);
    expect(res.status).toBe(502);
    const webhook = body.results.find((r: { method: string }) => r.method === 'WEBHOOK');
    expect(webhook.status).toBe('FAILED');
    expect(webhook.detail).toContain('RAINBOW_WEBHOOK_SECRET');
  });

  it('signs the webhook when the secret is configured', async () => {
    process.env.OPSH_WEBHOOK_URL = 'https://opsh.example.test/hook';
    env.webhookSecret = 'a-shared-secret';

    const { body } = await notify({ alertId: ALERT, agency: 'OPSH', targetLga: 'JOS SOUTH' });

    const call = vi.mocked(globalThis.fetch).mock.calls[0];
    expect(String(call[0])).toBe('https://opsh.example.test/hook');
    const headers = (call[1] as RequestInit).headers as Record<string, string>;
    expect(headers['X-Rainbow-Auth']).toBe('a-shared-secret');
    const sent = JSON.parse(String((call[1] as RequestInit).body));
    expect(sent.agency).toBe('OPSH');
    expect(sent.alert_id).toBe(ALERT);
    expect(body.delivered).toBe(true);
  });
});

describe('getting in', () => {
  it('refuses an unauthenticated caller before reading the body', async () => {
    authorised = { ok: false, status: 401, error: 'Authentication required' };
    const { res } = await notify({ alertId: ALERT, agency: 'POLICE' });
    expect(res.status).toBe(401);
    expect(inserted).toHaveLength(0);
  });

  it('requires an alert and an agency', async () => {
    const { res } = await notify({ agency: 'POLICE' });
    expect(res.status).toBe(400);
  });
});
