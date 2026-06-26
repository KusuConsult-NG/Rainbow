'use client';
import { useEffect, useRef } from 'react';

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

  // Plateau State Tactical Bounds
  const plateauBounds: [[number, number], [number, number]] = [[8.30, 8.30], [10.50, 10.80]];

  useEffect(() => {
    if (!mapRef.current || mapInstanceRef.current) return;

    const Leaflet = (window as any).L;
    if (!Leaflet) {
      console.warn('[HQ_MAP] Leaflet is not loaded on window.');
      return;
    }

    const map = Leaflet.map(mapRef.current!, {
      center: [9.9167, 8.8917],
      zoom: 9,
      minZoom: 8,
      maxBounds: Leaflet.latLngBounds(plateauBounds[0], plateauBounds[1]),
      zoomControl: false,
    });

    Leaflet.control.zoom({ position: 'bottomright' }).addTo(map);

    const tileUrl = theme === 'dark'
      ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
      : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png';

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

    return () => {
      if (mapInstanceRef.current) {
        mapInstanceRef.current.map.remove();
        mapInstanceRef.current = null;
      }
      markersRef.current = [];
      agentMarkersRef.current.clear();
      agentPolylinesRef.current.clear();
      tileLayerRef.current = null;
    };
  }, []);

  useEffect(() => {
    if (!mapInstanceRef.current || !tileLayerRef.current) return;
    const tileUrl = theme === 'dark'
      ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
      : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png';
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
      const isDuress = agent.status === 'DURESS';
      const isOutOfBounds = agent.geo_integrity === 'OUT_OF_BOUNDS';
      
      const color = isDuress || isOutOfBounds ? 'var(--duress)' : agent.status === 'BUSY' ? '#FFC107' : '#4CAF50';
      const anim = isDuress || isOutOfBounds ? 'animation:pulse-ring 1.2s infinite;' : '';

      // 1. Draw pulsing target-radar icon for Citizen Distress signals
      let html = `<div style="width:24px;height:24px;background:${color};border-radius:50%;border:3px solid white;box-shadow:0 2px 8px rgba(0,0,0,0.4);display:flex;align-items:center;justify-content:center;${anim}"><div style="width:8px;height:8px;background:white;border-radius:50%;"></div></div>`;
      if (isDuress && agent.displayName?.toUpperCase().includes('CITIZEN')) {
        html = `
          <div style="width:36px;height:36px;background:rgba(239, 68, 68, 0.15);border-radius:50%;border:2.5px dashed rgba(239, 68, 68, 0.65);display:flex;align-items:center;justify-content:center;animation:spin-radar 10s linear infinite;">
            <div style="width:24px;height:24px;background:rgb(239, 68, 68);border-radius:50%;border:2px solid white;box-shadow:0 0 15px rgb(239, 68, 68);display:flex;align-items:center;justify-content:center;animation:pulse-ring 1.2s infinite;">
              <div style="width:8px;height:8px;background:white;border-radius:50%;"></div>
            </div>
          </div>
        `;
      }

      const iconSize = isDuress && agent.displayName?.toUpperCase().includes('CITIZEN') ? 36 : 24;
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
    </div>
  );
}
