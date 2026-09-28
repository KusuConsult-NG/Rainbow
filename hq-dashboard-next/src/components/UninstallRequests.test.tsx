// Characterisation tests for UninstallRequests.
//
// Written against the ORIGINAL implementation, before the
// `react-hooks/set-state-in-effect` fix, so they describe behaviour that must
// survive the refactor rather than behaviour invented to match it.
//
// The risk being guarded is specific: this panel approves and denies requests
// to remove the app from a field responder's phone. If the refactor leaves it
// loading forever, or stops it refreshing after an action, an approval appears
// not to have happened and gets issued twice.
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

// The row as the DATABASE actually holds it.
//
// This fixture used to carry `created_at` and an embedded `profiles` object,
// because that is what the component asked for — and neither was real. The
// table's timestamp is `submitted_at`, and `user_id` references `auth.users`,
// not `public.profiles`, so PostgREST could not embed the one from the other
// and rejected the query outright. The tests passed throughout, because a stub
// returns whatever shape it is handed.
//
// That is the trap in a characterisation test written against a stub: it pins
// the behaviour and the data shape together, and if the shape was wrong the
// test defends the bug. The assertions below are unchanged; only the fixture
// moved to what production can return.
const PENDING = {
  id: 'req-1',
  user_id: 'user-aaaaaaaa',
  reason: 'Phone replaced',
  remarks: 'Old handset returned to store',
  status: 'PENDING',
  submitted_at: '2026-09-01T09:00:00Z',
};

const REPORTER = {
  id: 'user-aaaaaaaa',
  full_name: 'Officer Danjuma',
  role: 'LGA_COMMANDER',
  geo_lga: 'JOS SOUTH',
};

describe('UninstallRequests', () => {
  beforeEach(() => {
    db = makeSupabaseStub();
    // The reporter's name comes from a second query now, not an embed.
    db.setRows('profiles', [REPORTER]);
  });

  it('shows a loading state, then the requests it fetched', async () => {
    db.setRows('uninstall_requests', [PENDING]);
    const UninstallRequests = (await import('./UninstallRequests')).default;

    render(<UninstallRequests />);
    expect(screen.getByText(/Loading requests/i)).toBeInTheDocument();

    expect(await screen.findByText('Officer Danjuma')).toBeInTheDocument();
    expect(screen.queryByText(/Loading requests/i)).not.toBeInTheDocument();
    expect(screen.getByText(/Phone replaced/)).toBeInTheDocument();
  });

  it('stops loading and says so when there is nothing pending', async () => {
    db.setRows('uninstall_requests', []);
    const UninstallRequests = (await import('./UninstallRequests')).default;

    render(<UninstallRequests />);
    expect(
      await screen.findByText(/No pending uninstall verification requests/i),
    ).toBeInTheDocument();
  });

  // The failure this exists to catch: an error that leaves `loading` true
  // forever, so the panel spins and an operator cannot tell it is broken.
  it('leaves the loading state even when the query errors', async () => {
    db.setError('uninstall_requests', { message: 'permission denied' });
    const UninstallRequests = (await import('./UninstallRequests')).default;

    render(<UninstallRequests />);
    await waitFor(() =>
      expect(screen.queryByText(/Loading requests/i)).not.toBeInTheDocument(),
    );
  });

  it('writes the new status and re-reads the list after an approval', async () => {
    db.setRows('uninstall_requests', [PENDING]);
    const UninstallRequests = (await import('./UninstallRequests')).default;

    render(<UninstallRequests />);
    await screen.findByText('Officer Danjuma');

    const readsBefore = db.selectCount('uninstall_requests');
    await userEvent.click(screen.getByRole('button', { name: /APPROVE/i }));

    await waitFor(() =>
      expect(db.updates).toContainEqual(
        expect.objectContaining({
          table: 'uninstall_requests',
          values: expect.objectContaining({ status: 'APPROVED' }),
          eq: ['id', 'req-1'],
        }),
      ),
    );

    // Re-reading is the point: without it the operator still sees PENDING and
    // approves a second time.
    await waitFor(() =>
      expect(db.selectCount('uninstall_requests')).toBeGreaterThan(readsBefore),
    );
  });

  it('denies as well as approves', async () => {
    db.setRows('uninstall_requests', [PENDING]);
    const UninstallRequests = (await import('./UninstallRequests')).default;

    render(<UninstallRequests />);
    await screen.findByText('Officer Danjuma');
    await userEvent.click(screen.getByRole('button', { name: /DENY/i }));

    await waitFor(() =>
      expect(db.updates).toContainEqual(
        expect.objectContaining({
          values: expect.objectContaining({ status: 'DENIED' }),
        }),
      ),
    );
  });
});
