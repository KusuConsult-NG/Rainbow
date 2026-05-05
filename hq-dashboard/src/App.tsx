import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { MapContainer, TileLayer, Marker, Popup, ZoomControl } from 'react-leaflet';
import 'leaflet/dist/leaflet.css';
import { ShieldAlert, Users, Radio, Map as MapIcon, Settings, Target } from 'lucide-react';
import React, { useEffect, useState } from 'react';
import { collection, onSnapshot, query, where, limit, doc, updateDoc, getDoc } from 'firebase/firestore';
import { onAuthStateChanged, User } from 'firebase/auth';
import { db, auth } from './firebase';
import { LoginScreen } from './LoginScreen';

import L from 'leaflet';

const createCustomIcon = (isDuress: boolean, isCritical: boolean) => {
  const color = isDuress ? '#720000' : (isCritical ? '#E53935' : '#F57F17');
  const size = isDuress ? 64 : (isCritical ? 48 : 32);
  const borderSize = isDuress ? 4 : 2;
  
  return L.divIcon({
    className: 'custom-div-icon',
    html: `
      <div style="
        width: ${size}px;
        height: ${size}px;
        background-color: ${color}${isDuress || isCritical ? '66' : 'FF'};
        border-radius: 50%;
        border: ${borderSize}px solid white;
        display: flex;
        align-items: center;
        justify-content: center;
        ${isDuress ? 'animation: pulse-border 1.5s infinite;' : ''}
      ">
        ${(isDuress || isCritical) ? `<div style="
          width: ${size * 0.5}px;
          height: ${size * 0.5}px;
          background-color: ${color};
          border-radius: 50%;
          border: 2px solid white;
        "></div>` : ''}
      </div>
    `,
    iconSize: [size, size],
    iconAnchor: [size / 2, size / 2],
    popupAnchor: [0, -size / 2]
  });
};

import { useNavigate, useLocation } from 'react-router-dom';
import { AdminDirectory } from './AdminDirectory';
import { MassBroadcast } from './MassBroadcast';
import { signOut } from 'firebase/auth';
// ... (icon setup remains in App.tsx)

const Sidebar = ({ activeAlerts = 0, criticalCount = 0 }) => {
  const navigate = useNavigate();
  const location = useLocation();

  const handleLogout = async () => {
    await signOut(auth);
    navigate('/login');
  };

  return (
    <div className="glass-panel" style={{ width: '320px', height: '100vh', display: 'flex', flexDirection: 'column', padding: '24px', zIndex: 1000, position: 'relative' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: '12px', marginBottom: '40px' }}>
        <div style={{ background: 'var(--accent)', padding: '10px', borderRadius: '12px' }}>
          <ShieldAlert size={28} color="white" />
        </div>
        <div>
          <h1 style={{ fontSize: '18px', fontWeight: 900, letterSpacing: '1px' }}>COMMAND HQ</h1>
          <p style={{ fontSize: '10px', color: 'var(--text-muted)', letterSpacing: '2px' }}>OPERATION RAINBOW</p>
        </div>
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: '8px', flex: 1 }}>
        <NavItem icon={<MapIcon size={18}/>} label="Live Intelligence Map" active={location.pathname === '/'} onClick={() => navigate('/')} />
        <NavItem icon={<Users size={18}/>} label="Admin Directory" active={location.pathname === '/admin'} onClick={() => navigate('/admin')} />
        <NavItem icon={<Radio size={18}/>} label="Mass Broadcast" active={location.pathname === '/broadcast'} onClick={() => navigate('/broadcast')} />
        <NavItem icon={<Settings size={18}/>} label="System Settings" />
        
        <div style={{ marginTop: '32px' }}>
          <p style={{ fontSize: '10px', color: 'var(--text-muted)', letterSpacing: '1px', marginBottom: '12px' }}>GLOBAL STATS</p>
          <div style={{ background: 'rgba(255,255,255,0.05)', padding: '12px', borderRadius: '8px', marginBottom: '8px' }}>
            <TextMetric label="CRITICAL ALERTS" value={criticalCount} color="var(--accent)" />
          </div>
          <div style={{ background: 'rgba(255,255,255,0.05)', padding: '12px', borderRadius: '8px' }}>
            <TextMetric label="ACTIVE INCIDENTS" value={activeAlerts} color="#F57F17" />
          </div>
        </div>
      </div>

      <div style={{ marginTop: 'auto', background: 'rgba(255,255,255,0.05)', padding: '16px', borderRadius: '12px', marginBottom: '16px' }}>
        <p style={{ fontSize: '10px', color: 'var(--text-muted)' }}>NETWORK UPLINK</p>
        <h3 style={{ fontSize: '14px', color: '#4CAF50', fontWeight: 800 }}>FIREBASE SYNCING</h3>
      </div>
      
      <button onClick={handleLogout} style={{ width: '100%', padding: '12px', background: 'rgba(229, 57, 53, 0.1)', color: 'var(--accent)', border: '1px solid var(--accent)', borderRadius: '8px', cursor: 'pointer', fontWeight: 800, fontSize: '11px', letterSpacing: '1px' }}>
        TERMINATE SESSION
      </button>
    </div>
  );
};

const TextMetric = ({ label, value, color }: { label: string, value: number, color: string }) => (
  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
    <span style={{ fontSize: '11px', fontWeight: 800, color: 'var(--text-muted)' }}>{label}</span>
    <span style={{ fontSize: '18px', fontWeight: 900, color }}>{value}</span>
  </div>
);

const NavItem = ({ icon, label, active = false, onClick }: { icon: React.ReactNode, label: string, active?: boolean, onClick?: () => void }) => (
  <div 
    onClick={onClick}
    style={{ 
      display: 'flex', alignItems: 'center', gap: '12px', padding: '12px 16px', 
      background: active ? 'rgba(229, 57, 53, 0.15)' : 'transparent',
      borderLeft: active ? '3px solid var(--accent)' : '3px solid transparent',
      color: active ? 'white' : 'var(--text-muted)',
      borderRadius: '4px', cursor: 'pointer', fontWeight: 600, fontSize: '13px'
  }}>
    {icon}
    {label}
  </div>
)

const Dashboard = ({ userRole }: { userRole: string }) => {
  const [alerts, setAlerts] = useState<any[]>([]);
  const [filterStatus, setFilterStatus] = useState<string>('ALL');
  const [filterTier, setFilterTier] = useState<string>('ALL');

  useEffect(() => {
    // Stream live data securely mapped to the user Role
    let q;
    
    if (userRole === 'HQ_OFFICER') {
      q = query(
        collection(db, 'alerts'), 
        where('status', 'in', ['ACTIVE', 'DURESS']),
        limit(150)
      );
    } else {
      let assignedTier = 'POLLING_UNIT';
      if (userRole === 'WARD_OFFICER') assignedTier = 'WARD';
      if (userRole === 'LGA_OFFICER') assignedTier = 'LGA';

      q = query(
        collection(db, 'alerts'), 
        where('status', 'in', ['ACTIVE', 'DURESS']),
        where('assigned_to', '==', assignedTier),
        limit(150)
      );
    }

    const unsubscribe = onSnapshot(q, (snapshot) => {
      const data = snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
      setAlerts(data);
    }, (error) => {
      console.error("Firebase Streaming Error:", error);
    });

    return () => unsubscribe();
  }, [userRole]);

  const filteredAlerts = alerts.filter(a => {
    if (filterStatus !== 'ALL' && a.status !== filterStatus) return false;
    if (filterTier !== 'ALL' && a.assigned_to !== filterTier) return false;
    return true;
  });

  return (
    <div style={{ height: '100%', width: '100%' }}>
      <MapContainer 
        center={[9.9167, 8.8917]} 
        zoom={9} 
        style={{ height: '100%', width: '100%', background: '#0a0a0a' }}
        zoomControl={false}
      >
          <TileLayer
            attribution='&copy; CARTO'
            url="https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png"
          />
          <ZoomControl position="bottomright" />
          
          {filteredAlerts.map((alert) => {
            const isDuress = alert.status === 'DURESS';
            const isCritical = alert.isCritical === true;
            return (
              <Marker 
                key={alert.id}
                position={[alert.lat || 0, alert.lng || 0]}
                icon={createCustomIcon(isDuress, isCritical)}
              >
                <Popup>
                  <div style={{ padding: '8px 4px', fontFamily: 'Inter', minWidth: '220px' }}>
                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '8px' }}>
                      <h3 style={{ 
                        color: isDuress ? '#720000' : 'var(--accent)', 
                        fontWeight: 900, 
                        fontSize: '14px',
                        margin: 0
                      }}>
                        {isDuress ? 'DURESS ACTIVATED' : (alert.type || 'EMERGENCY')}
                      </h3>
                      <span style={{ fontSize: '10px', background: '#333', color: 'white', padding: '2px 6px', borderRadius: '4px', fontWeight: 800 }}>
                        {alert.assigned_to || 'UNASSIGNED'}
                      </span>
                    </div>
                    
                    <p style={{ fontSize: '12px', fontWeight: 600, color: '#444', margin: '4px 0' }}>User ID: {alert.reportedBy}</p>
                    <p style={{ fontSize: '11px', color: '#666', marginTop: '4px', marginBottom: '12px', lineHeight: 1.4 }}>{alert.description}</p>
                    
                    {/* Control Actions */}
                    <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
                      <div style={{ display: 'flex', gap: '6px' }}>
                        <button 
                          onClick={() => updateDoc(doc(db, 'alerts', alert.id), { assigned_to: alert.assigned_to === 'POLLING_UNIT' ? 'WARD' : (alert.assigned_to === 'WARD' ? 'LGA' : 'HQ') })}
                          style={{ flex: 1, padding: '8px', background: '#FF9800', color: 'white', border: 'none', borderRadius: '4px', fontSize: '11px', fontWeight: 800, cursor: 'pointer' }}
                        >
                          ESCALATE
                        </button>
                        <a 
                          href={`tel:${alert.reportedBy}`}
                          style={{ flex: 1, textDecoration: 'none', textAlign: 'center', padding: '8px', background: '#2196F3', color: 'white', border: 'none', borderRadius: '4px', fontSize: '11px', fontWeight: 800, cursor: 'pointer' }}
                        >
                          CALL USER
                        </a>
                      </div>
                      <button 
                        onClick={() => updateDoc(doc(db, 'alerts', alert.id), { status: 'RESOLVED' })}
                        style={{ width: '100%', padding: '8px', background: '#4CAF50', color: 'white', border: 'none', borderRadius: '4px', fontSize: '11px', fontWeight: 800, cursor: 'pointer', marginTop: '2px' }}
                      >
                        MARK RESOLVED
                      </button>
                    </div>
                  </div>
                </Popup>
              </Marker>
            )
          })}
        </MapContainer>

        {/* Live Incident Feed Overlay */}
        <div className="glass-panel" style={{ position: 'absolute', top: '24px', right: '24px', zIndex: 1000, width: '300px', borderRadius: '16px', maxHeight: 'calc(100vh - 48px)', display: 'flex', flexDirection: 'column' }}>
           <div style={{ padding: '16px 20px', borderBottom: '1px solid rgba(255,255,255,0.05)' }}>
             <h2 style={{ fontSize: '11px', color: 'var(--accent)', fontWeight: 900, letterSpacing: '2px', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
               <span style={{ display: 'flex', alignItems: 'center', gap: '8px' }}><Target size={14} /> LIVE THREAT FEED</span>
             </h2>
             <div style={{ display: 'flex', gap: '8px', marginTop: '12px' }}>
                <select 
                  value={filterStatus} 
                  onChange={(e) => setFilterStatus(e.target.value)}
                  style={{ flex: 1, background: 'rgba(255,255,255,0.1)', color: 'white', border: 'none', borderRadius: '4px', padding: '6px', fontSize: '10px', fontWeight: 700 }}
                >
                  <option value="ALL">ALL STATUS</option>
                  <option value="ACTIVE">ACTIVE</option>
                  <option value="DURESS">DURESS</option>
                </select>
                <select 
                  value={filterTier} 
                  onChange={(e) => setFilterTier(e.target.value)}
                  style={{ flex: 1, background: 'rgba(255,255,255,0.1)', color: 'white', border: 'none', borderRadius: '4px', padding: '6px', fontSize: '10px', fontWeight: 700 }}
                >
                  <option value="ALL">ALL COMMANDS</option>
                  <option value="POLLING_UNIT">POLLING UNIT</option>
                  <option value="WARD">WARD COMM</option>
                  <option value="LGA">LGA COMM</option>
                  <option value="HQ">HQ SUPREME</option>
                </select>
             </div>
           </div>
           
           <div style={{ padding: '16px', overflowY: 'auto', flex: 1, display: 'flex', flexDirection: 'column', gap: '12px' }}>
             {filteredAlerts.length === 0 ? (
               <div style={{ textAlign: 'center', padding: '24px', color: 'var(--text-muted)', fontSize: '12px' }}>NO ACTIVE TACTICAL ALERTS</div>
             ) : filteredAlerts.map(a => (
               <div key={a.id} style={{ 
                 background: 'rgba(0,0,0,0.3)', 
                 borderLeft: `4px solid ${a.status === 'DURESS' ? '#720000' : (a.isCritical ? '#E53935' : '#F57F17')}`,
                 padding: '12px',
                 borderRadius: '0 8px 8px 0'
               }}>
                 <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '4px' }}>
                   <span style={{ fontSize: '10px', color: 'var(--text-muted)', fontWeight: 700 }}>{a.reportedBy}</span>
                   {a.status === 'DURESS' && (
                     <span style={{ background: '#720000', color: 'white', fontSize: '9px', fontWeight: 900, padding: '2px 6px', borderRadius: '4px' }}>DURESS</span>
                   )}
                 </div>
                 <h4 style={{ fontSize: '13px', fontWeight: 800 }}>{a.type}</h4>
               </div>
             ))}
           </div>
        </div>
    </div>
  );
};

function App() {
  const [user, setUser] = useState<User | null>(null);
  const [userRole, setUserRole] = useState<string>('HQ_OFFICER');
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const unsub = onAuthStateChanged(auth, async (currentUser) => {
      setUser(currentUser);
      if (currentUser) {
        try {
          const userDoc = await getDoc(doc(db, 'users', currentUser.uid));
          if (userDoc.exists()) {
            setUserRole(userDoc.data().role || 'HQ_OFFICER');
          } else {
            setUserRole('POLLING_UNIT_OFFICER');
          }
        } catch (e) {
          console.error("Failed to fetch user role", e);
        }
      }
      setLoading(false);
    });
    return () => unsub();
  }, []);

  if (loading) return <div style={{ height: '100vh', background: 'var(--bg-primary)' }}></div>;

  return (
    <BrowserRouter>
      <Routes>
        <Route path="/login" element={!user ? <LoginScreen /> : <Navigate to="/" />} />
        
        <Route path="*" element={
          user ? (
            <div style={{ display: 'flex', height: '100vh', width: '100vw', background: 'var(--bg-primary)' }}>
              <Sidebar />
              <div style={{ flex: 1, position: 'relative', overflowY: 'auto' }}>
                <Routes>
                  <Route path="/" element={<Dashboard userRole={userRole} />} />
                  <Route path="/admin" element={<AdminDirectory />} />
                  <Route path="/broadcast" element={<MassBroadcast />} />
                </Routes>
              </div>
            </div>
          ) : <Navigate to="/login" />
        } />
      </Routes>
    </BrowserRouter>
  );
}

export default App;
