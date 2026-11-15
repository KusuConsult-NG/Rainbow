// Characterisation tests for AgencyAccessManager.
//
// Written against the ORIGINAL implementation, before the
// `react-hooks/set-state-in-effect` fix.
//
// This panel grants and revokes portal access for outside agencies — police,
// army, DSS. The behaviour worth pinning is that a grant actually creates the
// account AND the list re-reads, and that a revoke writes SUSPENDED. A refactor
// that quietly dropped the re-read would leave a revoked liaison still listed
// as active.
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

const LIAISON = {
  id: 'liaison-1',
  full_name: 'DSP Audu Ibrahim',
  role: 'POLICE_LIAISON',
  agency: 'POLICE',
  created_at: '2026-08-01T10:00:00Z',
};

async function load() {
  return (await import('./AgencyAccessManager')).default;
}

describe('AgencyAccessManager', () => {
  beforeEach(() => {
    db = makeSupabaseStub();
  });

  it('shows a loading state, then the liaisons it fetched', async () => {
    db.setRows('profiles', [LIAISON]);
    const AgencyAccessManager = await load();

    render(<AgencyAccessManager />);
    expect(screen.getByText(/Loading liaison accounts/i)).toBeInTheDocument();

    expect(await screen.findByText('DSP Audu Ibrahim')).toBeInTheDocument();
    expect(screen.getByText(/Nigeria Police Force · POLICE_LIAISON/)).toBeInTheDocument();
  });

  it('stops loading and offers the empty state when there are none', async () => {
    db.setRows('profiles', []);
    const AgencyAccessManager = await load();

    render(<AgencyAccessManager />);
    expect(await screen.findByText(/No agency liaisons registered/i)).toBeInTheDocument();
  });

  // A failed read must never be displayed as "none registered". That claim
  // invites an administrator to grant access that already exists.
  it('reports a failed read as a failure, never as an empty roster', async () => {
    db.setError('profiles', { message: 'permission denied' });
    const AgencyAccessManager = await load();

    render(<AgencyAccessManager />);
    const alert = await screen.findByRole('alert');
    expect(alert).toHaveTextContent(/Could not load liaison accounts/i);
    expect(alert).toHaveTextContent(/permission denied/i);
    expect(screen.queryByText(/No agency liaisons registered/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/Loading liaison accounts/i)).not.toBeInTheDocument();
  });

  it('recovers when RETRY is pressed and the read succeeds', async () => {
    db.setError('profiles', { message: 'connection reset' });
    const AgencyAccessManager = await load();

    render(<AgencyAccessManager />);
    await screen.findByRole('alert');
    const before = db.selectCount('profiles');

    db.setRows('profiles', [LIAISON]);
    await userEvent.click(screen.getByRole('button', { name: /RETRY/i }));

    expect(await screen.findByText('DSP Audu Ibrahim')).toBeInTheDocument();
    expect(db.selectCount('profiles')).toBeGreaterThan(before);
    expect(screen.queryByRole('alert')).not.toBeInTheDocument();
  });

  it('keeps the last good roster, marked stale, when a refresh fails', async () => {
    db.setRows('profiles', [LIAISON]);
    const AgencyAccessManager = await load();

    render(<AgencyAccessManager />);
    await screen.findByText('DSP Audu Ibrahim');

    db.setError('profiles', { message: 'timeout' });
    await userEvent.click(screen.getAllByRole('button')[0]); // the refresh icon button

    const alert = await screen.findByRole('alert');
    expect(alert).toHaveTextContent(/showing the last list that loaded/i);
    // The roster itself is still there — stale but visible.
    expect(screen.getByText('DSP Audu Ibrahim')).toBeInTheDocument();
    expect(screen.queryByText(/No agency liaisons registered/i)).not.toBeInTheDocument();
  });

  it('re-reads the list when the refresh button is used', async () => {
    db.setRows('profiles', [LIAISON]);
    const AgencyAccessManager = await load();

    render(<AgencyAccessManager />);
    await screen.findByText('DSP Audu Ibrahim');
    const before = db.selectCount('profiles');

    // The refresh control is the icon-only button before GRANT ACCESS.
    await userEvent.click(screen.getAllByRole('button')[0]);
    await waitFor(() => expect(db.selectCount('profiles')).toBeGreaterThan(before));
  });

  // Through the server, never `supabase.auth.signUp` plus a profile upsert
  // from the browser: sign-up ignores a role the browser states, so that made
  // a CITIZEN, and a browser that could write the role would be the hole.
  it('creates the account through the server and re-reads', async () => {
    db.setRows('profiles', []);
    const provision = vi.fn(async () => ({
      ok: true,
      status: 201,
      json: async () => ({ id: 'new-user-id', role: 'POLICE_LIAISON' }),
    }));
    vi.stubGlobal('fetch', provision);
    const AgencyAccessManager = await load();

    render(<AgencyAccessManager />);
    await screen.findByText(/No agency liaisons registered/i);
    const before = db.selectCount('profiles');

    await userEvent.click(screen.getByRole('button', { name: /GRANT ACCESS/i }));
    await userEvent.type(screen.getByPlaceholderText(/DSP Audu Ibrahim/), 'Insp Grace Bala');
    await userEvent.type(screen.getByPlaceholderText(/liaison@agency.gov.ng/), 'g.bala@police.gov.ng');
    await userEvent.type(screen.getByPlaceholderText(/Min. 12 characters/), 'temp-pass-1234');
    await userEvent.click(screen.getByRole('button', { name: /Create Liaison Account/i }));

    expect(await screen.findByText(/created as POLICE Liaison/i)).toBeInTheDocument();
    const [url, init] = provision.mock.calls[0] as unknown as [string, { body: string }];
    expect(url).toBe('/api/admin/provision');
    expect(JSON.parse(init.body)).toMatchObject({
      fullName: 'Insp Grace Bala',
      role: 'POLICE_LIAISON',
      agency: 'POLICE',
    });
    expect(db.inserts.filter((w) => w.table === 'profiles')).toHaveLength(0);
    await waitFor(() => expect(db.selectCount('profiles')).toBeGreaterThan(before));
  });

  it('reports a refused creation rather than claiming success', async () => {
    db.setRows('profiles', []);
    vi.stubGlobal('fetch', vi.fn(async () => ({
      ok: false,
      status: 400,
      json: async () => ({ error: 'Password must be at least 12 characters.' }),
    })));
    const AgencyAccessManager = await load();

    render(<AgencyAccessManager />);
    await screen.findByText(/No agency liaisons registered/i);
    await userEvent.click(screen.getByRole('button', { name: /GRANT ACCESS/i }));
    await userEvent.type(screen.getByPlaceholderText(/DSP Audu Ibrahim/), 'Insp Grace Bala');
    await userEvent.type(screen.getByPlaceholderText(/liaison@agency.gov.ng/), 'g@police.gov.ng');
    await userEvent.type(screen.getByPlaceholderText(/Min. 12 characters/), 'short');
    await userEvent.click(screen.getByRole('button', { name: /Create Liaison Account/i }));

    expect(await screen.findByText(/at least 12 characters/i)).toBeInTheDocument();
    expect(screen.queryByText(/created as/i)).not.toBeInTheDocument();
  });

  it('refuses to submit an incomplete form and says why', async () => {
    db.setRows('profiles', []);
    const AgencyAccessManager = await load();

    render(<AgencyAccessManager />);
    await screen.findByText(/No agency liaisons registered/i);

    await userEvent.click(screen.getByRole('button', { name: /GRANT ACCESS/i }));
    await userEvent.click(screen.getByRole('button', { name: /Create Liaison Account/i }));

    expect(await screen.findByText(/All fields are required/i)).toBeInTheDocument();
    expect(db.inserts).toHaveLength(0);
  });

  it('revokes by writing SUSPENDED, then re-reads', async () => {
    db.setRows('profiles', [LIAISON]);
    vi.spyOn(window, 'confirm').mockReturnValue(true);
    const AgencyAccessManager = await load();

    render(<AgencyAccessManager />);
    await screen.findByText('DSP Audu Ibrahim');
    const before = db.selectCount('profiles');

    await userEvent.click(screen.getByRole('button', { name: /REVOKE/i }));

    await waitFor(() =>
      expect(db.updates).toContainEqual(
        expect.objectContaining({
          table: 'profiles',
          values: expect.objectContaining({ role: 'SUSPENDED' }),
          eq: ['id', 'liaison-1'],
        }),
      ),
    );
    await waitFor(() => expect(db.selectCount('profiles')).toBeGreaterThan(before));
  });

  it('does not revoke when the confirmation is declined', async () => {
    db.setRows('profiles', [LIAISON]);
    vi.spyOn(window, 'confirm').mockReturnValue(false);
    const AgencyAccessManager = await load();

    render(<AgencyAccessManager />);
    await screen.findByText('DSP Audu Ibrahim');

    await userEvent.click(screen.getByRole('button', { name: /REVOKE/i }));
    expect(db.updates).toHaveLength(0);
  });
});
