#!/usr/bin/env node
// ============================================================================
// Regression guards for audit finding C-6.
//
//   node functions/test_guards.js      (exit 0 = the endpoints are shut)
//
// `functions.https.onRequest` is a PUBLIC HTTP endpoint with no authentication
// unless the handler adds it. Two exports in index.js did not add it:
//
//   smsWebhook    POST ALERT|<any phone>|KD|LAT:..|LNG:.. created a CRITICAL
//                 kidnap alert attributed to a phone number of the caller's
//                 choosing, and enqueued a real escalation to WARD tier.
//   seedMockData  one unauthenticated request wrote ten CRITICAL alerts, three
//                 of them flagged DURESS — the code word this system uses for
//                 reporting under coercion.
//
// This drives the REAL exported handlers, not a re-implementation. Firestore is
// stubbed so that every write attempt is recorded, because the property under
// test is not "the response code is 401" — it is "nothing reached the database".
// A guard that returns 401 after writing the row would pass the first check and
// fail this one.
//
// Verified by mutation: with the guards removed, 15 of the 16 assertions below
// fail, and the unauthenticated seedMockData call produces 11 writes. The one
// that still passes is the deliberate control — "an authorised request is still
// processed" — which must hold in both directions, or the guard is just an
// outage.
//
// ── SCOPE, stated plainly ───────────────────────────────────────────────────
// This protects anything deployed FROM NOW ON. It does NOT help an
// already-deployed copy: source changes do not reach a live Cloud Function
// until someone redeploys. Closing C-6 means deleting the DEPLOYMENT:
//
//   firebase functions:list   --project rainbow-97f1e
//   firebase functions:delete smsWebhook seedMockData --project rainbow-97f1e
//
// See E2E_AUDIT_REPORT.md C-6, including why functions/ must not be deleted
// before that check is done.
// ============================================================================
const Module = require('module');

const writes = [];

// Stub firebase-admin before index.js requires it, so no credential is needed
// and no real project can be touched by running this.
const stubAdmin = {
  initializeApp: () => {},
  firestore: () => ({
    collection: () => ({
      doc: () => ({ id: 'stub' }),
      add: async (d) => { writes.push(d); return { id: 'stub' }; },
    }),
    batch: () => ({ set: (_r, d) => writes.push(d), commit: async () => writes.push('COMMIT') }),
  }),
};
stubAdmin.firestore.FieldValue = { serverTimestamp: () => 'TS', arrayUnion: (x) => x };

const origLoad = Module._load;
Module._load = function (request) {
  if (request === 'firebase-admin') return stubAdmin;
  if (request === 'firebase-admin/functions') {
    return { getFunctions: () => ({ taskQueue: () => ({ enqueue: async () => {} }) }) };
  }
  if (request === '@google-cloud/vertexai') return { VertexAI: function () { return {}; } };
  return origLoad.apply(this, arguments);
};

const fns = require('./index.js');

const makeRes = () => {
  const r = { code: null, body: null };
  r.status = (c) => { r.code = c; return r; };
  r.send = (b) => { r.body = b; return r; };
  return r;
};

const makeReq = ({ method = 'POST', headers = {}, body = {} } = {}) => {
  const lower = {};
  for (const [k, v] of Object.entries(headers)) lower[k.toLowerCase()] = v;
  return { method, body, get: (h) => lower[h.toLowerCase()] };
};

let failures = 0;
const check = (name, ok, detail = '') => {
  console.log(`${ok ? '  PASS' : '  FAIL'}: ${name}${detail ? ` — ${detail}` : ''}`);
  if (!ok) failures++;
};

const SMS = 'ALERT|+2348000000000|KD|LAT:9.9|LNG:8.9';

