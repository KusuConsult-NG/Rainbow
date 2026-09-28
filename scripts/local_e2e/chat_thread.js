/**
 * A message, sent by one person and read by another.
 *
 * Messaging was the last thing in this system I had changed by reading rather
 * than by watching. Four things were wrong with it and all four were found in
 * the source: the console could not reply at all, any account could write into
 * any incident's channel, a failed send cleared the box and vanished, and the
 * chat routes redirect away without an alert so the screens had never actually
 * been rendered in a run. The database half is proven against real PostgreSQL
 * in `scripts/privacy_behaviour_test.sql`. This is the other half: two people,
 * one incident, a message going each way, photographed and read back.
 *
 * What makes it a real test rather than a screenshot of a text box is the
 * CROSS-PARTY assertion. Writing a row proves an insert. Signing in as somebody
 * else and finding that row on their screen proves the thing the feature is
 * for, and it is the half that a send-only test would call working while the
 * other end saw nothing.
 *
 *   node scripts/local_e2e/chat_thread.js
 */

const fs = require('fs');
const http = require('http');
const path = require('path');
const { launch } = require('./browser');
const { DOMAIN, PEOPLE } = require('./fixtures');

const ROOT = path.join(__dirname, '..', '..');
const WEB = path.join(ROOT, 'build', 'web');
const PORT = Number(process.env.CHAT_PORT || 8088);
const REST = 'http://127.0.0.1:54321/rest/v1';
const OUT = process.env.E2E_OUT || path.join(ROOT, 'local_e2e_screenshots');
const PHONE = { width: 390, height: 844, deviceScaleFactor: 2, isMobile: true, hasTouch: true };
const HERE = { latitude: 9.8965, longitude: 8.8583 };

fs.mkdirSync(OUT, { recursive: true });
for (const f of fs.readdirSync(OUT)) {
  if (/^C\d{2}-.*\.png$/.test(f)) fs.unlinkSync(path.join(OUT, f));
}

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

