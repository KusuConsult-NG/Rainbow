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

# WHERE THE BROWSER IS.
#
# In CI `npm ci` downloads puppeteer's own Chrome and it resolves itself. A
# sandbox that sets PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 has a Chromium already
# and no puppeteer download, so every pass died at launch with "Could not find
# Chrome" — after the build, after the server was up, forty seconds in. The
# browser was on disk the whole time and the run needed one environment
# variable that nothing recorded.
#
# Resolved here, once, rather than left to whoever remembers to export it:
# an explicit PUPPETEER_EXECUTABLE_PATH wins, then puppeteer's own cache
# (CI), then a sandbox Chromium. Unset if none is found, so puppeteer reports
# its own error rather than this script inventing a worse one.
if [[ -z "${PUPPETEER_EXECUTABLE_PATH:-}" ]]; then
  # Puppeteer's own download, which is what CI has. Left to resolve itself:
  # it knows which build its version wants and this script must not guess.
  # The mac layouts are here because this script could not find a browser on a
  # Mac AT ALL — not the system Chrome, and not puppeteer's own download, which
  # unpacks to `chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/`
  # rather than to a bare `chrome`. Reported from a developer's machine after
  # it built the console, served it, and only then died at browser launch.
  shopt -s nullglob
  pcache="${PUPPETEER_CACHE_DIR:-$HOME/.cache/puppeteer}"
  puppeteer_own=("$pcache"/chrome*/*/chrome \
                 "$pcache"/chrome*/*/chrome-*/chrome \
                 "$pcache"/chrome*/*/chrome-mac*/*.app/Contents/MacOS/*)
  shopt -u nullglob
  if (( ${#puppeteer_own[@]} == 0 )); then
    for candidate in \
      /opt/pw-browsers/chromium \
      /usr/bin/chromium \
      /usr/bin/chromium-browser \
      /usr/bin/google-chrome \
      "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
      "/Applications/Chromium.app/Contents/MacOS/Chromium" \
      "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge" \
      "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser" \
      "$HOME/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    do
      # -f as well as -x: a DIRECTORY is executable, and passing one to
      # puppeteer fails with a confusing ENOENT rather than "not a browser".
      if [[ -f "$candidate" && -x "$candidate" ]]; then
        export PUPPETEER_EXECUTABLE_PATH="$candidate"
        echo "==> browser: $candidate (puppeteer has no download of its own)"
        break
      fi
    done
    if [[ -z "${PUPPETEER_EXECUTABLE_PATH:-}" ]]; then
      # Said here, in full, because the alternative is what used to happen:
      # a warning that predicted failure without saying how to avoid it, then
      # a minute of building the console, then puppeteer's own error.
      {
        echo "no browser found, and every browser pass needs one."
        echo
        echo "  download puppeteer's own (~150MB, once):"
        echo "    ( cd hq-dashboard-next && npx puppeteer browsers install chrome )"
        echo
        echo "  or point at one you already have:"
        echo "    export PUPPETEER_EXECUTABLE_PATH=/path/to/chrome"
        echo
        echo "stopping now rather than building the console first and failing at launch."
      } >&2
      exit 1
    fi
  fi
fi

# Is anything listening? No curl, no lsof: a bare TCP connect, which cannot be
# fooled by a server that answers 404.
port_busy() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null && exec 3<&- || return 1; }

# A SECOND RUN USED TO TEST THE FIRST RUN'S BUILD.
#
# `npm start` forks `sh -c next start`, so $NEXT_PID below was the WRAPPER and
# killing it left `next-server` holding :3000. On the next run `npm start` could
# not bind, exited, and the health check two lines down was satisfied by the
# server still running from last time — while `npm run build` had meanwhile
# replaced the `.next` directory underneath it. Every screen then rendered blank
# and 30 of 46 checks failed, against code that was fine. Diagnosing that cost
# more than the run.
#
# Two changes. Next is started DIRECTLY so the PID is the server's own, and this
# script refuses to start at all if either port is taken, because a run that
# silently exercises the wrong build is worse than no run.
cleanup() {
  [[ -n "${FAKE_PID:-}" ]] && kill "$FAKE_PID" 2>/dev/null || true
  [[ -n "${NEXT_PID:-}" ]] && kill "$NEXT_PID" 2>/dev/null || true
  # Next spawns workers; give the group a moment, then say so rather than
  # leaving the next run to discover it.
  for _ in $(seq 1 20); do
    port_busy "$PORT" || port_busy "$FAKE_PORT" || return 0
    sleep 0.5
  done
  port_busy "$PORT" && echo "WARNING: something is still listening on :$PORT — kill it before the next run" >&2
  port_busy "$FAKE_PORT" && echo "WARNING: something is still listening on :$FAKE_PORT" >&2
  return 0
}
trap cleanup EXIT

for occupied in "$PORT" "$FAKE_PORT"; do
  if port_busy "$occupied"; then
    echo "127.0.0.1:$occupied is already in use." >&2
    echo "This run would not be able to bind it, and the health checks below" >&2
    echo "would be answered by whatever is there — most likely a server left" >&2
    echo "over from an earlier run, serving a build this one has replaced." >&2
    echo "Stop it first:  pkill -f next-server ; pkill -f fake_supabase.js" >&2
    exit 1
  fi
done

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
#
# `next` directly rather than `npm start`: npm forks a shell, and killing the
# shell leaves the server running on the port — see cleanup() above.
./node_modules/.bin/next start -p "$PORT" &
NEXT_PID=$!

for _ in $(seq 1 60); do
  curl -sf --noproxy '*' -o /dev/null "http://127.0.0.1:$PORT/login" && break
  sleep 0.5
done
curl -sf --noproxy '*' -o /dev/null "http://127.0.0.1:$PORT/login" \
  || { echo "the console never came up"; exit 1; }


# EVERY PASS RUNS, EVEN AFTER ONE FAILS.
#
# Each pass exits non-zero on a failed check, and under `set -e` the first one
# ended the run — so a broken console control meant the handset screens were
# never rendered at all, and a 35-minute run bought one failure at a time. The
# passes are independent: what a console button writes says nothing about
# whether a handset screen renders. So they all run, the summary names every
# one that failed, and the script still exits non-zero.
FAILED_PASSES=()
pass() {
  local label="$1"; shift
  echo "==> $label"
  if "$@"; then
    return 0
  fi
  FAILED_PASSES+=("$label")
  echo "!!! $label FAILED — carrying on, so the rest of the evidence is still collected" >&2
  return 0
}

rm -rf "$OUT"
cd "$ROOT"
export E2E_OUT="$OUT"
export CONSOLE_URL="http://127.0.0.1:$PORT"

pass "driving it in a browser: every screen, every role" \
  node scripts/local_e2e/capture.js

# Separate from the screens pass on purpose. `capture.js` answers "does it
# render?"; this answers "does it do anything?" — and a button that looks right,
# logs nothing and writes nothing is invisible to a screenshot.
pass "pressing the buttons" node scripts/local_e2e/interact.js

# ── The mobile app ───────────────────────────────────────────────────────────
#
# Flutter's web target builds the same widget tree from the same Dart, so the
# app's screens can be rendered here. Skipped rather than failed when the SDK is
# absent: this script's first job is the console, and a missing Flutter should
# not stop that being checked.
if command -v flutter >/dev/null 2>&1; then
  echo "==> building the mobile app for the browser"

  # One script, shared with the CI job, so the two cannot drift again.
  "$ROOT/scripts/local_e2e/provision_env.sh"

  cd "$ROOT"
  flutter pub get
  # --no-web-resources-cdn keeps CanvasKit local; the gstatic copy is blocked
  # here and an app that never paints photographs as a blank page.
  # --dart-define points the build at the stand-in: the project URL is
  # otherwise compiled in, and it is production's.
  flutter build web --release --no-web-resources-cdn \
    --dart-define=SUPABASE_URL="http://127.0.0.1:$FAKE_PORT" \
    --dart-define=SUPABASE_ANON_KEY=local-e2e-anon-key-not-a-real-credential

  pass "rendering the mobile screens at phone size" \
    node scripts/local_e2e/mobile_capture.js

  pass "using the mobile app: SOS, AI report, every category, every button" \
    node scripts/local_e2e/mobile_interact.js

  # Separate because it needs a synthetic capture device. Every other pass must
  # keep behaving as a device whose camera is unavailable.
  pass "the live camera/microphone stream, and the citizen settings" \
    node scripts/local_e2e/user_features.js

  pass "the messaging round trip" node scripts/local_e2e/chat_thread.js

  # The tier-specific controls are the ones that matter and the ones the
  # general sweep could not reach: it ran as a plain `responder`, which is the
  # single account whose tier-specific controls do not exist.
  pass "every control on the responder dashboard, as every tier" \
    node scripts/local_e2e/tier_controls.js

  # Separate again, and for the same reason the interaction pass is separate
  # from the screens pass. The two above prove each screen renders and each
  # control does something; this proves ONE incident travels the whole chain —
  # which is a claim about the system, not about a screen, and is the only pass
  # that can catch a rung that works in isolation and drops the handover.
  pass "the whole command chain: citizen -> PU -> WARD -> LGA -> HQ -> responder" \
    node scripts/local_e2e/chain_lifecycle.js
  MOBILE_RAN=yes
else
  MOBILE_RAN=no
  echo "==> flutter not installed — skipping the mobile screens"
  echo '    That is the half that renders the handset. "flutter --version"'
  echo '    must work in THIS shell, or you are only checking the console.'

fi

# A RUN THAT CANNOT TELL YOU IT FINISHED.
#
# The last line of this script used to be the `fi` above. After thirty-five
# minutes it printed nothing: no count, no location, no verdict — and the
# control sweep before it is silent for about fifteen minutes, so there was no
# way to tell a finished run from a hung one without listing a directory. It
# was asked, in exactly those words, by somebody watching it.
echo
echo "========================================================================"
if (( ${#FAILED_PASSES[@]} )); then
  echo "FAILED: ${#FAILED_PASSES[@]} pass(es) reported a failing check"
  for label in "${FAILED_PASSES[@]}"; do
    echo "  - $label"
  done
  echo
  echo "Each pass printed its own FAILED list above; search back for 'FAILED:'."
else
  echo "PASSED: every pass that ran reported all checks passing"
fi
shots=$(find "$OUT" -name '*.png' 2>/dev/null | wc -l | tr -d ' ')
echo
echo "$shots screenshots in $OUT"
echo "  report.json        — the screens pass"
echo "  interactions.json  — the controls pass"
if [[ "$MOBILE_RAN" == yes ]]; then
  echo "console and handset both exercised"
else
  echo "CONSOLE ONLY — the handset half was skipped (no flutter on PATH)"
fi
echo "not proven here: row-level security (the stand-in applies none), and"
echo "that the real OpenStreetMap tiles render (they are served locally)."
echo "========================================================================"

(( ${#FAILED_PASSES[@]} == 0 ))
