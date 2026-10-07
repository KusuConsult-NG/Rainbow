'use strict';
/**
 * Sign in to the mobile app, once, for every harness that needs to.
 *
 * ## Why this module exists
 *
 * Three harnesses carried their own copy of this flow — tier_controls.js,
 * chat_thread.js and chain_lifecycle.js — each about twenty lines of "type the
 * badge, click AUTHORIZE ACCESS, sleep, read the hash". When the login screen
 * grew a second step, one copy was updated and two were not.
 *
 * The way that failed is the point. A staff badge no longer signs anybody in on
 * its own: the access code was never a secret — it was the email local-part, a
 * USERNAME — and the one password every officer shared was readable in the APK
 * because `pubspec.yaml` ships `.env` as an asset (T-20). So AUTHORIZE ACCESS
 * now only REVEALS a password field, and its own label changes to SIGN IN.
 *
 * The old helpers typed the badge, clicked, waited 8.5 seconds, and returned
 * the login screen's hash as though they had signed in. tier_controls.js then
 * carried on and died sixty seconds later inside an unrelated
 * `waitForFunction(... canvas ...)`, reporting a line that had nothing to do
 * with the cause. chat_thread.js did not even fail: it signs in as `unit` and
 * `hq`, never got past the login screen, and still reported PASS — which is
 * worse, because a harness that passes without signing in is testing nothing.
 *
 * So: one copy, and it ASSERTS. Every failure names the step that failed
 * instead of leaving a timeout for someone to trace.
 *
 * ## The two paths
 *
 * A citizen signs in with a phone number and an OTP; there is no password and
 * no email. A staff member signs in with a badge and a password, in two steps.
 * Both are real paths — the demo bypass is compiled out of release builds — and
 * `fake_supabase.js` accepts `123456` as the OTP and `fixtures.PASSWORD` as the
 * password, and nothing else.
 */

const { DOMAIN, PASSWORD, byKey } = require('./fixtures');

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** Click the first visible semantics button whose accessible name matches. */
async function clickButton(page, pattern) {
  return page.evaluate((pat) => {
    const re = new RegExp(pat, 'i');
    for (const n of document.querySelectorAll('flt-semantics[role="button"]')) {
      const r = n.getBoundingClientRect();
      if (r.width < 4 || r.height < 4) continue;
      const t = `${n.textContent || ''} ${n.getAttribute('aria-label') || ''}`;
      if (re.test(t)) { n.click(); return true; }
    }
    return false;
  }, pattern);
}

/** What the semantics tree currently reads as, for assertions. */
async function screenText(page) {
  return page.evaluate(() => {
    const h = document.querySelector('flt-semantics-host') || document.body;
    return h.textContent || '';
  });
}

/**
 * Type into the field Flutter currently has focused.
 *
 * Flutter web keeps ONE DOM `<input>` for whichever field has focus, so a
 * second field has to be focused through its semantics node before typing —
 * `document.querySelector('input')` would otherwise keep hitting the first.
 */
async function typeIntoRevealedField(page, text) {
  // No focusing. Both revealed fields — the staff password and the citizen OTP
  // — carry `autofocus: true`, so Flutter has already moved focus by the time
  // they are on screen, and reaching in to focus them achieved nothing good:
  // Flutter exposes NO `flt-semantics[role="textbox"]` node for a TextField in
  // this version (a probe measured zero, with semantics fully on), so every
  // attempt fell through to the single DOM <input> Flutter maintains.
  //
  // ## An open defect this helper does NOT cause and does NOT fix
  //
  // Typing into the staff password field makes the Flutter engine throw
  // `Cannot read properties of null (reading 'toString')` — twice, from engine
  // frames only (`q.toString` on null), while the sign-in itself still reaches
  // #/agent-dashboard. mobile_capture.js fails on it; tier_controls.js and
  // chat_thread.js collect `pageerror` only and so pass regardless.
  //
  // Six theories were tested with a build and a probe each, and every one was
  // wrong: writing `el.value = ''` (my first and most confident guess), this
  // helper focusing the field, missing `autofillHints`, `obscureText: true`,
  // `autocorrect`/`enableSuggestions: false`, and the accessibility tree being
  // enabled. The reveal on its own is clean — zero errors with no typing. The
  // citizen OTP field, same reveal-then-type shape, never throws.
  //
  // It survives with semantics OFF, so it is not a harness artifact: ordinary
  // users hit it. The release build is minified with no source map, so the next
  // step is a profile build to resolve the frame. Left RED in mobile_capture.js
  // deliberately — that harness is the only one that detects it, and widening
  // its filter to go green would throw away the detector.
  const ready = await page.evaluate(
    () => document.querySelectorAll('input').length > 0);
  if (!ready) return false;
  await page.keyboard.type(text, { delay: 20 });
  await sleep(400);
  return true;
}

