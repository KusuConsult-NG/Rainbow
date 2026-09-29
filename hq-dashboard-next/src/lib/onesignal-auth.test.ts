// The Authorization header for OneSignal.
//
// Three call sites sent the same credential under two different schemes — Basic
// twice, Key once — so at least one had never authenticated. And the one most
// likely to be broken reported `success: true` without looking at `response.ok`,
// which is why nobody would ever have found out.
//
// These tests hold the property that makes the fix safe regardless of which
// scheme is actually correct: a refused credential is retried under the other
// scheme, and a failure is never reported as a success.
import { describe, expect, it, vi } from 'vitest';

import {
  authAttempts,
  authHeader,
  isAuthFailure,
  postNotification,
  schemeForKey,
} from './onesignal-auth';

const LEGACY = 'NjAwZTNhZDUtMzk0ZC00ZDI0LWE4YzQtZjUwMzI0MjI5ZjAw';
const V2 = 'os_v2_app_abc123def456';

describe('guessing the scheme', () => {
  it('uses Key for an os_v2 credential and Basic for a legacy one', () => {
    expect(schemeForKey(V2)).toBe('Key');
    expect(schemeForKey(LEGACY)).toBe('Basic');
  });

  it('ignores surrounding whitespace, which a pasted secret often has', () => {
    expect(schemeForKey(`  ${V2}  `)).toBe('Key');
  });
});

describe('what gets tried, and in what order', () => {
  it('tries the guess first, then the other', () => {
    expect(authAttempts(LEGACY)).toEqual(['Basic', 'Key']);
    expect(authAttempts(V2)).toEqual(['Key', 'Basic']);
  });

  it('honours an explicit override, and STILL keeps the other as a fallback', () => {
    // An operator who sets it wrongly should get a delivered notification and a
    // log line telling them so, not silence.
    expect(authAttempts(LEGACY, 'Key')).toEqual(['Key', 'Basic']);
    expect(authAttempts(V2, 'basic')).toEqual(['Basic', 'Key']);
  });

  it('ignores an override it does not understand', () => {
    expect(authAttempts(LEGACY, 'Bearer')).toEqual(['Basic', 'Key']);
    expect(authAttempts(LEGACY, '')).toEqual(['Basic', 'Key']);
  });

  it('tries nothing when there is no key', () => {
    expect(authAttempts('')).toEqual([]);
    expect(authAttempts('   ')).toEqual([]);
  });

  it('builds the header with no stray whitespace', () => {
    expect(authHeader('Basic', `  ${LEGACY} `)).toBe(`Basic ${LEGACY}`);
  });
});

describe('recognising a refused credential', () => {
  it('is 401 and 403, and nothing else', () => {
    expect(isAuthFailure(401)).toBe(true);
    expect(isAuthFailure(403)).toBe(true);
    // A 400 is a bad payload and a 429 is a rate limit. Re-sending either under
    // a different scheme helps nobody.
    for (const s of [200, 400, 404, 429, 500, 503]) {
      expect(isAuthFailure(s), String(s)).toBe(false);
    }
  });
});

