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
  theme?: 'light' | 'dark';
}

export default function LiveMap({
  alerts,
  agents = [],
  onResolve,
  onEscalate,
  usersMap = {},
  onOpenDossier,
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

    // Force map to adjust size to container after render
    setTimeout(() => {
      map.invalidateSize();
    }, 250);

    // Fetch and draw Geo-Boundaries
    fetch('/plateau_boundaries.json')
      .then(res => res.json())
      .then(data => {
        Leaflet.geoJSON(data, {
          style: {
            color: 'var(--duress)',
            weight: 1.5,
            opacity: 0.8,
            fillColor: 'var(--duress)',
            fillOpacity: 0.05,
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
      .catch(err => console.error('Failed to load boundaries:', err));

    mapInstanceRef.current = { map, L: Leaflet };
    readySignal.set(true);

    return () => {
      readySignal.set(false);
      if (mapInstanceRef.current) {
        mapInstanceRef.current.map.remove();
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

        let color = '#FFC107'; // Moderate
        let riskLabel = 'MODERATE RISK CELL';
        let opacity = 0.15;
        if (cellAlerts.length >= 4) {
          color = '#F44336'; // Critical
          riskLabel = 'CRITICAL HOTSPOT CELL';
          opacity = 0.4;
        } else if (cellAlerts.length >= 2) {
          color = '#FF9800'; // Elevated
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

  const alertMarkersRef = useRef<Map<string, any>>(new Map());
  const clusterGroupRef = useRef<any>(null);

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
                html: `<div style="background:var(--duress);color:white;width:30px;height:30px;border-radius:50%;display:flex;align-items:center;justify-content:center;font-weight:900;border:3px solid white;box-shadow:0 0 15px var(--duress)">${count}</div>`,
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
      // `!alert.lat` also rejects 0. That is a coordinate — in the Gulf of
      // Guinea, so never a real Plateau fix — but a falsy check on a number is
      // the habit that produces C-5-shaped bugs, so this asks the question it
      // means: is there a usable fix?
      if (!Number.isFinite(alert.lat) || !Number.isFinite(alert.lng)) return;
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
        theme,
      });

      const existingMarker = alertMarkersRef.current.get(alert.id);
      if (existingMarker) {
        existingMarker.setLatLng([alert.lat!, alert.lng!]);
        existingMarker.setIcon(icon);
        if (existingMarker.getPopup()) {
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
    });

    // Remove old markers that no longer exist
    alertMarkersRef.current.forEach((marker, id) => {
      if (!currentIds.has(id)) {
        clusterGroup.removeLayer(marker);
        alertMarkersRef.current.delete(id);
      }
    });
    // `usersMap` and `theme` belong here. Profiles load in their OWN effect,
    // which resolves AFTER the first alerts arrive, so a popup built without
    // this dependency would be built once — before any profile existed — and
    // every reporter would read "profile not loaded" for the life of the
    // session even though the name was sitting in state.
  }, [alerts, mapReady, usersMap, theme]);

  useEffect(() => {
    if (!mapInstanceRef.current) return;
    const { map, L } = mapInstanceRef.current;

    agents.forEach(agent => {
      if (!agent.lat || !agent.lng) return;

      const existing = agentMarkersRef.current.get(agent.user_id);
      const isDuress = agent.status === 'DURESS' || agent.status === 'EMERGENCY' || agent.mode === 'sos';
      const isOutOfBounds = agent.geo_integrity === 'OUT_OF_BOUNDS';
      const isCitizenSos = agent.mode === 'sos' || agent.status === 'EMERGENCY' || isDuress;
      
      const color = isDuress || isOutOfBounds ? 'var(--duress)' : agent.status === 'BUSY' ? '#FFC107' : '#4CAF50';
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
            color: isDuress ? '#EF4444' : '#3B82F6',
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

  // The popup is an HTML string, so its buttons can only reach code through
  // globals. One effect installs all four and removes all four: the previous
  // arrangement had two effects fighting over two of these names, and the
  // cleanup belonged to the one that lost.
  useEffect(() => {
    (window as any)._hqResolve = async (id: string) => {
      try {
        await onResolve(clusterOf(id));
      } catch (e: any) {
        window.alert('Resolution failed: ' + e.message);
      }
    };
    (window as any)._hqEscalate = async (id: string, currentTier: string) => {
      try {
        await onEscalate(clusterOf(id), currentTier);
      } catch (e: any) {
        window.alert('Escalation failed: ' + e.message);
      }
    };
    (window as any)._hqShowDispatch = (id: string) => {
      const event = new CustomEvent('hq-show-dispatch', { detail: { alertId: id } });
      window.dispatchEvent(event);
    };
    // The popup holds the fields a dispatcher acts on; the dossier holds the
    // rest — the escalation log, the media, the chat, the feedback. The button
    // exists so nobody has to leave the map, find the same incident in the list
    // and open it there, which is what the map's thin popup used to force.
    //
    // NOT expanded to the cluster: a dossier is about one report, and the
    // popup's own id is the cluster master. The write paths expand; reading
    // does not.
    (window as any)._hqDossier = (id: string) => {
      if (typeof onOpenDossier === 'function') {
        onOpenDossier(id);
        return;
      }
      window.dispatchEvent(new CustomEvent('hq-open-dossier', { detail: { alertId: id } }));
    };

    return () => {
      delete (window as any)._hqResolve;
      delete (window as any)._hqEscalate;
      delete (window as any)._hqShowDispatch;
      delete (window as any)._hqDossier;
    };
  }, [onResolve, onEscalate, onOpenDossier, clusterOf]);

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

        /* The incident card. Leaflet's default popup is a white bubble with a
           white tip, which on the dark console looked like a browser dialog
           that had landed on the map. The class goes on the map CONTAINER, not
           on each popup, so a theme toggle restyles popups that are already
           open — a per-popup class is fixed at bindPopup time and would leave
           whatever the operator had open in the previous theme. */
        .hq-map .leaflet-popup-content-wrapper {
          border-radius: 14px;
          box-shadow: 0 18px 44px rgba(2, 6, 23, 0.32);
          padding: 2px;
        }
        .hq-map .leaflet-popup-content { margin: 12px 14px; line-height: 1.35; }
        .hq-map-dark .leaflet-popup-content-wrapper,
        .hq-map-dark .leaflet-popup-tip {
          background: #111726;
          border: 1px solid rgba(255, 255, 255, 0.12);
          color: #e2e8f0;
        }
        .hq-map-dark .leaflet-popup-close-button { color: #94a3b8 !important; }
        .hq-map-dark .leaflet-popup-tip { border-top: none; border-left: none; }
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
        className={theme === 'dark' ? 'hq-map hq-map-dark' : 'hq-map'}
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
          <span style={{ fontSize: '11px', fontWeight: 900, letterSpacing: '1.5px', color: theme === 'dark' ? '#f8fafc' : '#0f172a' }}>
            FORECASTING HUD
          </span>
          <button
            onClick={() => setShowRiskGrid(!showRiskGrid)}
            style={{
              background: showRiskGrid ? 'var(--duress, #ff4d4d)' : (theme === 'dark' ? 'rgba(255, 255, 255, 0.08)' : 'rgba(0, 0, 0, 0.08)'),
              color: showRiskGrid ? 'white' : (theme === 'dark' ? '#cbd5e1' : '#475569'),
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
            <div style={{ fontSize: '9px', color: theme === 'dark' ? '#94a3b8' : '#64748b', marginBottom: '4px' }}>
              SPATIAL-TEMPORAL RISK DENSITY:
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
              <div style={{ width: '12px', height: '12px', background: '#F44336', borderRadius: '3px', opacity: 0.8 }} />
              <span style={{ fontSize: '10px', color: theme === 'dark' ? '#e2e8f0' : '#334155', fontWeight: 600 }}>Critical Hotspot (4+ alerts)</span>
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
              <div style={{ width: '12px', height: '12px', background: '#FF9800', borderRadius: '3px', opacity: 0.8 }} />
              <span style={{ fontSize: '10px', color: theme === 'dark' ? '#e2e8f0' : '#334155', fontWeight: 600 }}>Elevated Risk (2-3 alerts)</span>
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
              <div style={{ width: '12px', height: '12px', background: '#FFC107', borderRadius: '3px', opacity: 0.8 }} />
              <span style={{ fontSize: '10px', color: theme === 'dark' ? '#e2e8f0' : '#334155', fontWeight: 600 }}>Moderate Risk (1 alert)</span>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
