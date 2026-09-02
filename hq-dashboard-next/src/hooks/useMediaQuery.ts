'use client';

import { useEffect, useState } from 'react';

/**
 * Tracks a CSS media query from React.
 *
 * The console's layout lives in inline styles rather than stylesheets, so a
 * plain `@media` rule cannot reach it. This gives the same information to the
 * component tree.
 *
 * Starts `false` on the server and on first paint, then corrects in an effect.
 * `window.matchMedia` does not exist during prerender, and reading it during
 * render would produce a hydration mismatch — so the desktop layout is the
 * first frame, and a narrow viewport switches immediately after mount.
 */
export function useMediaQuery(query: string): boolean {
  const [matches, setMatches] = useState(false);

  useEffect(() => {
    const mql = window.matchMedia(query);
    setMatches(mql.matches);
    const onChange = (e: MediaQueryListEvent) => setMatches(e.matches);
    mql.addEventListener('change', onChange);
    return () => mql.removeEventListener('change', onChange);
  }, [query]);

  return matches;
}
