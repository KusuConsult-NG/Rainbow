'use client';
import { useState, useEffect } from 'react';
import { supabase } from '../lib/supabase';
import { Activity, Target, Shield, Users } from 'lucide-react';

export default function Analytics() {
  const [totalAlerts, setTotalAlerts] = useState(0);
  const [activeAlerts, setActiveAlerts] = useState(0);
  const [resolvedAlerts, setResolvedAlerts] = useState(0);
  const [totalPersonnel, setTotalPersonnel] = useState(0);

  useEffect(() => {
    const fetchAnalytics = async () => {
      const { count: alertsCount } = await supabase.from('alerts').select('*', { count: 'exact', head: true });
      setTotalAlerts(alertsCount || 0);

      const { count: activeCount } = await supabase.from('alerts').select('*', { count: 'exact', head: true }).eq('status', 'PENDING');
      setActiveAlerts(activeCount || 0);

      const { count: resolvedCount } = await supabase.from('alerts').select('*', { count: 'exact', head: true }).eq('status', 'RESOLVED');
      setResolvedAlerts(resolvedCount || 0);

      const { count: profilesCount } = await supabase.from('profiles').select('*', { count: 'exact', head: true });
      setTotalPersonnel(profilesCount || 0);
    };

    fetchAnalytics();
  }, []);

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 24 }}>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))', gap: 20 }}>
        <div className="tactical-panel glass" style={{ padding: 24 }}>
          <Activity size={24} style={{ color: 'var(--primary)', marginBottom: 12 }} />
          <p style={{ fontSize: 11, color: 'var(--text-muted)', fontWeight: 800 }}>TOTAL INCIDENTS LOGGED</p>
          <h3 style={{ fontSize: 32, fontWeight: 900, color: 'var(--text-primary)' }}>{totalAlerts}</h3>
        </div>

        <div className="tactical-panel glass" style={{ padding: 24 }}>
          <Target size={24} style={{ color: 'var(--warning)', marginBottom: 12 }} />
          <p style={{ fontSize: 11, color: 'var(--text-muted)', fontWeight: 800 }}>ACTIVE THREAT ALERTS</p>
          <h3 style={{ fontSize: 32, fontWeight: 900, color: 'var(--text-primary)' }}>{activeAlerts}</h3>
        </div>

        <div className="tactical-panel glass" style={{ padding: 24 }}>
          <Shield size={24} style={{ color: 'var(--success)', marginBottom: 12 }} />
          <p style={{ fontSize: 11, color: 'var(--text-muted)', fontWeight: 800 }}>RESOLVED INCIDENTS</p>
          <h3 style={{ fontSize: 32, fontWeight: 900, color: 'var(--text-primary)' }}>{resolvedAlerts}</h3>
        </div>

        <div className="tactical-panel glass" style={{ padding: 24 }}>
          <Users size={24} style={{ color: 'var(--accent)', marginBottom: 12 }} />
          <p style={{ fontSize: 11, color: 'var(--text-muted)', fontWeight: 800 }}>ACTIVE PERSONNEL</p>
          <h3 style={{ fontSize: 32, fontWeight: 900, color: 'var(--text-primary)' }}>{totalPersonnel}</h3>
        </div>
      </div>
    </div>
  );
}
