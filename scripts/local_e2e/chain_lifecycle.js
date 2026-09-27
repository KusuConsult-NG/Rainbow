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

  // The one incident we follow all the way up.
  const subject = mine.find((r) => /Kidnap/i.test(r.type)) || mine[0];
  const subjectDesc = subject.description;
  console.log(`\n  following: ${subject.type} — ${subject.id}\n`);

  // =========================================================================
  // 2. UP THE CHAIN
  // =========================================================================
  const HOPS = [
    ['unit', 'UNIT', 'WARD'],
    ['ward', 'WARD', 'LGA'],
    ['lga', 'LGA', 'HQ'],
  ];

  for (const [role, from, to] of HOPS) {
    state.screen = `lifecycle:${role}`;
    const at = await signIn(role);
    check(`${from}: the officer signs in`, /agent-dashboard/.test(at), `on ${at}`);
    await sleep(2500);

    const seen = await text();
    check(
      `${from}: sees the incident it owns`,
      seen.includes(subjectDesc.slice(0, 24)) || seen.toLowerCase().includes('kidnap'),
      '',
    );
    await shot(`${role}-dashboard-owns-it`);

    // The escalate control is the up-arrow on the card: an icon button with no
    // text, sitting beside ENGAGE.
    const opened = await page.evaluate(() => {
      const btns = [...document.querySelectorAll('flt-semantics[role="button"]')]
        .filter((b) => {
          const r = b.getBoundingClientRect();
          return r.width > 20 && r.width < 90 && r.height > 20 && r.height < 90
            && !(b.textContent || '').trim();
        });
      // first icon-only button in the card region
      const target = btns.find((b) => b.getBoundingClientRect().y > 200);
      if (!target) return false;
      target.click();
      return true;
    });
    await sleep(2200);
    if (!opened) {
      check(`${from}: the escalate control is reachable`, false, 'icon button not found');
      continue;
    }
    await shot(`${role}-escalation-dialog`);

    await tap('confirm escalation', { role: 'button', settle: 4000 });
    await shot(`${role}-after-escalating`);

    const [after] = await rest(`alerts?select=assigned_tier,status,escalation_log&id=eq.${subject.id}`);
    check(
      `${from} → ${to}: the database records the hop`,
      after && after.assigned_tier === to,
      after ? `assigned_tier=${after.assigned_tier} status=${after.status}` : 'row not found',
    );
    check(
      `${from} → ${to}: the chain of custody is appended`,
      after && Array.isArray(after.escalation_log) && after.escalation_log.length > 0,
      after && after.escalation_log ? `${after.escalation_log.length} entries` : 'empty',
    );
  }

  // =========================================================================
  // 3. THE TIER BELOW CAN NO LONGER SEE IT
  // =========================================================================
  state.screen = 'lifecycle:unit-after';
  await signIn('unit');
  await sleep(2500);
  const unitSees = await text();
  check(
    'once escalated, the UNIT no longer sees the incident it handed up',
    !unitSees.includes(subjectDesc.slice(0, 24)),
    'owner tier and above only',
  );
  await shot('unit-no-longer-sees-it');

  // =========================================================================
  // 4. HQ SEES IT, AND ASSIGNS BACK DOWN
  // =========================================================================
  state.screen = 'lifecycle:hq';
  const hqAt = await signIn('hq');
  check('HQ signs in', /agent-dashboard/.test(hqAt), `on ${hqAt}`);
  await sleep(2500);
  const hqSees = await text();
  check(
    'HQ sees the incident that climbed the whole chain',
    hqSees.toLowerCase().includes('kidnap') || hqSees.includes(subjectDesc.slice(0, 24)),
    '',
  );
  check('HQ identifies itself as HQ COMMAND', /HQ COMMAND/.test(hqSees),
    (hqSees.split('\n').find((l) => /COMMAND|OPERATIONAL/.test(l)) || '').trim());
  await shot('hq-dashboard-top-of-chain');

  // ENGAGE is the assignment: HQ takes the incident and dispatches.
  const engaged = await tap('engage', { role: 'button', settle: 3500 });
  await shot('hq-assigning');
  if (engaged) {
    await tap('confirm|dispatch|assign|proceed|yes', { role: 'button', settle: 3500 });
    await shot('hq-after-assignment');
  }
  const [assigned] = await rest(`alerts?select=status,assigned_to,assigned_tier&id=eq.${subject.id}`);
  check(
    'HQ assigning the incident is written to the database',
    assigned && (assigned.assigned_to || assigned.status !== 'ESCALATED'),
    assigned ? `status=${assigned.status} assigned_to=${assigned.assigned_to ? 'set' : 'null'}` : 'row gone',
  );

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
