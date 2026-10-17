#!/usr/bin/env bash
# ============================================================================
# Wire up the SMS provider, or say exactly which step is missing.
#
#   ./scripts/wire_up_sms_provider.sh --check            # diagnose, no credentials
#   ./scripts/wire_up_sms_provider.sh --commit           # configure it
#
# WHY THIS EXISTS
#
# `signInWithOtp` is refused outright by a Supabase project with no SMS
# provider, so until this is done NO CITIZEN CAN SIGN IN. The hook itself has
# been in the repository since PR #59 (supabase/functions/send-sms, 25 unit
# tests). What was left was five dashboard steps described in prose in
# docs/PRODUCTION_DEPLOYMENT.md §2b, performed by hand, with no way to check the
# result short of asking a real person to request a real code.
#
# ## --check needs no credentials at all, and sends no SMS
#
# THREE unauthenticated requests. Two to the function's public URL, which tell
# the four deployment failure modes apart because this function's own error
# bodies are distinguishable from the platform's — and one to the project's
# PUBLIC auth settings document, which answers the question the first two
# cannot: whether Auth will ever call the hook at all.
#
# That third one was missing, and its absence had a cost. This script reported
# "✓ The function is deployed, reachable without a JWT, and verifying
# signatures" against a project where every citizen sign-in failed, because the
# Phone provider was switched off and Auth refuses `signInWithOtp` before the
# hook is consulted. A green diagnostic beside a red product is worse than no
# diagnostic: it sends the operator looking everywhere except at the fault.
#
#   GET  /functions/v1/send-sms
#     401 from the PLATFORM     -> deployed WITH JWT verification. The hook can
#                                  never reach it: Auth calls it before any JWT
#                                  exists, so every real call is refused and the
#                                  user just sees "failed to send OTP".
#                                  Fix: deploy with --no-verify-jwt.
#     405 {"error":{...}}       -> our code answered. Deployed correctly.
#     404                       -> not deployed at all.
#
#   GET  /auth/v1/settings       with the publishable key
#     external.phone false      -> the Phone provider is OFF. Auth refuses every
#                                  sign-in before the hook is consulted, and the
#                                  app says "SMS SIGN-IN IS NOT SWITCHED ON FOR
#                                  THIS SERVICE YET".
#     disable_signup true       -> the provider is on, but a number that has
#                                  never signed in is refused.
#     both clear                -> Auth will call the hook.
#
#   POST /functions/v1/send-sms  with a deliberately invalid signature
#     503 hook is not configured-> deployed, but SEND_SMS_HOOK_SECRET is unset.
#     503 old name              -> only the legacy HOOK_SECRET is set.
#     401                       -> the secret IS set and signature verification
#                                  works. This is the healthy answer.
#
# Neither request can send a message: the 405 path returns before reading a
# body, and the 401 path fails verification before Termii is ever called. No
# OTP, no Termii credit, nothing written.
#
# ## --commit
#
# Needs, in the environment and never on the command line:
#
#   SUPABASE_ACCESS_TOKEN   a personal access token with auth_config_write
#   SUPABASE_PROJECT_REF    the 20-character project ref
#   TERMII_API_KEY          Termii API key
#   TERMII_SENDER_ID        the sender ID Termii approved (e.g. "OE Alert")
#
# and then it: generates a Standard Webhooks signing secret if you have not
# supplied one, stores the three function secrets, deploys the function with
# --no-verify-jwt, enables the Send SMS hook pointing at it, turns
# `sms_autoconfirm` OFF — with it on, Auth confirms the phone without ever
# sending a code, so the hook never fires and this all silently does nothing —
# reads the configuration back, and finally runs the --check probes.
#
# No secret value is ever printed: only its length and first few characters.
#
# API shapes verified against the Supabase docs on 2026-10-06 rather than
# written from memory:
#   PATCH /v1/projects/{ref}/config/auth   hook_send_sms_enabled   (boolean)
#                                          hook_send_sms_uri       (string)
#                                          hook_send_sms_secrets   (string)
#                                          sms_autoconfirm         (boolean)
#   POST  /v1/projects/{ref}/secrets       [{"name":…,"value":…}] -> 201
#   secret format                          v1,whsec_<base64>
#   hook success                           empty JSON, HTTP 200
#
# `external_phone_enabled` is deliberately NOT asserted: it appears in no
# documentation I could confirm, and asserting a field name I am guessing at
# would fail against a correctly configured project. The read-back prints every
# phone/sms/hook field the API returns, so you can see the real names.
# ============================================================================
set -euo pipefail

