import { useState } from 'react';
import { plateauTacticalMap } from '@/lib/tactical_mapping';
import { collection, query, where, getDocs, addDoc, serverTimestamp } from 'firebase/firestore';
import { getFunctions, httpsCallable } from 'firebase/functions';
import { db, app } from '../lib/firebase';
import { Radio, Users, Send, ShieldAlert, Loader2, Target } from 'lucide-react';
import { getCleanBroadcastList, UserSegment } from '@/lib/broadcast-logic';

const TERMII_API_KEY = process.env.NEXT_PUBLIC_TERMII_API_KEY || '';
const TERMII_SENDER_ID = process.env.NEXT_PUBLIC_TERMII_SENDER_ID || 'N-Alert';

const GSM_ALPHABET = "@£$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ !\"#¤%&'()*+,-./:;<=>?¡ÄÖÑÜ§¿äöñüà^{}\\[~\\]|€";

const getSpecialCharacter = (text: string): string | null => {
  for (let i = 0; i < text.length; i++) {
    if (GSM_ALPHABET.indexOf(text[i]) === -1) {
      return text[i];
    }
  }
  return null;
};

const TEMPLATES = [
  '[OPERATION RAINBOW]: SECURITY ALERT - A public safety incident has been reported in your area. Please stay indoors and await official guidance.',
  '[OPERATION RAINBOW]: POLLING ADVISORY - All polling operations are proceeding under heightened security. Report suspicious activity via the RainBow app.',
  '[OPERATION RAINBOW]: ALL CLEAR - The security situation in your area has been resolved. Normal activities may resume. Stay alert.',
  '[OPERATION RAINBOW]: EVACUATION NOTICE - Please move calmly to the nearest designated safe zone. Follow directions from security personnel.',
];

