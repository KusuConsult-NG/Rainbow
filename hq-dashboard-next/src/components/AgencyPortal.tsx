'use client';
import React, { useState, useEffect, useCallback } from 'react';

import { supabase } from '@/lib/supabase';
import LiveFeedViewer from '@/components/LiveFeedViewer';

import {
  Shield, Users, FileText, AlertTriangle, CheckCircle,
  Clock, Send, Plus, RefreshCw, Eye, MapPin, Radio,
  UserCheck, UserX, Loader2, ChevronDown, ChevronRight
} from 'lucide-react';

// ─── Types ──────────────────────────────────────────────────────────────

interface AgencyAlert {
  id: string;
  type: string;
  description: string;
  status: string;
  severity: string;
  geo_lga: string;
  geo_ward: string;
  geo_pu: string;
  latitude?: number;
  longitude?: number;
  media_urls?: string[];
  escalated_to_agency: string;
  escalation_log?: any[];
  created_at: string;
  updated_at: string;
}

interface AgencyPersonnel {
  id: string;
  name: string;
  rank: string;
  badge_number: string;
  phone: string;
  status: 'AVAILABLE' | 'DEPLOYED' | 'UNAVAILABLE' | 'OFF_DUTY';
  agency: string;
}

interface AgencyDeployment {
  id: string;
  alert_id: string;
  agency: string;
  personnel_count: number;
  deployment_note: string;
  status: string;
  deployed_at: string;
}

interface AgencyActionReport {
  id: string;
  alert_id: string;
  agency: string;
  report_type: string;
  narrative: string;
  outcome: string;
  personnel_count: number;
  casualties: number;
  submitted_at: string;
  submitted_by_name: string;
  read_by_hq: boolean;
  hq_acknowledged_by?: string;
  hq_acknowledged_at?: string;
}

const AGENCIES = [
  { code: 'POLICE',   label: 'Nigeria Police Force',        color: '#3b82f6', icon: '🚔' },
  { code: 'ARMY',     label: 'Nigerian Army',               color: '#22c55e', icon: '🪖' },
  { code: 'DSS',      label: 'Dept. of State Services',     color: '#8b5cf6', icon: '🕵️' },
  { code: 'NSCDC',    label: 'NSCDC',                       color: '#f59e0b', icon: '🛡️' },
  { code: 'FRSC',     label: 'Federal Road Safety Corps',   color: '#ef4444', icon: '🚨' },
  { code: 'AMOTEKUN', label: 'Operation Amotekun',          color: '#14b8a6', icon: '🦁' },
];

const STATUS_COLORS: Record<string, string> = {
  AVAILABLE:   '#22c55e',
  DEPLOYED:    '#f59e0b',
  UNAVAILABLE: '#ef4444',
  OFF_DUTY:    '#6b7280',
  EN_ROUTE:    '#3b82f6',
  ON_SITE:     '#22c55e',
  WITHDRAWN:   '#6b7280',
  RESOLVED:    '#22c55e',
};

const OUTCOME_COLORS: Record<string, string> = {
  CONTAINED:    '#22c55e',
  RESOLVED:     '#22c55e',
  ONGOING:      '#f59e0b',
  REQUIRES_HQ:  '#ef4444',
  INCONCLUSIVE: '#6b7280',
};

// ─── Props ───────────────────────────────────────────────────────────────

interface AgencyPortalProps {
  userRole: string;      // e.g. 'POLICE_LIAISON', 'HQ_COMMAND'
  userAgency?: string;   // e.g. 'POLICE' (derived from role for liaisons)
  isHq: boolean;         // true = HQ operator sees all agencies
  userEmail?: string;
  userId?: string;
}

/**
 * One consistent snapshot of an agency's data, tagged with whose it is.
 *
 * The tag is what makes `loading` derivable and what makes a late response
 * from a previously-selected agency harmless.
 */
interface AgencyData {
  agency: string;
  incidents: AgencyAlert[];
  personnel: AgencyPersonnel[];
  reports: AgencyActionReport[];
  deployments: AgencyDeployment[];
}

// Shared empties. A fresh `[]` on every render would hand the child
// components a new prop identity each time and defeat their memoisation.
// Typed mutable because that is what the children's props expect; nothing
// writes to them.
const EMPTY_INCIDENTS: AgencyAlert[] = [];
const EMPTY_PERSONNEL: AgencyPersonnel[] = [];
const EMPTY_REPORTS: AgencyActionReport[] = [];
const EMPTY_DEPLOYMENTS: AgencyDeployment[] = [];

/**
 * Reads one agency's whole picture. No state, no React — just the four
 * queries, returned as a single tagged snapshot.
 *
 * On failure it returns an EMPTY snapshot rather than throwing, so the portal
 * clears its spinner and says "no incidents" instead of spinning forever. The
 * snapshot is still tagged, so a later successful read replaces it.
 */
async function loadAgencyData(agency: string): Promise<AgencyData> {
  try {
    const { data: incidentData } = await supabase
      .from('alerts')
      .select('id, type, description, status, severity, geo_lga, geo_ward, geo_pu, latitude, longitude, media_urls, escalated_to_agency, escalation_log, created_at, updated_at')
      .eq('escalated_to_agency', agency)
      .neq('status', 'RESOLVED')
      .order('created_at', { ascending: false })
      .limit(50);

    const { data: personnelData } = await supabase
      .from('agency_personnel')
      .select('*')
      .eq('agency', agency)
      .order('name');

    const { data: reportData } = await supabase
      .from('agency_action_reports')
      .select('*')
      .eq('agency', agency)
      .order('submitted_at', { ascending: false })
      .limit(30);

    const { data: deployData } = await supabase
      .from('agency_deployments')
      .select('*')
      .eq('agency', agency)
      .in('status', ['EN_ROUTE', 'ON_SITE'])
      .order('deployed_at', { ascending: false });

    return {
      agency,
      incidents: (incidentData as AgencyAlert[]) || [],
      personnel: (personnelData as AgencyPersonnel[]) || [],
      reports: (reportData as AgencyActionReport[]) || [],
      deployments: (deployData as AgencyDeployment[]) || [],
    };
  } catch (e) {
    console.error('[AGENCY_PORTAL_FETCH]', e);
    return {
      agency,
      incidents: EMPTY_INCIDENTS,
      personnel: EMPTY_PERSONNEL,
      reports: EMPTY_REPORTS,
      deployments: EMPTY_DEPLOYMENTS,
    };
  }
}

