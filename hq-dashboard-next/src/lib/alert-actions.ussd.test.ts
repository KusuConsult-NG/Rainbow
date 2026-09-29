// Standing behind a keypad report, and recording that one was a lie.
//
// These three actions go through RPCs rather than table writes, because the
// rules they enforce are ones only the database can hold: `confirm_ussd_report()`
// is SECURITY INVOKER so row-level security decides who may confirm, and it
// returns NO ROW when refused.
//
// The assertion that matters most is that an empty result is reported as a
// FAILURE. An officer told "confirmed" on a report that is still held out of the
// escalation ladder would believe the timers were running when nothing was
// chasing it at all.
import { beforeEach, describe, expect, it, vi } from 'vitest';

interface Call { fn: string; args: Record<string, unknown> }

const calls: Call[] = [];
/** What each RPC answers. Keyed by function name. */
let answers: Record<string, { data: unknown; error: unknown }> = {};

vi.mock('@/lib/supabase', () => ({
  supabase: {
    rpc: async (fn: string, args: Record<string, unknown>) => {
      calls.push({ fn, args });
      return answers[fn] ?? { data: null, error: null };
    },
  },
}));

beforeEach(() => {
  calls.length = 0;
  answers = {};
  vi.spyOn(console, 'error').mockImplementation(() => {});
});

const load = () => import('./alert-actions');

describe('confirming a keypad report', () => {
  it('calls the database and reports what was confirmed', async () => {
    answers = { confirm_ussd_report: { data: [{ confirmed: true, tier: 'UNIT' }], error: null } };
    const { confirmUssdReport } = await load();

    const res = await confirmUssdReport('a-1');

    expect(calls).toEqual([{ fn: 'confirm_ussd_report', args: { p_alert_id: 'a-1' } }]);
    expect(res.ok).toBe(true);
    if (!res.ok) return;
    expect(res.value).toEqual({ confirmed: 1, refused: 0 });
  });

  it('reports a REFUSAL as a failure, never as success', async () => {
    // No row means RLS refused, it is not a USSD report, or somebody already
    // confirmed it. Reporting that as success tells an officer the ladder is
    // running on a report that is still held back and that nothing will chase.
    answers = { confirm_ussd_report: { data: [], error: null } };
    const { confirmUssdReport } = await load();

    const res = await confirmUssdReport('a-1');

    expect(res.ok).toBe(false);
    if (res.ok) return;
    expect(res.error).toContain('Not confirmed');
    // And it says which of the two things happened, because they need different
    // actions: ask somebody who commands that area, or do nothing.
    expect(res.error).toContain('already');
  });

  it('handles null as a refusal too, not as a row', async () => {
    answers = { confirm_ussd_report: { data: null, error: null } };
    const { confirmUssdReport } = await load();
    const res = await confirmUssdReport('a-1');
    expect(res.ok).toBe(false);
  });

  it('confirms a cluster and reports the partial result', async () => {
    // A card can represent several reports of one event. Some may be outside
    // this officer's command, and the ones that ARE theirs must still go
    // through — a partial confirmation is a real outcome, not an error.
    let call = 0;
    answers = {};
    const { confirmUssdReport } = await load();
    const { supabase } = (await import('@/lib/supabase')) as unknown as {
      supabase: { rpc: (fn: string, a: Record<string, unknown>) => Promise<unknown> };
    };
    vi.spyOn(supabase, 'rpc').mockImplementation(async (fn, args) => {
      calls.push({ fn, args });
      call += 1;
      return call === 2 ? { data: [], error: null } : { data: [{ confirmed: true }], error: null };
    });

    const res = await confirmUssdReport(['a-1', 'a-2', 'a-3']);

    expect(res.ok).toBe(true);
    if (!res.ok) return;
    expect(res.value).toEqual({ confirmed: 2, refused: 1 });
  });

  it('surfaces a database error rather than swallowing it', async () => {
    answers = { confirm_ussd_report: { data: null, error: { message: 'deadlock detected' } } };
    const { confirmUssdReport } = await load();
    const res = await confirmUssdReport('a-1');
    expect(res.ok).toBe(false);
    if (res.ok) return;
    expect(res.error).toBeTruthy();
  });
});

describe('marking a report false', () => {
  it('records the note, which is what the next dispatcher reads', async () => {
    answers = { mark_false_report: { data: true, error: null } };
    const { markFalseReport } = await load();

    const res = await markFalseReport('a-1', 'rang the number, nothing happening');

    expect(calls[0].args).toEqual({
      p_alert_id: 'a-1',
      p_note: 'rang the number, nothing happening',
    });
    expect(res.ok).toBe(true);
  });

  it('fails when the database says it changed nothing', async () => {
    answers = { mark_false_report: { data: false, error: null } };
    const { markFalseReport } = await load();
    const res = await markFalseReport('a-1', 'note');
    expect(res.ok).toBe(false);
    if (res.ok) return;
    expect(res.error).toContain('not yours');
  });

  it('uses FALSE_REPORT rather than resolving or cancelling', async () => {
    // CANCELLED is a reporter standing themselves down and carries no
    // accusation. Closing a lie as CANCELLED would leave no history, and the
    // credibility signal would silently be zero for ever.
    answers = { mark_false_report: { data: true, error: null } };
    const { markFalseReport } = await load();
    await markFalseReport('a-1', 'note');
    expect(calls.map(c => c.fn)).toEqual(['mark_false_report']);
    expect(calls.map(c => c.fn)).not.toContain('resolve_alert');
  });
});

describe('reading the credibility', () => {
  const ROW = {
    first_time_caller: true,
    caller_report_count: 0,
    caller_false_reports: 0,
    caller_known_days: 0,
    callback_offered: true,
    corroborating_reports: 2,
    corroborating_numbers: 2,
  };

  it('returns the row', async () => {
    answers = { ussd_report_credibility: { data: [ROW], error: null } };
    const { ussdCredibility } = await load();
    await expect(ussdCredibility('a-1')).resolves.toEqual(ROW);
  });

  it('returns null rather than throwing when it cannot be read', async () => {
    // A card that cannot show the credibility panel must still show the
    // incident. Throwing here would take the whole board down over a panel.
    answers = { ussd_report_credibility: { data: null, error: { message: 'boom' } } };
    const { ussdCredibility } = await load();
    await expect(ussdCredibility('a-1')).resolves.toBeNull();
  });

  it('returns null for an incident with no credibility row', async () => {
    answers = { ussd_report_credibility: { data: [], error: null } };
    const { ussdCredibility } = await load();
    await expect(ussdCredibility('a-1')).resolves.toBeNull();
  });
});