API=https://api.supabase.com
MODE=check
for a in "$@"; do
  case "$a" in
    --check)  MODE=check ;;
    --commit) MODE=commit ;;
    -h|--help) sed -n '2,70p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $a (use --check or --commit)" >&2; exit 2 ;;
  esac
done

REF="${SUPABASE_PROJECT_REF:-}"
if [ -z "$REF" ]; then
  echo "SUPABASE_PROJECT_REF is not set. It is the 20-character ref in your" >&2
  echo "project URL: https://<ref>.supabase.co" >&2
  exit 2
fi
[ "${#REF}" -eq 20 ] || {
  echo "SUPABASE_PROJECT_REF is ${#REF} characters; a project ref is exactly 20." >&2
  echo "Pass the ref, not the whole URL." >&2; exit 2; }

FN_URL="https://${REF}.supabase.co/functions/v1/send-sms"
AUTH_URL="https://${REF}.supabase.co/auth/v1/settings"

# The publishable key, which is public by design — it ships inside the APK and
# row-level security is the access model. Read from the file that declares it so
# there is one source of truth, and overridable for a project that is not the
# default one.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANON="${SUPABASE_ANON_KEY:-$(sed -n "s/.*defaultValue: '\\(sb_publishable_[^']*\\)'.*/\\1/p" \
  "$REPO/lib/core/supabase/supabase_config.dart" | head -1)}"

# What the sources in THIS checkout hash to. The deployed function reports its
# own marker on GET, so the two can be compared — which is the only way to tell
# a current deployment from a stale one. Empty if this is run from outside the
# repository; the probe then says what it found and makes no claim about it.
WANT_BUILD="$(python3 -c "import sys; sys.path.insert(0, '$REPO/scripts'); from stamp_send_sms_version import fingerprint; print(fingerprint())" 2>/dev/null || true)"

mask() {  # never print a secret, only its shape
  local v="$1"
  if [ -z "$v" ]; then echo "(unset)"; else
    echo "${v:0:6}… (${#v} chars)"; fi
}

# ── The probe classifier, kept as one function so it can be tested ───────────
#
# Prints one stable verdict token, then a human line. scripts/
# wire_up_sms_provider_test.sh feeds it every body shape this function can
# return and asserts the token, because a diagnostic that mis-reads a 401 would
# send an operator to fix the wrong thing.
classify_get() {
  local code="$1" body="$2"
  case "$code" in
    000) echo "UNREACHABLE  could not connect to $FN_URL"; return ;;
    404) echo "NOT_DEPLOYED  the function is not deployed. Run: supabase functions deploy send-sms --no-verify-jwt"; return ;;
    405)
      if printf '%s' "$body" | grep -q '"http_code":405'; then
        # Which build answered. Every other signal this script reads was
        # already green against a deployment whose sign-in SMS named the app
        # from two rebrands ago (T-65), and the operator read the tick as
        # "my paste landed". It could not have told them either way.
        local live
        live=$(printf '%s' "$body" | sed -n 's/.*"build"[[:space:]]*:[[:space:]]*"\([0-9a-f]*\)".*/\1/p')
        if [ -z "$live" ]; then
          echo "UNMARKED_BUILD  our code answered, but it is a build from before the version marker existed, so there is no way to tell which one. Redeploy from this checkout."
        elif [ -z "$WANT_BUILD" ]; then
          echo "OK_REACHABLE  our code answered (405, POST only) — deployed with JWT verification OFF, which is correct. Build $live; this run could not read the sources to compare it with."
        elif [ "$live" != "$WANT_BUILD" ]; then
          echo "STALE_BUILD  our code answered, but it is build $live and this checkout is $WANT_BUILD. The deployment is an OLDER version of this function. Redeploy, or paste supabase/functions/send-sms/bundled_for_dashboard.ts again."
        else
          echo "OK_REACHABLE  our code answered (405, POST only) — deployed with JWT verification OFF, and it is build $live, which is this checkout"
        fi
      else
        echo "ODD_405  something returned 405 that is not this function: $body"
      fi
      return ;;
    401|403)
      if printf '%s' "$body" | grep -q '"http_code"'; then
        echo "OK_REACHABLE  our code answered — deployed correctly"
      else
        echo "JWT_ON  the PLATFORM refused this ($code) before our code ran. The hook fires before any JWT exists, so every real call is refused and users see \"failed to send OTP\". Redeploy: supabase functions deploy send-sms --no-verify-jwt"
      fi
      return ;;
    *) echo "UNEXPECTED_$code  $body" ;;
  esac
}

