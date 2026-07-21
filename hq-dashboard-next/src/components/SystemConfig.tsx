'use client';
import { useState } from 'react';
import { Settings, Save } from 'lucide-react';

export default function SystemConfig() {
  const [thresholds, setThresholds] = useState({ POLLING_UNIT: 2, WARD: 5, LGA: 10 });
  const [msg, setMsg] = useState('');

  const saveConfig = () => {
    setMsg('Statewide tactical escalation configuration saved.');
  };

  return (
    <div className="tactical-panel glass" style={{ padding: 24, maxWidth: 600, margin: '0 auto' }}>
      <h2 style={{ fontSize: 18, fontWeight: 900, marginBottom: 16, display: 'flex', alignItems: 'center', gap: 8, color: 'var(--text-primary)' }}>
        <Settings style={{ width: 20, height: 20, color: 'var(--primary)' }} />
        Jurisdictional Escalation Config
      </h2>

      {msg && (
        <div style={{ padding: 12, background: 'var(--success-dim)', border: '1px solid var(--success)', borderRadius: 10, color: 'var(--success)', marginBottom: 16, fontSize: 13 }}>
          {msg}
        </div>
      )}

      <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
        <div>
          <label style={{ fontSize: 11, fontWeight: 700, color: 'var(--text-muted)', display: 'block', marginBottom: 6 }}>
            Polling Unit Timeout (Minutes)
          </label>
          <input
            type="number"
            className="input-tactical"
            style={{ width: '100%' }}
            value={thresholds.POLLING_UNIT}
            onChange={(e) => setThresholds({ ...thresholds, POLLING_UNIT: Number(e.target.value) })}
          />
        </div>

        <div>
          <label style={{ fontSize: 11, fontWeight: 700, color: 'var(--text-muted)', display: 'block', marginBottom: 6 }}>
            Ward Timeout (Minutes)
          </label>
          <input
            type="number"
            className="input-tactical"
            style={{ width: '100%' }}
            value={thresholds.WARD}
            onChange={(e) => setThresholds({ ...thresholds, WARD: Number(e.target.value) })}
          />
        </div>

        <div>
          <label style={{ fontSize: 11, fontWeight: 700, color: 'var(--text-muted)', display: 'block', marginBottom: 6 }}>
            LGA Timeout (Minutes)
          </label>
          <input
            type="number"
            className="input-tactical"
            style={{ width: '100%' }}
            value={thresholds.LGA}
            onChange={(e) => setThresholds({ ...thresholds, LGA: Number(e.target.value) })}
          />
        </div>

        <button
          onClick={saveConfig}
          className="btn-tactical btn-primary"
          style={{ padding: '12px 24px', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8 }}
        >
          <Save size={16} /> Save Configuration
        </button>
      </div>
    </div>
  );
}
