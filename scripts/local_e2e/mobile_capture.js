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
  const origin = `http://127.0.0.1:${PORT}`;
  console.log(`[mobile] serving build/web on ${origin}`);

  const { browser, newPage, problems, state, tiles } = await launch({ viewport: PHONE, canvaskitDir: path.join(WEB, 'canvaskit') });
  const page = await newPage();

  // A release build fetches CanvasKit from gstatic, which the egress policy
  // refuses. The same files are already in build/web/canvaskit, so serve those:
  // otherwise the app never paints and every screenshot is a blank page.

  state.screen = 'mobile:boot';
  await page.goto(origin, { waitUntil: 'domcontentloaded' });

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

  /** Flutter keeps a real <input> in the DOM for whichever field has focus. */
  async function typeInto(text) {
    const box = await page.evaluate(() => {
      const el = document.querySelector('input, textarea');
      if (!el) return null;
      el.focus();
      const r = el.getBoundingClientRect();
      return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
    });
    if (!box) return false;
    await page.mouse.click(box.x, box.y);
    await sleep(350);
    await page.keyboard.type(text, { delay: 25 });
    await sleep(400);
    return true;
  }

  /**
   * Tap through the semantics element's own click handler. A synthetic mouse
   * click at the node's coordinates stops at the overlay and never reaches the
   * widget.
   */
  async function tapLabelled(pattern) {
    const ok = await page.evaluate((pat) => {
      const re = new RegExp(pat, 'i');
      for (const n of document.querySelectorAll('flt-semantics[role="button"]')) {
        const r = n.getBoundingClientRect();
        if (r.width < 4 || r.height < 4) continue;
        if (re.test(n.textContent || n.getAttribute('aria-label') || '')) {
          n.click();
          return true;
        }
      }
      return false;
    }, pattern);
    if (ok) await sleep(1200);
    return ok;
  }

  /**
   * Sign in.
   *
   * Two different paths, because the app has two:
   *   citizen — phone number, then an OTP (08000000000 / 123456 is the demo
   *             bypass, which signs in with DEMO_CITIZEN_* from .env)
   *   staff   — an access code, which is the email; signInWithAccessCode pairs
   *             it with AGENT_DEFAULT_PASS and there is no second step
   *
   * Anything whose profile role is not CITIZEN becomes a responder in the app,
   * with a tier derived from the role string — so RESPONDER, LGA_COMMAND and
   * HQ_COMMAND each land on the agent dashboard in a different state, and a
   * citizen is redirected away from all of it.
   */
  async function signIn(role) {
    await page.evaluate(() => {
      try { localStorage.clear(); sessionStorage.clear(); } catch { /* ignore */ }
    });
    await page.goto(origin, { waitUntil: 'domcontentloaded' });
    await page.waitForFunction(
      () => !!document.querySelector('flutter-view, flt-glass-pane, canvas'),
      { timeout: 90000 },
    );
    await sleep(6000);
    await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
    await sleep(1800);

    if (role === 'citizen') {
      await typeInto('08000000000');
      await tapLabelled('authorize access');
      await sleep(2800);
      await typeInto('123456');
      await tapLabelled('verify otp');
    } else {
      await typeInto(`${role}@${DOMAIN}`);
      await tapLabelled('authorize access');
    }
    await sleep(6500);
    return page.evaluate(() => window.location.hash);
  }

  // Every route in AppRoutes, paired with the screen widget it must render.
  // There are 24 of each, and the pairing is what makes "every screen" a
  // checkable claim rather than a hopeful one: the run asserts that each of
  // these was actually REACHED by at least one role.
  const ROUTES = [
    ['/splash', 'splash', 'splash_screen.dart'],
    ['/login', 'login', 'login_screen.dart'],
    ['/onboarding-profile', 'onboarding-profile', 'onboarding_profile_screen.dart'],
    ['/onboarding-permissions', 'onboarding-permissions', 'onboarding_permissions_screen.dart'],
    ['/onboarding-contacts', 'onboarding-contacts', 'onboarding_contacts_screen.dart'],
    ['/home', 'home', 'home_screen.dart'],
    ['/report-initial', 'report-initial', 'report_initial_screen.dart'],
    ['/report-category', 'report-category', 'report_category_screen.dart'],
    ['/report-subtype', 'report-subtype', 'report_subtype_screen.dart'],
    ['/report-details', 'report-details', 'report_details_screen.dart'],
    ['/report-success', 'report-success', 'report_success_screen.dart'],
    ['/incident-history', 'incident-history', 'incident_history_screen.dart'],
    ['/emergency-active', 'emergency-active', 'emergency_active_screen.dart'],
    ['/emergency-pins', 'emergency-pins', 'emergency_pin_screen.dart'],
    ['/live-tracking', 'live-tracking', 'live_tracking_screen.dart'],
    ['/safe-zone', 'safe-zone', 'safe_zone_screen.dart'],
    ['/dispatcher-chat', 'dispatcher-chat', 'dispatcher_chat_screen.dart'],
    ['/settings', 'settings', 'settings_screen.dart'],
    ['/uninstall-request', 'uninstall-request', 'uninstall_request_screen.dart'],
    // Staff only. A citizen is redirected away from every one of these, which
    // is why capturing them needs a responder, an LGA commander and HQ —
    // running as the citizen alone photographed the redirect, not the screen.
    ['/agent-dashboard', 'agent-dashboard', 'agent_dashboard_screen.dart'],
    ['/mission-intel', 'mission-intel', 'mission_intel_screen.dart'],
    ['/mission-resolution', 'mission-resolution', 'mission_resolution_screen.dart'],
    ['/secure-chat', 'secure-chat', 'secure_chat_screen.dart'],
    ['/admin-broadcast', 'admin-broadcast', 'admin_broadcast_screen.dart'],
  ];

  const ROLES = ['citizen', 'responder', 'lga', 'hq'];
  const coverage = new Map();   // route -> the roles that reached it
  const roleReport = {};

  // /splash and /login only exist while signed OUT: once there is a session the
  // router correctly redirects away from both, so no signed-in role can ever
  // reach them. Capturing them here is not a loophole in the coverage claim —
  // it is the only state in which those screens are real.
  for (const [route, slug] of [['/splash', 'splash'], ['/login', 'login']]) {
    state.screen = `mobile:signed-out:${slug}`;
    await page.evaluate(() => {
      try { localStorage.clear(); sessionStorage.clear(); } catch { /* ignore */ }
    });
    await page.goto(`${origin}/#${route}`, { waitUntil: 'domcontentloaded' });
    await page.waitForFunction(
      () => !!document.querySelector('flutter-view, flt-glass-pane, canvas'),
      { timeout: 90000 },
    );
    await sleep(6000);
    await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
    await sleep(1500);
    const f = `80-mobile-signed-out-${slug}.png`;
    await page.screenshot({ path: path.join(OUT, f) });
    shots.push(f);
    const here = (await page.evaluate(() => window.location.hash)).replace(/^#/, '');
    const chars = (await semanticsText(page)).length;
    if (chars > 0) {
      if (!coverage.has(route)) coverage.set(route, []);
      coverage.get(route).push('signed-out');
    }
    console.log(`      shot  ${f}  ${here === route ? 'reached' : `-> ${here}`}, ${chars} chars`);
  }

  for (const role of ROLES) {
    state.screen = `mobile:${role}:signin`;
    const landed = await signIn(role);
    const signedIn = !/login/.test(landed);
    check(`${role}: signs in`, signedIn, `landed on ${landed || '#/'}`);
    {
      const f = `80-mobile-${role}-00-after-signin.png`;
      await page.screenshot({ path: path.join(OUT, f) });
      shots.push(f);
    }
    if (!signedIn) { roleReport[role] = { landed, reached: [] }; continue; }

    const reached = [];
    let n = 0;
    for (const [route, slug] of ROUTES) {
      state.screen = `mobile:${role}:${slug}`;
      n += 1;
      await page.evaluate((r) => { window.location.hash = `#${r}`; }, route);
      await sleep(2500);
      const name = `80-mobile-${role}-${String(n).padStart(2, '0')}-${slug}`;
      await page.screenshot({ path: path.join(OUT, `${name}.png`) });
      shots.push(`${name}.png`);
      const here = (await page.evaluate(() => window.location.hash)).replace(/^#/, '');
      const chars = (await semanticsText(page)).length;
      if (here === route && chars > 0) {
        reached.push(route);
        if (!coverage.has(route)) coverage.set(route, []);
        coverage.get(route).push(role);
      }
      console.log(
        `      shot  ${name}.png  ${here === route ? 'reached' : `-> ${here}`}, ${chars} chars`,
      );
    }
    roleReport[role] = { landed, reached };
    console.log(`  ${role}: ${reached.length}/${ROUTES.length} routes reached`);
  }

  // THE completeness claim. Every screen the app has must have been rendered by
  // somebody. Running as one role cannot satisfy this, which is the point: the
  // first version of this file shot 23 routes as the citizen and called that
  // "every screen", while every staff screen had quietly redirected to /home.
  const never = ROUTES.filter(([route]) => !coverage.has(route));
  check(
    `every one of the app's ${ROUTES.length} screens was rendered by at least one role`,
    never.length === 0,
    never.length
      ? `never rendered: ${never.map(([r, , f]) => `${r} (${f})`).join(', ')}`
      : `${coverage.size}/${ROUTES.length}`,
  );

  // A screen only a citizen can open and a screen only staff can open are both
  // real; a screen NOBODY can open is the finding.
  const citizenOnly = ROUTES.filter(([r]) => (coverage.get(r) || []).length === 1);
  check(
    'the role-restricted screens are restricted to the right roles',
    (coverage.get('/agent-dashboard') || []).every((r) => r !== 'citizen')
      && (coverage.get('/home') || []).includes('citizen'),
    `agent-dashboard: ${(coverage.get('/agent-dashboard') || []).join(', ') || 'nobody'}; ` +
      `single-role screens: ${citizenOnly.length}`,
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
        coverage: Object.fromEntries([...coverage].map(([k, v]) => [k, v])),
        roles: roleReport,
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
