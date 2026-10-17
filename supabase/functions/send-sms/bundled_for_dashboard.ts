// GENERATED — DO NOT EDIT. Run scripts/build_send_sms_bundle.py.
//
// index.ts and hook.ts, in one file, for pasting into the Supabase dashboard's
// function editor when the CLI cannot deploy. Deploy with JWT verification
// OFF: the Auth hook fires before any JWT exists, so with it on the platform
// refuses every real call before this code runs — and logs nothing, which
// reads exactly like "the hook is not wired".
//
// Prefer the CLI, which needs no bundle:
//
//     supabase functions deploy send-sms --no-verify-jwt --project-ref <ref>
//
// Edit supabase/functions/send-sms/index.ts or hook.ts. Never edit this file:
// check_send_sms_bundle_is_current.py regenerates it and fails on a diff.

// ── hook.ts ────────────────────────────────────────────────────────────────

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
/// Which build of this function is running.
///
/// There is no other way to know. `wire_up_sms_provider.sh --check` reports
/// that the endpoint answers, verifies signatures and has its provider on —
/// and every one of those was already green against a deployment carrying a
/// sign-in SMS with the wrong app name in it (T-65). A probe that cannot tell
/// a current deployment from a stale one lets an operator read "✓" as "my
/// paste landed", which is exactly what happened.
///
/// It matters more here than in most places: the CLI deploy returns 403 for
/// this account, so every change to this function is a manual paste into the
/// dashboard editor, with nothing to confirm it took.
///
/// Not a secret: a hash of two files already in a public repository, which
/// says nothing about the signing secret, Termii, or any phone number.
/// Generated by `scripts/stamp_send_sms_version.py`; held to the sources by
/// `scripts/check_send_sms_bundle_is_current.py`.
export const SOURCE_FINGERPRINT = 'c75cc2893c5f76fd';

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

// ── index.ts ───────────────────────────────────────────────────────────────
// supabase/functions/send-sms/index.ts
// Supabase Auth Hook — custom SMS provider, delivering through Termii v4.
//
// Citizen sign-in is phone + one-time code. There is no email path and no
// password, and Supabase refuses `signInWithOtp(phone:)` outright unless the
// project has an SMS provider. Termii is not one of Supabase's built-ins
// (Twilio, MessageBird, Vonage, TextLocal), so it is attached through this
// hook — which keeps one SMS account and one bill.
//
// If this hook does not work, nobody can sign in. That is the whole of it.
//
// ── Configure ────────────────────────────────────────────────────────────────
//
//   Supabase Dashboard
//     Authentication → Providers → Phone              enable
//     Authentication → Hooks → Send SMS               Supabase Edge Function
//                                                      → send-sms
//     OTP length                                       6  (the app's field is
//                                                          maxLength: 6)
//
//   Secrets (supabase secrets set --env-file ...)
//     SEND_SMS_HOOK_SECRET  the signing secret the hook page shows, in the form
//                           v1,whsec_<base64>. Pasting it with or without the
//                           prefixes both work.
//     TERMII_API_KEY        Termii API key
//     TERMII_SENDER_ID      approved sender ID (default: OE Alert)
//     TERMII_BASE_URL       optional override of the Termii endpoint
//     ALLOW_UNSENT_OTP      staging only — see below. Unset in production.
//
// All the logic lives in ./hook.ts so that it can be tested without deploying:
// hq-dashboard-next/src/lib/send-sms-hook.test.ts covers the signature
// verification, the payload shape, the phone normalisation and the response
// envelopes. The previous version of this file had two faults that stopped
// every sign-in and could not be caught by anything, because nothing here was
// reachable from a test.

import { serve } from 'https://deno.land/std@0.208.0/http/server.ts';


const HOOK_SECRET = Deno.env.get('SEND_SMS_HOOK_SECRET') ?? '';
const LEGACY_SECRET = Deno.env.get('HOOK_SECRET') ?? '';
const TERMII_API_KEY = Deno.env.get('TERMII_API_KEY') ?? '';
const TERMII_SENDER = Deno.env.get('TERMII_SENDER_ID') ?? 'OE Alert';
const TERMII_URL = Deno.env.get('TERMII_BASE_URL') ?? TERMII_URL_DEFAULT;

/// Whether this deployment has deliberately opted into "carry on without SMS".
///
/// Off unless set, and it must stay off in production. See notSent().
const ALLOW_UNSENT_OTP = (Deno.env.get('ALLOW_UNSENT_OTP') ?? '').toLowerCase() === 'true';

function respond(parts: { status: number; body: string; headers: Record<string, string> }) {
  return new Response(parts.body, { status: parts.status, headers: parts.headers });
}

/// The documented success: an empty body with 200.
function sent() {
  return new Response(null, { status: 200 });
}

