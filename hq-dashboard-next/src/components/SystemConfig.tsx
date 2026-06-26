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

  return (
    <div style={{ padding: '8px 0', maxWidth: 600 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 14, marginBottom: 32 }}>
        <div style={{ padding: 12, background: 'var(--primary-dim)', borderRadius: 12, boxShadow: 'var(--primary-glow)' }}>
          <Settings size={28} color="var(--primary)" />
        </div>
        <div>
          <h2 style={{ fontSize: 22, fontWeight: 900 }}>SYSTEM CONFIGURATION</h2>
          <p style={{ fontSize: 11, color: 'var(--text-muted)' }}>Manage global platform rules and escalation timings</p>
        </div>
      </div>

      <div className="tactical-panel glass" style={{ padding: 24 }}>
        <h3 style={{ fontSize: 13, fontWeight: 900, marginBottom: 22, borderBottom: '1px solid var(--border)', paddingBottom: 12 }}>
          ESCALATION THRESHOLDS (MINUTES)
        </h3>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
          <div>
            <label style={{ display: 'block', fontSize: 10, fontWeight: 800, color: 'var(--text-muted)', letterSpacing: 1.2, marginBottom: 6 }}>
              POLLING UNIT TIMEOUT
            </label>
            <input type="number" value={thresholds.POLLING_UNIT} onChange={e => setThresholds({...thresholds, POLLING_UNIT: parseInt(e.target.value) || 0})} className="input-tactical" style={{ width: '100%' }} />
          </div>
          <div>
            <label style={{ display: 'block', fontSize: 10, fontWeight: 800, color: 'var(--text-muted)', letterSpacing: 1.2, marginBottom: 6 }}>
              WARD TIMEOUT
            </label>
            <input type="number" value={thresholds.WARD} onChange={e => setThresholds({...thresholds, WARD: parseInt(e.target.value) || 0})} className="input-tactical" style={{ width: '100%' }} />
          </div>
          <div>
            <label style={{ display: 'block', fontSize: 10, fontWeight: 800, color: 'var(--text-muted)', letterSpacing: 1.2, marginBottom: 6 }}>
              LGA TIMEOUT
            </label>
            <input type="number" value={thresholds.LGA} onChange={e => setThresholds({...thresholds, LGA: parseInt(e.target.value) || 0})} className="input-tactical" style={{ width: '100%' }} />
          </div>

          <button onClick={saveConfig} disabled={saving}
            className="btn-tactical"
            style={{
              padding: '13px',
              background: saving ? 'var(--border)' : 'var(--primary)',
              color: '#ffffff',
              boxShadow: saving ? 'none' : 'var(--primary-glow)',
              cursor: saving ? 'not-allowed' : 'pointer',
              width: '100%',
              marginTop: 12
            }}
          >
            {saving ? <><Loader2 size={14} className="spin" /> SAVING...</> : <><Save size={14} /> SAVE CONFIGURATION</>}
          </button>

          {msg && <p style={{ fontSize: 11, fontWeight: 800, color: msg.includes('Error') ? 'var(--duress)' : 'var(--success)', textAlign: 'center', marginTop: 8 }}>{msg}</p>}
        </div>
      </div>
    </div>
  );
}
