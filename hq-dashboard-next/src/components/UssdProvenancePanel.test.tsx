// The panel where an officer stands behind a keypad report.
//
// The database holds an unconfirmed USSD report out of the escalation ladder so
// no timer can turn a stranger's keypresses into a deployment. This panel is the
// decision an officer makes instead, and these tests pin the four things that
// decide whether it is safe:
//
//   * it appears for a keypad report and for nothing else;
//   * a REFUSED confirmation is shown in place, never swallowed — an officer told
//     "confirmed" would believe the ladder was running on a report still held;
//   * marking something false REQUIRES a reason, because that note is what the
//     next dispatcher weighs against a real emergency;
//   * a failed credibility lookup does not take the controls down with it.
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import UssdProvenancePanel from './UssdProvenancePanel';
import type { UssdCredibility } from '@/lib/ussd-provenance';

const CRED: UssdCredibility = {
  first_time_caller: true,
  caller_report_count: 0,
  caller_false_reports: 0,
  caller_known_days: 0,
  callback_offered: true,
  corroborating_reports: 0,
  corroborating_numbers: 0,
};

const KEYPAD = {
  id: 'a-1',
  arrived_via: 'USSD',
  ussd_confirmed_at: null,
  reporter_msisdn: '+2348030001111',
  caller_may_be_called: true,
  public_reference: 'R4K2M9',
};

let confirm: ReturnType<typeof vi.fn>;
let markFalse: ReturnType<typeof vi.fn>;
let credibility: ReturnType<typeof vi.fn>;

function mount(alert: Record<string, unknown> = KEYPAD, onChanged = vi.fn()) {
  const actions = { confirm, markFalse, credibility } as never;
  const r = render(
    <UssdProvenancePanel alert={alert as never} actions={actions} onChanged={onChanged} />,
  );
  return { ...r, onChanged };
}

beforeEach(() => {
  confirm = vi.fn().mockResolvedValue({ ok: true, value: { confirmed: 1, refused: 0 } });
  markFalse = vi.fn().mockResolvedValue({ ok: true, value: { marked: 1 } });
  credibility = vi.fn().mockResolvedValue(CRED);
});

describe('when it appears', () => {
  it('shows for an unconfirmed keypad report', async () => {
    mount();
    expect(await screen.findByText(/KEYPAD · UNCONFIRMED/)).toBeTruthy();
    expect(screen.getByText('+2348030001111')).toBeTruthy();
  });

  it('renders NOTHING for a report from the app', () => {
    const { container } = mount({ id: 'a-2', arrived_via: null, ussd_confirmed_at: null });
    expect(container.querySelector('[data-testid="ussd-provenance"]')).toBeNull();
  });

  it('renders nothing for an SMS fallback report, which has its own banner', () => {
    const { container } = mount({ id: 'a-3', arrived_via: 'SMS', ussd_confirmed_at: null });
    expect(container.querySelector('[data-testid="ussd-provenance"]')).toBeNull();
  });

  it('shows a confirmed keypad report WITHOUT the controls', async () => {
    // Once an officer has stood behind it, the credibility of the number is no
    // longer the decision in front of anybody. A panel that never goes away is a
    // panel people stop reading.
    mount({ ...KEYPAD, ussd_confirmed_at: '2026-09-29T10:00:00Z' });
    expect(await screen.findByText(/KEYPAD · CONFIRMED/)).toBeTruthy();
    expect(screen.queryByText(/CONFIRM — IT IS REAL/)).toBeNull();
    expect(credibility).not.toHaveBeenCalled();
  });

  it('says why it is not escalating, and that confirming is in your name', async () => {
    mount();
    const hold = await screen.findByText(/not yet confirmed/);
    expect(hold.textContent).toContain('will not escalate');
    expect(hold.textContent).toContain('in your name');
  });

  it('notes when the reporter declined a callback', async () => {
    mount({ ...KEYPAD, caller_may_be_called: false });
    expect(await screen.findByText(/no callback/)).toBeTruthy();
  });
});

describe('the credibility panel', () => {
  it('lists what is known about the number', async () => {
    mount();
    expect(await screen.findByText(/First time this number/)).toBeTruthy();
    expect(screen.getByText(/Nobody else is reporting this/)).toBeTruthy();
    expect(screen.getByText(/agreed to be called back/)).toBeTruthy();
  });

  it('shows corroboration from other numbers', async () => {
    credibility.mockResolvedValue({
      ...CRED, corroborating_reports: 4, corroborating_numbers: 4,
    });
    mount();
    expect(await screen.findByText(/4 other reports from 4 other numbers/)).toBeTruthy();
  });

  it('leads with a prior FALSE report from this number', async () => {
    credibility.mockResolvedValue({ ...CRED, caller_false_reports: 2 });
    mount();
    expect(await screen.findByText(/2 reports officers marked FALSE/)).toBeTruthy();
  });

  it('does not take the controls down when the lookup fails', async () => {
    // An emergency must never be un-actionable because a side panel errored.
    credibility.mockResolvedValue(null);
    mount();
    expect(await screen.findByText(/CONFIRM — IT IS REAL/)).toBeTruthy();
    expect(screen.queryByText(/First time this number/)).toBeNull();
  });
});

