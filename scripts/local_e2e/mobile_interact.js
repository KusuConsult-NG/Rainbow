/**
 * Use the mobile app: every button, every reporting category, SOS, AI report.
 *
 * `mobile_capture.js` proves the screens render. This proves they do something,
 * and checks each action against the database write it is supposed to cause.
 * That distinction is not academic here: the app's alert submission has a
 * fallback that enqueues to offline SQLite and tells the user the report was
 * sent, so an insert that the database REFUSES looks exactly like an insert
 * that succeeded. Only watching the database can tell them apart.
 *
 * Flows asserted:
 *   panic SOS (long press)      -> alerts insert
 *   silent SOS (tap)            -> alerts insert
 *   all ten reporting categories-> ten alerts inserts, each carrying its type
 *   AI / voice report           -> opens, and says so when it cannot listen
 *   emergency PIN               -> reaches the server-side PIN function
 *   uninstall request           -> uninstall_requests insert
 *   safe zones, history         -> read the tables they display
 * then a sweep of every remaining button on every screen.
 *
 * Proves behaviour, NOT row-level security: the stand-in answers every query.
 *
 *   node scripts/local_e2e/mobile_interact.js
 */

const fs = require('fs');
const http = require('http');
const path = require('path');
const { launch } = require('./browser');
const { DOMAIN, byKey } = require('./fixtures');

const ROOT = path.join(__dirname, '..', '..');
const WEB = path.join(ROOT, 'build', 'web');
const PORT = Number(process.env.MOBILE_PORT || 8083);
const CONTROL = 'http://127.0.0.1:54322/';
const OUT = process.env.E2E_OUT || path.join(ROOT, 'local_e2e_screenshots');
const PHONE = { width: 390, height: 844, deviceScaleFactor: 2, isMobile: true, hasTouch: true };

// Jos North, so a located report lands where the fixtures live.
const HERE = { latitude: 9.8965, longitude: 8.8583 };

fs.mkdirSync(OUT, { recursive: true });

const checks = [];
const shots = [];
const sweepLog = [];
const deadControls = [];

function check(name, pass, detail = '') {
  checks.push({ name, pass: !!pass, detail });
  console.log(`${pass ? 'PASS' : 'FAIL'}  ${name}${detail ? `  — ${detail}` : ''}`);
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

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
  res.writeHead(200, { 'content-type': TYPES[path.extname(file)] || 'application/octet-stream' });
  fs.createReadStream(file).pipe(res);
});

async function control(p = '') {
  return (await fetch(CONTROL + p)).json();
}
async function writeMark() {
  return (await control()).writes.length;
}
async function writesSince(mark, table = null) {
  const { writes } = await control();
  return writes.slice(mark).filter((w) => !table || w.table === table);
}
async function readsSince(mark, table) {
  const { log } = await control();
  return log.slice(mark).filter((e) => e.path === `/rest/v1/${table}` && e.method === 'GET');
}
async function logMark() {
  return (await control()).log.length;
}

