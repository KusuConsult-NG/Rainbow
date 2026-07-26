'use client';
import { useEffect, useState, useCallback, useRef } from 'react';
import { supabase } from '@/lib/supabase';
import { useRouter } from 'next/navigation';
import dynamic from 'next/dynamic';
import AdminDirectory from '@/components/AdminDirectory';
import SystemConfig from '@/components/SystemConfig';
import AuditLogs from '@/components/AuditLogs';
import MassBroadcast from '@/components/MassBroadcast';
import SystemAlertListener from '@/components/SystemAlertListener';
import Analytics from '@/components/Analytics';
import UninstallRequests from '@/components/UninstallRequests';
import AgencyPortal from '@/components/AgencyPortal';
import IncidentReplayPanel from '@/components/IncidentReplayPanel';
import { useToast } from '@/components/ToastProvider';
import { plateauTacticalMap, TacticalJurisdiction, TacticalWard, STATE_SECURITY_AGENCIES } from '@/lib/tactical_mapping';
import {
  ShieldAlert, Shield, Map as MapIcon, Users, Radio, Settings,
  LogOut, AlertTriangle, CheckCircle, ChevronUp, Phone,
  Loader2, Filter, Bell, Activity, Clock, Target, Edit3, Send,
  Sun, Moon, X, Sparkles, MapPin
} from 'lucide-react';


// Leaflet must be client-only (no SSR)
const LiveMap = dynamic(() => import('@/components/LiveMap'), { ssr: false });

// Canonical Mission Alert Interface (Supabase Aligned)
export interface Alert {
  id: string;
  local_id?: string;
  type?: string;
  sub_type?: string;
  description?: string;
  status: 'PENDING' | 'DISPATCHED' | 'ACKNOWLEDGED' | 'ON_ROUTE' | 'ON_SITE' | 'RESOLVED' | 'DURESS' | 'CANCELLED';
  severity: 'LOW' | 'MEDIUM' | 'HIGH' | 'CRITICAL';
  priority?: string;
  assigned_to?: string;
  assignedToUid?: string | null;
  latitude?: number;
  longitude?: number;
  lat?: number;
  lng?: number;
  reported_by?: string;
  reportedBy?: string;
  geo_lga?: string;
  geo_ward?: string;
  geo_pu?: string;
  ai_summary?: string;
  citizen_feedback?: string;
  feedback_at?: string;
  post_sos_status?: string;
  media_urls?: string[];
  attachments?: string[];
  created_at?: string;
  reportedAt?: any;
  resolved_by?: string;
  resolved_at?: string;
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

type Tab = 'map' | 'alerts' | 'history' | 'analytics' | 'broadcast' | 'admin' | 'settings' | 'audit' | 'uninstall' | 'agency';

const formatAlertTimestamp = (alert: Alert | null | undefined, type: 'reported' | 'resolved' = 'reported'): string => {
  if (!alert) return '—';
  let dateVal: any = null;
  if (type === 'reported') {
    dateVal = alert.created_at || alert.reportedAt;
  } else {
    dateVal = alert.resolved_at || alert.created_at;
  }
  
  if (!dateVal) return '—';
  if (typeof dateVal === 'string') {
    const d = new Date(dateVal);
    return isNaN(d.getTime()) ? dateVal : d.toLocaleString('en-GB', {
      day: '2-digit',
      month: 'short',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit'
    });
  }
  if (dateVal.seconds) {
    return new Date(dateVal.seconds * 1000).toLocaleString('en-GB', {
      day: '2-digit',
      month: 'short',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit'
    });
  }
  return String(dateVal);
};

const formatOfficerBadge = (
  idOrStr?: string,
  usersMap?: Record<string, any>
): string => {
  if (!idOrStr || idOrStr === 'UNASSIGNED') return 'TACTICAL COMMAND';

  if (usersMap && usersMap[idOrStr]) {
    const p = usersMap[idOrStr];
    if (p.badge_number) return p.badge_number;
    if (p.full_name) return p.full_name;
  }

  if (usersMap) {
    const matched = Object.values(usersMap).find(
      (p: any) => p.badge_number === idOrStr || p.email === idOrStr || p.id === idOrStr
    );
    if (matched) return matched.badge_number || matched.full_name || matched.email;
  }

  if (idOrStr.includes('@')) {
    return `OFFICER-${idOrStr.split('@')[0].toUpperCase()}`;
  }

  if (/^[0-9a-fA-F-]{24,}$/.test(idOrStr)) {
    return `TACTICAL SQUAD #${idOrStr.substring(0, 6).toUpperCase()}`;
  }

  return idOrStr.toUpperCase();
};

const getOfficerDisplayName = (
  resolvedBy?: string,
  assignedTo?: string,
  assignedResponders?: string[],
  usersMap?: Record<string, any>
): string => {
  const resolveSingleUser = (idOrStr?: string): string | null => {
    if (!idOrStr || idOrStr === 'UNASSIGNED' || idOrStr === 'Unknown Officer') return null;

    // 1. Direct lookup in usersMap by ID
    if (usersMap && usersMap[idOrStr]) {
      const p = usersMap[idOrStr];
      const name = p.full_name || p.name || p.badge_number || 'Field Officer';
      const badge = p.badge_number ? ` (${p.badge_number})` : '';
      return `${name}${badge}`;
    }

    // 2. Lookup in usersMap by badge_number or email
    if (usersMap) {
      const matched = Object.values(usersMap).find(
        (p: any) => p.badge_number === idOrStr || p.email === idOrStr || p.id === idOrStr
      );
      if (matched) {
        const name = matched.full_name || matched.name || matched.badge_number;
        const badge = matched.badge_number ? ` (${matched.badge_number})` : '';
        return `${name}${badge}`;
      }
    }

    // 3. Email string
    if (idOrStr.includes('@')) {
      const namePart = idOrStr.split('@')[0].toUpperCase();
      return `Officer ${namePart}`;
    }

    // 4. Raw UUID string fallback
    if (/^[0-9a-fA-F-]{24,}$/.test(idOrStr)) {
      return `Tactical Squad #${idOrStr.substring(0, 6).toUpperCase()}`;
    }

    return idOrStr;
  };

  // 1. Check resolvedBy first
  const resolvedName = resolveSingleUser(resolvedBy);
  if (resolvedName) return resolvedName;

  // 2. Check assignedResponders list
  if (assignedResponders && assignedResponders.length > 0) {
    const names = assignedResponders
      .map(id => resolveSingleUser(id))
      .filter(Boolean);
    if (names.length > 0) {
      return `Dispatched Squad: ${names.join(', ')}`;
    }
  }

  // 3. Check assignedTo
  const assignedName = resolveSingleUser(assignedTo);
  if (assignedName) return assignedName;

  return 'HQ Duty Operations Officer';
};

const formatIncidentId = (id?: string): string => {
  if (!id) return '#INC-0000';
  if (id.startsWith('INC-') || id.startsWith('#')) return id.toUpperCase();
  return `#INC-${id.substring(0, 8).toUpperCase()}`;
};

const resolveReporterDetails = (alert: Alert, usersMap: Record<string, any>) => {
  const reporterId = alert.reported_by || alert.reportedBy || '';
  const alertPhone = (alert as any).phone_number || (alert as any).reporter_phone || (alert as any).phone || (alert as any).contact;
  
  const profile = reporterId ? usersMap[reporterId] : null;

  let name = 'Registered Citizen';
  let contact = 'No Phone Registered';
  let type = 'Citizen Mobile SOS';

  // 1. Resolve phone number from alert or profile
  if (alertPhone) {
    contact = alertPhone;
  } else if (profile?.phone || profile?.phone_number || profile?.mobile) {
    contact = profile.phone || profile.phone_number || profile.mobile;
  } else if (profile?.email) {
    contact = profile.email;
  } else if (reporterId.startsWith('+') || /^\+?\d{7,}$/.test(reporterId)) {
    contact = reporterId;
  }

  // 2. Resolve name
  if (profile?.full_name || profile?.name || profile?.displayName) {
    name = profile.full_name || profile.name || profile.displayName;
  } else if (reporterId && reporterId.includes('@')) {
    name = `Officer ${reporterId.split('@')[0].toUpperCase()}`;
    if (!alertPhone && !profile?.phone) contact = reporterId;
  } else if (reporterId && !/^[0-9a-fA-F-]{24,}$/.test(reporterId) && !reporterId.startsWith('+')) {
    name = reporterId;
  }

  // 3. Resolve role / type
  if (profile?.role) {
    type = profile.role === 'ADMIN' || profile.role === 'HQ_OFFICER' ? 'HQ Command Center' :
           profile.role === 'RESPONDER' ? 'Field Tactical Responder' : 'Citizen Mobile App';
  } else if (reporterId.includes('operationrainbow')) {
    type = 'Field Operator';
  }

  return { name, contact, type };
};

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
  const [user, setUser] = useState<any>(null);
  const [userRole, setUserRole] = useState('HQ_OFFICER');

  // Load real user role from Supabase session
  useEffect(() => {
    const loadUserRole = async () => {
      try {
        const { data: { user } } = await supabase.auth.getUser();
        if (user) {
          const { data: profile } = await supabase
            .from('profiles')
            .select('role, full_name')
            .eq('id', user.id)
            .single();
          if (profile?.role) {
            setUserRole(profile.role as string);
              // Auto-navigate agency liaisons to their portal
              if ((profile.role as string).endsWith('_LIAISON')) {
                setActiveTab('agency');
              }
          }
        }
      } catch (e) {
        console.error('[ROLE_LOAD] Failed to load user role:', e);
      }
    };
    loadUserRole();
  }, []);
  const [userProfile, setUserProfile] = useState<any>(null);
  const [usersMap, setUsersMap] = useState<Record<string, any>>({});
  const [authLoading, setAuthLoading] = useState(true);
  const [alerts, setAlerts] = useState<Alert[]>([]);
  const [history, setHistory] = useState<Alert[]>([]);
  const [agentLocations, setAgentLocations] = useState<any[]>([]);
  const agentPathsRef = useRef<Map<string, {lat: number; lng: number; timestamp: string}[]>>(new Map());
  const [activeTab, setActiveTab] = useState<Tab>('map');
  const [unreadAgencyReports, setUnreadAgencyReports] = useState(0);

