'use client';
import { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import { Users, UserPlus, Trash2, Loader2, RefreshCw } from 'lucide-react';
import { plateauTacticalMap, TacticalJurisdiction, TacticalWard } from '@/lib/tactical_mapping';

interface StaffRecord {
  id: string;
  email?: string;
  role?: string;
  full_name?: string;
  phone?: string;
  created_at?: string;
  geo_lga?: string;
  geo_ward?: string;
  geo_pu?: string;
}

const ROLES = [
  { value: 'HQ_COMMAND', label: 'Tactical HQ (Statewide)' },
  { value: 'LGA_COMMAND', label: 'LGA Command' },
  { value: 'WARD_COMMAND', label: 'Ward Command' },
  { value: 'UNIT_COMMAND', label: 'Unit Command (PU)' },
];

export default function AdminDirectory() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [role, setRole] = useState('UNIT_COMMAND');
  const [fullName, setFullName] = useState('');
  const [phone, setPhone] = useState('');

  const [selectedLga, setSelectedLga] = useState<TacticalJurisdiction | null>(null);
  const [selectedWard, setSelectedWard] = useState<TacticalWard | null>(null);
  const [selectedPu, setSelectedPu] = useState('');

  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [staff, setStaff] = useState<StaffRecord[]>([]);

  const fetchStaff = async () => {
    try {
      const { data, error: err } = await supabase.from('profiles').select('*').order('created_at', { ascending: false });
      if (err) throw err;
      setStaff((data || []) as StaffRecord[]);
    } catch (e: any) {
      console.error('Failed to load profiles:', e);
    }
  };

  useEffect(() => {
    fetchStaff();
  }, []);

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
            <label style={{ fontSize: 11, fontWeight: 700, color: 'var(--text-muted)', display: 'block', marginBottom: 6 }}>Role</label>
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

          <div style={{ gridColumn: '1 / -1', marginTop: 8 }}>
            <button
              type="submit"
              disabled={loading}
              className="btn-tactical btn-primary"
              style={{ width: '100%', padding: '14px' }}
            >
              {loading ? <Loader2 className="animate-spin" style={{ width: 16, height: 16 }} /> : 'Register Tactical Officer'}
            </button>
          </div>
        </form>
      </div>

      <div className="tactical-panel glass" style={{ padding: 24 }}>
        <h2 style={{ fontSize: 18, fontWeight: 900, marginBottom: 16, display: 'flex', alignItems: 'center', gap: 8, color: 'var(--text-primary)' }}>
          <Users style={{ width: 20, height: 20, color: 'var(--primary)' }} />
          Active Personnel Directory ({staff.length})
        </h2>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          {staff.map((s) => (
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
                <h4 style={{ fontSize: 14, fontWeight: 700, color: 'var(--text-primary)' }}>{s.full_name || s.email || 'Officer'}</h4>
                <p style={{ fontSize: 11, color: 'var(--text-muted)' }}>{s.email} | Role: {s.role}</p>
                <p style={{ fontSize: 10, color: 'var(--text-dim)' }}>LGA: {s.geo_lga || 'HQ'} | Ward: {s.geo_ward || 'N/A'}</p>
              </div>

              <span style={{ fontSize: 10, fontWeight: 900, background: 'var(--primary-dim)', color: 'var(--primary)', padding: '4px 10px', borderRadius: 20 }}>
                {s.role}
              </span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
