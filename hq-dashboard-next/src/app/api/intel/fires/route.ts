import { NextResponse } from 'next/server';
import { PLATEAU_BBOX, placeInPlateau } from '@/lib/fire-place';
import { FIRMS_SOURCES, firmsAreaUrl, parseFirmsCsv, redactKey, type FireDetection } from '@/lib/fires';
import { getSupabaseAdmin } from '@/lib/supabase-server';

/**
 * Fetches NASA FIRMS fire detections over Plateau and records them.
 *
 * Phase 2 of the intelligence layer. VIIRS on three satellites reports every
 * hot 375 m pixel within about three hours of a pass; this keeps the ones
 * inside Plateau's LGA polygons, places each in an LGA and ward, and writes
 * them to `fire_detections` (migration 20261119000000). What a detection
 * means is decided elsewhere: near an open incident it is one more source in
 * the console's corroboration score.
 *
 * ## Authorisation and keys
 *
 * A shared secret, `INTEL_INGEST_SECRET`, as `/api/notify/drain` uses: nobody
 * is signed in when a scheduler calls this. Compared in constant time. Unset,
 * the endpoint refuses to run rather than run open.
 *
 * `FIRMS_MAP_KEY` is NASA's free key (firms.modaps.eosdis.nasa.gov, "Map Key").
 * It travels in the request PATH, so every error recorded or returned has it
 * redacted, and the URL itself is never logged.
 *
 * ## Running it
 *
 * Every 30 minutes, from a Railway cron service:
 *
 *     curl -fsS -X POST https://<host>/api/intel/fires \
 *       -H "x-intel-secret: $INTEL_INGEST_SECRET"
 *
 * Each call asks for the last day from each satellite, so a missed run or two
 * loses nothing; the unique constraint drops what is already recorded. Every
 * run, good or bad, is a row in `intel_ingest_runs`, which is how the console
 * says how fresh the fire layer is.
 */

export const dynamic = 'force-dynamic';

const FETCH_TIMEOUT_MS = 30_000;

function secretsMatch(given: string, expected: string): boolean {
  if (given.length !== expected.length) return false;
  let diff = 0;
  for (let i = 0; i < given.length; i += 1) diff |= given.charCodeAt(i) ^ expected.charCodeAt(i);
  return diff === 0;
}

interface Placed extends FireDetection {
  geo_lga: string;
  geo_ward: string | null;
}

export async function POST(request: Request) {
  const expected = process.env.INTEL_INGEST_SECRET ?? '';
  if (!expected) {
    console.error('[INTEL_FIRES] INTEL_INGEST_SECRET is not configured');
    return NextResponse.json({ error: 'Not configured' }, { status: 503 });
  }
  if (!secretsMatch(request.headers.get('x-intel-secret') ?? '', expected)) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  const supabase = getSupabaseAdmin();
  const key = process.env.FIRMS_MAP_KEY ?? '';
  const record = (ok: boolean, seen: number, added: number, error: string | null) =>
    supabase.from('intel_ingest_runs').insert({ feed: 'FIRMS', ok, seen, added, error });

  if (!key) {
    await record(false, 0, 0, 'FIRMS_MAP_KEY is not configured');
    return NextResponse.json({ error: 'FIRMS_MAP_KEY is not configured' }, { status: 503 });
  }

  const placed: Placed[] = [];
  const failures: string[] = [];
  let rejected = 0;

  for (const source of FIRMS_SOURCES) {
    try {
      const res = await fetch(firmsAreaUrl(key, source, PLATEAU_BBOX, 1), {
        signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
        cache: 'no-store',
      });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const parsed = parseFirmsCsv(await res.text(), source);
      rejected += parsed.rejected;
      for (const d of parsed.detections) {
        const where = placeInPlateau(d.latitude, d.longitude);
        if (where) placed.push({ ...d, geo_lga: where.lga, geo_ward: where.ward });
      }
    } catch (e) {
      failures.push(`${source}: ${redactKey(e instanceof Error ? e.message : String(e), key)}`);
    }
  }

  let added = 0;
  if (placed.length > 0) {
    const { data, error } = await supabase
      .from('fire_detections')
      .upsert(placed, { onConflict: 'satellite,observed_at,latitude,longitude', ignoreDuplicates: true })
      .select('id');
    if (error) {
      const message = `write failed: ${redactKey(error.message, key)}`;
      await record(false, placed.length, 0, message);
      return NextResponse.json({ error: message }, { status: 500 });
    }
    added = data?.length ?? 0;
  }

  // A run is good only if every satellite answered: one silent satellite is a
  // third of the passes missing, and the layer must not call itself current.
  const ok = failures.length === 0;
  const note = [...failures, ...(rejected > 0 ? [`${rejected} malformed row(s) skipped`] : [])].join('; ') || null;
  await record(ok, placed.length, added, note);

  return NextResponse.json(
    { ok, seen: placed.length, added, rejected, failures },
    { status: ok ? 200 : 502 },
  );
}
