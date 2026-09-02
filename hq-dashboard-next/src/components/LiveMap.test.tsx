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

vi.mock('@/lib/supabase', () => ({ supabase: {} }));

// LiveMap reads `lat`/`lng`, not `latitude`/`longitude` — the dashboard maps
// the DB columns across before passing them down (see dashboard/page.tsx,
// `lat: d.latitude ?? d.lat`). Getting this wrong in a fixture produces a map
// with no markers, which is exactly the failure these tests exist to catch.
const alert = (id: string, lat: number, lng: number) => ({
  id,
  type: 'FIRE',
  status: 'ACTIVE',
  severity: 'HIGH',
  lat,
  lng,
  geo_lga: 'JOS NORTH',
  created_at: '2026-09-01T12:00:00Z',
});

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
