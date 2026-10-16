// Escape closes the thing on top.
//
// The console had no `keydown` handler anywhere, so the incident dossier — a
// fixed overlay over the feed and the map — and the narrow-screen drawer could
// only be dismissed with a pointer.
//
// All of these fail against that version, because there was nothing to call.
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';

import { useEscapeKey } from './useEscapeKey';

function Overlay({ enabled, onEscape }: { enabled: boolean; onEscape: () => void }) {
  useEscapeKey(enabled, onEscape);
  return <p>overlay</p>;
}

describe('useEscapeKey', () => {
  it('calls back on Escape', async () => {
    const onEscape = vi.fn();
    render(<Overlay enabled onEscape={onEscape} />);

    await userEvent.keyboard('{Escape}');

    expect(onEscape).toHaveBeenCalledTimes(1);
  });

  it('ignores every other key', async () => {
    const onEscape = vi.fn();
    render(<Overlay enabled onEscape={onEscape} />);

    await userEvent.keyboard('{Enter}{Tab} x{Backspace}');

    expect(onEscape).not.toHaveBeenCalled();
  });

  it('does nothing while disabled', async () => {
    const onEscape = vi.fn();
    render(<Overlay enabled={false} onEscape={onEscape} />);

    await userEvent.keyboard('{Escape}');

    expect(onEscape).not.toHaveBeenCalled();
  });

  it('stops listening once the overlay closes', async () => {
    const onEscape = vi.fn();
    const { rerender } = render(<Overlay enabled onEscape={onEscape} />);
    rerender(<Overlay enabled={false} onEscape={onEscape} />);

    await userEvent.keyboard('{Escape}');

    // A listener that outlives its overlay closes the one UNDERNEATH on the
    // next keystroke, which on this console means losing the dossier an
    // operator had open behind a dialog.
    expect(onEscape).not.toHaveBeenCalled();
  });

  it('lets the caller decide which of two overlays closes', async () => {
    // Two listeners on `window` fire in REGISTRATION order, not in z-order, so
    // the overlay that mounted FIRST would otherwise win. Precedence is
    // expressed by the caller's `enabled` — which is what dashboard/page.tsx
    // does with `navOpen && selectedReport === null`.
    const closeUnder = vi.fn();
    const closeTop = vi.fn();
    const Nested = ({ topOpen }: { topOpen: boolean }) => {
      useEscapeKey(!topOpen, closeUnder);   // the drawer: only while nothing is above it
      useEscapeKey(topOpen, closeTop);      // the dossier
      return <p>nested</p>;
    };

    const { rerender } = render(<Nested topOpen />);
    await userEvent.keyboard('{Escape}');
    expect(closeTop).toHaveBeenCalledTimes(1);
    expect(closeUnder).not.toHaveBeenCalled();

    rerender(<Nested topOpen={false} />);
    await userEvent.keyboard('{Escape}');
    expect(closeUnder).toHaveBeenCalledTimes(1);
    expect(closeTop).toHaveBeenCalledTimes(1);
  });

  it('keeps working when the handler identity changes', async () => {
    // The effect depends on `onEscape`, so an inline arrow passed by a parent
    // that re-renders on every tick would re-subscribe constantly. It must
    // still be listening afterwards, and exactly once.
    const calls: string[] = [];
    const Tick = ({ n }: { n: number }) => {
      useEscapeKey(true, () => calls.push(`close-${n}`));
      return <p>tick {n}</p>;
    };
    const { rerender } = render(<Tick n={1} />);
    rerender(<Tick n={2} />);
    rerender(<Tick n={3} />);

    await userEvent.keyboard('{Escape}');

    expect(calls).toEqual(['close-3']);
    expect(screen.getByText('tick 3')).toBeTruthy();
  });
});
