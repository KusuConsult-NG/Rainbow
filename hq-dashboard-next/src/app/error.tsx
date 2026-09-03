'use client';

import { useEffect } from 'react';
import ConsoleFailure from '@/components/ConsoleFailure';

/**
 * Error boundary for every route that is not the dashboard — login, and
 * anything added later that forgets to bring its own.
 *
 * `error.tsx` does not wrap the layout in its own segment, so a crash in the
 * root layout falls through to `global-error.tsx` instead. Both exist.
 */
export default function AppError({
  error,
  unstable_retry,
}: {
  error: Error & { digest?: string };
  unstable_retry: () => void;
}) {
  useEffect(() => {
    console.error('[HQ_CONSOLE_CRASH]', error);
  }, [error]);

  return <ConsoleFailure scope="Command console" error={error} onRetry={unstable_retry} />;
}
