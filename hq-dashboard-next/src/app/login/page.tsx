'use client';
import { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import { Shield, ShieldAlert, Loader2, Eye, EyeOff, Lock, User as UserIcon, Radio, Sparkles, KeyRound, CheckCircle2, ArrowRight } from 'lucide-react';

const DEMO_ACCOUNTS = [
  { label: 'HQ Commander', badge: 'HQ-001', pin: '12345Gg!', role: 'State Administrator' },
  { label: 'Duty Officer', badge: 'HQ-002', pin: '12345Gg!', role: 'Operations Dispatcher' },
  { label: 'Test Commander', badge: 'COMMANDER-TEST', pin: '12345Gg!', role: 'Field Tactical Lead' },
];

export default function LoginPage() {
  const [badgeId, setBadgeId] = useState('');
  const [pin, setPin] = useState('');
  const [showPin, setShowPin] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
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
      
      // Set session cookie without 'Secure' attribute to support http://localhost
      document.cookie = `__session=true; path=/; max-age=86400; SameSite=Lax`;
      
      // Perform full window navigation so middleware receives the fresh session cookie
      window.location.href = '/dashboard';
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Authentication failed.';
      setError(msg.includes('invalid-credential') ? 'Invalid Badge ID or PIN.' : msg);
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
              background: '#10b981',
              boxShadow: '0 0 10px #10b981',
              display: 'inline-block'
            }} />
            <span style={{ fontSize: 11, fontWeight: 700, letterSpacing: 1.2, color: '#e2e8f0', textTransform: 'uppercase' }}>
              HQ COMMAND NODE · ONLINE
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

          {/* Quick-Fill Demo Accounts Section */}
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

          {/* Error Notice */}
          {error && (
            <div style={{
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
              <label style={{
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
              <label style={{
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
                <button
                  type="button"
                  onClick={() => setShowPin(p => !p)}
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
              FOR OFFICIAL AUTHORIZED PERSONNEL ONLY · JOS, PLATEAU STATE<br />
              <span style={{ color: '#fbbf24', fontWeight: 700 }}>
                Default Password for Demo Badges: <code>12345Gg!</code>
              </span>
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}
