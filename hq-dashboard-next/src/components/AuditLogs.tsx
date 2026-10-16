'use client';

/**
 * What was actually DONE to incidents.
 *
 * ## What this showed before
 *
 * `chat_messages` — the private conversations between dispatchers and responders
 * — under the heading "System Tactical Audit History". It contained no action
 * anybody had taken: not a dispatch, not an escalation, not a resolution, not a
 * classification applied, not a report marked false. Every one of those is
 * recorded in `alerts.escalation_log`, and none of them appeared here.
 *
 * PR #2 suggested reading `alert_timeline` instead. That table does not exist in
 * any migration, so the suggested fix would have produced a permanently empty
 * screen — which for an audit log is worse than the wrong content, because an
 * empty audit log reads as "nothing has happened".
 *
 * `audit_trail()` (migration 20261015000000) flattens the real log. It is
 * SECURITY INVOKER, so the same rule that scopes incidents scopes their history —
 * including keeping complaints against security personnel out of it.
 *
 * ## And it did not check for failure
 *
 * `const { data } = await ...` with no error check, rendering
 * "NO AUDIT EVENTS RECORDED" when `data` came back null. For an audit log that is
 * not an empty state, it is an assertion that nothing was done — the same class
 * of lie as a feed saying ALL SECTORS CLEAR on a query nobody read.
 */

import { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import { stampLabel } from '@/lib/incident-timeline';
import { AlertTriangle, ShieldAlert, Clock } from 'lucide-react';

interface AuditEntry {
  alert_id: string;
  reference: string;
  incident: string | null;
  at: string;
  action: string;
  actor: string;
  detail: string;
}

export default function AuditLogs() {
  const [logs, setLogs] = useState<AuditEntry[]>([]);
  const [loading, setLoading] = useState(true);
  /** Non-null when the last read FAILED. Never "nothing was done". */
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    const fetchLogs = async () => {
      const { data, error: err } = await supabase.rpc('audit_trail', { p_limit: 100 });
      if (cancelled) return;
      if (err) {
        console.error('[AUDIT_TRAIL_ERR]', err);
        setError(err.message || 'The audit trail could not be read.');
        setLoading(false);
        return;
      }
      setError(null);
      setLogs((data ?? []) as AuditEntry[]);
      setLoading(false);
    };

    void fetchLogs();
    return () => { cancelled = true; };
  }, []);

  return (
    <div className="tactical-panel glass" style={{ padding: 24 }}>
      <h2 style={{ fontSize: 18, fontWeight: 900, marginBottom: 16, display: 'flex', alignItems: 'center', gap: 8, color: 'var(--text-primary)' }}>
        <ShieldAlert style={{ width: 20, height: 20, color: 'var(--primary)' }} />
        System Tactical Audit History
      </h2>

      {loading ? (
        <div style={{ padding: 20, color: 'var(--text-muted)' }}>Loading the audit trail...</div>
      ) : error ? (
        /* NOT "nothing recorded". A refused read says nothing about whether
           anything was done, and for an audit log those are opposite claims. */
        <div role="alert" style={{ padding: 20, border: '1px solid var(--duress)', borderRadius: 12 }}>
          <div style={{ fontSize: 12, fontWeight: 900, color: 'var(--duress)', display: 'flex', alignItems: 'center', gap: 6 }}>
            <AlertTriangle size={14} /> AUDIT TRAIL UNAVAILABLE
          </div>
          <p style={{ fontSize: 11.5, color: 'var(--text-muted)', margin: '6px 0 0' }}>
            The trail could not be read. This does not mean nothing was done.
          </p>
          <p style={{ fontSize: 10, color: 'var(--text-dim)', margin: '6px 0 0', fontFamily: 'monospace' }}>
            {error}
          </p>
        </div>
      ) : logs.length === 0 ? (
        <div style={{ padding: 20, color: 'var(--text-dim)' }}>
          NO RECORDED ACTIONS ON THE INCIDENTS YOU CAN SEE
        </div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          {logs.map((log, i) => (
            <div
              key={`${log.alert_id}-${log.at}-${i}`}
              style={{ padding: 14, background: 'var(--input-bg)', border: '1px solid var(--border)', borderRadius: 12 }}
            >
              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 4, gap: 8 }}>
                <span style={{ fontSize: 11, fontWeight: 900, color: 'var(--primary)' }}>
                  {log.action} · {log.actor}
                </span>
                <span style={{ fontSize: 10, color: 'var(--text-muted)', display: 'flex', alignItems: 'center', gap: 4, flexShrink: 0 }}>
                  {/* `audit_trail()` coalesces an entry's time down to the
                      incident's own, so this is normally set — but the wording
                      for a time nobody recorded belongs in one place, and a
                      screen that prints "Invalid Date" reads as a broken
                      console rather than as a gap in the record. */}
                  <Clock size={12} /> {stampLabel(log.at, 'full')}
                </span>
              </div>
              <p style={{ fontSize: 12.5, color: 'var(--text-primary)', margin: 0 }}>
                {log.incident ?? 'Incident'} · <span style={{ fontFamily: 'monospace' }}>{log.reference}</span>
              </p>
              {log.detail && (
                <p style={{ fontSize: 11.5, color: 'var(--text-secondary)', margin: '4px 0 0' }}>{log.detail}</p>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
