'use client';
import { useState, useEffect } from 'react';
import { collection, onSnapshot, query, orderBy, deleteDoc, doc, setDoc, updateDoc } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { Users, UserPlus, Trash2, Loader2, RefreshCw, LogOut } from 'lucide-react';

import { plateauTacticalMap, TacticalJurisdiction, TacticalWard } from '@/lib/tactical_mapping';

interface StaffRecord {
  id: string;
  email?: string;
  role?: string;
  badgeId?: string;
  displayName?: string;
  createdAt?: string;
  geo_lga?: string;
  geo_ward?: string;
  geo_pu?: string;
}

const ROLES = [
  { value: 'HQ_OFFICER', label: 'HQ Officer' },
  { value: 'LGA_OFFICER', label: 'LGA Officer' },
  { value: 'WARD_OFFICER', label: 'Ward Officer' },
  { value: 'POLLING_UNIT_OFFICER', label: 'Polling Unit Officer' },
];

const API_KEY = process.env.NEXT_PUBLIC_FIREBASE_API_KEY!;

export default function AdminDirectory() {
  const [badgeId, setBadgeId] = useState('');
  const [pin, setPin] = useState('');
  const [role, setRole] = useState('POLLING_UNIT_OFFICER');
  const [displayName, setDisplayName] = useState('');
  
  const [selectedLga, setSelectedLga] = useState<TacticalJurisdiction | null>(null);
  const [selectedWard, setSelectedWard] = useState<TacticalWard | null>(null);
  const [selectedPu, setSelectedPu] = useState('');

  const [loading, setLoading] = useState(false);
  const [msg, setMsg] = useState('');
  const [msgType, setMsgType] = useState<'ok' | 'err'>('ok');
  const [staff, setStaff] = useState<StaffRecord[]>([]);
  const [staffLoading, setStaffLoading] = useState(true);
  const [roleFilter, setRoleFilter] = useState('ALL');

  useEffect(() => {
    const q = query(collection(db, 'users'), orderBy('createdAt', 'desc'));
    const unsub = onSnapshot(q, snap => {
      setStaff(snap.docs.map(d => ({ id: d.id, ...d.data() } as StaffRecord)));
      setStaffLoading(false);
    }, () => setStaffLoading(false));
    return () => unsub();
  }, []);

  const provision = async () => {
    if (!badgeId.trim() || !pin.trim()) return;
    setLoading(true);
    setMsg('');
    try {
      const email = `${badgeId.toLowerCase().replace(/\s/g, '-')}@operationrainbow.plateau.gov.ng`;
      const res = await fetch(
        `https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${API_KEY}`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ email, password: pin, returnSecureToken: true }),
        }
      );
      const data = await res.json();
      if (!res.ok) throw new Error(data.error?.message || 'Provisioning failed');

      // Write Firestore profile
      await setDoc(doc(db, 'users', data.localId), {
        email,
        badgeId: badgeId.toUpperCase(),
        role,
        displayName: displayName || badgeId.toUpperCase(),
        createdAt: new Date().toISOString(),
        geo_lga: selectedLga?.name || null,
        geo_ward: selectedWard?.name || null,
        geo_pu: selectedPu || null,
      });

      setMsg(`✓ BADGE SECURED: ${badgeId.toUpperCase()} · ${email}`);
      setMsgType('ok');
      setBadgeId(''); setPin(''); setDisplayName('');
      setSelectedLga(null); setSelectedWard(null); setSelectedPu('');
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : 'Unknown error';
      setMsg(`ERROR: ${msg.includes('EMAIL_EXISTS') ? 'Badge ID already exists' : msg}`);
      setMsgType('err');
    } finally {
      setLoading(false);
    }
  };

  const handleDelete = async (userId: string, name: string) => {
    if (!confirm(`Remove ${name} from platform? Auth account remains active.`)) return;
    try {
      await deleteDoc(doc(db, 'users', userId));
    } catch (e) {
      alert('Delete failed: ' + e);
    }
  };

  // PRD §5 + §12: HQ-controlled forced logout
  const handleForceLogout = async (userId: string, name: string) => {
    if (!confirm(`Force logout ${name} from all devices immediately?`)) return;
    try {
      await updateDoc(doc(db, 'users', userId), { forceLogout: true });
      setMsg(`✓ FORCE LOGOUT sent to ${name}. Device will disconnect within seconds.`);
      setMsgType('ok');
    } catch (e: unknown) {
      setMsg('Force logout failed: ' + (e instanceof Error ? e.message : String(e)));
      setMsgType('err');
    }
  };

  const filtered = roleFilter === 'ALL' ? staff : staff.filter(s => s.role === roleFilter);

  const s: React.CSSProperties = {
    width: '100%', padding: '12px 14px',
    background: 'rgba(0,0,0,0.04)',
    border: '1px solid rgba(0,0,0,0.1)',
    borderRadius: 10, color: 'var(--text-primary)',
    fontFamily: 'Inter,sans-serif', fontSize: 13, fontWeight: 600, outline: 'none',
  };

  return (
    <div style={{ padding: '8px 0', maxWidth: 1200 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 14, marginBottom: 32 }}>
        <div style={{ padding: 12, background: 'rgba(229,57,53,0.15)', borderRadius: 12 }}>
          <Users size={28} color="var(--accent)" />
        </div>
        <div>
          <h2 style={{ fontSize: 22, fontWeight: 900 }}>ADMIN DIRECTORY</h2>
          <p style={{ fontSize: 11, color: 'var(--text-muted)' }}>Provision and manage Rainbow platform access</p>
        </div>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '380px 1fr', gap: 24 }}>
        {/* Provision Panel */}
        <div className="glass" style={{ borderRadius: 16, padding: 24, alignSelf: 'start' }}>
          <h3 style={{ fontSize: 13, fontWeight: 900, marginBottom: 22, display: 'flex', alignItems: 'center', gap: 8 }}>
            <UserPlus size={15} color="var(--accent)" /> PROVISION NEW BADGE
          </h3>

          <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
            <div>
              <label style={{ display: 'block', fontSize: 10, fontWeight: 800, color: 'var(--text-muted)', letterSpacing: 1.2, marginBottom: 6 }}>BADGE IDENTIFIER</label>
              <input value={badgeId} onChange={e => setBadgeId(e.target.value)} placeholder="e.g. WD-045" style={s} />
              <p style={{ fontSize: 9, color: 'var(--text-dim)', marginTop: 4 }}>
                Login email: {badgeId ? `${badgeId.toLowerCase()}@operationrainbow.plateau.gov.ng` : '—'}
              </p>
            </div>
            <div>
              <label style={{ display: 'block', fontSize: 10, fontWeight: 800, color: 'var(--text-muted)', letterSpacing: 1.2, marginBottom: 6 }}>DISPLAY NAME</label>
              <input value={displayName} onChange={e => setDisplayName(e.target.value)} placeholder="e.g. Sgt. Musa Ibrahim" style={s} />
            </div>
            <div>
              <label style={{ display: 'block', fontSize: 10, fontWeight: 800, color: 'var(--text-muted)', letterSpacing: 1.2, marginBottom: 6 }}>ROLE</label>
              <select value={role} onChange={e => {
                setRole(e.target.value);
                setSelectedLga(null); setSelectedWard(null); setSelectedPu('');
              }} style={{ ...s, cursor: 'pointer' }}>
                {ROLES.map(r => <option key={r.value} value={r.value}>{r.label}</option>)}
              </select>
            </div>

            {role !== 'HQ_OFFICER' && (
              <>
                <div style={{ padding: '12px', background: 'rgba(255,255,255,0.02)', borderRadius: 12, border: '1px dashed var(--border)' }}>
                  <p style={{ fontSize: 9, fontWeight: 900, color: 'var(--accent)', letterSpacing: 1, marginBottom: 12 }}>JURISDICTIONAL BOUNDS</p>
                  
                  <div style={{ marginBottom: 12 }}>
                    <label style={{ display: 'block', fontSize: 10, fontWeight: 800, color: 'var(--text-muted)', marginBottom: 6 }}>ASSIGNED LGA</label>
                    <select 
                      value={selectedLga?.id || ''} 
                      onChange={e => {
                        const lga = plateauTacticalMap.find(l => l.id === e.target.value);
                        setSelectedLga(lga || null);
                        setSelectedWard(null);
                        setSelectedPu('');
                      }} 
                      style={s}
                    >
                      <option value="">Select LGA...</option>
                      {plateauTacticalMap.map(l => <option key={l.id} value={l.id}>{l.name}</option>)}
                    </select>
                  </div>

                  {(role === 'WARD_OFFICER' || role === 'POLLING_UNIT_OFFICER') && selectedLga && (
                    <div style={{ marginBottom: 12 }}>
                      <label style={{ display: 'block', fontSize: 10, fontWeight: 800, color: 'var(--text-muted)', marginBottom: 6 }}>ASSIGNED WARD</label>
                      <select 
                        value={selectedWard?.id || ''} 
                        onChange={e => {
                          const ward = selectedLga.wards.find(w => w.id === e.target.value);
                          setSelectedWard(ward || null);
                          setSelectedPu('');
                        }} 
                        style={s}
                      >
                        <option value="">Select Ward...</option>
                        {selectedLga.wards.map(w => <option key={w.id} value={w.id}>{w.name}</option>)}
                      </select>
                    </div>
                  )}

                  {role === 'POLLING_UNIT_OFFICER' && selectedWard && (
                    <div>
                      <label style={{ display: 'block', fontSize: 10, fontWeight: 800, color: 'var(--text-muted)', marginBottom: 6 }}>ASSIGNED POLLING UNIT</label>
                      <select value={selectedPu} onChange={e => setSelectedPu(e.target.value)} style={s}>
                        <option value="">Select Polling Unit...</option>
                        {selectedWard.pollingUnits.map(pu => <option key={pu} value={pu}>{pu}</option>)}
                      </select>
                    </div>
                  )}
                </div>
              </>
            )}

            <div>
              <label style={{ display: 'block', fontSize: 10, fontWeight: 800, color: 'var(--text-muted)', letterSpacing: 1.2, marginBottom: 6 }}>SECURE PIN / PASSWORD</label>
              <input type="password" value={pin} onChange={e => setPin(e.target.value)} placeholder="Min 6 characters" style={{ ...s, letterSpacing: pin ? 6 : 0 }} />
            </div>

            <button onClick={provision} disabled={loading || !badgeId || !pin || (role !== 'HQ_OFFICER' && !selectedLga)}
              style={{ padding: '13px', background: loading ? 'rgba(0,0,0,0.1)' : 'var(--accent)', color: '#ffffff', border: 'none', borderRadius: 10, cursor: loading ? 'not-allowed' : 'pointer', fontWeight: 900, fontSize: 12, letterSpacing: 1.5, fontFamily: 'Inter,sans-serif', marginTop: 4, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8 }}>
              {loading ? <><Loader2 size={14} className="spin" /> PROVISIONING...</> : 'GENERATE CREDENTIALS'}
            </button>

            {msg && (
              <p style={{ fontSize: 11, fontWeight: 800, color: msgType === 'ok' ? 'var(--success)' : 'var(--accent)', textAlign: 'center', lineHeight: 1.4 }}>{msg}</p>
            )}
          </div>
        </div>

        {/* Staff Table */}
        <div className="glass" style={{ borderRadius: 16, padding: 24 }}>
          <div style={{ display: 'flex', alignItems: 'center', marginBottom: 20, gap: 12 }}>
            <h3 style={{ fontSize: 13, fontWeight: 900, flex: 1, display: 'flex', alignItems: 'center', gap: 8 }}>
              ACTIVE PERSONNEL
              {staffLoading && <RefreshCw size={13} className="spin" color="var(--text-muted)" />}
            </h3>
            <select value={roleFilter} onChange={e => setRoleFilter(e.target.value)}
              style={{ background: 'rgba(0,0,0,0.06)', border: '1px solid var(--border)', borderRadius: 8, padding: '6px 10px', color: 'var(--text-primary)', fontFamily: 'Inter,sans-serif', fontSize: 11, fontWeight: 700 }}>
              <option value="ALL">ALL ROLES</option>
              {ROLES.map(r => <option key={r.value} value={r.value}>{r.label}</option>)}
            </select>
            <span style={{ fontSize: 10, color: 'var(--text-muted)', fontWeight: 800 }}>{filtered.length} REGISTERED</span>
          </div>

          {filtered.length === 0 ? (
            <div style={{ textAlign: 'center', padding: '48px 0', color: 'var(--text-muted)' }}>
              <Users size={36} style={{ opacity: 0.2, marginBottom: 12 }} />
              <p style={{ fontSize: 13, fontWeight: 700 }}>No personnel in this category</p>
            </div>
          ) : (
            <table style={{ width: '100%', borderCollapse: 'collapse' }}>
              <thead>
                <tr style={{ borderBottom: '1px solid var(--border)' }}>
                  {['NAME / BADGE', 'ROLE', 'JURISDICTION', 'CREATED', 'ACTIONS'].map(h => (
                    <th key={h} style={{ padding: '10px 8px', fontSize: 10, color: 'var(--text-muted)', fontWeight: 800, letterSpacing: 1, textAlign: h === 'ACTIONS' ? 'right' : 'left' }}>{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {filtered.map(s => (
                  <tr key={s.id} style={{ borderBottom: '1px solid rgba(0,0,0,0.04)' }}>
                    <td style={{ padding: '14px 8px' }}>
                      <div style={{ fontWeight: 900, fontSize: 13 }}>{s.displayName || s.badgeId || s.id}</div>
                      <div style={{ fontSize: 10, color: 'var(--text-muted)', marginTop: 2 }}>{s.badgeId}</div>
                    </td>
                    <td style={{ padding: '14px 8px' }}>
                      <span style={{ fontSize: 9, fontWeight: 800, padding: '4px 8px', borderRadius: 20, background: 'rgba(229,57,53,0.15)', color: 'var(--accent)' }}>
                        {s.role?.replace('_', ' ') || 'CITIZEN'}
                      </span>
                    </td>
                    <td style={{ padding: '14px 8px' }}>
                      <div style={{ fontSize: 10, color: 'var(--text-primary)', fontWeight: 800 }}>{s.geo_lga || 'NATIONAL'}</div>
                      {(s.geo_ward || s.geo_pu) && (
                        <div style={{ fontSize: 9, color: 'var(--text-muted)', marginTop: 2 }}>
                          {s.geo_ward}{s.geo_pu ? ` · ${s.geo_pu}` : ''}
                        </div>
                      )}
                    </td>
                    <td style={{ padding: '14px 8px', fontSize: 10, color: 'var(--text-muted)' }}>
                      {s.createdAt ? new Date(s.createdAt).toLocaleDateString('en-GB') : '—'}
                    </td>
                    <td style={{ padding: '14px 8px', textAlign: 'right', display: 'flex', gap: 4, justifyContent: 'flex-end' }}>
                       <button onClick={() => handleForceLogout(s.id, s.displayName || s.id)}
                         title="Force Logout from all devices"
                         style={{ background: 'none', border: 'none', cursor: 'pointer', color: '#F57F17', padding: 4 }}>
                         <LogOut size={14} />
                       </button>
                       <button onClick={() => handleDelete(s.id, s.displayName || s.id)}
                         title="Remove from platform"
                         style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--accent)', padding: 4 }}>
                         <Trash2 size={15} />
                       </button>
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
}
