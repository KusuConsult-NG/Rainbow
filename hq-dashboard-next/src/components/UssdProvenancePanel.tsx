'use client';

/**
 * The panel on an incident that arrived from a keypad.
 *
 * A USSD report is held out of the escalation ladder until a named officer
 * stands behind it, because USSD is the cheapest way to lure responders to a
 * chosen place and no TIMER may make that call (migration 20261011000000). This
 * is where the officer makes it instead.
 *
 * Three things about its design are deliberate:
 *
 *   * **It is loud but not alarming.** An unconfirmed report is not a threat —
 *     most of them are real, from people with no other way to reach anybody. The
 *     panel is the accent colour, not the duress colour, unless the credibility
 *     actually warrants caution.
 *   * **Nothing is disabled.** DISPATCH stays live on the card. Confirming is
 *     one click, and dispatching an unconfirmed report confirms it anyway; a
 *     greyed-out button would cost seconds in an armed attack and buy nothing.
 *   * **The credibility panel failing does not hide the incident.** If the
 *     lookup cannot be read, the confirm control still works. An emergency must
 *     never be invisible because a side panel errored.
 */

import { useEffect, useState } from 'react';
import { AlertTriangle, CheckCircle, Phone, ShieldQuestion, XCircle } from 'lucide-react';

import { confirmUssdReport, markFalseReport, ussdCredibility } from '@/lib/alert-actions';
import {
  type Concern,
  type ProvenanceAlert,
  type UssdCredibility,
  awaitingConfirmation,
  credibilityConcerns,
  holdExplanation,
  provenanceBadge,
  warrantsCaution,
} from '@/lib/ussd-provenance';

const LEVEL_COLOUR: Record<Concern['level'], string> = {
  high: 'var(--duress)',
  medium: 'var(--warning)',
  low: 'var(--text-muted)',
  good: 'var(--success)',
};

export interface UssdProvenancePanelProps {
  alert: ProvenanceAlert & { id: string };
  /** Called after a successful confirm or false-mark, so the board can refetch. */
  onChanged?: () => void;
  /** Injected in tests. */
  actions?: {
    confirm: typeof confirmUssdReport;
    markFalse: typeof markFalseReport;
    credibility: typeof ussdCredibility;
  };
}

