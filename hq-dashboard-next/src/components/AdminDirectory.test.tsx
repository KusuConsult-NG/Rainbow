// Characterisation tests for AdminDirectory.
//
// Written against the ORIGINAL implementation, before the
// `react-hooks/set-state-in-effect` fix.
//
// This panel provisions officer accounts and their jurisdiction. The behaviour
// that must survive the refactor: the roster loads on mount, a successful
// creation re-reads it, and a failed creation reports the failure instead of
// looking like a success.
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { makeSupabaseStub, type SupabaseStub } from '@/test/supabase-stub';

let db: SupabaseStub;

/**
 * Provisioning is a server call now, not `supabase.auth.signUp`.
 *
 * It had to move: the old path put the chosen role in `options.data`, and
 * `handle_new_user()` copied that onto the profile — so anyone holding the anon
 * key could sign themselves up as HQ_COMMAND. The role is now decided by
 * `/api/admin/provision`, which checks who is asking. These tests therefore
 * stub `fetch` where they used to stub the auth client; what they assert about
 * the PANEL — the roster reloads on success, a failure is reported rather than
 * dressed as success — is unchanged.
 */
function stubProvision(result: { ok: boolean; body: unknown; status?: number }) {
  const spy = vi.fn(async () => ({
    ok: result.ok,
    status: result.status ?? (result.ok ? 201 : 400),
    json: async () => result.body,
  }));
  vi.stubGlobal('fetch', spy);
  return spy;
}

vi.mock('@/lib/supabase', () => ({
  get supabase() {
    return db.client;
  },
}));

const OFFICER = {
  id: 'staff-1',
  email: 'a.musa@operationrainbow.plateau.gov.ng',
  full_name: 'Insp Amina Musa',
  role: 'LGA_COMMAND',
  agency: 'RAINBOW',
  geo_lga: 'JOS SOUTH',
  created_at: '2026-07-01T08:00:00Z',
};

async function load() {
  return (await import('./AdminDirectory')).default;
}

async function fillForm() {
  await userEvent.type(screen.getByPlaceholderText('Officer Name'), 'Sgt Bala Yakubu');
  await userEvent.type(
    screen.getByPlaceholderText(/officer@operationrainbow/),
    'b.yakubu@operationrainbow.plateau.gov.ng',
  );
  await userEvent.type(screen.getByPlaceholderText('••••••••'), 'temp-pass-123');
}

describe('AdminDirectory', () => {
  beforeEach(() => {
    db = makeSupabaseStub();
  });

  it('loads the staff roster on mount', async () => {
    db.setRows('profiles', [OFFICER]);
    const AdminDirectory = await load();

    render(<AdminDirectory />);
    expect(await screen.findByText('Insp Amina Musa')).toBeInTheDocument();
    expect(db.selectCount('profiles')).toBeGreaterThan(0);
  });

  // A read failure must not take the panel down with it — the provisioning
  // form above the roster still has to work.
  it('survives a roster read that errors', async () => {
    db.setError('profiles', { message: 'permission denied' });
    const AdminDirectory = await load();

    render(<AdminDirectory />);
    expect(
      await screen.findByText(/Provision Tactical Officer Account/i),
    ).toBeInTheDocument();
  });

  it('creates an account and re-reads the roster', async () => {
    db.setRows('profiles', []);
    const provision = stubProvision({
      ok: true,
      body: { id: 'new-officer', email: 'b.yakubu@operationrainbow.plateau.gov.ng', role: 'UNIT_COMMAND' },
    });
    const AdminDirectory = await load();

    render(<AdminDirectory />);
    await waitFor(() => expect(db.selectCount('profiles')).toBeGreaterThan(0));
    const before = db.selectCount('profiles');

    await fillForm();
    await userEvent.click(screen.getByRole('button', { name: /Register|Provision|Create/i }));

    expect(await screen.findByText(/registered successfully/i)).toBeInTheDocument();
    await waitFor(() => expect(db.selectCount('profiles')).toBeGreaterThan(before));

    // The role must travel to the server, not to the database from here.
    expect(provision).toHaveBeenCalledWith(
      '/api/admin/provision',
      expect.objectContaining({ method: 'POST' }),
    );
  });

  // The whole point of moving this server-side: the browser must not be able to
  // write a role itself, whatever it puts in the form.
  it('does not try to set the role from the browser', async () => {
    db.setRows('profiles', []);
    stubProvision({ ok: true, body: { id: 'new-officer', role: 'UNIT_COMMAND' } });
    const AdminDirectory = await load();

    render(<AdminDirectory />);
    await waitFor(() => expect(db.selectCount('profiles')).toBeGreaterThan(0));

    await fillForm();
    await userEvent.click(screen.getByRole('button', { name: /Register|Provision|Create/i }));
    await screen.findByText(/registered successfully/i);

    expect(db.updates.filter((w) => w.table === 'profiles')).toHaveLength(0);
    expect(db.inserts.filter((w) => w.table === 'profiles')).toHaveLength(0);
  });

  // The failure mode that matters: a rejected sign-up that still showed the
  // green "registered successfully" banner would have an administrator believe
  // an officer can log in when they cannot.
  it('reports a failed sign-up rather than claiming success', async () => {
    db.setRows('profiles', []);
    stubProvision({ ok: false, body: { error: 'Email already registered' } });
    const AdminDirectory = await load();

    render(<AdminDirectory />);
    await waitFor(() => expect(db.selectCount('profiles')).toBeGreaterThan(0));

    await fillForm();
    await userEvent.click(screen.getByRole('button', { name: /Register|Provision|Create/i }));

    expect(await screen.findByText(/Email already registered/i)).toBeInTheDocument();
    expect(screen.queryByText(/registered successfully/i)).not.toBeInTheDocument();
  });
});
