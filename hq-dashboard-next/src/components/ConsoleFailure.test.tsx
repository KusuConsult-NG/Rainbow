// What the operator sees when the console crashes.
//
// The property under test is not "a fallback renders" — it is that the
// fallback CANNOT BE MISTAKEN FOR A QUIET SHIFT. On this system a blank board
// and a board with nothing to report look the same to a tired operator at 3am,
// and only one of them means incidents are arriving unseen.
//
// So these assert the things that make the difference: it announces itself to
// assistive technology, it says the console failed, it says incidents may be
// missing, it names the fallback (radio), and it offers a way back.
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';

import ConsoleFailure from './ConsoleFailure';

const err = (digest?: string) => Object.assign(new Error('boom'), { digest });

describe('ConsoleFailure', () => {
  it('announces the failure rather than rendering an empty screen', () => {
    render(<ConsoleFailure scope="Live operations board" error={err()} />);

    // An assertive live region: a screen reader interrupts for this one.
    const panel = screen.getByRole('alert');
    expect(panel).toHaveAttribute('aria-live', 'assertive');

    expect(screen.getByText(/console failed/i)).toBeInTheDocument();
    expect(screen.getByText('Live operations board')).toBeInTheDocument();
  });

  it('tells the operator that incidents may be arriving unseen', () => {
    render(<ConsoleFailure scope="Live operations board" error={err()} />);

    // The exact wording may change; the claim must not disappear. Without it
    // the screen reads as "nothing to show", which is the failure this file
    // exists to prevent.
    expect(
      screen.getByText(/incidents may be arriving that you cannot\s+see here/i),
    ).toBeInTheDocument();
    expect(screen.getByText(/radio/i)).toBeInTheDocument();
  });

  it('says the recorded data is intact, so nobody re-reports resolved incidents', () => {
    render(<ConsoleFailure scope="Live operations board" error={err()} />);
    expect(screen.getByText(/display failure, not a data failure/i)).toBeInTheDocument();
  });

  it('offers retry when the boundary can recover, and always offers reload', async () => {
    const onRetry = vi.fn();
    render(<ConsoleFailure scope="Board" error={err()} onRetry={onRetry} />);

    await userEvent.click(screen.getByRole('button', { name: /retry/i }));
    expect(onRetry).toHaveBeenCalledOnce();
    expect(screen.getByRole('button', { name: /reload console/i })).toBeInTheDocument();
  });

  it('drops the retry button when the boundary cannot re-render its children', () => {
    render(<ConsoleFailure scope="Board" error={err()} />);
    expect(screen.queryByRole('button', { name: /^retry$/i })).not.toBeInTheDocument();
    // ...but there is still a way out.
    expect(screen.getByRole('button', { name: /reload console/i })).toBeInTheDocument();
  });

  it('shows the digest for a fault report, and never the raw error message', () => {
    render(<ConsoleFailure scope="Board" error={err('a1b2c3d4')} />);

    expect(screen.getByText('a1b2c3d4')).toBeInTheDocument();
    // Next replaces `message` with a generic string in production precisely so
    // internals do not reach a screen someone else may be standing behind.
    // Rendering it anyway would defeat that.
    expect(screen.queryByText(/boom/)).not.toBeInTheDocument();
  });

  it('omits the digest line when there is no digest', () => {
    render(<ConsoleFailure scope="Board" error={err()} />);
    expect(screen.queryByText(/quote this when reporting/i)).not.toBeInTheDocument();
  });
});
