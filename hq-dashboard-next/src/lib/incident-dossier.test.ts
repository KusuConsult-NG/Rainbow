import { describe, expect, it } from 'vitest';
import { BRAND } from './brand';

import type { Alert } from '@/app/dashboard/types';
import {
  arrivalLabel,
  canDispatch,
  canResolve,
  escapeHtml,
  formatAge,
  formatStamp,
  incidentDetailRows,
  incidentPopupHtml,
  incidentRef,
  isDiallable,
  isUnacknowledged,
  resolveAssignee,
  resolveReporterDetails,
  severityColour,
  statusColour,
  statusLabel,
} from './incident-dossier';

const NOW = new Date('2026-09-28T12:00:00.000Z');

const alert = (over: Partial<Alert> = {}): Alert =>
  ({
    id: '7f3c9a10-1111-2222-3333-444455556666',
    type: 'ARMED_ROBBERY',
    status: 'PENDING',
    severity: 'HIGH',
    created_at: '2026-09-28T11:45:00.000Z',
    ...over,
  }) as Alert;

const CITIZEN = {
  id: 'c1',
  full_name: 'Amina Dung',
  phone: '+2348030001111',
  role: 'CITIZEN',
  email: 'amina@example.test',
};

const OFFICER = {
  id: 'o1',
  full_name: 'Insp. Bature Musa',
  phone: '08099992222',
  role: 'RESPONDER',
  badge_number: 'OPSH-114',
  email: 'bature@operationrainbow.test',
};

describe('escapeHtml', () => {
  it('neutralises a script injected through a citizen description', () => {
    // The popup is an HTML string handed to Leaflet, and descriptions come from
    // whoever filed the report — including, since the SMS channel opened,
    // anyone holding a device key.
    const escaped = escapeHtml('<img src=x onerror="fetch(\'/api/admin\')">');
    expect(escaped).not.toContain('<img');
    expect(escaped).not.toContain('"');
    expect(escaped).toContain('&lt;img');
  });

  it('escapes ampersands before anything else, so no double-encoding', () => {
    expect(escapeHtml('Tudun Wada & Kabong')).toBe('Tudun Wada &amp; Kabong');
    expect(escapeHtml('<')).toBe('&lt;');
  });

  it('renders null and undefined as nothing, not as the word', () => {
    expect(escapeHtml(null)).toBe('');
    expect(escapeHtml(undefined)).toBe('');
  });
});

describe('the popup does not execute what a reporter writes', () => {
  it('keeps an injected tag out of the rendered HTML', () => {
    const hostile = alert({
      description: '<script>window._hqResolve = null</script>',
      type: '<svg onload=alert(1)>',
    });
    const html = incidentPopupHtml(hostile, {
      reporter: resolveReporterDetails(hostile, {}),
      now: NOW,
    });
    expect(html).not.toContain('<script');
    expect(html).not.toContain('<svg');
    expect(html).toContain('&lt;script&gt;');
  });

  it('escapes the id it puts inside an onclick attribute', () => {
    const html = incidentPopupHtml(alert({ id: "x');alert(1)//" }), {
      reporter: resolveReporterDetails(alert(), {}),
      now: NOW,
    });
    expect(html).not.toContain("');alert(1)");
    expect(html).toContain('&#39;');
  });
});

