'use client';
import { useState } from 'react';
import { Radio, ShieldAlert, Send, Loader2, Users } from 'lucide-react';
import { getFunctions, httpsCallable } from 'firebase/functions';
import { app } from '../lib/firebase';

const TERMII_API_KEY = process.env.NEXT_PUBLIC_TERMII_API_KEY || '';
const TERMII_SENDER_ID = process.env.NEXT_PUBLIC_TERMII_SENDER_ID || 'RainbowHQ';

const TEMPLATES = [
  '[OPERATION RAINBOW]: SECURITY ALERT — A public safety incident has been reported in your area. Please stay indoors and await official guidance.',
  '[OPERATION RAINBOW]: POLLING ADVISORY — All polling operations are proceeding under heightened security. Report suspicious activity via the RainBow app.',
  '[OPERATION RAINBOW]: ALL CLEAR — The security situation in your area has been resolved. Normal activities may resume. Stay alert.',
  '[OPERATION RAINBOW]: EVACUATION NOTICE — Please move calmly to the nearest designated safe zone. Follow directions from security personnel.',
];

export default function MassBroadcast() {
  const [message, setMessage] = useState('');
  const [recipients, setRecipients] = useState('');
  const [status, setStatus] = useState<null | 'sending' | 'success' | 'error'>(null);
  const [errorMsg, setErrorMsg] = useState('');
  const [confirmed, setConfirmed] = useState(false);
  const [targetType, setTargetType] = useState<'ALL' | 'LGA' | 'WARD' | 'PU'>('ALL');
  const [targetValue, setTargetValue] = useState('');
  const [broadcastMode, setBroadcastMode] = useState<'ALL_PUSH' | 'MANUAL_SMS'>('ALL_PUSH');

  // Plateau State Mock Geodata for Dropdowns
  const lgaOptions = ['Jos North', 'Jos South', 'Jos East', 'Mangu', 'Barkin Ladi', 'Bokkos', 'Wase', 'Langtang North'];
  const wardOptions = ['Tudun Wada', 'Bukuru', 'Mangu Halle', 'Gashish', 'Naraguta', 'Vwang', 'Kaduna Makama'];
  const puOptions = ['PU-001', 'PU-002', 'PU-009', 'PU-014', 'PU-042', 'PU-101'];

  const getOptionsList = () => {
    if (targetType === 'LGA') return lgaOptions;
    if (targetType === 'WARD') return wardOptions;
    if (targetType === 'PU') return puOptions;
    return [];
  };

  const phoneList = recipients.split(',').map(p => p.trim()).filter(Boolean);

  const handleBroadcast = async () => {
    if (!message || !confirmed) return;
    setStatus('sending');
    setErrorMsg('');

    try {
      if (broadcastMode === 'ALL_PUSH') {
        const functions = getFunctions(app);
        const broadcastFn = httpsCallable(functions, 'massBroadcast');
        await broadcastFn({ 
          title: 'OPERATION RAINBOW ALERT', 
          body: message,
          targetType,
          targetValue: targetType === 'ALL' ? 'STATEWIDE' : targetValue
        });
      } else {
        if (phoneList.length === 0) {
          throw new Error('No valid recipients provided.');
        }
        let allOk = true;
        for (const phone of phoneList) {
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
          if (!res.ok) allOk = false;
        }
        if (!allOk) throw new Error('One or more messages failed. Verify Termii API key.');
      }

      setStatus('success');
      setMessage('');
      setRecipients('');
      setConfirmed(false);
      setTimeout(() => setStatus(null), 4000);
    } catch (err: any) {
      setStatus('error');
      setErrorMsg(err.message || 'Broadcast transmission failed.');
    }
  };

  const inp: React.CSSProperties = {
    width: '100%', padding: '13px 16px',
    background: 'rgba(0,0,0,0.06)',
    border: '1px solid rgba(0,0,0,0.1)',
    borderRadius: 10, color: 'var(--text-primary)',
    fontFamily: 'Inter,sans-serif', fontSize: 13, fontWeight: 600, outline: 'none',
  };

  return (
    <div style={{ maxWidth: 800 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 14, marginBottom: 32 }}>
        <div style={{ padding: 12, background: 'var(--accent-dim)', borderRadius: 12 }}>
          <Radio size={28} color="var(--accent)" />
        </div>
        <div>
          <h2 style={{ fontSize: 22, fontWeight: 900 }}>MASS BROADCAST</h2>
          <p style={{ fontSize: 11, color: 'var(--text-muted)' }}>Termii SMS Gateway · Statewide push to all registered citizens</p>
        </div>
      </div>

      {/* Warning banner */}
      <div style={{ background: 'var(--accent-dim)', border: '1px solid var(--accent)', borderRadius: 12, padding: '16px 20px', marginBottom: 24, display: 'flex', gap: 14, alignItems: 'flex-start' }}>
        <ShieldAlert size={22} color="var(--accent)" style={{ flexShrink: 0, marginTop: 2 }} />
        <div>
          <p style={{ fontSize: 13, fontWeight: 900, color: 'var(--accent)', marginBottom: 4 }}>STATEWIDE OVERRIDE — HIGH IMPACT</p>
          <p style={{ fontSize: 11, color: 'rgba(0,0,0,0.65)', lineHeight: 1.6 }}>
            This portal uses Termii CPaaS to push SMS to all registered citizen devices in the Plateau State database.
            This is a critical action. Only authorised by HQ Command. All broadcasts are permanently logged.
          </p>
        </div>
      </div>

      <div className="glass" style={{ borderRadius: 16, padding: 28, marginBottom: 20 }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
          <div style={{ display: 'flex', gap: 12, marginBottom: 8 }}>
            <button
              onClick={() => setBroadcastMode('ALL_PUSH')}
              style={{ flex: 1, padding: '12px', background: broadcastMode === 'ALL_PUSH' ? 'var(--accent-dim)' : 'transparent', border: `1px solid ${broadcastMode === 'ALL_PUSH' ? 'var(--accent)' : 'var(--border)'}`, borderRadius: 8, color: broadcastMode === 'ALL_PUSH' ? 'var(--accent)' : 'var(--text-muted)', fontWeight: 800, fontSize: 11, cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8 }}
            >
              <Users size={14} /> STATEWIDE PUSH NOTIFICATION (FCM)
            </button>
            <button
              onClick={() => setBroadcastMode('MANUAL_SMS')}
              style={{ flex: 1, padding: '12px', background: broadcastMode === 'MANUAL_SMS' ? 'var(--accent-dim)' : 'transparent', border: `1px solid ${broadcastMode === 'MANUAL_SMS' ? 'var(--accent)' : 'var(--border)'}`, borderRadius: 8, color: broadcastMode === 'MANUAL_SMS' ? 'var(--accent)' : 'var(--text-muted)', fontWeight: 800, fontSize: 11, cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8 }}
            >
              <Radio size={14} /> TARGETED TERMII SMS
            </button>
          </div>

          {/* Targeting Dropdowns */}
          {broadcastMode === 'ALL_PUSH' && (
            <div style={{ display: 'flex', gap: 12 }}>
              <div style={{ flex: 1 }}>
                <label style={{ display: 'block', fontSize: 10, fontWeight: 800, color: 'var(--text-muted)', letterSpacing: 1.5, marginBottom: 8 }}>
                  JURISDICTION TARGET
                </label>
                <select
                  value={targetType}
                  onChange={e => setTargetType(e.target.value as any)}
                  style={inp}
                >
                  <option value="ALL">STATEWIDE (ALL REGIONS)</option>
                  <option value="LGA">SPECIFIC LGA</option>
                  <option value="WARD">SPECIFIC WARD</option>
                  <option value="PU">SPECIFIC POLLING UNIT</option>
                </select>
              </div>
              
              {targetType !== 'ALL' && (
                <div style={{ flex: 1 }}>
                  <label style={{ display: 'block', fontSize: 10, fontWeight: 800, color: 'var(--text-muted)', letterSpacing: 1.5, marginBottom: 8 }}>
                    SELECT {targetType}
                  </label>
                  <select
                    value={targetValue}
                    onChange={e => setTargetValue(e.target.value)}
                    style={inp}
                  >
                    <option value="" disabled>-- Select {targetType} --</option>
                    {getOptionsList().map(opt => (
                      <option key={opt} value={opt}>{opt}</option>
                    ))}
                  </select>
                </div>
              )}
            </div>
          )}

          {/* Recipients */}
          {broadcastMode === 'MANUAL_SMS' && (
            <div>
              <label style={{ display: 'block', fontSize: 10, fontWeight: 800, color: 'var(--text-muted)', letterSpacing: 1.5, marginBottom: 8 }}>
                RECIPIENT PHONE NUMBERS
              </label>
              <input
                value={recipients}
                onChange={e => setRecipients(e.target.value)}
                placeholder="+2348034567890, +2347081234567, ..."
                style={inp}
              />
              <p style={{ fontSize: 10, color: 'var(--text-dim)', marginTop: 5 }}>
                Comma-separated international format. {phoneList.length > 0 && <strong style={{ color: 'var(--text-muted)' }}>{phoneList.length} recipient{phoneList.length !== 1 ? 's' : ''} detected</strong>}
              </p>
            </div>
          )}

          {/* Message */}
          <div>
            <label style={{ display: 'flex', justifyContent: 'space-between', fontSize: 10, fontWeight: 800, color: 'var(--text-muted)', letterSpacing: 1.5, marginBottom: 8 }}>
              <span>BROADCAST PAYLOAD</span>
              <span style={{ color: message.length > 160 ? 'var(--accent)' : 'var(--text-muted)' }}>{message.length} / 160</span>
            </label>
            <textarea
              value={message}
              onChange={e => setMessage(e.target.value)}
              placeholder="[OPERATION RAINBOW]: Enter broadcast message..."
              rows={5}
              style={{ ...inp, resize: 'vertical' }}
            />
          </div>

          {/* Confirmation checkbox */}
          <label style={{ display: 'flex', alignItems: 'center', gap: 12, cursor: 'pointer', userSelect: 'none' }}>
            <input
              type="checkbox"
              checked={confirmed}
              onChange={e => setConfirmed(e.target.checked)}
              style={{ width: 18, height: 18, accentColor: 'var(--accent)', cursor: 'pointer' }}
            />
            <span style={{ fontSize: 12, fontWeight: 700, color: 'var(--text-muted)' }}>
              I confirm this broadcast is authorised by HQ Command and will be sent to all listed recipients.
            </span>
          </label>

          {errorMsg && (
            <div style={{ background: 'var(--accent-dim)', border: '1px solid var(--accent)', borderRadius: 8, padding: '12px 16px' }}>
              <p style={{ fontSize: 12, fontWeight: 700, color: 'var(--accent)' }}>⚠ {errorMsg}</p>
            </div>
          )}

          {status === 'success' && (
            <div style={{ background: 'var(--success-dim)', border: '1px solid var(--success)', borderRadius: 8, padding: '12px 16px' }}>
              <p style={{ fontSize: 12, fontWeight: 700, color: 'var(--success)' }}>✓ PAYLOAD DELIVERED — Broadcast transmitted successfully.</p>
            </div>
          )}

          <button
            onClick={handleBroadcast}
            disabled={status === 'sending' || !message.trim() || (broadcastMode === 'MANUAL_SMS' && phoneList.length === 0) || !confirmed}
            style={{
              padding: '15px', background: status === 'sending' || !confirmed || !message.trim() ? 'rgba(0,0,0,0.08)' : 'var(--accent)',
              color: '#ffffff', border: 'none', borderRadius: 10, cursor: (!confirmed || !message.trim() || status === 'sending') ? 'not-allowed' : 'pointer',
              fontWeight: 900, fontSize: 13, letterSpacing: 1.5, fontFamily: 'Inter,sans-serif',
              display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 10,
            }}
          >
            {status === 'sending'
              ? <><Loader2 size={16} className="spin" /> TRANSMITTING...</>
              : <><Send size={16} /> INITIATE {broadcastMode === 'ALL_PUSH' ? 'STATEWIDE PUSH' : 'TARGETED SMS'}</>
            }
          </button>
        </div>
      </div>

      {/* Templates */}
      <div className="glass" style={{ borderRadius: 16, padding: 24 }}>
        <p style={{ fontSize: 10, fontWeight: 900, color: 'var(--text-muted)', letterSpacing: 2, marginBottom: 16 }}>APPROVED TEMPLATES</p>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          {TEMPLATES.map((t, i) => (
            <button
              key={i}
              onClick={() => setMessage(t)}
              style={{ background: 'rgba(0,0,0,0.04)', border: '1px solid var(--border)', borderRadius: 10, padding: '14px 16px', color: 'var(--text-muted)', fontSize: 12, textAlign: 'left', cursor: 'pointer', fontFamily: 'Inter,sans-serif', lineHeight: 1.6, transition: 'background 0.15s' }}
            >
              {t}
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}

