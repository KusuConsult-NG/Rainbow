'use client';
import { useState, useEffect } from 'react';
import { collection, query, orderBy, limit, onSnapshot } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { ShieldAlert, Clock, Activity } from 'lucide-react';

interface AuditLog {
  id: string;
  action: string;
  alert_id?: string;
  actor?: string;
  from_tier?: string;
  to_tier?: string;
  minutes_elapsed?: number;
  timestamp?: { seconds: number };
}

export default function AuditLogs() {
  const [logs, setLogs] = useState<AuditLog[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const q = query(collection(db, 'audit_logs'), orderBy('timestamp', 'desc'), limit(100));
    const unsub = onSnapshot(q, snap => {
      setLogs(snap.docs.map(d => ({ id: d.id, ...d.data() } as AuditLog)));
      setLoading(false);
    }, () => setLoading(false));
    return () => unsub();
  }, []);

  const getActionStyle = (action: string) => {
    switch (action) {
      case 'TIER_HANDOFF': return { bg: 'rgba(33,150,243,0.1)', color: '#2196F3', label: 'JURISDICTIONAL HANDOFF' };
      case 'ADMIN_DISPATCH': return { bg: 'rgba(33,150,243,0.1)', color: '#2196F3', label: 'UNIT DISPATCHED' };
      case 'WATCHDOG_RECOVERY': return { bg: 'rgba(255,152,0,0.1)', color: '#FF9800', label: 'WATCHDOG RECOVERY' };
      case 'HQ_OVERRIDE': return { bg: 'rgba(156,39,176,0.1)', color: '#9C27B0', label: 'HQ COMMAND OVERRIDE' };
      case 'AGENT_ACKNOWLEDGED': return { bg: 'rgba(0,188,212,0.1)', color: '#00BCD4', label: 'FIELD ACKNOWLEDGMENT' };
      case 'INCIDENT_RESOLVED': return { bg: 'rgba(76,175,80,0.1)', color: '#4CAF50', label: 'THREAT NEUTRALIZED' };
      case 'FRAUD_SUSPICION': return { bg: 'rgba(244,67,54,0.1)', color: '#F44336', label: 'SECURITY ALERT' };
      default: return { bg: 'rgba(255,255,255,0.06)', color: 'var(--text-primary)', label: action };
    }
  };

  return (
    <div style={{ padding: '24px', maxWidth: 1200 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 40 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 18 }}>
          <div className="tactical-panel glass" style={{ padding: 16, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <ShieldAlert size={32} color="var(--primary)" />
          </div>
          <div>
            <h2 style={{ fontSize: 26, fontWeight: 900, letterSpacing: '-0.5px' }}>IMMUTABLE COMMAND AUDIT</h2>
            <p style={{ fontSize: 12, color: 'var(--text-muted)', fontWeight: 600 }}>High-assurance record of every jurisdictional decision and system trigger</p>
          </div>
        </div>
        <div style={{ display: 'flex', gap: 8 }}>
          <div style={{ padding: '8px 16px', background: 'var(--success-dim)', border: '1px solid rgba(16,185,129,0.2)', borderRadius: 30, display: 'flex', alignItems: 'center', gap: 8 }}>
            <div style={{ width: 6, height: 6, borderRadius: '50%', background: 'var(--success)', boxShadow: 'var(--success-glow)' }} className="pulse-emerald"></div>
            <span style={{ fontSize: 10, fontWeight: 900, color: 'var(--success)', letterSpacing: 0.5 }}>INTEGRITY VERIFIED</span>
          </div>
        </div>
      </div>

      <div className="tactical-panel glass" style={{ overflow: 'hidden' }}>
        <table style={{ width: '100%', borderCollapse: 'collapse' }}>
          <thead>
            <tr style={{ background: 'var(--input-bg)', borderBottom: '1px solid var(--border)' }}>
              <th style={{ padding: '20px 24px', textAlign: 'left', fontSize: 10, color: 'var(--text-muted)', fontWeight: 800, letterSpacing: 1.5 }}>TIMESTAMP (WAT)</th>
              <th style={{ padding: '20px 24px', textAlign: 'left', fontSize: 10, color: 'var(--text-muted)', fontWeight: 800, letterSpacing: 1.5 }}>OPERATIONAL ACTION</th>
              <th style={{ padding: '20px 24px', textAlign: 'left', fontSize: 10, color: 'var(--text-muted)', fontWeight: 800, letterSpacing: 1.5 }}>ACTOR IDENTITY</th>
              <th style={{ padding: '20px 24px', textAlign: 'left', fontSize: 10, color: 'var(--text-muted)', fontWeight: 800, letterSpacing: 1.5 }}>INCIDENT DETAILS</th>
            </tr>
          </thead>
          <tbody>
            {loading ? (
              <tr><td colSpan={4} style={{ padding: 64, textAlign: 'center' }}>
                <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 12 }}>
                  <Activity size={32} className="spin" color="var(--primary)" />
                  <span style={{ fontSize: 12, fontWeight: 600, color: 'var(--text-muted)' }}>Decrypting Secure Audit Stream...</span>
                </div>
              </td></tr>
            ) : logs.length === 0 ? (
              <tr><td colSpan={4} style={{ padding: 48, textAlign: 'center', fontSize: 13, color: 'var(--text-muted)', fontWeight: 500 }}>No jurisdictional activity recorded in the current epoch.</td></tr>
            ) : (
              logs.map(log => {
                const style = getActionStyle(log.action);
                return (
                  <tr key={log.id} style={{ borderBottom: '1px solid var(--border)', transition: 'background 0.2s' }} className="card-hover">
                    <td style={{ padding: '18px 24px', fontSize: 12, color: 'var(--text-primary)', fontWeight: 500, fontFamily: 'monospace' }}>
                      {log.timestamp ? new Date(log.timestamp.seconds * 1000).toLocaleString('en-GB', { hour: '2-digit', minute: '2-digit', second: '2-digit', day: '2-digit', month: 'short' }) : 'PENDING'}
                    </td>
                    <td style={{ padding: '18px 24px' }}>
                      <span style={{ fontSize: 9, fontWeight: 900, padding: '5px 12px', borderRadius: 6, background: style.bg, color: style.color, letterSpacing: 0.5, display: 'inline-block' }}>
                        {style.label}
                      </span>
                    </td>
                    <td style={{ padding: '18px 24px' }}>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                        <div style={{ width: 24, height: 24, background: 'var(--input-bg)', border: '1px solid var(--border)', borderRadius: '50%', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 10, fontWeight: 800 }}>
                          {log.actor?.charAt(0).toUpperCase() || 'S'}
                        </div>
                        <span style={{ fontSize: 12, fontWeight: 700, color: 'var(--text-primary)' }}>{log.actor || 'SYSTEM_DAEMON'}</span>
                      </div>
                    </td>
                    <td style={{ padding: '18px 24px', fontSize: 12, color: 'var(--text-muted)', lineHeight: 1.5 }}>
                      {log.action === 'TIER_HANDOFF' || log.action === 'WATCHDOG_RECOVERY' ? (
                        <span>
                          Incident <strong style={{ color: 'var(--text-primary)' }}>{log.alert_id?.substring(0, 8)}</strong> escalated: 
                          <span style={{ fontWeight: 800, margin: '0 4px', color: 'var(--text-primary)' }}>{log.from_tier}</span> 
                          ➔ 
                          <span style={{ fontWeight: 800, margin: '0 4px', color: 'var(--primary)' }}>{log.to_tier}</span>
                          {log.minutes_elapsed && <span style={{ marginLeft: 6, fontSize: 10 }}>(Latency: {log.minutes_elapsed}m)</span>}
                        </span>
                      ) : (
                        <span>Incident Hash: <strong style={{ color: 'var(--text-primary)' }}>{log.alert_id?.substring(0, 12)}</strong></span>
                      )}
                    </td>
                  </tr>
                );
              })
            )}
          </tbody>
        </table>
      </div>
      <style>{`
        .spin { animation: spin 2s linear infinite; }
        @keyframes spin { from { transform: rotate(0deg); } to { transform: rotate(360deg); } }
      `}</style>
    </div>
  );
}
