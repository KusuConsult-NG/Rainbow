'use client';
import { useEffect, useState, useCallback } from 'react';
import { onAuthStateChanged, signOut, User } from 'firebase/auth';
import { collection, onSnapshot, query, where, doc, orderBy, limit, getDoc, updateDoc, addDoc, serverTimestamp } from 'firebase/firestore';
import { ref as dbRef, onValue } from 'firebase/database';
import { httpsCallable } from 'firebase/functions';
import { auth, db, rtdb, functions } from '@/lib/firebase';
import { useRouter } from 'next/navigation';
import dynamic from 'next/dynamic';
import AdminDirectory from '@/components/AdminDirectory';
import SystemConfig from '@/components/SystemConfig';
import AuditLogs from '@/components/AuditLogs';
import MassBroadcast from '@/components/MassBroadcast';
import { plateauTacticalMap, TacticalJurisdiction, TacticalWard } from '@/lib/tactical_mapping';
import {
  ShieldAlert, Map as MapIcon, Users, Radio, Settings,
  LogOut, AlertTriangle, CheckCircle, ChevronUp, Phone,
  Loader2, Filter, Bell, Activity, Clock, Target, Edit3, Send
} from 'lucide-react';

// Leaflet must be client-only (no SSR)
const LiveMap = dynamic(() => import('@/components/LiveMap'), { ssr: false });

export interface Alert {
  id: string;
  type?: string;
  description?: string;
  status: 'ACTIVE' | 'DURESS' | 'RESOLVED';
  priority?: string;
  assigned_to?: string;
  lat?: number;
  lng?: number;
  reportedBy?: string;
  isCritical?: boolean;
  reportedAt?: { seconds: number };
  geo_lga?: string;
  geo_ward?: string;
  geo_pu?: string;
  resolved_by?: string;
  interfered_at?: any;
  interfered_by?: string;
}

const btnStyle = (color: string, bg: string): React.CSSProperties => ({
  flex: 1, padding: '12px 0', background: bg, color, border: `1px solid ${color}44`,
  borderRadius: 12, cursor: 'pointer', fontWeight: 900, fontSize: 10, letterSpacing: 1, transition: 'all 0.2s',
  fontFamily: "'Outfit', sans-serif"
});

const overlaySelect: React.CSSProperties = {
  background: 'rgba(255,255,255,0.85)', backdropFilter: 'blur(12px)',
  border: '1px solid rgba(0,0,0,0.15)', borderRadius: 8, padding: '8px 12px',
  color: 'var(--text-primary)', fontFamily: 'Inter,sans-serif', fontSize: 11, fontWeight: 700, cursor: 'pointer',
};

const fSel: React.CSSProperties = {
  background: 'rgba(0,0,0,0.06)', color: 'var(--text-primary)',
  border: '1px solid var(--border)', borderRadius: 8, padding: '7px 11px',
  fontSize: 11, fontWeight: 700, cursor: 'pointer', fontFamily: 'Inter,sans-serif',
};

type Tab = 'map' | 'alerts' | 'history' | 'analytics' | 'broadcast' | 'admin' | 'settings' | 'audit';

