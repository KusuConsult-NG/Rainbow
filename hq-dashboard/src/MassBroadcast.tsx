import { useState } from 'react';
import { Target, ShieldAlert, Send } from 'lucide-react';

const TERMII_API_KEY = import.meta.env.VITE_TERMII_API_KEY || '';
const TERMII_SENDER_ID = import.meta.env.VITE_TERMII_SENDER_ID || 'RainbowHQ';

export const MassBroadcast = () => {
  const [message, setMessage] = useState('');
  const [recipients, setRecipients] = useState('');
  const [status, setStatus] = useState<null | 'sending' | 'success' | 'error'>(null);
  const [errorMsg, setErrorMsg] = useState('');

  const handleBroadcast = async () => {
    if (!message || !recipients.trim()) return;
    setStatus('sending');
    setErrorMsg('');

    const phones = recipients.split(',').map(p => p.trim()).filter(Boolean);
    let allSuccess = true;

    for (const phone of phones) {
      try {
        const res = await fetch('https://api.ng.termii.com/api/sms/send', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            to: phone,
            from: TERMII_SENDER_ID,
            sms: message,
            type: 'plain',
            api_key: TERMII_API_KEY,
            channel: 'generic',
          }),
        });
        if (!res.ok) allSuccess = false;
      } catch {
        allSuccess = false;
      }
    }

    setStatus(allSuccess ? 'success' : 'error');
    if (allSuccess) {
      setMessage('');
      setTimeout(() => setStatus(null), 3000);
    } else {
      setErrorMsg('One or more messages failed. Check Termii API key and recipient numbers.');
    }
  };

  return (
    <div style={{ padding: '32px', color: 'white', maxWidth: '800px', margin: '0 auto' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: '16px', marginBottom: '40px' }}>
        <div style={{ padding: '12px', background: 'rgba(255,255,255,0.1)', borderRadius: '12px' }}>
           <Target size={32} color="var(--accent)" />
        </div>
        <div>
          <h1 style={{ fontSize: '28px', fontWeight: 900 }}>MASS BROADCAST</h1>
          <p style={{ color: 'var(--text-muted)' }}>Termii SMS Gateway Integration</p>
        </div>
      </div>

      <div className="glass-panel" style={{ padding: '32px', borderRadius: '16px' }}>
        
        <div style={{ display: 'flex', alignItems: 'flex-start', gap: '16px', marginBottom: '24px', background: 'rgba(229, 57, 53, 0.1)', padding: '16px', borderRadius: '12px', borderLeft: '4px solid var(--accent)' }}>
          <ShieldAlert size={24} color="var(--accent)" />
          <div>
            <h4 style={{ fontSize: '13px', fontWeight: 800, color: 'white', marginBottom: '4px' }}>STATEWIDE OVERRIDE</h4>
            <p style={{ fontSize: '11px', color: 'rgba(255,255,255,0.7)', lineHeight: 1.5 }}>
              This portal utilizes the Termii CPaaS to push SMS messages to all registered citizen devices on the Plateau State database. This invokes a severe alert. Only use during critical public safety situations.
            </p>
          </div>
        </div>

        <div style={{ marginBottom: '16px' }}>
          <label style={{ display: 'block', fontSize: '11px', fontWeight: 800, color: 'var(--text-muted)', marginBottom: '8px', letterSpacing: '1px' }}>RECIPIENT PHONE NUMBERS</label>
          <input
            value={recipients}
            onChange={e => setRecipients(e.target.value)}
            placeholder="+2348034567890, +2347081234567, ..."
            style={{ width: '100%', padding: '14px', borderRadius: '8px', border: '1px solid rgba(255,255,255,0.1)', background: 'rgba(0,0,0,0.5)', color: 'white', fontFamily: 'Inter', fontSize: '13px' }}
          />
          <p style={{ fontSize: '10px', color: 'var(--text-muted)', marginTop: '6px' }}>Comma-separated international format. Loaded from Firestore citizen registry in production.</p>
        </div>

        <div style={{ marginBottom: '24px' }}>
          <label style={{ display: 'flex', justifyContent: 'space-between', fontSize: '11px', fontWeight: 800, color: 'var(--text-muted)', marginBottom: '8px', letterSpacing: '1px' }}>
            <span>BROADCAST PAYLOAD</span>
            <span style={{ color: message.length > 160 ? 'var(--accent)' : 'var(--text-muted)' }}>{message.length} / 160 CHARS</span>
          </label>
          <textarea 
            value={message}
            onChange={e => setMessage(e.target.value)}
            placeholder="[OPERATION RAINBOW]: Enter your emergency broadcast..."
            rows={5}
            style={{ width: '100%', padding: '16px', borderRadius: '8px', border: '1px solid rgba(255,255,255,0.1)', background: 'rgba(0,0,0,0.5)', color: 'white', fontFamily: 'Inter', fontSize: '14px', resize: 'none' }}
          />
        </div>

        {errorMsg && (
          <div style={{ marginBottom: '16px', padding: '12px', borderRadius: '8px', background: 'rgba(229,57,53,0.15)', border: '1px solid rgba(229,57,53,0.4)', color: '#E53935', fontSize: '12px', fontWeight: 700 }}>
            ⚠ {errorMsg}
          </div>
        )}

        <button 
          onClick={handleBroadcast}
          disabled={status === 'sending' || !message || !recipients.trim()}
          style={{ width: '100%', padding: '16px', background: status === 'success' ? '#4CAF50' : status === 'error' ? '#E53935' : 'white', color: (status === 'success' || status === 'error') ? 'white' : 'black', fontWeight: 900, border: 'none', borderRadius: '8px', cursor: (status === 'sending' || !message || !recipients.trim()) ? 'not-allowed' : 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '10px' }}>
          {status === 'sending' ? (
             <span style={{ fontSize: '14px', letterSpacing: '1px' }}>TRANSMITTING...</span>
          ) : status === 'success' ? (
             <span style={{ fontSize: '14px', letterSpacing: '1px' }}>PAYLOAD DELIVERED ✓</span>
          ) : status === 'error' ? (
             <span style={{ fontSize: '14px', letterSpacing: '1px' }}>TRANSMISSION FAILED — RETRY</span>
          ) : (
            <>
              <Send size={18} />
              <span style={{ fontSize: '14px', letterSpacing: '1px' }}>INITIATE STATEWIDE PUSH</span>
            </>
          )}
        </button>
      </div>
    </div>
  )
}
