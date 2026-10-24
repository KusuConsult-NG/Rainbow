'use client';
import { useCallback, useEffect, useState } from 'react';
import {
  AlertTriangle, Check, Crosshair, EyeOff, Loader2, MapPin, RefreshCw, Shield,
} from 'lucide-react';
import {
  type PositionProblem, type SafeZone, ZONE_TYPES, knownLgas, loadSafeZones,
  nearestWardIn, publishSafeZone, retireSafeZone, verifySafeZone,
  wardDisagreement,
} from '@/lib/safe-zones';

/**
 * Shelters, and whether anybody has stood at them.
 *
 * `safe_zone_screen.dart` draws a fleeing citizen a route to the nearest one of
 * these. Until now nothing anywhere could write the table: the RLS policy
 * letting command do it had existed since August and nothing had ever called
 * it, which is why nobody noticed that only 2 of the project's 22 staff
 * accounts satisfied `is_command()`. The seven rows in it came from a seed, at
 * coordinates nobody measured, and three were outside every surveyed ward of
 * the LGA their own row claimed — the worst by 9.6km, in a different LGA
 * entirely.
 *
 * So this screen's job is not "manage shelters". It is to let the people who
 * know where the police stations and outposts actually are say so, and to make
 * the difference between a measured position and a guess impossible to lose.
 * Hence:
 *
 *   * hidden rows are shown FIRST, because correcting them is the work;
 *   * the form starts EMPTY — no default coordinate, ever;
 *   * "use my position" is the browser's own fix, which is a measurement;
 *   * the position is measured against the LGA it claims as it is typed;
 *   * confirming a position is a separate act, and it stores who did it.
 *
 * See E2E_AUDIT_REPORT.md T-93, T-94, T-98.
 */

const EMPTY = {
  name: '', type: 'POLICE', lga: '', ward: '', lat: '', lng: '',
  capacity: '', description: '', verified: false,
};

function fmt(n: number): string {
  return n.toFixed(6);
}

