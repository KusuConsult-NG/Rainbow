import localFont from 'next/font/local';

/**
 * The console's two typefaces, self-hosted.
 *
 * WHY NOT GOOGLE FONTS AT RUNTIME
 *
 * `globals.css` used to `@import` Inter and Outfit from fonts.googleapis.com.
 * That is a runtime dependency on a third party, and on a restricted
 * government network — the same condition that made Leaflet-from-unpkg a
 * finding (M-10) — the request fails and every label on the console quietly
 * falls back to a system font. The Flutter web target hit exactly this and now
 * bundles its resources (`build_web.sh`); the console never got the same fix.
 *
 * It also left two directives of the Content-Security-Policy unverifiable:
 * the audit environment cannot reach Google Fonts, so `font-src` and
 * `style-src` were never exercised in a browser — and two of the three CSP
 * directives that WERE "verified" turned out to be wrong.
 *
 * WHY `next/font/local` AND NOT `next/font/google`
 *
 * `next/font/google` downloads the files at BUILD time. That moves the network
 * dependency from the browser to CI, which is not an improvement on a network
 * that cannot reach Google either. These files are the same Inter and Outfit
 * the mobile app already ships (assets/google_fonts, SIL Open Font License),
 * converted to WOFF2 with fontTools — 4.3 MB of TTF down to ~1.3 MB, served
 * from `'self'` under /_next/static/media with no request leaving the origin.
 *
 * Every weight the console uses is present: 500–900 (plus 400 for
 * completeness). Weight 850, used twice, has no file and snaps to the nearest
 * — the same behaviour it had against Google's CSS.
 *
 * Both are exposed as CSS variables rather than class names because the
 * console names its fonts in ~60 inline `style={{ fontFamily }}` props and a
 * handful of CSS rules; `var(--font-outfit)` drops into all of them.
 */
export const inter = localFont({
  variable: '--font-inter',
  display: 'swap',
  src: [
    { path: './fonts/Inter-Regular.woff2', weight: '400', style: 'normal' },
    { path: './fonts/Inter-Medium.woff2', weight: '500', style: 'normal' },
    { path: './fonts/Inter-SemiBold.woff2', weight: '600', style: 'normal' },
    { path: './fonts/Inter-Bold.woff2', weight: '700', style: 'normal' },
    { path: './fonts/Inter-ExtraBold.woff2', weight: '800', style: 'normal' },
    { path: './fonts/Inter-Black.woff2', weight: '900', style: 'normal' },
  ],
});

export const outfit = localFont({
  variable: '--font-outfit',
  display: 'swap',
  src: [
    { path: './fonts/Outfit-Regular.woff2', weight: '400', style: 'normal' },
    { path: './fonts/Outfit-Medium.woff2', weight: '500', style: 'normal' },
    { path: './fonts/Outfit-SemiBold.woff2', weight: '600', style: 'normal' },
    { path: './fonts/Outfit-Bold.woff2', weight: '700', style: 'normal' },
    { path: './fonts/Outfit-ExtraBold.woff2', weight: '800', style: 'normal' },
    { path: './fonts/Outfit-Black.woff2', weight: '900', style: 'normal' },
  ],
});
