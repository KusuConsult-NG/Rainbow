'use client';
import { useEffect, useState } from 'react';
import { Settings, Save, AlertTriangle, Loader2 } from 'lucide-react';
import { supabase } from '@/lib/supabase';

/**
 * The statewide escalation policy: how long an incident waits at each tier
 * before it climbs. The SQL escalation watchdog reads these three rows.
 *
 * ## The defect this closes
 *
 * The load was:
 *
 *     supabase.from('app_config').select('key, value').in('key', KEYS)
 *       .then(({ data }) => { if (data && data.length > 0) { ... } });
 *
 * `error` is destructured away. A refused or failed read left the component's
 * own seeded placeholders — 2 / 5 / 10 — on screen with nothing saying the read
 * had not happened. The component had an `error` state; only the SAVE path ever
 * set it.
 *
 * That is this repository's own rule, from the badge two hundred lines into the
 * dashboard: "A failed count must not read as zero: a badge that says nothing
 * when it could not ask is the same lie as an empty board." Here it is worse
 * than a badge, because Save **upserts all three keys**. An operator who saw
 * 2 / 5 / 10, changed one field and pressed Save replaced the live statewide
 * policy with placeholders — and the migration seeds exactly 2 / 5 / 10, so the
 * screen looked right until somebody had changed them, which is the only point
 * at which it mattered.
 *
 * Three smaller faults in the same ten lines:
 *
 *   * a key with no row merged over the placeholder, so a value that had never
 *     been configured read as though it had;
 *   * `Number(row.value)` is unchecked and the column is TEXT, so a non-numeric
 *     value became `NaN`, rendered as an empty number input, and `String(NaN)`
 *     — the literal "NaN" — is what Save would have written back;
 *   * the labels were not associated with their inputs, so a screen reader had
 *     three unlabelled number boxes on the page that sets the escalation
 *     policy.
 *
 * ## The rule
 *
 * Do not offer to save what you could not read. A baseline this form does not
 * have is a baseline it must not overwrite.
 */

interface Config {
  POLLING_UNIT: number;
  WARD: number;
  LGA: number;
}

/** Field, its `app_config` key, its label, and what the migration seeds. */
const FIELDS = [
  { field: 'POLLING_UNIT', key: 'escalation_timeout_pu', label: 'Polling Unit Timeout (Minutes)', seeded: 2 },
  { field: 'WARD', key: 'escalation_timeout_ward', label: 'Ward Timeout (Minutes)', seeded: 5 },
  { field: 'LGA', key: 'escalation_timeout_lga', label: 'LGA Timeout (Minutes)', seeded: 10 },
] as const satisfies readonly { field: keyof Config; key: string; label: string; seeded: number }[];

type Load =
  | { status: 'loading' }
  /** The policy could not be read. Nothing is shown and nothing may be saved. */
  | { status: 'failed'; reason: string }
  /** `missing` names the keys that have no row — never configured here. */
  | { status: 'ready'; missing: readonly string[] };

