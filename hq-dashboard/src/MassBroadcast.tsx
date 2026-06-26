import { useState } from 'react';
import { Target, ShieldAlert, Send } from 'lucide-react';
import { collection, query, where, getDocs } from 'firebase/firestore';
import { db } from './firebase';

const TERMII_API_KEY = import.meta.env.VITE_TERMII_API_KEY || '';
const TERMII_SENDER_ID = import.meta.env.VITE_TERMII_SENDER_ID || 'N-Alert';

export const MassBroadcast = () => {
  const [message, setMessage] = useState('');
  const [targetType, setTargetType] = useState<'MANUAL' | 'STATEWIDE' | 'WARD'>('MANUAL');
  const [targetSiecWard, setTargetSiecWard] = useState('');
  const [recipients, setRecipients] = useState('');
  const [status, setStatus] = useState<null | 'fetching' | 'sending' | 'success' | 'error'>(null);
  const [errorMsg, setErrorMsg] = useState('');

  const handleBroadcast = async () => {
    if (!message) return;
    if (targetType === 'MANUAL' && !recipients.trim()) return;
    
    setStatus('fetching');
    setErrorMsg('');

    let phones: string[] = [];

    if (targetType === 'MANUAL') {
      phones = recipients.split(',').map(p => p.trim()).filter(Boolean);
    } else {
      try {
        let q;
        if (targetType === 'STATEWIDE') {
          q = query(collection(db, 'users'));
        } else if (targetType === 'WARD' && targetSiecWard.trim()) {
          q = query(collection(db, 'users'), where('geo_siec_ward', '==', targetSiecWard.trim()));
        } else {
          setErrorMsg('Please specify a SIEC Ward ID');
          setStatus(null);
          return;
        }

        const snap = await getDocs(q);
        snap.forEach(doc => {
          const data = doc.data();
          if (data.phone) {
            phones.push(data.phone);
          } else if (data.phoneNumber) {
            phones.push(data.phoneNumber);
          }
        });

        phones = Array.from(new Set(phones));

        if (phones.length === 0) {
          setErrorMsg('No citizens found for this target area.');
          setStatus(null);
          return;
        }
      } catch (err) {
        console.error(err);
        setErrorMsg('Failed to query citizen database.');
        setStatus(null);
        return;
      }
    }

    setStatus('sending');

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
            channel: 'dnd',
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
      if (targetType === 'MANUAL') setRecipients('');
      setTimeout(() => setStatus(null), 3000);
    } else {
      setErrorMsg(`One or more messages failed. Processed ${phones.length} numbers.`);
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

        <div style={{ marginBottom: '24px' }}>
          <label style={{ display: 'block', fontSize: '11px', fontWeight: 800, color: 'var(--text-muted)', marginBottom: '8px', letterSpacing: '1px' }}>TARGETING MODE</label>
          <div style={{ display: 'flex', gap: '8px' }}>
            {['MANUAL', 'STATEWIDE', 'WARD'].map((type) => (
              <button 
                key={type}
                onClick={() => setTargetType(type as any)}
                style={{ 
                  flex: 1, padding: '12px', borderRadius: '8px', border: '1px solid', 
                  borderColor: targetType === type ? 'var(--accent)' : 'rgba(255,255,255,0.1)',
                  background: targetType === type ? 'rgba(229, 57, 53, 0.1)' : 'rgba(0,0,0,0.5)',
                  color: targetType === type ? 'white' : 'var(--text-muted)',
                  fontWeight: 800, fontSize: '11px', cursor: 'pointer'
                }}
              >
                {type}
              </button>
            ))}
          </div>
        </div>

        {targetType === 'MANUAL' && (
          <div style={{ marginBottom: '16px' }}>
            <label style={{ display: 'block', fontSize: '11px', fontWeight: 800, color: 'var(--text-muted)', marginBottom: '8px', letterSpacing: '1px' }}>RECIPIENT PHONE NUMBERS</label>
            <input
              value={recipients}
              onChange={e => setRecipients(e.target.value)}
              placeholder="+2348034567890, +2347081234567, ..."
              style={{ width: '100%', padding: '14px', borderRadius: '8px', border: '1px solid rgba(255,255,255,0.1)', background: 'rgba(0,0,0,0.5)', color: 'white', fontFamily: 'Inter', fontSize: '13px' }}
            />
            <p style={{ fontSize: '10px', color: 'var(--text-muted)', marginTop: '6px' }}>Comma-separated international format.</p>
          </div>
        )}

        {targetType === 'WARD' && (
          <div style={{ marginBottom: '16px' }}>
            <label style={{ display: 'block', fontSize: '11px', fontWeight: 800, color: 'var(--text-muted)', marginBottom: '8px', letterSpacing: '1px' }}>SIEC WARD IDENTIFIER</label>
            <input
              value={targetSiecWard}
              onChange={e => setTargetSiecWard(e.target.value)}
              placeholder="e.g. JOS_NORTH_01"
              style={{ width: '100%', padding: '14px', borderRadius: '8px', border: '1px solid rgba(255,255,255,0.1)', background: 'rgba(0,0,0,0.5)', color: 'white', fontFamily: 'Inter', fontSize: '13px' }}
            />
            <p style={{ fontSize: '10px', color: 'var(--text-muted)', marginTop: '6px' }}>Exact match with SIEC database identifier.</p>
          </div>
        )}

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
          disabled={status === 'sending' || status === 'fetching' || !message || (targetType === 'MANUAL' && !recipients.trim()) || (targetType === 'WARD' && !targetSiecWard.trim())}
          style={{ width: '100%', padding: '16px', background: status === 'success' ? '#4CAF50' : status === 'error' ? '#E53935' : 'white', color: (status === 'success' || status === 'error') ? 'white' : 'black', fontWeight: 900, border: 'none', borderRadius: '8px', cursor: (status === 'sending' || status === 'fetching' || !message) ? 'not-allowed' : 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '10px' }}>
          {status === 'fetching' ? (
             <span style={{ fontSize: '14px', letterSpacing: '1px' }}>RESOLVING TARGETS...</span>
          ) : status === 'sending' ? (
             <span style={{ fontSize: '14px', letterSpacing: '1px' }}>TRANSMITTING...</span>
          ) : status === 'success' ? (
             <span style={{ fontSize: '14px', letterSpacing: '1px' }}>PAYLOAD DELIVERED ✓</span>
          ) : status === 'error' ? (
             <span style={{ fontSize: '14px', letterSpacing: '1px' }}>TRANSMISSION FAILED — RETRY</span>
          ) : (
            <>
              <Send size={18} />
              <span style={{ fontSize: '14px', letterSpacing: '1px' }}>INITIATE PUSH</span>
            </>
          )}
        </button>
      </div>
    </div>
  )
}
