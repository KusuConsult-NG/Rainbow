import { NextResponse } from 'next/server';
import { requireUser } from '@/lib/supabase-server';
import { serverEnv } from '@/lib/env';

/**
 * Citizen SOS → escalation SMS to the HQ dispatch line.
 *
 * ## Why this route exists (finding H-3)
 *
 * The mobile app used to call Termii directly, which meant `TERMII_API_KEY` had
 * to be in `.env` — and `pubspec.yaml` declares `.env` as a Flutter ASSET, so it
 * ships verbatim inside the APK and extracts with `unzip`. Anyone who downloaded
 * the app owned the SMS credential for an emergency service.
 *
 * The key now lives only here. The app sends its Supabase access token and the
 * facts of the incident; it never sees the credential.
 *
 * ## Why this is not an open SMS relay
 *
 * Moving a credential server-side is worthless if the endpoint will send anything
 * anywhere on request. Three constraints, all enforced below:
 *
 *  1. **The recipient is not client-supplied.** It comes from `SOS_DISPATCH_PHONE`.
 *  2. **The message body is not client-supplied.** The caller sends structured
 *     fields (alert id, coordinates); this route composes the text. There is no
 *     path by which caller-controlled prose reaches an SMS from the HQ sender ID.
 *  3. **The caller must be an authenticated Supabase user**, verified against the
 *     auth server rather than by locally decoding a JWT.
 *
 * ## What this route deliberately does NOT do
 *
 * It does not decide whether the SOS is real, and it does not write the alert.
 * The alert row in Supabase is the system of record; this SMS is a redundant
 * out-of-band nudge. A failure here must never fail the SOS — hence the response
 * always carries a status the client logs rather than an error it retries on.
 */

/** Max SOS SMS per user per window. Sized for "panic-tapped a few times", not throughput. */
const RATE_LIMIT = 3;
const RATE_WINDOW_MS = 5 * 60 * 1000;

/**
 * Best-effort per-user throttle.
 *
 * Honest limitation: this is per server instance and resets on cold start, so on
 * a multi-instance or serverless deployment it bounds the common case (one user's
 * app retrying) and not a determined authenticated attacker. A durable limit
 * belongs in the database or at the edge; this is the cheap 90% and is documented
 * as such rather than presented as a security control.
 */
const recentSends = new Map<string, number[]>();

function rateLimited(userId: string): boolean {
  const now = Date.now();
  const hits = (recentSends.get(userId) ?? []).filter((t) => now - t < RATE_WINDOW_MS);
  if (hits.length >= RATE_LIMIT) {
    recentSends.set(userId, hits);
    return true;
  }
  hits.push(now);
  recentSends.set(userId, hits);

  // Bound the map so a long-lived instance cannot grow it without limit.
  if (recentSends.size > 5000) {
    for (const [key, stamps] of recentSends) {
      if (stamps.every((t) => now - t >= RATE_WINDOW_MS)) recentSends.delete(key);
    }
  }
  return false;
}

/** Accept a coordinate only if it is a real, in-range number. */
function coord(value: unknown, limit: number): number | null {
  if (typeof value !== 'number' || !Number.isFinite(value)) return null;
  if (Math.abs(value) > limit) return null;
  return value;
}

export async function POST(request: Request) {
  try {
    const auth = await requireUser(request);
    if (!auth.ok) {
      return NextResponse.json({ error: auth.error }, { status: auth.status });
    }

    let body: { alertId?: unknown; latitude?: unknown; longitude?: unknown };
    try {
      body = await request.json();
    } catch {
      return NextResponse.json({ error: 'Malformed JSON body' }, { status: 400 });
    }

    if (rateLimited(auth.userId)) {
      return NextResponse.json(
        { error: 'Too many SOS dispatches — the alert itself was still recorded.' },
        { status: 429 }
      );
    }

    // Only ever used as an 8-char reference, stripped to characters a UUID can contain.
    const alertRef =
      typeof body.alertId === 'string'
        ? body.alertId.replace(/[^A-Za-z0-9-]/g, '').slice(0, 8).toUpperCase()
        : '';

    const lat = coord(body.latitude, 90);
    const lng = coord(body.longitude, 180);

    const { termiiApiKey, termiiSenderId, sosDispatchPhone } = serverEnv();

    if (!termiiApiKey || !sosDispatchPhone) {
      // Not an error for the caller: the alert row is the system of record. Say so
      // plainly instead of returning a misleading success.
      console.warn('[SOS_SMS] Skipped — TERMII_API_KEY or SOS_DISPATCH_PHONE unset.');
      return NextResponse.json({ sms: 'SKIPPED', reason: 'not configured' }, { status: 200 });
    }

    // Composed here, from validated fields only. `lat`/`lng` are numbers by this
    // point and `alertRef` is [A-Za-z0-9-]{0,8}; nothing the caller typed appears.
    const location =
      lat !== null && lng !== null
        ? `${lat.toFixed(5)}, ${lng.toFixed(5)}`
        : 'NO GPS FIX — location unknown';

    const smsBody = [
      '[OPERATION RAINBOW — CITIZEN SOS]',
      `Ref: ${alertRef || 'PENDING'}`,
      `User: ${auth.userId.slice(0, 8).toUpperCase()}`,
      `Location: ${location}`,
      `Time: ${new Date().toLocaleString('en-NG', { timeZone: 'Africa/Lagos' })}`,
      'Dispatch immediately.',
    ].join('\n');

    try {
      const res = await fetch('https://v3.api.termii.com/api/sms/send', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          to: sosDispatchPhone,
          from: termiiSenderId,
          sms: smsBody,
          type: 'plain',
          api_key: termiiApiKey,
          channel: 'dnd',
        }),
      });

      if (!res.ok) {
        // Log the provider's reason server-side; do not echo it to the client,
        // which would leak account detail to any authenticated user.
        console.error('[SOS_SMS] Termii rejected the send:', res.status, await res.text());
        return NextResponse.json({ sms: 'FAILED' }, { status: 200 });
      }
      return NextResponse.json({ sms: 'SENT' }, { status: 200 });
    } catch (err) {
      console.error('[SOS_SMS] Termii request failed:', err);
      return NextResponse.json({ sms: 'FAILED' }, { status: 200 });
    }
  } catch (err) {
    console.error('[SOS_SMS_ERR]', err);
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 });
  }
}
