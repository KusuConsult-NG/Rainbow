'use client';
import { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import { ShieldAlert, Clock, ArrowRight } from 'lucide-react';

interface AuditLog {
  id: string;
  action: string;
  alert_id?: string | null;
  actor?: string | null;
  from_tier?: string | null;
  to_tier?: string | null;
  reason?: string | null;
  detail?: Record<string, unknown> | null;
  created_at?: string | null;
}

export default function AuditLogs() {
  const [logs, setLogs] = useState<AuditLog[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;

    const fetchLogs = async () => {
      // This panel reads the audit log. It used to read `chat_messages`, which
      // meant the audit tab showed operator chatter and the actual audit trail
      // — every escalation, dispatch and tier change the engine records — was
      // written but never surfaced anywhere.
      const { data, error: err } = await supabase
        .from('audit_logs')
        .select('*')
        .order('created_at', { ascending: false })
        .limit(100);

      if (cancelled) return;
      if (err) setError(err.message);
      setLogs((data || []) as AuditLog[]);
      setLoading(false);
    };

    fetchLogs();
    return () => {
      cancelled = true;
    };
  }, []);

  const describe = (log: AuditLog): string => {
    if (log.reason) return log.reason;
    if (log.detail && Object.keys(log.detail).length > 0) {
      return Object.entries(log.detail)
        .map(([k, v]) => `${k}: ${String(v)}`)
        .join(' · ');
    }
    return '—';
  };

  return (
    <div className="tactical-panel glass" style={{ padding: 24 }}>
      <h2 style={{ fontSize: 18, fontWeight: 900, marginBottom: 16, display: 'flex', alignItems: 'center', gap: 8, color: 'var(--text-primary)' }}>
        <ShieldAlert style={{ width: 20, height: 20, color: 'var(--primary)' }} />
        System Tactical Audit History
      </h2>

      {loading ? (
        <div style={{ padding: 20, color: 'var(--text-muted)' }}>Loading audit logs...</div>
      ) : error ? (
        <div style={{ padding: 20, color: 'var(--danger)' }}>AUDIT LOG UNAVAILABLE: {error}</div>
      ) : logs.length === 0 ? (
        <div style={{ padding: 20, color: 'var(--text-dim)' }}>NO AUDIT EVENTS RECORDED</div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          {logs.map((log) => (
            <div key={log.id} style={{ padding: 14, background: 'var(--input-bg)', border: '1px solid var(--border)', borderRadius: 12 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 4, gap: 8 }}>
                <span style={{ fontSize: 11, fontWeight: 900, color: 'var(--primary)', letterSpacing: 0.5 }}>
                  {log.action}
                  {log.from_tier && log.to_tier ? (
                    <span style={{ color: 'var(--warning)', display: 'inline-flex', alignItems: 'center', gap: 4, marginLeft: 8 }}>
                      {log.from_tier} <ArrowRight size={10} /> {log.to_tier}
                    </span>
                  ) : null}
                </span>
                <span style={{ fontSize: 10, color: 'var(--text-muted)', display: 'flex', alignItems: 'center', gap: 4, whiteSpace: 'nowrap' }}>
                  <Clock size={12} /> {log.created_at ? new Date(log.created_at).toLocaleString() : 'N/A'}
                </span>
              </div>
              <p style={{ fontSize: 13, color: 'var(--text-primary)', margin: '0 0 4px' }}>{describe(log)}</p>
              <div style={{ fontSize: 10, color: 'var(--text-muted)' }}>
                BY {log.actor || 'SYSTEM'}
                {log.alert_id ? ` · INCIDENT ${log.alert_id}` : ''}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
