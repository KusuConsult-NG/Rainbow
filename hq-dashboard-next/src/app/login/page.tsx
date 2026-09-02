'use client';
import { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import { Shield, ShieldAlert, Loader2, Eye, EyeOff, Lock, User as UserIcon, Radio, Sparkles, KeyRound, CheckCircle2, ArrowRight } from 'lucide-react';

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

  useEffect(() => {
    document.body.classList.add('dark-theme');
  }, []);

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
      const emailDomain = badgeId.toLowerCase().includes('@')
        ? ''
        : '@operationrainbow.plateau.gov.ng';
      const email = `${badgeId.toLowerCase()}${emailDomain}`;
      
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
      background: 'radial-gradient(ellipse at 50% 20%, #1e1b4b 0%, #0f172a 45%, #020617 100%)',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      padding: '32px 20px',
      position: 'relative',
      overflow: 'hidden',
      fontFamily: "'Inter', sans-serif"
    }}>
      {/* Background Ambient Glow Orbs */}
      <div style={{
        position: 'absolute',
        width: '650px',
        height: '650px',
        borderRadius: '50%',
        background: 'radial-gradient(circle, rgba(99, 102, 241, 0.25) 0%, rgba(79, 70, 229, 0.08) 45%, transparent 70%)',
        top: '-15%',
        left: '20%',
        pointerEvents: 'none',
        filter: 'blur(60px)',
        animation: 'pulse 8s ease-in-out infinite alternate'
      }} />
      <div style={{
        position: 'absolute',
        width: '550px',
        height: '550px',
        borderRadius: '50%',
        background: 'radial-gradient(circle, rgba(16, 185, 129, 0.2) 0%, rgba(5, 150, 105, 0.05) 50%, transparent 70%)',
        bottom: '-10%',
        right: '15%',
        pointerEvents: 'none',
        filter: 'blur(70px)',
        animation: 'pulse 10s ease-in-out infinite alternate-reverse'
      }} />

      {/* Cybernetic Tech Grid Pattern */}
      <div style={{
        position: 'absolute',
        inset: 0,
        opacity: 0.07,
        backgroundImage: 'linear-gradient(rgba(255, 255, 255, 0.1) 1px, transparent 1px), linear-gradient(90deg, rgba(255, 255, 255, 0.1) 1px, transparent 1px)',
        backgroundSize: '40px 40px',
        pointerEvents: 'none'
      }} />

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
          background: 'rgba(15, 23, 42, 0.75)',
          backdropFilter: 'blur(16px)',
          border: '1px solid rgba(99, 102, 241, 0.3)',
          borderRadius: '16px 16px 0 0',
          marginBottom: -1
        }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <span style={{
              width: 8,
              height: 8,
              borderRadius: '50%',
              background: reachable === false ? '#ef4444' : reachable === true ? '#10b981' : '#64748b',
              boxShadow: reachable === false ? '0 0 10px #ef4444' : reachable === true ? '0 0 10px #10b981' : 'none',
              display: 'inline-block'
            }} />
            <span style={{ fontSize: 11, fontWeight: 700, letterSpacing: 1.2, color: '#e2e8f0', textTransform: 'uppercase' }}>
              {reachable === false
                ? 'HQ COMMAND NODE · UNREACHABLE'
                : reachable === true
                  ? 'HQ COMMAND NODE · ONLINE'
                  : 'HQ COMMAND NODE · CHECKING…'}
            </span>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 10, color: '#818cf8', fontWeight: 600 }}>
            <Radio size={12} className="spin-slow" />
            <span>256-BIT ENCRYPTED</span>
          </div>
        </div>

        {/* Hero Card */}
        <div className="tactical-panel" style={{
          padding: '36px 32px 32px',
          background: 'rgba(15, 23, 42, 0.82)',
          backdropFilter: 'blur(24px) saturate(200%)',
          borderRadius: '0 0 24px 24px',
          border: '1px solid rgba(99, 102, 241, 0.25)',
          boxShadow: '0 25px 60px -15px rgba(0, 0, 0, 0.8), 0 0 40px rgba(79, 70, 229, 0.25)',
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
                borderRadius: 24,
                background: 'linear-gradient(135deg, rgba(79, 70, 229, 0.3) 0%, rgba(16, 185, 129, 0.2) 100%)',
                border: '2px solid rgba(129, 140, 248, 0.4)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                boxShadow: '0 10px 30px rgba(79, 70, 229, 0.3), inset 0 0 20px rgba(255, 255, 255, 0.1)',
                padding: 10
              }}>
                <img 
                  src="/app_icon.png" 
                  alt="Operation Rainbow Emblem" 
                  style={{ width: '100%', height: '100%', objectFit: 'contain', borderRadius: 14 }}
                  onError={(e) => {
                    e.currentTarget.style.display = 'none';
                    const fb = e.currentTarget.parentElement?.querySelector('.logo-fb');
                    if (fb) (fb as HTMLElement).style.display = 'flex';
                  }}
                />
                <div className="logo-fb" style={{ display: 'none', alignItems: 'center', justifyContent: 'center' }}>
                  <Shield size={44} color="#818cf8" />
                </div>
              </div>
              <div style={{
                position: 'absolute',
                bottom: -4,
                right: -4,
                background: '#10b981',
                borderRadius: '50%',
                padding: 4,
                boxShadow: '0 0 12px #10b981'
              }}>
                <Sparkles size={12} color="#ffffff" />
              </div>
            </div>

            <h1 style={{
              fontSize: 22,
              fontWeight: 900,
              letterSpacing: 2,
              color: '#ffffff',
              textAlign: 'center',
              fontFamily: "'Outfit', sans-serif",
              marginBottom: 4,
              textShadow: '0 2px 10px rgba(0,0,0,0.5)'
            }}>
              OPERATION RAINBOW
            </h1>
            <p style={{
              fontSize: 11,
              fontWeight: 700,
              letterSpacing: 2.5,
              color: '#818cf8',
              textAlign: 'center',
              fontFamily: "'Outfit', sans-serif",
              textTransform: 'uppercase'
            }}>
              PLATEAU STATE EARLY WARNING & RESPONSE HQ
            </p>
          </div>

          {/* Quick-Fill Demo Accounts Section — development builds only */}
          {SHOW_DEMO_ACCOUNTS && (
          <div style={{
            background: 'rgba(30, 41, 59, 0.6)',
            border: '1px solid rgba(148, 163, 184, 0.15)',
            borderRadius: 16,
            padding: 14,
            marginBottom: 24
          }}>
            <div style={{
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
              marginBottom: 10
            }}>
              <span style={{ fontSize: 11, fontWeight: 700, color: '#cbd5e1', display: 'flex', alignItems: 'center', gap: 6 }}>
                <KeyRound size={13} color="#fbbf24" />
                ONE-TAP QUICK LOGIN PRESETS
              </span>
              <span style={{ fontSize: 10, color: '#94a3b8', fontWeight: 500 }}>Select to Auto-Fill</span>
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
                        ? 'linear-gradient(135deg, rgba(79, 70, 229, 0.4) 0%, rgba(99, 102, 241, 0.3) 100%)' 
                        : 'rgba(15, 23, 42, 0.7)',
                      border: isActive 
                        ? '1px solid #818cf8' 
                        : '1px solid rgba(255, 255, 255, 0.08)',
                      borderRadius: 10,
                      padding: '8px 6px',
                      cursor: 'pointer',
                      textAlign: 'center',
                      transition: 'all 0.2s ease',
                      boxShadow: isActive ? '0 0 15px rgba(99, 102, 241, 0.3)' : 'none'
                    }}
                  >
                    <div style={{ fontSize: 11, fontWeight: 800, color: isActive ? '#ffffff' : '#e2e8f0', marginBottom: 2, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 3 }}>
                      {isActive && <CheckCircle2 size={10} color="#34d399" />}
                      {acc.label}
                    </div>
                    <div style={{ fontSize: 9, color: isActive ? '#c7d2fe' : '#94a3b8', fontWeight: 600 }}>
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
              background: 'rgba(239, 68, 68, 0.15)',
              border: '1px solid rgba(239, 68, 68, 0.4)',
              borderRadius: 12,
              padding: '12px 16px',
              marginBottom: 20,
              display: 'flex',
              alignItems: 'center',
              gap: 10
            }}>
              <ShieldAlert size={18} color="#f87171" style={{ flexShrink: 0 }} />
              <p style={{ color: '#fca5a5', fontSize: 12, fontWeight: 600, margin: 0 }}>{error}</p>
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
                color: '#cbd5e1',
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
                    background: 'rgba(30, 41, 59, 0.7)',
                    border: '1px solid rgba(148, 163, 184, 0.25)',
                    color: '#ffffff',
                    fontSize: 14,
                    fontWeight: 600
                  }}
                />
                <UserIcon size={18} color="#818cf8" style={{
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
                color: '#cbd5e1',
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
                    background: 'rgba(30, 41, 59, 0.7)',
                    border: '1px solid rgba(148, 163, 184, 0.25)',
                    color: '#ffffff',
                    fontSize: 14,
                    fontWeight: 600,
                    letterSpacing: showPin ? 0 : 3
                  }}
                />
                <Lock size={18} color="#818cf8" style={{
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
                    color: '#94a3b8',
                    padding: 4,
                    display: 'flex',
                    alignItems: 'center'
                  }}
                >
                  {showPin ? <EyeOff size={18} color="#cbd5e1" /> : <Eye size={18} color="#94a3b8" />}
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
                background: 'linear-gradient(135deg, #4f46e5 0%, #3b82f6 100%)',
                color: '#ffffff',
                border: 'none',
                borderRadius: 14,
                fontSize: 14,
                fontWeight: 800,
                letterSpacing: 1.2,
                textTransform: 'uppercase',
                cursor: loading ? 'not-allowed' : 'pointer',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                gap: 10,
                boxShadow: '0 10px 25px -5px rgba(79, 70, 229, 0.5), 0 0 15px rgba(59, 130, 246, 0.3)',
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
            borderTop: '1px solid rgba(255, 255, 255, 0.08)',
            textAlign: 'center'
          }}>
            <p style={{
              fontSize: 10,
              color: '#94a3b8',
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
