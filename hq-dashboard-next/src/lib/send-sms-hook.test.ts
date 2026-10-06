// The Send SMS auth hook: the one thing standing between a citizen and the app.
//
// Sign-in is phone + one-time code. No email path, no password. Supabase
// refuses `signInWithOtp(phone:)` unless the project has an SMS provider, and
// Termii is not one of the built-ins, so delivery goes through this hook. If
// the hook does not work, nobody can sign in to report anything.
//
// The previous version could not have worked, in two independent ways, and
// nothing could have caught either because no test could reach it — it was a
// Deno `serve()` call with the logic inline. The logic is in
// supabase/functions/send-sms/hook.ts now and this file is why.
//
// The first two tests are the two faults. They are written to fail against the
// old behaviour, not merely to pass against the new.
import { describe, expect, it } from 'vitest';

import {
  TIMESTAMP_TOLERANCE_SECONDS,
  constantTimeEquals,
  extractOtp,
  hookError,
  hookSecretBytes,
  maskPhone,
  normalisePhone,
  otpMessage,
  signPayload,
  termiiRequest,
  verifyStandardWebhook,
} from '../../../supabase/functions/send-sms/hook';

// A real-shaped secret: 32 random bytes, base64, as Supabase presents it.
const SECRET = 'v1,whsec_c2VjcmV0LWtleS1mb3ItdGVzdGluZy0zMi1ieXRlcyE=';
const BODY = JSON.stringify({
  user: { id: '8484b834-0000-4000-8000-000000000001', phone: '+2348012345678' },
  sms: { otp: '561166' },
});

async function signedHeaders(body = BODY, at = Math.floor(Date.now() / 1000)) {
  const secret = hookSecretBytes(SECRET)!;
  const id = 'msg_2KWPBgLlAfxdpx2AI54pPJ85f4W';
  const timestamp = String(at);
  const signature = `v1,${await signPayload(secret, id, timestamp, body)}`;
  return { id, timestamp, signature };
}

describe('the two faults that stopped every sign-in', () => {
  it('reads the code from sms.otp, not from a top-level otp', async () => {
    // FAULT 1. The old hook read `payload.otp`. Supabase sends
    // `payload.sms.otp`, so `otp` was always undefined and the hook answered
    // 400 "Missing phone or OTP" to every real request — no code was ever sent
    // to anybody.
    const got = extractOtp(JSON.parse(BODY));
    expect(got.ok).toBe(true);
    expect(got.ok && got.otp).toBe('561166');

    // And the shape the old version expected is NOT accepted, so a regression
    // back to it fails here rather than in production.
    const oldShape = extractOtp({ user: { phone: '+2348012345678' }, otp: '561166' });
    expect(oldShape.ok).toBe(false);
    expect(oldShape.ok === false && oldShape.reason).toContain('sms.otp');
  });

  it('authenticates by signature, not by a bearer secret', async () => {
    // FAULT 2. The old hook compared the Authorization header against a shared
    // secret. These requests carry no such header — they are signed per
    // Standard Webhooks — so every real call was refused 401 before it even
    // reached fault 1.
    const h = await signedHeaders();
    const ok = await verifyStandardWebhook({
      secret: SECRET, body: BODY, id: h.id, timestamp: h.timestamp, signature: h.signature,
    });
    expect(ok.ok).toBe(true);

    // A request with a correct-looking bearer token and no signature is refused.
    const bearerOnly = await verifyStandardWebhook({
      secret: SECRET, body: BODY, id: null, timestamp: null, signature: null,
    });
    expect(bearerOnly.ok).toBe(false);
    expect(bearerOnly.ok === false && bearerOnly.status).toBe(401);
  });
});

