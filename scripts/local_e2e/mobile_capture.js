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
const { DOMAIN, PASSWORD, byKey } = require('./fixtures');
const { signInMobile } = require('./mobile_login');

const ROOT = path.join(__dirname, '..', '..');
const WEB = path.join(ROOT, 'build', 'web');
const PORT = Number(process.env.MOBILE_PORT || 8080);
const OUT = process.env.E2E_OUT || path.join(ROOT, 'local_e2e_screenshots');

// A phone, not a small desktop window. Layout overflow is the defect class this
// catches, and it only appears at real handset dimensions.
const PHONE = { width: 390, height: 844, deviceScaleFactor: 2, isMobile: true, hasTouch: true };

fs.mkdirSync(OUT, { recursive: true });

const os = require('os');

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

/**
 * What the stand-in recorded. Only used for the RPC claim below, which is why
 * this file never needed it before — and is why the claim was never made.
 */
async function control() {
  return new Promise((resolve) => {
    http.get('http://127.0.0.1:54322/', (res) => {
      let d = '';
      res.on('data', (c) => (d += c));
      res.on('end', () => { try { resolve(JSON.parse(d)); } catch { resolve({}); } });
    }).on('error', () => resolve({}));
  });
}

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

  // The collectors live out here so a browser restart does not lose them.
  const tiles = [];
  const problems = [];
  const state = { screen: 'startup' };
  const LAUNCH = { viewport: PHONE, canvaskitDir: path.join(WEB, 'canvaskit'), tiles, problems, state };

  let { browser, newPage } = await launch(LAUNCH);
  let page = await newPage();

  /**
   * Replace the browser.
   *
   * Eight accounts, twenty-four routes each, in one CanvasKit browser exhausted
   * this container on the eighth: the process died mid-screenshot and the run
   * ended on `TargetCloseError` with no report written. The screens captured
   * before that were fine, which is the dangerous part — a partial run that
   * looks like a crash rather than like missing coverage.
   */
  async function freshBrowser() {
    // `browser.close()` resolves when the DevTools websocket closes, which is
    // NOT when the process is gone: a wedged renderer can outlive it. Eight
    // roles meant eight launches, and if even a few linger the runner is
    // carrying several CanvasKit Chromiums at once. Wait for the process, then
    // insist.
    const dying = browser.process?.();
    try { await browser.close(); } catch { /* already gone */ }
    if (dying && dying.exitCode === null) {
      await Promise.race([
        new Promise((r) => dying.once('exit', r)),
        sleep(5000),
      ]);
      if (dying.exitCode === null) {
        try { dying.kill('SIGKILL'); } catch { /* already gone */ }
        await Promise.race([
          new Promise((r) => dying.once('exit', r)),
          sleep(2000),
        ]);
      }
    }
    ({ browser, newPage } = await launch(LAUNCH));
    page = await newPage();
  }

  /** What the machine has left, so a resource failure says so rather than timing out. */
  function freeMemory() {
    const free = os.freemem() / 1024 / 1024;
    const total = os.totalmem() / 1024 / 1024;
    return `${free.toFixed(0)}MB free of ${total.toFixed(0)}MB`;
  }

  /**
   * Wait for Flutter to paint, and say what was on the page if it never does.
   *
   * On a CI runner this is where the run has died twice: the 4th role, then
   * the 6th, with nothing but `TimeoutError: Waiting failed: 120000ms
   * exceeded` and a puppeteer stack. That names the line and says nothing
   * about WHY — whether the bundle 404'd, the renderer was killed, or the
   * machine was out of memory. A harness whose failure teaches you nothing
   * costs a whole CI cycle to learn nothing twice.
   */
  // Overridable so a slower runner can be given longer — and so the failure
  // path below can be exercised deliberately rather than only in production:
  //   MOBILE_PAINT_TIMEOUT_MS=1 node scripts/local_e2e/mobile_capture.js
  const PAINT_TIMEOUT = Number(process.env.MOBILE_PAINT_TIMEOUT_MS) || 120000;

  async function waitForPaint(what, timeout = PAINT_TIMEOUT) {
    try {
      await page.waitForFunction(
        () => !!document.querySelector('flutter-view, flt-glass-pane, canvas'),
        { timeout },
      );
      return;
    } catch (err) {
      const seen = await page.evaluate(() => ({
        readyState: document.readyState,
        htmlChars: document.documentElement.outerHTML.length,
        scripts: [...document.querySelectorAll('script')].map((t) => t.src || 'inline'),
        bodyText: (document.body?.innerText || '').slice(0, 200),
      })).catch((e) => ({ unreadable: String(e) }));
      try {
        await page.screenshot({
          path: path.join(OUT, `80-mobile-${what}-never-painted.png`),
        });
      } catch { /* the page may be gone too */ }
      const last = problems.length
        ? JSON.stringify(problems[problems.length - 1]).slice(0, 300)
        : 'none';
      throw new Error(
        `the app never painted for ${what} within ${timeout}ms.`
        + `\n    memory:  ${freeMemory()}`
        + `\n    page:    ${JSON.stringify(seen)}`
        + `\n    console problems so far: ${problems.length}, last: ${last}`,
      );
    }
  }

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
   *   citizen — phone number, then the code sent to it. The real path: the
   *             demo bypass this used to take is compiled out of release
   *             builds, and the stand-in answers /auth/v1/otp and
   *             /auth/v1/verify so the harness exercises what ships.
   *   staff   — an access code, which is the email; signInWithAccessCode pairs
   *             it with AGENT_DEFAULT_PASS and there is no second step
   *
   * Anything whose profile role is not CITIZEN becomes a responder in the app,
   * with a tier derived from the role string — so RESPONDER, LGA_COMMAND and
   * HQ_COMMAND each land on the agent dashboard in a different state, and a
   * citizen is redirected away from all of it.
   */
  async function signIn(role) {
    // A FRESH PAGE per role, not a reload.
    //
    // Reusing one page meant booting the whole Flutter app a fourth time in a
    // tab that had already rendered ~100 screenshots, and on a CI runner the
    // fourth boot never finished: `waitForFunction` timed out after 90s and the
    // HQ role was never captured. Locally, with more memory, the same code
    // passed — which is the CI-only failure this project keeps producing.
    //
    // A new page also clears storage for free, so the session cannot leak from
    // one role into the next.
    try { await page.close(); } catch { /* already gone */ }
    page = await newPage();

    // A new PAGE does not mean new storage: localStorage is per origin per
    // browser context, so the previous role's Supabase session is still there
    // and the app signs straight back in as them. Dropping the explicit clear
    // when this stopped reloading is exactly what happened — every staff role
    // came back as the citizen and landed on /home, and the run reported the
    // agent dashboard as unreachable by anyone.
    await page.goto(origin, { waitUntil: 'domcontentloaded' });
    await page.evaluate(() => {
      try { localStorage.clear(); sessionStorage.clear(); } catch { /* blocked */ }
    });
    await page.reload({ waitUntil: 'domcontentloaded' });
    await waitForPaint(`${role}-signin`);
    await sleep(6000);
    await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
    await sleep(1800);

    if (role === 'citizen') {
      // The REAL citizen sign-in: a phone number, then a code sent to it.
      //
      // This used to type 08000000000 and 123456 — the app's demo bypass,
      // which swapped in an email/password login behind the scenes. That is
      // compiled out of release builds now (AuthService.isDemoNumber returns
      // false under kReleaseMode), because in a shipped APK it was a published
      // credential: the number is in the source and the password is in the
      // bundled .env, which extracts with `unzip`.
      //
      // So the harness could not sign a citizen in at all — which is worth
      // recording, because it means every citizen test here had been
      // travelling through a door production does not have. The stand-in
      // answers /auth/v1/otp and /auth/v1/verify now, so this is the path a
      // citizen actually takes.
      return signInMobile(page, 'citizen');
    }
    // Staff: a badge AND a password, in two steps. The branch here typed the
    // badge, tapped AUTHORIZE ACCESS and returned the hash — which stopped
    // being a sign-in the day the password step arrived. See mobile_login.js.
    return signInMobile(page, role);
  }

  // SIX ROUTES RENDER A DIFFERENT SCREEN WHEN REACHED BY URL.
  //
  // Their `pageBuilder` needs `state.extra` — an alert, a category — and falls
  // back to another screen when it is null, which is correct: a URL cannot
  // carry an incident. This walk reaches every route BY URL, so for these six
  // it photographs the fallback, the hash still reads the route it asked for,
  // and `here === route` holds. They were therefore counted as covered, and the
  // claim below — "every one of the app's screens was rendered" — was false for
  // a quarter of them while reading green.
  //
  // `/lock` had this treatment already, with a comment: it cannot be reached by
  // URL either, so the walk reaches it the way a person does. These six cannot
  // be given that treatment here, because each needs an incident that another
  // harness creates — so they are named, excluded from the claim, and the claim
  // says where their real coverage lives.
  //
  // `scripts/check_the_capture_counts_only_what_it_rendered.py` asserts this
  // map against `app_router.dart` in both directions: a new fallback route
  // cannot go unlisted, and a listed one cannot outlive its fallback. T-81.
  const URL_RENDERS_A_FALLBACK = {
    '/mission-intel': 'agent_dashboard_screen.dart — needs an alert; driven by tier_controls.js',
    '/mission-resolution': 'agent_dashboard_screen.dart — needs an alert; driven by tier_controls.js',
    '/secure-chat': 'agent_dashboard_screen.dart — needs an alert; driven by chat_thread.js',
    '/dispatcher-chat': 'home_screen.dart — needs an alert; driven by chat_thread.js',
    '/report-subtype': 'report_category_screen.dart — needs a category; driven by mobile_interact.js',
    '/report-details': 'report_category_screen.dart — needs a category; driven by mobile_interact.js',
  };

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
    // LAST, and it has to be.
    //
    // Two things about this route are unlike every other one here. It cannot
    // be reached by URL — the router sends anybody at /lock who is not locked
    // back to their home screen, which is what stops a lock screen appearing
    // over a live emergency — so it is reached the way a person reaches it,
    // through Settings → Lock This Phone.
    //
    // And reaching it LOCKS THE APP. Put it in the middle of this list and
    // every route after it correctly redirects to /lock, so the walk captures
    // the lock screen over and over and reports the rest as unreachable. The
    // first version of this sat after /settings and did exactly that, which is
    // a good demonstration that the gate works and a bad way to photograph
    // twenty-five screens.
    ['/lock', 'lock', 'lock_screen.dart'],
  ];

  // The whole command chain, bottom to top, plus a citizen and an untiered
  // responder. Capturing only responder/LGA/HQ left the polling-unit and ward
  // rungs — two of the four — never rendered.
  // Every account type that can sign in. The command chain bottom to top,
  // the untiered responder, and both agency liaisons — all of them land in the
  // responder app, and only three of the eight had ever been rendered.
  const ROLES = ['citizen', 'responder', 'unit', 'ward', 'lga', 'hq', 'police', 'army'];
  const coverage = new Map();   // route -> the roles that reached it
  const feedText = {};          // role -> the mission feed as rendered
  const setupText = {};         // role -> the first screen of first-run setup
  const roleReport = {};
  /** role -> which seeded advisory was on screen. See the block in the loop. */
  const advisoryReport = {};

  // /splash and /login only exist while signed OUT: once there is a session the
  // router correctly redirects away from both, so no signed-in role can ever
  // reach them. Capturing them here is not a loophole in the coverage claim —
  // it is the only state in which those screens are real.
  for (const [route, slug] of [['/splash', 'splash'], ['/login', 'login']]) {
    state.screen = `mobile:signed-out:${slug}`;
    try { await page.close(); } catch { /* already gone */ }
    page = await newPage();
    // Clear this origin's storage WITHOUT booting the app to get at it.
    //
    // This used to `goto(origin)`, then clear `localStorage` from the page,
    // then `goto(origin + '/#' + route)`. Both halves of that are a race:
    //
    //   * `goto` resolves at DOMContentLoaded, which is BEFORE Flutter boots.
    //     So the clear landed in the middle of start-up, while
    //     `Supabase.initialize` was reading the very keys being deleted.
    //   * the second `goto` differs from the first only by fragment — and for
    //     a signed-out visit the app has already redirected itself to
    //     `#/login` — so it is a same-document navigation. Nothing reloads.
    //     Whether `flutter-view` ever appears therefore depends entirely on
    //     that first, interfered-with boot completing.
    //
    // When it did not, the wait below burned its full 120s and the job failed
    // on a timeout with no explanation. It passed on the previous push with
    // byte-identical application code, which is what a race looks like.
    //
    // `Storage.clearDataForOrigin` is browser-level: it needs no page, so the
    // app boots once, from clean storage, at the route being captured.
    const cdp = await page.createCDPSession();
    await cdp.send('Storage.clearDataForOrigin', {
      origin,
      storageTypes: 'local_storage,session_storage,indexeddb,websql,cache_storage',
    });
    await cdp.detach();
    await page.goto(`${origin}/#${route}`, { waitUntil: 'domcontentloaded' });
    await waitForPaint(`signed-out${route.replace(/\//g, '-')}`);
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
    // One role falling over must not discard the five that worked, nor the
    // report. The hq role timed out on a CI runner and the throw took the
    // whole script with it: police and army were never attempted, no
    // report was written, and the artifact held 133 screenshots nothing
    // described. The run still fails — it records a failed check — but it
    // finishes, and says which roles got through.
    try {
      state.screen = `mobile:${role}:signin`;
      await freshBrowser();
      const landed = await signIn(role);
      const signedIn = !/login/.test(landed);
      check(`${role}: signs in`, signedIn, `landed on ${landed || '#/'}`);
      {
        const f = `80-mobile-${role}-00-after-signin.png`;
        await page.screenshot({ path: path.join(OUT, f) });
        shots.push(f);
      }
      if (!signedIn) { roleReport[role] = { landed, reached: [] }; continue; }

      // The dashboard banner names the tier; grab it before walking the routes.
      const landingText = await semanticsText(page);
      const banner = landingText.split('\n').map((l) => l.trim())
        .find((l) => /COMMAND|OPERATIONAL UNIT|CITIZEN/.test(l)) || '';

      // WHICH ADVISORY REACHED THIS PERSON.
      //
      // `SystemAlertListener` wraps every screen, so an advisory addressed to this
      // role is on the landing screen. Two are seeded: one scoped to NARAGUTA
      // ward, and one legacy row carrying its audience in `target_type` and
      // addressed to AGENTS. Every fixture person is in NARAGUTA except the ARMY
      // liaison, who is in PANYAM — so the pair tells the roles apart, and the
      // assertions below are the only end-to-end check of T-29 outside the widget
      // tests.
      advisoryReport[role] = {
        ward: /naraguta junction/i.test(landingText),
        legacyAgents: /radio discipline/i.test(landingText),
      };

      const reached = [];
      let n = 0;
      for (const [route, slug] of ROUTES) {
        state.screen = `mobile:${role}:${slug}`;
        n += 1;
        if (route === '/lock') {
          // The one screen a URL cannot reach, by design: the router sends
          // anybody at /lock who is not locked back to their home screen, which
          // is what stops a lock screen appearing over a live emergency. So it
          // is reached the way a person reaches it — Settings, then "Lock This
          // Phone".
          await page.evaluate(() => { window.location.hash = '#/settings'; });
          await sleep(2500);
          await tapLabelled('lock this phone');
          await sleep(2500);
        } else {
          await page.evaluate((r) => { window.location.hash = `#${r}`; }, route);
          await sleep(2500);
        }
        const name = `80-mobile-${role}-${String(n).padStart(2, '0')}-${slug}`;
        await page.screenshot({ path: path.join(OUT, `${name}.png`) });
        shots.push(`${name}.png`);
        const here = (await page.evaluate(() => window.location.hash)).replace(/^#/, '');
        const screenText = await semanticsText(page);
        const chars = screenText.length;
        // WHICH INCIDENTS THIS OFFICER'S MISSION FEED SHOWS. Asserted after the
        // loop: the word "liaison" appeared nowhere in lib/, so the feed filter
        // had no branch for one and answered them from their own POSTING.
        if (route === '/agent-dashboard' && here === route) {
          feedText[role] = screenText;
        }
        // THE LANGUAGE CONTROL ON THE FIRST SCREEN OF SETUP. Asserted after the
        // loop: the picker in Settings wrote `app_language` = 'HA' while every
        // translated string watches `app_lang` = 'ha', so choosing Hausa changed
        // nothing, and the only working control was a flag button three screens
        // further in.
        if (route === '/onboarding-permissions' && here === route) {
          setupText[role] = screenText;
        }
        const fellBack = URL_RENDERS_A_FALLBACK[route];
        if (here === route && chars > 0 && !fellBack) {
          reached.push(route);
          if (!coverage.has(route)) coverage.set(route, []);
          coverage.get(route).push(role);
        }
        console.log(
          `      shot  ${name}.png  ${
            fellBack ? `FALLBACK (${fellBack.split(' —')[0]})`
            : here === route ? 'reached' : `-> ${here}`}, ${chars} chars`,
        );
      }
      roleReport[role] = { landed, banner, reached };
      console.log(`  ${role}: ${reached.length}/${ROUTES.length} routes reached`);
    } catch (err) {
      const [first, ...rest] = String(err && err.message ? err.message : err).split('\n');
      check(`${role}: is captured at all`, false, first);
      for (const line of rest) console.log(line);
      roleReport[role] = { landed: 'threw', banner: '', reached: [], error: first };
    }
  }

  // THE completeness claim. Every screen the app has must have been rendered by
  // somebody. Running as one role cannot satisfy this, which is the point: the
  // first version of this file shot 23 routes as the citizen and called that
  // "every screen", while every staff screen had quietly redirected to /home.
  const byUrl = ROUTES.filter(([route]) => !URL_RENDERS_A_FALLBACK[route]);
  const never = byUrl.filter(([route]) => !coverage.has(route));
  check(
    `every one of the app's ${byUrl.length} URL-reachable screens was rendered `
    + `by at least one role`,
    never.length === 0,
    never.length
      ? `never rendered: ${never.map(([r, , f]) => `${r} (${f})`).join(', ')}`
      : `${coverage.size}/${byUrl.length}; the other `
        + `${Object.keys(URL_RENDERS_A_FALLBACK).length} need an incident a URL `
        + `cannot carry and are driven elsewhere: `
        + Object.entries(URL_RENDERS_A_FALLBACK)
            .map(([r, why]) => `${r} <- ${why.split('driven by ')[1]}`)
            .join(', '),
  );

  // THE LANGUAGE CAN BE CHOSEN BEFORE THE REST OF SETUP IS READ.
  //
  // Everything below the picker on that screen is read by somebody who may not
  // read English. The only language control used to be a flag button on the
  // home screen, which is three screens past here, and the one in Settings was
  // wired to a key no reader has ever heard of.
  const setup = (setupText.citizen || '').toLowerCase();
  for (const language of ['english', 'hausa', 'pidgin']) {
    check(
      `first-run setup offers ${language}`,
      setup.includes(language),
      setup.includes(language)
        ? 'on the first screen, before anything it has to explain'
        : `not offered. screen was: ${setup.replace(/\s+/g, ' ').slice(0, 160)}`,
    );
  }

  // AN OUTSIDE AGENCY SEES WHAT WAS HANDED TO THEM, AND ONLY THAT.
  //
  // RLS says so — `alert_is_ours()` gives a liaison exactly
  // `escalated_to_agency = liaison_agency()` — and the handset's filter had no
  // branch for a liaison at all, so it fell through to the place rules and
  // answered them from their own posting.
  //
  // Both fixtures are needed to see it. a005 is handed to the ARMY and sits in
  // MANGU/PANYAM/PU-11, which is exactly where the Army liaison is posted, so
  // the old filter admitted it by coincidence. a006 is handed to the POLICE and
  // is in BOKKOS while the Police liaison is posted to JOS NORTH, so only a
  // filter that reads the column can deliver it — and the four incidents handed
  // to NOBODY are all in JOS NORTH, so only a filter that reads the column
  // keeps them out.
  //
  // This stand-in applies no RLS, which is why no run caught this: the Police
  // liaison was shown four incidents never handed to the Police. Empty against
  // production, wrong here, green in both.
  // READ THE STAND-IN, DO NOT TRUST THE FIXTURE.
  //
  // This block used to name the incidents by hand: a005 is the Army's, a006 is
  // the Police's, and a001 ("Armed men at the junction") is handed to nobody.
  // That was true of `fixtures.js` and false by the time this pass ran.
  //
  // `interact.js` runs first, against the same stand-in, and it presses the
  // console's real controls — including ESCALATE, on whichever incident owns
  // the first ESCALATE button on the feed. Polled every ten seconds during a
  // run, a001 went:
  //
  //     PENDING -> DISPATCHED -> RESOLVED -> PENDING -> ESCALATED('ALL')
  //
  // and was never restored. The agency it lands on is not pinned either: the
  // harness picks ARMY if the modal offers it, POLICE if not, and the form's
  // own default ('ALL') when it finds no select at all. So on some runs a001
  // really is handed to the Police — and this pass then reported the Police
  // liaison seeing it as "an incident escalated to nobody reached an outside
  // agency", which was a failure of the assertion, not of the app.
  //
  // The rule worth asserting does not depend on any of that: an incident
  // reaches a liaison if and only if it is escalated to THEIR agency. So read
  // what the stand-in holds at this moment and assert that.
  const liveAlerts = await fetch(
    'http://127.0.0.1:54321/rest/v1/alerts?select=description,escalated_to_agency,status,assigned_to,assigned_responders',
  ).then((r) => r.json()).catch(() => null);

  check(
    'the stand-in can still be read, so the liaison rules are checked against real state',
    Array.isArray(liveAlerts) && liveAlerts.length > 0,
    Array.isArray(liveAlerts)
      ? `${liveAlerts.length} alert(s) read back`
      : 'could not read alerts from the stand-in — the checks below would be vacuous',
  );

  if (Array.isArray(liveAlerts) && liveAlerts.length) {
    // A description short enough to appear by accident is not a probe. Nothing
    // in the fixtures is this short; the guard is here so that adding one does
    // not silently turn a safety check into a coin toss.
    const probe = (a) =>
      (a.description || '').trim().replace(/\.$/, '').toLowerCase();
    const usable = liveAlerts.filter((a) => probe(a).length >= 12);
    const handedTo = (a) =>
      (a.escalated_to_agency || '').trim().toUpperCase();

    for (const [role, agency] of [['police', 'POLICE'], ['army', 'ARMY']]) {
      const feed = (feedText[role] || '').toLowerCase();
      const uid = byKey(role).id;

      // An incident DISPATCHED to this officer by name is theirs whatever it
      // was escalated to — `alertReaches` rule 1, before the agency rule — and
      // the console pass dispatches a real incident to a real responder on
      // every run. Counting one of those as a leak would be the same mistake
      // in the other direction: an assertion that fails on correct behaviour.
      const assignedToThem = (a) =>
        a.assigned_to === uid ||
        (Array.isArray(a.assigned_responders) && a.assigned_responders.includes(uid));

      const theirs = usable.filter((a) => handedTo(a) === agency);
      const notTheirs = usable.filter(
        (a) => handedTo(a) !== agency && !assignedToThem(a),
      );

      // THE SAFETY PROPERTY. Nothing that was not handed to this agency may be
      // on this agency's handset — whatever it was handed to instead, and
      // whoever is posted where.
      const leaked = notTheirs.filter((a) => feed.includes(probe(a)));
      check(
        `${role} liaison: only what was handed to ${agency} is on their handset`,
        leaked.length === 0,
        leaked.length === 0
          ? `${notTheirs.length} incident(s) not handed to ${agency}, none of them on the feed`
          : leaked
              .map((a) => `"${probe(a)}" is handed to ${JSON.stringify(a.escalated_to_agency)} and is on the feed`)
              .join('; '),
      );

      // THE DELIVERY PROPERTY, and only for incidents still open: an incident
      // the console pass resolved is legitimately off the feed, and asserting
      // it is present would re-introduce exactly the fixture assumption this
      // block exists to remove.
      const open = theirs.filter((a) => (a.status || '').toUpperCase() !== 'RESOLVED');
      if (open.length) {
        const delivered = open.filter((a) => feed.includes(probe(a)));
        check(
          `${role} liaison: what was handed to ${agency} reaches their handset`,
          delivered.length === open.length,
          delivered.length === open.length
            ? `${open.length} open incident(s) handed to ${agency}, all delivered`
            : open
                .filter((a) => !feed.includes(probe(a)))
                .map((a) => `"${probe(a)}" was handed to ${agency} and is NOT on the feed`)
                .join('; '),
        );
      } else {
        // Not silent: a run where nothing is open for this agency has proved
        // the withholding rule and nothing about delivery, and the summary
        // should say so rather than imply both were checked.
        console.log(
          `  (no open incident is currently handed to ${agency}; ` +
          'delivery to that liaison was not exercised this run)',
        );
      }
    }
  }

  // Each rung of the chain must identify itself. HQ used to read "OPERATIONAL
  // UNIT" here — the top of the chain wearing the label of an untiered
  // responder, because both mapped to ResponderTier.unknown.
  const EXPECTED_BANNER = {
    unit: 'UNIT COMMAND',
    ward: 'WARD COMMAND',
    lga: 'LGA COMMAND',
    hq: 'HQ COMMAND',
  };
  const wrongBanner = Object.entries(EXPECTED_BANNER)
    .filter(([role, banner]) => !(roleReport[role]?.banner || '').includes(banner))
    .map(([role, banner]) => `${role} should read ${banner}, read "${roleReport[role]?.banner || '(nothing)'}"`);
  check(
    'every rung of the command chain identifies itself on the dashboard',
    wrongBanner.length === 0,
    wrongBanner.join('; ') || Object.values(EXPECTED_BANNER).join(' / '),
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


  // AN ADVISORY REACHES THE WARD IT NAMES, AND NOT THE NEXT ONE.
  //
  // T-29: this banner wraps every screen in the app and had its own targeting
  // filter, reading `target_type` / `target_value` — columns the console does
  // not write — so the default let EVERY advisory through to EVERY user. It
  // calls `broadcastReaches()` now, the same function the HUD uses, and this is
  // the only check of that outside the widget tests.
  //
  // The seeded advisory is scoped to NARAGUTA, where every fixture person works
  // except the ARMY liaison, who is in PANYAM. Under the old filter the row —
  // which carries no `target_type` at all, because no writer has ever written
  // one — defaulted to 'ALL' and would have reached the Army too, so this fails
  // on the old code and passes on the new.
  const inWard = ROLES.filter((r) => r !== 'army');
  const missedWard = inWard.filter((r) => advisoryReport[r] && !advisoryReport[r].ward);
  check(
    'a ward-scoped advisory reaches everybody posted to that ward',
    missedWard.length === 0,
    missedWard.length
      ? `did not reach: ${missedWard.join(', ')}`
      : `${inWard.length} role(s) in NARAGUTA all saw it`,
  );
  check(
    'and does not reach the liaison posted to another ward',
    advisoryReport.army ? advisoryReport.army.ward === false : false,
    advisoryReport.army
      ? (advisoryReport.army.ward
          ? 'the ARMY liaison in PANYAM was shown a NARAGUTA advisory'
          : 'the ARMY liaison in PANYAM was not shown it')
      : 'the ARMY liaison never signed in, so this proves nothing',
  );

  // AND A LEGACY ROW STILL ARRIVES, TO THE RIGHT AUDIENCE.
  //
  // The old mobile broadcast screen wrote the audience into `target_type`, and
  // `broadcastAudience()` falls back to it. That is the one legacy path that is
  // real — the place half of the legacy pair was never written by anything — and
  // it had no end-to-end coverage. The ARMY liaison is a responder outside
  // NARAGUTA, so the ward advisory does not reach them and this one does, which
  // is what makes the two distinguishable in a one-banner-at-a-time surface.
  check(
    'a legacy advisory addressed by target_type still reaches its audience',
    advisoryReport.army ? advisoryReport.army.legacyAgents === true : false,
    advisoryReport.army
      ? (advisoryReport.army.legacyAgents
          ? 'the AGENTS advisory reached a responder through the legacy column'
          : 'a row carrying its audience in target_type reached nobody')
      : 'the ARMY liaison never signed in, so this proves nothing',
  );

  // EVERY DATABASE FUNCTION THE APP CALLED MUST HAVE BEEN ANSWERED.
  //
  // `SmsDeviceKey` calls `register_sms_device()` on every sign-in, and the
  // stand-in had no RPC router at all — so the call came back
  // `400 relation "public.rpc/register_sms_device" does not exist` for all eight
  // roles. The app treats that as non-fatal on purpose ("a device with no SMS
  // key still works normally"), so nothing on screen changed and this harness
  // reported 15/15: the encrypted SMS fallback has never once been provisioned
  // in a browser run.
  //
  // A refusal is now a failure, because "the function is not implemented" and
  // "the feature works" are indistinguishable from the outside.
  const ctl = await control();
  const misses = [...new Set(ctl.rpcMisses || [])];
  check(
    'every database function the app called was answered, not refused',
    misses.length === 0,
    misses.length
      ? `refused: ${misses.join(', ')}`
        + ' — implement it in RPCS in scripts/local_e2e/fake_supabase.js'
      : `none refused; ${new Set((ctl.rpcCalls || []).map((c) => c.fn)).size}`
        + ' function(s) answered',
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
        advisories: advisoryReport,
        rpcMisses: misses,
        rpcCalls: ctl.rpcCalls || [],
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
