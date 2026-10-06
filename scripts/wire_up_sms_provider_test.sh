#!/usr/bin/env bash
# ============================================================================
# The SMS probe classifier must read every response shape correctly.
#
#   ./scripts/wire_up_sms_provider_test.sh
#
# No network, no credentials, nothing deployed: it sources the classifier out of
# wire_up_sms_provider.sh and feeds it each status/body pair the real endpoint
# can produce.
#
# Why this is worth a test of its own. The whole value of `--check` is telling
# two 401s apart:
#
#   * the PLATFORM refusing the call because the function was deployed with JWT
#     verification on — in which case the hook can never work, and the fix is a
#     redeploy;
#   * our own code refusing a bad signature — which is the HEALTHY state, and
#     the fix is nothing at all.
#
# Read the wrong way round, this diagnostic would send an operator to redeploy a
# correctly deployed function, or tell them a broken one is fine. Both bodies
# are JSON with a 401 status; only the shape differs. So the distinction is
# asserted here rather than assumed.
# ============================================================================
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO/scripts/wire_up_sms_provider.sh"
[ -f "$SRC" ] || { echo "missing $SRC" >&2; exit 2; }

# Pull in just the two classifiers. Sourcing the whole script would run it, so
# the function bodies are extracted. FN_URL is referenced by classify_get.
FN_URL='https://example00000000000.supabase.co/functions/v1/send-sms'
eval "$(awk '/^classify_get\(\) \{/,/^\}/' "$SRC")"
eval "$(awk '/^classify_post\(\) \{/,/^\}/' "$SRC")"

type classify_get  >/dev/null 2>&1 || { echo "could not load classify_get" >&2; exit 2; }
type classify_post >/dev/null 2>&1 || { echo "could not load classify_post" >&2; exit 2; }

FAILED=0
check() {  # check <what> <expected token> <actual line>
  local what="$1" want="$2" got="$3" tok="${3%% *}"
  if [ "$tok" = "$want" ]; then
    printf '  PASS  %-46s -> %s\n' "$what" "$tok"
  else
    printf '  FAIL  %-46s -> %s (wanted %s)\n' "$what" "$tok" "$want"
    printf '        full line: %s\n' "$got"
    FAILED=$((FAILED + 1))
  fi
}

echo "▶ GET probe"
# The platform's own refusal. No http_code field — that is the whole tell.
check "platform 401 (JWT verification left on)" JWT_ON \
  "$(classify_get 401 '{"code":401,"message":"Missing authorization header"}')"
check "platform 403" JWT_ON \
  "$(classify_get 403 '{"message":"Invalid JWT"}')"
# Our own bodies always carry error.http_code.
check "our 405 (POST only) — healthy" OK_REACHABLE \
  "$(classify_get 405 '{"error":{"http_code":405,"message":"send-sms accepts POST"}}')"
check "our 401 reached us" OK_REACHABLE \
  "$(classify_get 401 '{"error":{"http_code":401,"message":"signature did not verify"}}')"
check "not deployed" NOT_DEPLOYED "$(classify_get 404 'Function not found')"
check "connection refused" UNREACHABLE "$(classify_get 000 '')"
check "someone else's 405" ODD_405 "$(classify_get 405 '<html>405</html>')"
check "unexpected 500" UNEXPECTED_500 "$(classify_get 500 'boom')"

echo "▶ POST probe (invalid signature on purpose)"
check "secret unset" NO_SECRET \
  "$(classify_post 503 '{"error":{"http_code":503,"message":"hook is not configured"}}')"
check "only the legacy secret name is set" LEGACY_SECRET \
  "$(classify_post 503 '{"error":{"http_code":503,"message":"hook secret is configured under the old name"}}')"
check "bad signature refused — healthy" OK_VERIFYING \
  "$(classify_post 401 '{"error":{"http_code":401,"message":"signature did not verify"}}')"
check "accepts an unsigned request — a hole" ACCEPTS_UNSIGNED \
  "$(classify_post 200 '{}')"
check "not deployed" NOT_DEPLOYED "$(classify_post 404 'Function not found')"
check "connection refused" UNREACHABLE "$(classify_post 000 '')"

# The two 401s are the point of the exercise: assert directly that they do not
# collapse into the same verdict.
PLATFORM=$(classify_get 401 '{"code":401,"message":"Missing authorization header"}')
OURS=$(classify_get 401 '{"error":{"http_code":401,"message":"nope"}}')
echo "▶ The two 401s stay distinct"
if [ "${PLATFORM%% *}" = "${OURS%% *}" ]; then
  echo "  FAIL  both 401s classified as ${PLATFORM%% *}"
  FAILED=$((FAILED + 1))
else
  echo "  PASS  ${PLATFORM%% *} vs ${OURS%% *}"
fi

# And the healthy pair must be the only combination the script treats as ready.
echo "▶ Only the healthy pair reads as ready"
G_OK=$(classify_get 405 '{"error":{"http_code":405,"message":"send-sms accepts POST"}}')
P_OK=$(classify_post 401 '{"error":{"http_code":401,"message":"bad sig"}}')
case "${G_OK}${P_OK}" in
  OK_REACHABLE*OK_VERIFYING*) echo "  PASS  the healthy pair matches the readiness pattern" ;;
  *) echo "  FAIL  the healthy pair does not match the pattern the script tests"
     FAILED=$((FAILED + 1)) ;;
esac
G_BAD=$(classify_get 401 '{"code":401}')
case "${G_BAD}${P_OK}" in
  OK_REACHABLE*OK_VERIFYING*) echo "  FAIL  a platform 401 still read as ready"
     FAILED=$((FAILED + 1)) ;;
  *) echo "  PASS  a platform 401 does not read as ready" ;;
esac

echo
if [ "$FAILED" -ne 0 ]; then
  echo "✗ $FAILED assertion(s) failed."
  exit 1
fi
echo "✓ the SMS probe classifier reads every response shape correctly."
