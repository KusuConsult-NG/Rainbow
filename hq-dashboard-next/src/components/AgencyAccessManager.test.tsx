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

  it('leaves the loading state even when the query errors', async () => {
    db.setError('profiles', { message: 'permission denied' });
    const AgencyAccessManager = await load();

    render(<AgencyAccessManager />);
    await waitFor(() =>
      expect(screen.queryByText(/Loading liaison accounts/i)).not.toBeInTheDocument(),
    );
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

  it('creates the account, upserts the profile, and re-reads', async () => {
    db.setRows('profiles', []);
    db.authResult = { data: { user: { id: 'new-user-id' } }, error: null };
    const AgencyAccessManager = await load();

    render(<AgencyAccessManager />);
    await screen.findByText(/No agency liaisons registered/i);
    const before = db.selectCount('profiles');

    await userEvent.click(screen.getByRole('button', { name: /GRANT ACCESS/i }));
    await userEvent.type(screen.getByPlaceholderText(/DSP Audu Ibrahim/), 'Insp Grace Bala');
    await userEvent.type(screen.getByPlaceholderText(/liaison@agency.gov.ng/), 'g.bala@police.gov.ng');
    await userEvent.type(screen.getByPlaceholderText(/Min. 8 characters/), 'temp-pass-123');
    await userEvent.click(screen.getByRole('button', { name: /Create Liaison Account/i }));

    await waitFor(() =>
      expect(db.inserts).toContainEqual(
        expect.objectContaining({
          table: 'profiles',
          values: expect.objectContaining({
            id: 'new-user-id',
            full_name: 'Insp Grace Bala',
            role: 'POLICE_LIAISON',
          }),
        }),
      ),
    );
    await waitFor(() => expect(db.selectCount('profiles')).toBeGreaterThan(before));
    expect(await screen.findByText(/created as POLICE Liaison/i)).toBeInTheDocument();
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
