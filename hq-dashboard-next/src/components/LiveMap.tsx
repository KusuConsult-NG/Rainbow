'use client';
import { useMediaQuery } from '@/hooks/useMediaQuery';
import { useCallback, useEffect, useRef, useState, useSyncExternalStore } from 'react';

/**
 * The alert shape comes from the ONE place that defines it.
 *
 * This file used to declare its own interface: `id`, `status`, `lat`, `lng`,
 * `type`, `priority`, `description`, `assigned_to`, `reportedBy` and
 * `reportedAt?: { seconds: number }`. The last two are Firebase names —
 * PostgREST returns `reported_by` and `created_at` and never a camelCase key —
 * so the map could not have shown the reporter or the time even if it had tried.
 * Everything else in the row was invisible here simply because the interface
 * did not mention it.
 *
 * Importing the canonical type means a column the schema gains is available the
 * day the type learns about it, and a field that does not exist is a type error
 * rather than a silent `undefined`.
 */
import type { Alert } from '@/app/dashboard/types';
import {
  incidentPopupHtml,
  isUnacknowledged,
  resolveReporterDetails,
  statusColour,
} from '@/lib/incident-dossier';
import {
  approxRadiusLabel,
  locateIncident,
  type IncidentLocation,
} from '@/lib/incident-locate';

/**
 * A one-bit store for "the Leaflet map exists".
 *
 * The map is created imperatively inside an effect, and the marker-drawing
 * effects need to know when it is there. Doing that with `setState` inside the
 * effect is what `react-hooks/set-state-in-effect` forbids — and the rule is
 * right about the shape even though the cascade here is one render at mount:
 * an allowlist with one entry still has to be maintained, and can be widened
 * by the next person.
 *
 * Modelling the map as what it is — an external system this component
 * subscribes to — removes the exception entirely. It does not reduce the
 * number of renders; it makes the rule enforceable everywhere with no
 * exceptions, which is the actual benefit.
 */
function createReadySignal() {
  let ready = false;
  const subscribers = new Set<() => void>();
  return {
    get: () => ready,
    set: (next: boolean) => {
      if (ready === next) return;
      ready = next;
      subscribers.forEach((notify) => notify());
    },
    subscribe: (notify: () => void) => {
      subscribers.add(notify);
      return () => {
        subscribers.delete(notify);
      };
    },
  };
}

export interface AgentLocation {
  id: string;
  user_id: string;
  lat: number;
  lng: number;
  mode?: string;
  status?: 'PATROLLING' | 'BUSY' | 'EMERGENCY' | 'OFFLINE' | 'DURESS';
  displayName?: string;
  timestamp?: any;
  geo_integrity?: string;
  path?: { lat: number; lng: number; timestamp?: string }[];
  telemetry?: {
    battery: number;
    network: string;
    accuracy: number;
  };
}

interface Props {
  alerts: Alert[];
  agents?: AgentLocation[];
  onResolve: (ids: string | string[]) => void;
  onEscalate: (ids: string | string[], tier: string) => void;
  /**
   * Profiles by id, so a marker can name the person who reported the incident
   * and the officer it is assigned to. Without it the popup can still render —
   * it says the profile was not loaded rather than inventing a citizen.
   */
  usersMap?: Record<string, any>;
  /** Opens the full incident dossier for one alert. */
  onOpenDossier?: (id: string) => void;
  /**
   * The stored route of the incident currently being looked at.
   *
   * Separate from `agents[].path`, which is accumulated in the browser from
   * live telemetry and therefore only exists for as long as the tab does. This
   * one comes from `incident_tracks` and survives a refresh — it is the answer
   * to "which way did they go" for an incident that has already happened.
   */
  incidentTrack?: { lat: number; lng: number }[];
  theme?: 'light' | 'dark';
}