// ─── Main Component ──────────────────────────────────────────────────────

export default function AgencyPortal({ userRole, userAgency, isHq, userEmail, userId }: AgencyPortalProps) {
  // If HQ, they can select which agency to view. Liaisons are locked to their agency.
  const [selectedAgency, setSelectedAgency] = useState<string>(
    isHq ? (AGENCIES[0].code) : (userAgency || 'POLICE')
  );
  const [activeSection, setActiveSection] = useState<'incidents' | 'personnel' | 'reports' | 'add_personnel'>('incidents');

  // Data — ONE piece of state, tagged with the agency it belongs to.
  //
  // This used to be five separate states plus a `loading` flag that the fetch
  // set to true as its first statement. Because the fetch was called straight
  // from an effect, that was a `set-state-in-effect`; and because the lists
  // were untagged, a slow response for the previous agency could land after a
  // switch and render POLICE incidents under the ARMY heading.
  //
  // Tagging the payload fixes both. `loading` is now DERIVED — "what I have is
  // not for the agency being shown" — so nothing has to set it, and stale
  // responses are ignored rather than displayed.
  const [data, setData] = useState<AgencyData | null>(null);

  const loading = data === null || data.agency !== selectedAgency;
  const incidents = loading ? EMPTY_INCIDENTS : data.incidents;
  const personnel = loading ? EMPTY_PERSONNEL : data.personnel;
  const reports = loading ? EMPTY_REPORTS : data.reports;
  const deployments = loading ? EMPTY_DEPLOYMENTS : data.deployments;
  const unreadReports = reports.filter(r => !r.read_by_hq).length;

  // Selected incident for action
  const [selectedIncident, setSelectedIncident] = useState<AgencyAlert | null>(null);
  const [showDeployModal, setShowDeployModal] = useState(false);
  const [showReportModal, setShowReportModal] = useState(false);

  const agencyInfo = AGENCIES.find(a => a.code === selectedAgency) || AGENCIES[0];

  // ── Data fetching ─────────────────────────────────────────────────────
  //
  // `fetchAll` is a thin wrapper so the refresh button, the realtime handlers
  // and the modals can all re-read. The effect below does NOT call it: the
  // lint rule cannot see across the useCallback boundary to tell that every
  // setState happens after an await, and a rule that has to be argued with is
  // a rule that gets disabled. Inlining the load in the effect is also plainly
  // better — it can cancel.
  const fetchAll = useCallback(async () => {
    setData(await loadAgencyData(selectedAgency));
  }, [selectedAgency]);

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      const snapshot = await loadAgencyData(selectedAgency);
      // Discard a response for an agency the operator has already left, so
      // POLICE incidents can never appear under the ARMY heading.
      if (!cancelled) setData(snapshot);
    })();
    return () => {
      cancelled = true;
    };
  }, [selectedAgency]);

  // Realtime subscription for incidents assigned to this agency
  useEffect(() => {
    const channel = supabase
      .channel(`agency-portal-${selectedAgency}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'alerts' }, () => fetchAll())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'agency_action_reports' }, () => fetchAll())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'agency_deployments' }, () => fetchAll())
      .subscribe();
    return () => { supabase.removeChannel(channel); };
  }, [selectedAgency, fetchAll]);

  // ── HQ acknowledge report ─────────────────────────────────────────────
  const acknowledgeReport = async (reportId: string) => {
    await supabase
      .from('agency_action_reports')
      .update({ read_by_hq: true, hq_acknowledged_at: new Date().toISOString(), hq_acknowledged_by: userEmail })
      .eq('id', reportId);
    fetchAll();
  };

  // ── Render ────────────────────────────────────────────────────────────
  return (
    <div style={{ height: '100%', display: 'flex', flexDirection: 'column', gap: 0 }}>

      {/* Agency selector header */}
      <div style={{
        padding: '16px 24px',
        background: 'var(--surface)',
        borderBottom: '1px solid var(--border)',
        display: 'flex',
        alignItems: 'center',
        gap: 16,
        flexWrap: 'wrap',
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <div style={{
            width: 36, height: 36, borderRadius: 10,
            background: agencyInfo.color + '22',
            border: `2px solid ${agencyInfo.color}`,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            fontSize: 18,
          }}>
            {agencyInfo.icon}
          </div>
          <div>
            <div style={{ fontSize: 13, fontWeight: 900, color: 'var(--text-primary)', fontFamily: "'Outfit', sans-serif", letterSpacing: 1 }}>
              {agencyInfo.label.toUpperCase()}
            </div>
            <div style={{ fontSize: 10, color: 'var(--text-muted)' }}>INTER-AGENCY COMMAND PORTAL</div>
          </div>
        </div>

        {/* Agency switcher — HQ only */}
        {isHq && (
          <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', marginLeft: 'auto' }}>
            {AGENCIES.map(a => (
              <button
                key={a.code}
                onClick={() => setSelectedAgency(a.code)}
                style={{
                  padding: '5px 12px',
                  borderRadius: 20,
                  border: `1px solid ${selectedAgency === a.code ? a.color : 'var(--border)'}`,
                  background: selectedAgency === a.code ? a.color + '22' : 'transparent',
                  color: selectedAgency === a.code ? a.color : 'var(--text-muted)',
                  fontSize: 10, fontWeight: 700, cursor: 'pointer', fontFamily: "'Outfit', sans-serif",
                }}
              >
                {a.icon} {a.code}
              </button>
            ))}
          </div>
        )}

        <button
          onClick={fetchAll}
          style={{ marginLeft: isHq ? 8 : 'auto', background: 'none', border: '1px solid var(--border)', borderRadius: 8, padding: '6px 10px', cursor: 'pointer', color: 'var(--text-muted)' }}
          title="Refresh"
        >
          <RefreshCw size={14} />
        </button>
      </div>

      {/* Stats strip */}
      <div style={{
        display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)',
        gap: 1, background: 'var(--border)',
      }}>
        {[
          { label: 'ACTIVE INCIDENTS', value: incidents.length, color: '#ef4444' },
          { label: 'PERSONNEL', value: personnel.filter(p => p.status === 'AVAILABLE').length + '/' + personnel.length, color: '#22c55e' },
          { label: 'DEPLOYED', value: deployments.length, color: '#f59e0b' },
          { label: 'UNREAD REPORTS', value: isHq ? unreadReports : reports.length, color: '#8b5cf6' },
        ].map(stat => (
          <div key={stat.label} style={{ padding: '12px 16px', background: 'var(--surface)', textAlign: 'center' }}>
            <div style={{ fontSize: 20, fontWeight: 900, color: stat.color, fontFamily: "'Outfit', sans-serif" }}>{stat.value}</div>
            <div style={{ fontSize: 9, color: 'var(--text-muted)', letterSpacing: 1, fontWeight: 700 }}>{stat.label}</div>
          </div>
        ))}
      </div>

      {/* Section tabs */}
      <div style={{ display: 'flex', borderBottom: '1px solid var(--border)', background: 'var(--surface)' }}>
        {([
          { key: 'incidents',     label: 'Situation Feed',   icon: <AlertTriangle size={14} />, badge: incidents.length as number | undefined },
          { key: 'personnel',     label: 'Personnel',        icon: <Users size={14} />,          badge: undefined as number | undefined },
          { key: 'reports',       label: 'Action Reports',   icon: <FileText size={14} />,       badge: (isHq ? unreadReports : undefined) as number | undefined },
          { key: 'add_personnel', label: 'Add Officer',      icon: <Plus size={14} />,           badge: undefined as number | undefined },
        ] as Array<{ key: string; label: string; icon: React.ReactNode; badge?: number }>).map(tab => (
          <button
            key={tab.key}
            onClick={() => setActiveSection(tab.key as 'incidents' | 'personnel' | 'reports' | 'add_personnel')}
            style={{
              padding: '10px 16px', background: 'none',
              border: 'none', borderBottom: activeSection === tab.key ? `2px solid ${agencyInfo.color}` : '2px solid transparent',
              color: activeSection === tab.key ? agencyInfo.color : 'var(--text-muted)',
              cursor: 'pointer', fontSize: 11, fontWeight: 700, display: 'flex', alignItems: 'center', gap: 6,
              fontFamily: "'Outfit', sans-serif", letterSpacing: 0.5, position: 'relative',
            }}
          >
            {tab.icon} {tab.label}
            {tab.badge !== undefined && tab.badge > 0 && (
              <span style={{
                background: '#ef4444', color: 'white', borderRadius: 10,
                fontSize: 9, fontWeight: 900, padding: '1px 5px', minWidth: 16,
              }}>{tab.badge}</span>
            )}
          </button>
        ))}
      </div>

      {/* Content */}
      <div style={{ flex: 1, overflowY: 'auto', padding: 20 }}>
        {loading ? (
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: 200, gap: 10, color: 'var(--text-muted)' }}>
            <Loader2 size={20} style={{ animation: 'spin 1s linear infinite' }} />
            Loading agency data...
          </div>
        ) : (
          <>
            {/* ── Situation Feed ── */}
            {activeSection === 'incidents' && (
              <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
                {incidents.length === 0 ? (
                  <div style={{ textAlign: 'center', padding: 48, color: 'var(--text-muted)' }}>
                    <Shield size={40} style={{ margin: '0 auto 12px', opacity: 0.3 }} />
                    <div style={{ fontSize: 13, fontWeight: 600 }}>No active incidents escalated to {agencyInfo.label}</div>
                    <div style={{ fontSize: 11, marginTop: 4 }}>Incidents escalated from HQ will appear here in real-time</div>
                  </div>
                ) : incidents.map(incident => (
                  <IncidentCard
                    key={incident.id}
                    incident={incident}
                    agencyColor={agencyInfo.color}
                    onDeploy={() => { setSelectedIncident(incident); setShowDeployModal(true); }}
                    onReport={() => { setSelectedIncident(incident); setShowReportModal(true); }}
                    deployments={deployments.filter(d => d.alert_id === incident.id)}
                    isHq={isHq}
                  />
                ))}
              </div>
            )}

            {/* ── Personnel ── */}
            {activeSection === 'personnel' && (
              <PersonnelPanel
                personnel={personnel}
                agencyColor={agencyInfo.color}
                agency={selectedAgency}
                onRefresh={fetchAll}
              />
            )}

            {/* ── Action Reports ── */}
            {activeSection === 'reports' && (
              <ReportsPanel
                reports={reports}
                agencyColor={agencyInfo.color}
                isHq={isHq}
                onAcknowledge={acknowledgeReport}
              />
            )}

            {/* ── Add Personnel ── */}
            {activeSection === 'add_personnel' && (
              <AddPersonnelForm
                agency={selectedAgency}
                agencyColor={agencyInfo.color}
                userId={userId}
                onSuccess={() => { setActiveSection('personnel'); fetchAll(); }}
              />
            )}
          </>
        )}
      </div>

      {/* Deploy Modal */}
      {showDeployModal && selectedIncident && (
        <DeployModal
          incident={selectedIncident}
          personnel={personnel.filter(p => p.status === 'AVAILABLE')}
          agency={selectedAgency}
          userId={userId}
          userEmail={userEmail}
          agencyColor={agencyInfo.color}
          onClose={() => setShowDeployModal(false)}
          onSuccess={() => { setShowDeployModal(false); fetchAll(); }}
        />
      )}

      {/* Report Modal */}
      {showReportModal && selectedIncident && (
        <ReportModal
          incident={selectedIncident}
          agency={selectedAgency}
          userId={userId}
          userEmail={userEmail}
          agencyColor={agencyInfo.color}
          onClose={() => setShowReportModal(false)}
          onSuccess={() => { setShowReportModal(false); fetchAll(); }}
        />
      )}
    </div>
  );
}

// ─── Incident Card ─────────────────────────────────────────────────────────

function IncidentCard({ incident, agencyColor, onDeploy, onReport, deployments, isHq }: {
  incident: AgencyAlert;
  agencyColor: string;
  onDeploy: () => void;
  onReport: () => void;
  deployments: AgencyDeployment[];
  isHq: boolean;
}) {
  const [expanded, setExpanded] = useState(false);
  const sevColor = incident.severity === 'CRITICAL' ? '#ef4444' : incident.severity === 'HIGH' ? '#f59e0b' : '#22c55e';
  const activeDeployment = deployments.find(d => d.status === 'EN_ROUTE' || d.status === 'ON_SITE');

  return (
    <div style={{
      background: 'var(--surface)',
      border: `1px solid ${activeDeployment ? agencyColor + '66' : 'var(--border)'}`,
      borderRadius: 12,
      overflow: 'hidden',
    }}>
      <div
        style={{ padding: '14px 16px', cursor: 'pointer', display: 'flex', alignItems: 'flex-start', gap: 12 }}
        onClick={() => setExpanded(!expanded)}
      >
        {/* Severity dot */}
        <div style={{ width: 10, height: 10, borderRadius: '50%', background: sevColor, marginTop: 4, flexShrink: 0 }} />

        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 8 }}>
            <div>
              <span style={{ fontSize: 13, fontWeight: 700, color: 'var(--text-primary)', fontFamily: "'Outfit', sans-serif" }}>
                {incident.type}
              </span>
              {activeDeployment && (
                <span style={{
                  marginLeft: 8, fontSize: 9, fontWeight: 700, padding: '2px 6px',
                  background: agencyColor + '22', color: agencyColor, borderRadius: 4,
                }}>UNIT DEPLOYED</span>
              )}
            </div>
            <span style={{ fontSize: 9, fontWeight: 900, padding: '3px 8px', borderRadius: 4, background: sevColor + '22', color: sevColor }}>
              {incident.severity}
            </span>
          </div>
          <div style={{ fontSize: 12, color: 'var(--text-muted)', marginTop: 4 }}>
            <MapPin size={10} style={{ display: 'inline', marginRight: 4 }} />
            {[incident.geo_lga, incident.geo_ward, incident.geo_pu].filter(Boolean).join(' › ')}
          </div>
          <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 2 }}>
            {incident.description?.slice(0, 100)}{incident.description?.length > 100 ? '...' : ''}
          </div>
        </div>
        {expanded ? <ChevronDown size={14} style={{ color: 'var(--text-muted)', flexShrink: 0 }} /> : <ChevronRight size={14} style={{ color: 'var(--text-muted)', flexShrink: 0 }} />}
      </div>

      {expanded && (
        <div style={{ padding: '0 16px 16px', borderTop: '1px solid var(--border)' }}>
          <div style={{ paddingTop: 12, fontSize: 12, color: 'var(--text-secondary)', lineHeight: 1.7 }}>
            {incident.description}
          </div>

          {/* WebRTC Live Stream Receiver */}
          <LiveFeedViewer alertId={incident.id} />

          {/* Media */}
          {incident.media_urls && incident.media_urls.length > 0 && (
            <div style={{ marginTop: 12 }}>
              <div style={{ fontSize: 9, fontWeight: 900, color: 'var(--text-muted)', letterSpacing: 1, marginBottom: 6 }}>EVIDENCE ({incident.media_urls.length})</div>
              <div style={{ display: 'flex', gap: 6 }}>
                {incident.media_urls.slice(0, 4).map((url, i) => (
                  <div
                    key={i}
                    onClick={() => window.open(url, '_blank')}
                    style={{
                      width: 64, height: 64, borderRadius: 8, overflow: 'hidden',
                      background: 'var(--input-bg)', border: '1px solid var(--border)',
                      cursor: 'pointer', flexShrink: 0,
                    }}
                  >
                    <img src={url} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }}
                      onError={e => { (e.target as HTMLImageElement).style.display = 'none'; }}
                    />
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Escalation history */}
          {incident.escalation_log && incident.escalation_log.length > 0 && (
            <div style={{ marginTop: 12, padding: 10, background: 'var(--input-bg)', borderRadius: 8 }}>
              <div style={{ fontSize: 9, fontWeight: 900, color: 'var(--text-muted)', letterSpacing: 1, marginBottom: 6 }}>ESCALATION LOG</div>
              {incident.escalation_log.map((entry: any, i: number) => (
                <div key={i} style={{ fontSize: 11, color: 'var(--text-muted)', marginBottom: 4 }}>
                  <span style={{ color: agencyColor, fontWeight: 700 }}>{entry.from_tier} → {entry.to_tier}</span>
                  {' '}{entry.reason} · {entry.by_email} · {new Date(entry.at).toLocaleString()}
                </div>
              ))}
            </div>
          )}

          {/* Actions — agency liaisons only (not HQ read-only view) */}
          {!isHq && (
            <div style={{ display: 'flex', gap: 8, marginTop: 14 }}>
              <button
                onClick={onDeploy}
                style={{
                  flex: 1, padding: '9px 16px', borderRadius: 8, border: `1px solid ${agencyColor}`,
                  background: agencyColor + '22', color: agencyColor, fontWeight: 700, fontSize: 12,
                  cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6,
                  fontFamily: "'Outfit', sans-serif",
                }}
              >
                <UserCheck size={14} /> DEPLOY PERSONNEL
              </button>
              <button
                onClick={onReport}
                style={{
                  flex: 1, padding: '9px 16px', borderRadius: 8, border: '1px solid var(--border)',
                  background: 'var(--input-bg)', color: 'var(--text-primary)', fontWeight: 700, fontSize: 12,
                  cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6,
                  fontFamily: "'Outfit', sans-serif",
                }}
              >
                <Send size={14} /> FILE REPORT TO HQ
              </button>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

// ─── Personnel Panel ──────────────────────────────────────────────────────

function PersonnelPanel({ personnel, agencyColor, agency, onRefresh }: {
  personnel: AgencyPersonnel[];
  agencyColor: string;
  agency: string;
  onRefresh: () => void;
}) {
  const updateStatus = async (id: string, status: string) => {
    await supabase.from('agency_personnel').update({ status, updated_at: new Date().toISOString() }).eq('id', id);
    onRefresh();
  };

  if (personnel.length === 0) {
    return (
      <div style={{ textAlign: 'center', padding: 48, color: 'var(--text-muted)' }}>
        <Users size={40} style={{ margin: '0 auto 12px', opacity: 0.3 }} />
        <div style={{ fontSize: 13, fontWeight: 600 }}>No personnel registered yet</div>
        <div style={{ fontSize: 11, marginTop: 4 }}>Switch to &ldquo;Add Officer&rdquo; to register your team</div>
      </div>
    );
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(280px, 1fr))', gap: 10 }}>
        {personnel.map(p => (
          <div key={p.id} style={{
            padding: 14, background: 'var(--surface)', borderRadius: 10,
            border: `1px solid ${p.status === 'DEPLOYED' ? agencyColor + '66' : 'var(--border)'}`,
          }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
              <div>
                <div style={{ fontWeight: 700, fontSize: 13, color: 'var(--text-primary)' }}>{p.name}</div>
                <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>{p.rank} {p.badge_number ? `· ${p.badge_number}` : ''}</div>
                {p.phone && <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>📞 {p.phone}</div>}
              </div>
              <span style={{
                fontSize: 9, fontWeight: 900, padding: '3px 8px', borderRadius: 4,
                background: (STATUS_COLORS[p.status] || '#6b7280') + '22',
                color: STATUS_COLORS[p.status] || '#6b7280',
              }}>{p.status}</span>
            </div>
            <div style={{ display: 'flex', gap: 4, marginTop: 10 }}>
              {(['AVAILABLE', 'DEPLOYED', 'OFF_DUTY'] as const).map(s => (
                <button
                  key={s}
                  onClick={() => updateStatus(p.id, s)}
                  disabled={p.status === s}
                  style={{
                    flex: 1, padding: '4px 6px', borderRadius: 6, fontSize: 9, fontWeight: 700,
                    border: `1px solid ${p.status === s ? STATUS_COLORS[s] : 'var(--border)'}`,
                    background: p.status === s ? STATUS_COLORS[s] + '22' : 'transparent',
                    color: p.status === s ? STATUS_COLORS[s] : 'var(--text-muted)',
                    cursor: p.status === s ? 'default' : 'pointer',
                  }}
                >{s.replace('_', ' ')}</button>
              ))}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

// ─── Reports Panel ────────────────────────────────────────────────────────

function ReportsPanel({ reports, agencyColor, isHq, onAcknowledge }: {
  reports: AgencyActionReport[];
  agencyColor: string;
  isHq: boolean;
  onAcknowledge: (id: string) => void;
}) {
  if (reports.length === 0) {
    return (
      <div style={{ textAlign: 'center', padding: 48, color: 'var(--text-muted)' }}>
        <FileText size={40} style={{ margin: '0 auto 12px', opacity: 0.3 }} />
        <div style={{ fontSize: 13, fontWeight: 600 }}>No action reports filed yet</div>
      </div>
    );
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
      {reports.map(report => (
        <div key={report.id} style={{
          padding: 14, background: 'var(--surface)', borderRadius: 10,
          border: `1px solid ${!report.read_by_hq && isHq ? agencyColor + '88' : 'var(--border)'}`,
        }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 8 }}>
            <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
              <span style={{
                fontSize: 9, fontWeight: 900, padding: '3px 8px', borderRadius: 4,
                background: 'var(--input-bg)', color: 'var(--text-muted)', border: '1px solid var(--border)',
              }}>{report.report_type}</span>
              {report.outcome && (
                <span style={{
                  fontSize: 9, fontWeight: 900, padding: '3px 8px', borderRadius: 4,
                  background: (OUTCOME_COLORS[report.outcome] || '#6b7280') + '22',
                  color: OUTCOME_COLORS[report.outcome] || '#6b7280',
                }}>{report.outcome}</span>
              )}
              {!report.read_by_hq && isHq && (
                <span style={{ fontSize: 9, fontWeight: 900, padding: '3px 8px', borderRadius: 4, background: '#ef444422', color: '#ef4444' }}>UNREAD</span>
              )}
            </div>
            <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>
              {new Date(report.submitted_at).toLocaleString()}
            </div>
          </div>

          <div style={{ fontSize: 13, color: 'var(--text-primary)', lineHeight: 1.6, marginBottom: 8 }}>
            {report.narrative}
          </div>

          {(report.personnel_count > 0 || report.casualties > 0) && (
            <div style={{ display: 'flex', gap: 12, fontSize: 11, color: 'var(--text-muted)' }}>
              {report.personnel_count > 0 && <span>👮 {report.personnel_count} personnel</span>}
              {report.casualties > 0 && <span style={{ color: '#ef4444' }}>⚠️ {report.casualties} casualties</span>}
            </div>
          )}

          <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 6 }}>
            Filed by: {report.submitted_by_name || '—'}
            {report.read_by_hq && report.hq_acknowledged_by && (
              <span style={{ marginLeft: 12, color: '#22c55e' }}>
                ✓ Acknowledged by {report.hq_acknowledged_by}
              </span>
            )}
          </div>

          {isHq && !report.read_by_hq && (
            <button
              onClick={() => onAcknowledge(report.id)}
              style={{
                marginTop: 10, padding: '7px 14px', borderRadius: 8,
                border: `1px solid ${agencyColor}`, background: agencyColor + '22',
                color: agencyColor, fontWeight: 700, fontSize: 11, cursor: 'pointer',
                display: 'flex', alignItems: 'center', gap: 6,
              }}
            >
              <CheckCircle size={13} /> ACKNOWLEDGE REPORT
            </button>
          )}
        </div>
      ))}
    </div>
  );
}

// ─── Add Personnel Form ────────────────────────────────────────────────────

function AddPersonnelForm({ agency, agencyColor, userId, onSuccess }: {
  agency: string;
  agencyColor: string;
  userId?: string;
  onSuccess: () => void;
}) {
  const [form, setForm] = useState({ name: '', rank: '', badge_number: '', phone: '' });
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!form.name.trim()) { setError('Officer name is required'); return; }
    setSaving(true);
    setError('');
    try {
      const { error: dbErr } = await supabase.from('agency_personnel').insert({
        agency,
        name: form.name.trim(),
        rank: form.rank.trim(),
        badge_number: form.badge_number.trim(),
        phone: form.phone.trim(),
        status: 'AVAILABLE',
        created_by: userId || null,
      });
      if (dbErr) throw dbErr;
      setForm({ name: '', rank: '', badge_number: '', phone: '' });
      onSuccess();
    } catch (err: any) {
      setError(err?.message || 'Failed to add personnel');
    } finally {
      setSaving(false);
    }
  };

  return (
    <div style={{ maxWidth: 480 }}>
      <h3 style={{ fontSize: 15, fontWeight: 900, color: 'var(--text-primary)', marginBottom: 20, fontFamily: "'Outfit', sans-serif" }}>
        Register New Officer
      </h3>
      {error && (
        <div style={{ padding: 10, background: '#ef444422', border: '1px solid #ef4444', borderRadius: 8, color: '#ef4444', fontSize: 12, marginBottom: 16 }}>
          {error}
        </div>
      )}
      <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
        {[{ key: 'name', label: 'Full Name *', placeholder: 'e.g. Inspector Adamu Musa' },
          { key: 'rank', label: 'Rank / Designation', placeholder: 'e.g. Inspector, Sergeant, Agent' },
          { key: 'badge_number', label: 'Badge / Service Number', placeholder: 'e.g. NP/JOS/001' },
          { key: 'phone', label: 'Phone Number', placeholder: 'e.g. 08012345678' },
        ].map(field => (
          <div key={field.key}>
            <label style={{ fontSize: 11, fontWeight: 700, color: 'var(--text-muted)', display: 'block', marginBottom: 6 }}>
              {field.label}
            </label>
            <input
              type="text"
              placeholder={field.placeholder}
              value={(form as any)[field.key]}
              onChange={e => setForm({ ...form, [field.key]: e.target.value })}
              style={{
                width: '100%', padding: '10px 14px',
                background: 'var(--input-bg)', border: '1px solid var(--border)',
                borderRadius: 8, color: 'var(--text-primary)', fontSize: 13,
                outline: 'none', boxSizing: 'border-box',
              }}
            />
          </div>
        ))}
        <button
          type="submit"
          disabled={saving}
          style={{
            padding: '12px 24px', borderRadius: 8,
            border: `1px solid ${agencyColor}`, background: agencyColor,
            color: 'white', fontWeight: 700, fontSize: 13, cursor: saving ? 'not-allowed' : 'pointer',
            opacity: saving ? 0.7 : 1, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
            fontFamily: "'Outfit', sans-serif",
          }}
        >
          {saving ? <><Loader2 size={14} style={{ animation: 'spin 1s linear infinite' }} /> Saving...</> : <><Plus size={14} /> Register Officer</>}
        </button>
      </form>
    </div>
  );
}

// ─── Deploy Modal ──────────────────────────────────────────────────────────

function DeployModal({ incident, personnel, agency, userId, userEmail, agencyColor, onClose, onSuccess }: {
  incident: AgencyAlert;
  personnel: AgencyPersonnel[];
  agency: string;
  userId?: string;
  userEmail?: string;
  agencyColor: string;
  onClose: () => void;
  onSuccess: () => void;
}) {
  const [selected, setSelected] = useState<string[]>([]);
  const [note, setNote] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState('');

  const toggle = (id: string) =>
    setSelected(prev => prev.includes(id) ? prev.filter(x => x !== id) : [...prev, id]);

  const handleDeploy = async () => {
    setSubmitting(true);
    setError('');
    try {
      const { error: dbErr } = await supabase.from('agency_deployments').insert({
        alert_id: incident.id,
        agency,
        personnel_ids: selected,
        personnel_count: selected.length,
        deployment_note: note.trim(),
        status: 'EN_ROUTE',
        deployed_by: userId || null,
        deployed_at: new Date().toISOString(),
      });
      if (dbErr) throw dbErr;

      // Update deployed officers' status
      if (selected.length > 0) {
        await supabase.from('agency_personnel').update({ status: 'DEPLOYED', updated_at: new Date().toISOString() }).in('id', selected);
      }

      // Append deployment note to alert ai_summary
      const deployNote = `[${agency} DEPLOYMENT] ${selected.length} officer(s) deployed EN ROUTE to incident. ${note ? 'Note: ' + note : ''} (by ${userEmail || agency})`;
      const { data: alertData } = await supabase.from('alerts').select('ai_summary').eq('id', incident.id).single();
      const existing = alertData?.ai_summary || '';
      await supabase.from('alerts').update({
        ai_summary: existing ? `${existing}\n${deployNote}` : deployNote,
        updated_at: new Date().toISOString(),
      }).eq('id', incident.id);

      onSuccess();
    } catch (err: any) {
      setError(err?.message || 'Deployment failed');
      setSubmitting(false);
    }
  };

  return (
    <div style={{
      position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.7)',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      zIndex: 9999, padding: 20,
    }}>
      <div style={{
        background: 'var(--surface)', borderRadius: 16, padding: 24,
        width: '100%', maxWidth: 480, maxHeight: '80vh', overflowY: 'auto',
        border: `1px solid ${agencyColor}`,
      }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 20 }}>
          <h3 style={{ fontSize: 15, fontWeight: 900, color: 'var(--text-primary)', fontFamily: "'Outfit', sans-serif", margin: 0 }}>
            🚔 DEPLOY PERSONNEL
          </h3>
          <button onClick={onClose} style={{ background: 'none', border: 'none', color: 'var(--text-muted)', cursor: 'pointer', fontSize: 18 }}>✕</button>
        </div>

        <div style={{ fontSize: 12, color: 'var(--text-muted)', marginBottom: 16, padding: '8px 12px', background: 'var(--input-bg)', borderRadius: 8 }}>
          Incident: <strong style={{ color: 'var(--text-primary)' }}>{incident.type}</strong>
          <span style={{ marginLeft: 8 }}>· {[incident.geo_lga, incident.geo_ward].filter(Boolean).join(' › ')}</span>
        </div>

        {error && <div style={{ padding: 10, background: '#ef444422', border: '1px solid #ef4444', borderRadius: 8, color: '#ef4444', fontSize: 12, marginBottom: 14 }}>{error}</div>}

        <div style={{ marginBottom: 16 }}>
          <div style={{ fontSize: 11, fontWeight: 700, color: 'var(--text-muted)', marginBottom: 8 }}>SELECT OFFICERS ({selected.length} selected)</div>
          {personnel.length === 0 ? (
            <div style={{ padding: 16, textAlign: 'center', color: 'var(--text-muted)', fontSize: 12 }}>No available officers. Register personnel first.</div>
          ) : (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
              {personnel.map(p => (
                <label key={p.id} style={{
                  display: 'flex', alignItems: 'center', gap: 10, padding: '8px 12px',
                  background: selected.includes(p.id) ? agencyColor + '22' : 'var(--input-bg)',
                  border: `1px solid ${selected.includes(p.id) ? agencyColor : 'var(--border)'}`,
                  borderRadius: 8, cursor: 'pointer',
                }}>
                  <input type="checkbox" checked={selected.includes(p.id)} onChange={() => toggle(p.id)} style={{ accentColor: agencyColor }} />
                  <div>
                    <div style={{ fontSize: 12, fontWeight: 600, color: 'var(--text-primary)' }}>{p.name}</div>
                    <div style={{ fontSize: 10, color: 'var(--text-muted)' }}>{p.rank} {p.badge_number ? `· ${p.badge_number}` : ''}</div>
                  </div>
                </label>
              ))}
            </div>
          )}
        </div>

        <div style={{ marginBottom: 16 }}>
          <div style={{ fontSize: 11, fontWeight: 700, color: 'var(--text-muted)', marginBottom: 6 }}>DEPLOYMENT NOTE (optional)</div>
          <textarea
            value={note}
            onChange={e => setNote(e.target.value)}
            placeholder="Tactical notes, entry points, ETA..."
            rows={3}
            style={{ width: '100%', padding: '10px 14px', background: 'var(--input-bg)', border: '1px solid var(--border)', borderRadius: 8, color: 'var(--text-primary)', fontSize: 12, resize: 'vertical', outline: 'none', boxSizing: 'border-box' }}
          />
        </div>

        <div style={{ display: 'flex', gap: 10 }}>
          <button onClick={onClose} style={{ flex: 1, padding: '10px', borderRadius: 8, border: '1px solid var(--border)', background: 'transparent', color: 'var(--text-muted)', cursor: 'pointer', fontWeight: 700 }}>CANCEL</button>
          <button
            onClick={handleDeploy}
            disabled={submitting || selected.length === 0}
            style={{
              flex: 2, padding: '10px', borderRadius: 8, border: `1px solid ${agencyColor}`,
              background: agencyColor, color: 'white', fontWeight: 700, fontSize: 13,
              cursor: submitting || selected.length === 0 ? 'not-allowed' : 'pointer',
              opacity: submitting || selected.length === 0 ? 0.6 : 1,
              fontFamily: "'Outfit', sans-serif", display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
            }}
          >
            {submitting ? <Loader2 size={14} style={{ animation: 'spin 1s linear infinite' }} /> : <UserCheck size={14} />}
            {submitting ? 'Deploying...' : `DEPLOY ${selected.length > 0 ? selected.length + ' OFFICER' + (selected.length > 1 ? 'S' : '') : ''}`}
          </button>
        </div>
      </div>
    </div>
  );
}

// ─── Report Modal ──────────────────────────────────────────────────────────

function ReportModal({ incident, agency, userId, userEmail, agencyColor, onClose, onSuccess }: {
  incident: AgencyAlert;
  agency: string;
  userId?: string;
  userEmail?: string;
  agencyColor: string;
  onClose: () => void;
  onSuccess: () => void;
}) {
  const [form, setForm] = useState({
    report_type: 'SITREP',
    narrative: '',
    outcome: 'ONGOING',
    personnel_count: 0,
    casualties: 0,
  });
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState('');

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!form.narrative.trim()) { setError('Narrative is required'); return; }
    setSubmitting(true);
    setError('');
    try {
      const { error: dbErr } = await supabase.from('agency_action_reports').insert({
        alert_id: incident.id,
        agency,
        report_type: form.report_type,
        narrative: form.narrative.trim(),
        outcome: form.outcome,
        personnel_count: form.personnel_count,
        casualties: form.casualties,
        submitted_by: userId || null,
        submitted_by_name: userEmail || agency,
        submitted_at: new Date().toISOString(),
        read_by_hq: false,
      });
      if (dbErr) throw dbErr;
      onSuccess();
    } catch (err: any) {
      setError(err?.message || 'Failed to submit report');
      setSubmitting(false);
    }
  };

  return (
    <div style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.7)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 9999, padding: 20 }}>
      <div style={{ background: 'var(--surface)', borderRadius: 16, padding: 24, width: '100%', maxWidth: 520, maxHeight: '85vh', overflowY: 'auto', border: `1px solid ${agencyColor}` }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 20 }}>
          <h3 style={{ fontSize: 15, fontWeight: 900, color: 'var(--text-primary)', fontFamily: "'Outfit', sans-serif", margin: 0 }}>📋 FILE ACTION REPORT TO HQ</h3>
          <button onClick={onClose} style={{ background: 'none', border: 'none', color: 'var(--text-muted)', cursor: 'pointer', fontSize: 18 }}>✕</button>
        </div>

        <div style={{ fontSize: 12, color: 'var(--text-muted)', marginBottom: 16, padding: '8px 12px', background: 'var(--input-bg)', borderRadius: 8 }}>
          Reporting on: <strong style={{ color: 'var(--text-primary)' }}>{incident.type}</strong>
        </div>

        {error && <div style={{ padding: 10, background: '#ef444422', border: '1px solid #ef4444', borderRadius: 8, color: '#ef4444', fontSize: 12, marginBottom: 14 }}>{error}</div>}

        <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
            <div>
              <label style={{ fontSize: 11, fontWeight: 700, color: 'var(--text-muted)', display: 'block', marginBottom: 6 }}>REPORT TYPE</label>
              <select
                value={form.report_type}
                onChange={e => setForm({ ...form, report_type: e.target.value })}
                style={{ width: '100%', padding: '9px 12px', background: 'var(--input-bg)', border: '1px solid var(--border)', borderRadius: 8, color: 'var(--text-primary)', fontSize: 12 }}
              >
                <option value="SITREP">SITREP (Situation Report)</option>
                <option value="DEPLOYMENT">Deployment Report</option>
                <option value="RESOLUTION">Resolution Report</option>
                <option value="ESCALATION">Further Escalation</option>
                <option value="UPDATE">General Update</option>
              </select>
            </div>
            <div>
              <label style={{ fontSize: 11, fontWeight: 700, color: 'var(--text-muted)', display: 'block', marginBottom: 6 }}>OUTCOME</label>
              <select
                value={form.outcome}
                onChange={e => setForm({ ...form, outcome: e.target.value })}
                style={{ width: '100%', padding: '9px 12px', background: 'var(--input-bg)', border: '1px solid var(--border)', borderRadius: 8, color: 'var(--text-primary)', fontSize: 12 }}
              >
                <option value="ONGOING">Situation Ongoing</option>
                <option value="CONTAINED">Situation Contained</option>
                <option value="RESOLVED">Fully Resolved</option>
                <option value="REQUIRES_HQ">Requires HQ Intervention</option>
                <option value="INCONCLUSIVE">Inconclusive</option>
              </select>
            </div>
          </div>

          <div>
            <label style={{ fontSize: 11, fontWeight: 700, color: 'var(--text-muted)', display: 'block', marginBottom: 6 }}>NARRATIVE *</label>
            <textarea
              value={form.narrative}
              onChange={e => setForm({ ...form, narrative: e.target.value })}
              placeholder="Detailed account of actions taken, current situation, and next steps..."
              rows={5}
              style={{ width: '100%', padding: '10px 14px', background: 'var(--input-bg)', border: '1px solid var(--border)', borderRadius: 8, color: 'var(--text-primary)', fontSize: 13, resize: 'vertical', outline: 'none', boxSizing: 'border-box' }}
            />
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
            {[
              { key: 'personnel_count', label: 'Personnel Involved' },
              { key: 'casualties', label: 'Casualties (if any)' },
            ].map(field => (
              <div key={field.key}>
                <label style={{ fontSize: 11, fontWeight: 700, color: 'var(--text-muted)', display: 'block', marginBottom: 6 }}>{field.label}</label>
                <input
                  type="number"
                  min={0}
                  value={(form as any)[field.key]}
                  onChange={e => setForm({ ...form, [field.key]: Number(e.target.value) })}
                  style={{ width: '100%', padding: '9px 12px', background: 'var(--input-bg)', border: '1px solid var(--border)', borderRadius: 8, color: 'var(--text-primary)', fontSize: 13, boxSizing: 'border-box' }}
                />
              </div>
            ))}
          </div>

          <div style={{ display: 'flex', gap: 10 }}>
            <button type="button" onClick={onClose} style={{ flex: 1, padding: '10px', borderRadius: 8, border: '1px solid var(--border)', background: 'transparent', color: 'var(--text-muted)', cursor: 'pointer', fontWeight: 700 }}>CANCEL</button>
            <button
              type="submit"
              disabled={submitting}
              style={{
                flex: 2, padding: '10px', borderRadius: 8, border: `1px solid ${agencyColor}`,
                background: agencyColor, color: 'white', fontWeight: 700, fontSize: 13,
                cursor: submitting ? 'not-allowed' : 'pointer', opacity: submitting ? 0.7 : 1,
                fontFamily: "'Outfit', sans-serif", display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
              }}
            >
              {submitting ? <Loader2 size={14} style={{ animation: 'spin 1s linear infinite' }} /> : <Send size={14} />}
              {submitting ? 'Submitting...' : 'SUBMIT REPORT TO HQ'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
