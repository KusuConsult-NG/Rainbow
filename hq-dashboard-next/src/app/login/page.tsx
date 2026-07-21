'use client';
import { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import { ShieldAlert, Loader2, Eye, EyeOff, Lock, User as UserIcon } from 'lucide-react';
import { useRouter } from 'next/navigation';

export default function LoginPage() {
  const [badgeId, setBadgeId] = useState('');
  const [pin, setPin] = useState('');
  const [showPin, setShowPin] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const router = useRouter();

  // Force dark theme on the document body for the tactical HUD aesthetic
  useEffect(() => {
    document.body.classList.add('dark-theme');
    return () => {
      // Optional cleanup, but since the entire application is dark-themed, we can keep it active
    };
  }, []);

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!badgeId.trim() || !pin.trim()) return;
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
      
      // Set session cookie for Next.js middleware compatibility in local development
      document.cookie = `__session=true; path=/; max-age=86400; SameSite=Strict; Secure`;
      router.replace('/dashboard');
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Authentication failed.';
      setError(msg.includes('invalid-credential') ? 'Invalid Badge ID or PIN.' : msg);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div style={{
      minHeight: '100vh',
      background: 'radial-gradient(circle at 50% 50%, #0d121f 0%, #05070c 100%)',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      padding: '24px',
      position: 'relative',
      overflow: 'hidden'
    }}>
      {/* Decorative High-Tech Grid Backdrop */}
      <div style={{
        position: 'absolute',
        inset: 0,
        opacity: 0.04,
        backgroundImage: 'radial-gradient(var(--text-primary) 1px, transparent 1px)',
        backgroundSize: '24px 24px',
        pointerEvents: 'none'
      }} />

      {/* Decorative Glowing Orbs */}
      <div style={{
        position: 'absolute',
        width: '500px',
        height: '500px',
        background: 'radial-gradient(circle, rgba(79, 70, 229, 0.12) 0%, transparent 70%)',
        top: '-10%',
        left: '-10%',
        pointerEvents: 'none',
        filter: 'blur(50px)'
      }} />
      <div style={{
        position: 'absolute',
        width: '500px',
        height: '500px',
        background: 'radial-gradient(circle, rgba(52, 211, 153, 0.08) 0%, transparent 70%)',
        bottom: '-10%',
        right: '-10%',
        pointerEvents: 'none',
        filter: 'blur(50px)'
      }} />

      <div className="fade-in tactical-panel glass" style={{
        width: '100%',
        maxWidth: 440,
        padding: '48px 40px',
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        position: 'relative', // essential for corner brackets placement
        boxShadow: '0 20px 50px rgba(0, 0, 0, 0.6), var(--primary-glow)',
        border: '1px solid rgba(255, 255, 255, 0.08)'
      }}>
        {/* Tactical Corner Brackets (HUD Reticle styling) */}
        <div style={{ position: 'absolute', top: -1, left: -1, width: 16, height: 16, borderTop: '2px solid var(--primary)', borderLeft: '2px solid var(--primary)', borderTopLeftRadius: 6 }} />
        <div style={{ position: 'absolute', top: -1, right: -1, width: 16, height: 16, borderTop: '2px solid var(--primary)', borderRight: '2px solid var(--primary)', borderTopRightRadius: 6 }} />
        <div style={{ position: 'absolute', bottom: -1, left: -1, width: 16, height: 16, borderBottom: '2px solid var(--primary)', borderLeft: '2px solid var(--primary)', borderBottomLeftRadius: 6 }} />
        <div style={{ position: 'absolute', bottom: -1, right: -1, width: 16, height: 16, borderBottom: '2px solid var(--primary)', borderRight: '2px solid var(--primary)', borderBottomRightRadius: 6 }} />

        {/* Official Brand Emblem with Soft Blue-Green Glow */}
        <div className="pulse-emerald" style={{
          background: 'rgba(9, 13, 22, 0.8)',
          border: '1.5px solid rgba(79, 70, 229, 0.3)',
          padding: 8,
          borderRadius: '24px',
          marginBottom: 24,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          boxShadow: 'var(--primary-glow)',
          width: 88,
          height: 88,
          overflow: 'hidden'
        }}>
          <img 
            src="/app_icon.png" 
            alt="Operation Rainbow Logo" 
            style={{ 
              width: '100%', 
              height: '100%', 
              objectFit: 'contain',
              borderRadius: '16px'
            }} 
            onError={(e) => {
              // Fallback to ShieldAlert icon if the image fails to load
              e.currentTarget.style.display = 'none';
              const fallback = e.currentTarget.parentElement?.querySelector('.fallback-icon');
              if (fallback) (fallback as HTMLElement).style.display = 'flex';
            }}
          />
          <div className="fallback-icon" style={{ display: 'none', alignItems: 'center', justifyContent: 'center', width: '100%', height: '100%' }}>
            <ShieldAlert size={36} color="var(--primary)" />
          </div>
        </div>

        <h1 style={{
          fontSize: 20,
          fontWeight: 900,
          letterSpacing: 2,
          marginBottom: 6,
          textAlign: 'center',
          color: 'var(--text-primary)',
          fontFamily: "'Outfit', sans-serif",
          textTransform: 'uppercase'
        }}>OPERATION RAINBOW</h1>
        
        <p style={{
          fontSize: 9,
          color: 'var(--primary)',
          fontWeight: 800,
          letterSpacing: 2,
          marginBottom: 36,
          textAlign: 'center',
          fontFamily: "'Outfit', sans-serif",
          textTransform: 'uppercase'
        }}>
          SECURE COMMAND PORTAL
        </p>

        {error && (
          <div style={{
            width: '100%',
            background: 'var(--duress-dim)',
            border: '1px solid rgba(248, 113, 113, 0.2)',
            borderRadius: 12,
            padding: '12px 16px',
            marginBottom: 28
          }}>
            <p style={{
              color: 'var(--duress)',
              fontSize: 13,
              fontWeight: 600,
              textAlign: 'center',
              fontFamily: "'Inter', sans-serif"
            }}>{error}</p>
          </div>
        )}

        <form onSubmit={handleLogin} style={{ width: '100%', display: 'flex', flexDirection: 'column', gap: 24 }}>
          <div>
            <label style={{
              display: 'block',
              fontSize: 10,
              color: 'var(--text-muted)',
              fontWeight: 800,
              letterSpacing: 1.5,
              marginBottom: 10,
              fontFamily: "'Outfit', sans-serif"
            }}>
              ADMIN BADGE ID
            </label>
            <div style={{ position: 'relative' }}>
              <input
                value={badgeId}
                onChange={e => setBadgeId(e.target.value)}
                placeholder="e.g. HQ-001"
                autoComplete="username"
                className="input-tactical"
                style={{ width: '100%', paddingLeft: 44 }}
              />
              <UserIcon size={16} color="var(--text-dim)" style={{
                position: 'absolute',
                left: 16,
                top: '50%',
                transform: 'translateY(-50%)',
                pointerEvents: 'none'
              }} />
            </div>
          </div>
          
          <div>
            <label style={{
              display: 'block',
              fontSize: 10,
              color: 'var(--text-muted)',
              fontWeight: 800,
              letterSpacing: 1.5,
              marginBottom: 10,
              fontFamily: "'Outfit', sans-serif"
            }}>
              SECURE PIN / PASSWORD
            </label>
            <div style={{ position: 'relative' }}>
              <input
                value={pin}
                onChange={e => setPin(e.target.value)}
                type={showPin ? 'text' : 'password'}
                placeholder="••••••••"
                autoComplete="current-password"
                className="input-tactical"
                style={{
                  width: '100%',
                  paddingLeft: 44,
                  paddingRight: 48,
                  letterSpacing: showPin ? 0 : 4
                }}
              />
              <Lock size={16} color="var(--text-dim)" style={{
                position: 'absolute',
                left: 16,
                top: '50%',
                transform: 'translateY(-50%)',
                pointerEvents: 'none'
              }} />
              <button
                type="button"
                onClick={() => setShowPin(p => !p)}
                style={{
                  position: 'absolute',
                  right: 16,
                  top: '50%',
                  transform: 'translateY(-50%)',
                  background: 'none',
                  border: 'none',
                  cursor: 'pointer',
                  color: 'var(--text-dim)',
                  display: 'flex',
                  alignItems: 'center'
                }}
              >
                {showPin ? <EyeOff size={18} /> : <Eye size={18} />}
              </button>
            </div>
          </div>

          <button
            type="submit"
            disabled={loading}
            className="btn-tactical btn-primary"
            style={{
              width: '100%',
              padding: '16px',
              marginTop: 12,
              opacity: loading ? 0.7 : 1,
              cursor: loading ? 'not-allowed' : 'pointer',
            }}
          >
            {loading ? (
              <>
                <Loader2 size={18} className="spin" />
                Authenticating...
              </>
            ) : (
              'Authenticate'
            )}
          </button>
        </form>

        <p style={{
          marginTop: 32,
          fontSize: 9,
          color: 'var(--text-dim)',
          textAlign: 'center',
          lineHeight: 1.6,
          fontFamily: "'Inter', sans-serif",
          letterSpacing: 1,
          textTransform: 'uppercase'
        }}>
          HQ ACCESS ONLY · UNAUTHORIZED USE IS A CRIMINAL OFFENSE<br />
          <span style={{ color: 'var(--duress)', fontWeight: 700, letterSpacing: 1.5 }}>
            ALL SYSTEM ACTIVITY IS LOGGED AND MONITORED
          </span>
        </p>
      </div>
    </div>
  );
}
