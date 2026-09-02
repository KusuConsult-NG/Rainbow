import type { NextConfig } from "next";

/**
 * Origins this dashboard legitimately talks to, enumerated from the source
 * rather than guessed. Keeping them in one place means a new third party has
 * to be added here deliberately instead of arriving unnoticed.
 */
const SUPABASE_ORIGIN = (() => {
  const raw = process.env.NEXT_PUBLIC_SUPABASE_URL;
  if (!raw) return null;
  try {
    return new URL(raw).origin;
  } catch {
    return null;
  }
})();

// Supabase Realtime upgrades to a WebSocket on the same host.
const SUPABASE_WS = SUPABASE_ORIGIN?.replace(/^https:/, 'wss:') ?? null;

// Leaflet basemap tiles (src/components/LiveMap.tsx).
const TILE_HOSTS = [
  'https://*.basemaps.cartocdn.com',
  'https://*.tile.openstreetmap.org',
];

/**
 * Content Security Policy.
 *
 * WHAT THIS DOES AND DOES NOT BUY US — read before trusting it.
 *
 * `frame-ancestors 'none'` is the directive that closes the finding this was
 * written for: the login page had no framing protection at all, so any site
 * could iframe the command console and overlay a lookalike to harvest badge IDs
 * and PINs. That, plus `form-action`, `base-uri` and `object-src`, is real and
 * enforced.
 *
 * `script-src` still carries `'unsafe-inline'`, which means this policy does
 * NOT stop injected inline script — the headline XSS protection is absent.
 * That is a deliberate, documented limit rather than an oversight:
 *
 *   - Next's App Router streams its RSC payload through inline <script> tags.
 *     Blocking inline script without a nonce leaves a blank page.
 *   - Nonces require per-request rendering (see
 *     node_modules/next/dist/docs/01-app/02-guides/content-security-policy.md —
 *     "your page must be dynamically rendered"). Every page here is statically
 *     prerendered, so a nonce cannot be injected into them as they stand.
 *
 * Getting to a strict `script-src` therefore means moving nonce generation into
 * proxy.ts, widening its matcher past the auth guard, and opting every page into
 * dynamic rendering. That is a change to the authentication path and to the
 * rendering model of an authenticated console that no one can exercise from CI,
 * so it is left as a separate, deliberate piece of work.
 *
 * `style-src` carries `'unsafe-inline'` because the pages are built almost
 * entirely from React `style={{…}}` props, which server-render as `style="…"`
 * attributes. CSP blocks those without `'unsafe-inline'`, and a nonce does not
 * exempt them — a nonce in `style-src` would in fact make the browser IGNORE
 * `'unsafe-inline'` and strip the styling off every page.
 */
function contentSecurityPolicy(): string {
  const connect = ["'self'", SUPABASE_ORIGIN, SUPABASE_WS]
    .filter(Boolean)
    .join(' ');

  return [
    "default-src 'self'",
    "script-src 'self' 'unsafe-inline'",
    "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
    "font-src 'self' data: https://fonts.gstatic.com",
    `img-src 'self' data: blob: ${TILE_HOSTS.join(' ')}`,
    `connect-src ${connect}`,
    "object-src 'none'",
    "base-uri 'self'",
    "form-action 'self'",
    "frame-ancestors 'none'",
    "upgrade-insecure-requests",
  ].join('; ');
}

const SECURITY_HEADERS = [
  { key: 'Content-Security-Policy', value: contentSecurityPolicy() },
  // Belt and braces with frame-ancestors: still honoured by older browsers
  // that ignore CSP framing directives.
  { key: 'X-Frame-Options', value: 'DENY' },
  { key: 'X-Content-Type-Options', value: 'nosniff' },
  { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
  // Nothing in this dashboard calls a permission-gated browser API; denying
  // them means an injected script cannot either.
  {
    key: 'Permissions-Policy',
    value: 'geolocation=(), camera=(), microphone=(), payment=(), usb=(), interest-cohort=()',
  },
  // Two years, subdomains included. No `preload` token: that is a one-way
  // submission to a browser-vendor list and is not ours to make from here.
  { key: 'Strict-Transport-Security', value: 'max-age=63072000; includeSubDomains' },
];

const nextConfig: NextConfig = {
  // output: 'export' removed — static export is incompatible with Next.js middleware
  // (auth guard). The HQ dashboard is served via Firebase App Hosting (Node.js runtime)
  // which supports SSR and edge middleware for RBAC enforcement (PRD §4).
  images: {
    unoptimized: true,
  },
  // Do not advertise the framework and version to anyone scanning for a
  // known-vulnerable release.
  poweredByHeader: false,
  async headers() {
    return [{ source: '/:path*', headers: SECURITY_HEADERS }];
  },
};

export default nextConfig;
