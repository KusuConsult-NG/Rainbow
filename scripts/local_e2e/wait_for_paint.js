'use strict';
/**
 * Wait for the Flutter app to paint, retrying one cold boot.
 *
 * ## Why this is shared rather than copied
 *
 * Five places across three harnesses had their own
 * `page.waitForFunction(() => document.querySelector('flutter-view, …'))` with
 * their own timeout — 60s, 90s, 120s — and no retry. Each one of them failed at
 * some point today, and each failure looked like this:
 *
 *     TimeoutError: Waiting failed: 60000ms exceeded
 *         at .../mobile_interact.js:330:16
 *
 * A bare puppeteer stack at a line number, with nothing saying which screen was
 * loading or how long it really waited. That shape is what sent me chasing CI
 * run #396 up the wrong tree for an hour: I assumed the most recent thing I had
 * touched had broken it, when the truth was a slow boot.
 *
 * The sign-in flow taught the same lesson the harder way — six copies, one
 * updated, two silently passing without signing in at all (see
 * mobile_login.js). So this primitive gets one copy.
 *
 * ## Why a retry is defensible here
 *
 * These harnesses reboot the entire CanvasKit app per screen — a fresh page per
 * route per role, tens of cold boots in a run. A cold start that occasionally
 * exceeds the timeout in a constrained container is infrastructure, not a
 * defect in the app, and the retry covers exactly that. It does NOT paper over a
 * failing assertion: nothing here touches an expectation, and if the app
 * genuinely never paints, both attempts fail and the error names the screen and
 * the seconds actually spent.
 *
 * Adding a retry to make a test pass is usually the wrong move. The narrow
 * justification is the point — if this ever starts hiding a real failure, the
 * message it throws is what will show it.
 */

/**
 * @param {import('puppeteer-core').Page} page
 * @param {string} label  what is loading, for the failure message
 * @param {{ timeout?: number }} [opts]
 */
async function waitForPaint(page, label, { timeout = 120000 } = {}) {
  const began = Date.now();
  const once = () => page.waitForFunction(
    () => !!document.querySelector('flutter-view, flt-glass-pane, canvas'),
    { timeout },
  );
  try {
    await once();
    return;
  } catch {
    // One reload, then one more wait. A cold CanvasKit start that misses the
    // deadline usually succeeds on the second attempt.
  }
  try {
    await page.reload({ waitUntil: 'domcontentloaded' });
  } catch {
    // A page that cannot even reload is reported by the wait below.
  }
  try {
    await once();
  } catch {
    throw new Error(
      `${label}: the app did not paint after two attempts — waited `
      + `${Math.round((Date.now() - began) / 1000)}s. These harnesses reboot `
      + 'the whole app per screen, so this is where a slow cold start shows up '
      + 'first; if it is reproducible, it is the app failing to boot.');
  }
}

module.exports = { waitForPaint };