/// The answer when the code was NOT sent.
///
/// ## Why this is not a 200
///
/// Every failure path here once returned 200, commented "so sign-in is NOT
/// blocked". It does not unblock anything. A citizen signs in with a phone
/// number and a code; if no code is sent there is nothing for them to type.
/// Answering 200 tells Supabase the code went out, so the app says "we have
/// sent you a code" and waits — for a code that does not exist.
///
/// The citizen cannot get in either way. The only difference the 200 makes is
/// whether they are told, or left on a screen watching a timer. This app is how
/// somebody reports a kidnapping.
///
/// So: fail loudly. `verifyPhoneNumber` in auth_service.dart returns a bool and
/// `_describeOtpSendFailure` already has words for it.
function notSent(reason: string, detail?: unknown) {
  if (ALLOW_UNSENT_OTP) {
    console.warn(`[SEND_SMS] ${reason} — ALLOW_UNSENT_OTP is set, letting auth proceed`);
    return sent();
  }
  console.error(`[SEND_SMS] ${reason}`, detail ?? '');
  return respond(hookError(500, reason));
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers':
          'authorization, x-client-info, apikey, content-type, '
          + 'webhook-id, webhook-timestamp, webhook-signature',
      },
    });
  }
  // The one request that is safe to answer with anything: a GET sends no SMS
  // and reads no body. It carries the build marker so an operator can tell
  // WHICH version is live, which no other signal here can.
  //
  // Built inline rather than through hookError() so the documented error
  // envelope stays exactly as it is — `--check` keys on `"http_code":405` to
  // tell our answer from the platform's, and that must not move.
  if (req.method !== 'POST') {
    return new Response(
      JSON.stringify({
        error: { http_code: 405, message: 'send-sms accepts POST' },
        build: SOURCE_FINGERPRINT,
      }),
      { status: 405, headers: { 'Content-Type': 'application/json' } },
    );
  }

  // ── 1. Authenticate the caller ─────────────────────────────────────────────
  //
  // Standard Webhooks, which is what Supabase actually sends. The previous
  // version compared the Authorization header against a shared secret: there is
  // no such header on these requests, so every real call was refused 401.
  //
  // The secret being unset is a 503 and not a pass. An earlier version only
  // checked when the secret happened to be set, which meant an unconfigured
  // deployment had NO check — anyone who found the URL could post a phone
  // number and have Termii send to it, billed to this account.
  if (!HOOK_SECRET) {
    if (LEGACY_SECRET) {
      console.error(
        '[SEND_SMS] HOOK_SECRET is set but SEND_SMS_HOOK_SECRET is not. The hook '
        + 'is signed per Standard Webhooks now and needs the signing secret from '
        + 'Authentication → Hooks → Send SMS, in the form v1,whsec_<base64>.',
      );
      return respond(hookError(503, 'hook secret is configured under the old name'));
    }
    console.error('[SEND_SMS] SEND_SMS_HOOK_SECRET is not set — refusing to run');
    return respond(hookError(503, 'hook is not configured'));
  }

  // The RAW body: the signature covers the bytes as sent, so it has to be read
  // before anything parses or re-serialises it.
  const raw = await req.text();

  const verdict = await verifyStandardWebhook({
    secret: HOOK_SECRET,
    id: req.headers.get('webhook-id'),
    timestamp: req.headers.get('webhook-timestamp'),
    signature: req.headers.get('webhook-signature'),
    body: raw,
  });
  if (!verdict.ok) {
    console.error(`[SEND_SMS] rejected: ${verdict.reason}`);
    return respond(hookError(verdict.status, verdict.reason));
  }

  // ── 2. Read the payload ────────────────────────────────────────────────────
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return respond(hookError(400, 'body is not JSON'));
  }

  const extracted = extractOtp(parsed);
  if (!extracted.ok) {
    console.error(`[SEND_SMS] ${extracted.reason}`);
    return respond(hookError(extracted.status, extracted.reason));
  }

  // ── 3. Deliver ─────────────────────────────────────────────────────────────
  if (!TERMII_API_KEY) {
    return notSent('TERMII_API_KEY is not set in Supabase secrets');
  }

  const { url, init } = termiiRequest({
    url: TERMII_URL,
    apiKey: TERMII_API_KEY,
    sender: TERMII_SENDER,
    phone: extracted.phone,
    otp: extracted.otp,
  });

  try {
    const res = await fetch(url, init);
    // Termii answers 200 with a body that says what happened, so the status
    // alone is not the verdict.
    let data: Record<string, unknown> = {};
    try {
      data = await res.json();
    } catch {
      // Non-JSON from the gateway. The status still decides.
    }

    if (!res.ok) {
      return notSent('Termii refused the message', data);
    }

    // Never log the code, and never the whole number.
    console.log(
      `[SEND_SMS] code dispatched to ${maskPhone(extracted.phone)}:`,
      data.message_id ?? 'ok',
    );
    return sent();
  } catch (err) {
    return notSent(`could not reach Termii: ${err instanceof Error ? err.message : String(err)}`);
  }
});