export default function UssdProvenancePanel({
  alert,
  onChanged,
  actions,
}: UssdProvenancePanelProps) {
  const api = actions ?? {
    confirm: confirmUssdReport,
    markFalse: markFalseReport,
    credibility: ussdCredibility,
  };

  const [cred, setCred] = useState<UssdCredibility | null>(null);
  const [busy, setBusy] = useState<'confirm' | 'false' | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [askingFalse, setAskingFalse] = useState(false);
  const [note, setNote] = useState('');

  const badge = provenanceBadge(alert);
  const unconfirmed = awaitingConfirmation(alert);

  useEffect(() => {
    // Only for an unconfirmed report. Once an officer has stood behind it the
    // credibility of the number is no longer the decision in front of anybody,
    // and a panel that stays up for ever is a panel people stop reading.
    if (!unconfirmed) return;
    let live = true;
    void api.credibility(alert.id).then(c => {
      if (live) setCred(c);
    });
    return () => {
      live = false;
    };
  }, [alert.id, unconfirmed, api]);

  if (!badge) return null;

  const cautious = cred ? warrantsCaution(cred) : false;
  const accent = cautious ? 'var(--duress)' : unconfirmed ? 'var(--accent)' : 'var(--success)';

  async function doConfirm() {
    setBusy('confirm');
    setError(null);
    const res = await api.confirm(alert.id);
    setBusy(null);
    if (!res.ok) {
      // Shown in place rather than as a toast that scrolls away: the officer
      // needs to know the report is STILL held back and nothing is chasing it.
      setError(res.error);
      return;
    }
    onChanged?.();
  }

  async function doMarkFalse() {
    setBusy('false');
    setError(null);
    const res = await api.markFalse(alert.id, note.trim());
    setBusy(null);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    setAskingFalse(false);
    setNote('');
    onChanged?.();
  }

  return (
    <div
      data-testid="ussd-provenance"
      style={{
        background: cautious ? 'rgba(239, 68, 68, 0.12)' : 'rgba(59, 130, 246, 0.10)',
        border: `1px solid ${accent}`,
        padding: '10px 12px',
        borderRadius: 10,
        marginBottom: 14,
      }}
    >
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 8 }}>
        <span style={{ fontSize: 10, fontWeight: 900, color: accent, letterSpacing: 0.8, display: 'flex', alignItems: 'center', gap: 6 }}>
          <ShieldQuestion size={13} /> {badge}
        </span>
        {alert.reporter_msisdn && (
          <span style={{ fontSize: 9, fontWeight: 700, color: 'var(--text-muted)', fontFamily: 'monospace', display: 'flex', alignItems: 'center', gap: 4 }}>
            <Phone size={10} /> {alert.reporter_msisdn}
            {alert.caller_may_be_called === false && ' · no callback'}
          </span>
        )}
      </div>

      {unconfirmed && (
        <p style={{ fontSize: 11, color: 'var(--text-muted)', margin: '8px 0 0' }}>
          {holdExplanation(alert)}
        </p>
      )}

      {cred && (
        <ul style={{ listStyle: 'none', padding: 0, margin: '10px 0 0', display: 'flex', flexDirection: 'column', gap: 4 }}>
          {credibilityConcerns(cred).map((c, i) => (
            <li
              key={i}
              style={{ fontSize: 10.5, color: LEVEL_COLOUR[c.level], display: 'flex', alignItems: 'flex-start', gap: 6 }}
            >
              {c.level === 'good' ? <CheckCircle size={11} style={{ marginTop: 2, flexShrink: 0 }} />
                : c.level === 'high' ? <AlertTriangle size={11} style={{ marginTop: 2, flexShrink: 0 }} />
                : <span style={{ marginTop: 1, flexShrink: 0 }}>·</span>}
              <span>{c.text}</span>
            </li>
          ))}
        </ul>
      )}

      {error && (
        <p role="alert" style={{ fontSize: 10.5, color: 'var(--duress)', margin: '8px 0 0', fontWeight: 700 }}>
          {error}
        </p>
      )}

      {unconfirmed && !askingFalse && (
        <div style={{ display: 'flex', gap: 8, marginTop: 10, flexWrap: 'wrap' }}>
          <button
            onClick={doConfirm}
            disabled={busy !== null}
            style={{
              flex: '1 1 auto', minWidth: 130, padding: '7px 10px', borderRadius: 8,
              border: `1px solid ${accent}`, background: 'transparent', color: accent,
              fontSize: 10, fontWeight: 900, letterSpacing: 0.6,
              cursor: busy ? 'wait' : 'pointer',
            }}
          >
            {busy === 'confirm' ? 'CONFIRMING…' : 'CONFIRM — IT IS REAL'}
          </button>
          <button
            onClick={() => setAskingFalse(true)}
            disabled={busy !== null}
            style={{
              flex: '1 1 auto', minWidth: 120, padding: '7px 10px', borderRadius: 8,
              border: '1px solid var(--border)', background: 'transparent',
              color: 'var(--text-muted)', fontSize: 10, fontWeight: 900, letterSpacing: 0.6,
              cursor: busy ? 'wait' : 'pointer',
            }}
          >
            MARK FALSE
          </button>
        </div>
      )}

      {askingFalse && (
        <div style={{ marginTop: 10 }}>
          <label
            htmlFor={`false-note-${alert.id}`}
            style={{ fontSize: 10, fontWeight: 800, color: 'var(--text-muted)', display: 'block', marginBottom: 4 }}
          >
            {/* The note is the whole point. It is what the next dispatcher reads
                when this same number calls again. */}
            How do you know? The next dispatcher will read this.
          </label>
          <input
            id={`false-note-${alert.id}`}
            value={note}
            onChange={e => setNote(e.target.value)}
            placeholder="e.g. rang the number back, nothing happening"
            style={{
              width: '100%', padding: '7px 9px', borderRadius: 8, fontSize: 11,
              background: 'var(--bg-secondary)', color: 'var(--text-primary)',
              border: '1px solid var(--border)',
            }}
          />
          <div style={{ display: 'flex', gap: 8, marginTop: 8 }}>
            <button
              onClick={doMarkFalse}
              // A note is required. "Marked false by an officer" with no reason
              // is an accusation nobody can check, and it is what the next
              // dispatcher has to weigh against a real emergency.
              disabled={busy !== null || note.trim().length < 4}
              style={{
                flex: 1, padding: '7px 10px', borderRadius: 8,
                border: '1px solid var(--duress)', background: 'transparent',
                color: 'var(--duress)', fontSize: 10, fontWeight: 900,
                opacity: note.trim().length < 4 ? 0.5 : 1,
                cursor: note.trim().length < 4 ? 'not-allowed' : 'pointer',
              }}
            >
              <XCircle size={11} style={{ verticalAlign: -2, marginRight: 4 }} />
              {busy === 'false' ? 'RECORDING…' : 'RECORD AS FALSE'}
            </button>
            <button
              onClick={() => { setAskingFalse(false); setNote(''); setError(null); }}
              disabled={busy !== null}
              style={{
                padding: '7px 12px', borderRadius: 8, border: '1px solid var(--border)',
                background: 'transparent', color: 'var(--text-muted)', fontSize: 10, fontWeight: 900,
              }}
            >
              CANCEL
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
