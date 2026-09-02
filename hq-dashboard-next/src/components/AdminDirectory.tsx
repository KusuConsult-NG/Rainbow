'use client';
import { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import { Users, UserPlus, Trash2, Loader2, RefreshCw, Shield } from 'lucide-react';
import { plateauTacticalMap, TacticalJurisdiction, TacticalWard, STATE_SECURITY_AGENCIES } from '@/lib/tactical_mapping';
import AgencyAccessManager from '@/components/AgencyAccessManager';


interface StaffRecord {
  id: string;
  email?: string;
  role?: string;
  agency?: string;
  full_name?: string;
  phone?: string;
  created_at?: string;
  geo_lga?: string;
  geo_ward?: string;
  geo_pu?: string;
}

const ROLES = [
  { value: 'HQ_COMMAND', label: 'Tactical HQ (Statewide)' },
  { value: 'LGA_COMMAND', label: 'LGA Sector Command' },
  { value: 'WARD_COMMAND', label: 'District / Sub-District Command' },
  { value: 'UNIT_COMMAND', label: 'Local Post Command' },
];

/**
 * The read, with no state in it. Returns null on failure so the caller leaves
 * the roster it already has rather than blanking it — an empty directory reads
 * as "no officers are provisioned", which is not what a failed query means.
 */
async function loadStaff(): Promise<StaffRecord[] | null> {
  try {
    const { data, error: err } = await supabase
      .from('profiles')
      .select('*')
      .order('created_at', { ascending: false });
    if (err) throw err;
    return (data || []) as StaffRecord[];
  } catch (e: any) {
    console.error('Failed to load profiles:', e);
    return null;
  }
}

export default function AdminDirectory() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [role, setRole] = useState('UNIT_COMMAND');
  const [agency, setAgency] = useState('RAINBOW');
  const [fullName, setFullName] = useState('');
  const [phone, setPhone] = useState('');

  const [selectedLga, setSelectedLga] = useState<TacticalJurisdiction | null>(null);
  const [selectedWard, setSelectedWard] = useState<TacticalWard | null>(null);
  const [selectedPu, setSelectedPu] = useState('');

  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [staff, setStaff] = useState<StaffRecord[]>([]);

  // The initial load. The old code called `fetchStaff()` as the effect body,
  // which made its setState a set-state-in-effect. `cancelled` also stops a
  // setState landing after the administrator navigates away mid-request.
  useEffect(() => {
    let cancelled = false;
    void (async () => {
      const rows = await loadStaff();
      if (!cancelled && rows) setStaff(rows);
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  // Called after a successful provision, not from an effect.
  const fetchStaff = async () => {
    const rows = await loadStaff();
    if (rows) setStaff(rows);
  };

  const handleCreateUser = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setError(null);
    setSuccess(null);

    try {
      const { data, error: signUpErr } = await supabase.auth.signUp({
        email,
        password,
        options: {
          data: {
            full_name: fullName,
            role,
            agency,
            phone,
            geo_lga: (selectedLga as any)?.name || 'STATEWIDE HQ',
            geo_ward: selectedWard?.name || 'N/A',
            geo_pu: selectedPu || 'N/A',
          },
        },
      });

      if (signUpErr) throw signUpErr;

      setSuccess(`Account registered successfully for ${email}`);
      setEmail('');
      setPassword('');
      setFullName('');
      setPhone('');
      fetchStaff();
    } catch (err: any) {
      setError(err.message || 'Failed to create user account');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 24 }}>
      <div className="tactical-panel glass" style={{ padding: 24 }}>
        <h2 style={{ fontSize: 18, fontWeight: 900, marginBottom: 16, display: 'flex', alignItems: 'center', gap: 8, color: 'var(--text-primary)' }}>
          <UserPlus style={{ width: 20, height: 20, color: 'var(--primary)' }} />
          Provision Tactical Officer Account
        </h2>

        {error && (
          <div style={{ padding: 12, background: 'var(--duress-dim)', border: '1px solid var(--duress)', borderRadius: 10, color: 'var(--duress)', marginBottom: 16, fontSize: 13 }}>
            {error}
          </div>
        )}

        {success && (
          <div style={{ padding: 12, background: 'var(--success-dim)', border: '1px solid var(--success)', borderRadius: 10, color: 'var(--success)', marginBottom: 16, fontSize: 13 }}>
            {success}
          </div>
        )}

        <form onSubmit={handleCreateUser} style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))', gap: 16 }}>
          <div>
            <label style={{ fontSize: 11, fontWeight: 700, color: 'var(--text-muted)', display: 'block', marginBottom: 6 }}>Full Name</label>
            <input
              type="text"
              required
              className="input-tactical"
              style={{ width: '100%' }}
              value={fullName}
              onChange={(e) => setFullName(e.target.value)}
              placeholder="Officer Name"
            />
          </div>

          <div>
            <label style={{ fontSize: 11, fontWeight: 700, color: 'var(--text-muted)', display: 'block', marginBottom: 6 }}>Email / Badge ID</label>
            <input
              type="email"
              required
              className="input-tactical"
              style={{ width: '100%' }}
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="officer@operationrainbow.plateau.gov.ng"
            />
          </div>

          <div>
            <label style={{ fontSize: 11, fontWeight: 700, color: 'var(--text-muted)', display: 'block', marginBottom: 6 }}>Password</label>
            <input
              type="password"
              required
              className="input-tactical"
              style={{ width: '100%' }}
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="••••••••"
            />
          </div>

          <div>
            <label style={{ fontSize: 11, fontWeight: 700, color: 'var(--text-muted)', display: 'block', marginBottom: 6 }}>Command Role</label>
            <select
              className="input-tactical"
              style={{ width: '100%' }}
              value={role}
              onChange={(e) => setRole(e.target.value)}
            >
              {ROLES.map((r) => (
                <option key={r.value} value={r.value}>
                  {r.label}
                </option>
              ))}
            </select>
          </div>

          <div>
            <label style={{ fontSize: 11, fontWeight: 700, color: 'var(--text-muted)', display: 'block', marginBottom: 6 }}>Security Agency Affiliation</label>
            <select
              className="input-tactical"
              style={{ width: '100%' }}
              value={agency}
              onChange={(e) => setAgency(e.target.value)}
            >
              {STATE_SECURITY_AGENCIES.map((a) => (
                <option key={a.id} value={a.id}>
                  {a.badge} {a.name} ({a.shortCode})
                </option>
              ))}
            </select>
          </div>

          <div style={{ gridColumn: '1 / -1', marginTop: 8 }}>
            <button
              type="submit"
              disabled={loading}
              className="btn-tactical btn-primary"
              style={{ width: '100%', padding: '14px' }}
            >
              {loading ? <Loader2 className="animate-spin" style={{ width: 16, height: 16 }} /> : 'Provision Security Personnel Account'}
            </button>
          </div>
        </form>
      </div>

      <div className="tactical-panel glass" style={{ padding: 24 }}>
        <h2 style={{ fontSize: 18, fontWeight: 900, marginBottom: 16, display: 'flex', alignItems: 'center', gap: 8, color: 'var(--text-primary)' }}>
          <Users style={{ width: 20, height: 20, color: 'var(--primary)' }} />
          Active Multi-Agency Personnel Directory ({staff.length})
        </h2>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          {staff.map((s) => {
            const ag = STATE_SECURITY_AGENCIES.find(a => a.id === (s.agency || 'RAINBOW')) || STATE_SECURITY_AGENCIES[0];
            return (
              <div
                key={s.id}
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'space-between',
                  padding: '16px 20px',
                  background: 'var(--input-bg)',
                  border: '1px solid var(--border)',
                  borderRadius: 14,
                }}
              >
                <div>
                  <h4 style={{ fontSize: 14, fontWeight: 700, color: 'var(--text-primary)', display: 'flex', alignItems: 'center', gap: 8 }}>
                    <span>{s.full_name || s.email || 'Officer'}</span>
                    <span style={{ fontSize: 10, fontWeight: 900, background: ag.color + '22', color: ag.color, border: `1px solid ${ag.color}66`, padding: '2px 8px', borderRadius: 12 }}>
                      {ag.badge} {ag.shortCode}
                    </span>
                  </h4>
                  <p style={{ fontSize: 11, color: 'var(--text-muted)' }}>{s.email} | Role: {s.role}</p>
                  <p style={{ fontSize: 10, color: 'var(--text-dim)' }}>Sector: {s.geo_lga || 'STATEWIDE HQ'} | District: {s.geo_ward || 'N/A'}</p>
                </div>

                <span style={{ fontSize: 10, fontWeight: 900, background: 'var(--primary-dim)', color: 'var(--primary)', padding: '4px 10px', borderRadius: 20 }}>
                  {s.role}
                </span>
              </div>
            );
          })}
        </div>
      </div>

      {/* ── Agency Liaison Access ───────────────────────────────────────── */}
      <div style={{ marginTop: 32, borderTop: '1px solid var(--border)', paddingTop: 24 }}>
        <AgencyAccessManager />
      </div>
    </div>
  );
}