describe('sending one', () => {
  const ok = () => new Response(JSON.stringify({ id: 'n-1' }), { status: 200 });
  const refused = () => new Response(JSON.stringify({ errors: ['bad auth'] }), { status: 401 });

  it('succeeds on the first scheme when that is the right one', async () => {
    const fetchImpl = vi.fn().mockResolvedValue(ok());
    const out = await postNotification(LEGACY, { app_id: 'a' }, { fetchImpl });

    expect(out.ok).toBe(true);
    expect(out.scheme).toBe('Basic');
    expect(fetchImpl).toHaveBeenCalledTimes(1);
    const headers = (fetchImpl.mock.calls[0][1] as RequestInit).headers as Record<string, string>;
    expect(headers.Authorization).toBe(`Basic ${LEGACY}`);
  });

  it('retries under the OTHER scheme when the first is refused', async () => {
    // The property that makes this safe whichever scheme OneSignal actually
    // wants: being wrong costs one round trip, not every notification.
    const fetchImpl = vi.fn()
      .mockResolvedValueOnce(refused())
      .mockResolvedValueOnce(ok());
    const log = vi.fn();

    const out = await postNotification(LEGACY, { app_id: 'a' }, { fetchImpl, log });

    expect(out.ok).toBe(true);
    expect(out.scheme).toBe('Key');
    expect(fetchImpl).toHaveBeenCalledTimes(2);
    const second = (fetchImpl.mock.calls[1][1] as RequestInit).headers as Record<string, string>;
    expect(second.Authorization).toBe(`Key ${LEGACY}`);
  });

  it('logs the remedy when the fallback is the one that works', async () => {
    // Otherwise a wrong guess is a permanent extra round trip nobody notices.
    const fetchImpl = vi.fn()
      .mockResolvedValueOnce(refused())
      .mockResolvedValueOnce(ok());
    const log = vi.fn();
    await postNotification(LEGACY, {}, { fetchImpl, log });

    const said = log.mock.calls.flat().join(' ');
    expect(said).toContain('ONESIGNAL_AUTH_SCHEME=Key');
  });

  it('does NOT log when the first scheme worked', async () => {
    const log = vi.fn();
    await postNotification(LEGACY, {}, { fetchImpl: vi.fn().mockResolvedValue(ok()), log });
    expect(log).not.toHaveBeenCalled();
  });

  it('does not retry a 400 — that is a bad payload, not bad auth', async () => {
    const fetchImpl = vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ errors: ['invalid player ids'] }), { status: 400 }),
    );
    const out = await postNotification(LEGACY, {}, { fetchImpl });
    expect(out.ok).toBe(false);
    expect(fetchImpl).toHaveBeenCalledTimes(1);
    expect(out.status).toBe(400);
  });

  it('does not retry a 429', async () => {
    const fetchImpl = vi.fn().mockResolvedValue(new Response('slow down', { status: 429 }));
    await postNotification(LEGACY, {}, { fetchImpl });
    expect(fetchImpl).toHaveBeenCalledTimes(1);
  });

  it('reports a failure when BOTH schemes are refused', async () => {
    const fetchImpl = vi.fn().mockResolvedValue(refused());
    const out = await postNotification(LEGACY, {}, { fetchImpl });

    expect(out.ok).toBe(false);
    expect(fetchImpl).toHaveBeenCalledTimes(2);
    expect(out.error).toContain('both authentication schemes');
    // Names the variable to check, because "push is broken" is not actionable.
    expect(out.error).toContain('ONESIGNAL_REST_API_KEY');
  });

  it('does not retry a transport failure under the other scheme', async () => {
    // A dropped socket is not an auth problem; a second doomed request just
    // delays the error.
    const fetchImpl = vi.fn().mockRejectedValue(new Error('socket hang up'));
    const out = await postNotification(LEGACY, {}, { fetchImpl });
    expect(out.ok).toBe(false);
    expect(fetchImpl).toHaveBeenCalledTimes(1);
    expect(out.error).toContain('Could not reach OneSignal');
  });

  it('refuses to try at all with no key, and says so', async () => {
    const fetchImpl = vi.fn();
    const out = await postNotification('', {}, { fetchImpl });
    expect(out.ok).toBe(false);
    expect(fetchImpl).not.toHaveBeenCalled();
    expect(out.error).toContain('No OneSignal key');
  });

  it('survives a response body that is not JSON', async () => {
    // OneSignal returns HTML from its edge on some failures, and a throw here
    // would turn a refused push into a 500 in the caller.
    const fetchImpl = vi.fn().mockResolvedValue(
      new Response('<html>gateway error</html>', { status: 502 }),
    );
    const out = await postNotification(LEGACY, {}, { fetchImpl });
    expect(out.ok).toBe(false);
    expect(out.status).toBe(502);
  });

  it('never reports ok for a non-2xx, whatever the body says', async () => {
    // The defect this whole module exists to close: api/push/dispatch returned
    // `{ success: true, notifiedCount: N }` without looking at response.ok, so a
    // 401 read as N notifications delivered.
    for (const status of [400, 401, 403, 429, 500, 502]) {
      const fetchImpl = vi.fn().mockResolvedValue(
        new Response(JSON.stringify({ id: 'looks-fine' }), { status }),
      );
      const out = await postNotification(LEGACY, {}, { fetchImpl });
      expect(out.ok, String(status)).toBe(false);
    }
  });
});
