'use client';
import { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import { Users, UserPlus, Trash2, Loader2, RefreshCw, Shield } from 'lucide-react';
import { plateauTacticalMap, TacticalJurisdiction, TacticalWard, STATE_SECURITY_AGENCIES } from '@/lib/tactical_mapping';
import AgencyAccessManager from '@/components/AgencyAccessManager';
import { placeField } from '@/lib/place-label';
import { staffEmailDomain } from '@/lib/staff-identity';


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
      // NOT `supabase.auth.signUp` with the role in `options.data`.
      //
      // That is what this form used to do, and it worked because
      // `handle_new_user()` copied `raw_user_meta_data->>'role'` onto the
      // profile. So did everyone else's signup: `options.data` is written by
      // the client, with the anon key that ships in the browser bundle and in
      // the APK, so any stranger could enrol themselves as HQ_COMMAND and pass
      // every policy in the system. The migration
      // 20260927000000_signup_cannot_choose_role.sql makes every signup a
      // CITIZEN whatever it asks for, which is why provisioning has to happen
      // on a server that holds the service key and checks who is asking.
      //
      // The response is deliberately trusted for nothing but its error text:
      // the role that took effect is the one the SERVER decided.
      const res = await fetch('/api/admin/provision', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          email,
          password,
          fullName,
          phone,
          role,
          agency,
          geoLga: (selectedLga as any)?.name || 'STATEWIDE HQ',
          geoWard: selectedWard?.name || 'N/A',
          geoPu: selectedPu || 'N/A',
        }),
      });

      const payload = await res.json().catch(() => ({}));
      if (!res.ok) {
        throw new Error(payload.error || `Provisioning failed (${res.status})`);
      }

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
            {/* The placeholder's domain comes from the one place sign-in
                reads it. One that drifts tells whoever is creating the account
                to type an email on a domain nobody can sign in under, which is
                one of the two ways an officer ends up with two accounts. T-99. */}
            <input
              type="email"
              required
              className="input-tactical"
              style={{ width: '100%' }}
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder={`officer@${staffEmailDomain()}`}
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
                  <p style={{ fontSize: 10, color: 'var(--text-dim)' }}>Sector: {placeField(s.geo_lga, 'lga')} | District: {s.geo_ward || 'N/A'}</p>
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
