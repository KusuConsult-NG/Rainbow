// The Send SMS auth hook, as logic rather than as a server.
//
// Everything here is pure or uses only Web Crypto, which exists in Deno and in
// Node 18+. index.ts is the thin Deno wrapper; this file is what the tests in
// hq-dashboard-next/src/lib/send-sms-hook.test.ts exercise, because an edge
// function that can only be tested by deploying it is an edge function nobody
// tests.
//
// ## Why this was rewritten
//
// The previous version could not have worked. Two independent faults, each
// enough on its own to stop every citizen signing in:
//
//   1. It read the one-time code from `payload.otp`. Supabase sends it at
//      `payload.sms.otp`. So `otp` was always undefined and the hook answered
//      400 "Missing phone or OTP" to every real request.
//
//   2. It authenticated by comparing the `Authorization` header against a
//      shared secret. Supabase signs hook payloads per the Standard Webhooks
//      specification — `webhook-id`, `webhook-timestamp` and
//      `webhook-signature` headers, HMAC-SHA256 — so there was no bearer token
//      to match and every real request was refused 401 before it reached the
//      payload bug.
//
// Both are confirmed against the Supabase documentation source
// (apps/docs/content/guides/auth/auth-hooks/send-sms-hook.mdx) and the Standard
// Webhooks specification, not from memory. The payload shape and the signing
// string are a contract with somebody else's service; guessing them is how the
// first version came to be shipped.
//
// ## The contract, as documented
//
//   POST, with headers
//     webhook-id         opaque message id
//     webhook-timestamp  unix seconds
//     webhook-signature  space-delimited list of "v1,<base64 HMAC-SHA256>"
//
//   body
//     { "user": { "id": "...", "phone": "+2348012345678", ... },
//       "sms":  { "otp": "561166" } }
//
//   signed content
//     "{webhook-id}.{webhook-timestamp}.{raw body}"
//
//   secret
//     base64, given by Supabase as "v1,whsec_<base64>"
//
//   success
//     an EMPTY response with status 200
//   failure
//     non-200 with { "error": { "http_code": n, "message": "..." } }

export type HookPayload = {
  user?: { id?: string; phone?: string | null } | null;
  sms?: { otp?: string | null } | null;
};

export type Refusal = { ok: false; status: number; reason: string };
export type Extracted = { ok: true; phone: string; otp: string };

/** The documented error envelope. An empty 200 is the documented success. */
export function hookError(status: number, message: string): {
  status: number;
  body: string;
  headers: Record<string, string>;
} {
  return {
    status,
    body: JSON.stringify({ error: { http_code: status, message } }),
    headers: { 'Content-Type': 'application/json' },
  };
}

/** Decode the signing key out of whatever form the secret was pasted in.
 *
 * Supabase shows it as `v1,whsec_<base64>`. Operators paste all three of the
 * obvious variants, and the difference between them is invisible in a
 * dashboard field, so all three are accepted rather than silently failing to
 * verify — which would look exactly like a wrong secret.
 */
export function hookSecretBytes(configured: string): Uint8Array | null {
  let value = (configured ?? '').trim();
  if (!value) return null;
  if (value.startsWith('v1,')) value = value.slice(3);
  if (value.startsWith('whsec_')) value = value.slice(6);
  try {
    const binary = atob(value);
    if (!binary.length) return null;
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
    return bytes;
  } catch {
    return null;
  }
}

/** Compare without leaking the answer through timing. */
export function constantTimeEquals(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i += 1) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

export async function signPayload(
  secret: Uint8Array,
  id: string,
  timestamp: string,
  body: string,
): Promise<string> {
  const key = await crypto.subtle.importKey(
    'raw',
    secret as unknown as ArrayBuffer,
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signed = `${id}.${timestamp}.${body}`;
  const mac = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(signed));
  return btoa(String.fromCharCode(...new Uint8Array(mac)));
}

/** Five minutes either side, which is the usual reading of the spec's
 *  "within some allowable tolerance". The spec names no number. */
export const TIMESTAMP_TOLERANCE_SECONDS = 300;

