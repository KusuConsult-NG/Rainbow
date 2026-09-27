/**
 * Render the MOBILE app's screens, in a browser, at phone size.
 *
 * Every mobile finding in this repository came from reading code or from the
 * widget tests. No screen had been rendered — the audit container has no
 * Android emulator and no device, and for a long time it had no Flutter SDK
 * either, so "the app builds and its tests pass" was the whole of the evidence.
 *
 * Flutter's web target builds the same widget tree from the same Dart, so the
 * screens can be rendered and photographed here. What that is and is not:
 *
 *   IS      the real screens — the same widgets, the same router, the same
 *           state, at phone dimensions, against a stand-in backend
 *   IS NOT  an Android or iOS build. Platform plugins (GPS, camera, secure
 *           storage, notifications) behave differently or not at all on web,
 *           and a screen that depends on one will show its degraded state.
 *           That is worth seeing too, but it is not the same as a device.
 *
 * Two things are served locally because the egress policy blocks them, and
 * because a screenshot of a failed download is not a screenshot of a screen:
 * CanvasKit (which a release build fetches from gstatic) and map tiles.
 *
 *   node scripts/local_e2e/mobile_capture.js
 */

const fs = require('fs');
const http = require('http');
const path = require('path');
const { launch } = require('./browser');
const { DOMAIN, PASSWORD } = require('./fixtures');

const ROOT = path.join(__dirname, '..', '..');
const WEB = path.join(ROOT, 'build', 'web');
const PORT = Number(process.env.MOBILE_PORT || 8080);
const OUT = process.env.E2E_OUT || path.join(ROOT, 'local_e2e_screenshots');

// A phone, not a small desktop window. Layout overflow is the defect class this
// catches, and it only appears at real handset dimensions.
const PHONE = { width: 390, height: 844, deviceScaleFactor: 2, isMobile: true, hasTouch: true };

fs.mkdirSync(OUT, { recursive: true });