/** Focus the first field without writing to the DOM input Flutter owns. */
async function focusFirstField(page) {
  const viaSemantics = await page.evaluate(() => {
    const box = document.querySelector(
      'flt-semantics[role="textbox"], flt-semantics[role="text"]');
    if (box) { box.click(); return true; }
    return false;
  });
  if (!viaSemantics) {
    // Before the semantics tree is up there is nothing to click, so fall back to
    // focusing the input — focus alone does not disturb Flutter's editing state;
    // assigning to `value` is what did.
    await page.evaluate(() => { document.querySelector('input')?.focus(); });
  }
  await sleep(600);
}

/**
 * Sign in as `role` on a page already loaded at the app's origin.
 *
 * `role` is a fixtures key: 'citizen' takes the phone/OTP path, anything else
 * takes the staff badge/password path. Resolves to the resulting location hash,
 * and THROWS naming the step if any part of it did not happen.
 */
async function signInMobile(page, role) {
  await page.waitForFunction(
    () => !!document.querySelector('flutter-view, flt-glass-pane, canvas'),
    { timeout: 120000 });
  await sleep(6000);
  await page.evaluate(
    () => document.querySelector('flt-semantics-placeholder')?.click());
  await sleep(1600);

  if (role === 'citizen') {
    const person = byKey('citizen');
    if (!person) throw new Error('signInMobile: no citizen in fixtures');
    await focusFirstField(page);
    await page.keyboard.type(person.phone.replace('+234', '0'), { delay: 20 });
    await sleep(400);
    if (!await clickButton(page, 'authorize access')) {
      throw new Error('signInMobile(citizen): no AUTHORIZE ACCESS control');
    }
    await sleep(2600);
    if (!await typeIntoRevealedField(page, '123456')) {
      throw new Error('signInMobile(citizen): no OTP field appeared');
    }
    if (!await clickButton(page, 'verify otp')) {
      throw new Error('signInMobile(citizen): no VERIFY OTP control');
    }
  } else {
    await focusFirstField(page);
    await page.keyboard.type(`${role}@${DOMAIN}`, { delay: 20 });
    await sleep(400);
    if (!await clickButton(page, 'authorize access')) {
      throw new Error(`signInMobile(${role}): no AUTHORIZE ACCESS control`);
    }
    await sleep(2500);

    // The reveal. Without this assertion the helper cannot tell "the password
    // step appeared" from "the badge signed me straight in", and that is
    // exactly the ambiguity that let two harnesses rot.
    if (!/sign in/i.test(await screenText(page))) {
      throw new Error(
        `signInMobile(${role}): AUTHORIZE ACCESS did not reveal the password `
        + 'step — the button never became SIGN IN. If the login flow changed '
        + 'again, this module is what has to change with it.');
    }
    if (!await typeIntoRevealedField(page, PASSWORD)) {
      throw new Error(`signInMobile(${role}): no password field to type into`);
    }
    if (!await clickButton(page, 'sign in')) {
      throw new Error(`signInMobile(${role}): no SIGN IN control after reveal`);
    }
  }

  await sleep(8500);
  const hash = await page.evaluate(() => window.location.hash);
  if (!hash || hash === '#/' || /login/i.test(hash)) {
    throw new Error(
      `signInMobile(${role}): still on the login screen (hash `
      + `${hash || '(empty)'}). fake_supabase.js accepts only `
      + 'fixtures.PASSWORD for staff and 123456 as the OTP, so check those '
      + 'first.');
  }
  return hash;
}

module.exports = { signInMobile, clickButton, screenText, typeIntoRevealedField };
