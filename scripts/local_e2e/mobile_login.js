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
async function typeIntoLastField(page, text) {
  const focused = await page.evaluate(() => {
    const boxes = [...document.querySelectorAll(
      'flt-semantics[role="textbox"], flt-semantics[role="text"]')];
    const box = boxes[boxes.length - 1];
    if (box) { box.click(); return true; }
    const el = document.querySelector('input');
    if (el) { el.focus(); return true; }
    return false;
  });
  if (!focused) return false;
  await sleep(1200);
  await page.evaluate(() => {
    const els = document.querySelectorAll('input');
    const el = els[els.length - 1];
    if (el) { el.focus(); el.value = ''; }
  });
  await page.keyboard.type(text, { delay: 20 });
  await sleep(400);
  return true;
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
    await page.evaluate(() => {
      const el = document.querySelector('input');
      if (el) { el.focus(); el.value = ''; }
    });
    await page.keyboard.type(person.phone.replace('+234', '0'), { delay: 20 });
    await sleep(400);
    if (!await clickButton(page, 'authorize access')) {
      throw new Error('signInMobile(citizen): no AUTHORIZE ACCESS control');
    }
    await sleep(2600);
    if (!await typeIntoLastField(page, '123456')) {
      throw new Error('signInMobile(citizen): no OTP field appeared');
    }
    if (!await clickButton(page, 'verify otp')) {
      throw new Error('signInMobile(citizen): no VERIFY OTP control');
    }
  } else {
    await page.evaluate(() => {
      const el = document.querySelector('input');
      if (el) { el.focus(); el.value = ''; }
    });
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
    if (!await typeIntoLastField(page, PASSWORD)) {
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

module.exports = { signInMobile, clickButton, screenText, typeIntoLastField };
