/**
 * A local stand-in for Supabase: Auth, a PostgREST subset, and enough of the
 * realtime socket that subscriptions reach SUBSCRIBED instead of erroring.
 *
 * Why this exists. Every console finding in this repository so far came from
 * reading code or from unit tests of logic deliberately lifted out so it could
 * be tested. No screen had ever been rendered. A screen that renders is a
 * different claim from logic that passes: it covers the wiring between them,
 * which is where this system's worst defects lived.
 *
 * What it is NOT. It does not enforce row-level security, and it must never be
 * read as evidence that the deployed database does. Policies can only be proven
 * against a real PostgREST — `scripts/verify_rls.js` against a staging project.
 * This fake answers every query as the service role would.
 *
 * What it does enforce, because it is the one thing a fake can get wrong in a
 * way that HIDES a bug: unknown columns. PostgREST rejects a query naming a
 * column that does not exist, in full, both on read and on write. A tolerant
 * fake would turn the system's most expensive defect class into a pass. So the
 * column list comes from `supabase/migrations/` and an unknown column is a 400,
 * the same as production.
 */

const http = require('http');
const crypto = require('crypto');
const path = require('path');
const { tables, PEOPLE, PASSWORD, DOMAIN } = require('./fixtures');
const { columns: schema, relationships } = require('./schema').build();

const PORT = Number(process.env.FAKE_SUPABASE_PORT || 54321);

/**
 * The fixtures as loaded, kept aside so a flow that dispatches an incident does
 * not change what the next flow sees. Without this the run's assertions depend
 * on their own order, which is the kind of test that passes until someone adds
 * a case in the middle.
 */
const PRISTINE = JSON.parse(JSON.stringify(tables));

/** Requests are recorded so the run can assert on what the app actually asked for. */
const log = [];
/** Columns the app named that the migrations do not define. Any entry fails the run. */
const unknownColumns = [];
/** Writes the app performed, so a "did the broadcast actually send?" claim has evidence. */
const writes = [];

// ---------------------------------------------------------------------------
// Fixture self-check: a fixture column the schema does not define is a bug in
// the fixture, and would make the fake serve a field production cannot.
// ---------------------------------------------------------------------------
{
  const bad = [];
  for (const [table, rows] of Object.entries(tables)) {
    const allowed = schema[table];
    if (!allowed) {
      bad.push(`${table}: no such table in supabase/migrations/`);
      continue;
    }
    for (const key of new Set(rows.flatMap((r) => Object.keys(r)))) {
      if (!allowed.includes(key)) bad.push(`${table}.${key}`);
    }
  }
  if (bad.length) {
    console.error('[fake] FIXTURES NAME COLUMNS THAT DO NOT EXIST:\n  ' + bad.join('\n  '));
    process.exit(1);
  }
}

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

const b64url = (obj) =>
  Buffer.from(JSON.stringify(obj)).toString('base64url');

/**
 * A structurally real JWT. supabase-js reads `exp` off the payload to decide
 * whether to refresh, so a placeholder string is not enough; nothing local
 * verifies the signature.
 */
function mintToken(user) {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url({ alg: 'HS256', typ: 'JWT' });
  const payload = b64url({
    aud: 'authenticated',
    exp: now + 3600,
    iat: now,
    iss: `http://127.0.0.1:${PORT}/auth/v1`,
    sub: user.id,
    email: user.email,
    role: 'authenticated',
    app_metadata: { provider: 'email', providers: ['email'] },
    user_metadata: {},
  });
  const sig = crypto
    .createHmac('sha256', 'local-e2e-not-a-secret')
    .update(`${header}.${payload}`)
    .digest('base64url');
  return `${header}.${payload}.${sig}`;
}

const authUsers = PEOPLE.map((p) => ({
  id: p.id,
  aud: 'authenticated',
  role: 'authenticated',
  email: `${p.key}@${DOMAIN}`,
  email_confirmed_at: '2026-09-01T08:00:00.000Z',
  phone: '',
  confirmed_at: '2026-09-01T08:00:00.000Z',
  last_sign_in_at: new Date().toISOString(),
  app_metadata: { provider: 'email', providers: ['email'] },
  user_metadata: {},
  identities: [],
  created_at: '2026-09-01T08:00:00.000Z',
  updated_at: '2026-09-01T08:00:00.000Z',
  is_anonymous: false,
}));

