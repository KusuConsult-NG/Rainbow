'use client';

import { useCallback, useSyncExternalStore } from 'react';

/**
 * Tracks a CSS media query from React.
 *
 * The console's layout lives in inline styles rather than stylesheets, so a
 * plain `@media` rule cannot reach it. This gives the same information to the
 * component tree.
 *
 * Built on `useSyncExternalStore` rather than `useState` + `useEffect`.
 * `matchMedia` is an external store, and that is the API React provides for
 * subscribing to one: it reads the current value during render on the client
 * and takes a separate snapshot for the server, so there is no
 * set-state-inside-an-effect and no extra render on mount to correct a wrong
 * initial guess. The effect version also tripped `react-hooks/set-state-in-effect`
 * legitimately — it really was setting state in an effect, it just had no
 * alternative in that shape.
 *
 * The server snapshot is `false`: `window.matchMedia` does not exist during
 * prerender, so the desktop layout is what gets rendered on the server, and a
 * narrow viewport corrects on hydration.
 */
export function useMediaQuery(query: string): boolean {
  const subscribe = useCallback(
    (onStoreChange: () => void) => {
      const mql = window.matchMedia(query);
      mql.addEventListener('change', onStoreChange);
      return () => mql.removeEventListener('change', onStoreChange);
    },
    [query],
  );

  const getSnapshot = useCallback(
    () => window.matchMedia(query).matches,
    [query],
  );

  const getServerSnapshot = useCallback(() => false, []);

  return useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
}
