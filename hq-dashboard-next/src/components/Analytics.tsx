'use client';
import { useState, useEffect } from 'react';
import { supabase } from '../lib/supabase';
import { Activity, Target, Shield, Users, TrendingUp, TimerOff } from 'lucide-react';
import { OPEN_STATUSES } from '../lib/alert-status';

export default function Analytics() {
  const [totalAlerts, setTotalAlerts] = useState(0);
  const [activeAlerts, setActiveAlerts] = useState(0);
  const [resolvedAlerts, setResolvedAlerts] = useState(0);
  const [totalPersonnel, setTotalPersonnel] = useState(0);
  const [escalatedAlerts, setEscalatedAlerts] = useState(0);
  const [breachedAlerts, setBreachedAlerts] = useState(0);

  useEffect(() => {
    let cancelled = false;

    const fetchAnalytics = async () => {
      const head = { count: 'exact' as const, head: true };

      const { count: alertsCount } = await supabase.from('alerts').select('*', head);

      // Every open state, not just PENDING. Counting only PENDING meant an
      // incident under way — dispatched, acknowledged, en route, on site,
      // escalated or in duress — dropped out of the active figure, so the
      // dashboard under-reported exactly the incidents being worked.
      const { count: activeCount } = await supabase
        .from('alerts')
        .select('*', head)
        .in('status', OPEN_STATUSES as unknown as string[]);

      const { count: resolvedCount } = await supabase
        .from('alerts')
        .select('*', head)
        .in('status', ['RESOLVED', 'CLOSED']);

      const { count: escalatedCount } = await supabase
        .from('alerts')
        .select('*', head)
        .not('escalated_at', 'is', null);

      const { count: breachedCount } = await supabase
        .from('alerts')
        .select('*', head)
        .eq('sla_breached', true);

      const { count: profilesCount } = await supabase.from('profiles').select('*', head);

      if (cancelled) return;
      setTotalAlerts(alertsCount || 0);
      setActiveAlerts(activeCount || 0);
      setResolvedAlerts(resolvedCount || 0);
      setEscalatedAlerts(escalatedCount || 0);
      setBreachedAlerts(breachedCount || 0);
      setTotalPersonnel(profilesCount || 0);
    };

    fetchAnalytics();
    return () => {
      cancelled = true;
    };
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
          <TrendingUp size={24} style={{ color: 'var(--warning)', marginBottom: 12 }} />
          <p style={{ fontSize: 11, color: 'var(--text-muted)', fontWeight: 800 }}>ESCALATED AT LEAST ONCE</p>
          <h3 style={{ fontSize: 32, fontWeight: 900, color: 'var(--text-primary)' }}>{escalatedAlerts}</h3>
        </div>

        <div className="tactical-panel glass" style={{ padding: 24 }}>
          <TimerOff size={24} style={{ color: 'var(--danger)', marginBottom: 12 }} />
          <p style={{ fontSize: 11, color: 'var(--text-muted)', fontWeight: 800 }}>RESPONSE SLA BREACHED</p>
          <h3 style={{ fontSize: 32, fontWeight: 900, color: 'var(--text-primary)' }}>{breachedAlerts}</h3>
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