classify_post() {
  local code="$1" body="$2"
  case "$code" in
    000) echo "UNREACHABLE  could not connect"; return ;;
    404) echo "NOT_DEPLOYED  the function is not deployed"; return ;;
    503)
      if printf '%s' "$body" | grep -q 'old name'; then
        echo "LEGACY_SECRET  only the legacy HOOK_SECRET is set. Set SEND_SMS_HOOK_SECRET instead"
      else
        echo "NO_SECRET  deployed, but SEND_SMS_HOOK_SECRET is unset, so the hook refuses to run"
      fi
      return ;;
    401)
      echo "OK_VERIFYING  the secret is set and the signature check rejected a bad signature — healthy"
      return ;;
    200)
      echo "ACCEPTS_UNSIGNED  it accepted a request with an invalid signature. That is a hole: anyone could drive this endpoint"
      return ;;
    *) echo "UNEXPECTED_$code  $body" ;;
  esac
}

# The third probe, and the one that was missing.
#
# `--check` used to end by saying "What this CANNOT see from outside: whether
# the Send SMS hook is enabled and pointed here". Half of that is visible, with
# no credentials at all: GET /auth/v1/settings returns the project's PUBLIC auth
# configuration, including whether the Phone provider is switched on and whether
# signups are allowed.
#
# That matters because those two are checked by Auth BEFORE the hook is ever
# consulted. With the Phone provider off, a perfectly deployed, perfectly
# signing hook is never called at all — which is exactly the state this script
# reported as "✓ The function is deployed, reachable without a JWT, and
# verifying signatures" while every citizen sign-in failed with
# "SMS SIGN-IN IS NOT SWITCHED ON FOR THIS SERVICE YET".
#
# No writes, no SMS: a GET of a public settings document.
classify_auth() {
  local code="$1" body="$2"
  case "$code" in
    000) echo "UNREACHABLE  could not reach $AUTH_URL"; return ;;
    401|403) echo "KEY_REFUSED  the publishable key was refused ($code). Pass the project's current one as SUPABASE_ANON_KEY"; return ;;
    404) echo "NO_SETTINGS  404 from /auth/v1/settings — check the project ref"; return ;;
    200) : ;;
    *) echo "UNEXPECTED_$code  $body"; return ;;
  esac

  # `external` is a flat object of booleans, so everything up to the first `}`
  # is the whole of it. Nothing here needs a JSON parser, which this script
  # cannot assume is installed.
  local external phone signup
  external=$(printf '%s' "$body" | sed -n 's/.*"external"[[:space:]]*:[[:space:]]*{\([^}]*\)}.*/\1/p')
  phone=$(printf '%s' "$external" | grep -o '"phone"[[:space:]]*:[[:space:]]*[a-z]*' | sed 's/.*:[[:space:]]*//')
  signup=$(printf '%s' "$body" | grep -o '"disable_signup"[[:space:]]*:[[:space:]]*[a-z]*' | sed 's/.*:[[:space:]]*//')

  if [ -z "$phone" ]; then
    echo "NO_PHONE_FIELD  /auth/v1/settings answered but named no phone provider: $body"
    return
  fi
  if [ "$phone" != true ]; then
    echo "PHONE_OFF  the Phone provider is switched OFF, so Auth refuses every sign-in before the hook is consulted — the app says \"SMS SIGN-IN IS NOT SWITCHED ON FOR THIS SERVICE YET\". Dashboard: Authentication -> Sign In / Providers -> Phone -> enable it"
    return
  fi
  if [ "$signup" = true ]; then
    echo "SIGNUPS_OFF  the Phone provider is on, but new signups are disabled, so a number that has never signed in is refused with \"Signups not allowed for otp\". Dashboard: Authentication -> Sign In / Providers -> Allow new users to sign up"
    return
  fi
  echo "OK_PHONE_ON  the Phone provider is enabled and new numbers may sign up"
}

