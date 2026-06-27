'use client';
import { useEffect, useState, useCallback } from 'react';
import { onAuthStateChanged, signOut, User } from 'firebase/auth';
import { collection, onSnapshot, query, where, doc, orderBy, limit, getDoc, updateDoc, addDoc, serverTimestamp } from 'firebase/firestore';
import { ref as dbRef, onValue } from 'firebase/database';
import { httpsCallable } from 'firebase/functions';
import { auth, db, rtdb, functions, getGeminiModel } from '@/lib/firebase';
import { useRouter } from 'next/navigation';
import dynamic from 'next/dynamic';
import AdminDirectory from '@/components/AdminDirectory';
import SystemConfig from '@/components/SystemConfig';
import AuditLogs from '@/components/AuditLogs';
import MassBroadcast from '@/components/MassBroadcast';
import SystemAlertListener from '@/components/SystemAlertListener';
import Analytics from '@/components/Analytics';
import UninstallRequests from '@/components/UninstallRequests';
import { plateauTacticalMap, TacticalJurisdiction, TacticalWard } from '@/lib/tactical_mapping';
import {
  ShieldAlert, Map as MapIcon, Users, Radio, Settings,
  LogOut, AlertTriangle, CheckCircle, ChevronUp, Phone,
  Loader2, Filter, Bell, Activity, Clock, Target, Edit3, Send,
  Sun, Moon, X, Sparkles
} from 'lucide-react';


// Leaflet must be client-only (no SSR)
const LiveMap = dynamic(() => import('@/components/LiveMap'), { ssr: false });

// Canonical Mission Alert Interface (Phase 2 Normalized)
export interface Alert {
  id: string;
  type?: string;
  description?: string;
  status: 'OPEN' | 'DISPATCHED' | 'ACKNOWLEDGED' | 'ON_ROUTE' | 'ON_SITE' | 'RESOLVED' | 'DURESS';
  priority: 'LOW' | 'MEDIUM' | 'HIGH' | 'CRITICAL';
  assigned_to: 'POLLING_UNIT' | 'WARD' | 'LGA' | 'HQ';
  assignedToUid?: string | null;
  lat?: number;
  lng?: number;
  reportedBy?: string;
  reportedAt?: { seconds: number };
  geo_lga?: string;
  geo_ward?: string;
  geo_pu?: string;
  resolved_by?: string;
  resolved_at?: any;
  timeline?: any[];
}

const btnStyle = (color: string, bg: string): React.CSSProperties => ({
  flex: 1, padding: '12px 0', background: bg, color, border: `1px solid ${color}44`,
  borderRadius: 12, cursor: 'pointer', fontWeight: 900, fontSize: 10, letterSpacing: 1, transition: 'all 0.2s',
  fontFamily: "'Outfit', sans-serif"
});

const overlaySelect: React.CSSProperties = {
  background: 'var(--bg-secondary)', backdropFilter: 'blur(12px)',
  border: '1px solid var(--border)', borderRadius: 8, padding: '8px 12px',
  color: 'var(--text-primary)', fontFamily: 'Inter,sans-serif', fontSize: 11, fontWeight: 700, cursor: 'pointer',
};

const fSel: React.CSSProperties = {
  background: 'var(--input-bg)', color: 'var(--text-primary)',
  border: '1px solid var(--border)', borderRadius: 8, padding: '7px 11px',
  fontSize: 11, fontWeight: 700, cursor: 'pointer', fontFamily: 'Inter,sans-serif',
};

type Tab = 'map' | 'alerts' | 'history' | 'analytics' | 'broadcast' | 'admin' | 'settings' | 'audit' | 'uninstall';

const renderFormattedSummary = (text: string) => {
  if (!text) return null;
  const parts = text.split(/###\s+/);
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
      {parts.map((part, index) => {
        if (!part.trim()) return null;
        const firstLineEnd = part.indexOf('\n');
        let title = '';
        let content = '';
        if (firstLineEnd !== -1) {
          title = part.substring(0, firstLineEnd).trim();
          content = part.substring(firstLineEnd + 1).trim();
        } else {
          const firstColon = part.indexOf(':');
          if (firstColon !== -1) {
            title = part.substring(0, firstColon).trim();
            content = part.substring(firstColon + 1).trim();
          } else {
            title = 'ANALYSIS NOTE';
            content = part.trim();
          }
        }
        title = title.replace(/^:\s*/, '').replace(/:\s*$/, '').toUpperCase();
        const contentLines = content.split('\n').map((line, lIdx) => {
          const trimmed = line.trim();
          if (trimmed.startsWith('* ') || trimmed.startsWith('- ')) {
            return (
              <li key={lIdx} style={{ fontSize: 11.5, color: 'var(--text-primary)', marginBottom: 6, marginLeft: 12, lineHeight: 1.5, listStyleType: 'disc' }}>
                {trimmed.substring(2)}
              </li>
            );
          }
          if (trimmed.match(/^\d+\.\s+/)) {
            const clean = trimmed.replace(/^\d+\.\s+/, '');
            return (
              <li key={lIdx} style={{ fontSize: 11.5, color: 'var(--text-primary)', marginBottom: 6, marginLeft: 12, listStyleType: 'decimal', lineHeight: 1.5 }}>
                {clean}
              </li>
            );
          }
          return trimmed ? (
            <p key={lIdx} style={{ fontSize: 11.5, color: 'var(--text-primary)', margin: '0 0 8px 0', lineHeight: 1.5 }}>
              {trimmed}
            </p>
          ) : null;
        });

        let sectionColor = 'var(--primary)';
        if (title.includes('EXECUTIVE')) sectionColor = 'var(--accent)';
        else if (title.includes('SLA') || title.includes('TIMELINE')) sectionColor = 'var(--warning)';
        else if (title.includes('RESOURCE') || title.includes('PERFORMANCE')) sectionColor = 'var(--success)';
        else if (title.includes('RECOMMENDATIONS') || title.includes('STRATEGIC')) sectionColor = 'var(--duress)';

        return (
          <div key={index} style={{
            background: 'var(--bg-card)',
            borderLeft: `3px solid ${sectionColor}`,
            padding: '14px 18px',
            borderRadius: '0 12px 12px 0',
            boxShadow: 'var(--shadow-sm)',
            border: '1px solid var(--border)',
            borderLeftWidth: 0
          }}>
            <h5 style={{ 
              fontSize: 10, 
              fontWeight: 900, 
              color: sectionColor, 
              letterSpacing: 1.2, 
              margin: '0 0 10px 0', 
              fontFamily: "'Outfit', sans-serif" 
            }}>
              {title}
            </h5>
            <ul style={{ margin: 0, padding: 0, listStyleType: 'none' }}>
              {contentLines}
            </ul>
          </div>
        );
      })}
    </div>
  );
};

