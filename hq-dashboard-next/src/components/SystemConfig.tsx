'use client';
import { useState, useEffect } from 'react';
import { Settings, Save } from 'lucide-react';
import { supabase } from '@/lib/supabase';

interface Config {
  POLLING_UNIT: number;
  WARD: number;
  LGA: number;
}

export default function SystemConfig() {
  const [thresholds, setThresholds] = useState<Config>({ POLLING_UNIT: 2, WARD: 5, LGA: 10 });
  const [msg, setMsg] = useState('');
  const [error, setError] = useState('');
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    // Load existing config from DB on mount
    supabase
      .from('app_config')
      .select('key, value')
      .in('key', ['escalation_timeout_pu', 'escalation_timeout_ward', 'escalation_timeout_lga'])
      .then(({ data }) => {
        if (data && data.length > 0) {
          const cfg: Partial<Config> = {};
          data.forEach((row: { key: string; value: string }) => {
            if (row.key === 'escalation_timeout_pu') cfg.POLLING_UNIT = Number(row.value);
            if (row.key === 'escalation_timeout_ward') cfg.WARD = Number(row.value);
            if (row.key === 'escalation_timeout_lga') cfg.LGA = Number(row.value);
          });
          setThresholds((prev) => ({ ...prev, ...cfg }));
        }
      });
  }, []);

  const saveConfig = async () => {
    setSaving(true);
    setMsg('');
    setError('');
    try {
      const rows = [
        { key: 'escalation_timeout_pu', value: String(thresholds.POLLING_UNIT), description: 'Polling Unit escalation timeout in minutes' },
        { key: 'escalation_timeout_ward', value: String(thresholds.WARD), description: 'Ward escalation timeout in minutes' },
        { key: 'escalation_timeout_lga', value: String(thresholds.LGA), description: 'LGA escalation timeout in minutes' },
      ];

      const { error: dbErr } = await supabase
        .from('app_config')
        .upsert(rows, { onConflict: 'key' });

      if (dbErr) throw dbErr;
      setMsg('Statewide tactical escalation configuration saved successfully.');
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : 'Failed to save configuration';
      setError(msg);
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="tactical-panel glass" style={{ padding: 24, maxWidth: 600, margin: '0 auto' }}>
      <h2 style={{ fontSize: 18, fontWeight: 900, marginBottom: 16, display: 'flex', alignItems: 'center', gap: 8, color: 'var(--text-primary)' }}>
        <Settings style={{ width: 20, height: 20, color: 'var(--primary)' }} />
        Jurisdictional Escalation Config
      </h2>

      {msg && (
        <div style={{ padding: 12, background: 'var(--success-dim)', border: '1px solid var(--success)', borderRadius: 10, color: 'var(--success)', marginBottom: 16, fontSize: 13 }}>
          ✓ {msg}
        </div>
      )}

      {error && (
        <div style={{ padding: 12, background: 'rgba(239,68,68,0.1)', border: '1px solid #ef4444', borderRadius: 10, color: '#ef4444', marginBottom: 16, fontSize: 13 }}>
          ✗ {error}
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
          disabled={saving}
          className="btn-tactical btn-primary"
          style={{ padding: '12px 24px', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, opacity: saving ? 0.7 : 1 }}
        >
          <Save size={16} />
          {saving ? 'Saving...' : 'Save Configuration'}
        </button>
      </div>
    </div>
  );
}
