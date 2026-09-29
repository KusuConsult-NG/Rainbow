import { describe, expect, it } from 'vitest';

import {
  describeTrack,
  metresBetween,
  orderTrack,
  summariseTrack,
  thinTrack,
  type TrackPoint,
} from './incident-track';

const at = (
  lat: number,
  lng: number,
  minute: number,
  extra: Partial<TrackPoint> = {},
): TrackPoint => ({
  latitude: lat,
  longitude: lng,
  recorded_at: new Date(Date.UTC(2026, 8, 28, 12, minute)).toISOString(),
  ...extra,
});

describe('distance', () => {
  it('measures a known span on the ground', () => {
    // Jos: 9.8965,8.8583 to 9.8991,8.8620 is roughly 470m.
    const d = metresBetween(at(9.8965, 8.8583, 0), at(9.8991, 8.862, 1));
    expect(d).toBeGreaterThan(400);
    expect(d).toBeLessThan(550);
  });

  it('is zero between a point and itself', () => {
    expect(metresBetween(at(9.9, 8.9, 0), at(9.9, 8.9, 1))).toBe(0);
  });
});

describe('putting a route in order', () => {
  it('sorts by when the handset recorded, not when the row arrived', () => {
    // A point queued while offline is delivered later and must still sit in
    // the right place on the route.
    const ordered = orderTrack([at(9.9, 8.9, 5), at(9.9, 8.9, 1), at(9.9, 8.9, 3)]);
    expect(ordered.map((p) => p.recorded_at.slice(14, 16))).toEqual(['01', '03', '05']);
  });

  it('drops a row that cannot be drawn rather than drawing it wrong', () => {
    const ordered = orderTrack([
      at(9.9, 8.9, 1),
      { latitude: NaN, longitude: 8.9, recorded_at: at(9.9, 8.9, 2).recorded_at },
      { latitude: 9.9, longitude: 8.9, recorded_at: 'not a time' },
    ]);
    expect(ordered).toHaveLength(1);
  });
});

describe('what the route adds up to', () => {
  it('measures a walk', () => {
    const summary = summariseTrack([
      at(9.8965, 8.8583, 0),
      at(9.8991, 8.862, 5),
      at(9.9025, 8.8665, 10),
    ]);
    expect(summary.points).toBe(3);
    expect(summary.distanceMetres).toBeGreaterThan(800);
    expect(summary.durationMs).toBe(10 * 60 * 1000);
    expect(summary.stationary).toBe(false);
  });

  it('does not turn GPS jitter into a two-kilometre journey', () => {
    // A handset on a table reports a few metres of drift every few seconds.
    // Summing those steps tells an operator the person walked across town —
    // worse than saying nothing, because it is specific and wrong.
    const jitter: TrackPoint[] = [];
    for (let i = 0; i < 120; i += 1) {
      jitter.push(
        at(
          9.9 + (i % 2 === 0 ? 0.00002 : -0.00002),
          8.9 + (i % 3 === 0 ? 0.00002 : -0.00002),
          i,
          { accuracy: 12 },
        ),
      );
    }
    const summary = summariseTrack(jitter);
    expect(summary.distanceMetres).toBe(0);
    expect(summary.stationary).toBe(true);
    expect(describeTrack(summary)).toContain('Stayed in one place');
  });

  it('counts a step that clears the accuracy of the fixes that made it', () => {
    const summary = summariseTrack([
      at(9.9, 8.9, 0, { accuracy: 5 }),
      at(9.905, 8.9, 1, { accuracy: 5 }),
    ]);
    expect(summary.distanceMetres).toBeGreaterThan(400);
  });

  it('reports the fastest fix, and ignores a nonsense one', () => {
    const summary = summariseTrack([
      at(9.9, 8.9, 0, { speed: 1.2 }),
      at(9.91, 8.9, 1, { speed: -1 }),
      at(9.92, 8.9, 2, { speed: 14.7 }),
    ]);
    expect(summary.maxSpeed).toBeCloseTo(14.7);
  });

  it('says nothing about an empty track rather than zero-everything', () => {
    const summary = summariseTrack([]);
    expect(summary.points).toBe(0);
    expect(summary.from).toBeNull();
    expect(describeTrack(summary)).toBe('No movement recorded for this incident.');
  });

  it('distinguishes "did not report" from "did not move"', () => {
    // A dispatcher deciding whether somebody is still where they said they
    // were needs these to read differently.
    const none = describeTrack(summariseTrack([]));
    const still = describeTrack(
      summariseTrack([at(9.9, 8.9, 0, { accuracy: 8 }), at(9.9, 8.9, 9, { accuracy: 8 })]),
    );
    expect(none).not.toEqual(still);
    expect(none.toLowerCase()).toContain('no movement recorded');
    expect(still.toLowerCase()).toContain('stayed in one place');
  });

  it('says when there is only one fix', () => {
    expect(describeTrack(summariseTrack([at(9.9, 8.9, 0)])))
      .toContain('not enough for a route');
  });
});

describe('thinning a long route for drawing', () => {
  it('keeps short routes whole', () => {
    const points = [at(9.9, 8.9, 0), at(9.91, 8.9, 1)];
    expect(thinTrack(points, 300)).toHaveLength(2);
  });

  it('keeps the first and last fix', () => {
    // Losing either moves where the route starts or ends, which is the part an
    // operator reads first.
    const points = Array.from({ length: 1000 }, (_, i) => at(9.9 + i * 0.0001, 8.9, i));
    const thinned = thinTrack(points, 100);
    expect(thinned).toHaveLength(100);
    expect(thinned[0].recorded_at).toBe(points[0].recorded_at);
    expect(thinned[thinned.length - 1].recorded_at).toBe(points[999].recorded_at);
  });

  it('keeps the route in order', () => {
    const points = Array.from({ length: 700 }, (_, i) => at(9.9 + i * 0.0001, 8.9, i));
    const thinned = thinTrack(points, 50);
    const times = thinned.map((p) => Date.parse(p.recorded_at));
    expect(times).toEqual([...times].sort((a, b) => a - b));
  });

  it('does not lose the shape of the journey', () => {
    const points = Array.from({ length: 1000 }, (_, i) => at(9.9 + i * 0.0001, 8.9, i));
    const whole = summariseTrack(points).distanceMetres;
    const thinned = summariseTrack(thinTrack(points, 100)).distanceMetres;
    expect(thinned).toBeGreaterThan(whole * 0.9);
  });
});
