'use client';
import { useState, useEffect, useCallback } from 'react';
import { supabase } from '../lib/supabase';
import { sendChatMessage } from '../lib/alert-actions';
import { Clock, ShieldAlert, Radio, CheckCircle2, MessageSquare, AlertTriangle, Send } from 'lucide-react';

interface TimelineEvent {
  id?: string;
  type: 'INITIAL_REPORT' | 'DISPATCH' | 'ESCALATION' | 'RESOLUTION' | 'COMMUNICATION';
  actor: string;
  role: string;
  timestamp: string;
  notes?: string;
}

export default function IncidentReplayPanel({ alertId }: { alertId: string }) {
  const [events, setEvents] = useState<TimelineEvent[]>([]);
  const [loading, setLoading] = useState(true);
  const [draft, setDraft] = useState('');
  const [sending, setSending] = useState(false);
  const [sendError, setSendError] = useState<string | null>(null);
  const [reload, setReload] = useState(0);

  useEffect(() => {
    if (!alertId) return;

    const fetchUnifiedTimeline = async () => {
      setLoading(true);
      const combined: TimelineEvent[] = [];

      try {
        // 1. Fetch Alert record for core lifecycle events
        const { data: alert } = await supabase
          .from('alerts')
          .select('*')
          .eq('id', alertId)
          .maybeSingle();

        if (alert) {
          // Initial creation event
          combined.push({
            id: `create-${alert.id}`,
            type: 'INITIAL_REPORT',
            actor: alert.reported_by || 'Citizen',  // `reportedBy` is not a column; the fallback was dead
            role: 'CITIZEN',
            timestamp: alert.created_at || new Date().toISOString(),
            notes: `Alert initiated: ${alert.type || 'EMERGENCY'}. Details: ${alert.description || 'No description'}`,
          });

          // Dispatch / Escalation / Summary log parsed from ai_summary
          if (alert.ai_summary) {
            const summaryLines = alert.ai_summary.split('\n');
            summaryLines.forEach((line: string, idx: number) => {
              if (line.includes('[MULTI-UNIT DISPATCH]')) {
                combined.push({
                  id: `dispatch-${idx}`,
                  type: 'DISPATCH',
                  actor: 'Command Center',
                  role: 'COMMAND',
                  timestamp: alert.updated_at || alert.created_at,
                  notes: line,
                });
              } else if (line.includes('[ESCALATED TO') || line.includes('[COMMAND ESCALATION]')) {
                combined.push({
                  id: `escalate-${idx}`,
                  type: 'ESCALATION',
                  actor: 'Tactical Command',
                  role: 'COMMAND',
                  timestamp: alert.updated_at || alert.created_at,
                  notes: line,
                });
              }
            });
          }

          // The handset left while this was open. On the timeline because the
          // question a review asks is "when did we lose the app", and a gap in
          // the track cannot answer it.
          if (alert.device_signed_out_at) {
            combined.push({
              id: `signout-${alert.id}`,
              type: 'ESCALATION',
              actor: 'Reporting handset',
              role: 'DEVICE',
              timestamp: alert.device_signed_out_at,
              notes: 'Signed out while this incident was open. Location '
                + 'tracking continued; the app did not.',
            });
          }

          // Resolution event
          if (alert.status === 'RESOLVED' || alert.resolved_at) {
            combined.push({
              id: `resolve-${alert.id}`,
              type: 'RESOLUTION',
              actor: alert.resolved_by || 'Field Commander',
              role: 'OFFICER',
              timestamp: alert.resolved_at || alert.updated_at || new Date().toISOString(),
              notes: `Incident marked as RESOLVED and archived.`,
            });
          }
        }

        // 2. Fetch Chat Messages for tactical communication events
        const { data: chatData } = await supabase
          .from('chat_messages')
          .select('*')
          .eq('alert_id', alertId)
          .order('created_at', { ascending: true });

        if (chatData) {
          chatData.forEach(d => {
            combined.push({
              id: d.id,
              type: 'COMMUNICATION',
              // A replay is evidence. It used to name an unattributed message
              // as from 'Responder' with role 'AGENT' — two facts about an
              // author nobody recorded, on the screen whose whole purpose is
              // saying who did what (T-32).
              actor: d.sender_name || 'UNKNOWN',
              role: d.sender_role || 'UNKNOWN',
              timestamp: d.created_at,
              notes: d.message,
            });
          });
        }

        // 3. Sort all events chronologically
        combined.sort((a, b) => new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime());
        setEvents(combined);
      } catch (err) {
        console.error('[REPLAY_ERR] Failed to load replay timeline:', err);
      } finally {
        setLoading(false);
      }
    };

    fetchUnifiedTimeline();
  }, [alertId, reload]);

  // THE DISPATCHER'S REPLY.
  //
  // This panel already read `chat_messages` and rendered each one as a
  // COMMUNICATION event, so the console could WATCH a conversation it had no
  // way to join. The citizen's screen in the mobile app is literally titled
  // DISPATCHER CHAT; until now the dispatcher was the one participant who
  // could not speak.
  const send = useCallback(async () => {
    const text = draft.trim();
    if (!text || sending) return;
    setSending(true);
    setSendError(null);

    const { data: { user } } = await supabase.auth.getUser();
    let name = user?.email ?? 'HQ DISPATCH';
    let role = 'HQ_COMMAND';
    if (user?.id) {
      const { data: profile } = await supabase
        .from('profiles')
        .select('full_name, role')
        .eq('id', user.id)
        .maybeSingle();
      if (profile?.full_name) name = profile.full_name as string;
      if (profile?.role) role = profile.role as string;
    }

    const res = await sendChatMessage(alertId, text, {
      id: user?.id,
      email: user?.email,
      name,
      role,
    });
    setSending(false);
    if (res.ok) {
      setDraft('');
      setReload(n => n + 1);
    } else {
      // Never clear the draft on failure. The mobile screens used to do
      // exactly that and the message simply vanished.
      setSendError(res.error);
    }
  }, [alertId, draft, sending]);

  const getEventIcon = (type: string) => {
    switch (type) {
      case 'INITIAL_REPORT': return <ShieldAlert size={14} color="var(--danger)" />;
      case 'DISPATCH': return <Radio size={14} color="var(--primary)" />;
      case 'ESCALATION': return <AlertTriangle size={14} color="var(--warning)" />;
      case 'RESOLUTION': return <CheckCircle2 size={14} color="var(--success)" />;
      default: return <MessageSquare size={14} color="var(--accent)" />;
    }
  };

  return (
    <div className="tactical-panel glass" style={{ padding: 20 }}>
      <h3 style={{ fontSize: 14, fontWeight: 900, marginBottom: 16, display: 'flex', alignItems: 'center', gap: 8, color: 'var(--text-primary)' }}>
        <Clock size={16} style={{ color: 'var(--primary)' }} /> Incident Replay Log ({events.length})
      </h3>

      {loading ? (
        <p style={{ fontSize: 12, color: 'var(--text-muted)' }}>Loading timeline events...</p>
      ) : events.length === 0 ? (
        <p style={{ fontSize: 12, color: 'var(--text-muted)' }}>No recorded timeline events for this alert.</p>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          {events.map((e, idx) => (
            <div 
              key={e.id || idx} 
              style={{ 
                padding: 12, 
                background: 'var(--input-bg)', 
                border: '1px solid var(--border)', 
                borderRadius: 10,
                display: 'flex',
                flexDirection: 'column',
                gap: 4
              }}
            >
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                <span style={{ fontSize: 11, fontWeight: 900, color: 'var(--primary)', display: 'flex', alignItems: 'center', gap: 6 }}>
                  {getEventIcon(e.type)}
                  [{new Date(e.timestamp).toLocaleTimeString()}] {e.actor} ({e.role})
                </span>
                <span style={{ fontSize: 9, fontWeight: 800, color: 'var(--text-muted)', letterSpacing: 0.5 }}>
                  {e.type}
                </span>
              </div>
              <p style={{ fontSize: 12, color: 'var(--text-primary)', margin: 0, lineHeight: 1.4 }}>
                {e.notes}
              </p>
            </div>
          ))}
        </div>
      )}

      <div style={{ display: 'flex', flexDirection: 'column', gap: 6, marginTop: 12 }}>
        <div style={{ display: 'flex', gap: 8 }}>
          <input
            value={draft}
            onChange={e => setDraft(e.target.value)}
            onKeyDown={e => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); void send(); } }}
            placeholder="Reply to this incident's channel…"
            aria-label="Reply to this incident's channel"
            disabled={sending}
            style={{
              flex: 1,
              padding: '10px 12px',
              background: 'var(--input-bg)',
              border: '1px solid var(--border)',
              borderRadius: 10,
              color: 'var(--text-primary)',
              fontSize: 12,
            }}
          />
          <button
            type="button"
            onClick={() => void send()}
            disabled={sending || !draft.trim()}
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: 6,
              padding: '10px 16px',
              background: draft.trim() ? 'var(--primary)' : 'var(--input-bg)',
              color: draft.trim() ? '#fff' : 'var(--text-muted)',
              border: '1px solid var(--border)',
              borderRadius: 10,
              fontSize: 11,
              fontWeight: 900,
              letterSpacing: 1,
              cursor: draft.trim() && !sending ? 'pointer' : 'default',
            }}
          >
            <Send size={13} />
            {sending ? 'SENDING…' : 'SEND'}
          </button>
        </div>
        {sendError && (
          <span role="alert" style={{ fontSize: 11, fontWeight: 700, color: 'var(--danger)' }}>
            NOT SENT — {sendError}
          </span>
        )}
      </div>
    </div>
  );
}
