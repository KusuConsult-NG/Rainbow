// What HQ sees, and what it does not.
//
// `clusterAlerts` and `filterAlerts` were extracted verbatim from
// dashboard/page.tsx, where they had no coverage. They decide which incidents
// reach an operator's screen, so a mistake here does not look like a bug — it
// looks like a quiet night.
import { describe, expect, it } from 'vitest';

import type { Alert } from '@/app/dashboard/types';
import { CLUSTER_WINDOW_MS, NO_FILTERS, clusterAlerts, filterAlerts } from './alert-display';

const a = (over: Partial<Alert> & { id: string }): Alert =>
  ({
    type: 'FIRE',
    status: 'PENDING',
    severity: 'MEDIUM',
    geo_lga: 'JOS NORTH',
    geo_ward: 'NARAGUTA',
    geo_pu: 'PU-01',
    created_at: '2026-09-01T10:00:00Z',
    ...over,
  }) as Alert;

const witnesses = (alert: Alert) =>
  (alert as unknown as { witness_count: number }).witness_count;

describe('clusterAlerts', () => {
  it('passes everything through untouched when clustering is off', () => {
    const rows = [a({ id: '1' }), a({ id: '2' })];
    expect(clusterAlerts(rows, false)).toBe(rows);
  });

  it('folds duplicate reports of the same event into one card', () => {
    const out = clusterAlerts(
      [a({ id: '1' }), a({ id: '2' }), a({ id: '3' })],
      true,
    );

    expect(out).toHaveLength(1);
    expect(witnesses(out[0])).toBe(3);
  });

  it('keeps incidents apart when any of type, LGA, ward or PU differs', () => {
    const out = clusterAlerts(
      [
        a({ id: '1' }),
        a({ id: '2', type: 'MEDICAL' }),
        a({ id: '3', geo_lga: 'JOS SOUTH' }),
        a({ id: '4', geo_ward: 'VOM' }),
        a({ id: '5', geo_pu: 'PU-02' }),
      ],
      true,
    );

    expect(out).toHaveLength(5);
  });

  it('never merges resolved alerts, even identical ones', () => {
    const out = clusterAlerts(
      [
        a({ id: '1', status: 'RESOLVED' }),
        a({ id: '2', status: 'RESOLVED' }),
      ],
      true,
    );

    expect(out).toHaveLength(2);
    expect(out.map(x => x.id).sort()).toEqual(['1', '2']);
  });

  // Severity must travel upward through a merge. If a DURESS report is folded
  // into a routine one and the card stays routine, the most urgent thing on
  // the board is displayed as the least.
  it('promotes the surviving card to DURESS when any member is DURESS', () => {
    const out = clusterAlerts(
      [a({ id: '1', status: 'PENDING' }), a({ id: '2', status: 'DURESS' })],
      true,
    );

    expect(out).toHaveLength(1);
    expect(out[0].status).toBe('DURESS');
    expect(out[0].priority).toBe('CRITICAL');
  });

  it('promotes to CRITICAL priority when any member is CRITICAL', () => {
    const out = clusterAlerts(
      [a({ id: '1' }), a({ id: '2', priority: 'CRITICAL' })],
      true,
    );

    expect(out[0].priority).toBe('CRITICAL');
  });

  it('does not mutate the alerts it was given', () => {
    const first = a({ id: '1', status: 'PENDING' });
    clusterAlerts([first, a({ id: '2', status: 'DURESS' })], true);

    expect(first.status).toBe('PENDING');
    expect(witnesses(first)).toBeUndefined();
  });

  it('carries every member id, so acting on the card can act on all of them', () => {
    const out = clusterAlerts([a({ id: '1' }), a({ id: '2' }), a({ id: '3' })], true);

    expect(out[0].member_ids).toEqual(['1', '2', '3']);
    expect(out[0].witness_count).toBe(3);
  });

  it('gives a lone alert a one-element member list too', () => {
    const out = clusterAlerts([a({ id: 'solo' })], true);
    expect(out[0].member_ids).toEqual(['solo']);
    expect(out[0].witness_count).toBe(1);
  });

  // The "temporal" half of "spatial-temporal" clustering. Reports of one event
  // arrive minutes apart; the same place and type on different days is a
  // different event, and merging them hid one.
  it('does not merge reports filed further apart than the window', () => {
    const t0 = Date.parse('2026-09-01T10:00:00Z');
    const later = new Date(t0 + CLUSTER_WINDOW_MS + 60_000).toISOString();
    const out = clusterAlerts(
      [a({ id: 'morning', created_at: new Date(t0).toISOString() }), a({ id: 'afternoon', created_at: later })],
      true,
    );

    expect(out).toHaveLength(2);
    expect(out.map(x => x.id).sort()).toEqual(['afternoon', 'morning']);
  });

  it('merges reports filed inside the window', () => {
    const t0 = Date.parse('2026-09-01T10:00:00Z');
    const soon = new Date(t0 + 10 * 60_000).toISOString();
    const out = clusterAlerts(
      [a({ id: '1', created_at: new Date(t0).toISOString() }), a({ id: '2', created_at: soon })],
      true,
    );

    expect(out).toHaveLength(1);
    expect(out[0].member_ids).toEqual(['1', '2']);
  });

  it('still merges a report with no usable timestamp rather than hide it', () => {
    const out = clusterAlerts(
      [a({ id: '1' }), a({ id: 'undated', created_at: undefined as unknown as string })],
      true,
    );
    expect(out).toHaveLength(1);
    expect(out[0].member_ids).toEqual(['1', 'undated']);
  });

  // The surviving card carries the FIRST report's id for display, but every
  // member id travels with it. The write paths act on `member_ids`, so nothing
  // is closed while its siblings stay open and invisible.
  it('displays as the first report but stands for all of them', () => {
    const out = clusterAlerts(
      [a({ id: 'first' }), a({ id: 'second', status: 'DURESS' })],
      true,
    );

    expect(out[0].id).toBe('first');
    expect(out[0].status).toBe('DURESS');
    expect(out[0].member_ids).toEqual(['first', 'second']);
  });
});

