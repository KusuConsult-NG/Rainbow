/**
 * Press the buttons.
 *
 * `capture.js` proves the screens render. This proves they DO something: every
 * action a commander or an agency liaison can take is performed in a real
 * browser and checked against the write it was supposed to produce. A button
 * that looks right, logs nothing and writes nothing is the defect this exists
 * to find, and it is invisible to a screenshot.
 *
 * Two phases:
 *
 *   FLOWS   named actions — dispatch, escalate, resolve, approve an uninstall,
 *           save config, change a role, add an officer, deploy, file and
 *           acknowledge an action report, switch theme, sign out — each
 *           asserted against the database write it must cause.
 *
 *   SWEEP   every remaining visible, enabled control on every screen, clicked
 *           in turn, with what happened recorded: a request, a DOM change, a
 *           navigation, or nothing at all. The last is what we are hunting.
 *
 * As with capture.js, this proves behaviour and NOT row-level security: the
 * stand-in answers every query.
 *
 *   node scripts/local_e2e/interact.js
 */

const fs = require('fs');
const path = require('path');
const { launch, tileToLatLon } = require('./browser');
const { DOMAIN, PASSWORD } = require('./fixtures');

// Read out of the console's own source rather than written here: a harness with
// its own copy of this list is how the escalation menu drifted in the first
// place. src/lib/agencies.ts owns it.
const AGENCY_CODES = (() => {
  const src = fs.readFileSync(
    path.join(__dirname, '..', '..', 'hq-dashboard-next', 'src', 'lib', 'agencies.ts'),
    'utf8',
  );
  const block = /export const AGENCY_CODES = \[([^\]]*)\] as const;/.exec(src);
  if (!block) throw new Error('agencies.ts: AGENCY_CODES not found');
  return [...block[1].matchAll(/'([A-Z]+)'/g)].map((m) => m[1]);
})();

const BASE = process.env.CONSOLE_URL || 'http://127.0.0.1:3000';
const CONTROL = 'http://127.0.0.1:54322/';
const OUT = process.env.E2E_OUT || path.join(__dirname, '..', '..', 'local_e2e_screenshots');
const VIEWPORT = { width: 1600, height: 1000 };

fs.mkdirSync(OUT, { recursive: true });

const checks = [];
const shots = [];
const deadControls = [];
const sweepLog = [];

