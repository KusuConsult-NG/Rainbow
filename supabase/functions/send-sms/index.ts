// supabase/functions/send-sms/index.ts
// Supabase Auth Hook — Custom SMS Provider via Termii v4
//
// Configure in Supabase Dashboard:
//   Authentication → Hooks → Send SMS hook → Supabase Edge Function → send-sms
//
// Required Supabase secrets (supabase secrets set):
//   TERMII_API_KEY   — your Termii API key
//   TERMII_SENDER_ID — sender ID (default: OE Alert, the ID approved on the Termii workspace)
//   TERMII_BASE_URL  — optional override (default: https://v4.api.termii.com/api/sms/send)
//   HOOK_SECRET      — the secret Supabase passes to verify the hook caller

import { serve } from 'https://deno.land/std@0.208.0/http/server.ts';

const TERMII_API_KEY  = Deno.env.get('TERMII_API_KEY') ?? '';
const TERMII_SENDER   = Deno.env.get('TERMII_SENDER_ID') ?? 'OE Alert';
const TERMII_URL      = Deno.env.get('TERMII_BASE_URL') ?? 'https://v4.api.termii.com/api/sms/send';
const HOOK_SECRET     = Deno.env.get('HOOK_SECRET') ?? '';

// ── Helpers ───────────────────────────────────────────────────────────────────

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

// Normalize phone to international format expected by Termii
// Termii requires: 2348012345678 (no + prefix, no spaces)
function normalizePhone(phone: string): string {
  const digits = phone.replace(/\D/g, '');
  // Nigerian numbers: if starts with 0, replace with 234
  if (digits.startsWith('0') && digits.length === 11) return '234' + digits.slice(1);
  // If already has country code 234
  if (digits.startsWith('234')) return digits;
  // Fallback: return as-is (international numbers from other countries)
  return digits;
}

/// Compare without leaking the answer through timing.
function secretsMatch(given: string, expected: string): boolean {
  if (given.length !== expected.length) return false;
  let diff = 0;
  for (let i = 0; i < given.length; i += 1) {
    diff |= given.charCodeAt(i) ^ expected.charCodeAt(i);
  }
  return diff === 0;
}

/// Whether a deployment has deliberately opted into "carry on without SMS".
///
/// Off unless set. See the note on the failure paths below: the lenient
/// behaviour is for a staging box with no Termii account, and production must
/// not inherit it by accident.
const ALLOW_UNSENT_OTP = (Deno.env.get('ALLOW_UNSENT_OTP') ?? '').toLowerCase() === 'true';

/// The answer when the code was NOT sent.
///
/// ## Why this is not a 200
///
/// Every failure path here used to return 200 with `skipped: true`, commented
/// "so sign-in is NOT blocked". It does not unblock anything. A citizen signs
/// in with a phone number and a code; if no code is sent, there is nothing for
/// them to type. Answering 200 tells Supabase the code went out, so the app
/// says "we have sent you a code" and waits — for a code that does not exist.
///
/// The citizen cannot get in either way. The only difference the 200 makes is
/// whether they are told, or left on a screen watching a timer. This app is
/// how somebody reports a kidnapping.
///
/// So: fail loudly. `verifyPhoneNumber` in auth_service.dart already returns a
/// bool and `_describeOtpSendFailure` already has words for this — the app is
/// waiting for a signal that never came.
function notSent(reason: string, detail?: unknown): Response {
  if (ALLOW_UNSENT_OTP) {
    console.warn(`[SEND_SMS] ${reason} — ALLOW_UNSENT_OTP is set, letting auth proceed`);
    return jsonResponse({ error: reason, detail, skipped: true }, 200);
  }
  console.error(`[SEND_SMS] ${reason} — reporting failure so the app can say so`);
  return jsonResponse({ error: reason, detail }, 500);
}

// ── Main handler ──────────────────────────────────────────────────────────────

serve(async (req: Request) => {
  // CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
      },
    });
  }

  // ── 1. Verify hook secret (Supabase passes it as Authorization header) ─────
  //
  // This used to be `if (HOOK_SECRET) { ...check... }`, so an unset secret
  // meant NO check: anyone who found the function URL could post a phone
  // number and have Termii send to it, billed to this account. An SMS relay
  // that costs money per call is worth finding.
  //
  // Refuse to run instead. A hook that is not configured should be visibly
  // broken, not quietly open.
  if (!HOOK_SECRET) {
    console.error('[SEND_SMS] HOOK_SECRET is not set — refusing to run');
    return jsonResponse({ error: 'Hook is not configured' }, 503);
  }
  {
    const authHeader = req.headers.get('authorization') ?? '';
    const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : authHeader;
    if (!secretsMatch(token, HOOK_SECRET)) {
      console.error('[SEND_SMS] Hook secret mismatch — rejecting');
      return jsonResponse({ error: 'Unauthorized' }, 401);
    }
  }

  // ── 2. Parse hook payload ──────────────────────────────────────────────────
  // Supabase Auth sends: { "user": { "phone": "..." }, "otp": "123456" }
  let payload: { user?: { phone?: string }; otp?: string };
  try {
    payload = await req.json();
  } catch {
    return jsonResponse({ error: 'Invalid JSON body' }, 400);
  }

  const rawPhone = payload?.user?.phone;
  const otp      = payload?.otp;

  if (!rawPhone || !otp) {
    // Not a delivery failure — the hook was called with nothing to send, which
    // means something upstream is wrong. A 400 says so plainly.
    console.error('[SEND_SMS] Missing phone or OTP in hook payload');
    return jsonResponse({ error: 'Missing phone or OTP' }, 400);
  }

  const phone = normalizePhone(rawPhone);
  const message = `Your Rainbow EWER verification code is: ${otp}. It expires in 5 minutes. Do not share this code.`;

  // ── 3. Guard: no Termii key ────────────────────────────────────────────────
  if (!TERMII_API_KEY) {
    return notSent('TERMII_API_KEY is not set in Supabase secrets');
  }

  // ── 4. Send via Termii v4 ─────────────────────────────────────────────────
  try {
    const termiiRes = await fetch(TERMII_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        to:      phone,
        from:    TERMII_SENDER,
        sms:     message,
        type:    'plain',
        api_key: TERMII_API_KEY,
        channel: 'dnd',
      }),
    });

    const termiiData = await termiiRes.json();

    if (!termiiRes.ok) {
      return notSent('Termii refused the message', termiiData);
    }

    console.log(`[SEND_SMS] OTP dispatched to ${phone.slice(0, 6)}*** via Termii:`, termiiData.message_id ?? 'ok');
    return jsonResponse({ success: true, message_id: termiiData.message_id });

  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    return notSent(`could not reach Termii: ${msg}`);
  }
});