export default function DashboardPage() {
  const [user, setUser] = useState<User | null>(null);
  const [userRole, setUserRole] = useState('HQ_OFFICER');
  const [userProfile, setUserProfile] = useState<any>(null);
  const [usersMap, setUsersMap] = useState<Record<string, any>>({});
  const [authLoading, setAuthLoading] = useState(true);
  const [alerts, setAlerts] = useState<Alert[]>([]);
  const [history, setHistory] = useState<Alert[]>([]);
  const [agentLocations, setAgentLocations] = useState<any[]>([]);
  const [activeTab, setActiveTab] = useState<Tab>('map');
  const [filterTier, setFilterTier] = useState('ALL');
  const [filterStatus, setFilterStatus] = useState('ALL');
  const [theme, setTheme] = useState<'light' | 'dark'>('light');
  const [timeString, setTimeString] = useState('');
  const [selectedReport, setSelectedReport] = useState<Alert | null>(null);
  const [aiSummary, setAiSummary] = useState<string | null>(null);
  const [isGeneratingSummary, setIsGeneratingSummary] = useState(false);
  const router = useRouter();

  useEffect(() => {
    setAiSummary(null);
    setIsGeneratingSummary(false);
  }, [selectedReport]);

  const generateAISummary = async (report: Alert) => {
    if (!report) return;
    setIsGeneratingSummary(true);
    setAiSummary(null);
    try {
      const model = getGeminiModel();
      if (!model) {
        throw new Error('Firebase AI Logic service is not initialized.');
      }

      const timelineText = (report.timeline || []).map((e: any) => {
        const t = e.timestamp ? new Date(e.timestamp).toISOString() : '';
        return `[${t}] ${e.type} by ${e.actor || 'System'} (${e.role || 'System'}): ${e.notes || ''}${e.reason ? ' Reason: ' + e.reason : ''}`;
      }).join('\n');

      const prompt = `You are the Operation Rainbow Forensic AI Assistant. Your task is to analyze the following resolved incident report and compile a premium, structured Post-Action Operational Summary.
      
INCIDENT METADATA:
- ID: ${report.id}
- Type: ${report.type || 'N/A'}
- Description: ${report.description || 'No description provided'}
- Scope: ${report.assigned_to}
- Priority: ${report.priority}
- LGA: ${report.geo_lga || 'STATE HQ'}
- Ward: ${report.geo_ward || 'N/A'}
- Resolved By: ${report.resolved_by || 'Unknown'}

HISTORICAL AUDIT TIMELINE:
${timelineText || 'No timeline events recorded.'}

Provide your analysis formatted in Markdown. Your summary MUST contain the following four specific sections:
1. ### EXECUTIVE OPERATIONAL SUMMARY: A concise 2-sentence tactical summary of the incident and its resolution.
2. ### TIMELINE SLA AUDIT: Audit the timeline response times, highlighting latency between creation, dispatch, and resolution. Determine if SLAs were met.
3. ### KEY RESOURCE PERFORMANCE: Evaluate the actions taken by responding officers and system actors.
4. ### STRATEGIC RECOMMENDATIONS: Provide 2-3 actionable, high-impact tactical recommendations for geofenced patrols or resources in this LGA/Ward to prevent future similar incidents.

Be precise, objective, and professional. Avoid generic filler. Use clean markdown formatting.`;

      const result = await model.generateContent(prompt);
      const text = await result.response.text();
      setAiSummary(text);
    } catch (error: any) {
      console.error('Error generating AI summary:', error);
      setAiSummary(`Failed to generate forensic summary: ${error.message || error}. Please ensure Generative Language API Terms of Service are accepted for the project.`);
    } finally {
      setIsGeneratingSummary(false);
    }
  };

  useEffect(() => {
    const updateTime = () => {
      const now = new Date();
      setTimeString(now.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit', second: '2-digit' }) + ' HRS');
    };
    updateTime();
    const interval = setInterval(updateTime, 1000);
    return () => clearInterval(interval);
  }, []);

  useEffect(() => {
    const savedTheme = localStorage.getItem('hq-theme') as 'light' | 'dark' | null;
    if (savedTheme) {
      setTheme(savedTheme);
    }
  }, []);

  useEffect(() => {
    if (theme === 'dark') {
      document.body.classList.add('dark-theme');
    } else {
      document.body.classList.remove('dark-theme');
    }
    localStorage.setItem('hq-theme', theme);
  }, [theme]);

  useEffect(() => {
    const handleShowDispatch = (e: any) => {
      setActiveTab('alerts');
      // Potential logic to scroll to specific alert card
    };
    window.addEventListener('hq-show-dispatch', handleShowDispatch);
    return () => window.removeEventListener('hq-show-dispatch', handleShowDispatch);
  }, []);

  // PRD: Secure Auth Guard + Custom Claim RBAC
  useEffect(() => {
    const unsub = onAuthStateChanged(auth, async (u) => {
      if (!u) {
        setUser(null);
        setUserProfile(null);
        router.replace('/login');
        return;
      }

      try {
        const idTokenResult = await u.getIdTokenResult();
        const isStaff = idTokenResult.claims.isStaff;
        const role = (idTokenResult.claims.role as string) || 'HQ_OFFICER';
        const isHq = role === 'HQ_OFFICER' || role === 'HQ_COMMAND';
        
        if (!isStaff || !isHq) {
          console.warn('[HQ_AUTH] Non-HQ command access attempt blocked.');
          await signOut(auth);
          router.replace('/login');
          return;
        }

        setUser(u);
        setUserRole(role);

        // Fetch User Profile from Firestore to obtain geographical scopes
        const userDocRef = doc(db, 'users', u.uid);
        const userDocSnap = await getDoc(userDocRef);
        if (userDocSnap.exists()) {
          setUserProfile(userDocSnap.data());
        } else {
          setUserProfile({});
        }

        setAuthLoading(false);
      } catch (err) {
        console.error('[HQ_AUTH] Claim verification failed:', err);
        router.replace('/login');
      }
    });
    return () => unsub();
  }, [router]);

  // Live active+duress alerts stream (role-scoped)
  useEffect(() => {
    if (!user || !userProfile) return;
    
    // Normalized statuses for active monitoring
    const activeStatuses = ['OPEN', 'ACTIVE', 'DISPATCHED', 'ACKNOWLEDGED', 'ON_ROUTE', 'ON_SITE', 'DURESS'];
    const tierMap: Record<string, string> = { 
      LGA_COMMAND: 'LGA', 
      WARD_COMMAND: 'WARD', 
      UNIT_COMMAND: 'POLLING_UNIT',
      LGA_OFFICER: 'LGA', // Legacy support
      WARD_OFFICER: 'WARD',
      POLLING_UNIT_OFFICER: 'POLLING_UNIT'
    };
    const tier = tierMap[userRole] || 'POLLING_UNIT';

    let queries: any[] = [];

    if (userRole === 'HQ_OFFICER' || userRole === 'HQ_COMMAND') {
      queries.push(query(collection(db, 'alerts'), where('status', 'in', activeStatuses), orderBy('reportedAt', 'desc'), limit(200)));
    } else if (userRole === 'LGA_COMMAND' || userRole === 'LGA_OFFICER') {
      const lgas = userProfile.geo_lgas || (userProfile.geo_lga ? [userProfile.geo_lga] : []);
      if (lgas.length > 0) {
        lgas.forEach((lga: string) => {
          queries.push(query(collection(db, 'alerts'), where('status', 'in', activeStatuses), where('assigned_to', '==', tier), where('geo_lga', '==', lga), orderBy('reportedAt', 'desc'), limit(100)));
        });
      } else {
        queries.push(query(collection(db, 'alerts'), where('status', 'in', activeStatuses), where('assigned_to', '==', tier), where('geo_lga', '==', 'NONE'), orderBy('reportedAt', 'desc'), limit(100)));
      }
    } else if (userRole === 'WARD_COMMAND' || userRole === 'WARD_OFFICER') {
      const wards = userProfile.geo_wards || (userProfile.geo_ward ? [userProfile.geo_ward] : []);
      if (wards.length > 0) {
        wards.forEach((ward: string) => {
          queries.push(query(collection(db, 'alerts'), where('status', 'in', activeStatuses), where('assigned_to', '==', tier), where('geo_ward', '==', ward), orderBy('reportedAt', 'desc'), limit(100)));
        });
      } else {
        queries.push(query(collection(db, 'alerts'), where('status', 'in', activeStatuses), where('assigned_to', '==', tier), where('geo_ward', '==', 'NONE'), orderBy('reportedAt', 'desc'), limit(100)));
      }
    } else if (userRole === 'UNIT_COMMAND' || userRole === 'POLLING_OFFICER' || userRole === 'POLLING_UNIT_OFFICER') {
      const pus = userProfile.geo_pus || (userProfile.geo_pu ? [userProfile.geo_pu] : []);
      if (pus.length > 0) {
        pus.forEach((pu: string) => {
          queries.push(query(collection(db, 'alerts'), where('status', 'in', activeStatuses), where('assigned_to', '==', tier), where('geo_pu', '==', pu), orderBy('reportedAt', 'desc'), limit(100)));
        });
      } else {
        queries.push(query(collection(db, 'alerts'), where('status', 'in', activeStatuses), where('assigned_to', '==', tier), where('geo_pu', '==', 'NONE'), orderBy('reportedAt', 'desc'), limit(100)));
      }
    } else {
      queries.push(query(collection(db, 'alerts'), where('status', 'in', activeStatuses), where('assigned_to', '==', tier), orderBy('reportedAt', 'desc'), limit(200)));
    }

    setAlerts([]);

    const unsubscribers = queries.map((q, idx) => {
      return onSnapshot(q, (snap: any) => {
        setAlerts(prev => {
          const others = prev.filter(p => !snap.docs.some((d: any) => d.id === p.id));
          const updated = [...others, ...snap.docs.map((d: any) => ({ id: d.id, ...d.data() } as Alert))];
          return updated.sort((a, b) => {
            const timeA = a.reportedAt?.seconds || 0;
            const timeB = b.reportedAt?.seconds || 0;
            return timeB - timeA;
          });
        });
      }, err => console.error(`[HQ] Scoped active alerts stream error (query ${idx}):`, err));
    });

    return () => unsubscribers.forEach(unsub => unsub());
  }, [user, userRole, userProfile]);

  // Resolved history stream
  useEffect(() => {
    if (!user || !userProfile) return;
    
    // Normalized statuses for history
    const tierMap: Record<string, string> = { 
      LGA_COMMAND: 'LGA', 
      WARD_COMMAND: 'WARD', 
      UNIT_COMMAND: 'POLLING_UNIT',
      LGA_OFFICER: 'LGA', // Legacy support
      WARD_OFFICER: 'WARD',
      POLLING_UNIT_OFFICER: 'POLLING_UNIT'
    };
    const tier = tierMap[userRole] || 'POLLING_UNIT';

    let queries: any[] = [];

    if (userRole === 'HQ_OFFICER' || userRole === 'HQ_COMMAND') {
      queries.push(query(collection(db, 'alerts'), where('status', '==', 'RESOLVED'), orderBy('reportedAt', 'desc'), limit(100)));
    } else if (userRole === 'LGA_COMMAND' || userRole === 'LGA_OFFICER') {
      const lgas = userProfile.geo_lgas || (userProfile.geo_lga ? [userProfile.geo_lga] : []);
      if (lgas.length > 0) {
        lgas.forEach((lga: string) => {
          queries.push(query(collection(db, 'alerts'), where('status', '==', 'RESOLVED'), where('assigned_to', '==', tier), where('geo_lga', '==', lga), orderBy('reportedAt', 'desc'), limit(50)));
        });
      } else {
        queries.push(query(collection(db, 'alerts'), where('status', '==', 'RESOLVED'), where('assigned_to', '==', tier), where('geo_lga', '==', 'NONE'), orderBy('reportedAt', 'desc'), limit(50)));
      }
    } else if (userRole === 'WARD_COMMAND' || userRole === 'WARD_OFFICER') {
      const wards = userProfile.geo_wards || (userProfile.geo_ward ? [userProfile.geo_ward] : []);
      if (wards.length > 0) {
        wards.forEach((ward: string) => {
          queries.push(query(collection(db, 'alerts'), where('status', '==', 'RESOLVED'), where('assigned_to', '==', tier), where('geo_ward', '==', ward), orderBy('reportedAt', 'desc'), limit(50)));
        });
      } else {
        queries.push(query(collection(db, 'alerts'), where('status', '==', 'RESOLVED'), where('assigned_to', '==', tier), where('geo_ward', '==', 'NONE'), orderBy('reportedAt', 'desc'), limit(50)));
      }
    } else if (userRole === 'UNIT_COMMAND' || userRole === 'POLLING_OFFICER' || userRole === 'POLLING_UNIT_OFFICER') {
      const pus = userProfile.geo_pus || (userProfile.geo_pu ? [userProfile.geo_pu] : []);
      if (pus.length > 0) {
        pus.forEach((pu: string) => {
          queries.push(query(collection(db, 'alerts'), where('status', '==', 'RESOLVED'), where('assigned_to', '==', tier), where('geo_pu', '==', pu), orderBy('reportedAt', 'desc'), limit(50)));
        });
      } else {
        queries.push(query(collection(db, 'alerts'), where('status', '==', 'RESOLVED'), where('assigned_to', '==', tier), where('geo_pu', '==', 'NONE'), orderBy('reportedAt', 'desc'), limit(50)));
      }
    } else {
      queries.push(query(collection(db, 'alerts'), where('status', '==', 'RESOLVED'), where('assigned_to', '==', tier), orderBy('reportedAt', 'desc'), limit(100)));
    }

    setHistory([]);

    const unsubscribers = queries.map((q, idx) => {
      return onSnapshot(q, (snap: any) => {
        setHistory(prev => {
          const others = prev.filter(p => !snap.docs.some((d: any) => d.id === p.id));
          const updated = [...others, ...snap.docs.map((d: any) => ({ id: d.id, ...d.data() } as Alert))];
          return updated.sort((a, b) => {
            const timeA = a.reportedAt?.seconds || 0;
            const timeB = b.reportedAt?.seconds || 0;
            return timeB - timeA;
          });
        });
      }, err => console.error(`[HQ] History stream error (query ${idx}):`, err));
    });

    return () => unsubscribers.forEach(unsub => unsub());
  }, [user, userRole, userProfile]);

  // Load all users to map telemetry to sector profiles
  useEffect(() => {
    if (!user) return;
    const q = query(collection(db, 'users'));
    const unsub = onSnapshot(q, (snap: any) => {
      const mapping: Record<string, any> = {};
      snap.docs.forEach((doc: any) => {
        mapping[doc.id] = doc.data();
      });
      setUsersMap(mapping);
    });
    return () => unsub();
  }, [user]);

  // Live Agent Tracking (RTDB Migration for Scale) + Citizen Tracking (Firestore)
  useEffect(() => {
    if (!user) return;
    const trackingRef = dbRef(rtdb, 'tracking');
    let rtdbLocations: any[] = [];
    let firestoreLocations: any[] = [];

    const isHq = userRole === 'HQ_OFFICER' || userRole === 'HQ_COMMAND';

    const updateLocations = () => {
      const combined = [...rtdbLocations, ...firestoreLocations];
      const scopedLocations = combined.filter(loc => {
        if (isHq) return true;
        
        // Citizens in SOS are only visible if they have an active alert in our scoped alerts
        if (loc.status === 'DURESS' || loc.mode === 'sos') {
          return alerts.some(a => a.reportedBy === loc.user_id);
        }
        
        // Responders are mapped using usersMap directory sector assignment
        const profile = usersMap[loc.user_id];
        if (!profile) return false;
        
        if (userRole === 'LGA_COMMAND' || userRole === 'LGA_OFFICER') {
          return profile.geo_lga === userProfile?.geo_lga;
        }
        if (userRole === 'WARD_COMMAND' || userRole === 'WARD_OFFICER') {
          return profile.geo_ward === userProfile?.geo_ward;
        }
        if (userRole === 'UNIT_COMMAND' || userRole === 'POLLING_UNIT_OFFICER' || userRole === 'POLLING_OFFICER') {
          return profile.geo_pu === userProfile?.geo_pu;
        }
        return false;
      });

      setAgentLocations(scopedLocations);
    };

    const unsubRTDB = onValue(trackingRef, (snapshot) => {
      const now = Date.now();
      if (snapshot.exists()) {
        const data = snapshot.val();
        rtdbLocations = Object.keys(data).map(userId => {
          const agentData = data[userId];
          const heartbeat = agentData.heartbeat || 0;
          const diff = now - heartbeat;
          
          let status = agentData.status || 'PATROLLING';
          if (diff > 300000) status = 'OFFLINE';
          else if (diff > 120000) status = 'DISCONNECTED';

          let pathArray: any[] = [];
          if (agentData.path && typeof agentData.path === 'object') {
            pathArray = Object.keys(agentData.path)
              .map(key => agentData.path[key])
              .sort((a, b) => (a.t || 0) - (b.t || 0));
          }

          return {
            id: userId,
            user_id: userId,
            ...agentData,
            status,
            path: pathArray,
            lastSeenSeconds: Math.floor(diff / 1000)
          };
        });
      } else {
        rtdbLocations = [];
      }
      updateLocations();
    });

    // Listen to citizen tracking in Firestore
    const qTracking = query(collection(db, 'tracking'));
    const unsubFirestore = onSnapshot(qTracking, (snap: any) => {
      firestoreLocations = snap.docs.map((doc: any) => {
        const d = doc.data();
        return {
          id: doc.id,
          user_id: doc.id,
          lat: d.lat,
          lng: d.lng,
          status: 'DURESS', // Always show citizens as DURESS since they only track during SOS
          displayName: 'CITIZEN SOS',
          timestamp: d.updatedAt,
          path: d.path || [],
          telemetry: {
            speed: d.speed,
            heading: d.heading
          }
        };
      });
      updateLocations();
    }, err => console.error('[HQ] Firestore Tracking Stream error:', err));

    return () => {
      unsubRTDB();
      unsubFirestore();
    };
  }, [user, usersMap, userRole, userProfile, alerts]);

  const escalateAlert = useCallback(async (alertId: string, currentTier: string) => {
    const next = currentTier === 'POLLING_UNIT' ? 'WARD' : currentTier === 'WARD' ? 'LGA' : 'HQ';
    try {
      const func = httpsCallable(functions, 'adminEscalateAlert');
      await func({ alertId, targetTier: next });
    } catch (e: any) {
      console.error('[HQ_ESCALATE_ERR]', e);
      throw e;
    }
  }, []);

  const hqOverride = useCallback(async (alertId: string) => {
    try {
      const func = httpsCallable(functions, 'adminEscalateAlert');
      await func({ alertId, targetTier: 'HQ' });
    } catch (e: any) {
      console.error('[HQ_OVERRIDE_ERR]', e);
      throw e;
    }
  }, []);

  const resolveAlert = useCallback(async (alertId: string) => {
    try {
      const func = httpsCallable(functions, 'adminResolveAlert');
      await func({ alertId });
    } catch (e: any) {
      console.error('[HQ_RESOLVE_ERR]', e);
      throw e;
    }
  }, []);

  const dispatchAlert = useCallback(async (alertId: string, responderUid: string) => {
    try {
      const func = httpsCallable(functions, 'adminDispatchAlert');
      await func({ alertId, responderUid });
    } catch (e: any) {
      console.error('[HQ_DISPATCH_ERR]', e);
      throw e;
    }
  }, []);

  const [filterLga, setFilterLga] = useState('ALL');

  const filtered = alerts.filter(a => {
    if (filterStatus === 'CRITICAL') {
      if (a.status !== 'DURESS' && a.priority !== 'CRITICAL') return false;
    } else if (filterStatus !== 'ALL' && a.status !== filterStatus) return false;
    if (filterTier !== 'ALL' && a.assigned_to !== filterTier) return false;
    if (filterLga !== 'ALL' && a.geo_lga !== filterLga) return false;
    return true;
  });

  const duressCount = alerts.filter(a => a.status === 'DURESS').length;

  const handleLogout = async () => { 
    await signOut(auth); 
    // Clear session cookie for Next.js middleware compatibility in local development
    document.cookie = '__session=; path=/; expires=Thu, 01 Jan 1970 00:00:00 GMT; SameSite=Strict; Secure';
    router.replace('/login'); 
  };

  if (authLoading) return (
    <div style={{ height: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'var(--bg-primary)' }}>
      <Loader2 size={32} color="var(--accent)" className="spin" />
    </div>
  );
  if (!user) return null;

  const isHqUser = userRole === 'HQ_OFFICER' || userRole === 'HQ_COMMAND';

  return (
    <div style={{ display: 'flex', height: '100vh', background: 'var(--bg-primary)', overflow: 'hidden', color: 'var(--text-primary)', padding: '16px', gap: '16px', boxSizing: 'border-box' }}>
      <SystemAlertListener />

      <aside className="tactical-panel glass" style={{ width: 280, display: 'flex', flexDirection: 'column', padding: '24px 16px', flexShrink: 0, zIndex: 100, maxHeight: '100%' }}>
        {/* Sidebar Header (Fixed at top) */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 24, padding: '0 8px', flexShrink: 0 }}>
          <div className="pulse-emerald" style={{ background: 'var(--primary)', padding: 10, borderRadius: 12, display: 'flex', alignItems: 'center', justifyContent: 'center', boxShadow: 'var(--primary-glow)' }}>
            <ShieldAlert size={24} color="#fff" />
          </div>
          <div>
            <h1 style={{ fontSize: 16, fontWeight: 900, letterSpacing: 1, textTransform: 'uppercase' }}>
              {userRole === 'LGA_COMMAND' || userRole === 'LGA_OFFICER' ? 'LGA Command' :
               userRole === 'WARD_COMMAND' || userRole === 'WARD_OFFICER' ? 'Ward Command' :
               userRole === 'UNIT_COMMAND' || userRole === 'POLLING_UNIT_OFFICER' || userRole === 'POLLING_OFFICER' ? 'PU Command' :
               'Command HQ'}
            </h1>
            <p style={{ fontSize: 9, color: 'var(--primary)', fontWeight: 800, letterSpacing: 2.5 }}>
              {userRole === 'LGA_COMMAND' || userRole === 'LGA_OFFICER' ? (userProfile?.geo_lga || 'LGA').toUpperCase() + ' SECTOR' :
               userRole === 'WARD_COMMAND' || userRole === 'WARD_OFFICER' ? (userProfile?.geo_ward || 'WARD').toUpperCase() + ' SECTOR' :
               userRole === 'UNIT_COMMAND' || userRole === 'POLLING_UNIT_OFFICER' || userRole === 'POLLING_OFFICER' ? (userProfile?.geo_pu || 'PU').toUpperCase() + ' SECTOR' :
               'TACTICAL MONITOR'}
            </p>
          </div>
        </div>

        {/* Scrollable Navigation & Metrics Container */}
        <div style={{ flex: 1, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 24, paddingRight: 4, marginBottom: 16 }}>
          <nav style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
            <p style={{ fontSize: 9, fontWeight: 900, color: 'var(--text-dim)', letterSpacing: 2, marginBottom: 8, paddingLeft: 12 }}>SYSTEM NAVIGATION</p>
            <NavItem icon={<MapIcon size={18} />} label="Intelligence Map" active={activeTab === 'map'} onClick={() => setActiveTab('map')} />
            <NavItem icon={<Activity size={18} />} label="Incident Feed" active={activeTab === 'alerts'} onClick={() => setActiveTab('alerts')} badge={alerts.length > 0 ? alerts.length : undefined} />
            <NavItem icon={<Clock size={18} />} label="Mission History" active={activeTab === 'history'} onClick={() => setActiveTab('history')} />
            
            {isHqUser && (
              <>
                <NavItem icon={<Radio size={18} />} label="Mass Broadcast" active={activeTab === 'broadcast'} onClick={() => setActiveTab('broadcast')} />
                <div style={{ margin: '20px 0', height: 1, background: 'var(--border)' }}></div>
                <p style={{ fontSize: 9, fontWeight: 900, color: 'var(--text-dim)', letterSpacing: 2, marginBottom: 8, paddingLeft: 12 }}>ADMINISTRATION</p>
                <NavItem icon={<Users size={18} />} label="Agent Directory" active={activeTab === 'admin'} onClick={() => setActiveTab('admin')} />
                <NavItem icon={<Activity size={18} />} label="Forensic Audit" active={activeTab === 'audit'} onClick={() => setActiveTab('audit')} />
                <NavItem icon={<Settings size={18} />} label="System Logic" active={activeTab === 'settings'} onClick={() => setActiveTab('settings')} />
                <NavItem icon={<ShieldAlert size={18} />} label="Uninstall Requests" active={activeTab === 'uninstall'} onClick={() => setActiveTab('uninstall')} />
              </>
            )}
          </nav>

          <div style={{ display: 'flex', flexDirection: 'column', gap: 8, padding: '16px', background: 'var(--input-bg)', borderRadius: 16, border: '1px solid var(--border)' }}>
            <p style={{ fontSize: 9, fontWeight: 900, color: 'var(--text-muted)', letterSpacing: 1.5, marginBottom: 4 }}>UNIT STATUS</p>
            <StatBar label="DURESS" value={duressCount} color="var(--duress)" onClick={() => { setActiveTab('alerts'); setFilterStatus('DURESS'); }} />
            <StatBar label="ACTIVE" value={alerts.length} color="var(--warning)" onClick={() => { setActiveTab('alerts'); setFilterStatus('ACTIVE'); }} />
            <StatBar label="ONLINE" value={agentLocations.length} color="var(--success)" onClick={() => setActiveTab('map')} />
          </div>
        </div>

        {/* Action Button (Fixed at bottom) */}
        <button onClick={handleLogout} className="btn-tactical"
          style={{ width: '100%', background: 'var(--duress-dim)', color: 'var(--duress)', border: '1px solid rgba(239,68,68,0.2)', flexShrink: 0 }}>
          <LogOut size={14} /> TERMINATE UPLINK
        </button>
      </aside>

      <main className="tactical-panel glass" style={{ flex: 1, display: 'flex', flexDirection: 'column', overflow: 'hidden', position: 'relative' }}>
        <header style={{ padding: '0 24px', height: 72, borderBottom: '1px solid var(--border)', display: 'flex', alignItems: 'center', justifyContent: 'space-between', flexShrink: 0 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 24 }}>
            <div>
              <h2 style={{ fontSize: 18, fontWeight: 900, textTransform: 'uppercase', letterSpacing: 1 }}>
                {activeTab === 'map' && (isHqUser ? 'Statewide Monitoring' : `${userProfile?.geo_lga || userProfile?.geo_ward || userProfile?.geo_pu || 'Sector'} Monitoring`)}
                {activeTab === 'alerts' && (isHqUser ? 'Statewide Incident Command' : `${userProfile?.geo_lga || userProfile?.geo_ward || userProfile?.geo_pu || 'Sector'} Command Feed`)}
                {activeTab === 'history' && (isHqUser ? 'Statewide Mission Logs' : `${userProfile?.geo_lga || userProfile?.geo_ward || userProfile?.geo_pu || 'Sector'} Archive`)}
                {activeTab === 'broadcast' && 'Signal Dispatch'}
                {activeTab === 'admin' && 'Staff Command'}
                {activeTab === 'audit' && 'Accountability'}
                {activeTab === 'settings' && 'Platform Core'}
              </h2>
            </div>
            <div style={{ height: 24, width: 1, background: 'var(--border)' }}></div>
            <div style={{ display: 'flex', gap: 16 }}>
               <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                  <div style={{ width: 8, height: 8, borderRadius: '50%', background: 'var(--success)', boxShadow: 'var(--success-glow)' }} className="pulse-emerald"></div>
                  <span style={{ fontSize: 11, fontWeight: 700, color: 'var(--success)' }}>LIVE UPLINK</span>
               </div>
               <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                  <Clock size={14} color="var(--text-muted)" />
                  <span style={{ fontSize: 11, fontWeight: 700, color: 'var(--text-muted)', fontFamily: 'monospace' }}>{timeString}</span>
               </div>
            </div>
          </div>

          <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
            {duressCount > 0 && (
              <div className="pulse-crimson" style={{ 
                background: 'var(--duress-dim)',
                border: '1px solid var(--duress)', 
                borderRadius: 8, 
                padding: '8px 16px', 
                display: 'flex', 
                alignItems: 'center', 
                gap: 8,
                boxShadow: 'var(--duress-glow)'
              }}>
                <AlertTriangle size={14} color="var(--duress)" />
                <span style={{ fontSize: 11, fontWeight: 900, color: 'var(--duress)' }}>{duressCount} DURESS EMERGENCY</span>
              </div>
            )}
            
            {/* Theme Toggle Button */}
            <button 
              onClick={() => setTheme(t => t === 'light' ? 'dark' : 'light')}
              title={`Switch to ${theme === 'light' ? 'Dark' : 'Light'} Mode`}
              className="btn-tactical btn-secondary"
              style={{
                borderRadius: '50%',
                width: 40,
                height: 40,
                padding: 0,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                boxShadow: 'var(--shadow-sm)',
              }}
            >
              {theme === 'light' ? <Moon size={18} /> : <Sun size={18} />}
            </button>

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
                <option value="OPEN">OPEN</option>
                <option value="ACTIVE">ACTIVE</option>
                <option value="DURESS">DURESS</option>
                <option value="CRITICAL">CRITICAL</option>
              </select>
              {isHqUser ? (
                <>
                  <select value={filterLga} onChange={e => setFilterLga(e.target.value)} style={overlaySelect}>
                    <option value="ALL">ALL SECTORS (LGA)</option>
                    {plateauTacticalMap.map(lga => <option key={lga.id} value={lga.name}>{lga.name.toUpperCase()}</option>)}
                  </select>
                  <select value={filterTier} onChange={e => setFilterTier(e.target.value)} style={overlaySelect}>
                    <option value="ALL">ALL TIERS</option>
                    <option value="POLLING_UNIT">PU</option>
                    <option value="WARD">WARD</option>
                    <option value="LGA">LGA</option>
                    <option value="HQ">HQ</option>
                  </select>
                </>
              ) : (
                <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
                  <span style={{ fontSize: 9, fontWeight: 900, background: 'var(--accent-dim)', color: 'var(--accent)', padding: '2px 8px', borderRadius: 4, textTransform: 'uppercase', fontFamily: 'monospace' }}>
                    {userRole === 'LGA_COMMAND' || userRole === 'LGA_OFFICER' ? `LGA: ${userProfile?.geo_lga || 'NONE'}` :
                     userRole === 'WARD_COMMAND' || userRole === 'WARD_OFFICER' ? `WARD: ${userProfile?.geo_ward || 'NONE'}` :
                     `PU: ${userProfile?.geo_pu || 'NONE'}`}
                  </span>
                </div>
              )}
            </div>
          </div>
        )}

        <div style={{ flex: 1, overflow: activeTab === 'map' ? 'hidden' : 'auto', padding: activeTab === 'map' ? 0 : '32px 40px' }}>
          {activeTab === 'map' && (
            <div style={{ position: 'relative', height: '100%', width: '100%' }}>
              <LiveMap alerts={filtered} agents={agentLocations} onResolve={resolveAlert} onEscalate={escalateAlert} theme={theme} />
              <div className="glass fade-in" style={{ position: 'absolute', top: 24, right: 24, width: 320, maxHeight: 'calc(100% - 48px)', borderRadius: 20, display: 'flex', flexDirection: 'column', overflow: 'hidden', border: '1px solid var(--border)', boxShadow: '0 20px 40px rgba(0,0,0,0.4)' }}>
                <div style={{ padding: '20px', borderBottom: '1px solid var(--border)', background: 'var(--bg-secondary)' }}>
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
                  ) : filtered.map(a => {
                    const statusColors: any = {
                      'OPEN': 'var(--warning)',
                      'ACTIVE': 'var(--warning)',
                      'DISPATCHED': 'var(--info)',
                      'ACKNOWLEDGED': 'var(--success)',
                      'ON_ROUTE': 'var(--accent)',
                      'ON_SITE': 'var(--success)',
                      'DURESS': 'var(--duress)'
                    };
                    return (
                      <div key={a.id} className="card-hover" style={{ background: 'var(--input-bg)', borderRadius: 12, padding: '14px', borderLeft: `4px solid ${statusColors[a.status] || 'white'}` }}>
                        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 6 }}>
                          <span style={{ fontSize: 11, fontWeight: 900 }}>{a.type}</span>
                          <span style={{ fontSize: 9, fontWeight: 800, color: statusColors[a.status], letterSpacing: 0.5 }}>{a.status}</span>
                        </div>
                        <p style={{ fontSize: 11, color: 'var(--text-muted)', lineHeight: 1.4, marginBottom: 8 }}>{a.description?.substring(0, 60)}...</p>
                        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                          <span style={{ fontSize: 9, fontWeight: 800, color: 'var(--text-dim)' }}>{a.geo_lga?.toUpperCase()}</span>
                          <button onClick={() => setActiveTab('alerts')} style={{ background: 'transparent', border: 'none', color: 'var(--accent)', fontSize: 10, fontWeight: 900, cursor: 'pointer' }}>ENGAGE ›</button>
                        </div>
                      </div>
                    );
                  })}
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
                {isHqUser ? (
                  <div style={{ marginLeft: 'auto', display: 'flex', gap: 10 }}>
                     <select value={filterStatus} onChange={e => setFilterStatus(e.target.value)} style={fSel}>
                      <option value="ALL">ALL STATUS</option>
                      <option value="OPEN">OPEN</option>
                      <option value="ACTIVE">ACTIVE</option>
                      <option value="DURESS">DURESS</option>
                    </select>
                     <select value={filterLga} onChange={e => setFilterLga(e.target.value)} style={fSel}>
                      <option value="ALL">ALL SECTORS (LGA)</option>
                      {plateauTacticalMap.map(lga => <option key={lga.id} value={lga.name}>{lga.name.toUpperCase()}</option>)}
                    </select>
                    <select value={filterTier} onChange={e => setFilterTier(e.target.value)} style={fSel}>
                      <option value="ALL">ALL TIERS</option>
                      <option value="POLLING_UNIT">PU</option>
                      <option value="WARD">WARD</option>
                      <option value="LGA">LGA</option>
                      <option value="HQ">HQ</option>
                    </select>
                  </div>
                ) : (
                  <div style={{ marginLeft: 'auto', display: 'flex', gap: 10, alignItems: 'center' }}>
                     <select value={filterStatus} onChange={e => setFilterStatus(e.target.value)} style={fSel}>
                      <option value="ALL">ALL STATUS</option>
                      <option value="OPEN">OPEN</option>
                      <option value="ACTIVE">ACTIVE</option>
                      <option value="DURESS">DURESS</option>
                    </select>
                    <span style={{ fontSize: 10, fontWeight: 900, background: 'var(--accent-dim)', color: 'var(--accent)', padding: '6px 12px', borderRadius: 8, textTransform: 'uppercase', fontFamily: 'monospace' }}>
                      {userRole === 'LGA_COMMAND' || userRole === 'LGA_OFFICER' ? `LGA: ${userProfile?.geo_lga || 'NONE'}` :
                       userRole === 'WARD_COMMAND' || userRole === 'WARD_OFFICER' ? `WARD: ${userProfile?.geo_ward || 'NONE'}` :
                       `PU: ${userProfile?.geo_pu || 'NONE'}`}
                    </span>
                  </div>
                )}
              </div>
              {filtered.length === 0 ? (
                <div className="glass" style={{ padding: '80px', textAlign: 'center', borderRadius: 24 }}>
                  <CheckCircle size={64} color="var(--success)" style={{ opacity: 0.3, marginBottom: 20 }} />
                  <h3 style={{ fontSize: 20, fontWeight: 900, marginBottom: 8 }}>ALL SECTORS CLEAR</h3>
                  <p style={{ color: 'var(--text-muted)' }}>No active incidents require intervention at this time.</p>
                </div>
              ) : (
                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(380px, 1fr))', gap: 24 }}>
                  {filtered.map(a => <AlertCard key={a.id} alert={a} agents={agentLocations} usersMap={usersMap} onDispatch={dispatchAlert} onEscalate={escalateAlert} onResolve={resolveAlert} onHqOverride={hqOverride} />)}
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
                    <tr style={{ background: 'var(--input-bg)', borderBottom: '1px solid var(--border)' }}>
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
                          <button 
                            onClick={() => setSelectedReport(a)}
                            style={{ background: 'var(--accent-dim)', color: 'var(--accent)', border: 'none', padding: '6px 12px', borderRadius: 8, fontSize: 10, fontWeight: 900, cursor: 'pointer' }}
                          >
                            VIEW
                          </button>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          )}

          {activeTab === 'analytics' && <Analytics />}

          {activeTab === 'broadcast' && <MassBroadcast />}
          {activeTab === 'admin' && <AdminDirectory />}
          {activeTab === 'settings' && <SystemConfig />}
          {activeTab === 'audit' && <AuditLogs />}
          {activeTab === 'uninstall' && <UninstallRequests />}
        </div>
      </main>

      {/* Post-Action Mission Report Modal */}
      {selectedReport && (() => {
        const reporterId = selectedReport.reportedBy || '';
        const reporterProfile = usersMap[reporterId];

        let reporterName = 'Anonymous Citizen';
        let reporterContact = 'No Contact Info';
        let reporterType = 'Citizen';

        if (reporterProfile) {
          reporterName = reporterProfile.displayName || reporterProfile.name || 'Anonymous Officer';
          reporterContact = reporterProfile.email || reporterProfile.phone || 'No Email';
          reporterType = reporterProfile.roleLabel || reporterProfile.role || reporterProfile.type || 'Field Unit';
        } else if (reporterId) {
          if (reporterId.includes('@')) {
            reporterName = reporterId.split('@')[0].toUpperCase();
            reporterContact = reporterId;
            reporterType = reporterId.endsWith('operationrainbow.plateau.gov.ng') ? 'Field Operator' : 'External Reporter';
          } else if (reporterId.startsWith('+') || /^\d+$/.test(reporterId)) {
            reporterName = 'Citizen Reporter';
            reporterContact = reporterId;
            reporterType = 'Mobile App SOS';
          } else {
            reporterContact = reporterId;
          }
        }

        const isDuress = selectedReport.status === 'DURESS';
        const priorityColors: Record<string, string> = {
          'LOW': 'var(--success)',
          'MEDIUM': 'var(--warning)',
          'HIGH': 'var(--duress)',
          'CRITICAL': 'var(--duress)'
        };
        const priorityGlows: Record<string, string> = {
          'LOW': 'var(--success-glow)',
          'MEDIUM': 'var(--warning-glow)',
          'HIGH': 'var(--duress-glow)',
          'CRITICAL': 'var(--duress-glow)'
        };
        
        const prioColor = priorityColors[selectedReport.priority] || 'var(--text-muted)';
        const prioGlow = priorityGlows[selectedReport.priority] || 'none';

        return (
          <div style={{
            position: 'fixed',
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            backgroundColor: 'rgba(9, 13, 22, 0.85)',
            backdropFilter: 'blur(12px)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            zIndex: 9999,
            padding: '24px'
          }} onClick={() => setSelectedReport(null)}>
            <div className="tactical-panel glass fade-in" style={{
              width: '100%',
              maxWidth: '800px',
              maxHeight: '90vh',
              background: 'var(--bg-secondary)',
              borderRadius: '24px',
              overflowY: 'auto',
              border: '1px solid var(--border)',
              boxShadow: 'var(--shadow-md)',
              display: 'flex',
              flexDirection: 'column',
              padding: 0
            }} onClick={(e) => e.stopPropagation()}>
              
              {/* Header HUD */}
              <div style={{
                display: 'flex',
                justifyContent: 'space-between',
                alignItems: 'center',
                padding: '24px 32px',
                borderBottom: '1px solid var(--border)',
                background: 'var(--bg-card)'
              }}>
                <div>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 4 }}>
                    <span style={{ fontSize: 9, fontWeight: 900, color: 'var(--primary)', letterSpacing: 2, fontFamily: "'Outfit', sans-serif" }}>POST-ACTION MISSION REPORT</span>
                    <span style={{ fontSize: 8, fontWeight: 900, background: 'var(--success-dim)', color: 'var(--success)', border: '1px solid var(--success)', padding: '2px 8px', borderRadius: 20, boxShadow: 'var(--success-glow)' }}>ARCHIVED & RESOLVED</span>
                  </div>
                  <h3 style={{ fontSize: 20, fontWeight: 900, color: isDuress ? 'var(--duress)' : 'var(--text-primary)', fontFamily: "'Outfit', sans-serif", margin: 0 }}>
                    {isDuress ? 'DURESS CRISIS LOG' : selectedReport.type}
                  </h3>
                </div>
                <button 
                  onClick={() => setSelectedReport(null)}
                  style={{
                    background: 'var(--input-bg)',
                    border: '1px solid var(--border)',
                    color: 'var(--text-primary)',
                    borderRadius: '50%',
                    width: 36,
                    height: 36,
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    cursor: 'pointer',
                    transition: 'all 0.2s',
                    boxShadow: 'var(--shadow-sm)'
                  }}
                  className="card-hover"
                >
                  <X size={18} />
                </button>
              </div>

              {/* Modal Body */}
              <div style={{ padding: 32, display: 'flex', flexDirection: 'column', gap: 24 }}>
                
                {/* Tactical Metadata Grid */}
                <div style={{ 
                  display: 'grid', 
                  gridTemplateColumns: '1fr 1fr', 
                  gap: 20, 
                  padding: 20, 
                  background: 'var(--input-bg)', 
                  borderRadius: 20, 
                  border: '1px solid var(--border)' 
                }}>
                  {/* Left Column: Scope and Status */}
                  <div>
                    <h4 style={{ fontSize: 10, fontWeight: 900, color: 'var(--primary)', letterSpacing: 1.5, textTransform: 'uppercase', marginBottom: 12, fontFamily: "'Outfit', sans-serif" }}>OPERATIONAL DETAILS</h4>
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                        <span style={{ fontSize: 11, color: 'var(--text-muted)' }}>Assigned Scope:</span>
                        <span style={{ fontSize: 11, fontWeight: 800, color: 'var(--text-primary)' }}>{selectedReport.assigned_to}</span>
                      </div>
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                        <span style={{ fontSize: 11, color: 'var(--text-muted)' }}>Priority Level:</span>
                        <span style={{ 
                          fontSize: 9, 
                          fontWeight: 900, 
                          padding: '4px 10px', 
                          background: `${prioColor}15`, 
                          color: prioColor, 
                          border: `1px solid ${prioColor}44`, 
                          borderRadius: 20,
                          boxShadow: prioGlow
                        }}>{selectedReport.priority}</span>
                      </div>
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                        <span style={{ fontSize: 11, color: 'var(--text-muted)' }}>Incident ID:</span>
                        <span style={{ fontSize: 10, fontWeight: 600, color: 'var(--text-dim)', fontFamily: 'monospace' }}>{selectedReport.id}</span>
                      </div>
                    </div>
                  </div>

                  {/* Right Column: Location & Resolution */}
                  <div style={{ borderLeft: '1px solid var(--border)', paddingLeft: 20 }}>
                    <h4 style={{ fontSize: 10, fontWeight: 900, color: 'var(--primary)', letterSpacing: 1.5, textTransform: 'uppercase', marginBottom: 12, fontFamily: "'Outfit', sans-serif" }}>GEOSPATIAL & ARCHIVE</h4>
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                        <span style={{ fontSize: 11, color: 'var(--text-muted)' }}>LGA / Sector:</span>
                        <span style={{ fontSize: 11, fontWeight: 800, color: 'var(--text-primary)', textTransform: 'uppercase' }}>{selectedReport.geo_lga || 'STATE HQ'}</span>
                      </div>
                      {selectedReport.geo_ward && (
                        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                          <span style={{ fontSize: 11, color: 'var(--text-muted)' }}>Ward:</span>
                          <span style={{ fontSize: 11, fontWeight: 700, color: 'var(--text-primary)', textTransform: 'uppercase' }}>{selectedReport.geo_ward}</span>
                        </div>
                      )}
                      {selectedReport.lat && selectedReport.lng && (
                        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                          <span style={{ fontSize: 11, color: 'var(--text-muted)' }}>Coordinates:</span>
                          <span style={{ fontSize: 10, fontWeight: 600, color: 'var(--text-dim)', fontFamily: 'monospace' }}>{selectedReport.lat.toFixed(5)}°N, {selectedReport.lng.toFixed(5)}°E</span>
                        </div>
                      )}
                    </div>
                  </div>
                </div>

                {/* Description Section */}
                <div>
                  <h4 style={{ fontSize: 10, fontWeight: 900, color: 'var(--primary)', letterSpacing: 1.5, textTransform: 'uppercase', marginBottom: 8, fontFamily: "'Outfit', sans-serif" }}>INITIAL REPORT DESCRIPTION</h4>
                  <div style={{ 
                    padding: '16px 20px', 
                    background: 'var(--input-bg)', 
                    borderRadius: 16, 
                    border: '1px solid var(--border)',
                    fontSize: 13,
                    color: 'var(--text-primary)',
                    lineHeight: 1.6
                  }}>
                    {selectedReport.description || 'No description provided.'}
                  </div>
                </div>

                {/* Reporter & Resolution Profile Deck */}
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 20 }}>
                  {/* Reporter Profile */}
                  <div style={{ padding: 20, background: 'var(--input-bg)', borderRadius: 20, border: '1px solid var(--border)' }}>
                    <h4 style={{ fontSize: 9, fontWeight: 900, color: 'var(--primary)', letterSpacing: 1.5, textTransform: 'uppercase', marginBottom: 12, fontFamily: "'Outfit', sans-serif" }}>REPORTER PROFILE</h4>
                    <div style={{ fontSize: 13, fontWeight: 800, color: 'var(--text-primary)' }}>{reporterName}</div>
                    <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 4, fontWeight: 600 }}>{reporterContact}</div>
                    <div style={{ fontSize: 8, color: 'var(--text-dim)', marginTop: 8, fontWeight: 900, textTransform: 'uppercase', letterSpacing: 0.5 }}>
                      SOURCE: {reporterType}
                    </div>
                  </div>

                  {/* Resolution Details */}
                  <div style={{ padding: 20, background: 'var(--input-bg)', borderRadius: 20, border: '1px solid var(--border)' }}>
                    <h4 style={{ fontSize: 9, fontWeight: 900, color: 'var(--primary)', letterSpacing: 1.5, textTransform: 'uppercase', marginBottom: 12, fontFamily: "'Outfit', sans-serif" }}>RESOLUTION LOG</h4>
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
                      <div>
                        <span style={{ fontSize: 10, color: 'var(--text-dim)', display: 'block' }}>RESOLVED BY</span>
                        <span style={{ fontSize: 12, fontWeight: 800, color: 'var(--success)' }}>{selectedReport.resolved_by || 'Unknown Officer'}</span>
                      </div>
                      <div style={{ marginTop: 4 }}>
                        <span style={{ fontSize: 10, color: 'var(--text-dim)', display: 'block' }}>TIMESTAMPS</span>
                        <span style={{ fontSize: 11, fontWeight: 600, color: 'var(--text-primary)' }}>
                          Reported: {selectedReport.reportedAt ? new Date(selectedReport.reportedAt.seconds * 1000).toLocaleString() : '—'}
                        </span>
                      </div>
                    </div>
                  </div>
                </div>

                {/* Complete Forensic Timeline */}
                <div>
                  <h4 style={{ fontSize: 10, fontWeight: 900, color: 'var(--primary)', letterSpacing: 1.5, textTransform: 'uppercase', marginBottom: 12, fontFamily: "'Outfit', sans-serif" }}>FORENSIC INCIDENT AUDIT</h4>
                  {selectedReport.timeline && selectedReport.timeline.length > 0 ? (
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 16, borderLeft: '2px solid var(--border)', paddingLeft: 20, marginLeft: 8, marginTop: 12 }}>
                      {selectedReport.timeline.map((event: any, idx: number) => {
                        const date = new Date(event.timestamp);
                        const formattedTime = date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' }) + ' HRS';
                        const formattedDate = date.toLocaleDateString([], { month: 'short', day: 'numeric' });
                        
                        let eventColor = 'var(--text-muted)';
                        if (event.type === 'CREATED') eventColor = 'var(--warning)';
                        else if (event.type === 'ESCALATION' || event.type === 'SLA_AUTO_ESCALATION') eventColor = 'var(--duress)';
                        else if (event.type === 'DISPATCHED') eventColor = 'var(--accent)';
                        else if (event.type === 'ACKNOWLEDGED') eventColor = 'var(--success)';
                        else if (event.type === 'RESOLVED') eventColor = 'var(--success)';

                        return (
                          <div key={idx} style={{ position: 'relative' }}>
                            {/* Stepper Node Indicator */}
                            <div style={{
                              position: 'absolute',
                              left: -28,
                              top: 2,
                              width: 12,
                              height: 12,
                              borderRadius: '50%',
                              background: 'var(--bg-secondary)',
                              border: `3.5px solid ${eventColor}`,
                              boxShadow: `0 0 6px ${eventColor}`
                            }} />
                            
                            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                              <span style={{ fontSize: 10, fontWeight: 900, color: eventColor, letterSpacing: 0.5 }}>{event.type}</span>
                              <span style={{ fontSize: 9, color: 'var(--text-dim)', fontWeight: 600 }}>{formattedDate} · {formattedTime}</span>
                            </div>
                            
                            <div style={{ fontSize: 11, color: 'var(--text-primary)', marginTop: 4, fontWeight: 700 }}>
                              {event.notes || (event.type === 'CREATED' ? 'Incident created.' : '')}
                            </div>
                            
                            {event.reason && (
                              <div style={{ fontSize: 9, color: 'var(--warning)', marginTop: 2, fontWeight: 700 }}>
                                Reason: <span style={{ color: 'var(--text-muted)' }}>{event.reason}</span>
                              </div>
                            )}
                            
                            <div style={{ fontSize: 8, color: 'var(--text-dim)', marginTop: 4, fontStyle: 'italic', fontWeight: 600 }}>
                              Actor: {event.actor} ({event.role})
                            </div>
                          </div>
                        );
                      })}
                    </div>
                  ) : (
                    <div style={{ 
                      padding: '16px 20px', 
                      background: 'var(--input-bg)', 
                      borderRadius: 16, 
                      border: '1px dashed var(--border)',
                      fontSize: 12,
                      color: 'var(--text-muted)',
                      textAlign: 'center'
                    }}>
                      No forensic timeline events recorded for this incident.
                    </div>
                  )}
                </div>

                {/* Forensic AI Summary */}
                <div style={{
                  padding: 24,
                  background: 'var(--input-bg)',
                  borderRadius: 20,
                  border: '1px solid var(--border)',
                  marginTop: 8
                }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 16 }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                      <Sparkles size={16} style={{ color: 'var(--primary)' }} />
                      <h4 style={{ fontSize: 10, fontWeight: 900, color: 'var(--primary)', letterSpacing: 1.5, textTransform: 'uppercase', margin: 0, fontFamily: "'Outfit', sans-serif" }}>
                        Tactical Forensic AI Analysis
                      </h4>
                    </div>
                    {aiSummary && !isGeneratingSummary && (
                      <button
                        onClick={() => generateAISummary(selectedReport)}
                        style={{
                          background: 'none',
                          border: 'none',
                          color: 'var(--primary)',
                          fontSize: 9,
                          fontWeight: 900,
                          cursor: 'pointer',
                          textDecoration: 'underline',
                          padding: 0
                        }}
                      >
                        REGENERATE
                      </button>
                    )}
                  </div>

                  {!aiSummary && !isGeneratingSummary && (
                    <div style={{ textAlign: 'center', padding: '12px 0' }}>
                      <p style={{ fontSize: 12, color: 'var(--text-muted)', marginBottom: 14 }}>
                        Synthesize raw dispatch timeline, responder telemetry, and incident outcomes into a post-action operational report.
                      </p>
                      <button
                        onClick={() => generateAISummary(selectedReport)}
                        style={{
                          padding: '10px 20px',
                          background: 'var(--primary)',
                          color: '#fff',
                          border: 'none',
                          borderRadius: 10,
                          fontSize: 11,
                          fontWeight: 900,
                          cursor: 'pointer',
                          display: 'inline-flex',
                          alignItems: 'center',
                          gap: 6,
                          boxShadow: 'var(--primary-glow)'
                        }}
                        className="card-hover"
                      >
                        <Sparkles size={12} />
                        GENERATE FORENSIC DEBRIEF
                      </button>
                    </div>
                  )}

                  {isGeneratingSummary && (
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 12, padding: '12px 0' }}>
                      <style dangerouslySetInnerHTML={{__html: `
                        @keyframes pulse {
                          0%, 100% { opacity: 0.6; }
                          50% { opacity: 1; }
                        }
                        .tactical-pulse {
                          animation: pulse 1.5s infinite ease-in-out;
                        }
                      `}} />
                      <div style={{ display: 'flex', alignItems: 'center', gap: 10, color: 'var(--primary)', fontSize: 12, fontWeight: 700 }}>
                        <Loader2 size={16} className="animate-spin" />
                        <span>Querying Gemini AI Engine...</span>
                      </div>
                      <div className="tactical-pulse" style={{ height: 16, width: '90%', borderRadius: 4, background: 'var(--bg-secondary)' }} />
                      <div className="tactical-pulse" style={{ height: 16, width: '75%', borderRadius: 4, background: 'var(--bg-secondary)' }} />
                      <div className="tactical-pulse" style={{ height: 16, width: '80%', borderRadius: 4, background: 'var(--bg-secondary)' }} />
                    </div>
                  )}

                  {aiSummary && (
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
                      {renderFormattedSummary(aiSummary)}
                    </div>
                  )}
                </div>

              </div>

              {/* Footer Actions */}
              <div style={{
                display: 'flex',
                justifyContent: 'flex-end',
                gap: 12,
                padding: '20px 32px',
                borderTop: '1px solid var(--border)',
                background: 'var(--bg-card)'
              }}>
                <button 
                  onClick={() => {
                    window.print();
                  }}
                  style={{
                    padding: '10px 20px',
                    background: 'var(--input-bg)',
                    color: 'var(--text-primary)',
                    border: '1px solid var(--border)',
                    borderRadius: 10,
                    fontSize: 11,
                    fontWeight: 700,
                    cursor: 'pointer',
                    transition: 'all 0.2s'
                  }}
                  className="card-hover"
                >
                  Print Report
                </button>
                <button 
                  onClick={() => setSelectedReport(null)}
                  style={{
                    padding: '10px 24px',
                    background: 'var(--primary)',
                    color: '#ffffff',
                    border: 'none',
                    borderRadius: 10,
                    fontSize: 11,
                    fontWeight: 900,
                    letterSpacing: 0.5,
                    cursor: 'pointer',
                    boxShadow: 'var(--primary-glow)',
                    transition: 'all 0.2s'
                  }}
                  className="card-hover"
                >
                  Close Archive
                </button>
              </div>

            </div>
          </div>
        );
      })()}
    </div>
  );
}

