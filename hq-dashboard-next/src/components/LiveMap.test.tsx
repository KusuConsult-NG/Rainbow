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

  it('routes an action it was not given a button for, with the tier from the incident', async () => {
    // The listener switches on `data-hq-action`, and `escalate` is a branch no
    // popup currently renders a button for — the global it replaces
    // (`window._hqEscalate(id, tier)`) was installed by this component and
    // called from nowhere at all, so the only caller it ever had would have
    // been passing a tier invented at the call site.
    //
    // This presses a button carrying that action to prove two things: the
    // listener is a real router rather than one handler per popup, and the
    // tier it hands on comes from the INCIDENT. A string in the markup is not
    // a fact about where the incident currently sits.
    const LiveMap = await load();
    const escalated: Array<[string, string]> = [];
    const { container } = render(
      <LiveMap
        alerts={[alert('a-1', 9.9167, 8.8917, { assigned_tier: 'LGA' } as Partial<Alert>)]}
        agents={[]}
        onResolve={noop}
        onEscalate={(ids, tier) => escalated.push([String(ids), tier])}
        theme="dark"
      />,
    );
    await waitFor(() => expect(markerCount(container)).toBeGreaterThan(0), { timeout: 5000 });

    const popup = await openPopup(container);
    const button = document.createElement('button');
    button.setAttribute('data-hq-action', 'escalate');
    button.setAttribute('data-hq-id', 'a-1');
    popup.appendChild(button);
    button.click();

    await waitFor(() => expect(escalated).toEqual([['a-1', 'LGA']]), { timeout: 2000 });
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
    // A REAL CLICK, all the way through.
    //
    // This used to assert the two halves separately — that the button carried
    // `onclick="window._hqDossier('a-1')"`, and that calling that global did
    // the work — with a comment explaining that jsdom evaluates an inline
    // handler in its own global scope, so the join could not be tested here
    // and was left to the browser harness. The browser harness pressed it,
    // recorded "nothing", and that was not a failing check: the console's own
    // CSP (`script-src` with no `'unsafe-inline'`) refuses inline event
    // handlers, so the join NEVER WORKED and neither half said so.
    //
    // The button now carries `data-hq-action` and the map listens once, which
    // is CSP-safe and clickable in jsdom, so the whole path is one assertion.
    expect(button.getAttribute('onclick')).toBeNull();
    expect(button.getAttribute('data-hq-action')).toBe('dossier');
    expect(button.getAttribute('data-hq-id')).toBe('a-1');

    button.click();

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

  it('a theme toggle does not throw, and re-filters the tiles', async () => {
    // `mapInstanceRef.current.getPane(...)` — the ref holds `{ map, L }`, so
    // this threw "not a function" inside an effect on every theme toggle, and
    // took the whole board down with it: the harness caught the console
    // rendering its CONSOLE FAILED boundary for all six roles.
    //
    // The popup no longer has a per-theme class to check, which is the point:
    // its colours come from CSS variables that `.dark-theme` on <body>
    // redefines. The tile filter is the one thing that still has to change
    // here, because a filter is not a colour.
    const LiveMap = await load();
    const props = {
      alerts: [alert('a-1', 9.9167, 8.8917)],
      agents: [],
      onResolve: noop,
      onEscalate: noop,
    };
    const { container, rerender } = render(<LiveMap {...props} theme="dark" />);
    await waitFor(() => expect(markerCount(container)).toBeGreaterThan(0), { timeout: 5000 });

    const tilePane = () => container.querySelector('.leaflet-tile-pane') as HTMLElement;
    expect(tilePane().style.filter).toContain('invert');

    expect(() => rerender(<LiveMap {...props} theme="light" />)).not.toThrow();
    await waitFor(() => expect(tilePane().style.filter).toBe('none'));
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

  it('unmounting with a popup open does not throw a frame later', async () => {
    // Opening a popup near an edge starts Leaflet's autoPan, which runs on
    // requestAnimationFrame. Switching tab inside that window unmounts the map
    // mid-animation, and the next frame called `map._mapPane.classList` on a
    // map with no panes: an uncaught TypeError in the console HQ watches,
    // twice per visit. The browser harness caught it first; this suite
    // reproduced it five times over once the popup tests existed.
    const LiveMap = await load();
    const thrown: unknown[] = [];
    const onUncaught = (e: unknown) => thrown.push(e);
    process.on('uncaughtException', onUncaught);
    try {
      const { container, unmount } = render(
        <LiveMap
          alerts={[alert('a-1', 9.9167, 8.8917)]}
          agents={[]}
          onResolve={noop}
          onEscalate={noop}
          theme="dark"
        />,
      );
      await waitFor(() => expect(markerCount(container)).toBeGreaterThan(0), { timeout: 5000 });
      await openPopup(container);
      unmount();
      // Let several animation frames run against the dead map.
      await new Promise((r) => setTimeout(r, 400));
    } finally {
      process.off('uncaughtException', onUncaught);
    }
    expect(thrown.map(String)).toEqual([]);
  });

  it('cancels the boundary fetch and the resize timer when it unmounts', async () => {
    // Signing out unmounts the map. Two things were still in flight and both
    // touched it afterwards: the 250ms `invalidateSize` timer, which read
    // `_leaflet_pos` off a pane that had been removed, and the boundary fetch,
    // which added a GeoJSON layer to a map with no panes to append it to. The
    // browser harness caught both on a role switch.
    //
    // Asserted on the MECHANISM — the signal is aborted, the timer never fires
    // — rather than on "nothing threw". jsdom tolerates both calls against a
    // dead map without raising, so an assertion about throwing would pass with
    // the fix removed, which is worse than no test. Chromium does raise, and
    // the harness fails the run on it.
    const LiveMap = await load();
    const signals: (AbortSignal | null | undefined)[] = [];
    (globalThis.fetch as unknown) = vi.fn((_url: string, init?: RequestInit) => {
      signals.push(init?.signal);
      // Never resolves: the unmount must be what ends this, not the response.
      return new Promise(() => {});
    });

    const { container, unmount } = render(
      <LiveMap
        alerts={[alert('a-1', 9.9167, 8.8917)]}
        agents={[]}
        onResolve={noop}
        onEscalate={noop}
        theme="dark"
      />,
    );
    await waitFor(() => expect(container.querySelector('.leaflet-container')).not.toBeNull());

    const Leaflet = (window as unknown as { L: { Map: { prototype: Record<string, unknown> } } }).L;
    const invalidateSize = vi.spyOn(Leaflet.Map.prototype as never, 'invalidateSize');

    unmount();
    // Well past the 250ms resize timer.
    await new Promise((r) => setTimeout(r, 500));

    expect(signals.length, 'the boundary overlay is fetched').toBeGreaterThan(0);
    expect(signals[0]?.aborted, 'the fetch is aborted by the unmount').toBe(true);
    expect(
      invalidateSize,
      'the resize timer must not fire on a map that has been removed',
    ).not.toHaveBeenCalled();
    invalidateSize.mockRestore();
  });

  // ── The blinking dossier ──────────────────────────────────────────────────
  //
  // Reported from the console: "when admin click on the point on the map to see
  // more details, the info card blinks why?"
  //
  // Because every realtime event ends in an unconditional `setAlerts(mapped)` —
  // a new array even when nothing differs — so the marker effect re-ran two or
  // three times a minute and called `setIcon` and `setContent` on every
  // existing marker. `Marker.setIcon` re-binds the popup and `Popup.setContent`
  // replaces its content node, so the open card was torn down and rebuilt from
  // inputs that had not changed.
  //
  // These assert on DOM IDENTITY, not on text: the card showing the same words
  // is exactly what it looked like before, and is not the same thing as the
  // card not having been rebuilt.

  describe('a refetch that changes nothing', () => {
    it('leaves an open dossier standing rather than rebuilding it', async () => {
      const LiveMap = await load();
      const rows = [alert('a-1', 9.9167, 8.8917, { reported_by: REPORTER_ID })];
      const props = {
        agents: [],
        usersMap: { [REPORTER_ID]: REPORTER },
        onResolve: noop,
        onEscalate: noop,
        theme: 'dark' as const,
      };
      const { container, rerender } = render(<LiveMap alerts={rows} {...props} />);
      await waitFor(() => expect(markerCount(container)).toBeGreaterThan(0), { timeout: 5000 });

      const before = await openPopup(container);
      const markerBefore = container.querySelector('.leaflet-marker-icon');

      // What a realtime poll actually hands down: equal rows, new identities.
      rerender(<LiveMap alerts={rows.map(r => ({ ...r }))} {...props} />);
      await waitFor(() => expect(markerCount(container)).toBeGreaterThan(0));

      const after = container.querySelector('.leaflet-popup-content');
      expect(after).not.toBeNull();
      // The same node, not merely a node with the same words in it.
      expect(after).toBe(before);
      expect(container.querySelector('.leaflet-marker-icon')).toBe(markerBefore);
    });

    it('does not replace the contents of the card either', async () => {
      // A SECOND signal, because the first one cannot see this defect.
      //
      // `Popup.setContent` with a string ends in `contentNode.innerHTML = html`,
      // which REUSES the content node and destroys everything inside it. So
      // node identity is blind to it, and the children are what to watch: an
      // innerHTML assignment gives the card a whole new first child even when
      // the html is identical.
      const LiveMap = await load();
      const rows = [alert('a-1', 9.9167, 8.8917)];
      const props = { agents: [], onResolve: noop, onEscalate: noop, theme: 'dark' as const };
      const { container, rerender } = render(<LiveMap alerts={rows} {...props} />);
      await waitFor(() => expect(markerCount(container)).toBeGreaterThan(0), { timeout: 5000 });

      const card = await openPopup(container);
      const childBefore = card.firstElementChild;
      expect(childBefore).not.toBeNull();

      for (let i = 0; i < 5; i += 1) {
        rerender(<LiveMap alerts={[{ ...rows[0] }]} {...props} />);
        await waitFor(() => expect(markerCount(container)).toBe(1));
      }

      const cardAfter = container.querySelector('.leaflet-popup-content')!;
      expect(cardAfter.firstElementChild).toBe(childBefore);
    });
  });

  describe('a refetch that changes something', () => {
    it('updates the dossier when the incident actually changed', async () => {
      // The guard must not become a cache. An incident that has been taken has
      // to say so on the card the operator is looking at.
      const LiveMap = await load();
      const props = { agents: [], onResolve: noop, onEscalate: noop, theme: 'dark' as const };
      const { container, rerender } = render(
        <LiveMap alerts={[alert('a-1', 9.9167, 8.8917, { status: 'PENDING' })]} {...props} />,
      );
      await waitFor(() => expect(markerCount(container)).toBeGreaterThan(0), { timeout: 5000 });
      const popup = await openPopup(container);
      // The card prints plain words, not the enum: statusLabel() in
      // incident-dossier.ts maps PENDING to AWAITING DISPATCH.
      expect(popup.textContent).toContain('AWAITING DISPATCH');

      rerender(
        <LiveMap
          alerts={[alert('a-1', 9.9167, 8.8917, { status: 'DISPATCHED' })]}
          {...props}
        />,
      );
      await waitFor(() => {
        expect(
          container.querySelector('.leaflet-popup-content')!.textContent,
        ).toContain('UNIT DISPATCHED');
      });
    });

    it('follows a marker that moved, and the card stays open on it', async () => {
      // This test first asserted that a move leaves the card's contents
      // untouched, and that was simply wrong: the dossier PRINTS the
      // coordinates (the COORDINATES row in incident-dossier.ts), so a move
      // genuinely changes the html and setContent firing is correct.
      //
      // What matters is what an operator would notice: the card must not CLOSE,
      // and it must tell the truth about where the incident now is.
      const LiveMap = await load();
      const props = { agents: [], onResolve: noop, onEscalate: noop, theme: 'dark' as const };
      const { container, rerender } = render(
        <LiveMap alerts={[alert('a-1', 9.9167, 8.8917)]} {...props} />,
      );
      await waitFor(() => expect(markerCount(container)).toBeGreaterThan(0), { timeout: 5000 });
      const before = await openPopup(container);
      expect(before.textContent).toContain('9.91670');

      rerender(<LiveMap alerts={[alert('a-1', 9.9300, 8.9000)]} {...props} />);
      await waitFor(() => {
        expect(
          container.querySelector('.leaflet-popup-content')!.textContent,
        ).toContain('9.93000');
      });
      // Still open, and still the same card rather than a fresh one.
      expect(container.querySelector('.leaflet-popup-content')).toBe(before);
    });
  });

  // ── An incident with no GPS ───────────────────────────────────────────────
  //
  // A USSD report has no GPS and cannot have one. This component used to skip
  // any alert without finite coordinates, so a USSD emergency appeared in the
  // incident list and NOWHERE on the map the operator is watching.
  //
  // The fix is not to invent coordinates — that is the C-5 defect, where a
  // missing fix fell back to central Jos and drew a confident pin. It is to draw
  // an approximate position as an approximate position, and these tests hold that
  // line: an AREA, never a marker, and never mistakable for a fix.

  describe('an incident with a ward but no GPS', () => {
    const wardAlert = () =>
      ({
        ...alert('u-1', 0, 0),
        lat: undefined,
        lng: undefined,
        geo_lga: 'JOS NORTH',
        geo_ward: 'ABBA NA SHEHU',
      }) as unknown as Alert;

    it('is drawn, rather than vanishing from the map', async () => {
      const LiveMap = await load();
      const { container } = render(
        <LiveMap alerts={[wardAlert()]} agents={[]} onResolve={noop} onEscalate={noop} theme="dark" />,
      );
      await waitFor(() =>
        expect(container.querySelector('.leaflet-container')).not.toBeNull(),
      );
      // Leaflet renders a circle into the overlay pane as an SVG path.
      await waitFor(() =>
        expect(container.querySelectorAll('.leaflet-overlay-pane path').length)
          .toBeGreaterThan(0),
      );
    });

    it('is NOT drawn as a marker', async () => {
      // The whole point. A pin says "here"; this is not here, it is somewhere in
      // a ward, and the difference decides whether a vehicle can be sent.
      const LiveMap = await load();
      const { container } = render(
        <LiveMap alerts={[wardAlert()]} agents={[]} onResolve={noop} onEscalate={noop} theme="dark" />,
      );
      await waitFor(() =>
        expect(container.querySelectorAll('.leaflet-overlay-pane path').length)
          .toBeGreaterThan(0),
      );
      expect(markerCount(container)).toBe(0);
    });

    it('warns in the dossier, at the TOP, and says not to dispatch to it', async () => {
      // A warning found three rows down, after a coordinate-shaped circle has
      // already been believed, is not a warning.
      const LiveMap = await load();
      const { container } = render(
        <LiveMap alerts={[wardAlert()]} agents={[]} onResolve={noop} onEscalate={noop} theme="dark" />,
      );
      const circle = await waitFor(() => {
        const p = container.querySelector('.leaflet-overlay-pane path');
        expect(p).not.toBeNull();
        return p as Element;
      });
      circle.dispatchEvent(new MouseEvent('click', { bubbles: true }));
      const popup = await waitFor(() => {
        const el = container.querySelector('.leaflet-popup-content');
        expect(el).not.toBeNull();
        return el as HTMLElement;
      }, { timeout: 5000 });
      expect(popup.textContent).toContain('NO GPS');
      expect(popup.textContent).toContain('Do not dispatch');
      // And it carries the SAME dossier a marker would, so an approximate
      // incident is not second-class on the screen that decides who gets help.
      expect(popup.textContent).toContain('INCIDENT');
    });
  });

  describe('the landmark on an approximate incident', () => {
    it('is in the same banner as the no-GPS warning', async () => {
      // It is the answer to the question the warning raises — "then where is
      // it?" — and a dispatcher who reads "no GPS" and stops has missed the one
      // navigable thing on the card.
      const LiveMap = await load();
      const withLandmark = {
        ...alert('u-3', 0, 0),
        lat: undefined, lng: undefined,
        geo_lga: 'JOS NORTH', geo_ward: 'ABBA NA SHEHU',
        reporter_landmark: 'behind the Bauchi Road mosque',
      } as unknown as Alert;
      const { container } = render(
        <LiveMap alerts={[withLandmark]} agents={[]} onResolve={noop} onEscalate={noop} theme="dark" />,
      );
      const circle = await waitFor(() => {
        const p = container.querySelector('.leaflet-overlay-pane path');
        expect(p).not.toBeNull();
        return p as Element;
      });
      circle.dispatchEvent(new MouseEvent('click', { bubbles: true }));
      const popup = await waitFor(() => {
        const el = container.querySelector('.leaflet-popup-content');
        expect(el).not.toBeNull();
        return el as HTMLElement;
      }, { timeout: 5000 });
      expect(popup.textContent).toContain('behind the Bauchi Road mosque');
      expect(popup.textContent).toContain('NO GPS');
    });

    it('does not execute markup a reporter typed into it', async () => {
      // The landmark is typed by a member of the public and lands in innerHTML.
      // incident-dossier.ts escapes every reporter-supplied value for exactly
      // this reason; a banner that skipped it would be the one place a reporter
      // could script the dispatcher's console.
      const LiveMap = await load();
      const hostile = {
        ...alert('u-4', 0, 0),
        lat: undefined, lng: undefined,
        geo_lga: 'JOS NORTH', geo_ward: 'ABBA NA SHEHU',
        reporter_landmark: '<img src=x onerror="window.__pwned=1">near the market',
      } as unknown as Alert;
      const { container } = render(
        <LiveMap alerts={[hostile]} agents={[]} onResolve={noop} onEscalate={noop} theme="dark" />,
      );
      const circle = await waitFor(() => {
        const p = container.querySelector('.leaflet-overlay-pane path');
        expect(p).not.toBeNull();
        return p as Element;
      });
      circle.dispatchEvent(new MouseEvent('click', { bubbles: true }));
      const popup = await waitFor(() => {
        const el = container.querySelector('.leaflet-popup-content');
        expect(el).not.toBeNull();
        return el as HTMLElement;
      }, { timeout: 5000 });
      expect(popup.querySelector('img')).toBeNull();
      expect((globalThis as Record<string, unknown>).__pwned).toBeUndefined();
      // The words still reach the dispatcher, escaped.
      expect(popup.textContent).toContain('near the market');
    });
  });

  describe('an incident with nothing at all', () => {
    it('is still not drawn, and no coordinates are invented', async () => {
      // The C-5 line. An alert with no location must not appear anywhere on the
      // map — the console reports it in the UNLOCATED counter instead.
      const LiveMap = await load();
      const nowhere = {
        ...alert('n-1', 0, 0),
        lat: undefined, lng: undefined, geo_lga: undefined, geo_ward: undefined,
      } as unknown as Alert;
      const { container } = render(
        <LiveMap alerts={[nowhere]} agents={[]} onResolve={noop} onEscalate={noop} theme="dark" />,
      );
      await waitFor(() =>
        expect(container.querySelector('.leaflet-container')).not.toBeNull(),
      );
      expect(markerCount(container)).toBe(0);
      expect(container.querySelectorAll('.leaflet-overlay-pane path')).toHaveLength(0);
    });
  });

  describe('a GPS fix beside an approximate one', () => {
    it('draws one marker and one circle, not two of either', async () => {
      const LiveMap = await load();
      const fixed = alert('g-1', 9.9167, 8.8917);
      const approx = {
        ...alert('u-2', 0, 0),
        lat: undefined, lng: undefined,
        geo_lga: 'MANGU', geo_ward: 'AMPANG WEST',
      } as unknown as Alert;
      const { container } = render(
        <LiveMap alerts={[fixed, approx]} agents={[]} onResolve={noop} onEscalate={noop} theme="dark" />,
      );
      await waitFor(() => expect(markerCount(container)).toBe(1));
      expect(container.querySelectorAll('.leaflet-overlay-pane path').length)
        .toBeGreaterThan(0);
    });
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