/** access_token -> user. Held in memory; the process is per-run. */
const sessions = new Map();

function session(user) {
  const access_token = mintToken(user);
  sessions.set(access_token, user);
  return {
    access_token,
    token_type: 'bearer',
    expires_in: 3600,
    expires_at: Math.floor(Date.now() / 1000) + 3600,
    refresh_token: crypto.randomBytes(16).toString('hex'),
    user,
  };
}

function bearer(req) {
  const h = req.headers.authorization || '';
  const m = h.match(/^Bearer\s+(.+)$/i);
  if (!m) return null;
  return sessions.get(m[1]) || null;
}

// ---------------------------------------------------------------------------
// PostgREST subset
// ---------------------------------------------------------------------------

/**
 * Split `select=` into its own columns and its embedded resources.
 *
 * `select=*,profiles(full_name,role)` is two different things: a column list
 * and a request to embed another table. PostgREST will only do the second if a
 * foreign key joins them, so they have to be told apart rather than flattened —
 * an earlier version of this function concatenated the embed's columns into one
 * nonsense identifier and reported a fault that did not exist.
 *
 * Returns { columns, embeds } where `columns` is null for `*`.
 */
function parseSelect(select) {
  if (!select) return { columns: null, embeds: [] };
  const parts = [];
  let depth = 0;
  let cur = '';
  for (const ch of select) {
    if (ch === '(') depth++;
    if (ch === ')') depth--;
    if (ch === ',' && depth === 0) { parts.push(cur); cur = ''; continue; }
    cur += ch;
  }
  if (cur) parts.push(cur);

  const columns = [];
  const embeds = [];
  let sawStar = false;
  for (const raw of parts) {
    const part = raw.trim();
    if (!part) continue;
    const embed = part.match(/^([a-z_][a-z0-9_]*)\s*\(([\s\S]*)\)$/i);
    if (embed) {
      embeds.push({
        table: embed[1],
        columns: embed[2].split(',').map((c) => c.trim().split(':').pop().trim()).filter(Boolean),
      });
      continue;
    }
    const name = part.split(':').pop().trim();
    if (name === '*') { sawStar = true; continue; }
    columns.push(name);
  }
  return { columns: sawStar && !columns.length ? null : columns, embeds, sawStar };
}

const OPS = {
  eq: (a, b) => String(a) === b,
  neq: (a, b) => String(a) !== b,
  gt: (a, b) => Number(a) > Number(b),
  gte: (a, b) => Number(a) >= Number(b),
  lt: (a, b) => Number(a) < Number(b),
  lte: (a, b) => Number(a) <= Number(b),
  like: (a, b) => new RegExp('^' + b.replace(/%/g, '.*') + '$').test(String(a)),
  ilike: (a, b) => new RegExp('^' + b.replace(/%/g, '.*') + '$', 'i').test(String(a)),
  is: (a, b) => (b === 'null' ? a === null || a === undefined : String(a) === b),
  in: (a, b) =>
    b.replace(/^\(|\)$/g, '').split(',').map((v) => v.replace(/^"|"$/g, '')).includes(String(a)),
};

const RESERVED = new Set(['select', 'order', 'limit', 'offset', 'on_conflict', 'and', 'or', 'not']);

