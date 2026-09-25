'use client';
import { useState, useEffect } from 'react';
import { supabase } from '../lib/supabase';
import { Clock, ShieldAlert, Radio, CheckCircle2, MessageSquare, AlertTriangle, MapPin, FileText } from 'lucide-react';

type EventType =
  | 'INITIAL_REPORT'
  | 'DISPATCH'
  | 'ESCALATION'
  | 'RESOLUTION'
  | 'COMMUNICATION'
  | 'MOVEMENT'
  | 'DEBRIEF';

interface TimelineEvent {
  id?: string;
  type: EventType;
  actor: string;
  role: string;
  timestamp: string;
  notes?: string;
}

// The engine records every lifecycle event in `alert_timeline` and stamps the
// status times on the alert itself. This panel used to reconstruct the timeline
// by string-matching bracketed tags inside the free-text `ai_summary` field,
// which missed anything the engine did and broke as soon as the wording moved.
const TIMELINE_KIND: Record<string, EventType> = {
  ALERT_CREATED: 'INITIAL_REPORT',
  DISPATCHED: 'DISPATCH',
  ASSIGNED: 'DISPATCH',
  ESCALATED: 'ESCALATION',
  AUTO_ESCALATED: 'ESCALATION',
  MANUAL_ESCALATION: 'ESCALATION',
  SLA_BREACH: 'ESCALATION',
  RESOLVED: 'RESOLUTION',
};

export default function IncidentReplayPanel({ alertId }: { alertId: string }) {
  const [events, setEvents] = useState<TimelineEvent[]>([]);
  const [trackPoints, setTrackPoints] = useState(0);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!alertId) return;
    let cancelled = false;

    const fetchUnifiedTimeline = async () => {
      setLoading(true);
      const combined: TimelineEvent[] = [];

      try {
        const [alertRes, timelineRes, chatRes, trackRes] = await Promise.all([
          supabase.from('alerts').select('*').eq('id', alertId).maybeSingle(),
          supabase
            .from('alert_timeline')
            .select('*')
            .eq('alert_id', alertId)
            .order('created_at', { ascending: true }),
          supabase
            .from('chat_messages')
            .select('*')
            .eq('alert_id', alertId)
            .order('created_at', { ascending: true }),
          supabase
            .from('telemetry_history')
            .select('*')
            .eq('alert_id', alertId)
            .order('recorded_at', { ascending: true }),
        ]);

        const alert = alertRes.data;

        if (alert) {
          combined.push({
            id: `create-${alert.id}`,
            type: 'INITIAL_REPORT',
            actor: alert.reported_by || 'Citizen',
            role: 'CITIZEN',
            timestamp: alert.created_at || new Date().toISOString(),
            notes: `Alert initiated: ${alert.type || 'EMERGENCY'}. ${alert.description || 'No description'}`,
          });

          // Status stamps, written by the database trigger. These cover rows
          // that predate the timeline table.
          const stamps: Array<[string | null, EventType, string]> = [
            [alert.dispatched_at, 'DISPATCH', 'Responder dispatched'],
            [alert.acknowledged_at, 'DISPATCH', 'Responder acknowledged'],
            [alert.escalated_at, 'ESCALATION', `Escalated to ${alert.assigned_tier || 'next tier'}`],
            [alert.sla_breached_at, 'ESCALATION', 'Response SLA breached'],
            [alert.resolved_at, 'RESOLUTION', 'Incident resolved and archived'],
          ];
          stamps.forEach(([at, type, label], idx) => {
            if (!at) return;
            combined.push({
              id: `stamp-${idx}-${alert.id}`,
              type,
              actor: type === 'RESOLUTION' ? alert.resolved_by || 'Field Commander' : 'Command Center',
              role: 'COMMAND',
              timestamp: at,
              notes: label,
            });
          });

          if (alert.debrief) {
            combined.push({
              id: `debrief-${alert.id}`,
              type: 'DEBRIEF',
              actor: alert.debrief_by || alert.resolved_by || 'Field Commander',
              role: 'OFFICER',
              timestamp: alert.debrief_at || alert.resolved_at || alert.updated_at,
              notes: alert.debrief,
            });
          }
        }

        (timelineRes.data || []).forEach((t) => {
          const tiers = t.from_tier && t.to_tier ? ` (${t.from_tier} → ${t.to_tier})` : '';
          combined.push({
            id: t.id,
            type: TIMELINE_KIND[t.event_type] || 'DISPATCH',
            actor: t.actor || 'SYSTEM',
            role: t.actor_role || 'SYSTEM',
            timestamp: t.created_at,
            notes: `${t.event_type}${tiers}${t.reason ? ` — ${t.reason}` : ''}${t.notes ? `. ${t.notes}` : ''}`,
          });
        });

        (chatRes.data || []).forEach((d) => {
          combined.push({
            id: d.id,
            type: 'COMMUNICATION',
            actor: d.sender_name || 'Responder',
            role: d.sender_role || 'AGENT',
            timestamp: d.created_at,
            notes: d.message,
          });
        });

        // The full track would flood the log, so only the points where the
        // responder's status changed are shown; the count carries the rest.
        const track = trackRes.data || [];
        let lastStatus: string | null = null;
        track.forEach((p) => {
          if (p.status === lastStatus) return;
          lastStatus = p.status;
          combined.push({
            id: `track-${p.id}`,
            type: 'MOVEMENT',
            actor: p.user_id || 'Responder',
            role: p.mode === 'sos' ? 'CITIZEN' : 'AGENT',
            timestamp: p.recorded_at,
            notes: `${p.status || 'POSITION'} at ${Number(p.latitude).toFixed(5)}, ${Number(p.longitude).toFixed(5)}${
              p.battery != null ? ` · battery ${p.battery}%` : ''
            }`,
          });
        });

        combined.sort((a, b) => new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime());

        if (cancelled) return;
        setTrackPoints(track.length);
        setEvents(combined);
      } catch (err) {
        console.error('[REPLAY_ERR] Failed to load replay timeline:', err);
      } finally {
        if (!cancelled) setLoading(false);
      }
    };

    fetchUnifiedTimeline();
    return () => {
      cancelled = true;
    };
  }, [alertId]);

  const getEventIcon = (type: string) => {
    switch (type) {
      case 'INITIAL_REPORT': return <ShieldAlert size={14} color="var(--danger)" />;
      case 'DISPATCH': return <Radio size={14} color="var(--primary)" />;
      case 'ESCALATION': return <AlertTriangle size={14} color="var(--warning)" />;
      case 'RESOLUTION': return <CheckCircle2 size={14} color="var(--success)" />;
      case 'MOVEMENT': return <MapPin size={14} color="var(--accent)" />;
      case 'DEBRIEF': return <FileText size={14} color="var(--success)" />;
      default: return <MessageSquare size={14} color="var(--accent)" />;
    }
  };

  return (
    <div className="tactical-panel glass" style={{ padding: 20 }}>
      <h3 style={{ fontSize: 14, fontWeight: 900, marginBottom: 16, display: 'flex', alignItems: 'center', gap: 8, color: 'var(--text-primary)' }}>
        <Clock size={16} style={{ color: 'var(--primary)' }} /> Incident Replay Log ({events.length})
      </h3>

      {trackPoints > 0 ? (
        <p style={{ fontSize: 11, color: 'var(--text-muted)', margin: '0 0 12px' }}>
          {trackPoints} position point{trackPoints === 1 ? '' : 's'} recorded for this incident.
        </p>
      ) : null}

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
