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
AUTH_URL='https://example00000000000.supabase.co/auth/v1/settings'
eval "$(awk '/^classify_get\(\) \{/,/^\}/' "$SRC")"
eval "$(awk '/^classify_post\(\) \{/,/^\}/' "$SRC")"
eval "$(awk '/^classify_auth\(\) \{/,/^\}/' "$SRC")"

type classify_get  >/dev/null 2>&1 || { echo "could not load classify_get" >&2; exit 2; }
type classify_post >/dev/null 2>&1 || { echo "could not load classify_post" >&2; exit 2; }
type classify_auth >/dev/null 2>&1 || { echo "could not load classify_auth" >&2; exit 2; }

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
# The build marker. WANT_BUILD is what the checkout hashes to; the body is
# what the live function says it is running.
WANT_BUILD=aaaaaaaaaaaaaaaa
MARKED='{"error":{"http_code":405,"message":"send-sms accepts POST"},"build":"aaaaaaaaaaaaaaaa"}'
OLDER='{"error":{"http_code":405,"message":"send-sms accepts POST"},"build":"bbbbbbbbbbbbbbbb"}'
UNMARKED='{"error":{"http_code":405,"message":"send-sms accepts POST"}}'

check "our 405, build matches the checkout" OK_REACHABLE \
  "$(classify_get 405 "$MARKED")"
# The one this exists for: a function that answers, verifies and has its
# provider on, but is running YESTERDAY's code. Every other probe is green.
check "our 405, build is an OLDER deployment" STALE_BUILD \
  "$(classify_get 405 "$OLDER")"
check "our 405, build from before the marker existed" UNMARKED_BUILD \
  "$(classify_get 405 "$UNMARKED")"
# Run from outside a checkout there is nothing to compare with, and the probe
# must report what it saw rather than call it stale.
WANT_BUILD='' check_outside=$(classify_get 405 "$MARKED")
check "no sources to compare with, so no claim" OK_REACHABLE "$check_outside"
WANT_BUILD=aaaaaaaaaaaaaaaa

check "our 405 (POST only) — healthy" OK_REACHABLE \
  "$(classify_get 405 "$MARKED")"
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
G_OK=$(classify_get 405 "$MARKED")
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

echo "▶ AUTH probe (the project's public settings document)"
# A real /auth/v1/settings body, trimmed to the fields this reads. `external`
# is a flat object of booleans, which is what lets a sed extract it safely.
PHONE_OFF_BODY='{"external":{"anonymous_users":false,"apple":false,"email":true,"phone":false},"disable_signup":false,"mailer_autoconfirm":false}'
PHONE_ON_BODY='{"external":{"anonymous_users":false,"apple":false,"email":true,"phone":true},"disable_signup":false,"mailer_autoconfirm":false}'
NO_SIGNUP_BODY='{"external":{"email":true,"phone":true},"disable_signup":true}'

check "phone provider off — the reported fault" PHONE_OFF \
  "$(classify_auth 200 "$PHONE_OFF_BODY")"
check "phone provider on, signups allowed" OK_PHONE_ON \
  "$(classify_auth 200 "$PHONE_ON_BODY")"
check "phone on but signups disabled" SIGNUPS_OFF \
  "$(classify_auth 200 "$NO_SIGNUP_BODY")"
# `"phone":true` also appears in `external`; make sure the reader is not simply
# grepping the whole body, which would call a project with phone OFF healthy
# the moment any other field spelled the word.
check "phone off, the word phone elsewhere" PHONE_OFF \
  "$(classify_auth 200 '{"external":{"phone":false},"disable_signup":false,"sms_provider":"phone"}')"
check "key refused" KEY_REFUSED "$(classify_auth 401 '{"message":"Invalid API key"}')"
check "settings not found" NO_SETTINGS "$(classify_auth 404 '{}')"
check "no answer" UNREACHABLE "$(classify_auth 000 '')"
check "no phone field at all" NO_PHONE_FIELD \
  "$(classify_auth 200 '{"external":{"email":true},"disable_signup":false}')"

echo "▶ readiness pattern, with the AUTH verdict in it"
A_OK=$(classify_auth 200 "$PHONE_ON_BODY")
A_OFF=$(classify_auth 200 "$PHONE_OFF_BODY")
case "${G_OK}${P_OK}${A_OK}" in
  OK_REACHABLE*OK_VERIFYING*OK_PHONE_ON*) echo "  PASS  all three healthy reads as ready" ;;
  *) echo "  FAIL  all three healthy does not read as ready"; FAILED=$((FAILED + 1)) ;;
esac
# The whole point: a healthy FUNCTION with the provider off must NOT read as
# ready. That combination is what the script used to call "✓ deployed" while
# every sign-in failed.
# A stale deployment must not read as ready either, however green the rest is.
G_STALE=$(classify_get 405 "$OLDER")
case "${G_STALE}${P_OK}${A_OK}" in
  OK_REACHABLE*OK_VERIFYING*OK_PHONE_ON*)
     echo "  FAIL  a STALE deployment read as ready"
     FAILED=$((FAILED + 1)) ;;
  *) echo "  PASS  a stale deployment is not ready" ;;
esac

case "${G_OK}${P_OK}${A_OFF}" in
  OK_REACHABLE*OK_VERIFYING*OK_PHONE_ON*)
     echo "  FAIL  a healthy function with the phone provider OFF read as ready"
     FAILED=$((FAILED + 1)) ;;
  *) echo "  PASS  a healthy function with the phone provider OFF is not ready" ;;
esac

echo
if [ "$FAILED" -ne 0 ]; then
  echo "✗ $FAILED assertion(s) failed."
  exit 1
fi
echo "✓ the SMS probe classifier reads every response shape correctly."