const checks = [];
const shots = [];
function check(name, pass, detail = '') {
  checks.push({ name, pass: !!pass, detail });
  console.log(`${pass ? 'PASS' : 'FAIL'}  ${name}${detail ? `  — ${detail}` : ''}`);
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---------------------------------------------------------------------------
// Static server for the built app.
// ---------------------------------------------------------------------------
const TYPES = {
  '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript',
  '.json': 'application/json', '.wasm': 'application/wasm', '.png': 'image/png',
  '.otf': 'font/otf', '.ttf': 'font/ttf', '.woff2': 'font/woff2',
  '.css': 'text/css', '.svg': 'image/svg+xml', '.symbols': 'text/plain',
};

const server = http.createServer((req, res) => {
  const rel = decodeURIComponent(req.url.split('?')[0]).replace(/^\/+/, '') || 'index.html';
  const file = path.join(WEB, rel);
  if (!file.startsWith(WEB) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
    res.writeHead(404); return res.end('not found');
  }
  res.writeHead(200, {
    'content-type': TYPES[path.extname(file)] || 'application/octet-stream',
    // CanvasKit's wasm wants these to use SharedArrayBuffer paths.
    'cross-origin-opener-policy': 'same-origin',
    'cross-origin-embedder-policy': 'require-corp',
    'cross-origin-resource-policy': 'cross-origin',
  });
  fs.createReadStream(file).pipe(res);
});

/** The app's visible text, read out of the semantics tree. */
async function semanticsText(page) {
  return page.evaluate(() => {
    const host = document.querySelector('flt-semantics-host') || document.body;
    const labels = [...host.querySelectorAll('[aria-label]')].map((e) => e.getAttribute('aria-label'));
    return (labels.join('\n') + '\n' + host.innerText).trim();
  });
}

(async () => {
  if (!fs.existsSync(path.join(WEB, 'index.html'))) {
    console.error(
      'build/web is missing. Build it first:\n' +
      '  flutter build web --release --no-web-resources-cdn \\\n' +
      '    --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \\\n' +
      '    --dart-define=SUPABASE_ANON_KEY=local-e2e-anon-key-not-a-real-credential',
    );
    process.exit(1);
  }

  // Fail loudly if the stand-in backend is not up. Without it the app renders
  // perfectly and simply cannot sign in, so every screenshot is the login page
  // and the run looks like an app defect rather than a missing service — which
  // is exactly what happened the first time this was run.
  const backend = 'http://127.0.0.1:54321/auth/v1/health';
  const up = await fetch(backend).then((r) => r.ok).catch(() => false);
  if (!up) {
    console.error(
      `the stand-in backend is not answering at ${backend}.\n` +
      'Start it first:  node scripts/local_e2e/fake_supabase.js',
    );
    process.exit(1);
  }

  await new Promise((r) => server.listen(PORT, '127.0.0.1', r));
  console.log(`[mobile] serving build/web on http://127.0.0.1:${PORT}`);

  const { browser, newPage, problems, state, tiles } = await launch({ viewport: PHONE, canvaskitDir: path.join(WEB, 'canvaskit') });
  const page = await newPage();

  // A release build fetches CanvasKit from gstatic, which the egress policy
  // refuses. The same files are already in build/web/canvaskit, so serve those:
  // otherwise the app never paints and every screenshot is a blank page.

  state.screen = 'mobile:boot';
  await page.goto(`http://127.0.0.1:${PORT}/`, { waitUntil: 'domcontentloaded' });

  // Flutter paints into a canvas; wait for it rather than for the network.
  const painted = await page
    .waitForFunction(
      () => !!document.querySelector('flutter-view, flt-glass-pane, canvas'),
      { timeout: 90000 },
    )
    .then(() => true)
    .catch(() => false);
  check('the app boots and paints in a browser', painted, painted ? '' : 'no canvas appeared');
  await sleep(6000);

  // Without the semantics tree the app is pixels: no text to assert on. Flutter
  // exposes a hidden placeholder that turns it on.
  const semantics = await page.evaluate(() => {
    const ph = document.querySelector('flt-semantics-placeholder');
    if (!ph) return false;
    ph.click();
    return true;
  });
  await sleep(2500);
  check('the accessibility tree can be turned on', semantics,
    semantics ? 'semantics enabled — screen text is readable' : 'no semantics placeholder found');

  const first = await semanticsText(page);
  await page.screenshot({ path: path.join(OUT, '80-mobile-01-launch.png') });
  shots.push('80-mobile-01-launch.png');
  console.log(`      shot  80-mobile-01-launch.png`);

  check(
    'the launch screen is the login, not a crash or a blank canvas',
    /access code|phone|login|sign in|rainbow/i.test(first),
    (first.split('\n').find((l) => l.trim()) || '(no text in the semantics tree)').slice(0, 80),
  );

  // -----------------------------------------------------------------------
  // Sign in as the seeded citizen.
  // -----------------------------------------------------------------------
  state.screen = 'mobile:login';

  // Flutter keeps a real <input> in the DOM for whichever field has focus, so
  // the form is typed into rather than assigned: setting `.value` on a canvas
  // app's shadow input does not reach the widget's controller.
  const typeInto = async (text) => {
    const box = await page.evaluate(() => {
      const el = document.querySelector('input, textarea');
      if (!el) return null;
      el.focus();
      const r = el.getBoundingClientRect();
      return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
    });
    if (!box) return false;
    await page.mouse.click(box.x, box.y);
    await sleep(400);
    await page.keyboard.type(text, { delay: 30 });
    await sleep(500);
    return true;
  };

  const tapLabelled = async (pattern) =>
    page.evaluate((pat) => {
      const re = new RegExp(pat, 'i');
      const hit = [...document.querySelectorAll('flt-semantics[role="button"], [role="button"]')].find(
        (e) => re.test(e.textContent || e.getAttribute('aria-label') || ''),
      );
      if (!hit) return false;
      hit.click();
      return true;
    }, pattern);

  // The citizen path is phone + OTP, with a demo bypass on 08000000000 that
  // signs in with DEMO_CITIZEN_* from .env — pointed at the seeded fixture
  // account for this run.
  const phoneTyped = await typeInto('08000000000');
  await page.screenshot({ path: path.join(OUT, '80-mobile-02-login-filled.png') });
  shots.push('80-mobile-02-login-filled.png');
  check('the login screen accepts typed input', phoneTyped, phoneTyped ? '08000000000' : 'no field');

  await tapLabelled('authorize access|continue|next|send');
  await sleep(3000);
  await page.screenshot({ path: path.join(OUT, '80-mobile-02b-otp-step.png') });
  shots.push('80-mobile-02b-otp-step.png');

  // Second step: the six-digit code. The demo path accepts exactly 123456 and
  // then signs in with DEMO_CITIZEN_* — it is not "any value", and typing the
  // field's own placeholder (000000) is silently rejected.
  const otpTyped = await typeInto('123456');
  check('the OTP step offers a field to type into', otpTyped, otpTyped ? '' : 'no field');
  await tapLabelled('authorize access|verify|confirm|continue|sign in');
  await sleep(6000);
  await page.screenshot({ path: path.join(OUT, '80-mobile-02c-after-signin.png') });
  shots.push('80-mobile-02c-after-signin.png');

  const afterLogin = await page.evaluate(() => window.location.hash);
  const signedIn = !/login/i.test(afterLogin);
  check(
    'signing in as the seeded citizen leaves the login screen',
    signedIn,
    `landed on ${afterLogin || '#/'}`,
  );

  // -----------------------------------------------------------------------
  // Every route, photographed. The router redirects what the session may not
  // reach, which is itself worth seeing — an unauthenticated build should not
  // be able to open the agent dashboard by typing its path.
  // -----------------------------------------------------------------------
  const ROUTES = [
    ['/login', 'login'],
    ['/splash', 'splash'],
    ['/home', 'home'],
    ['/report-initial', 'report-initial'],
    ['/report-category', 'report-category'],
    ['/report-subtype', 'report-subtype'],
    ['/report-details', 'report-details'],
    ['/incident-history', 'incident-history'],
    ['/emergency-active', 'emergency-active'],
    ['/emergency-pins', 'emergency-pins'],
    ['/live-tracking', 'live-tracking'],
    ['/safe-zone', 'safe-zone'],
    ['/secure-chat', 'secure-chat'],
    ['/dispatcher-chat', 'dispatcher-chat'],
    ['/settings', 'settings'],
    ['/uninstall-request', 'uninstall-request'],
    ['/onboarding-profile', 'onboarding-profile'],
    ['/onboarding-permissions', 'onboarding-permissions'],
    ['/onboarding-contacts', 'onboarding-contacts'],
    ['/agent-dashboard', 'agent-dashboard'],
    ['/mission-intel', 'mission-intel'],
    ['/mission-resolution', 'mission-resolution'],
    ['/admin-broadcast', 'admin-broadcast'],
  ];

  const seen = [];
  let n = 2;
  for (const [route, slug] of ROUTES) {
    state.screen = `mobile:${slug}`;
    n += 1;
    await page.evaluate((r) => { window.location.hash = `#${r}`; }, route);
    await sleep(2600);
    const name = `80-mobile-${String(n).padStart(2, '0')}-${slug}.png`;
    await page.screenshot({ path: path.join(OUT, name) });
    shots.push(name);
    const txt = await semanticsText(page);
    const landed = (await page.evaluate(() => window.location.hash)).replace(/^#/, '');
    seen.push({ route, landed, reached: landed === route, chars: txt.length });
    console.log(
      `      shot  ${name}   (${landed === route ? 'reached' : `redirected to ${landed}`}, ${txt.length} chars)`,
    );
  }

  // The first version of this check asked only whether the canvas had any text
  // on it. Every route had redirected to /login, so it passed on 23 photographs
  // of the same screen — a check that cannot fail is worse than no check.
  const reached = seen.filter((s) => s.reached);
  check(
    'the routes actually open rather than all bouncing to login',
    reached.length >= seen.length / 2,
    `${reached.length}/${seen.length} reached; redirected: ` +
      (seen.filter((s) => !s.reached).map((s) => `${s.route}→${s.landed}`).join(', ') || 'none'),
  );
  check(
    'every screen that opened drew something',
    reached.every((s) => s.chars > 0),
    reached.filter((s) => !s.chars).map((s) => s.route).join(', ') || `${reached.length} screens`,
  );

  const fatal = problems.filter(
    (p) => p.kind === 'pageerror' || /uncaught|cannot read|is not a function/i.test(p.text),
  );
  check(
    'no screen threw while rendering',
    fatal.length === 0,
    fatal.length ? `${fatal.length}: ${fatal.slice(0, 3).map((f) => `${f.screen}: ${f.text}`).join(' | ')}` : 'clean',
  );

  fs.writeFileSync(
    path.join(OUT, 'mobile.json'),
    JSON.stringify(
      {
        ranAt: new Date().toISOString(),
        target: 'Flutter web build of the mobile app',
        viewport: PHONE,
        proves:
          'the mobile screens render and route at phone size; NOT an Android/iOS build, ' +
          'and NOT row-level security',
        routes: seen,
        checks,
        screenshots: shots,
        mapTilesRequested: tiles.length,
        browserProblems: problems,
      },
      null,
      2,
    ),
  );

  await browser.close();
  server.close();

  const failed = checks.filter((c) => !c.pass);
  console.log(`\n${checks.length - failed.length}/${checks.length} checks passed, ${shots.length} mobile screenshots in ${OUT}`);
  if (failed.length) {
    console.log('\nFAILED:');
    for (const f of failed) console.log(`  - ${f.name}${f.detail ? `  (${f.detail})` : ''}`);
  }
  process.exit(failed.length ? 1 : 0);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
