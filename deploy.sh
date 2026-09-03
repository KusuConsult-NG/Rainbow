#!/usr/bin/env bash
# ============================================================
# Operation Rainbow — production deploy
# ============================================================
#
# Rewritten during the E2E audit. The previous version could not run anywhere
# except one developer's laptop, and would have failed even there:
#
#   1. It hardcoded NODE_BIN=/Users/mac/nodejs/... — a macOS path on one machine.
#   2. It ran `du -sh hq-dashboard-next/out`, but `out/` stopped being produced
#      when static export was removed from next.config.ts. Under `set -e` the
#      deploy aborted at that line.
#   3. It invoked `firebase deploy --only hosting|firestore:rules|functions`
#      with no firebase.json in the repo, so no target could resolve.
#
# It also deployed Firestore rules and Cloud Functions for a backend the app no
# longer uses — the mobile app is on Supabase and has no Firebase dependency in
# pubspec.yaml. Those steps are gone. If the Firebase stack is still live, it
# needs its own script and its own firebase.json.

set -euo pipefail

PROJECT="${FIREBASE_PROJECT:-rainbow-97f1e}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DASHBOARD="$ROOT/hq-dashboard-next"

log()  { printf '\n\033[0;34m▶ %s\033[0m\n' "$*"; }
ok()   { printf '\033[0;32m✓ %s\033[0m\n' "$*"; }
fail() { printf '\033[0;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

# ── Preflight ────────────────────────────────────────────────────────────────
log "Preflight"

command -v node >/dev/null || fail "node not found on PATH"
command -v npm  >/dev/null || fail "npm not found on PATH"
ok "node $(node -v), npm $(npm -v)"

# Fail before building rather than shipping a dashboard that cannot reach its
# backend. These are read at build time and baked into the bundle.
: "${NEXT_PUBLIC_SUPABASE_URL:?must be set (see hq-dashboard-next/.env.example)}"
: "${NEXT_PUBLIC_SUPABASE_ANON_KEY:?must be set (see hq-dashboard-next/.env.example)}"
ok "Supabase public env present"

if [ -z "${SUPABASE_SERVICE_ROLE_KEY:-}" ]; then
  fail "SUPABASE_SERVICE_ROLE_KEY must be set — the API routes need it server-side.
       It must NOT be prefixed NEXT_PUBLIC_: that would ship it to every browser,
       which is exactly how it leaked before (E2E_AUDIT_REPORT.md C-1)."
fi
ok "Service role key present (server-side only)"

# ── Build ────────────────────────────────────────────────────────────────────
log "Building HQ dashboard"
npm --prefix "$DASHBOARD" ci
npm --prefix "$DASHBOARD" run build
ok "Build complete ($(du -sh "$DASHBOARD/.next" | cut -f1))"

# ── Secret scan ──────────────────────────────────────────────────────────────
# Same guard as CI. A deploy must never ship a server secret in a client chunk.
log "Scanning client bundle for leaked secrets"
LEAKED=0
for PATTERN in 'sb_secret_[A-Za-z0-9_-]{16,}' 'eyJhbGciOi[A-Za-z0-9_-]{20,}' 'SUPABASE_SERVICE_ROLE_KEY'; do
  if grep -rlE "$PATTERN" "$DASHBOARD/.next/static/" 2>/dev/null; then
    printf '\033[0;31m  /%s/ matched in the client bundle\033[0m\n' "$PATTERN" >&2
    LEAKED=1
  fi
done
[ "$LEAKED" -eq 0 ] || fail "ABORTING: a server secret is present in the client bundle."
ok "No server secrets in client bundle"

# ── Deploy ───────────────────────────────────────────────────────────────────
log "Deploying HQ dashboard"

# App Hosting, not Hosting. `firebase deploy --only hosting` serves static
# files; this console must run as a Node server or Next.js middleware — which is
# the entire auth guard — is dropped and every page is served to anonymous
# visitors with no error anywhere.
[ -f "$ROOT/firebase.json" ] || fail "firebase.json is missing; nothing to deploy to."
[ -f "$DASHBOARD/apphosting.yaml" ] || fail "hq-dashboard-next/apphosting.yaml is missing."

command -v firebase >/dev/null || fail "firebase CLI not found on PATH"

# The build above already proved the public env is present locally. On App
# Hosting it comes from Secret Manager, and a missing secret fails the remote
# build with a message about the variable rather than about access — so check
# the grants are in place before spending a build on it.
log "Checking Secret Manager access"
for SECRET in supabase-url supabase-anon-key supabase-service-role-key; do
  if ! firebase apphosting:secrets:describe "$SECRET" --project "$PROJECT" >/dev/null 2>&1; then
    fail "Secret '$SECRET' is not readable by App Hosting in $PROJECT.
       Create it and grant access — see hq-dashboard-next/apphosting.yaml,
       which lists the exact commands. Deploying without it produces a console
       that builds and cannot reach its database."
  fi
done
ok "All three required secrets are accessible"

firebase deploy --only apphosting --project "$PROJECT"
ok "Deploy complete"

cat <<'EOF'

Post-deploy checklist (not automated — these need a human):
  • Confirm RLS is enforced:  node scripts/verify_rls.js
  • Confirm no credential in this deploy has been leaked previously; rotate if so.
EOF
