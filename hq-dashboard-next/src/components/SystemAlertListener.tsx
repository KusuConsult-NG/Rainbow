'use client';
import { useState, useEffect } from 'react';
import { supabase } from '../lib/supabase';
import { AlertTriangle, Info, ShieldAlert, X } from 'lucide-react';

export default function SystemAlertListener() {
  const [activeAlert, setActiveAlert] = useState<any>(null);

  useEffect(() => {
    const fetchActiveAlert = async () => {
      const { data } = await supabase.from('system_alerts').select('*').order('created_at', { ascending: false }).limit(1);
      if (data && data.length > 0) {
        setActiveAlert(data[0]);
      }
    };

    fetchActiveAlert();

    const channel = supabase
      .channel('public:system_alerts')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'system_alerts' }, () => {
        fetchActiveAlert();
      })
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, []);

  if (!activeAlert) return null;

  const severity = activeAlert.severity || 'INFO';
  const isCritical = severity === 'CRITICAL';
  
  return (
    // DOCKED, not floating.
    //
    // This was `position: fixed; top: 24; left: 50%`, which put it straight over
    // the console header — hiding the live-status readout that tells an operator
    // whether the console is still connected at all. Moving it to the bottom
    // only traded one collision for another: it then clipped the map's
    // forecasting legend, because every corner of the map is already claimed by
    // filters, the incident feed, the legend and the zoom controls.
    //
    // A system-wide advisory is not a map overlay. Docking it under the header
    // as a full-width bar means it can never occlude anything, at any width.
    <div className="fade-in" style={{
      flexShrink: 0, margin: '12px 24px 0', zIndex: 500,
      background: isCritical ? 'var(--duress)' : 'var(--accent)',
      color: '#ffffff', padding: '16px 24px', borderRadius: 16,
      boxShadow: `0 10px 40px ${isCritical ? 'var(--duress)' : 'var(--accent)'}66`,
      display: 'flex', alignItems: 'center', gap: 20,
      border: '2px solid rgba(255,255,255,0.2)',
      fontFamily: 'Inter, sans-serif'
    }}>
      <div style={{ background: 'rgba(255,255,255,0.2)', padding: 10, borderRadius: 12 }}>
        {isCritical ? <ShieldAlert size={24} /> : <Info size={24} />}
      </div>
      <div style={{ flex: 1 }}>
        <div style={{ fontSize: 10, fontWeight: 900, letterSpacing: 2, opacity: 0.8, marginBottom: 4 }}>
          SYSTEM ADVISORY: {severity}
        </div>
        <div style={{ fontWeight: 800, fontSize: 14 }}>
          {activeAlert.message?.toUpperCase()}
        </div>
      </div>
      <button 
        onClick={() => setActiveAlert(null)}
        style={{ background: 'transparent', border: 'none', color: '#ffffff', cursor: 'pointer', opacity: 0.5 }}
      >
        <X size={20} />
      </button>
    </div>
  );
}
