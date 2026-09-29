'use client';
import { useCallback, useEffect, useState } from 'react';
import { SignalZero, SignalHigh, RefreshCw, Check, Loader2 } from 'lucide-react';
import { supabase } from '@/lib/supabase';

/**
 * Handsets whose SMS channel has changed.
 *
 * In this system the phone number is the identity: it is what the account was
 * created with, what HQ rings back, and what the encrypted SMS fallback rides
 * on. When a SIM leaves a handset that channel dies and nothing else notices —
 * the alert queue keeps queueing, the sign-in code has nowhere to arrive, and
 * the operator finds out when they try to reach somebody.
 *
 * THIS IS A CHANNEL BOARD, NOT A SURVEILLANCE BOARD. The rows carry no
 * location and the table has no column for one. The holder is told on their
 * handset, in one line, every time a row is written. If a future change adds a
 * position to this table, it stops being this and becomes a movement log on
 * private citizens — which, in a conflict zone, is a reason not to install the
 * app at all.
 *
 * WHAT IT CANNOT SHOW. Android reports SIM present/absent and the NETWORK with
 * no permission; the values that identify a particular CARD have needed
 * READ_PRIVILEGED_PHONE_STATE since Android 10. So one MTN SIM swapped for
 * another MTN SIM never appears here. On iOS 16+ nothing appears at all — the
 * carrier API is deprecated and returns a placeholder. An operator who assumed
 * this board covered "SIM swap" would be wrong about the commonest swap there
 * is, so the panel says so on its face rather than in a comment.
 */

interface SimEvent {
  id: string;
  user_id: string;
  change: 'REMOVED' | 'INSERTED' | 'REPLACED';
  operator_name: string | null;
  operator_code: string | null;
  noticed_at: string;
  created_at: string;
  acknowledged_at: string | null;
}

interface Holder {
  full_name?: string;
  phone?: string;
  role?: string;
  badge_number?: string;
}

/** The words an operator reads. Composed HERE, from the code. */
export function describeSimEvent(event: Pick<SimEvent, 'change' | 'operator_name'>): string {
  switch (event.change) {
    case 'REMOVED':
      return 'SIM removed — SMS alerts and sign-in codes cannot reach this handset.';
    case 'REPLACED':
      return `Now on ${event.operator_name || 'a different network'} — the registered number may no longer reach this handset.`;
    case 'INSERTED':
      return `A ${event.operator_name || ''} SIM is in this handset again.`.replace('  ', ' ');
    default:
      return 'Unrecognised change.';
  }
}

/**
 * A compromised handset must not be able to write prose onto an operator's
 * screen, so `change` is the only thing read from the row and anything else is
 * refused rather than rendered.
 */
export function isRenderableChange(value: string): value is SimEvent['change'] {
  return value === 'REMOVED' || value === 'INSERTED' || value === 'REPLACED';
}

export function severityOf(change: SimEvent['change']): 'alert' | 'note' {
  // A removal and a replacement both mean the channel is down or has moved.
  // An insertion is the channel coming back, which is good news.
  return change === 'INSERTED' ? 'note' : 'alert';
}

function timeAgo(iso: string, now: Date = new Date()): string {
  const then = new Date(iso).getTime();
  if (Number.isNaN(then)) return '—';
  const mins = Math.round((now.getTime() - then) / 60000);
  if (mins < 1) return 'just now';
  if (mins < 60) return `${mins}m ago`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `${hours}h ${mins % 60}m ago`;
  return `${Math.floor(hours / 24)}d ago`;
}

/**
 * The read, with no state in it.
 *
 * Returns null on failure so the caller can tell "the query failed" from "no
 * handset has lost its channel" — blanking the board on an error would tell an
 * operator that every phone in the state is reachable when we simply could not
 * ask. Same shape as the uninstall panel, for the same reason.
 */
async function loadSimEvents(): Promise<
  { events: SimEvent[]; holders: Record<string, Holder> } | null
> {
  const { data, error } = await supabase
    .from('sim_channel_events')
    .select('id, user_id, change, operator_name, operator_code, noticed_at, created_at, acknowledged_at')
    .is('acknowledged_at', null)
    .order('created_at', { ascending: false })
    .limit(200);

  if (error) {
    console.error('[SIM_EVENTS] could not load:', error);
    return null;
  }

  const events = (data || []).filter((r) => isRenderableChange(r.change)) as SimEvent[];

  // The holder's name and number are fetched separately rather than by
  // embedding: an embed fails for any row whose profile has been deleted, and
  // losing the whole board because one holder left is not a trade worth
  // making.
  const ids = Array.from(new Set(events.map((r) => r.user_id)));
  const holders: Record<string, Holder> = {};
  if (ids.length > 0) {
    const { data: profiles } = await supabase
      .from('profiles')
      .select('id, full_name, phone, role, badge_number')
      .in('id', ids);
    (profiles || []).forEach((p: any) => { holders[p.id] = p; });
  }
  return { events, holders };
}

