'use client';
import { useState, useEffect } from 'react';
import { doc, getDoc, setDoc } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { Settings, Save, Loader2 } from 'lucide-react';

export default function SystemConfig() {
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [thresholds, setThresholds] = useState({ POLLING_UNIT: 2, WARD: 5, LGA: 10 });
  const [msg, setMsg] = useState('');

  useEffect(() => {
    const fetchConfig = async () => {
      const d = await getDoc(doc(db, 'system', 'config'));
      if (d.exists() && d.data().escalation_thresholds) {
        setThresholds(d.data().escalation_thresholds);
      }
      setLoading(false);
    };
    fetchConfig();
  }, []);

  const saveConfig = async () => {
    setSaving(true);
    setMsg('');
    try {
      await setDoc(doc(db, 'system', 'config'), { escalation_thresholds: thresholds }, { merge: true });
      setMsg('Configuration saved successfully.');
    } catch (e: any) {
      setMsg('Error saving configuration: ' + e.message);
    }
    setSaving(false);
  };

  if (loading) return <div style={{ padding: 24 }}>Loading system configuration...</div>;

  const s: React.CSSProperties = {
    width: '100%', padding: '12px 14px',
    background: 'rgba(0,0,0,0.06)',
    border: '1px solid rgba(0,0,0,0.1)',
    borderRadius: 10, color: 'var(--text-primary)',
    fontFamily: 'Inter,sans-serif', fontSize: 13, fontWeight: 600, outline: 'none',
  };

  return (
    <div style={{ padding: '8px 0', maxWidth: 600 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 14, marginBottom: 32 }}>
        <div style={{ padding: 12, background: 'rgba(0,0,0,0.06)', borderRadius: 12 }}>
          <Settings size={28} color="var(--accent)" />
        </div>
        <div>
          <h2 style={{ fontSize: 22, fontWeight: 900 }}>SYSTEM CONFIGURATION</h2>
          <p style={{ fontSize: 11, color: 'var(--text-muted)' }}>Manage global platform rules and escalation timings</p>
        </div>
      </div>

      <div className="glass" style={{ borderRadius: 16, padding: 24 }}>
        <h3 style={{ fontSize: 13, fontWeight: 900, marginBottom: 22, borderBottom: '1px solid var(--border)', paddingBottom: 12 }}>
          ESCALATION THRESHOLDS (MINUTES)
        </h3>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
          <div>
            <label style={{ display: 'block', fontSize: 10, fontWeight: 800, color: 'var(--text-muted)', letterSpacing: 1.2, marginBottom: 6 }}>
              POLLING UNIT TIMEOUT
            </label>
            <input type="number" value={thresholds.POLLING_UNIT} onChange={e => setThresholds({...thresholds, POLLING_UNIT: parseInt(e.target.value) || 0})} style={s} />
          </div>
          <div>
            <label style={{ display: 'block', fontSize: 10, fontWeight: 800, color: 'var(--text-muted)', letterSpacing: 1.2, marginBottom: 6 }}>
              WARD TIMEOUT
            </label>
            <input type="number" value={thresholds.WARD} onChange={e => setThresholds({...thresholds, WARD: parseInt(e.target.value) || 0})} style={s} />
          </div>
          <div>
            <label style={{ display: 'block', fontSize: 10, fontWeight: 800, color: 'var(--text-muted)', letterSpacing: 1.2, marginBottom: 6 }}>
              LGA TIMEOUT
            </label>
            <input type="number" value={thresholds.LGA} onChange={e => setThresholds({...thresholds, LGA: parseInt(e.target.value) || 0})} style={s} />
          </div>

          <button onClick={saveConfig} disabled={saving}
            style={{ padding: '13px', background: saving ? 'rgba(0,0,0,0.1)' : 'var(--accent)', color: '#ffffff', border: 'none', borderRadius: 10, cursor: saving ? 'not-allowed' : 'pointer', fontWeight: 900, fontSize: 12, letterSpacing: 1.5, fontFamily: 'Inter,sans-serif', marginTop: 12, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8 }}>
            {saving ? <><Loader2 size={14} className="spin" /> SAVING...</> : <><Save size={14} /> SAVE CONFIGURATION</>}
          </button>

          {msg && <p style={{ fontSize: 11, fontWeight: 800, color: msg.includes('Error') ? 'var(--accent)' : 'var(--success)', textAlign: 'center', marginTop: 8 }}>{msg}</p>}
        </div>
      </div>
    </div>
  );
}
