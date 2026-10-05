/**
 * The two things a citizen can do that nothing had ever tested.
 *
 * 1. THE LIVE STREAM. A button on the Emergency Active screen turns on the
 *    phone's camera and microphone and offers them to HQ over WebRTC. It had
 *    never been pressed by any test, because a headless browser has no capture
 *    device and `getUserMedia` rejects — so the single most consequential
 *    control in the app, the one that opens a live camera and mic, was verified
 *    by reading alone. Chromium can synthesise both, so it can be pressed.
 *
 *    The assertion is not "the button lit up". WebRTC negotiation goes over a
 *    Supabase BROADCAST channel and touches no table, so nothing in a database
 *    write log could ever distinguish a stream that started from one that
 *    silently failed. The stand-in records channel traffic; this asserts the
 *    OFFER left the device, with an SDP in it.
 *
 * 2. THE SETTINGS CONTROLS. Editing a name, adding and removing an emergency
 *    contact, and — the one that matters — setting the safe and duress PINs.
 *    The duress PIN is the mechanism by which somebody under coercion can
 *    appear to cancel an emergency while help keeps coming. It had never been
 *    set through the UI by a test.
 *
 *   node scripts/local_e2e/user_features.js
 */

const fs = require('fs');
const http = require('http');
const path = require('path');
const { launch } = require('./browser');
const { PEOPLE, byKey } = require('./fixtures');

const ROOT = path.join(__dirname, '..', '..');
const WEB = path.join(ROOT, 'build', 'web');
const PORT = Number(process.env.FEATURES_PORT || 8089);
const REST = 'http://127.0.0.1:54321/rest/v1';
const CONTROL = 'http://127.0.0.1:54322/';
const OUT = process.env.E2E_OUT || path.join(ROOT, 'local_e2e_screenshots');
const PHONE = { width: 390, height: 844, deviceScaleFactor: 2, isMobile: true, hasTouch: true };
const HERE = { latitude: 9.8965, longitude: 8.8583 };

