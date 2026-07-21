'use client';
import { useState, useEffect } from 'react';
import { supabase } from '../lib/supabase';
import { Clock } from 'lucide-react';

interface TimelineEvent {
  id?: string;
  type: string;
  actor: string;
  role: string;
  timestamp: string;
  notes?: string;
}

export default function IncidentReplayPanel({ alertId }: { alertId: string }) {
  const [events, setEvents] = useState<TimelineEvent[]>([]);

  useEffect(() => {
    if (!alertId) return;

    const fetchTimeline = async () => {
      const { data } = await supabase.from('chat_messages').select('*').eq('alert_id', alertId).order('created_at', { ascending: true });
      if (data) {
        setEvents(data.map(d => ({
          id: d.id,
          type: 'COMMUNICATION',
          actor: d.sender_name || 'Unit',
          role: d.sender_role || 'AGENT',
          timestamp: d.created_at,
          notes: d.message,
        })));
      }
    };

    fetchTimeline();
  }, [alertId]);

  return (
    <div className="tactical-panel glass" style={{ padding: 20 }}>
      <h3 style={{ fontSize: 14, fontWeight: 900, marginBottom: 12, display: 'flex', alignItems: 'center', gap: 8, color: 'var(--text-primary)' }}>
        <Clock size={16} style={{ color: 'var(--primary)' }} /> Incident Replay Log ({events.length})
      </h3>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
        {events.map((e, idx) => (
          <div key={idx} style={{ padding: 10, background: 'var(--input-bg)', border: '1px solid var(--border)', borderRadius: 8 }}>
            <span style={{ fontSize: 10, fontWeight: 900, color: 'var(--primary)' }}>[{new Date(e.timestamp).toLocaleTimeString()}] {e.actor}</span>
            <p style={{ fontSize: 12, color: 'var(--text-primary)' }}>{e.notes}</p>
          </div>
        ))}
      </div>
    </div>
  );
}
