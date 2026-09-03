// The payload HQ's mass broadcast actually writes.
//
// Every broadcast sent from this console failed. The insert carried six columns
// that exist in no migration (`active`, `target_sector`, `target_agency`,
// `target_lga`, `target_ward`, `target_pu`) and omitted `title`, which is
// NOT NULL — so PostgREST rejected it and the operator saw a raw error where a
// statewide warning should have been.
//
// A test that only checked "insert was called" would have passed throughout. So
// these assert the SHAPE of the row against the schema: the columns that must be
// present, and — just as important — that nothing invented is sent, because one
// unknown column rejects the whole insert.
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { makeSupabaseStub, type SupabaseStub } from '@/test/supabase-stub';

let db: SupabaseStub;

vi.mock('@/lib/supabase', () => ({
  get supabase() {
    return db.client;
  },
}));

/**
 * Every column `system_alerts` actually has, across the initial schema,
 * phase1, and 20260903000002. An insert naming anything outside this set is
 * rejected in full by PostgREST — which is precisely what used to happen.
 */
const SCHEMA_COLUMNS = new Set([
  'id', 'title', 'message', 'severity', 'target_type', 'target_value',
  'is_active', 'created_by', 'created_at',
  'target_audience', 'target_agency', 'target_lga', 'target_ward', 'target_pu',
  'expires_at',
]);

async function load() {
  return (await import('./MassBroadcast')).default;
}

async function send(message = 'Avoid Terminus junction.') {
  const MassBroadcast = await load();
  render(<MassBroadcast />);
  await userEvent.type(screen.getByRole('textbox'), message);
  await userEvent.click(screen.getByRole('button', { name: /transmit|broadcast|dispatch|send/i }));
  await waitFor(() => expect(db.inserts.length).toBeGreaterThan(0));
  return db.inserts[0].values as Record<string, unknown>;
}

describe('MassBroadcast', () => {
  beforeEach(() => {
    db = makeSupabaseStub();
    vi.useFakeTimers({ shouldAdvanceTime: true });
    vi.setSystemTime(new Date('2026-06-01T12:00:00Z'));
  });

  it('writes only columns that exist — one invented column rejects the whole insert', async () => {
    const row = await send();
    const unknown = Object.keys(row).filter(k => !SCHEMA_COLUMNS.has(k));
    expect(unknown).toEqual([]);
  });

  it('supplies title, which is NOT NULL and used to be omitted', async () => {
    const row = await send();
    expect(row.title).toBeTruthy();
    expect(String(row.title)).toContain('CRITICAL');
  });

  it('marks the advisory live under the column the apps actually filter on', async () => {
    const row = await send();
    // The mobile listener streams `.eq('is_active', true)`. The old payload set
    // `active`, which is not a column and which nothing read.
    expect(row.is_active).toBe(true);
    expect(row).not.toHaveProperty('active');
  });

  it('gives the advisory an end, so it cannot outlive the situation', async () => {
    const row = await send();
    // The default is 24 hours out. Asserted as an interval rather than an exact
    // instant: the fake clock advances with real time while the user types, so
    // pinning a millisecond would make this test flaky rather than strict.
    const expiry = Date.parse(String(row.expires_at));
    const hoursOut = (expiry - Date.now()) / 3_600_000;
    expect(hoursOut).toBeGreaterThan(23.9);
    expect(hoursOut).toBeLessThanOrEqual(24);
  });

  it('records the audience under the canonical column', async () => {
    const MassBroadcast = await load();
    render(<MassBroadcast />);
    await userEvent.type(screen.getByRole('textbox'), 'Responders only.');
    await userEvent.selectOptions(screen.getByDisplayValue(/ALL \(Citizens/i), 'AGENTS');
    await userEvent.click(screen.getByRole('button', { name: /transmit|broadcast|dispatch|send/i }));
    await waitFor(() => expect(db.inserts.length).toBeGreaterThan(0));

    const row = db.inserts[0].values as Record<string, unknown>;
    // `target_audience` is what the reader now consults. Writing the operator's
    // choice anywhere else is how "FIELD RESPONDERS ONLY" reached every citizen.
    expect(row.target_audience).toBe('AGENTS');
  });

  it('carries the geographic scope the operator selected', async () => {
    const row = await send();
    expect(row.target_lga).toBe('ALL');
    expect(row.target_ward).toBe('ALL');
    expect(row.target_pu).toBe('ALL');
  });

  it('writes to system_alerts and reports failure rather than success', async () => {
    db.setUpdateError('system_alerts', { message: 'permission denied for table system_alerts' });
    const MassBroadcast = await load();
    render(<MassBroadcast />);
    await userEvent.type(screen.getByRole('textbox'), 'Test.');
    await userEvent.click(screen.getByRole('button', { name: /transmit|broadcast|dispatch|send/i }));

    // A broadcast that silently fails is the whole reason this file exists.
    expect(await screen.findByText(/permission denied/i)).toBeInTheDocument();
  });
});
