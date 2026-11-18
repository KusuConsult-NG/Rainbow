// How well an incident is corroborated. The point of the score is that a
// person is counted once however many times they press, that a decoy burst of
// keypad reports cannot raise it, and that one real person is never hidden.
import { describe, expect, it } from 'vitest';

import type { Alert } from '@/app/dashboard/types';
import { clusterAlerts } from './alert-display';
import { channelOf, corroborate, corroborationLine, sourceOf, withCorroboration } from './corroboration';

let n = 0;
const r = (over: Partial<Alert> = {}): Alert =>
  ({
    id: `a${++n}`,
    type: 'Community attack - Armed Invasion',
    status: 'PENDING',
    severity: 'CRITICAL',
    geo_lga: 'RIYOM',
    geo_ward: 'RIYOM',
    geo_pu: 'PU-01',
    created_at: '2026-11-18T22:00:00Z',
    reported_by: 'user-1',
    ...over,
  }) as Alert;

const ussd = (msisdn: string, confirmed = false, over: Partial<Alert> = {}) =>
  r({
    arrived_via: 'USSD',
    reporter_msisdn: msisdn,
    reported_by: undefined,
    ussd_confirmed_at: confirmed ? '2026-11-18T22:05:00Z' : null,
    ...over,
  });

describe('channelOf', () => {
  it('names every channel a report can arrive over', () => {
    expect(channelOf(r())).toBe('APP');
    expect(channelOf(r({ description: 'Guardian: distress phrase heard (abduction)' }))).toBe('GUARDIAN');
    expect(channelOf(r({ arrived_via: 'SMS' }))).toBe('SMS');
    expect(channelOf(r({ arrived_via: 'mesh' }))).toBe('MESH');
    expect(channelOf(ussd('08031234567'))).toBe('USSD');
  });
});

describe('sourceOf', () => {
  it('is the account for app reports and the number for keypad ones', () => {
    expect(sourceOf(r({ reported_by: 'u9' }))).toBe('user:u9');
    // +234 and a leading 0 are the same number.
    expect(sourceOf(ussd('+2348031234567'))).toBe(sourceOf(ussd('08031234567')));
  });

  it('treats a report with no reporter as its own source', () => {
    const a = r({ reported_by: undefined });
    expect(sourceOf(a)).toBe(`report:${a.id}`);
  });
});

describe('corroborate', () => {
  it('one person pressing ten times is one source', () => {
    const c = corroborate(Array.from({ length: 10 }, () => r({ reported_by: 'same' })));
    expect(c.level).toBe('UNCONFIRMED');
    expect(c.sources).toBe(1);
    expect(c.reports).toBe(10);
  });

  it('two people corroborate', () => {
    const c = corroborate([r({ reported_by: 'p1' }), r({ reported_by: 'p2' })]);
    expect(c.level).toBe('CORROBORATED');
    expect(c.sources).toBe(2);
    expect(c.channels).toEqual(['APP']);
  });

  it('three people on one channel are corroborated, not strong', () => {
    const c = corroborate(['p1', 'p2', 'p3'].map((p) => r({ reported_by: p })));
    expect(c.level).toBe('CORROBORATED');
  });

  it('three people over two channels are strong', () => {
    const c = corroborate([
      r({ reported_by: 'p1' }),
      r({ reported_by: 'p2', description: 'Guardian: secret phrase heard' }),
      ussd('08031234567', true),
    ]);
    expect(c.level).toBe('STRONG');
    expect(c.sources).toBe(3);
    expect(c.channels).toEqual(['APP', 'GUARDIAN', 'USSD']);
  });

  it('a burst of unconfirmed keypad reports is shown but raises nothing', () => {
    const c = corroborate([
      r({ reported_by: 'p1' }),
      ussd('08030000001'),
      ussd('08030000002'),
      ussd('08030000003'),
    ]);
    expect(c.level).toBe('UNCONFIRMED');
    expect(c.sources).toBe(1);
    expect(c.unconfirmedSources).toBe(3);
  });

  it('a keypad report counts once an officer confirms it', () => {
    const c = corroborate([r({ reported_by: 'p1' }), ussd('08030000001', true)]);
    expect(c.level).toBe('CORROBORATED');
    expect(c.unconfirmedSources).toBe(0);
  });

  it('a number already counted adds nothing through its unconfirmed reports', () => {
    const c = corroborate([ussd('08030000001', true), ussd('08030000001', false)]);
    expect(c.sources).toBe(1);
    expect(c.unconfirmedSources).toBe(0);
  });

  it('a single real person is UNCONFIRMED, never nothing', () => {
    const c = corroborate([r()]);
    expect(c.level).toBe('UNCONFIRMED');
    expect(c.sources).toBe(1);
  });
});

describe('corroborationLine', () => {
  it('says sources, channels, unconfirmed keypad and raw reports', () => {
    const line = corroborationLine(
      corroborate([
        r({ reported_by: 'p1' }),
        r({ reported_by: 'p1' }),
        r({ reported_by: 'p2', arrived_via: 'SMS' }),
        ussd('08030000009'),
      ]),
    );
    expect(line).toBe('2 independent sources · 2 channels (APP, SMS) · +1 unconfirmed keypad · 4 reports');
  });

  it('reads naturally for one source', () => {
    expect(corroborationLine(corroborate([r()]))).toBe('1 independent source · 1 channel (APP)');
  });
});

describe('withCorroboration', () => {
  it('scores each clustered card from the reports folded into it', () => {
    const raw = [r({ reported_by: 'p1' }), r({ reported_by: 'p2' }), r({ reported_by: 'p2' })];
    const cards = withCorroboration(clusterAlerts(raw, true), raw);
    expect(cards).toHaveLength(1);
    expect(cards[0].corroboration?.sources).toBe(2);
    expect(cards[0].corroboration?.reports).toBe(3);
  });

  it('scores every card when clustering is off, each on its own report', () => {
    const raw = [r({ reported_by: 'p1' }), r({ reported_by: 'p2' })];
    const cards = withCorroboration(clusterAlerts(raw, false), raw);
    expect(cards.map((c) => c.corroboration?.sources)).toEqual([1, 1]);
  });
});