function NavItem({ icon, label, active, onClick, badge }: { icon: React.ReactNode; label: string; active: boolean; onClick?: () => void; badge?: number }) {
  return (
    <button onClick={onClick} className={`sidebar-nav-btn ${active ? 'active' : ''}`} style={{
      borderRadius: '12px',
      padding: '12px 16px',
      marginBottom: '2px'
    }}>
      <span style={{ display: 'flex', alignItems: 'center' }}>{icon}</span>
      <span style={{ flex: 1, marginLeft: '12px' }}>{label}</span>
      {badge !== undefined && <span style={{ background: 'var(--duress)', color: '#ffffff', fontSize: 10, fontWeight: 900, padding: '2px 8px', borderRadius: 20, boxShadow: 'var(--duress-glow)' }}>{badge}</span>}
    </button>
  );
}

function StatBar({ label, value, color, onClick }: { label: string; value: number; color: string; onClick?: () => void }) {
  return (
    <div onClick={onClick} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', cursor: onClick ? 'pointer' : 'default', padding: '6px 12px', borderRadius: '8px', transition: 'background 0.2s' }} className="card-hover">
      <span style={{ fontSize: 10, fontWeight: 900, color: 'var(--text-muted)', letterSpacing: 1.5, fontFamily: "'Outfit', sans-serif" }}>{label}</span>
      <span style={{ fontSize: 14, fontWeight: 900, color, textShadow: `0 0 10px ${color}44`, fontFamily: "'Outfit', sans-serif" }}>{value}</span>
    </div>
  );
}