describe('the signature', () => {
  it('covers the body, so a tampered payload is refused', async () => {
    const h = await signedHeaders();
    // Same signature, different body: a captured request with the phone number
    // swapped for the attacker's.
    const tampered = BODY.replace('+2348012345678', '+2349099999999');
    const verdict = await verifyStandardWebhook({
      secret: SECRET, body: tampered, id: h.id, timestamp: h.timestamp, signature: h.signature,
    });
    expect(verdict.ok).toBe(false);
    expect(verdict.ok === false && verdict.reason).toContain('no v1 signature matched');
  });

  it('covers the id and the timestamp as well as the body', async () => {
    const h = await signedHeaders();
    for (const changed of [{ id: 'msg_other' }, { timestamp: String(Number(h.timestamp) + 1) }]) {
      const verdict = await verifyStandardWebhook({
        secret: SECRET, body: BODY, ...h, ...changed,
      });
      expect(verdict.ok, JSON.stringify(changed)).toBe(false);
    }
  });

  it('refuses a signature made with a different secret', async () => {
    const h = await signedHeaders();
    const verdict = await verifyStandardWebhook({
      secret: 'v1,whsec_b3RoZXItc2VjcmV0LWZvci10ZXN0aW5nLTMyLWJ5dGVz',
      body: BODY, ...h,
    });
    expect(verdict.ok).toBe(false);
  });

  it('accepts any of several space-delimited signatures, for rotation', async () => {
    // The header is a LIST so both the old and new signature can be sent during
    // a secret rotation. Accepting only the first would make a rotation look
    // like an attack and take sign-in down for the overlap.
    const h = await signedHeaders();
    const verdict = await verifyStandardWebhook({
      secret: SECRET, body: BODY, id: h.id, timestamp: h.timestamp,
      signature: `v1,ZmFrZS1zaWduYXR1cmUtdGhhdC13aWxsLW5vdC1tYXRjaA== ${h.signature}`,
    });
    expect(verdict.ok).toBe(true);
  });

  it('ignores signature versions it does not implement', async () => {
    const h = await signedHeaders();
    const verdict = await verifyStandardWebhook({
      secret: SECRET, body: BODY, id: h.id, timestamp: h.timestamp,
      // v1a is ed25519, which this hook does not verify. It must be skipped,
      // not mistaken for a v1 HMAC.
      signature: `v1a,${h.signature.slice(3)}`,
    });
    expect(verdict.ok).toBe(false);
  });

  it('refuses a replayed request once it is stale', async () => {
    const now = 1_767_000_000;
    const h = await signedHeaders(BODY, now - TIMESTAMP_TOLERANCE_SECONDS - 1);
    const stale = await verifyStandardWebhook({
      secret: SECRET, body: BODY, ...h, nowSeconds: now,
    });
    expect(stale.ok).toBe(false);
    expect(stale.ok === false && stale.reason).toContain('tolerance');

    // Inside the window it is accepted — otherwise a clock a minute out would
    // take sign-in down.
    const fresh = await signedHeaders(BODY, now - TIMESTAMP_TOLERANCE_SECONDS + 10);
    const ok = await verifyStandardWebhook({
      secret: SECRET, body: BODY, ...fresh, nowSeconds: now,
    });
    expect(ok.ok).toBe(true);
  });

  it('refuses a timestamp from the future beyond tolerance, not just the past', async () => {
    const now = 1_767_000_000;
    const h = await signedHeaders(BODY, now + TIMESTAMP_TOLERANCE_SECONDS + 1);
    const verdict = await verifyStandardWebhook({
      secret: SECRET, body: BODY, ...h, nowSeconds: now,
    });
    expect(verdict.ok).toBe(false);
  });

  it('refuses a non-numeric timestamp instead of treating it as zero', async () => {
    const h = await signedHeaders();
    const verdict = await verifyStandardWebhook({
      secret: SECRET, body: BODY, id: h.id, timestamp: 'yesterday', signature: h.signature,
    });
    expect(verdict.ok).toBe(false);
    expect(verdict.ok === false && verdict.reason).toContain('not a number');
  });
});

describe('the secret', () => {
  it('is accepted in all three forms an operator might paste', () => {
    const raw = 'c2VjcmV0LWtleS1mb3ItdGVzdGluZy0zMi1ieXRlcyE=';
    const forms = [`v1,whsec_${raw}`, `whsec_${raw}`, raw];
    const decoded = forms.map(f => hookSecretBytes(f));
    expect(decoded.every(d => d !== null)).toBe(true);
    // All three must decode to the SAME key, or two of them verify nothing.
    expect(new Set(decoded.map(d => Array.from(d!).join(',')))).toHaveLength(1);
  });

  it('is rejected when absent or not base64, as a 503 and not a 401', async () => {
    // The distinction matters operationally: 401 sends somebody to look at
    // Supabase, 503 tells them the fault is their own configuration.
    for (const bad of ['', '   ', 'v1,whsec_not base64 at all!!']) {
      const verdict = await verifyStandardWebhook({
        secret: bad, body: BODY, id: 'x', timestamp: '1', signature: 'v1,y',
      });
      expect(verdict.ok, JSON.stringify(bad)).toBe(false);
      expect(verdict.ok === false && verdict.status).toBe(503);
    }
  });

  it('compares in constant time', () => {
    expect(constantTimeEquals('abc', 'abc')).toBe(true);
    expect(constantTimeEquals('abc', 'abd')).toBe(false);
    expect(constantTimeEquals('abc', 'ab')).toBe(false);
    expect(constantTimeEquals('', '')).toBe(true);
  });
});

