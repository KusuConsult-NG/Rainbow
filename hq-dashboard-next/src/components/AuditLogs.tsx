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

  return (
    <div style={{ padding: '8px 0', maxWidth: 1000 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 14, marginBottom: 32 }}>
        <div style={{ padding: 12, background: 'rgba(0,0,0,0.06)', borderRadius: 12 }}>
          <ShieldAlert size={28} color="var(--accent)" />
        </div>
        <div>
          <h2 style={{ fontSize: 22, fontWeight: 900 }}>SYSTEM AUDIT LOGS</h2>
          <p style={{ fontSize: 11, color: 'var(--text-muted)' }}>Immutable record of critical system actions and automated escalations</p>
        </div>
      </div>

      <div className="glass" style={{ borderRadius: 16, overflow: 'hidden' }}>
        <table style={{ width: '100%', borderCollapse: 'collapse' }}>
          <thead>
            <tr style={{ background: 'rgba(0,0,0,0.02)', borderBottom: '1px solid var(--border)' }}>
              <th style={{ padding: '12px 16px', textAlign: 'left', fontSize: 10, color: 'var(--text-muted)', fontWeight: 800, letterSpacing: 1 }}>TIME</th>
              <th style={{ padding: '12px 16px', textAlign: 'left', fontSize: 10, color: 'var(--text-muted)', fontWeight: 800, letterSpacing: 1 }}>ACTION</th>
              <th style={{ padding: '12px 16px', textAlign: 'left', fontSize: 10, color: 'var(--text-muted)', fontWeight: 800, letterSpacing: 1 }}>ACTOR</th>
              <th style={{ padding: '12px 16px', textAlign: 'left', fontSize: 10, color: 'var(--text-muted)', fontWeight: 800, letterSpacing: 1 }}>DETAILS</th>
            </tr>
          </thead>
          <tbody>
            {loading ? (
              <tr><td colSpan={4} style={{ padding: 24, textAlign: 'center', fontSize: 12 }}>Loading logs...</td></tr>
            ) : logs.length === 0 ? (
              <tr><td colSpan={4} style={{ padding: 24, textAlign: 'center', fontSize: 12, color: 'var(--text-muted)' }}>No audit logs found.</td></tr>
            ) : (
              logs.map(log => (
                <tr key={log.id} style={{ borderBottom: '1px solid rgba(0,0,0,0.03)' }}>
                  <td style={{ padding: '12px 16px', fontSize: 11, color: 'var(--text-muted)' }}>
                    {log.timestamp ? new Date(log.timestamp.seconds * 1000).toLocaleString('en-GB') : '—'}
                  </td>
                  <td style={{ padding: '12px 16px' }}>
                    <span style={{ fontSize: 9, fontWeight: 800, padding: '3px 8px', borderRadius: 20, background: 'rgba(0,0,0,0.06)', color: log.action.includes('ESCALATION') ? 'var(--accent)' : 'var(--text-primary)' }}>
                      {log.action}
                    </span>
                  </td>
                  <td style={{ padding: '12px 16px', fontSize: 11, fontWeight: 700 }}>{log.actor || 'SYSTEM'}</td>
                  <td style={{ padding: '12px 16px', fontSize: 11, color: 'var(--text-muted)' }}>
                    {log.action === 'AUTO_ESCALATION' ? (
                      <span>Alert <strong>{log.alert_id?.substring(0, 8)}...</strong> escalated from <strong>{log.from_tier}</strong> to <strong>{log.to_tier}</strong> after {log.minutes_elapsed}m</span>
                    ) : (
                      <span>Alert: {log.alert_id}</span>
                    )}
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
