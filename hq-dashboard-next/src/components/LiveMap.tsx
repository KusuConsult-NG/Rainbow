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
  timestamp?: any;
}

interface Props {
  alerts: Alert[];
  agents?: AgentLocation[];
  onResolve: (id: string) => void;
  onEscalate: (id: string, tier: string) => void;
}

export default function LiveMap({ alerts, agents = [], onResolve, onEscalate }: Props) {
  const mapRef = useRef<HTMLDivElement>(null);
  const mapInstanceRef = useRef<any>(null);
  const markersRef = useRef<any[]>([]);
  const agentMarkersRef = useRef<any[]>([]);

  useEffect(() => {
    if (!mapRef.current || mapInstanceRef.current) return;

    // Dynamically import Leaflet (client-only)
    import('leaflet').then((L) => {
      import('leaflet/dist/leaflet.css');

      const map = L.default.map(mapRef.current!, {
        center: [9.9167, 8.8917],
        zoom: 9,
        zoomControl: false,
      });

      L.default.control.zoom({ position: 'bottomright' }).addTo(map);

      L.default.tileLayer(
        'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
        { attribution: '© CARTO' }
      ).addTo(map);

      // Fetch and draw Geo-Boundaries
      fetch('/plateau_boundaries.json')
        .then(res => res.json())
        .then(data => {
          L.default.geoJSON(data, {
            style: {
              color: '#af101a',
              weight: 2,
              opacity: 0.6,
              fillColor: '#af101a',
              fillOpacity: 0.05,
              dashArray: '5, 5'
            },
            onEachFeature: (feature: any, layer: any) => {
              if (feature.properties && feature.properties.lga) {
                layer.bindTooltip(`<b>${feature.properties.lga}</b>`, {
                  permanent: true,
                  direction: 'center',
                  className: 'bg-transparent border-0 shadow-none text-red-800 font-bold text-xs',
                  opacity: 0.7
                });
              }
            }
          }).addTo(map);
        })
        .catch(err => console.error('Failed to load boundaries:', err));

      mapInstanceRef.current = { map, L: L.default };
    });

    return () => {
      if (mapInstanceRef.current) {
        mapInstanceRef.current.map.remove();
        mapInstanceRef.current = null;
      }
    };
  }, []);

  useEffect(() => {
    if (!mapInstanceRef.current) return;
    const { map, L } = mapInstanceRef.current;

    // Clear old markers
    markersRef.current.forEach(m => m.remove());
    markersRef.current = [];

    alerts.forEach(alert => {
      if (!alert.lat || !alert.lng) return;
      const isDuress = alert.status === 'DURESS';
      const isCritical = alert.isCritical || alert.priority === 'CRITICAL';
      const color = isDuress ? '#720000' : isCritical ? '#E53935' : '#F57F17';
      const size = isDuress ? 56 : isCritical ? 42 : 28;

      const icon = L.divIcon({
        className: '',
        html: `<div style="
          width:${size}px;height:${size}px;
          background:${color}99;border-radius:50%;
          border:3px solid white;display:flex;align-items:center;justify-content:center;
          ${isDuress ? 'animation:pulse-ring 1.5s infinite;' : ''}
        "><div style="width:${size * 0.45}px;height:${size * 0.45}px;background:${color};border-radius:50%;"></div></div>`,
        iconSize: [size, size],
        iconAnchor: [size / 2, size / 2],
        popupAnchor: [0, -size / 2],
      });

      const time = alert.reportedAt
        ? new Date(alert.reportedAt.seconds * 1000).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' })
        : 'Unknown';

      const marker = L.marker([alert.lat, alert.lng], { icon }).addTo(map);
      marker.bindPopup(`
        <div style="font-family:Inter,sans-serif;min-width:220px;padding:4px">
          <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px">
            <strong style="color:${isDuress ? '#720000' : color};font-size:14px">
              ${isDuress ? '🔴 DURESS' : alert.type || 'EMERGENCY'}
            </strong>
            <span style="font-size:9px;background:#222;color:#fff;padding:2px 6px;border-radius:4px;font-weight:800">
              ${(alert.assigned_to || '').replace('_', ' ')}
            </span>
          </div>
          <p style="font-size:11px;color:#555;margin:0 0 4px">${time} · ${alert.reportedBy || 'Anonymous'}</p>
          <p style="font-size:12px;color:#333;margin:0 0 12px;line-height:1.4">${alert.description || 'No description'}</p>
          <div style="display:flex;gap:6px">
            <button onclick="window._hqEscalate('${alert.id}','${alert.assigned_to}')"
              style="flex:1;padding:8px;background:#FF9800;color:white;border:none;border-radius:4px;font-size:11px;font-weight:800;cursor:pointer">
              ESCALATE
            </button>
            <button onclick="window._hqResolve('${alert.id}')"
              style="flex:1;padding:8px;background:#4CAF50;color:white;border:none;border-radius:4px;font-size:11px;font-weight:800;cursor:pointer">
              RESOLVE
            </button>
          </div>
          ${alert.lat && alert.lng ? `<a href="https://www.google.com/maps?q=${alert.lat},${alert.lng}" target="_blank"
            style="display:block;margin-top:8px;font-size:10px;color:#af101a;text-align:center">📍 Open in Google Maps</a>` : ''}
        </div>
      `);
      markersRef.current.push(marker);
    });
  }, [alerts]);

  useEffect(() => {
    if (!mapInstanceRef.current) return;
    const { map, L } = mapInstanceRef.current;

    // Clear old agent markers
    agentMarkersRef.current.forEach(m => m.remove());
    agentMarkersRef.current = [];

    agents.forEach(agent => {
      if (!agent.lat || !agent.lng) return;

      const icon = L.divIcon({
        className: '',
        html: `<div style="width:20px;height:20px;background:#af101a;border-radius:50%;border:3px solid white;box-shadow:0 2px 4px rgba(0,0,0,0.3);display:flex;align-items:center;justify-content:center;">
          <div style="width:6px;height:6px;background:white;border-radius:50%;"></div>
        </div>`,
        iconSize: [20, 20],
        iconAnchor: [10, 10],
        popupAnchor: [0, -10],
      });

      const time = agent.timestamp?.seconds 
        ? new Date(agent.timestamp.seconds * 1000).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit', second: '2-digit' })
        : 'Live';

      const marker = L.marker([agent.lat, agent.lng], { icon, zIndexOffset: 1000 }).addTo(map);
      marker.bindPopup(`
        <div style="font-family:Inter,sans-serif;padding:4px">
          <strong style="color:#af101a;font-size:12px;display:flex;align-items:center;gap:4px">
            <span style="display:inline-block;width:6px;height:6px;background:#4CAF50;border-radius:50%"></span>
            FIELD AGENT
          </strong>
          <p style="font-size:10px;color:#555;margin:4px 0 0">ID: ${agent.user_id}</p>
          <p style="font-size:9px;color:#888;margin:2px 0 0">Last seen: ${time}</p>
        </div>
      `);
      agentMarkersRef.current.push(marker);
    });
  }, [agents]);

  // Bridge popup buttons to React handlers via window globals
  useEffect(() => {
    (window as any)._hqResolve = onResolve;
    (window as any)._hqEscalate = onEscalate;
  }, [onResolve, onEscalate]);

  return (
    <div style={{ position: 'relative', height: '100%', width: '100%' }}>
      <style>{`
        @keyframes pulse-ring {
          0% { box-shadow: 0 0 0 0 rgba(114,0,0,0.7); }
          70% { box-shadow: 0 0 0 20px rgba(114,0,0,0); }
          100% { box-shadow: 0 0 0 0 rgba(114,0,0,0); }
        }
        .leaflet-container { background: #f8f9fa; }
      `}</style>
      <div ref={mapRef} style={{ height: '100%', width: '100%' }} />
    </div>
  );
}