describe('resolveReporterDetails', () => {
  it('names the reporter and gives HQ the number to ring', () => {
    const r = resolveReporterDetails(alert({ reported_by: 'c1' }), { c1: CITIZEN });
    expect(r.name).toBe('Amina Dung');
    expect(r.contact).toBe('+2348030001111');
    expect(r.type).toBe('Citizen mobile app');
    expect(r.identified).toBe(true);
  });

  it('carries an officer’s badge and calls them a responder', () => {
    const r = resolveReporterDetails(alert({ reported_by: 'o1' }), { o1: OFFICER });
    expect(r.badge).toBe('OPSH-114');
    expect(r.type).toBe('Field tactical responder');
  });

  it('distinguishes an ANONYMOUS report from an unknown one', () => {
    // The offline ingest writes reported_by NULL when the reporter asked for
    // anonymity. Calling that "unidentified" would send an operator hunting for
    // a name the server deliberately never kept.
    const anon = resolveReporterDetails(alert({ reported_by: undefined, arrived_via: 'SMS' }), {});
    expect(anon.anonymous).toBe(true);
    expect(anon.name).toContain('ANONYMOUS');

    const blank = resolveReporterDetails(alert({ reported_by: undefined }), {});
    expect(blank.anonymous).toBe(false);
    expect(blank.name).toBe('NO REPORTER RECORDED');
  });

  it('says the profile was not loaded rather than inventing a citizen', () => {
    // This is the case that rendered as "Registered Citizen / No Phone
    // Registered" for two months while the profile query was broken. An
    // operator must be able to tell a citizen with no phone on file from a
    // lookup that failed.
    const r = resolveReporterDetails(alert({ reported_by: 'deadbeef-0000-0000-0000-000000000000' }), {});
    expect(r.identified).toBe(false);
    expect(r.name).toContain('UNIDENTIFIED');
    expect(r.name).toContain('deadbeef');
  });

  it('falls back to an email when there is no phone', () => {
    const r = resolveReporterDetails(alert({ reported_by: 'c1' }), {
      c1: { full_name: 'No Phone Person', email: 'np@example.test', role: 'CITIZEN' },
    });
    expect(r.contact).toBe('np@example.test');
  });

  it('uses a phone number carried on the alert itself', () => {
    // An SMS-borne report can name a handset with no profile at all.
    const r = resolveReporterDetails({ ...alert(), phone_number: '+2348121234567' } as Alert, {});
    expect(r.contact).toBe('+2348121234567');
  });
});

describe('isDiallable', () => {
  it('accepts Nigerian local and international forms', () => {
    expect(isDiallable('+2348030001111')).toBe(true);
    expect(isDiallable('08099992222')).toBe(true);
  });

  it('rejects emails and the honest placeholders', () => {
    expect(isDiallable('amina@example.test')).toBe(false);
    expect(isDiallable('No contact on file')).toBe(false);
    expect(isDiallable('Withheld at the reporter’s request')).toBe(false);
  });
});

describe('the actions offered on a marker', () => {
  it('offers DISPATCH on a newly reported incident', () => {
    // The regression this file exists for. The popup used to gate DISPATCH on
    // `status === 'OPEN' || status === 'ACTIVE'`; the column defaults to
    // 'PENDING' and nothing in this database has ever written either of those,
    // so every new report offered RESOLVE and no way to send anyone.
    expect(canDispatch('PENDING')).toBe(true);
    const html = incidentPopupHtml(alert({ status: 'PENDING' }), {
      reporter: resolveReporterDetails(alert(), {}),
      now: NOW,
    });
    expect(html).toContain('DISPATCH');
  });

  it('still offers DISPATCH on an incident already dispatched, for reassignment', () => {
    expect(canDispatch('DISPATCHED')).toBe(true);
    expect(canDispatch('ON_ROUTE')).toBe(true);
  });

  it('offers neither on a closed incident', () => {
    expect(canDispatch('RESOLVED')).toBe(false);
    expect(canResolve('RESOLVED')).toBe(false);
    expect(canDispatch('CANCELLED')).toBe(false);
    const html = incidentPopupHtml(alert({ status: 'RESOLVED' }), {
      reporter: resolveReporterDetails(alert(), {}),
      now: NOW,
    });
    expect(html).not.toContain('>RESOLVE<');
    expect(html).toContain('DOSSIER');
  });

  it('offers CALL only when there is a number to call', () => {
    const withPhone = incidentPopupHtml(alert({ reported_by: 'c1' }), {
      reporter: resolveReporterDetails(alert({ reported_by: 'c1' }), { c1: CITIZEN }),
      now: NOW,
    });
    expect(withPhone).toContain('tel:+2348030001111');

    const anonymous = alert({ arrived_via: 'MESH' });
    const withoutPhone = incidentPopupHtml(anonymous, {
      reporter: resolveReporterDetails(anonymous, {}),
      now: NOW,
    });
    expect(withoutPhone).not.toContain('tel:');
  });

  it('always offers the full dossier', () => {
    const html = incidentPopupHtml(alert(), { reporter: resolveReporterDetails(alert(), {}), now: NOW });
    expect(html).toContain('data-hq-action="dossier"');
  });

  it('carries no inline event handler, which the CSP refuses to run', () => {
    // This test asserted `window._hqDossier` — the presence of an
    // `onclick="…"` attribute. The console's CSP is `script-src 'self'
    // 'nonce-…' 'strict-dynamic'` with no `'unsafe-inline'`, and a nonce
    // cannot apply to an event handler ATTRIBUTE, so the browser refused
    // every one of them: DOSSIER, DISPATCH and RESOLVE were dead in every map
    // popup on the console's landing screen. The suite was defending the
    // defect.
    const html = incidentPopupHtml(
      alert({ status: 'PENDING' }),
      { reporter: resolveReporterDetails(alert(), { 'user-1': CITIZEN }), now: NOW },
    );

    expect(html).not.toMatch(/\son[a-z]+\s*=/);
    expect(html).toContain('data-hq-action="dossier"');
    expect(html).toContain('data-hq-action="dispatch"');
    expect(html).toContain('data-hq-id=');
  });
});

