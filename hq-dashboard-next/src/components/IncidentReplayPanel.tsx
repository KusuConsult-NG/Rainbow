'use client';
import { useState, useEffect, useRef } from 'react';
import { collection, query, orderBy, onSnapshot } from 'firebase/firestore';
import { db } from '../lib/firebase';
import { Play, Pause, ChevronLeft, ChevronRight, RotateCcw, Clock } from 'lucide-react';

interface TimelineEvent {
  id?: string;
  type: string;
  actor: string;
  role: string;
  timestamp: string;
  reason?: string;
  notes?: string;
}

export default function IncidentReplayPanel({ alertId }: { alertId: string }) {
  const [events, setEvents] = useState<TimelineEvent[]>([]);
  const [currentIndex, setCurrentIndex] = useState(0);
  const [isPlaying, setIsPlaying] = useState(false);
  const timerRef = useRef<NodeJS.Timeout | null>(null);

  useEffect(() => {
    if (!alertId) return;

    const q = query(
      collection(db, 'alerts', alertId, 'timeline'),
      orderBy('timestamp', 'asc')
    );

    const unsubscribe = onSnapshot(q, (snap) => {
      const list = snap.docs.map(doc => ({
        id: doc.id,
        ...doc.data()
      })) as TimelineEvent[];
      
      setEvents(list);
      setCurrentIndex(list.length > 0 ? list.length - 1 : 0);
    });

    return () => {
      unsubscribe();
      if (timerRef.current) clearInterval(timerRef.current);
    };
  }, [alertId]);

  useEffect(() => {
    if (isPlaying) {
      timerRef.current = setInterval(() => {
        setCurrentIndex((prev) => {
          if (prev >= events.length - 1) {
            setIsPlaying(false);
            if (timerRef.current) clearInterval(timerRef.current);
            return prev;
          }
          return prev + 1;
        });
      }, 2500);
    } else {
      if (timerRef.current) {
        clearInterval(timerRef.current);
        timerRef.current = null;
      }
    }

    return () => {
      if (timerRef.current) clearInterval(timerRef.current);
    };
  }, [isPlaying, events.length]);

  const handlePlayPause = () => {
    if (currentIndex >= events.length - 1 && !isPlaying) {
      setCurrentIndex(0); // Reset to start if playing from end
    }
    setIsPlaying(!isPlaying);
  };

  const handleReset = () => {
    setCurrentIndex(0);
    setIsPlaying(false);
  };

  const handlePrev = () => {
    setIsPlaying(false);
    setCurrentIndex(prev => Math.max(0, prev - 1));
  };

  const handleNext = () => {
    setIsPlaying(false);
    setCurrentIndex(prev => Math.min(events.length - 1, prev + 1));
  };

  if (events.length === 0) {
    return (
      <div className="tactical-panel glass" style={{ padding: 24, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', height: '100%', gap: 12 }}>
        <Clock size={32} color="var(--text-muted)" />
        <span style={{ fontSize: 12, color: 'var(--text-muted)', fontWeight: 800 }}>NO REPLAY TIMELINE AVAILABLE</span>
      </div>
    );
  }

  const currentEvent = events[currentIndex];

  const getEventColor = (type: string) => {
    switch (type) {
      case 'CREATED':
      case 'AI_VOICE_REPORT':
        return 'var(--primary)';
      case 'DISPATCHED':
        return 'var(--warning)';
      case 'ACKNOWLEDGED':
      case 'ON_ROUTE':
        return 'var(--accent)';
      case 'ON_SITE':
        return 'var(--success)';
      case 'RESOLVED':
        return 'var(--success)';
      case 'SLA_BREACH_ALERT':
      case 'SLA_AUTO_ESCALATION':
        return 'var(--duress)';
      default:
        return 'var(--text-dim)';
    }
  };

  return (
    <div className="tactical-panel glass" style={{ padding: 24, display: 'flex', flexDirection: 'column', gap: 20, height: '100%' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <div>
          <h4 style={{ fontSize: 13, fontWeight: 900, letterSpacing: 1, textTransform: 'uppercase' }}>Incident Response Replay</h4>
          <span style={{ fontSize: 10, color: 'var(--text-muted)', fontWeight: 600 }}>Step-by-step operational timeline player</span>
        </div>
        <div style={{ display: 'flex', gap: 8 }}>
          <button onClick={handlePrev} disabled={currentIndex === 0} className="card-hover" style={{ background: 'var(--input-bg)', border: '1px solid var(--border)', color: 'var(--text-primary)', padding: 8, borderRadius: 8, cursor: 'pointer' }}>
            <ChevronLeft size={14} />
          </button>
          <button onClick={handlePlayPause} className="card-hover" style={{ background: 'var(--primary)', border: 'none', color: '#fff', padding: 8, borderRadius: 8, cursor: 'pointer', boxShadow: 'var(--primary-glow)' }}>
            {isPlaying ? <Pause size={14} /> : <Play size={14} />}
          </button>
          <button onClick={handleNext} disabled={currentIndex === events.length - 1} className="card-hover" style={{ background: 'var(--input-bg)', border: '1px solid var(--border)', color: 'var(--text-primary)', padding: 8, borderRadius: 8, cursor: 'pointer' }}>
            <ChevronRight size={14} />
          </button>
          <button onClick={handleReset} className="card-hover" style={{ background: 'var(--input-bg)', border: '1px solid var(--border)', color: 'var(--text-primary)', padding: 8, borderRadius: 8, cursor: 'pointer' }}>
            <RotateCcw size={14} />
          </button>
        </div>
      </div>

      {/* Progress Bar */}
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 9, fontWeight: 900, color: 'var(--text-muted)' }}>
          <span>STEP {currentIndex + 1} OF {events.length}</span>
          <span>{currentEvent ? new Date(currentEvent.timestamp).toLocaleTimeString() : ''}</span>
        </div>
        <div style={{ height: 6, background: 'var(--border)', borderRadius: 3, overflow: 'hidden' }}>
          <div style={{ height: '100%', background: 'var(--primary)', width: `${((currentIndex + 1) / events.length) * 100}%`, borderRadius: 3, transition: 'width 0.3s' }}></div>
        </div>
      </div>

      {/* Event Details Card */}
      {currentEvent && (
        <div className="glass" style={{ padding: 16, borderRadius: 12, borderLeft: `4px solid ${getEventColor(currentEvent.type)}`, background: 'rgba(255,255,255,0.02)', display: 'flex', flexDirection: 'column', gap: 12 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <span style={{ fontSize: 11, fontWeight: 900, color: getEventColor(currentEvent.type), letterSpacing: 1, textTransform: 'uppercase' }}>{currentEvent.type}</span>
            <span style={{ fontSize: 9, color: 'var(--text-muted)', fontWeight: 800 }}>{new Date(currentEvent.timestamp).toLocaleDateString()}</span>
          </div>
          <div>
            <div style={{ fontSize: 12, fontWeight: 800, color: 'var(--text-primary)' }}>{currentEvent.reason || 'State Change Triggered'}</div>
            {currentEvent.notes && (
              <p style={{ fontSize: 10, color: 'var(--text-muted)', marginTop: 4, lineHeight: 1.4 }}>{currentEvent.notes}</p>
            )}
          </div>
          <div style={{ display: 'flex', gap: 12, borderTop: '1px solid var(--border)', paddingTop: 10, fontSize: 9, fontWeight: 900, color: 'var(--text-muted)' }}>
            <div>ACTOR: <span style={{ color: 'var(--text-primary)' }}>{currentEvent.actor}</span></div>
            <div>ROLE: <span style={{ color: 'var(--text-primary)' }}>{currentEvent.role}</span></div>
          </div>
        </div>
      )}

      {/* Full Timeline List */}
      <div style={{ flex: 1, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 12, maxHeight: '200px' }}>
        {events.map((ev, i) => (
          <div key={i} onClick={() => setCurrentIndex(i)} style={{ display: 'flex', gap: 12, cursor: 'pointer', opacity: i <= currentIndex ? 1 : 0.4, transition: 'all 0.2s' }}>
            <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
              <div style={{ width: 8, height: 8, borderRadius: '50%', background: getEventColor(ev.type), boxShadow: i === currentIndex ? `0 0 8px ${getEventColor(ev.type)}` : 'none' }}></div>
              {i < events.length - 1 && <div style={{ width: 2, flex: 1, background: 'var(--border)', marginTop: 4 }}></div>}
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 2, paddingBottom: 12 }}>
              <span style={{ fontSize: 10, fontWeight: 800, color: i === currentIndex ? 'var(--text-primary)' : 'var(--text-muted)' }}>{ev.type}</span>
              <span style={{ fontSize: 8, color: 'var(--text-muted)' }}>{new Date(ev.timestamp).toLocaleTimeString()}</span>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
