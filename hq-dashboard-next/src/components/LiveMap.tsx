'use client';
import { useEffect, useRef, useState } from 'react';

interface Alert {
  id: string;
  type?: string;
  status: string;
  priority?: string;
  lat?: number;
  lng?: number;
  assigned_to?: string;
  reportedBy?: string;
  description?: string;
  isCritical?: boolean;
  reportedAt?: { seconds: number };
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
  onResolve: (id: string) => void;
  onEscalate: (id: string, tier: string) => void;
  theme?: 'light' | 'dark';
}

export default function LiveMap({ alerts, agents = [], onResolve, onEscalate, theme = 'light' }: Props) {
  const mapRef = useRef<HTMLDivElement>(null);
  const mapInstanceRef = useRef<any>(null);
  const markersRef = useRef<any[]>([]);
  const agentMarkersRef = useRef<Map<string, any>>(new Map());
  const agentPolylinesRef = useRef<Map<string, any>>(new Map());
  const tileLayerRef = useRef<any>(null);

  const [mapReady, setMapReady] = useState(false);
  const [showRiskGrid, setShowRiskGrid] = useState(true);
  const riskGridLayersRef = useRef<any[]>([]);
  const [leafletLoaded, setLeafletLoaded] = useState(false);

  // Plateau State Tactical Bounds
  const plateauBounds: [[number, number], [number, number]] = [[8.30, 8.30], [10.50, 10.80]];

  // Dynamic script loader for Leaflet & MarkerCluster (prevents React JSX script tag warnings)
  useEffect(() => {
    let isMounted = true;

    const isReady = () => {
      const L = (window as any).L;
      return L && typeof L.markerClusterGroup === 'function';
    };

    if (isReady()) {
      setLeafletLoaded(true);
      return;
    }

    const loadScript = (src: string) => new Promise<void>((resolve, reject) => {
      const existing = document.querySelector(`script[src="${src}"]`);
      if (existing) {
        resolve();
        return;
      }
      const s = document.createElement('script');
      s.src = src;
      s.onload = () => resolve();
      s.onerror = reject;
      document.head.appendChild(s);
    });

    const initScripts = async () => {
      try {
        if (!(window as any).L) {
          await loadScript('https://unpkg.com/leaflet@1.9.4/dist/leaflet.js');
        }
        if (typeof (window as any).L?.markerClusterGroup !== 'function') {
          await loadScript('https://unpkg.com/leaflet.markercluster@1.4.1/dist/leaflet.markercluster.js');
        }
        if (isMounted && isReady()) {
          setLeafletLoaded(true);
        }
      } catch (err) {
        console.error('Failed to load Leaflet scripts:', err);
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
      minZoom: 8,
      maxBounds: Leaflet.latLngBounds(plateauBounds[0], plateauBounds[1]),
      zoomControl: false,
    });

    Leaflet.control.zoom({ position: 'bottomright' }).addTo(map);

    const tileUrl = theme === 'dark'
      ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
      : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png';

    const tileLayer = Leaflet.tileLayer(tileUrl, { attribution: '© CARTO' }).addTo(map);
    tileLayerRef.current = tileLayer;

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
    setMapReady(true);

    return () => {
      setMapReady(false);
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
          <div style="font-family:Inter,sans-serif;padding:6px;min-width:165px;color:black;">
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
    if (!mapInstanceRef.current || !tileLayerRef.current) return;
    const tileUrl = theme === 'dark'
      ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
      : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png';
    tileLayerRef.current.setUrl(tileUrl);
  }, [theme]);

  useEffect(() => {
    if (!mapInstanceRef.current) return;
    const { map, L } = mapInstanceRef.current;

    markersRef.current.forEach(m => m.remove());
    markersRef.current = [];

    const incidentCluster = L.markerClusterGroup({
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
    });

    alerts.forEach(alert => {
      if (!alert.lat || !alert.lng) return;
      const isDuress = alert.status === 'DURESS';
      const statusColors: any = {
        'OPEN': '#FF9800', 'ACTIVE': '#FF9800', 'DISPATCHED': '#2196F3', 'ACKNOWLEDGED': '#4CAF50',
        'ON_ROUTE': '#E91E63', 'ON_SITE': '#00BCD4', 'RESOLVED': '#8BC34A', 'DURESS': 'var(--duress)'
      };

      const color = statusColors[alert.status] || '#FF9800';
      const size = isDuress ? 48 : 32;

      const icon = L.divIcon({
        className: '',
        html: `<div style="width:${size}px;height:${size}px;background:${color}99;border-radius:50%;border:3px solid white;display:flex;align-items:center;justify-content:center;${isDuress ? 'animation:pulse-ring 1.5s infinite;' : ''}"><div style="width:${size * 0.45}px;height:${size * 0.45}px;background:${color};border-radius:50%;"></div></div>`,
        iconSize: [size, size],
        iconAnchor: [size / 2, size / 2],
      });

      const marker = L.marker([alert.lat, alert.lng], { icon });
      marker.bindPopup(`
        <div style="font-family:Inter,sans-serif;min-width:200px;padding:4px;color:var(--text-primary)">
          <strong style="color:${color};font-size:14px">${alert.type || 'EMERGENCY'}</strong>
          <div style="margin:4px 0; font-size:10px; font-weight:800; color:var(--text-muted)">STATUS: ${alert.status}</div>
          <p style="font-size:11px;color:var(--text-secondary);margin:8px 0">${alert.description || 'No details'}</p>
          <div style="display:flex;gap:6px;margin-top:12px">
            <button onclick="window._hqResolve('${alert.id}')" style="flex:1;padding:8px;background:#4CAF50;color:white;border:none;border-radius:4px;font-size:10px;font-weight:800;cursor:pointer">RESOLVE</button>
            ${(alert.status === 'OPEN' || alert.status === 'ACTIVE') ? `<button onclick="window._hqShowDispatch('${alert.id}')" style="flex:1;padding:8px;background:var(--primary);color:white;border:none;border-radius:4px;font-size:10px;font-weight:800;cursor:pointer">DISPATCH</button>` : ''}
          </div>
        </div>
      `);
      incidentCluster.addLayer(marker);
    });

    map.addLayer(incidentCluster);
    markersRef.current.push(incidentCluster);
  }, [alerts]);

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
          <div style="font-family:Inter,sans-serif;padding:4px">
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

  useEffect(() => {
    (window as any)._hqResolve = async (id: string) => {
      try {
        await onResolve(id);
      } catch (e: any) {
        window.alert("Resolution failed: " + e.message);
      }
    };
    (window as any)._hqEscalate = async (id: string, currentTier: string) => {
      try {
        await onEscalate(id, currentTier);
      } catch (e: any) {
        window.alert("Escalation failed: " + e.message);
      }
    };
    (window as any)._hqShowDispatch = (id: string) => {
       const event = new CustomEvent('hq-show-dispatch', { detail: { alertId: id } });
       window.dispatchEvent(event);
    };
  }, [onResolve, onEscalate]);

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
        .tactical-tooltip {
          background: transparent !important;
          border: none !important;
          box-shadow: none !important;
          color: var(--text-dim) !important;
          font-size: 10px !important;
          font-family: 'Inter', sans-serif !important;
          letter-spacing: 2px !important;
          pointer-events: none !important;
        }
      `}</style>
      <div ref={mapRef} style={{ height: '100%', width: '100%' }} />

      {/* Strategic Forecasting Dashboard Overlay */}
      <div style={{
        position: 'absolute',
        top: '20px',
        right: '20px',
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
