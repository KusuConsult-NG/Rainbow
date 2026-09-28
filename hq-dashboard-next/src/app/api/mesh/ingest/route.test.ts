// The one endpoint here that cannot ask who is calling.
//
// During a network shutdown the phone that gets a signal back first may be a
// stranger's, signed out, or carrying a token that expired days ago. So this
// route is an unauthenticated write path into an emergency system, and these
// tests are mostly about what that means: what an anonymous caller can and
// cannot make HQ believe, how much of our time they can waste, and what the
// response tells them about the frames they uploaded.
//
// Every frame used here was sealed by the Dart app
// (`test/gen_mesh_vectors_test.dart`), so this exercises the real crypto and the
// real wire format rather than a fixture written to match the handler.
import { beforeEach, describe, expect, it, vi } from 'vitest';

import meshVectors from '@/lib/__fixtures__/mesh_envelope_vectors.json';
import smsVectors from '@/lib/__fixtures__/sms_alert_vectors.json';

const frames = meshVectors.frames as Record<string, string>;
const ids = meshVectors.ids as Record<string, string>;
const keyHex = Buffer.from(smsVectors.keyBase64, 'base64').toString('hex');

const inserted: Record<string, unknown>[] = [];
let existingRows: unknown[] = [];
let keyRows: unknown[] = [];
/** Envelope ids this fake HQ has already seen. */
let seen = new Set<string>();
let dedupFails = false;

