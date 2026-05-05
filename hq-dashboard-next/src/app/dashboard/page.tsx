'use client';
import { useEffect, useState, useCallback } from 'react';
import { onAuthStateChanged, signOut, User } from 'firebase/auth';
import { collection, onSnapshot, query, where, doc, updateDoc, orderBy, limit, getDoc } from 'firebase/firestore';
import { ref as dbRef, onValue } from 'firebase/database';
import { auth, db, rtdb } from '@/lib/firebase';
import { useRouter } from 'next/navigation';
import dynamic from 'next/dynamic';
import AdminDirectory from '@/components/AdminDirectory';
import SystemConfig from '@/components/SystemConfig';
import AuditLogs from '@/components/AuditLogs';
import MassBroadcast from '@/components/MassBroadcast';
import {
  ShieldAlert, Map as MapIcon, Users, Radio, Settings,
  LogOut, AlertTriangle, CheckCircle, ChevronUp, Phone,
  Loader2, Filter, Bell, Activity, Clock, Target,
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
}

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
    const docRef = doc(db, 'alerts', alertId);
    await updateDoc(docRef, { assigned_to: next });
    // PRD §20: Audit log every system action
    const { addDoc, collection: col, serverTimestamp } = await import('firebase/firestore');
    await addDoc(col(db, 'audit_logs'), {
      action: 'MANUAL_ESCALATION', alert_id: alertId,
      from_tier: currentTier, to_tier: next,
      actor: user?.email || 'HQ', timestamp: serverTimestamp(),
    });
  }, [user]);

  // PRD §7: Forced HQ override — reassign any alert directly to HQ regardless of tier
  const hqOverride = useCallback(async (alertId: string) => {
    const docRef = doc(db, 'alerts', alertId);
    await updateDoc(docRef, { assigned_to: 'HQ', status: 'ACTIVE' });
    const { addDoc, collection: col, serverTimestamp } = await import('firebase/firestore');
    await addDoc(col(db, 'audit_logs'), {
      action: 'HQ_OVERRIDE', alert_id: alertId,
      actor: user?.email || 'HQ', timestamp: serverTimestamp(),
    });
  }, [user]);

  const resolveAlert = useCallback(async (alertId: string) => {
    const docRef = doc(db, 'alerts', alertId);
    await updateDoc(docRef, { status: 'RESOLVED' });
    const { addDoc, collection: col, serverTimestamp } = await import('firebase/firestore');
    await addDoc(col(db, 'audit_logs'), {
      action: 'RESOLVED', alert_id: alertId,
      actor: user?.email || 'HQ', timestamp: serverTimestamp(),
    });
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
    <div style={{ display: 'flex', height: '100vh', background: 'var(--bg-primary)', overflow: 'hidden' }}>

      {/* ── SIDEBAR ── */}
      <aside className="glass" style={{ width: 270, display: 'flex', flexDirection: 'column', padding: '20px 14px', borderRight: '1px solid var(--border)', flexShrink: 0, zIndex: 100 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 36, padding: '0 6px' }}>
          <div style={{ background: 'var(--accent)', padding: 9, borderRadius: 11, flexShrink: 0 }}>
            <ShieldAlert size={22} color="white" />
          </div>
          <div>
            <h1 style={{ fontSize: 14, fontWeight: 900, letterSpacing: 1 }}>COMMAND HQ</h1>
            <p style={{ fontSize: 9, color: 'var(--accent)', fontWeight: 800, letterSpacing: 2 }}>OPERATION RAINBOW</p>
          </div>
        </div>

        <nav style={{ display: 'flex', flexDirection: 'column', gap: 3, flex: 1 }}>
          <NavItem icon={<MapIcon size={16} />} label="Intelligence Map" active={activeTab === 'map'} onClick={() => setActiveTab('map')} />
          <NavItem icon={<Activity size={16} />} label="Live Alerts" active={activeTab === 'alerts'} onClick={() => setActiveTab('alerts')} badge={alerts.length > 0 ? alerts.length : undefined} />
          <NavItem icon={<Clock size={16} />} label="Incident History" active={activeTab === 'history'} onClick={() => setActiveTab('history')} badge={undefined} />
          <NavItem icon={<Activity size={16} />} label="Analytics" active={activeTab === 'analytics'} onClick={() => setActiveTab('analytics')} />
          <NavItem icon={<Radio size={16} />} label="Mass Broadcast" active={activeTab === 'broadcast'} onClick={() => setActiveTab('broadcast')} />
          <NavItem icon={<Users size={16} />} label="Admin Directory" active={activeTab === 'admin'} onClick={() => setActiveTab('admin')} />
          <NavItem icon={<Activity size={16} />} label="Audit Logs" active={activeTab === 'audit'} onClick={() => setActiveTab('audit')} />
          <NavItem icon={<Settings size={16} />} label="System Settings" active={activeTab === 'settings'} onClick={() => setActiveTab('settings')} />
        </nav>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 7, marginBottom: 14 }}>
          <StatBar label="DURESS ACTIVE" value={duressCount} color="var(--accent)" onClick={() => { setActiveTab('alerts'); setFilterStatus('DURESS'); setFilterTier('ALL'); }} />
          <StatBar label="TOTAL INCIDENTS" value={alerts.length} color="var(--warning)" onClick={() => { setActiveTab('alerts'); setFilterStatus('ALL'); setFilterTier('ALL'); }} />
          <StatBar label="CRITICAL FLAGS" value={criticalCount} color="#E91E63" onClick={() => { setActiveTab('alerts'); setFilterStatus('CRITICAL'); setFilterTier('ALL'); }} />
          <StatBar label="RESOLVED TODAY" value={history.length} color="var(--success)" onClick={() => { setActiveTab('history'); setFilterStatus('ALL'); setFilterTier('ALL'); }} />
        </div>

        <div style={{ background: 'rgba(76,175,80,0.08)', border: '1px solid rgba(76,175,80,0.2)', borderRadius: 8, padding: '8px 12px', marginBottom: 10 }}>
          <p style={{ fontSize: 9, color: 'var(--text-muted)', fontWeight: 700, letterSpacing: 1 }}>FIREBASE REALTIME</p>
          <p style={{ fontSize: 11, color: 'var(--success)', fontWeight: 800 }}>● LIVE SYNC ACTIVE</p>
        </div>

        <button onClick={handleLogout}
          style={{ width: '100%', padding: '10px', background: 'var(--accent-dim)', color: 'var(--accent)', border: '1px solid var(--accent)', borderRadius: 8, cursor: 'pointer', fontWeight: 800, fontSize: 11, letterSpacing: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, fontFamily: 'Inter,sans-serif' }}>
          <LogOut size={13} /> TERMINATE SESSION
        </button>
      </aside>

      {/* ── MAIN ── */}
      <main style={{ flex: 1, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
        {/* Topbar */}
        <header className="glass" style={{ padding: '14px 24px', borderBottom: '1px solid var(--border)', display: 'flex', alignItems: 'center', justifyContent: 'space-between', flexShrink: 0 }}>
          <div>
            <h2 style={{ fontSize: 15, fontWeight: 900 }}>
              {activeTab === 'map' && 'Live Intelligence Map'}
              {activeTab === 'alerts' && 'Live Incident Feed'}
              {activeTab === 'history' && 'Resolved Incident History'}
              {activeTab === 'broadcast' && 'Mass Broadcast'}
              {activeTab === 'admin' && 'Admin Directory'}
            </h2>
            <p style={{ fontSize: 10, color: 'var(--text-muted)', marginTop: 1 }}>
              {new Date().toLocaleString('en-GB', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric', hour: '2-digit', minute: '2-digit' })}
            </p>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
            {duressCount > 0 && (
              <div style={{ background: 'var(--accent-dim)', border: '1px solid var(--accent)', borderRadius: 8, padding: '7px 12px', display: 'flex', alignItems: 'center', gap: 7 }}>
                <Bell size={13} color="var(--accent)" />
                <span style={{ fontSize: 11, fontWeight: 900, color: 'var(--accent)' }}>{duressCount} DURESS ACTIVE</span>
              </div>
            )}
            <span style={{ fontSize: 11, color: 'var(--text-muted)', fontWeight: 700 }}>
              {user.email?.split('@')[0].toUpperCase()} · {userRole.replace('_', ' ')}
            </span>
          </div>
        </header>

        {/* Content area */}
        <div style={{ flex: 1, overflow: activeTab === 'map' ? 'hidden' : 'auto', padding: activeTab === 'map' ? 0 : '24px 28px', position: 'relative' }}>

          {/* MAP TAB — full bleed */}
          {activeTab === 'map' && (
            <div style={{ position: 'relative', height: '100%' }}>
              <LiveMap alerts={filtered} agents={agentLocations} onResolve={resolveAlert} onEscalate={escalateAlert} />
              {/* Overlay: filter bar + live feed panel */}
              <div style={{ position: 'absolute', top: 20, left: 20, zIndex: 1000, display: 'flex', gap: 8 }}>
                <select value={filterStatus} onChange={e => setFilterStatus(e.target.value)} style={overlaySelect}>
                  <option value="ALL">ALL STATUS</option>
                  <option value="ACTIVE">ACTIVE</option>
                  <option value="DURESS">DURESS</option>
                  <option value="CRITICAL">CRITICAL</option>
                </select>
                <select value={filterTier} onChange={e => setFilterTier(e.target.value)} style={overlaySelect}>
                  <option value="ALL">ALL TIERS</option>
                  <option value="POLLING_UNIT">POLLING UNIT</option>
                  <option value="WARD">WARD</option>
                  <option value="LGA">LGA</option>
                  <option value="HQ">HQ</option>
                </select>
              </div>
              {/* Live feed panel */}
              <div className="glass" style={{ position: 'absolute', top: 20, right: 20, zIndex: 1000, width: 290, maxHeight: 'calc(100% - 40px)', borderRadius: 16, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
                <div style={{ padding: '14px 16px', borderBottom: '1px solid var(--border)' }}>
                  <p style={{ fontSize: 10, fontWeight: 900, color: 'var(--accent)', letterSpacing: 2, display: 'flex', alignItems: 'center', gap: 6 }}>
                    <Target size={12} /> LIVE THREAT FEED · {filtered.length}
                  </p>
                </div>
                <div style={{ overflow: 'auto', flex: 1, padding: 12, display: 'flex', flexDirection: 'column', gap: 8 }}>
                  {filtered.length === 0
                    ? <p style={{ fontSize: 12, color: 'var(--text-muted)', textAlign: 'center', padding: '24px 0' }}>NO ACTIVE THREATS</p>
                    : filtered.map(a => (
                      <div key={a.id} style={{ background: 'rgba(0,0,0,0.04)', borderLeft: `3px solid ${a.status === 'DURESS' ? 'var(--duress)' : a.isCritical ? 'var(--accent)' : 'var(--warning)'}`, padding: '10px 12px', borderRadius: '0 8px 8px 0' }}>
                        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 3 }}>
                          <span style={{ fontSize: 11, fontWeight: 900 }}>{a.type || 'EMERGENCY'}</span>
                          {a.status === 'DURESS' && <span style={{ background: '#720000', color: '#ffffff', fontSize: 9, fontWeight: 900, padding: '2px 6px', borderRadius: 4 }}>DURESS</span>}
                        </div>
                        <p style={{ fontSize: 10, color: 'var(--text-muted)' }}>{a.assigned_to?.replace('_', ' ')} · {a.reportedBy}</p>
                      </div>
                    ))
                  }
                </div>
              </div>
            </div>
          )}

          {/* ALERTS TAB */}
          {activeTab === 'alerts' && (
            <div className="fade-in">
              <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 24 }}>
                <Filter size={14} color="var(--text-muted)" />
                <select value={filterStatus} onChange={e => setFilterStatus(e.target.value)} style={fSel}>
                  <option value="ALL">ALL STATUS</option>
                  <option value="ACTIVE">ACTIVE</option>
                  <option value="DURESS">DURESS</option>
                  <option value="CRITICAL">CRITICAL</option>
                </select>
                <select value={filterTier} onChange={e => setFilterTier(e.target.value)} style={fSel}>
                  <option value="ALL">ALL TIERS</option>
                  <option value="POLLING_UNIT">POLLING UNIT</option>
                  <option value="WARD">WARD</option>
                  <option value="LGA">LGA</option>
                  <option value="HQ">HQ</option>
                </select>
                <span style={{ marginLeft: 'auto', fontSize: 11, color: 'var(--text-muted)', fontWeight: 700 }}>{filtered.length} incident{filtered.length !== 1 ? 's' : ''}</span>
              </div>

              {filtered.length === 0 ? (
                <div style={{ textAlign: 'center', padding: '80px 0', color: 'var(--text-muted)' }}>
                  <CheckCircle size={48} style={{ opacity: 0.2, marginBottom: 16 }} />
                  <p style={{ fontWeight: 700, fontSize: 14 }}>No active incidents</p>
                </div>
              ) : (
                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(350px, 1fr))', gap: 16 }}>
                  {filtered.map(a => <AlertCard key={a.id} alert={a} onEscalate={escalateAlert} onResolve={resolveAlert} onHqOverride={hqOverride} />)}
                </div>
              )}
            </div>
          )}

          {/* HISTORY TAB */}
          {activeTab === 'history' && (
            <div className="fade-in">
              <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 20 }}>
                <Clock size={14} color="var(--success)" />
                <span style={{ fontSize: 13, fontWeight: 700 }}>Resolved incidents ({history.length})</span>
              </div>
              {history.length === 0 ? (
                <div style={{ textAlign: 'center', padding: '80px 0', color: 'var(--text-muted)' }}>
                  <CheckCircle size={48} style={{ opacity: 0.2, marginBottom: 16 }} />
                  <p style={{ fontSize: 14, fontWeight: 700 }}>No resolved incidents yet</p>
                </div>
              ) : (
                <div style={{ display: 'flex', flexDirection: 'column', gap: 0 }}>
                  <div className="glass" style={{ borderRadius: 16, overflow: 'hidden' }}>
                    <table style={{ width: '100%', borderCollapse: 'collapse' }}>
                      <thead>
                        <tr style={{ borderBottom: '1px solid var(--border)', background: 'rgba(0,0,0,0.02)' }}>
                          {['TYPE', 'DESCRIPTION', 'REPORTER', 'TIER', 'TIME', 'LOCATION'].map(h => (
                            <th key={h} style={{ padding: '12px 16px', fontSize: 10, color: 'var(--text-muted)', fontWeight: 800, letterSpacing: 1, textAlign: 'left' }}>{h}</th>
                          ))}
                        </tr>
                      </thead>
                      <tbody>
                        {history.map(a => (
                          <tr key={a.id} style={{ borderBottom: '1px solid rgba(0,0,0,0.03)' }}>
                            <td style={{ padding: '12px 16px' }}>
                              <span style={{ fontSize: 11, fontWeight: 900, color: 'var(--success)' }}>✓ {a.type || 'EMERGENCY'}</span>
                            </td>
                            <td style={{ padding: '12px 16px', fontSize: 12, color: 'var(--text-muted)', maxWidth: 260 }}>
                              <div style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{a.description || '—'}</div>
                            </td>
                            <td style={{ padding: '12px 16px', fontSize: 11, color: 'var(--text-muted)' }}>{a.reportedBy || '—'}</td>
                            <td style={{ padding: '12px 16px' }}>
                              <span style={{ fontSize: 9, fontWeight: 800, padding: '3px 8px', borderRadius: 20, background: 'rgba(0,0,0,0.06)', color: 'var(--text-muted)' }}>
                                {a.assigned_to?.replace('_', ' ') || '—'}
                              </span>
                            </td>
                            <td style={{ padding: '12px 16px', fontSize: 11, color: 'var(--text-muted)' }}>
                              {a.reportedAt ? new Date(a.reportedAt.seconds * 1000).toLocaleString('en-GB', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' }) : '—'}
                            </td>
                            <td style={{ padding: '12px 16px' }}>
                              {a.lat && a.lng ? (
                                <a href={`https://www.google.com/maps?q=${a.lat},${a.lng}`} target="_blank" rel="noreferrer"
                                  style={{ display: 'inline-flex', alignItems: 'center', gap: 4, fontSize: 9, fontWeight: 800, color: '#1565C0', textDecoration: 'none', background: 'rgba(21, 101, 192, 0.1)', padding: '4px 8px', borderRadius: 6 }}>
                                  <MapIcon size={10} color="#1565C0" /> MAP
                                </a>
                              ) : <span style={{ fontSize: 10, color: 'var(--text-dim)' }}>—</span>}
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                </div>
              )}
            </div>
          )}

          {/* ANALYTICS TAB */}
          {activeTab === 'analytics' && (
            <div className="fade-in" style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                <Activity size={18} color="var(--accent)" />
                <h3 style={{ fontSize: 16, fontWeight: 900 }}>Platform Analytics</h3>
              </div>
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(250px, 1fr))', gap: 16 }}>
                <div className="glass" style={{ padding: 24, borderRadius: 16 }}>
                  <h4 style={{ fontSize: 10, color: 'var(--text-muted)', fontWeight: 800, letterSpacing: 1.5, marginBottom: 8 }}>TOTAL HISTORICAL INCIDENTS</h4>
                  <p style={{ fontSize: 32, fontWeight: 900, color: 'var(--text-primary)' }}>{history.length + alerts.length}</p>
                </div>
                <div className="glass" style={{ padding: 24, borderRadius: 16 }}>
                  <h4 style={{ fontSize: 10, color: 'var(--text-muted)', fontWeight: 800, letterSpacing: 1.5, marginBottom: 8 }}>CRITICAL EMERGENCIES</h4>
                  <p style={{ fontSize: 32, fontWeight: 900, color: 'var(--accent)' }}>{criticalCount}</p>
                </div>
                <div className="glass" style={{ padding: 24, borderRadius: 16 }}>
                  <h4 style={{ fontSize: 10, color: 'var(--text-muted)', fontWeight: 800, letterSpacing: 1.5, marginBottom: 8 }}>DURESS ACTIVATIONS</h4>
                  <p style={{ fontSize: 32, fontWeight: 900, color: '#720000' }}>{duressCount}</p>
                </div>
              </div>
              
              <div className="glass" style={{ padding: 24, borderRadius: 16, marginTop: 12 }}>
                <h4 style={{ fontSize: 12, fontWeight: 800, marginBottom: 16, borderBottom: '1px solid var(--border)', paddingBottom: 12 }}>INCIDENTS BY ESCALATION TIER</h4>
                <div style={{ display: 'flex', gap: 20, flexWrap: 'wrap' }}>
                  {['POLLING_UNIT', 'WARD', 'LGA', 'HQ'].map(tier => (
                    <div key={tier} style={{ flex: 1, minWidth: 100, background: 'rgba(0,0,0,0.03)', padding: 16, borderRadius: 12 }}>
                      <p style={{ fontSize: 10, fontWeight: 800, color: 'var(--text-muted)' }}>{tier.replace('_', ' ')}</p>
                      <p style={{ fontSize: 24, fontWeight: 900, marginTop: 8 }}>
                        {alerts.filter(a => a.assigned_to === tier).length + history.filter(a => a.assigned_to === tier).length}
                      </p>
                    </div>
                  ))}
                </div>
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

/* ── Sub-components ── */

function NavItem({ icon, label, active, onClick, badge }: { icon: React.ReactNode; label: string; active: boolean; onClick?: () => void; badge?: number }) {
  return (
    <button onClick={onClick} style={{
      display: 'flex', alignItems: 'center', gap: 10, padding: '9px 12px',
      background: active ? 'var(--accent-dim)' : 'transparent',
      borderLeft: `3px solid ${active ? 'var(--accent)' : 'transparent'}`,
      color: active ? 'white' : 'var(--text-muted)',
      border: 'none', borderRadius: '0 8px 8px 0', cursor: onClick ? 'pointer' : 'default',
      fontWeight: 600, fontSize: 12, textAlign: 'left', width: '100%', fontFamily: 'Inter,sans-serif', transition: 'all 0.15s',
    }}>
      {icon}<span style={{ flex: 1 }}>{label}</span>
      {badge !== undefined && <span style={{ background: 'var(--accent)', color: '#ffffff', fontSize: 9, fontWeight: 900, padding: '2px 6px', borderRadius: 20 }}>{badge}</span>}
    </button>
  );
}

function StatBar({ label, value, color, onClick }: { label: string; value: number; color: string; onClick?: () => void }) {
  return (
    <div onClick={onClick} style={{ background: 'rgba(0,0,0,0.03)', borderRadius: 7, padding: '8px 12px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', cursor: onClick ? 'pointer' : 'default', transition: 'background 0.15s' }}>
      <span style={{ fontSize: 9, fontWeight: 800, color: 'var(--text-muted)', letterSpacing: 1 }}>{label}</span>
      <span style={{ fontSize: 16, fontWeight: 900, color }}>{value}</span>
    </div>
  );
}

function AlertCard({ alert, onEscalate, onResolve, onHqOverride }: { alert: Alert; onEscalate: (id: string, t: string) => void; onResolve: (id: string) => void; onHqOverride: (id: string) => void }) {
  const isDuress = alert.status === 'DURESS';
  const isCritical = alert.isCritical || alert.priority === 'CRITICAL';
  const borderColor = isDuress ? '#720000' : isCritical ? 'var(--accent)' : 'var(--warning)';
  const time = alert.reportedAt ? new Date(alert.reportedAt.seconds * 1000).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' }) : '—';
  const a = alert as any; // allow geo_ fields

  return (
    <div className="glass fade-in" style={{ borderRadius: 14, padding: 18, borderLeft: `4px solid ${borderColor}`, display: 'flex', flexDirection: 'column', gap: 12 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
        <div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 7, marginBottom: 3 }}>
            {isDuress && <AlertTriangle size={13} color="var(--accent)" />}
            <span style={{ fontSize: 13, fontWeight: 900, color: isDuress ? 'var(--accent)' : 'var(--text-primary)' }}>
              {isDuress ? '🔴 DURESS ACTIVATED' : alert.type || 'EMERGENCY'}
            </span>
          </div>
          <p style={{ fontSize: 10, color: 'var(--text-muted)', fontWeight: 600 }}>{time}</p>
          {/* PRD §13: Show auto-mapped jurisdiction */}
          {a.geo_lga && <p style={{ fontSize: 9, color: 'var(--text-muted)', marginTop: 2 }}>{a.geo_lga} › {a.geo_ward} › {a.geo_pu}</p>}
        </div>
        <span style={{ fontSize: 9, background: 'rgba(0,0,0,0.07)', padding: '3px 9px', borderRadius: 20, fontWeight: 800, color: 'var(--text-muted)', letterSpacing: 1 }}>
          {alert.assigned_to?.replace('_', ' ') || '—'}
        </span>
      </div>

      {alert.description && <p style={{ fontSize: 12, color: 'var(--text-muted)', lineHeight: 1.5 }}>{alert.description}</p>}

      {alert.reportedBy && (
        <div style={{ display: 'flex', alignItems: 'center', gap: 7 }}>
          <Phone size={11} color="var(--text-muted)" />
          <span style={{ fontSize: 11, fontWeight: 600, color: 'var(--text-muted)', flex: 1 }}>{alert.reportedBy}</span>
          {alert.reportedBy.startsWith('+') && (
            <a href={`tel:${alert.reportedBy}`} style={{ fontSize: 10, fontWeight: 800, color: 'var(--success)', textDecoration: 'none', background: 'var(--success-dim)', padding: '3px 9px', borderRadius: 20 }}>CALL</a>
          )}
        </div>
      )}

      {alert.lat && alert.lng && (
        <a href={`https://www.google.com/maps?q=${alert.lat},${alert.lng}`} target="_blank" rel="noreferrer"
          style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 10, fontWeight: 800, color: '#1565C0', textDecoration: 'none', background: 'rgba(21, 101, 192, 0.1)', padding: '6px 12px', borderRadius: 8, alignSelf: 'flex-start' }}>
          <MapIcon size={12} color="#1565C0" /> VIEW ON MAP ({alert.lat.toFixed(4)}°N, {alert.lng.toFixed(4)}°E)
        </a>
      )}

      <div style={{ display: 'flex', gap: 8 }}>
        <button onClick={() => onEscalate(alert.id, alert.assigned_to || 'POLLING_UNIT')} style={actBtn('#F57F17', 'var(--warning-dim)')}>
          <ChevronUp size={12} /> ESCALATE
        </button>
        {/* PRD §7: Forced HQ override button */}
        {alert.assigned_to !== 'HQ' && (
          <button onClick={() => onHqOverride(alert.id)} style={actBtn('#7B1FA2', 'rgba(123,31,162,0.1)')}>
            <ShieldAlert size={12} /> HQ OVERRIDE
          </button>
        )}
        <button onClick={() => onResolve(alert.id)} style={actBtn('var(--success)', 'var(--success-dim)')}>
          <CheckCircle size={12} /> RESOLVE
        </button>
      </div>
    </div>
  );
}

const actBtn = (color: string, bg: string): React.CSSProperties => ({
  flex: 1, padding: '8px 0', background: bg, color, border: `1px solid ${color}`,
  borderRadius: 8, cursor: 'pointer', fontWeight: 800, fontSize: 10, letterSpacing: 0.8,
  fontFamily: 'Inter,sans-serif', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 5,
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