/** Returns {rows} or {error}. `error` mirrors PostgREST's unknown-column 400. */
function query(table, params, noteUnknown) {
  const allowed = schema[table];
  if (!allowed) {
    return { error: { code: '42P01', message: `relation "public.${table}" does not exist` } };
  }

  const bad = [];
  const { columns: cols, embeds, sawStar } = parseSelect(params.get('select'));
  for (const c of cols || []) if (!allowed.includes(c)) bad.push(c);
  for (const [key] of params) {
    if (RESERVED.has(key)) continue;
    if (!allowed.includes(key)) bad.push(key);
  }
  // `order=` names a column too, and it is the one place a bad name is easiest
  // to miss: the query looks right, and the column only appears in a modifier.
  const order = params.get('order');
  if (order) {
    const c = order.split('.')[0];
    if (c && !allowed.includes(c)) bad.push(c);
  }
  if (bad.length) {
    for (const c of new Set(bad)) noteUnknown(table, c, 'read');
    return {
      error: {
        code: '42703',
        message: `column ${table}.${[...new Set(bad)][0]} does not exist`,
      },
    };
  }

  // Embedding needs a declared foreign key. Without one PostgREST refuses the
  // whole query, exactly as it does for an unknown column.
  for (const e of embeds) {
    const joined =
      (relationships[table] || []).includes(e.table) ||
      (relationships[e.table] || []).includes(table);
    if (!joined) {
      noteUnknown(table, `${e.table}(…) — no foreign key joins them`, 'embed');
      return {
        error: {
          code: 'PGRST200',
          message: `Could not find a relationship between '${table}' and '${e.table}' in the schema cache`,
        },
      };
    }
    for (const c of e.columns) {
      if (!(schema[e.table] || []).includes(c)) {
        noteUnknown(e.table, c, 'embed');
        return { error: { code: '42703', message: `column ${e.table}.${c} does not exist` } };
      }
    }
  }

  let rows = (tables[table] || []).slice();
  for (const [key, raw] of params) {
    if (RESERVED.has(key)) continue;
    const dot = raw.indexOf('.');
    const op = raw.slice(0, dot);
    const val = raw.slice(dot + 1);
    if (!OPS[op]) continue;
    rows = rows.filter((r) => OPS[op](r[key], val));
  }

  if (order) {
    const [col, ...rest] = order.split('.');
    const asc = !rest.includes('desc');
    rows.sort((a, b) => {
      const x = a[col], y = b[col];
      if (x === y) return 0;
      if (x === null || x === undefined) return 1;
      if (y === null || y === undefined) return -1;
      return (x > y ? 1 : -1) * (asc ? 1 : -1);
    });
  }

  const total = rows.length;
  const limit = params.get('limit');
  if (limit) rows = rows.slice(0, Number(limit));

  if (cols && !sawStar) {
    rows = rows.map((r) => Object.fromEntries(cols.map((c) => [c, r[c] ?? null])));
  }
  return { rows, total };
}

function checkWriteColumns(table, body, noteUnknown) {
  const allowed = schema[table];
  if (!allowed) return { code: '42P01', message: `relation "public.${table}" does not exist` };
  const rows = Array.isArray(body) ? body : [body];
  const bad = new Set();
  for (const r of rows) for (const k of Object.keys(r || {})) if (!allowed.includes(k)) bad.add(k);
  if (bad.size) {
    for (const c of bad) noteUnknown(table, c, 'write');
    return { code: 'PGRST204', message: `Could not find the '${[...bad][0]}' column of '${table}' in the schema cache` };
  }
  return null;
}

// ---------------------------------------------------------------------------
// Server
// ---------------------------------------------------------------------------

const noteUnknown = (table, column, direction) => {
  const entry = `${table}.${column} (${direction})`;
  if (!unknownColumns.includes(entry)) unknownColumns.push(entry);
  console.error(`[fake] UNKNOWN COLUMN ${entry} — rejected, as PostgREST would`);
};

