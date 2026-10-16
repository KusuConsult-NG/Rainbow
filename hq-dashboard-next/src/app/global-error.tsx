'use client';

import { useEffect } from 'react';
import ConsoleFailure from '@/components/ConsoleFailure';

/**
 * Last line of defence: a crash in the ROOT LAYOUT.
 *
 * `error.tsx` cannot catch this — a boundary does not wrap the layout of its
 * own segment — so without this file a failure in `layout.tsx` (the font
 * loader, the toast provider, `connection()`) renders Next's built-in blank
 * error page and the operator gets no instruction at all.
 *
 * This file REPLACES the root layout when it is active, so it must supply its
 * own `<html>` and `<body>`. That also means it cannot rely on globals.css
 * having loaded or the font variables existing — which is why ConsoleFailure
 * styles itself inline and names a real fallback stack after the font
 * variable.
 *
 * `metadata` exports are not supported in a client component, so the title is
 * set with React's own `<title>`.
 */
export default function GlobalError({
  error,
  unstable_retry,
}: {
  error: Error & { digest?: string };
  unstable_retry: () => void;
}) {
  useEffect(() => {
    console.error('[HQ_ROOT_CRASH]', error);
  }, [error]);

  return (
    <html lang="en">
      <body style={{ margin: 0 }}>
        <title>Console failed — Plateau Eye</title>
        <ConsoleFailure
          scope="Command console (root)"
          error={error}
          onRetry={unstable_retry}
        />
      </body>
    </html>
  );
}