describe('the landmark', () => {
  it('is shown, because it is the only navigable thing on a keypad report', async () => {
    mount({ ...KEYPAD, reporter_landmark: 'behind Bukuru market, by the junction' });
    expect(await screen.findByText(/behind Bukuru market, by the junction/)).toBeTruthy();
  });

  it('is shown on a CONFIRMED report too', async () => {
    // It is what the responder needs, and it does not stop being useful once an
    // officer has stood behind the report.
    mount({
      ...KEYPAD,
      ussd_confirmed_at: '2026-09-29T10:00:00Z',
      reporter_landmark: 'POLICE BARRACKS',
    });
    expect(await screen.findByText(/POLICE BARRACKS/)).toBeTruthy();
  });

  it('is absent when the caller skipped it', async () => {
    mount({ ...KEYPAD, reporter_landmark: null });
    await screen.findByText(/KEYPAD · UNCONFIRMED/);
    expect(screen.queryByText(/Nearest landmark/)).toBeNull();
  });
});

describe('confirming', () => {
  it('calls the action and tells the board to refetch', async () => {
    const { onChanged } = mount();
    await userEvent.click(await screen.findByText(/CONFIRM — IT IS REAL/));
    await waitFor(() => expect(confirm).toHaveBeenCalledWith('a-1'));
    expect(onChanged).toHaveBeenCalled();
  });

  it('shows a REFUSAL in place, and does not tell the board anything changed', async () => {
    // The most important assertion here. An officer told "confirmed" on a report
    // still held out of the ladder would believe the timers were running when
    // nothing at all was chasing it.
    confirm.mockResolvedValue({ ok: false, error: 'Not confirmed — not yours to confirm.' });
    const { onChanged } = mount();
    await userEvent.click(await screen.findByText(/CONFIRM — IT IS REAL/));
    const alertBox = await screen.findByRole('alert');
    expect(alertBox.textContent).toContain('Not confirmed');
    expect(onChanged).not.toHaveBeenCalled();
    // And the control stays available, so they can try again or hand it on.
    expect(screen.getByText(/CONFIRM — IT IS REAL/)).toBeTruthy();
  });
});

describe('marking a report false', () => {
  it('requires a reason before it can be recorded', async () => {
    // "Marked false by an officer" with no reason is an accusation nobody can
    // check, and it is what the next dispatcher weighs against a real emergency.
    mount();
    await userEvent.click(await screen.findByText('MARK FALSE'));
    const record = screen.getByText(/RECORD AS FALSE/).closest('button')!;
    expect(record.hasAttribute('disabled')).toBe(true);

    await userEvent.type(screen.getByLabelText(/How do you know/), 'abc');
    expect(record.hasAttribute('disabled')).toBe(true);

    await userEvent.type(screen.getByLabelText(/How do you know/), 'd');
    expect(record.hasAttribute('disabled')).toBe(false);
  });

  it('records the note with the mark', async () => {
    const { onChanged } = mount();
    await userEvent.click(await screen.findByText('MARK FALSE'));
    await userEvent.type(screen.getByLabelText(/How do you know/), 'rang back, nothing there');
    await userEvent.click(screen.getByText(/RECORD AS FALSE/));
    await waitFor(() =>
      expect(markFalse).toHaveBeenCalledWith('a-1', 'rang back, nothing there'));
    expect(onChanged).toHaveBeenCalled();
  });

  it('can be cancelled without recording anything', async () => {
    mount();
    await userEvent.click(await screen.findByText('MARK FALSE'));
    await userEvent.type(screen.getByLabelText(/How do you know/), 'changed my mind');
    await userEvent.click(screen.getByText('CANCEL'));
    expect(markFalse).not.toHaveBeenCalled();
    expect(await screen.findByText(/CONFIRM — IT IS REAL/)).toBeTruthy();
  });

  it('shows a refusal rather than closing the form', async () => {
    markFalse.mockResolvedValue({ ok: false, error: 'Not marked — not yours to close.' });
    const { onChanged } = mount();
    await userEvent.click(await screen.findByText('MARK FALSE'));
    await userEvent.type(screen.getByLabelText(/How do you know/), 'rang back, nothing there');
    await userEvent.click(screen.getByText(/RECORD AS FALSE/));
    expect((await screen.findByRole('alert')).textContent).toContain('Not marked');
    expect(onChanged).not.toHaveBeenCalled();
  });
});
