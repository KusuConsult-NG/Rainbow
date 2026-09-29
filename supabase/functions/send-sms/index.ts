// supabase/functions/send-sms/index.ts
// Supabase Auth Hook — Custom SMS Provider via Termii v4
//
// Configure in Supabase Dashboard:
//   Authentication → Hooks → Send SMS hook → Supabase Edge Function → send-sms
//
// Required Supabase secrets (supabase secrets set):
//   TERMII_API_KEY   — your Termii API key
//   TERMII_SENDER_ID — sender ID (default: RainbowHQ)
//   TERMII_BASE_URL  — optional override (default: https://v4.api.termii.com/api/sms/send)
//   HOOK_SECRET      — the secret Supabase passes to verify the hook caller

import { serve } from 'https://deno.land/std@0.208.0/http/server.ts';

const TERMII_API_KEY  = Deno.env.get('TERMII_API_KEY') ?? '';
const TERMII_SENDER   = Deno.env.get('TERMII_SENDER_ID') ?? 'RainbowHQ';
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
  if (HOOK_SECRET) {
    const authHeader = req.headers.get('authorization') ?? '';
    const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : authHeader;
    if (token !== HOOK_SECRET) {
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
    console.error('[SEND_SMS] Missing phone or OTP in hook payload', JSON.stringify(payload));
    // Return 200 with error body — Supabase Auth interprets non-2xx as hook failure
    // and blocks sign-in. Return 200 so auth still proceeds but log the issue.
    return jsonResponse({ error: 'Missing phone or OTP', skipped: true }, 200);
  }

  const phone = normalizePhone(rawPhone);
  const message = `Your Rainbow EWER verification code is: ${otp}. It expires in 5 minutes. Do not share this code.`;

  // ── 3. Guard: no Termii key ────────────────────────────────────────────────
  if (!TERMII_API_KEY) {
    console.error('[SEND_SMS] TERMII_API_KEY not set in Supabase secrets — SMS skipped');
    // Return 200 so sign-in is NOT blocked when key is missing in staging
    return jsonResponse({ error: 'SMS provider not configured', skipped: true }, 200);
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
      console.error('[SEND_SMS] Termii error:', JSON.stringify(termiiData));
      // Return 200 to avoid blocking sign-in — Termii delivery failure ≠ auth failure
      return jsonResponse({
        error:   'SMS delivery failed',
        detail:  termiiData,
        skipped: true,
      }, 200);
    }

    console.log(`[SEND_SMS] OTP dispatched to ${phone.slice(0, 6)}*** via Termii:`, termiiData.message_id ?? 'ok');
    return jsonResponse({ success: true, message_id: termiiData.message_id });

  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error('[SEND_SMS] Network error calling Termii:', msg);
    // Return 200 — network error should not block the citizen from signing in
    return jsonResponse({ error: msg, skipped: true }, 200);
  }
});