describe('filterAlerts', () => {
  const rows = [
    a({ id: 'pending' }),
    a({ id: 'duress', status: 'DURESS' }),
    a({ id: 'critical', priority: 'CRITICAL' }),
    a({ id: 'resolved', status: 'RESOLVED' }),
    a({ id: 'sms', description: 'Fire at market [OFFLINE_SMS]' }),
    a({ id: 'south', geo_lga: 'JOS SOUTH', geo_ward: 'VOM', geo_pu: 'PU-09' }),
  ];

  const ids = (out: Alert[]) => out.map(x => x.id).sort();

  it('returns everything with no filters applied', () => {
    expect(filterAlerts(rows, NO_FILTERS)).toHaveLength(rows.length);
  });

  it('CRITICAL means DURESS status OR CRITICAL priority', () => {
    expect(ids(filterAlerts(rows, { ...NO_FILTERS, status: 'CRITICAL' })))
      .toEqual(['critical', 'duress']);
  });

  it('an exact status filter matches only that status', () => {
    expect(ids(filterAlerts(rows, { ...NO_FILTERS, status: 'RESOLVED' })))
      .toEqual(['resolved']);
  });

  it('SMS_FALLBACK finds alerts that arrived over the SMS path', () => {
    expect(ids(filterAlerts(rows, { ...NO_FILTERS, status: 'SMS_FALLBACK' })))
      .toEqual(['sms']);
  });

  it.each([
    ['via', { via: 'SMS_GATEWAY' }],
    ['source', { source: 'SMS' }],
    ['channel', { channel: 'SMS' }],
    ['[SMS] in the description', { description: 'Reported [SMS]' }],
  ])('SMS_FALLBACK also matches on %s', (_label, extra) => {
    const out = filterAlerts(
      [a({ id: 'x', ...(extra as Partial<Alert>) })],
      { ...NO_FILTERS, status: 'SMS_FALLBACK' },
    );
    expect(out).toHaveLength(1);
  });

  it('filters by assignment tier', () => {
    const out = filterAlerts(
      [a({ id: 'mine', assigned_to: 'LGA' }), a({ id: 'theirs', assigned_to: 'HQ' })],
      { ...NO_FILTERS, tier: 'LGA' },
    );
    expect(ids(out)).toEqual(['mine']);
  });

  it('filters by LGA, ward and PU together', () => {
    const out = filterAlerts(rows, {
      ...NO_FILTERS,
      lga: 'JOS SOUTH',
      ward: 'VOM',
      pu: 'PU-09',
    });
    expect(ids(out)).toEqual(['south']);
  });

  // Field-entered place names are inconsistent, and under-matching hides live
  // incidents from the officer responsible for them.
  it.each([
    ['case differences', 'jos north'],
    ['surrounding whitespace', '  JOS NORTH  '],
    ['a longer official name', 'JOS NORTH LGA'],
  ])('matches an LGA despite %s', (_label, filterValue) => {
    const out = filterAlerts([a({ id: 'x' })], { ...NO_FILTERS, lga: filterValue });
    expect(out).toHaveLength(1);
  });

  // The flip side of loose matching, asserted so the trade-off is visible
  // rather than discovered: substring matching pulls in neighbours whose names
  // are contained in one another.
  it('loose matching also admits a different LGA whose name is a substring', () => {
    const out = filterAlerts(
      [a({ id: 'north', geo_lga: 'JOS NORTH' }), a({ id: 'jos', geo_lga: 'JOS' })],
      { ...NO_FILTERS, lga: 'JOS NORTH' },
    );
    expect(ids(out)).toEqual(['jos', 'north']);
  });

  it('an alert with no geography survives a geographic filter', () => {
    // '' contains everything and everything contains '', so a blank LGA never
    // filters out. That is deliberate fail-open: an unlocated emergency must
    // not vanish because the operator narrowed the view.
    const out = filterAlerts([a({ id: 'nowhere', geo_lga: undefined })], {
      ...NO_FILTERS,
      lga: 'JOS NORTH',
    });
    expect(out).toHaveLength(1);
  });

  it('combines a status filter with a geographic one', () => {
    const out = filterAlerts(
      [
        a({ id: 'a', status: 'DURESS', geo_lga: 'JOS SOUTH' }),
        a({ id: 'b', status: 'DURESS', geo_lga: 'BARKIN LADI' }),
        a({ id: 'c', status: 'PENDING', geo_lga: 'JOS SOUTH' }),
      ],
      { ...NO_FILTERS, status: 'CRITICAL', lga: 'JOS SOUTH' },
    );
    expect(ids(out)).toEqual(['a']);
  });
});
