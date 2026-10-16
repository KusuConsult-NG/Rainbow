'use client';

import { AlertOctagon, RefreshCw, RotateCw } from 'lucide-react';

/**
 * What an operator sees when the console has crashed.
 *
 * The single most important property here is that this must NOT look like a
 * quiet shift. An emergency console that renders nothing is indistinguishable
 * from an emergency console with nothing to report — and the second reading is
 * the one a tired operator will take at 3am. So this screen is loud, says the
 * word FAILED, and states in plain language that incidents may be arriving
 * unseen and that radio is the fallback until it is back.
 *
 * This is the same reasoning that drove the mission-feed liveness fix on the
 * mobile side: on this system, "no alerts shown" and "the alert path is broken"
 * must never be drawn the same way.
 *
 * Rendered by three boundaries — app/dashboard/error.tsx, app/error.tsx and
 * app/global-error.tsx — which differ only in what they can rely on, so the
 * markup is shared here and the styles are inline: global-error.tsx replaces
 * the root layout entirely, and cannot assume globals.css has loaded.
 */

export interface ConsoleFailureProps {
  /** What crashed, in the operator's terms — not a stack trace. */
  scope: string;
  /** The caught error. Its `digest` is the only safe thing to show. */
  error: Error & { digest?: string };
  /**
   * Re-render the boundary's children, re-fetching as it goes. Next 16 calls
   * this `unstable_retry`; the older `reset()` only clears the error state
   * without re-fetching, which on a data-driven board usually crashes straight
   * back. Optional because global-error may only be able to offer a reload.
   */
  onRetry?: () => void;
}

const DURESS = '#B3261E';

export default function ConsoleFailure({ scope, error, onRetry }: ConsoleFailureProps) {
  return (
    <div
      role="alert"
      aria-live="assertive"
      style={{
        minHeight: '100vh',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        padding: 24,
        background: '#F7F7F7',
        color: '#1A1A1A',
        fontFamily: 'var(--font-inter), system-ui, -apple-system, sans-serif',
      }}
    >
      <div
        style={{
          maxWidth: 560,
          width: '100%',
          background: '#ffffff',
          border: `2px solid ${DURESS}`,
          borderRadius: 16,
          padding: '28px 28px 24px',
          boxShadow: '0 12px 36px rgba(15, 23, 42, 0.12)',
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 14 }}>
          <AlertOctagon size={28} color={DURESS} aria-hidden="true" />
          <div>
            <div style={{ fontSize: 11, fontWeight: 900, letterSpacing: 1.4, color: DURESS }}>
              CONSOLE FAILED
            </div>
            <h1 style={{ fontSize: 19, fontWeight: 800, margin: '2px 0 0' }}>{scope}</h1>
          </div>
        </div>

        {/* The operational instruction comes before the technical detail: it is
            the part that matters in the first two seconds. */}
        <p style={{ fontSize: 14, lineHeight: 1.6, margin: '0 0 10px', color: '#212121' }}>
          This screen stopped working. <strong>Incidents may be arriving that you cannot
          see here.</strong> Treat the board as offline until it comes back.
        </p>
        <p style={{ fontSize: 14, lineHeight: 1.6, margin: '0 0 18px', color: '#212121' }}>
          Fall back to radio for dispatch and hand-off. Nothing already recorded is lost —
          this is a display failure, not a data failure.
        </p>

        <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap' }}>
          {onRetry && (
            <button
              onClick={onRetry}
              style={{
                display: 'inline-flex',
                alignItems: 'center',
                gap: 8,
                padding: '11px 18px',
                borderRadius: 10,
                border: 'none',
                background: DURESS,
                color: '#ffffff',
                fontSize: 13,
                fontWeight: 800,
                cursor: 'pointer',
                fontFamily: 'inherit',
              }}
            >
              <RotateCw size={15} aria-hidden="true" /> RETRY
            </button>
          )}
          <button
            onClick={() => window.location.reload()}
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              gap: 8,
              padding: '11px 18px',
              borderRadius: 10,
              border: '1px solid rgba(148, 163, 184, 0.5)',
              background: '#F7F7F7',
              color: '#1A1A1A',
              fontSize: 13,
              fontWeight: 700,
              cursor: 'pointer',
              fontFamily: 'inherit',
            }}
          >
            <RefreshCw size={15} aria-hidden="true" /> RELOAD CONSOLE
          </button>
        </div>

        {/* `digest` is a server-generated hash of the real error. The message
            itself is deliberately not rendered in production builds — Next
            replaces it with a generic string precisely so a stack trace does not
            reach a screen someone else might be standing behind. The digest is
            what makes a report actionable. */}
        {error.digest && (
          <p
            style={{
              margin: '18px 0 0',
              paddingTop: 14,
              borderTop: '1px solid rgba(148, 163, 184, 0.35)',
              fontSize: 11,
              color: '#616161',
            }}
          >
            Quote this when reporting the fault: <code style={{ fontWeight: 700 }}>{error.digest}</code>
          </p>
        )}
      </div>
    </div>
  );
}
