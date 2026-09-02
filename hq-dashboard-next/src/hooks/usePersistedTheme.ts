'use client';
import { useCallback, useSyncExternalStore } from 'react';

/**
 * The console's light/dark preference, backed by localStorage.
 *
 * WHY THIS IS NOT `useState` + AN EFFECT
 *
 * The dashboard read the saved theme in a mount effect and called `setTheme`,
 * which is a `set-state-in-effect`: it renders once with the wrong theme, then
 * again with the right one. It cannot simply become a lazy `useState`
 * initialiser either — `localStorage` does not exist during server rendering,
 * so the server and the first client render would disagree and hydration would
 * break.
 *
 * `useSyncExternalStore` is React's answer to exactly this shape: it renders
 * `getServerSnapshot()` on the server and during hydration, then switches to
 * the real value, with no mismatch and no effect.
 */
export type Theme = 'light' | 'dark';

const KEY = 'hq-theme';

const listeners = new Set<() => void>();

/** Cached so getSnapshot is referentially stable between notifications. */
let cached: Theme | null = null;

function read(): Theme {
  try {
    return window.localStorage.getItem(KEY) === 'dark' ? 'dark' : 'light';
  } catch {
    // Private mode, or storage disabled by policy. A themeless console is
    // still a working console.
    return 'light';
  }
}

function getSnapshot(): Theme {
  if (cached === null) cached = read();
  return cached;
}

/** The server has no storage, so it always renders the default. */
function getServerSnapshot(): Theme {
  return 'light';
}

function emit() {
  listeners.forEach((l) => l());
}

function subscribe(onChange: () => void): () => void {
  listeners.add(onChange);
  // Another tab changing the theme should move this one too.
  const onStorage = (e: StorageEvent) => {
    if (e.key === null || e.key === KEY) {
      cached = read();
      emit();
    }
  };
  window.addEventListener('storage', onStorage);
  return () => {
    listeners.delete(onChange);
    window.removeEventListener('storage', onStorage);
  };
}

/** Test seam: drop the cached value so the next read hits storage again. */
export function resetThemeCache(): void {
  cached = null;
}

export function usePersistedTheme(): [Theme, (next: Theme | ((prev: Theme) => Theme)) => void] {
  const theme = useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);

  const setTheme = useCallback((next: Theme | ((prev: Theme) => Theme)) => {
    const value = typeof next === 'function' ? next(getSnapshot()) : next;
    cached = value;
    try {
      window.localStorage.setItem(KEY, value);
    } catch {
      // Preference simply will not persist; the session still switches.
    }
    emit();
  }, []);

  return [theme, setTheme];
}
