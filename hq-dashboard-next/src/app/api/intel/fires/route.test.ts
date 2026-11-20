// Recording NASA FIRMS fire detections over Plateau.
//
// What must hold: only the scheduler can run it; a detection outside Plateau
// is not recorded; every run says whether it worked; a satellite that did not
// answer makes the run a failure, not a quiet night; and the key, which FIRMS
// takes in the URL path, never reaches a stored error or a response.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { wardCentroids } from '@/lib/ward_centroids';

const SECRET = 'a-long-shared-intel-secret';
const KEY = 'firms-key-abc123';

let runs: Record<string, unknown>[] = [];
let upserted: Record<string, unknown>[][] = [];
let upsertError: { message: string } | null = null;

vi.mock('@/lib/supabase-server', () => ({
  getSupabaseAdmin: () => ({
    from: (table: string) => ({
      insert: async (row: Record<string, unknown>) => {
        if (table === 'intel_ingest_runs') runs.push(row);
        return { error: null };
      },
      upsert: (rows: Record<string, unknown>[]) => ({
        select: async () => {
          if (upsertError) return { data: null, error: upsertError };
          upserted.push(rows);
          return { data: rows.map((_, i) => ({ id: `f${i}` })), error: null };
        },
      }),
    }),
  }),
}));

const HEADER = 'latitude,longitude,bright_ti4,scan,track,acq_date,acq_time,satellite,confidence,version,bright_ti5,frp,daynight';
const wase = wardCentroids.find((w) => w.lga === 'WASE')!;
const csv = (...rows: string[]) => [HEADER, ...rows].join('\n');
const IN_PLATEAU = `${wase.lat},${wase.lng},340,0.4,0.4,2026-11-18,0022,N20,nominal,2.0NRT,300,12.5,N`;
const IN_BAUCHI = '10.31,9.84,340,0.4,0.4,2026-11-18,0022,N20,high,2.0NRT,300,40,N';

type Answer = { status: number; body: string } | Error;
let answers: Record<string, Answer> = {};

beforeEach(() => {
  runs = [];
  upserted = [];
  upsertError = null;
  answers = {};
  vi.stubEnv('INTEL_INGEST_SECRET', SECRET);
  vi.stubEnv('FIRMS_MAP_KEY', KEY);
  vi.stubGlobal('fetch', vi.fn(async (url: string) => {
    const source = String(url).split('/')[7];
    const a = answers[source] ?? { status: 200, body: HEADER };
    if (a instanceof Error) throw a;
    return new Response(a.body, { status: a.status });
  }));
});
afterEach(() => {
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
});

async function run(headers: Record<string, string> = { 'x-intel-secret': SECRET }) {
  const { POST } = await import('./route');
  return POST(new Request('http://localhost/api/intel/fires', { method: 'POST', headers }));
}

describe('who may run it', () => {
  it('refuses without the secret', async () => {
    expect((await run({})).status).toBe(401);
    expect((await run({ 'x-intel-secret': 'wrong' })).status).toBe(401);
    expect(runs).toEqual([]);
  });

  it('refuses to run open when no secret is configured', async () => {
    vi.stubEnv('INTEL_INGEST_SECRET', '');
    expect((await run()).status).toBe(503);
  });
});

describe('a run', () => {
  it('records detections inside Plateau, with their LGA and ward, and nothing outside', async () => {
    answers.VIIRS_NOAA20_NRT = { status: 200, body: csv(IN_PLATEAU, IN_BAUCHI) };
    const res = await run();
    expect(res.status).toBe(200);
    expect(upserted).toHaveLength(1);
    expect(upserted[0]).toHaveLength(1);
    expect(upserted[0][0]).toMatchObject({
      source: 'VIIRS_NOAA20_NRT',
      satellite: 'N20',
      observed_at: '2026-11-18T00:22:00Z',
      daynight: 'N',
      geo_lga: 'WASE',
      geo_ward: wase.ward,
    });
    expect(runs).toEqual([{ feed: 'FIRMS', ok: true, seen: 1, added: 1, error: null }]);
  });

  it('asks all three satellites for the last day of the Plateau box', async () => {
    await run();
    const urls = (fetch as unknown as { mock: { calls: string[][] } }).mock.calls.map((c) => c[0]);
    expect(urls.map((u) => u.split('/')[7])).toEqual(['VIIRS_SNPP_NRT', 'VIIRS_NOAA20_NRT', 'VIIRS_NOAA21_NRT']);
    expect(urls.every((u) => u.endsWith('/1'))).toBe(true);
  });

  it('a quiet night with every satellite answering is a good run with nothing added', async () => {
    const res = await run();
    expect(res.status).toBe(200);
    expect(runs).toEqual([{ feed: 'FIRMS', ok: true, seen: 0, added: 0, error: null }]);
  });
});

describe('failures are said, never quiet', () => {
  it('a satellite that does not answer makes the run a failure, while keeping what the others saw', async () => {
    answers.VIIRS_SNPP_NRT = new Error('network unreachable');
    answers.VIIRS_NOAA20_NRT = { status: 200, body: csv(IN_PLATEAU) };
    const res = await run();
    expect(res.status).toBe(502);
    expect(upserted[0]).toHaveLength(1);
    expect(runs[0]).toMatchObject({ ok: false, seen: 1, added: 1 });
    expect(String(runs[0].error)).toContain('VIIRS_SNPP_NRT: network unreachable');
  });

  it('an invalid key answer is a failure, not "no fires"', async () => {
    answers.VIIRS_SNPP_NRT = { status: 200, body: 'Invalid MAP_KEY.' };
    const res = await run();
    expect(res.status).toBe(502);
    expect(runs[0]).toMatchObject({ ok: false });
  });

  it('records a missing key as a failed run', async () => {
    vi.stubEnv('FIRMS_MAP_KEY', '');
    expect((await run()).status).toBe(503);
    expect(runs).toEqual([{ feed: 'FIRMS', ok: false, seen: 0, added: 0, error: 'FIRMS_MAP_KEY is not configured' }]);
  });

  it('a failed write is a failed run', async () => {
    answers.VIIRS_NOAA21_NRT = { status: 200, body: csv(IN_PLATEAU) };
    upsertError = { message: 'relation "fire_detections" does not exist' };
    const res = await run();
    expect(res.status).toBe(500);
    expect(runs[0]).toMatchObject({ ok: false, added: 0 });
  });

  it('never stores or returns the key, even when an error quotes the URL', async () => {
    answers.VIIRS_NOAA20_NRT = new Error(`fetch failed for https://firms.modaps.eosdis.nasa.gov/api/area/csv/${KEY}/VIIRS_NOAA20_NRT`);
    const res = await run();
    const body = JSON.stringify(await res.json());
    expect(body).not.toContain(KEY);
    expect(JSON.stringify(runs)).not.toContain(KEY);
    expect(JSON.stringify(runs)).toContain('[MAP_KEY]');
  });
});