probe() {
  echo "▶ Probing $FN_URL (no credentials, no SMS sent)"
  local g gcode gbody p pcode pbody
  g=$(curl -sS -m 20 -w '\n%{http_code}' "$FN_URL" 2>/dev/null || echo $'\n000')
  gcode=$(printf '%s' "$g" | tail -1); gbody=$(printf '%s' "$g" | sed '$d')
  echo "  GET  -> $(classify_get "$gcode" "$gbody")"

  # A syntactically valid Standard Webhooks header set with a signature that
  # cannot verify. The body is a well-formed hook payload so that nothing before
  # the signature check can be what rejects it.
  p=$(curl -sS -m 20 -X POST "$FN_URL" \
        -H 'Content-Type: application/json' \
        -H 'webhook-id: msg_wire_up_probe' \
        -H "webhook-timestamp: $(date +%s)" \
        -H 'webhook-signature: v1,AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=' \
        -d '{"user":{"phone":"+2340000000000"},"sms":{"otp":"000000"}}' \
        -w '\n%{http_code}' 2>/dev/null || echo $'\n000')
  pcode=$(printf '%s' "$p" | tail -1); pbody=$(printf '%s' "$p" | sed '$d')
  echo "  POST -> $(classify_post "$pcode" "$pbody")"

  # The function can be perfect and sign-in still fail, because Auth checks the
  # Phone provider before it ever reaches the hook. Read-only, sends no SMS.
  local a acode abody
  if [ -z "$ANON" ]; then
    echo "  AUTH -> NO_KEY  could not find a publishable key to read "
    echo "          /auth/v1/settings with. Set SUPABASE_ANON_KEY."
  else
    a=$(curl -sS -m 20 -H "apikey: $ANON" -w '\n%{http_code}' "$AUTH_URL" 2>/dev/null || echo $'\n000')
    acode=$(printf '%s' "$a" | tail -1); abody=$(printf '%s' "$a" | sed '$d')
    echo "  AUTH -> $(classify_auth "$acode" "$abody")"
  fi

  case "$(classify_get "$gcode" "$gbody")$(classify_post "$pcode" "$pbody")$(classify_auth "${acode:-000}" "${abody:-}")" in
    OK_REACHABLE*OK_VERIFYING*OK_PHONE_ON*)
      echo
      echo "✓ The function is deployed, reachable without a JWT and verifying"
      echo "  signatures, and the Phone provider is on with signups allowed."
      echo "  What this still CANNOT see from outside: whether the Send SMS hook"
      echo "  is pointed at this function, and whether Termii has credit on an"
      echo "  approved sender ID. --commit sets the first; only a real sign-in"
      echo "  proves the second."
      return 0 ;;
    OK_REACHABLE*OK_VERIFYING*)
      echo
      echo "✗ The function is healthy, but Auth will not call it. The AUTH line"
      echo "  above names what to switch on. Until then every citizen sign-in"
      echo "  fails before the hook is ever consulted."
      return 1 ;;
  esac
  return 1
}