function MetricCard({ label, value, color }: { label: string, value: string | number, color: string }) {
  return (
    <div className="tactical-panel glass" style={{ padding: '24px', borderTop: `4px solid ${color}` }}>
      <p style={{ fontSize: 9, fontWeight: 900, color: 'var(--text-muted)', letterSpacing: 1.5, marginBottom: 8 }}>{label}</p>
      <h3 style={{ fontSize: 28, fontWeight: 900, color: 'var(--text-primary)' }}>{value}</h3>
    </div>
  );
}


function AlertCard({ alert, agents, usersMap, onDispatch, onEscalate, onResolve, onHqOverride }: { 
  alert: Alert; 
  agents: any[];
  usersMap: Record<string, any>;
  onDispatch: (id: string, responderUid: string) => Promise<void> | void;
  onEscalate: (id: string, t: string) => Promise<void> | void; 
  onResolve: (id: string) => Promise<void> | void; 
  onHqOverride: (id: string) => Promise<void> | void;
}) {
  const isDuress = alert.status === 'DURESS';
  const statusColors: Record<string, string> = {
    'OPEN': 'var(--warning)',
    'ACTIVE': 'var(--warning)',
    'DURESS': 'var(--duress)',
    'DISPATCHED': 'var(--info)',
    'ACKNOWLEDGED': 'var(--success)',
    'ON_ROUTE': 'var(--accent)',
    'ON_SITE': 'var(--success)',
    'RESOLVED': 'var(--text-dim)'
  };
  const color = statusColors[alert.status] || 'white';
  const a = alert as any;
  const [showDispatch, setShowDispatch] = useState(false);
  const [loading, setLoading] = useState(false);
  const [triageLoading, setTriageLoading] = useState(false);
  const [triageError, setTriageError] = useState<string | null>(null);

  const runTriageAssessment = async () => {
    if (!alert.description) return;
    setTriageLoading(true);
    setTriageError(null);
    try {
      const model = getGeminiModel({ responseMimeType: "application/json" });
      if (!model) {
        throw new Error("Firebase AI Logic is not initialized.");
      }

      const prompt = `You are the Operation Rainbow Emergency Triage AI. Analyze the following raw incident description:
"${alert.description}"

Categorize the incident, recommend threat priority, detect the input language (especially Hausa, Nigerian Pidgin, or other Plateau State local dialects), and translate it to professional English if it is not in English. You MUST respond with a valid JSON object matching this exact schema:
{
  "recommended_type": "The classified type (e.g. PROTEST, ROAD_ACCIDENT, CIVIL_UNREST, ELECTRICAL_FIRE, BOLO, ROBBERY, MEDICAL_EMERGENCY, ILLEGAL_CHECKPOINT)",
  "recommended_priority": "LOW, MEDIUM, HIGH, or CRITICAL",
  "justification": "A single sentence explaining your classification.",
  "weapons_detected": true,
  "crowd_size": "Estimated number of people involved, or N/A if not applicable",
  "detected_language": "The language/dialect of the raw text (e.g., English, Hausa, Nigerian Pidgin, Berom)",
  "translated_description": "Clean, professional English translation of the raw text. If the raw text is already in English, output the original text."
}
Ensure that "weapons_detected" is a boolean (true/false).
Do not include any markdown backticks or formatting outside the raw JSON object.`;

      const result = await model.generateContent(prompt);
      const text = await result.response.text();
      const parsed = JSON.parse(text);

      const alertRef = doc(db, 'alerts', alert.id);
      await updateDoc(alertRef, {
        ai_triage: {
          recommended_type: parsed.recommended_type || "UNKNOWN",
          recommended_priority: parsed.recommended_priority || "HIGH",
          justification: parsed.justification || "",
          weapons_detected: !!parsed.weapons_detected,
          crowd_size: parsed.crowd_size || "N/A",
          detected_language: parsed.detected_language || "English",
          translated_description: parsed.translated_description || alert.description,
          timestamp: new Date().toISOString()
        }
      });
    } catch (err: any) {
      console.error("AI Triage failed:", err);
      setTriageError(err.message || String(err));
    } finally {
      setTriageLoading(false);
    }
  };

  const applyTriage = async () => {
    const ai_triage = (alert as any).ai_triage;
    if (!ai_triage) return;
    
    setLoading(true);
    try {
      const alertRef = doc(db, 'alerts', alert.id);
      
      const newTimeline = [...(alert.timeline || [])];
      newTimeline.push({
        type: 'AI_TRIAGE_APPLIED',
        timestamp: new Date().toISOString(),
        notes: `Applied AI recommended classification: ${ai_triage.recommended_type} / ${ai_triage.recommended_priority}`,
        actor: 'HQ Dispatcher',
        role: 'HQ_OFFICER'
      });

      await updateDoc(alertRef, {
        type: ai_triage.recommended_type,
        priority: ai_triage.recommended_priority,
        timeline: newTimeline
      });
    } catch (err: any) {
      console.error("Failed to apply triage:", err);
      window.alert("Failed to apply AI classifications: " + err.message);
    } finally {
      setLoading(false);
    }
  };

  // Resolve reporter dynamically from usersMap to eliminate placeholders
  const reporterId = alert.reportedBy || '';
  const reporterProfile = usersMap[reporterId];

  let reporterName = 'Anonymous Citizen';
  let reporterContact = 'No Contact Info';
  let reporterType = 'Citizen';

  if (reporterProfile) {
    reporterName = reporterProfile.displayName || reporterProfile.name || 'Anonymous Officer';
    reporterContact = reporterProfile.email || reporterProfile.phone || 'No Email';
    reporterType = reporterProfile.roleLabel || reporterProfile.role || reporterProfile.type || 'Field Unit';
  } else if (reporterId) {
    if (reporterId.includes('@')) {
      reporterName = reporterId.split('@')[0].toUpperCase();
      reporterContact = reporterId;
      reporterType = reporterId.endsWith('operationrainbow.plateau.gov.ng') ? 'Field Operator' : 'External Reporter';
    } else if (reporterId.startsWith('+') || /^\d+$/.test(reporterId)) {
      reporterName = 'Citizen Reporter';
      reporterContact = reporterId;
      reporterType = 'Mobile App SOS';
    } else {
      reporterContact = reporterId;
    }
  }

  const handleEscalate = async () => {
    setLoading(true);
    try {
      await onEscalate(alert.id, alert.assigned_to || 'POLLING_UNIT');
    } catch (e: any) {
      window.alert("Escalation failed: " + e.message);
    } finally {
      setLoading(false);
    }
  };

  const handleResolve = async () => {
    setLoading(true);
    try {
      await onResolve(alert.id);
    } catch (e: any) {
      window.alert("Resolution failed: " + e.message);
    } finally {
      setLoading(false);
    }
  };

  const handleDispatch = async (responderUid: string) => {
    setLoading(true);
    try {
      await onDispatch(alert.id, responderUid);
    } catch (e: any) {
      window.alert("Dispatch failed: " + e.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="tactical-panel glass tactical-panel-hover fade-in" style={{ padding: 24, borderTop: `4px solid ${color}`, position: 'relative', overflow: 'hidden' }}>
      {isDuress && <div className="duress-pulse" style={{ position: 'absolute', top: 0, left: 0, right: 0, height: 40, opacity: 0.1, pointerEvents: 'none' }}></div>}
      
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 20 }}>
        <div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 4 }}>
            <span style={{ fontSize: 9, fontWeight: 900, color: 'var(--text-muted)', letterSpacing: 2, fontFamily: "'Outfit', sans-serif" }}>INCIDENT REPORT</span>
            {['DISPATCHED', 'ACKNOWLEDGED', 'ON_ROUTE', 'ON_SITE'].includes(a.status) && (
              <span style={{ fontSize: 8, fontWeight: 900, background: 'var(--success)', color: 'white', padding: '2px 6px', borderRadius: 4, boxShadow: 'var(--success-glow)' }}>UNIT {a.status}</span>
            )}
          </div>
          <h3 style={{ fontSize: 16, fontWeight: 900, color: isDuress ? 'var(--duress)' : 'var(--text-primary)', fontFamily: "'Outfit', sans-serif" }}>{isDuress ? 'DURESS ALERT' : alert.type}</h3>
        </div>
        <div style={{ background: 'var(--input-bg)', border: '1px solid var(--border)', padding: '6px 12px', borderRadius: 10 }}>
          <span style={{ fontSize: 10, fontWeight: 900, color: 'var(--primary)', fontFamily: "'Inter', sans-serif" }}>{alert.assigned_to || 'PU'}</span>
        </div>
      </div>

      <p style={{ fontSize: 13, color: 'var(--text-muted)', lineHeight: 1.6, marginBottom: 20 }}>{alert.description}</p>

      {/* AI Triage Panel */}
      <div style={{
        background: 'var(--input-bg)',
        border: '1px solid var(--border)',
        borderRadius: 16,
        padding: 16,
        marginBottom: 20,
      }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 12 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <Sparkles size={13} style={{ color: 'var(--primary)' }} />
            <span style={{ fontSize: 9, fontWeight: 900, color: 'var(--primary)', letterSpacing: 1.5, fontFamily: "'Outfit', sans-serif" }}>AI TRIAGE ASSESSMENT</span>
          </div>
          {(alert as any).ai_triage && !triageLoading && (
            <button
              onClick={runTriageAssessment}
              style={{ background: 'none', border: 'none', color: 'var(--primary)', fontSize: 9, fontWeight: 900, cursor: 'pointer', textDecoration: 'underline', padding: 0 }}
            >
              RERUN
            </button>
          )}
        </div>

        {triageError && (
          <div style={{ fontSize: 11, color: 'var(--duress)', marginBottom: 8, fontWeight: 700 }}>
            Triage Failed: {triageError}
          </div>
        )}

        {!(alert as any).ai_triage && !triageLoading && (
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <span style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>Classify incident category and priority via AI</span>
            <button
              onClick={runTriageAssessment}
              style={{
                background: 'var(--primary-dim)',
                color: 'var(--primary)',
                border: '1px solid rgba(59,130,246,0.2)',
                borderRadius: 8,
                padding: '6px 12px',
                fontSize: 10,
                fontWeight: 900,
                cursor: 'pointer',
                display: 'inline-flex',
                alignItems: 'center',
                gap: 4
              }}
              className="card-hover"
            >
              <Sparkles size={10} />
              RUN AI TRIAGE
            </button>
          </div>
        )}

        {triageLoading && (
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '4px 0' }}>
            <Loader2 size={14} className="animate-spin" />
            <span style={{ fontSize: 11, color: 'var(--text-muted)', fontWeight: 600 }}>Analyzing telemetry & text payload...</span>
          </div>
        )}

        {(alert as any).ai_triage && !triageLoading && (() => {
          const triage = (alert as any).ai_triage;
          const isMatch = alert.type === triage.recommended_type && alert.priority === triage.recommended_priority;
          const priorityColors: Record<string, string> = {
            'LOW': 'var(--success)',
            'MEDIUM': 'var(--warning)',
            'HIGH': 'var(--duress)',
            'CRITICAL': 'var(--duress)'
          };
          const prioCol = priorityColors[triage.recommended_priority] || 'var(--text-muted)';
          
          return (
            <div>
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10, background: 'var(--bg-secondary)', padding: 12, borderRadius: 10, border: '1px solid var(--border)', marginBottom: 12 }}>
                <div>
                  <span style={{ fontSize: 9, color: 'var(--text-dim)', display: 'block', fontWeight: 800 }}>RECOMMENDED TYPE</span>
                  <span style={{ fontSize: 11, fontWeight: 900, color: 'var(--text-primary)' }}>{triage.recommended_type}</span>
                </div>
                <div>
                  <span style={{ fontSize: 9, color: 'var(--text-dim)', display: 'block', fontWeight: 800 }}>RECOMMENDED PRIORITY</span>
                  <span style={{ fontSize: 9, fontWeight: 900, color: prioCol, background: `${prioCol}15`, border: `1px solid ${prioCol}44`, padding: '2px 8px', borderRadius: 10, display: 'inline-block', marginTop: 2 }}>
                    {triage.recommended_priority}
                  </span>
                </div>
                <div style={{ gridColumn: 'span 2', borderTop: '1px solid var(--border)', paddingTop: 8 }}>
                  <span style={{ fontSize: 9, color: 'var(--text-dim)', display: 'block', fontWeight: 800 }}>AI JUSTIFICATION</span>
                  <p style={{ fontSize: 11, color: 'var(--text-secondary)', margin: '2px 0 0 0', lineHeight: 1.4 }}>{triage.justification}</p>
                </div>
                <div style={{ gridColumn: 'span 2', borderTop: '1px solid var(--border)', paddingTop: 8, display: 'flex', gap: 16 }}>
                  <div>
                    <span style={{ fontSize: 8, color: 'var(--text-dim)', display: 'block', fontWeight: 800 }}>WEAPONS DETECTED</span>
                    <span style={{ fontSize: 10.5, fontWeight: 900, color: triage.weapons_detected ? 'var(--duress)' : 'var(--text-muted)' }}>
                      {triage.weapons_detected ? 'YES 🚨' : 'NO'}
                    </span>
                  </div>
                  <div>
                    <span style={{ fontSize: 8, color: 'var(--text-dim)', display: 'block', fontWeight: 800 }}>CROWD SIZE</span>
                    <span style={{ fontSize: 10.5, fontWeight: 900, color: 'var(--text-primary)' }}>{triage.crowd_size}</span>
                  </div>
                </div>
                {triage.detected_language && triage.detected_language.toLowerCase() !== 'english' && (
                  <div style={{ gridColumn: 'span 2', borderTop: '1px solid var(--border)', paddingTop: 8 }}>
                    <span style={{ fontSize: 8, color: 'var(--primary)', display: 'block', fontWeight: 900, letterSpacing: 0.5 }}>
                      TRANSLATION ({triage.detected_language.toUpperCase()} ➔ ENGLISH)
                    </span>
                    <p style={{ fontSize: 11.5, color: 'var(--text-primary)', margin: '4px 0 0 0', fontStyle: 'italic', lineHeight: 1.4, background: 'var(--input-bg)', border: '1px solid var(--border)', padding: 8, borderRadius: 8 }}>
                      "{triage.translated_description}"
                    </p>
                  </div>
                )}
              </div>

              {!isMatch ? (
                <div style={{ display: 'flex', justifyContent: 'flex-end' }}>
                  <button
                    onClick={applyTriage}
                    style={{
                      background: 'var(--success-dim)',
                      color: 'var(--success)',
                      border: '1px solid rgba(16,185,129,0.2)',
                      borderRadius: 8,
                      padding: '6px 12px',
                      fontSize: 10,
                      fontWeight: 900,
                      cursor: 'pointer',
                      display: 'inline-flex',
                      alignItems: 'center',
                      gap: 4
                    }}
                    className="card-hover"
                  >
                    <CheckCircle size={10} />
                    APPLY AI CLASSIFICATIONS
                  </button>
                </div>
              ) : (
                <div style={{ display: 'flex', alignItems: 'center', gap: 6, color: 'var(--success)', fontSize: 10, fontWeight: 800, justifyContent: 'flex-end' }}>
                  <CheckCircle size={10} />
                  <span>AI RECOMMENDATIONS ALIGNED & APPLIED</span>
                </div>
              )}
            </div>
          );
        })()}
      </div>

      {/* Dynamic Geospatial & Reporter Profiles (Purging all placeholders) */}
      <div style={{ 
        display: 'grid', 
        gridTemplateColumns: '1fr 1fr', 
        gap: 16, 
        marginBottom: 20, 
        padding: 16, 
        background: 'var(--input-bg)', 
        borderRadius: 16, 
        border: '1px solid var(--border)',
        fontFamily: "'Inter', sans-serif" 
      }}>
        <div style={{ borderRight: '1px solid var(--border)', paddingRight: 12 }}>
          <span style={{ fontSize: 9, fontWeight: 900, color: 'var(--primary)', letterSpacing: 1.5, display: 'block', marginBottom: 6, fontFamily: "'Outfit', sans-serif" }}>TACTICAL LOCATION</span>
          <div style={{ fontSize: 11, fontWeight: 850, color: 'var(--text-primary)', textTransform: 'uppercase' }}>
            {a.geo_lga ? `${a.geo_lga} LGA` : 'STATEWIDE HQ'}
          </div>
          <div style={{ fontSize: 10, color: 'var(--text-muted)', marginTop: 4, fontWeight: 600 }}>
            {a.geo_ward ? `Ward: ${a.geo_ward}` : 'State Scope'}
          </div>
          {a.geo_pu && a.geo_pu !== 'N/A' && (
            <div style={{ fontSize: 9, color: 'var(--text-dim)', marginTop: 2, fontWeight: 600 }}>
              PU: {a.geo_pu}
            </div>
          )}
          {a.lat && a.lng && (
            <div style={{ fontSize: 8, color: 'var(--text-dim)', marginTop: 6, letterSpacing: 0.5, fontFamily: 'monospace' }}>
              {a.lat.toFixed(5)}°N, {a.lng.toFixed(5)}°E
            </div>
          )}
        </div>
        <div style={{ paddingLeft: 4 }}>
          <span style={{ fontSize: 9, fontWeight: 900, color: 'var(--primary)', letterSpacing: 1.5, display: 'block', marginBottom: 6, fontFamily: "'Outfit', sans-serif" }}>REPORTER MAIN PROFILE</span>
          <div style={{ fontSize: 11, fontWeight: 850, color: 'var(--text-primary)', textTransform: 'uppercase', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
            {reporterName}
          </div>
          <div style={{ fontSize: 10, color: 'var(--text-muted)', marginTop: 4, fontWeight: 600, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
            {reporterContact}
          </div>
          <div style={{ fontSize: 8, color: 'var(--text-dim)', marginTop: 6, fontWeight: 900, textTransform: 'uppercase', letterSpacing: 0.5 }}>
            SOURCE: {reporterType}
          </div>
        </div>
      </div>

      {/* Incident Timeline Stepper */}
      {alert.timeline && alert.timeline.length > 0 && (
        <div style={{ marginTop: 20, marginBottom: 24, padding: 16, background: 'var(--input-bg)', borderRadius: 16, border: '1px solid var(--border)' }}>
          <p style={{ fontSize: 9, fontWeight: 900, color: 'var(--primary)', letterSpacing: 1.5, marginBottom: 12, textTransform: 'uppercase', fontFamily: "'Outfit', sans-serif" }}>Command Audit Timeline</p>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 16, borderLeft: '2px solid var(--border)', paddingLeft: 16, marginLeft: 8 }}>
            {alert.timeline.map((event: any, idx: number) => {
              const date = new Date(event.timestamp);
              const formattedTime = date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' }) + ' HRS';
              const formattedDate = date.toLocaleDateString([], { month: 'short', day: 'numeric' });
              
              let eventColor = 'var(--text-muted)';
              if (event.type === 'CREATED') eventColor = 'var(--warning)';
              else if (event.type === 'ESCALATION' || event.type === 'SLA_AUTO_ESCALATION') eventColor = 'var(--duress)';
              else if (event.type === 'DISPATCHED') eventColor = 'var(--accent)';
              else if (event.type === 'ACKNOWLEDGED') eventColor = 'var(--success)';
              else if (event.type === 'RESOLVED') eventColor = 'var(--success)';

              return (
                <div key={idx} style={{ position: 'relative' }}>
                  {/* Stepper Node Indicator */}
                  <div style={{
                    position: 'absolute',
                    left: -24,
                    top: 2,
                    width: 12,
                    height: 12,
                    borderRadius: '50%',
                    background: 'var(--bg-secondary)',
                    border: `3.5px solid ${eventColor}`,
                    boxShadow: `0 0 6px ${eventColor}`
                  }} />
                  
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                    <span style={{ fontSize: 10, fontWeight: 900, color: eventColor, letterSpacing: 0.5 }}>{event.type}</span>
                    <span style={{ fontSize: 8, color: 'var(--text-dim)', fontWeight: 600 }}>{formattedDate} · {formattedTime}</span>
                  </div>
                  
                  <div style={{ fontSize: 11, color: 'var(--text-primary)', marginTop: 4, fontWeight: 700 }}>
                    {event.notes || (event.type === 'CREATED' ? 'Incident created.' : '')}
                  </div>
                  
                  {event.reason && (
                    <div style={{ fontSize: 9, color: 'var(--warning)', marginTop: 2, fontWeight: 700 }}>
                      Reason: <span style={{ color: 'var(--text-muted)' }}>{event.reason}</span>
                    </div>
                  )}
                  
                  <div style={{ fontSize: 8, color: 'var(--text-dim)', marginTop: 4, fontStyle: 'italic', fontWeight: 600 }}>
                    Actor: {event.actor} ({event.role})
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {showDispatch && (
        <div style={{ background: 'var(--input-bg)', padding: 12, borderRadius: 12, marginBottom: 20, border: '1px solid var(--border)' }}>
          <p style={{ fontSize: 10, fontWeight: 900, color: 'var(--primary)', marginBottom: 8 }}>SELECT LIVE RESPONDER</p>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 6, maxHeight: 150, overflow: 'auto' }}>
            {agents.filter(ag => ag.status === 'PATROLLING' || !ag.status).map(agent => (
              <button 
                key={agent.id}
                onClick={async () => { await handleDispatch(agent.user_id); setShowDispatch(false); }}
                style={{ textAlign: 'left', padding: '10px', background: 'var(--bg-secondary)', border: '1px solid var(--border)', borderRadius: 8, color: 'var(--text-primary)', cursor: 'pointer', transition: 'all 0.2s' }}
                className="card-hover"
              >
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <span style={{ fontSize: 11, fontWeight: 700 }}>{agent.displayName || agent.user_id.substring(0, 8)}</span>
                  <span style={{ fontSize: 9, color: 'var(--success)' }}>ONLINE</span>
                </div>
              </button>
            ))}
            {agents.length === 0 && <p style={{ fontSize: 10, color: 'var(--text-dim)', textAlign: 'center', padding: 10 }}>NO RESPONDERS IN VICINITY</p>}
          </div>
        </div>
      )}

      <div style={{ display: 'flex', gap: 10 }}>
        {loading ? (
          <div style={{ display: 'flex', flex: 1, justifyContent: 'center', alignItems: 'center', padding: '12px 0' }}>
            <Loader2 size={20} color="var(--primary)" className="spin" />
            <span style={{ fontSize: 10, fontWeight: 900, marginLeft: 8, color: 'var(--text-muted)' }}>PROCESSING...</span>
          </div>
        ) : !showDispatch ? (
          <>
            <button onClick={handleEscalate} className="btn-tactical" style={{ flex: 1, background: 'var(--warning-dim)', color: 'var(--warning)', border: '1px solid rgba(245,158,11,0.2)' }}>ESCALATE</button>
            <button onClick={() => setShowDispatch(true)} className="btn-tactical" style={{ flex: 1, background: 'var(--primary-dim)', color: 'var(--primary)', border: '1px solid rgba(59,130,246,0.2)' }}>DISPATCH</button>
            <button onClick={handleResolve} className="btn-tactical" style={{ flex: 1, background: 'var(--success-dim)', color: 'var(--success)', border: '1px solid rgba(16,185,129,0.2)' }}>RESOLVE</button>
          </>
        ) : (
          <button onClick={() => setShowDispatch(false)} className="btn-tactical btn-secondary" style={{ width: '100%' }}>CANCEL DISPATCH</button>
        )}
      </div>
    </div>
  );
}