fs.mkdirSync(OUT, { recursive: true });
for (const f of fs.readdirSync(OUT)) {
  if (/^F\d{2}-.*\.png$/.test(f)) fs.unlinkSync(path.join(OUT, f));
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

const control = async () => (await fetch(CONTROL)).json();
const rest = async (q) => (await fetch(`${REST}/${q}`)).json();

(async () => {
  if (!await fetch('http://127.0.0.1:54321/auth/v1/health').then((r) => r.ok).catch(() => false)) {
    console.error('start the stand-in first: node scripts/local_e2e/fake_supabase.js');
    process.exit(1);
  }
  await fetch(`${CONTROL}reset-data`);
  await new Promise((r) => server.listen(PORT, '127.0.0.1', r));
  const origin = `http://127.0.0.1:${PORT}`;

  const tiles = [];
  const problems = [];
  const state = { screen: 'startup' };
  // fakeMedia is the whole reason this pass is separate: every other run should
  // keep behaving as a device whose camera is unavailable.
  const LAUNCH = {
    viewport: PHONE, canvaskitDir: path.join(WEB, 'canvaskit'), tiles, problems, state,
    fakeMedia: true,
  };
  let { browser, newPage } = await launch(LAUNCH);
  await browser.defaultBrowserContext().overridePermissions(origin, ['geolocation', 'camera', 'microphone']);
  let page;

  const shot = async (name) => {
    step += 1;
    const f = `F${String(step).padStart(2, '0')}-${name}.png`;
    await page.screenshot({ path: path.join(OUT, f) });
    shots.push(f);
    console.log(`      shot  ${f}`);
  };

  const screenText = () => page.evaluate(() => {
    const h = document.querySelector('flt-semantics-host') || document.body;
    return ([...h.querySelectorAll('[aria-label]')]
      .map((e) => e.getAttribute('aria-label')).join('\n') + '\n' + h.textContent).trim();
  });

  async function tap(pattern, { settle = 1800 } = {}) {
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
    if (hit) await sleep(settle);
    return hit;
  }

  async function typeInto(text, { which = 'last' } = {}) {
    const focused = await page.evaluate((w) => {
      const boxes = [...document.querySelectorAll('flt-semantics')].filter((n) => {
        const r = n.getBoundingClientRect();
        return (n.getAttribute('role') === 'textbox' || n.querySelector('input, textarea'))
          && r.width > 40 && r.height > 12;
      });
      if (!boxes.length) return false;
      (w === 'first' ? boxes[0] : boxes[boxes.length - 1]).click();
      return true;
    }, which);
    if (!focused) return false;
    await sleep(600);
    const box = await page.evaluate(() => {
      const el = document.querySelector('input, textarea');
      if (!el) return null;
      el.focus();
      const r = el.getBoundingClientRect();
      return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
    });
    if (!box) return false;
    await page.mouse.click(box.x, box.y);
    await sleep(250);
    state.typing = true;
    // Clear whatever is already in it. The name dialog pre-fills the current
    // name, so typing alone appended and produced "Amina BelloAmina
    // Bello-Danjuma" — a write that succeeded with the wrong value, which
    // reads as a broken save rather than a harness that did not clear.
    await page.keyboard.down('Control');
    await page.keyboard.press('KeyA');
    await page.keyboard.up('Control');
    await page.keyboard.press('Backspace');
    await sleep(150);
    await page.keyboard.type(text, { delay: 18 });
    state.typing = false;
    await sleep(400);
    return true;
  }

  async function signInCitizen() {
    try { await browser.close(); } catch { /* gone */ }
    ({ browser, newPage } = await launch(LAUNCH));
    await browser.defaultBrowserContext()
      .overridePermissions(origin, ['geolocation', 'camera', 'microphone']);
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
    // The seeded citizen's own number, signed in the real way. This typed
    // 08000000000, the demo bypass number, which release builds compile
    // out — so this pass could never sign in. It had never run in CI: the
    // job always failed at an earlier step.
    await typeInto(byKey('citizen').phone.replace('+234', '0'));
    await tap('authorize access', { settle: 2600 });
    await typeInto('123456');
    await tap('verify otp', { settle: 7000 });
    return page.evaluate(() => window.location.hash);
  }

  // =========================================================================
  // 1. THE LIVE CAMERA AND MICROPHONE
  // =========================================================================
  state.screen = 'features:sos';
  const landed = await signInCitizen();
  check('a citizen signs in', /home/.test(landed), `on ${landed}`);
  await shot('citizen-home');

  // The stream button lives on the Emergency Active screen, which needs a live
  // SOS: it refuses to stream before the alert is confirmed, on purpose.
  //
  // A TAP on this control is the silent SOS; a HOLD is the full panic alarm,
  // and only the panic path opens the Emergency Active screen. A long press has
  // no semantics equivalent — the node exposes a tap and nothing else — so it
  // has to be pointer events on the element, held.
  const sosMark = (await rest('alerts?select=id')).length;
  const sosNode = await page.evaluate(() => {
    const n = [...document.querySelectorAll('flt-semantics[role="button"]')]
      .find((b) => /SILENT SOS|SOS|PANIC/i.test(
        `${b.textContent || ''} ${b.getAttribute('aria-label') || ''}`));
    if (!n) return null;
    const r = n.getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  });
  if (sosNode) {
    await page.evaluate((x, y, hold) => {
      const target = document.elementFromPoint(x, y) || document.body;
      const opts = { bubbles: true, cancelable: true, clientX: x, clientY: y, pointerId: 1, isPrimary: true, button: 0 };
      target.dispatchEvent(new PointerEvent('pointerdown', opts));
      target.dispatchEvent(new MouseEvent('mousedown', opts));
      return new Promise((res) => setTimeout(() => {
        target.dispatchEvent(new PointerEvent('pointerup', opts));
        target.dispatchEvent(new MouseEvent('mouseup', opts));
        res();
      }, hold));
    }, sosNode.x, sosNode.y, 1500);
  }
  await sleep(10000);
  const onEmergency = await page.evaluate(() => window.location.hash);
  // Count the same thing both times. The first version compared a `limit=3`
  // query against the full count and reported "-2 new alerts" for a panic
  // button that had worked perfectly.
  const afterCount = (await rest('alerts?select=id')).length;
  check(
    'the panic button raises an alert and opens the live emergency screen',
    /emergency-active/.test(onEmergency) && afterCount > sosMark,
    `${onEmergency}, ${afterCount - sosMark} new alert(s)`,
  );
  await shot('emergency-active');

  const before = (await control()).broadcasts.length;
  const streamed = await tap('live|stream|broadcast|camera', { settle: 6000 });
  check('the live stream control is reachable', streamed,
    streamed ? '' : 'no stream control on the emergency screen');
  await shot('live-stream-pressed');

  // Assert the PERSISTENT indication, not the snackbar.
  //
  // The confirmation toast — "🔴 LIVE STREAM BROADCASTING TO HQ" — is gone in
  // four seconds, so reading the screen after the stream has settled finds
  // nothing and reports that the user was left guessing. They are not: the
  // button itself flips to a red STOP STREAM and stays there, which is the
  // indication that actually matters for somebody who needs to know their
  // camera is on.
  const said = await screenText();
  check(
    'the control shows, and keeps showing, that the camera is live',
    /STOP STREAM/i.test(said),
    /STOP STREAM/i.test(said) ? 'button reads STOP STREAM' : 'no lasting indication',
  );

  // The claim that matters: the offer left the device.
  const bc = (await control()).broadcasts.slice(before);
  const offer = bc.find((b) => b.event === 'signalling' && b.payload?.signal === 'offer');
  check(
    'a WebRTC offer is actually broadcast to HQ',
    !!offer,
    offer ? `on ${offer.topic}` : `${bc.length} channel message(s), no offer`,
  );
  check(
    'the offer carries a real session description, not an empty envelope',
    !!(offer && typeof offer.payload.sdp === 'string' && offer.payload.sdp.includes('m=')),
    offer && offer.payload.sdp ? `${offer.payload.sdp.length} chars of SDP` : 'no sdp',
  );
  check(
    'the signalling kind survives the SDK, which overwrites `type`',
    !!(offer && offer.payload.signal === 'offer' && offer.payload.type === 'broadcast'),
    offer ? `signal=${offer.payload.signal} type=${offer.payload.type}` : '',
  );
  check(
    'and it offers BOTH the camera and the microphone, which is what it claims',
    !!(offer && /m=video/.test(offer.payload.sdp || '') && /m=audio/.test(offer.payload.sdp || '')),
    offer && offer.payload.sdp
      ? `${/m=video/.test(offer.payload.sdp) ? 'video' : '-'} + ${/m=audio/.test(offer.payload.sdp) ? 'audio' : '-'}`
      : '',
  );

  // Stopping has to work too: a stream you cannot end is worse than none.
  const stopped = await tap('live|stream|broadcast|camera', { settle: 4000 });
  const bye = (await control()).broadcasts.slice(before)
    .find((b) => b.event === 'signalling' && b.payload?.signal === 'bye');
  check(
    'pressing it again ends the stream and says so on the channel',
    stopped && !!bye,
    bye ? 'bye sent' : 'no bye on the channel',
  );
  const afterStop = await screenText();
  check(
    'and the control goes back to offering the stream, not to nothing',
    /BROADCAST LIVE/i.test(afterStop),
    /BROADCAST LIVE/i.test(afterStop) ? 'button reads BROADCAST LIVE' : 'control missing after stop',
  );
  await shot('live-stream-stopped');

  // =========================================================================
  // 2. THE SETTINGS CONTROLS
  // =========================================================================
  state.screen = 'features:settings';
  const citizen = PEOPLE.find((p) => p.key === 'citizen');
  await page.evaluate(() => { window.location.hash = '#/settings'; });
  await sleep(3500);
  await shot('settings');
  check('the settings screen opens', /SYSTEM SETTINGS|PREFERENCES/i.test(await screenText()));

  // -- the name -----------------------------------------------------------
  const NEW_NAME = 'Amina Bello-Danjuma';
  const nameMark = (await control()).writes.length;
  await tap('Edit your name', { settle: 2200 });
  await typeInto(NEW_NAME);
  await shot('settings-edit-name');
  await tap('save|confirm|update|ok', { settle: 2600 });
  const nameWrites = (await control()).writes.slice(nameMark).filter((w) => w.table === 'profiles');
  const profile = (await rest(`profiles?select=full_name&id=eq.${citizen.id}`))[0];
  check(
    'editing the name writes it to the profile',
    nameWrites.length > 0 && profile && profile.full_name === NEW_NAME,
    profile ? `full_name=${profile.full_name}` : 'profile not found',
  );

  // -- an emergency contact ------------------------------------------------
  const CONTACT = '08031234567';
  const contactMark = (await control()).writes.length;
  await tap('Add an emergency contact', { settle: 2200 });
  await typeInto(CONTACT);
  await shot('settings-add-contact');
  await tap('save|add|confirm|ok', { settle: 2600 });
  const withContact = (await rest(`profiles?select=emergency_contacts&id=eq.${citizen.id}`))[0];
  check(
    'adding an emergency contact stores it',
    !!(withContact && JSON.stringify(withContact.emergency_contacts || []).includes(CONTACT)),
    JSON.stringify(withContact?.emergency_contacts || []).slice(0, 60),
  );
  void contactMark;

  // -- and removing it -----------------------------------------------------
  await tap('Remove this emergency contact', { settle: 2600 });
  await tap('remove|delete|confirm|yes', { settle: 2400 });
  const withoutContact = (await rest(`profiles?select=emergency_contacts&id=eq.${citizen.id}`))[0];
  check(
    'and removing it takes it back out',
    !JSON.stringify(withoutContact?.emergency_contacts || []).includes(CONTACT),
    JSON.stringify(withoutContact?.emergency_contacts || []).slice(0, 60),
  );
  await shot('settings-contact-removed');

  // -- the duress PIN ------------------------------------------------------
  //
  // The one that matters. A duress PIN is what somebody under coercion enters
  // to appear to cancel an emergency while help keeps coming; the safe PIN
  // genuinely cancels it. They must be set, they must differ, and neither may
  // be readable back through the API even by its owner.
  state.screen = 'features:pins';
  await page.evaluate(() => { window.location.hash = '#/emergency-pins'; });
  await sleep(3500);
  await shot('emergency-pins');
  const pinScreen = await screenText();
  check('the emergency PIN screen opens', /PIN/i.test(pinScreen),
    (pinScreen.split('\n')[0] || '').slice(0, 50));

  // Four steps: choose the safe PIN, confirm it, choose the duress PIN, confirm
  // that. Not the two-field form it was first written against — which is why
  // the run reported "no save control" while sitting happily on step 1 of 4.
  const pinMark = (await control()).log.length;
  const SAFE = '2468';
  const DURESS = '1357';
  let pinSaved = false;
  for (const [i, value] of [SAFE, SAFE, DURESS, DURESS].entries()) {
    await typeInto(value);
    if (i === 0) await shot('emergency-pins-filled');
    // The last step commits; the others advance.
    pinSaved = await tap('save|set|confirm|continue|next|proceed|done', { settle: 3000 });
    if (!pinSaved) break;
  }
  const pinCalls = (await control()).log.slice(pinMark)
    .filter((l) => /set_emergency_pins|rpc/i.test(JSON.stringify(l)));
  check(
    'setting the safe and duress PINs reaches the server',
    pinSaved && pinCalls.length > 0,
    pinCalls.length ? pinCalls[0].path || JSON.stringify(pinCalls[0]).slice(0, 80)
      : (pinSaved ? 'saved, nothing sent' : 'no save control'),
  );
  await shot('emergency-pins-saved');

  // Whatever the UI did, the hashes must not be readable through the API.
  const pinLeak = await rest(`profiles?select=*&id=eq.${citizen.id}`);
  const leaked = JSON.stringify(pinLeak).match(/"(safe|duress)_pin[^"]*":"[^"]+"/g) || [];
  check(
    'the PIN material is not readable back through the API',
    leaked.length === 0,
    leaked.length ? leaked.join(', ').slice(0, 80) : 'no pin columns exposed',
  );

  fs.writeFileSync(path.join(OUT, 'user-features.json'), JSON.stringify({
    ranAt: new Date().toISOString(),
    proves: 'the live camera/microphone stream and the citizen settings controls',
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
