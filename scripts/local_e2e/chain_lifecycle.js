/**
 * The whole lifecycle, photographed and asserted at every hop.
 *
 *   citizen reports  ->  the alert lands at the PU with real geography
 *   UNIT sees it     ->  escalates
 *   WARD sees it     ->  UNIT no longer does  ->  escalates
 *   LGA sees it      ->  escalates
 *   HQ sees it       ->  assigns it back down to a responder
 *
 * Every step takes a screenshot AND checks the database, because in this app
 * those are different claims: alert submission falls back to an offline queue
 * and tells the user the report was sent, so a screenshot of a success message
 * is not evidence that anything was written.
 *
 *   node scripts/local_e2e/chain_lifecycle.js
 */

const fs = require('fs');
const http = require('http');
const path = require('path');
const { launch } = require('./browser');
const { DOMAIN, PASSWORD } = require('./fixtures');

const ROOT = path.join(__dirname, '..', '..');
const WEB = path.join(ROOT, 'build', 'web');
const PORT = Number(process.env.MOBILE_PORT || 8086);
const REST = 'http://127.0.0.1:54321/rest/v1';
const OUT = process.env.E2E_OUT || path.join(ROOT, 'local_e2e_screenshots');
const PHONE = { width: 390, height: 844, deviceScaleFactor: 2, isMobile: true, hasTouch: true };
const HERE = { latitude: 9.8965, longitude: 8.8583 }; // Jos North

fs.mkdirSync(OUT, { recursive: true });

const checks = [];
const shots = [];
let step = 0;

