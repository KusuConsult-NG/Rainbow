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
| Builder | leave as the default (Railpack detects Node) |
| Build command | `npm ci && npm run build` |
| Start command | `npm run start` |
| Healthcheck path | `/login` |

Root Directory is a **service setting**, not something `railway.json` can
express, and getting it wrong is the first thing that happens. Left at the
repository root, the build fails like this:

```
╭─────────────────╮
│ Railpack 0.40.0 │
╰─────────────────╯
  ⚠ Script start.sh not found
  ✖ Railpack could not determine how to build the app.
  ...
  The app contents that Railpack analyzed contains:
  ./
  ├── android/
  ├── hq-dashboard-next/
  ├── ios/
  ├── lib/
  ├── pubspec.yaml
```

Read that listing: it analysed the **Flutter project**. There is no
`package.json` at the repository root, so no language matched — and note that
`hq-dashboard-next/railway.json` was never read either, because Railway looks for
it inside the service's root directory. Until Root Directory is set, none of the
configuration in this repository applies.

Railway's current builder is **Railpack**, not Nixpacks. `railway.json` therefore
names no builder at all and lets the platform choose; pinning `"builder":
"NIXPACKS"` was wrong and is removed. Railpack detects Node from
`hq-dashboard-next/package.json` on its own, and the `build` and `start` scripts
are the ones Next.js expects.

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
MESH_HQ_PRIVATE_KEY     inbound mesh alerts (64 hex characters; the 66 is the PUBLIC half)
TERMII_API_KEY          outbound SOS escalation SMS
SOS_DISPATCH_PHONE      where that SMS goes
GEMINI_API_KEY          AI triage (falls back to the rule engine)
ONESIGNAL_APP_ID        push
ONESIGNAL_REST_API_KEY  push
RAINBOW_WEBHOOK_SECRET  outbound agency webhooks
NOTIFY_DRAIN_SECRET     the escalation notification worker (see below)
```

### The citizen OTP hook (Supabase, not Railway)

Citizens have no email and no password — the phone number IS the identity, and
`signInWithOtp(phone:)` needs Supabase to actually send an SMS. Supabase's
built-in providers are Twilio, MessageBird, Vonage and Textlocal. **Termii is
not one of them**, so the only way Supabase can send through Termii is a Send
SMS auth hook: `supabase/functions/send-sms`.

Until that function is deployed AND selected in the dashboard, no citizen can
sign in at all — the code is never sent, so there is nothing to type.

```
supabase functions deploy send-sms
supabase secrets set TERMII_API_KEY=... TERMII_SENDER_ID="OE Alert" HOOK_SECRET=...
```

Then **Authentication → Hooks → Send SMS hook → Edge Function → send-sms**, with
the same `HOOK_SECRET`.

`HOOK_SECRET` is not optional. The function refuses to run without it, because
an unauthenticated hook URL is an SMS relay: anyone who finds it can post a
phone number and have Termii send to it, billed to this account.

`ALLOW_UNSENT_OTP=true` is a staging-only escape hatch. With it set, a failure
to send answers 200 and auth proceeds; without it, a failure answers 500 so the
app can tell the person the code could not be sent. Do not set it in
production: answering 200 when no SMS went out tells the app the code is on its
way, and the citizen waits on a timer for a code that does not exist.

### The escalation notification worker

`escalate_overdue_alerts()` runs inside PostgreSQL every minute and climbs any
incident whose tier has held it longer than `app_config` allows. It writes the
move and a row in `notification_outbox` in ONE statement, so an escalation
cannot happen without a notice being owed.

Nothing in the database can make an HTTP call, and it should not try: a call
inside a transaction cannot be rolled back, and a failure inside one has
nowhere to live. So the queue is drained from outside, by
`POST /api/notify/drain`.

**Without a scheduler calling it, escalations still happen and nobody is
notified.** The rows accumulate; nothing is lost; but the phone does not ring,
which is the whole point of a timeout that fires at 02:00.

Add a Railway **cron service** in the same project, scheduled `* * * * *`:

```
curl -fsS -X POST https://<your-console-host>/api/notify/drain \
  -H "x-drain-secret: $NOTIFY_DRAIN_SECRET"
```

`NOTIFY_DRAIN_SECRET` is a shared secret you generate — `openssl rand -hex 32`
— set on BOTH the console service and the cron service. The endpoint refuses to
run at all when it is unset, rather than running unauthenticated: an open drain
endpoint lets anyone empty the queue, marking every row delivered with nobody
notified.

Running more than one worker is safe. `claim_notifications` uses
`FOR UPDATE SKIP LOCKED`, so two workers take different rows rather than both
sending everything.

To check it is working:

```sql
-- Should be small and falling. A growing number means nothing is draining.
select count(*) from notification_outbox where delivered_at is null;

-- Why anything failed.
select id, kind, attempts, last_error, next_attempt_at
  from notification_outbox
 where delivered_at is null and last_error is not null
 order by next_attempt_at;

-- And that the job feeding it is actually scheduled. The pg_cron block is
-- conditional, so the automation can be absent while every migration reports
-- success.
select * from escalation_automation_status();
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

## Deployed

The console is on Railway. This was written before the move, as config derived
from the Railway schema and the Next.js self-hosting guide, with "the deploy
itself is the test" where this paragraph now is — the deploy has since happened
and Railway is the live target.

Firebase App Hosting was the previous one and its config has been removed from
the repository (`firebase.json`, `.firebaserc`,
`hq-dashboard-next/apphosting.yaml`). Both sets of files were present at once for
a month, each documented as live, so a "redeploy" was a coin flip between a real
target and a dead one — and a stale console answering requests is
indistinguishable from a deploy that worked.
`scripts/check_one_deploy_target.py` fails CI if a second target reappears.

What still cannot be checked from this repository, and needs a human on the
Railway side after a deploy:

* the health check on `/login` going green — `railway.json` allows it 60s;
* `/dashboard` redirecting to `/login` without a verified session;
* `node scripts/verify_rls.js`, against **staging**, never production — it
  inserts a row.

## TURN_URL, and the live stream that never connected

`TURN_URL`, `TURN_USERNAME`, `TURN_CREDENTIAL` — set these, or the live stream
from a handset will usually fail to connect.

A WebRTC connection needs a path for the media. STUN only tells each peer what
its own public address looks like from outside; the media still has to travel
directly between them. A handset on a Nigerian mobile network is behind
carrier-grade NAT, which is commonly SYMMETRIC — it uses a different external
port per destination, so the address STUN reports is useless to a peer trying to
reach it, and hole punching fails. HQ, behind an office firewall, is no better
placed. When neither side can be reached directly the media has to be relayed,
and TURN is the only way WebRTC does that.

Until T-96 both sides carried three public STUN servers as literals and no
relay, so the stream connected when the network happened to allow it — and the
handset said "BROADCASTING LIVE TO HQ" either way. It now says CONNECTING until
the peer connection reports connected, and the console shows COULD NOT CONNECT
rather than STANDBY, so an unset relay is visible instead of silent.

The handset reads these from `.env` (see `lib/core/config/live_stream.dart`).
The console reads them server-side and serves the ICE list from
`/api/rtc/config`: a TURN credential must NOT be `NEXT_PUBLIC_*`, because that
is inlined into the browser bundle at build time — which is how this project
once served its Gemini key to every dashboard visitor.

No default is shipped. There is no public TURN server that works, and a
made-up credential fails exactly like no credential while looking configured.