describe('status and severity colours', () => {
  it('has a colour for PENDING, the status every report arrives with', () => {
    expect(statusColour('PENDING')).toBe(statusColour('OPEN'));
    expect(statusColour('CANCELLED')).not.toBe(statusColour('RESOLVED'));
  });

  it('does not give an ungraded report the colour of a graded one', () => {
    // `priority: d.severity || 'UNKNOWN'` deliberately surfaces the absence.
    // Painting UNKNOWN in HIGH's orange would put it straight back.
    const ungraded = severityColour('UNKNOWN');
    expect(ungraded).not.toBe(severityColour('HIGH'));
    expect(ungraded).not.toBe(severityColour('CRITICAL'));
    expect(severityColour(undefined)).toBe(ungraded);
  });

  it('spells out the status for people who do not read enums', () => {
    expect(statusLabel('PENDING')).toBe('AWAITING DISPATCH');
    expect(statusLabel('ON_ROUTE')).toBe('UNIT EN ROUTE');
    expect(statusLabel(undefined)).toBe('STATUS NOT RECORDED');
  });
});

describe('time', () => {
  it('reports an age in the units a dispatcher thinks in', () => {
    expect(formatAge('2026-09-28T11:59:40.000Z', NOW)).toBe('just now');
    expect(formatAge('2026-09-28T11:45:00.000Z', NOW)).toBe('15m ago');
    expect(formatAge('2026-09-28T09:30:00.000Z', NOW)).toBe('2h 30m ago');
    expect(formatAge('2026-09-26T09:00:00.000Z', NOW)).toBe('2d 3h ago');
  });

  it('says a timestamp is missing instead of saying "just now"', () => {
    // The dossier rendered a row with no created_at as 'JUST NOW', which is an
    // assertion about a brand-new emergency made from an empty column.
    expect(formatAge(undefined, NOW)).toBe('time not recorded');
    expect(formatStamp(undefined)).toBe('—');
  });

  it('names clock skew rather than showing a negative age', () => {
    // The offline channels set created_at from the PHONE's clock.
    const ahead = formatAge('2026-09-28T12:20:00.000Z', NOW);
    expect(ahead).toContain('FUTURE');
    expect(ahead).not.toContain('-');
  });
});

describe('arrivalLabel', () => {
  it('flags SMS and mesh as a reporter with no data connection', () => {
    expect(arrivalLabel(alert({ arrived_via: 'SMS' })).warn).toBe(true);
    expect(arrivalLabel(alert({ arrived_via: 'SMS' })).value).toContain('no data connection');
    expect(arrivalLabel(alert({ arrived_via: 'MESH' })).value).toContain('MESH');
    expect(arrivalLabel(alert({ arrived_via: 'MESH' })).warn).toBe(true);
  });

  it('does not claim a data connection it cannot know about', () => {
    const r = arrivalLabel(alert({ arrived_via: null }));
    expect(r.warn).toBe(false);
    expect(r.value).toContain('no fallback recorded');
  });
});

describe('isUnacknowledged', () => {
  it('is true for an open incident nobody has taken', () => {
    expect(isUnacknowledged(alert({ acknowledged_at: null }))).toBe(true);
  });

  it('is false once somebody acknowledges it', () => {
    expect(isUnacknowledged(alert({ acknowledged_at: '2026-09-28T11:50:00.000Z' }))).toBe(false);
  });

  it('is false for a closed incident, whatever its acknowledgement', () => {
    expect(isUnacknowledged(alert({ status: 'RESOLVED', acknowledged_at: null }))).toBe(false);
  });
});