export default function DashboardPage() {
  const [user, setUser] = useState<User | null>(null);
  const [userRole, setUserRole] = useState('HQ_OFFICER');
  const [authLoading, setAuthLoading] = useState(true);
  const [alerts, setAlerts] = useState<Alert[]>([]);
  const [history, setHistory] = useState<Alert[]>([]);
  const [agentLocations, setAgentLocations] = useState<any[]>([]);
  const [activeTab, setActiveTab] = useState<Tab>('map');
  const [filterTier, setFilterTier] = useState('ALL');
  const [filterStatus, setFilterStatus] = useState('ALL');
  const router = useRouter();

  // Auth guard + role fetch
  useEffect(() => {
    const unsub = onAuthStateChanged(auth, async (u) => {
      setUser(u);
      if (!u) { router.replace('/login'); return; }
      try {
        const userDoc = await getDoc(doc(db, 'users', u.uid));
        if (userDoc.exists()) setUserRole(userDoc.data().role || 'HQ_OFFICER');
      } catch { /* default HQ_OFFICER */ }
      setAuthLoading(false);
    });
    return () => unsub();
  }, [router]);

  // Live active+duress alerts stream (role-scoped)
  useEffect(() => {
    if (!user) return;
    let q;
    if (userRole === 'HQ_OFFICER') {
      q = query(collection(db, 'alerts'), where('status', 'in', ['ACTIVE', 'DURESS']), orderBy('reportedAt', 'desc'), limit(200));
    } else {
      const tierMap: Record<string, string> = { LGA_OFFICER: 'LGA', WARD_OFFICER: 'WARD', POLLING_UNIT_OFFICER: 'POLLING_UNIT' };
      const tier = tierMap[userRole] || 'POLLING_UNIT';
      q = query(collection(db, 'alerts'), where('status', 'in', ['ACTIVE', 'DURESS']), where('assigned_to', '==', tier), orderBy('reportedAt', 'desc'), limit(200));
    }
    const unsub = onSnapshot(q, snap => {
      setAlerts(snap.docs.map(d => ({ id: d.id, ...d.data() } as Alert)));
    }, err => console.error('[HQ] Stream error:', err));
    return () => unsub();
  }, [user, userRole]);

  // Resolved history stream
  useEffect(() => {
    if (!user) return;
    const q = query(collection(db, 'alerts'), where('status', '==', 'RESOLVED'), orderBy('reportedAt', 'desc'), limit(100));
    const unsub = onSnapshot(q, snap => {
      setHistory(snap.docs.map(d => ({ id: d.id, ...d.data() } as Alert)));
    });
    return () => unsub();
  }, [user]);

  // Live Agent Tracking (RTDB Migration for Scale)
  useEffect(() => {
    if (!user) return;
    const trackingRef = dbRef(rtdb, 'tracking');
    const unsub = onValue(trackingRef, (snapshot) => {
      if (snapshot.exists()) {
        const data = snapshot.val();
        const locations = Object.keys(data).map(userId => ({
          id: userId,
          user_id: userId,
          ...data[userId]
        }));
        setAgentLocations(locations);
      } else {
        setAgentLocations([]);
      }
    });
    return () => unsub();
  }, [user]);

  const escalateAlert = useCallback(async (alertId: string, currentTier: string) => {
    const next = currentTier === 'POLLING_UNIT' ? 'WARD' : currentTier === 'WARD' ? 'LGA' : 'HQ';
    const func = httpsCallable(functions, 'adminEscalateAlert');
    await func({ alertId, targetTier: next });
  }, []);

  const hqOverride = useCallback(async (alertId: string) => {
    const func = httpsCallable(functions, 'adminEscalateAlert');
    await func({ alertId, targetTier: 'HQ' });
  }, []);

  const resolveAlert = useCallback(async (alertId: string) => {
    const func = httpsCallable(functions, 'adminResolveAlert');
    await func({ alertId });
  }, []);

  // PRD §5: HQ Interference flow
  const reassignAlert = useCallback(async (alertId: string, lga: string, ward?: string, pu?: string) => {
    try {
      await updateDoc(doc(db, 'alerts', alertId), {
        geo_lga: lga,
        geo_ward: ward || null,
        geo_pu: pu || null,
        interfered_at: serverTimestamp(),
        interfered_by: user?.email
      });
      await addDoc(collection(db, 'audit_logs'), {
        action: 'HQ_OVERRIDE',
        alert_id: alertId,
        actor: user?.email,
        details: `Jurisdictional shift to ${lga}${ward ? ' > ' + ward : ''}`,
        timestamp: serverTimestamp()
      });
    } catch (e) {
      console.error('Interference failed:', e);
    }
  }, [user]);

  const handleLogout = async () => { await signOut(auth); router.replace('/login'); };

  const filtered = alerts.filter(a => {
    if (filterStatus === 'CRITICAL') {
      if (!a.isCritical && a.status !== 'DURESS' && a.priority !== 'CRITICAL') return false;
    } else if (filterStatus !== 'ALL' && a.status !== filterStatus) return false;
    if (filterTier !== 'ALL' && a.assigned_to !== filterTier) return false;
    return true;
  });

  const criticalCount = alerts.filter(a => a.status === 'DURESS' || a.isCritical).length;
  const duressCount = alerts.filter(a => a.status === 'DURESS').length;

  if (authLoading) return (
    <div style={{ height: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'var(--bg-primary)' }}>
      <Loader2 size={32} color="var(--accent)" className="spin" />
    </div>
  );
  if (!user) return null;

  return (
    <div style={{ display: 'flex', height: '100vh', background: 'var(--bg-primary)', overflow: 'hidden', color: 'var(--text-primary)' }}>

      <aside className="glass" style={{ width: 280, display: 'flex', flexDirection: 'column', padding: '24px 16px', borderRight: '1px solid var(--border)', flexShrink: 0, zIndex: 100 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 40, padding: '0 8px' }}>
          <div className="pulse" style={{ background: 'var(--accent)', padding: 10, borderRadius: 12, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <ShieldAlert size={24} color="#000" />
          </div>
          <div>
            <h1 style={{ fontSize: 16, fontWeight: 900, letterSpacing: 1, textTransform: 'uppercase' }}>Command HQ</h1>
            <p style={{ fontSize: 9, color: 'var(--accent)', fontWeight: 800, letterSpacing: 2.5 }}>TACTICAL MONITOR</p>
          </div>
        </div>

        <nav style={{ display: 'flex', flexDirection: 'column', gap: 6, flex: 1 }}>
          <p style={{ fontSize: 9, fontWeight: 900, color: 'var(--text-dim)', letterSpacing: 2, marginBottom: 8, paddingLeft: 12 }}>SYSTEM NAVIGATION</p>
          <NavItem icon={<MapIcon size={18} />} label="Intelligence Map" active={activeTab === 'map'} onClick={() => setActiveTab('map')} />
          <NavItem icon={<Activity size={18} />} label="Incident Feed" active={activeTab === 'alerts'} onClick={() => setActiveTab('alerts')} badge={alerts.length > 0 ? alerts.length : undefined} />
          <NavItem icon={<Clock size={18} />} label="Mission History" active={activeTab === 'history'} onClick={() => setActiveTab('history')} />
          <NavItem icon={<Radio size={18} />} label="Mass Broadcast" active={activeTab === 'broadcast'} onClick={() => setActiveTab('broadcast')} />
          
          <div style={{ margin: '20px 0', height: 1, background: 'var(--border)' }}></div>
          
          <p style={{ fontSize: 9, fontWeight: 900, color: 'var(--text-dim)', letterSpacing: 2, marginBottom: 8, paddingLeft: 12 }}>ADMINISTRATION</p>
          <NavItem icon={<Users size={18} />} label="Agent Directory" active={activeTab === 'admin'} onClick={() => setActiveTab('admin')} />
          <NavItem icon={<Activity size={18} />} label="Forensic Audit" active={activeTab === 'audit'} onClick={() => setActiveTab('audit')} />
          <NavItem icon={<Settings size={18} />} label="System Logic" active={activeTab === 'settings'} onClick={() => setActiveTab('settings')} />
        </nav>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginTop: 24, padding: '16px', background: 'rgba(0,0,0,0.2)', borderRadius: 16, border: '1px solid var(--border)' }}>
          <p style={{ fontSize: 9, fontWeight: 900, color: 'var(--text-muted)', letterSpacing: 1.5, marginBottom: 4 }}>UNIT STATUS</p>
          <StatBar label="DURESS" value={duressCount} color="var(--duress)" onClick={() => { setActiveTab('alerts'); setFilterStatus('DURESS'); }} />
          <StatBar label="ACTIVE" value={alerts.length} color="var(--warning)" onClick={() => { setActiveTab('alerts'); setFilterStatus('ACTIVE'); }} />
          <StatBar label="ONLINE" value={agentLocations.length} color="var(--success)" onClick={() => setActiveTab('map')} />
        </div>

        <button onClick={handleLogout} className="card-hover"
          style={{ marginTop: 20, width: '100%', padding: '12px', background: 'rgba(255,23,68,0.05)', color: 'var(--duress)', border: '1px solid var(--duress-dim)', borderRadius: 12, cursor: 'pointer', fontWeight: 800, fontSize: 11, letterSpacing: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 10 }}>
          <LogOut size={14} /> TERMINATE UPLINK
        </button>
      </aside>

      <main style={{ flex: 1, display: 'flex', flexDirection: 'column', overflow: 'hidden', position: 'relative' }}>
        <header className="glass" style={{ padding: '0 24px', height: 72, borderBottom: '1px solid var(--border)', display: 'flex', alignItems: 'center', justifyContent: 'space-between', flexShrink: 0 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 24 }}>
            <div>
              <h2 style={{ fontSize: 18, fontWeight: 900, textTransform: 'uppercase', letterSpacing: 1 }}>
                {activeTab === 'map' && 'Sector Monitoring'}
                {activeTab === 'alerts' && 'Incident Response'}
                {activeTab === 'history' && 'Mission Logs'}
                {activeTab === 'broadcast' && 'Signal Dispatch'}
                {activeTab === 'admin' && 'Staff Command'}
                {activeTab === 'audit' && 'Accountability'}
                {activeTab === 'settings' && 'Platform Core'}
              </h2>
            </div>
            <div style={{ height: 24, width: 1, background: 'var(--border)' }}></div>
            <div style={{ display: 'flex', gap: 16 }}>
               <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                  <div style={{ width: 8, height: 8, borderRadius: '50%', background: 'var(--success)' }} className="pulse"></div>
                  <span style={{ fontSize: 11, fontWeight: 700, color: 'var(--success)' }}>LIVE UPLINK</span>
               </div>
               <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                  <Clock size={14} color="var(--text-muted)" />
                  <span style={{ fontSize: 11, fontWeight: 700, color: 'var(--text-muted)' }}>{new Date().toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit', second: '2-digit' })}</span>
               </div>
            </div>
          </div>

          <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
            {duressCount > 0 && (
              <div className="duress-pulse" style={{ border: '1px solid var(--duress)', borderRadius: 8, padding: '8px 16px', display: 'flex', alignItems: 'center', gap: 8 }}>
                <AlertTriangle size={14} color="white" />
                <span style={{ fontSize: 11, fontWeight: 900, color: 'white' }}>{duressCount} DURESS EMERGENCY</span>
              </div>
            )}
            <div style={{ textAlign: 'right' }}>
              <p style={{ fontSize: 11, fontWeight: 900, color: 'var(--text-primary)' }}>{user.email?.split('@')[0].toUpperCase()}</p>
              <p style={{ fontSize: 9, fontWeight: 700, color: 'var(--accent)' }}>{userRole.replace('_', ' ')}</p>
            </div>
          </div>
        </header>

        {activeTab === 'map' && (
          <div style={{ position: 'absolute', top: 90, left: 24, zIndex: 1000, display: 'flex', gap: 12 }}>
            <div className="glass" style={{ padding: '6px 12px', borderRadius: 10, display: 'flex', alignItems: 'center', gap: 12 }}>
              <span style={{ fontSize: 10, fontWeight: 900, color: 'var(--text-muted)' }}>FILTER:</span>
              <select value={filterStatus} onChange={e => setFilterStatus(e.target.value)} style={overlaySelect}>
                <option value="ALL">ALL STATUS</option>
                <option value="ACTIVE">ACTIVE</option>
                <option value="DURESS">DURESS</option>
                <option value="CRITICAL">CRITICAL</option>
              </select>
              <select value={filterTier} onChange={e => setFilterTier(e.target.value)} style={overlaySelect}>
                <option value="ALL">ALL TIERS</option>
                <option value="POLLING_UNIT">PU</option>
                <option value="WARD">WARD</option>
                <option value="LGA">LGA</option>
                <option value="HQ">HQ</option>
              </select>
            </div>
          </div>
        )}

        <div style={{ flex: 1, overflow: activeTab === 'map' ? 'hidden' : 'auto', padding: activeTab === 'map' ? 0 : '32px 40px' }}>
          {activeTab === 'map' && (
            <div style={{ position: 'relative', height: '100%', width: '100%' }}>
              <LiveMap alerts={filtered} agents={agentLocations} onResolve={resolveAlert} onEscalate={escalateAlert} />
              <div className="glass fade-in" style={{ position: 'absolute', top: 24, right: 24, width: 320, maxHeight: 'calc(100% - 48px)', borderRadius: 20, display: 'flex', flexDirection: 'column', overflow: 'hidden', border: '1px solid var(--border)', boxShadow: '0 20px 40px rgba(0,0,0,0.4)' }}>
                <div style={{ padding: '20px', borderBottom: '1px solid var(--border)', background: 'rgba(255,255,255,0.02)' }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                    <h3 style={{ fontSize: 12, fontWeight: 900, color: 'var(--accent)', letterSpacing: 1.5 }}>SITUATIONAL FEED</h3>
                    <div style={{ background: 'var(--accent-dim)', padding: '4px 10px', borderRadius: 20 }}>
                      <span style={{ fontSize: 10, fontWeight: 900, color: 'var(--accent)' }}>{filtered.length} UNITS</span>
                    </div>
                  </div>
                </div>
                <div style={{ overflow: 'auto', flex: 1, padding: '16px', display: 'flex', flexDirection: 'column', gap: 12 }}>
                  {filtered.length === 0 ? (
                    <div style={{ textAlign: 'center', padding: '40px 0' }}>
                      <CheckCircle size={32} color="var(--text-dim)" style={{ marginBottom: 12 }} />
                      <p style={{ fontSize: 12, color: 'var(--text-muted)', fontWeight: 600 }}>NO ACTIVE THREATS</p>
                    </div>
                  ) : filtered.map(a => (
                    <div key={a.id} className="card-hover" style={{ background: 'rgba(255,255,255,0.03)', borderRadius: 12, padding: '14px', borderLeft: `4px solid ${a.status === 'DURESS' ? 'var(--duress)' : 'var(--warning)'}` }}>
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 6 }}>
                        <span style={{ fontSize: 11, fontWeight: 900 }}>{a.type}</span>
                        <span style={{ fontSize: 9, fontWeight: 800, color: 'var(--text-muted)' }}>{a.assigned_to}</span>
                      </div>
                      <p style={{ fontSize: 11, color: 'var(--text-muted)', lineHeight: 1.4, marginBottom: 8 }}>{a.description?.substring(0, 60)}...</p>
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                        <span style={{ fontSize: 9, fontWeight: 800, color: 'var(--accent)' }}>GPS TRACKED</span>
                        <button onClick={() => setActiveTab('alerts')} style={{ background: 'transparent', border: 'none', color: 'var(--accent)', fontSize: 10, fontWeight: 900, cursor: 'pointer' }}>ENGAGE ›</button>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          )}

          {activeTab === 'alerts' && (
            <div className="fade-in">
              <div style={{ display: 'flex', alignItems: 'center', gap: 16, marginBottom: 32 }}>
                <div style={{ padding: 12, background: 'var(--warning-dim)', borderRadius: 12 }}>
                  <Activity size={24} color="var(--warning)" />
                </div>
                <div>
                  <h2 style={{ fontSize: 24, fontWeight: 900 }}>INCIDENT COMMAND</h2>
                  <p style={{ fontSize: 12, color: 'var(--text-muted)' }}>Active triage and escalation management</p>
                </div>
                <div style={{ marginLeft: 'auto', display: 'flex', gap: 10 }}>
                   <select value={filterStatus} onChange={e => setFilterStatus(e.target.value)} style={fSel}>
                    <option value="ALL">ALL STATUS</option>
                    <option value="ACTIVE">ACTIVE</option>
                    <option value="DURESS">DURESS</option>
                  </select>
                  <select value={filterTier} onChange={e => setFilterTier(e.target.value)} style={fSel}>
                    <option value="ALL">ALL TIERS</option>
                    <option value="POLLING_UNIT">PU</option>
                    <option value="WARD">WARD</option>
                    <option value="LGA">LGA</option>
                    <option value="HQ">HQ</option>
                  </select>
                </div>
              </div>
              {filtered.length === 0 ? (
                <div className="glass" style={{ padding: '80px', textAlign: 'center', borderRadius: 24 }}>
                  <CheckCircle size={64} color="var(--success)" style={{ opacity: 0.3, marginBottom: 20 }} />
                  <h3 style={{ fontSize: 20, fontWeight: 900, marginBottom: 8 }}>ALL SECTORS CLEAR</h3>
                  <p style={{ color: 'var(--text-muted)' }}>No active incidents require intervention at this time.</p>
                </div>
              ) : (
                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(380px, 1fr))', gap: 24 }}>
                  {filtered.map(a => <AlertCard key={a.id} alert={a} onEscalate={escalateAlert} onResolve={resolveAlert} onHqOverride={hqOverride} onReassign={reassignAlert} />)}
                </div>
              )}
            </div>
          )}

          {activeTab === 'history' && (
            <div className="fade-in">
              <div style={{ marginBottom: 32 }}>
                <h2 style={{ fontSize: 24, fontWeight: 900 }}>MISSION ARCHIVE</h2>
                <p style={{ fontSize: 12, color: 'var(--text-muted)' }}>Post-action reports and resolved incidents</p>
              </div>
              <div className="glass" style={{ borderRadius: 24, overflow: 'hidden' }}>
                <table style={{ width: '100%', borderCollapse: 'collapse' }}>
                  <thead>
                    <tr style={{ background: 'rgba(255,255,255,0.03)', borderBottom: '1px solid var(--border)' }}>
                      {['INCIDENT', 'TIER', 'RESOLVED BY', 'TIMESTAMP', 'DATA'].map(h => (
                        <th key={h} style={{ padding: '16px 24px', textAlign: 'left', fontSize: 10, fontWeight: 900, color: 'var(--text-muted)', letterSpacing: 1.5 }}>{h}</th>
                      ))}
                    </tr>
                  </thead>
                  <tbody>
                    {history.map(a => (
                      <tr key={a.id} style={{ borderBottom: '1px solid var(--border)' }} className="card-hover">
                        <td style={{ padding: '16px 24px' }}>
                          <p style={{ fontSize: 13, fontWeight: 800 }}>{a.type}</p>
                          <p style={{ fontSize: 11, color: 'var(--text-muted)' }}>{a.description?.substring(0, 40)}...</p>
                        </td>
                        <td style={{ padding: '16px 24px' }}>
                          <span style={{ fontSize: 10, fontWeight: 900, padding: '4px 10px', background: 'rgba(255,255,255,0.05)', borderRadius: 20 }}>{a.assigned_to}</span>
                        </td>
                        <td style={{ padding: '16px 24px', fontSize: 12, color: 'var(--success)', fontWeight: 700 }}>
                          {a.resolved_by?.split('@')[0]}
                        </td>
                        <td style={{ padding: '16px 24px', fontSize: 12, color: 'var(--text-muted)' }}>
                          {a.reportedAt ? new Date(a.reportedAt.seconds * 1000).toLocaleDateString() : '—'}
                        </td>
                        <td style={{ padding: '16px 24px' }}>
                          <button style={{ background: 'var(--accent-dim)', color: 'var(--accent)', border: 'none', padding: '6px 12px', borderRadius: 8, fontSize: 10, fontWeight: 900, cursor: 'pointer' }}>VIEW</button>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          )}

          {activeTab === 'analytics' && (
            <div className="fade-in">
              <h2 style={{ fontSize: 24, fontWeight: 900, marginBottom: 32 }}>TACTICAL ANALYTICS</h2>
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 20, marginBottom: 40 }}>
                 <MetricCard label="TOTAL ENGAGEMENTS" value={history.length + alerts.length} color="var(--accent)" />
                 <MetricCard label="DURESS FREQUENCY" value={duressCount} color="var(--duress)" />
                 <MetricCard label="MEAN RESPONSE TIME" value="4.2m" color="var(--success)" />
                 <MetricCard label="FIELD AGENTS" value={agentLocations.length} color="var(--warning)" />
              </div>
              <div className="glass" style={{ height: 400, borderRadius: 24, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                 <p style={{ color: 'var(--text-muted)', fontWeight: 800, fontSize: 12, letterSpacing: 2 }}>DATA VISUALIZATION INTERFACE INACTIVE</p>
              </div>
            </div>
          )}

          {activeTab === 'broadcast' && <MassBroadcast />}
          {activeTab === 'admin' && <AdminDirectory />}
          {activeTab === 'settings' && <SystemConfig />}
          {activeTab === 'audit' && <AuditLogs />}
        </div>
      </main>
    </div>
  );
}

function NavItem({ icon, label, active, onClick, badge }: { icon: React.ReactNode; label: string; active: boolean; onClick?: () => void; badge?: number }) {
  return (
    <button onClick={onClick} className="card-hover" style={{
      display: 'flex', alignItems: 'center', gap: 14, padding: '12px 16px',
      background: active ? 'var(--accent-dim)' : 'transparent',
      borderLeft: `4px solid ${active ? 'var(--accent)' : 'transparent'}`,
      color: active ? 'white' : 'var(--text-muted)',
      border: 'none', borderRadius: '0 12px 12px 0', cursor: onClick ? 'pointer' : 'default',
      fontWeight: 700, fontSize: 13, textAlign: 'left', width: '100%', transition: 'all 0.2s',
      fontFamily: "'Inter', sans-serif"
    }}>
      <span style={{ color: active ? 'var(--accent)' : 'inherit', display: 'flex' }}>{icon}</span>
      <span style={{ flex: 1 }}>{label}</span>
      {badge !== undefined && <span style={{ background: 'var(--duress)', color: '#ffffff', fontSize: 10, fontWeight: 900, padding: '2px 8px', borderRadius: 20 }}>{badge}</span>}
    </button>
  );
}

function StatBar({ label, value, color, onClick }: { label: string; value: number; color: string; onClick?: () => void }) {
  return (
    <div onClick={onClick} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', cursor: onClick ? 'pointer' : 'default', padding: '4px 8px' }}>
      <span style={{ fontSize: 10, fontWeight: 900, color: 'var(--text-muted)', letterSpacing: 1.5, fontFamily: "'Outfit', sans-serif" }}>{label}</span>
      <span style={{ fontSize: 14, fontWeight: 900, color, textShadow: `0 0 10px ${color}44`, fontFamily: "'Outfit', sans-serif" }}>{value}</span>
    </div>
  );
}

function MetricCard({ label, value, color }: { label: string, value: string | number, color: string }) {
  return (
    <div className="glass" style={{ padding: '24px', borderRadius: 20, borderTop: `4px solid ${color}` }}>
      <p style={{ fontSize: 9, fontWeight: 900, color: 'var(--text-muted)', letterSpacing: 1.5, marginBottom: 8 }}>{label}</p>
      <h3 style={{ fontSize: 28, fontWeight: 900, color: 'white' }}>{value}</h3>
    </div>
  );
}

function AlertCard({ alert, onEscalate, onResolve, onHqOverride, onReassign }: { 
  alert: Alert; 
  onEscalate: (id: string, t: string) => void; 
  onResolve: (id: string) => void; 
  onHqOverride: (id: string) => void;
  onReassign: (id: string, lga: string, ward?: string, pu?: string) => void;
}) {
  const isDuress = alert.status === 'DURESS';
  const color = isDuress ? 'var(--duress)' : 'var(--warning)';
  const a = alert as any;
  const [showReassign, setShowReassign] = useState(false);
  const [selLga, setSelLga] = useState(a.geo_lga || '');
  const [selWard, setSelWard] = useState(a.geo_ward || '');
  const [selPu, setSelPu] = useState(a.geo_pu || '');

  const lgaData = plateauTacticalMap.find(l => l.name === selLga);
  const wardData = lgaData?.wards.find(w => w.name === selWard);

  return (
    <div className="glass card-hover fade-in" style={{ borderRadius: 20, padding: 24, borderTop: `4px solid ${color}`, position: 'relative', overflow: 'hidden' }}>
      {isDuress && <div className="duress-pulse" style={{ position: 'absolute', top: 0, left: 0, right: 0, height: 40, opacity: 0.1, pointerEvents: 'none' }}></div>}
      
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 20 }}>
        <div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 4 }}>
            <span style={{ fontSize: 9, fontWeight: 900, color: 'var(--text-muted)', letterSpacing: 2, fontFamily: "'Outfit', sans-serif" }}>INCIDENT REPORT</span>
            {a.interfered_at && (
              <span style={{ fontSize: 8, fontWeight: 900, background: 'var(--accent)', color: 'white', padding: '2px 6px', borderRadius: 4 }}>HQ INTERFERED</span>
            )}
          </div>
          <h3 style={{ fontSize: 16, fontWeight: 900, color: isDuress ? 'var(--duress)' : 'white', fontFamily: "'Outfit', sans-serif" }}>{isDuress ? 'DURESS ALERT' : alert.type}</h3>
        </div>
        <div style={{ background: 'rgba(255,255,255,0.05)', padding: '6px 12px', borderRadius: 10 }}>
          <span style={{ fontSize: 10, fontWeight: 900, color: 'var(--accent)', fontFamily: "'Inter', sans-serif" }}>{alert.assigned_to}</span>
        </div>
      </div>

      <p style={{ fontSize: 13, color: 'var(--text-muted)', lineHeight: 1.6, marginBottom: 20 }}>{alert.description}</p>

      {!showReassign ? (
        <div style={{ display: 'flex', gap: 6, marginBottom: 20 }}>
           {[a.geo_lga, a.geo_ward].filter(Boolean).map(tag => (
             <span key={tag} style={{ fontSize: 9, fontWeight: 800, color: 'var(--text-dim)', border: '1px solid var(--border)', padding: '4px 10px', borderRadius: 6, fontFamily: "'Outfit', sans-serif" }}>{tag.toUpperCase()}</span>
           ))}
        </div>
      ) : (
        <div style={{ background: 'rgba(255,255,255,0.03)', padding: 12, borderRadius: 12, marginBottom: 20 }}>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8, marginBottom: 8 }}>
            <select value={selLga} onChange={e => { setSelLga(e.target.value); setSelWard(''); setSelPu(''); }} style={fSel}>
              <option value="">SELECT LGA</option>
              {plateauTacticalMap.map(l => <option key={l.id} value={l.name}>{l.name}</option>)}
            </select>
            <select value={selWard} onChange={e => { setSelWard(e.target.value); setSelPu(''); }} style={fSel}>
              <option value="">SELECT WARD</option>
              {lgaData?.wards.map(w => <option key={w.id} value={w.name}>{w.name}</option>)}
            </select>
          </div>
          <button 
            onClick={() => { onReassign(alert.id, selLga, selWard, selPu); setShowReassign(false); }}
            style={{ width: '100%', padding: '10px', background: 'var(--accent)', border: 'none', borderRadius: 8, color: 'white', fontWeight: 900, fontSize: 10, cursor: 'pointer' }}
          >
            CONFIRM REASSIGNMENT
          </button>
        </div>
      )}

      <div style={{ display: 'flex', gap: 10 }}>
        {!showReassign ? (
          <>
            <button onClick={() => onEscalate(alert.id, alert.assigned_to || 'POLLING_UNIT')} style={btnStyle('var(--warning)', 'var(--warning-dim)')}>ESCALATE</button>
            <button onClick={() => setShowReassign(true)} style={btnStyle('var(--text-primary)', 'rgba(255,255,255,0.05)')}>REASSIGN</button>
            <button onClick={() => onResolve(alert.id)} style={btnStyle('var(--success)', 'var(--success-dim)')}>RESOLVE</button>
          </>
        ) : (
          <button onClick={() => setShowReassign(false)} style={{ width: '100%', padding: '12px 0', background: 'transparent', border: '1px solid var(--border)', borderRadius: 12, color: 'var(--text-muted)', fontWeight: 900, fontSize: 10, cursor: 'pointer' }}>CANCEL</button>
        )}
      </div>
    </div>
  );
}
