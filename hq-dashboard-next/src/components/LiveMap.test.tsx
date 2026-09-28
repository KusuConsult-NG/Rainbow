// Characterisation tests for LiveMap.
//
// Written against the ORIGINAL implementation, before the
// `react-hooks/set-state-in-effect` fix on the readiness signal.
//
// This component had NO test coverage at all, and it is the surface HQ watches
// incoming emergencies on. The behaviour that must survive: the map
// initialises, alerts with coordinates become markers, and a change to the
// alert list is reflected on the map. If the readiness signal is mishandled
// the map renders but stays EMPTY — which looks exactly like "no incidents".
//
// Leaflet does work under jsdom, which is what makes this possible; it needs
// matchMedia and ResizeObserver, both polyfilled in vitest.setup.ts.
import { render, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import type { Alert } from '@/app/dashboard/types';

vi.mock('@/lib/supabase', () => ({ supabase: {} }));

// LiveMap reads `lat`/`lng`, not `latitude`/`longitude` — the dashboard maps
// the DB columns across before passing them down (see dashboard/page.tsx,
// `lat: d.latitude ?? d.lat`). Getting this wrong in a fixture produces a map
// with no markers, which is exactly the failure these tests exist to catch.
//
// The status is PENDING, which is what the database actually produces. These
// fixtures said 'ACTIVE' — a Firebase-era value no migration has ever written —
// and that happened to be the ONLY status the popup's DISPATCH button was
// gated on, so the fixtures agreed with the bug.
const alert = (id: string, lat: number, lng: number, over: Partial<Alert> = {}): Alert =>
  ({
    id,
    type: 'FIRE',
    status: 'PENDING',
    severity: 'HIGH',
    lat,
    lng,
    geo_lga: 'JOS NORTH',
    created_at: '2026-09-01T12:00:00Z',
    ...over,
  }) as Alert;

const noop = () => {};

async function load() {
  return (await import('./LiveMap')).default;
}

function markerCount(container: HTMLElement) {
  return container.querySelectorAll('.leaflet-marker-icon').length;
}

describe('LiveMap', () => {
  beforeEach(() => {
    // The boundary overlay is fetched at runtime; jsdom cannot resolve the
    // relative URL. The component already tolerates the failure — this keeps
    // the noise out of the test output.
    vi.spyOn(globalThis, 'fetch').mockRejectedValue(new Error('offline in tests'));
  });

  it('initialises a Leaflet map', async () => {
    const LiveMap = await load();
    const { container } = render(
      <LiveMap alerts={[]} agents={[]} onResolve={noop} onEscalate={noop} theme="dark" />,
    );

    await waitFor(() =>
      expect(container.querySelector('.leaflet-container')).not.toBeNull(),
    );
  });

  // The one that matters. A map that initialises but never draws markers is
  // indistinguishable, to an operator, from a night with no incidents.
  it('draws a marker for an alert that has coordinates', async () => {
    const LiveMap = await load();
    const { container } = render(
      <LiveMap
        alerts={[alert('a-1', 9.9167, 8.8917)]}
        agents={[]}
        onResolve={noop}
        onEscalate={noop}
        theme="dark"
      />,
    );

    await waitFor(() => expect(markerCount(container)).toBeGreaterThan(0), {
      timeout: 5000,
    });
  });

  // Asserted by REMOVAL rather than addition: markers are clustered, so two
  // nearby alerts collapse into a single cluster icon and the count would not
  // move. Going to an empty list is unambiguous — and it is the case that
  // matters, since a stale marker for a resolved incident sends responders to
  // somewhere nothing is happening.
  it('removes a marker when its alert leaves the list', async () => {
    const LiveMap = await load();
    const props = {
      agents: [],
      onResolve: noop,
      onEscalate: noop,
      theme: 'dark' as const,
    };
    const { container, rerender } = render(
      <LiveMap alerts={[alert('a-1', 9.9167, 8.8917)]} {...props} />,
    );
    await waitFor(() => expect(markerCount(container)).toBeGreaterThan(0), {
      timeout: 5000,
    });

    rerender(<LiveMap alerts={[]} {...props} />);

    await waitFor(() => expect(markerCount(container)).toBe(0), { timeout: 5000 });
  });

  // ── What the operator sees when they click the marker ─────────────────────
  //
  // These drive the real Leaflet popup rather than the string builder (that has
  // its own tests in src/lib/incident-dossier.test.ts): the point here is that
  // the component WIRES it — the profiles reach the popup, the theme reaches it,
  // and the buttons reach the callbacks.
  // A uuid, because that is what `reported_by` holds. A short label like
  // 'rep-1' takes a different branch in the resolver — one that treats the
  // value as already human-readable — and would not exercise the lookup.
  const REPORTER_ID = 'b71c4d2e-8f10-4a33-9c55-0e6d21aa7741';
  const REPORTER = {
    id: REPORTER_ID,
    full_name: 'Amina Dung',
    phone: '+2348030001111',
    role: 'CITIZEN',
  };

  async function openPopup(
    container: HTMLElement,
    _user: unknown = null,
  ): Promise<HTMLElement> {
    const marker = container.querySelector('.leaflet-marker-icon') as HTMLElement;
    marker.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    await waitFor(() => {
      expect(container.querySelector('.leaflet-popup-content')).not.toBeNull();
    }, { timeout: 5000 });
    return container.querySelector('.leaflet-popup-content') as HTMLElement;
  }

  it('names the reporter and shows the number to ring them on', async () => {
    // The defect: LiveMap declared `reportedBy`/`reportedAt` — Firebase names
    // PostgREST never returns — and was given no profiles at all, so a marker
    // could not identify the person who raised the emergency.
    const LiveMap = await load();
    const { container } = render(
      <LiveMap
        alerts={[alert('a-1', 9.9167, 8.8917, { reported_by: REPORTER_ID })]}
        agents={[]}
        usersMap={{ [REPORTER_ID]: REPORTER }}
        onResolve={noop}
        onEscalate={noop}
        theme="dark"
      />,
    );
    await waitFor(() => expect(markerCount(container)).toBeGreaterThan(0), { timeout: 5000 });

    const popup = await openPopup(container);
    expect(popup.textContent).toContain('Amina Dung');
    expect(popup.textContent).toContain('+2348030001111');
    expect(popup.querySelector('a[href^="tel:"]')).not.toBeNull();
  });

  it('shows the status, the age and whether anybody has taken it', async () => {
    const LiveMap = await load();
    const { container } = render(
      <LiveMap
        alerts={[alert('a-1', 9.9167, 8.8917, { acknowledged_at: null })]}
        agents={[]}
        onResolve={noop}
        onEscalate={noop}
        theme="dark"
      />,
    );
    await waitFor(() => expect(markerCount(container)).toBeGreaterThan(0), { timeout: 5000 });

    const popup = await openPopup(container);
    expect(popup.textContent).toContain('AWAITING DISPATCH');
    expect(popup.textContent).toContain('ACKNOWLEDGED');
    expect(popup.textContent).toContain('NO');
    expect(popup.textContent).toContain('JOS NORTH');
    expect(popup.textContent).toContain('9.91670');
  });

  it('offers DISPATCH on a PENDING incident', async () => {
    // It did not. The button was gated on `status === 'OPEN' || 'ACTIVE'`,
    // neither of which this database produces, so a newly reported emergency
    // could be resolved from the map but never dispatched from it.
    const LiveMap = await load();
    const dispatched: string[] = [];
    const { container } = render(
      <LiveMap
        alerts={[alert('a-1', 9.9167, 8.8917)]}
        agents={[]}
        onResolve={noop}
        onEscalate={(ids) => dispatched.push(String(ids))}
        theme="dark"
      />,
    );
    await waitFor(() => expect(markerCount(container)).toBeGreaterThan(0), { timeout: 5000 });

    const popup = await openPopup(container);
    const button = Array.from(popup.querySelectorAll('button')).find(
      (b) => b.textContent === 'DISPATCH',
    );
    expect(button, 'a PENDING incident must be dispatchable from the map').not.toBeUndefined();
  });

  it('opens the full dossier for the incident clicked', async () => {
    const LiveMap = await load();
    const opened: string[] = [];
    const { container } = render(
      <LiveMap
        alerts={[alert('a-1', 9.9167, 8.8917)]}
        agents={[]}
        onResolve={noop}
        onEscalate={noop}
        onOpenDossier={(id) => opened.push(id)}
        theme="dark"
      />,
    );
    await waitFor(() => expect(markerCount(container)).toBeGreaterThan(0), { timeout: 5000 });

    const popup = await openPopup(container);
    const button = Array.from(popup.querySelectorAll('button')).find(
      (b) => b.textContent === 'DOSSIER',
    ) as HTMLButtonElement;
    expect(button).not.toBeUndefined();
    // The button carries the call, and the handler it names does the work. The
    // two halves are asserted separately because jsdom evaluates an inline
    // `onclick` in its own global scope, which is not the one vitest gives the
    // test — a real click is covered by the browser harness
    // (scripts/local_e2e), where there is a real window.
    expect(button.getAttribute('onclick')).toBe("window._hqDossier('a-1')");
    (window as unknown as { _hqDossier: (id: string) => void })._hqDossier('a-1');
    expect(opened).toEqual(['a-1']);
  });

  it('does not execute markup a reporter typed into a description', async () => {
    const LiveMap = await load();
    const { container } = render(
      <LiveMap
        alerts={[
          alert('a-1', 9.9167, 8.8917, {
            description: '<img src=x onerror="window.__pwned=true">',
          }),
        ]}
        agents={[]}
        onResolve={noop}
        onEscalate={noop}
        theme="dark"
      />,
    );
    await waitFor(() => expect(markerCount(container)).toBeGreaterThan(0), { timeout: 5000 });

    const popup = await openPopup(container);
    expect(popup.querySelector('img')).toBeNull();
    expect((window as unknown as { __pwned?: boolean }).__pwned).toBeUndefined();
    expect(popup.textContent).toContain('<img');
  });

  it('a theme toggle does not throw, and restyles the popup', async () => {
    // `mapInstanceRef.current.getPane(...)` — the ref holds `{ map, L }`, so
    // this threw "not a function" inside an effect on every theme toggle.
    const LiveMap = await load();
    const props = {
      alerts: [alert('a-1', 9.9167, 8.8917)],
      agents: [],
      onResolve: noop,
      onEscalate: noop,
    };
    const { container, rerender } = render(<LiveMap {...props} theme="dark" />);
    await waitFor(() => expect(markerCount(container)).toBeGreaterThan(0), { timeout: 5000 });
    expect(container.querySelector('.hq-map-dark')).not.toBeNull();

    expect(() => rerender(<LiveMap {...props} theme="light" />)).not.toThrow();
    await waitFor(() => expect(container.querySelector('.hq-map-dark')).toBeNull());
  });

  it('rebuilds the popup when the profiles arrive after the alerts', async () => {
    // Profiles load in their own effect, which resolves after the first alerts.
    // With `usersMap` missing from the marker effect's dependencies the popup
    // was built once, before any profile existed, and the reporter stayed
    // unnamed for the whole session.
    const LiveMap = await load();
    const props = {
      alerts: [alert('a-1', 9.9167, 8.8917, { reported_by: REPORTER_ID })],
      agents: [],
      onResolve: noop,
      onEscalate: noop,
      theme: 'dark' as const,
    };
    const { container, rerender } = render(<LiveMap {...props} usersMap={{}} />);
    await waitFor(() => expect(markerCount(container)).toBeGreaterThan(0), { timeout: 5000 });
    let popup = await openPopup(container);
    expect(popup.textContent).toContain('UNIDENTIFIED');

    rerender(<LiveMap {...props} usersMap={{ [REPORTER_ID]: REPORTER }} />);
    await waitFor(() => {
      popup = container.querySelector('.leaflet-popup-content') as HTMLElement;
      expect(popup.textContent).toContain('Amina Dung');
    }, { timeout: 5000 });
  });

  it('unmounts without throwing', async () => {
    const LiveMap = await load();
    const { container, unmount } = render(
      <LiveMap
        alerts={[alert('a-1', 9.9167, 8.8917)]}
        agents={[]}
        onResolve={noop}
        onEscalate={noop}
        theme="dark"
      />,
    );
    await waitFor(() =>
      expect(container.querySelector('.leaflet-container')).not.toBeNull(),
    );
    expect(() => unmount()).not.toThrow();
  });
});