describe('incidentDetailRows', () => {
  const rowsFor = (over: Partial<Alert>, users: Record<string, any> = {}) => {
    const a = alert(over);
    return incidentDetailRows(a, resolveReporterDetails(a, users), users, NOW);
  };

  const valueOf = (rows: ReturnType<typeof rowsFor>, label: string) =>
    rows.find((r) => r.label === label)?.value;

  it('leads with how long the incident has been waiting, unclaimed', () => {
    const rows = rowsFor({ acknowledged_at: null });
    expect(rows[0].label).toBe('RAISED');
    const ack = rows.find((r) => r.label === 'ACKNOWLEDGED');
    expect(ack?.value).toContain('NO');
    expect(ack?.value).toContain('15m');
    expect(ack?.tone).toBe('warn');
  });

  it('shows every field an operator needs to act', () => {
    const rows = rowsFor(
      {
        reported_by: 'c1',
        assigned_to: 'o1',
        assigned_tier: 'WARD',
        tier_assigned_at: '2026-09-28T11:50:00.000Z',
        arrived_via: 'SMS',
        geo_lga: 'Jos North',
        geo_ward: 'Naraguta A',
        geo_pu: 'PU 012',
        latitude: 9.9285,
        longitude: 8.8921,
        local_id: 'OFFLINE_1759000000000_a1b2c3d4e5f6',
        media_urls: ['https://media.test/1.jpg'],
      },
      { c1: CITIZEN, o1: OFFICER },
    );
    const labels = rows.map((r) => r.label);
    for (const expected of [
      'RAISED',
      'SEVERITY',
      'COMMAND TIER',
      'ASSIGNED TO',
      'CHANNEL',
      'REPORTER',
      'CONTACT',
      'REPORTER TYPE',
      'LOCATION',
      'COORDINATES',
      'MEDIA',
      'DEVICE REF',
      'INCIDENT',
    ]) {
      expect(labels).toContain(expected);
    }
    expect(valueOf(rows, 'REPORTER')).toBe('Amina Dung');
    expect(valueOf(rows, 'CONTACT')).toBe('+2348030001111');
    expect(valueOf(rows, 'ASSIGNED TO')).toContain('OPSH-114');
    expect(valueOf(rows, 'LOCATION')).toBe('Jos North › Naraguta A › PU 012');
    expect(valueOf(rows, 'COORDINATES')).toBe('9.92850, 8.89210');
    expect(valueOf(rows, 'COMMAND TIER')).toContain('WARD');
  });

  it('says an unassigned incident is nobody’s, and flags it', () => {
    const rows = rowsFor({ assigned_to: undefined });
    const assigned = rows.find((r) => r.label === 'ASSIGNED TO');
    expect(assigned?.value).toContain('unassigned');
    expect(assigned?.tone).toBe('warn');
  });

  it('reports a missing GPS fix as missing, not as a coordinate', () => {
    // C-5 again, one surface over: an alert with no fix used to be drawn at the
    // centre of Jos. It is now absent from the map entirely, and where it does
    // appear the popup must not imply a position.
    const rows = rowsFor({ latitude: undefined, longitude: undefined });
    const coords = rows.find((r) => r.label === 'COORDINATES');
    expect(coords?.value).toContain('NO GPS FIX');
    expect(coords?.tone).toBe('warn');
    expect(coords?.value).not.toContain('9.9');
  });

  it('says a severity is missing rather than implying one', () => {
    const rows = rowsFor({ severity: undefined, priority: undefined });
    expect(valueOf(rows, 'SEVERITY')).toBe('NOT GRADED');
  });

  it('declares how many reports a clustered marker stands for', () => {
    const rows = rowsFor({ witness_count: 4 });
    expect(valueOf(rows, 'WITNESS REPORTS')).toContain('4 reports');
  });

  it('omits the witness row for a single report', () => {
    const rows = rowsFor({ witness_count: 1 });
    expect(rows.map((r) => r.label)).not.toContain('WITNESS REPORTS');
  });

  it('names the agency an incident was escalated to', () => {
    const rows = rowsFor({ escalated_to_agency: 'OPSH' });
    expect(valueOf(rows, 'ESCALATED TO')).toBe('OPSH');
  });
});