function body(req) {
  return new Promise((resolve) => {
    let data = '';
    req.on('data', (c) => (data += c));
    req.on('end', () => {
      try { resolve(data ? JSON.parse(data) : null); } catch { resolve(null); }
    });
  });
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://127.0.0.1:${PORT}`);
  const send = (status, payload, extraHeaders = {}) => {
    const text = payload === null ? '' : JSON.stringify(payload);
    res.writeHead(status, {
      'content-type': 'application/json; charset=utf-8',
      'access-control-allow-origin': '*',
      'access-control-allow-headers': '*',
      'access-control-expose-headers': 'content-range',
      'access-control-allow-methods': 'GET,POST,PATCH,DELETE,HEAD,OPTIONS',
      ...extraHeaders,
    });
    res.end(req.method === 'HEAD' ? '' : text);
  };

  log.push({ method: req.method, path: url.pathname, search: url.search });

  if (req.method === 'OPTIONS') return send(204, null);

  // ---- Auth -------------------------------------------------------------
  if (url.pathname === '/auth/v1/health') return send(200, { name: 'GoTrue', version: 'local-e2e' });

  if (url.pathname === '/auth/v1/settings') {
    return send(200, { external: { email: true }, disable_signup: false, mailer_autoconfirm: true });
  }

  if (url.pathname === '/auth/v1/token') {
    const grant = url.searchParams.get('grant_type');
    const b = await body(req);
    if (grant === 'password') {
      const user = authUsers.find((u) => u.email === String(b?.email || '').toLowerCase());
      if (!user || b?.password !== PASSWORD) {
        return send(400, { error: 'invalid_grant', error_description: 'Invalid login credentials' });
      }
      return send(200, session(user));
    }
    if (grant === 'refresh_token') {
      const user = [...sessions.values()][0];
      if (!user) return send(400, { error: 'invalid_grant', error_description: 'Invalid Refresh Token' });
      return send(200, session(user));
    }
    return send(400, { error: 'unsupported_grant_type' });
  }

  if (url.pathname === '/auth/v1/user') {
    const user = bearer(req);
    if (!user) return send(401, { code: 401, message: 'invalid claim: missing sub claim' });
    return send(200, user);
  }

  // Admin user management, used by /api/admin/provision. Staff accounts can no
  // longer be created from the browser — a signup may not choose its own role —
  // so this is the path a commander's provisioning actually takes.
  if (url.pathname === '/auth/v1/admin/users' && req.method === 'POST') {
    const b = await body(req);
    const email = String(b?.email || '').toLowerCase();
    if (authUsers.some((u) => u.email === email)) {
      return send(422, { code: 'email_exists', message: 'A user with this email address has already been registered' });
    }
    const user = {
      id: crypto.randomUUID(),
      aud: 'authenticated',
      role: 'authenticated',
      email,
      email_confirmed_at: new Date().toISOString(),
      phone: '',
      app_metadata: { provider: 'email', providers: ['email'] },
      user_metadata: b?.user_metadata ?? {},
      identities: [],
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
      is_anonymous: false,
    };
    authUsers.push(user);
    // The database trigger creates the profile, as a CITIZEN whatever the
    // metadata asked for. Modelling that here is the point: if the route stopped
    // setting the role afterwards, the account would silently be a citizen and
    // the run would catch it.
    tables.profiles.push({
      id: user.id,
      email,
      full_name: b?.user_metadata?.full_name ?? 'User',
      role: 'CITIZEN',
      badge_number: null,
      agency: null,
      tier: null,
      geo_lga: null,
      geo_ward: null,
      geo_pu: null,
      phone: b?.user_metadata?.phone ?? null,
      fcm_token: null,
      push_enabled: true,
      profile_complete: false,
      is_active: true,
      last_seen: null,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    });
    return send(200, { user });
  }

  if (url.pathname.startsWith('/auth/v1/admin/users/') && req.method === 'DELETE') {
    const id = url.pathname.split('/').pop();
    const i = authUsers.findIndex((u) => u.id === id);
    if (i >= 0) authUsers.splice(i, 1);
    tables.profiles = tables.profiles.filter((p) => p.id !== id);
    return send(200, {});
  }

  if (url.pathname === '/auth/v1/logout') {
    const h = (req.headers.authorization || '').replace(/^Bearer\s+/i, '');
    sessions.delete(h);
    return send(204, null);
  }

  // ---- PostgREST --------------------------------------------------------
  if (url.pathname.startsWith('/rest/v1/')) {
    const table = url.pathname.slice('/rest/v1/'.length);
    const single = String(req.headers.accept || '').includes('vnd.pgrst.object');

    if (req.method === 'GET' || req.method === 'HEAD') {
      const r = query(table, url.searchParams, noteUnknown);
      if (r.error) return send(400, r.error);
      const wantsCount = String(req.headers.prefer || '').includes('count=');
      const headers = wantsCount
        ? { 'content-range': `0-${Math.max(r.total - 1, 0)}/${r.total}` }
        : {};
      if (single) {
        if (r.rows.length !== 1) {
          return send(406, {
            code: 'PGRST116',
            message: `JSON object requested, multiple (or no) rows returned`,
          });
        }
        return send(200, r.rows[0], headers);
      }
      return send(200, r.rows, headers);
    }

    if (req.method === 'POST' || req.method === 'PATCH') {
      const b = await body(req);
      const err = checkWriteColumns(table, b, noteUnknown);
      if (err) return send(400, err);
      const rows = Array.isArray(b) ? b : [b];
      // Which key made the write, so a run can tell a browser write from a
      // server one. "The browser must never set a role" is only checkable if
      // the two are distinguishable, and they are: the service key never
      // reaches a browser (supabase-server.ts is import-guarded).
      const key = req.headers.apikey
        || (req.headers.authorization || '').replace(/^Bearer\s+/i, '');
      writes.push({
        table,
        method: req.method,
        rows,
        filters: url.search,
        viaServiceKey: String(key).includes('service'),
      });

      if (req.method === 'PATCH') {
        // Apply the patch to the in-memory fixture so a screenshot taken after
        // an action shows the board the action produced.
        const r = query(table, url.searchParams, noteUnknown);
        if (r.error) return send(400, r.error);
        const ids = new Set(r.rows.map((x) => x.id));
        for (const row of tables[table] || []) {
          if (ids.has(row.id)) Object.assign(row, rows[0]);
        }
        return send(200, [...ids].map((id) => (tables[table] || []).find((x) => x.id === id)));
      }

      const created = rows.map((r) => ({
        id: r.id || crypto.randomUUID(),
        created_at: new Date().toISOString(),
        ...r,
      }));
      if (tables[table]) tables[table].push(...created);
      return send(201, single ? created[0] : created);
    }

    if (req.method === 'DELETE') {
      const r = query(table, url.searchParams, noteUnknown);
      if (r.error) return send(400, r.error);
      const ids = new Set(r.rows.map((x) => x.id));
      if (tables[table]) {
        tables[table] = tables[table].filter((x) => !ids.has(x.id));
      }
      writes.push({ table, method: 'DELETE', rows: [...ids], filters: url.search });
      return send(200, []);
    }
  }

  // ---- Storage (media URLs are rendered, not uploaded, in this run) ------
  if (url.pathname.startsWith('/storage/v1/')) return send(200, []);

  send(404, { message: `no route for ${req.method} ${url.pathname}` });
});