(async () => {
  console.log('▶ smsWebhook — unauthenticated emergency injection');

  delete process.env.RAINBOW_SMS_GATEWAY_SECRET;
  writes.length = 0;
  let res = makeRes();
  await fns.smsWebhook(makeReq({ body: { Body: SMS } }), res);
  check('unconfigured secret fails CLOSED (503)', res.code === 503, `got ${res.code}`);
  check('...and nothing reached the database', writes.length === 0, `${writes.length} writes`);

  process.env.RAINBOW_SMS_GATEWAY_SECRET = 'correct-horse';

  writes.length = 0; res = makeRes();
  await fns.smsWebhook(makeReq({ body: { Body: SMS } }), res);
  check('missing auth header -> 401', res.code === 401, `got ${res.code}`);
  check('...and nothing reached the database', writes.length === 0, `${writes.length} writes`);

  writes.length = 0; res = makeRes();
  await fns.smsWebhook(makeReq({ headers: { 'X-Rainbow-Gateway-Auth': 'wrong' }, body: { Body: SMS } }), res);
  check('wrong secret -> 401', res.code === 401, `got ${res.code}`);
  check('...and nothing reached the database', writes.length === 0, `${writes.length} writes`);

  // Control: the guard must not be a blanket outage of the SMS gateway.
  writes.length = 0; res = makeRes();
  await fns.smsWebhook(makeReq({
    headers: { 'X-Rainbow-Gateway-Auth': 'correct-horse' },
    body: { Body: 'ALERT|+2348000000000|KD|LAT:|LNG:' },
  }), res);
  let row = writes.find((w) => w && w.type);
  check('CONTROL: an authorised request is still processed', !!row, `code=${res.code}`);

  // C-5, third occurrence: `|| 9.9167` / `|| 8.8917` turned an SMS with no
  // usable position into a confident pin in central Jos.
  if (row) {
    check('C-5: unusable coords stored as null, not 9.9167', row.lat === null, `lat=${row.lat}`);
    check('C-5: unusable coords stored as null, not 8.8917', row.lng === null, `lng=${row.lng}`);
  }

  // The old `||` also replaced a legitimate coordinate of exactly 0.
  writes.length = 0; res = makeRes();
  await fns.smsWebhook(makeReq({
    headers: { 'X-Rainbow-Gateway-Auth': 'correct-horse' },
    body: { Body: 'ALERT|+2348000000000|KD|LAT:0|LNG:0' },
  }), res);
  row = writes.find((w) => w && w.type);
  check('C-5: a legitimate 0 coordinate survives',
    !!row && row.lat === 0 && row.lng === 0, row ? `lat=${row.lat} lng=${row.lng}` : 'no row');

  console.log('▶ seedMockData — unauthenticated DURESS-alert injection');

  delete process.env.RAINBOW_ALLOW_SEED;
  delete process.env.RAINBOW_SEED_SECRET;
  writes.length = 0; res = makeRes();
  await fns.seedMockData(makeReq({ method: 'GET' }), res);
  check('default configuration refuses (403)', res.code === 403, `got ${res.code}`);
  check('...and wrote no DURESS rows', writes.length === 0, `${writes.length} writes`);

  process.env.RAINBOW_ALLOW_SEED = 'true';
  process.env.RAINBOW_SEED_SECRET = 'seed-secret';

  writes.length = 0; res = makeRes();
  await fns.seedMockData(makeReq({ method: 'GET' }), res);
  check('GET rejected even when seeding is enabled (405)', res.code === 405, `got ${res.code}`);
  check('...and nothing reached the database', writes.length === 0, `${writes.length} writes`);

  writes.length = 0; res = makeRes();
  await fns.seedMockData(makeReq({ method: 'POST' }), res);
  check('enabled but no auth header -> 401', res.code === 401, `got ${res.code}`);
  check('...and nothing reached the database', writes.length === 0, `${writes.length} writes`);

  if (failures === 0) {
    console.log('\n✓ C-6 guards hold. Reminder: this covers FUTURE deploys only —');
    console.log('  run `firebase functions:list --project rainbow-97f1e` to close it for real.');
    process.exit(0);
  }
  console.error(`\n✗ ${failures} assertion(s) failed — an endpoint is open.`);
  process.exit(1);
})().catch((e) => {
  console.error('HARNESS ERROR:', e);
  process.exit(2);
});
