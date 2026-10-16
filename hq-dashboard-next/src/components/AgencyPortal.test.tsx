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
    // `role="tab"`, not `button`: setting an explicit ARIA role REPLACES the
    // implicit one, so these are no longer buttons in the accessibility tree.
    await userEvent.click(screen.getByRole('tab', { name: /ARMY/ }));

    expect(await screen.findByText(/Incident for ARMY/)).toBeInTheDocument();
    expect(screen.queryByText(/Incident for POLICE/)).not.toBeInTheDocument();
  });

  // The escalation log on this desk is the only history a sister agency gets:
  // they have no console, no feed and no audit screen. It is read with the
  // same three functions as the HQ replay panel, so "who escalated this" has
  // one answer in the codebase (T-32's order: `by`, then `by_email`, then
  // SYSTEM) and an entry whose time was never written says so instead of
  // rendering the string "Invalid Date".
  // KEYBOARD. This desk is the whole of an outside agency's access — they have
  // no console, no feed, no audit screen — and the incident card was a
  // clickable div, so the escalation log, the evidence, the live feed and both
  // action buttons sat behind a control a pointer could use and nothing else
  // could.
  it('opens an incident from the keyboard, and says whether it is open', async () => {
    db.setRows('alerts', [{
      ...incident('a-1', 'POLICE'),
      // Something that only exists once the card is open, so this proves the
      // detail was REACHED and not merely that an attribute flipped.
      escalation_log: [{
        at: '2026-09-01T12:30:00Z', from_tier: 'LGA', to_tier: 'HQ',
        by_email: 'hq@operationrainbow.test', reason: 'Handed to the Police',
      }],
    }]);
    const AgencyPortal = await load();

    render(<AgencyPortal {...hqProps} />);
    await screen.findByText(/Incident for POLICE/);

    const card = screen.getByRole('button', { expanded: false, name: /CIVIL_UNREST/ });
    card.focus();
    expect(card).toHaveFocus();

    await userEvent.keyboard('{Enter}');

    // `aria-expanded` is the state the chevron shows visually and said nowhere
    // else, so a screen reader could not tell an open card from a shut one.
    expect(screen.getByRole('button', { expanded: true, name: /CIVIL_UNREST/ })).toBeInTheDocument();
    expect(await screen.findByText(/ESCALATION LOG/)).toBeTruthy();
    expect(screen.getByText(/Handed to the Police/)).toBeTruthy();

    // And Space shuts it again, because that is what a button does.
    await userEvent.keyboard(' ');
    expect(screen.getByRole('button', { expanded: false, name: /CIVIL_UNREST/ })).toBeInTheDocument();
  });

  it('reads an escalation entry the same way the replay panel does', async () => {
    db.setRows('alerts', [{
      ...incident('a-1', 'POLICE'),
      escalation_log: [
        {
          at: '2026-09-01T12:30:00Z',
          from_tier: 'WARD',
          to_tier: 'LGA',
          by_email: 'ward.commander@operationrainbow.test',
          reason: 'No unit free in the ward',
        },
        // No `at`. Nothing validates the log's keys, and `audit_trail()`
        // already falls back for exactly this shape.
        { from_tier: 'LGA', to_tier: 'HQ', by: 'SYSTEM', reason: 'TIMEOUT' },
      ],
    }]);
    const AgencyPortal = await load();

    const { container } = render(<AgencyPortal {...hqProps} />);
    await userEvent.click(await screen.findByText(/Incident for POLICE/));

    expect(await screen.findByText(/WARD → LGA/)).toBeInTheDocument();
    expect(container.textContent).toContain('ward.commander@operationrainbow.test');
    expect(container.textContent).toContain('TIME NOT RECORDED');
    expect(container.textContent).not.toContain('Invalid Date');
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

    // `tab`, not `button`: the section tabs carry role="tab" so that the
    // selected one is stated rather than implied by a border colour. Setting an
    // explicit role REPLACES the implicit one, so this query had to follow —
    // which is the accessibility tree changing, exactly as intended.
    await userEvent.click(screen.getByRole('tab', { name: /Action Reports/i }));
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

describe('whose desk this is', () => {
  // The dashboard renders this component before it knows whose console it is.
  // `userRole` is declared `useState('HQ_OFFICER')` — a command role — so until
  // the `profiles.role` read returns, `consoleAccess` reports the command
  // console and the dashboard passes `isHq: true` with no agency. That is the
  // flash `consoleAccess`'s own doc comment says it exists to prevent (T-34,
  // T-35), and these are the props it hands over meanwhile.
  const unresolved = {
    userRole: 'HQ_OFFICER',
    userAgency: undefined,
    isHq: true,
    userEmail: 'liaison@army.mil.ng',
    userId: 'l-1',
  };
  const armyLiaison = {
    ...unresolved,
    userRole: 'ARMY_LIAISON',
    userAgency: 'ARMY',
    isHq: false,
  };

  beforeEach(() => {
    db.setRows('alerts', [incident('a-1', 'POLICE'), incident('a-2', 'ARMY')]);
  });

  it('an Army liaison whose role arrived late is not left on the Police desk', async () => {
    const AgencyPortal = await load();
    const { rerender } = render(<AgencyPortal {...unresolved} />);
    // While the role is unknown the portal must not name a desk at all: the
    // first agency in the list is not a guess worth making.
    rerender(<AgencyPortal {...armyLiaison} />);

    expect(await screen.findByText(/NIGERIAN ARMY/)).toBeInTheDocument();
    expect(screen.queryByText(/NIGERIA POLICE FORCE/)).not.toBeInTheDocument();
    // And the data is theirs. The portal reading the Police desk for an Army
    // liaison does not fail loudly — RLS returns no rows and the portal
    // reports the Police as having no incidents, no personnel and no
    // deployments, on the only screen this role has.
    expect(await screen.findByText(/Incident for ARMY/)).toBeInTheDocument();
    expect(screen.queryByText(/Incident for POLICE/)).not.toBeInTheDocument();
  });

  it('says it does not know yet rather than naming an agency', async () => {
    const AgencyPortal = await load();
    render(<AgencyPortal {...unresolved} isHq={false} />);
    // A non-HQ account with no agency is not the Police. It used to default to
    // `'POLICE'` literally, in both branches.
    await waitFor(() =>
      expect(screen.queryByText(/Loading agency data/i)).not.toBeInTheDocument(),
    );
    expect(screen.queryByText(/NIGERIA POLICE FORCE/)).not.toBeInTheDocument();
    expect(screen.getByText(/RESOLVING/i)).toBeInTheDocument();
  });

  it('an HQ operator still gets a desk and a switcher', async () => {
    const AgencyPortal = await load();
    render(<AgencyPortal {...unresolved} userRole="HQ_COMMAND" />);
    expect(await screen.findByText(/NIGERIA POLICE FORCE/)).toBeInTheDocument();
    expect(screen.getByRole('tablist', { name: 'Agency' })).toBeInTheDocument();
  });
});