export default function SafeZonesPanel() {
  const [zones, setZones] = useState<SafeZone[] | null>(null);
  const [failed, setFailed] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [form, setForm] = useState({ ...EMPTY });
  const [formError, setFormError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [locating, setLocating] = useState(false);

  const refresh = useCallback(async () => {
    const res = await loadSafeZones();
    if (res.ok) { setZones(res.zones); setFailed(null); }
    // The error is kept and the list is NOT blanked: an empty board would tell
    // command there are no shelters when we simply could not ask.
    else setFailed(res.error);
  }, []);

  useEffect(() => { void refresh(); }, [refresh]);

  const lat = Number.parseFloat(form.lat);
  const lng = Number.parseFloat(form.lng);
  const hasPosition = Number.isFinite(lat) && Number.isFinite(lng);
  const problem: PositionProblem | null = hasPosition
    ? wardDisagreement(lat, lng, form.lga)
    : null;

  const useMyPosition = () => {
    if (!navigator.geolocation) {
      setFormError('This browser cannot report a position.');
      return;
    }
    setLocating(true);
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        setLocating(false);
        const next = {
          lat: fmt(pos.coords.latitude),
          lng: fmt(pos.coords.longitude),
        };
        setForm((f) => ({
          ...f, ...next,
          ward: f.ward || nearestWardIn(
            pos.coords.latitude, pos.coords.longitude, f.lga) || '',
        }));
        setFormError(null);
      },
      (err) => {
        setLocating(false);
        // Said, not swallowed: a refused permission and a failed fix look the
        // same from here and neither must leave the field quietly empty.
        setFormError(`Could not read this device's position: ${err.message}`);
      },
      { enableHighAccuracy: true, timeout: 15_000 },
    );
  };

  const submit = async () => {
    setFormError(null);
    setNotice(null);
    if (!form.name.trim()) {
      setFormError('A shelter needs a name somebody can ask directions to.');
      return;
    }
    if (!hasPosition) {
      setFormError(
        'A shelter with no position cannot be routed to. Leave it out rather ' +
        'than storing a guess.',
      );
      return;
    }
    if (problem && problem.kind !== 'outside-lga') {
      setFormError(problem.message);
      return;
    }
    setBusy('publish');
    const res = await publishSafeZone({
      name: form.name,
      latitude: lat,
      longitude: lng,
      type: form.type,
      geoLga: form.lga.trim() || null,
      geoWard: form.ward.trim() || null,
      capacity: form.capacity.trim() ? Number.parseInt(form.capacity, 10) : null,
      description: form.description.trim() || null,
      verified: form.verified,
    });
    setBusy(null);
    if (!res.ok) { setFormError(res.error); return; }
    setNotice(
      `${res.zone.name} is published and ${
        res.zone.verified_at ? 'recorded as confirmed by you' : 'marked unconfirmed'
      }.`,
    );
    setForm({ ...EMPTY });
    await refresh();
  };

  const act = async (
    id: string,
    what: 'verify' | 'retire',
    name: string,
  ) => {
    setNotice(null);
    setFormError(null);
    if (what === 'retire') {
      const why = window.prompt(
        `Hide ${name} from the citizen app. It is not deleted.\n\n` +
        'Why? (shown in the record)',
      );
      if (why === null) return;
      setBusy(id);
      const res = await retireSafeZone(id, why.trim() || null);
      setBusy(null);
      if (!res.ok) { setFormError(res.error); return; }
      setNotice(`${name} is hidden from the citizen app.`);
    } else {
      // An attestation, not a button. The id stored against it is the whole
      // value of the column.
      const ok = window.confirm(
        `Confirm the position of ${name}?\n\n` +
        'This records YOUR account as having confirmed it, and the citizen ' +
        'app stops warning people that the position is unconfirmed. Only do ' +
        'this if you know where this building is — a position read from a ' +
        'desk is not a confirmation.',
      );
      if (!ok) return;
      setBusy(id);
      const res = await verifySafeZone(id);
      setBusy(null);
      if (!res.ok) { setFormError(res.error); return; }
      setNotice(`${name} is recorded as confirmed by you.`);
    }
    await refresh();
  };

  const correct = (z: SafeZone) => {
    setForm({
      name: z.name,
      type: z.type || 'POLICE',
      lga: z.geo_lga ?? '',
      ward: z.geo_ward ?? '',
      lat: fmt(z.latitude),
      lng: fmt(z.longitude),
      capacity: z.capacity == null ? '' : String(z.capacity),
      description: z.description ?? '',
      verified: false,
    });
    setNotice(
      `Editing ${z.name}. Publishing with the same name corrects that row ` +
      'rather than adding a second one.',
    );
    window.scrollTo({ top: 0, behavior: 'smooth' });
  };

  const hidden = (zones ?? []).filter((z) => !z.is_active);
  const unconfirmed = (zones ?? []).filter((z) => z.is_active && !z.verified_at);

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
      <div style={{
        background: 'var(--surface)', borderRadius: 16, padding: 16,
        border: '1px solid var(--border)',
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8 }}>
          <Shield size={16} color="var(--accent)" />
          <span style={{ fontSize: 11, fontWeight: 900, letterSpacing: 1 }}>
            SHELTERS — POLICE STATIONS AND SECURITY OUTPOSTS
          </span>
        </div>
        <p style={{ fontSize: 11, color: 'var(--text-muted)', lineHeight: 1.6, margin: 0 }}>
          The citizen app draws a route to the nearest one of these. A position
          nobody has stood at sends somebody to the wrong place, so the app tells
          them when it is unconfirmed — and the seven that came with the system
          are all unconfirmed, because none of their coordinates was measured.
        </p>
        {(hidden.length > 0 || unconfirmed.length > 0) && (
          <div style={{
            marginTop: 12, padding: 10, borderRadius: 10,
            background: 'rgba(245,158,11,0.10)', border: '1px solid var(--warning)',
            fontSize: 11, color: 'var(--warning)', fontWeight: 700, lineHeight: 1.6,
          }}>
            <AlertTriangle size={12} style={{ verticalAlign: '-2px' }} />{' '}
            {hidden.length > 0 && (
              <>
                {hidden.length} shelter{hidden.length === 1 ? ' is' : 's are'} hidden
                because the position disagrees with its own LGA. Correcting one
                un-hides it.{' '}
              </>
            )}
            {unconfirmed.length > 0 && (
              <>
                {unconfirmed.length} visible shelter
                {unconfirmed.length === 1 ? ' has' : 's have'} an unconfirmed
                position.
              </>
            )}
          </div>
        )}
      </div>

      {/* ── the form, which starts empty ── */}
      <div style={{
        background: 'var(--surface)', borderRadius: 16, padding: 16,
        border: '1px solid var(--border)', display: 'flex',
        flexDirection: 'column', gap: 10,
      }}>
        <span style={{ fontSize: 11, fontWeight: 900, letterSpacing: 1 }}>
          PUBLISH OR CORRECT A SHELTER
        </span>

        <input
          value={form.name}
          onChange={(e) => setForm({ ...form, name: e.target.value })}
          placeholder="Name, as somebody would ask for it — e.g. BUKURU DIVISIONAL POLICE"
          style={inputStyle}
        />

        <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap' }}>
          <select
            value={form.type}
            onChange={(e) => setForm({ ...form, type: e.target.value })}
            style={{ ...inputStyle, flex: '1 1 200px' }}
          >
            {ZONE_TYPES.map((t) => (
              <option key={t.value} value={t.value}>{t.label}</option>
            ))}
          </select>
          <select
            value={form.lga}
            onChange={(e) => setForm({
              ...form,
              lga: e.target.value,
              ward: hasPosition
                ? nearestWardIn(lat, lng, e.target.value) ?? ''
                : '',
            })}
            style={{ ...inputStyle, flex: '1 1 160px' }}
          >
            <option value="">LGA (none)</option>
            {knownLgas().map((l) => <option key={l} value={l}>{l}</option>)}
          </select>
          <input
            value={form.ward}
            onChange={(e) => setForm({ ...form, ward: e.target.value })}
            placeholder="Ward"
            style={{ ...inputStyle, flex: '1 1 140px' }}
          />
        </div>

        <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap', alignItems: 'center' }}>
          <input
            value={form.lat}
            onChange={(e) => setForm({ ...form, lat: e.target.value })}
            placeholder="Latitude"
            inputMode="decimal"
            style={{ ...inputStyle, flex: '1 1 130px' }}
          />
          <input
            value={form.lng}
            onChange={(e) => setForm({ ...form, lng: e.target.value })}
            placeholder="Longitude"
            inputMode="decimal"
            style={{ ...inputStyle, flex: '1 1 130px' }}
          />
          <button onClick={useMyPosition} disabled={locating} style={buttonStyle}>
            {locating ? <Loader2 size={12} className="animate-spin" /> : <Crosshair size={12} />}
            {locating ? 'READING' : 'USE THIS DEVICE'}
          </button>
          <input
            value={form.capacity}
            onChange={(e) => setForm({ ...form, capacity: e.target.value })}
            placeholder="Capacity"
            inputMode="numeric"
            style={{ ...inputStyle, flex: '0 1 110px' }}
          />
        </div>

        {problem && (
          <div style={{
            padding: 10, borderRadius: 10, fontSize: 11, fontWeight: 700,
            lineHeight: 1.6,
            background: problem.kind === 'outside-lga'
              ? 'rgba(245,158,11,0.10)' : 'rgba(239,68,68,0.10)',
            border: `1px solid ${problem.kind === 'outside-lga' ? 'var(--warning)' : 'var(--duress)'}`,
            color: problem.kind === 'outside-lga' ? 'var(--warning)' : 'var(--duress)',
          }}>
            <AlertTriangle size={12} style={{ verticalAlign: '-2px' }} />{' '}
            {problem.message}
            {problem.kind === 'outside-lga' && (
              <>
                {' '}This is a warning, not a refusal — a building can sit just
                over a ward boundary, and you may know better than the surveyed
                centroids do.
              </>
            )}
          </div>
        )}

        <input
          value={form.description}
          onChange={(e) => setForm({ ...form, description: e.target.value })}
          placeholder="Anything that helps somebody find it — landmark, road"
          style={inputStyle}
        />

        <label style={{
          display: 'flex', gap: 8, alignItems: 'flex-start', fontSize: 11,
          color: 'var(--text-muted)', lineHeight: 1.6, cursor: 'pointer',
        }}>
          <input
            type="checkbox"
            checked={form.verified}
            onChange={(e) => setForm({ ...form, verified: e.target.checked })}
            style={{ marginTop: 2 }}
          />
          <span>
            I know where this is. Records my account against the position, and
            stops the citizen app warning people about it. Leave unchecked if
            you are entering a position somebody read to you.
          </span>
        </label>

        {formError && (
          <div style={{ fontSize: 11, color: 'var(--duress)', fontWeight: 700 }}>{formError}</div>
        )}
        {notice && (
          <div style={{ fontSize: 11, color: 'var(--accent)', fontWeight: 700 }}>{notice}</div>
        )}

        <button
          onClick={submit}
          disabled={busy === 'publish'}
          style={{ ...buttonStyle, alignSelf: 'flex-start', padding: '8px 16px' }}
        >
          {busy === 'publish' ? <Loader2 size={12} className="animate-spin" /> : <MapPin size={12} />}
          PUBLISH
        </button>
      </div>

      {/* ── the list ── */}
      <div style={{
        background: 'var(--surface)', borderRadius: 16, padding: 16,
        border: '1px solid var(--border)',
      }}>
        <div style={{
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          marginBottom: 12,
        }}>
          <span style={{ fontSize: 11, fontWeight: 900, letterSpacing: 1 }}>
            {zones === null ? 'LOADING' : `${zones.length} SHELTER(S) ON RECORD`}
          </span>
          <button onClick={() => void refresh()} style={buttonStyle}>
            <RefreshCw size={12} /> REFRESH
          </button>
        </div>

        {failed && (
          <div style={{ fontSize: 11, color: 'var(--duress)', fontWeight: 700, marginBottom: 10 }}>
            Could not read the shelters: {failed}. This is not the same as there
            being none — nothing below has been refreshed.
          </div>
        )}

        {zones !== null && zones.length === 0 && !failed && (
          <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>
            No shelter has been published. The citizen app shows its empty state
            rather than inventing somewhere to run to.
          </div>
        )}

        <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          {(zones ?? []).map((z) => {
            const trouble = wardDisagreement(z.latitude, z.longitude, z.geo_lga);
            return (
              <div key={z.id} style={{
                padding: 12, borderRadius: 12, border: '1px solid var(--border)',
                background: z.is_active ? 'transparent' : 'rgba(100,116,139,0.08)',
                display: 'flex', flexDirection: 'column', gap: 6,
              }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
                  <span style={{ fontSize: 12, fontWeight: 900 }}>{z.name}</span>
                  <Pill text={z.type} tone="muted" />
                  {!z.is_active && <Pill text="HIDDEN" tone="muted" icon={<EyeOff size={9} />} />}
                  {z.verified_at
                    ? <Pill text="POSITION CONFIRMED" tone="ok" icon={<Check size={9} />} />
                    : <Pill text="UNCONFIRMED" tone="warn" icon={<AlertTriangle size={9} />} />}
                </div>
                <div style={{ fontSize: 10, color: 'var(--text-muted)', fontFamily: 'monospace' }}>
                  {z.geo_lga || '—'}{z.geo_ward ? ` / ${z.geo_ward}` : ''}
                  {'  ·  '}{fmt(z.latitude)}, {fmt(z.longitude)}
                  {z.capacity ? `  ·  capacity ${z.capacity}` : ''}
                </div>
                {trouble?.kind === 'outside-lga' && (
                  <div style={{ fontSize: 10, color: 'var(--warning)', fontWeight: 700, lineHeight: 1.5 }}>
                    {trouble.message}
                  </div>
                )}
                {z.description && (
                  <div style={{ fontSize: 10, color: 'var(--text-muted)', lineHeight: 1.5 }}>
                    {z.description}
                  </div>
                )}
                <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', marginTop: 2 }}>
                  <button onClick={() => correct(z)} style={buttonStyle}>CORRECT</button>
                  {!z.verified_at && (
                    <button
                      onClick={() => void act(z.id, 'verify', z.name)}
                      disabled={busy === z.id}
                      style={buttonStyle}
                    >
                      {busy === z.id ? <Loader2 size={12} className="animate-spin" /> : <Check size={12} />}
                      CONFIRM POSITION
                    </button>
                  )}
                  {z.is_active && (
                    <button
                      onClick={() => void act(z.id, 'retire', z.name)}
                      disabled={busy === z.id}
                      style={buttonStyle}
                    >
                      <EyeOff size={12} /> HIDE
                    </button>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}

const inputStyle: React.CSSProperties = {
  background: 'var(--surface-container)',
  border: '1px solid var(--border)',
  borderRadius: 10,
  padding: '8px 10px',
  fontSize: 11,
  color: 'var(--text-primary)',
  fontFamily: 'inherit',
};

const buttonStyle: React.CSSProperties = {
  display: 'inline-flex',
  alignItems: 'center',
  gap: 6,
  padding: '6px 12px',
  borderRadius: 8,
  border: '1px solid var(--border)',
  background: 'var(--surface-container)',
  color: 'var(--text-primary)',
  fontSize: 10,
  fontWeight: 800,
  letterSpacing: 0.5,
  cursor: 'pointer',
};

function Pill({ text, tone, icon }: {
  text: string;
  tone: 'ok' | 'warn' | 'muted';
  icon?: React.ReactNode;
}) {
  const colour = tone === 'ok' ? 'var(--success)'
    : tone === 'warn' ? 'var(--warning)' : 'var(--text-muted)';
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: 4,
      fontSize: 9, fontWeight: 800, padding: '2px 8px', borderRadius: 12,
      color: colour, border: `1px solid ${colour}`,
    }}>
      {icon}{text}
    </span>
  );
}
