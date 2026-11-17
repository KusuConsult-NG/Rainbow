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
// At the moment of failure it writes down everything that happened since the
// navigation started, so each occurrence explains itself. It changes one
// outcome only: the stall those reports pinned down (isBrowserHeldWasm, the
// browser holding a WebAssembly file it was sent) gets one more reload.
// Every other failure fails exactly as before.

const fs = require('fs');
const http = require('http');
const path = require('path');

const MAX_EVENTS = 400;

/// Whether a stall is the one known browser-side stall, and only that.
///
/// 2026-11-17 the report finally caught both ends of it (chain_lifecycle.js,
/// sign-in ward): the file server received canvaskit.wasm 44 ms after the
/// reload and sent all of it by 60 ms; the page had run main.dart.js, which
/// went on to fetch the fonts; the page still answered probes; and its own
/// fetch of canvaskit.wasm was pending at 120 s, with no resource-timing
/// entry, so inside the page the response never ended. The browser stopped
/// reading a file it had been sent. Nothing in the app or the harness's
/// server does that, and it did not reproduce in 30 local reloads.
///
/// So that stall alone earns one more reload. Everything else still fails
/// at once: a script error, a crash, a page that does not answer, a file the
/// server never received or never finished sending, or anything pending
/// that is not WebAssembly.
function isBrowserHeldWasm({ pending, server, events, dom }) {
  if (!dom || dom.probeError) return false;
  if (!pending || pending.length === 0 || !server) return false;
  if ((events || []).some((e) => /pageerror|crash/.test(e.kind))) return false;
  return pending.every((p) => {
    const tail = p.url.replace(/^https?:\/\/[^/]+/, '').split('?')[0];
    if (!tail.endsWith('.wasm')) return false;
    const seen = server.filter((e) => e.path === tail);
    return seen.some((e) => e.event === 'sent')
      && !seen.some((e) => e.event !== 'received' && e.event !== 'sent');
  });
}

/// Starts recording what [page] does. Call `mark(label)` just before a
/// navigation, then `waitForApp(...)` in place of the bare wait.
///
/// [serverLog], if given, returns what the harness's own file server saw
/// since a time (ms since epoch): the other side of every request, so a
/// request the browser is still waiting on can be told apart as "never
/// arrived" or "arrived and was never answered".
function watchPage(page, { serverLog } = {}) {
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

    let server = null;
    try {
      server = serverLog ? serverLog(since) : null;
    } catch (e) {
      server = [{ error: String(e) }];
    }
    const body = {
      label,
      waitedMs: timeoutMs,
      error: String(err).slice(0, 300),
      dom,
      metrics,
      pendingRequests: stillPending,
      events,
      server,
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
    if (server) {
      // What the file server did about each request the browser still waits on.
      for (const p of stillPending) {
        const tail = p.url.replace(/^https?:\/\/[^/]+/, '').split('?')[0];
        const seen = server.filter((e) => e.path === tail);
        console.log(`        server, ${tail}: ${seen.length
          ? seen.map((e) => `${e.event} at ${e.at - since} ms`).join(', ')
          : 'never received it'}`);
      }
    }
    return { browserHeldWasm: isBrowserHeldWasm({ pending: stillPending, server, events, dom }) };
  }

  const appUp = (timeoutMs) => page.waitForFunction(
    () => !!document.querySelector('flutter-view, flt-glass-pane, canvas'),
    { timeout: timeoutMs },
  );

  /// The wait the harness always did, plus a report when it times out.
  ///
  /// When the report shows the known browser-side stall (isBrowserHeldWasm),
  /// the page is reloaded ONCE and waited on again for the same time: the app
  /// must still start, on its own, from a clean load. A second stall, or any
  /// other kind of failure, rethrows the original error unchanged. Every
  /// stall still writes its report and says so in the log.
  ///
  /// `retry: false` is for a caller with a recovery of its own (a fresh
  /// browser, a reload of any failure): the report is written, and the error
  /// goes straight back to that caller.
  async function waitForApp(timeoutMs, outDir, { retry = true } = {}) {
    try {
      await appUp(timeoutMs);
      return;
    } catch (err) {
      let diagnosis = null;
      try {
        diagnosis = await report(outDir, timeoutMs, err);
      } catch (e) {
        console.log(`      stall report failed: ${e}`);
      }
      if (!retry || !diagnosis || !diagnosis.browserHeldWasm) throw err;

      const first = label;
      console.log(`      ${first}: the browser held a WebAssembly file the server had sent`
        + ' (the known stall) — reloading once');
      mark(`${first} retry`);
      await page.reload({ waitUntil: 'domcontentloaded' });
      try {
        await appUp(timeoutMs);
      } catch (err2) {
        try {
          await report(outDir, timeoutMs, err2);
        } catch (e) {
          console.log(`      stall report failed: ${e}`);
        }
        throw err;
      }
      console.log(`      ${first}: the app started after one reload`);
    }
  }

  return { mark, waitForApp };
}

const STATIC_TYPES = {
  '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript',
  '.json': 'application/json', '.wasm': 'application/wasm', '.png': 'image/png',
  '.otf': 'font/otf', '.ttf': 'font/ttf', '.woff2': 'font/woff2',
  '.css': 'text/css', '.svg': 'image/svg+xml', '.symbols': 'text/plain',
};

/// The harness's file server for the web build in [webRoot], recording what it
/// did with every request: received, sent, closed early, read error, 404.
/// Pass `serverLog` to watchPage so a stall report can say whether a request
/// the browser is still waiting on ever arrived. Shared, so every script that
/// reloads the app gets the same evidence: the reload stall has now been seen
/// in mobile_interact.js (2026-11-14, 2026-11-15) and chain_lifecycle.js
/// (2026-11-16, 2026-11-17).
///
/// [headers] are added to every file served (mobile_capture.js sends the
/// cross-origin isolation headers it always has).
function loggedStaticServer(webRoot, { headers = {} } = {}) {
  const served = [];
  const note = (event, p) => {
    served.push({ at: Date.now(), event, path: p });
    if (served.length > 2000) served.splice(0, served.length - 2000);
  };
  const server = http.createServer((req, res) => {
    const urlPath = req.url.split('?')[0];
    note('received', urlPath);
    const rel = decodeURIComponent(urlPath).replace(/^\/+/, '') || 'index.html';
    const file = path.join(webRoot, rel);
    if (!file.startsWith(webRoot) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
      note('404', urlPath);
      res.writeHead(404); return res.end('not found');
    }
    res.on('finish', () => note('sent', urlPath));
    res.on('close', () => { if (!res.writableFinished) note('connection closed before the end', urlPath); });
    res.writeHead(200, {
      'content-type': STATIC_TYPES[path.extname(file)] || 'application/octet-stream',
      ...headers,
    });
    fs.createReadStream(file)
      .on('error', (e) => { note(`read error: ${e.code || e}`, urlPath); res.destroy(); })
      .pipe(res);
  });
  return { server, serverLog: (since) => served.filter((e) => e.at >= since) };
}

module.exports = { watchPage, loggedStaticServer, isBrowserHeldWasm };
