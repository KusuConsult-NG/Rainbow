/**
 * Alerts arriving by SMS, from a handset with signal but no data.
 *
 * ## This replaces `smsWebhook`, which accepted anything
 *
 * The Firebase function this supersedes was unauthenticated: anyone who found
 * the URL could inject an emergency into the system, and this audit flagged it
 * for deletion. Two things are different here.
 *
 * First, the GATEWAY is authenticated — a shared secret in a header, compared
 * in constant time — so the endpoint only talks to the SMS provider.
 *
 * Second, and more importantly, the MESSAGE is authenticated. The body is
 * sealed with a per-device AES-GCM key, so even a caller who gets past the
 * gateway check cannot forge an alert: they would have to produce a valid tag
 * for a key they do not have. The gateway secret protects the endpoint; the
 * device key protects the truth of what it records.
 *
 * ## It tells the caller as little as possible
 *
 * Every rejection is the same response. A wrong gateway secret, an unknown
 * device ref, a bad tag, a replay and a malformed body are indistinguishable
 * from outside, because the differences would let somebody search for valid
 * device references or confirm that a particular handset is registered.
 *
 * The only thing that varies is between "accepted" and "not", and even that is
 * 200 either way to the gateway — a provider that retries on a non-2xx would
 * otherwise turn one rejected message into a retry storm.
 */

import { NextRequest, NextResponse } from 'next/server';
import { timingSafeEqual } from 'node:crypto';

import { getSupabaseAdmin } from '@/lib/supabase-server';
import {
  categoryLabel,
  decodeSmsAlert,
  readDeviceRef,
  severityLabel,
} from '@/lib/sms-alert-codec';

/**
 * Always the same answer, whatever went wrong.
 *
 * A FUNCTION, not a shared constant. A `Response` body is a stream that can be
 * read once, so a single module-level instance returned from every rejection
 * works for the first refused message of the process's life and then throws
 * "Body has already been read" for every one after it — which would turn a
 * flood of malformed messages into a dead endpoint. Caught by the test below
 * that refuses twice in a row.
 */
const ack = () => NextResponse.json({ ok: true });

function secretMatches(provided: string | null, expected: string): boolean {
  if (!provided || !expected) return false;
  const a = Buffer.from(provided);
  const b = Buffer.from(expected);
  // timingSafeEqual throws on a length mismatch, which would itself leak the
  // expected length.
  if (a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}

export async function POST(req: NextRequest) {
  const expected = process.env.SMS_GATEWAY_SECRET ?? '';
  if (!expected) {
    // Refusing to run unconfigured rather than accepting everything, which is
    // how the function this replaces behaved.
    console.error('[SMS_INBOUND] SMS_GATEWAY_SECRET is not set — refusing');
    return ack();
  }
  if (!secretMatches(req.headers.get('x-gateway-secret'), expected)) {
    console.warn('[SMS_INBOUND] rejected: gateway secret');
    return ack();
  }

  let body: string | null = null;
  let from: string | null = null;
  try {
    const json = (await req.json()) as Record<string, unknown>;
    // Termii and most gateways post `{ text, msisdn }`; accept the common
    // spellings rather than coupling this to one provider.
    body = (json.text ?? json.message ?? json.body ?? null) as string | null;
    from = (json.msisdn ?? json.from ?? json.sender ?? null) as string | null;
  } catch {
    return ack();
  }
  if (typeof body !== 'string') return ack();

  const deviceRef = readDeviceRef(body);
  if (!deviceRef) return ack();

  const supabase = getSupabaseAdmin();

  // Which key sealed this? Service-role only; a phone or a browser cannot
  // reach this function at all.
  const { data: keyRows, error: keyErr } = await supabase
    .rpc('sms_key_for_ingest', { p_ref: `\\x${deviceRef}` });
  if (keyErr || !Array.isArray(keyRows) || keyRows.length === 0) {
    console.warn('[SMS_INBOUND] rejected: no live key for that device');
    return ack();
  }
  const row = keyRows[0] as { user_id: string; secret: string };
  const secret = Buffer.from(String(row.secret).replace(/^\\x/, ''), 'hex');

  const alert = decodeSmsAlert(body, secret);
  if (!alert) {
    // A forgery, a replay of a revoked key, or corruption in transit. All the
    // same from here.
    console.warn('[SMS_INBOUND] rejected: message did not authenticate');
    return ack();
  }

  // Deduplicate against the reporter's own offline queue. The same incident
  // will very often arrive twice: once by SMS now, and again when the phone
  // regains data and replays its queue. `local_id` is the shared identity, and
  // the SMS carries its first six bytes.
  const { data: existing } = await supabase
    .from('alerts')
    .select('id')
    .eq('reported_by', row.user_id)
    .like('local_id', `%${alert.localRef}%`)
    .limit(1);
  if (existing && existing.length > 0) {
    return NextResponse.json({ ok: true, duplicate: true });
  }

  const { error: insertErr } = await supabase.from('alerts').insert({
    type: categoryLabel(alert.categoryCode),
    description: alert.isDuress
      ? 'DURESS alert received by SMS. The reporter had no data connection.'
      : 'Reported by SMS. The reporter had no data connection.',
    severity: alert.isDuress ? 'CRITICAL' : severityLabel(alert.severityCode),
    reported_by: alert.isAnonymous ? null : row.user_id,
    latitude: alert.latitude,
    longitude: alert.longitude,
    // WHEN THE PHONE RAISED IT. An SMS can sit in a carrier queue for minutes,
    // and a dispatcher must not read a ten-minute-old kidnapping as new.
    created_at: alert.sentAt.toISOString(),
    local_id: alert.localRef,
    // So the board can show that this arrived over a degraded channel — not
    // because the content is untrusted, it is authenticated, but because a
    // phone that could not reach the network is itself significant.
    arrived_via: 'SMS',
  });
  if (insertErr) {
    console.error('[SMS_INBOUND] could not record the alert:', insertErr);
    return ack();
  }

  console.warn(
    `[SMS_INBOUND] accepted ${alert.isDuress ? 'DURESS ' : ''}alert from ` +
      `device ${deviceRef}${from ? ` (${from})` : ''}`,
  );
  return NextResponse.json({ ok: true, accepted: true });
}
