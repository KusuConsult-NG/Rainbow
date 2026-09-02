/**
 * The console's Content-Security-Policy, built per request around a nonce.
 *
 * WHY A NONCE, AND WHY THIS SHAPE
 *
 * The first version of this policy shipped `script-src 'self' 'unsafe-inline'`,
 * which is honest-looking and nearly useless: `'unsafe-inline'` permits exactly
 * the injected inline script the directive exists to stop. It was written that
 * way because Next's App Router streams its RSC payload through inline
 * <script> tags, and blocking those without a nonce leaves a blank page.
 *
 * A nonce fixes that properly. Next parses the `Content-Security-Policy`
 * request header, extracts `nonce-…`, and stamps it onto the framework and
 * page scripts it emits, so they run while anything injected does not. It
 * requires per-request rendering — a nonce cannot be baked into a statically
 * prerendered page — which is why the root layout opts every route into
 * dynamic rendering.
 *
 * TWO DIRECTIVES ARE DELIBERATELY NOT NONCED.
 *
 * `style-src` keeps `'unsafe-inline'` and MUST NOT be given a nonce. These
 * pages are built almost entirely from React `style={{…}}` props, which
 * server-render as `style="…"` attributes, and CSP blocks those without
 * `'unsafe-inline'`. Crucially, a nonce does not exempt a style ATTRIBUTE — and
 * per the CSP spec, the presence of a nonce makes the browser IGNORE
 * `'unsafe-inline'` entirely. Adding one here would therefore strip the styling
 * off every page. Verified, not assumed.
 *
 * `'strict-dynamic'` is included so scripts loaded BY the nonced bootstrap are
 * trusted. Browsers that honour it ignore `'self'` in this directive; `'self'`
 * stays for those that do not.
 */

/** Origins the console legitimately talks to, enumerated from the source. */
const TILE_HOSTS = [
  'https://*.basemaps.cartocdn.com',
  'https://*.tile.openstreetmap.org',
];

function supabaseOrigins(): string[] {
  const raw = process.env.NEXT_PUBLIC_SUPABASE_URL;
  if (!raw) return [];
  let origin: string;
  try {
    origin = new URL(raw).origin;
  } catch {
    return [];
  }
  // Realtime upgrades to a WebSocket on the same host. Derive the scheme from
  // the URL rather than assuming https: a self-hosted or local Supabase on
  // http speaks ws, and hard-coding wss silently blocks its realtime channel.
  const socket = origin.replace(/^http:/, 'ws:').replace(/^https:/, 'wss:');
  return [origin, socket];
}

/**
 * Builds the policy for one request.
 *
 * @param nonce  a fresh, unpredictable value — one per request, never reused.
 * @param isDev  React uses `eval` in development to rebuild server stacks in
 *               the browser. Production needs no `'unsafe-eval'` and must not
 *               be given it.
 */
export function contentSecurityPolicy(nonce: string, isDev: boolean): string {
  const connect = ["'self'", ...supabaseOrigins()].join(' ');

  return [
    "default-src 'self'",
    `script-src 'self' 'nonce-${nonce}' 'strict-dynamic'${isDev ? " 'unsafe-eval'" : ''}`,
    // No nonce here, on purpose — see the note above.
    "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
    "font-src 'self' data: https://fonts.gstatic.com",
    `img-src 'self' data: blob: ${TILE_HOSTS.join(' ')}`,
    `connect-src ${connect}`,
    "object-src 'none'",
    "base-uri 'self'",
    "form-action 'self'",
    "frame-ancestors 'none'",
    'upgrade-insecure-requests',
  ].join('; ');
}

/** A fresh nonce. Uses the Web Crypto API, which the edge runtime provides. */
export function newNonce(): string {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  return btoa(String.fromCharCode(...bytes));
}