  // Load unread agency report count for HQ notification badge
  // Note: uses userRole directly since isHqUser is declared later in the component
  useEffect(() => {
    const hqRoles = ['HQ_OFFICER', 'HQ_COMMAND', 'ADMIN'];
    if (!hqRoles.includes(userRole)) return;
    const loadUnread = async () => {
      const { count } = await supabase
        .from('agency_action_reports')
        .select('id', { count: 'exact', head: true })
        .eq('read_by_hq', false);
      setUnreadAgencyReports(count || 0);
    };
    loadUnread();
    const channel = supabase
      .channel('agency-reports-badge')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'agency_action_reports' }, loadUnread)
      .subscribe();
    return () => { supabase.removeChannel(channel); };
  }, [userRole]);

  const [filterTier, setFilterTier] = useState('ALL');
  const [filterStatus, setFilterStatus] = useState('ALL');
  const [theme, setTheme] = useState<'light' | 'dark'>('light');
  const [timeString, setTimeString] = useState('');
  const [selectedReport, setSelectedReport] = useState<Alert | null>(null);
  const [aiSummary, setAiSummary] = useState<string | null>(null);
  const [isGeneratingSummary, setIsGeneratingSummary] = useState(false);
  const router = useRouter();
  const toast = useToast();

  useEffect(() => {
    setAiSummary(null);
    setIsGeneratingSummary(false);
  }, [selectedReport]);

  const generateAISummary = async (report: Alert) => {
    if (!report) return;
    setIsGeneratingSummary(true);
    setAiSummary(null);
    const toastId = toast.loading('Querying Gemini AI Engine...', 'Synthesizing incident data');
    try {
      const apiKey = process.env.NEXT_PUBLIC_GEMINI_API_KEY || '';
      const prompt = `You are the Operation Rainbow Forensic AI Assistant. Your task is to analyze the following resolved incident report and compile a premium, structured Post-Action Operational Summary.
      
INCIDENT METADATA:
- ID: ${report.id}
- Type: ${report.type || 'N/A'}
- Description: ${report.description || 'No description provided'}
- Severity: ${report.severity || report.priority || 'MEDIUM'}
- LGA: ${report.geo_lga || 'STATE HQ'}
- Ward: ${report.geo_ward || 'N/A'}

Provide your analysis formatted in Markdown. Your summary MUST contain the following four specific sections:
1. ### EXECUTIVE OPERATIONAL SUMMARY: A concise 2-sentence tactical summary of the incident and its resolution.
2. ### TIMELINE SLA AUDIT: Audit response times and evaluate if response milestones were met.
3. ### KEY RESOURCE PERFORMANCE: Evaluate the actions taken by responding officers and field units.
4. ### STRATEGIC RECOMMENDATIONS: Provide 2-3 actionable, high-impact tactical recommendations for geofenced patrols in this LGA/Ward.`;

      const res = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash-latest:generateContent?key=${apiKey}`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            contents: [{ parts: [{ text: prompt }] }],
          }),
        }
      );
      const resData = await res.json();
      const text = resData.candidates?.[0]?.content?.parts?.[0]?.text || 'Forensic analysis completed with default parameters.';
      setAiSummary(text);
      toast.update(toastId, 'success', 'Forensic Debrief Ready', 'AI analysis complete');
    } catch (error: any) {
      console.error('Error generating AI summary:', error);
      const errMsg = error.message || String(error);
      setAiSummary(`Failed to generate forensic summary: ${errMsg}`);
      toast.update(toastId, 'error', 'AI Analysis Failed', errMsg.substring(0, 80));
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
    const checkAuth = async () => {
      const { data: { session } } = await supabase.auth.getSession();
      const u = session?.user;
      if (!u) {
        setUser(null);
        setUserProfile(null);
        router.replace('/login');
        return;
      }

      setUser(u);
      setUserRole(u.user_metadata?.role || 'HQ_COMMAND');

      const { data: profile } = await supabase
        .from('profiles')
        .select('*')
        .eq('id', u.id)
        .maybeSingle();

      setUserProfile(profile || {});
      setAuthLoading(false);
    };

    checkAuth();

    const { data: authListener } = supabase.auth.onAuthStateChange((_event, session) => {
      if (!session?.user) {
        setUser(null);
        setUserProfile(null);
        router.replace('/login');
      }
    });

    return () => {
      authListener.subscription.unsubscribe();
    };
  }, [router]);

  // Live active+duress alerts stream (Supabase Realtime with Throttled Batching)
  useEffect(() => {
    if (!user) return;

    let alertDebounceTimer: NodeJS.Timeout | null = null;
    let telemetryDebounceTimer: NodeJS.Timeout | null = null;

    const fetchAlertsData = async () => {
      const { data } = await supabase
        .from('alerts')
        .select('*')
        .order('created_at', { ascending: false })
        .limit(500);

      if (data) {
        const mapped = data.map((d: any) => ({
          ...d,
          lat: d.latitude || d.lat || 9.9285,
          lng: d.longitude || d.lng || 8.8921,
          priority: d.severity || 'HIGH',
        }));
        setAlerts(mapped as Alert[]);
        setHistory(mapped.filter((a: any) => a.status === 'RESOLVED') as Alert[]);
      }
    };

    const debouncedFetchAlerts = () => {
      if (alertDebounceTimer) clearTimeout(alertDebounceTimer);
      alertDebounceTimer = setTimeout(() => {
        fetchAlertsData();
      }, 300);
    };

    const fetchTelemetryData = async () => {
      const { data: telemetryData } = await supabase.from('telemetry').select('*').limit(500);
      if (!telemetryData || telemetryData.length === 0) return;

      // Enrich with profile names in one batch query
      const userIds = telemetryData.map((t: any) => t.user_id);
      const { data: profiles } = await supabase
        .from('profiles')
        .select('id, full_name, role')
        .in('id', userIds);

      const profileMap: Record<string, { full_name?: string; role?: string }> = {};
      (profiles || []).forEach((p: any) => { profileMap[p.id] = p; });

      // Plateau State bounding polygon (approximate)
      const plateauBounds = { minLat: 8.30, maxLat: 10.50, minLng: 8.30, maxLng: 10.80 };

      const normalized = telemetryData.map((t: any) => {
        const lat = t.latitude ?? t.lat ?? null;
        const lng = t.longitude ?? t.lng ?? null;
        const profile = profileMap[t.user_id] || {};

        // Accumulate path history (cap at 30 points per agent)
        if (lat !== null && lng !== null) {
          const existing = agentPathsRef.current.get(t.user_id) || [];
          const newPoint = { lat, lng, timestamp: t.updated_at || new Date().toISOString() };
          // Only add if moved more than ~10m
          const last = existing[existing.length - 1];
          if (!last || Math.abs(last.lat - lat) > 0.0001 || Math.abs(last.lng - lng) > 0.0001) {
            const updated = [...existing, newPoint].slice(-30);
            agentPathsRef.current.set(t.user_id, updated);
          }
        }

        // Geo-fencing: check if inside Plateau State bounds
        const inBounds = lat !== null && lng !== null &&
          lat >= plateauBounds.minLat && lat <= plateauBounds.maxLat &&
          lng >= plateauBounds.minLng && lng <= plateauBounds.maxLng;

        return {
          ...t,
          lat,
          lng,
          displayName: profile.full_name || 'FIELD UNIT',
          status: t.status || 'PATROLLING',
          geo_integrity: (lat !== null && lng !== null)
            ? (inBounds ? 'IN_BOUNDS' : 'OUT_OF_BOUNDS')
            : 'UNKNOWN',
          path: agentPathsRef.current.get(t.user_id) || [],
          telemetry: {
            battery: t.battery ?? 100,
            network: t.network ?? 'UNKNOWN',
            accuracy: t.accuracy ?? 0,
          },
        };
      });

      setAgentLocations(normalized);
    };

    const debouncedFetchTelemetry = () => {
      if (telemetryDebounceTimer) clearTimeout(telemetryDebounceTimer);
      telemetryDebounceTimer = setTimeout(() => {
        fetchTelemetryData();
      }, 300);
    };

    fetchAlertsData();
    fetchTelemetryData();

    const alertsChannel = supabase
      .channel('hq-alerts-channel')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'alerts' }, () => {
        debouncedFetchAlerts();
      })
      .subscribe();

    const telemetryChannel = supabase
      .channel('hq-telemetry-channel')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'telemetry' }, () => {
        debouncedFetchTelemetry();
      })
      .subscribe();

    return () => {
      if (alertDebounceTimer) clearTimeout(alertDebounceTimer);
      if (telemetryDebounceTimer) clearTimeout(telemetryDebounceTimer);
      supabase.removeChannel(alertsChannel);
      supabase.removeChannel(telemetryChannel);
    };
  }, [user]);

  // Load all users to map telemetry to sector profiles
  useEffect(() => {
    if (!user) return;

    const fetchProfiles = async () => {
      const { data } = await supabase
        .from('profiles')
        .select('id, full_name, role, lga, ward, sector_id')
        .limit(1000);
      if (data) {
        const mapping: Record<string, any> = {};
        data.forEach((p: any) => {
          mapping[p.id] = p;
        });
        setUsersMap(mapping);
      }
    };

    fetchProfiles();
  }, [user]);

  // NOTE: Live agent tracking is handled by the combined data useEffect above
  // (hq-telemetry-channel). Duplicate subscription removed — BUG #11.

  const escalateAlert = useCallback(async (alertId: string, targetLga: string = 'ALL', reason: string = '', targetAgency: string = 'ALL') => {
    const lgaTarget = targetLga || 'ALL';
    const agencyTarget = targetAgency || 'ALL';
    const toastId = toast.loading('Escalating Incident...', `Handing over to ${agencyTarget} Command (${lgaTarget})`);
    try {
      const { data: existing } = await supabase
        .from('alerts')
        .select('ai_summary, escalation_log, geo_lga')
        .eq('id', alertId)
        .single();
      const existingNotes = existing?.ai_summary || '';
      const existingLog = existing?.escalation_log || [];

      // Resolve the target LGA commander UUID — do NOT use the HQ operator's own ID
      let targetCommanderId: string | null = null;
      let targetCommanderName = `${agencyTarget} Command`;
      if (lgaTarget && lgaTarget !== 'ALL') {
        const { data: commander } = await supabase
          .from('profiles')
          .select('id, full_name')
          .eq('role', 'LGA_COMMAND')
          .eq('geo_lga', lgaTarget)
          .limit(1)
          .maybeSingle();
        if (commander) {
          targetCommanderId = commander.id;
          targetCommanderName = commander.full_name || targetCommanderName;
        }
      }

      const escNote = `[HQ ESCALATION → ${agencyTarget} | ${lgaTarget}] ${reason || 'High Threat Escalation'} (by ${user?.email || 'HQ_OFFICER'})`;
      const logEntry = {
        from_tier: 'HQ',
        to_tier: lgaTarget,
        to_agency: agencyTarget,
        to_officer_id: targetCommanderId,
        to_officer_name: targetCommanderName,
        reason: reason || 'High Threat Escalation',
        by_email: user?.email || 'HQ_OFFICER',
        at: new Date().toISOString(),
      };

      const updateData: Record<string, any> = {
        severity: 'CRITICAL',
        status: 'ESCALATED',
        escalated_to_agency: agencyTarget,
        // IMPORTANT: Do NOT overwrite geo_lga — incident location must stay intact
        escalation_log: [...existingLog, logEntry],
        ai_summary: existingNotes ? `${existingNotes}\n${escNote}` : escNote,
        updated_at: new Date().toISOString(),
      };

      // Assign to the resolved commander UUID — NOT the HQ operator's own ID
      if (targetCommanderId) {
        updateData.assigned_to = targetCommanderId;
      } else if (user?.id) {
        // Fallback: assign to HQ operator only if no commander found
        updateData.assigned_to = user.id;
      }

      const { error } = await supabase.from('alerts').update(updateData).eq('id', alertId);
      if (error) throw error;

      // Fire agency notification if a specific external agency was selected
      if (agencyTarget !== 'ALL' && agencyTarget !== 'HQ') {
        fetch('/api/notify-agency', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            alertId,
            agency: agencyTarget,
            targetLga: lgaTarget,
            reason: reason || 'High Threat Escalation',
            sentBy: user?.email || 'HQ_OFFICER',
          }),
        }).catch(err => console.warn('[HQ_AGENCY_NOTIFY_WARN]', err));
      }

      toast.update(toastId, 'success', 'Escalation Sent', `Handed off to ${targetCommanderName} (${agencyTarget})`);
    } catch (e: any) {
      console.error('[HQ_ESCALATE_ERR]', e);
      toast.update(toastId, 'error', 'Escalation Failed', (e as any)?.message || 'Unknown error');
    }
  }, [toast, user]);

  const hqOverride = useCallback(async (alertId: string) => {
    const toastId = toast.loading('HQ Override...', 'Taking command of incident');
    try {
      const updateData: Record<string, any> = {
        severity: 'CRITICAL',
        status: 'IN_PROGRESS',
      };
      if (user?.id) {
        updateData.assigned_to = user.id;
      }
      const { error } = await supabase.from('alerts').update(updateData).eq('id', alertId);
      if (error) throw error;
      toast.update(toastId, 'success', 'HQ Override Applied', 'Incident transferred to Command HQ');
    } catch (e: any) {
      console.error('[HQ_OVERRIDE_ERR]', e);
      const msg = e?.message || 'Override failed';
      toast.update(toastId, 'error', 'Override Failed', msg);
    }
  }, [toast, user]);

  const resolveAlert = useCallback(async (alertId: string) => {
    const toastId = toast.loading('Resolving Incident...', 'Marking incident as resolved');
    try {
      const resolver = user?.email || user?.id || 'HQ_OFFICER';
      const nowIso = new Date().toISOString();
      const { error } = await supabase.from('alerts').update({ 
        status: 'RESOLVED',
        resolved_by: resolver,
        resolved_at: nowIso,
        updated_at: nowIso
      }).eq('id', alertId);
      if (error) throw error;
      toast.update(toastId, 'success', 'Incident Resolved', 'Alert marked as resolved and archived with officer attribution');
    } catch (e: any) {
      console.error('[HQ_RESOLVE_ERR]', e);
      const msg = e?.message || 'Resolution failed';
      toast.update(toastId, 'error', 'Resolution Failed', msg);
    }
  }, [toast, user]);

  const dispatchAlert = useCallback(async (alertId: string, responderUids: string[] | string) => {
    const uids = Array.isArray(responderUids) ? responderUids : [responderUids];
    if (uids.length === 0) return;
    const toastId = toast.loading('Dispatching Tactical Team...', `Assigning ${uids.length} responders to incident`);
    try {
      const leadId = uids[0];
      const nowIso = new Date().toISOString();
      const { error } = await supabase.from('alerts').update({ 
        status: 'DISPATCHED', 
        assigned_to: leadId,
        assigned_responders: uids,
        updated_at: nowIso
      }).eq('id', alertId);
      if (error) throw error;

      // Secure server-side push notification dispatch
      try {
        await fetch('/api/push/dispatch', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ alertId, responderUids: uids })
        });
      } catch (pushErr) {
        console.warn('[HQ_PUSH_WARN] Notification push API failed:', pushErr);
      }

      toast.update(toastId, 'success', 'Tactical Team Dispatched', `${uids.length} field units successfully assigned and notified`);
    } catch (e: any) {
      console.error('[HQ_DISPATCH_ERR]', e);
      const msg = e?.message || 'Dispatch failed';
      toast.update(toastId, 'error', 'Dispatch Failed', msg);
    }
  }, [toast]);

  const [filterLga, setFilterLga] = useState('ALL');
  const [filterWard, setFilterWard] = useState('ALL');
  const [filterPu, setFilterPu] = useState('ALL');
  const [enableClustering, setEnableClustering] = useState(true);

  const selectedLgaObj = plateauTacticalMap.find(l => l.name.toUpperCase() === filterLga.toUpperCase());
  const selectedWardObj = selectedLgaObj?.wards?.find(w => w.name.toUpperCase() === filterWard.toUpperCase());

  // High-Scale Spatial-Temporal Cluster Aggregation (Handles 100,000+ incoming reports)
  const processAlertsForDisplay = (rawAlerts: Alert[]): Alert[] => {
    if (!enableClustering) return rawAlerts;

    const clusterMap = new Map<string, { master: Alert; count: number }>();

    rawAlerts.forEach(alert => {
      if (alert.status === 'RESOLVED') {
        clusterMap.set(`resolved-${alert.id}`, { master: { ...alert }, count: 1 });
        return;
      }

      // Group active threats by LGA + Ward + PU + Type
      const lga = alert.geo_lga || 'STATE';
      const ward = alert.geo_ward || 'SECTOR';
      const pu = alert.geo_pu || 'AREA';
      const key = `${lga}_${ward}_${pu}_${alert.type}`;

      if (!clusterMap.has(key)) {
        clusterMap.set(key, { master: { ...alert }, count: 1 });
      } else {
        const item = clusterMap.get(key)!;
        item.count += 1;
        if (alert.status === 'DURESS' || alert.priority === 'CRITICAL') {
          item.master.status = alert.status;
          item.master.priority = 'CRITICAL';
        }
      }
    });

    const result: Alert[] = [];
    clusterMap.forEach(({ master, count }) => {
      (master as any).witness_count = count;
      result.push(master);
    });

    return result;
  };

  const displayAlerts = processAlertsForDisplay(alerts);

  const filtered = displayAlerts.filter(a => {
    if (filterStatus === 'CRITICAL') {
      if (a.status !== 'DURESS' && a.priority !== 'CRITICAL') return false;
    } else if (filterStatus === 'SMS_FALLBACK') {
      const isSms = (a.description || '').includes('[OFFLINE_SMS]') || 
                    (a.description || '').includes('[SMS]') ||
                    (a as any).via === 'SMS_GATEWAY' || 
                    (a as any).source === 'SMS' || 
                    (a as any).channel === 'SMS';
      if (!isSms) return false;
    } else if (filterStatus !== 'ALL' && a.status !== filterStatus) return false;
    if (filterTier !== 'ALL' && a.assigned_to !== filterTier) return false;
    if (filterLga !== 'ALL') {
      const alertLga = (a.geo_lga || '').trim().toLowerCase();
      const targetLga = filterLga.trim().toLowerCase();
      if (alertLga !== targetLga && !alertLga.includes(targetLga) && !targetLga.includes(alertLga)) {
        return false;
      }
    }
    if (filterWard !== 'ALL') {
      const alertWard = (a.geo_ward || '').trim().toLowerCase();
      const targetWard = filterWard.trim().toLowerCase();
      if (alertWard !== targetWard && !alertWard.includes(targetWard) && !targetWard.includes(alertWard)) {
        return false;
      }
    }
    if (filterPu !== 'ALL') {
      const alertPu = (a.geo_pu || '').trim().toLowerCase();
      const targetPu = filterPu.trim().toLowerCase();
      if (alertPu !== targetPu && !alertPu.includes(targetPu) && !targetPu.includes(alertPu)) {
        return false;
      }
    }
    return true;
  });

  // Sector-Aware Duress & SMS Fallback Counters
  const sectorAlerts = filterLga === 'ALL'
    ? alerts
    : alerts.filter(a => {
        const alertLga = (a.geo_lga || '').trim().toLowerCase();
        const targetLga = filterLga.trim().toLowerCase();
        const matchesLga = alertLga === targetLga || alertLga.includes(targetLga) || targetLga.includes(alertLga);
        if (!matchesLga) return false;
        if (filterWard !== 'ALL') {
          const alertWard = (a.geo_ward || '').trim().toLowerCase();
          const targetWard = filterWard.trim().toLowerCase();
          if (alertWard !== targetWard && !alertWard.includes(targetWard) && !targetWard.includes(alertWard)) return false;
        }
        if (filterPu !== 'ALL') {
          const alertPu = (a.geo_pu || '').trim().toLowerCase();
          const targetPu = filterPu.trim().toLowerCase();
          if (alertPu !== targetPu && !alertPu.includes(targetPu) && !targetPu.includes(alertPu)) return false;
        }
        return true;
      });

  const duressCount = sectorAlerts.filter(a => a.status === 'DURESS').length;
  const smsFallbackCount = sectorAlerts.filter(a => 
    (a.description || '').includes('[OFFLINE_SMS]') || 
    (a.description || '').includes('[SMS]') ||
    (a as any).via === 'SMS_GATEWAY' || 
    (a as any).source === 'SMS' ||
    (a as any).channel === 'SMS'
  ).length;

  const handleLogout = async () => { 
    await supabase.auth.signOut(); 
    router.replace('/login'); 
  };

  if (authLoading) return (
    <div style={{ height: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'var(--bg-primary)' }}>
      <Loader2 size={32} color="var(--accent)" className="spin" />
    </div>
  );
  if (!user) return null;

  const isHqUser = userRole === 'HQ_OFFICER' || userRole === 'HQ_COMMAND' || userRole === 'ADMIN';
  const isAgencyLiaison = userRole.endsWith('_LIAISON');
  // Derive agency code from role: 'POLICE_LIAISON' -> 'POLICE'
  const userAgencyCode = isAgencyLiaison ? userRole.replace('_LIAISON', '') : undefined;

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
            <NavItem icon={<Radio size={18} />} label="Communications & Broadcast" active={activeTab === 'broadcast'} onClick={() => setActiveTab('broadcast')} />
            <NavItem
              icon={<Shield size={18} />}
              label="Inter-Agency Command"
              active={activeTab === 'agency'}
              onClick={() => setActiveTab('agency')}
              badge={unreadAgencyReports > 0 ? unreadAgencyReports : undefined}
            />
            
            {isHqUser && (
              <>
                <div style={{ margin: '16px 0', height: 1, background: 'var(--border)' }}></div>
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
                {activeTab === 'map' && (
                  filterLga !== 'ALL' 
                    ? `${filterLga.toUpperCase()} SECTOR MONITORING`
                    : (isHqUser ? 'Statewide Monitoring' : `${userProfile?.geo_lga || 'Sector'} Monitoring`)
                )}
                {activeTab === 'alerts' && (
                  filterLga !== 'ALL'
                    ? `${filterLga.toUpperCase()} COMMAND FEED`
                    : (isHqUser ? 'Statewide Incident Command' : `${userProfile?.geo_lga || 'Sector'} Command Feed`)
                )}
                {activeTab === 'history' && (
                  filterLga !== 'ALL'
                    ? `${filterLga.toUpperCase()} MISSION LOGS`
                    : (isHqUser ? 'Statewide Mission Logs' : `${userProfile?.geo_lga || 'Sector'} Archive`)
                )}
                {activeTab === 'broadcast' && 'Signal Dispatch'}
                {activeTab === 'admin' && 'Staff Command'}
                {activeTab === 'audit' && 'Accountability'}
                {activeTab === 'settings' && 'Platform Core'}
                {activeTab === 'agency' && 'Inter-Agency Command'}
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

            {smsFallbackCount > 0 && (
              <div
                onClick={() => {
                  setActiveTab('alerts');
                  setFilterStatus('SMS_FALLBACK');
                }}
                title="Click to view all offline SMS gateway reports"
                style={{ 
                  background: 'rgba(245, 158, 11, 0.15)',
                  border: '1px solid rgba(245, 158, 11, 0.5)', 
                  borderRadius: 8, 
                  padding: '8px 16px', 
                  display: 'flex', 
                  alignItems: 'center', 
                  gap: 8,
                  cursor: 'pointer',
                  boxShadow: '0 0 15px rgba(245, 158, 11, 0.2)'
                }}
              >
                <Radio size={14} color="#fbbf24" className="spin-slow" />
                <span style={{ fontSize: 11, fontWeight: 900, color: '#fbbf24' }}>{smsFallbackCount} SMS FALLBACK</span>
              </div>
            )}

            <button
              onClick={() => setEnableClustering(c => !c)}
              title={enableClustering ? 'Spatial-Temporal Proximity Clustering Active (Grouping duplicate reports for 100k+ users)' : 'Clustering Off (Showing raw un-grouped signal feed)'}
              style={{
                background: enableClustering ? 'rgba(79, 70, 229, 0.15)' : 'var(--bg-secondary)',
                border: enableClustering ? '1px solid #818cf8' : '1px solid var(--border)',
                borderRadius: 8,
                padding: '8px 14px',
                display: 'flex',
                alignItems: 'center',
                gap: 8,
                cursor: 'pointer',
                color: enableClustering ? '#818cf8' : 'var(--text-muted)',
                fontSize: 11,
                fontWeight: 800
              }}
            >
              <Sparkles size={14} color={enableClustering ? '#818cf8' : 'var(--text-muted)'} />
              <span>{enableClustering ? 'HIGH-SCALE CLUSTERING: ON' : 'RAW SIGNAL FEED'}</span>
            </button>

            {/* Permanent Top Bar Cascading 3-Tier Sector Selector (LGA -> Ward -> PU) */}
            <div style={{
              display: 'flex',
              alignItems: 'center',
              gap: 8,
              background: filterLga !== 'ALL' ? 'rgba(16, 185, 129, 0.15)' : 'var(--bg-secondary)',
              border: filterLga !== 'ALL' ? '1px solid var(--primary)' : '1px solid var(--border)',
              borderRadius: 8,
              padding: '6px 12px',
              boxShadow: filterLga !== 'ALL' ? 'var(--primary-glow)' : 'none'
            }}>
              <MapPin size={14} color={filterLga !== 'ALL' ? 'var(--primary)' : 'var(--text-muted)'} />
              <span style={{ fontSize: 10, fontWeight: 900, color: filterLga !== 'ALL' ? 'var(--primary)' : 'var(--text-muted)', letterSpacing: 0.5 }}>SECTOR:</span>
              <select
                value={filterLga}
                onChange={e => {
                  setFilterLga(e.target.value);
                  setFilterWard('ALL');
                  setFilterPu('ALL');
                }}
                style={{
                  background: 'transparent',
                  border: 'none',
                  color: filterLga !== 'ALL' ? '#34d399' : 'var(--text-primary)',
                  fontSize: 11,
                  fontWeight: 900,
                  cursor: 'pointer',
                  outline: 'none',
                  textTransform: 'uppercase',
                  fontFamily: "'Outfit', sans-serif"
                }}
              >
                <option value="ALL" style={{ background: 'var(--bg-secondary)', color: 'var(--text-primary)' }}>ALL LGAS (STATEWIDE)</option>
                {plateauTacticalMap.map(lga => (
                  <option key={lga.id} value={lga.name} style={{ background: 'var(--bg-secondary)', color: 'var(--text-primary)' }}>
                    {lga.name.toUpperCase()}
                  </option>
                ))}
              </select>

              {filterLga !== 'ALL' && selectedLgaObj?.wards && selectedLgaObj.wards.length > 0 && (
                <>
                  <span style={{ fontSize: 10, color: 'var(--text-dim)' }}>/</span>
                  <select
                    value={filterWard}
                    onChange={e => {
                      setFilterWard(e.target.value);
                      setFilterPu('ALL');
                    }}
                    style={{
                      background: 'transparent',
                      border: 'none',
                      color: filterWard !== 'ALL' ? '#818cf8' : 'var(--text-muted)',
                      fontSize: 11,
                      fontWeight: 800,
                      cursor: 'pointer',
                      outline: 'none',
                      textTransform: 'uppercase',
                      fontFamily: "'Outfit', sans-serif"
                    }}
                  >
                    <option value="ALL" style={{ background: 'var(--bg-secondary)', color: 'var(--text-primary)' }}>ALL DISTRICTS</option>
                    {selectedLgaObj.wards.map(w => (
                      <option key={w.id} value={w.name} style={{ background: 'var(--bg-secondary)', color: 'var(--text-primary)' }}>
                        {w.name.toUpperCase()}
                      </option>
                    ))}
                  </select>
                </>
              )}

              {filterWard !== 'ALL' && selectedWardObj?.pollingUnits && selectedWardObj.pollingUnits.length > 0 && (
                <>
                  <span style={{ fontSize: 10, color: 'var(--text-dim)' }}>/</span>
                  <select
                    value={filterPu}
                    onChange={e => setFilterPu(e.target.value)}
                    style={{
                      background: 'transparent',
                      border: 'none',
                      color: filterPu !== 'ALL' ? '#fbbf24' : 'var(--text-muted)',
                      fontSize: 11,
                      fontWeight: 800,
                      cursor: 'pointer',
                      outline: 'none',
                      textTransform: 'uppercase',
                      fontFamily: "'Outfit', sans-serif"
                    }}
                  >
                    <option value="ALL" style={{ background: 'var(--bg-secondary)', color: 'var(--text-primary)' }}>ALL BEATS</option>
                    {selectedWardObj.pollingUnits.map(pu => (
                      <option key={pu} value={pu} style={{ background: 'var(--bg-secondary)', color: 'var(--text-primary)' }}>
                        {pu}
                      </option>
                    ))}
                  </select>
                </>
              )}
            </div>
            
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
                <option value="SMS_FALLBACK">📡 SMS FALLBACK REPORTS</option>
              </select>
              {isHqUser ? (
                <>
                  <select value={filterLga} onChange={e => { setFilterLga(e.target.value); setFilterWard('ALL'); setFilterPu('ALL'); }} style={overlaySelect}>
                    <option value="ALL">ALL LGAS (STATEWIDE)</option>
                    {plateauTacticalMap.map(lga => <option key={lga.id} value={lga.name}>{lga.name.toUpperCase()}</option>)}
                  </select>
                  {filterLga !== 'ALL' && selectedLgaObj?.wards && selectedLgaObj.wards.length > 0 && (
                    <select value={filterWard} onChange={e => { setFilterWard(e.target.value); setFilterPu('ALL'); }} style={overlaySelect}>
                      <option value="ALL">ALL DISTRICTS</option>
                      {selectedLgaObj.wards.map(w => <option key={w.id} value={w.name}>{w.name.toUpperCase()}</option>)}
                    </select>
                  )}
                  {filterWard !== 'ALL' && selectedWardObj?.pollingUnits && selectedWardObj.pollingUnits.length > 0 && (
                    <select value={filterPu} onChange={e => setFilterPu(e.target.value)} style={overlaySelect}>
                      <option value="ALL">ALL BEATS (PU)</option>
                      {selectedWardObj.pollingUnits.map(pu => <option key={pu} value={pu}>{pu}</option>)}
                    </select>
                  )}
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
                      <option value="SMS_FALLBACK">📡 SMS FALLBACK REPORTS</option>
                    </select>
                     <select value={filterLga} onChange={e => { setFilterLga(e.target.value); setFilterWard('ALL'); setFilterPu('ALL'); }} style={fSel}>
                      <option value="ALL">ALL LGAS (STATEWIDE)</option>
                      {plateauTacticalMap.map(lga => <option key={lga.id} value={lga.name}>{lga.name.toUpperCase()}</option>)}
                    </select>
                    {filterLga !== 'ALL' && selectedLgaObj?.wards && selectedLgaObj.wards.length > 0 && (
                      <select value={filterWard} onChange={e => { setFilterWard(e.target.value); setFilterPu('ALL'); }} style={fSel}>
                        <option value="ALL">ALL DISTRICTS</option>
                        {selectedLgaObj.wards.map(w => <option key={w.id} value={w.name}>{w.name.toUpperCase()}</option>)}
                      </select>
                    )}
                    {filterWard !== 'ALL' && selectedWardObj?.pollingUnits && selectedWardObj.pollingUnits.length > 0 && (
                      <select value={filterPu} onChange={e => setFilterPu(e.target.value)} style={fSel}>
                        <option value="ALL">ALL BEATS (PU)</option>
                        {selectedWardObj.pollingUnits.map(pu => <option key={pu} value={pu}>{pu}</option>)}
                      </select>
                    )}
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
                      <option value="SMS_FALLBACK">📡 SMS FALLBACK REPORTS</option>
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
                  {filtered.map(a => <AlertCard key={a.id} alert={a} agents={agentLocations} usersMap={usersMap} onViewDossier={(alert) => setSelectedReport(alert)} onDispatch={dispatchAlert} onEscalate={escalateAlert} onResolve={resolveAlert} onHqOverride={hqOverride} />)}
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
                          <span style={{ fontSize: 10, fontWeight: 900, padding: '4px 10px', background: 'rgba(255,255,255,0.05)', borderRadius: 20 }}>{formatOfficerBadge(a.assigned_to, usersMap)}</span>
                        </td>
                        <td style={{ padding: '16px 24px', fontSize: 12, color: 'var(--success)', fontWeight: 700 }}>
                          {getOfficerDisplayName(a.resolved_by, a.assigned_to, (a as any).assigned_responders, usersMap)}
                        </td>
                        <td style={{ padding: '16px 24px', fontSize: 12, color: 'var(--text-muted)' }}>
                          {formatAlertTimestamp(a, 'reported')}
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
          {activeTab === 'agency' && (
            <AgencyPortal
              userRole={userRole}
              userAgency={userAgencyCode}
              isHq={isHqUser}
              userEmail={user?.email || ''}
              userId={user?.id || ''}
            />
          )}
        </div>
      </main>

      {/* Post-Action Mission Report Modal */}
      {selectedReport && (() => {
        const { name: reporterName, contact: reporterContact, type: reporterType } = resolveReporterDetails(selectedReport, usersMap);

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
        
        const prioKey = selectedReport.severity || selectedReport.priority || 'MEDIUM';
        const prioColor = priorityColors[prioKey] || 'var(--text-muted)';
        const prioGlow = priorityGlows[prioKey] || 'none';

        const rStatus = (selectedReport.status as string) || 'PENDING';
        const statusBadgeLabel = rStatus === 'RESOLVED' ? 'ARCHIVED & RESOLVED' :
          rStatus === 'DURESS' ? 'CRISIS DURESS' :
          rStatus === 'DISPATCHED' ? 'SQUAD DISPATCHED' :
          rStatus === 'ON_ROUTE' || rStatus === 'ON_SITE' || rStatus === 'ENGAGED' ? 'RESPONDER ENGAGED' :
          rStatus === 'ESCALATED' ? 'ESCALATED TO COMMAND' : 'PENDING COMMAND ACTION';

        const statusBadgeColor = rStatus === 'RESOLVED' ? 'var(--success)' :
          rStatus === 'DURESS' ? 'var(--duress)' :
          rStatus === 'DISPATCHED' ? 'var(--info)' :
          rStatus === 'ON_ROUTE' || rStatus === 'ON_SITE' || rStatus === 'ENGAGED' ? 'var(--success)' : 'var(--warning)';

        const reportedTimeStr = selectedReport.created_at
          ? new Date(selectedReport.created_at).toLocaleString()
          : selectedReport.reportedAt
          ? new Date(selectedReport.reportedAt.seconds * 1000).toLocaleString()
          : 'JUST NOW';

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
                    <span style={{ fontSize: 9, fontWeight: 900, color: 'var(--primary)', letterSpacing: 2, fontFamily: "'Outfit', sans-serif" }}>INCIDENT DOSSIER</span>
                    <span style={{ fontSize: 8, fontWeight: 900, background: `${statusBadgeColor}22`, color: statusBadgeColor, border: `1px solid ${statusBadgeColor}`, padding: '2px 8px', borderRadius: 20 }}>{statusBadgeLabel}</span>
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
                        <span style={{ fontSize: 11, fontWeight: 800, color: 'var(--text-primary)' }}>
                          {getOfficerDisplayName(undefined, selectedReport.assigned_to, (selectedReport as any).assigned_responders, usersMap)}
                        </span>
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
                        <span title={selectedReport.id} style={{ fontSize: 11, fontWeight: 800, color: 'var(--primary)', fontFamily: "'Outfit', monospace", letterSpacing: 0.5 }}>
                          {formatIncidentId(selectedReport.id)}
                        </span>
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
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                        <span style={{ fontSize: 11, color: 'var(--text-muted)', fontWeight: 700 }}>Polling Unit (PU):</span>
                        <span style={{ 
                          fontSize: 11, 
                          fontWeight: 900, 
                          color: '#818cf8', 
                          background: 'rgba(99, 102, 241, 0.15)', 
                          border: '1px solid rgba(99, 102, 241, 0.3)',
                          padding: '3px 10px', 
                          borderRadius: 8,
                          textTransform: 'uppercase',
                          letterSpacing: 0.5
                        }}>
                          {selectedReport.geo_pu || 'PU UNASSIGNED / CENTRAL HQ'}
                        </span>
                      </div>
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

                {/* Attached Media Dossier (Video, Photos, Audio) */}
                {((selectedReport.media_urls && selectedReport.media_urls.length > 0) || (selectedReport.attachments && selectedReport.attachments.length > 0)) && (
                  <div>
                    <h4 style={{ fontSize: 10, fontWeight: 900, color: 'var(--accent)', letterSpacing: 1.5, textTransform: 'uppercase', marginBottom: 12, fontFamily: "'Outfit', sans-serif" }}>
                      ATTACHED EVIDENCE MEDIA ({((selectedReport.media_urls || selectedReport.attachments || []).length)} FILES)
                    </h4>
                    <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(280px, 1fr))', gap: 16 }}>
                      {(selectedReport.media_urls || selectedReport.attachments || []).map((url: string, idx: number) => {
                        const isVideo = url.endsWith('.mp4') || url.endsWith('.mov') || url.endsWith('.webm') || url.includes('video');
                        const isAudio = url.endsWith('.m4a') || url.endsWith('.mp3') || url.endsWith('.wav') || url.includes('audio');
                        return (
                          <div key={idx} style={{ background: 'var(--input-bg)', borderRadius: 16, padding: 12, border: '1px solid var(--border)' }}>
                            {isVideo ? (
                              <div>
                                <span style={{ fontSize: 9, fontWeight: 900, color: 'var(--primary)', display: 'block', marginBottom: 8, letterSpacing: 1 }}>📹 INCIDENT VIDEO FOOTAGE</span>
                                <video src={url} controls style={{ width: '100%', height: 180, borderRadius: 12, objectFit: 'cover', background: '#000' }} />
                              </div>
                            ) : isAudio ? (
                              <div>
                                <span style={{ fontSize: 9, fontWeight: 900, color: 'var(--accent)', display: 'block', marginBottom: 8, letterSpacing: 1 }}>🎙️ VOICE AUDIO RECORDING</span>
                                <audio src={url} controls style={{ width: '100%', marginTop: 8 }} />
                              </div>
                            ) : (
                              <div>
                                <span style={{ fontSize: 9, fontWeight: 900, color: 'var(--success)', display: 'block', marginBottom: 8, letterSpacing: 1 }}>📷 SCENE PHOTO</span>
                                <img src={url} alt="Incident media" style={{ width: '100%', height: 180, borderRadius: 12, objectFit: 'cover' }} />
                              </div>
                            )}
                          </div>
                        );
                      })}
                    </div>
                  </div>
                )}

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
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
                      <div>
                        <span style={{ fontSize: 10, color: 'var(--text-dim)', display: 'block', fontWeight: 700, marginBottom: 2 }}>RESOLVED BY</span>
                        <span style={{ fontSize: 13, fontWeight: 800, color: 'var(--success)' }}>
                          {getOfficerDisplayName(selectedReport.resolved_by, selectedReport.assigned_to, (selectedReport as any).assigned_responders, usersMap)}
                        </span>
                      </div>
                      <div style={{ marginTop: 4 }}>
                        <span style={{ fontSize: 10, color: 'var(--text-dim)', display: 'block', fontWeight: 700, marginBottom: 4 }}>TIMESTAMPS</span>
                        <div style={{ fontSize: 11, fontWeight: 600, color: 'var(--text-primary)', display: 'flex', flexDirection: 'column', gap: 4 }}>
                          <div style={{ display: 'flex', gap: 6 }}>
                            <span style={{ color: 'var(--text-muted)' }}>Reported:</span>
                            <span style={{ fontWeight: 700 }}>{formatAlertTimestamp(selectedReport, 'reported')}</span>
                          </div>
                          {selectedReport.resolved_at && (
                            <div style={{ display: 'flex', gap: 6, color: 'var(--success)' }}>
                              <span style={{ opacity: 0.8 }}>Resolved:</span>
                              <span style={{ fontWeight: 700 }}>{formatAlertTimestamp(selectedReport, 'resolved')}</span>
                            </div>
                          )}
                        </div>
                      </div>
                    </div>
                  </div>
                </div>

                {/* Complete Forensic Timeline */}
                <div style={{ marginTop: 12 }}>
                  <IncidentReplayPanel alertId={selectedReport.id} />
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

                {/* Dossier Tactical Action Footer Deck */}
                <div style={{
                  display: 'flex',
                  gap: 12,
                  marginTop: 16,
                  borderTop: '1px solid var(--border)',
                  paddingTop: 20
                }}>
                  {selectedReport.status !== 'RESOLVED' && (
                    <>
                      <button
                        onClick={async () => {
                          const responderUid = agentLocations[0]?.user_id || user?.id || '';
                          await dispatchAlert(selectedReport.id, responderUid);
                          setSelectedReport(null);
                        }}
                        className="btn-tactical"
                        style={{ flex: 1, background: 'var(--primary)', color: '#fff' }}
                      >
                        <Radio size={14} /> DISPATCH SQUAD
                      </button>
                      <button
                        onClick={async () => {
                          await escalateAlert(selectedReport.id, selectedReport.geo_lga || 'ALL');
                          setSelectedReport(null);
                        }}
                        className="btn-tactical"
                        style={{ flex: 1, background: 'var(--warning)', color: '#000' }}
                      >
                        <AlertTriangle size={14} /> ESCALATE COMMAND
                      </button>
                      <button
                        onClick={async () => {
                          await resolveAlert(selectedReport.id);
                          setSelectedReport(null);
                        }}
                        className="btn-tactical"
                        style={{ flex: 1, background: 'var(--success)', color: '#fff' }}
                      >
                        <CheckCircle size={14} /> RESOLVE INCIDENT
                      </button>
                    </>
                  )}
                  {selectedReport.status === 'RESOLVED' && (
                    <div style={{ flex: 1, textAlign: 'center', padding: '10px 0', fontSize: 11, fontWeight: 900, color: 'var(--success)', letterSpacing: 1.5 }}>
                      ✓ THIS INCIDENT HAS BEEN RESOLVED AND ARCHIVED
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


function AlertCard({ alert, agents, usersMap, onViewDossier, onDispatch, onEscalate, onResolve, onHqOverride }: { 
  alert: Alert; 
  agents: any[];
  usersMap: Record<string, any>;
  onViewDossier?: (alert: Alert) => void;
  onDispatch: (id: string, responderUid: string) => Promise<void> | void;
  onEscalate: (id: string, t: string, notes?: string, agency?: string) => Promise<void> | void; 
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
  const toast = useToast();
  const [showDispatch, setShowDispatch] = useState(false);
  const [showEscalate, setShowEscalate] = useState(false);
  const [selectedResponders, setSelectedResponders] = useState<string[]>([]);
  const [targetLga, setTargetLga] = useState('ALL');
  const [targetAgency, setTargetAgency] = useState('ALL');
  const [escalateNotes, setEscalateNotes] = useState('');
  const [loading, setLoading] = useState(false);
  const [triageLoading, setTriageLoading] = useState(false);
  const [triageError, setTriageError] = useState<string | null>(null);

  const runTriageAssessment = async () => {
    if (!alert.description) return;
    setTriageLoading(true);
    setTriageError(null);
    const toastId = toast.loading('Running AI Triage...', 'Analyzing incident description');
    try {
      const apiKey = process.env.NEXT_PUBLIC_GEMINI_API_KEY || '';
      const prompt = `You are the Operation Rainbow Emergency Triage AI. Analyze: "${alert.description}".
Respond ONLY with a JSON object with this exact shape: 
{
  "recommended_type": "CRIME",
  "recommended_priority": "HIGH",
  "justification": "Threat analysis details",
  "weapons_detected": false,
  "crowd_size": "1-5",
  "detected_language": "English",
  "translated_description": "${alert.description}"
}`;

      let parsed: any = null;

      if (apiKey) {
        try {
          const res = await fetch(
            `https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash-latest:generateContent?key=${apiKey}`,
            {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ contents: [{ parts: [{ text: prompt }] }] }),
            }
          );
          const resData = await res.json();
          const rawText = resData.candidates?.[0]?.content?.parts?.[0]?.text || '';
          const cleanJson = rawText.replace(/```json/g, '').replace(/```/g, '').trim();
          if (cleanJson) {
            parsed = JSON.parse(cleanJson);
          }
        } catch (apiErr) {
          console.warn('Gemini API call failed, using rule-based fallback triage:', apiErr);
        }
      }

      // Rule-based fallback triage engine when API key is missing or fails
      if (!parsed) {
        const desc = alert.description.toLowerCase();
        const hasWeapons = desc.includes('gun') || desc.includes('weapon') || desc.includes('shoot') || desc.includes('kill') || desc.includes('knife');
        const isFire = desc.includes('fire') || desc.includes('explosion') || desc.includes('smoke');
        const isProtest = desc.includes('protest') || desc.includes('riot') || desc.includes('crowd');

        let recType = 'SUSPICIOUS';
        let recPrio = 'HIGH';
        if (hasWeapons) { recType = 'CRIME'; recPrio = 'CRITICAL'; }
        else if (isFire) { recType = 'ENVIRONMENT'; recPrio = 'CRITICAL'; }
        else if (isProtest) { recType = 'DANGER'; recPrio = 'HIGH'; }

        parsed = {
          recommended_type: recType,
          recommended_priority: recPrio,
          justification: `Automated threat assessment: ${hasWeapons ? 'Active weapons reported.' : isFire ? 'Hazardous explosion/fire reported.' : 'Suspicious activity flagged.'}`,
          weapons_detected: hasWeapons,
          crowd_size: isProtest ? '50+' : '1-5',
          detected_language: 'English',
          translated_description: alert.description
        };
      }

      const existingNotes = alert.ai_summary || '';
      const triageNote = `[AI TRIAGE ASSESSMENT] ${parsed.justification} (Recommended: ${parsed.recommended_type} / ${parsed.recommended_priority})`;
      const newSummary = existingNotes ? `${existingNotes}\n${triageNote}` : triageNote;

      const { error } = await supabase.from('alerts').update({
        ai_triage: parsed,
        ai_summary: newSummary,
        severity: parsed.recommended_priority || alert.severity,
      }).eq('id', alert.id);

      if (error) {
        // Fallback update if ai_triage column not yet cached
        await supabase.from('alerts').update({
          ai_summary: newSummary,
          severity: parsed.recommended_priority || alert.severity,
        }).eq('id', alert.id);
      }

      toast.update(toastId, 'success', 'AI Triage Complete', 'Incident assessment updated');
    } catch (err: any) {
      console.error('AI Triage failed:', err);
      setTriageError(err.message || String(err));
      toast.update(toastId, 'error', 'AI Triage Failed', (err.message || '').substring(0, 80));
    } finally {
      setTriageLoading(false);
    }
  };

  const applyTriage = async () => {
    setLoading(true);
    const toastId = toast.loading('Applying Classifications...', 'Updating incident status');
    try {
      await supabase.from('alerts').update({ status: 'DISPATCHED' }).eq('id', alert.id);
      toast.update(toastId, 'success', 'Classifications Applied', 'Incident status updated to DISPATCHED');
    } catch (err: any) {
      console.error("Failed to apply triage:", err);
      toast.update(toastId, 'error', 'Apply Failed', err.message || 'Could not update incident classifications');
    } finally {
      setLoading(false);
    }
  };

  const { name: reporterName, contact: reporterContact, type: reporterType } = resolveReporterDetails(alert, usersMap);

  const handleEscalate = async () => {
    setLoading(true);
    try {
      await onEscalate(alert.id, alert.assigned_to || 'POLLING_UNIT');
    } catch (e: any) {
      // Error toast is already shown by the parent callback
    } finally {
      setLoading(false);
    }
  };

  const handleResolve = async () => {
    setLoading(true);
    try {
      await onResolve(alert.id);
    } catch (e: any) {
      // Error toast is already shown by the parent callback
    } finally {
      setLoading(false);
    }
  };

  const handleDispatch = async (responderUid: string) => {
    setLoading(true);
    try {
      await onDispatch(alert.id, responderUid);
      setShowDispatch(false);
    } catch (e: any) {
      // Error toast is already shown by the parent callback
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="tactical-panel glass tactical-panel-hover fade-in" style={{ padding: 24, borderTop: `4px solid ${color}`, position: 'relative', overflow: 'hidden' }}>
      {isDuress && <div className="duress-pulse" style={{ position: 'absolute', top: 0, left: 0, right: 0, height: 40, opacity: 0.1, pointerEvents: 'none' }}></div>}
      
      {((alert as any).via === 'SMS_GATEWAY' || (alert as any).source === 'SMS' || (alert.description || '').includes('[OFFLINE_SMS]') || (alert.description || '').includes('[SMS]')) && (
        <div style={{
          background: 'rgba(245, 158, 11, 0.15)',
          border: '1px solid rgba(245, 158, 11, 0.4)',
          padding: '8px 12px',
          borderRadius: 10,
          marginBottom: 14,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between'
        }}>
          <span style={{ fontSize: 10, fontWeight: 900, color: '#fbbf24', letterSpacing: 0.8, display: 'flex', alignItems: 'center', gap: 6 }}>
            📡 SMS FALLBACK REPORT (OFFLINE CITIZEN)
          </span>
          <span style={{ fontSize: 9, fontWeight: 700, color: '#fde68a', background: 'rgba(0,0,0,0.3)', padding: '2px 8px', borderRadius: 4 }}>
            TERMII CPaaS SMS GATEWAY
          </span>
        </div>
      )}

      {(alert as any).witness_count && (alert as any).witness_count > 1 && (
        <div style={{
          background: 'rgba(99, 102, 241, 0.15)',
          border: '1px solid rgba(129, 140, 248, 0.4)',
          padding: '8px 12px',
          borderRadius: 10,
          marginBottom: 14,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between'
        }}>
          <span style={{ fontSize: 10, fontWeight: 900, color: '#818cf8', letterSpacing: 0.8, display: 'flex', alignItems: 'center', gap: 6 }}>
            👥 HIGH-SCALE CLUSTER: {(alert as any).witness_count.toLocaleString()} WITNESS REPORTS AGGREGATED
          </span>
          <span style={{ fontSize: 9, fontWeight: 800, color: '#c7d2fe', background: 'rgba(0,0,0,0.3)', padding: '2px 8px', borderRadius: 4 }}>
            AUTO-CLUSTERED
          </span>
        </div>
      )}

      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 16 }}>
        <div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 4 }}>
            <span style={{ fontSize: 9, fontWeight: 900, color: 'var(--text-muted)', letterSpacing: 2, fontFamily: "'Outfit', sans-serif" }}>INCIDENT REPORT</span>
            {['DISPATCHED', 'ACKNOWLEDGED', 'ON_ROUTE', 'ON_SITE'].includes(a.status) && (
              <span style={{ fontSize: 8, fontWeight: 900, background: 'var(--success)', color: 'white', padding: '2px 6px', borderRadius: 4, boxShadow: 'var(--success-glow)' }}>UNIT {a.status}</span>
            )}
            <span style={{ fontSize: 9, fontWeight: 800, color: 'var(--primary)', marginLeft: 6 }}>
              {alert.created_at ? new Date(alert.created_at).toLocaleString('en-GB', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' }) : 'JUST NOW'}
            </span>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <h3 style={{ fontSize: 16, fontWeight: 900, color: isDuress ? 'var(--duress)' : 'var(--text-primary)', fontFamily: "'Outfit', sans-serif", margin: 0 }}>{isDuress ? 'DURESS ALERT' : alert.type}</h3>
            {onViewDossier && (
              <button
                onClick={() => onViewDossier(alert)}
                style={{
                  background: 'var(--accent-dim)',
                  color: 'var(--accent)',
                  border: '1px solid var(--accent)',
                  borderRadius: 6,
                  padding: '3px 8px',
                  fontSize: 9,
                  fontWeight: 900,
                  cursor: 'pointer',
                  letterSpacing: 0.5
                }}
              >
                📄 DOSSIER
              </button>
            )}
          </div>
        </div>
        <div style={{ background: 'var(--input-bg)', border: '1px solid var(--border)', padding: '6px 12px', borderRadius: 10 }}>
          <span style={{ fontSize: 10, fontWeight: 900, color: 'var(--primary)', fontFamily: "'Inter', sans-serif" }}>{formatOfficerBadge(alert.assigned_to, usersMap)}</span>
        </div>
      </div>

      {alert.citizen_feedback && (
        <div style={{
          background: alert.citizen_feedback === 'SAFE' ? 'rgba(16,185,129,0.15)' : 'rgba(239,68,68,0.15)',
          border: `1px solid ${alert.citizen_feedback === 'SAFE' ? 'var(--success)' : 'var(--danger)'}`,
          padding: '10px 14px',
          borderRadius: 10,
          marginBottom: 16,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between'
        }}>
          <span style={{ fontSize: 10, fontWeight: 900, color: alert.citizen_feedback === 'SAFE' ? 'var(--success)' : 'var(--danger)', letterSpacing: 0.5 }}>
            CITIZEN STATUS: {alert.citizen_feedback === 'SAFE' ? "SAFE (CANCELLED SOS)" : alert.citizen_feedback === 'INJURED' ? "INJURED - URGENT MEDICAL AID REQUIRED" : "NEED IMMEDIATE ASSISTANCE"}
          </span>
          {alert.feedback_at && (
            <span style={{ fontSize: 9, color: 'var(--text-muted)', fontWeight: 700 }}>
              {new Date(alert.feedback_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
            </span>
          )}
        </div>
      )}

      <p style={{ fontSize: 13, color: 'var(--text-muted)', lineHeight: 1.6, marginBottom: alert.media_urls && alert.media_urls.length > 0 ? 12 : 20 }}>{alert.description}</p>

      {/* Evidence Media Thumbnails — Phase 7 */}
      {alert.media_urls && alert.media_urls.length > 0 && (
        <div style={{ marginBottom: 20 }}>
          <div style={{ fontSize: 9, fontWeight: 900, color: 'var(--text-muted)', letterSpacing: 1.5, marginBottom: 8, fontFamily: "'Outfit', sans-serif" }}>
            EVIDENCE ({alert.media_urls.length} FILE{alert.media_urls.length > 1 ? 'S' : ''})
          </div>
          <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
            {alert.media_urls.slice(0, 6).map((url: string, idx: number) => {
              const u = url.toLowerCase();
              const isVideo = u.includes('/video/') || u.endsWith('.mp4') || u.endsWith('.mov') || u.endsWith('.webm');
              const isAudio = u.includes('/raw/') || u.endsWith('.m4a') || u.endsWith('.mp3') || u.endsWith('.wav');
              return (
                <div
                  key={idx}
                  onClick={() => window.open(url, '_blank')}
                  title={isVideo ? 'Click to open video' : isAudio ? 'Click to play audio' : 'Click to view image'}
                  style={{
                    width: 72, height: 72, borderRadius: 8, overflow: 'hidden', cursor: 'pointer', flexShrink: 0,
                    background: 'var(--input-bg)', border: '1px solid var(--border)',
                    display: 'flex', alignItems: 'center', justifyContent: 'center', position: 'relative',
                  }}
                >
                  {isVideo ? (
                    <div style={{ textAlign: 'center' }}>
                      <div style={{ fontSize: 24 }}>▶</div>
                      <div style={{ fontSize: 8, color: 'var(--text-muted)', marginTop: 2 }}>VIDEO</div>
                    </div>
                  ) : isAudio ? (
                    <div style={{ textAlign: 'center' }}>
                      <div style={{ fontSize: 24 }}>🎵</div>
                      <div style={{ fontSize: 8, color: 'var(--text-muted)', marginTop: 2 }}>AUDIO</div>
                    </div>
                  ) : (
                    <img
                      src={url}
                      alt={`Evidence ${idx + 1}`}
                      style={{ width: '100%', height: '100%', objectFit: 'cover' }}
                      onError={(e) => { (e.target as HTMLImageElement).style.display = 'none'; }}
                    />
                  )}
                  {idx === 5 && alert.media_urls!.length > 6 && (
                    <div style={{
                      position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.6)',
                      display: 'flex', alignItems: 'center', justifyContent: 'center',
                      fontSize: 13, fontWeight: 900, color: 'white',
                    }}>
                      +{alert.media_urls!.length - 6}
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        </div>
      )}


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
          <div style={{ 
            fontSize: 9, 
            color: '#818cf8', 
            marginTop: 6, 
            fontWeight: 800, 
            background: 'rgba(99, 102, 241, 0.12)', 
            border: '1px solid rgba(99, 102, 241, 0.25)',
            padding: '2px 6px', 
            borderRadius: 6,
            display: 'inline-block'
          }}>
            PU: {a.geo_pu || 'SECTOR HQ'}
          </div>
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
        <div style={{ background: 'var(--input-bg)', padding: 14, borderRadius: 12, marginBottom: 20, border: '1px solid var(--primary)' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 8 }}>
            <p style={{ fontSize: 10, fontWeight: 900, color: 'var(--primary)', letterSpacing: 1 }}>SELECT TACTICAL RESPONDER TEAM</p>
            <span style={{ fontSize: 9, color: 'var(--text-muted)', fontWeight: 700 }}>{selectedResponders.length} SELECTED</span>
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 6, maxHeight: 180, overflow: 'auto', marginBottom: 10 }}>
            {(() => {
              const profileResponders = Object.values(usersMap || {}).filter(
                (u: any) => u && u.role !== 'CITIZEN'
              );

              const responderList = profileResponders.length > 0
                ? profileResponders.map((p: any) => {
                    const telem = (agents || []).find((a: any) => a.user_id === p.id || a.id === p.id);
                    const ag = STATE_SECURITY_AGENCIES.find(a => a.id === (p.agency || 'RAINBOW')) || STATE_SECURITY_AGENCIES[0];
                    return {
                      userId: p.id,
                      name: p.full_name || p.badge_number || `Officer ${p.id.substring(0, 6)}`,
                      badge: p.badge_number || p.role || 'RESPONDER',
                      agencyBadge: ag.badge,
                      agencyShort: ag.shortCode,
                      agencyColor: ag.color,
                      status: telem?.status || 'PATROLLING',
                      isLive: !!telem,
                    };
                  })
                : (agents || []).map((a: any) => ({
                    userId: a.user_id || a.id,
                    name: a.displayName || a.name || `Unit ${(a.user_id || a.id).substring(0, 6)}`,
                    badge: 'PATROL UNIT',
                    agencyBadge: '🌈',
                    agencyShort: 'OR-TU',
                    agencyColor: '#6366f1',
                    status: a.status || 'PATROLLING',
                    isLive: true,
                  }));

              if (responderList.length === 0) {
                return (
                  <p style={{ fontSize: 10, color: 'var(--text-dim)', textAlign: 'center', padding: 10 }}>
                    NO REGISTERED RESPONDERS FOUND
                  </p>
                );
              }

              return responderList.map((r: any) => {
                const isSelected = selectedResponders.includes(r.userId);
                return (
                  <div
                    key={r.userId}
                    onClick={() => {
                      setSelectedResponders(prev => 
                        prev.includes(r.userId)
                          ? prev.filter(id => id !== r.userId)
                          : [...prev, r.userId]
                      );
                    }}
                    style={{
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'space-between',
                      padding: '10px 14px',
                      background: isSelected ? 'rgba(59,130,246,0.15)' : 'var(--bg-secondary)',
                      border: isSelected ? '1px solid var(--primary)' : '1px solid var(--border)',
                      borderRadius: 8,
                      color: 'var(--text-primary)',
                      cursor: 'pointer',
                      transition: 'all 0.2s',
                    }}
                    className="card-hover"
                  >
                    <div style={{ display: 'flex', alignItems: 'center', gap: 10, flex: 1 }}>
                      <input
                        type="checkbox"
                        checked={isSelected}
                        onChange={() => {}} // Handled by div onClick
                        style={{ cursor: 'pointer' }}
                      />
                      <div style={{ display: 'flex', alignItems: 'center', gap: 6, flexWrap: 'wrap' }}>
                        <span style={{ fontSize: 11, fontWeight: 700 }}>{r.name}</span>
                        {r.agencyShort && (
                          <span style={{ fontSize: 8.5, fontWeight: 900, background: r.agencyColor + '22', color: r.agencyColor, border: `1px solid ${r.agencyColor}66`, padding: '1px 6px', borderRadius: 6 }}>
                            {r.agencyBadge} {r.agencyShort}
                          </span>
                        )}
                        <span style={{ fontSize: 9, color: 'var(--text-muted)' }}>[{r.badge}]</span>
                      </div>
                    </div>
                    <span style={{ fontSize: 9, fontWeight: 800, color: r.isLive ? 'var(--success)' : 'var(--warning)' }}>
                      {r.isLive ? '● LIVE GPS' : 'READY'}
                    </span>
                  </div>
                );
              });
            })()}
          </div>

          <button
            disabled={selectedResponders.length === 0}
            onClick={async () => {
              if (selectedResponders.length > 0) {
                await onDispatch(alert.id, selectedResponders as any);
                setShowDispatch(false);
                setSelectedResponders([]);
              }
            }}
            className="btn-tactical"
            style={{
              width: '100%',
              background: selectedResponders.length > 0 ? 'var(--primary)' : 'var(--bg-secondary)',
              color: selectedResponders.length > 0 ? '#fff' : 'var(--text-muted)',
              fontWeight: 900,
              padding: '10px',
              cursor: selectedResponders.length > 0 ? 'pointer' : 'not-allowed'
            }}
          >
            {selectedResponders.length === 0 ? 'SELECT RESPONDER UNITS' : `CONFIRM TACTICAL TEAM DISPATCH (${selectedResponders.length} UNITS)`}
          </button>
        </div>
      )}

      {showEscalate && (
        <div style={{ background: 'var(--input-bg)', padding: 14, borderRadius: 12, marginBottom: 20, border: '1px solid var(--warning)' }}>
          <p style={{ fontSize: 10, fontWeight: 900, color: 'var(--warning)', marginBottom: 8, letterSpacing: 1 }}>INTER-AGENCY ESCALATION / COMMAND HANDOVER</p>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
            <div>
              <label style={{ fontSize: 9, color: 'var(--text-muted)', fontWeight: 700, display: 'block', marginBottom: 4 }}>TARGET INTER-AGENCY COMMAND:</label>
              <select
                value={targetAgency}
                onChange={(e) => setTargetAgency(e.target.value)}
                style={{
                  width: '100%',
                  padding: '8px 10px',
                  background: 'var(--bg-secondary)',
                  border: '1px solid var(--border)',
                  borderRadius: 6,
                  color: 'var(--text-primary)',
                  fontSize: 11,
                  fontWeight: 700,
                  fontFamily: 'inherit'
                }}
              >
                <option value="ALL">🌐 ALL JOINT COMMANDS (Broad Inter-Agency Escalation)</option>
                <option value="MILITARY">🎖️ OPERATION ENDURING PEACE / MILITARY STF</option>
                <option value="NPF">👮‍♂️ NIGERIA POLICE FORCE (NPF TACTICAL CELL)</option>
                <option value="NSCDC">🛡️ CIVIL DEFENCE CORPS (NSCDC RAPID UNIT)</option>
                <option value="DSS">🕶️ DEPT OF STATE SERVICES (DSS HIGH-THREAT)</option>
                <option value="RAINBOW">🌈 OPERATION RAINBOW TACTICAL HQ</option>
                <option value="VGN">🛡️ VIGILANTE GROUP (VGN COMMUNITY DEFENSE)</option>
              </select>
            </div>

            <div>
              <label style={{ fontSize: 9, color: 'var(--text-muted)', fontWeight: 700, display: 'block', marginBottom: 4 }}>TARGET SECTOR JURISDICTION:</label>
              <select
                value={targetLga}
                onChange={(e) => setTargetLga(e.target.value)}
                style={{
                  width: '100%',
                  padding: '8px 10px',
                  background: 'var(--bg-secondary)',
                  border: '1px solid var(--border)',
                  borderRadius: 6,
                  color: 'var(--text-primary)',
                  fontSize: 11,
                  fontWeight: 700,
                  fontFamily: 'inherit'
                }}
              >
                <option value="ALL">ALL LGAs (Statewide Emergency Broadcast)</option>
                <option value="BARKIN LADI">BARKIN LADI LGA</option>
                <option value="BASSA">BASSA LGA</option>
                <option value="BOKKOS">BOKKOS LGA</option>
                <option value="JOS EAST">JOS EAST LGA</option>
                <option value="JOS NORTH">JOS NORTH LGA</option>
                <option value="JOS SOUTH">JOS SOUTH LGA</option>
                <option value="KANAM">KANAM LGA</option>
                <option value="KANKE">KANKE LGA</option>
                <option value="LANGTANG NORTH">LANGTANG NORTH LGA</option>
                <option value="LANGTANG SOUTH">LANGTANG SOUTH LGA</option>
                <option value="MANGU">MANGU LGA</option>
                <option value="MIANGO">MIANGO LGA</option>
                <option value="PANKSHIN">PANKSHIN LGA</option>
                <option value="QUA'AN PAN">QUA'AN PAN LGA</option>
                <option value="RIYOM">RIYOM LGA</option>
                <option value="SHENDAM">SHENDAM LGA</option>
                <option value="WASE">WASE LGA</option>
              </select>
            </div>

            <div>
              <label style={{ fontSize: 9, color: 'var(--text-muted)', fontWeight: 700, display: 'block', marginBottom: 4 }}>TACTICAL DIRECTIVES / REASON:</label>
              <input
                value={escalateNotes}
                onChange={(e) => setEscalateNotes(e.target.value)}
                placeholder="e.g. Requesting Military STF armored response unit..."
                style={{
                  width: '100%',
                  padding: '8px 10px',
                  background: 'var(--bg-secondary)',
                  border: '1px solid var(--border)',
                  borderRadius: 6,
                  color: 'var(--text-primary)',
                  fontSize: 11,
                  fontFamily: 'inherit'
                }}
              />
            </div>

            <button
              onClick={async () => {
                await onEscalate(alert.id, targetLga, escalateNotes, targetAgency);
                setShowEscalate(false);
              }}
              className="btn-tactical"
              style={{
                width: '100%',
                background: 'var(--warning)',
                color: '#000',
                fontWeight: 900,
                padding: '10px',
                cursor: 'pointer'
              }}
            >
              CONFIRM INTER-AGENCY ESCALATION
            </button>
          </div>
        </div>
      )}

      <div style={{ display: 'flex', gap: 10 }}>
        {loading ? (
          <div style={{ display: 'flex', flex: 1, justifyContent: 'center', alignItems: 'center', padding: '12px 0' }}>
            <Loader2 size={20} color="var(--primary)" className="spin" />
            <span style={{ fontSize: 10, fontWeight: 900, marginLeft: 8, color: 'var(--text-muted)' }}>PROCESSING...</span>
          </div>
        ) : showDispatch ? (
          <button onClick={() => setShowDispatch(false)} className="btn-tactical btn-secondary" style={{ width: '100%' }}>CANCEL DISPATCH</button>
        ) : showEscalate ? (
          <button onClick={() => setShowEscalate(false)} className="btn-tactical btn-secondary" style={{ width: '100%' }}>CANCEL ESCALATION</button>
        ) : (
          <>
            <button onClick={() => { setShowEscalate(true); setShowDispatch(false); }} className="btn-tactical" style={{ flex: 1, background: 'var(--warning-dim)', color: 'var(--warning)', border: '1px solid rgba(245,158,11,0.2)' }}>ESCALATE</button>
            <button onClick={() => { setShowDispatch(true); setShowEscalate(false); }} className="btn-tactical" style={{ flex: 1, background: 'var(--primary-dim)', color: 'var(--primary)', border: '1px solid rgba(59,130,246,0.2)' }}>DISPATCH</button>
            <button onClick={handleResolve} className="btn-tactical" style={{ flex: 1, background: 'var(--success-dim)', color: 'var(--success)', border: '1px solid rgba(16,185,129,0.2)' }}>RESOLVE</button>
          </>
        )}
      </div>
    </div>
  );
}
