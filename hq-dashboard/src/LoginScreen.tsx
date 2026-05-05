import React, { useState } from 'react';
import { signInWithEmailAndPassword } from 'firebase/auth';
import { auth } from './firebase';
import { ShieldAlert, Loader2 } from 'lucide-react';
import { useNavigate } from 'react-router-dom';

export const LoginScreen = () => {
  const [badgeId, setBadgeId] = useState('');
  const [pin, setPin] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const navigate = useNavigate();

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!badgeId || !pin) return;
    
    setLoading(true);
    setError('');

    try {
      // Format badge input into our internal firebase email format
      const emailDomain = badgeId.toLowerCase().includes('@') ? '' : '@operationrainbow.plateau.gov.ng';
      const formattedEmail = `${badgeId.toLowerCase()}${emailDomain}`;
      
      await signInWithEmailAndPassword(auth, formattedEmail, pin);
      navigate('/');
    } catch (err: any) {
      setError(err.message || 'Verification failed. Invalid credentials.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div style={{ display: 'flex', height: '100vh', width: '100vw', background: 'var(--bg-primary)', alignItems: 'center', justifyContent: 'center' }}>
      <div className="glass-panel" style={{ width: '400px', padding: '48px', borderRadius: '24px', display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
        
        <div style={{ background: 'var(--accent)', padding: '16px', borderRadius: '50%', marginBottom: '24px' }}>
          <ShieldAlert size={48} color="white" />
        </div>
        
        <h1 style={{ fontSize: '24px', fontWeight: 900, letterSpacing: '2px', marginBottom: '8px', color: 'white' }}>COMMAND PORTAL</h1>
        <p style={{ fontSize: '11px', color: 'var(--accent)', fontWeight: 800, letterSpacing: '2px', marginBottom: '40px' }}>OPERATION RAINBOW HQ</p>

        {error && (
          <div style={{ width: '100%', padding: '12px', background: 'rgba(229, 57, 53, 0.2)', border: '1px solid var(--accent)', borderRadius: '8px', marginBottom: '24px' }}>
            <p style={{ color: '#ff8a80', fontSize: '12px', fontWeight: 600, textAlign: 'center' }}>{error}</p>
          </div>
        )}

        <form onSubmit={handleLogin} style={{ width: '100%', display: 'flex', flexDirection: 'column', gap: '20px' }}>
          <div>
            <label style={{ display: 'block', fontSize: '10px', color: 'var(--text-muted)', fontWeight: 800, letterSpacing: '1px', marginBottom: '8px' }}>ADMIN BADGE ID</label>
            <input 
              value={badgeId} 
              onChange={e => setBadgeId(e.target.value)}
              placeholder="e.g. HQ-001"
              style={{ width: '100%', padding: '14px', borderRadius: '8px', border: '1px solid rgba(255,255,255,0.1)', background: 'rgba(0,0,0,0.5)', color: 'white', fontFamily: 'Inter', fontSize: '14px', fontWeight: 600 }}
            />
          </div>

          <div>
            <label style={{ display: 'block', fontSize: '10px', color: 'var(--text-muted)', fontWeight: 800, letterSpacing: '1px', marginBottom: '8px' }}>SECURE PIN</label>
            <input 
              value={pin} 
              onChange={e => setPin(e.target.value)}
              type="password"
              placeholder="••••••"
              style={{ width: '100%', padding: '14px', borderRadius: '8px', border: '1px solid rgba(255,255,255,0.1)', background: 'rgba(0,0,0,0.5)', color: 'white', fontFamily: 'Inter', fontSize: '18px', letterSpacing: '4px' }}
            />
          </div>

          <button 
            type="submit" 
            disabled={loading}
            style={{ 
              width: '100%', padding: '16px', background: 'var(--accent)', color: 'white', 
              fontWeight: 900, fontSize: '14px', letterSpacing: '1px', border: 'none', 
              borderRadius: '8px', cursor: loading ? 'not-allowed' : 'pointer', marginTop: '12px',
              display: 'flex', justifyContent: 'center'
            }}
          >
            {loading ? <Loader2 size={18} className="spin" style={{ animation: 'spin 1s linear infinite' }} /> : 'AUTHENTICATE'}
          </button>
        </form>
      </div>

      <style>
        {`
          @keyframes spin { 100% { transform: rotate(360deg); } }
        `}
      </style>
    </div>
  );
};
