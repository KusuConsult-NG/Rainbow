import { useState } from 'react';
import { supabase } from '@/lib/supabase';
import { Radio, Send, ShieldAlert, Loader2 } from 'lucide-react';

const TEMPLATES = [
  '[OPERATION RAINBOW]: SECURITY ALERT - A public safety incident has been reported in your area. Please stay indoors and await official guidance.',
  '[OPERATION RAINBOW]: POLLING ADVISORY - All polling operations are proceeding under heightened security. Report suspicious activity via the RainBow app.',
  '[OPERATION RAINBOW]: ALL CLEAR - The security situation in your area has been resolved. Normal activities may resume. Stay alert.',
  '[OPERATION RAINBOW]: EVACUATION NOTICE - Please move calmly to the nearest designated safe zone. Follow directions from security personnel.',
];

export default function MassBroadcast() {
  const [message, setMessage] = useState('');
  const [severity, setSeverity] = useState<'INFO' | 'WARNING' | 'CRITICAL'>('CRITICAL');
  const [sending, setSending] = useState(false);
  const [success, setSuccess] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const handleBroadcast = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!message.trim()) return;

    setSending(true);
    setSuccess(null);
    setError(null);

    try {
      const { error: insertErr } = await supabase.from('system_alerts').insert({
        message: message.trim(),
        severity,
        active: true,
      });

      if (insertErr) throw insertErr;

      setSuccess('Tactical Broadcast advisory published across all mobile app feeds!');
      setMessage('');
    } catch (err: any) {
      setError(err.message || 'Failed to send broadcast advisory');
    } finally {
      setSending(false);
    }
  };

  return (
    <div className="tactical-panel glass" style={{ padding: 28, maxWidth: 800, margin: '0 auto' }}>
      <h2 style={{ fontSize: 20, fontWeight: 900, marginBottom: 8, display: 'flex', alignItems: 'center', gap: 10, color: 'var(--text-primary)' }}>
        <Radio style={{ width: 22, height: 22, color: 'var(--primary)' }} />
        Mass Tactical Broadcast Dispatcher
      </h2>
      <p style={{ fontSize: 13, color: 'var(--text-muted)', marginBottom: 24 }}>
        Broadcast urgent tactical security advisories directly to all active mobile agent and citizen devices statewide.
      </p>

      {error && (
        <div style={{ padding: 12, background: 'var(--duress-dim)', border: '1px solid var(--duress)', borderRadius: 10, color: 'var(--duress)', marginBottom: 16, fontSize: 13 }}>
          {error}
        </div>
      )}

      {success && (
        <div style={{ padding: 12, background: 'var(--success-dim)', border: '1px solid var(--success)', borderRadius: 10, color: 'var(--success)', marginBottom: 16, fontSize: 13 }}>
          {success}
        </div>
      )}

      <form onSubmit={handleBroadcast} style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
        <div>
          <label style={{ fontSize: 11, fontWeight: 700, color: 'var(--text-muted)', display: 'block', marginBottom: 6 }}>
            Advisory Severity Level
          </label>
          <select
            className="input-tactical"
            style={{ width: '100%' }}
            value={severity}
            onChange={(e) => setSeverity(e.target.value as any)}
          >
            <option value="INFO">INFO (General Advisory)</option>
            <option value="WARNING">WARNING (Heightened Alert)</option>
            <option value="CRITICAL">CRITICAL (Emergency / Flash Alert)</option>
          </select>
        </div>

        <div>
          <label style={{ fontSize: 11, fontWeight: 700, color: 'var(--text-muted)', display: 'block', marginBottom: 6 }}>
            Quick Template Preset
          </label>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {TEMPLATES.map((t, idx) => (
              <button
                key={idx}
                type="button"
                onClick={() => setMessage(t)}
                style={{
                  textAlign: 'left',
                  padding: '10px 14px',
                  background: 'var(--input-bg)',
                  border: '1px solid var(--border)',
                  borderRadius: 10,
                  fontSize: 12,
                  color: 'var(--text-primary)',
                  cursor: 'pointer',
                }}
              >
                {t}
              </button>
            ))}
          </div>
        </div>

        <div>
          <label style={{ fontSize: 11, fontWeight: 700, color: 'var(--text-muted)', display: 'block', marginBottom: 6 }}>
            Broadcast Message Payload
          </label>
          <textarea
            required
            rows={4}
            className="input-tactical"
            style={{ width: '100%', resize: 'vertical' }}
            value={message}
            onChange={(e) => setMessage(e.target.value)}
            placeholder="Type tactical security advisory..."
          />
        </div>

        <button
          type="submit"
          disabled={sending || !message.trim()}
          className="btn-tactical btn-primary"
          style={{ padding: '14px 28px', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8 }}
        >
          {sending ? <Loader2 className="animate-spin" style={{ width: 16, height: 16 }} /> : <Send style={{ width: 16, height: 16 }} />}
          Transmit Statewide Broadcast
        </button>
      </form>
    </div>
  );
}
