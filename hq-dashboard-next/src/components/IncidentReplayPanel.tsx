'use client';
import { useState, useEffect } from 'react';
import { supabase } from '../lib/supabase';
import { Clock, ShieldAlert, Radio, CheckCircle2, MessageSquare, AlertTriangle } from 'lucide-react';

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
            actor: alert.reported_by || alert.reportedBy || 'Citizen',
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
              actor: d.sender_name || 'Responder',
              role: d.sender_role || 'AGENT',
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
  }, [alertId]);

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
    </div>
  );
}