if [ "$MODE" = check ]; then
  probe || {
    echo
    echo "✗ Not ready. Fix what the lines above name, or run --commit."
    exit 1; }
  exit 0
fi

# ── --commit ────────────────────────────────────────────────────────────────
TOKEN="${SUPABASE_ACCESS_TOKEN:-}"
[ -n "$TOKEN" ] || { echo "SUPABASE_ACCESS_TOKEN is not set." >&2; exit 2; }
[ -n "${TERMII_API_KEY:-}" ] || { echo "TERMII_API_KEY is not set." >&2; exit 2; }
SENDER="${TERMII_SENDER_ID:-OE Alert}"

# Reuse a secret if the operator already generated one in the dashboard;
# otherwise make one. 32 random bytes is what Standard Webhooks specifies.
SECRET="${SEND_SMS_HOOK_SECRET:-}"
if [ -z "$SECRET" ]; then
  SECRET="v1,whsec_$(head -c 32 /dev/urandom | base64 | tr -d '\n')"
  GENERATED=yes
else
  GENERATED=no
  case "$SECRET" in
    v1,whsec_*) ;;
    *) echo "SEND_SMS_HOOK_SECRET must look like v1,whsec_<base64>." >&2; exit 2 ;;
  esac
fi

echo "▶ Project $REF"
echo "  access token:  $(mask "$TOKEN")"
echo "  termii key:    $(mask "${TERMII_API_KEY}")"
echo "  sender id:     $SENDER"
echo "  hook secret:   $(mask "$SECRET")$([ "$GENERATED" = yes ] && echo '  [generated now — it is stored, and printed nowhere]')"
echo

api() {  # api <method> <path> [body]
  local method="$1" path="$2" body="${3:-}"
  local args=(-sS -m 30 -X "$method" "$API$path"
              -H "Authorization: Bearer $TOKEN"
              -H 'Content-Type: application/json' -w '\n%{http_code}')
  [ -n "$body" ] && args+=(-d "$body")
  curl "${args[@]}"
}

echo "▶ Reading the current auth configuration"
CUR=$(api GET "/v1/projects/$REF/config/auth")
CUR_CODE=$(printf '%s' "$CUR" | tail -1); CUR_BODY=$(printf '%s' "$CUR" | sed '$d')
[ "$CUR_CODE" = 200 ] || {
  echo "  HTTP $CUR_CODE from the Management API." >&2
  echo "  $(printf '%s' "$CUR_BODY" | head -c 300)" >&2
  echo "  A 401 means the token is wrong or lacks auth_config_write; a 404 means" >&2
  echo "  the project ref is wrong." >&2
  exit 1; }
show_relevant() {
  python3 - "$1" <<'PY'
import json, sys
try:
    cfg = json.loads(sys.argv[1])
except Exception:
    print('    (could not parse the response as JSON)'); raise SystemExit(0)
keys = sorted(k for k in cfg if 'sms' in k.lower() or 'phone' in k.lower())
if not keys:
    print('    (the API returned no sms/phone fields)')
for k in keys:
    v = cfg[k]
    if isinstance(v, str) and ('secret' in k or 'token' in k or 'key' in k) and v:
        v = f'{v[:6]}… ({len(v)} chars)'
    print(f'    {k} = {v!r}')
PY
}
show_relevant "$CUR_BODY"

echo
echo "▶ Storing the three function secrets"
SECRETS_JSON=$(python3 - "$SECRET" "$TERMII_API_KEY" "$SENDER" <<'PY'
import json, sys
print(json.dumps([
    {"name": "SEND_SMS_HOOK_SECRET", "value": sys.argv[1]},
    {"name": "TERMII_API_KEY",       "value": sys.argv[2]},
    {"name": "TERMII_SENDER_ID",     "value": sys.argv[3]},
]))
PY
)
S=$(api POST "/v1/projects/$REF/secrets" "$SECRETS_JSON")
S_CODE=$(printf '%s' "$S" | tail -1)
case "$S_CODE" in
  200|201) echo "  ok: three secrets stored" ;;
  *) echo "  HTTP $S_CODE storing secrets:" >&2
     printf '%s' "$S" | sed '$d' | head -c 300 >&2; echo >&2; exit 1 ;;
