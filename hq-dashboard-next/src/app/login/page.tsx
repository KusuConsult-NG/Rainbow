'use client';
import { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import { usePersistedTheme } from '@/hooks/usePersistedTheme';
import { Shield, ShieldAlert, Loader2, Eye, EyeOff, Lock, User as UserIcon, Radio, KeyRound, CheckCircle2, ArrowRight } from 'lucide-react';
import { emailForBadge } from '@/lib/staff-identity';

// Quick-fill presets are a development convenience only. They are compiled out of
// production builds so operational badge IDs and the shared demo password are never
// served from the public login page.
const SHOW_DEMO_ACCOUNTS = process.env.NODE_ENV !== 'production';

const DEMO_ACCOUNTS: { label: string; badge: string; pin: string; role: string }[] =
  SHOW_DEMO_ACCOUNTS
    ? [
        { label: 'HQ Commander', badge: 'HQ-001', pin: process.env.NEXT_PUBLIC_DEV_DEMO_PIN ?? '', role: 'State Administrator' },
        { label: 'Duty Officer', badge: 'HQ-002', pin: process.env.NEXT_PUBLIC_DEV_DEMO_PIN ?? '', role: 'Operations Dispatcher' },
        { label: 'Test Commander', badge: 'COMMANDER-TEST', pin: process.env.NEXT_PUBLIC_DEV_DEMO_PIN ?? '', role: 'Field Tactical Lead' },
      ]
    : [];


/**
 * Turn any thrown value into something an officer can act on.
 *
 * The distinction that matters on an emergency console is credentials-versus-
 * connectivity: a wrong PIN means try again, an unreachable server means fall
 * back to radio and report the outage. A raw `err.message` — "Failed to fetch",
 * "NetworkError when attempting to fetch resource" — tells the user neither.
 */
function describeAuthError(err: unknown): string {
  const raw = err instanceof Error ? err.message : String(err ?? '');
  const lower = raw.toLowerCase();

  // Transport-level: the request never got an answer from Supabase.
  if (
    lower.includes('failed to fetch') ||
    lower.includes('networkerror') ||
    lower.includes('load failed') ||
    lower.includes('err_') ||
    lower.includes('timeout') ||
    lower.includes('econnrefused')
  ) {
    return 'Cannot reach the command server. Check this terminal\u2019s connection — your credentials have not been checked.';
  }

  // Supabase's wording for a bad email/password pair.
  if (
    lower.includes('invalid login credentials') ||
    lower.includes('invalid-credential') ||
    lower.includes('invalid credentials')
  ) {
    return 'Invalid Badge ID or PIN.';
  }

  if (lower.includes('email not confirmed')) {
    return 'This account is not yet activated. Contact HQ administration.';
  }
  if (lower.includes('rate limit') || lower.includes('too many')) {
    return 'Too many attempts. Wait a minute before trying again.';
  }

  // Anything unrecognised: say so plainly rather than leaking internals.
  console.error('[LOGIN] Unclassified auth error:', raw);
  return 'Sign-in failed. If this repeats, report it to HQ administration.';
}

export default function LoginPage() {
  const [badgeId, setBadgeId] = useState('');
  const [pin, setPin] = useState('');
  const [showPin, setShowPin] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  // null = not yet probed. The banner must not claim ONLINE before it knows.
  const [reachable, setReachable] = useState<boolean | null>(null);
  const [selectedDemo, setSelectedDemo] = useState<string | null>(null);

  // The sign-in screen used to force the dark theme on, whatever the operator
  // had chosen, because it was built as a dark page with its colours written
  // into it. The app's sign-in screen is white — white ground, the emblem, two
  // fields and one red button — and this is the first thing anybody sees of
  // the console, so it is where the mismatch was loudest.
  //
  // It now takes the theme the operator chose, like every other screen. The
  // dashboard's own effect syncs the class from persisted state; removing this
  // one means signing out no longer silently flips the whole console to dark.
  const [theme] = usePersistedTheme();
  useEffect(() => {
    document.body.classList.toggle('dark-theme', theme === 'dark');
  }, [theme]);

  const handleQuickFill = (acc: typeof DEMO_ACCOUNTS[0]) => {
    setBadgeId(acc.badge);
    setPin(acc.pin);
    setSelectedDemo(acc.badge);
    setError('');
  };

  // The banner used to read "HQ COMMAND NODE · ONLINE" as a hardcoded string —
  // it said ONLINE with every backend request failing. A status light that can
  // only ever show healthy is worse than no status light, because an operator
  // reads it as information. This asks the auth endpoint whether it is actually
  // there.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        // NOT getSession(): that reads localStorage and never touches the
        // network, so it reports success against a server that is completely
        // unreachable — which is exactly the wrong answer for a status light.
        // The auth health endpoint is a real round trip and needs no session.
        const res = await fetch(
          `${process.env.NEXT_PUBLIC_SUPABASE_URL}/auth/v1/health`,
          { method: 'GET', cache: 'no-store',
            headers: { apikey: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? '' } },
        );
        if (!cancelled) setReachable(res.ok);
      } catch {
        if (!cancelled) setReachable(false);
      }
    })();
    return () => { cancelled = true; };
  }, []);

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!badgeId.trim() || !pin.trim()) {
      setError('Please provide both Badge ID and PIN / Password.');
      return;
    }
    setLoading(true);
    setError('');
    try {
      // The domain was a literal here and another one in the handset's
      // auth_service.dart. It is the second half of the primary key of a
      // person: two copies that must agree is how one officer came to have two
      // accounts on two domains, with the posting on one of them. T-99.
      const email = emailForBadge(badgeId);
      
      const { error: authErr } = await supabase.auth.signInWithPassword({
        email,
        password: pin,
      });
      if (authErr) throw authErr;

      // NOTE: do NOT hand-write a `__session` cookie here. @supabase/ssr already
      // persists the real, signed session cookies that proxy.ts verifies. The old
      // `document.cookie = '__session=true'` line was an auth bypass: it was
      // unsigned, non-HttpOnly, and the guard accepted it as proof of login.

      // Full window navigation so the proxy sees the freshly-written session cookies.
      window.location.href = '/dashboard';
    } catch (err: unknown) {
      // Never surface a raw exception message.
      //
      // This used to pass `err.message` straight through unless it happened to
      // contain 'invalid-credential'. A UI test with the backend unreachable
      // showed the operator the literal string "Failed to fetch" — a browser
      // internal. On an emergency console the one thing the user must be able
      // to tell apart is "my PIN is wrong" from "this console cannot reach the
      // server", because those need completely different responses: try again,
      // versus fall back to radio and tell someone the system is down.
      setError(describeAuthError(err));
      setReachable(false);
      setLoading(false);
    }
  };

  return (
    <div style={{
      minHeight: '100vh',
      background: 'var(--bg-primary)',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      padding: '32px 20px',
      position: 'relative',
      overflow: 'hidden',
      fontFamily: "var(--font-inter), sans-serif"
    }}>
      {/* The two blurred indigo/emerald glow orbs and the "cybernetic tech
          grid" that used to sit here are gone. The app's sign-in screen is a
          plain white field with the emblem, two fields and one red button —
          nothing ambient behind it — and this is the first screen anybody sees
          of the console. An officer who signs in on the handset and then opens
          this used to arrive somewhere that looked like a different product
          made by a different team. */}

      {/* Main Container Card */}
      <div style={{
        width: '100%',
        maxWidth: 480,
        position: 'relative',
        zIndex: 10
      }}>
        {/* Top Status Bar Badge */}
        <div style={{
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          padding: '10px 18px',
          background: 'var(--bg-secondary)',
          border: '1px solid var(--border)',
          borderBottom: 'none',
          borderRadius: '16px 16px 0 0',
          marginBottom: -1
        }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <span style={{
              width: 8,
              height: 8,
              borderRadius: '50%',
              background: reachable === false ? 'var(--duress)' : reachable === true ? 'var(--success)' : 'var(--text-dim)',
              boxShadow: 'none',
              display: 'inline-block'
            }} />
            <span style={{ fontSize: 11, fontWeight: 700, letterSpacing: 1.2, color: 'var(--text-muted)', textTransform: 'uppercase' }}>
              {reachable === false
                ? 'HQ COMMAND NODE · UNREACHABLE'
                : reachable === true
                  ? 'HQ COMMAND NODE · ONLINE'
                  : 'HQ COMMAND NODE · CHECKING…'}
            </span>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 10, color: 'var(--text-dim)', fontWeight: 600 }}>
            <Radio size={12} className="spin-slow" />
            <span>256-BIT ENCRYPTED</span>
          </div>
        </div>

        {/* Hero Card */}
        <div className="tactical-panel" style={{
          padding: '36px 32px 32px',
          background: 'var(--bg-card)',
          borderRadius: '0 0 var(--radius-card) var(--radius-card)',
          border: '1px solid var(--border)',
          boxShadow: 'var(--shadow-md)',
          position: 'relative'
        }}>
          {/* Header Brand */}
          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', marginBottom: 28 }}>
            <div style={{
              position: 'relative',
              marginBottom: 16
            }}>
              <div style={{
                width: 84,
                height: 84,
                borderRadius: 'var(--radius-card)',
                background: 'var(--primary-dim)',
                border: '1px solid var(--border)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                boxShadow: 'none',
                padding: 10
              }}>
                {/* eslint-disable-next-line @next/next/no-img-element -- a local static emblem, above the fold, with a JS fallback on error. images.unoptimized is set so next/image would serve the same bytes, and it lazy-loads by default — wrong for the first thing on the sign-in page, which would then need `priority` to undo. */}
                <img
                  src="/app_icon.png"
                  alt="Plateau Eye Emblem"
                  decoding="async" 
                  style={{ width: '100%', height: '100%', objectFit: 'contain', borderRadius: 14 }}
                  onError={(e) => {
                    e.currentTarget.style.display = 'none';
                    const fb = e.currentTarget.parentElement?.querySelector('.logo-fb');
                    if (fb) (fb as HTMLElement).style.display = 'flex';
                  }}
                />
                <div className="logo-fb" style={{ display: 'none', alignItems: 'center', justifyContent: 'center' }}>
                  <Shield size={44} color="var(--primary)" />
                </div>
              </div>
            </div>

            <h1 style={{
              fontSize: 22,
              fontWeight: 900,
              letterSpacing: 2,
              color: 'var(--text-primary)',
              textAlign: 'center',
              fontFamily: "var(--font-outfit), sans-serif",
              marginBottom: 4
            }}>
              PLATEAU EYE
            </h1>
            <p style={{
              fontSize: 11,
              fontWeight: 700,
              letterSpacing: 2.5,
              color: 'var(--text-muted)',
              textAlign: 'center',
              fontFamily: "var(--font-outfit), sans-serif",
              textTransform: 'uppercase'
            }}>
              PLATEAU STATE EARLY WARNING & RESPONSE HQ
            </p>
          </div>

          {/* Quick-Fill Demo Accounts Section — development builds only */}
          {SHOW_DEMO_ACCOUNTS && (
          <div style={{
            background: 'var(--input-bg)',
            border: '1px solid var(--border)',
            borderRadius: 'var(--radius-card)',
            padding: 14,
            marginBottom: 24
          }}>
            <div style={{
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
              marginBottom: 10
            }}>
              <span style={{ fontSize: 11, fontWeight: 700, color: 'var(--text-secondary)', display: 'flex', alignItems: 'center', gap: 6 }}>
                <KeyRound size={13} color="var(--warning)" />
                ONE-TAP QUICK LOGIN PRESETS
              </span>
              <span style={{ fontSize: 10, color: 'var(--text-dim)', fontWeight: 500 }}>Select to Auto-Fill</span>
            </div>
            
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 8 }}>
              {DEMO_ACCOUNTS.map((acc) => {
                const isActive = selectedDemo === acc.badge;
                return (
                  <button
                    key={acc.badge}
                    type="button"
                    onClick={() => handleQuickFill(acc)}
                    style={{
                      background: isActive 
                        ? 'var(--primary-dim)'
                        : 'var(--bg-secondary)',
                      border: isActive 
                        ? '1px solid var(--primary)'
                        : '1px solid var(--border)',
                      borderRadius: 10,
                      padding: '8px 6px',
                      cursor: 'pointer',
                      textAlign: 'center',
                      transition: 'all 0.2s ease',
                      boxShadow: 'none'
                    }}
                  >
                    <div style={{ fontSize: 11, fontWeight: 800, color: isActive ? 'var(--primary)' : 'var(--text-secondary)', marginBottom: 2, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 3 }}>
                      {isActive && <CheckCircle2 size={10} color="var(--success)" />}
                      {acc.label}
                    </div>
                    <div style={{ fontSize: 9, color: 'var(--text-dim)', fontWeight: 600 }}>
                      {acc.badge}
                    </div>
                  </button>
                );
              })}
            </div>
          </div>
          )}

          {/* Error Notice.
              role="alert" (an implicit assertive live region) is what makes a
              screen reader speak this the moment it appears. Without it the
              failure is purely visual: the operator hears the button click,
              nothing else happens, and there is no way to tell "wrong PIN"
              from "the console cannot reach the server". */}
          {error && (
            <div role="alert" style={{
              background: 'var(--duress-dim)',
              border: '1px solid var(--duress)',
              borderRadius: 'var(--radius-control)',
              padding: '12px 16px',
              marginBottom: 20,
              display: 'flex',
              alignItems: 'center',
              gap: 10
            }}>
              <ShieldAlert size={18} color="var(--duress)" style={{ flexShrink: 0 }} />
              <p style={{ color: 'var(--duress)', fontSize: 12, fontWeight: 700, margin: 0 }}>{error}</p>
            </div>
          )}

          {/* Login Form */}
          <form onSubmit={handleLogin} style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
            <div>
              {/* htmlFor is not decoration: without it this <label> is just
                  styled text that happens to sit above a box, and a screen
                  reader announces the field as an unnamed "edit text". */}
              <label htmlFor="badge-id" style={{
                display: 'block',
                fontSize: 11,
                color: 'var(--text-muted)',
                fontWeight: 700,
                letterSpacing: 1,
                marginBottom: 8,
                textTransform: 'uppercase'
              }}>
                Officer Badge ID / Email
              </label>
              <div style={{ position: 'relative' }}>
                <input
                  id="badge-id"
                  value={badgeId}
                  onChange={e => {
                    setBadgeId(e.target.value);
                    setSelectedDemo(null);
                  }}
                  placeholder="e.g. HQ-001 or commander@..."
                  autoComplete="username"
                  className="input-tactical"
                  style={{
                    width: '100%',
                    paddingLeft: 44,
                    height: 48,
                    background: 'var(--input-bg)',
                    border: '1px solid var(--input-border)',
                    color: 'var(--text-primary)',
                    fontSize: 14,
                    fontWeight: 600
                  }}
                />
                <UserIcon size={18} color="var(--primary)" style={{
                  position: 'absolute',
                  left: 14,
                  top: '50%',
                  transform: 'translateY(-50%)',
                  pointerEvents: 'none'
                }} />
              </div>
            </div>

            <div>
              <label htmlFor="security-pin" style={{
                display: 'block',
                fontSize: 11,
                color: 'var(--text-muted)',
                fontWeight: 700,
                letterSpacing: 1,
                marginBottom: 8,
                textTransform: 'uppercase'
              }}>
                Security PIN / Password
              </label>
              <div style={{ position: 'relative' }}>
                <input
                  id="security-pin"
                  value={pin}
                  onChange={e => {
                    setPin(e.target.value);
                    setSelectedDemo(null);
                  }}
                  type={showPin ? 'text' : 'password'}
                  placeholder="••••••••"
                  autoComplete="current-password"
                  className="input-tactical"
                  style={{
                    width: '100%',
                    paddingLeft: 44,
                    paddingRight: 48,
                    height: 48,
                    background: 'var(--input-bg)',
                    border: '1px solid var(--input-border)',
                    color: 'var(--text-primary)',
                    fontSize: 14,
                    fontWeight: 600,
                    letterSpacing: showPin ? 0 : 3
                  }}
                />
                <Lock size={18} color="var(--primary)" style={{
                  position: 'absolute',
                  left: 14,
                  top: '50%',
                  transform: 'translateY(-50%)',
                  pointerEvents: 'none'
                }} />
                {/* Icon-only, so it carries no text for assistive tech to read.
                    Without an explicit name it is announced as just "button",
                    and aria-pressed is what tells the user which state it is
                    currently in. */}
                <button
                  type="button"
                  onClick={() => setShowPin(p => !p)}
                  aria-label={showPin ? 'Hide PIN' : 'Show PIN'}
                  aria-pressed={showPin}
                  aria-controls="security-pin"
                  title={showPin ? 'Hide PIN' : 'Show PIN'}
                  style={{
                    position: 'absolute',
                    right: 14,
                    top: '50%',
                    transform: 'translateY(-50%)',
                    background: 'none',
                    border: 'none',
                    cursor: 'pointer',
                    color: 'var(--text-dim)',
                    padding: 4,
                    display: 'flex',
                    alignItems: 'center'
                  }}
                >
                  {showPin ? <EyeOff size={18} color="var(--text-secondary)" /> : <Eye size={18} color="var(--text-dim)" />}
                </button>
              </div>
            </div>

            {/* Authenticate Submit Button */}
            <button
              type="submit"
              disabled={loading}
              style={{
                width: '100%',
                height: 52,
                marginTop: 8,
                background: 'var(--primary)',
                color: '#ffffff',
                border: 'none',
                borderRadius: 'var(--radius-card)',
                fontSize: 14,
                fontWeight: 800,
                letterSpacing: 1.2,
                textTransform: 'uppercase',
                cursor: loading ? 'not-allowed' : 'pointer',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                gap: 10,
                boxShadow: 'var(--shadow-sm)',
                transition: 'all 0.2s ease',
                opacity: loading ? 0.75 : 1
              }}
            >
              {loading ? (
                <>
                  <Loader2 size={20} style={{ animation: 'spin 1s linear infinite' }} />
                  AUTHENTICATING CREDS...
                </>
              ) : (
                <>
                  AUTHENTICATE HQ ACCESS
                  <ArrowRight size={18} />
                </>
              )}
            </button>
          </form>

          {/* Footer Notice */}
          <div style={{
            marginTop: 28,
            paddingTop: 18,
            borderTop: '1px solid var(--border)',
            textAlign: 'center'
          }}>
            <p style={{
              fontSize: 10,
              color: 'var(--text-dim)',
              lineHeight: 1.6,
              fontWeight: 500
            }}>
              FOR OFFICIAL AUTHORIZED PERSONNEL ONLY · JOS, PLATEAU STATE
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}
