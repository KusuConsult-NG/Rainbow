import { useState } from 'react';
import { AGENCY_LIST, AGENCY_TARGET_ALL } from '@/lib/agencies';
import { supabase } from '@/lib/supabase';
import { Radio, Send, ShieldAlert, Loader2, MapPin, Users, MessageSquare } from 'lucide-react';
import { plateauTacticalMap } from '@/lib/tactical_mapping';

const TEMPLATES = [
  '[OPERATION RAINBOW]: PUBLIC SAFETY ALERT - A security incident has been reported in your sector. Stay indoors and await official guidance.',
  '[OPERATION RAINBOW]: TACTICAL ADVISORY - Heightened security patrols deployed to your sector. Report any suspicious activity via the RainBow app.',
  '[OPERATION RAINBOW]: ALL CLEAR - The security situation in your sector has been successfully resolved. Normal activities may resume. Stay alert.',
  '[OPERATION RAINBOW]: EMERGENCY REFUGE NOTICE - Move calmly to the nearest verified safe zone or police post. Follow directions from uniformed personnel.',
];

export default function MassBroadcast() {
  const [message, setMessage] = useState('');
  const [severity, setSeverity] = useState<'INFO' | 'WARNING' | 'CRITICAL'>('CRITICAL');
  const [targetAudience, setTargetAudience] = useState<'ALL' | 'CITIZENS' | 'AGENTS'>('ALL');
  const [targetAgency, setTargetAgency] = useState<string>('ALL');
  // How long the advisory stands. The console had no control for this and never
  // wrote `expires_at`, so every broadcast lived on the default until somebody
  // deactivated it by hand — which nothing in this UI can do either.
  const [expiryHours, setExpiryHours] = useState(24);
  const [targetLga, setTargetLga] = useState('ALL');
  const [targetWard, setTargetWard] = useState('ALL');
  const [targetPu, setTargetPu] = useState('ALL');

  const [sending, setSending] = useState(false);
  const [success, setSuccess] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const selectedLgaData = plateauTacticalMap.find(l => l.name.toUpperCase() === targetLga.toUpperCase());
  const selectedWardData = selectedLgaData?.wards?.find(w => w.name.toUpperCase() === targetWard.toUpperCase());

  const handleBroadcast = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!message.trim()) return;

    setSending(true);
    setSuccess(null);
    setError(null);

    const fullSectorScope = targetPu !== 'ALL' 
      ? `${targetLga} - ${targetWard} (${targetPu})`
      : targetWard !== 'ALL'
      ? `${targetLga} - ${targetWard} District`
      : targetLga !== 'ALL'
      ? `${targetLga} LGA`
      : 'STATEWIDE (ALL SECTORS)';

    try {
      // Every field here is a real column (see
      // supabase/migrations/20260903000002_system_alerts_broadcast.sql).
      // It previously was not: `active` and `target_sector` existed nowhere, so
      // PostgREST rejected the whole insert, and `title` was omitted while being
      // NOT NULL. No broadcast sent from this console ever reached anybody.
      const payload = {
        // NOT NULL. Neither this screen nor the mobile one asks the operator for
        // a heading, so it is derived — severity and scope are what an advisory
        // needs at a glance.
        title: `${severity} ADVISORY — ${fullSectorScope}`,
        message: message.trim(),
        severity,
        target_audience: targetAudience,
        target_agency: targetAgency,
        target_lga: targetLga,
        target_ward: targetWard,
        target_pu: targetPu,
        // The mobile listener filters on `is_active`. The old payload set
        // `active`, which is not a column — and even had it been, nothing read it.
        is_active: true,
        // Was never set, so console advisories relied on the column default and
        // could not be given a duration. An advisory that outlives the situation
        // it describes is how a board full of stale warnings starts.
        expires_at: new Date(Date.now() + expiryHours * 3600_000).toISOString(),
        created_at: new Date().toISOString()
      };

      const { error: insertErr } = await supabase.from('system_alerts').insert(payload);

      if (insertErr) throw insertErr;

      const agencyLabel = targetAgency === 'ALL' ? 'All Joint Agencies' : targetAgency;
      setSuccess(`Inter-Agency Communications advisory dispatched successfully to ${agencyLabel} (${targetAudience}) in ${fullSectorScope}!`);
      setMessage('');
    } catch (err: any) {
      setError(err.message || 'Failed to transmit broadcast advisory');
    } finally {
      setSending(false);
    }
  };

  return (
    <div className="tactical-panel glass" style={{ padding: 32, maxWidth: 840, margin: '0 auto', borderRadius: 20 }}>
      <h2 style={{ fontSize: 20, fontWeight: 900, marginBottom: 6, display: 'flex', alignItems: 'center', gap: 10, color: 'var(--text-primary)', fontFamily: "var(--font-outfit), sans-serif" }}>
        <Radio style={{ width: 24, height: 24, color: 'var(--primary)' }} />
        Inter-Agency Public Safety Communications & Dispatcher
      </h2>
      <p style={{ fontSize: 12, color: 'var(--text-muted)', marginBottom: 28 }}>
        Transmit real-time joint security advisories, emergency alerts, and inter-agency dispatches directly to Police, Military STF, Civil Defence, and Operation Rainbow units.
      </p>

      {error && (
        <div style={{ padding: 14, background: 'var(--duress-dim)', border: '1px solid var(--duress)', borderRadius: 12, color: 'var(--duress)', marginBottom: 20, fontSize: 12, fontWeight: 700 }}>
          {error}
        </div>
      )}

      {success && (
        <div style={{ padding: 14, background: 'var(--success-dim)', border: '1px solid var(--success)', borderRadius: 12, color: 'var(--success)', marginBottom: 20, fontSize: 12, fontWeight: 800 }}>
          {success}
        </div>
      )}

      <form onSubmit={handleBroadcast} style={{ display: 'flex', flexDirection: 'column', gap: 24 }}>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 16 }}>
          <div>
            <label style={{ fontSize: 11, fontWeight: 800, color: 'var(--text-muted)', display: 'block', marginBottom: 8, letterSpacing: 0.5 }}>
              SEVERITY LEVEL
            </label>
            <select
              className="input-tactical"
              style={{ width: '100%', padding: '10px 14px', borderRadius: 10, fontSize: 12, fontWeight: 700 }}
              value={severity}
              onChange={(e) => setSeverity(e.target.value as any)}
            >
              <option value="INFO">🟢 INFO (General Advisory)</option>
              <option value="WARNING">🟡 WARNING (Heightened Alert)</option>
              <option value="CRITICAL">🔴 CRITICAL (Emergency / Flash)</option>
            </select>
          </div>

          <div>
            <label style={{ fontSize: 11, fontWeight: 800, color: 'var(--text-muted)', display: 'block', marginBottom: 8, letterSpacing: 0.5 }}>
              TARGET AUDIENCE
            </label>
            <select
              className="input-tactical"
              style={{ width: '100%', padding: '10px 14px', borderRadius: 10, fontSize: 12, fontWeight: 700 }}
              value={targetAudience}
              onChange={(e) => setTargetAudience(e.target.value as any)}
            >
              <option value="ALL">🌐 ALL (Citizens + Security Units)</option>
              <option value="CITIZENS">📱 CITIZENS MOBILE APP ONLY</option>
              <option value="AGENTS">👮 FIELD RESPONDERS ONLY</option>
            </select>
          </div>

          <div>
            <label htmlFor="broadcast-expiry" style={{ fontSize: 11, fontWeight: 800, color: 'var(--text-muted)', display: 'block', marginBottom: 8, letterSpacing: 0.5 }}>
              ADVISORY STANDS FOR
            </label>
            <select
              id="broadcast-expiry"
              className="input-tactical"
              style={{ width: '100%', padding: '10px 14px', borderRadius: 10, fontSize: 12, fontWeight: 700 }}
              value={expiryHours}
              onChange={(e) => setExpiryHours(Number(e.target.value))}
            >
              <option value={6}>6 HOURS</option>
              <option value={12}>12 HOURS</option>
              <option value={24}>24 HOURS</option>
              <option value={72}>72 HOURS (3 DAYS)</option>
            </select>
          </div>

          <div>
            <label style={{ fontSize: 11, fontWeight: 800, color: 'var(--text-muted)', display: 'block', marginBottom: 8, letterSpacing: 0.5 }}>
              TARGET SECURITY AGENCY
            </label>
            <select
              className="input-tactical"
              style={{ width: '100%', padding: '10px 14px', borderRadius: 10, fontSize: 12, fontWeight: 700 }}
              value={targetAgency}
              onChange={(e) => setTargetAgency(e.target.value)}
            >
              {/*
                BUILT FROM THE SHARED LIST — the same correction as T-28, and
                it became urgent the moment this control acquired a reader.

                These were six hand-written options from the staff-badge list:
                NPF, MILITARY, RAINBOW, VGN and two that happened to overlap.
                While `target_agency` was read by nothing that was merely
                untidy. Now `advisoryReaches` compares it against the viewer's
                agency — POLICE / ARMY / DSS / NSCDC / FRSC / OPSH, derived from
                their liaison role — so an advisory addressed to "NIGERIA POLICE
                FORCE (NPF)" would have matched no liaison at all and reached
                nobody but command, which is exactly what the escalation menu
                did to incidents.

                RAINBOW and VGN are gone for the same reason they are not
                escalation destinations: Operation Rainbow's own staff are
                reached by `target_audience: AGENTS`, and no vigilante outfit
                has a console account to read an advisory with.
              */}
              <option value={AGENCY_TARGET_ALL}>🌐 ALL JOINT AGENCIES</option>
              {AGENCY_LIST.map(a => (
                <option key={a.code} value={a.code}>{a.icon} {a.label.toUpperCase()}</option>
              ))}
            </select>
          </div>
        </div>

        {/* 3-Tier Cascading Sector Hierarchy (LGA -> District/Ward -> Local Post/PU) */}
        <div style={{ background: 'var(--input-bg)', padding: 16, borderRadius: 14, border: '1px solid var(--border)' }}>
          <span style={{ fontSize: 10, fontWeight: 900, color: 'var(--primary)', letterSpacing: 1.5, display: 'block', marginBottom: 12 }}>
            TARGET SECTOR HIERARCHY (CASCADING)
          </span>

          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 14 }}>
            <div>
              <label style={{ fontSize: 10, fontWeight: 800, color: 'var(--text-muted)', display: 'block', marginBottom: 6 }}>
                1. LGA SECTOR
              </label>
              <select
                className="input-tactical"
                style={{ width: '100%', padding: '8px 12px', borderRadius: 8, fontSize: 11, fontWeight: 700, textTransform: 'uppercase' }}
                value={targetLga}
                onChange={(e) => {
                  setTargetLga(e.target.value);
                  setTargetWard('ALL');
                  setTargetPu('ALL');
                }}
              >
                <option value="ALL">STATEWIDE (ALL LGAS)</option>
                {plateauTacticalMap.map((lga) => (
                  <option key={lga.id} value={lga.name}>
                    {lga.name.toUpperCase()}
                  </option>
                ))}
              </select>
            </div>

            <div>
              <label style={{ fontSize: 10, fontWeight: 800, color: 'var(--text-muted)', display: 'block', marginBottom: 6 }}>
                2. DISTRICT / WARD
              </label>
              <select
                disabled={targetLga === 'ALL'}
                className="input-tactical"
                style={{ width: '100%', padding: '8px 12px', borderRadius: 8, fontSize: 11, fontWeight: 700, textTransform: 'uppercase', opacity: targetLga === 'ALL' ? 0.5 : 1 }}
                value={targetWard}
                onChange={(e) => {
                  setTargetWard(e.target.value);
                  setTargetPu('ALL');
                }}
              >
                <option value="ALL">ALL DISTRICTS IN {targetLga.toUpperCase()}</option>
                {selectedLgaData?.wards?.map((w) => (
                  <option key={w.id} value={w.name}>
                    {w.name.toUpperCase()}
                  </option>
                ))}
              </select>
            </div>

            <div>
              <label style={{ fontSize: 10, fontWeight: 800, color: 'var(--text-muted)', display: 'block', marginBottom: 6 }}>
                3. LOCAL POST / BEAT (PU)
              </label>
              <select
                disabled={targetWard === 'ALL'}
                className="input-tactical"
                style={{ width: '100%', padding: '8px 12px', borderRadius: 8, fontSize: 11, fontWeight: 700, textTransform: 'uppercase', opacity: targetWard === 'ALL' ? 0.5 : 1 }}
                value={targetPu}
                onChange={(e) => setTargetPu(e.target.value)}
              >
                <option value="ALL">ALL BEATS IN {targetWard.toUpperCase()}</option>
                {selectedWardData?.pollingUnits?.map((pu) => (
                  <option key={pu} value={pu}>
                    {pu}
                  </option>
                ))}
              </select>
            </div>
          </div>
        </div>

        <div>
          <label style={{ fontSize: 11, fontWeight: 800, color: 'var(--text-muted)', display: 'block', marginBottom: 8, letterSpacing: 0.5 }}>
            QUICK SECURITY TEMPLATE PRESETS
          </label>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {TEMPLATES.map((t, idx) => (
              <button
                key={idx}
                type="button"
                onClick={() => setMessage(t)}
                style={{
                  textAlign: 'left',
                  padding: '12px 16px',
                  background: 'var(--input-bg)',
                  border: '1px solid var(--border)',
                  borderRadius: 10,
                  fontSize: 12,
                  color: 'var(--text-primary)',
                  cursor: 'pointer',
                  fontWeight: 600,
                  transition: 'all 0.2s ease'
                }}
                className="card-hover"
              >
                {t}
              </button>
            ))}
          </div>
        </div>

        <div>
          <label style={{ fontSize: 11, fontWeight: 800, color: 'var(--text-muted)', display: 'block', marginBottom: 8, letterSpacing: 0.5 }}>
            BROADCAST ADVISORY PAYLOAD (PUSH + SMS GATEWAY)
          </label>
          <textarea
            required
            rows={4}
            className="input-tactical"
            style={{ width: '100%', resize: 'vertical', padding: '14px', borderRadius: 12, fontSize: 13, lineHeight: 1.5 }}
            value={message}
            onChange={(e) => setMessage(e.target.value)}
            placeholder="Type official emergency advisory message..."
          />
        </div>

        <button
          type="submit"
          disabled={sending || !message.trim()}
          className="btn-tactical btn-primary"
          style={{ padding: '14px 28px', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 10, borderRadius: 12, fontWeight: 900, fontSize: 13 }}
        >
          {sending ? <Loader2 className="animate-spin" style={{ width: 18, height: 18 }} /> : <Send style={{ width: 18, height: 18 }} />}
          TRANSMIT COMMUNICATIONS ADVISORY
        </button>
      </form>
    </div>
  );
}
