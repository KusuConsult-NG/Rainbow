'use client';
import { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import { ShieldAlert, Clock } from 'lucide-react';

interface AuditLog {
  id: string;
  sender_name?: string;
  sender_role?: string;
  message?: string;
  created_at?: string;
}

export default function AuditLogs() {
  const [logs, setLogs] = useState<AuditLog[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const fetchLogs = async () => {
      const { data } = await supabase.from('chat_messages').select('*').order('created_at', { ascending: false }).limit(50);
      setLogs((data || []) as AuditLog[]);
      setLoading(false);
    };

    fetchLogs();
  }, []);

  return (
    <div className="tactical-panel glass" style={{ padding: 24 }}>
      <h2 style={{ fontSize: 18, fontWeight: 900, marginBottom: 16, display: 'flex', alignItems: 'center', gap: 8, color: 'var(--text-primary)' }}>
        <ShieldAlert style={{ width: 20, height: 20, color: 'var(--primary)' }} />
        System Tactical Audit History
      </h2>

      {loading ? (
        <div style={{ padding: 20, color: 'var(--text-muted)' }}>Loading audit logs...</div>
      ) : logs.length === 0 ? (
        <div style={{ padding: 20, color: 'var(--text-dim)' }}>NO AUDIT EVENTS RECORDED</div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          {logs.map((log) => (
            <div key={log.id} style={{ padding: 14, background: 'var(--input-bg)', border: '1px solid var(--border)', borderRadius: 12 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 4 }}>
                <span style={{ fontSize: 11, fontWeight: 900, color: 'var(--primary)' }}>{log.sender_name || 'System'} ({log.sender_role || 'HQ'})</span>
                <span style={{ fontSize: 10, color: 'var(--text-muted)', display: 'flex', alignItems: 'center', gap: 4 }}>
                  <Clock size={12} /> {log.created_at ? new Date(log.created_at).toLocaleTimeString() : 'N/A'}
                </span>
              </div>
              <p style={{ fontSize: 13, color: 'var(--text-primary)' }}>{log.message}</p>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