describe('resolveAssignee', () => {
  it('gives the officer’s name and badge', () => {
    expect(resolveAssignee(alert({ assigned_to: 'o1' }), { o1: OFFICER })).toBe(
      'Insp. Bature Musa (OPSH-114)',
    );
  });

  it('says nobody when nobody is assigned', () => {
    expect(resolveAssignee(alert({ assigned_to: undefined }), {})).toContain('NOBODY');
    expect(resolveAssignee(alert({ assigned_to: 'UNASSIGNED' }), {})).toContain('NOBODY');
  });
});

describe('incidentRef', () => {
  it('shortens a uuid the way the rest of the console does', () => {
    expect(incidentRef('7f3c9a10-1111-2222-3333-444455556666')).toBe('#INC-7F3C9A10');
    expect(incidentRef(undefined)).toBe('#INC-0000');
    expect(incidentRef('INC-42')).toBe('#INC-42');
  });
});

describe('incidentPopupHtml, as a whole', () => {
  it('shows the reporter, the status and the time on one card', () => {
    const a = alert({ reported_by: 'c1', status: 'PENDING', acknowledged_at: null });
    const html = incidentPopupHtml(a, {
      reporter: resolveReporterDetails(a, { c1: CITIZEN }),
      usersMap: { c1: CITIZEN },
      now: NOW,
    });
    expect(html).toContain('Amina Dung');
    expect(html).toContain('+2348030001111');
    expect(html).toContain('AWAITING DISPATCH');
    expect(html).toContain('15m ago');
    expect(html).toContain('ARMED_ROBBERY');
  });

  it('takes its surface colours from the shared tokens, not its own palette', () => {
    // The card used to carry light/dark hexes of its own — #0F172A on one
    // theme, #E2E8F0 on the other — which are slate, not the app's neutral
    // greys. It now reads the same variables as every other panel in the
    // console, which are the app's palette, so a theme toggle restyles a popup
    // that is already open and nothing here can drift from globals.css.
    const html = incidentPopupHtml(alert(), {
      reporter: resolveReporterDetails(alert(), {}),
      now: NOW,
    });
    expect(html).toContain('var(--text-primary)');
    expect(html).toContain('var(--border)');
    expect(html).not.toContain('#0F172A');
    expect(html).not.toContain('#E2E8F0');
  });

  it('keeps status and severity as literal colours, because they are concatenated', () => {
    // `${colour}22` builds a hex with an alpha suffix, and the same value goes
    // on a Leaflet div icon. A var() cannot do either, so these two stay
    // literal — but they come from BRAND rather than being typed in here.
    //
    // They used to be typed in, with the comment "AppColors.danger" beside a
    // red the app has never had: E3-1E-24, the previous brand's. Asserting
    // the literal is what let that stand, so the assertion now reads the same
    // module the code does.
    expect(severityColour('CRITICAL')).toBe(BRAND.danger);
    expect(severityColour('HIGH')).toBe(BRAND.warning);
    expect(severityColour('MEDIUM')).toBe(BRAND.navy);
    expect(severityColour('LOW')).toBe(BRAND.emeraldDeep);
    expect(statusColour('RESOLVED')).toBe(BRAND.emeraldLight);
    expect(statusColour('PENDING')).toBe(BRAND.warning);
    expect(statusColour('DURESS')).toBe(BRAND.danger);
  });

  it('says so when there is no description, instead of leaving a gap', () => {
    const html = incidentPopupHtml(alert({ description: undefined }), {
      reporter: resolveReporterDetails(alert(), {}),
      now: NOW,
    });
    expect(html).toContain('No description was given');
  });

  it('truncates a long triage summary rather than producing an endless popup', () => {
    const html = incidentPopupHtml(alert({ ai_summary: 'x'.repeat(900) }), {
      reporter: resolveReporterDetails(alert(), {}),
      now: NOW,
    });
    const baseline = incidentPopupHtml(alert(), {
      reporter: resolveReporterDetails(alert(), {}),
      now: NOW,
    });
    expect(html).toContain('…');
    expect(html).not.toContain('x'.repeat(400));
    // The summary contributes a bounded amount, not its whole length.
    expect(html.length - baseline.length).toBeLessThan(700);
  });
});
