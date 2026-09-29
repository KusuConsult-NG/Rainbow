'use client';
import { useState, useEffect } from 'react';
import { supabase } from '../lib/supabase';
import { Activity, Target, Shield, Users } from 'lucide-react';

export default function Analytics() {
  const [totalAlerts, setTotalAlerts] = useState(0);
  const [activeAlerts, setActiveAlerts] = useState(0);
  /**
   * Set when a figure could not be read.
   *
   * A zero that came from a failed query looks exactly like a zero that came from
   * an empty table, and on a dashboard the first is a lie.
   */
  const [loadError, setLoadError] = useState<string | null>(null);
  const [resolvedAlerts, setResolvedAlerts] = useState(0);
  const [totalPersonnel, setTotalPersonnel] = useState(0);

  useEffect(() => {
    const fetchAnalytics = async () => {
      // Every one of these is checked. A zero from a failed query looks exactly
      // like a zero from an empty table, and on a dashboard the first is a lie —
      // the same defect as a feed saying ALL SECTORS CLEAR on a query nobody read.
      const failures: string[] = [];

      const { count: alertsCount, error: totalErr } = await supabase
        .from('alerts').select('*', { count: 'exact', head: true });
      if (totalErr) failures.push('total incidents');
      setTotalAlerts(alertsCount || 0);

      // ACTIVE is "not closed", not "PENDING".
      //
      // This counted only status = 'PENDING', so an incident that had been
      // DISPATCHED, or ESCALATED, or was a DURESS alarm counted as NOT active.
      // The number an operator read as "active incidents" excluded every incident
      // anybody was actually working on, and excluded silent duress alarms
      // entirely — the most urgent thing in the system was missing from the count
      // of urgent things.
      //
      // Expressed as "not in the closed set" so a status added later is counted
      // by default. The failure direction matters: a new status omitted from an
      // inclusion list vanishes from the total silently, while one wrongly
      // counted is visible and gets fixed.
      const { count: activeCount, error: activeErr } = await supabase
        .from('alerts')
        .select('*', { count: 'exact', head: true })
        .not('status', 'in', '("RESOLVED","CANCELLED","FALSE_REPORT")');
      if (activeErr) failures.push('active incidents');
      setActiveAlerts(activeCount || 0);

      const { count: resolvedCount, error: resolvedErr } = await supabase
        .from('alerts').select('*', { count: 'exact', head: true }).eq('status', 'RESOLVED');
      if (resolvedErr) failures.push('resolved incidents');
      setResolvedAlerts(resolvedCount || 0);

      const { count: profilesCount, error: personnelErr } = await supabase
        .from('profiles').select('*', { count: 'exact', head: true });
      if (personnelErr) failures.push('personnel');
      setTotalPersonnel(profilesCount || 0);

      if (failures.length > 0) {
        console.error('[ANALYTICS_ERR] could not read:', failures.join(', '));
        // Names WHICH figures, because "some figures failed" leaves an operator
        // unable to tell which number on the screen to distrust.
        setLoadError(`Could not read: ${failures.join(', ')}. Those figures show 0.`);
      } else {
        setLoadError(null);
      }
    };

    fetchAnalytics();
  }, []);

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 24 }}>
      {loadError && (
        <div role="alert" style={{ padding: '10px 14px', border: '1px solid var(--duress)', borderRadius: 12 }}>
          <span style={{ fontSize: 11, fontWeight: 900, color: 'var(--duress)' }}>
            FIGURES INCOMPLETE
          </span>
          <p style={{ fontSize: 11.5, color: 'var(--text-muted)', margin: '4px 0 0' }}>{loadError}</p>
        </div>
      )}
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