function check(name, pass, detail = '') {
  checks.push({ name, pass: !!pass, detail });
  console.log(`${pass ? 'PASS' : 'FAIL'}  ${name}${detail ? `  — ${detail}` : ''}`);
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function shot(page, name) {
  const file = path.join(OUT, `${name}.png`);
  await page.screenshot({ path: file });
  shots.push(path.basename(file));
  return file;
}

async function control(pathname = '') {
  const res = await fetch(CONTROL + pathname);
  return res.json();
}

/** Forget both the request record and any edits a previous flow made. */
async function resetAll() {
  await fetch(`${CONTROL}reset-data`);
}

const text = (page) => page.evaluate(() => document.body.innerText);

/** Click the first visible, enabled element whose text matches. */
async function clickText(page, pattern, { tag = 'button', exact = false } = {}) {
  const done = await page.evaluate(
    (pat, t, ex) => {
      const re = new RegExp(pat, 'i');
      const els = [...document.querySelectorAll(t)];
      const hit = els.find((e) => {
        if (e.disabled) return false;
        if (e.offsetParent === null) return false;
        const s = e.textContent.replace(/\s+/g, ' ').trim();
        return ex ? s.toLowerCase() === pat.toLowerCase() : re.test(s);
      });
      if (!hit) return false;
      hit.click();
      return true;
    },
    pattern,
    tag,
    exact,
  );
  if (done) await sleep(900);
  return done;
}

async function openTab(page, label) {
  const ok = await page.evaluate((t) => {
    const hit = [...document.querySelectorAll('div,button,a,span')].find(
      (e) => e.textContent.trim() === t && e.getBoundingClientRect().width > 0,
    );
    if (!hit) return false;
    (hit.closest('[role="button"],button,a,div') || hit).click();
    return true;
  }, label);
  if (ok) await sleep(1100);
  return ok;
}

async function setField(page, selector, value, index = 0) {
  return page.evaluate(
    (sel, val, idx) => {
      const el = document.querySelectorAll(sel)[idx];
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
    index,
  );
}

async function login(page, key) {
  await page.goto(`${BASE}/login`, { waitUntil: 'networkidle2' });
  await page.waitForSelector('input', { timeout: 20000 });
  const inputs = await page.$$('input');
  await inputs[0].click({ clickCount: 3 });
  await inputs[0].type(`${key}@${DOMAIN}`);
  await inputs[1].click({ clickCount: 3 });
  await inputs[1].type(PASSWORD);
  await Promise.all([
    page.waitForNavigation({ waitUntil: 'networkidle2', timeout: 30000 }).catch(() => {}),
    page.evaluate(() => document.querySelector('form')?.requestSubmit()),
  ]);
  await sleep(3000);
  return page.url();
}

/** The writes a flow caused, since a marker taken before it. */
async function writesSince(mark, table = null) {
  const { writes } = await control();
  return writes.slice(mark).filter((w) => !table || w.table === table);
}
async function writeMark() {
  return (await control()).writes.length;
}

// ===========================================================================

(async () => {
  const { browser, newPage, tiles, problems, state } = await launch({ viewport: VIEWPORT });
  const page = await newPage();

  await resetAll();

  // -----------------------------------------------------------------------
  // The map, with a base layer that actually renders.
  // -----------------------------------------------------------------------
  state.screen = 'hq:map';
  await login(page, 'hq');
  await sleep(4000);
  await shot(page, '50-map-with-base-layer');

  check('the map requests base tiles at all', tiles.length > 0, `${tiles.length} tiles`);
  if (tiles.length) {
    const corners = tiles.map((t) => tileToLatLon(t.z, t.x, t.y));
    // Plateau State is roughly 8.4–10.6 N, 8.3–10.4 E. Allow a tile's slack.
    const over = corners.filter(
      (c) => c.lat > 7.5 && c.lat < 11.5 && c.lon > 7.5 && c.lon < 11.5,
    );
    check(
      'the tiles it asks for are over Plateau State, not somewhere else',
      over.length > 0 && over.length / corners.length > 0.5,
      `${over.length}/${corners.length} tiles inside the state's bounding box; ` +
        `first at ${corners[0].lat.toFixed(2)}N ${corners[0].lon.toFixed(2)}E`,
    );
    check(
      'tiles are requested at a usable zoom, not the whole world',
      tiles.every((t) => t.z >= 7),
      `zooms: ${[...new Set(tiles.map((t) => t.z))].sort((a, b) => a - b).join(',')}`,
    );
  }

  const markerCount = await page.evaluate(
    () => document.querySelectorAll('.leaflet-marker-icon').length,
  );
  check(
    'markers are drawn on the map',
    markerCount > 0,
    `${markerCount} marker elements (4 locatable incidents, clustered)`,
  );

  // Theme switch must repoint the base layer, not just recolour the chrome.
  state.screen = 'hq:theme';
  const lightTiles = tiles.length;
  const themed = await page.evaluate(() => {
    const btn = [...document.querySelectorAll('button')].find(
      (b) => b.querySelector('svg') && /theme|dark|light/i.test(b.getAttribute('aria-label') || b.title || ''),
    );
    if (btn) { btn.click(); return 'labelled'; }
    // Fall back to the moon/sun control in the header.
    const header = [...document.querySelectorAll('button')].filter(
      (b) => b.offsetParent !== null && b.textContent.trim() === '' && b.querySelector('svg'),
    );
    if (header.length) { header[0].click(); return 'unlabelled'; }
    return null;
  });
  if (themed) {
    await sleep(2500);
    // This used to assert that the toggle REPOINTED the base layer at a dark
    // provider, and it passed for as long as that provider was CARTO — which
    // now answers unauthenticated callers with a placeholder tile reading
    // "API key required". The fix was to stop swapping providers: one tile
    // source, darkened locally with a CSS filter on the tile pane, so the map
    // cannot stop working because of somebody else's pricing change.
    //
    // So the assertion is inverted. A dark theme must (a) filter the tiles and
    // (b) NOT refetch every visible tile from a second provider.
    const paneFilter = await page.evaluate(() => {
      const pane = document.querySelector('.leaflet-tile-pane');
      return pane ? getComputedStyle(pane).filter : '';
    });
    check(
      'the dark theme darkens the tiles it already has',
      /invert/i.test(paneFilter),
      paneFilter || '(no filter on the tile pane)',
    );
    const refetched = tiles.slice(lightTiles).length;
    check(
      'the dark theme does not refetch the basemap from a second provider',
      !tiles.slice(lightTiles).some((t) => t.dark),
      `${refetched} tile request(s) after the toggle, none from a dark provider`,
    );
    await shot(page, '51-map-dark-theme');
    await page.evaluate(() => {
      const b = [...document.querySelectorAll('button')].filter(
        (x) => x.offsetParent !== null && x.textContent.trim() === '' && x.querySelector('svg'),
      );
      b[0]?.click();
    });
    await sleep(1500);
  } else {
    check('a theme control is reachable in the header', false, 'not found');
  }

  // -----------------------------------------------------------------------
  // Incident actions: dispatch, escalate, resolve.
  // -----------------------------------------------------------------------
  for (const [label, expect, file] of [
    ['DISPATCH', { status: 'DISPATCHED' }, '52-action-dispatch'],
    ['RESOLVE', { status: 'RESOLVED' }, '53-action-resolve'],
  ]) {
    state.screen = `hq:${label.toLowerCase()}`;
    await resetAll();
    await page.reload({ waitUntil: 'networkidle2' });
    await sleep(3000);
    await openTab(page, 'Incident Feed');
    const mark = await writeMark();
    const clicked = await clickText(page, label, { exact: true });
    if (!clicked) {
      check(`${label} is offered on an incident card`, false, 'button not found');
      continue;
    }
    await sleep(2000);
    // DISPATCH opens a responder picker. The confirm button stays disabled
    // until somebody is selected — dispatching to nobody is refused, which is
    // right, and is why a naive click-and-assert reported this as broken.
    if (label === 'DISPATCH') {
      await page.evaluate(() => {
        const rows = [...document.querySelectorAll('div')].filter(
          (d) => /LIVE GPS|READY/.test(d.textContent) && d.children.length < 6,
        );
        (rows[rows.length - 1] || rows[0])?.click();
      });
      await sleep(800);
      await shot(page, '52a-dispatch-responder-picker');
    }
    await clickText(page, 'confirm|dispatch|assign|deploy team');
    await sleep(2200);
    const w = await writesSince(mark, 'alerts');
    const got = w.find((x) => x.method === 'PATCH');
    check(
      `${label} writes ${JSON.stringify(expect)} to alerts`,
      !!got && Object.entries(expect).every(([k, v]) => got.rows[0]?.[k] === v),
      got ? `PATCH ${JSON.stringify(got.rows[0]).slice(0, 160)}` : 'no PATCH reached the database',
    );
    await shot(page, file);
  }

  // Escalation opens a modal and needs a target agency.
  state.screen = 'hq:escalate';
  await resetAll();
  await page.reload({ waitUntil: 'networkidle2' });
  await sleep(3000);
  await openTab(page, 'Incident Feed');
  const escMark = await writeMark();
  if (await clickText(page, 'ESCALATE', { exact: true })) {
    await sleep(1800);
    await shot(page, '54-action-escalate-modal');
    // Pick an agency if the modal offers one, then confirm.
    await page.evaluate(() => {
      const sel = [...document.querySelectorAll('select')].find((s) =>
        [...s.options].some((o) => /police|army|nscdc|agency/i.test(o.textContent)),
      );
      if (sel) {
        const opt = [...sel.options].find((o) => /army/i.test(o.textContent))
          || [...sel.options].find((o) => /police/i.test(o.textContent));
        if (opt) {
          Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype, 'value')
            .set.call(sel, opt.value);
          sel.dispatchEvent(new Event('change', { bubbles: true }));
        }
      }
    });
    await sleep(600);
    await clickText(page, 'escalate|confirm|transfer|hand ?over');
    await sleep(2500);
    const w = await writesSince(escMark, 'alerts');
    const got = w.find((x) => x.method === 'PATCH');
    check(
      'ESCALATE writes an escalation to alerts',
      !!got && (got.rows[0]?.escalated_to_agency || got.rows[0]?.assigned_tier || got.rows[0]?.status),
      got ? JSON.stringify(got.rows[0]).slice(0, 200) : 'no PATCH reached the database',
    );

    // AND THAT IT WROTE A CODE AN AGENCY ANSWERS TO.
    //
    // The check above passed for a year on `escalated_to_agency: 'NPF'`, because
    // it only asked whether SOMETHING was written. 'NPF' is not a code anything
    // in this system knows: the Police liaison's portal loads its whole desk
    // with `.eq('escalated_to_agency', 'POLICE')`, so the incident never
    // appeared on it, and /api/notify-agency answered 400 Unknown agency, so no
    // SMS and no webhook were sent. The console said "Escalation Sent".
    const stored = got?.rows[0]?.escalated_to_agency;
    check(
      'the escalation names an agency the portal and the notifier both know',
      AGENCY_CODES.includes(stored),
      stored
        ? `escalated_to_agency = ${JSON.stringify(stored)}`
          + (AGENCY_CODES.includes(stored)
            ? ''
            : ` — not one of ${AGENCY_CODES.join(', ')}, so no liaison portal`
              + ' can find it and /api/notify-agency refuses it')
        : 'nothing was written to escalated_to_agency',
    );

    // AND THAT THE OPERATOR IS TOLD WHEN THE AGENCY WAS NOT REACHED.
    //
    // This run configures no liaison phone and no webhook URL — which is also
    // true of the deployment — so the honest answer is that the agency was not
    // notified. The toast used to read "Escalation Sent" either way.
    const toast = await text(page);
    check(
      'the console says the agency was NOT notified, rather than claiming it was',
      /NOT NOTIFIED/i.test(toast) && !/Escalation Sent/i.test(toast),
      /NOT NOTIFIED/i.test(toast)
        ? 'the handover is recorded and the operator is told nobody was reached'
        : `no "not notified" warning on screen: ${toast.replace(/\s+/g, ' ').slice(0, 200)}`,
    );
    await shot(page, '55-action-escalate-after');
  } else {
    check('ESCALATE is offered on an incident card', false, 'button not found');
  }

  // -----------------------------------------------------------------------
  // Administration: config, directory, uninstall queue.
  // -----------------------------------------------------------------------
  state.screen = 'hq:config';
  await resetAll();
  await page.reload({ waitUntil: 'networkidle2' });
  await sleep(3000);
  await openTab(page, 'System Logic');
  await sleep(1500);
  const cfgMark = await writeMark();
  await page.evaluate(() => {
    const el = document.querySelector('input[type="checkbox"]');
    if (el) el.click();
  });
  await setField(page, 'input[type="text"]', 'true');
  await clickText(page, 'save|apply|update|commit');
  await sleep(2500);
  const cfgWrites = await writesSince(cfgMark, 'app_config');
  check(
    'System Logic persists a configuration change to app_config',
    cfgWrites.length > 0,
    cfgWrites.length ? JSON.stringify(cfgWrites[0].rows[0]).slice(0, 160) : 'nothing written',
  );
  await shot(page, '56-admin-system-config');

  // Agent Directory provisions staff accounts. There is no control for editing
  // an existing user's role, and there should not be one in the browser: the
  // role is the privilege, and the browser is the least trustworthy place to
  // decide it. What must be true is that provisioning goes through the server
  // route, and that the account comes out with the role that was asked for —
  // set by the service key, after the server checked who was asking.
  state.screen = 'hq:directory';
  await openTab(page, 'Agent Directory');
  await sleep(1800);
  const dirMark = await writeMark();
  const newEmail = `provisioned.${Date.now()}@staging.operationrainbow.test`;
  const filled = await page.evaluate((email) => {
    const set = (el, v) => {
      if (!el) return false;
      Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(el, v);
      el.dispatchEvent(new Event('input', { bubbles: true }));
      return true;
    };
    const name = document.querySelector('input[placeholder="Officer Name"]');
    const mail = document.querySelector('input[placeholder*="operationrainbow" i]');
    const pass = document.querySelector('input[type="password"], input[placeholder="••••••••"]');
    return set(name, 'Sgt. Provisioned Officer') && set(mail, email)
      && set(pass, 'a-long-enough-temp-password');
  }, newEmail);

  let provisionStatus = 'form not filled';
  if (filled) {
    const responses = [];
    const onResp = (r) => {
      if (r.url().includes('/api/admin/provision')) responses.push(r.status());
    };
    page.on('response', onResp);
    await clickText(page, 'provision|register|create');
    await sleep(3000);
    page.off('response', onResp);
    provisionStatus = responses.length ? `HTTP ${responses.join(',')}` : 'no request to the route';

    const { rows } = await (await fetch(
      `http://127.0.0.1:54321/rest/v1/profiles?select=email,role&email=eq.${newEmail}`,
    ).then((r) => r.json()).then((rows) => ({ rows })));
    const made = rows?.[0];
    check(
      'provisioning goes through /api/admin/provision and sets the role server-side',
      responses.includes(201) && made && made.role && made.role !== 'CITIZEN',
      made ? `${provisionStatus}; profile role = ${made.role}` : `${provisionStatus}; no profile created`,
    );
  } else {
    check('the Agent Directory provisioning form can be filled', false, 'fields not found');
  }
  // The role must be written by the SERVER, holding the service key, and never
  // by the browser. Both writes land in the same table, so the check is on who
  // made them — the fake records which key each write arrived with.
  const dirWrites = await writesSince(dirMark, 'profiles');
  const roleWrites = dirWrites.filter((w) => w.rows?.some((r) => r.role));
  check(
    'profiles.role is only ever written with the service key, never from the browser',
    roleWrites.length > 0 && roleWrites.every((w) => w.viaServiceKey),
    roleWrites.length
      ? roleWrites.map((w) => `${w.method} via ${w.viaServiceKey ? 'service key' : 'BROWSER'}`).join('; ')
      : 'no role write seen at all',
  );
  await shot(page, '57-admin-agent-directory');

  state.screen = 'hq:uninstall';
  await openTab(page, 'Uninstall Requests');
  await sleep(1800);
  const unMark = await writeMark();
  const approved = await clickText(page, 'approve');
  await sleep(2500);
  const unWrites = await writesSince(unMark, 'uninstall_requests');
  check(
    'APPROVE on an uninstall request writes its new status',
    approved && unWrites.length > 0,
    unWrites.length ? JSON.stringify(unWrites[0].rows[0]).slice(0, 160)
      : (approved ? 'clicked, nothing written' : 'no APPROVE button'),
  );
  await shot(page, '58-admin-uninstall-approved');

  // -----------------------------------------------------------------------
  // The agency portal, as the ARMY liaison.
  // -----------------------------------------------------------------------
  state.screen = 'army:portal';
  await resetAll();
  await login(page, 'army');
  await sleep(3500);
  // The liaison's nav calls this their own desk now. HQ still sees the
  // state's inter-agency board under the old label, and this harness drives
  // both, so try each.
  (await openTab(page, 'Inter-Agency Command')) ||
    (await openTab(page, 'Our Deployments'));
  await sleep(2000);

  // Add an officer.
  const addMark = await writeMark();
  if (await clickText(page, 'add officer|add personnel')) {
    await sleep(1400);
    // name / rank / badge / phone, in the order the form declares them.
    await setField(page, 'input', 'Lt. Test Officer', 0);
    await setField(page, 'input', 'LT', 1);
    await setField(page, 'input', 'NA/PL/999', 2);
    await setField(page, 'input', '08000009999', 3);
    await shot(page, '60-agency-add-officer-form');
    await page.evaluate(() => {
      document.querySelector('button[type="submit"]')?.click();
    });
    await sleep(2500);
    const w = await writesSince(addMark, 'agency_personnel');
    check(
      'adding an officer inserts into agency_personnel',
      w.some((x) => x.method === 'POST'),
      w.length ? JSON.stringify(w[0].rows[0]).slice(0, 160) : 'nothing inserted',
    );
    await shot(page, '61-agency-personnel-after-add');
  } else {
    check('the agency portal offers Add Officer', false, 'control not found');
  }

  // Personnel status change.
  state.screen = 'army:personnel';
  // The liaison's nav calls this their own desk now. HQ still sees the
  // state's inter-agency board under the old label, and this harness drives
  // both, so try each.
  (await openTab(page, 'Inter-Agency Command')) ||
    (await openTab(page, 'Our Deployments'));
  await sleep(800);
  await clickText(page, 'Personnel', { exact: true });
  await sleep(1500);
  const stMark = await writeMark();
  const statusClicked = await clickText(page, 'AVAILABLE|DEPLOYED|STAND ?DOWN|RESTING');
  await sleep(2000);
  const stWrites = await writesSince(stMark, 'agency_personnel');
  check(
    'a personnel status button writes to agency_personnel',
    statusClicked && stWrites.length > 0,
    stWrites.length ? JSON.stringify(stWrites[0].rows[0]).slice(0, 140)
      : (statusClicked ? 'clicked, nothing written' : 'no status control'),
  );
  await shot(page, '62-agency-personnel-status');

  // Deploy against the escalated incident.
  state.screen = 'army:deploy';
  // The portal's own section tab, found BY ROLE rather than by text.
  //
  // This was `clickText(page, 'situation feed|incidents')`, and the `incidents`
  // alternation started matching the liaison's NAV entry — "Incidents For Us" —
  // which navigated out of the portal altogether. Every following step then ran
  // against the dashboard's incident feed: the card was found, the dossier
  // opened, and "deploy" matched nothing, so the deployment check failed while
  // the screenshot showed an incident dossier. A matcher loose enough to leave
  // the screen is a matcher that can report the wrong thing.
  await page.evaluate(() => {
    const tab = [...document.querySelectorAll('[role="tab"]')].find(
      (t) => /situation feed/i.test(t.textContent || ''),
    );
    tab?.click();
  });
  await sleep(1500);
  // DEPLOY and REPORT only appear once the incident card is expanded.
  const expanded = await page.evaluate(() => {
    const card = [...document.querySelectorAll('div')].reverse().find(
      (d) => /mangu road|roadblock/i.test(d.textContent) && d.querySelector('div'),
    );
    if (!card) return false;
    (card.querySelector('[style*="cursor"]') || card).click();
    return true;
  });
  await sleep(1400);
  await shot(page, '62b-agency-incident-expanded');
  if (!expanded) check('the escalated incident card can be expanded', false, 'card not found');
  const depMark = await writeMark();
  // "deploy" alone matches the sidebar's "Our Deployments" nav item, which
  // comes first in the DOM — so this pressed the nav, the modal never opened,
  // and the check reported the app inserting nothing when the app had never
  // been asked to. The button on the incident card is "DEPLOY PERSONNEL".
  if (await clickText(page, 'deploy personnel')) {
    await sleep(1500);
    await page.evaluate(() => {
      const box = document.querySelector('input[type="checkbox"]');
      if (box) { box.click(); box.dispatchEvent(new Event('change', { bubbles: true })); }
    });
    await sleep(500);
    await setField(page, 'textarea', 'Local end-to-end deployment note.');
    await shot(page, '63-agency-deploy-modal');
    // The modal's two buttons are CANCEL and the confirm; take the last.
    await page.evaluate(() => {
      const btns = [...document.querySelectorAll('button')].filter(
        (b) => b.offsetParent !== null && !/cancel/i.test(b.textContent),
      );
      btns[btns.length - 1]?.click();
    });
    await sleep(2500);
    const w = await writesSince(depMark, 'agency_deployments');
    check(
      'confirming a deployment inserts into agency_deployments',
      w.some((x) => x.method === 'POST'),
      w.length ? JSON.stringify(w[0].rows[0]).slice(0, 160) : 'nothing inserted',
    );
    await shot(page, '64-agency-after-deploy');
  } else {
    check('the agency portal offers DEPLOY on an escalated incident', false, 'control not found');
  }

  // File an action report. The card collapses when the deployment modal
  // closes, so it has to be opened again — the buttons live on the expanded
  // card and only for a liaison, never in HQ's read-only view of the portal.
  state.screen = 'army:report';
  await page.evaluate(() => {
    const card = [...document.querySelectorAll('div')].reverse().find(
      (d) => /mangu road|roadblock/i.test(d.textContent) && d.querySelector('div'),
    );
    (card?.querySelector('[style*="cursor"]') || card)?.click();
  });
  await sleep(1400);
  const repMark = await writeMark();
  // Must be the button on the expanded card, not the "Action Reports" TAB —
  // which is what a looser pattern matched, quietly navigating to the list and
  // then reporting that filing a report wrote nothing.
  if (await clickText(page, 'file report to hq')) {
    await sleep(1500);
    await setField(page, 'textarea', 'Local end-to-end action report narrative.');
    await shot(page, '65-agency-action-report-form');
    await page.evaluate(() => {
      document.querySelector('button[type="submit"]')?.click();
    });
    await sleep(2500);
    const w = await writesSince(repMark, 'agency_action_reports');
    check(
      'filing an action report inserts into agency_action_reports',
      w.some((x) => x.method === 'POST'),
      w.length ? JSON.stringify(w[0].rows[0]).slice(0, 160) : 'nothing inserted',
    );
    await shot(page, '66-agency-after-report');
  } else {
    check('the agency portal offers an action report', false, 'control not found');
  }

  // HQ acknowledging a report closes the loop between the two sides.
  state.screen = 'hq:acknowledge';
  await resetAll();
  await login(page, 'hq');
  await sleep(3500);
  // The liaison's nav calls this their own desk now. HQ still sees the
  // state's inter-agency board under the old label, and this harness drives
  // both, so try each.
  (await openTab(page, 'Inter-Agency Command')) ||
    (await openTab(page, 'Our Deployments'));
  await sleep(2000);
  // HQ sees every agency's portal and opens on one of them; the seeded report
  // is the ARMY's, so choose that before looking for it.
  await clickText(page, 'ARMY|NIGERIAN ARMY');
  await sleep(1500);
  await clickText(page, 'action reports|reports');
  await sleep(1500);
  const ackMark = await writeMark();
  const ackClicked = await clickText(page, 'acknowledge|mark read|ack');
  await sleep(2200);
  const ackWrites = await writesSince(ackMark, 'agency_action_reports');
  check(
    'HQ acknowledging an agency report writes it back',
    ackClicked && ackWrites.length > 0,
    ackWrites.length ? JSON.stringify(ackWrites[0].rows[0]).slice(0, 140)
      : (ackClicked ? 'clicked, nothing written' : 'no acknowledge control'),
  );
  await shot(page, '67-hq-acknowledge-report');

  // -----------------------------------------------------------------------
  // The dispatcher's reply.
  //
  // The console read `chat_messages` in two places and wrote nowhere, so the
  // citizen's screen — which is titled DISPATCHER CHAT — had no dispatcher on
  // the other end. The only person who could answer was a responder with that
  // exact incident open on a handset. A composer was added to the incident
  // dossier's timeline; this is the first time it has been opened in a browser.
  // -----------------------------------------------------------------------
  state.screen = 'hq:dossier-reply';
  await page.goto(`${BASE}/dashboard`, { waitUntil: 'networkidle2' });
  await sleep(3500);
  // The console opens on the Intelligence Map. The incident cards — and the
  // DOSSIER button on each — are in the Incident Feed.
  await clickText(page, 'Incident Feed');
  await sleep(2500);
  const dossierOpened = await clickText(page, '📄 DOSSIER|DOSSIER');
  await sleep(2500);
  check('an incident dossier opens', dossierOpened, dossierOpened ? '' : 'no dossier control');
  await shot(page, '68-hq-incident-dossier');

  const REPLY = 'HQ: ward team is staging at the junction, hold your position.';
  const composerFound = await setField(
    page, 'input[aria-label="Reply to this incident\'s channel"]', REPLY);
  check('the dossier offers a reply composer', composerFound,
    composerFound ? '' : 'no composer on the incident timeline');

  const chatMark = await writeMark();
  const sentReply = await clickText(page, 'SEND');
  await sleep(2600);
  const chatWrites = await writesSince(chatMark, 'chat_messages');
  check(
    'the dispatcher can reply, and it is written to the incident channel',
    sentReply && chatWrites.length > 0,
    chatWrites.length
      ? JSON.stringify(chatWrites[0].rows[0]).slice(0, 150)
      : (sentReply ? 'clicked, nothing written' : 'no send control'),
  );
  check(
    'the reply carries the operator, not an anonymous sender',
    chatWrites.length > 0 && !!chatWrites[0].rows[0].sender_id
      && chatWrites[0].rows[0].message === REPLY,
    chatWrites.length ? `${chatWrites[0].rows[0].sender_name} (${chatWrites[0].rows[0].sender_role})` : '',
  );
  await shot(page, '69-hq-dossier-reply-sent');

  // -----------------------------------------------------------------------
  // Mass broadcast.
  //
  // Every broadcast HQ ever sent failed: the screen wrote six columns no
  // migration defines, PostgREST rejected the insert in full, and the operator
  // saw a raw error where a statewide warning should have been. The columns
  // exist now — this asserts the send actually reaches `system_alerts`, which
  // no test has ever checked.
  // -----------------------------------------------------------------------
  state.screen = 'hq:mass-broadcast';
  await page.goto(`${BASE}/dashboard`, { waitUntil: 'networkidle2' });
  await sleep(3000);
  await clickText(page, 'Communications & Broadcast|Communications');
  await sleep(2500);
  await shot(page, '70-hq-mass-broadcast');

  const WARNING = 'Avoid the Bukuru expressway until further notice.';
  await setField(page, 'textarea', WARNING);
  await setField(page, 'input[type="text"]', 'ROAD CLOSURE');
  const bcMark = await writeMark();
  const bcSent = await clickText(page, 'transmit|send broadcast|broadcast now|send');
  await sleep(3000);
  const bcWrites = await writesSince(bcMark, 'system_alerts');
  check(
    'a mass broadcast reaches system_alerts',
    bcSent && bcWrites.length > 0,
    bcWrites.length
      ? JSON.stringify(bcWrites[0].rows[0]).slice(0, 150)
      : (bcSent ? 'clicked, nothing written' : 'no send control'),
  );
  await shot(page, '71-hq-mass-broadcast-sent');

  // -----------------------------------------------------------------------
  // Sign out.
  // -----------------------------------------------------------------------
  state.screen = 'hq:signout';
  await clickText(page, 'terminate uplink|sign out|log ?out');
  await sleep(3000);
  check('signing out returns to the login screen', page.url().includes('/login'), page.url());
  await shot(page, '68-after-sign-out');

  // -----------------------------------------------------------------------
  // SWEEP: click everything else and see whether anything happens.
  //
  // PER ROLE, not just as HQ. This swept the HQ console and nothing else, so a
  // control that only an LGA commander or an agency liaison ever sees was
  // never pressed by anybody — and the liaison desk is the newest surface in
  // the console and the one belonging to people from outside this
  // organisation. What each role may open now comes from
  // `src/lib/console-access.ts`, so the tab lists below mirror it.
  //
  // Links as well as buttons. A dead `<a>` is exactly as dead as a dead
  // `<button>`, and the sweep only ever looked at buttons.
  // -----------------------------------------------------------------------
  const HQ_TABS = [
    'Intelligence Map', 'Incident Feed', 'Mission History',
    'Communications & Broadcast', 'Inter-Agency Command',
    'Agent Directory', 'Forensic Audit', 'System Logic', 'Uninstall Requests',
    'Handset SMS Channel',
  ];
  const SWEEPS = [
    { role: 'hq', tabs: HQ_TABS },
    { role: 'lga', tabs: ['Intelligence Map', 'Incident Feed', 'Mission History',
                          'Communications & Broadcast', 'Inter-Agency Command'] },
    // The desk an officer of another organisation sits at.
    { role: 'police', tabs: ['Our Deployments', 'Incidents For Us'] },
  ];
  const ALL_TAB_LABELS = [
    ...HQ_TABS, 'Our Deployments', 'Incidents For Us',
  ].map((t) => t.toLowerCase());

  for (const { role, tabs } of SWEEPS) {
    await resetAll();
    await login(page, role);
    await sleep(3500);

    for (const tab of tabs) {
      state.screen = `sweep:${role}:${tab}`;
      if (!(await openTab(page, tab))) {
        check(`${role}: the "${tab}" screen is reachable`, false, 'nav entry not found');
        continue;
      }
      await sleep(1200);

      const count = await page.evaluate(() => {
        window.__sweep = [...document.querySelectorAll('button, a[href], [role="button"]')].filter(
          (b) => !b.disabled && b.offsetParent !== null,
        );
        return window.__sweep.length;
      });

      for (let i = 0; i < count; i++) {
        const label = await page.evaluate((idx) => {
          const b = window.__sweep?.[idx];
          if (!b || !b.isConnected || b.disabled || b.offsetParent === null) return null;
          return (b.textContent.replace(/\s+/g, ' ').trim()
            || b.getAttribute('aria-label') || b.title || '(icon)').slice(0, 48);
        }, i);
        if (!label) continue;
        // Leaving the screen mid-sweep would attribute the next tab's controls
        // to this one, and signing out would end the sweep entirely.
        if (/terminate uplink|sign out|log ?out/i.test(label)) continue;
        // Nav entries carry a count badge, so "Incident Feed" arrives as
        // "Incident Feed5". Clicking the tab you are already on legitimately
        // does nothing; counting that as a dead control is a false positive.
        const bare = label.replace(/\d+$/, '').trim().toLowerCase();
        if (ALL_TAB_LABELS.includes(bare)) continue;
        // An external link leaves the console entirely — OpenStreetMap's
        // attribution, for one — and the sweep cannot come back from it.
        const external = await page.evaluate((idx) => {
          const b = window.__sweep?.[idx];
          const href = b?.getAttribute?.('href') || '';
          return /^https?:/i.test(href) && !href.includes('127.0.0.1');
        }, i);
        if (external) {
          sweepLog.push({ tab: `${role}:${tab}`, label, effect: 'external link, not followed' });
          continue;
        }

        // A length comparison misses a change that swaps equal-length text —
        // for instance selecting a different agency in the portal. Hash it.
        const digest = () => {
          let h = 5381;
          const s = document.body.innerHTML;
          for (let i = 0; i < s.length; i++) h = ((h * 33) ^ s.charCodeAt(i)) >>> 0;
          return h;
        };
        const before = await page.evaluate((fn) => {
          // eslint-disable-next-line no-eval
          return { html: eval(`(${fn})`)(), url: location.href };
        }, digest.toString());
        const reqBefore = (await control()).log.length;

        const clicked = await page.evaluate((idx) => {
          const b = window.__sweep?.[idx];
          if (!b || !b.isConnected || b.disabled || b.offsetParent === null) return false;
          b.click();
          return true;
        }, i);
        if (!clicked) continue;
        await sleep(650);

        const after = await page.evaluate((fn) => {
          // eslint-disable-next-line no-eval
          return { html: eval(`(${fn})`)(), url: location.href };
        }, digest.toString());
        const reqAfter = (await control()).log.length;

        // A `required` field that blocks submission is the control working,
        // not failing: the browser shows its own validation bubble and the DOM
        // is untouched. Counting that as "did nothing" would report every
        // form's submit button as dead.
        const blockedByValidation = await page.evaluate((idx) => {
          const b = window.__sweep?.[idx];
          const form = b?.form || b?.closest?.('form');
          if (!form || b?.type !== 'submit') return false;
          return !form.checkValidity();
        }, i);

        // Clicking the tab you are already on is CORRECTLY a no-op. The app
        // says which tab is selected (`aria-selected`), so this can be told
        // apart from a button wired to nothing — which is the distinction that
        // matters, and why the fix went into the component rather than into a
        // suppression list here.
        const alreadySelected = await page.evaluate((idx) => {
          const b = window.__sweep?.[idx];
          return b?.getAttribute?.('aria-selected') === 'true';
        }, i);

        const effect = [];
        if (alreadySelected) effect.push('already the selected tab');
        if (blockedByValidation) effect.push('refused by field validation');
        if (after.url !== before.url) effect.push('navigated');
        if (after.html !== before.html) effect.push('changed the page');
        if (reqAfter > reqBefore) effect.push(`made ${reqAfter - reqBefore} request(s)`);

        sweepLog.push({ tab: `${role}:${tab}`, label, effect: effect.join(', ') || 'nothing' });
        if (!effect.length) deadControls.push({ tab: `${role}:${tab}`, label });

        // Close anything that opened, so the next click starts from the screen.
        await page.keyboard.press('Escape').catch(() => {});
        await sleep(200);
      }
      await shot(page, `70-sweep-${role}-${tab.toLowerCase().replace(/[^a-z]+/g, '-')}`);
    }
  }

  // An agency liaison must not be OFFERED what the database will refuse them.
  // `system_alerts` INSERT requires is_command(), so the broadcast composer was
  // a control that let an officer of another organisation write a statewide
  // advisory and only then be told no.
  state.screen = 'police:no-command-screens';
  const liaisonNav = await page.evaluate(() =>
    [...document.querySelectorAll('nav *')].map((e) => e.textContent.trim()).join(' | '),
  );
  for (const forbidden of ['Intelligence Map', 'Mission History',
                           'Communications & Broadcast', 'Agent Directory',
                           'Forensic Audit', 'Uninstall Requests']) {
    check(
      `a liaison is not offered "${forbidden}"`,
      !liaisonNav.includes(forbidden),
      liaisonNav.includes(forbidden) ? 'still in the navigation' : '',
    );
  }

  check(
    'every control that was clicked did something',
    deadControls.length === 0,
    deadControls.length
      ? `${deadControls.length} did nothing: ` +
        deadControls.slice(0, 8).map((d) => `${d.tab}/"${d.label}"`).join(', ')
      : `${sweepLog.length} controls exercised`,
  );

  const fatal = problems.filter(
    (p) => p.kind === 'pageerror'
      || /is not a function|undefined is not|cannot read|hydration failed|minified react error|chunkloaderror/i.test(p.text),
  );
  check(
    'no control threw and no React crash was logged',
    fatal.length === 0,
    fatal.length ? `${fatal.length}: ${fatal.slice(0, 3).map((f) => `${f.screen}: ${f.text}`).join(' | ')}` : 'clean',
  );

  const ctl = await control();
  check(
    'nothing any control did named a column the migrations do not define',
    ctl.unknownColumns.length === 0,
    ctl.unknownColumns.join('; ') || 'none',
  );

  // AND NOTHING ANY CONTROL DID WAS REFUSED FOR WANT OF A FUNCTION.
  //
  // The sibling claim, missing for the same reason. This pass presses the
  // dossier's controls, two of which are `confirm_ussd_report()` and
  // `mark_false_report()`, and the stand-in had no RPC router at all — so both
  // came back 400 while the sweep recorded the button as having done something
  // (it issued a request) and moved on.
  const rpcRefused = [...new Set(ctl.rpcMisses || [])];
  check(
    'every database function a control called was answered, not refused',
    rpcRefused.length === 0,
    rpcRefused.length
      ? `refused: ${rpcRefused.join(', ')}`
        + ' — implement it in RPCS in scripts/local_e2e/fake_supabase.js'
      : `none refused; ${new Set((ctl.rpcCalls || []).map((c) => c.fn)).size}`
        + ' function(s) answered',
  );

  fs.writeFileSync(
    path.join(OUT, 'interactions.json'),
    JSON.stringify(
      {
        ranAt: new Date().toISOString(),
        proves: 'controls act and write; NOT that row-level security is enforced',
        checks,
        screenshots: shots,
        tilesRequested: tiles.length,
        controlsExercised: sweepLog.length,
        deadControls,
        sweep: sweepLog,
        rpcMisses: rpcRefused,
        rpcCalls: ctl.rpcCalls || [],
        browserProblems: problems,
      },
      null,
      2,
    ),
  );

  await browser.close();

  const failed = checks.filter((c) => !c.pass);
  console.log(
    `\n${checks.length - failed.length}/${checks.length} checks passed, ` +
      `${sweepLog.length} controls exercised, ${shots.length} screenshots in ${OUT}`,
  );
  if (failed.length) {
    console.log('\nFAILED:');
    for (const f of failed) console.log(`  - ${f.name}${f.detail ? `  (${f.detail})` : ''}`);
  }
  process.exit(failed.length ? 1 : 0);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