const UNIT_SAYS = 'Unit on scene, two vehicles blocking the north approach.';
const HQ_SAYS = 'Acknowledged. Holding the ward team until you confirm.';

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
    const f = `C${String(step).padStart(2, '0')}-${name}.png`;
    await page.screenshot({ path: path.join(OUT, f) });
    shots.push(f);
    console.log(`      shot  ${f}`);
  };

  const screenText = () => page.evaluate(() => {
    const h = document.querySelector('flt-semantics-host') || document.body;
    return ([...h.querySelectorAll('[aria-label]')]
      .map((e) => e.getAttribute('aria-label')).join('\n') + '\n' + h.textContent).trim();
  });

  async function signIn(role) {
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

  /**
   * Open Secure Chat from the incident's own card.
   *
   * By structure, not by position: the chat icon is one of three identical
   * 40x40 icon buttons on every card, so "the third small button" picks
   * whichever card happens to be on top. The semantics tree nests the way the
   * widgets do, so the card is an ancestor of both its incident text and its
   * chat button — a relationship that does not depend on scrolling.
   */
  async function openChatOn(pattern) {
    await page.mouse.move(195, 620);
    for (let s = 0; s < 14; s++) {
      const r = await page.evaluate((pat) => {
        const re = new RegExp(pat, 'i');
        const lbl = (n) => `${n.textContent || ''} ${n.getAttribute('aria-label') || ''}`;
        const inSameCard = (btn) => {
          let p = btn.parentElement;
          for (let d = 0; d < 10 && p; d += 1, p = p.parentElement) {
            if (p.tagName && p.tagName.toLowerCase() === 'flt-semantics'
                && [...p.querySelectorAll('flt-semantics')].some((n) => re.test(lbl(n)))) return true;
          }
          return false;
        };
        const buttons = [...document.querySelectorAll('flt-semantics[role="button"]')]
          .filter((b) => /Secure Chat/i.test(lbl(b)));
        if (!buttons.length) return 'no-button';
        const target = buttons.find(inSameCard);
        if (!target) return 'not-this-card';
        target.click();
        return 'clicked';
      }, pattern);
      if (r === 'clicked') { await sleep(3200); return true; }
      await page.mouse.wheel({ deltaY: 380 });
      await sleep(500);
    }
    return false;
  }

  /** Focus the composer and type into it. */
  async function compose(text) {
    const focused = await page.evaluate(() => {
      const boxes = [...document.querySelectorAll('flt-semantics')].filter((n) => {
        const r = n.getBoundingClientRect();
        return (n.getAttribute('role') === 'textbox' || n.querySelector('input, textarea'))
          && r.width > 40 && r.height > 12;
      });
      if (!boxes.length) return false;
      boxes[boxes.length - 1].click();
      return true;
    });
    if (!focused) return false;
    await sleep(700);
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
    await page.keyboard.type(text, { delay: 18 });
    state.typing = false;
    await sleep(500);
    return true;
  }

  const sendIt = () => page.evaluate(() => {
    for (const n of document.querySelectorAll('flt-semantics[role="button"]')) {
      const t = `${n.textContent || ''} ${n.getAttribute('aria-label') || ''}`;
      if (/^\s*Send\s*$/i.test(t.trim())) { n.click(); return true; }
    }
    return false;
  });

  // ── An incident for the two of them to talk about ─────────────────────────
  const citizen = PEOPLE.find((p) => p.key === 'citizen');
  const unit = PEOPLE.find((p) => p.key === 'unit');
  const hq = PEOPLE.find((p) => p.key === 'hq');

  const seeded = await (await fetch(`${REST}/alerts`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', prefer: 'return=representation' },
    body: JSON.stringify({
      type: 'Community attack - Armed Invasion',
      description: 'Chat thread subject.',
      severity: 'CRITICAL',
      reported_by: citizen.id,
      assigned_to: unit.id,
      assigned_tier: 'UNIT',
      status: 'DISPATCHED',
      geo_lga: 'JOS NORTH',
      geo_ward: 'NARAGUTA',
      latitude: HERE.latitude,
      longitude: HERE.longitude,
    }),
  })).json();
  const alertId = Array.isArray(seeded) ? seeded[0].id : seeded.id;
  const needle = 'Community attack';
  console.log(`\n  incident: ${alertId}\n`);

  // =========================================================================
  // 1. THE UNIT OFFICER SENDS
  // =========================================================================
  state.screen = 'chat:unit:send';
  const unitAt = await signIn('unit');
  check('the unit officer signs in', /agent-dashboard/.test(unitAt), `on ${unitAt}`);
  await waitForFeed();

  const opened = await openChatOn(needle);
  check('Secure Chat opens from the incident card', opened);
  const chatScreen = await screenText();
  check(
    'it is the tactical comms channel for THIS incident',
    /TACTICAL COMMS CHANNEL/i.test(chatScreen)
      && chatScreen.includes(alertId.slice(0, 8).toUpperCase()),
    (chatScreen.split('\n').find((l) => /INCIDENT REF/i.test(l)) || '').trim(),
  );
  await shot('unit-chat-empty');

  const typed = await compose(UNIT_SAYS);
  check('the composer accepts a message', typed);
  await shot('unit-chat-typed');

  const before = (await rest(`chat_messages?select=id&alert_id=eq.${alertId}`)).length;
  await sendIt();
  await sleep(3000);
  await shot('unit-chat-sent');

  const afterUnit = await rest(
    `chat_messages?select=id,alert_id,sender_id,sender_name,sender_role,message&alert_id=eq.${alertId}`);
  check(
    'the message reaches the database',
    afterUnit.length === before + 1,
    `${afterUnit.length} message(s) on this incident`,
  );
  const first = afterUnit[afterUnit.length - 1];
  check(
    'it is filed against the right incident, signed by the right officer',
    first && first.alert_id === alertId && first.sender_id === unit.id,
    first ? `${first.sender_name} (${first.sender_role})` : 'no row',
  );
  check(
    'the text is what was typed, not a truncation of it',
    first && first.message === UNIT_SAYS,
    first ? `"${(first.message || '').slice(0, 44)}…"` : '',
  );
  check(
    'the sent message appears in the officer\'s own thread',
    (await screenText()).includes(UNIT_SAYS.slice(0, 30)),
  );

  // =========================================================================
  // 2. HQ READS IT, AND REPLIES
  // =========================================================================
  // This is the assertion the whole feature rests on. An insert proves a write;
  // only somebody else finding it on their screen proves a conversation.
  state.screen = 'chat:hq:read';
  const hqAt = await signIn('hq');
  check('HQ signs in', /agent-dashboard/.test(hqAt), `on ${hqAt}`);
  await waitForFeed();
  const hqOpened = await openChatOn(needle);
  check('HQ opens the same incident\'s channel', hqOpened);

  const hqSees = await screenText();
  check(
    'HQ SEES the message the unit officer sent',
    hqSees.includes(UNIT_SAYS.slice(0, 30)),
    hqSees.includes(UNIT_SAYS.slice(0, 30)) ? 'delivered' : 'the other end saw nothing',
  );
  check(
    'and it is attributed to the officer, not to HQ',
    new RegExp(unit.full_name.split(' ').pop(), 'i').test(hqSees) && !/^YOU$/m.test(hqSees.split('\n')[0]),
    unit.full_name,
  );
  await shot('hq-chat-sees-unit-message');

  const hqTyped = await compose(HQ_SAYS);
  check('HQ can reply', hqTyped);
  await sendIt();
  await sleep(3000);
  await shot('hq-chat-replied');

  const both = await rest(
    `chat_messages?select=sender_id,sender_role,message&alert_id=eq.${alertId}&order=created_at.asc`);
  check(
    'the thread now holds both messages',
    both.length === 2,
    `${both.length} message(s)`,
  );
  check(
    'each is signed by whoever actually sent it',
    both.length === 2 && both[0].sender_id === unit.id && both[1].sender_id === hq.id,
    both.length === 2 ? `${both[0].sender_role} then ${both[1].sender_role}` : '',
  );

  // =========================================================================
  // 3. AND THE OFFICER SEES THE REPLY
  // =========================================================================
  state.screen = 'chat:unit:read';
  await signIn('unit');
  await waitForFeed();
  await openChatOn(needle);
  const unitSeesReply = await screenText();
  check(
    'the unit officer sees HQ\'s reply',
    unitSeesReply.includes(HQ_SAYS.slice(0, 30)),
    unitSeesReply.includes(HQ_SAYS.slice(0, 30)) ? 'round trip complete' : 'the reply never arrived',
  );
  check(
    'and their own message is still there, marked as theirs',
    unitSeesReply.includes(UNIT_SAYS.slice(0, 30)) && /YOU/i.test(unitSeesReply),
  );
  await shot('unit-chat-round-trip');

  fs.writeFileSync(path.join(OUT, 'chat-thread.json'), JSON.stringify({
    ranAt: new Date().toISOString(),
    proves: 'a message sent by one party is read by another, on the same incident',
    incident: alertId,
    thread: both,
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
