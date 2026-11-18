// Every layer says how current it is. The case that matters: a feed that died
// must never read as live, however calm the map looks.
import { describe, expect, it } from 'vitest';

import { ago, freshness, type LiveLayer } from './layer-freshness';

const NOW = Date.parse('2026-11-18T22:00:00Z');
const incidents = (over: Partial<LiveLayer> = {}): LiveLayer => ({
  kind: 'live',
  name: 'Incidents',
  connection: 'LIVE',
  syncedAt: NOW - 5 * 60_000,
  ...over,
});

describe('freshness of a live layer', () => {
  it('is LIVE while the channel is connected, however old the last change', () => {
    expect(freshness(incidents(), NOW)).toEqual({ state: 'LIVE', text: 'live · last read 5 min ago' });
  });

  it('is DOWN when the channel drops, and says how old the picture is', () => {
    expect(freshness(incidents({ connection: 'DOWN' }), NOW)).toEqual({
      state: 'DOWN',
      text: 'live link lost · showing data from 5 min ago',
    });
  });

  it('is DOWN when the read failed, even with the channel up', () => {
    expect(freshness(incidents({ error: 'permission denied' }), NOW).state).toBe('DOWN');
  });

  it('says when nothing has loaded at all', () => {
    expect(freshness(incidents({ connection: 'DOWN', syncedAt: null }), NOW).text).toBe(
      'live link lost · nothing loaded',
    );
  });

  it('is CONNECTING until the first read, not LIVE', () => {
    expect(freshness(incidents({ connection: 'LIVE', syncedAt: null }), NOW).state).toBe('CONNECTING');
    expect(freshness(incidents({ connection: 'CONNECTING' }), NOW).state).toBe('CONNECTING');
  });
});

describe('a derived layer', () => {
  it('inherits the state of the layer it is computed from', () => {
    const f = freshness({ kind: 'derived', name: 'Ward grid', from: incidents({ connection: 'DOWN' }) }, NOW);
    expect(f.state).toBe('DOWN');
    expect(f.text).toBe('from incidents · live link lost · showing data from 5 min ago');
  });
});

describe('a static layer', () => {
  it('says its source instead of an age', () => {
    expect(freshness({ kind: 'static', name: 'LGA boundaries', source: 'geoBoundaries (CC BY 4.0)' }, NOW)).toEqual({
      state: 'STATIC',
      text: 'geoBoundaries (CC BY 4.0)',
    });
  });

  it('is DOWN, not a quiet source line, when it did not load', () => {
    expect(
      freshness({ kind: 'static', name: 'LGA boundaries', source: 'geoBoundaries (CC BY 4.0)', failed: true }, NOW),
    ).toEqual({ state: 'DOWN', text: 'did not load · geoBoundaries (CC BY 4.0)' });
  });
});

describe('ago', () => {
  it('reads like a person would say it', () => {
    expect(ago(3_000)).toBe('just now');
    expect(ago(40_000)).toBe('40 s ago');
    expect(ago(12 * 60_000)).toBe('12 min ago');
    expect(ago(3 * 3_600_000)).toBe('3 h ago');
    expect(ago(-5_000)).toBe('just now');
  });
});