esac

echo
echo "▶ Deploying the function with JWT verification OFF"
if command -v supabase >/dev/null 2>&1; then
  ( cd "$(dirname "${BASH_SOURCE[0]}")/.." \
    && supabase functions deploy send-sms --no-verify-jwt --project-ref "$REF" ) \
    && echo "  ok: deployed" \
    || { echo "  ✗ deploy failed — fix that before the hook is enabled, or Auth" >&2
         echo "    will point at a function that is not there." >&2; exit 1; }
else
  echo "  ! the supabase CLI is not on PATH, so this step was skipped."
  echo "    Run it yourself, from the repository root:"
  echo "      supabase functions deploy send-sms --no-verify-jwt --project-ref $REF"
  echo "    --no-verify-jwt is not optional: Auth calls the hook before any JWT"
  echo "    exists, so a normally-deployed function is refused on every call."
fi

echo
echo "▶ Enabling the Send SMS hook, and turning sms_autoconfirm off"
PATCH_JSON=$(python3 - "$FN_URL" "$SECRET" <<'PY'
import json, sys
print(json.dumps({
    "hook_send_sms_enabled": True,
    "hook_send_sms_uri": sys.argv[1],
    "hook_send_sms_secrets": sys.argv[2],
    # With this on, Auth confirms the phone without sending a code, the hook
    # never fires, and every step above silently achieves nothing.
    "sms_autoconfirm": False,
}))
PY
)
P=$(api PATCH "/v1/projects/$REF/config/auth" "$PATCH_JSON")
P_CODE=$(printf '%s' "$P" | tail -1)
[ "$P_CODE" = 200 ] || {
  echo "  HTTP $P_CODE updating the auth config:" >&2
  printf '%s' "$P" | sed '$d' | head -c 400 >&2; echo >&2; exit 1; }
echo "  ok: hook enabled"

echo
echo "▶ Reading the configuration back"
AFTER=$(api GET "/v1/projects/$REF/config/auth")
AFTER_BODY=$(printf '%s' "$AFTER" | sed '$d')
show_relevant "$AFTER_BODY"
python3 - "$AFTER_BODY" "$FN_URL" <<'PY' || exit 1
import json, sys
cfg = json.loads(sys.argv[1]); want_uri = sys.argv[2]
bad = []
if cfg.get('hook_send_sms_enabled') is not True:
    bad.append('hook_send_sms_enabled did not come back true')
if cfg.get('hook_send_sms_uri') != want_uri:
    bad.append(f'hook_send_sms_uri is {cfg.get("hook_send_sms_uri")!r}, not {want_uri!r}')
if cfg.get('sms_autoconfirm') is True:
    bad.append('sms_autoconfirm is still on, so no code will ever be sent')
for b in bad:
    print(f'  ✗ {b}')
raise SystemExit(1 if bad else 0)
PY
echo "  ok: the hook is enabled, pointed here, and autoconfirm is off"

echo
probe || exit 1

cat <<EOF

✓ The SMS provider is wired up.

  What is proven: the function is deployed, reachable without a JWT, verifying
  signatures, and Auth is configured to call it with autoconfirm off.

  What is NOT proven, and cannot be from here: that Termii will actually
  deliver. That needs a real sign-in with a real handset, and Termii credit on
  an approved sender ID. A delivery failure now shows up as the hook returning
  an error, which Auth surfaces to the app — lib/services/auth_service.dart
  turns it into a message a citizen can act on rather than "unknown error".

  If sign-in still fails, run this with --check and read the two probe lines.
EOF
