/**
 * How current each layer on the HQ map is, said on the map.
 *
 * Phase 1 of the intelligence layer, after God's Eye View's rule that every
 * layer says when its feed is stale or on a fallback. A map that looks the
 * same whether its feed is live or died an hour ago invites a commander to
 * trust a picture nobody is updating.
 *
 * Three kinds of layer:
 *  - LIVE layers come from a realtime channel (incidents, field units). While
 *    the channel is connected the picture is current however long ago the last
 *    change was, because a change would have arrived. When it is not, the
 *    picture is only as new as the last successful read, and says so.
 *  - DERIVED layers (the ward grid) are computed from a live one and inherit
 *    its state.
 *  - STATIC layers (boundaries, ward centroids) are datasets with a source and
 *    a licence, said instead of an age.
 */

export type Connection = 'CONNECTING' | 'LIVE' | 'DOWN';
export type FreshnessState = 'LIVE' | 'CONNECTING' | 'DOWN' | 'STATIC';

export interface LiveLayer {
  kind: 'live';
  name: string;
  connection: Connection;
  /** When the last successful read finished (ms since epoch), or null. */
  syncedAt: number | null;
  /** The last read's error, if it failed. */
  error?: string | null;
}

export interface DerivedLayer {
  kind: 'derived';
  name: string;
  /** The live layer it is computed from. */
  from: LiveLayer;
}

export interface StaticLayer {
  kind: 'static';
  name: string;
  /** Where the data comes from, with its licence. */
  source: string;
  /** A dataset fetched at load time that did not arrive. */
  failed?: boolean;
}

/**
 * A layer fetched on a schedule from outside (NASA FIRMS), from the runs the
 * fetcher records in `intel_ingest_runs`.
 */
export interface PolledLayer {
  kind: 'polled';
  name: string;
  /** The newest run, good or bad, or null if none was ever recorded. */
  lastRunAt: number | null;
  /** The newest SUCCESSFUL run. */
  lastOkAt: number | null;
  /** Why the newest run failed, if it did. */
  lastError?: string | null;
  /** How often the fetch is scheduled to run. */
  everyMs: number;
  /** A note on how far behind the source itself runs, e.g. FIRMS' ~3 h. */
  lag?: string;
  /** Our own read of the table failed. */
  readError?: string | null;
}

export type Layer = LiveLayer | DerivedLayer | StaticLayer | PolledLayer;

/** A polled layer with no good run for this many schedules reads as DOWN. */
export const POLLED_MISSED_RUNS = 3;

function polled(l: PolledLayer, now: number): Freshness {
  const lag = l.lag ? ` · ${l.lag}` : '';
  if (l.readError) return { state: 'DOWN', text: 'could not be read' };
  if (l.lastRunAt === null) return { state: 'DOWN', text: 'no fetch recorded: is the scheduler set up?' };
  const good = l.lastOkAt === null ? null : ago(now - l.lastOkAt);
  if (l.lastError) {
    return {
      state: 'DOWN',
      text: `last fetch failed (${l.lastError.slice(0, 60)})${good ? ` · last good ${good}` : ''}`,
    };
  }
  if (l.lastOkAt === null || now - l.lastOkAt > POLLED_MISSED_RUNS * l.everyMs) {
    return { state: 'DOWN', text: good ? `no good fetch since ${good}` : 'no good fetch yet' };
  }
  return { state: 'LIVE', text: `fetched ${good}${lag}` };
}

export interface Freshness {
  state: FreshnessState;
  text: string;
}

/** "just now", "40 s ago", "12 min ago", "3 h ago". */
export function ago(ms: number): string {
  const s = Math.max(0, Math.round(ms / 1000));
  if (s < 10) return 'just now';
  if (s < 60) return `${s} s ago`;
  const m = Math.round(s / 60);
  if (m < 60) return `${m} min ago`;
  return `${Math.round(m / 60)} h ago`;
}

function live(l: LiveLayer, now: number): Freshness {
  const read = l.syncedAt === null ? null : ago(now - l.syncedAt);
  if (l.error) {
    return {
      state: 'DOWN',
      text: read ? `read failed · showing data from ${read}` : 'read failed · nothing loaded',
    };
  }
  if (l.connection === 'DOWN') {
    return {
      state: 'DOWN',
      text: read ? `live link lost · showing data from ${read}` : 'live link lost · nothing loaded',
    };
  }
  if (l.connection === 'CONNECTING' || l.syncedAt === null) {
    return { state: 'CONNECTING', text: read ? `connecting · last read ${read}` : 'connecting' };
  }
  return { state: 'LIVE', text: `live · last read ${read}` };
}

export function freshness(layer: Layer, now: number): Freshness {
  switch (layer.kind) {
    case 'live':
      return live(layer, now);
    case 'derived': {
      const f = live(layer.from, now);
      return { state: f.state, text: `from ${layer.from.name.toLowerCase()} · ${f.text}` };
    }
    case 'polled':
      return polled(layer, now);
    case 'static':
      return layer.failed
        ? { state: 'DOWN', text: `did not load · ${layer.source}` }
        : { state: 'STATIC', text: layer.source };
  }
}
