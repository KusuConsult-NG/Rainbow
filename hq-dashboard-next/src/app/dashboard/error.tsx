'use client';

import { useEffect } from 'react';
import ConsoleFailure from '@/components/ConsoleFailure';

/**
 * Error boundary for the operations board.
 *
 * Without this file, an uncaught render error anywhere in the 3,000-line
 * dashboard tree took out the whole page: Next's default boundary is a blank
 * screen in production. On an emergency console that is the worst possible
 * failure mode, because a blank board and a quiet board look identical.
 *
 * This is the boundary that matters most, because it is the deepest one — it
 * catches the crash while the shell, the session and the navigation survive,
 * so `unstable_retry()` can genuinely recover: it re-fetches and re-renders
 * the segment, and a transient Supabase or map failure clears without the
 * operator losing their place.
 */
export default function DashboardError({
  error,
  unstable_retry,
}: {
  error: Error & { digest?: string };
  unstable_retry: () => void;
}) {
  useEffect(() => {
    // Nothing aggregates client errors yet, so the console is the only record.
    // Tagged so it is greppable in a browser session someone screenshots.
    console.error('[HQ_DASHBOARD_CRASH]', error);
  }, [error]);

  return (
    <ConsoleFailure
      scope="Live operations board"
      error={error}
      onRetry={unstable_retry}
    />
  );
}