vi.mock('@/lib/supabase-server', () => ({
  getSupabaseAdmin: () => ({
    rpc: async (fn: string, args: Record<string, string>) => {
      if (fn === 'mesh_note_envelope') {
        if (dedupFails) return { data: null, error: { message: 'unavailable' } };
        const id = String(args.p_id).replace(/^\\x/, '');
        const isNew = !seen.has(id);
        seen.add(id);
        return { data: isNew, error: null };
      }
      return { data: keyRows, error: null };
    },
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

async function post(
  body: unknown,
  headers: Record<string, string> = {},
): Promise<{ status: number; json: { ok?: boolean; done?: string[] } }> {
  const { POST } = await import('./route');
  const req = new Request('http://localhost/api/mesh/ingest', {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...headers },
    body: typeof body === 'string' ? body : JSON.stringify(body),
  });
  const res = await POST(req as unknown as Parameters<typeof POST>[0]);
  return { status: res.status, json: await res.json() };
}

/** Rewrites a frame's own timestamp, leaving the sealed body untouched. */
function frameAgedBy(name: string, ms: number): string {
  const raw = Buffer.from(frames[name], 'base64url');
  const was = Number(raw.readBigUInt64BE(18));
  raw.writeBigUInt64BE(BigInt(was - ms), 18);
  return raw.toString('base64url');
}

beforeEach(async () => {
  inserted.length = 0;
  existingRows = [];
  keyRows = [{ user_id: 'citizen-uuid', secret: `\\x${keyHex}` }];
  seen = new Set();
  dedupFails = false;
  process.env.MESH_HQ_PRIVATE_KEY = meshVectors.hqPrivateKeyHex;
  // The rate limiter is module state and outlives a single test, which is the
  // point of it. Tests must not inherit each other's budget.
  const { __resetMeshRateLimit } = await import('./route');
  __resetMeshRateLimit();
  // The frames were sealed at a fixed instant; without this the freshness check
  // would reject every one of them by 2027.
  vi.setSystemTime(new Date(meshVectors.createdAtIso).getTime() + 30 * 60_000);
});

describe('an alert that crossed a crowd to get here', () => {
  it('is recorded, once, with no session of any kind', async () => {
    const r = await post({ frames: [frames.ordinary] });
    expect(r.status).toBe(200);
    expect(inserted).toHaveLength(1);
    expect(inserted[0].type).toBe('Community attack');
    expect(inserted[0].severity).toBe('CRITICAL');
  });

  it('is marked as having arrived through the mesh', async () => {
    // A dispatcher must know the reporter had no network: they cannot be called
    // back through the app and nothing further is coming from them.
    await post({ frames: [frames.ordinary] });
    expect(inserted[0].arrived_via).toBe('MESH');
    expect(String(inserted[0].description)).toContain('nearby phones');
  });

  it('is timestamped when the PHONE raised it, not when it reached us', async () => {
    // It may have crossed a dozen handsets over an hour. A dispatcher must not
    // read an hour-old kidnapping as new.
    await post({ frames: [frames.ordinary] });
    expect(inserted[0].created_at).toBe(smsVectors.sentAtIso);
  });

  it('carries the position the phone had', async () => {
    await post({ frames: [frames.ordinary] });
    expect(inserted[0].latitude).toBeCloseTo(9.89654, 5);
    expect(inserted[0].longitude).toBeCloseTo(8.85831, 5);
  });

  it('is attributed to the handset that raised it, not the relay', async () => {
    // The relay is anonymous and unauthenticated; the reporter is proven by the
    // device key sealed inside the envelope.
    await post({ frames: [frames.ordinary] });
    expect(inserted[0].reported_by).toBe('citizen-uuid');
  });

  it('a duress alert is CRITICAL and says so', async () => {
    await post({ frames: [frames.duress] });
    expect(inserted[0].severity).toBe('CRITICAL');
    expect(String(inserted[0].description)).toContain('DURESS');
  });

  it('a relay uploading its whole outbox is served in one request', async () => {
    const r = await post({ frames: [frames.ordinary, frames.duress] });
    expect(inserted).toHaveLength(2);
    expect(r.json.done).toEqual([ids.ordinary, ids.duress]);
  });

  it('a single frame may be posted without a list', async () => {
    await post({ frame: frames.ordinary });
    expect(inserted).toHaveLength(1);
  });

  it('a frame that spent hops on the way is recorded like any other', async () => {
    await post({ frames: [frames.forwarded] });
    expect(inserted).toHaveLength(1);
  });
});

describe('the same emergency arriving many times', () => {
  it('records one incident however many relays deliver it', async () => {
    // This is not an edge case. Flooding means several relays each reach a
    // network and each upload the same envelope. Six units to one incident is
    // six units not at the next one.
    await post({ frames: [frames.ordinary] });
    await post({ frames: [frames.ordinary] });
    await post({ frames: [frames.ordinary, frames.ordinary] });
    expect(inserted).toHaveLength(1);
  });

  it('but still tells every relay it is done with the frame', async () => {
    // Otherwise a relay carries an envelope HQ already has, for ever.
    await post({ frames: [frames.ordinary] });
    const second = await post({ frames: [frames.ordinary] });
    expect(second.json.done).toEqual([ids.ordinary]);
  });

  it('drops a report the reporter already delivered by data', async () => {
    // The commonest duplicate of all: the mesh gets it out, then the reporter's
    // own phone regains data and replays its offline queue.
    existingRows = [{ id: 'already-here' }];
    await post({ frames: [frames.ordinary] });
    expect(inserted).toHaveLength(0);
  });

  it('records the local ref, which is what matches the queue and the SMS', async () => {
    await post({ frames: [frames.ordinary] });
    expect(inserted[0].local_id).toBe(smsVectors.localRefHex);
  });

  it('records the alert anyway if the dedup table is unavailable', async () => {
    // Fails OPEN. A duplicate incident is visible to a dispatcher and can be
    // merged; an alert dropped because a bookkeeping table was down is visible
    // to nobody.
    dedupFails = true;
    await post({ frames: [frames.ordinary] });
    expect(inserted).toHaveLength(1);
  });
});

describe('what an anonymous caller cannot do', () => {
  it('cannot invent an alert without a device key', async () => {
    keyRows = [];
    await post({ frames: [frames.ordinary] });
    expect(inserted).toHaveLength(0);
  });

  it('cannot alter a frame it carried', async () => {
    await post({ frames: [frames.tampered] });
    expect(inserted).toHaveLength(0);
  });

  it('cannot get anything recorded by sealing to another key', async () => {
    await post({ frames: [frames.sealedToAnotherKey] });
    expect(inserted).toHaveLength(0);
  });

  it('cannot replay a frame captured days ago', async () => {
    await post({ frames: [frameAgedBy('ordinary', 72 * 3600_000)] });
    expect(inserted).toHaveLength(0);
  });

  it('cannot extend a frame_s life by dating it in the future', async () => {
    await post({ frames: [frameAgedBy('ordinary', -48 * 3600_000)] });
    expect(inserted).toHaveLength(0);
  });

  it('cannot make one request cost us unbounded work', async () => {
    // 40 frames, cap of 32.
    const many = Array.from({ length: 40 }, (_, i) =>
      i === 0 ? frames.ordinary : frames.duress,
    );
    const r = await post({ frames: many });
    expect(r.json.done!.length).toBe(32);
  });

  it('cannot flood one instance without being told to wait', async () => {
    let last = 200;
    for (let i = 0; i < 40; i++) {
      last = (await post({ frames: [] })).status;
    }
    expect(last).toBe(429);
  });

  it('cannot use the endpoint as a file upload', async () => {
    const r = await post({ frames: [frames.ordinary] }, { 'content-length': '900000' });
    expect(inserted).toHaveLength(0);
    expect(r.status).toBe(200);
  });

  it('cannot crash it with something that is not a frame', async () => {
    for (const body of [
      { frames: ['not base64 at all !!!'] },
      { frames: [42, null, {}] },
      { frames: 'a string, not a list' },
      { frame: 1234 },
      {},
      'not json at all',
      '[]',
    ]) {
      const r = await post(body);
      expect(r.status).toBe(200);
    }
    expect(inserted).toHaveLength(0);
  });
});

describe('the answer says nothing about which frames HQ wanted', () => {
  it('a real alert and a foreign one get the same shape of answer', async () => {
    // A relay that could tell which frames HQ actually wanted could tell which
    // of the phones around it are reporting. It is a stranger's phone.
    const real = await post({ frames: [frames.ordinary] });
    const foreign = await post({ frames: [frames.sealedToAnotherKey] });
    expect(Object.keys(real.json).sort()).toEqual(Object.keys(foreign.json).sort());
    expect(real.json.done).toHaveLength(1);
    expect(foreign.json.done).toHaveLength(1);
    expect(real.status).toBe(foreign.status);
  });

  it('a tampered frame is acknowledged exactly like a valid one', async () => {
    const good = await post({ frames: [frames.duress] });
    const bad = await post({ frames: [frames.tampered] });
    expect(bad.json.done).toHaveLength(good.json.done!.length);
  });

  it('nothing in the answer says accepted, rejected or duplicate', async () => {
    const r = await post({ frames: [frames.ordinary] });
    expect(JSON.stringify(r.json)).not.toMatch(/accepted|rejected|duplicate/i);
  });
});

describe('when the mesh is not configured', () => {
  it('refuses traffic instead of half-working', async () => {
    process.env.MESH_HQ_PRIVATE_KEY = '';
    const r = await post({ frames: [frames.ordinary] });
    expect(inserted).toHaveLength(0);
    expect(r.status).toBe(200);
  });

  it('and does not leak that it is misconfigured', async () => {
    process.env.MESH_HQ_PRIVATE_KEY = 'too-short';
    const r = await post({ frames: [frames.ordinary] });
    expect(r.json).toEqual({ ok: true, done: [] });
  });
});
