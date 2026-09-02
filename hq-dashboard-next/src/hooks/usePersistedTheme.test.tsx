import { act, render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { resetThemeCache, usePersistedTheme } from './usePersistedTheme';

function Probe() {
  const [theme, setTheme] = usePersistedTheme();
  return (
    <div>
      <span data-testid="theme">{theme}</span>
      <button onClick={() => setTheme((t) => (t === 'light' ? 'dark' : 'light'))}>
        toggle
      </button>
    </div>
  );
}

describe('usePersistedTheme', () => {
  beforeEach(() => {
    window.localStorage.clear();
    resetThemeCache();
  });

  it('defaults to light when nothing is stored', () => {
    render(<Probe />);
    expect(screen.getByTestId('theme')).toHaveTextContent('light');
  });

  it('renders the stored theme on the FIRST paint, with no flash of the default', () => {
    window.localStorage.setItem('hq-theme', 'dark');
    resetThemeCache();

    render(<Probe />);
    // The point of the refactor: the old mount-effect rendered 'light' first
    // and corrected itself afterwards.
    expect(screen.getByTestId('theme')).toHaveTextContent('dark');
  });

  it('persists a change so the next mount starts there', async () => {
    render(<Probe />);
    await userEvent.click(screen.getByRole('button', { name: 'toggle' }));

    expect(screen.getByTestId('theme')).toHaveTextContent('dark');
    expect(window.localStorage.getItem('hq-theme')).toBe('dark');
  });

  it('follows a change made in another tab', () => {
    render(<Probe />);
    expect(screen.getByTestId('theme')).toHaveTextContent('light');

    act(() => {
      window.localStorage.setItem('hq-theme', 'dark');
      window.dispatchEvent(new StorageEvent('storage', { key: 'hq-theme', newValue: 'dark' }));
    });

    expect(screen.getByTestId('theme')).toHaveTextContent('dark');
  });

  // A console that throws on a storage read is worse than one with no
  // preference — this runs on machines with site data locked down by policy.
  it('still renders when localStorage throws', () => {
    resetThemeCache();
    vi.spyOn(Storage.prototype, 'getItem').mockImplementation(() => {
      throw new Error('access denied');
    });

    render(<Probe />);
    expect(screen.getByTestId('theme')).toHaveTextContent('light');
  });

  it('does not throw when a write is refused', async () => {
    render(<Probe />);
    vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => {
      throw new Error('quota exceeded');
    });

    await userEvent.click(screen.getByRole('button', { name: 'toggle' }));
    // The session still switched, it just did not persist.
    expect(screen.getByTestId('theme')).toHaveTextContent('dark');
  });
});
