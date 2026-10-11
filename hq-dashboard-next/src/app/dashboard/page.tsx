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
import { useMediaQuery } from '@/hooks/useMediaQuery';
import Analytics from '@/components/Analytics';
import UninstallRequests from '@/components/UninstallRequests';
import SimChannelEvents from '@/components/SimChannelEvents';
import AgencyPortal from '@/components/AgencyPortal';
import IncidentReplayPanel from '@/components/IncidentReplayPanel';
import LiveFeedViewer from '@/components/LiveFeedViewer';
import TacticalSelect, { SelectOption } from '@/components/TacticalSelect';
import { usePersistedTheme } from '@/hooks/usePersistedTheme';


import { useToast } from '@/components/ToastProvider';
import { plateauTacticalMap, TacticalJurisdiction, TacticalWard, STATE_SECURITY_AGENCIES } from '@/lib/tactical_mapping';
import { AGENCY_LIST, AGENCY_TARGET_ALL } from '@/lib/agencies';
import { placeField } from '@/lib/place-label';
import {
  ShieldAlert, Shield, Map as MapIcon, Users, Radio, Settings,
  LogOut, AlertTriangle, CheckCircle, ChevronUp, Phone,
  Loader2, Filter, Bell, Activity, Clock, Target, Edit3, Send,
  Sun, Moon, X, Sparkles, MapPin, Menu, SignalZero,
} from 'lucide-react';
import type { Alert } from './types';
import { clusterAlerts, filterAlerts } from '@/lib/alert-display';
import { emptyBoardMeaning, emptyBoardWording } from '@/lib/empty-board';
import { geoKey, geoMatchesKeyed } from '@/lib/geo-key';
import UssdProvenancePanel from '@/components/UssdProvenancePanel';
import {
  alreadyApplied,
  applyButtonLabel,
  triageChanges,
  type TriageRecommendation,
} from '@/lib/ai-triage-apply';
import { consoleAccess } from '@/lib/console-access';
import { describeTrack, summariseTrack, thinTrack, type TrackPoint } from '@/lib/incident-track';
import { resolveReporterDetails } from '@/lib/incident-dossier';
import { categoriesPresent, categoryCounts, categoryLabel } from '@/lib/alert-category';
import { assignableResponders, emptyRosterReason, type Posting } from '@/lib/assignable-responders';
import * as alertActions from '@/lib/alert-actions';
import type { AlertIds } from '@/lib/alert-actions';

export type { Alert };


// Leaflet must be client-only (no SSR)
const LiveMap = dynamic(() => import('@/components/LiveMap'), { ssr: false });

/**
 * How many alerts the console holds in memory at once.
 *
 * This was 500 with no indication anywhere that it was a cap, so past 500
 * incidents the oldest simply stopped existing as far as the operator was
 * concerned — and the board would have looked completely normal. The window is
 * still bounded, because an unbounded fetch into a browser is its own failure
 * during exactly the event that produces this many incidents; what changed is
 * that the console now asks for the true count alongside it and SAYS when it
 * is showing a window rather than the whole board.
 */
const ALERT_WINDOW = 2000;

// Canonical Mission Alert Interface (Supabase Aligned)

const btnStyle = (color: string, bg: string): React.CSSProperties => ({
  flex: 1, padding: '12px 0', background: bg, color, border: `1px solid ${color}44`,
  borderRadius: 12, cursor: 'pointer', fontWeight: 900, fontSize: 10, letterSpacing: 1, transition: 'all 0.2s',
  fontFamily: "var(--font-outfit), sans-serif"
});

const overlaySelect: React.CSSProperties = {
  background: 'var(--bg-secondary)', backdropFilter: 'blur(12px)',
  border: '1px solid var(--border)', borderRadius: 8, padding: '8px 12px',
  color: 'var(--text-primary)', fontFamily: 'var(--font-inter),sans-serif', fontSize: 11, fontWeight: 700, cursor: 'pointer',
};

const fSel: React.CSSProperties = {
  background: 'var(--input-bg)', color: 'var(--text-primary)',
  border: '1px solid var(--border)', borderRadius: 8, padding: '7px 11px',
  fontSize: 11, fontWeight: 700, cursor: 'pointer', fontFamily: 'var(--font-inter),sans-serif',
};

type Tab = 'map' | 'alerts' | 'history' | 'analytics' | 'broadcast' | 'admin' | 'settings' | 'audit' | 'uninstall' | 'agency' | 'sim';

