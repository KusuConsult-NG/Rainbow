// What the SMS inbound endpoint accepts, and — mostly — what it refuses.
//
// The Firebase function this replaces was unauthenticated: anyone who found
// the URL could inject an emergency. Two layers are different here, and both
// are tested, because either one alone would be insufficient:
//
//   * the GATEWAY is authenticated, so only the SMS provider can reach it;
//   * the MESSAGE is authenticated, so even a caller who gets past that cannot
//     forge an alert without a device key.
//
// And every rejection must look the same from outside, or the endpoint becomes
// an oracle for finding valid device references.
import { beforeEach, describe, expect, it, vi } from 'vitest';

import vectors from '@/lib/__fixtures__/sms_alert_vectors.json';

const cases = vectors.cases as Record<string, string>;
const keyHex = Buffer.from(vectors.keyBase64, 'base64').toString('hex');

const inserted: Record<string, unknown>[] = [];
let existingRows: unknown[] = [];
let keyRows: unknown[] = [];

vi.mock('@/lib/supabase-server', () => ({
  getSupabaseAdmin: () => ({
    rpc: async () => ({ data: keyRows, error: null }),
    from: () => ({
      select: () => ({
        eq: () => ({
          like: () => ({
            limit: async () => ({ data: existingRows, error: null }),
          }),
        }),
      }),
      insert: async (values: Record<string, unknown>) => {
        inserted.push(values);
        return { error: null };
      },
    }),
  }),
}));

async function post(body: unknown, secret = 'right-secret') {
  const { POST } = await import('./route');
  const req = new Request('http://localhost/api/sms/inbound', {
    method: 'POST',
    headers: { 'x-gateway-secret': secret, 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
  const res = await POST(req as unknown as Parameters<typeof POST>[0]);
  return { status: res.status, json: await res.json() };
}

describe('the SMS inbound endpoint', () => {
  beforeEach(() => {
    inserted.length = 0;
    existingRows = [];
    keyRows = [{ user_id: 'citizen-uuid', secret: `\\x${keyHex}` }];
    process.env.SMS_GATEWAY_SECRET = 'right-secret';
  });

  describe('accepting a real alert', () => {
    it('records one, with the right type and severity', async () => {
      const r = await post({ text: cases.ordinary, msisdn: '+2348000000000' });
      expect(r.json.accepted).toBe(true);
      expect(inserted).toHaveLength(1);
      expect(inserted[0].type).toBe('Community attack');
      expect(inserted[0].severity).toBe('CRITICAL');
      expect(inserted[0].arrived_via).toBe('SMS');
    });

    it('uses WHEN THE PHONE RAISED IT as created_at', async () => {
      // An SMS can sit in a carrier queue for minutes. A dispatcher must not
      // read a ten-minute-old kidnapping as new.
      await post({ text: cases.ordinary });
      expect(inserted[0].created_at).toBe(vectors.sentAtIso);
    });

    it('carries the position', async () => {
      await post({ text: cases.ordinary });
      expect(inserted[0].latitude).toBeCloseTo(9.89654, 5);
      expect(inserted[0].longitude).toBeCloseTo(8.85831, 5);
    });

    it('a duress alert is recorded as CRITICAL and says so', async () => {
      await post({ text: cases.duress });
      expect(inserted[0].severity).toBe('CRITICAL');
      expect(String(inserted[0].description)).toContain('DURESS');
    });

    it('no GPS fix stays no fix, rather than becoming the Atlantic', async () => {
      await post({ text: cases.noFix });
      expect(inserted[0].latitude).toBeNull();
      expect(inserted[0].longitude).toBeNull();
    });

    it('an anonymous report is not attributed to its reporter', async () => {
      await post({ text: cases.anonymous });
      expect(inserted[0].reported_by).toBeNull();
    });

    it('marks the channel, so the board can show it arrived degraded', async () => {
      await post({ text: cases.ordinary });
      expect(inserted[0].arrived_via).toBe('SMS');
    });
  });

  describe('refusing everything else', () => {
    it('refuses a wrong gateway secret', async () => {
      const r = await post({ text: cases.ordinary }, 'wrong');
      expect(inserted).toHaveLength(0);
      expect(r.json.accepted).toBeUndefined();
    });

    it('refuses when the gateway secret is not configured at all', async () => {
      // Rather than accepting everything, which is how the function this
      // replaces behaved.
      process.env.SMS_GATEWAY_SECRET = '';
      await post({ text: cases.ordinary }, '');
      expect(inserted).toHaveLength(0);
    });

    it('refuses a message signed with a key we do not hold', async () => {
      keyRows = [{ user_id: 'someone', secret: `\\x${'11'.repeat(32)}` }];
      await post({ text: cases.ordinary });
      expect(inserted).toHaveLength(0);
    });

    it('refuses an unknown device ref', async () => {
      keyRows = [];
      await post({ text: cases.ordinary });
      expect(inserted).toHaveLength(0);
    });

    it('refuses a tampered body — HQ cannot be fed a forgery', async () => {
      const t = `${cases.ordinary.slice(0, -2)}AA`;
      await post({ text: t });
      expect(inserted).toHaveLength(0);
    });

    it('ignores a message that is not ours', async () => {
      await post({ text: 'hello mum' });
      expect(inserted).toHaveLength(0);
    });

    it('ignores a body that is not a string', async () => {
      await post({ text: 42 });
      expect(inserted).toHaveLength(0);
    });

    it('every refusal answers the same, so this is not an oracle', async () => {
      // Distinguishable rejections would let an attacker search for valid
      // device references, or confirm that a given handset is registered.
      const answers: string[] = [];
      answers.push(JSON.stringify((await post({ text: cases.ordinary }, 'wrong')).json));
      keyRows = [];
      answers.push(JSON.stringify((await post({ text: cases.ordinary })).json));
      answers.push(JSON.stringify((await post({ text: 'rubbish' })).json));
      answers.push(JSON.stringify((await post({ text: 42 })).json));
      expect(new Set(answers).size).toBe(1);
      expect(answers[0]).toBe('{"ok":true}');
    });

    it('answers 200 even on refusal, so a gateway does not retry-storm', async () => {
      const r = await post({ text: 'rubbish' });
      expect(r.status).toBe(200);
    });
  });

  describe('not recording the same emergency twice', () => {
    it('drops a report the phone already delivered by data', async () => {
      // The commonest duplicate: the SMS arrives, then the handset regains
      // data and replays its offline queue. Two units to one incident, and
      // none to the next one.
      existingRows = [{ id: 'already-here' }];
      const r = await post({ text: cases.ordinary });
      expect(r.json.duplicate).toBe(true);
      expect(inserted).toHaveLength(0);
    });

    it('records the local ref so the queue can be matched against it', async () => {
      await post({ text: cases.ordinary });
      expect(inserted[0].local_id).toBe(vectors.localRefHex);
    });
  });
});