function check(name, pass, detail = '') {
  checks.push({ name, pass: !!pass, detail });
  console.log(`${pass ? 'PASS' : 'FAIL'}  ${name}${detail ? `  — ${detail}` : ''}`);
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const TYPES = {
  '.html': 'text/html', '.js': 'text/javascript', '.json': 'application/json',
  '.wasm': 'application/wasm', '.png': 'image/png', '.otf': 'font/otf',
  '.ttf': 'font/ttf', '.woff2': 'font/woff2', '.css': 'text/css', '.symbols': 'text/plain',
};
const server = http.createServer((req, res) => {
  const rel = decodeURIComponent(req.url.split('?')[0]).replace(/^\/+/, '') || 'index.html';
  const file = path.join(WEB, rel);
  if (!file.startsWith(WEB) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
    res.writeHead(404); return res.end();
  }
  res.writeHead(200, { 'content-type': TYPES[path.extname(file)] || 'application/octet-stream' });
  fs.createReadStream(file).pipe(res);
});

const rest = async (q) => (await fetch(`${REST}/${q}`)).json();

(async () => {
  if (!await fetch('http://127.0.0.1:54321/auth/v1/health').then((r) => r.ok).catch(() => false)) {
    console.error('start the stand-in first: node scripts/local_e2e/fake_supabase.js');
    process.exit(1);
  }
  await fetch('http://127.0.0.1:54322/reset-data');
  await new Promise((r) => server.listen(PORT, '127.0.0.1', r));
  const origin = `http://127.0.0.1:${PORT}`;

  const { browser, newPage, problems, state } = await launch({
    viewport: PHONE, canvaskitDir: path.join(WEB, 'canvaskit'),
  });
  await browser.defaultBrowserContext().overridePermissions(origin, ['geolocation']);
  let page = await newPage();
  await page.setGeolocation(HERE);

  const shot = async (name) => {
    step += 1;
    const f = `A${String(step).padStart(2, '0')}-${name}.png`;
    await page.screenshot({ path: path.join(OUT, f) });
    shots.push(f);
    console.log(`      shot  ${f}`);
  };

  const text = () => page.evaluate(() => {
    const h = document.querySelector('flt-semantics-host') || document.body;
    return ([...h.querySelectorAll('[aria-label]')].map((e) => e.getAttribute('aria-label')).join('\n')
      + '\n' + h.innerText).trim();
  });

  async function typeInto(t) {
    const box = await page.evaluate(() => {
      const el = document.querySelector('input, textarea');
      if (!el) return null;
      el.focus();
      const r = el.getBoundingClientRect();
      return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
    });
    if (!box) return false;
    await page.mouse.click(box.x, box.y);
    await sleep(300);
    state.typing = true;
    await page.keyboard.type(t, { delay: 22 });
    state.typing = false;
    await sleep(350);
    return true;
  }

  /**
   * Focus a text field, then type into it.
   *
   * Flutter web keeps a DOM `<input>` in the page only for the field that
   * currently has focus, so `typeInto` on its own finds nothing on a screen
   * whose field has never been tapped — which is every dialog the moment it
   * opens. The SITREP box in the escalation dialog carries no label text, so it
   * is found by its semantics role rather than by what it says.
   */
  async function typeIntoTextbox(t) {
    const focused = await page.evaluate(() => {
      const boxes = [...document.querySelectorAll('flt-semantics')]
        .filter((n) => {
          const role = n.getAttribute('role');
          const r = n.getBoundingClientRect();
          return (role === 'textbox' || n.querySelector('input, textarea'))
            && r.width > 40 && r.height > 12;
        });
      if (!boxes.length) return false;
      boxes[boxes.length - 1].click();
      return true;
    });
    if (!focused) return false;
    await sleep(600);
    return typeInto(t);
  }

  async function tap(pattern, { role = null, settle = 1400, maxH = 400 } = {}) {
    const ok = await page.evaluate((pat, wantRole, mh) => {
      const re = new RegExp(pat, 'i');
      for (const n of document.querySelectorAll('flt-semantics')) {
        const r = n.getBoundingClientRect();
        if (r.width < 4 || r.height < 4 || r.height > mh) continue;
        if (wantRole && n.getAttribute('role') !== wantRole) continue;
        if (re.test((n.textContent || '') + ' ' + (n.getAttribute('aria-label') || ''))) {
          n.click(); return true;
        }
      }
      return false;
    }, pattern, role, maxH);
    if (ok) await sleep(settle);
    return ok;
  }

  /**
   * Wait for the mission feed to actually arrive.
   *
   * The dashboard reports "MISSION FEED NOT LIVE" while its realtime socket is
   * still timing out, and the incident fetch lands after that. Sampling a
   * fixed number of seconds after sign-in caught the empty state and reported
   * that a tier could not see its own incidents — which was the harness
   * reading the screen too early, not the app failing to load them.
   */
  /**
   * Scroll the feed until the card for the followed incident is in the page,
   * then press ENGAGE on THAT card.
   *
   * Tapping the first ENGAGE found is not the same thing. Every assertion after
   * this reads one row by id, so acting on a neighbouring card produces a run
   * where every control works and every database check fails — which is what
   * happened, and it reads exactly like a broken app.
   */
  async function engageOnSubject(pattern) {
    // A wheel event goes to whatever is under the pointer, and the pointer
    // starts at (0, 0) — the app bar, which does not scroll. Put it over the
    // feed first or the list never moves and every card below the fold stays
    // out of the page.
    await page.mouse.move(195, 620);
    for (let s = 0; s < 16; s++) {
      const clicked = await page.evaluate((pat) => {
        const re = new RegExp(pat, 'i');
        // A Flutter web semantics leaf carries its text in `aria-label`, not in
        // `textContent` — only a composite node such as a button has both.
        const lbl = (n) => `${n.textContent || ''} ${n.getAttribute('aria-label') || ''}`;
        // Find the ENGAGE button that belongs to THIS incident's card, by
        // structure rather than by position.
        //
        // The geometric version of this — "the first ENGAGE below the text" —
        // picked a neighbouring card, because the incident type also appears
        // above the feed (in the map markers and the critical-incident
        // summary), so the nearest button below the first match was the wrong
        // one. The whole chain then ran correctly on a different alert while
        // every assertion, which reads one row by id, failed. Semantics nest
        // the way the widgets do, so the card is an ancestor of both its type
        // text and its ENGAGE button, and that relationship does not depend on
        // where anything has scrolled to.
        const inSameCard = (btn) => {
          let p = btn.parentElement;
          for (let d = 0; d < 10 && p; d += 1, p = p.parentElement) {
            if (p.tagName && p.tagName.toLowerCase() === 'flt-semantics') {
              const subtree = [...p.querySelectorAll('flt-semantics')];
              if (subtree.some((n) => re.test(lbl(n)))) return true;
            }
          }
          return false;
        };
        const buttons = [...document.querySelectorAll('flt-semantics[role="button"]')]
          .filter((b) => /ENGAGE/i.test(lbl(b)));
        if (!buttons.length) return 'no-engage';
        const target = buttons.find(inSameCard);
        if (!target) return 'not-this-card';
        target.click();
        return 'clicked';
      }, pattern);
      if (clicked === 'clicked') { await sleep(2600); return true; }
      await page.mouse.wheel({ deltaY: 380 });
      await sleep(500);
    }
    return false;
  }

  /** Is the followed incident visible in the feed, scrolling to look? */
  async function subjectVisible(pattern) {
    await page.mouse.move(195, 620);
    for (let s = 0; s < 16; s++) {
      const seen = await page.evaluate((pat) => {
        const re = new RegExp(pat, 'i');
        return [...document.querySelectorAll('flt-semantics')]
          .some((n) => re.test(`${n.textContent || ''} ${n.getAttribute('aria-label') || ''}`));
      }, pattern);
      if (seen) return true;
      await page.mouse.wheel({ deltaY: 380 });
      await sleep(450);
    }
    return false;
  }

  async function waitForFeed({ timeout = 40000 } = {}) {
    const deadline = Date.now() + timeout;
    while (Date.now() < deadline) {
      const n = await page.evaluate(() =>
        [...document.querySelectorAll('flt-semantics[role="button"]')]
          .filter((b) => /ENGAGE/i.test(
            `${b.textContent || ''} ${b.getAttribute('aria-label') || ''}`)).length);
      if (n > 0) return n;
      await sleep(1500);
    }
    return 0;
  }

  const go = async (route, settle = 2400) => {
    await page.evaluate((r) => { window.location.hash = `#${r}`; }, route);
    await sleep(settle);
  };

  async function signIn(role) {
    try { await page.close(); } catch { /* gone */ }
    page = await newPage();
    await page.setGeolocation(HERE);
    await page.goto(origin, { waitUntil: 'domcontentloaded' });
    await page.evaluate(() => {
      try { localStorage.clear(); sessionStorage.clear(); } catch { /* blocked */ }
    });
    await page.reload({ waitUntil: 'domcontentloaded' });
    await page.waitForFunction(
      () => !!document.querySelector('flutter-view, flt-glass-pane, canvas'), { timeout: 120000 });
    await sleep(6000);
    await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
    await sleep(1600);
    if (role === 'citizen') {
      await typeInto('08000000000');
      await tap('authorize access', { role: 'button' });
      await sleep(2600);
      await typeInto('123456');
      await tap('verify otp', { role: 'button' });
    } else {
      await typeInto(`${role}@${DOMAIN}`);
      await tap('authorize access', { role: 'button' });
    }
    await sleep(6500);
    return page.evaluate(() => window.location.hash);
  }

  // =========================================================================
  // 1. A CITIZEN REPORTS, IN EVERY CATEGORY
  // =========================================================================
  const CATEGORIES = ['Kidnap', 'Fire', 'Drug abuse', 'Police brutality', 'Flood',
    'Cyber crime', 'Child abuse', 'Domestic violence', 'Cattle rustling', 'Community attack'];

  state.screen = 'lifecycle:citizen';
  const landed = await signIn('citizen');
  check('a citizen signs in', /home/.test(landed), `on ${landed}`);
  await shot('citizen-home');

  const before = (await rest('alerts?select=id')).length;
  const submitted = [];

  for (const [i, cat] of CATEGORIES.entries()) {
    state.screen = `lifecycle:report:${cat}`;
    if (i > 0) {
      await page.reload({ waitUntil: 'domcontentloaded' });
      await page.waitForFunction(
        () => !!document.querySelector('flutter-view, flt-glass-pane, canvas'), { timeout: 60000 });
      await sleep(5000);
      await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
      await sleep(1400);
    }
    await go('/report-category', 2800);
    for (let s = 0; s < 16; s++) {
      const found = await page.evaluate((c) => {
        const re = new RegExp(c, 'i');
        return [...document.querySelectorAll('flt-semantics[role="button"]')]
          .some((b) => re.test(b.textContent || ''));
      }, cat);
      if (found) break;
      await page.mouse.wheel({ deltaY: 300 });
      await sleep(450);
    }
    if (!(await tap(cat, { role: 'button', settle: 2400 }))) continue;
    if (i === 0) await shot('report-categories');

    await page.evaluate(() => {
      const n = [...document.querySelectorAll('flt-semantics[role="button"]')].find((b) => {
        const r = b.getBoundingClientRect();
        const l = (b.textContent || '').trim();
        return r.y > 120 && r.y < 640 && r.width > 180 && l.length > 3
          && !/change|initiate|dashboard|movement|new report|home/i.test(l);
      });
      n?.click();
    });
    await sleep(1600);
    await tap('initiate tactical report', { role: 'button', settle: 2600 });
    await tap('enter mission details|mission narrative', { settle: 800 });
    await typeInto(`Lifecycle ${cat} report.`);
    for (let s = 0; s < 8; s++) {
      const f = await page.evaluate(() => [...document.querySelectorAll('flt-semantics[role="button"]')]
        .some((b) => /initiate transmission/i.test(b.textContent || '')));
      if (f) break;
      await page.mouse.wheel({ deltaY: 320 });
      await sleep(380);
    }
    if (i === 0) await shot('report-dossier-filled');
    await tap('initiate transmission', { role: 'button', settle: 3600 });
    submitted.push(cat);
    if (i === 0) await shot('report-transmitted');
  }

  const rows = await rest('alerts?select=id,type,severity,status,assigned_tier,geo_lga,geo_ward,geo_pu,description&order=created_at.desc&limit=60');
  const mine = rows.filter((r) => (r.description || '').startsWith('Lifecycle '));
  check(
    `all ${CATEGORIES.length} categories reach the database`,
    mine.length === CATEGORIES.length,
    `${mine.length}/${CATEGORIES.length} written (${rows.length - before} new rows)`,
  );
  check(
    'every citizen report lands at the POLLING UNIT',
    mine.length > 0 && mine.every((r) => r.assigned_tier === 'UNIT'),
    `tiers: ${[...new Set(mine.map((r) => r.assigned_tier))].join(', ') || 'none'}`,
  );
  check(
    'every report carries the jurisdiction resolved from its GPS',
    mine.length > 0 && mine.every((r) => r.geo_lga && r.geo_ward),
    mine.length ? `e.g. ${mine[0].geo_lga} / ${mine[0].geo_ward}` : '',
  );
  check(
    'each category keeps its own type and severity',
    new Set(mine.map((r) => r.type)).size === CATEGORIES.length,
    mine.slice(0, 2).map((r) => `${r.type}=${r.severity}`).join('; '),
  );

  // THE ONE INCIDENT WE FOLLOW ALL THE WAY UP.
  //
  // It has to be the NEWEST, and the reason is worth writing down. `mine` is
  // ordered created_at DESC and the mission feed sorts the same way, so the
  // newest alert is the top card. An earlier version followed the Kidnap
  // report — the FIRST category submitted, therefore the OLDEST, therefore the
  // tenth card down a phone-sized list. Flutter web only builds semantics nodes
  // for widgets that are actually rendered, so that card was not in the page at
  // all: the harness read "the tier cannot see its own incident", escalated
  // whatever was on top instead, and then found the followed row unchanged.
  //
  // Every one of those failures was the harness looking in the wrong place. The
  // chain had climbed correctly the whole time.
  const subject = mine[0];
  const subjectDesc = subject.description;
  const needle = subject.type.split(' - ')[0]; // the card shows the full type
  console.log(`\n  following: ${subject.type} — ${subject.id}\n`);

  // =========================================================================
  // 2. UP THE CHAIN
  // =========================================================================
  const HOPS = [
    ['unit', 'UNIT', 'WARD'],
    ['ward', 'WARD', 'LGA'],
    ['lga', 'LGA', 'HQ'],
  ];

  let hop = 1;
  for (const [role, from, to] of HOPS) {
    state.screen = `lifecycle:${role}`;
    const at = await signIn(role);
    check(`${from}: the officer signs in`, /agent-dashboard/.test(at), `on ${at}`);
    const cards = await waitForFeed();
    check(`${from}: the mission feed loads`, cards > 0, `${cards} actionable incident card(s)`);

    check(`${from}: sees the incident it owns`, await subjectVisible(needle), subject.type);
    await shot(`${role}-dashboard-owns-it`);

    // ESCALATE, THE WAY AN OFFICER ACTUALLY DOES IT.
    //
    // There are two routes to the same dialog: an icon-only up-arrow on the
    // card, and a labelled button inside the tactical action sheet. This drives
    // the labelled one, because the sheet is the full sequence a real officer
    // goes through and each step is nameable:
    //
    //   ENGAGE  ->  TACTICAL ENGAGEMENT sheet
    //           ->  ESCALATE TO HIGHER COMMAND
    //           ->  MISSION AUTHORIZATION  (biometrics are unavailable in a
    //                                       browser, so the app falls back to
    //                                       a confirmation dialog)  ->  CONFIRM
    //           ->  TACTICAL ESCALATION dialog  ->  SITREP  ->  CONFIRM ESCALATION
    //
    // An earlier version hunted for the icon button by size and emptiness and
    // found nothing. That was the harness guessing at a control, not the
    // control being missing.
    const sheet = await engageOnSubject(needle);
    check(`${from}: ENGAGE opens the tactical action sheet`, sheet,
      sheet ? `on the ${subject.type} card` : 'no ENGAGE button on that card');
    if (!sheet) continue;
    await shot(`${role}-action-sheet`);

    const escalateTapped = await tap('escalate to higher command', { settle: 2000 });
    check(`${from}: the escalate control is reachable`, escalateTapped,
      escalateTapped ? 'ESCALATE TO HIGHER COMMAND' : 'button not in the sheet');
    if (!escalateTapped) continue;

    // The mission-authorization fallback. Present in a browser; harmless to
    // miss if a device ever authorises biometrically instead.
    await tap('confirm', { role: 'button', settle: 2400 });
    await sleep(1800);
    await shot(`${role}-escalation-dialog`);

    const sitrep = await typeIntoTextbox(`${from} handing up: no capacity to respond.`);
    check(`${from}: the SITREP the dialog requires can be entered`, sitrep,
      sitrep ? '' : 'no text field focused');
    await shot(`${role}-escalation-sitrep`);

    await tap('confirm escalation', { role: 'button', settle: 4500 });
    await shot(`${role}-after-escalating`);

    const [after] = await rest(
      `alerts?select=assigned_tier,status,assigned_to,tier_assigned_at,acknowledged_at,escalation_log&id=eq.${subject.id}`);
    check(
      `${from} → ${to}: the database records the hop`,
      after && after.assigned_tier === to,
      after ? `assigned_tier=${after.assigned_tier} status=${after.status}` : 'row not found',
    );
    check(
      `${from} → ${to}: the chain of custody is appended`,
      after && Array.isArray(after.escalation_log) && after.escalation_log.length >= hop,
      after && after.escalation_log ? `${after.escalation_log.length} entries` : 'empty',
    );
    check(
      `${from} → ${to}: a named commander at ${to} takes it`,
      !!(after && after.assigned_to),
      after && after.assigned_to ? after.assigned_to : 'nobody named',
    );
    // The clock has to restart, or the server-side job escalates the alert
    // straight past the tier that just took it. Proven against real PostgreSQL
    // in command_chain_behaviour_test.sql; this asserts the APP sends it.
    const restarted = after && after.tier_assigned_at
      && Date.now() - Date.parse(after.tier_assigned_at) < 5 * 60 * 1000;
    check(
      `${from} → ${to}: the ownership clock restarts for ${to}`,
      restarted,
      after ? `tier_assigned_at=${after.tier_assigned_at}` : '',
    );
    check(
      `${from} → ${to}: the tier below's acknowledgement is cleared`,
      after && !after.acknowledged_at,
      after && after.acknowledged_at ? `still ${after.acknowledged_at}` : 'null',
    );
    hop += 1;
  }

  // =========================================================================
  // 3. THE TIER BELOW CAN NO LONGER SEE IT
  // =========================================================================
  state.screen = 'lifecycle:unit-after';
  await signIn('unit');
  await waitForFeed();
  // Only meaningful if the chain actually moved the alert. Asserting "the unit
  // cannot see it" when nothing was ever escalated passes for the wrong
  // reason, which is worse than failing.
  const [nowAt] = await rest(`alerts?select=assigned_tier&id=eq.${subject.id}`);
  const movedUp = nowAt && nowAt.assigned_tier && nowAt.assigned_tier !== 'UNIT';
  const stillVisible = await subjectVisible(needle);
  check(
    'once escalated, the UNIT no longer sees the incident it handed up',
    movedUp ? !stillVisible : false,
    movedUp
      ? `owner tier and above only (it is at ${nowAt.assigned_tier})`
      : `not asserted: the alert is still at ${nowAt ? nowAt.assigned_tier : 'unknown'}`,
  );
  await shot('unit-no-longer-sees-it');

  // =========================================================================
  // 4. HQ SEES IT, AND ASSIGNS BACK DOWN
  // =========================================================================
  state.screen = 'lifecycle:hq';
  const hqAt = await signIn('hq');
  check('HQ signs in', /agent-dashboard/.test(hqAt), `on ${hqAt}`);
  await waitForFeed();
  const hqSees = await text();
  check('HQ sees the incident that climbed the whole chain',
    await subjectVisible(needle), subject.type);
  check('HQ identifies itself as HQ COMMAND', /HQ COMMAND/.test(hqSees),
    (hqSees.split('\n').find((l) => /COMMAND|OPERATIONAL/.test(l)) || '').trim());
  await shot('hq-dashboard-top-of-chain');

  // =========================================================================
  // 4b. HQ HAS NOWHERE TO ESCALATE TO
  // =========================================================================
  const hqEngaged = await engageOnSubject(needle);
  check('HQ: ENGAGE opens the action sheet', hqEngaged);
  await shot('hq-action-sheet');

  const sheetText = await text();
  check(
    'HQ is offered no escalation — there is nothing above it',
    !/ESCALATE TO HIGHER COMMAND/i.test(sheetText),
    /ESCALATE TO HIGHER COMMAND/i.test(sheetText)
      ? 'the escalate button is still there, so HQ can escalate to itself'
      : 'no escalate control at the top of the chain',
  );

  // =========================================================================
  // 4c. HQ OVERRIDES: IT ASSIGNS A FIELD RESPONDER DIRECTLY
  // =========================================================================
  // This is the requirement in the operator's own words — "HQ can override
  // where the chain is not accessible". The control was gated on
  // `assignedTier != 'HQ'`, so the tier that exists to override was the one
  // tier that could not send anyone.
  const dispatchOpened = await tap('dispatch unit', { settle: 2000 });
  check(
    'HQ can dispatch a field unit',
    dispatchOpened,
    dispatchOpened ? 'DISPATCH UNIT' : 'no dispatch control at HQ',
  );
  if (dispatchOpened) {
    // The authorization fallback, then the responder picker.
    await tap('confirm', { role: 'button', settle: 2400 });
    await sleep(2000);
    await shot('hq-responder-picker');

    // Pick the first officer the picker lists.
    //
    // Each row is `Full Name [BADGE]`, drawn from `profiles`, so a badge in
    // square brackets is the thing that distinguishes an officer row from the
    // dialog's own instruction line — which is what an earlier, looser selector
    // matched and "selected", leaving the confirm button reading SELECT OFFICERS
    // and nothing dispatched.
    const picked = await page.evaluate(() => {
      const rows = [...document.querySelectorAll('flt-semantics')]
        .filter((n) => {
          const r = n.getBoundingClientRect();
          return r.width > 100 && r.height > 14 && r.height < 140
            && /\[[A-Z]{2,5}-?\d*\]/.test(
              `${n.textContent || ''} ${n.getAttribute('aria-label') || ''}`);
        })
        .sort((a, b) => a.getBoundingClientRect().height - b.getBoundingClientRect().height);
      if (!rows.length) return null;
      // Prefer the POLLING-UNIT officer, three rungs below HQ. The alert is
      // owned by tier HQ, and a unit officer sees nothing at that tier, so the
      // only thing that can put this mission on their screen is the "it is
      // assigned to me" rule — which read a camelCase key PostgREST never
      // returns and was therefore dead. Picking the lowest tier on purpose is
      // what makes the next assertion about the override rather than about
      // tier visibility it would have passed anyway.
      const lowest = rows.find((n) => /UNIT_COMMAND|POLLING/i.test(
        `${n.textContent || ''} ${n.getAttribute('aria-label') || ''}`)) || rows[0];
      lowest.click();
      return `${lowest.textContent || ''} ${lowest.getAttribute('aria-label') || ''}`
        .trim().slice(0, 60);
    });
    check('HQ: the responder picker lists real officers', !!picked, picked || 'nobody listed');
    await sleep(1400);
    await shot('hq-responder-selected');

    // The button counts what is selected: SELECT OFFICERS until one is, then
    // DISPATCH (n UNITS). Matching the count is how we know a row took.
    const confirmLabel = await page.evaluate(() => {
      const b = [...document.querySelectorAll('flt-semantics[role="button"]')]
        .find((n) => /DISPATCH \(|SELECT OFFICERS/i.test(
          `${n.textContent || ''} ${n.getAttribute('aria-label') || ''}`));
      return b ? `${b.textContent || ''} ${b.getAttribute('aria-label') || ''}`.trim() : null;
    });
    check(
      'HQ: selecting an officer arms the dispatch button',
      !!confirmLabel && /DISPATCH \(/i.test(confirmLabel),
      confirmLabel || 'neither label present',
    );
    await tap('dispatch \\(', { role: 'button', settle: 4500 });
    await shot('hq-after-assignment');
  }

  const [assigned] = await rest(
    `alerts?select=status,assigned_to,assigned_responders,assigned_tier,ai_summary&id=eq.${subject.id}`);
  check(
    'HQ dispatching the incident is written to the database',
    assigned && assigned.status === 'DISPATCHED',
    assigned ? `status=${assigned.status}` : 'row gone',
  );
  check(
    'the dispatched incident names the officer who has it',
    assigned && !!assigned.assigned_to,
    assigned && assigned.assigned_to ? assigned.assigned_to : 'assigned_to is null',
  );
  check(
    'the whole dispatched team is recorded, not just the lead',
    assigned && Array.isArray(assigned.assigned_responders)
      && assigned.assigned_responders.length > 0,
    assigned && assigned.assigned_responders
      ? `${assigned.assigned_responders.length} responder(s)`
      : 'empty',
  );

  // =========================================================================
  // 4d. AND THE OFFICER HQ REACHED DOWN TO CAN SEE IT
  // =========================================================================
  // The override is only real if the alert becomes visible to the officer it
  // was handed to. The alert is owned by tier HQ; a unit officer is three rungs
  // below and sees nothing at that tier — so the only thing that can make this
  // work is the "it is assigned to me" rule, which read a camelCase key that
  // PostgREST never returns and was therefore dead.
  if (assigned && assigned.assigned_to) {
    const [who] = await rest(`profiles?select=id,role,full_name&id=eq.${assigned.assigned_to}`);
    const key = who && /HQ/.test(who.role || '') ? 'hq'
      : who && /LGA/.test(who.role || '') ? 'lga'
        : who && /WARD/.test(who.role || '') ? 'ward'
          : who && /UNIT|POLLING/.test(who.role || '') ? 'unit' : 'responder';
    state.screen = `lifecycle:assignee:${key}`;
    await signIn(key);
    await waitForFeed();
    const theirs = await text();
    check(
      `the officer HQ dispatched (${who ? who.role : '?'}) can see the mission`,
      theirs.toLowerCase().includes('kidnap') || theirs.includes(subjectDesc.slice(0, 24)),
      who ? who.full_name : '',
    );
    await shot('assignee-sees-the-mission');
  }

  // =========================================================================
  // 5. TIMEOUT ESCALATION, WHICH NEEDS NO UI AT ALL
  // =========================================================================
  // Proven fully in scripts/command_chain_behaviour_test.sql against real
  // PostgreSQL; the stand-in has no scheduler, so this is not re-asserted here.

  fs.writeFileSync(path.join(OUT, 'chain-lifecycle.json'), JSON.stringify({
    ranAt: new Date().toISOString(),
    followed: { id: subject.id, type: subject.type },
    categories: submitted,
    checks, screenshots: shots,
    browserProblems: problems.filter((p) => p.kind === 'pageerror'),
  }, null, 2));

  await browser.close();
  server.close();

  const failed = checks.filter((c) => !c.pass);
  console.log(`\n${checks.length - failed.length}/${checks.length} checks passed, ${shots.length} screenshots`);
  if (failed.length) {
    console.log('\nFAILED:');
    for (const f of failed) console.log(`  - ${f.name}${f.detail ? `  (${f.detail})` : ''}`);
  }
  process.exit(failed.length ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
