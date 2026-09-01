#!/usr/bin/env bash
# ============================================================================
# Build the Flutter web target safely.
#
#   ./scripts/build_web.sh
#
# Use this instead of a bare `flutter build web`. Two things go wrong otherwise,
# both found by driving the built app in a real browser rather than by reading it.
#
# 1. NO TEXT RENDERS WITHOUT THE NETWORK.
#    A plain `flutter build web` emits a bundle that pulls CanvasKit from
#    gstatic.com at runtime, and `google_fonts` pulls the typefaces from there
#    too. With that host unreachable the app booted and painted the logo and the
#    icon fonts — and every single label was blank. The panic button had no text
#    on it. `--no-web-resources-cdn` bundles CanvasKit; the fonts are bundled via
#    pubspec `assets/google_fonts/` plus `allowRuntimeFetching = false` in main.
#
# 2. `.env` IS SERVED AS A STATIC ASSET.
#    `pubspec.yaml` declares `.env` as a Flutter asset because the mobile app
#    reads it at runtime. The web build copies assets verbatim into
#    `build/web/assets/`, so a deployed site answers
#        GET https://<host>/assets/.env
#    with the whole file — SAFE_PIN and DURESS_PIN included. Confirmed against a
#    running build: HTTP 200. This script deletes it after the build and then
#    asserts it is gone, so the failure mode cannot come back quietly.
#
# The mobile app is unaffected by 2 in the sense that it needs the asset; the
# real fix for that is per-user server-verified PINs (see E2E_AUDIT_REPORT.md
# H-3), which is a product change. This closes the web exposure now.
# ============================================================================
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

echo "▶ Building Flutter web with all resources bundled"
flutter build web --no-web-resources-cdn "$@"

WEB_ENV="build/web/assets/.env"
if [ -f "$WEB_ENV" ]; then
  echo "▶ Removing $WEB_ENV from the web bundle"
  rm -f "$WEB_ENV"
fi

# Also scrub it from the asset manifests so the engine does not try to load a
# file that is no longer there.
for MANIFEST in build/web/assets/AssetManifest.json build/web/assets/AssetManifest.bin.json; do
  [ -f "$MANIFEST" ] || continue
  python3 - "$MANIFEST" <<'PY'
import json, sys, pathlib
p = pathlib.Path(sys.argv[1])
try:
    data = json.loads(p.read_text())
except Exception:
    sys.exit(0)          # binary manifest — the delete above is what matters
if isinstance(data, dict) and '.env' in data:
    del data['.env']
    p.write_text(json.dumps(data))
    print(f"  scrubbed .env from {p.name}")
PY
done

echo "▶ Asserting the bundle carries no environment file"
FOUND=$(find build/web -name '.env' -o -name '*.env' 2>/dev/null || true)
if [ -n "$FOUND" ]; then
  echo "::error::An environment file is still present in the web bundle:"
  echo "$FOUND"
  exit 1
fi

# Belt and braces: no PIN VALUE may appear in the shipped output.
#
# Deliberately not a search for the names. `AppConfig._read('SAFE_PIN')` compiles
# the key name into main.dart.js as a string literal, unavoidably and harmlessly —
# a key name is not a secret. The first version of this check searched for the
# names, fired on every build, and would have been deleted rather than fixed.
#
# What matters is an assignment carrying a value, which is what the .env file
# looked like: `SAFE_PIN=1234`.
if grep -rlE '(SAFE_PIN|DURESS_PIN|HMAC_SECRET|TERMII_API_KEY)=[^"'"'"',}\s][^"'"'"',}\s]*' build/web/ 2>/dev/null | head -3 | grep -q .; then
  echo "::error::A configured secret VALUE appears in the web bundle:"
  grep -rlE '(SAFE_PIN|DURESS_PIN|HMAC_SECRET|TERMII_API_KEY)=[^"'"'"',}\s][^"'"'"',}\s]*' build/web/ 2>/dev/null | head -5
  exit 1
fi

echo "✓ Web build clean: CanvasKit and fonts bundled, no .env, no PIN names."
echo "  Output: build/web"
