/**
 * Alerts arriving from the mesh, uploaded by whichever phone reached a network.
 *
 * ## The one endpoint in this system that cannot require a session
 *
 * Every other API route here authenticates its caller, and this audit added
 * that check to the ones that did not. This route deliberately does not, and the
 * reason is the scenario it exists for: during a network shutdown the phone that
 * gets a signal back first may be a stranger's, may be signed out, may be a
 * handset whose own token expired days ago. Insisting on a session would mean
 * the mesh works only when it is not needed.
 *
 * So this is an unauthenticated write path into an emergency system, and it has
 * to be built like one. What makes it safe is not who is calling but **what they
 * can say**:
 *
 *   * A frame's contents are sealed to HQ's public key, and inside that seal is
 *     an SMS-format payload authenticated by a per-device AES-GCM key. A caller
 *     who cannot produce a valid tag for a registered device cannot invent an
 *     alert. The relay uploading it certainly cannot — it never could read it.
 *   * So the worst an anonymous caller can do is waste our time: submit garbage,
 *     or replay frames they captured. Both are bounded below.
 *
 * ## What bounds the damage
 *
 * | control            | what it stops                                        |
 * |--------------------|------------------------------------------------------|
 * | body size cap      | the endpoint used as a file upload                   |
 * | frames per request | one POST costing us an unbounded amount of work      |
 * | per-IP rate limit  | one host flooding                                    |
 * | envelope-id dedup  | the same frame, by many paths, becoming many alerts  |
 * | freshness window   | a captured frame replayed for ever                   |
 * | `local_id` dedup   | the reporter's own queue duplicating their report    |
 *
 * The rate limit is **per running instance**, which is honest rather than
 * sufficient: on a platform that scales this route out, ten instances permit ten
 * times the traffic. It is a brake on the obvious case, not a defence against a
 * distributed flood — that belongs at the edge, and is noted in the design doc as
 * an operational requirement rather than quietly assumed here.
 *
 * ## Every frame gets the same answer
 *
 * The response lists the frames this endpoint is finished with, and a relay
 * drops exactly those from its outbox. Accepted, already-seen, sealed to another
 * key, undecryptable garbage — all the same. That is deliberate: a relay that
 * could tell which frames HQ actually wanted would be able to tell which of the
 * phones around it are reporting, and it is a stranger's phone.
 */

import { NextRequest, NextResponse } from 'next/server';

import { decodeMeshFrameBase64, meshFrameIsFresh, type MeshFrame } from '@/lib/mesh-envelope';
import { meshOpen, meshPrivateKeyFromHex } from '@/lib/mesh-sealer';
import { recordOfflineAlert } from '@/lib/offline-alert-ingest';
import { getSupabaseAdmin } from '@/lib/supabase-server';

// node:crypto, via the sealer. Explicit so an accidental edge migration fails
// the build rather than failing at 2am on the one night the mesh is carrying
// traffic.
export const runtime = 'nodejs';

/** A relay with a queue uploads in one go, but not without limit. */
const MAX_FRAMES_PER_REQUEST = 32;

/** 32 frames of 512 bytes, base64, with room for JSON around them. */
const MAX_BODY_BYTES = 64 * 1024;

/** Requests per window, per IP. */
const RATE_LIMIT = 30;
const RATE_WINDOW_MS = 60 * 1000;

/**
 * Per-instance, in-memory. Bounded, so the rate limiter cannot itself be used to
 * exhaust the process's memory — the thing rate limiters are embarrassingly
 * often used for.
 */
const hits = new Map<string, number[]>();
const MAX_TRACKED_IPS = 4096;

function rateLimited(ip: string, now: number): boolean {
  const recent = (hits.get(ip) ?? []).filter((t) => now - t < RATE_WINDOW_MS);
  if (recent.length >= RATE_LIMIT) {
    hits.set(ip, recent);
    return true;
  }
  recent.push(now);
  hits.set(ip, recent);
  if (hits.size > MAX_TRACKED_IPS) {
    for (const [key, times] of hits) {
      if (times.every((t) => now - t >= RATE_WINDOW_MS)) hits.delete(key);
      if (hits.size <= MAX_TRACKED_IPS) break;
    }
  }
  return false;
}

/** Exported for the tests, which must not inherit another test's budget. */
export function __resetMeshRateLimit(): void {
  hits.clear();
}

function callerIp(req: NextRequest): string {
  // Behind a proxy the socket address is the proxy's. The left-most entry of
  // x-forwarded-for is client-controlled and therefore not trustworthy as
  // identity — but this is a brake, not an authorisation decision, and using it
  // spreads legitimate relays behind one NAT across separate buckets instead of
  // lumping them together.
  const fwd = req.headers.get('x-forwarded-for') ?? '';
  const first = fwd.split(',')[0]?.trim();
  return first || req.headers.get('x-real-ip') || 'unknown';
}

