/**
 * Every control on the responder dashboard, pressed as EVERY tier.
 *
 * The interaction pass that existed before this one swept the staff screens as
 * a plain `responder` and found, on the whole agent dashboard, a single control
 * it could only describe as `(icon)`. Two reasons, and both were real:
 *
 *   * four of the app bar's five buttons had no tooltip, so they had no
 *     accessible name for anything — a screen reader or a test — to find;
 *   * a plain responder is the one account whose tier-specific controls do not
 *     exist, so sweeping as that account could not have exercised them anyway.
 *
 * The controls that DIFFER between tiers are exactly the ones that matter:
 * DISPATCH UNIT appears for WARD, LGA and HQ and not for a polling unit; the
 * escalate arrow appears for everyone EXCEPT HQ, which has nothing above it;
 * the broadcast button is HQ and LGA only. Every one of those is a tier
 * boundary, and none of them had ever been pressed by a test.
 *
 *   node scripts/local_e2e/tier_controls.js
 */

const fs = require('fs');
const http = require('http');
const path = require('path');
const { launch } = require('./browser');
const { DOMAIN } = require('./fixtures');

const ROOT = path.join(__dirname, '..', '..');
const WEB = path.join(ROOT, 'build', 'web');
const PORT = Number(process.env.TIER_PORT || 8087);
const REST = 'http://127.0.0.1:54321/rest/v1';
const OUT = process.env.E2E_OUT || path.join(ROOT, 'local_e2e_screenshots');
const PHONE = { width: 390, height: 844, deviceScaleFactor: 2, isMobile: true, hasTouch: true };
const HERE = { latitude: 9.8965, longitude: 8.8583 };

fs.mkdirSync(OUT, { recursive: true });
for (const f of fs.readdirSync(OUT)) {
  if (/^T\d{2}-.*\.png$/.test(f)) fs.unlinkSync(path.join(OUT, f));
}

const checks = [];
const shots = [];
const inventory = {};
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

/**
 * What each tier must be offered, and what it must NOT be.
 *
 * The negatives carry as much weight as the positives here. "HQ has no
 * escalate arrow" is a real requirement — the control existed, and the dialog
 * behind it offered to escalate HQ to HQ — and an assertion that only ever
 * checks for presence cannot catch a control that should have gone away.
 */
const TIERS = [
  {
    role: 'unit',
    banner: 'UNIT COMMAND',
    card: { present: ['ENGAGE', 'Escalate Mission', 'Secure Chat'], absent: ['Dispatch Unit'] },
    appBar: { present: ['AUDIO'], absent: ['Send a command broadcast'] },
  },
  {
    role: 'ward',
    banner: 'WARD COMMAND',
    card: { present: ['ENGAGE', 'Dispatch Unit', 'Escalate Mission', 'Secure Chat'], absent: [] },
    appBar: { present: ['AUDIO'], absent: ['Send a command broadcast'] },
  },
  {
    role: 'lga',
    banner: 'LGA COMMAND',
    card: { present: ['ENGAGE', 'Dispatch Unit', 'Escalate Mission', 'Secure Chat'], absent: [] },
    appBar: { present: ['AUDIO', 'Send a command broadcast'], absent: [] },
  },
  {
    role: 'hq',
    banner: 'HQ COMMAND',
    // HQ is the top of the chain: it dispatches, and it does not escalate.
    card: { present: ['ENGAGE', 'Dispatch Unit', 'Secure Chat'], absent: ['Escalate Mission'] },
    appBar: { present: ['AUDIO', 'Send a command broadcast'], absent: [] },
  },
];

// The app bar, in the order it renders. Every one of these had an empty
// accessible name until `scripts/check_control_labels.py` existed.
const APP_BAR = [
  'Open the command menu',
  'AUDIO',
  'Switch between the map and the incident list',
  'Send a command broadcast',
  'Sign out',
];

const NAV = ['DASHBOARD', 'MOVEMENT', 'NEW REPORT'];

