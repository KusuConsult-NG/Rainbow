/**
 * Drive the HQ console in a real browser, screen by screen and role by role,
 * and assert on what is actually on the screen.
 *
 * This is the first thing in this repository that renders a console screen. Up
 * to now every console finding came from reading code or from unit tests of
 * logic lifted out so it could be tested; the wiring between them — which is
 * where the worst defects lived — was never exercised.
 *
 * It proves the screens, not the policies. Row-level security is not enforced
 * by the local fake and cannot be: only `scripts/verify_rls.js` against a real
 * staging PostgREST can make that claim.
 *
 *   node scripts/local_e2e/capture.js
 *
 * Expects the fake on :54321 (control plane :54322) and the console on :3000.
 */

const fs = require('fs');
const path = require('path');
const puppeteer = require(path.join(
  __dirname, '..', '..', 'hq-dashboard-next', 'node_modules', 'puppeteer',
));
const { DOMAIN, PASSWORD } = require('./fixtures');

const BASE = process.env.CONSOLE_URL || 'http://127.0.0.1:3000';
const CONTROL = 'http://127.0.0.1:54322/';
const OUT = process.env.E2E_OUT || path.join(__dirname, '..', '..', 'local_e2e_screenshots');
const VIEWPORT = { width: 1600, height: 1000 };

fs.mkdirSync(OUT, { recursive: true });

const checks = [];
const shots = [];
/** Anything the browser itself complained about, per screen. */
const browserProblems = [];

function check(name, pass, detail = '') {
  checks.push({ name, pass: !!pass, detail });
  console.log(`${pass ? 'PASS' : 'FAIL'}  ${name}${detail ? `  — ${detail}` : ''}`);
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function shot(page, name) {
  const file = path.join(OUT, `${name}.png`);
  await page.screenshot({ path: file, fullPage: false });
  shots.push(path.basename(file));
  console.log(`      shot  ${path.basename(file)}`);
  return file;
}

/** Click the nav entry whose visible text matches, and wait for the panel. */
async function openTab(page, label) {
  const clicked = await page.evaluate((text) => {
    const els = [...document.querySelectorAll('div,button,a,span')];
    const hit = els.find(
      (e) => e.textContent.trim() === text && e.getBoundingClientRect().width > 0,
    );
    if (!hit) return false;
    (hit.closest('[role="button"],button,a,div') || hit).click();
    return true;
  }, label);
  if (clicked) await sleep(900);
  return clicked;
}

async function textOf(page) {
  return page.evaluate(() => document.body.innerText);
}

async function login(page, key) {
  await page.goto(`${BASE}/login`, { waitUntil: 'networkidle2' });
  await page.waitForSelector('input', { timeout: 15000 });
  const inputs = await page.$$('input');
  await inputs[0].click({ clickCount: 3 });
  await inputs[0].type(`${key}@${DOMAIN}`);
  await inputs[1].click({ clickCount: 3 });
  await inputs[1].type(PASSWORD);
  await Promise.all([
    page.waitForNavigation({ waitUntil: 'networkidle2', timeout: 30000 }).catch(() => {}),
    page.evaluate(() => document.querySelector('form')?.requestSubmit()),
  ]);
  await sleep(2500);
  return page.url();
}

async function control() {
  const res = await fetch(CONTROL);
  return res.json();
}

/**
 * Set a React-controlled field.
 *
 * Assigning `.value` and firing `input` is not enough: React caches the last
 * value on the node and treats an unchanged cached value as no change, so the
 * event arrives and the state never moves. Going through the prototype setter
 * updates the cache too, which is what makes React see it.
 */
async function setField(page, selector, value) {
  return page.evaluate(
    (sel, val) => {
      const el = document.querySelector(sel);
      if (!el) return false;
      const proto = el instanceof HTMLTextAreaElement
        ? HTMLTextAreaElement.prototype
        : HTMLInputElement.prototype;
      Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, val);
      el.dispatchEvent(new Event('input', { bubbles: true }));
      el.dispatchEvent(new Event('change', { bubbles: true }));
      return true;
    },
    selector,
    value,
  );
}

/**
 * Choose an option from a TacticalSelect, which is a button plus a popup of
 * buttons rather than a native <select>.
 */
