'use client';
import { useState } from 'react';
import { signInWithEmailAndPassword } from 'firebase/auth';
import { auth } from '@/lib/firebase';
import { ShieldAlert, Loader2, Eye, EyeOff } from 'lucide-react';
import { useRouter } from 'next/navigation';

export default function LoginPage() {
  const [badgeId, setBadgeId] = useState('');
  const [pin, setPin] = useState('');
  const [showPin, setShowPin] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const router = useRouter();

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!badgeId.trim() || !pin.trim()) return;
    setLoading(true);
    setError('');
    try {
      const emailDomain = badgeId.toLowerCase().includes('@')
        ? ''
        : '@operationrainbow.plateau.gov.ng';
      await signInWithEmailAndPassword(auth, `${badgeId.toLowerCase()}${emailDomain}`, pin);
      router.replace('/dashboard');
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Authentication failed.';
      setError(msg.includes('invalid-credential') ? 'Invalid Badge ID or PIN.' : msg);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div style={{ minHeight: '100vh', background: '#000000', color: '#ffffff', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '24px' }}>
      <div className="fade-in" style={{ width: '100%', maxWidth: 420, background: 'rgba(255,255,255,0.04)', border: '1px solid rgba(255,255,255,0.08)', borderRadius: 24, padding: '48px 40px', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 0, backdropFilter: 'blur(20px)' }}>
        
        {/* Logo */}
        <div style={{ background: 'var(--accent)', padding: 18, borderRadius: '50%', marginBottom: 24, position: 'relative' }}>
          <ShieldAlert size={48} color="white" />
        </div>

        <h1 style={{ fontSize: 22, fontWeight: 900, letterSpacing: 2, marginBottom: 4, textAlign: 'center' }}>COMMAND PORTAL</h1>
        <p style={{ fontSize: 10, color: 'var(--accent)', fontWeight: 800, letterSpacing: 3, marginBottom: 40, textAlign: 'center' }}>
          OPERATION RAINBOW · HQ ACCESS
        </p>

        {error && (
          <div style={{ width: '100%', background: 'rgba(229,57,53,0.15)', border: '1px solid var(--accent)', borderRadius: 10, padding: '12px 16px', marginBottom: 24 }}>
            <p style={{ color: '#ff8a80', fontSize: 13, fontWeight: 600, textAlign: 'center' }}>{error}</p>
          </div>
        )}

        <form onSubmit={handleLogin} style={{ width: '100%', display: 'flex', flexDirection: 'column', gap: 20 }}>
          <div>
            <label style={{ display: 'block', fontSize: 10, color: 'rgba(255,255,255,0.45)', fontWeight: 800, letterSpacing: 1.5, marginBottom: 8 }}>
              ADMIN BADGE ID
            </label>
            <input
              value={badgeId}
              onChange={e => setBadgeId(e.target.value)}
              placeholder="e.g. HQ-001 or full email"
              autoComplete="username"
              style={inputStyle}
            />
          </div>
          <div>
            <label style={{ display: 'block', fontSize: 10, color: 'rgba(255,255,255,0.45)', fontWeight: 800, letterSpacing: 1.5, marginBottom: 8 }}>
              SECURE PIN / PASSWORD
            </label>
            <div style={{ position: 'relative' }}>
              <input
                value={pin}
                onChange={e => setPin(e.target.value)}
                type={showPin ? 'text' : 'password'}
                placeholder="••••••••"
                autoComplete="current-password"
                style={{ ...inputStyle, paddingRight: 48, letterSpacing: showPin ? 0 : 4 }}
              />
              <button
                type="button"
                onClick={() => setShowPin(p => !p)}
                style={{ position: 'absolute', right: 14, top: '50%', transform: 'translateY(-50%)', background: 'none', border: 'none', cursor: 'pointer', color: 'rgba(255,255,255,0.45)' }}
              >
                {showPin ? <EyeOff size={18} /> : <Eye size={18} />}
              </button>
            </div>
          </div>

          <button
            type="submit"
            disabled={loading}
            style={{
              width: '100%', padding: '16px', marginTop: 8,
              background: loading ? 'rgba(229,57,53,0.4)' : 'var(--accent)',
              color: '#ffffff', fontWeight: 900, fontSize: 13, letterSpacing: 2,
              border: 'none', borderRadius: 10, cursor: loading ? 'not-allowed' : 'pointer',
              display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 10,
              transition: 'background 0.2s',
            }}
          >
            {loading ? <><Loader2 size={18} className="spin" /> AUTHENTICATING...</> : 'AUTHENTICATE →'}
          </button>
        </form>

        <p style={{ marginTop: 32, fontSize: 10, color: 'rgba(255,255,255,0.25)', textAlign: 'center', lineHeight: 1.6 }}>
          HQ ACCESS ONLY · UNAUTHORIZED USE IS A CRIMINAL OFFENSE<br />
          ALL ACTIVITY IS LOGGED AND MONITORED
        </p>
      </div>
    </div>
  );
}

const inputStyle: React.CSSProperties = {
  width: '100%',
  padding: '14px 16px',
  background: 'rgba(255,255,255,0.06)',
  border: '1px solid rgba(255,255,255,0.1)',
  borderRadius: 10,
  color: '#ffffff',
  fontFamily: 'Inter, sans-serif',
  fontSize: 14,
  fontWeight: 600,
  outline: 'none',
};
