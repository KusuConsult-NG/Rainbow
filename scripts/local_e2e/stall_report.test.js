'use strict';
// Which stalls earn a second reload: the known browser-side one, and nothing
// else. Run with `node --test scripts/local_e2e/stall_report.test.js`.

const test = require('node:test');
const assert = require('node:assert');
const { isBrowserHeldWasm } = require('./stall_report');

const WASM = 'http://127.0.0.1:8086/canvaskit/chromium/canvaskit.wasm';
const PATH = '/canvaskit/chromium/canvaskit.wasm';

// The 2026-11-17 report (chain_lifecycle.js, sign-in ward), trimmed.
const known = () => ({
  dom: { readyState: 'complete', appElements: { flutterView: false }, jsHeapMB: 19 },
  pending: [{ url: WASM, method: 'GET', type: 'fetch', at: 43, waitedMs: 120014 }],
  server: [
    { at: 1, event: 'received', path: PATH },
    { at: 2, event: 'received', path: '/main.dart.js' },
    { at: 17, event: 'sent', path: PATH },
    { at: 40, event: 'sent', path: '/main.dart.js' },
  ],
  events: [
    { t: 18, kind: 'navigated' },
    { t: 40, kind: 'console.warn', text: 'Automatic fallback to software WebGL…' },
    { t: 44, kind: 'console.debug', text: 'Injecting <script> tag. Using callback.' },
  ],
});

test('the stall seen on 2026-11-17 is the known one', () => {
  assert.strictEqual(isBrowserHeldWasm(known()), true);
});

test('a file the server never received is not', () => {
  const s = known();
  s.server = s.server.filter((e) => e.path !== PATH);
  assert.strictEqual(isBrowserHeldWasm(s), false);
});

test('a file the server received but never finished sending is not', () => {
  const s = known();
  s.server = s.server.filter((e) => !(e.path === PATH && e.event === 'sent'));
  assert.strictEqual(isBrowserHeldWasm(s), false);
});

test('a file whose sending broke off is not', () => {
  const s = known();
  s.server.push({ at: 18, event: 'connection closed before the end', path: PATH });
  assert.strictEqual(isBrowserHeldWasm(s), false);
});

test('a script error on the page is not', () => {
  const s = known();
  s.events.push({ t: 50, kind: 'pageerror', text: 'TypeError: x is undefined' });
  assert.strictEqual(isBrowserHeldWasm(s), false);
});

test('a crashed renderer is not', () => {
  const s = known();
  s.events.push({ t: 50, kind: 'crash', text: 'Page crashed!' });
  assert.strictEqual(isBrowserHeldWasm(s), false);
});

test('a page that does not answer is not', () => {
  const s = known();
  s.dom = { probeError: 'no answer within 5000 ms' };
  assert.strictEqual(isBrowserHeldWasm(s), false);
});

test('nothing pending is not: the app simply did not start', () => {
  const s = known();
  s.pending = [];
  assert.strictEqual(isBrowserHeldWasm(s), false);
});

test('anything pending besides WebAssembly is not', () => {
  const s = known();
  s.pending.push({ url: 'http://127.0.0.1:8086/main.dart.js', type: 'script', at: 42 });
  s.server.push({ at: 41, event: 'sent', path: '/main.dart.js' });
  assert.strictEqual(isBrowserHeldWasm(s), false);
});

test('without the server log it is not', () => {
  const s = known();
  s.server = null;
  assert.strictEqual(isBrowserHeldWasm(s), false);
});
