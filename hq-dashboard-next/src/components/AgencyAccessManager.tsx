'use client';
import { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import { Shield, Plus, Trash2, RefreshCw, Loader2, Eye, EyeOff } from 'lucide-react';

const AGENCIES = [
  { code: 'POLICE', label: 'Nigeria Police Force', icon: '🚔' },
  { code: 'ARMY', label: 'Nigerian Army', icon: '🪖' },
  { code: 'DSS', label: 'Dept. of State Services', icon: '🕵️' },
  { code: 'NSCDC', label: 'NSCDC', icon: '🛡️' },
  { code: 'FRSC', label: 'Federal Road Safety Corps', icon: '🚨' },
  { code: 'AMOTEKUN', label: 'Operation Amotekun', icon: '🦁' },
];

interface LiaisonUser {
  id: string;
  full_name: string;
  role: string;
  agency: string;
  created_at: string;
}

/**
 * The read, with no state in it. Keeping the query separate from the setState
 * calls is what lets the mount path stop touching state synchronously.
 *
 * Returns `[]` rather than null on failure, preserving the original
 * behaviour — see the note in E2E_AUDIT_REPORT.md: an error here renders as
 * "No agency liaisons registered", which is a claim the panel cannot support.
 * Changing that is a UI decision, not a lint fix, so it is recorded rather
 * than smuggled in here.
 */
async function loadLiaisons(): Promise<LiaisonUser[]> {
  const { data } = await supabase
    .from('profiles')
    .select('id, full_name, role, agency, created_at')
    .like('role', '%_LIAISON%')
    .order('created_at', { ascending: false });
  return (data as LiaisonUser[]) || [];
}

export default function AgencyAccessManager() {
  const [liaisons, setLiaisons] = useState<LiaisonUser[]>([]);
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [form, setForm] = useState({ email: '', password: '', full_name: '', agency: 'POLICE' });
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');
  const [showPassword, setShowPassword] = useState(false);

  // The initial load. `loading` already starts true, so the old
  // `setLoading(true)` in the fetch was redundant on mount and was what made
  // this a set-state-in-effect — it ran synchronously as the effect body.
  // `cancelled` also stops a setState landing after the operator navigates
  // away mid-request.
  useEffect(() => {
    let cancelled = false;
    void (async () => {
      const rows = await loadLiaisons();
      if (cancelled) return;
      setLiaisons(rows);
      setLoading(false);
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  // Called from clicks, never from an effect, so setting state up front is
  // fine here — and it is what tells the operator the list is re-reading.
  const fetchLiaisons = async () => {
    setLoading(true);
    setLiaisons(await loadLiaisons());
    setLoading(false);
  };

  const createLiaison = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!form.email || !form.password || !form.full_name) {
      setError('All fields are required');
      return;
    }
    setSaving(true);
    setError('');
    setSuccess('');

    try {
      // Create Supabase auth user via admin API (requires service role)
      // Since we're on client side, we use a workaround: sign up then update profile
      const { data: signUpData, error: signUpErr } = await supabase.auth.signUp({
        email: form.email,
        password: form.password,
        options: {
          data: {
            full_name: form.full_name,
            role: `${form.agency}_LIAISON`,
          },
        },
      });

      if (signUpErr) throw signUpErr;

      const newUserId = signUpData.user?.id;
      if (!newUserId) throw new Error('User creation failed — no ID returned');

      // Upsert profile with agency and role
      await supabase.from('profiles').upsert({
        id: newUserId,
        full_name: form.full_name,
        role: `${form.agency}_LIAISON`,
        agency: form.agency,
        created_at: new Date().toISOString(),
      }, { onConflict: 'id' });

      setSuccess(`✓ ${form.full_name} created as ${form.agency} Liaison. They can now log in with their credentials.`);
      setForm({ email: '', password: '', full_name: '', agency: 'POLICE' });
      setShowForm(false);
      fetchLiaisons();
    } catch (err: any) {
      setError(err?.message || 'Failed to create liaison account');
    } finally {
      setSaving(false);
    }
  };

  const revokeLiaison = async (id: string, name: string) => {
    if (!confirm(`Revoke portal access for ${name}? Their account will be deactivated.`)) return;
    await supabase.from('profiles').update({ role: 'SUSPENDED', agency: null }).eq('id', id);
    fetchLiaisons();
  };

  const agencyInfo = (code: string) => AGENCIES.find(a => a.code === code);

  return (
    <div style={{ padding: 24, maxWidth: 700 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 20 }}>
        <h3 style={{ fontSize: 15, fontWeight: 900, color: 'var(--text-primary)', fontFamily: "var(--font-outfit), sans-serif", margin: 0, display: 'flex', alignItems: 'center', gap: 8 }}>
          <Shield size={18} style={{ color: 'var(--primary)' }} />
          Agency Liaison Access Control
        </h3>
        <div style={{ display: 'flex', gap: 8 }}>
          <button onClick={fetchLiaisons} style={{ background: 'none', border: '1px solid var(--border)', borderRadius: 8, padding: '6px 10px', cursor: 'pointer', color: 'var(--text-muted)' }}>
            <RefreshCw size={14} />
          </button>
          <button
            onClick={() => { setShowForm(!showForm); setError(''); setSuccess(''); }}
            style={{
              padding: '8px 16px', borderRadius: 8, border: '1px solid var(--primary)',
              background: 'var(--primary-dim)', color: 'var(--primary)', fontWeight: 700,
              fontSize: 12, cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 6,
            }}
          >
            <Plus size={14} /> GRANT ACCESS
          </button>
        </div>
      </div>

      {/* Success / Error */}
      {success && <div style={{ padding: 12, background: '#22c55e22', border: '1px solid #22c55e', borderRadius: 8, color: '#22c55e', fontSize: 12, marginBottom: 16 }}>{success}</div>}
      {error && <div style={{ padding: 12, background: '#ef444422', border: '1px solid #ef4444', borderRadius: 8, color: '#ef4444', fontSize: 12, marginBottom: 16 }}>{error}</div>}

      {/* Create form */}
      {showForm && (
        <div style={{ padding: 20, background: 'var(--surface)', border: '1px solid var(--primary)', borderRadius: 12, marginBottom: 24 }}>
          <h4 style={{ fontSize: 13, fontWeight: 900, color: 'var(--text-primary)', marginBottom: 16 }}>New Agency Liaison Account</h4>
          <form onSubmit={createLiaison} style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
              <div>
                <label style={{ fontSize: 11, fontWeight: 700, color: 'var(--text-muted)', display: 'block', marginBottom: 4 }}>FULL NAME *</label>
                <input value={form.full_name} onChange={e => setForm({ ...form, full_name: e.target.value })} placeholder="e.g. DSP Audu Ibrahim"
                  style={{ width: '100%', padding: '9px 12px', background: 'var(--input-bg)', border: '1px solid var(--border)', borderRadius: 8, color: 'var(--text-primary)', fontSize: 12, boxSizing: 'border-box' }} />
              </div>
              <div>
                <label style={{ fontSize: 11, fontWeight: 700, color: 'var(--text-muted)', display: 'block', marginBottom: 4 }}>AGENCY *</label>
                <select value={form.agency} onChange={e => setForm({ ...form, agency: e.target.value })}
                  style={{ width: '100%', padding: '9px 12px', background: 'var(--input-bg)', border: '1px solid var(--border)', borderRadius: 8, color: 'var(--text-primary)', fontSize: 12 }}>
                  {AGENCIES.map(a => <option key={a.code} value={a.code}>{a.icon} {a.label}</option>)}
                </select>
              </div>
            </div>
            <div>
              <label style={{ fontSize: 11, fontWeight: 700, color: 'var(--text-muted)', display: 'block', marginBottom: 4 }}>EMAIL ADDRESS *</label>
              <input type="email" value={form.email} onChange={e => setForm({ ...form, email: e.target.value })} placeholder="liaison@agency.gov.ng"
                style={{ width: '100%', padding: '9px 12px', background: 'var(--input-bg)', border: '1px solid var(--border)', borderRadius: 8, color: 'var(--text-primary)', fontSize: 12, boxSizing: 'border-box' }} />
            </div>
            <div style={{ position: 'relative' }}>
              <label style={{ fontSize: 11, fontWeight: 700, color: 'var(--text-muted)', display: 'block', marginBottom: 4 }}>TEMPORARY PASSWORD *</label>
              <input type={showPassword ? 'text' : 'password'} value={form.password} onChange={e => setForm({ ...form, password: e.target.value })} placeholder="Min. 8 characters"
                style={{ width: '100%', padding: '9px 40px 9px 12px', background: 'var(--input-bg)', border: '1px solid var(--border)', borderRadius: 8, color: 'var(--text-primary)', fontSize: 12, boxSizing: 'border-box' }} />
              <button type="button" onClick={() => setShowPassword(!showPassword)}
                style={{ position: 'absolute', right: 10, top: 28, background: 'none', border: 'none', cursor: 'pointer', color: 'var(--text-muted)' }}>
                {showPassword ? <EyeOff size={14} /> : <Eye size={14} />}
              </button>
            </div>
            <div style={{ display: 'flex', gap: 10 }}>
              <button type="button" onClick={() => setShowForm(false)} style={{ flex: 1, padding: '9px', borderRadius: 8, border: '1px solid var(--border)', background: 'transparent', color: 'var(--text-muted)', cursor: 'pointer', fontWeight: 700 }}>CANCEL</button>
              <button type="submit" disabled={saving} style={{ flex: 2, padding: '9px', borderRadius: 8, border: '1px solid var(--primary)', background: 'var(--primary)', color: 'white', fontWeight: 700, cursor: saving ? 'not-allowed' : 'pointer', opacity: saving ? 0.7 : 1, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6, fontSize: 12 }}>
                {saving ? <><Loader2 size={13} style={{ animation: 'spin 1s linear infinite' }} /> Creating...</> : <><Plus size={13} /> Create Liaison Account</>}
              </button>
            </div>
          </form>
        </div>
      )}

      {/* Liaisons list */}
      {loading ? (
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, color: 'var(--text-muted)', fontSize: 13 }}>
          <Loader2 size={16} style={{ animation: 'spin 1s linear infinite' }} /> Loading liaison accounts...
        </div>
      ) : liaisons.length === 0 ? (
        <div style={{ textAlign: 'center', padding: 40, color: 'var(--text-muted)' }}>
          <Shield size={36} style={{ margin: '0 auto 12px', opacity: 0.3 }} />
          <div style={{ fontSize: 13, fontWeight: 600 }}>No agency liaisons registered</div>
          <div style={{ fontSize: 11, marginTop: 4 }}>Click &ldquo;GRANT ACCESS&rdquo; to create a liaison account</div>
        </div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          {liaisons.map(liaison => {
            const agency = agencyInfo(liaison.agency);
            return (
              <div key={liaison.id} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '12px 16px', background: 'var(--surface)', border: '1px solid var(--border)', borderRadius: 10 }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                  <span style={{ fontSize: 20 }}>{agency?.icon || '🏛️'}</span>
                  <div>
                    <div style={{ fontSize: 13, fontWeight: 700, color: 'var(--text-primary)' }}>{liaison.full_name}</div>
                    <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>{agency?.label || liaison.agency} · {liaison.role}</div>
                  </div>
                </div>
                <button
                  onClick={() => revokeLiaison(liaison.id, liaison.full_name)}
                  style={{ padding: '6px 12px', borderRadius: 6, border: '1px solid #ef4444', background: '#ef444422', color: '#ef4444', fontWeight: 700, fontSize: 11, cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 4 }}
                >
                  <Trash2 size={12} /> REVOKE
                </button>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