export async function POST(req: NextRequest) {
  const now = Date.now();
  const ip = callerIp(req);

  const declared = Number(req.headers.get('content-length') ?? '0');
  if (Number.isFinite(declared) && declared > MAX_BODY_BYTES) {
    return NextResponse.json({ ok: true, done: [] }, { status: 200 });
  }
  if (rateLimited(ip, now)) {
    console.warn('[MESH_INGEST] rate limited a relay');
    // 429 rather than a silent 200: this one IS safe to say out loud, it tells
    // an honest relay to come back later rather than retry immediately, and it
    // reveals nothing about any frame.
    return NextResponse.json({ ok: false, retryAfter: 60 }, { status: 429 });
  }

  const hqKey = meshPrivateKeyFromHex(process.env.MESH_HQ_PRIVATE_KEY);
  if (!hqKey) {
    console.error('[MESH_INGEST] MESH_HQ_PRIVATE_KEY is not configured — refusing');
    return NextResponse.json({ ok: true, done: [] }, { status: 200 });
  }

  let raw: string;
  try {
    raw = await req.text();
  } catch {
    return NextResponse.json({ ok: true, done: [] }, { status: 200 });
  }
  // The declared length is a hint; this is the actual one.
  if (raw.length > MAX_BODY_BYTES) {
    return NextResponse.json({ ok: true, done: [] }, { status: 200 });
  }

  let submitted: unknown;
  try {
    submitted = JSON.parse(raw);
  } catch {
    return NextResponse.json({ ok: true, done: [] }, { status: 200 });
  }
  const payload = (submitted ?? {}) as Record<string, unknown>;
  const list = Array.isArray(payload.frames)
    ? payload.frames
    : typeof payload.frame === 'string'
      ? [payload.frame]
      : [];

  const done: string[] = [];
  let accepted = 0;
  let discarded = 0;
  const supabase = getSupabaseAdmin();

  for (const entry of list.slice(0, MAX_FRAMES_PER_REQUEST)) {
    if (typeof entry !== 'string') {
      discarded += 1;
      continue;
    }
    const frame = decodeMeshFrameBase64(entry);
    if (!frame) {
      // Nothing to acknowledge: without a valid frame there is no id to name,
      // and a relay holding bytes this malformed did not get them from this app.
      discarded += 1;
      continue;
    }

    // Acknowledged whatever happens next, so the relay stops carrying it and the
    // answer says nothing about whether we wanted it.
    done.push(frame.id);

    if (!meshFrameIsFresh(frame, new Date(now))) {
      discarded += 1;
      continue;
    }

    // Before decryption, and cheaper than it: the same frame will arrive many
    // times by different paths, because that is how flooding works.
    const fresh = await noteEnvelope(supabase, frame);
    if (!fresh) continue;

    const opened = meshOpen(frame.sealed, hqKey);
    if (!opened) {
      // Sealed to a key we do not hold, tampered with in transit, or invented.
      discarded += 1;
      continue;
    }

    // The plaintext is an SMS-format body — see mesh_alert_envelope.dart for why
    // — so it is authenticated per-device and recorded by exactly the same code
    // as an SMS.
    const outcome = await recordOfflineAlert(
      supabase,
      opened.toString('ascii'),
      'MESH',
    );
    if (outcome === 'accepted') accepted += 1;
    else discarded += 1;
  }

  if (accepted > 0 || discarded > 0) {
    console.warn(
      `[MESH_INGEST] ${accepted} recorded, ${discarded} discarded, ` +
        `${done.length} acknowledged`,
    );
  }
  // `done` is the whole answer. Deliberately no per-frame outcome.
  return NextResponse.json({ ok: true, done }, { status: 200 });
}

/**
 * Records that this envelope arrived, and says whether it is the first time.
 *
 * The arrival count is kept rather than discarded: how many times one envelope
 * reaches HQ, by how many paths, is the only measure of mesh health we can get
 * without asking handsets to report on each other.
 *
 * Fails OPEN — an error here returns "first time" — because losing an alert
 * because the dedup table was unavailable is far worse than recording an
 * incident twice. A duplicate is visible to a dispatcher; a dropped duress alert
 * is not visible to anyone.
 */
async function noteEnvelope(
  supabase: ReturnType<typeof getSupabaseAdmin>,
  frame: MeshFrame,
): Promise<boolean> {
  try {
    const { data, error } = await supabase.rpc('mesh_note_envelope', {
      p_id: `\\x${frame.id}`,
    });
    if (error) {
      console.error('[MESH_INGEST] envelope dedup unavailable:', error);
      return true;
    }
    return data !== false;
  } catch (err) {
    console.error('[MESH_INGEST] envelope dedup threw:', err);
    return true;
  }
}
