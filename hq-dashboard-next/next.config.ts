import type { NextConfig } from "next";

/**
 * Static security headers.
 *
 * The Content-Security-Policy is NOT here. It carries a per-request nonce, and
 * `headers()` is static config that cannot mint one, so it is issued from
 * proxy.ts instead — see src/lib/csp.ts for why the nonce matters. Setting a
 * CSP in both places would be actively harmful: a response with two policies
 * must satisfy both, and a static one has no nonce, so the pair would block the
 * scripts the nonce exists to allow.
 */
const SECURITY_HEADERS = [
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
  // (auth guard). The HQ dashboard is served by Railway as a Node server
  // (`npm run start`, see railway.json), which supports SSR and middleware for
  // RBAC enforcement (PRD §4). This was Firebase App Hosting until the move;
  // either way the requirement is the same and it is not a preference — a static
  // export drops middleware silently and serves every page anonymously.
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