export default function SystemConfig() {
  const [load, setLoad] = useState<Load>({ status: 'loading' });
  const [thresholds, setThresholds] = useState<Config>({ POLLING_UNIT: 2, WARD: 5, LGA: 10 });
  const [msg, setMsg] = useState('');
  const [error, setError] = useState('');
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      const { data, error: readErr } = await supabase
        .from('app_config')
        .select('key, value')
        .in('key', FIELDS.map(f => f.key));
      if (cancelled) return;

      if (readErr) {
        setLoad({
          status: 'failed',
          reason: readErr.message || 'Could not read the escalation configuration',
        });
        return;
      }

      const stored = new Map(
        ((data ?? []) as { key: string; value: string }[]).map(r => [r.key, r.value]),
      );
      const values = {} as Config;
      const missing: string[] = [];
      const notNumeric: string[] = [];

      for (const { field, key, seeded } of FIELDS) {
        const raw = stored.get(key);
        if (raw === undefined || raw === null || String(raw).trim() === '') {
          // Never configured. The seeded value is shown so the field has
          // something to edit, and `missing` is what says it is not live.
          missing.push(key);
          values[field] = seeded;
          continue;
        }
        const parsed = Number(raw);
        if (!Number.isFinite(parsed)) {
          notNumeric.push(`${key} = "${raw}"`);
          continue;
        }
        values[field] = parsed;
      }

      if (notNumeric.length > 0) {
        // Not editable: saving would write "NaN" over it, and whatever put a
        // word in a minutes column needs a person to look at it.
        setLoad({
          status: 'failed',
          reason:
            'app_config holds a value that is not a number, so this screen '
            + `cannot show the live policy: ${notNumeric.join('; ')}`,
        });
        return;
      }

      setThresholds(values);
      setLoad({ status: 'ready', missing });
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  const saveConfig = async () => {
    // Guarded here as well as by the disabled button: this is the write that
    // replaces the statewide policy.
    if (load.status !== 'ready') return;
    setSaving(true);
    setMsg('');
    setError('');
    try {
      const rows = FIELDS.map(({ field, key }) => ({
        key,
        value: String(thresholds[field]),
        description: `${field === 'POLLING_UNIT' ? 'Polling Unit' : field} escalation timeout in minutes`,
      }));

      const { error: dbErr } = await supabase
        .from('app_config')
        .upsert(rows, { onConflict: 'key' });

      if (dbErr) throw dbErr;
      setMsg('Statewide tactical escalation configuration saved successfully.');
      setLoad({ status: 'ready', missing: [] });
    } catch (e: unknown) {
      const message = e instanceof Error ? e.message : 'Failed to save configuration';
      setError(message);
    } finally {
      setSaving(false);
    }
  };

  const banner = (
    tone: 'ok' | 'bad' | 'warn',
    body: React.ReactNode,
  ) => {
    const colours = {
      ok: { bg: 'var(--success-dim)', line: 'var(--success)', text: 'var(--success)' },
      bad: { bg: 'rgba(239,68,68,0.1)', line: '#E31E24', text: '#E31E24' },
      warn: { bg: 'rgba(245,158,11,0.12)', line: '#F59E0B', text: '#F59E0B' },
    }[tone];
    return (
      <div style={{
        padding: 12, background: colours.bg, border: `1px solid ${colours.line}`,
        borderRadius: 10, color: colours.text, marginBottom: 16, fontSize: 13,
      }}>
        {body}
      </div>
    );
  };

  return (
    <div className="tactical-panel glass" style={{ padding: 24, maxWidth: 600, margin: '0 auto' }}>
      <h2 style={{ fontSize: 18, fontWeight: 900, marginBottom: 16, display: 'flex', alignItems: 'center', gap: 8, color: 'var(--text-primary)' }}>
        <Settings style={{ width: 20, height: 20, color: 'var(--primary)' }} />
        Jurisdictional Escalation Config
      </h2>

      {msg && banner('ok', <>✓ {msg}</>)}
      {error && banner('bad', <>✗ {error}</>)}

      {load.status === 'failed' && banner('bad', (
        <div style={{ display: 'flex', gap: 8, alignItems: 'flex-start' }}>
          <AlertTriangle size={16} style={{ flexShrink: 0, marginTop: 2 }} />
          <div>
            <div style={{ fontWeight: 800, marginBottom: 4 }}>
              The live escalation policy could not be read
            </div>
            <div style={{ fontSize: 12 }}>{load.reason}</div>
            <div style={{ fontSize: 12, marginTop: 6 }}>
              Saving is disabled, because this form writes all three timeouts
              and would replace a policy it has not seen.
            </div>
          </div>
        </div>
      ))}

      {load.status === 'ready' && load.missing.length > 0 && banner('warn', (
        <div style={{ display: 'flex', gap: 8, alignItems: 'flex-start' }}>
          <AlertTriangle size={16} style={{ flexShrink: 0, marginTop: 2 }} />
          <div>
            <div style={{ fontWeight: 800, marginBottom: 4 }}>
              Not configured in this database
            </div>
            <div style={{ fontSize: 12 }}>
              {load.missing.join(', ')} — no row in <code>app_config</code>. The
              value shown is this build&apos;s default, not the live policy. Save
              to set it.
            </div>
          </div>
        </div>
      ))}

      {load.status === 'loading' ? (
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, color: 'var(--text-muted)', fontSize: 13, padding: '24px 0' }}>
          <Loader2 size={16} className="spin" /> Reading the live escalation policy...
        </div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
          {load.status === 'ready' && FIELDS.map(({ field, key, label }) => (
            <div key={key}>
              <label
                htmlFor={`cfg-${key}`}
                style={{ fontSize: 11, fontWeight: 700, color: 'var(--text-muted)', display: 'block', marginBottom: 6 }}
              >
                {label}
              </label>
              <input
                id={`cfg-${key}`}
                type="number"
                className="input-tactical"
                style={{ width: '100%' }}
                value={thresholds[field]}
                onChange={(e) => setThresholds({ ...thresholds, [field]: Number(e.target.value) })}
              />
            </div>
          ))}

          <button
            onClick={saveConfig}
            disabled={saving || load.status !== 'ready'}
            className="btn-tactical btn-primary"
            style={{ padding: '12px 24px', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, opacity: saving || load.status !== 'ready' ? 0.7 : 1 }}
          >
            <Save size={16} />
            {saving ? 'Saving...' : 'Save Configuration'}
          </button>
        </div>
      )}
    </div>
  );
}
