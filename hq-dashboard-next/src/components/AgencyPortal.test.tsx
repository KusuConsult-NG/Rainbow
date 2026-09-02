// Characterisation tests for AgencyPortal.
//
// Written against the ORIGINAL implementation, before the
// `react-hooks/set-state-in-effect` fix.
//
// This is the surface an outside agency — police, army, DSS — uses to see the
// incidents HQ escalated to them. The behaviours that must survive the
// refactor: it loads for the selected agency, switching agency shows the
// spinner and then the NEW agency's data (never the previous one's), and an
// acknowledgement re-reads.
//
// The agency-switch case is the one the refactor could plausibly break, and it
// matters operationally: showing POLICE incidents under an ARMY heading is
// worse than showing nothing.
import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { makeSupabaseStub, type SupabaseStub } from '@/test/supabase-stub';

let db: SupabaseStub;

vi.mock('@/lib/supabase', () => ({
  get supabase() {
    return db.client;
  },
}));

const incident = (id: string, agency: string) => ({
  id,
  type: 'CIVIL_UNREST',
  description: `Incident for ${agency}`,
  status: 'ACTIVE',
  severity: 'HIGH',
  geo_lga: 'JOS NORTH',
  escalated_to_agency: agency,
  created_at: '2026-09-01T12:00:00Z',
});

async function load() {
  return (await import('./AgencyPortal')).default;
}

const hqProps = {
  userRole: 'HQ_COMMAND',
  userAgency: '',
  isHq: true,
  userEmail: 'hq@operationrainbow.plateau.gov.ng',
  userId: 'hq-1',
};

describe('AgencyPortal', () => {
  beforeEach(() => {
    db = makeSupabaseStub();
    db.setRows('agency_personnel', []);
    db.setRows('agency_action_reports', []);
    db.setRows('agency_deployments', []);
  });

  it('shows a spinner, then the incidents for the selected agency', async () => {
    db.setRows('alerts', [incident('a-1', 'POLICE')]);
    const AgencyPortal = await load();

    render(<AgencyPortal {...hqProps} />);
    expect(screen.getByText(/Loading agency data/i)).toBeInTheDocument();

    expect(await screen.findByText(/Incident for POLICE/)).toBeInTheDocument();
    expect(screen.queryByText(/Loading agency data/i)).not.toBeInTheDocument();
  });

  it('leaves the spinner even when every query errors', async () => {
    db.setError('alerts', { message: 'permission denied' });
    const AgencyPortal = await load();

    render(<AgencyPortal {...hqProps} />);
    await waitFor(() =>
      expect(screen.queryByText(/Loading agency data/i)).not.toBeInTheDocument(),
    );
  });

  it('says so when the agency has no escalated incidents', async () => {
    db.setRows('alerts', []);
    const AgencyPortal = await load();

    render(<AgencyPortal {...hqProps} />);
    expect(
      await screen.findByText(/No active incidents escalated to/i),
    ).toBeInTheDocument();
  });

  // The important one. Switching agency must not leave the previous agency's
  // incidents on screen under the new agency's name.
  it('re-reads when HQ switches agency, and never shows the old agency data', async () => {
    // The stub applies `.eq()`, so each agency really does get its own rows.
    db.setRows('alerts', [incident('a-1', 'POLICE'), incident('a-2', 'ARMY')]);
    const AgencyPortal = await load();

    render(<AgencyPortal {...hqProps} />);
    expect(await screen.findByText(/Incident for POLICE/)).toBeInTheDocument();

    // The switcher is a row of pill buttons, one per agency.
    await userEvent.click(screen.getByRole('button', { name: /ARMY/ }));

    expect(await screen.findByText(/Incident for ARMY/)).toBeInTheDocument();
    expect(screen.queryByText(/Incident for POLICE/)).not.toBeInTheDocument();
  });

  it('acknowledges a report and re-reads', async () => {
    db.setRows('alerts', []);
    db.setRows('agency_action_reports', [
      {
        id: 'rep-1',
        agency: 'POLICE',
        alert_id: 'a-1',
        summary: 'Crowd dispersed without injury',
        submitted_at: '2026-09-01T13:00:00Z',
        read_by_hq: false,
      },
    ]);
    const AgencyPortal = await load();

    render(<AgencyPortal {...hqProps} />);
    await screen.findByText(/No active incidents escalated to/i);

    await userEvent.click(screen.getByRole('button', { name: /Action Reports/i }));
    const ackButton = await screen.findByRole('button', { name: /acknowledge/i });
    const before = db.selectCount('agency_action_reports');
    await userEvent.click(ackButton);

    await waitFor(() =>
      expect(db.updates).toContainEqual(
        expect.objectContaining({
          table: 'agency_action_reports',
          values: expect.objectContaining({ read_by_hq: true }),
          eq: ['id', 'rep-1'],
        }),
      ),
    );
    await waitFor(() =>
      expect(db.selectCount('agency_action_reports')).toBeGreaterThan(before),
    );
  });

  it('counts unread reports in the header', async () => {
    db.setRows('alerts', []);
    db.setRows('agency_action_reports', [
      { id: 'r1', agency: 'POLICE', summary: 'a', submitted_at: '2026-09-01T13:00:00Z', read_by_hq: false },
      { id: 'r2', agency: 'POLICE', summary: 'b', submitted_at: '2026-09-01T13:05:00Z', read_by_hq: true },
    ]);
    const AgencyPortal = await load();

    render(<AgencyPortal {...hqProps} />);
    await screen.findByText(/No active incidents escalated to/i);

    // The tile is `<div><div>{value}</div><div>UNREAD REPORTS</div></div>`.
    const tile = screen.getByText('UNREAD REPORTS').parentElement!;
    expect(within(tile).getByText('1')).toBeInTheDocument();
  });
});
