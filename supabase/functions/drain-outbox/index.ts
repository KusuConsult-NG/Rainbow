// supabase/functions/drain-outbox/index.ts
//
// Notification Outbox Drain Worker
// Runs every minute via Supabase Cron (configured in the Supabase dashboard or
// via pg_cron in the 20261007000000_notification_outbox.sql migration).
//
// What it does:
//   1. Claims up to 20 undelivered, due rows from notification_outbox
//   2. For each row, fires the appropriate delivery method (push / SMS / webhook)
//   3. Marks delivered rows as done; failed rows get exponential backoff + error log
//
// Delivery methods dispatched:
//   kind=PUSH       → OneSignal push notification
//   kind=SMS        → Termii v4 SMS  
//   kind=WEBHOOK    → agency webhook (RAINBOW_WEBHOOK_SECRET)
//
// This function is the worker side of the transactional outbox described in
// 20261007000000_notification_outbox.sql. It never sends twice because
// claim_notifications() uses FOR UPDATE SKIP LOCKED.

import { serve } from 'https://deno.land/std@0.208.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// ── Config ────────────────────────────────────────────────────────────────────
const SUPABASE_URL            = Deno.env.get('SUPABASE_URL') ?? '';
const SUPABASE_SERVICE_KEY    = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const ONESIGNAL_APP_ID        = Deno.env.get('ONESIGNAL_APP_ID') ?? '';
const ONESIGNAL_REST_API_KEY  = Deno.env.get('ONESIGNAL_REST_API_KEY') ?? '';
const TERMII_API_KEY          = Deno.env.get('TERMII_API_KEY') ?? '';
const TERMII_SENDER           = Deno.env.get('TERMII_SENDER_ID') ?? 'RainbowHQ';
const TERMII_URL              = Deno.env.get('TERMII_BASE_URL') ?? 'https://v4.api.termii.com/api/sms/send';
const WEBHOOK_SECRET          = Deno.env.get('RAINBOW_WEBHOOK_SECRET') ?? '';
const DRAIN_BATCH             = 20;

// Exponential backoff caps at 1 hour
const backoffSeconds = (attempts: number) =>
  Math.min(3600, Math.pow(2, attempts) * 30);

// ── Supabase client (service role — reads notification_outbox) ────────────────
function getSupabase() {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY, {
    auth: { persistSession: false },
  });
}

// ── Delivery methods ──────────────────────────────────────────────────────────

async function deliverPush(payload: Record<string, unknown>): Promise<void> {
  if (!ONESIGNAL_REST_API_KEY) throw new Error('ONESIGNAL_REST_API_KEY not set');
  const body = {
    app_id: ONESIGNAL_APP_ID,
    headings: { en: payload.heading ?? '🚨 Alert Update' },
    contents: { en: payload.body ?? 'An incident has been updated.' },
    data: payload.data ?? {},
    ...(payload.player_ids
      ? { include_player_ids: payload.player_ids }
      : { included_segments: ['Active Users'] }),
  };
  const res = await fetch('https://onesignal.com/api/v1/notifications', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Key ${ONESIGNAL_REST_API_KEY}`,
    },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const err = await res.text();
    throw new Error(`OneSignal ${res.status}: ${err}`);
  }
}

async function deliverSms(payload: Record<string, unknown>): Promise<void> {
  if (!TERMII_API_KEY) throw new Error('TERMII_API_KEY not set');
  const phone = String(payload.phone ?? '').replace(/\D/g, '');
  if (!phone) throw new Error('Missing phone in SMS payload');
  const res = await fetch(TERMII_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      to:      phone,
      from:    TERMII_SENDER,
      sms:     payload.message ?? 'Operation Rainbow notification.',
      type:    'plain',
      api_key: TERMII_API_KEY,
      channel: 'dnd',
    }),
  });
  if (!res.ok) {
    const err = await res.text();
    throw new Error(`Termii ${res.status}: ${err}`);
  }
}

async function deliverWebhook(payload: Record<string, unknown>): Promise<void> {
  const url = String(payload.url ?? '');
  if (!url) throw new Error('Missing webhook URL in payload');
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Rainbow-Auth': WEBHOOK_SECRET,
    },
    body: JSON.stringify(payload.body ?? payload),
  });
  if (!res.ok) {
    const err = await res.text();
    throw new Error(`Webhook ${res.status}: ${err}`);
  }
}

// ── Main handler ──────────────────────────────────────────────────────────────

serve(async (_req: Request) => {
  const supabase = getSupabase();
  const results: { id: number; kind: string; ok: boolean; error?: string }[] = [];

  // 1. Claim a batch (SKIP LOCKED — safe to run concurrently)
  const { data: rows, error: claimErr } = await supabase
    .rpc('claim_notifications', { p_limit: DRAIN_BATCH });

  if (claimErr) {
    console.error('[DRAIN] claim_notifications failed:', claimErr.message);
    return new Response(JSON.stringify({ error: claimErr.message }), { status: 500 });
  }

  if (!rows || rows.length === 0) {
    return new Response(JSON.stringify({ drained: 0 }), { status: 200 });
  }

  // 2. Deliver each row
  for (const row of rows) {
    const payload = row.payload as Record<string, unknown>;
    let ok = false;
    let errorMsg: string | undefined;

    try {
      switch (row.kind) {
        case 'PUSH':    await deliverPush(payload);    break;
        case 'SMS':     await deliverSms(payload);     break;
        case 'WEBHOOK': await deliverWebhook(payload); break;
        default:
          console.warn(`[DRAIN] Unknown kind: ${row.kind} — marking delivered`);
      }
      ok = true;
    } catch (e) {
      errorMsg = e instanceof Error ? e.message : String(e);
      console.error(`[DRAIN] row ${row.id} (${row.kind}) failed:`, errorMsg);
    }

    // 3. Mark delivered or schedule retry
    if (ok) {
      await supabase
        .from('notification_outbox')
        .update({ delivered_at: new Date().toISOString(), last_error: null })
        .eq('id', row.id);
    } else {
      const nextAttempt = new Date(
        Date.now() + backoffSeconds(row.attempts + 1) * 1000
      ).toISOString();
      await supabase
        .from('notification_outbox')
        .update({
          attempts:       row.attempts + 1,
          last_error:     errorMsg,
          next_attempt_at: nextAttempt,
        })
        .eq('id', row.id);
    }

    results.push({ id: row.id, kind: row.kind, ok, error: errorMsg });
  }

  const delivered = results.filter(r => r.ok).length;
  const failed    = results.filter(r => !r.ok).length;
  console.log(`[DRAIN] batch complete: ${delivered} delivered, ${failed} failed`);

  return new Response(
    JSON.stringify({ drained: delivered, failed, results }),
    { status: 200, headers: { 'Content-Type': 'application/json' } },
  );
});