(async () => {
  const up = await fetch('http://127.0.0.1:54321/auth/v1/health').then((r) => r.ok).catch(() => false);
  if (!up) {
    console.error('the stand-in backend is not answering. Start it:  node scripts/local_e2e/fake_supabase.js');
    process.exit(1);
  }
  if (!fs.existsSync(path.join(WEB, 'index.html'))) {
    console.error('build/web is missing — build the app first (see scripts/local_e2e/run.sh).');
    process.exit(1);
  }

  await new Promise((r) => server.listen(PORT, '127.0.0.1', r));
  const origin = `http://127.0.0.1:${PORT}`;

  const { browser, newPage, problems, state } = await launch({ viewport: PHONE, canvaskitDir: path.join(WEB, 'canvaskit') });

  // SOS needs a fix. Without this the permission gate stops the flow before any
  // alert is created, and the run would report SOS broken when it is only
  // unpermitted.
  await browser.defaultBrowserContext().overridePermissions(origin, ['geolocation']);

  const page = await newPage();
  await page.setGeolocation(HERE);

  // ---- helpers that speak Flutter's semantics tree --------------------------

  const screenText = () =>
    page.evaluate(() => {
      const host = document.querySelector('flt-semantics-host') || document.body;
      return (
        [...host.querySelectorAll('[aria-label]')].map((e) => e.getAttribute('aria-label')).join('\n') +
        '\n' + host.innerText
      ).trim();
    });

  /** Centre of the first semantics node whose text matches. */
  const findNode = (pattern, { role = null } = {}) =>
    page.evaluate(
      (pat, wantRole) => {
        const re = new RegExp(pat, 'i');
        const nodes = [...document.querySelectorAll('flt-semantics')];
        for (const n of nodes) {
          const r = n.getBoundingClientRect();
          if (r.width < 4 || r.height < 4) continue;
          if (wantRole && n.getAttribute('role') !== wantRole) continue;
          const txt = (n.textContent || '') + ' ' + (n.getAttribute('aria-label') || '');
          // Prefer the tightest node that matches, so a tap lands on the
          // control and not on the whole screen behind it.
          if (re.test(txt) && r.height < (wantRole === 'button' ? 400 : 220)) {
            return { x: r.x + r.width / 2, y: r.y + r.height / 2, w: r.width, h: r.height };
          }
        }
        return null;
      },
      pattern,
      role,
    );

  /**
   * Tap a control through its semantics element's own click handler.
   *
   * A synthetic mouse click at the node's coordinates does NOT reliably reach
   * the widget: the semantics element sits over the canvas and the event stops
   * there. Flutter puts a real click listener on that element, so clicking the
   * element is what actually delivers the tap.
   */
  async function tap(pattern, opts = {}) {
    const ok = await page.evaluate(
      (pat, wantRole, maxH) => {
        const re = new RegExp(pat, 'i');
        for (const n of document.querySelectorAll('flt-semantics')) {
          const r = n.getBoundingClientRect();
          if (r.width < 4 || r.height < 4 || r.height > maxH) continue;
          if (wantRole && n.getAttribute('role') !== wantRole) continue;
          const txt = (n.textContent || '') + ' ' + (n.getAttribute('aria-label') || '');
          if (re.test(txt)) { n.click(); return true; }
        }
        return false;
      },
      pattern,
      opts.role ?? null,
      opts.maxHeight ?? (opts.role === 'button' ? 400 : 220),
    );
    if (ok) await sleep(opts.settle ?? 1400);
    return ok;
  }

  /**
   * A long press has no semantics equivalent — the element exposes a tap and
   * nothing else — so this one has to be pointer events on the element, held.
   */
  async function longPress(pattern, ms = 1300) {
    const n = await findNode(pattern, { role: 'button' });
    if (!n) return false;
    await page.evaluate(
      (x, y, hold) => {
        const target = document.elementFromPoint(x, y) || document.body;
        const opts = { bubbles: true, cancelable: true, clientX: x, clientY: y, pointerId: 1, isPrimary: true, button: 0 };
        target.dispatchEvent(new PointerEvent('pointerdown', opts));
        target.dispatchEvent(new MouseEvent('mousedown', opts));
        return new Promise((res) => setTimeout(() => {
          target.dispatchEvent(new PointerEvent('pointerup', opts));
          target.dispatchEvent(new MouseEvent('mouseup', opts));
          res();
        }, hold));
      },
      n.x,
      n.y,
      ms,
    );
    await sleep(2400);
    return true;
  }

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
    state.typing = true;
    await page.keyboard.type(text, { delay: 25 });
    await sleep(400);
    state.typing = false;
    return true;
  }

  const go = async (route, settle = 2400) => {
    await page.evaluate((r) => { window.location.hash = `#${r}`; }, route);
    await sleep(settle);
  };

  async function shot(name) {
    const file = `${name}.png`;
    await page.screenshot({ path: path.join(OUT, file) });
    shots.push(file);
    console.log(`      shot  ${file}`);
  }

  // ---- boot + sign in -------------------------------------------------------
  state.screen = 'mobile:boot';
  await page.goto(origin, { waitUntil: 'domcontentloaded' });
  await page.waitForFunction(() => !!document.querySelector('flutter-view, flt-glass-pane, canvas'), { timeout: 90000 });
  await sleep(6500);
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await sleep(2000);

  // The real citizen sign-in — see the note in mobile_capture.js.
  await typeInto(byKey('citizen').phone.replace('+234', '0'));
  await tap('authorize access', { role: 'button' });
  await sleep(2500);
  await typeInto('123456');
  await tap('verify otp', { role: 'button' });
  await sleep(6000);

  const home = await page.evaluate(() => window.location.hash);
  check('signed in as the seeded citizen', /home/.test(home), `on ${home}`);
  if (!/home/.test(home)) {
    await shot('90-mobile-signin-failed');
    await browser.close(); server.close(); process.exit(1);
  }

  // ---- SOS ------------------------------------------------------------------
  // Tap is the SILENT SOS; long press is the full panic alarm. Both must reach
  // the database — the fallback that enqueues offline makes a refused insert
  // look identical to a successful one from inside the app.
  state.screen = 'mobile:silent-sos';
  let mark = await writeMark();
  const tapped = await tap('SILENT SOS', { role: 'button', settle: 5000 });
  await shot('90-mobile-sos-01-silent-tapped');
  let w = await writesSince(mark, 'alerts');
  check(
    'SILENT SOS reaches the database',
    tapped && w.some((x) => x.method === 'POST'),
    w.length ? JSON.stringify(w[0].rows[0]).slice(0, 180) : (tapped ? 'tapped, nothing inserted' : 'SOS control not found'),
  );
  if (w.length) {
    const row = w[0].rows[0];
    check(
      'the silent SOS carries the reporter and a real position',
      !!row.reported_by && row.latitude != null && row.longitude != null,
      `reported_by=${row.reported_by ? 'set' : 'MISSING'} lat=${row.latitude} lng=${row.longitude}`,
    );
  }

  state.screen = 'mobile:panic-sos';
  await go('/home');
  mark = await writeMark();
  const pressed = await longPress('SILENT SOS');
  await shot('90-mobile-sos-02-panic-longpress');
  w = await writesSince(mark, 'alerts');
  check(
    'PANIC SOS (long press) reaches the database',
    pressed && w.some((x) => x.method === 'POST'),
    w.length ? `type=${w[0].rows[0].type} severity=${w[0].rows[0].severity}` : (pressed ? 'pressed, nothing inserted' : 'SOS control not found'),
  );
  const onEmergency = await page.evaluate(() => window.location.hash);
  check(
    'the panic SOS opens the emergency screen',
    /emergency/.test(onEmergency),
    `on ${onEmergency}`,
  );
  await shot('90-mobile-sos-03-emergency-active');

  // ---- AI / voice report ----------------------------------------------------
  // Speech recognition does not exist in a headless browser. What matters is
  // that the dialog says so rather than sitting silent or claiming a report was
  // filed — "nothing is happening" and "this is broken" must not look alike.
  state.screen = 'mobile:ai-report';
  await go('/home');
  const opened = await tap('AI REPORT|SPEAK TO REPORT', { role: 'button', settle: 3000 });
  await shot('91-mobile-ai-report-dialog');
  const aiText = await screenText();
  check('the AI report control opens its dialog', opened, opened ? '' : 'control not found');
  if (opened) {
    check(
      'the AI report dialog states what it is doing or why it cannot',
      /listen|speak|record|no voice|unavailable|not supported|error|try again|tap/i.test(aiText),
      (aiText.split('\n').map((l) => l.trim()).filter(Boolean).slice(0, 3).join(' / ') || '(no text)').slice(0, 120),
    );
  }
  await page.keyboard.press('Escape').catch(() => {});
  await sleep(800);

  // ---- every reporting category --------------------------------------------
  const CATEGORIES = [
    'Kidnap', 'Fire', 'Drug abuse', 'Police brutality', 'Flood',
    'Cyber crime', 'Child abuse', 'Domestic violence', 'Cattle rustling',
    'Community attack',
  ];

  const categoryResults = [];
  for (const [i, cat] of CATEGORIES.entries()) {
    state.screen = `mobile:report:${cat}`;
    // Reload between categories. Walking back with location.hash leaves the
    // report flow's own state behind, and after the first submission the
    // category list stopped appearing at all — which looked like nine broken
    // categories and was one dirty starting point.
    await page.reload({ waitUntil: 'domcontentloaded' });
    await page.waitForFunction(() => !!document.querySelector('flutter-view, flt-glass-pane, canvas'), { timeout: 60000 });
    await sleep(5000);
    await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
    await sleep(1500);
    await go('/report-category', 2800);

    // The list scrolls; bring the category into view before tapping it.
    for (let attempt = 0; attempt < 16; attempt++) {
      if (await findNode(cat, { role: 'button' })) break;
      await page.mouse.wheel({ deltaY: 300 });
      await sleep(500);
    }
    const pickedCat = await tap(cat, { role: 'button', settle: 2400 });
    if (!pickedCat) {
      categoryResults.push({ cat, reached: false, inserted: false, why: 'category not found' });
      continue;
    }
    if (i === 0) await shot('92-mobile-report-01-categories');

    // Subtype, then details, then submit. Each screen's primary action is the
    // only enabled button at the bottom, but tapping by name is clearer.
    // The flow is three screens, not two:
    //   category  ->  SUBTYPE (pick one, INITIATE TACTICAL REPORT)
    //             ->  DETAILS (narrative, INITIATE TRANSMISSION)
    // Collapsing the middle step is why the first attempt submitted nothing:
    // it typed a narrative into a screen that has no narrative field, then
    // looked for a button that is on the screen after it.
    const pickedSub = await page.evaluate(() => {
      const n = [...document.querySelectorAll('flt-semantics[role="button"]')].find((b) => {
        const r = b.getBoundingClientRect();
        const label = (b.textContent || '').trim();
        return r.y > 120 && r.y < 640 && r.width > 180 && label.length > 3
          && !/change|initiate|dashboard|movement|new report|home/i.test(label);
      });
      if (!n) return null;
      const label = (n.textContent || '').trim().slice(0, 40);
      n.click();
      return label;
    });
    await sleep(1600);
    if (i === 0) await shot('92-mobile-report-02-subtypes');

    const advanced = await tap('initiate tactical report', { role: 'button', settle: 2600 });
    if (i === 0) await shot('92-mobile-report-03-details');

    // The narrative field has to be focused before Flutter puts a DOM input
    // in the page at all; `typeInto` alone found nothing and the field stayed
    // at "0 CHARS".
    await tap('enter mission details|mission narrative', { settle: 900 });
    const narrated = await typeInto(`Local end-to-end ${cat} report.`);
    await sleep(500);

    // INITIATE TRANSMISSION sits below the fold on this screen.
    for (let sc = 0; sc < 8; sc++) {
      if (await findNode('initiate transmission', { role: 'button' })) break;
      await page.mouse.wheel({ deltaY: 320 });
      await sleep(400);
    }
    if (i === 0) await shot('92-mobile-report-03b-details-filled');

    const mk = await writeMark();
    await tap('initiate transmission', { role: 'button', settle: 4000 });
    const ins = (await writesSince(mk, 'alerts')).filter((x) => x.method === 'POST');
    categoryResults.push({
      cat,
      reached: true,
      subtype: pickedSub,
      advanced,
      narrated,
      inserted: ins.length > 0,
      type: ins[0]?.rows?.[0]?.type,
      severity: ins[0]?.rows?.[0]?.severity,
      description: ins[0]?.rows?.[0]?.description,
    });
    if (i === 0) await shot('92-mobile-report-04-submitted');
  }

  const submitted = categoryResults.filter((r) => r.inserted);
  check(
    'every reporting category can be selected',
    categoryResults.every((r) => r.reached),
    categoryResults.filter((r) => !r.reached).map((r) => r.cat).join(', ') || `${CATEGORIES.length} categories`,
  );
  check(
    'a report submitted from each category reaches the database',
    submitted.length === CATEGORIES.length,
    `${submitted.length}/${CATEGORIES.length} inserted` +
      (submitted.length ? `; e.g. ${submitted[0].type} / ${submitted[0].severity}` : ''),
  );

  // ---- the rest of the features --------------------------------------------
  state.screen = 'mobile:history';
  let lm = await logMark();
  await go('/incident-history', 3000);
  await shot('93-mobile-incident-history');
  check(
    'incident history reads the alerts table',
    (await readsSince(lm, 'alerts')).length > 0,
    '',
  );

  state.screen = 'mobile:safe-zone';
  lm = await logMark();
  await go('/safe-zone', 3000);
  await shot('93-mobile-safe-zones');
  const zoneText = await screenText();
  check(
    'the safe zones screen shows zones or says why it cannot',
    zoneText.length > 0,
    (zoneText.split('\n').find((l) => l.trim()) || '').slice(0, 70),
  );

  state.screen = 'mobile:emergency-pins';
  await go('/emergency-pins', 3000);
  await shot('93-mobile-emergency-pins');
  const pinMark = await logMark();
  // Four STEPS, not four fields: safe PIN, safe PIN again, duress PIN, duress
  // PIN again, each behind its own CONTINUE. The duress PIN must differ from
  // the safe one or the last step is refused — which is the point of it.
  const PIN_STEPS = ['1379', '1379', '2468', '2468'];
  for (const [step, value] of PIN_STEPS.entries()) {
    await typeInto(value);
    await sleep(400);
    if (step === 0) await shot('93-mobile-emergency-pins-filled');
    await tap('continue|save|confirm|finish|set pin', { role: 'button', settle: 2200 });
  }
  await shot('93-mobile-emergency-pins-done');
  const pinCalls = (await control()).log.slice(pinMark).filter((e) => /rpc|emergency_pin/i.test(e.path));
  check(
    'setting an emergency PIN goes to the server, never the device',
    pinCalls.length > 0,
    pinCalls.length ? pinCalls.map((c) => c.path).join(', ') : 'no server call was made',
  );

  state.screen = 'mobile:uninstall';
  await go('/uninstall-request', 3000);
  const unMark = await writeMark();
  await typeInto('Local end-to-end uninstall request.');
  await tap('submit|send|request|confirm', { role: 'button', settle: 2800 });
  await shot('93-mobile-uninstall-request');
  const unWrites = await writesSince(unMark, 'uninstall_requests');
  check(
    'an uninstall request is recorded',
    unWrites.some((x) => x.method === 'POST'),
    unWrites.length ? JSON.stringify(unWrites[0].rows[0]).slice(0, 140) : 'nothing inserted',
  );

  state.screen = 'mobile:settings';
  await go('/settings', 3000);
  await shot('93-mobile-settings');

  // ---- the re-entry lock ---------------------------------------------------
  //
  // The lock engages by itself once the app has been away from the foreground
  // for a couple of minutes, which a browser harness cannot produce. Settings
  // → "Lock This Phone" is the deliberate version of the same thing, and it is
  // how this screen is reached on purpose.
  //
  // The assertion that matters is not that the lock appears. It is that the
  // EMERGENCY BUTTON is on it. A lock screen in front of a panic button is a
  // liability, and the whole design of this feature is the list of things it
  // must not do.
  state.screen = 'mobile:lock';
  const lockOpened = await tap('lock this phone', { role: 'button', settle: 3000 });
  check('Settings offers a way to lock the phone deliberately', lockOpened);
  if (lockOpened) {
    await shot('93b-mobile-lock-screen');
    const lockText = await screenText();
    const hash = await page.evaluate(() => window.location.hash);
    check(
      'locking the phone reaches the lock screen',
      /#\/lock/.test(hash),
      hash || '(no hash)',
    );
    check(
      'the emergency button is on the lock screen',
      /EMERGENCY|SEND SOS/i.test(lockText),
      /EMERGENCY|SEND SOS/i.test(lockText) ? '' : 'the panic button is behind the lock',
    );
    check(
      'the lock screen says it will send a code, and to which number',
      /code/i.test(lockText),
      lockText.split('\n').map((l) => l.trim()).find((l) => /code/i.test(l)) || '',
    );
    check(
      'a locked phone can still be signed out of',
      /SIGN OUT/i.test(lockText),
      '',
    );

    // A locked app must not be reachable around the lock. The router is where
    // that is decided — a gate a route can be got around is not a gate, and
    // this app has thirty-odd routes including deep links into a report in
    // progress.
    for (const forbidden of ['/home', '/report-initial', '/incident-history', '/settings']) {
      await page.evaluate((r) => { window.location.hash = `#${r}`; }, forbidden);
      await sleep(1800);
      const landed = await page.evaluate(() => window.location.hash);
      check(
        `a locked phone cannot be walked into ${forbidden}`,
        /#\/lock/.test(landed),
        landed,
      );
    }
    // And the emergency screen is the ONE exception, deliberately.
    await page.evaluate(() => { window.location.hash = '#/emergency-active'; });
    await sleep(1800);
    const emergency = await page.evaluate(() => window.location.hash);
    check(
      'a locked phone still reaches a running emergency',
      /#\/emergency-active/.test(emergency),
      emergency,
    );
  }

  // Back to a usable app for the sweep below. Signing out of the lock screen
  // is the only way out of it that does not need a code, which is itself the
  // thing being relied on here.
  //
  // The check above left the app on /emergency-active — that IS the assertion.
  // Going straight for the sign-out button from there found nothing to press,
  // because the button is on the lock screen; the tap silently returned false,
  // the phone number was typed into no field, and the entire sweep below then
  // ran against the lock screen. Nothing reported it, because none of these
  // recovery steps was ever checked. So: come back to the lock screen first,
  // and assert every step of the way back.
  await page.evaluate(() => { window.location.hash = '#/lock'; });
  await sleep(2000);

  const signedOut = await tap('sign out', { role: 'button', settle: 3500 });
  check('the lock screen offers a way out that needs no code', signedOut);
  const afterSignOut = await page.evaluate(() => window.location.hash);
  check(
    'signing out of the lock screen actually leaves it',
    !/#\/lock/.test(afterSignOut),
    afterSignOut || '(no hash)',
  );

  await typeInto(byKey('citizen').phone.replace('+234', '0'));
  await tap('authorize access', { role: 'button', settle: 2800 });
  await typeInto('123456');
  await tap('verify otp', { role: 'button', settle: 6000 });
  await sleep(3000);

  // A completed phone+OTP sign-in is more proof than the lock screen asks for,
  // so it must land in the app and not back behind the lock. This is also what
  // makes the sweep below meaningful: without it, a sweep of thirteen lock
  // screens passes for a sweep of the app.
  const backIn = await page.evaluate(() => window.location.hash);
  check(
    'signing in again after a lock lands in the app, not back on the lock',
    /#\/home/.test(backIn),
    backIn || '(no hash)',
  );

  // ---- sweep: every button on every screen ---------------------------------
  const SCREENS = [
    '/home', '/report-initial', '/incident-history', '/safe-zone',
    '/settings', '/emergency-pins', '/live-tracking', '/secure-chat',
    '/dispatcher-chat', '/uninstall-request', '/onboarding-profile',
    '/onboarding-permissions', '/onboarding-contacts',
  ];

  // How many of the swept screens were actually the screen asked for. A locked
  // app answers every route with the lock screen, and a sweep that does not
  // notice reports "34 controls exercised" over thirteen copies of one screen.
  let sweptElsewhere = 0;

  // Controls deliberately not pressed. Reported alongside the count that WAS
  // pressed, so a sweep that skipped most of the app cannot read as a clean
  // one — which is exactly how the over-wide pattern above went unnoticed.
  let skipped = 0;

  /** Per screen: how much of the accessibility tree the sweep can reach. */
  const coverage = [];

  /** Controls that were found but had gone from the DOM by the time we pressed. */
  let unreachable = 0;

  // WHAT COUNTS AS "IT DID SOMETHING".
  //
  // URL, innerHTML length and network traffic miss a whole class of real effect
  // in a CanvasKit app: the pixels live on a canvas, so choosing an option
  // repaints without changing the DOM at all. The report subtype rows are
  // exactly this — tapping one calls setState to move the selection and nothing
  // else; CONTINUE is what navigates. The sweep reported "VEHICLE FIRE did
  // nothing" when it had done precisely what it is supposed to do.
  //
  // The accessibility tree DOES carry selection: aria-checked, aria-selected,
  // aria-pressed, aria-expanded and aria-disabled. Snapshotting those catches a
  // selection change without pretending a dead control is alive.
  //
  // Defined here rather than installed on `window`: the responder sign-in below
  // calls page.goto(), which wipes page globals, so a helper living in the page
  // would be gone by the time the staff sweep used it.
  const snapshot = () => page.evaluate(() => {
    const flags = [...document.querySelectorAll('flt-semantics')]
      .map((n) => [
        n.getAttribute('aria-checked'), n.getAttribute('aria-selected'),
        n.getAttribute('aria-pressed'), n.getAttribute('aria-expanded'),
        n.getAttribute('aria-disabled'),
      ].join(''))
      .join('|');
    return {
      url: location.hash,
      len: document.body.innerHTML.length,
      state: flags,
    };
  });

  for (const route of SCREENS) {
    state.screen = `sweep:${route}`;
    await go(route, 2600);

    const landed = await page.evaluate(() => window.location.hash);
    if (!landed.includes(route)) sweptElsewhere += 1;

    const captureControls = () => page.evaluate(() => {
      // `flt-semantics[role="button"]` alone found under two controls per
      // screen — 34 across nineteen screens, against the console sweep's 140.
      // Flutter only gives role="button" to widgets it considers semantic
      // buttons; an InkWell, a ListTile, a GestureDetector and a tappable card
      // are marked `flt-tappable` with no role, and those are most of this
      // app's controls. A sweep that cannot see them is not a sweep.
      const all = [...document.querySelectorAll(
        'flt-semantics[role="button"], flt-semantics[flt-tappable],'
        + ' flt-semantics[role="link"], flt-semantics[role="checkbox"]',
      )].filter((b) => {
        const r = b.getBoundingClientRect();
        return r.width > 4 && r.height > 4;
      });
      // Keep the innermost only. Flutter nests semantics, so a tappable card
      // containing a tappable button would otherwise be counted and pressed
      // twice — and pressing the wrapper does not necessarily do what pressing
      // the button does.
      window.__mb = all.filter((n) => !all.some((o) => o !== n && n.contains(o)));
      window.__coverage = {
        // Every semantics node on the screen, against the ones we can press.
        // Reported so a low control count is attributable: a sweep that finds
        // two controls on a screen with forty nodes is a selector problem, and
        // one that finds two on a screen with eight is the app exposing
        // nothing — a screen reader would see the same eight.
        nodes: document.querySelectorAll('flt-semantics').length,
        matched: all.length,
        innermost: window.__mb.length,
      };
      return window.__mb.map((b) => (b.textContent || b.getAttribute('aria-label') || '(icon)').trim().slice(0, 40));
    });

    let labels = await captureControls();

    const cov = await page.evaluate(() => window.__coverage);
    coverage.push({ route, ...cov });
    console.log(`      semantics ${route}: ${cov.nodes} nodes, ${cov.matched} tappable, ${cov.innermost} pressable`);

    for (let i = 0; i < labels.length; i++) {
      const label = labels[i];
      // Signing out would end the sweep; SOS is asserted separately and files a
      // real alert every time it is pressed.
      //
      // The pattern used to anchor SOS at the start of the label (`^sos`), which
      // matched nothing the app actually renders — the panic button is labelled
      // "EMERGENCY — SEND SOS NOW". So the sweep pressed the panic button on
      // every screen that carries one, and the only reason this did not file a
      // dozen false CRITICAL alerts is that it reported them as doing nothing.
      //
      // Widening it to the bare word `emergency` then went too far the other
      // way: "Add Emergency Contact", "Emergency Contacts" and the
      // emergency-alerts toggle are ordinary controls, and skipping them
      // dropped the sweep to 22 controls over nineteen screens — a pass earned
      // by pressing almost nothing. Match the panic button's own wording.
      if (/sign ?out|log ?out|terminate|send sos|silent sos|\bsos\b|panic/i.test(label)) {
        skipped += 1;
        continue;
      }

      const before = snapshot();
      const reqBefore = await logMark();

      const clicked = await page.evaluate((idx) => {
        const b = window.__mb?.[idx];
        if (!b || !b.isConnected) return false;
        const r = b.getBoundingClientRect();
        if (r.width < 4) return false;
        b.click();
        return true;
      }, i);
      if (!clicked) {
        unreachable += 1;
        continue;
      }
      await sleep(700);

      const after = snapshot();
      const reqAfter = await logMark();

      const effect = [];
      if (after.url !== before.url) effect.push(`navigated to ${after.url}`);
      if (after.len !== before.len) effect.push('changed the screen');
      if (after.state !== before.state) effect.push('changed a selection');
      if (reqAfter > reqBefore) effect.push(`made ${reqAfter - reqBefore} request(s)`);

      sweepLog.push({ route, label, effect: effect.join(', ') || 'nothing' });
      if (!effect.length) deadControls.push({ route, label });

      // BACK TO THE SCREEN, AND RE-READ IT.
      //
      // The list was captured once and then indexed for the rest of the loop.
      // Flutter rebuilds its semantics tree on any change, so the FIRST control
      // that navigated — or opened a sheet, or expanded a card — detached every
      // node after it: `isConnected` went false, `clicked` came back false, and
      // the rest of that screen's controls were skipped in silence.
      //
      // That is why the sweep pressed 26 of the 75 controls it could see. It
      // was not the selector; it was this. Returning to the route and
      // re-reading the tree costs a navigation per press and reaches the whole
      // screen.
      if (effect.length) {
        await go(route, 1800);
        labels = await captureControls();
      }
    }
    await shot(`94-mobile-sweep${route.replace(/\//g, '-')}`);
  }

  // The sweep above is the CITIZEN's app. The responder's is a different
  // surface entirely — a citizen is redirected away from every screen on it —
  // so sweeping only as the citizen leaves the staff half of the app with no
  // button ever pressed.
  const STAFF_SCREENS = [
    '/agent-dashboard', '/mission-intel', '/mission-resolution',
    '/secure-chat', '/admin-broadcast', '/live-tracking',
  ];

  state.screen = 'mobile:responder:signin';
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
  await sleep(1500);
  // Staff sign in with an access code, not a phone: one step, no OTP.
  await typeInto(`responder@${DOMAIN}`);
  await tap('authorize access', { role: 'button', settle: 6500 });
  const responderLanded = await page.evaluate(() => window.location.hash);
  check(
    'the responder signs in and lands on the agent dashboard',
    /agent-dashboard/.test(responderLanded),
    `landed on ${responderLanded || '#/'}`,
  );

  if (/agent-dashboard/.test(responderLanded)) {
    for (const route of STAFF_SCREENS) {
      state.screen = `sweep:responder:${route}`;
      await go(route, 2800);

      const captureStaffControls = () => page.evaluate(() => {
        // Same widening as the citizen sweep above: role="button" alone misses
        // every InkWell, ListTile and tappable card, which is most of them.
        const all = [...document.querySelectorAll(
          'flt-semantics[role="button"], flt-semantics[flt-tappable],'
          + ' flt-semantics[role="link"], flt-semantics[role="checkbox"]',
        )].filter((b) => {
          const r = b.getBoundingClientRect();
          return r.width > 4 && r.height > 4;
        });
        window.__mb = all.filter((n) => !all.some((o) => o !== n && n.contains(o)));
        return window.__mb.map((b) => (b.textContent || b.getAttribute('aria-label') || '(icon)').trim().slice(0, 40));
      });

      let labels = await captureStaffControls();
      for (let i = 0; i < labels.length; i++) {
        const label = labels[i];
        if (/sign ?out|log ?out|terminate|power/i.test(label)) {
          skipped += 1;
          continue;
        }

        const before = snapshot();
        const reqBefore = await logMark();
        const clicked = await page.evaluate((idx) => {
          const b = window.__mb?.[idx];
          if (!b || !b.isConnected) return false;
          if (b.getBoundingClientRect().width < 4) return false;
          b.click();
          return true;
        }, i);
        if (!clicked) {
          unreachable += 1;
          continue;
        }
        await sleep(700);
        const after = snapshot();
        const reqAfter = await logMark();

        const effect = [];
        if (after.url !== before.url) effect.push(`navigated to ${after.url}`);
        if (after.len !== before.len) effect.push('changed the screen');
        if (after.state !== before.state) effect.push('changed a selection');
        if (reqAfter > reqBefore) effect.push(`made ${reqAfter - reqBefore} request(s)`);

        sweepLog.push({ route: `responder${route}`, label, effect: effect.join(', ') || 'nothing' });
        if (!effect.length) deadControls.push({ route: `responder${route}`, label });

        // Same as the citizen sweep: Flutter rebuilds its semantics tree on any
        // change, so without going back and re-reading it, the first control
        // that did anything detached every node after it.
        if (effect.length) {
          await go(route, 1800);
          labels = await captureStaffControls();
        }
      }
      await shot(`95-mobile-responder-sweep${route.replace(/\//g, '-')}`);
    }
  }

  const totalNodes = coverage.reduce((n, c) => n + c.nodes, 0);
  const totalPressable = coverage.reduce((n, c) => n + c.innermost, 0);
  // A sweep that presses a fraction of what it found is not a sweep, and the
  // shortfall must be visible rather than implied by a small tally.
  check(
    'the sweep pressed the controls it found',
    unreachable === 0,
    unreachable
      ? `${unreachable} control(s) had gone from the DOM before they could be pressed`
      : `${sweepLog.length} pressed, ${skipped} skipped, of ${totalPressable} found`,
  );

  check(
    'the app exposes its controls to the accessibility tree',
    totalPressable > 0,
    `${totalPressable} pressable of ${totalNodes} semantics nodes across ${coverage.length} screens`
    + ` — ${coverage.map((c) => `${c.route}:${c.innermost}/${c.nodes}`).join(' ')}`,
  );

  check(
    'the sweep actually reached the screens it swept',
    sweptElsewhere === 0,
    sweptElsewhere
      ? `${sweptElsewhere}/${SCREENS.length} routes answered with a different screen`
      : `all ${SCREENS.length} citizen screens reached`,
  );

  check(
    'every mobile control that was pressed did something',
    deadControls.length === 0,
    deadControls.length
      ? `${deadControls.length} did nothing: ${deadControls.slice(0, 8).map((d) => `${d.route}/"${d.label}"`).join(', ')}`
      : `${sweepLog.length} controls exercised, ${skipped} deliberately skipped`,
  );

  /**
   * Errors raised inside Flutter's own web engine rather than by this app.
   *
   * `TypeError: Cannot read properties of null (reading 'toString')` fires
   * whenever this harness synthesises a keystroke. Its stack, resolved through
   * main.dart.js.map, is entirely inside
   * `org-dartlang-sdk:///lib/_engine/engine/keyboard_binding.dart` — lines 92,
   * 105, 413, 539-565, 623-626 — with no frame in `lib/`. It is the web
   * engine's keyboard binding reacting to an event with no real key, and that
   * binding does not exist on Android or iOS.
   *
   * Excluded by BOTH the message and the fact that a synthetic keystroke was
   * in flight when it fired. An earlier version matched minified stack lines
   * instead, which rotted the moment the app was rebuilt — the line numbers
   * move, the filter stops matching, and the run fails on noise it had already
   * classified. An app error with the same wording, raised at any other
   * moment, is still reported.
   */
  const isEngineKeyboardNoise = (p) =>
    /Cannot read properties of null \(reading 'toString'\)/.test(p.text) && p.whileTyping;

  const engineNoise = problems.filter(isEngineKeyboardNoise);
  const fatal = problems.filter(
    (p) => (p.kind === 'pageerror' || /uncaught|cannot read|is not a function/i.test(p.text))
      && !isEngineKeyboardNoise(p),
  );
  check(
    'no mobile control threw anything the app is responsible for',
    fatal.length === 0,
    fatal.length
      ? fatal.slice(0, 3).map((f) => `${f.screen}: ${f.text}`).join(' | ')
      : `clean (${engineNoise.length} Flutter web keyboard-engine errors ignored — not app code, not present on a device)`,
  );

  const ctl = await control();
  check(
    'nothing the app did named a column the migrations do not define',
    ctl.unknownColumns.length === 0,
    ctl.unknownColumns.join('; ') || 'none',
  );

  fs.writeFileSync(
    path.join(OUT, 'mobile-interactions.json'),
    JSON.stringify(
      {
        ranAt: new Date().toISOString(),
        target: 'Flutter web build of the mobile app',
        viewport: PHONE,
        proves: 'the app\'s controls act and write; NOT an Android/iOS build, NOT row-level security',
        checks,
        categories: categoryResults,
        controlsExercised: sweepLog.length,
        deadControls,
        sweep: sweepLog,
        screenshots: shots,
        browserProblems: problems,
        engineKeyboardNoise: engineNoise.length,
      },
      null,
      2,
    ),
  );

  await browser.close();
  server.close();

  const failed = checks.filter((c) => !c.pass);
  console.log(`\n${checks.length - failed.length}/${checks.length} checks passed, ${sweepLog.length} controls exercised, ${shots.length} screenshots`);
  if (failed.length) {
    console.log('\nFAILED:');
    for (const f of failed) console.log(`  - ${f.name}${f.detail ? `  (${f.detail})` : ''}`);
  }
  process.exit(failed.length ? 1 : 0);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
