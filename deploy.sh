#!/usr/bin/env bash
# ============================================================
# Operation Rainbow — pre-deploy check for the HQ console
# ============================================================
#
# This does NOT deploy. Railway builds and deploys on push to the tracked
# branch, so there is no deploy command to run from here and a script that
# pretended otherwise would be a second, divergent way to ship.
#
# What it does is everything that is worth knowing BEFORE the push, locally,
# where a failure costs seconds instead of a remote build and a rollback:
#
#   1. the three environment values the console cannot start without;
#   2. the production build, exactly as Railway runs it (`npm ci && npm run
#      build` — from hq-dashboard-next/railway.json);
#   3. a scan of the built CLIENT bundle for server secrets.
#
# Run it, read it, then `git push`. Railway takes it from there.
#
#   ./deploy.sh
#
# ## It used to deploy, to somewhere that is no longer the target
#
# Until this rewrite it ran `firebase deploy --only apphosting` against the
# Firebase App Hosting backend `rainbow-hq` in project `rainbow-97f1e`. The
# deployment has since moved to Railway, and the repository was carrying BOTH
# configurations — `firebase.json` plus `hq-dashboard-next/apphosting.yaml` on
# one side, `hq-dashboard-next/railway.json` plus `docs/RAILWAY.md` on the
# other — each documented as if it were the live one. Anybody told to
# "redeploy" had even odds of shipping to a dead target and watching a stale
# console answer requests. The App Hosting files are gone; this is the only
# deploy path, and `scripts/check_one_deploy_target.py` fails CI if a second
# one reappears.
#
# ## The one protection that moving to Railway cost us
#
# Firebase App Hosting can mark a secret RUNTIME-only, so the service role key
# was not present during `next build` at all. Railway exposes every service
# variable to the build. A variable being available is not the same as it being
# referenced from client code — but the structural guarantee is gone, and what
# remains is code-level:
#
#   * `src/lib/supabase-server.ts` opens with `import 'server-only'`, which
#     makes it a BUILD error for a client component to import it;
#   * `src/lib/env.ts` reads the key through `serverEnv()`, which throws where
#     `window` exists;
#   * and the scan in step 3 below, which is also a CI job.
#
# That scan is the thing standing between this deployment and finding C-1
# recurring — the service role key served to every visitor of /login. It is why
# this script still exists at all now that it cannot deploy.
# ============================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DASHBOARD="$ROOT/hq-dashboard-next"

log()  { printf '\n\033[0;34m▶ %s\033[0m\n' "$*"; }
ok()   { printf '\033[0;32m✓ %s\033[0m\n' "$*"; }
fail() { printf '\033[0;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

# ── 1. Environment ───────────────────────────────────────────────────────────
log "Checking the environment the build needs"

command -v node >/dev/null || fail "node not found on PATH"
command -v npm  >/dev/null || fail "npm not found on PATH"
ok "node $(node -v), npm $(npm -v)"

# NEXT_PUBLIC_* values are inlined AT BUILD TIME, so a missing one is not a
# runtime warning — the app crashes on first render and serves
# <html id="__next_error__">. On Railway these are service variables and must
# exist before the build, not just at runtime.
: "${NEXT_PUBLIC_SUPABASE_URL:?must be set (see hq-dashboard-next/.env.example)}"
: "${NEXT_PUBLIC_SUPABASE_ANON_KEY:?must be set (see hq-dashboard-next/.env.example)}"
ok "Supabase public env present"

if [ -z "${SUPABASE_SERVICE_ROLE_KEY:-}" ]; then
  fail "SUPABASE_SERVICE_ROLE_KEY must be set — the API routes need it server-side.
       It must NOT be prefixed NEXT_PUBLIC_: that would ship it to every browser,
       which is exactly how it leaked before (E2E_AUDIT_REPORT.md C-1)."
fi
ok "Service role key present (server-side only)"

# A real PIN left in the environment of a non-production build re-publishes it.
# The quick-fill login presets are compiled out by NODE_ENV, but this is cheap
# to state and the failure is silent.
if [ -n "${NEXT_PUBLIC_DEV_DEMO_PIN:-}" ]; then
  fail "NEXT_PUBLIC_DEV_DEMO_PIN is set. Unset it: it is a NEXT_PUBLIC_ value and
       would be inlined into the bundle."
fi
ok "No demo PIN in the environment"

# ── 2. The build Railway runs ────────────────────────────────────────────────
log "Building the HQ console the way railway.json does"
npm --prefix "$DASHBOARD" ci
npm --prefix "$DASHBOARD" run build
ok "Build complete ($(du -sh "$DASHBOARD/.next" | cut -f1))"

# ── 3. Secret scan ───────────────────────────────────────────────────────────
# Same patterns as the CI job. `.next/static` is what the browser is served; a
# server secret appearing there is the C-1 defect, not a warning.
log "Scanning the client bundle for server secrets"
LEAKED=0
for PATTERN in 'sb_secret_[A-Za-z0-9_-]{16,}' 'eyJhbGciOi[A-Za-z0-9_-]{20,}' 'SUPABASE_SERVICE_ROLE_KEY'; do
  if grep -rlE "$PATTERN" "$DASHBOARD/.next/static/" 2>/dev/null; then
    printf '\033[0;31m  /%s/ matched in the client bundle\033[0m\n' "$PATTERN" >&2
    LEAKED=1
  fi
done
[ "$LEAKED" -eq 0 ] || fail "STOP: a server secret is present in the client bundle.
       Do not push. This is finding C-1 recurring."
ok "No server secrets in the client bundle"

cat <<'EOF'

────────────────────────────────────────────────────────────────────────────
Clear to push. Railway builds on push to the tracked branch.

  git push

Then, in Railway: watch the deploy log, and confirm the health check on
/login goes green (railway.json sets a 60s timeout).

Settings that live in the Railway UI and not in this repository — get these
wrong and the build fails in a way the repo cannot explain:

  Root Directory          hq-dashboard-next   ← the Flutter app is at the root
  NEXT_PUBLIC_SUPABASE_URL, NEXT_PUBLIC_SUPABASE_ANON_KEY,
  SUPABASE_SERVICE_ROLE_KEY                   ← needed AT BUILD time

docs/RAILWAY.md is the full runbook, including the URL, custom domains and
the escalation notification worker.

Still needs a human after the deploy:
  • node scripts/verify_rls.js            (against STAGING, never production)
  • confirm /login renders and /dashboard redirects without a session
────────────────────────────────────────────────────────────────────────────
EOF
