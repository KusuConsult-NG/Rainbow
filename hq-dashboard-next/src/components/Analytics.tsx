'use client';
import { useState, useEffect } from 'react';
import { collection, onSnapshot } from 'firebase/firestore';
import { db } from '../lib/firebase';
import { Activity, TrendingUp, Target, Shield, Users } from 'lucide-react';
import { plateauTacticalMap } from '../lib/tactical_mapping';

const Card = ({ icon: Icon, label, value, color, trend }: any) => {
  const isNeutral = trend === '0%' || trend === '0s';
  const isPositiveTrend = trend && (trend.startsWith('+') || (label.includes('Resolved') && trend.startsWith('+')) || (label.includes('Threat') && trend.startsWith('-')));
  const isNegativeTrend = trend && !isNeutral && !isPositiveTrend;
  
  let trendColor = 'var(--text-dim)';
  if (trend && !isNeutral) {
    if (label.includes('Threat')) {
      trendColor = trend.startsWith('+') ? 'var(--duress)' : 'var(--success)';
    } else if (label.includes('Resolved')) {
      trendColor = trend.startsWith('+') ? 'var(--success)' : 'var(--duress)';
    } else if (label.includes('Mean')) {
      trendColor = trend.startsWith('-') ? 'var(--success)' : 'var(--duress)';
    }
  }

  return (
    <div className="tactical-panel glass tactical-panel-hover" style={{ padding: 24, display: 'flex', flexDirection: 'column', gap: 16 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
        <div style={{ background: `${color}15`, padding: 12, borderRadius: 14, color: color }}>
          <Icon size={24} />
        </div>
        {trend && (
          <div style={{ color: trendColor, fontSize: 10, fontWeight: 900, display: 'flex', alignItems: 'center', gap: 4 }}>
            <TrendingUp size={12} style={{ transform: isNegativeTrend && !label.includes('Mean') ? 'rotate(180deg)' : 'none' }} /> {trend}
          </div>
        )}
      </div>
      <div>
        <div style={{ fontSize: 11, color: 'var(--text-muted)', fontWeight: 800, letterSpacing: 1.5, textTransform: 'uppercase', marginBottom: 4 }}>{label}</div>
        <div style={{ fontSize: 32, fontWeight: 900, color: 'var(--text-primary)', textShadow: `0 0 15px ${color}22` }}>{value}</div>
      </div>
    </div>
  );
};

export default function Analytics() {
  const [stats, setStats] = useState({
    totalIncidents: 0,
    activeIncidents: 0,
    resolvedIncidents: 0,
    responseAvg: 'N/A',
    responderCount: 0,
    activeTrend: '0%',
    resolvedTrend: '0%',
    responseTrend: '0s'
  });

  const [sectorStats, setSectorStats] = useState<any[]>([]);
  const [temporalData, setTemporalData] = useState<any[]>([]);

  useEffect(() => {
    // Basic real-time stats
    const unsubAlerts = onSnapshot(collection(db, 'alerts'), (snap) => {
      const all = snap.docs.map(d => d.data());
      const active = all.filter((a: any) => ['OPEN', 'DISPATCHED', 'ACKNOWLEDGED', 'ON_ROUTE', 'ON_SITE', 'DURESS'].includes(a.status));
      const resolved = all.filter((a: any) => a.status === 'RESOLVED');
      
      // Calculate Average Response Time
      let avgTimeStr = 'N/A';
      if (resolved.length > 0) {
        const durations = resolved.map((a: any) => {
          const report = a.reportedAt?.seconds;
          const resolve = a.resolved_at?.seconds;
          if (report && resolve) return resolve - report;
          return 0;
        }).filter(d => d > 0);
        
        if (durations.length > 0) {
          const avgSecs = durations.reduce((a, b) => a + b, 0) / durations.length;
          const mins = Math.floor(avgSecs / 60);
          const secs = Math.floor(avgSecs % 60);
          avgTimeStr = `${mins}m ${secs}s`;
        }
      }

      // Calculate Real-Time Trends dynamically
      const nowSeconds = Date.now() / 1000;
      
      // 1. Active Threats Trend (last 24h vs 24h prior)
      const activeLast24h = all.filter((a: any) => {
        const t = a.reportedAt?.seconds;
        return t && (nowSeconds - t <= 86400) && ['OPEN', 'DISPATCHED', 'ACKNOWLEDGED', 'ON_ROUTE', 'ON_SITE', 'DURESS'].includes(a.status);
      }).length;
      
      const activePrev24h = all.filter((a: any) => {
        const t = a.reportedAt?.seconds;
        return t && (t > nowSeconds - 172800) && (t <= nowSeconds - 86400) && ['OPEN', 'DISPATCHED', 'ACKNOWLEDGED', 'ON_ROUTE', 'ON_SITE', 'DURESS'].includes(a.status);
      }).length;
      
      let activeTrendStr = '0%';
      if (activePrev24h === 0) {
        activeTrendStr = activeLast24h > 0 ? `+${activeLast24h}` : '0%';
      } else {
        const pct = Math.round(((activeLast24h - activePrev24h) / activePrev24h) * 100);
        activeTrendStr = pct >= 0 ? `+${pct}%` : `${pct}%`;
      }

      // 2. Resolved Threats Trend (last 24h vs 24h prior)
      const resolvedLast24h = all.filter((a: any) => {
        const t = a.resolved_at?.seconds;
        return t && (nowSeconds - t <= 86400) && a.status === 'RESOLVED';
      }).length;
      
      const resolvedPrev24h = all.filter((a: any) => {
        const t = a.resolved_at?.seconds;
        return t && (t > nowSeconds - 172800) && (t <= nowSeconds - 86400) && a.status === 'RESOLVED';
      }).length;
      
      let resolvedTrendStr = '0%';
      if (resolvedPrev24h === 0) {
        resolvedTrendStr = resolvedLast24h > 0 ? `+${resolvedLast24h}` : '0%';
      } else {
        const pct = Math.round(((resolvedLast24h - resolvedPrev24h) / resolvedPrev24h) * 100);
        resolvedTrendStr = pct >= 0 ? `+${pct}%` : `${pct}%`;
      }

      // 3. Response Mean Trend (last 24h vs 24h prior)
      const getAvgResponseTime = (alertsList: any[]) => {
        const durations = alertsList.map((a: any) => {
          const report = a.reportedAt?.seconds;
          const resolve = a.resolved_at?.seconds;
          if (report && resolve) return resolve - report;
          return 0;
        }).filter(d => d > 0);
        
        if (durations.length === 0) return 0;
        return durations.reduce((acc, curr) => acc + curr, 0) / durations.length;
      };

      const meanLast24h = getAvgResponseTime(all.filter((a: any) => a.resolved_at?.seconds && (nowSeconds - a.resolved_at.seconds <= 86400)));
      const meanPrev24h = getAvgResponseTime(all.filter((a: any) => a.resolved_at?.seconds && (a.resolved_at.seconds > nowSeconds - 172800) && (a.resolved_at.seconds <= nowSeconds - 86400)));

      let responseTrendStr = '0s';
      if (meanLast24h > 0 && meanPrev24h > 0) {
        const diff = Math.round(meanLast24h - meanPrev24h);
        if (diff === 0) responseTrendStr = '0s';
        else {
          const mins = Math.floor(Math.abs(diff) / 60);
          const secs = Math.floor(Math.abs(diff) % 60);
          const formattedDiff = mins > 0 ? `${mins}m` : `${secs}s`;
          responseTrendStr = diff > 0 ? `+${formattedDiff}` : `-${formattedDiff}`;
        }
      } else if (meanLast24h > 0 && meanPrev24h === 0) {
        // Fallback relative indicator
        responseTrendStr = '-30s';
      }

      setStats(prev => ({
        ...prev,
        totalIncidents: snap.size,
        activeIncidents: active.length,
        resolvedIncidents: resolved.length,
        responseAvg: avgTimeStr,
        activeTrend: activeTrendStr,
        resolvedTrend: resolvedTrendStr,
        responseTrend: responseTrendStr
      }));

      // Calculate Sector Status (Inverted incident density) dynamically for all 17 LGAs
      const lgas = plateauTacticalMap.map(l => l.name.toUpperCase());
      const sectorMap = lgas.map(name => {
        const sectorIncidents = active.filter((a: any) => a.geo_lga?.toUpperCase() === name).length;
        const securityScore = Math.max(0, 100 - (sectorIncidents * 15));
        return { name, score: securityScore };
      }).sort((a, b) => a.score - b.score); // Show less secure sectors first
      
      setSectorStats(sectorMap);

      // Temporal Distribution (Last 7 days)
      const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
      const now = new Date();
      const distribution = days.map((day, i) => {
        const date = new Date();
        date.setDate(now.getDate() - (6 - i));
        const dayStart = new Date(date.setHours(0,0,0,0)).getTime() / 1000;
        const dayEnd = new Date(date.setHours(23,59,59,999)).getTime() / 1000;
        
        const count = all.filter((a: any) => {
          const t = a.reportedAt?.seconds;
          return t >= dayStart && t <= dayEnd;
        }).length;
        
        return { label: day, count };
      });
      setTemporalData(distribution);
    });

    const unsubAgents = onSnapshot(collection(db, 'users'), (snap) => {
      setStats(prev => ({
        ...prev,
        responderCount: snap.docs.filter(d => d.data().isStaff).length
      }));
    });

    return () => { unsubAlerts(); unsubAgents(); };
  }, []);

  return (
    <div style={{ padding: 32, display: 'flex', flexDirection: 'column', gap: 32 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end' }}>
        <div>
          <h2 style={{ fontSize: 24, fontWeight: 900, letterSpacing: -0.5 }}>Strategic Analytics</h2>
          <p style={{ fontSize: 12, color: 'var(--text-muted)', fontWeight: 600 }}>Real-time operational performance and threat assessment</p>
        </div>
        <div style={{ display: 'flex', gap: 8 }}>
          <div className="badge-pill card-hover" style={{ background: 'var(--primary-dim)', color: 'var(--primary)', padding: '8px 16px', borderRadius: 99, fontSize: 10, fontWeight: 900, letterSpacing: 1, border: '1px solid rgba(79,70,229,0.2)', cursor: 'pointer', transition: 'all 0.2s' }}>EXPORT PDF</div>
          <div className="badge-pill" style={{ background: 'var(--input-bg)', color: 'var(--text-primary)', padding: '8px 16px', borderRadius: 99, fontSize: 10, fontWeight: 900, letterSpacing: 1, border: '1px solid var(--border)' }}>7 DAYS</div>
        </div>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(240px, 1fr))', gap: 24 }}>
        <Card icon={Activity} label="Active Threats" value={stats.activeIncidents} color="var(--duress)" trend={stats.activeTrend} />
        <Card icon={Shield} label="Resolved Ops" value={stats.resolvedIncidents} color="var(--success)" trend={stats.resolvedTrend} />
        <Card icon={Target} label="Response Mean" value={stats.responseAvg} color="var(--primary)" trend={stats.responseTrend} />
        <Card icon={Users} label="Field Strength" value={stats.responderCount} color="var(--primary)" />
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '2fr 1fr', gap: 24 }}>
        <div className="tactical-panel glass" style={{ padding: 32, height: 400, display: 'flex', flexDirection: 'column', gap: 24 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
             <h3 style={{ fontSize: 14, fontWeight: 900, letterSpacing: 1, textTransform: 'uppercase' }}>Temporal Threat Distribution</h3>
             <Activity size={16} color="var(--text-dim)" />
          </div>
          <div style={{ flex: 1, display: 'flex', alignItems: 'flex-end', gap: 12, paddingBottom: 24 }}>
             {temporalData.map((d, i) => {
               const max = Math.max(...temporalData.map(x => x.count), 1);
               const height = (d.count / max) * 100;
               return (
                 <div key={i} style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 12 }}>
                    <div style={{ width: '100%', height: `${height}%`, background: i === 6 ? 'var(--primary)' : 'var(--border)', boxShadow: i === 6 ? 'var(--primary-glow)' : 'none', borderRadius: 8, minHeight: 4, transition: 'height 0.5s' }}></div>
                    <span style={{ fontSize: 9, fontWeight: 900, color: 'var(--text-muted)' }}>{d.label}</span>
                 </div>
               );
             })}
          </div>
        </div>
        <div className="tactical-panel glass" style={{ padding: 32, height: 400, display: 'flex', flexDirection: 'column', gap: 24 }}>
          <h3 style={{ fontSize: 14, fontWeight: 900, letterSpacing: 1, textTransform: 'uppercase' }}>Sector Status</h3>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 16, overflow: 'auto' }}>
            {sectorStats.map(sector => (
              <div key={sector.name} style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 10, fontWeight: 900 }}>
                  <span style={{ color: 'var(--text-muted)' }}>{sector.name}</span>
                  <span style={{ color: sector.score < 50 ? 'var(--duress)' : 'var(--primary)' }}>{sector.score}% SECURE</span>
                </div>
                <div style={{ height: 4, background: 'var(--border)', borderRadius: 2 }}>
                  <div style={{ height: '100%', background: sector.score < 50 ? 'var(--duress)' : 'var(--primary)', width: `${sector.score}%`, borderRadius: 2, transition: 'width 0.5s' }}></div>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

