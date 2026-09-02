import type { Metadata } from 'next';
import { connection } from 'next/server';
import './globals.css';
import { inter, outfit } from './fonts';
import { ToastProvider } from '@/components/ToastProvider';

export const metadata: Metadata = {
  title: 'Operation Rainbow — Command HQ',
  description: 'Plateau State Emergency Response Command Dashboard',
};

/**
 * Every route renders per request.
 *
 * This is what makes the nonced CSP possible. Next injects the nonce during
 * server-side rendering, by reading the `Content-Security-Policy` header off
 * the incoming request — so a statically prerendered page, generated at build
 * time when no request exists, can never carry one. Without this the policy in
 * proxy.ts would block the framework's own bootstrap scripts and every page
 * would render blank.
 *
 * `await connection()` is the documented way to opt in (see
 * node_modules/next/dist/docs/01-app/02-guides/content-security-policy.md).
 * The cost is real but small here: this is an authenticated operations console
 * for a handful of officers, not a public site trading on cache hits.
 */
export default async function RootLayout({ children }: { children: React.ReactNode }) {
  await connection();

  return (
    // The two font variables are scoped to <html> so `var(--font-inter)` and
    // `var(--font-outfit)` resolve everywhere — including inside Leaflet
    // popups, which are injected as HTML strings and pick up document CSS.
    <html lang="en" className={`${inter.variable} ${outfit.variable}`}>
      <body>
        <ToastProvider>
          {children}
        </ToastProvider>
      </body>
    </html>
  );
}
