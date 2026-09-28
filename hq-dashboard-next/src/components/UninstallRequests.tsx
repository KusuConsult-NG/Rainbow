'use client';
import { useState, useEffect } from 'react';
import { ShieldAlert, CheckCircle, XCircle, Loader2 } from 'lucide-react';
import { supabase } from '@/lib/supabase';

interface UninstallRequest {
  id: string;
  user_id: string;
  reason: string;
  remarks: string;
  status: string;
  submitted_at: string;
  profiles?: { full_name: string; role: string; geo_lga: string };
}

/**
 * The read, with no state in it.
 *
 * Keeping the query separate from the setState calls is what lets the mount
 * path stop touching state synchronously — see the effect below. Returns null
 * on failure so the caller can tell "the query failed" from "there are no
 * requests"; blanking the list on an error would claim there is nothing to
 * authorise when we simply could not ask.
 *
 * TWO THINGS THIS QUERY USED TO DO, BOTH OF WHICH PostgREST REFUSES OUTRIGHT —
 * found by rendering this panel in a browser, not by reading it:
 *
 *   .order('created_at')   — `uninstall_requests` has no `created_at`. Its
 *                            timestamp is `submitted_at`, and has been since
 *                            the table was created in phase1_foundation.sql.
 *   profiles(...)          — embedding needs a declared foreign key, and
 *                            `user_id` references `auth.users`, not
 *                            `public.profiles`. PostgREST answers PGRST200.
 *
 * Either one fails the whole query, so `loadRequests` returned null on every
 * call and the panel showed its "could not load" state permanently. The
 * fail-closed design above is why that was survivable rather than a lie — but
 * nobody could authorise an uninstall request through this console.
 *
 * The reporter's name is fetched separately rather than by adding a foreign
 * key: `user_id` is nullable ON DELETE SET NULL and rows may reference users
 * with no profile row, so a FK would be a migration that can fail on real data
 * to save one round trip.
 */
async function loadRequests(): Promise<UninstallRequest[] | null> {
  const { data, error } = await supabase
    .from('uninstall_requests')
    .select('*')
    .order('submitted_at', { ascending: false })
    .limit(50);
  if (error || !data) return null;

  const rows = data as UninstallRequest[];
  const ids = [...new Set(rows.map((r) => r.user_id).filter(Boolean))];
  if (ids.length === 0) return rows;

  const { data: people } = await supabase
    .from('profiles')
    .select('id, full_name, role, geo_lga')
    .in('id', ids);

  // A failed lookup must not empty the list: the request still needs
  // authorising whether or not we can name who made it.
  const byId = new Map((people ?? []).map((p) => [p.id, p]));
  return rows.map((r) => ({ ...r, profiles: byId.get(r.user_id) ?? undefined }));
}

