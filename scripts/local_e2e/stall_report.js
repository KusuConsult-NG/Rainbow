'use strict';
// WHEN THE APP NEVER APPEARS, SAY WHAT THE BROWSER WAS DOING.
//
// On 2026-11-14 a CI run of mobile_interact.js reloaded the page between
// report categories and the Flutter view never appeared within 60 s. A re-run
// passed. The failure said only "Waiting failed: 60000ms exceeded", which
// cannot tell a request that never came back from a script that threw, a
// main thread stuck in a loop, or a renderer that ran out of memory. Each of
// those has a different fix, and guessing between them is how a flake gets
// "fixed" by a longer timeout.
//
// This changes no outcome: the wait still fails exactly as before. It only
// writes down, at the moment of failure, everything that happened since the
// navigation started — so the next occurrence explains itself.

const fs = require('fs');
const path = require('path');

const MAX_EVENTS = 400;

/// Starts recording what [page] does. Call `mark(label)` just before a
/// navigation, then `waitForApp(...)` in place of the bare wait.
function watchPage(page) {
  let since = Date.now();
  let label = 'start';
  let events = [];
  const pending = new Map(); // request -> { url, method, type, at }

  const t = () => Date.now() - since;
  const push = (e) => {
    events.push({ t: t(), ...e });
    if (events.length > MAX_EVENTS) events = events.slice(-MAX_EVENTS);
  };
  const short = (url) => (url.length > 200 ? `${url.slice(0, 200)}…` : url);

  page.on('request', (r) => {
    pending.set(r, { url: short(r.url()), method: r.method(), type: r.resourceType(), at: t() });
  });
  page.on('requestfinished', (r) => {
    pending.delete(r);
    const res = r.response();
    if (res && res.status() >= 400) push({ kind: 'http', status: res.status(), url: short(r.url()) });
  });
  page.on('requestfailed', (r) => {
    pending.delete(r);
    push({ kind: 'requestfailed', url: short(r.url()), error: r.failure() ? r.failure().errorText : '' });
  });
  page.on('console', (m) => push({ kind: `console.${m.type()}`, text: m.text().slice(0, 300) }));
  page.on('pageerror', (e) => push({ kind: 'pageerror', text: String(e).slice(0, 300) }));
  page.on('framenavigated', (f) => {
    if (f === page.mainFrame()) push({ kind: 'navigated', url: short(f.url()) });
  });
  page.on('domcontentloaded', () => push({ kind: 'domcontentloaded' }));
  page.on('load', () => push({ kind: 'load' }));
  page.on('error', (e) => push({ kind: 'crash', text: String(e).slice(0, 300) }));

  function mark(newLabel) {
    since = Date.now();
    label = newLabel;
    events = [];
    pending.clear();
  }

  // A page whose main thread is stuck never answers evaluate(); the report
  // must still be written, so every probe has its own short deadline.
  const within = (ms, p) =>
    Promise.race([
      p.catch((e) => ({ probeError: String(e).slice(0, 200) })),
      new Promise((res) => setTimeout(() => res({ probeError: `no answer within ${ms} ms` }), ms)),
    ]);

  async function report(outDir, timeoutMs, err) {
    const dom = await within(5000, page.evaluate(() => {
      const pick = /main\.dart|flutter|canvaskit|skwasm/i;
      return {
        url: location.href,
        readyState: document.readyState,
        appElements: {
          flutterView: !!document.querySelector('flutter-view'),
          glassPane: !!document.querySelector('flt-glass-pane'),
          canvas: document.querySelectorAll('canvas').length,
        },
        bodyChildren: document.body ? document.body.children.length : null,
        scripts: [...document.scripts].map((s) => s.src || '(inline)').slice(0, 20),
        // How far each Flutter file got: a responseEnd of 0 never finished.
        resources: performance.getEntriesByType('resource')
          .filter((r) => pick.test(r.name))
          .map((r) => ({
            name: r.name.split('/').slice(-2).join('/'),
            start: Math.round(r.startTime),
            responseEnd: Math.round(r.responseEnd),
            duration: Math.round(r.duration),
            bytes: r.transferSize || r.encodedBodySize || 0,
          })),
        navigation: (() => {
          const n = performance.getEntriesByType('navigation')[0];
          return n ? { domContentLoaded: Math.round(n.domContentLoadedEventEnd), load: Math.round(n.loadEventEnd) } : null;
        })(),
        jsHeapMB: performance.memory
          ? Math.round(performance.memory.usedJSHeapSize / 1048576)
          : null,
      };
    }));
    const metrics = await within(5000, page.metrics());
    const stillPending = [...pending.values()].map((p) => ({ ...p, waitedMs: t() - p.at }));

    const slug = label.replace(/[^a-z0-9]+/gi, '-').replace(/^-|-$/g, '').toLowerCase();
    const file = path.join(outDir, `stall-${slug}.json`);
    const shotFile = path.join(outDir, `stall-${slug}.png`);
    const shot = await within(10000, page.screenshot({ path: shotFile }).then(() => path.basename(shotFile)));

    const body = {
      label,
      waitedMs: timeoutMs,
      error: String(err).slice(0, 300),
      dom,
      metrics,
      pendingRequests: stillPending,
      events,
      screenshot: shot,
    };
    try {
      fs.writeFileSync(file, JSON.stringify(body, null, 2));
    } catch (e) {
      console.log(`      stall report could not be written: ${e}`);
    }

    // The summary goes in the log too, where a CI failure is read first.
    const errs = events.filter((e) => /pageerror|requestfailed|http|crash|console\.error/.test(e.kind));
    console.log(`      STALL ${label}: no app after ${timeoutMs} ms — report ${path.basename(file)}`);
    console.log(`        readyState=${dom.readyState ?? '?'} app=${JSON.stringify(dom.appElements ?? dom.probeError)}`
      + ` heapMB=${dom.jsHeapMB ?? '?'}`);
    if (dom.probeError) {
      console.log('        the page itself did not answer: its main thread is busy (a loop, a huge'
        + ' parse) or the renderer is gone — see metrics and events in the report');
    }
    for (const r of dom.resources || []) {
      console.log(`        ${r.name}: start ${r.start} ms, end ${r.responseEnd || 'never'} ms, ${r.bytes} B`);
    }
    for (const p of stillPending.slice(0, 10)) {
      console.log(`        still waiting ${p.waitedMs} ms for ${p.type} ${p.url}`);
    }
    for (const e of errs.slice(-10)) {
      console.log(`        at ${e.t} ms ${e.kind}: ${e.text || e.error || ''} ${e.url || ''}`.trimEnd());
    }
    if (!errs.length && !stillPending.length) console.log('        no errors and no requests outstanding');
  }

  /// The wait the harness always did, plus a report when it times out. The
  /// original error is rethrown unchanged.
  async function waitForApp(timeoutMs, outDir) {
    try {
      await page.waitForFunction(
        () => !!document.querySelector('flutter-view, flt-glass-pane, canvas'),
        { timeout: timeoutMs },
      );
    } catch (err) {
      try {
        await report(outDir, timeoutMs, err);
      } catch (e) {
        console.log(`      stall report failed: ${e}`);
      }
      throw err;
    }
  }

  return { mark, waitForApp };
}

module.exports = { watchPage };
