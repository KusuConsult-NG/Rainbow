# Deploying the HQ console on Railway

The console is an ordinary Next.js Node server, which is the deployment shape
Next supports fully — every feature works, including the middleware the auth
guard depends on. Railway needs almost nothing from this repository; what it
needs is written in `hq-dashboard-next/railway.json`, and the rest is four
settings in the Railway UI.

> **The one thing that must not be got wrong:** this is a **Node server**, never
> a static export. The `/dashboard` auth guard is Next.js middleware
> (`src/proxy.ts`), and a static export silently drops middleware — the console
> would then serve every page to anonymous visitors with no error anywhere
> saying so. `next build` + `next start` is a Node server. Do not add
> `output: 'export'` to `next.config.ts`.

---

## 1. Point the service at the right directory

This repository holds a Flutter app at the root and the console in a
subdirectory, so Railway must be told which one to build.

| setting | value |
|---|---|
| **Root Directory** | `hq-dashboard-next` |
| Builder | Nixpacks (the default; `railway.json` names it explicitly) |
| Build command | `npm ci && npm run build` |
| Start command | `npm run start` |
| Healthcheck path | `/login` |

Root Directory is a **service setting**, not something `railway.json` can
express — if it is left at the repository root, the build fails looking for a
`package.json` that describes the Flutter project's tooling instead.

`/login` is the healthcheck rather than `/`, because `/` is a redirect to it and
a 307 is not a health signal.

Nothing needs to be done about the port. `next start` defaults to hostname
`0.0.0.0` and reads `PORT` from the environment, which is exactly what Railway
provides.

---

## 2. Variables

Three are required. The console starts without the optional ones and disables
the corresponding feature rather than breaking.

```
NEXT_PUBLIC_SUPABASE_URL        https://<project>.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY   <anon key>
SUPABASE_SERVICE_ROLE_KEY       <service role key>
```

`NEXT_PUBLIC_*` are **inlined into the JavaScript bundle at `next build`**, so
they must exist before the build runs, not just at runtime. Railway exposes
service variables to the build, so setting them normally is enough — but a
console deployed with them missing fails on first render with
`<html id="__next_error__">` and no useful message, and the cause is always
this.

Optional, each disabling one feature when unset — see `.env.example` for what
each does:

```
SMS_GATEWAY_SECRET      inbound SMS from the offline fallback
MESH_HQ_PRIVATE_KEY     inbound mesh alerts (66 hex characters)
TERMII_API_KEY          outbound SOS escalation SMS
SOS_DISPATCH_PHONE      where that SMS goes
GEMINI_API_KEY          AI triage (falls back to the rule engine)
ONESIGNAL_APP_ID        push
ONESIGNAL_REST_API_KEY  push
RAINBOW_WEBHOOK_SECRET  outbound agency webhooks
```

### What Railway does not give us, that App Hosting did

Firebase App Hosting can mark a secret **RUNTIME only**, so the service role key
is not even present during `next build`. Railway exposes every service variable
to the build. That is not a leak by itself — a variable being available is not
the same as it being referenced from client code — but it does mean the
structural protection is gone and only the code-level one remains:

* `src/lib/supabase-server.ts` begins with `import 'server-only'`, which makes
  it a **build error** for a client component to import it;
* `src/lib/env.ts` reads the key through `serverEnv()`, which throws if called
  where `window` exists;
* and the CI job **Scan client bundle for leaked secrets** greps `.next/static`
  for key material after every build.

That third one is what would actually catch a regression, and it is the reason
finding C-1 — the service role key served to every visitor of `/login` — cannot
recur silently. **Keep it green.** If CI is not running, that protection is not
running either, and on Railway there is no second line of defence behind it.

You can run the same check by hand against a local build:

```bash
cd hq-dashboard-next && npm run build
grep -rlE 'sb_secret_[A-Za-z0-9_-]{16,}|eyJhbGciOi[A-Za-z0-9_-]{20,}' .next/static/ \
  && echo "LEAK" || echo "clean"
```

---

## 3. The URL

Railway assigns one when you generate a domain for the service — Settings →
Networking → **Generate Domain** — and it looks like
`https://<service>-production-<hash>.up.railway.app`. It is not knowable in
advance and is not recorded in this repository.

Once it exists:

| path | what it is |
|---|---|
| `/` | redirects to `/login` |
| `/login` | sign in |
| `/dashboard` | the console; redirects to `/login` without a verified session |

There is **no separate admin URL**. Staff provisioning, broadcast, audit,
uninstall requests and the agency portal are all tabs inside `/dashboard`.

### If you put a custom domain in front of it

Nothing in the console hardcodes its own origin, so a custom domain needs no
code change. Two things to check:

* Supabase → Authentication → URL Configuration: add the domain to the allowed
  redirect list, or email links come back to the wrong host.
* The CSP is issued per-request from `src/proxy.ts` with a nonce. It does not
  name a host, so it follows the domain automatically — but if you add a
  third-party script tag, it will be blocked until `src/lib/csp.ts` admits it,
  which is the intended behaviour and not a misconfiguration.

---

## 4. Before the first real deploy

The database must be applied first — the console reads columns that the
migrations add, and PostgREST rejects a query naming a column that does not
exist **in full**, so a missing migration reads as a blank screen rather than a
useful error. `docs/PRODUCTION_DEPLOYMENT.md` §1 covers it; on the production
project this was done on 2026-09-28 (25/25 PASS).

And make the first staff account, which cannot be done through the console —
`/api/admin/provision` requires a command role, and a fresh database has none.
The one-time SQL is in `docs/PRODUCTION_DEPLOYMENT.md`.

---

## Not deploy-verified

`railway.json` was written from the Railway schema and the Next.js self-hosting
guide, and nothing in the audit container can run `railway up`. The build it
describes — `npm ci && npm run build` — is the same one CI runs on every commit
and is known to succeed. The deploy itself is the test.