export default function UninstallRequests() {
  const [requests, setRequests] = useState<UninstallRequest[]>([]);
  const [loading, setLoading] = useState(true);
  const [actionId, setActionId] = useState<string | null>(null);

  // The initial load. `loading` already starts true, so the old
  // `setLoading(true)` here was both redundant and the thing that made this a
  // set-state-in-effect: it ran synchronously as the effect body. Now nothing
  // touches state until the await resolves.
  //
  // `cancelled` matters beyond the lint: without it, an operator who navigates
  // away mid-request gets a setState on an unmounted component.
  useEffect(() => {
    let cancelled = false;
    void (async () => {
      const rows = await loadRequests();
      if (cancelled) return;
      if (rows) setRequests(rows);
      setLoading(false);
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  // Called from a click, not an effect, so setting state up front is fine here
  // — and it is what tells the operator the panel is re-reading.
  const refresh = async () => {
    setLoading(true);
    const rows = await loadRequests();
    if (rows) setRequests(rows);
    setLoading(false);
  };

  const handleAction = async (id: string, newStatus: 'APPROVED' | 'DENIED') => {
    setActionId(id);
    try {
      await supabase
        .from('uninstall_requests')
        .update({ status: newStatus, reviewed_at: new Date().toISOString() })
        .eq('id', id);
      // Re-read, always. Without it the row still shows PENDING and the same
      // authorisation gets issued twice.
      await refresh();
    } finally {
      setActionId(null);
    }
  };

  return (
    <div className="tactical-panel glass" style={{ padding: 24 }}>
      <h2 style={{ fontSize: 18, fontWeight: 900, marginBottom: 16, display: 'flex', alignItems: 'center', gap: 8, color: 'var(--text-primary)' }}>
        <ShieldAlert style={{ width: 20, height: 20, color: 'var(--primary)' }} />
        Staff App Removal Authorization Center
      </h2>

      {loading ? (
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, color: 'var(--text-muted)', fontSize: 13 }}>
          <Loader2 style={{ width: 16, height: 16, animation: 'spin 1s linear infinite' }} />
          Loading requests...
        </div>
      ) : requests.length === 0 ? (
        <p style={{ fontSize: 13, color: 'var(--text-muted)' }}>
          No pending uninstall verification requests from field personnel.
        </p>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          {requests.map((req) => (
            <div
              key={req.id}
              style={{
                padding: 16,
                background: 'var(--surface)',
                border: `1px solid ${req.status === 'PENDING' ? 'var(--warning)' : req.status === 'APPROVED' ? 'var(--success)' : 'var(--danger)'}`,
                borderRadius: 10,
              }}
            >
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 8 }}>
                <div>
                  <div style={{ fontWeight: 700, fontSize: 14, color: 'var(--text-primary)' }}>
                    {req.profiles?.full_name ?? req.user_id.substring(0, 8)}
                  </div>
                  <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>
                    {req.profiles?.role} · {req.profiles?.geo_lga ?? 'Unknown LGA'}
                  </div>
                </div>
                <span style={{
                  fontSize: 10,
                  fontWeight: 700,
                  padding: '3px 8px',
                  borderRadius: 4,
                  background: req.status === 'PENDING' ? 'rgba(245,158,11,0.2)' : req.status === 'APPROVED' ? 'rgba(16,185,129,0.2)' : 'rgba(239,68,68,0.2)',
                  color: req.status === 'PENDING' ? '#f59e0b' : req.status === 'APPROVED' ? '#10b981' : '#ef4444',
                }}>
                  {req.status}
                </span>
              </div>
              <div style={{ fontSize: 12, color: 'var(--text-secondary)', marginBottom: 4 }}>
                <strong>Reason:</strong> {req.reason}
              </div>
              {req.remarks && (
                <div style={{ fontSize: 12, color: 'var(--text-muted)', marginBottom: 8 }}>
                  <strong>Remarks:</strong> {req.remarks}
                </div>
              )}
              <div style={{ fontSize: 11, color: 'var(--text-muted)', marginBottom: req.status === 'PENDING' ? 12 : 0 }}>
                Submitted: {new Date(req.submitted_at).toLocaleString()}
              </div>
              {req.status === 'PENDING' && (
                <div style={{ display: 'flex', gap: 8 }}>
                  <button
                    onClick={() => handleAction(req.id, 'APPROVED')}
                    disabled={actionId === req.id}
                    className="btn-tactical"
                    style={{ flex: 1, padding: '8px 16px', background: 'rgba(16,185,129,0.2)', border: '1px solid #10b981', color: '#10b981', borderRadius: 6, fontSize: 12, fontWeight: 700, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 4, cursor: 'pointer' }}
                  >
                    <CheckCircle size={14} /> APPROVE
                  </button>
                  <button
                    onClick={() => handleAction(req.id, 'DENIED')}
                    disabled={actionId === req.id}
                    className="btn-tactical"
                    style={{ flex: 1, padding: '8px 16px', background: 'rgba(239,68,68,0.2)', border: '1px solid #ef4444', color: '#ef4444', borderRadius: 6, fontSize: 12, fontWeight: 700, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 4, cursor: 'pointer' }}
                  >
                    <XCircle size={14} /> DENY
                  </button>
                </div>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