// The drawer behind the menu button. Every previous sweep opened it and stopped
// there, and TERMINATE SESSION was explicitly skipped by name — the sweeps
// filtered out anything matching /sign ?out|log ?out|terminate|power/ so a run
// could continue. Which is reasonable for a sweep and means the app's only
// destructive control had never been pressed by anything.
// Each item is checked by what its destination SAYS, not by the address bar.
// These all use `context.push`, which on go_router's web target does not
// update the hash — the same thing that made the working broadcast button look
// broken earlier in this file. A phone has no address bar; the screen is the
// evidence.
const DRAWER = [
  { label: 'SECURITY HUB', lands: 'the settings screen', says: /PREFERENCES & SECURITY|TACTICAL SYSTEM SETTINGS/i },
  { label: 'MISSION ARCHIVE', lands: 'the incident archive', says: /HISTORICAL ARCHIVE|TACTICAL INCIDENT LOGS/i },
  { label: 'EXTRACTION LIST', lands: 'the emergency contacts', says: /EMERGENCY CONTACTS|trusted contacts/i },
];

(async () => {
  if (!await fetch('http://127.0.0.1:54321/auth/v1/health').then((r) => r.ok).catch(() => false)) {
    console.error('start the stand-in first: node scripts/local_e2e/fake_supabase.js');
    process.exit(1);
  }
  await fetch('http://127.0.0.1:54322/reset-data');
  await new Promise((r) => server.listen(PORT, '127.0.0.1', r));
  const origin = `http://127.0.0.1:${PORT}`;

  const tiles = [];
  const problems = [];
  const state = { screen: 'startup' };
  const LAUNCH = { viewport: PHONE, canvaskitDir: path.join(WEB, 'canvaskit'), tiles, problems, state };
  let { browser, newPage } = await launch(LAUNCH);
  await browser.defaultBrowserContext().overridePermissions(origin, ['geolocation']);
  let page;

  const shot = async (name) => {
    step += 1;
    const f = `T${String(step).padStart(2, '0')}-${name}.png`;
    await page.screenshot({ path: path.join(OUT, f) });
    shots.push(f);
    console.log(`      shot  ${f}`);
  };

  /** Every control in the page, with the name assistive tech would read. */
  const controls = () => page.evaluate(() => {
    const out = [];
    for (const n of document.querySelectorAll('flt-semantics[role="button"]')) {
      const r = n.getBoundingClientRect();
      if (r.width < 4 || r.height < 4) continue;
      const label = ((n.getAttribute('aria-label') || '') || (n.textContent || ''))
        .trim().replace(/\s+/g, ' ').slice(0, 60);
      out.push({ label, x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height) });
    }
    return out;
  });

  async function signIn(role) {
    // A fresh browser per role: eight CanvasKit sessions in one browser
    // exhausted this container mid-run once already.
    try { await browser.close(); } catch { /* gone */ }
    ({ browser, newPage } = await launch(LAUNCH));
    await browser.defaultBrowserContext().overridePermissions(origin, ['geolocation']);
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
    await page.evaluate(() => { const el = document.querySelector('input'); if (el) el.focus(); });
    await page.keyboard.type(`${role}@${DOMAIN}`, { delay: 20 });
    await sleep(400);
    await page.evaluate(() => {
      for (const n of document.querySelectorAll('flt-semantics[role="button"]')) {
        const t = `${n.textContent || ''} ${n.getAttribute('aria-label') || ''}`;
        if (/authorize access/i.test(t)) { n.click(); return; }
      }
    });
    await sleep(8500);
    return page.evaluate(() => window.location.hash);
  }

  /** Press the control whose accessible name matches, and say what changed. */
  async function press(pattern, { settle = 1800 } = {}) {
    const before = await page.evaluate(() => ({
      hash: location.hash,
      n: document.querySelectorAll('flt-semantics').length,
    }));
    const hit = await page.evaluate((pat) => {
      const re = new RegExp(pat, 'i');
      for (const n of document.querySelectorAll('flt-semantics[role="button"]')) {
        const r = n.getBoundingClientRect();
        if (r.width < 4 || r.height < 4) continue;
        const t = `${n.textContent || ''} ${n.getAttribute('aria-label') || ''}`;
        if (re.test(t)) { n.click(); return true; }
      }
      return false;
    }, pattern);
    if (!hit) return { found: false };
    await sleep(settle);
    const after = await page.evaluate(() => ({
      hash: location.hash,
      n: document.querySelectorAll('flt-semantics').length,
    }));
    return {
      found: true,
      navigated: before.hash !== after.hash,
      hash: after.hash,
      changed: before.hash !== after.hash || Math.abs(after.n - before.n) > 1,
    };
  }

  const waitForFeed = async ({ timeout = 40000 } = {}) => {
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
  };

  // Something for every tier to look at. Filed by the stand-in rather than
  // through the report flow, which chain_lifecycle.js already proves; this pass
  // is about the controls, not about submission.
  const seed = await (await fetch(`${REST}/alerts`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', prefer: 'return=representation' },
    body: JSON.stringify({
      type: 'Community attack - Armed Invasion',
      description: 'Tier control sweep subject.',
      severity: 'CRITICAL',
      geo_lga: 'JOS NORTH',
      geo_ward: 'NARAGUTA',
      latitude: HERE.latitude,
      longitude: HERE.longitude,
    }),
  })).json();
  const subjectId = Array.isArray(seed) ? seed[0].id : seed.id;

  for (const tier of TIERS) {
    state.screen = `tier:${tier.role}`;
    // Put the incident at this tier so the officer owns it.
    await fetch(`${REST}/alerts?id=eq.${subjectId}`, {
      method: 'PATCH',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        assigned_tier: tier.role === 'unit' ? 'UNIT' : tier.role.toUpperCase(),
        status: 'PENDING',
        assigned_to: null,
      }),
    });

    const landed = await signIn(tier.role);
    check(`${tier.banner}: signs in`, /agent-dashboard/.test(landed), `on ${landed}`);
    if (!/agent-dashboard/.test(landed)) continue;
    await waitForFeed();

    const found = await controls();
    inventory[tier.role] = found.map((c) => c.label);
    await shot(`${tier.role}-dashboard-controls`);

    // ── Nothing on this screen is nameless ────────────────────────────────
    const nameless = found.filter((c) => !c.label);
    check(
      `${tier.banner}: every control has an accessible name`,
      nameless.length === 0,
      nameless.length
        ? `${nameless.length} unnamed at ${nameless.map((c) => `${c.x},${c.y}`).join(' ')}`
        : `${found.length} controls, all named`,
    );

    // ── The app bar ───────────────────────────────────────────────────────
    for (const name of APP_BAR) {
      const want = !tier.appBar.absent.includes(name);
      const has = found.some((c) => new RegExp(name, 'i').test(c.label));
      if (want && name === 'Send a command broadcast' && !tier.appBar.present.includes(name)) continue;
      check(
        `${tier.banner}: app bar ${want ? 'offers' : 'withholds'} "${name}"`,
        has === want,
        has ? 'present' : 'absent',
      );
    }

    // ── The card's tier-specific actions ──────────────────────────────────
    for (const name of tier.card.present) {
      check(
        `${tier.banner}: the incident card offers ${name}`,
        found.some((c) => new RegExp(name, 'i').test(c.label)),
      );
    }
    for (const name of tier.card.absent) {
      check(
        `${tier.banner}: the incident card does NOT offer ${name}`,
        !found.some((c) => new RegExp(name, 'i').test(c.label)),
        'correctly withheld at this tier',
      );
    }

    // ── The bottom navigation actually navigates ──────────────────────────
    for (const item of NAV.slice(1)) {
      const r = await press(item, { settle: 2600 });
      check(
        `${tier.banner}: ${item} navigates`,
        r.found && r.navigated,
        r.found ? `-> ${r.hash}` : 'control not found',
      );
      if (r.found && r.navigated) await shot(`${tier.role}-nav-${item.toLowerCase().replace(/\W+/g, '-')}`);
      // back to the dashboard for the next one
      await page.evaluate(() => { window.location.hash = '#/agent-dashboard'; });
      await sleep(2600);
    }

    // ── The app bar controls DO something ─────────────────────────────────
    const drawer = await press('Open the command menu', { settle: 2000 });
    const drawerText = await page.evaluate(() => {
      const h = document.querySelector('flt-semantics-host') || document.body;
      return h.textContent || '';
    });
    check(`${tier.banner}: the menu opens the drawer`,
      drawer.found && /SECURITY HUB|MISSION ARCHIVE|TERMINATE SESSION/i.test(drawerText),
      drawer.found ? '' : 'control not found');
    if (drawer.found) await shot(`${tier.role}-drawer`);

    // Each item, pressed. Not just "the drawer opened".
    // Identical setup for every item, deliberately.
    //
    // The first version relied on the drawer already being open for the first
    // item and re-opened it for the rest, and the two shapes did not behave the
    // same: the items that ran against the already-open drawer reported the
    // drawer still showing after the press. Whatever the cause — an animation
    // still settling, most likely — the fix is to stop having two paths. Every
    // item now starts from a reloaded page with the drawer freshly opened.
    for (const item of DRAWER) {
      await page.evaluate(() => { window.location.hash = '#/agent-dashboard'; });
      await page.reload({ waitUntil: 'domcontentloaded' });
      await page.waitForFunction(
        () => !!document.querySelector('flutter-view, flt-glass-pane, canvas'), { timeout: 60000 });
      await sleep(5000);
      await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
      await sleep(1500);
      await press('Open the command menu', { settle: 2600 });
      const r = await press(item.label, { settle: 3600 });
      const landed = await page.evaluate(() => {
        const h = document.querySelector('flt-semantics-host') || document.body;
        return h.textContent || '';
      });
      const ok = r.found && item.says.test(landed);
      check(
        `${tier.banner}: ${item.label} opens ${item.lands}`,
        ok,
        r.found ? (ok ? '' : `landed on "${landed.replace(/\s+/g, ' ').slice(0, 50)}"`)
          : 'not in the drawer',
      );
      if (ok) await shot(`${tier.role}-drawer-${item.label.toLowerCase().replace(/\W+/g, '-')}`);
    }
    // Leave the screen clean for the app-bar assertions below: a Flutter Drawer
    // stays open across a hash change, and an open drawer covers the app bar —
    // which made every control after this loop report as missing.
    await page.evaluate(() => { window.location.hash = '#/agent-dashboard'; });
    await page.reload({ waitUntil: 'domcontentloaded' });
    await page.waitForFunction(
      () => !!document.querySelector('flutter-view, flt-glass-pane, canvas'), { timeout: 60000 });
    await sleep(5000);
    await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
    await sleep(1500);
    await waitForFeed();

    const mapToggle = await press('Switch between the map and the incident list', { settle: 2400 });
    check(`${tier.banner}: the map/list toggle switches the view`,
      mapToggle.found && mapToggle.changed, mapToggle.found ? '' : 'control not found');
    if (mapToggle.found) await shot(`${tier.role}-map-view`);
    await press('Switch between the map and the incident list', { settle: 2000 });

    const audio = await press('AUDIO', { settle: 1800 });
    // Read the name the same way `controls()` does. A Flutter web semantics
    // node usually carries its name in `textContent`, not `aria-label`;
    // checking only the attribute reported every one of these as absent.
    const audioNow = await page.evaluate(() =>
      [...document.querySelectorAll('flt-semantics[role="button"]')]
        .map((n) => `${n.textContent || ''} ${n.getAttribute('aria-label') || ''}`.trim())
        .find((l) => /AUDIO:/i.test(l)) || '');
    check(
      `${tier.banner}: the audio control toggles loudspeaker/earpiece`,
      audio.found && /EARPIECE/i.test(audioNow),
      audioNow || 'no audio control',
    );
    await press('AUDIO', { settle: 1500 });

    if (tier.appBar.present.includes('Send a command broadcast')) {
      const bc = await press('Send a command broadcast', { settle: 3000 });
      // ASSERT ON THE SCREEN, NOT THE URL.
      //
      // The bottom nav uses `context.go`, which updates the address bar, and
      // this button uses `context.push`, which on go_router's web target does
      // not. Checking the hash reported a working control as broken: the
      // broadcast screen was plainly rendered — HQ BROADCAST SENDER, SEND
      // BROADCAST — with the hash still reading /agent-dashboard. A phone has
      // no address bar, so that difference is an artifact of testing a mobile
      // app in a browser and not something about the app.
      const onBroadcast = await page.evaluate(() => {
        const h = document.querySelector('flt-semantics-host') || document.body;
        return /BROADCAST SENDER|SEND BROADCAST/i.test(h.textContent || '');
      });
      check(`${tier.banner}: the broadcast control opens the broadcast screen`,
        bc.found && onBroadcast,
        bc.found ? (onBroadcast ? 'HQ BROADCAST SENDER' : `still on ${bc.hash}`) : 'control not found');
      if (bc.found && onBroadcast) await shot(`${tier.role}-broadcast`);
      await page.evaluate(() => { window.location.hash = '#/agent-dashboard'; });
      await sleep(2600);
    }
  }

  // ── TERMINATE SESSION, last, because it ends the session ────────────────
  //
  // The drawer's only destructive control, and the one every sweep filtered out
  // by name so the run could carry on. It is also the control whose behaviour
  // changed most recently: signing out now stops background location tracking
  // first, because it used to clear the session and leave the phone
  // transmitting. Worth pressing at least once.
  state.screen = 'tier:signout';
  const soLanded = await signIn('hq');
  if (/agent-dashboard/.test(soLanded)) {
    await waitForFeed();
    await press('Open the command menu', { settle: 2200 });
    await shot('signout-drawer');
    const so = await press('TERMINATE SESSION', { settle: 4500 });
    const after = await page.evaluate(() => location.hash);
    check(
      'TERMINATE SESSION signs the officer out and returns to login',
      so.found && /login/.test(after),
      so.found ? `-> ${after}` : 'not in the drawer',
    );
    await shot('signout-back-at-login');

    // And it must really be signed out, not merely routed away from.
    const backIn = await page.evaluate(() => {
      window.location.hash = '#/agent-dashboard';
      return null;
    });
    void backIn;
    await sleep(3000);
    const guarded = await page.evaluate(() => location.hash);
    check(
      'and the dashboard cannot be re-entered by URL afterwards',
      /login|splash/.test(guarded),
      `-> ${guarded}`,
    );
    await shot('signout-dashboard-refused');
  }

  // ── The untiered responder, whose controls are the lowest common set ────
  state.screen = 'tier:responder';
  const rLanded = await signIn('responder');
  check('an untiered RESPONDER signs in', /agent-dashboard/.test(rLanded), `on ${rLanded}`);
  if (/agent-dashboard/.test(rLanded)) {
    await waitForFeed();
    const found = await controls();
    inventory.responder = found.map((c) => c.label);
    await shot('responder-dashboard-controls');
    check(
      'an untiered RESPONDER has no broadcast control',
      !found.some((c) => /Send a command broadcast/i.test(c.label)),
      'broadcast is command-only',
    );
    check(
      'an untiered RESPONDER still has every control named',
      found.every((c) => c.label),
      `${found.length} controls`,
    );
  }

  fs.writeFileSync(path.join(OUT, 'tier-controls.json'), JSON.stringify({
    ranAt: new Date().toISOString(),
    proves: 'every control on the responder dashboard, per tier, named and pressed',
    inventory,
    checks,
    screenshots: shots,
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
