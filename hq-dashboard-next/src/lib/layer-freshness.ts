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

export type Layer = LiveLayer | DerivedLayer | StaticLayer;

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
    case 'static':
      return layer.failed
        ? { state: 'DOWN', text: `did not load · ${layer.source}` }
        : { state: 'STATIC', text: layer.source };
  }
}