// ---- Realtime -------------------------------------------------------------
// Without this the console's three subscriptions sit in CHANNEL_ERROR, and the
// board renders in its "connection lost" state — which would make every
// screenshot a picture of a broken socket rather than of the screen.
let WebSocketServer;
try {
  ({ WebSocketServer } = require(path.join(
    __dirname, '..', '..', 'hq-dashboard-next', 'node_modules', 'ws',
  )));
} catch {
  console.error('[fake] ws not resolvable — realtime will not be served');
}

if (WebSocketServer) {
  const wss = new WebSocketServer({ server, path: '/realtime/v1/websocket' });
  wss.on('connection', (ws) => {
    ws.on('message', (raw) => {
      let msg;
      try { msg = JSON.parse(raw.toString()); } catch { return; }
      const { topic, event, ref, payload } = msg;
      if (event === 'phx_join') {
        // Echo the requested postgres_changes back as accepted, with ids, which
        // is what the client waits for before reporting SUBSCRIBED.
        const requested = payload?.config?.postgres_changes || [];
        ws.send(JSON.stringify({
          topic, ref, event: 'phx_reply',
          payload: {
            status: 'ok',
            response: { postgres_changes: requested.map((c, i) => ({ ...c, id: i + 1 })) },
          },
        }));
        return;
      }
      if (event === 'heartbeat') {
        ws.send(JSON.stringify({ topic: 'phoenix', ref, event: 'phx_reply', payload: { status: 'ok', response: {} } }));
      }
    });
  });
}

server.listen(PORT, '127.0.0.1', () => {
  console.log(`[fake] Supabase stand-in on http://127.0.0.1:${PORT}`);
  console.log(`[fake] ${Object.keys(schema).length} tables from migrations, strict column checking ON`);
});

// The capture script asks for these over a control endpoint rather than by
// parsing stdout, so an assertion failure is a value, not a grep.
const control = http.createServer((req, res) => {
  // A run starts from a clean record. Without this, anything a human poked at
  // the fake with beforehand — a curl testing the 400 path, say — is reported
  // as something the application did.
  if (req.url === '/reset' || req.url === '/reset-data') {
    log.length = 0;
    unknownColumns.length = 0;
    writes.length = 0;
    if (req.url === '/reset-data') {
      const fresh = JSON.parse(JSON.stringify(PRISTINE));
      for (const name of Object.keys(tables)) {
        tables[name].length = 0;
        tables[name].push(...fresh[name]);
      }
    }
    res.writeHead(200, { 'content-type': 'application/json' });
    return res.end('{"reset":true}');
  }
  res.writeHead(200, { 'content-type': 'application/json' });
  res.end(JSON.stringify({ log, unknownColumns, writes }, null, 1));
});
control.listen(PORT + 1, '127.0.0.1');