export default function MassBroadcast() {
  const [message, setMessage] = useState('');
  const [recipients, setRecipients] = useState('');
  const [status, setStatus] = useState<null | 'sending' | 'success' | 'error'>(null);
  const [errorMsg, setErrorMsg] = useState('');
  const [confirmed, setConfirmed] = useState(false);
  const [targetType, setTargetType] = useState<'ALL' | 'LGA' | 'WARD' | 'PU'>('ALL');
  const [targetValue, setTargetValue] = useState('');
  const [targetLga, setTargetLga] = useState('');
  const [targetWard, setTargetWard] = useState('');
  const [audience, setAudience] = useState<UserSegment | 'all'>('all');
  const [broadcastMode, setBroadcastMode] = useState<'ALL_PUSH' | 'JURISDICTIONAL_SMS' | 'MANUAL_SMS'>('ALL_PUSH');

  const specialChar = getSpecialCharacter(message);
  const isSpecial = specialChar !== null;
  const maxLimit = isSpecial ? 75 : 160;

  // Derived Jurisdictional Data
  const lgaData = plateauTacticalMap.find(l => l.name === targetValue || l.id === targetValue);
  const wardData = lgaData?.wards.find(w => w.name === targetValue || w.id === targetValue);

  const getOptionsList = () => {
    if (targetType === 'LGA') return plateauTacticalMap.map(l => l.name);
    if (targetType === 'WARD') {
       if (targetLga) {
         return plateauTacticalMap.find(l => l.name === targetLga)?.wards.map(w => w.name) || [];
       }
       return plateauTacticalMap.flatMap(l => l.wards.map(w => w.name));
    }
    if (targetType === 'PU') {
       if (targetLga && targetWard) {
         const lga = plateauTacticalMap.find(l => l.name === targetLga);
         const ward = lga?.wards.find(w => w.name === targetWard);
         return ward?.pollingUnits || [];
       }
       if (targetLga) {
         const lga = plateauTacticalMap.find(l => l.name === targetLga);
         return lga?.wards.flatMap(w => w.pollingUnits) || [];
       }
       return plateauTacticalMap.flatMap(l => l.wards.flatMap(w => w.pollingUnits));
    }
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
          targetValue: targetType === 'ALL' ? 'STATEWIDE' : targetValue,
          targetAudience: audience
        });
      } else {
        let finalRecipients = [...phoneList];

        if (broadcastMode === 'JURISDICTIONAL_SMS') {
          const result = await getCleanBroadcastList({
            audience,
            lga: targetType === 'LGA' ? targetValue : (targetType === 'WARD' ? targetLga : undefined),
            ward: targetType === 'WARD' ? targetValue : undefined,
            pu: targetType === 'PU' ? targetValue : undefined
          });

          if (!result.success || !result.data) throw new Error(result.error || 'Failed to resolve segment.');
          
          const regionalPhones = result.data.recipients
            .map(r => r.phone)
            .filter(p => p && p.length > 5);
          
          if (regionalPhones.length === 0) throw new Error(`No registered contacts found in the selected segment.`);
          finalRecipients = regionalPhones;
        }

        if (finalRecipients.length === 0) throw new Error('No valid recipients detected.');

        // Transmit via Termii
        let successCount = 0;
        for (const phone of finalRecipients) {
          try {
            await fetch('https://api.ng.termii.com/api/sms/send', {
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
            successCount++;
          } catch (e) { console.error('SMS Fail:', phone, e); }
        }

        // Permanent Tactical Audit
        await addDoc(collection(db, 'audit_logs'), {
          action: 'MASS_BROADCAST_SMS',
          mode: broadcastMode,
          target: targetValue || 'MANUAL_LIST',
          recipient_count: successCount,
          payload: message,
          timestamp: serverTimestamp()
        });

        if (successCount === 0) throw new Error('All SMS transmissions failed.');
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

  return (
    <div style={{ maxWidth: 800 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 14, marginBottom: 32 }}>
        <div style={{ padding: 12, background: 'var(--primary-dim)', borderRadius: 12, boxShadow: 'var(--primary-glow)' }}>
          <Radio size={28} color="var(--primary)" />
        </div>
        <div>
          <h2 style={{ fontSize: 22, fontWeight: 900 }}>MASS BROADCAST</h2>
          <p style={{ fontSize: 11, color: 'var(--text-muted)' }}>Termii SMS Gateway · Tactical regional targeting · Permanent Audit</p>
        </div>
      </div>

      {/* Warning banner */}
      <div style={{ background: 'var(--warning-dim)', border: '1px solid rgba(245, 158, 11, 0.2)', borderRadius: 12, padding: '16px 20px', marginBottom: 24, display: 'flex', gap: 14, alignItems: 'flex-start' }}>
        <ShieldAlert size={22} color="var(--warning)" style={{ flexShrink: 0, marginTop: 2 }} />
        <div>
          <p style={{ fontSize: 13, fontWeight: 900, color: 'var(--warning)', marginBottom: 4 }}>STATEWIDE OVERRIDE — HIGH IMPACT</p>
          <p style={{ fontSize: 11, color: 'var(--text-secondary)', lineHeight: 1.6 }}>
            This portal uses Termii CPaaS to push SMS to all registered citizen devices in the Plateau State database.
            This is a critical action. Only authorised by HQ Command. All broadcasts are permanently logged.
          </p>
        </div>
      </div>

      <div className="tactical-panel glass" style={{ padding: 28, marginBottom: 20 }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
          <div style={{ display: 'flex', gap: 12, marginBottom: 8 }}>
            <button
              onClick={() => setBroadcastMode('ALL_PUSH')}
              className="btn-tactical"
              style={{ flex: 1, background: broadcastMode === 'ALL_PUSH' ? 'var(--primary-dim)' : 'transparent', border: `1px solid ${broadcastMode === 'ALL_PUSH' ? 'var(--primary)' : 'var(--border)'}`, color: broadcastMode === 'ALL_PUSH' ? 'var(--primary)' : 'var(--text-muted)' }}
            >
              <Users size={14} /> STATEWIDE PUSH (FCM)
            </button>
            <button
              onClick={() => setBroadcastMode('JURISDICTIONAL_SMS')}
              className="btn-tactical"
              style={{ flex: 1, background: broadcastMode === 'JURISDICTIONAL_SMS' ? 'var(--primary-dim)' : 'transparent', border: `1px solid ${broadcastMode === 'JURISDICTIONAL_SMS' ? 'var(--primary)' : 'var(--border)'}`, color: broadcastMode === 'JURISDICTIONAL_SMS' ? 'var(--primary)' : 'var(--text-muted)' }}
            >
              <ShieldAlert size={14} /> JURISDICTIONAL SMS
            </button>
            <button
              onClick={() => setBroadcastMode('MANUAL_SMS')}
              className="btn-tactical"
              style={{ flex: 1, background: broadcastMode === 'MANUAL_SMS' ? 'var(--primary-dim)' : 'transparent', border: `1px solid ${broadcastMode === 'MANUAL_SMS' ? 'var(--primary)' : 'var(--border)'}`, color: broadcastMode === 'MANUAL_SMS' ? 'var(--primary)' : 'var(--text-muted)' }}
            >
              <Radio size={14} /> MANUAL CONTACT LIST
            </button>
          </div>

          {/* Targeting Dropdowns */}
          {(broadcastMode === 'ALL_PUSH' || broadcastMode === 'JURISDICTIONAL_SMS') && (
            <>
              <div style={{ display: 'flex', gap: 12 }}>
                <div style={{ flex: 1 }}>
                  <label style={{ display: 'block', fontSize: 10, fontWeight: 800, color: 'var(--text-muted)', letterSpacing: 1.5, marginBottom: 8 }}>
                    JURISDICTION TARGET
                  </label>
                  <select
                    value={targetType}
                    onChange={e => setTargetType(e.target.value as any)}
                    className="input-tactical"
                    style={{ width: '100%' }}
                  >
                    <option value="ALL">STATEWIDE (ALL REGIONS)</option>
                    <option value="LGA">SPECIFIC LGA</option>
                    <option value="WARD">SPECIFIC WARD</option>
                    <option value="PU">SPECIFIC POLLING UNIT</option>
                  </select>
                </div>

                <div style={{ flex: 1 }}>
                  <label style={{ display: 'block', fontSize: 10, fontWeight: 800, color: 'var(--text-muted)', letterSpacing: 1.5, marginBottom: 8 }}>
                    AUDIENCE SEGMENT
                  </label>
                  <select
                    value={audience}
                    onChange={e => setAudience(e.target.value as any)}
                    className="input-tactical"
                    style={{ width: '100%' }}
                  >
                    <option value="all">ALL USERS</option>
                    <option value="hq_command">HQ COMMAND</option>
                    <option value="lga_command">LGA COMMAND</option>
                    <option value="ward_command">WARD COMMAND</option>
                    <option value="unit_command">UNIT COMMAND</option>
                    <option value="field_agents">FIELD AGENTS</option>
                    <option value="citizens">CITIZENS ONLY</option>
                  </select>
                </div>
              </div>

              <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
                {/* Step-by-step parent selectors */}
                <div style={{ display: 'flex', gap: 12 }}>
                  {(targetType === 'WARD' || targetType === 'PU') && (
                    <div style={{ flex: 1 }}>
                      <label style={{ display: 'block', fontSize: 10, fontWeight: 800, color: 'var(--text-dim)', letterSpacing: 1.5, marginBottom: 8 }}>
                        SELECT LGA
                      </label>
                      <select
                        value={targetLga}
                        onChange={e => { setTargetLga(e.target.value); setTargetWard(''); setTargetValue(''); }}
                        className="input-tactical"
                        style={{ width: '100%' }}
                      >
                        <option value="">-- Select LGA --</option>
                        {plateauTacticalMap.map(l => <option key={l.name} value={l.name}>{l.name}</option>)}
                      </select>
                    </div>
                  )}

                  {targetType === 'PU' && (
                    <div style={{ flex: 1 }}>
                      <label style={{ display: 'block', fontSize: 10, fontWeight: 800, color: 'var(--text-dim)', letterSpacing: 1.5, marginBottom: 8 }}>
                        SELECT WARD
                      </label>
                      <select
                        value={targetWard}
                        onChange={e => { setTargetWard(e.target.value); setTargetValue(''); }}
                        className="input-tactical"
                        style={{ width: '100%' }}
                        disabled={!targetLga}
                      >
                        <option value="">-- Select Ward --</option>
                        {targetLga && plateauTacticalMap.find(l => l.name === targetLga)?.wards.map(w => (
                          <option key={w.name} value={w.name}>{w.name}</option>
                        ))}
                      </select>
                    </div>
                  )}
                </div>

                {/* Primary Target Selector */}
                {targetType !== 'ALL' && (
                  <div>
                    <label style={{ display: 'block', fontSize: 10, fontWeight: 800, color: 'var(--text-dim)', letterSpacing: 1.5, marginBottom: 8 }}>
                      SELECT TARGET {targetType === 'PU' ? 'POLLING UNIT' : targetType}
                    </label>
                    <select
                      value={targetValue}
                      onChange={e => setTargetValue(e.target.value)}
                      className="input-tactical"
                      style={{ width: '100%' }}
                      disabled={(targetType === 'WARD' && !targetLga) || (targetType === 'PU' && (!targetLga || !targetWard))}
                    >
                      <option value="">-- Select {targetType === 'PU' ? 'Polling Unit' : targetType} --</option>
                      {getOptionsList().map(opt => (
                        <option key={opt} value={opt}>{opt}</option>
                      ))}
                    </select>
                  </div>
                )}
              </div>
            </>
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
                className="input-tactical"
                style={{ width: '100%' }}
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
              <span style={{ color: message.length > maxLimit ? 'var(--duress)' : 'var(--text-muted)' }}>
                {message.length} / {maxLimit}
              </span>
            </label>
            <textarea
              value={message}
              onChange={e => {
                const val = e.target.value;
                const activeSpecial = getSpecialCharacter(val) !== null;
                const activeLimit = activeSpecial ? 75 : 160;
                if (val.length > activeLimit) {
                  setMessage(val.substring(0, activeLimit));
                } else {
                  setMessage(val);
                }
              }}
              maxLength={isSpecial ? 75 : 160}
              placeholder="[OPERATION RAINBOW]: Enter broadcast message..."
              rows={5}
              className="input-tactical"
              style={{ width: '100%', resize: 'vertical' }}
            />
            {isSpecial && (
              <div style={{ 
                marginTop: 8, 
                padding: '10px 14px', 
                background: 'var(--warning-dim)', 
                border: '1px solid rgba(245, 158, 11, 0.3)', 
                borderRadius: 8,
                display: 'flex',
                alignItems: 'center',
                gap: 8
              }}>
                <ShieldAlert size={14} color="var(--warning)" style={{ flexShrink: 0 }} />
                <span style={{ fontSize: 11, color: 'var(--text-primary)', fontWeight: 700 }}>
                  Special character detected: <span style={{ color: 'var(--duress)', background: 'rgba(239,68,68,0.08)', padding: '2px 6px', borderRadius: 4, fontFamily: 'monospace', fontWeight: 900 }}>{specialChar}</span>. 
                  Termii SMS rules apply: message restricted to 1 page (75 characters max).
                </span>
              </div>
            )}
          </div>

          {/* Confirmation checkbox */}
          <label style={{ display: 'flex', alignItems: 'center', gap: 12, cursor: 'pointer', userSelect: 'none' }}>
            <input
              type="checkbox"
              checked={confirmed}
              onChange={e => setConfirmed(e.target.checked)}
              style={{ width: 18, height: 18, accentColor: 'var(--primary)', cursor: 'pointer' }}
            />
            <span style={{ fontSize: 12, fontWeight: 700, color: 'var(--text-muted)' }}>
              I confirm this broadcast is authorised by HQ Command and will be sent to all listed recipients.
            </span>
          </label>

          {errorMsg && (
            <div style={{ background: 'var(--duress-dim)', border: '1px solid rgba(239, 68, 68, 0.2)', borderRadius: 8, padding: '12px 16px' }}>
              <p style={{ fontSize: 12, fontWeight: 700, color: 'var(--duress)' }}>⚠ {errorMsg}</p>
            </div>
          )}

          {status === 'success' && (
            <div style={{ background: 'var(--success-dim)', border: '1px solid var(--success)', borderRadius: 8, padding: '12px 16px' }}>
              <p style={{ fontSize: 12, fontWeight: 700, color: 'var(--success)' }}>✓ PAYLOAD DELIVERED — Broadcast transmitted successfully.</p>
            </div>
          )}

          <button
            onClick={handleBroadcast}
            disabled={status === 'sending' || !message.trim() || message.length > maxLimit || (broadcastMode === 'MANUAL_SMS' && phoneList.length === 0) || !confirmed}
            className="btn-tactical"
            style={{
              padding: '15px',
              background: status === 'sending' || !confirmed || !message.trim() || message.length > maxLimit ? 'var(--border)' : 'var(--primary)',
              color: '#ffffff',
              boxShadow: status === 'sending' || !confirmed || !message.trim() || message.length > maxLimit ? 'none' : 'var(--primary-glow)',
              cursor: (!confirmed || !message.trim() || status === 'sending' || message.length > maxLimit) ? 'not-allowed' : 'pointer',
              width: '100%'
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
      <div className="tactical-panel glass" style={{ padding: 24 }}>
        <p style={{ fontSize: 10, fontWeight: 900, color: 'var(--text-muted)', letterSpacing: 2, marginBottom: 16 }}>APPROVED TEMPLATES</p>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          {TEMPLATES.map((t, i) => (
            <button
              key={i}
              onClick={() => setMessage(t)}
              className="card-hover"
              style={{ background: 'var(--input-bg)', border: '1px solid var(--border)', borderRadius: 10, padding: '14px 16px', color: 'var(--text-primary)', fontSize: 12, textAlign: 'left', cursor: 'pointer', fontFamily: 'Inter,sans-serif', lineHeight: 1.6, transition: 'all 0.2s' }}
            >
              {t}
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}