const formatAlertTimestamp = (alert: Alert | null | undefined, type: 'reported' | 'resolved' = 'reported'): string => {
  if (!alert) return '—';
  let dateVal: any = null;
  if (type === 'reported') {
    // `|| alert.reportedAt` used to be here. PostgREST does not return
    // camelCase keys, so it was never reached; it only made `created_at` look
    // like one of two possible sources when it is the only one.
    dateVal = alert.created_at;
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

// resolveReporterDetails used to live here, 200 lines into a 3,000-line client
// component, and the map had no way to reach it — so the marker popup showed no
// reporter at all while the incident card 1,800 lines below showed one. It is
// now src/lib/incident-dossier.ts: one implementation, tested, shared by the
// card, the dossier and the map.

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
              fontFamily: "var(--font-outfit), sans-serif" 
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
  // Below this width the 280px sidebar left the map — the console's primary
  // instrument — a ~60px strip at 390px and squeezed at 768px. It becomes a
  // slide-over drawer instead of permanently claiming the width.
  // Declared before the effects that call setActiveTab. It used to sit ~30
  // lines below its first use, which only works because effect bodies run
  // after the component body — a temporal-dead-zone hazard the linter was
  // right to flag.
  const [activeTab, setActiveTab] = useState<Tab>('map');

  const isNarrow = useMediaQuery('(max-width: 1024px)');
  const [navOpen, setNavOpen] = useState(false);

  const [user, setUser] = useState<any>(null);
  /**
   * This account's role, or NULL until the `profiles` read says what it is.
   *
   * It used to be `useState('HQ_OFFICER')` — a COMMAND role — so `consoleAccess`
   * was never handed an unknown role. That function was written to prevent
   * exactly that, and says so:
   *
   *     An unknown role gets the smallest possible console rather than the
   *     largest: while the profile is still loading, `userRole` is '', and a
   *     default of "show everything" would flash the whole command console at
   *     an agency liaison on every page load before settling.
   *
   * `userRole` was never ''. The "Unknown, or still loading" branch was
   * unreachable, and its RESOLVING ACCESS subtitle had never once been rendered
   * despite being under test.
   *
   * And the window was not merely "until the read returns". This body is gated
   * on `authLoading`, cleared by the auth effect below — which set the role
   * from `user_metadata` BEFORE its own `profiles` read and before clearing the
   * gate. Two concurrent reads of the same row race; when the auth effect won,
   * the first visible render was command by an active claim.
   *
   * What the flash cost, beyond chrome: the advisory banner reads command as
   * "sees everything, because they sent it", so a liaison was shown advisories
   * addressed to other agencies and to citizens (T-34); and an agency tab
   * clicked in that window mounted `AgencyPortal` with `isHq` true and no
   * agency, which froze that liaison on the Police desk for the life of the
   * mount (T-35).
   *
   * The app learned this rule once already, in the responder tier filter:
   * "you cannot be assigned something when we do not know who you are". Same
   * principle. Unknown PLACE still fails open — withholding a warning from
   * somebody inside the affected area costs more than showing it to somebody
   * outside — but unknown IDENTITY fails closed.
   */
  const [userRole, setUserRole] = useState<string | null>(null);

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
            // THE ONLY WRITER. `profiles.role` is the authoritative source —
            // it is what `requireRole` reads with admin privileges and what the
            // RLS policies key on. A second path used to set `userRole` from
            // `user_metadata.role`, which in Supabase is USER-WRITABLE: that is
            // H-7, "role source user-writable", and a value a user can set must
            // not be what decides they are command. It is gone; an account with
            // no role in `profiles` keeps the smallest console, which is the
            // truth about it.
            setUserRole(profile.role as string);
            // Land where this role belongs. It used to send liaisons to the
            // agency tab but leave every other tab reachable, so the statewide
            // map was one click away for an officer of another organisation.
            const resolved = consoleAccess(profile.role as string);
            setActiveTab((current) =>
              resolved.tabs.includes(current) ? current : resolved.landing,
            );
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
  const [unreadAgencyReports, setUnreadAgencyReports] = useState(0);
  const [openSimEvents, setOpenSimEvents] = useState(0);

  // Handsets whose SMS channel has gone. Badged because the consequence is
  // invisible otherwise: the alert queue keeps queueing, the sign-in code has
  // nowhere to arrive, and an operator finds out when they try to reach
  // somebody. RLS restricts the table to command, so a liaison or a
  // polling-unit officer simply gets nothing here rather than an error.
  useEffect(() => {
    const commandRoles = ['HQ_OFFICER', 'HQ_COMMAND', 'ADMIN', 'LGA_COMMAND'];
    // `null` until the profile read lands, and not a member of any list: no
    // privileged read is issued on the strength of a role we do not have yet.
    if (!userRole || !commandRoles.includes(userRole)) return;
    const loadOpen = async () => {
      const { count, error } = await supabase
        .from('sim_channel_events')
        .select('id', { count: 'exact', head: true })
        .is('acknowledged_at', null);
      // A failed count must not read as zero: a badge that says "nothing" when
      // it could not ask is the same lie as an empty board.
      if (error) return;
      setOpenSimEvents(count || 0);
    };
    loadOpen();
    const channel = supabase
      .channel('sim-events-badge')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'sim_channel_events' }, loadOpen)
      .subscribe();
    return () => { supabase.removeChannel(channel); };
  }, [userRole]);

  // Load unread agency report count for HQ notification badge
  // Note: uses userRole directly since isHqUser is declared later in the component
  useEffect(() => {
    const hqRoles = ['HQ_OFFICER', 'HQ_COMMAND', 'ADMIN'];
    if (!userRole || !hqRoles.includes(userRole)) return;
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
  const [filterCategory, setFilterCategory] = useState('ALL');
  /** How many alerts exist, against the ALERT_WINDOW actually loaded. */
  const [alertsTotal, setAlertsTotal] = useState<number | null>(null);
  /** Non-null when the last read of the feed FAILED. Never "no incidents". */
  const [feedError, setFeedError] = useState<string | null>(null);
  /**
   * Whether the database confirmed it knows who is asking, checked only when
   * the board came back empty. false means an empty board proves nothing.
   * See src/lib/empty-board.ts.
   */
  const [identityConfirmed, setIdentityConfirmed] = useState<boolean | null>(null);
  const [theme, setTheme] = usePersistedTheme();
  const [timeString, setTimeString] = useState('');
  const [selectedReport, setSelectedReport] = useState<Alert | null>(null);
  /**
   * The route taken during the incident currently open in the dossier.
   *
   * `null` means "not asked yet or could not ask" and an empty array means
   * "asked, and this incident has no positions". The dossier says those
   * differently, because a dispatcher deciding whether somebody is still where
   * they said they were needs to know which one it is.
   */
  /// Held WITH the incident it belongs to, and matched during render rather
  /// than cleared in an effect. Storing the points alone meant the previous
  /// incident's route was on screen for one frame after opening the next
  /// dossier — a route attributed to the wrong person, which is the worst
  /// possible frame to render even briefly.
  const [trackFor, setTrackFor] =
    useState<{ alertId: string; points: TrackPoint[] } | null>(null);
  const selectedTrack =
    trackFor && trackFor.alertId === selectedReport?.id ? trackFor.points : null;

  useEffect(() => {
    const alertId = selectedReport?.id;
    if (!alertId) return;
    let cancelled = false;
    void (async () => {
      const { data, error } = await supabase
        .from('incident_tracks')
        .select('latitude, longitude, accuracy, speed, recorded_at')
        .eq('alert_id', alertId)
        .order('recorded_at', { ascending: true })
        .limit(5000);
      if (cancelled) return;
      // A failed read stays null rather than becoming an empty route, which
      // would read as "this person did not move".
      if (error) {
        console.error('[TRACK] could not load the route:', error);
        return;
      }
      setTrackFor({ alertId, points: (data || []) as TrackPoint[] });
    })();
    return () => { cancelled = true; };
  }, [selectedReport?.id]);
  // The AI summary belongs to ONE report, so it is stored WITH that report's
  // id and read back only when it still matches. The old code kept two loose
  // pieces of state and wiped them from an effect on `selectedReport` — a
  // set-state-in-effect that also rendered the previous report's summary for
  // one frame before clearing it. Deriving removes both problems: opening a
  // different report simply has nothing to show.
  const [summary, setSummary] = useState<
    {
      reportId: string;
      text: string | null;
      generating: boolean;
      /** When this report was produced, if it came from the record. */
      keptAt?: string | null;
    } | null
  >(null);

  // Read back the report the SERVER kept, rather than generating a new one.
  //
  // The forensic summary used to live in React state and nowhere else, so an
  // administrator had no way to see a report that had been generated and every
  // reopen billed Gemini again for the same analysis. It is now written by
  // /api/ai/analyze at the moment the model answers (migration 20261014000000),
  // and this simply looks for it.
  //
  // Only when there is nothing on screen for this report already: a freshly
  // generated summary must not be overwritten by an older stored one a moment
  // later.
  useEffect(() => {
    const id = selectedReport?.id;
    if (!id) return;
    if (summary && summary.reportId === id) return;
    let cancelled = false;
    void (async () => {
      const { data, error } = await supabase.rpc('latest_ai_report', {
        p_alert_id: id,
        p_kind: 'summary',
      });
      if (cancelled || error) return;
      const row = Array.isArray(data) && data.length > 0
        ? (data[0] as { body: string; created_at: string })
        : null;
      if (!row) return;
      setSummary({
        reportId: id,
        text: row.body,
        generating: false,
        keptAt: row.created_at,
      });
    })();
    return () => { cancelled = true; };
  }, [selectedReport?.id, summary]);
  const summaryIsForSelected =
    summary !== null && selectedReport !== null && summary.reportId === selectedReport.id;
  const aiSummary = summaryIsForSelected ? summary.text : null;
  /**
   * When the report on screen was produced, or null if it was just generated.
   *
   * Shown because a forensic debrief written before the incident was resolved
   * reads identically to one written after it, and an operator acting on a
   * week-old assessment as though it were current is the kind of mistake a
   * timestamp prevents for the cost of one line.
   */
  const aiSummaryKeptAt = summaryIsForSelected ? (summary.keptAt ?? null) : null;
  const isGeneratingSummary = summaryIsForSelected ? summary.generating : false;
  const router = useRouter();
  const toast = useToast();

  const generateAISummary = async (report: Alert) => {
    if (!report) return;
    setSummary({ reportId: report.id, text: null, generating: true });
    const toastId = toast.loading('Querying Gemini AI Engine...', 'Synthesizing incident data');
    try {
      // The Gemini key is server-side (audit H-9). This route composes the
      // prompt from the alert row itself, so no prompt text leaves the browser.
      const res = await fetch('/api/ai/analyze', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ alertId: report.id, kind: 'summary' }),
      });
      const resData = await res.json();
      if (resData.status === 'UNCONFIGURED') {
        setSummary({ reportId: report.id, text: 'AI analysis is not configured on this deployment.', generating: true });
        toast.update(toastId, 'success', 'AI Not Configured', 'No Gemini key is set server-side');
        return;
      }
      const text = resData.text || 'Forensic analysis completed with default parameters.';
      setSummary({ reportId: report.id, text: text, generating: true });
      toast.update(toastId, 'success', 'Forensic Debrief Ready', 'AI analysis complete');
    } catch (error: any) {
      console.error('Error generating AI summary:', error);
      const errMsg = error.message || String(error);
      setSummary({ reportId: report.id, text: `Failed to generate forensic summary: ${errMsg}`, generating: true });
      toast.update(toastId, 'error', 'AI Analysis Failed', errMsg.substring(0, 80));
    } finally {
      setSummary((prev) =>
        prev && prev.reportId === report.id ? { ...prev, generating: false } : prev,
      );
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

  // Syncing a class onto <body> is a genuine external-system effect: it sets
  // no state. Persistence now lives in usePersistedTheme, so the theme is
  // right on the FIRST render instead of being corrected by a mount effect.
  useEffect(() => {
    document.body.classList.toggle('dark-theme', theme === 'dark');
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
      // This used to read `setUserRole(u.user_metadata?.role || 'HQ_COMMAND')`.
      // `user_metadata` is writable by the user it belongs to (H-7), and the
      // fallback claimed the top of the command chain for an account with no
      // role in its metadata at all. The role comes from `profiles` and only
      // from there; see `userRole`.

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

    // Which refetch is the newest one asked for.
    //
    // Every realtime event triggers a full refetch, so during a burst several
    // are in flight at once. Responses are not guaranteed to come back in the
    // order they were sent, and each one ends in an unconditional setAlerts —
    // so a slower earlier request could land last and put an older board on
    // the screen. Nothing is lost from the database and the next event
    // corrects it, but "the screen briefly showed fewer incidents than exist"
    // is not a thing to leave in a dispatch console.
    //
    // Each request takes a number and only the newest one is allowed to write.
    let latestAlertsRequest = 0;
    let latestTelemetryRequest = 0;

    const fetchAlertsData = async () => {
      const mine = ++latestAlertsRequest;

      // `count: 'exact'` so the cap below can be reported rather than hidden.
      const { data, count, error } = await supabase
        .from('alerts')
        .select('*', { count: 'exact' })
        .order('created_at', { ascending: false })
        .limit(ALERT_WINDOW);

      // A newer refetch has already answered; this one is stale.
      if (mine !== latestAlertsRequest) return;

      // AN EMPTY BOARD AND A REFUSED ONE ARE NOT THE SAME THING.
      //
      // `error` was never destructured. A failed read — a row-level security
      // policy that does not admit this account, a dropped connection, a
      // column that does not exist — left `data` null, skipped the mapping
      // below, and left `alerts` as []. The screen then said:
      //
      //     ALL SECTORS CLEAR
      //     No active incidents require intervention at this time.
      //
      // which is an affirmative claim about the safety of Plateau State, made
      // on the strength of a question nobody answered. It is the most
      // dangerous failure a console like this has, because it is indisputable
      // and it is calm.
      //
      // The mobile app already had this rule — mission_feed_liveness_test.dart
      // asserts that a LIVE, empty feed is the only thing allowed to say ALL
      // CLEAR. The console never did.
      if (error) {
        console.error('[HQ_FEED_ERR]', error);
        setFeedError(error.message || 'The incident feed could not be read.');
        return;
      }
      setFeedError(null);

      setAlertsTotal(count ?? null);

      // AN EMPTY BOARD HAS TO BE CORROBORATED.
      //
      // Row-level security is not an error. A request that reaches PostgREST
      // without a usable token — an expired session this client still holds a
      // `user` for, an anon key from a different project — has a NULL
      // auth.uid() in every policy, so nothing is admitted and the answer is a
      // successful 200 with []. `error` is null. It is byte-for-byte the
      // response an empty Plateau would give, and the check above cannot tell
      // them apart.
      //
      // So when the board comes back empty, ask the database whether it knows
      // who is asking: select our own profiles row, which
      // profiles_select_self_or_staff admits on `id = auth.uid()`. A row back
      // means the token arrived and the emptiness is real. Nothing back, with
      // no error, means the token did not arrive and the emptiness means
      // nothing at all.
      //
      // Only when the board is empty, so the normal path pays for none of it.
      if ((data?.length ?? 0) === 0 && user?.id) {
        const { data: me, error: meError } = await supabase
          .from('profiles')
          .select('id')
          .eq('id', user.id)
          .maybeSingle();
        if (mine !== latestAlertsRequest) return;
        // An error here is its own answer and is reported as one. Absence of
        // both a row and an error is the case this exists for.
        setIdentityConfirmed(meError ? null : Boolean(me));
      } else {
        setIdentityConfirmed(null);
      }

      if (data) {
        const mapped = data.map((d: any) => ({
          ...d,
          // Do NOT invent coordinates. This used to fall back to
          // (9.9285, 8.8921) — central Jos — so an alert with no GPS fix
          // rendered as a confident pin and responders were dispatched to a
          // location produced by a `||` operator. `??` rather than `||` so a
          // legitimate 0 is preserved. See E2E_AUDIT_REPORT.md C-5.
          // The telemetry path below already does this correctly.
          lat: d.latitude ?? d.lat ?? null,
          lng: d.longitude ?? d.lng ?? null,
          // Was `|| 'HIGH'`, which invented a severity for a row that has
          // none — the same move as the fabricated coordinates in C-5, one
          // field over. An alert nobody has graded was drawn in the same red as
          // one graded HIGH by the person who reported it, and there was no way
          // to tell them apart. UNKNOWN renders muted (the colour maps have no
          // entry for it and fall through to var(--text-muted)) and does not
          // match the CRITICAL filter, which is correct: we do not know that it
          // is. Surface the absence rather than paint over it.
          priority: d.severity || 'UNKNOWN',
        }));
        setAlerts(mapped as Alert[]);
        setHistory(mapped.filter((a: any) => a.status === 'RESOLVED') as Alert[]);

        // Make sure the people named on these alerts are actually loadable.
        //
        // Reporter and officer names come from `usersMap`, which is filled by a
        // separate effect with `profiles ... limit(1000)`. That is fine for the
        // staff directory and wrong for reporters: this is a citizen app in a
        // state of four million people, so the 1001st citizen to raise an alert
        // would render as "profile not loaded" forever, on a query that
        // succeeded. Fetching the profiles these alerts actually name is
        // bounded by what is on screen — at most 500 rows — and merges into the
        // same map. Same pattern the telemetry path already uses.
        const named = Array.from(
          new Set(
            mapped
              .flatMap((a: any) => [a.reported_by, a.assigned_to, a.acknowledged_by])
              .filter((id: unknown): id is string => typeof id === 'string' && id.length > 0),
          ),
        );
        if (named.length > 0) {
          const { data: reporters } = await supabase
            .from('profiles')
            .select('id, full_name, email, phone, role, badge_number, geo_lga, geo_ward, geo_pu')
            .in('id', named);
          if (reporters && reporters.length > 0) {
            setUsersMap(prev => {
              // Return the SAME object when nothing is new. `usersMap` is a
              // dependency of the map's marker effect, so a fresh object on
              // every realtime refetch would rebuild every popup — including
              // the one the operator has open — two or three times a minute.
              if (reporters.every((p: any) => prev[p.id])) return prev;
              const merged = { ...prev };
              reporters.forEach((p: any) => { merged[p.id] = p; });
              return merged;
            });
          }
        }
      }
    };

    const debouncedFetchAlerts = () => {
      if (alertDebounceTimer) clearTimeout(alertDebounceTimer);
      alertDebounceTimer = setTimeout(() => {
        fetchAlertsData();
      }, 300);
    };

    const fetchTelemetryData = async () => {
      const mine = ++latestTelemetryRequest;
      const { data: telemetryData } = await supabase
        .from('telemetry').select('*').limit(ALERT_WINDOW);
      if (mine !== latestTelemetryRequest) return;
      if (!telemetryData || telemetryData.length === 0) return;

      // Enrich with profile names in one batch query
      const userIds = telemetryData.map((t: any) => t.user_id);
      const { data: profiles } = await supabase
        .from('profiles')
        .select('id, full_name, role')
        .in('id', userIds);

      if (mine !== latestTelemetryRequest) return;

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
          mode: t.mode,
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
        // This asked for `lga, ward, sector_id`, and `usersMap` stayed empty —
        // every officer rendered as `TACTICAL SQUAD #A1B2C3` and every reporter
        // as "Registered Citizen / No Phone Registered", with nothing errored.
        //
        // CORRECTION. This comment used to say none of those three is a column.
        // All three are, on production: 20260721000000_v2_agency_tables adds
        // `profiles.sector_id`, plus `lga` and `ward` as generated mirrors of
        // `geo_lga`/`geo_ward`. That file was applied to the live database by
        // hand, and no database this repository could build had those columns —
        // so the claim was true of the repository and false of the database it
        // talks to, and the reason the query failed is not recorded anywhere.
        //
        // 20261017000000 brings that era into the migration history, so the two
        // schemas agree and `scripts/check_schema_convergence.py` keeps them
        // agreeing. Selecting the real `geo_*` names is still right — they are
        // what the rest of this file reads — but the diagnosis above was reached
        // by checking the migrations instead of the database.
        //
        // It was also missing the fields its consumers actually read.
        // `badge_number` is what formatOfficerBadge() and
        // getOfficerDisplayName() label officers with, `email` is what both
        // fall back to and match on, and `phone` is what the incident dossier
        // shows as the reporter's contact — the number HQ rings back. All three
        // were read off a map they were never selected into.
        //
        // The geography columns are selected under their real names and kept:
        // nothing reads them off this map today, but they are what the map is
        // for if it ever scopes by area.
        .select('id, full_name, email, phone, role, badge_number, geo_lga, geo_ward, geo_pu')
        .limit(1000);
      if (data) {
        // Merge, do not replace. The alerts fetch also puts profiles in here —
        // the ones the visible alerts name, which for a reporter beyond this
        // query's 1000-row limit is the only place they come from — and these
        // two effects race. Replacing would drop them on whichever order won.
        setUsersMap(prev => {
          const merged = { ...prev };
          data.forEach((p: any) => { merged[p.id] = p; });
          return merged;
        });
      }
    };

    fetchProfiles();
  }, [user]);

  // NOTE: Live agent tracking is handled by the combined data useEffect above
  // (hq-telemetry-channel). Duplicate subscription removed — BUG #11.

  // The four writes live in src/lib/alert-actions.ts so they can be tested —
  // they change incidents, and a dispatch that silently did not happen looks
  // exactly like one that did. What stays here is the toast wrapping, which is
  // presentation.
  const escalateAlert = useCallback(async (alertId: AlertIds, targetLga: string = 'ALL', reason: string = '', targetAgency: string = 'ALL') => {
    const lgaTarget = targetLga || 'ALL';
    const agencyTarget = targetAgency || 'ALL';
    const toastId = toast.loading('Escalating Incident...', `Handing over to ${agencyTarget} Command (${lgaTarget})`);
    const res = await alertActions.escalateAlert(
      alertId,
      { targetLga, reason, targetAgency },
      { id: user?.id, email: user?.email },
    );
    if (res.ok) {
      // "RECORDED", not "SENT".
      //
      // This said `Escalation Sent`, and the only thing it knew about was the
      // write to `alerts`. Whether the agency was reached was decided by a POST
      // whose answer nobody read — and for four of the six destinations the
      // menu used to offer, that POST was refused outright. The handover is now
      // two statements because it is two facts: the incident has changed hands
      // in the record, and the agency has (or has not) been told.
      toast.update(toastId, 'success', 'Escalation Recorded', `Handed off to ${res.value.commanderName} (${res.value.agency})`);
      const notified = res.value.notified;
      if (notified && !notified.delivered) {
        // A warning, not an error: the escalation itself stands. What this
        // needs from the operator is a phone call, not a second escalation.
        toast.warning(`${res.value.agency} NOT NOTIFIED`, notified.detail);
      }
    } else {
      toast.update(toastId, 'error', 'Escalation Failed', res.error);
    }
  }, [toast, user]);

  /**
   * Opens the full dossier for an incident clicked on the map.
   *
   * The marker popup carries what a dispatcher acts on; the dossier carries the
   * rest. Looked up in `alerts` — the raw rows — because the map is handed
   * `filtered`, whose cards may be cluster masters, and the dossier is about
   * one report.
   */
  const openDossierById = useCallback((id: string) => {
    const found = alerts.find(a => a.id === id);
    if (found) setSelectedReport(found);
  }, [alerts]);

  const hqOverride = useCallback(async (alertId: AlertIds) => {
    const toastId = toast.loading('HQ Override...', 'Taking command of incident');
    const res = await alertActions.hqOverride(alertId, { id: user?.id, email: user?.email });
    if (res.ok) {
      toast.update(toastId, 'success', 'HQ Override Applied', 'Incident transferred to Command HQ');
    } else {
      toast.update(toastId, 'error', 'Override Failed', res.error);
    }
  }, [toast, user]);

  const resolveAlert = useCallback(async (alertId: AlertIds) => {
    const toastId = toast.loading('Resolving Incident...', 'Marking incident as resolved');
    const res = await alertActions.resolveAlert(alertId, { id: user?.id, email: user?.email });
    if (res.ok) {
      toast.update(toastId, 'success', 'Incident Resolved', 'Alert marked as resolved and archived with officer attribution');
    } else {
      toast.update(toastId, 'error', 'Resolution Failed', res.error);
    }
  }, [toast, user]);

  const dispatchAlert = useCallback(async (alertId: AlertIds, responderUids: string[] | string) => {
    const uids = Array.isArray(responderUids) ? responderUids : [responderUids];
    if (uids.length === 0) return;
    const toastId = toast.loading('Dispatching Tactical Team...', `Assigning ${uids.length} responders to incident`);
    const res = await alertActions.dispatchAlert(alertId, uids);
    if (res.ok) {
      toast.update(toastId, 'success', 'Tactical Team Dispatched', `${res.value.count} field units successfully assigned and notified`);
    } else {
      toast.update(toastId, 'error', 'Dispatch Failed', res.error);
    }
  }, [toast]);

  const [filterLga, setFilterLga] = useState('ALL');
  const [filterWard, setFilterWard] = useState('ALL');
  const [filterPu, setFilterPu] = useState('ALL');
  const [enableClustering, setEnableClustering] = useState(true);

  // Clustering and filtering moved to src/lib/alert-display.ts so they can be
  // tested: they decide what reaches an operator's screen, and were previously
  // buried in this component with no coverage at all.
  const displayAlerts = clusterAlerts(alerts, enableClustering);

  // Derived during render rather than held in state: these are a pure function
  // of the alerts already loaded, and a second copy in state would be one more
  // thing that can be stale.
  // The operator's own posting, which scopes the responder picker on every
  // incident card. Derived rather than held in state: it is a view of the
  // profile already loaded.
  const dispatcherPosting = {
    id: user?.id,
    role: userRole,
    geo_lga: userProfile?.geo_lga as string | undefined,
    geo_ward: userProfile?.geo_ward as string | undefined,
    geo_pu: userProfile?.geo_pu as string | undefined,
  };

  const categoriesOnBoard = categoriesPresent(alerts);
  const categoryTallies = categoryCounts(alerts);

  const filtered = filterAlerts(displayAlerts, {
    status: filterStatus,
    tier: filterTier,
    category: filterCategory,
    lga: filterLga,
    ward: filterWard,
    pu: filterPu,
  });

  // What an empty board means, and therefore what it is allowed to say.
  // `alerts.length`, not `displayAlerts.length`: clustering folds rows together
  // but never drops them, and the number an operator needs is how many
  // incidents came back from the database.
  const boardState = {
    feedError,
    loaded: alerts.length,
    visible: filtered.length,
    identityConfirmed,
  };
  const boardMeaning = emptyBoardMeaning(boardState);
  const boardWording = emptyBoardWording(boardState);

  const isMatchingLocation = (target: string, value?: string) => {
    if (!target || target === 'ALL') return true;
    if (!value) return false;
    // Keyed, not alphanumeric-squashed. The old version stripped every
    // non-alphanumeric character, which turned 'GINDIRI  I' into 'gindirii'
    // and 'GINDIRI  1' into 'gindiri1' — the two spellings of one ward, made
    // further apart by the normalisation meant to bring them together. Worse,
    // squashing let 'mangu11' contain 'mangu1', so the sector counters beside
    // the filter added the neighbouring ward's duress alarms to this one's.
    // geo-key.ts handles both, and matches what RLS compares on.
    if (geoMatchesKeyed(value, target)) return true;
    // A polling unit may carry a beat code in brackets that the other side
    // does not: 'KATAKO (BEAT-BARKIN_LADI-11)' against 'KATAKO'.
    const bare = (s: string) => s.replace(/\s*\([^)]+\)/g, '');
    return geoMatchesKeyed(bare(value), bare(target));
  };

  const formatPuOption = (puRaw: string, defaultBadge?: string): SelectOption => {
    const match = puRaw.match(/^(.*?)(?:\s*\((BEAT-[^)]+)\))?$/);
    const labelName = match && match[1] ? match[1].trim() : puRaw;
    const beatCode = match && match[2] ? match[2].trim() : undefined;
    return {
      value: puRaw,
      label: labelName,
      badge: beatCode ? beatCode.split('-').pop() : (defaultBadge || 'PU')
    };
  };

  // Sector-Aware Duress & SMS Fallback Counters
  const sectorAlerts = alerts.filter(a => {
    const aLga = a.geo_lga || (a as any).lga;
    const aWard = a.geo_ward || (a as any).ward;
    const aPu = a.geo_pu || (a as any).pu || (a as any).polling_unit;
    
    if (!isMatchingLocation(filterLga, aLga)) return false;
    if (!isMatchingLocation(filterWard, aWard)) return false;
    if (!isMatchingLocation(filterPu, aPu)) return false;
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
  const isHqUser = userRole === 'HQ_OFFICER' || userRole === 'HQ_COMMAND' || userRole === 'ADMIN';
  // One tested answer to "what may this account reach", rather than the
  // conditionals this had grown. See src/lib/console-access.ts.
  const access = consoleAccess(userRole, {
    sector: userProfile?.geo_lga || userProfile?.geo_ward || userProfile?.geo_pu,
  });
  const isAgencyLiaison = access.agency !== null;
  const userAgencyCode = access.agency ?? undefined;

  const lgaSelectOptions: SelectOption[] = [
    { value: 'ALL', label: 'ALL LGAS (STATEWIDE)', badge: 'STATE' },
    ...plateauTacticalMap.map(lga => ({
      value: lga.name,
      label: lga.name.toUpperCase(),
      badge: 'LGA'
    }))
  ];

  const selectedLgaObj = plateauTacticalMap.find(l => isMatchingLocation(filterLga, l.name));
  
  const selectedWardObj = selectedLgaObj
    ? selectedLgaObj.wards.find(w => isMatchingLocation(filterWard, w.name))
    : plateauTacticalMap.flatMap(l => l.wards).find(w => isMatchingLocation(filterWard, w.name));

  // Build full Wards list (from static tactical map + live alerts)
  const mapWards: SelectOption[] = selectedLgaObj
    ? selectedLgaObj.wards.map(w => ({
        value: w.name,
        label: w.name.toUpperCase(),
        badge: selectedLgaObj.name.substring(0, 4).toUpperCase()
      }))
    : plateauTacticalMap.flatMap(lga => lga.wards.map(w => ({
        value: w.name,
        label: `${w.name.toUpperCase()} (${lga.name.toUpperCase()})`,
        badge: lga.name.substring(0, 4).toUpperCase()
      })));

  // Extract extra wards from live alerts that might not be in static map
  // Deduplicated on geoKey, not on an alphanumeric squash. The squash kept
  // 'GINDIRI  I' and 'GINDIRI  1' apart, so the dropdown offered the same
  // ward twice — once from the map and once marked LIVE — and whichever the
  // operator picked selected only half its incidents.
  const alertWards: SelectOption[] = [];
  const seenWardVals = new Set(mapWards.map(w => geoKey(w.value)));
  
  alerts.forEach(a => {
    const wName = a.geo_ward || (a as any).ward;
    if (wName && !seenWardVals.has(geoKey(wName))) {
      seenWardVals.add(geoKey(wName));
      alertWards.push({
        value: wName,
        label: wName.toUpperCase(),
        badge: 'LIVE'
      });
    }
  });

  const wardSelectOptions: SelectOption[] = [
    { value: 'ALL', label: 'ALL WARDS / DISTRICTS', badge: 'ALL' },
    ...mapWards,
    ...alertWards
  ];

  // Build full Polling Units list (from static tactical map + live alerts)
  const mapPus: SelectOption[] = selectedWardObj
    ? selectedWardObj.pollingUnits.map(pu => formatPuOption(pu, 'PU'))
    : (selectedLgaObj
        ? selectedLgaObj.wards.flatMap(w => w.pollingUnits.map(pu => formatPuOption(pu, w.name.substring(0, 4).toUpperCase())))
        : plateauTacticalMap.flatMap(l => l.wards.flatMap(w => w.pollingUnits.map(pu => formatPuOption(pu, l.name.substring(0, 4).toUpperCase())))));

  const alertPus: SelectOption[] = [];
  const seenPuVals = new Set(mapPus.map(p => geoKey(p.value)));
  
  alerts.forEach(a => {
    const puName = a.geo_pu || (a as any).pu || (a as any).polling_unit;
    if (puName && !seenPuVals.has(geoKey(puName))) {
      seenPuVals.add(geoKey(puName));
      alertPus.push(formatPuOption(puName, 'LIVE'));
    }
  });

  const puSelectOptions: SelectOption[] = [
    { value: 'ALL', label: 'ALL BEATS (PU)', badge: 'ALL' },
    ...mapPus,
    ...alertPus
  ];

  const statusSelectOptions: SelectOption[] = [
    { value: 'ALL', label: 'ALL STATUS' },
    { value: 'OPEN', label: 'OPEN THREATS' },
    { value: 'ACTIVE', label: 'ACTIVE INCIDENTS' },
    { value: 'DURESS', label: 'DURESS EMERGENCY 🚨' },
    { value: 'CRITICAL', label: 'CRITICAL HOTSPOTS' },
    { value: 'SMS_FALLBACK', label: '📡 SMS FALLBACK' },
  ];

  const tierSelectOptions: SelectOption[] = [
    { value: 'ALL', label: 'ALL TIERS' },
    { value: 'POLLING_UNIT', label: 'POLLING UNIT (BEAT)', badge: 'PU' },
    { value: 'WARD', label: 'WARD / DISTRICT', badge: 'WARD' },
    { value: 'LGA', label: 'LGA COMMAND', badge: 'LGA' },
    { value: 'HQ', label: 'STATEWIDE HQ', badge: 'HQ' },
  ];

  return (
    <div style={{ display: 'flex', height: '100vh', background: 'var(--bg-primary)', overflow: 'hidden', color: 'var(--text-primary)', padding: isNarrow ? '8px' : '16px', gap: isNarrow ? 0 : '16px', boxSizing: 'border-box' }}>
      {/* Backdrop for the drawer. Only rendered while it is open, so it never
          swallows clicks on the desktop layout. */}
      {isNarrow && navOpen && (
        <div
          onClick={() => setNavOpen(false)}
          style={{ position: 'fixed', inset: 0, background: 'rgba(2,6,23,0.6)', zIndex: 4000 }}
        />
      )}

      <aside
        className="tactical-panel glass"
        onClick={() => { if (isNarrow) setNavOpen(false); }}
        style={{
          width: 280,
          display: 'flex',
          flexDirection: 'column',
          padding: '24px 16px',
          flexShrink: 0,
          ...(isNarrow
            ? {
                position: 'fixed' as const,
                top: 8, bottom: 8, left: 8,
                zIndex: 5000,
                maxHeight: 'calc(100vh - 16px)',
                transform: navOpen ? 'none' : 'translateX(calc(-100% - 16px))',
                transition: 'transform .22s ease',
                boxShadow: navOpen ? '0 24px 60px rgba(0,0,0,.5)' : 'none',
              }
            : { zIndex: 100, maxHeight: '100%' }),
        }}
      >
        {/* Sidebar Header (Fixed at top) */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 24, padding: '0 8px', flexShrink: 0 }}>
          <div className="pulse-emerald" style={{ background: 'var(--primary)', padding: 10, borderRadius: 12, display: 'flex', alignItems: 'center', justifyContent: 'center', boxShadow: 'var(--primary-glow)' }}>
            <ShieldAlert size={24} color="#fff" />
          </div>
          <div>
            {/* Whose console this is. It said "COMMAND HQ — TACTICAL MONITOR"
                to an officer of the Nigeria Police Force, which in a system
                that hands incidents between organisations is not cosmetic. */}
            <h1 style={{ fontSize: 16, fontWeight: 900, letterSpacing: 1, textTransform: 'uppercase' }}>
              {access.title}
            </h1>
            <p style={{ fontSize: 9, color: 'var(--primary)', fontWeight: 800, letterSpacing: 2.5 }}>
              {access.subtitle}
            </p>
          </div>
        </div>

        {/* Scrollable Navigation & Metrics Container */}
        <div style={{ flex: 1, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 24, paddingRight: 4, marginBottom: 16 }}>
          <nav style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
            <p style={{ fontSize: 9, fontWeight: 900, color: 'var(--text-dim)', letterSpacing: 2, marginBottom: 8, paddingLeft: 12 }}>
              {access.agency ? 'AGENCY NAVIGATION' : 'SYSTEM NAVIGATION'}
            </p>
            {/* What this account may reach, from one tested place
                (src/lib/console-access.ts). Hiding a control is not access
                control — the database decides — but OFFERING one that will be
                refused is its own defect, and the two have to agree. An agency
                liaison was being shown Communications & Broadcast, which
                `system_alerts` INSERT refuses for any non-command role: they
                could write a statewide advisory and only then be told no. */}
            {access.tabs.includes('map') && (
              <NavItem icon={<MapIcon size={18} />} label="Intelligence Map" active={activeTab === 'map'} onClick={() => setActiveTab('map')} />
            )}
            {access.tabs.includes('alerts') && (
              <NavItem
                icon={<Activity size={18} />}
                label={access.agency ? 'Incidents For Us' : 'Incident Feed'}
                active={activeTab === 'alerts'}
                onClick={() => setActiveTab('alerts')}
                badge={alerts.length > 0 ? alerts.length : undefined}
              />
            )}
            {access.tabs.includes('history') && (
              <NavItem icon={<Clock size={18} />} label="Mission History" active={activeTab === 'history'} onClick={() => setActiveTab('history')} />
            )}
            {access.tabs.includes('broadcast') && (
              <NavItem icon={<Radio size={18} />} label="Communications & Broadcast" active={activeTab === 'broadcast'} onClick={() => setActiveTab('broadcast')} />
            )}
            {access.tabs.includes('agency') && (
              <NavItem
                icon={<Shield size={18} />}
                label={access.agency ? 'Our Deployments' : 'Inter-Agency Command'}
                active={activeTab === 'agency'}
                onClick={() => setActiveTab('agency')}
                badge={unreadAgencyReports > 0 ? unreadAgencyReports : undefined}
              />
            )}
            
            {access.administration && (
              <>
                <div style={{ margin: '16px 0', height: 1, background: 'var(--border)' }}></div>
                <p style={{ fontSize: 9, fontWeight: 900, color: 'var(--text-dim)', letterSpacing: 2, marginBottom: 8, paddingLeft: 12 }}>ADMINISTRATION</p>
                <NavItem icon={<Users size={18} />} label="Agent Directory" active={activeTab === 'admin'} onClick={() => setActiveTab('admin')} />
                <NavItem icon={<Activity size={18} />} label="Forensic Audit" active={activeTab === 'audit'} onClick={() => setActiveTab('audit')} />
                <NavItem icon={<Settings size={18} />} label="System Logic" active={activeTab === 'settings'} onClick={() => setActiveTab('settings')} />
                <NavItem icon={<ShieldAlert size={18} />} label="Uninstall Requests" active={activeTab === 'uninstall'} onClick={() => setActiveTab('uninstall')} />
                <NavItem
                  icon={<SignalZero size={18} />}
                  label="Handset SMS Channel"
                  active={activeTab === 'sim'}
                  onClick={() => setActiveTab('sim')}
                  badge={openSimEvents > 0 ? openSimEvents : undefined}
                />
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
        <header style={{ padding: '0 24px', height: 72, borderBottom: '1px solid var(--border)', display: 'flex', alignItems: 'center', justifyContent: 'space-between', flexShrink: 0, gap: 16 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 16, minWidth: 0, flexShrink: 1 }}>
            {isNarrow && (
              <button
                type="button"
                onClick={() => setNavOpen(o => !o)}
                aria-label={navOpen ? 'Close navigation' : 'Open navigation'}
                aria-expanded={navOpen}
                style={{
                  flexShrink: 0, width: 38, height: 38, borderRadius: 10,
                  border: '1px solid var(--border)', background: 'var(--bg-secondary)',
                  color: 'var(--text-primary)', cursor: 'pointer',
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                }}
              >
                <Menu size={18} />
              </button>
            )}
            <div style={{ minWidth: 0 }}>
              <h2 style={{ fontSize: 15, fontWeight: 900, textTransform: 'uppercase', letterSpacing: 1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', maxWidth: 260 }}>
                {activeTab === 'map' && (
                  filterLga !== 'ALL' 
                    ? `${filterLga.toUpperCase()} SECTOR`
                    : (isHqUser ? 'Statewide Monitoring' : `${userProfile?.geo_lga || 'Sector'} Monitoring`)
                )}
                {activeTab === 'alerts' && (
                  filterLga !== 'ALL'
                    ? `${filterLga.toUpperCase()} FEED`
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
                {activeTab === 'sim' && 'Handset SMS Channel'}
              </h2>
            </div>
            {!isNarrow && <div style={{ height: 20, width: 1, background: 'var(--border)', flexShrink: 0 }}></div>}
            <div style={{ display: isNarrow ? 'none' : 'flex', gap: 12, flexShrink: 0 }}>
               <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                  <div style={{ width: 8, height: 8, borderRadius: '50%', background: 'var(--success)', boxShadow: 'var(--success-glow)' }} className="pulse-emerald"></div>
                  <span style={{ fontSize: 10, fontWeight: 900, color: 'var(--success)', letterSpacing: 0.5 }}>LIVE UPLINK</span>
               </div>
               <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                  <Clock size={13} color="var(--text-muted)" />
                  <span style={{ fontSize: 10, fontWeight: 700, color: 'var(--text-muted)', fontFamily: 'monospace' }}>{timeString}</span>
               </div>
            </div>
          </div>

          <div style={{ display: 'flex', alignItems: 'center', gap: 10, flexShrink: 0 }}>
            {duressCount > 0 && (
              <div className="pulse-crimson" style={{ 
                background: 'var(--duress-dim)',
                border: '1px solid var(--duress)', 
                borderRadius: 8, 
                padding: '6px 12px', 
                display: 'flex', 
                alignItems: 'center', 
                gap: 6,
                boxShadow: 'var(--duress-glow)'
              }}>
                <AlertTriangle size={13} color="var(--duress)" />
                <span style={{ fontSize: 10, fontWeight: 900, color: 'var(--duress)' }}>{duressCount} DURESS</span>
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
                  padding: '6px 12px', 
                  display: 'flex', 
                  alignItems: 'center', 
                  gap: 6,
                  cursor: 'pointer',
                  boxShadow: '0 0 15px rgba(245, 158, 11, 0.2)'
                }}
              >
                <Radio size={13} color="#FF9800" className="spin-slow" />
                <span style={{ fontSize: 10, fontWeight: 900, color: '#FF9800' }}>{smsFallbackCount} SMS</span>
              </div>
            )}

            <button
              onClick={() => setEnableClustering(c => !c)}
              title={enableClustering ? 'Spatial-Temporal Proximity Clustering Active' : 'Clustering Off'}
              style={{
                background: enableClustering ? 'rgba(79, 70, 229, 0.15)' : 'var(--bg-secondary)',
                border: enableClustering ? '1px solid var(--accent)' : '1px solid var(--border)',
                borderRadius: 8,
                padding: '6px 12px',
                display: 'flex',
                alignItems: 'center',
                gap: 6,
                cursor: 'pointer',
                color: enableClustering ? 'var(--accent)' : 'var(--text-muted)',
                fontSize: 10,
                fontWeight: 800
              }}
            >
              <Sparkles size={13} color={enableClustering ? 'var(--accent)' : 'var(--text-muted)'} />
              <span>{enableClustering ? 'CLUSTERING: ON' : 'RAW FEED'}</span>
            </button>

            {/* Theme Toggle Button */}
            <button 
              onClick={() => setTheme(t => t === 'light' ? 'dark' : 'light')}
              title={`Switch to ${theme === 'light' ? 'Dark' : 'Light'} Mode`}
              className="btn-tactical btn-secondary"
              style={{
                borderRadius: 8,
                width: 34,
                height: 34,
                padding: 0,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                boxShadow: 'var(--shadow-sm)',
              }}
            >
              {theme === 'light' ? <Moon size={15} /> : <Sun size={15} />}
            </button>

            <div style={{ textAlign: 'right', paddingLeft: 4 }}>
              <p style={{ fontSize: 10, fontWeight: 900, color: 'var(--text-primary)' }}>{(user?.email || 'HQ').split('@')[0].toUpperCase()}</p>
              <p style={{ fontSize: 9, fontWeight: 700, color: 'var(--accent)' }}>{(userRole ?? access.subtitle).replace('_', ' ')}</p>
            </div>
          </div>
        </header>

        {/* The advisory banner is scoped to this operator now: it applied no
            targeting at all, so an advisory addressed to citizens of one ward
            docked here and one addressed to another agency docked on that
            liaison's screen. `access.agency` rather than `userProfile.agency`,
            because the former is derived from the ROLE and the latter is a
            decorative badge (T-28). */}
        <SystemAlertListener
          viewer={{
            // Both come from the role, and the role is `null` until the
            // `profiles` read lands — so until then `access.agency` is null and
            // `isHqUser` is false, which is the most restricted viewer this
            // filter has. There was a `roleResolved ? ... : null` guard here
            // for one commit; it was a patch over the privileged default, and
            // once the default was gone it was dead logic reading as the thing
            // that protected you. The default is what protects you, and it
            // protects every other consumer of the role at the same time.
            agency: access.agency,
            isCommand: isHqUser,
            geoLga: userProfile?.geo_lga ?? null,
            geoWard: userProfile?.geo_ward ?? null,
            geoPu: userProfile?.geo_pu ?? null,
          }}
        />

        {/* Filters sit IN THE FLOW, not floating over the map.
            They were `position: absolute; top: 86` with only a left edge, so
            `flexWrap: 'wrap'` could never fire and the row simply ran off the
            side of the map — and the hard-coded 86px assumed nothing would ever
            appear between the header and the map, which the advisory banner now
            does. As a normal toolbar row they wrap when the viewport is narrow,
            stack correctly under the banner, and stop competing with the map's
            own overlays for the top-left corner. */}
        {activeTab === 'map' && (
          <div style={{ flexShrink: 0, padding: isNarrow ? '10px 12px 0' : '14px 24px 0', display: 'flex', gap: 8, flexWrap: 'wrap', alignItems: 'center' }}>
            <div className="glass" style={{ padding: '6px 10px', borderRadius: 12, display: 'flex', alignItems: 'center', gap: 8, border: '1px solid var(--border)', boxShadow: '0 12px 32px rgba(0,0,0,0.3)', backdropFilter: 'blur(16px)' }}>
              <Filter size={13} style={{ color: 'var(--text-muted)' }} />
              
              {/* STATUS FILTER */}
              <TacticalSelect
                value={filterStatus}
                options={statusSelectOptions}
                onChange={v => setFilterStatus(v)}
                accentColor="#FF9800"
                maxWidth={160}
              />
              
              <div style={{ width: 1, height: 16, background: 'var(--border)' }} />

              {/* LGA SELECTOR */}
              <TacticalSelect
                value={filterLga}
                options={lgaSelectOptions}
                onChange={v => {
                  setFilterLga(v);
                  setFilterWard('ALL');
                  setFilterPu('ALL');
                }}
                accentColor="#1B5E20"
                maxWidth={180}
                icon={<MapPin size={13} />}
                placeholder="LGA"
              />

              <span style={{ fontSize: 10, color: 'var(--text-dim)' }}>/</span>

              {/* WARD SELECTOR (ALWAYS VISIBLE) */}
              <TacticalSelect
                value={filterWard}
                options={wardSelectOptions}
                onChange={v => {
                  setFilterWard(v);
                  setFilterPu('ALL');
                  if (v !== 'ALL') {
                    const parentLga = plateauTacticalMap.find(l => l.wards.some(w => w.name === v));
                    if (parentLga) setFilterLga(parentLga.name);
                  }
                }}
                accentColor="var(--accent)"
                maxWidth={170}
                placeholder="WARD"
                searchable
              />

              <span style={{ fontSize: 10, color: 'var(--text-dim)' }}>/</span>

              {/* POLLING UNIT SELECTOR (ALWAYS VISIBLE) */}
              <TacticalSelect
                value={filterPu}
                options={puSelectOptions}
                onChange={v => {
                  setFilterPu(v);
                  if (v !== 'ALL') {
                    for (const lga of plateauTacticalMap) {
                      for (const ward of lga.wards) {
                        if (ward.pollingUnits.includes(v)) {
                          setFilterLga(lga.name);
                          setFilterWard(ward.name);
                          break;
                        }
                      }
                    }
                  }
                }}
                accentColor="#FF9800"
                maxWidth={210}
                placeholder="BEAT (PU)"
                searchable
              />

              <div style={{ width: 1, height: 16, background: 'var(--border)' }} />

              {/* TIER SELECTOR */}
              <TacticalSelect
                value={filterTier}
                options={tierSelectOptions}
                onChange={v => setFilterTier(v)}
                accentColor="#38bdf8"
                maxWidth={140}
              />
            </div>
          </div>
        )}

        <div style={{ flex: 1, overflow: activeTab === 'map' ? 'hidden' : 'auto', padding: activeTab === 'map' ? 0 : '32px 40px' }}>
          {activeTab === 'map' && (
            <div style={{ position: 'relative', height: '100%', width: '100%' }}>
              <LiveMap
                alerts={filtered}
                agents={agentLocations}
                onResolve={resolveAlert}
                onEscalate={escalateAlert}
                // The map could not name a reporter because it was never given
                // the profiles. It declared `reportedBy`/`reportedAt` — Firebase
                // names the database does not return — and had no profile map at
                // all, so a marker could show a type and a status and nothing
                // about the person who raised it.
                usersMap={usersMap}
                onOpenDossier={openDossierById}
                // The route of whichever incident is open in the dossier,
                // thinned for drawing: a two-hour SOS at one fix every five
                // seconds is well over a thousand points, and a polyline of
                // that redraws on every pan.
                incidentTrack={
                  selectedTrack
                    ? thinTrack(selectedTrack).map((p) => ({
                        lat: p.latitude,
                        lng: p.longitude,
                      }))
                    : undefined
                }
                theme={theme}
              />
              {/*
                zIndex, or Leaflet paints over this.

                The feed is absolutely positioned as a SIBLING of the map, and
                had no z-index at all — so it sat at `auto`, which is 0. Leaflet
                gives its own children positive ones: panes 200-700, controls
                800. `.leaflet-container` sets no z-index of its own, so it
                creates no stacking context and those values compete directly
                with this panel's 0. The map won, and the situational feed was
                rendered underneath it.

                1000 is what the map's own legend in LiveMap.tsx already uses to
                sit above the same panes.
              */}
              <div className="glass fade-in" style={{ position: 'absolute', top: 24, right: 24, width: 320, maxHeight: 'calc(100% - 48px)', display: isNarrow ? 'none' : 'flex', borderRadius: 20, flexDirection: 'column', overflow: 'hidden', border: '1px solid var(--border)', boxShadow: '0 20px 40px rgba(0,0,0,0.4)', zIndex: 1000 }}>
                <div style={{ padding: '20px', borderBottom: '1px solid var(--border)', background: 'var(--bg-secondary)' }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                    <h3 style={{ fontSize: 12, fontWeight: 900, color: 'var(--accent)', letterSpacing: 1.5 }}>SITUATIONAL FEED</h3>
                    <div style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
                      {filtered.some(a => a.lat == null || a.lng == null) && (
                        // How many alerts in view have no map pin. Without this
                        // the map silently under-reports the situation.
                        <div title="Alerts with no GPS fix are listed below but cannot be plotted"
                             style={{ background: 'var(--warning)', padding: '4px 8px', borderRadius: 20 }}>
                          <span style={{ fontSize: 10, fontWeight: 900, color: '#1A1A1A' }}>
                            {filtered.filter(a => a.lat == null || a.lng == null).length} UNLOCATED
                          </span>
                        </div>
                      )}
                      <div style={{ background: 'var(--accent-dim)', padding: '4px 10px', borderRadius: 20 }}>
                        <span style={{ fontSize: 10, fontWeight: 900, color: 'var(--accent)' }}>{filtered.length} UNITS</span>
                      </div>
                    </div>
                  </div>
                </div>
                <div style={{ overflow: 'auto', flex: 1, padding: '16px', display: 'flex', flexDirection: 'column', gap: 12 }}>
                  {boardMeaning !== 'NOT_EMPTY' ? (
                    // The same rule as the triage board: "NO ACTIVE THREATS"
                    // is a claim, and a refused read has not earned it.
                    <div style={{ textAlign: 'center', padding: '40px 0' }}>
                      {boardMeaning === 'ALL_CLEAR' ? (
                        <CheckCircle size={32} color="var(--text-dim)" style={{ marginBottom: 12 }} />
                      ) : (
                        <AlertTriangle size={32} color="var(--duress)" style={{ marginBottom: 12 }} />
                      )}
                      <p style={{
                        fontSize: 12,
                        fontWeight: 600,
                        color: boardMeaning === 'ALL_CLEAR' ? 'var(--text-muted)' : 'var(--duress)',
                      }}>
                        {boardMeaning === 'ALL_CLEAR' ? 'NO ACTIVE THREATS' : boardWording.heading}
                      </p>
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
                        {(a.lat == null || a.lng == null) && (
                          // No GPS fix: this alert has no pin on the map. Say so
                          // explicitly rather than letting a dispatcher assume
                          // the absence of a marker means the absence of an
                          // incident.
                          <div style={{ marginTop: 8, display: 'flex', alignItems: 'center', gap: 6, background: 'var(--warning-dim, rgba(251,191,36,0.12))', border: '1px solid var(--warning)', borderRadius: 8, padding: '5px 8px' }}>
                            <AlertTriangle size={11} color="var(--warning)" />
                            <span style={{ fontSize: 9, fontWeight: 900, color: 'var(--warning)', letterSpacing: 0.4 }}>
                              NO GPS FIX — NOT ON MAP{a.geo_ward ? ` · ${a.geo_ward.toUpperCase()}` : ''}
                            </span>
                          </div>
                        )}
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
                  {/*
                    The console reads a bounded window. When there are more
                    incidents than that, say so: a board that silently stops at
                    a cap looks exactly like a board with nothing older on it,
                    and the operator has no way to tell.
                  */}
                  {alertsTotal !== null && alertsTotal > alerts.length && (
                    <p style={{ fontSize: 11, fontWeight: 700, color: 'var(--warning)' }}>
                      SHOWING NEWEST {alerts.length} OF {alertsTotal} INCIDENTS — FILTER TO NARROW
                    </p>
                  )}
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
                    {/*
                      Sorting by what kind of emergency it is. The categories
                      offered are the ones actually on the board, with a count,
                      rather than a fixed list of ten — a dispatcher should not
                      be able to select KIDNAP and be shown an empty screen
                      without knowing whether that means "none" or "not loaded".
                    */}
                    <select
                      value={filterCategory}
                      onChange={e => setFilterCategory(e.target.value)}
                      style={fSel}
                      aria-label="Filter by incident category"
                    >
                      <option value="ALL">ALL CATEGORIES</option>
                      {categoriesOnBoard.map(c => (
                        <option key={c} value={c}>
                          {categoryLabel(c)} ({categoryTallies[c] ?? 0})
                        </option>
                      ))}
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
              {boardMeaning !== 'NOT_EMPTY' ? (
                // Three different empty boards, three different things to do.
                // Only ALL_CLEAR is allowed to look reassuring; see
                // src/lib/empty-board.ts for why that distinction is the whole
                // safety of this panel.
                <div
                  className="glass"
                  style={{
                    padding: '80px',
                    textAlign: 'center',
                    borderRadius: 24,
                    border: boardMeaning === 'ALL_CLEAR' ? undefined : '1px solid var(--duress)',
                  }}
                >
                  {boardMeaning === 'ALL_CLEAR' ? (
                    <CheckCircle size={64} color="var(--success)" style={{ opacity: 0.3, marginBottom: 20 }} />
                  ) : (
                    <AlertTriangle size={64} color="var(--duress)" style={{ opacity: 0.8, marginBottom: 20 }} />
                  )}
                  <h3 style={{
                    fontSize: 20,
                    fontWeight: 900,
                    marginBottom: 8,
                    color: boardMeaning === 'ALL_CLEAR' ? undefined : 'var(--duress)',
                  }}>
                    {boardWording.heading}
                  </h3>
                  <p style={{ color: 'var(--text-muted)', maxWidth: 520, margin: '0 auto' }}>
                    {boardWording.detail}
                  </p>
                  {feedError && (
                    <p style={{ color: 'var(--text-dim)', fontSize: 11, marginTop: 12, fontFamily: 'monospace' }}>
                      {feedError}
                    </p>
                  )}
                </div>
              ) : (
                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(380px, 1fr))', gap: 24 }}>
                  {filtered.map(a => <AlertCard key={a.id} alert={a} agents={agentLocations} usersMap={usersMap} dispatcher={dispatcherPosting} onViewDossier={(alert) => setSelectedReport(alert)} onDispatch={dispatchAlert} onEscalate={escalateAlert} onResolve={resolveAlert} onHqOverride={hqOverride} />)}
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
          {activeTab === 'sim' && <SimChannelEvents />}
          {activeTab === 'agency' && (
            <AgencyPortal
              userRole={userRole ?? ''}
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

        // 'JUST NOW' used to be the fallback for a row with no `created_at`,
        // which asserts that an emergency is brand new on the strength of an
        // empty column. A missing timestamp is a missing timestamp.
        const reportedTimeStr = selectedReport.created_at
          ? new Date(selectedReport.created_at).toLocaleString()
          : 'TIME NOT RECORDED';

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
                    <span style={{ fontSize: 9, fontWeight: 900, color: 'var(--primary)', letterSpacing: 2, fontFamily: "var(--font-outfit), sans-serif" }}>INCIDENT DOSSIER</span>
                    <span style={{ fontSize: 8, fontWeight: 900, background: `${statusBadgeColor}22`, color: statusBadgeColor, border: `1px solid ${statusBadgeColor}`, padding: '2px 8px', borderRadius: 20 }}>{statusBadgeLabel}</span>
                  </div>
                  <h3 style={{ fontSize: 20, fontWeight: 900, color: isDuress ? 'var(--duress)' : 'var(--text-primary)', fontFamily: "var(--font-outfit), sans-serif", margin: 0 }}>
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
                    <h4 style={{ fontSize: 10, fontWeight: 900, color: 'var(--primary)', letterSpacing: 1.5, textTransform: 'uppercase', marginBottom: 12, fontFamily: "var(--font-outfit), sans-serif" }}>OPERATIONAL DETAILS</h4>
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
                      {/* MOVEMENT DURING THE INCIDENT.
                          This was drawn live on the map and then discarded:
                          `telemetry` keeps one row per person, overwritten, so
                          the trail existed only in a browser tab's memory and
                          a refresh lost it. Anybody opening the dossier after
                          the fact saw no movement at all — and for a
                          kidnapping, which way they went is the question. */}
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 12 }}>
                        <span style={{ fontSize: 11, color: 'var(--text-muted)', flexShrink: 0 }}>Movement:</span>
                        <span
                          data-testid="dossier-movement"
                          style={{ fontSize: 11, fontWeight: 700, color: 'var(--text-primary)', textAlign: 'right' }}
                        >
                          {selectedTrack === null
                            ? 'Route not loaded'
                            : describeTrack(summariseTrack(selectedTrack))}
                        </span>
                      </div>
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                        <span style={{ fontSize: 11, color: 'var(--text-muted)' }}>Incident ID:</span>
                        <span title={selectedReport.id} style={{ fontSize: 11, fontWeight: 800, color: 'var(--primary)', fontFamily: "var(--font-outfit), monospace", letterSpacing: 0.5 }}>
                          {formatIncidentId(selectedReport.id)}
                        </span>
                      </div>
                    </div>
                  </div>

                  {/* Right Column: Location & Resolution */}
                  <div style={{ borderLeft: '1px solid var(--border)', paddingLeft: 20 }}>
                    <h4 style={{ fontSize: 10, fontWeight: 900, color: 'var(--primary)', letterSpacing: 1.5, textTransform: 'uppercase', marginBottom: 12, fontFamily: "var(--font-outfit), sans-serif" }}>GEOSPATIAL & ARCHIVE</h4>
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                        <span style={{ fontSize: 11, color: 'var(--text-muted)' }}>LGA / Sector:</span>
                        <span style={{ fontSize: 11, fontWeight: 800, color: 'var(--text-primary)', textTransform: 'uppercase' }}>{placeField(selectedReport.geo_lga, 'lga')}</span>
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
                          color: 'var(--accent)', 
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
                  <h4 style={{ fontSize: 10, fontWeight: 900, color: 'var(--primary)', letterSpacing: 1.5, textTransform: 'uppercase', marginBottom: 8, fontFamily: "var(--font-outfit), sans-serif" }}>INITIAL REPORT DESCRIPTION</h4>
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

                {/* WebRTC Live Stream Receiver */}
                <LiveFeedViewer alertId={selectedReport.id} />

                {/* Attached Media Dossier (Video, Photos, Audio) */}
                {((selectedReport.media_urls && selectedReport.media_urls.length > 0) || (selectedReport.attachments && selectedReport.attachments.length > 0)) && (
                  <div>
                    <h4 style={{ fontSize: 10, fontWeight: 900, color: 'var(--accent)', letterSpacing: 1.5, textTransform: 'uppercase', marginBottom: 12, fontFamily: "var(--font-outfit), sans-serif" }}>
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
                                {/* eslint-disable-next-line @next/next/no-img-element -- next.config sets images.unoptimized, so next/image would serve this byte-identically while additionally requiring the Supabase Storage host in images.remotePatterns — a second copy of the CSP's img-src allowlist to keep in sync. Lazy loading, the part of the rule's concern that is real here, is set explicitly. */}
                                <img src={url} alt="Incident media" loading="lazy" decoding="async" style={{ width: '100%', height: 180, borderRadius: 12, objectFit: 'cover' }} />
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
                    <h4 style={{ fontSize: 9, fontWeight: 900, color: 'var(--primary)', letterSpacing: 1.5, textTransform: 'uppercase', marginBottom: 12, fontFamily: "var(--font-outfit), sans-serif" }}>REPORTER PROFILE</h4>
                    <div style={{ fontSize: 13, fontWeight: 800, color: 'var(--text-primary)' }}>{reporterName}</div>
                    <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 4, fontWeight: 600 }}>{reporterContact}</div>
                    <div style={{ fontSize: 8, color: 'var(--text-dim)', marginTop: 8, fontWeight: 900, textTransform: 'uppercase', letterSpacing: 0.5 }}>
                      SOURCE: {reporterType}
                    </div>
                  </div>

                  {/* Resolution Details */}
                  <div style={{ padding: 20, background: 'var(--input-bg)', borderRadius: 20, border: '1px solid var(--border)' }}>
                    <h4 style={{ fontSize: 9, fontWeight: 900, color: 'var(--primary)', letterSpacing: 1.5, textTransform: 'uppercase', marginBottom: 12, fontFamily: "var(--font-outfit), sans-serif" }}>RESOLUTION LOG</h4>
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
                      <h4 style={{ fontSize: 10, fontWeight: 900, color: 'var(--primary)', letterSpacing: 1.5, textTransform: 'uppercase', margin: 0, fontFamily: "var(--font-outfit), sans-serif" }}>
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
                      {/* When it was produced. A debrief written before the
                          incident was resolved reads identically to one written
                          after it, and an operator acting on a week-old
                          assessment as though it were current is the kind of
                          mistake a timestamp prevents for one line. */}
                      <div style={{ fontSize: 9.5, fontWeight: 800, color: 'var(--text-dim)', letterSpacing: 0.5 }}>
                        {aiSummaryKeptAt
                          ? `ON RECORD · PRODUCED ${new Date(aiSummaryKeptAt).toLocaleString()}`
                          : 'JUST GENERATED · NOW ON RECORD'}
                      </div>
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
      <span style={{ fontSize: 10, fontWeight: 900, color: 'var(--text-muted)', letterSpacing: 1.5, fontFamily: "var(--font-outfit), sans-serif" }}>{label}</span>
      <span style={{ fontSize: 14, fontWeight: 900, color, textShadow: `0 0 10px ${color}44`, fontFamily: "var(--font-outfit), sans-serif" }}>{value}</span>
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


function AlertCard({ alert, agents, usersMap, dispatcher, onViewDossier, onDispatch, onEscalate, onResolve, onHqOverride }: { 
  alert: Alert; 
  agents: any[];
  usersMap: Record<string, any>;
  /**
   * The signed-in operator's own posting. The responder picker is scoped to
   * it — see assignable-responders.ts — so this card cannot offer an officer
   * outside the dispatcher's command.
   */
  dispatcher: Posting & { id?: string };
  onViewDossier?: (alert: Alert) => void;
  onDispatch: (ids: AlertIds, responderUid: string) => Promise<void> | void;
  onEscalate: (ids: AlertIds, t: string, notes?: string, agency?: string) => Promise<void> | void; 
  onResolve: (ids: AlertIds) => Promise<void> | void; 
  onHqOverride: (ids: AlertIds) => Promise<void> | void;
}) {
  // A clustered card stands for every report in `member_ids`. Acting on the
  // card acts on all of them — never just the first, which used to leave the
  // rest open and invisible.
  const targetIds: string[] = alert.member_ids ?? [alert.id];
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

      // Server-side Gemini (audit H-9). The rule-based fallback below still
      // covers UNCONFIGURED, FAILED, and any transport error, exactly as before.
      try {
        const res = await fetch('/api/ai/analyze', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ alertId: alert.id, kind: 'triage' }),
        });
        const resData = await res.json();
        if (resData.status === 'OK') {
          const cleanJson = String(resData.text ?? '').replace(/```json/g, '').replace(/```/g, '').trim();
          if (cleanJson) {
            parsed = JSON.parse(cleanJson);
          }
        }
      } catch (apiErr) {
        console.warn('AI triage call failed, using rule-based fallback triage:', apiErr);
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

  /**
   * Apply the AI's grading to this incident.
   *
   * The previous version wrote `status: 'DISPATCHED'` and nothing else: no
   * classification was applied, the incident was marked as having a unit sent
   * when none was, and the `catch` never fired because the Supabase client
   * returns `{ error }` rather than throwing — so a refused write still reported
   * "Classifications Applied". See lib/ai-triage-apply.ts for the whole account.
   */
  const applyTriage = async () => {
    const triage = (alert as any).ai_triage as TriageRecommendation | undefined;
    if (!triage) return;
    const change = triageChanges(alert, triage, { id: dispatcher?.id ?? null });
    if (Object.keys(change.patch).length === 0) {
      toast.info('Nothing to apply', 'This incident already carries that grading.');
      return;
    }

    setLoading(true);
    const toastId = toast.loading('Applying grading...', change.note.split('.')[0]);
    // The note appends to ai_summary so the change is on the record. Read fresh
    // rather than from props: another operator may have written to it since this
    // card rendered.
    const { data: fresh } = await supabase
      .from('alerts').select('ai_summary').eq('id', alert.id).maybeSingle();
    const existing = (fresh as { ai_summary?: string } | null)?.ai_summary ?? '';

    const { error } = await supabase
      .from('alerts')
      .update({
        ...change.patch,
        ai_summary: existing ? `${existing}\n${change.note}` : change.note,
        updated_at: new Date().toISOString(),
      })
      .eq('id', alert.id);

    setLoading(false);
    if (error) {
      // CHECKED, at last. The client does not throw, so the old try/catch was
      // decoration and every failure was reported as a success.
      console.error('[APPLY_TRIAGE_ERR]', error);
      toast.update(toastId, 'error', 'Not applied', error.message || 'The grading was not saved.');
      return;
    }
    toast.update(
      toastId, 'success',
      change.direction === 'lowered' ? 'Severity lowered' : 'Severity applied',
      change.note.split('.')[0],
    );
  };

  const { name: reporterName, contact: reporterContact, type: reporterType } = resolveReporterDetails(alert, usersMap);

  const handleEscalate = async () => {
    setLoading(true);
    try {
      await onEscalate(targetIds, alert.assigned_to || 'POLLING_UNIT');
    } catch (e: any) {
      // Error toast is already shown by the parent callback
    } finally {
      setLoading(false);
    }
  };

  const handleResolve = async () => {
    setLoading(true);
    try {
      await onResolve(targetIds);
    } catch (e: any) {
      // Error toast is already shown by the parent callback
    } finally {
      setLoading(false);
    }
  };

  const handleDispatch = async (responderUid: string) => {
    setLoading(true);
    try {
      await onDispatch(targetIds, responderUid);
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

      {/* A report that arrived from a keypad. Renders nothing for anything else.
          An unconfirmed one is held out of the escalation ladder, so this panel
          is where a named officer stands behind it — see
          components/UssdProvenancePanel.tsx and migration 20261011000000. */}
      <UssdProvenancePanel alert={alert as never} />

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
          <span style={{ fontSize: 10, fontWeight: 900, color: '#FF9800', letterSpacing: 0.8, display: 'flex', alignItems: 'center', gap: 6 }}>
            📡 SMS FALLBACK REPORT (OFFLINE CITIZEN)
          </span>
          <span style={{ fontSize: 9, fontWeight: 700, color: '#fde68a', background: 'rgba(0,0,0,0.3)', padding: '2px 8px', borderRadius: 4 }}>
            TERMII CPaaS SMS GATEWAY
          </span>
        </div>
      )}

      {alert.witness_count && alert.witness_count > 1 && (
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
          <span style={{ fontSize: 10, fontWeight: 900, color: 'var(--accent)', letterSpacing: 0.8, display: 'flex', alignItems: 'center', gap: 6 }}>
            👥 HIGH-SCALE CLUSTER: {alert.witness_count.toLocaleString()} WITNESS REPORTS AGGREGATED
          </span>
          <span style={{ fontSize: 9, fontWeight: 800, color: '#c7d2fe', background: 'rgba(0,0,0,0.3)', padding: '2px 8px', borderRadius: 4 }}>
            AUTO-CLUSTERED
          </span>
        </div>
      )}

      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 16 }}>
        <div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 4 }}>
            <span style={{ fontSize: 9, fontWeight: 900, color: 'var(--text-muted)', letterSpacing: 2, fontFamily: "var(--font-outfit), sans-serif" }}>INCIDENT REPORT</span>
            {['DISPATCHED', 'ACKNOWLEDGED', 'ON_ROUTE', 'ON_SITE'].includes(a.status) && (
              <span style={{ fontSize: 8, fontWeight: 900, background: 'var(--success)', color: 'white', padding: '2px 6px', borderRadius: 4, boxShadow: 'var(--success-glow)' }}>UNIT {a.status}</span>
            )}
            <span style={{ fontSize: 9, fontWeight: 800, color: 'var(--primary)', marginLeft: 6 }}>
              {alert.created_at ? new Date(alert.created_at).toLocaleString('en-GB', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' }) : 'JUST NOW'}
            </span>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <h3 style={{ fontSize: 16, fontWeight: 900, color: isDuress ? 'var(--duress)' : 'var(--text-primary)', fontFamily: "var(--font-outfit), sans-serif", margin: 0 }}>{isDuress ? 'DURESS ALERT' : alert.type}</h3>
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
          <span style={{ fontSize: 10, fontWeight: 900, color: 'var(--primary)', fontFamily: "var(--font-inter), sans-serif" }}>{formatOfficerBadge(alert.assigned_to, usersMap)}</span>
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
          <div style={{ fontSize: 9, fontWeight: 900, color: 'var(--text-muted)', letterSpacing: 1.5, marginBottom: 8, fontFamily: "var(--font-outfit), sans-serif" }}>
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
                    /* eslint-disable-next-line @next/next/no-img-element -- see the note on the incident media image above. An alert can carry six of these thumbnails and the board shows many alerts, so `loading="lazy"` matters here more than anywhere: without it every thumbnail on screen is fetched eagerly over what may be a constrained network. */
                    <img
                      src={url}
                      alt={`Evidence ${idx + 1}`}
                      loading="lazy"
                      decoding="async"
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
            <span style={{ fontSize: 9, fontWeight: 900, color: 'var(--primary)', letterSpacing: 1.5, fontFamily: "var(--font-outfit), sans-serif" }}>AI TRIAGE ASSESSMENT</span>
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
          // Was `alert.type === triage.recommended_type && ...`, comparing
          // 'Kidnap - Immediate Abduction' to 'CRIME'. Never equal, so the
          // button was offered on every graded incident including immediately
          // after being pressed. alreadyApplied() compares severity to severity.
          const isMatch = alreadyApplied(alert, triage);
          const pendingChange = triageChanges(alert, triage, { id: dispatcher?.id ?? null });
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
                      &ldquo;{triage.translated_description}&rdquo;
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
                    {/* Raising and lowering a grading are different acts, and
                        lowering CRITICAL on an AI's word is the one that
                        deserves a second look. The control says which. */}
                    {applyButtonLabel(pendingChange)}
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
        fontFamily: "var(--font-inter), sans-serif" 
      }}>
        <div style={{ borderRight: '1px solid var(--border)', paddingRight: 12 }}>
          <span style={{ fontSize: 9, fontWeight: 900, color: 'var(--primary)', letterSpacing: 1.5, display: 'block', marginBottom: 6, fontFamily: "var(--font-outfit), sans-serif" }}>TACTICAL LOCATION</span>
          <div style={{ fontSize: 11, fontWeight: 850, color: 'var(--text-primary)', textTransform: 'uppercase' }}>
            {a.geo_lga ? `${a.geo_lga} LGA` : 'STATEWIDE HQ'}
          </div>
          <div style={{ fontSize: 10, color: 'var(--text-muted)', marginTop: 4, fontWeight: 600 }}>
            {a.geo_ward ? `Ward: ${a.geo_ward}` : 'State Scope'}
          </div>
          <div style={{ 
            fontSize: 9, 
            color: 'var(--accent)', 
            marginTop: 6, 
            fontWeight: 800, 
            background: 'rgba(99, 102, 241, 0.12)', 
            border: '1px solid rgba(99, 102, 241, 0.25)',
            padding: '2px 6px', 
            borderRadius: 6,
            display: 'inline-block'
          }}>
            PU: {placeField(a.geo_pu, 'pu')}
          </div>
          {a.lat && a.lng && (
            <div style={{ fontSize: 8, color: 'var(--text-dim)', marginTop: 6, letterSpacing: 0.5, fontFamily: 'monospace' }}>
              {a.lat.toFixed(5)}°N, {a.lng.toFixed(5)}°E
            </div>
          )}
        </div>
        <div style={{ paddingLeft: 4 }}>
          <span style={{ fontSize: 9, fontWeight: 900, color: 'var(--primary)', letterSpacing: 1.5, display: 'block', marginBottom: 6, fontFamily: "var(--font-outfit), sans-serif" }}>REPORTER MAIN PROFILE</span>
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
          <p style={{ fontSize: 9, fontWeight: 900, color: 'var(--primary)', letterSpacing: 1.5, marginBottom: 12, textTransform: 'uppercase', fontFamily: "var(--font-outfit), sans-serif" }}>Command Audit Timeline</p>
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
              // This kept every profile with a role that was not CITIZEN —
              // statewide. A ward commander in Jos North was offered, and
              // could dispatch, an officer posted in Mangu: the officer got a
              // push for an incident their own commander knew nothing about,
              // and that commander never learned they had been sent.
              //
              // Scoped to the dispatcher's command, mirroring
              // alert_in_my_area() in the database one axis over — that
              // decides which incidents a posting reaches, this decides which
              // officers it reaches.
              const profileResponders = assignableResponders(
                Object.values(usersMap || {}) as any[],
                dispatcher,
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
                // "NO REGISTERED RESPONDERS FOUND" reads as "the system is
                // broken" during an emergency, and the causes need different
                // actions: nobody is posted to this command, or this account
                // has no posting and so commands nobody.
                return (
                  <p style={{ fontSize: 10, color: 'var(--text-dim)', textAlign: 'center', padding: 10 }}>
                    {emptyRosterReason(dispatcher).toUpperCase()}
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
                await onDispatch(targetIds, selectedResponders as any);
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
                {/*
                  BUILT FROM THE SHARED LIST, NOT WRITTEN OUT HERE.

                  These were seven hand-written options taken from
                  `STATE_SECURITY_AGENCIES`, which badges Operation Rainbow's
                  own staff. Four of them — NPF, MILITARY, RAINBOW, VGN — are
                  not agency codes: the value chosen here is written to
                  `alerts.escalated_to_agency`, and the liaison's portal, the
                  liaison's role and the liaison's phone number are all keyed
                  on POLICE / ARMY / DSS / NSCDC / FRSC / OPSH. So escalating
                  to the Police stored 'NPF', the Police portal asked for
                  'POLICE' and never showed it, /api/notify-agency answered
                  400 Unknown agency, and the operator was told it was sent.
                  FRSC and OPSH, the two this deployment has contacts for,
                  were not on the menu at all.
                */}
                <option value={AGENCY_TARGET_ALL}>🌐 ALL JOINT COMMANDS (Broad Inter-Agency Escalation)</option>
                {AGENCY_LIST.map(a => (
                  <option key={a.code} value={a.code}>{a.icon} {a.label.toUpperCase()}</option>
                ))}
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
                <option value="QUA'AN PAN">QUA&apos;AN PAN LGA</option>
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
                await onEscalate(targetIds, targetLga, escalateNotes, targetAgency);
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
