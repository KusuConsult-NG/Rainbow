import { NextResponse } from 'next/server';
import { requireRole, COMMAND_ROLES } from '@/lib/supabase-server';
import { serverEnv } from '@/lib/env';

/**
 * The ICE servers a live feed should use.
 *
 * ## Why a route and not NEXT_PUBLIC_
 *
 * A TURN server takes a credential. `NEXT_PUBLIC_*` is inlined into the client
 * bundle at BUILD time, so it would be served to every visitor and frozen at
 * whatever the build machine had — and `src/lib/env.ts` carries the note
 * explaining that this project already shipped its Gemini key that way. The
 * same mistake with a TURN credential is a relay anybody can bill.
 *
 * So the credential stays in `serverEnv()` and is handed out here, to a signed-
 * in operator, per request. It can be rotated without a rebuild.
 *
 * ## Why there is a route at all
 *
 * `LiveFeedViewer.tsx` and the handset's `live_stream_service.dart` each had
 * three public STUN servers written in as literals and no TURN server. STUN
 * discovers an address; it cannot relay. A citizen's handset is behind
 * carrier-grade NAT, which is commonly symmetric, and symmetric NAT on either
 * side defeats hole punching — so with STUN alone the media has no route and
 * the connection never completes. The feature whose entire purpose is for
 * somebody in danger to show HQ what is happening worked when the network
 * happened to allow it, which for a phone on mobile data is the exception.
 *
 * `hasRelay` is returned so the viewer can say which it has rather than
 * leaving an operator watching a spinner. See E2E_AUDIT_REPORT.md T-96.
 */
export const dynamic = 'force-dynamic';

export async function GET() {
  const auth = await requireRole(COMMAND_ROLES);
  if (!auth.ok) {
    return NextResponse.json({ error: auth.error }, { status: auth.status });
  }

  const env = serverEnv();
  const iceServers: RTCIceServer[] = [
    { urls: 'stun:stun.l.google.com:19302' },
    { urls: 'stun:stun1.l.google.com:19302' },
    { urls: 'stun:stun2.l.google.com:19302' },
  ];

  // A TURN URL that is not a turn:/turns: URI is ignored by the peer connection
  // without complaint — configured, and no different from unconfigured. Refused
  // here so `hasRelay` cannot be true while the relay does nothing.
  const url = env.turnUrl.trim();
  const usable = url.startsWith('turn:') || url.startsWith('turns:');
  if (url && !usable) {
    console.warn(
      `[RTC_CONFIG] TURN_URL is "${url}", which is not a turn: or turns: URI. ` +
        'Ignoring it — a malformed relay is indistinguishable from none.',
    );
  }
  if (usable) {
    iceServers.push({
      urls: url,
      ...(env.turnUsername ? { username: env.turnUsername } : {}),
      ...(env.turnCredential ? { credential: env.turnCredential } : {}),
    });
  }

  return NextResponse.json(
    { iceServers, hasRelay: usable },
    // Never cached: it carries a credential, and a rotated one has to take
    // effect on the next request.
    { headers: { 'Cache-Control': 'no-store' } },
  );
}
