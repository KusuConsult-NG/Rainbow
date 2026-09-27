#!/usr/bin/env bash
#
# The whole local end-to-end run: a stand-in Supabase, a real production build
# of the console, a real browser, and a screenshot of every screen.
#
#   ./scripts/local_e2e/run.sh
#
# Needs nothing from outside this machine — no Supabase project, no
# credentials, no network. That is the point: every console screen in this
# repository had never been rendered before this script existed, because
# rendering one appeared to need a live backend.
#
# It proves the screens. It does NOT prove row-level security: the fake answers
# every query, and policies can only be tested against a real PostgREST by
# `scripts/verify_rls.js` against a staging project.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONSOLE="$ROOT/hq-dashboard-next"
PORT="${CONSOLE_PORT:-3000}"
FAKE_PORT="${FAKE_SUPABASE_PORT:-54321}"
OUT="${E2E_OUT:-$ROOT/local_e2e_screenshots}"

# Loopback must not go through a proxy, or every request to the fake leaves the
# machine and comes back as a 403.
export NO_PROXY="127.0.0.1,localhost"
export no_proxy="127.0.0.1,localhost"

cleanup() {
  [[ -n "${FAKE_PID:-}" ]] && kill "$FAKE_PID" 2>/dev/null || true
  [[ -n "${NEXT_PID:-}" ]] && kill "$NEXT_PID" 2>/dev/null || true
}
trap cleanup EXIT

echo "==> Supabase stand-in on :$FAKE_PORT"
node "$ROOT/scripts/local_e2e/fake_supabase.js" &
FAKE_PID=$!

for _ in $(seq 1 30); do
  curl -sf --noproxy '*' "http://127.0.0.1:$FAKE_PORT/auth/v1/health" >/dev/null && break
  sleep 0.5
done
curl -sf --noproxy '*' "http://127.0.0.1:$FAKE_PORT/auth/v1/health" >/dev/null \
  || { echo "the stand-in never answered"; exit 1; }

echo "==> building the console against it"
# Written fresh every run: NEXT_PUBLIC_* are inlined at BUILD time, so a build
# carrying a previous run's URL would talk to the wrong place with no error.
cat > "$CONSOLE/.env.local" <<EOF
NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:$FAKE_PORT
NEXT_PUBLIC_SUPABASE_ANON_KEY=local-e2e-anon-key-not-a-real-credential
SUPABASE_SERVICE_ROLE_KEY=local-e2e-service-key-not-a-real-credential
EOF

cd "$CONSOLE"
[[ -d node_modules ]] || npm ci
npm run build

echo "==> serving it on :$PORT"
# A production build, not `next dev`. The guard is Next's proxy, and the thing
# being tested is what a deployed server does.
PORT="$PORT" npm start &
NEXT_PID=$!

for _ in $(seq 1 60); do
  curl -sf --noproxy '*' -o /dev/null "http://127.0.0.1:$PORT/login" && break
  sleep 0.5
done
curl -sf --noproxy '*' -o /dev/null "http://127.0.0.1:$PORT/login" \
  || { echo "the console never came up"; exit 1; }

echo "==> driving it in a browser"
rm -rf "$OUT"
cd "$ROOT"
CONSOLE_URL="http://127.0.0.1:$PORT" E2E_OUT="$OUT" node scripts/local_e2e/capture.js