export async function verifyStandardWebhook(opts: {
  secret: string;
  id: string | null;
  timestamp: string | null;
  signature: string | null;
  body: string;
  nowSeconds?: number;
  toleranceSeconds?: number;
}): Promise<{ ok: true } | Refusal> {
  const secret = hookSecretBytes(opts.secret);
  if (!secret) {
    // 503, not 401: the fault is this deployment's, not the caller's, and the
    // distinction is what tells an operator whether to look at Supabase or at
    // their own secret.
    return { ok: false, status: 503, reason: 'hook secret is missing or not base64' };
  }
  if (!opts.id || !opts.timestamp || !opts.signature) {
    return {
      ok: false,
      status: 401,
      reason: 'missing webhook-id, webhook-timestamp or webhook-signature',
    };
  }

  const sent = Number(opts.timestamp);
  if (!Number.isFinite(sent)) {
    return { ok: false, status: 401, reason: 'webhook-timestamp is not a number' };
  }
  const now = opts.nowSeconds ?? Math.floor(Date.now() / 1000);
  const tolerance = opts.toleranceSeconds ?? TIMESTAMP_TOLERANCE_SECONDS;
  if (Math.abs(now - sent) > tolerance) {
    // Replay protection. Without it a captured request can be re-sent for ever,
    // and this one makes somebody's phone ring with a code they did not ask for.
    return { ok: false, status: 401, reason: 'webhook-timestamp is outside the tolerance' };
  }

  const expected = await signPayload(secret, opts.id, opts.timestamp, opts.body);
  // The header is a space-delimited LIST, so that a secret can be rotated with
  // both signatures sent during the overlap. Accepting only the first would
  // make a rotation look like an attack.
  const offered = opts.signature.split(' ').filter(Boolean);
  for (const candidate of offered) {
    const [version, value] = candidate.split(',', 2);
    if (version !== 'v1' || !value) continue;
    if (constantTimeEquals(value, expected)) return { ok: true };
  }
  return { ok: false, status: 401, reason: 'no v1 signature matched' };
}

/** Pull the phone and the code out of the documented payload shape. */
export function extractOtp(payload: unknown): Extracted | Refusal {
  const body = (payload ?? {}) as HookPayload;
  const phone = body.user?.phone?.trim();
  const otp = body.sms?.otp?.trim();

  if (!phone && !otp) {
    return { ok: false, status: 400, reason: 'payload has neither user.phone nor sms.otp' };
  }
  if (!phone) return { ok: false, status: 400, reason: 'payload has no user.phone' };
  if (!otp) {
    // Named precisely, because `payload.otp` is where the previous version
    // looked and the error it produced said only "Missing phone or OTP".
    return { ok: false, status: 400, reason: 'payload has no sms.otp' };
  }
  return { ok: true, phone, otp };
}

/** Termii wants 2348012345678 — no plus, no spaces. */
export function normalisePhone(phone: string): string {
  const digits = (phone ?? '').replace(/\D/g, '');
  if (digits.startsWith('234')) return digits;
  if (digits.startsWith('0') && digits.length === 11) return `234${digits.slice(1)}`;
  return digits;
}

/// The single most-read string in the product: every citizen reads it to get
/// in. It said "Rainbow EWER" — the name from two rebrands ago — for every
/// code ever sent, and was reported from a real handset receiving a real one.
///
/// `scripts/check_one_brand_name.py` did not catch it. The gate read `lib/`
/// and the console's `src/`, and this file is in neither; and its list of
/// former names did not carry "Rainbow EWER" either, so it would have passed
/// this string even if it had been reading it. Both are fixed.
export function otpMessage(otp: string): string {
  return `Your Plateau Eye verification code is: ${otp}. `
    + 'It expires in 5 minutes. Do not share this code.';
}

/** Never put the code or the whole number in a log line. */
export function maskPhone(phone: string): string {
  const digits = (phone ?? '').replace(/\D/g, '');
  if (digits.length <= 4) return '***';
  return `${digits.slice(0, 6)}***${digits.slice(-2)}`;
}

export function termiiRequest(opts: {
  url: string;
  apiKey: string;
  sender: string;
  phone: string;
  otp: string;
}): { url: string; init: RequestInit } {
  return {
    url: opts.url,
    init: {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        to: normalisePhone(opts.phone),
        from: opts.sender,
        sms: otpMessage(opts.otp),
        type: 'plain',
        api_key: opts.apiKey,
        // 'dnd' reaches numbers on Nigeria's Do-Not-Disturb list, which most
        // are. A transactional one-time code is what that channel is for, and
        // on 'generic' the message is simply not delivered to them.
        channel: 'dnd',
      }),
    },
  };
}

export const TERMII_URL_DEFAULT = 'https://v4.api.termii.com/api/sms/send';
