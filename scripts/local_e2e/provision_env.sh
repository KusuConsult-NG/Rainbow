#!/usr/bin/env bash
#
# Write the root `.env` the local end-to-end run needs.
#
# This exists because there were two copies of it — one in run.sh, one written
# out longhand in the CI job — and they drifted. run.sh REPLACED the keys in
# place; the CI step APPENDED them, on top of the empty `DEMO_CITIZEN_EMAIL=`
# that `.env.example` already declares. The first value won, the demo login had
# no credentials, and every screen in CI was the login page while every screen
# locally was fine.
#
# The failure was maximally confusing: 23 screenshots of a login screen, a
# passing local run, and nothing in the log to say the credentials were empty.
# One script, used by both, is the fix.
#
#   scripts/local_e2e/provision_env.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="$ROOT/.env"

# `pubspec.yaml` declares .env as a Flutter ASSET, so it must exist for the
# build to run at all.
[ -f "$ENV_FILE" ] || cp "$ROOT/.env.example" "$ENV_FILE"

# The seeded fixture account. Not a credential: it exists only in
# scripts/local_e2e/fixtures.js and in a throwaway staging project.
# Remove every existing declaration, then write exactly one. Replacing in
# place is not enough: a file that already has the key twice stays having it
# twice, and which one a parser honours is not something to depend on.
set_key() {
  local key="$1" value="$2"
  sed -i "/^${key}=/d" "$ENV_FILE"
  printf '%s=%s\n' "$key" "$value" >> "$ENV_FILE"
}

# A LINE SAYING WHAT THIS FILE NOW IS.
#
# `pubspec.yaml` declares `.env` as a Flutter ASSET, so whatever is in it is
# bundled verbatim into the APK and extracts with `unzip`. This script puts a
# demo password into it. That is correct for a throwaway run and wrong for
# anything else, and the file itself said nothing about which it was — so a
# release built from a checkout that had run the harness would ship a working
# demo credential, which is a smaller version of T-20.
#
# The marker is for whoever next reads the artefact, and for the CI gate below.
#
# NO APOSTROPHE IN THAT LINE. flutter_dotenv strips a whole-line comment with
# `#[^'"]*$` — a regex that stops at the first quote — so `do not` is safe and
# `don't` would leave the tail of the line to be parsed as a setting. Checked in
# flutter_dotenv-6.0.1/lib/src/parser.dart, not assumed.
sed -i '/^# PROVISIONED FOR THE LOCAL END-TO-END RUN/d' "$ENV_FILE"
printf '%s\n' '# PROVISIONED FOR THE LOCAL END-TO-END RUN — do not build a release from this file' >> "$ENV_FILE"

set_key DEMO_CITIZEN_EMAIL "citizen@staging.operationrainbow.test"
set_key DEMO_CITIZEN_PASS  "staging-only-password"

# AGENT_DEFAULT_PASS IS NOT WRITTEN ANY MORE, AND IS REMOVED IF PRESENT.
#
# It was one password shared by every staff account, read by
# `AuthService.signInWithAccessCode` out of this bundled file — T-20. That path
# is gone: staff sign in with their own password via `signInWithBadge`, CI fails
# if the name reappears in `lib/` or `.env.example`, and nothing in the app has
# read it since PR #61. This script kept writing it anyway, and asserting it was
# non-empty, so the one file those gates exist to protect carried the name they
# were added to keep out — in the harness's own build of the APK. Verified by
# reading `build/web/assets/.env` out of a real release build.
#
# Deleted rather than merely not written: every checkout that has run this
# script before still has the line, and a `.env` is not regenerated from the
# template once it exists. Refusing to run would just strand those checkouts
# with the file this is trying to clean.
sed -i '/^AGENT_DEFAULT_PASS=/d' "$ENV_FILE"

# Prove it, rather than trusting the edit: an empty value here is the exact
# failure this script exists to prevent, and it is silent everywhere else.
for key in DEMO_CITIZEN_EMAIL DEMO_CITIZEN_PASS; do
  value="$(grep "^${key}=" "$ENV_FILE" | head -1 | cut -d= -f2-)"
  if [ -z "$value" ]; then
    echo "::error::${key} is empty in .env after provisioning — the demo login cannot work" >&2
    exit 1
  fi
done

# Exactly one declaration of each, or a later empty one could still shadow it.
for key in DEMO_CITIZEN_EMAIL DEMO_CITIZEN_PASS; do
  count="$(grep -c "^${key}=" "$ENV_FILE" || true)"
  if [ "$count" != "1" ]; then
    echo "::error::${key} appears ${count} times in .env; exactly one is required" >&2
    exit 1
  fi
done

# A post-condition, not a trap: the delete above is what clears it, and this
# fails only if that stopped working.
if grep -qE '^AGENT_DEFAULT_PASS=' "$ENV_FILE"; then
  echo "::error::AGENT_DEFAULT_PASS is still in .env, which is bundled into the APK. Nothing reads it (T-20)." >&2
  exit 1
fi

echo "provisioned .env with the seeded demo account, and marked the file as harness-provisioned"