export default function LiveMap({
  alerts,
  agents = [],
  onResolve,
  onEscalate,
  usersMap = {},
  onOpenDossier,
  incidentTrack,
  theme = 'light',
}: Props) {
  const mapRef = useRef<HTMLDivElement>(null);
  const mapInstanceRef = useRef<any>(null);
  const markersRef = useRef<any[]>([]);
  const agentMarkersRef = useRef<Map<string, any>>(new Map());
  const agentPolylinesRef = useRef<Map<string, any>>(new Map());
  const tileLayerRef = useRef<any>(null);

  // Per-instance, created once. Held in state rather than a ref because refs
  // must not be read during render, and `subscribe`/`getSnapshot` are read on
  // every render. `getServerSnapshot` is false — there is no map on the server.
  const [readySignal] = useState(createReadySignal);
  const mapReady = useSyncExternalStore(
    readySignal.subscribe,
    readySignal.get,
    () => false,
  );
  const [showRiskGrid, setShowRiskGrid] = useState(true);
  const riskGridLayersRef = useRef<any[]>([]);
  const [leafletLoaded, setLeafletLoaded] = useState(false);
  // The analytics HUD is a secondary overlay. At phone width it competes with
  // the map it annotates, so it stands down below the console breakpoint.
  const isNarrow = useMediaQuery('(max-width: 1024px)');

  // Plateau State Tactical Bounds
  /**
 * Where tiles come from. ONE definition — there were two, and they disagreed.
 *
 * CARTO's basemaps were used for the dark theme. CARTO now requires an account
 * and answers unauthenticated requests with a placeholder tile reading
 * "API key required", so the command map rendered as a grid of watermarks with
 * the incident markers floating on top. That is worse than a blank map: a blank
 * map is obviously broken, whereas a map covered in text looks like somebody
 * else's configuration problem while every street and landmark is gone.
 *
 * The second bug was the divergence. The initial layer used OpenStreetMap for
 * the light theme; the theme-change effect used CARTO for BOTH. So a dark/light
 * toggle moved even the light theme onto the watermarked provider, and which
 * tiles you got depended on whether you had touched the theme since loading.
 *
 * OpenStreetMap needs no key. It is light, so dark is produced here with a CSS
 * filter on the tile pane — markers and boundaries live in other panes and keep
 * their own colours, which matters because a filter over the whole map would
 * turn a red critical marker green.
 *
 * NEXT_PUBLIC_MAP_TILE_URL overrides it, so moving to a keyed or self-hosted
 * provider is a config change rather than a code change. OSM's tile policy is
 * aimed at modest use; a statewide service in daily operation should be on its
 * own or a commercial provider, and this is the seam for that.
 */
const TILE_URL =
  process.env.NEXT_PUBLIC_MAP_TILE_URL || 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/** A provider's own dark tiles must not be darkened again. */
const TILES_ALREADY_DARK = /dark|night/i.test(TILE_URL);

/** Invert, then pull back towards neutral so inverted water is not orange. */
const DARK_TILE_FILTER = 'invert(0.92) hue-rotate(180deg) saturate(0.75) brightness(0.95)';

function tileFilterFor(theme: string): string {
  if (TILES_ALREADY_DARK) return 'none';
  return theme === 'dark' ? DARK_TILE_FILTER : 'none';
}

const plateauBounds: [[number, number], [number, number]] = [[8.30, 8.30], [10.50, 10.80]];

  // Leaflet is loaded from the LOCAL package, not a CDN.
  //
  // This previously did `loadScript('https://unpkg.com/leaflet@1.9.4/dist/leaflet.js')`,
  // which made the command dashboard's map — the only surface through which HQ
  // sees incoming alerts — hard-dependent on unpkg being reachable at runtime.
  // On a restricted government network, or during an unpkg outage, the map did
  // not degrade: it never initialised. There was also no SRI, so an unpkg
  // compromise meant arbitrary JS inside the command dashboard.
  //
  // `leaflet` was already a dependency, so this was fetching over the network
  // something the bundle already contained. Imports stay dynamic and inside the
  // effect because Leaflet touches `window` and must not run during SSR.
  useEffect(() => {
    let isMounted = true;

    const isReady = () => {
      const L = (window as any).L;
      return !!L;
    };

    // There used to be a synchronous fast path here: if `window.L` already
    // existed (a remount), it called setLeafletLoaded(true) straight away.
    // That was a set-state-in-effect, and it was redundant — initScripts
    // already skips the import when `window.L` is set, and a dynamic import of
    // an already-evaluated module resolves from the module cache on the next
    // microtask. Going through one path costs a microtask and removes a branch.
    const initScripts = async () => {
      try {
        if (!(window as any).L) {
          const leaflet = await import('leaflet');
          // The markercluster plugin augments the global `L`, and the rest of
          // this component reads `window.L`, so keep that contract.
          (window as any).L = leaflet.default ?? leaflet;
        }
        if (typeof (window as any).L?.markerClusterGroup !== 'function') {
          try {
            await import('leaflet.markercluster');
          } catch (e) {
            console.warn('MarkerCluster failed to load, falling back to LayerGroup', e);
          }
        }
        if (isMounted && isReady()) {
          setLeafletLoaded(true);
        }
      } catch (err) {
        console.error('Failed to initialise Leaflet:', err);
      }
    };

    initScripts();
    return () => { isMounted = false; };
  }, []);

  useEffect(() => {
    if (!mapRef.current || mapInstanceRef.current || !leafletLoaded) return;

    const Leaflet = (window as any).L;
    if (!Leaflet) return;

    const map = Leaflet.map(mapRef.current!, {
      center: [9.9167, 8.8917],
      zoom: 9,
      minZoom: 7,
      maxBounds: Leaflet.latLngBounds(plateauBounds[0], plateauBounds[1]),
      zoomControl: false,
    });

    Leaflet.control.zoom({ position: 'bottomright' }).addTo(map);

    const tileLayer = Leaflet.tileLayer(TILE_URL, {
      attribution: '© OpenStreetMap contributors',
      maxZoom: 19,
    }).addTo(map);
    tileLayerRef.current = tileLayer;

    // The tile pane only. Markers, boundaries and the risk grid are in their own
    // panes and must keep their colours.
    const pane = map.getPane('tilePane');
    if (pane) pane.style.filter = tileFilterFor(theme);

    // Both of the async steps below outlive the map if nobody stops them, and
    // both then touch it. Signing out, or switching tab within a second of the
    // map appearing, used to throw twice:
    //
    //   TypeError: Cannot read properties of undefined (reading '_leaflet_pos')
    //   Failed to load boundaries: ... (reading 'appendChild')
    //
    // The first is this resize timer calling `invalidateSize()` on a map whose
    // panes are gone; the second is the boundary fetch resolving afterwards and
    // adding a layer to it. Neither was cancelled, because neither looks like
    // something that needs cancelling.
    let alive = true;
    const boundaries = new AbortController();

    // Force map to adjust size to container after render
    const resizeTimer = setTimeout(() => {
      if (alive) map.invalidateSize();
    }, 250);

    // Fetch and draw Geo-Boundaries
    fetch('/plateau_boundaries.json', { signal: boundaries.signal })
      .then(res => res.json())
      .then(data => {
        if (!alive) return;
        Leaflet.geoJSON(data, {
          // Navy, not `--duress`. The seventeen LGA boundaries were drawn
          // with the DURESS token: the state's own internal borders were
          // painted in the one colour that means a person is in danger, so
          // a map with nothing happening on it still read as alarming, and
          // a real critical marker had to compete with every border on
          // screen. Boundaries are structure; red is an incident.
          style: {
            color: 'var(--primary)',
            weight: 1.5,
            opacity: 0.55,
            fillColor: 'var(--primary)',
            fillOpacity: 0.04,
            dashArray: '3, 3'
          },
          onEachFeature: (feature: any, layer: any) => {
            if (feature.properties && feature.properties.lga) {
              layer.bindTooltip(`<b>${feature.properties.lga.toUpperCase()}</b>`, {
                permanent: true,
                direction: 'center',
                className: 'tactical-tooltip',
                opacity: 0.9
              });
            }
          }
        }).addTo(map);
      })
      .catch(err => {
        // An abort is this component being unmounted, which is not a failure
        // and must not be reported as one — the boundary overlay failing to
        // load is a real condition worth logging, and burying it under noise
        // from every tab change is how a real one gets ignored.
        if (boundaries.signal.aborted) return;
        console.error('Failed to load boundaries:', err);
      });

    mapInstanceRef.current = { map, L: Leaflet };
    readySignal.set(true);

    return () => {
      alive = false;
      clearTimeout(resizeTimer);
      boundaries.abort();
      readySignal.set(false);
      if (mapInstanceRef.current) {
        // Stop any animation FIRST.
        //
        // Opening a popup near an edge starts an autoPan, which runs on
        // requestAnimationFrame. If the operator switches tab inside that
        // window — click a pin, look at the feed — React unmounts this
        // component while the pan is still stepping, and the next frame calls
        // `_onPanTransitionEnd`, which reads `map._mapPane.classList` on a map
        // that no longer has panes. An uncaught TypeError in the console HQ
        // watches, twice, every time.
        //
        // `stop()` and `closePopup()` are Leaflet's public API for exactly
        // this. The browser harness catches it; jsdom does not, because it
        // runs no animation frames.
        const dying = mapInstanceRef.current.map;
        dying.closePopup();
        // Detach the pan animation's listeners before the map goes.
        //
        // `_onPanTransitionEnd` does `removeClass(this._mapPane, …)` and
        // `map.remove()` deletes `_mapPane`, so a pan that completes after the
        // unmount throws `Cannot read properties of undefined (reading
        // 'classList')` from a requestAnimationFrame callback — uncaught, in
        // the console HQ watches, every time an operator clicks a pin near the
        // edge (which starts an autoPan) and then switches tab.
        //
        // Neither `map.stop()` nor `setView(…, {animate: false})` fixes it and
        // both make it worse: they end the animation by firing `moveend`,
        // which the popup listens to, and its `_adjustPan` starts a FRESH pan
        // on a map that is about to lose its panes. Dropping the listeners is
        // the only thing that cannot restart anything. The animation object is
        // discarded with the map a line later.
        if (dying._panAnim) dying._panAnim.off();
        dying.remove();
        mapInstanceRef.current = null;
      }
      markersRef.current = [];
      agentMarkersRef.current.clear();
      agentPolylinesRef.current.clear();
      tileLayerRef.current = null;
    };
  }, [leafletLoaded]);

  useEffect(() => {
    if (!mapReady || !mapInstanceRef.current) return;
    const { map, L } = mapInstanceRef.current;

    // Clear existing grid layers
    riskGridLayersRef.current.forEach(layer => layer.remove());
    riskGridLayersRef.current = [];

    if (!showRiskGrid) return;

    // Jos and Plateau core coordinate bounding box grid (step ~0.04 degrees)
    const minLat = 9.78;
    const maxLat = 10.06;
    const minLng = 8.78;
    const maxLng = 9.06;
    const step = 0.04;

    const layers: any[] = [];
    for (let lat = minLat; lat < maxLat; lat += step) {
      for (let lng = minLng; lng < maxLng; lng += step) {
        const cellAlerts = alerts.filter(a =>
          a.lat && a.lng &&
          a.lat >= lat && a.lat < lat + step &&
          a.lng >= lng && a.lng < lng + step &&
          a.status !== 'RESOLVED'
        );

        if (cellAlerts.length === 0) continue;

        let color = '#7E6112'; // Moderate
        let riskLabel = 'MODERATE RISK CELL';
        let opacity = 0.15;
        if (cellAlerts.length >= 4) {
          color = '#B3261E'; // Critical
          riskLabel = 'CRITICAL HOTSPOT CELL';
          opacity = 0.4;
        } else if (cellAlerts.length >= 2) {
          color = '#7E6112'; // Elevated
          riskLabel = 'ELEVATED RISK CELL';
          opacity = 0.28;
        }

        const bounds: [[number, number], [number, number]] = [[lat, lng], [lat + step, lng + step]];
        const rect = L.rectangle(bounds, {
          color: color,
          weight: 1.5,
          opacity: 0.6,
          fillColor: color,
          fillOpacity: opacity
        });

        rect.bindPopup(`
          <div style="font-family:var(--font-inter),sans-serif;padding:6px;min-width:165px;color:black;">
            <strong style="color:${color};font-size:11px;letter-spacing:1px;">${riskLabel}</strong>
            <hr style="border:0;border-top:1px solid #eee;margin:6px 0;"/>
            <div style="font-size:10px;color:#555;">
              <b>Incident Count:</b> ${cellAlerts.length}<br/>
              <b>Types:</b> ${cellAlerts.map(a => a.type || 'Distress').join(', ')}<br/>
              <b>Trend:</b> Spatial Hazard Hotspot
            </div>
          </div>
        `);

        rect.addTo(map);
        layers.push(rect);
      }
    }
    riskGridLayersRef.current = layers;
  }, [alerts, showRiskGrid, mapReady]);

  useEffect(() => {
    if (!mapInstanceRef.current) return;
    // Filter the pane; do NOT swap the provider. Swapping is what made the two
    // definitions diverge, and it also refetches every visible tile on a theme
    // toggle for no reason.
    //
    // `mapInstanceRef.current` is `{ map, L }`, not the map. Reaching for
    // `.getPane` on the wrapper threw "not a function" on every theme toggle —
    // inside an effect, so it took the render with it.
    const pane = mapInstanceRef.current.map.getPane('tilePane');
    if (pane) pane.style.filter = tileFilterFor(theme);
  }, [theme]);

  // Global action handlers for popup buttons
  // Popup buttons carry ONE alert id (they are HTML strings). A clustered
  // card stands for several reports, so the id is expanded to the whole
  // cluster before any action — otherwise resolving from the map closes one
  // report and hides the rest.
  const clusterOf = useCallback(
    (id: string): string | string[] => alerts.find(a => a.id === id)?.member_ids ?? id,
    [alerts],
  );

  // There were TWO effects installing these handlers, 200 lines apart, and they
  // disagreed: the first called `onEscalate(id, 'DISPATCH')` directly, the
  // second raised an `hq-show-dispatch` event for the page to catch. React runs
  // effects in order, so the second silently won and the first was dead code
  // that still owned the cleanup. One effect, installed once, cleaned up once.
  // See the block below `alertMarkersRef`.

  /**
 * The dossier for an approximate location, with the warning first.
 *
 * Prepended rather than appended: a dispatcher reads the top of a popup and acts.
 * "No GPS" discovered three rows down, after a coordinate-shaped circle has
 * already been believed, is not a warning.
 */
/**
 * The landmark is typed by a member of the public, into a field that lands in
 * innerHTML. Escaped here rather than trusted: incident-dossier.ts already runs
 * every reporter-supplied value through escapeHtml for exactly this reason, and a
 * banner that skipped it would be the one place a reporter could script the
 * dispatcher's console.
 */
function escapeForPopup(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function approximateDossier(html: string, alert: Alert, where: IncidentLocation): string {
  const note = where.precision === 'WARD'
    ? `NO GPS — approximate area only, about ${approxRadiusLabel(where.radiusM)} across.`
    : `NO GPS — only the LGA is known, about ${approxRadiusLabel(where.radiusM)} across.`;
  // The landmark goes in the SAME banner as the warning, not further down. It is
  // the answer to the question the warning raises — "then where is it?" — and a
  // dispatcher who reads "no GPS" and stops has missed the one navigable thing on
  // the card.
  const landmark = (alert as { reporter_landmark?: string | null }).reporter_landmark;
  const landmarkRow = landmark
    ? `<br>Nearest landmark: ${escapeForPopup(landmark)}`
    : '';
  return (
    '<div style="background:rgba(245,158,11,0.18);border:1px solid rgba(245,158,11,0.5);'
    + 'padding:6px 8px;border-radius:6px;margin-bottom:8px;font-size:10px;font-weight:800;'
    + 'color:#7E6112;line-height:1.35">'
    + note
    + landmarkRow
    + '<br>Do not dispatch to this circle as an address.'
    + '</div>'
    + html
  );
}

/**
 * Draw an incident whose position is only approximately known.
 *
 * A CIRCLE, never a pin, and the difference is deliberately impossible to miss:
 * a dashed edge, a translucent fill, and nothing at the centre. A dispatcher must
 * not be able to mistake this for a fix, because the difference is whether a
 * vehicle can be sent to it — an area tells a commander which unit owns the
 * incident, which is a different question from where to drive.
 *
 * Reuses the circle across refetches for the same reason the markers do: every
 * realtime event hands down a new array, and rebuilding an open popup makes the
 * card the operator is reading blink.
 */
function drawApproximateArea(
  alert: Alert,
  where: IncidentLocation,
  L: any,
  group: any,
  existing: Map<string, any>,
  drawnFrom: Map<string, string>,
  popupHtml: string,
) {
  const colour = statusColour(alert.status);
  const signature = `${where.lat},${where.lng},${where.radiusM},${colour}`;
  const already = existing.get(alert.id);

  if (already) {
    if (drawnFrom.get(alert.id) !== signature) {
      already.setLatLng([where.lat!, where.lng!]);
      already.setRadius(where.radiusM);
      already.setStyle({ color: colour, fillColor: colour });
    }
    const popup = already.getPopup();
    if (popup && popup.getContent() !== popupHtml) popup.setContent(popupHtml);
    drawnFrom.set(alert.id, signature);
    return;
  }

  const circle = L.circle([where.lat!, where.lng!], {
    radius: where.radiusM,
    color: colour,
    fillColor: colour,
    fillOpacity: 0.12,
    weight: 2,
    // The dashed edge IS the message: this boundary is not a boundary.
    dashArray: '6 6',
  });
  circle.bindPopup(popupHtml, {
    closeButton: true,
    autoClose: false,
    closeOnClick: false,
    maxWidth: 340,
    minWidth: 272,
  });
  group.addLayer(circle);
  existing.set(alert.id, circle);
  drawnFrom.set(alert.id, signature);
}

  const alertMarkersRef = useRef<Map<string, any>>(new Map());
  /** What each approximate AREA was last drawn from. Same purpose as
   *  markerDrawnFromRef: a redraw on unchanged inputs makes an open card blink. */
  const areaDrawnFromRef = useRef<Map<string, string>>(new Map());
  const clusterGroupRef = useRef<any>(null);

  /**
   * What each marker was last drawn FROM, so an unchanged marker is left alone.
   *
   * ## The blink
   *
   * Every realtime event refetches the board, and `fetchAlertsData` ends in an
   * unconditional `setAlerts(mapped)` — a brand-new array even when not one
   * field differs. So `alerts` changes identity two or three times a minute,
   * this effect re-runs, and it used to call `setLatLng`, `setIcon` and
   * `setContent` on every existing marker unconditionally.
   *
   * Both of the latter two are destructive:
   *
   *   * `Marker.setIcon` replaces the marker's DOM element via `_initIcon` and
   *     then RE-BINDS the popup — so an open dossier is torn down and put back.
   *   * `Popup.setContent` replaces the content node and re-runs the layout and
   *     position passes, which re-measures and nudges the card.
   *
   * Neither had anything to do: the icon HTML is a pure function of status and
   * acknowledgement, and the dossier HTML of the alert and the profile map. The
   * operator was watching a card be rebuilt from identical inputs, and it read
   * as a flicker on the one thing they were trying to read.
   *
   * So each marker remembers the three strings it was drawn from, and each
   * setter is called only when its own string changed. Position, icon and
   * content are tracked separately because a moving marker must still move
   * without its popup being rebuilt.
   */
  const markerDrawnFromRef = useRef<Map<string, { pos: string; icon: string; html: string }>>(
    new Map(),
  );

  useEffect(() => {
    if (!mapReady || !mapInstanceRef.current) return;
    const { map, L } = mapInstanceRef.current;

    // Ensure single cluster group instance
    if (!clusterGroupRef.current) {
      clusterGroupRef.current = typeof L.markerClusterGroup === 'function'
        ? L.markerClusterGroup({
            showCoverageOnHover: false,
            spiderfyOnMaxZoom: true,
            iconCreateFunction: (cluster: any) => {
              const count = cluster.getChildCount();
              return L.divIcon({
                html: `<div style="background:var(--primary);color:white;width:30px;height:30px;border-radius:50%;display:flex;align-items:center;justify-content:center;font-weight:900;border:3px solid white;box-shadow:0 0 15px var(--primary)">${count}</div>`,
                className: '',
                iconSize: [30, 30]
              });
            }
          })
        : L.layerGroup();

      map.addLayer(clusterGroupRef.current);
    }

    const clusterGroup = clusterGroupRef.current;
    const currentIds = new Set<string>();

    alerts.forEach(alert => {
      // Where this incident actually is, and how certain to look about it.
      //
      // This used to be `if (!Number.isFinite(alert.lat)) return;` — correct as
      // far as it went, because inventing coordinates is the C-5 defect this
      // codebase already fixed once. But it meant an incident with a WARD and no
      // GPS was drawn nowhere at all, and USSD reports never have GPS: USSD
      // rides the signalling channel and cannot read the handset's location. A
      // USSD emergency appeared in the incident list and nowhere on the map the
      // operator is watching.
      //
      // So an approximate position is now drawn AS approximate — a circle the
      // size of the ward, with a dashed edge and NO PIN at its centre — and
      // only a real fix gets a marker. See lib/incident-locate.ts.
      const where = locateIncident(alert as never);
      if (where.precision === 'NONE') return;
      currentIds.add(alert.id);

      const isDuress = alert.status === 'DURESS';
      // Status colours now come from the shared module, which — unlike the map
      // table that used to live here — has an entry for PENDING, the status
      // every report arrives with, and for CANCELLED. Both fell through to the
      // same orange as an open incident.
      const color = statusColour(alert.status);

      // An incident nobody has acknowledged pulses. That is the thing an
      // operator scanning the map needs to see without clicking: the tier timer
      // is running on it, and it will climb to WARD and then LGA on its own.
      const unclaimed = isUnacknowledged(alert);
      const size = isDuress ? 44 : unclaimed ? 34 : 30;
      const pulse = isDuress
        ? 'animation:pulse-ring 1.5s infinite;'
        : unclaimed
          ? 'animation:pulse-ring 2.4s infinite;'
          : '';

      const icon = L.divIcon({
        className: '',
        html: `<div style="width:${size}px;height:${size}px;background:${color}99;border-radius:50%;border:3px solid white;display:flex;align-items:center;justify-content:center;${pulse}"><div style="width:${size * 0.45}px;height:${size * 0.45}px;background:${color};border-radius:50%;"></div></div>`,
        iconSize: [size, size],
        iconAnchor: [size / 2, size / 2],
      });

      // The whole dossier, built in one tested place. See
      // src/lib/incident-dossier.ts for what is shown and why every value goes
      // through escapeHtml on the way in.
      const popupContent = incidentPopupHtml(alert, {
        reporter: resolveReporterDetails(alert, usersMap),
        usersMap,
      });

      // Only a real fix gets a pin. Everything else is an area, and the branch
      // sits here rather than earlier so both paths carry the SAME dossier —
      // an operator clicking a circle must get the same detail as one clicking a
      // marker, or the approximate incidents become second-class on the screen
      // that decides who gets help.
      if (where.precision !== 'GPS') {
        drawApproximateArea(
          alert, where, L, clusterGroup,
          alertMarkersRef.current, areaDrawnFromRef.current,
          approximateDossier(popupContent, alert, where),
        );
        return;
      }

      const existingMarker = alertMarkersRef.current.get(alert.id);
      // The three things this marker is drawn from. Compared as strings rather
      // than rebuilt objects, because that is what changing actually means
      // here: `icon` is a fresh L.divIcon on every pass and would never be ===.
      const pos = `${alert.lat},${alert.lng}`;
      const iconSig = `${size}|${color}|${pulse}`;
      if (existingMarker) {
        const was = markerDrawnFromRef.current.get(alert.id);
        if (was?.pos !== pos) existingMarker.setLatLng([alert.lat!, alert.lng!]);
        // Guarded because setIcon re-binds the popup: calling it with an
        // identical icon closed and rebuilt the dossier the operator was
        // reading. See the note on markerDrawnFromRef.
        if (was?.icon !== iconSig) existingMarker.setIcon(icon);
        if (was?.html !== popupContent && existingMarker.getPopup()) {
          existingMarker.getPopup().setContent(popupContent);
        }
      } else {
        const marker = L.marker([alert.lat!, alert.lng!], { icon });
        marker.bindPopup(popupContent, {
          closeButton: true,
          autoClose: false,
          closeOnClick: false,
          // The card is a dossier now, not a label. Leaflet's 300px default
          // clipped the detail rows.
          maxWidth: 340,
          minWidth: 272,
        });
        clusterGroup.addLayer(marker);
        alertMarkersRef.current.set(alert.id, marker);
      }
      markerDrawnFromRef.current.set(alert.id, { pos, icon: iconSig, html: popupContent });
    });

    // Remove old markers that no longer exist
    alertMarkersRef.current.forEach((marker, id) => {
      if (!currentIds.has(id)) {
        clusterGroup.removeLayer(marker);
        alertMarkersRef.current.delete(id);
        markerDrawnFromRef.current.delete(id);
        areaDrawnFromRef.current.delete(id);
      }
    });
    // `usersMap` belongs here. Profiles load in their OWN effect, which
    // resolves AFTER the first alerts arrive, so a popup built without this
    // dependency would be built once — before any profile existed — and every
    // reporter would read "profile not loaded" for the life of the session
    // even though the name was sitting in state.
    //
    // `theme` does NOT belong here any more: the card takes its surface
    // colours from CSS variables, so a theme toggle restyles the popup that is
    // already open without rebuilding anything.
  }, [alerts, mapReady, usersMap]);

  // The stored route of the incident under inspection.
  //
  // Drawn in its own pane-level layer rather than among the agent trails: an
  // agent trail is where somebody IS GOING, redrawn as they move, and this is
  // where somebody WENT. Giving them the same treatment would let an operator
  // read a finished route as a live one.
  const incidentTrackRef = useRef<any>(null);
  useEffect(() => {
    if (!mapReady || !mapInstanceRef.current) return;
    const { map, L } = mapInstanceRef.current;

    if (incidentTrackRef.current) {
      incidentTrackRef.current.remove();
      incidentTrackRef.current = null;
    }
    // Two points is the minimum for a line. One position is not a route, and
    // drawing it as a dot on top of the incident marker says nothing.
    if (!incidentTrack || incidentTrack.length < 2) return;

    const latlngs = incidentTrack.map((p) => [p.lat, p.lng]);
    const line = L.polyline(latlngs, {
      color: '#0B234B',
      weight: 4,
      opacity: 0.9,
      lineCap: 'round',
      lineJoin: 'round',
    }).addTo(map);

    // Where it started and where it ended. Without these an operator has a
    // line and no idea which end is which.
    const start = L.circleMarker(latlngs[0], {
      radius: 6,
      color: '#ffffff',
      weight: 2,
      fillColor: '#0B234B',
      fillOpacity: 1,
    }).bindTooltip('Route start', { direction: 'top' });
    const end = L.circleMarker(latlngs[latlngs.length - 1], {
      radius: 7,
      color: '#ffffff',
      weight: 2,
      fillColor: '#B3261E',
      fillOpacity: 1,
    }).bindTooltip('Last known position', { direction: 'top' });

    const group = L.layerGroup([line, start, end]).addTo(map);
    incidentTrackRef.current = group;

    return () => {
      group.remove();
      if (incidentTrackRef.current === group) incidentTrackRef.current = null;
    };
  }, [incidentTrack, mapReady]);

  useEffect(() => {
    if (!mapInstanceRef.current) return;
    const { map, L } = mapInstanceRef.current;

    agents.forEach(agent => {
      if (!agent.lat || !agent.lng) return;

      const existing = agentMarkersRef.current.get(agent.user_id);
      const isDuress = agent.status === 'DURESS' || agent.status === 'EMERGENCY' || agent.mode === 'sos';
      const isOutOfBounds = agent.geo_integrity === 'OUT_OF_BOUNDS';
      const isCitizenSos = agent.mode === 'sos' || agent.status === 'EMERGENCY' || isDuress;
      
      const color = isDuress || isOutOfBounds ? 'var(--duress)' : agent.status === 'BUSY' ? '#7E6112' : '#0F6C32';
      const anim = isDuress || isOutOfBounds ? 'animation:pulse-ring 1.2s infinite;' : '';

      // 1. Draw pulsing target-radar icon for Citizen Distress signals
      let html = `<div style="width:24px;height:24px;background:${color};border-radius:50%;border:3px solid white;box-shadow:0 2px 8px rgba(0,0,0,0.4);display:flex;align-items:center;justify-content:center;${anim}"><div style="width:8px;height:8px;background:white;border-radius:50%;"></div></div>`;
      if (isCitizenSos) {
        html = `
          <div style="width:36px;height:36px;background:rgba(239, 68, 68, 0.15);border-radius:50%;border:2.5px dashed rgba(239, 68, 68, 0.65);display:flex;align-items:center;justify-content:center;animation:spin-radar 10s linear infinite;">
            <div style="width:24px;height:24px;background:rgb(239, 68, 68);border-radius:50%;border:2px solid white;box-shadow:0 0 15px rgb(239, 68, 68);display:flex;align-items:center;justify-content:center;animation:pulse-ring 1.2s infinite;">
              <div style="width:8px;height:8px;background:white;border-radius:50%;"></div>
            </div>
          </div>
        `;
      }

      const iconSize = isCitizenSos ? 36 : 24;
      const icon = L.divIcon({
        className: '',
        html: html,
        iconSize: [iconSize, iconSize],
        iconAnchor: [iconSize / 2, iconSize / 2],
      });

      if (existing) {
        existing.setLatLng([agent.lat, agent.lng]);
        existing.setIcon(icon);
      } else {
        const marker = L.marker([agent.lat, agent.lng], { icon, zIndexOffset: 1000 }).addTo(map);
        marker.bindPopup(`
          <div style="font-family:var(--font-inter),sans-serif;padding:4px">
            <strong style="color:${color};font-size:12px">${agent.displayName || 'FIELD AGENT'}</strong>
            <p style="font-size:10px;color:#555;margin:4px 0 0">STATUS: ${agent.status || 'ONLINE'}</p>
            ${isOutOfBounds ? '<p style="font-size:10px;color:var(--duress);font-weight:900;margin:4px 0 0">🚨 OUT OF PLATEAU BOUNDS</p>' : ''}
            <p style="font-size:9px;color:#888;margin:6px 0 0">BATTERY: ${agent.telemetry?.battery ?? '??'}% | NET: ${agent.telemetry?.network?.split('.')?.pop() ?? 'LIVE'}</p>
          </div>
        `);
        agentMarkersRef.current.set(agent.user_id, marker);
      }

      // 2. Draw Live distress/movement trails
      if (agent.path && agent.path.length >= 2) {
        const latlngs = agent.path.map((pt: any) => [pt.lat, pt.lng]);
        const existingPolyline = agentPolylinesRef.current.get(agent.user_id);
        if (existingPolyline) {
          existingPolyline.setLatLngs(latlngs);
        } else {
          const polyline = L.polyline(latlngs, {
            color: isDuress ? '#B3261E' : '#0B234B',
            weight: 3.5,
            opacity: 0.8,
            dashArray: '5, 8',
            lineCap: 'round',
            lineJoin: 'round'
          }).addTo(map);
          agentPolylinesRef.current.set(agent.user_id, polyline);
        }
      }
    });

    const currentIds = new Set(agents.map(a => a.user_id));
    agentMarkersRef.current.forEach((marker, id) => {
      if (!currentIds.has(id)) {
        marker.remove();
        agentMarkersRef.current.delete(id);
        
        const polyline = agentPolylinesRef.current.get(id);
        if (polyline) {
          polyline.remove();
          agentPolylinesRef.current.delete(id);
        }
      }
    });
  }, [agents]);

  // ONE REAL LISTENER, AND NO GLOBALS.
  //
  // The popup is an HTML string, so its buttons used to reach code through
  // `onclick="window._hqDossier('…')"` and four `window._hq*` functions
  // installed by this effect. Every one of those clicks was REFUSED by the
  // console's own Content Security Policy:
  //
  //   Refused to execute inline event handler because it violates the
  //   following Content Security Policy directive: "script-src …"
  //
  // `lib/csp.ts` sets `script-src 'self' 'nonce-…' 'strict-dynamic'` with no
  // `'unsafe-inline'`, deliberately and for good reasons it writes out at
  // length — and a nonce cannot apply to an inline event handler attribute.
  // So DOSSIER, DISPATCH and RESOLVE were dead in every map popup, on the
  // console's landing screen, from the day that policy shipped. Nothing
  // noticed: the browser sweep pressed them and recorded "nothing", which is
  // not a failing check, and the CSP's own test asserts the header rather than
  // what the header does to the page.
  //
  // Delegation fixes it without `'unsafe-inline'`: the buttons carry
  // `data-hq-action` and `data-hq-id` (see `incidentPopupHtml`), and this
  // listener reads them. It also disposes of the globals, which this comment
  // used to apologise for.
  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;

    const onPopupClick = (event: Event) => {
      const target = event.target as HTMLElement | null;
      const button = target?.closest?.('[data-hq-action]') as HTMLElement | null;
      if (!button) return;
      const action = button.getAttribute('data-hq-action');
      const id = button.getAttribute('data-hq-id');
      if (!action || !id) return;
      // The popup sits over the map; a click that has been handled must not
      // also pan it.
      event.preventDefault();
      event.stopPropagation();

      void (async () => {
        try {
          switch (action) {
            case 'resolve':
              await onResolve(clusterOf(id));
              break;
            case 'escalate':
              // The tier comes from the incident, not from the markup. The
              // global this replaces took it as a second argument and NOTHING
              // ever called it — so the only caller this branch has ever had
              // would have been handing it a string invented at the call site.
              await onEscalate(
                clusterOf(id),
                alerts.find((a) => a.id === id)?.assigned_tier ?? 'UNIT',
              );
              break;
            case 'dispatch':
              window.dispatchEvent(
                new CustomEvent('hq-show-dispatch', { detail: { alertId: id } }),
              );
              break;
            case 'dossier':
              // NOT expanded to the cluster: a dossier is about one report,
              // and the popup's own id is the cluster master. The write paths
              // expand; reading does not.
              if (typeof onOpenDossier === 'function') {
                onOpenDossier(id);
              } else {
                window.dispatchEvent(
                  new CustomEvent('hq-open-dossier', { detail: { alertId: id } }),
                );
              }
              break;
            default:
              // An action this build does not know about. Said, rather than
              // ignored: a popup button that silently does nothing is the
              // defect this whole change exists to fix.
              console.error('[LIVE_MAP] unknown popup action:', action);
          }
        } catch (e: any) {
          window.alert(`${action} failed: ${e?.message ?? e}`);
        }
      })();
    };

    // On the container, not on each popup: Leaflet creates and destroys popup
    // DOM as markers open and close, so a listener attached to a popup dies
    // with it — which is how this would quietly stop working again.
    map.addEventListener('click', onPopupClick);
    return () => map.removeEventListener('click', onPopupClick);
  }, [alerts, onResolve, onEscalate, onOpenDossier, clusterOf]);

  return (
    <div style={{ position: 'relative', height: '100%', width: '100%' }}>
      <style>{`
        @keyframes pulse-ring {
          0% { box-shadow: 0 0 0 0 rgba(239,68,68,0.7); }
          70% { box-shadow: 0 0 0 15px rgba(239,68,68,0); }
          100% { box-shadow: 0 0 0 0 rgba(239,68,68,0); }
        }
        @keyframes spin-radar {
          from { transform: rotate(0deg); }
          to { transform: rotate(360deg); }
        }
        .leaflet-container { background: var(--bg-primary); }

        /* The incident card's SURFACE is styled once, in globals.css, from the
           shared tokens: the rule for .leaflet-popup-content-wrapper there
           already takes --bg-secondary, --text-primary and --border, which are
           the app's palette. Restyling it here with its own hexes is how the
           console ended up with two greys for the same object. Only the
           spacing the dossier layout needs belongs to this component.
           (No backticks in this comment — it lives inside a template literal,
           and one would end the stylesheet here.) */
        .hq-map .leaflet-popup-content { margin: 12px 14px; line-height: 1.35; }
        .hq-map .leaflet-popup-tip {
          background: var(--bg-secondary);
          border: 1px solid var(--border);
        }
        .hq-map .leaflet-popup-close-button { color: var(--text-dim) !important; }
        .tactical-tooltip {
          background: transparent !important;
          border: none !important;
          box-shadow: none !important;
          color: var(--text-dim) !important;
          font-size: 10px !important;
          font-family: var(--font-inter), sans-serif !important;
          letter-spacing: 2px !important;
          pointer-events: none !important;
        }
      `}</style>
      <div
        ref={mapRef}
        className="hq-map"
        style={{ height: '100%', width: '100%' }}
      />

      {/* Strategic Forecasting Dashboard Overlay.
          Anchored bottom-LEFT, not top-right: the situational feed already
          occupies the top-right of the map at a greater width, so both panels
          landed on top of each other and the HUD clipped the text of the first
          incident card. Bottom-left is the one corner nothing else claims —
          filters sit top-left, zoom and attribution bottom-right. */}
      <div style={{
        display: isNarrow ? 'none' : 'block',
        position: 'absolute',
        bottom: '32px',
        left: '20px',
        zIndex: 1000,
        background: theme === 'dark' ? 'rgba(17, 23, 38, 0.95)' : 'rgba(255, 255, 255, 0.98)',
        border: theme === 'dark' ? '1px solid rgba(255, 255, 255, 0.1)' : '1px solid rgba(148, 163, 184, 0.35)',
        borderRadius: '16px',
        padding: '16px',
        width: '240px',
        boxShadow: 'var(--shadow-md)',
        backdropFilter: 'blur(8px)',
        WebkitBackdropFilter: 'blur(8px)'
      }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '12px' }}>
          <span style={{ fontSize: '11px', fontWeight: 900, letterSpacing: '1.5px', color: theme === 'dark' ? '#F7F7F7' : '#1A1A1A' }}>
            FORECASTING HUD
          </span>
          <button
            onClick={() => setShowRiskGrid(!showRiskGrid)}
            style={{
              background: showRiskGrid ? 'var(--duress, #B3261E)' : (theme === 'dark' ? 'rgba(255, 255, 255, 0.08)' : 'rgba(0, 0, 0, 0.08)'),
              color: showRiskGrid ? 'white' : (theme === 'dark' ? '#E0E0E0' : '#616161'),
              border: 'none',
              borderRadius: '8px',
              padding: '4px 8px',
              fontSize: '9px',
              fontWeight: 800,
              cursor: 'pointer',
              letterSpacing: '1px'
            }}
          >
            {showRiskGrid ? 'GRID: ON' : 'GRID: OFF'}
          </button>
        </div>

        {showRiskGrid && (
          <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
            <div style={{ fontSize: '9px', color: theme === 'dark' ? '#757575' : '#616161', marginBottom: '4px' }}>
              SPATIAL-TEMPORAL RISK DENSITY:
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
              <div style={{ width: '12px', height: '12px', background: '#B3261E', borderRadius: '3px', opacity: 0.8 }} />
              <span style={{ fontSize: '10px', color: theme === 'dark' ? '#E0E0E0' : '#212121', fontWeight: 600 }}>Critical Hotspot (4+ alerts)</span>
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
              <div style={{ width: '12px', height: '12px', background: '#7E6112', borderRadius: '3px', opacity: 0.8 }} />
              <span style={{ fontSize: '10px', color: theme === 'dark' ? '#E0E0E0' : '#212121', fontWeight: 600 }}>Elevated Risk (2-3 alerts)</span>
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
              <div style={{ width: '12px', height: '12px', background: '#7E6112', borderRadius: '3px', opacity: 0.8 }} />
              <span style={{ fontSize: '10px', color: theme === 'dark' ? '#E0E0E0' : '#212121', fontWeight: 600 }}>Moderate Risk (1 alert)</span>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
