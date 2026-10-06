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

import {
  TERMII_URL_DEFAULT,
  extractOtp,
  hookError,
  maskPhone,
  termiiRequest,
  verifyStandardWebhook,
} from './hook.ts';

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
  if (req.method !== 'POST') {
    return respond(hookError(405, 'send-sms accepts POST'));
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