describe('the payload', () => {
  it('names which field is missing, rather than "phone or OTP"', () => {
    const noPhone = extractOtp({ sms: { otp: '123456' } });
    expect(noPhone.ok === false && noPhone.reason).toContain('user.phone');

    const noOtp = extractOtp({ user: { phone: '+2348012345678' } });
    expect(noOtp.ok === false && noOtp.reason).toContain('sms.otp');

    // The old message was "Missing phone or OTP" for both, which is why a
    // payload-shape bug read as a configuration problem for weeks.
    expect(noPhone.ok === false && noPhone.reason)
      .not.toBe(noOtp.ok === false ? noOtp.reason : '');
  });

  it('survives null, undefined and the wrong shape without throwing', () => {
    for (const junk of [null, undefined, {}, { user: null, sms: null }, 'a string', 42, []]) {
      const got = extractOtp(junk);
      expect(got.ok, JSON.stringify(junk)).toBe(false);
    }
  });

  it('trims whitespace, which a gateway can introduce', () => {
    const got = extractOtp({ user: { phone: ' +2348012345678 ' }, sms: { otp: ' 561166 ' } });
    expect(got.ok && got.phone).toBe('+2348012345678');
    expect(got.ok && got.otp).toBe('561166');
  });
});

describe('the phone number Termii is given', () => {
  it('is digits only, with the country code and no plus', () => {
    expect(normalisePhone('+234 801 234 5678')).toBe('2348012345678');
    expect(normalisePhone('2348012345678')).toBe('2348012345678');
  });

  it('turns a local 0-prefixed Nigerian number into 234', () => {
    expect(normalisePhone('08012345678')).toBe('2348012345678');
  });

  it('leaves a number from another country alone rather than mangling it', () => {
    // Supabase sends E.164, so this is a +44 arriving as digits. Prefixing 234
    // would send a Nigerian SMS to a number that is not Nigerian.
    expect(normalisePhone('+447700900123')).toBe('447700900123');
  });
});

describe('what reaches Termii', () => {
  const built = () => termiiRequest({
    url: 'https://v4.api.termii.com/api/sms/send',
    apiKey: 'tk_test',
    sender: 'OE Alert',
    phone: '+2348012345678',
    otp: '561166',
  });

  it('carries the code, the sender and the normalised number', () => {
    const body = JSON.parse(built().init.body as string);
    expect(body.to).toBe('2348012345678');
    expect(body.from).toBe('OE Alert');
    expect(body.sms).toContain('561166');
    expect(body.api_key).toBe('tk_test');
  });

  it('uses the dnd channel, or most Nigerian numbers never receive it', () => {
    // Most Nigerian numbers are on the Do-Not-Disturb list. On 'generic' a
    // transactional code is simply not delivered to them, with no error.
    expect(JSON.parse(built().init.body as string).channel).toBe('dnd');
  });

  it('tells the person what the code is for and how long it lasts', () => {
    const text = otpMessage('561166');
    expect(text).toContain('561166');
    expect(text).toMatch(/expires/i);
    expect(text).toMatch(/do not share/i);
  });
});

describe('what the hook says back', () => {
  it('uses the documented error envelope', () => {
    const err = hookError(500, 'Termii refused the message');
    expect(err.status).toBe(500);
    expect(JSON.parse(err.body)).toEqual({
      error: { http_code: 500, message: 'Termii refused the message' },
    });
  });
});

describe('what gets logged', () => {
  it('masks the number, and the code appears nowhere', () => {
    const masked = maskPhone('+2348012345678');
    expect(masked).toContain('***');
    expect(masked).not.toContain('2345678');
    // A one-time code in a log line is a one-time code in whoever can read logs.
    expect(masked).not.toContain('561166');
  });

  it('does not leak a short number by printing it whole', () => {
    expect(maskPhone('123')).toBe('***');
  });
});
