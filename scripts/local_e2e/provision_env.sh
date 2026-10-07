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

set_key DEMO_CITIZEN_EMAIL "citizen@staging.operationrainbow.test"
set_key DEMO_CITIZEN_PASS  "staging-only-password"
# AGENT_DEFAULT_PASS is deliberately NOT written. It was one password shared
# by every staff account, read out of the bundled .env, and nothing reads it
# any more: staff sign in with their own password through signInWithBadge
# (T-20). CI fails if the name reappears in lib/ or .env.example.

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

echo "provisioned .env with the seeded demo account"