export default function SimChannelEvents() {
  const [events, setEvents] = useState<SimEvent[] | null>(null);
  const [holders, setHolders] = useState<Record<string, Holder>>({});
  const [failed, setFailed] = useState(false);
  const [busy, setBusy] = useState<string | null>(null);

  const load = useCallback(async () => {
    const result = await loadSimEvents();
    if (!result) {
      setFailed(true);
      return;
    }
    setFailed(false);
    setEvents(result.events);
    setHolders(result.holders);
  }, []);

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      const result = await loadSimEvents();
      if (cancelled) return;
      if (!result) {
        setFailed(true);
        return;
      }
      setEvents(result.events);
      setHolders(result.holders);
    })();

    const channel = supabase
      .channel('hq-sim-events')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'sim_channel_events' }, () => {
        void load();
      })
      .subscribe();
    return () => {
      cancelled = true;
      supabase.removeChannel(channel);
    };
  }, [load]);

  const acknowledge = async (id: string) => {
    setBusy(id);
    const { data: { user } } = await supabase.auth.getUser();
    const { error } = await supabase
      .from('sim_channel_events')
      .update({ acknowledged_at: new Date().toISOString(), acknowledged_by: user?.id ?? null })
      .eq('id', id);
    setBusy(null);
    if (error) {
      console.error('[SIM_EVENTS] could not acknowledge:', error);
      return;
    }
    void load();
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
      <div>
        <h2 style={{ fontSize: 18, fontWeight: 900, fontFamily: 'var(--font-outfit), sans-serif' }}>
          HANDSET SMS CHANNEL
        </h2>
        <p style={{ fontSize: 12, color: 'var(--text-muted)', marginTop: 6, maxWidth: 680, lineHeight: 1.6 }}>
          A handset reports here when its SIM is removed, replaced or put back. The SMS
          fallback and sign-in codes ride on that SIM, so a removal means this person can
          no longer be reached when the data network is down. No location is recorded, and
          the holder is told on their handset each time one of these is sent.
        </p>
        <p style={{ fontSize: 11, color: 'var(--text-dim)', marginTop: 8, maxWidth: 680, lineHeight: 1.6 }}>
          <strong>What this does not cover:</strong> a SIM swapped for another on the same
          network cannot be detected — the card&rsquo;s own identifiers need a permission
          Android reserves for system apps — and iPhones report nothing at all since iOS 16.
        </p>
      </div>

      {failed && (
        <div role="alert" style={{ padding: 16, borderRadius: 'var(--radius-card)', background: 'var(--duress-dim)', border: '1px solid var(--duress)', color: 'var(--duress)', fontSize: 12, fontWeight: 700 }}>
          This board could not be loaded, so it is not telling you anything right now — treat it as unknown, not as empty.
          <button onClick={load} style={{ marginLeft: 12, padding: '6px 12px', borderRadius: 8, border: '1px solid var(--duress)', background: 'transparent', color: 'var(--duress)', fontWeight: 800, fontSize: 11, cursor: 'pointer' }}>
            <RefreshCw size={11} style={{ verticalAlign: -1, marginRight: 4 }} />RETRY
          </button>
        </div>
      )}

      {events === null && !failed && (
        <p style={{ fontSize: 12, color: 'var(--text-muted)' }}>
          <Loader2 size={13} style={{ verticalAlign: -2, marginRight: 6, animation: 'spin 1s linear infinite' }} />
          Loading…
        </p>
      )}

      {events !== null && events.length === 0 && !failed && (
        <p style={{ fontSize: 12, color: 'var(--text-muted)' }}>
          Every handset that can report is reachable by SMS.
        </p>
      )}

      <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
        {(events || []).map((event) => {
          const holder = holders[event.user_id];
          const alert = severityOf(event.change) === 'alert';
          const colour = alert ? 'var(--duress)' : 'var(--success)';
          return (
            <div
              key={event.id}
              style={{
                display: 'flex',
                alignItems: 'flex-start',
                gap: 14,
                padding: 16,
                borderRadius: 'var(--radius-card)',
                background: 'var(--bg-card)',
                border: '1px solid var(--border)',
                borderLeft: `3px solid ${colour}`,
              }}
            >
              <div style={{ color: colour, flexShrink: 0, marginTop: 2 }}>
                {alert ? <SignalZero size={18} /> : <SignalHigh size={18} />}
              </div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ display: 'flex', alignItems: 'baseline', gap: 8, flexWrap: 'wrap' }}>
                  <strong style={{ fontSize: 13, fontWeight: 800 }}>
                    {holder?.full_name || `Profile ${event.user_id.slice(0, 8)} not loaded`}
                  </strong>
                  {holder?.badge_number && (
                    <span style={{ fontSize: 10, fontWeight: 800, color: 'var(--text-dim)' }}>
                      {holder.badge_number}
                    </span>
                  )}
                  <span style={{ fontSize: 10, fontWeight: 800, color: colour, letterSpacing: 0.6 }}>
                    {event.change}
                  </span>
                  <span style={{ fontSize: 10, color: 'var(--text-dim)', marginLeft: 'auto' }}>
                    {timeAgo(event.noticed_at)}
                  </span>
                </div>
                <p style={{ fontSize: 12, color: 'var(--text-muted)', margin: '6px 0 0', lineHeight: 1.5 }}>
                  {describeSimEvent(event)}
                </p>
                {holder?.phone && (
                  <p style={{ fontSize: 11, color: 'var(--text-dim)', margin: '4px 0 0' }}>
                    Registered number: {holder.phone}
                  </p>
                )}
              </div>
              <button
                onClick={() => acknowledge(event.id)}
                disabled={busy === event.id}
                style={{
                  flexShrink: 0,
                  padding: '7px 12px',
                  borderRadius: 'var(--radius-control)',
                  border: '1px solid var(--border)',
                  background: 'var(--input-bg)',
                  color: 'var(--text-secondary)',
                  fontWeight: 800,
                  fontSize: 11,
                  cursor: busy === event.id ? 'wait' : 'pointer',
                  display: 'flex',
                  alignItems: 'center',
                  gap: 5,
                }}
              >
                <Check size={12} />
                {busy === event.id ? 'SAVING…' : 'ACKNOWLEDGE'}
              </button>
            </div>
          );
        })}
      </div>
    </div>
  );
}