async function chooseTactical(page, triggerText, optionText) {
  const opened = await page.evaluate((t) => {
    const btn = [...document.querySelectorAll('button')].find(
      (b) => b.textContent.replace(/\s+/g, ' ').includes(t) && b.offsetParent !== null,
    );
    if (!btn) return false;
    btn.click();
    return true;
  }, triggerText);
  if (!opened) return false;
  await sleep(500);
  const picked = await page.evaluate((t) => {
    const btn = [...document.querySelectorAll('button')].find(
      (b) => b.textContent.replace(/\s+/g, ' ').trim().toUpperCase().includes(t.toUpperCase()),
    );
    if (!btn) return false;
    btn.click();
    return true;
  }, optionText);
  await sleep(1200);
  return picked;
}

(async () => {
  const browser = await puppeteer.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-dev-shm-usage', '--font-render-hinting=none'],
    defaultViewport: VIEWPORT,
  });

  // Start from a clean record so nothing done to the fake before the run is
  // attributed to the application.
  await fetch(`${CONTROL}reset`);

  const page = await browser.newPage();
  let currentScreen = 'startup';
  page.on('console', (m) => {
    if (m.type() === 'error') browserProblems.push({ screen: currentScreen, kind: 'console', text: m.text().slice(0, 300) });
  });
  page.on('pageerror', (e) => {
    browserProblems.push({ screen: currentScreen, kind: 'pageerror', text: String(e).slice(0, 300) });
  });

  // -----------------------------------------------------------------------
  // 1. The guard. An unauthenticated visit to /dashboard must not render it.
  // -----------------------------------------------------------------------
  currentScreen = 'guard';
  await page.goto(`${BASE}/dashboard`, { waitUntil: 'networkidle2' });
  check(
    'proxy guard: anonymous /dashboard lands on /login',
    page.url().includes('/login'),
    page.url(),
  );
  await shot(page, '01-guard-anonymous-dashboard-redirects-to-login');

  // -----------------------------------------------------------------------
  // 2. Login screen, including the status light that must reflect reality.
  // -----------------------------------------------------------------------
  currentScreen = 'login';
  await page.goto(`${BASE}/login`, { waitUntil: 'networkidle2' });
  await sleep(1500);
  const loginText = await textOf(page);
  check('login screen renders', /badge|pin|sign in|login/i.test(loginText));
  check(
    'login status light reports reachable when the backend answers',
    /online|connected|reachable/i.test(loginText),
    loginText.split('\n').find((l) => /online|offline|unreachable|connected/i.test(l)) || '(no status line found)',
  );
  await shot(page, '02-login-backend-reachable');

  // Wrong password must read as a credential problem, not a browser internal.
  const inputs = await page.$$('input');
  await inputs[0].type(`hq@${DOMAIN}`);
  await inputs[1].type('definitely-not-the-password');
  await page.evaluate(() => document.querySelector('form')?.requestSubmit());
  await sleep(2500);
  const badPwText = await textOf(page);
  check(
    'wrong password shows a credential error, not "Failed to fetch"',
    /incorrect|invalid|wrong|credential/i.test(badPwText) && !/failed to fetch/i.test(badPwText),
    badPwText.split('\n').find((l) => /incorrect|invalid|wrong|credential|failed/i.test(l)) || '(no error line)',
  );
  await shot(page, '03-login-wrong-password-error');

  // -----------------------------------------------------------------------
  // 3. Every role, every screen it can reach.
  // -----------------------------------------------------------------------
  // Every screen the console has. Which of them a given role is OFFERED is
  // the role's business — an agency liaison gets two — so this list is a
  // superset and `openTab` simply returns false for one that is not there.
  const ROLE_TABS = [
    ['Intelligence Map', 'map'],
    ['Incident Feed', 'feed'],
    ['Incidents For Us', 'feed'],
    ['Mission History', 'history'],
    ['Communications & Broadcast', 'broadcast'],
    ['Agent Directory', 'directory'],
    ['Forensic Audit', 'audit'],
    ['System Logic', 'config'],
    ['Uninstall Requests', 'uninstall'],
    ['Handset SMS Channel', 'sim'],
  ];

  const roleReport = {};

  for (const role of ['hq', 'lga', 'police', 'army', 'responder', 'citizen']) {
    currentScreen = `${role}:login`;
    const landed = await login(page, role);
    const onDashboard = landed.includes('/dashboard');
    check(`${role}: sign-in reaches ${onDashboard ? '/dashboard' : landed}`, true, landed);
    if (!onDashboard) {
      await shot(page, `10-${role}-blocked-at-${landed.split('/').pop()}`);
      roleReport[role] = { landed, tabs: [] };
      continue;
    }

    await sleep(2500);
    currentScreen = `${role}:map`;
    const body = await textOf(page);
    check(
      `${role}: dashboard renders (not the Next error shell)`,
      !/__next_error__/.test(await page.content()) && body.length > 200,
      `${body.length} chars of text`,
    );
    await shot(page, `20-${role}-01-map`);

    const seen = [];
    let n = 1;
    for (const [label, slug] of ROLE_TABS) {
      currentScreen = `${role}:${slug}`;
      const ok = await openTab(page, label);
      if (!ok) continue;
      n += 1;
      seen.push(slug);
      await shot(page, `20-${role}-${String(n).padStart(2, '0')}-${slug}`);
    }
    // The agency portal's nav label is built from the liaison's own agency.
    currentScreen = `${role}:agency`;
    const agencyOpened =
      (await openTab(page, 'Inter-Agency Command')) ||
      // What a liaison's own nav calls it now: their desk, not the state's
      // inter-agency board.
      (await openTab(page, 'Our Deployments')) ||
      (await openTab(page, 'Agency Portal')) ||
      (await openTab(page, 'ARMY Portal')) ||
      (await openTab(page, 'POLICE Portal'));
    if (agencyOpened) {
      seen.push('agency');
      await shot(page, `20-${role}-99-agency-portal`);
      const portal = await textOf(page);
      if (role === 'army') {
        check(
          'army portal shows the incident escalated to ARMY',
          /mangu road|roadblock/i.test(portal),
          'a005 present',
        );
      }
      if (role === 'police') {
        check(
          "police portal does NOT show the ARMY-escalated incident",
          !/mangu road|roadblock/i.test(portal),
          'a005 absent',
        );
      }
    }
    roleReport[role] = { landed, tabs: seen };
    console.log(`  ${role}: ${seen.length} screens — ${seen.join(', ')}`);
  }

  // -----------------------------------------------------------------------
  // 4. The display rules that were real defects. Done as HQ, on the feed.
  // -----------------------------------------------------------------------
  currentScreen = 'hq:map-assertions';
  await login(page, 'hq');
  await sleep(3000);

  // C-5 is a MAP claim, not a feed one: the defect was a fabricated pin in
  // central Jos for an alert with null coordinates. The map's situational feed
  // is where the absence has to be stated.
  const map = await textOf(page);
  check(
    'C-5: the SOS with no coordinates is called out as unlocated, not mapped',
    /no gps fix|unlocated/i.test(map),
    map.split('\n').find((l) => /no gps fix|unlocated/i.test(l))?.trim() || '(not found)',
  );
  check(
    'the unlocated count is 1, matching the one alert with null coordinates',
    /\b1\b[\s\S]{0,20}unlocated/i.test(map),
    '',
  );
  await shot(page, '30-hq-map-unlocated-callout');

  // ---------------------------------------------------------------------------
  // The incident card on the marker itself.
  //
  // This is what an operator does first: click the pin. The popup used to carry
  // the type, the status and the description, and nothing else — no reporter, no
  // contact, no age, no acknowledgement, no channel — because the component
  // declared Firebase field names for the reporter and the time and was never
  // given the profiles. Clicking a marker in a real browser is the only way to
  // prove the card is wired, since the popup is an HTML string built outside
  // React and inserted by Leaflet.
  // ---------------------------------------------------------------------------
  currentScreen = 'hq:map-marker-popup';
  const popupText = await (async () => {
    for (let attempt = 0; attempt < 3; attempt += 1) {
      const opened = await page.evaluate(() => {
        const pins = [...document.querySelectorAll('.leaflet-marker-icon')];
        // Cluster icons carry a count; incident pins do not. Click the last one,
        // which is the least likely to be under the filters toolbar.
        const pin = pins[pins.length - 1];
        if (!pin) return false;
        pin.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
        return true;
      });
      if (opened) {
        await sleep(900);
        const text = await page.evaluate(() => {
          const el = document.querySelector('.leaflet-popup-content');
          return el ? el.innerText : '';
        });
        if (text) return text;
      }
      // Markers are clustered; zoom in so individual pins are exposed.
      await page.evaluate(() => {
        const zoom = [...document.querySelectorAll('.leaflet-control-zoom-in')][0];
        if (zoom) zoom.click();
      });
      await sleep(1200);
    }
    return '';
  })();

  // THE MAP PAINTED OVER THE SITUATIONAL FEED.
  //
  // The feed is absolutely positioned as a sibling of the map and carried no
  // z-index, so it sat at `auto` — 0 — while Leaflet gives its own panes
  // 200-700 and its controls 800. `.leaflet-container` sets none itself, so it
  // opens no stacking context and those numbers competed directly with the
  // panel's. The map won.
  //
  // Screenshots did not catch it: the panel is still in the DOM, still the
  // right size, and a screenshot of a map with a panel behind it looks like a
  // map. Asking the browser WHAT IS ACTUALLY ON TOP at the panel's own
  // coordinates is the question that has an answer.
  const feedOnTop = await page.evaluate(() => {
    const panel = [...document.querySelectorAll('div')].find(
      (d) => /SITUATIONAL FEED/.test(d.textContent || '')
        && getComputedStyle(d).position === 'absolute',
    );
    if (!panel) return { found: false };
    const r = panel.getBoundingClientRect();
    if (r.width < 10 || r.height < 10) return { found: false };
    const hit = document.elementFromPoint(r.left + r.width / 2, r.top + 12);
    return {
      found: true,
      covered: !!hit && !panel.contains(hit),
      by: hit ? (hit.className || hit.tagName).toString().slice(0, 60) : '(nothing)',
    };
  });

  check(
    'the situational feed is on top of the map, not behind it',
    feedOnTop.found && !feedOnTop.covered,
    !feedOnTop.found
      ? '(the feed panel was not on screen)'
      : feedOnTop.covered
        ? `covered by ${feedOnTop.by}`
        : 'the feed answers to a click at its own coordinates',
  );

  check(
    'clicking an incident marker opens a card',
    popupText.length > 0,
    popupText ? `${popupText.split('\n').length} lines` : '(no popup opened)',
  );

  if (popupText) {
    check(
      'the card names the reporter',
      /amina bello/i.test(popupText),
      popupText.split('\n').find((l) => /amina/i.test(l))?.trim() || '(reporter absent)',
    );
    check(
      'the card gives HQ a number to ring the reporter on',
      /\+234\d{7,}/.test(popupText),
      popupText.split('\n').find((l) => /\+234/.test(l))?.trim() || '(no contact shown)',
    );
    check(
      'the card states the status in words',
      /awaiting dispatch|unit dispatched|acknowledged|en route|on site|resolved|escalated/i.test(popupText),
      popupText.split('\n').find((l) => /awaiting|dispatch|escalated/i.test(l))?.trim() || '',
    );
    check(
      'the card says how long the incident has been waiting',
      /(just now|\d+m ago|\d+h \d+m ago|\d+d \d+h ago)/i.test(popupText),
      popupText.match(/(just now|\d+[mhd][^\n]{0,12}ago)/i)?.[0] || '(no age shown)',
    );
    check(
      'the card says whether anybody has acknowledged it',
      /acknowledged/i.test(popupText),
      '',
    );
    check(
      'the card states which tier owns the incident',
      /command tier/i.test(popupText),
      popupText.split('\n').find((l) => /command tier/i.test(l))?.trim() || '',
    );
    check(
      'the card names the channel the report arrived over',
      /channel/i.test(popupText),
      popupText.split('\n').find((l) => /channel/i.test(l))?.trim() || '',
    );
    check(
      'the card carries the coordinates it is plotted at',
      /\d\.\d{4,}/.test(popupText),
      popupText.split('\n').find((l) => /coordinates/i.test(l))?.trim() || '',
    );

    // The regression that made the map read-only for new reports: DISPATCH was
    // gated on statuses this database never writes.
    const buttons = await page.evaluate(() =>
      [...document.querySelectorAll('.leaflet-popup-content button, .leaflet-popup-content a')]
        .map((b) => b.textContent.trim()),
    );
    check(
      'a live incident can be dispatched from its marker',
      buttons.includes('DISPATCH'),
      buttons.join(', ') || '(no actions)',
    );
    check(
      'the marker offers the full dossier',
      buttons.includes('DOSSIER'),
      buttons.join(', ') || '(no actions)',
    );
  }
  await shot(page, '31-hq-map-incident-card');

  currentScreen = 'hq:feed-assertions';
  await openTab(page, 'Incident Feed');
  await sleep(1500);
  const feed = await textOf(page);
  check(
    'all five seeded incidents are on the feed',
    ['junction', 'market', 'Cannot say where I am', 'Something is happening', 'Mangu road']
      .every((s) => feed.toLowerCase().includes(s.toLowerCase())),
    '',
  );
  await shot(page, '31-hq-feed-all-incidents');

  // CRITICAL HOTSPOTS is offered on the MAP toolbar (a TacticalSelect), not on
  // the feed, whose status control is a plain <select> with a shorter list.
  currentScreen = 'hq:critical-filter';
  await openTab(page, 'Intelligence Map');
  await sleep(1200);
  const filtered = await chooseTactical(page, 'ALL STATUS', 'CRITICAL HOTSPOTS');
  if (filtered) {
    const crit = await textOf(page);
    check(
      'CRITICAL filter keeps both CRITICAL incidents',
      /junction/i.test(crit) && /mangu road/i.test(crit),
      '',
    );
    check(
      'CRITICAL filter drops the ungraded incident (severity is not assumed)',
      !/something is happening/i.test(crit),
      '',
    );
    check(
      'CRITICAL filter drops the HIGH incidents',
      !/fire spreading/i.test(crit) && !/cannot say where i am/i.test(crit),
      '',
    );
    await shot(page, '32-hq-map-critical-filter');

    // One `filterStatus` drives both toolbars, but only the map's offers
    // CRITICAL. Carrying that value to the feed leaves the feed filtered by a
    // criterion its own control cannot display — which is the "a quiet night
    // and a broken board must not look alike" rule, one screen over.
    await openTab(page, 'Incident Feed');
    await sleep(1200);
    const carried = await page.evaluate(() => {
      const sel = [...document.querySelectorAll('select')].find((s) =>
        [...s.options].some((o) => /ALL STATUS/i.test(o.textContent)),
      );
      if (!sel) return null;
      return {
        value: sel.value,
        shownLabel: sel.selectedIndex >= 0 ? sel.options[sel.selectedIndex].textContent : '',
        offers: [...sel.options].map((o) => o.value),
        cards: document.body.innerText,
      };
    });
    if (carried) {
      check(
        'the feed status control can display whatever filter is actually applied',
        carried.offers.includes(carried.value),
        `applied "${carried.value}", control offers ${carried.offers.join('/')} — shows "${carried.shownLabel}"`,
      );
      await shot(page, '34-hq-feed-with-map-filter-carried-over');
    }
    await openTab(page, 'Intelligence Map');
    await sleep(800);
    await chooseTactical(page, 'CRITICAL HOTSPOTS', 'ALL STATUS');
    await openTab(page, 'Incident Feed');
    await sleep(800);
  } else {
    check('the CRITICAL HOTSPOTS filter can be selected on the map', false, 'control not found');
  }

  // The ungraded incident's dossier must say UNKNOWN rather than invent a grade.
  currentScreen = 'hq:dossier';
  const openedDossier = await page.evaluate(() => {
    const cards = [...document.querySelectorAll('div')].filter((d) =>
      d.textContent.includes('Something is happening'),
    );
    const card = cards[cards.length - 1];
    if (!card) return false;
    const btn = [...card.querySelectorAll('button')].find((b) => /dossier/i.test(b.textContent));
    if (!btn) return false;
    btn.click();
    return true;
  });
  if (openedDossier) {
    await sleep(1500);
    const dossier = await textOf(page);
    check(
      'the ungraded incident reads UNKNOWN in its dossier, not an invented grade',
      /unknown/i.test(dossier) && !/\bHIGH\b/.test(dossier.split('UNKNOWN')[0]?.slice(-80) || ''),
      dossier.split('\n').find((l) => /unknown/i.test(l))?.trim() || '(not found)',
    );
    await shot(page, '33-hq-dossier-ungraded-incident');
    await page.keyboard.press('Escape');
    await sleep(800);
  } else {
    check('the ungraded incident has an openable dossier', false, 'no DOSSIER button found');
  }

  // -----------------------------------------------------------------------
  // 5. Mass broadcast. Until migration 6 it failed on a NOT NULL title and six
  //    columns that did not exist; the fake rejects unknown columns, so a
  //    successful insert here is evidence the shape is right.
  // -----------------------------------------------------------------------
  currentScreen = 'hq:broadcast';
  const beforeWrites = (await control()).writes.length;
  await openTab(page, 'Communications & Broadcast');
  await sleep(1500);
  await shot(page, '40-hq-broadcast-empty');

  // There is no title field: neither this screen nor the mobile one asks for a
  // heading, and the payload derives one from severity and scope. The advisory
  // body is the only free text the operator enters.
  const bodySet = await setField(page, 'textarea', 'Local end-to-end run. Not a real advisory.');
  check('the broadcast composer takes an advisory message', bodySet, '');
  await sleep(600);
  await shot(page, '41-hq-broadcast-composed');

  const submitted = await page.evaluate(() => {
    const btn = [...document.querySelectorAll('button[type="submit"]')].find(
      (b) => /transmit/i.test(b.textContent),
    );
    if (!btn) return 'no submit button';
    if (btn.disabled) return 'submit button disabled';
    btn.click();
    return 'clicked';
  });
  check('the transmit button is enabled once a message is entered', submitted === 'clicked', submitted);
  await sleep(3000);
  await shot(page, '42-hq-broadcast-after-send');

  const afterCtl = await control();
  const broadcastWrites = afterCtl.writes.slice(beforeWrites).filter((w) => w.table === 'system_alerts');
  check(
    'broadcast performs a system_alerts insert the schema accepts',
    broadcastWrites.length > 0,
    broadcastWrites.length
      ? `columns: ${Object.keys(broadcastWrites[0].rows[0]).join(', ')}`
      : 'no insert reached the database',
  );
  if (broadcastWrites.length) {
    check(
      'the broadcast carries a non-null title (the NOT NULL that used to fail)',
      !!broadcastWrites[0].rows[0].title,
      String(broadcastWrites[0].rows[0].title),
    );
  }

  // -----------------------------------------------------------------------
  // 6. The whole-run claims.
  // -----------------------------------------------------------------------
  const ctl = await control();
  check(
    'no query named a column the migrations do not define',
    ctl.unknownColumns.length === 0,
    ctl.unknownColumns.join('; ') || 'none',
  );

  // A basemap refused by our OWN policy is invisible from the map code and
  // from the header: the map simply renders grey with the markers floating on
  // it, and the only evidence is a console message nobody reads during an
  // incident. `img-src` listed `*.tile.openstreetmap.org` while the map
  // requested `tile.openstreetmap.org` — a wildcard matches a subdomain of a
  // host, never the host — so every tile in the command console was blocked.
  const blockedImages = browserProblems.filter((p) =>
    /violates the following Content Security Policy directive: "img-src/i.test(p.text),
  );
  check(
    'the basemap is not blocked by our own content security policy',
    blockedImages.length === 0,
    blockedImages.length
      ? `${blockedImages.length} image(s) refused, first: ${blockedImages[0].text.slice(0, 120)}`
      : 'no img-src violations',
  );

  const otherCspRefusals = browserProblems.filter(
    (p) =>
      /violates the following Content Security Policy/i.test(p.text) &&
      !/"img-src/i.test(p.text),
  );
  check(
    'nothing else the console needs is refused by the policy either',
    otherCspRefusals.length === 0,
    otherCspRefusals.length
      ? `${otherCspRefusals.length}: ${otherCspRefusals[0].text.slice(0, 140)}`
      : 'clean',
  );

  const fatal = browserProblems.filter(
    (p) =>
      p.kind === 'pageerror' ||
      /is not a function|undefined is not|cannot read|hydration failed|minified react error/i.test(p.text),
  );
  check(
    'no page threw and no React crash was logged',
    fatal.length === 0,
    fatal.length ? `${fatal.length}: ${fatal.slice(0, 3).map((f) => `${f.screen}: ${f.text}`).join(' | ')}` : 'clean',
  );

  const report = {
    ranAt: new Date().toISOString(),
    console: BASE,
    viewport: VIEWPORT,
    proves: 'screens render and behave; NOT that row-level security is enforced',
    screenshots: shots,
    roles: roleReport,
    checks,
    unknownColumns: ctl.unknownColumns,
    writesObserved: ctl.writes.map((w) => ({ table: w.table, method: w.method })),
    browserProblems,
    requestCount: ctl.log.length,
  };
  fs.writeFileSync(path.join(OUT, 'report.json'), JSON.stringify(report, null, 2));

  await browser.close();

  const failed = checks.filter((c) => !c.pass);
  console.log(`\n${checks.length - failed.length}/${checks.length} checks passed, ${shots.length} screenshots in ${OUT}`);
  if (failed.length) {
    console.log('\nFAILED:');
    for (const f of failed) console.log(`  - ${f.name}${f.detail ? `  (${f.detail})` : ''}`);
  }
  process.exit(failed.length ? 1 : 0);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
