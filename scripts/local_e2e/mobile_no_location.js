/**
 * SOS from a phone with NO LOCATION, in a real browser at phone size.
 *
 *   node scripts/local_e2e/mobile_no_location.js
 *
 * WHY THIS IS A SEPARATE PASS. mobile_interact.js grants geolocation and sets
 * a position before it touches SOS, deliberately — "SOS needs a fix. Without
 * this the permission gate stops the flow before any alert is created, and the
 * run would report SOS broken when it is only unpermitted." That is the right
 * call for that pass. The consequence is that every automated pass over the
 * emergency screen has had a location, and the one state a person in danger
 * can actually be in was the one state nothing exercised.
 *
 * A citizen in Jos pressed SOS on a phone with no fix and the screen showed
 * LOCATION BROADCASTING above a row of dashes, while the alert reached HQ
 * carrying latitude and longitude null. Fixed, with a unit gate and widget
 * tests — and this, which is the only thing that reads the real screen with
 * the real permission denied.
 */
const fs = require('fs');
const path = require('path');
const { launch } = require('./browser');
const { signInMobile } = require('./mobile_login');
const { watchPage, loggedStaticServer } = require('./stall_report');

const ROOT = path.join(__dirname, '..', '..');
const WEB = path.join(ROOT, 'build', 'web');
const PORT = Number(process.env.NO_LOC_PORT || 8085);
const OUT = process.env.E2E_OUT || path.join(ROOT, 'local_e2e_screenshots');
const PHONE = { width: 390, height: 844, deviceScaleFactor: 2, isMobile: true, hasTouch: true };

fs.mkdirSync(OUT, { recursive: true });

const checks = [];
function check(name, pass, detail = '') {
  checks.push({ name, pass: !!pass, detail });
  console.log(`${pass ? 'PASS' : 'FAIL'}  ${name}${detail ? `  — ${detail}` : ''}`);
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const { server, serverLog } = loggedStaticServer(WEB, {});

(async () => {
  if (!fs.existsSync(path.join(WEB, 'index.html'))) {
    console.error('build/web is missing — build the app first (see scripts/local_e2e/run.sh).');
    process.exit(1);
  }
  const up = await fetch('http://127.0.0.1:54321/auth/v1/health').then((r) => r.ok).catch(() => false);
  if (!up) {
    console.error('the stand-in backend is not answering. Start it:  node scripts/local_e2e/fake_supabase.js');
    process.exit(1);
  }

  await new Promise((r) => server.listen(PORT, '127.0.0.1', r));
  const origin = `http://127.0.0.1:${PORT}`;

  const { browser, newPage, state } = await launch({
    viewport: PHONE,
    canvaskitDir: path.join(WEB, 'canvaskit'),
  });

  // THE WHOLE POINT: geolocation is NOT granted. No overridePermissions, no
  // setGeolocation. The page is refused a position, exactly as a handset with
  // location switched off or the permission declined refuses one.
  await browser.defaultBrowserContext().clearPermissionOverrides();

  const page = await newPage();
  const watch = watchPage(page, { serverLog });

  const screenText = () =>
    page.evaluate(() => {
      const host = document.querySelector('flt-semantics-host') || document.body;
      return (
        [...host.querySelectorAll('[aria-label]')].map((e) => e.getAttribute('aria-label')).join('\n')
        + '\n' + host.innerText
      ).trim();
    });

  const findNode = (pattern, { role = null } = {}) =>
    page.evaluate(
      (pat, wantRole) => {
        const re = new RegExp(pat, 'i');
        for (const n of [...document.querySelectorAll('flt-semantics')]) {
          const r = n.getBoundingClientRect();
          if (r.width < 4 || r.height < 4) continue;
          if (wantRole && n.getAttribute('role') !== wantRole) continue;
          const txt = (n.textContent || '') + ' ' + (n.getAttribute('aria-label') || '');
          if (re.test(txt) && r.height < (wantRole === 'button' ? 400 : 220)) {
            return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
          }
        }
        return null;
      },
      pattern,
      role,
    );

  async function tap(pattern, { role = null, settle = 900 } = {}) {
    const n = await findNode(pattern, { role });
    if (!n) return false;
    await page.mouse.click(n.x, n.y);
    await sleep(settle);
    return true;
  }

  async function shot(name) {
    await page.screenshot({ path: path.join(OUT, `${name}.png`) });
    console.log(`      shot  ${name}.png`);
  }

  state.screen = 'mobile:no-location:boot';
  await page.goto(origin, { waitUntil: 'domcontentloaded' });
  await watch.waitForApp(90000, OUT);
  await sleep(6500);
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await sleep(2000);
  await signInMobile(page, 'citizen');

  const home = await page.evaluate(() => window.location.hash);
  if (!/home/.test(home)) {
    check('signed in as the seeded citizen', false, `on ${home}`);
    await shot('95-no-location-signin-failed');
    await browser.close(); server.close(); process.exit(1);
  }
  check('signed in as the seeded citizen', true);

  // Three taps inside three seconds: the Silent SOS. With no fix it still has
  // to go — an alert without a position is worth more than no alert.
  state.screen = 'mobile:no-location:sos';
  const SOS = 'TAP 3 TIMES';
  await tap(SOS, { role: 'button', settle: 300 });
  await tap(SOS, { role: 'button', settle: 300 });
  const tapped = await tap(SOS, { role: 'button', settle: 5000 });
  check('SOS still sends with no location', tapped, tapped ? '' : 'SOS control not found');

  await page.evaluate(() => { window.location.hash = '#/emergency-active'; });
  await sleep(3500);
  state.screen = 'mobile:no-location:emergency';
  await shot('95-no-location-emergency-active');

  const text = await screenText();

  check(
    'the screen does NOT say LOCATION BROADCASTING',
    !/LOCATION BROADCASTING/i.test(text),
    'this is the exact string the citizen in Jos was shown with nothing to send',
  );
  check(
    'the screen says plainly that no location is going out',
    /NO LOCATION BEING SENT/i.test(text),
    text.match(/NO LOCATION[^\n]*/i)?.[0] || 'not found',
  );
  check(
    'it offers a way to turn location on',
    /TURN ON LOCATION|OPEN APP SETTINGS/i.test(text),
  );
  check(
    'it does not claim the location is still being recorded',
    !/location is still being recorded/i.test(text),
  );
  check(
    'it does not promise to send a location it has not got',
    !/alert and location/i.test(text),
  );

  await browser.close();
  server.close();

  const failed = checks.filter((c) => !c.pass);
  console.log(`\n${checks.length - failed.length}/${checks.length} checks passed.`);
  if (failed.length) {
    console.error('\nFAILED:');
    for (const f of failed) console.error(`  - ${f.name}${f.detail ? `  — ${f.detail}` : ''}`);
    process.exit(1);
  }
  console.log('OK: with no fix, the emergency screen says so and claims nothing.');
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
