/// <reference types="vite/client" />
import { useState, useEffect } from 'react';
import { Users, UserPlus, Trash2, KeyRound, RefreshCw } from 'lucide-react';
import { collection, onSnapshot, query, orderBy, deleteDoc, doc } from 'firebase/firestore';
import { db } from './firebase';

interface StaffRecord {
  id: string;
  email?: string;
  role?: string;
  name?: string;
  uid?: string;
  createdAt?: any;
}

export const AdminDirectory = () => {
  const [badgeId, setBadgeId] = useState('');
  const [pin, setPin] = useState('');
  const [loading, setLoading] = useState(false);
  const [msg, setMsg] = useState('');
  const [staff, setStaff] = useState<StaffRecord[]>([]);
  const [loadingStaff, setLoadingStaff] = useState(true);

  // Live Firestore stream of all provisioned staff
  useEffect(() => {
    const q = query(collection(db, 'users'), orderBy('name', 'asc'));
    const unsub = onSnapshot(q, (snap) => {
      setStaff(snap.docs.map(d => ({ id: d.id, ...d.data() } as StaffRecord)));
      setLoadingStaff(false);
    }, () => setLoadingStaff(false));
    return () => unsub();
  }, []);

  const generateCredentials = async () => {
    if (!badgeId || !pin) return;
    setLoading(true);
    setMsg('');

    try {
      const emailDomain = badgeId.toLowerCase().includes('@') ? '' : '@operationrainbow.plateau.gov.ng';
      const formattedEmail = `${badgeId.toLowerCase()}${emailDomain}`;
      const apiKey = import.meta.env.VITE_FIREBASE_API_KEY || '***REMOVED-SECRET***';
      
      const response = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${apiKey}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: formattedEmail, password: pin, returnSecureToken: true })
      });

      const data = await response.json();
      if (!response.ok) throw new Error(data.error?.message || 'Provisioning Failed');

      setMsg(`✓ BADGE SECURED: ${badgeId}`);
      setBadgeId('');
      setPin('');
    } catch (err: any) {
      setMsg(`ERROR: ${err.message}`);
    } finally {
      setLoading(false);
    }
  };

  const handleDelete = async (userId: string, name: string) => {
    if (!confirm(`Remove ${name || userId} from platform? This only removes their Firestore profile. Firebase Auth account remains.`)) return;
    try {
      await deleteDoc(doc(db, 'users', userId));
    } catch (e) {
      alert('Delete failed: ' + e);
    }
  };

  return (
    <div style={{ padding: '32px', color: 'white', maxWidth: '1200px', margin: '0 auto' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: '16px', marginBottom: '40px' }}>
        <div style={{ padding: '12px', background: 'rgba(255,255,255,0.1)', borderRadius: '12px' }}>
           <Users size={32} color="white" />
        </div>
        <div>
          <h1 style={{ fontSize: '28px', fontWeight: 900 }}>ADMIN DIRECTORY</h1>
          <p style={{ color: 'var(--text-muted)' }}>Manage Rainbow Platform Access</p>
        </div>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 2fr', gap: '32px' }}>
        {/* Creation Panel */}
        <div className="glass-panel" style={{ padding: '24px', borderRadius: '16px' }}>
          <h3 style={{ fontSize: '14px', fontWeight: 800, marginBottom: '24px', display: 'flex', alignItems: 'center', gap: '8px' }}>
            <UserPlus size={16} color="var(--accent)" />
            PROVISION NEW BADGE
          </h3>

          <div style={{ marginBottom: '20px' }}>
            <label style={{ display: 'block', fontSize: '11px', fontWeight: 700, color: 'var(--text-muted)', marginBottom: '8px' }}>BADGE IDENTIFIER</label>
            <input
              value={badgeId} onChange={e => setBadgeId(e.target.value)}
              placeholder="e.g. WD-45"
              style={{ width: '100%', padding: '12px', borderRadius: '8px', border: '1px solid rgba(255,255,255,0.1)', background: 'rgba(0,0,0,0.5)', color: 'white', fontFamily: 'Inter' }}
            />
            <p style={{ fontSize: '10px', color: 'var(--text-muted)', marginTop: '4px' }}>
              Login: {badgeId ? `${badgeId.toLowerCase()}@operationrainbow.plateau.gov.ng` : '—'}
            </p>
          </div>

          <div style={{ marginBottom: '32px' }}>
            <label style={{ display: 'block', fontSize: '11px', fontWeight: 700, color: 'var(--text-muted)', marginBottom: '8px' }}>SECURE PIN</label>
            <input
              value={pin} onChange={e => setPin(e.target.value)}
              type="password"
              placeholder="••••"
              style={{ width: '100%', padding: '12px', borderRadius: '8px', border: '1px solid rgba(255,255,255,0.1)', background: 'rgba(0,0,0,0.5)', color: 'white', fontFamily: 'Inter', letterSpacing: '8px' }}
            />
          </div>

          <button
            onClick={generateCredentials}
            disabled={loading}
            style={{ width: '100%', padding: '14px', background: loading ? 'gray' : 'white', color: 'black', fontWeight: 900, border: 'none', borderRadius: '8px', cursor: loading ? 'not-allowed' : 'pointer' }}
          >
            {loading ? 'PROVISIONING...' : 'GENERATE CREDENTIALS'}
          </button>

          {msg && (
            <p style={{ marginTop: '16px', fontSize: '11px', fontWeight: 900, color: msg.includes('ERROR') ? 'var(--accent)' : '#4CAF50', textAlign: 'center' }}>{msg}</p>
          )}
        </div>

        {/* Live Directory */}
        <div className="glass-panel" style={{ padding: '24px', borderRadius: '16px' }}>
          <h3 style={{ fontSize: '14px', fontWeight: 800, marginBottom: '24px', display: 'flex', alignItems: 'center', gap: '8px' }}>
            ACTIVE PERSONNEL
            {loadingStaff && <RefreshCw size={14} color="var(--text-muted)" />}
            <span style={{ marginLeft: 'auto', fontSize: '10px', color: 'var(--text-muted)', fontWeight: 600 }}>
              {staff.length} REGISTERED
            </span>
          </h3>

          {staff.length === 0 && !loadingStaff ? (
            <p style={{ color: 'var(--text-muted)', fontSize: '13px', textAlign: 'center', padding: '32px 0' }}>
              No staff provisioned yet. Use the form to add the first operator.
            </p>
          ) : (
            <table style={{ width: '100%', textAlign: 'left', borderCollapse: 'collapse' }}>
              <thead>
                <tr style={{ borderBottom: '1px solid rgba(255,255,255,0.1)' }}>
                  <th style={{ padding: '12px 0', fontSize: '11px', color: 'var(--text-muted)' }}>NAME / BADGE</th>
                  <th style={{ padding: '12px 0', fontSize: '11px', color: 'var(--text-muted)' }}>ROLE</th>
                  <th style={{ padding: '12px 0', fontSize: '11px', color: 'var(--text-muted)', textAlign: 'right' }}>ACTIONS</th>
                </tr>
              </thead>
              <tbody>
                {staff.map(s => (
                  <tr key={s.id} style={{ borderBottom: '1px solid rgba(255,255,255,0.05)' }}>
                    <td style={{ padding: '14px 0' }}>
                      <div style={{ fontWeight: 900, fontSize: '13px' }}>{s.name || s.id}</div>
                      <div style={{ fontSize: '10px', color: 'var(--text-muted)', marginTop: '2px' }}>
                        {s.email || `${s.id}@operationrainbow.plateau.gov.ng`}
                      </div>
                    </td>
                    <td style={{ padding: '14px 0', fontSize: '12px', color: 'var(--text-muted)' }}>{s.role || 'Citizen'}</td>
                    <td style={{ padding: '14px 0', textAlign: 'right' }}>
                      <div style={{ display: 'flex', gap: '16px', justifyContent: 'flex-end' }}>
                        <span title="Reset PIN via Firebase Console" style={{ opacity: 0.4, cursor: 'default' }}>
                          <KeyRound size={15} color="var(--text-muted)" />
                        </span>
                        <Trash2 size={15} color="var(--accent)" style={{ cursor: 'pointer' }} onClick={() => handleDelete(s.id, s.name || s.id)} />
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>
    </div>
  );
};
