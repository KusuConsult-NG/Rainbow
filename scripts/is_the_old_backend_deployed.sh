#!/usr/bin/env bash
# ============================================================================
# Is the abandoned Firebase backend still deployed?  (C-6)
#
#   ./scripts/is_the_old_backend_deployed.sh
#
# C-6 has been the longest-running unknown in E2E_AUDIT_REPORT.md: a second
# backend, `functions/`, deleted from this repository in PR #58 but never
# confirmed undeployed. Four of its endpoints answer with no credential, and two
# of those were never hardened:
#
#   validateAgentAccessCode  an unauthenticated STAFF ACCOUNT FACTORY. Given an
#                            access code it creates a Firebase Auth user with
#                            `isStaff: true`, sets the password to a value
#                            derived from the code, and RETURNS the email and
#                            password to the caller.
#   triggerSLASweep          iterates every OPEN or ACTIVE alert and escalates
#                            each one a tier. One request moves the whole board.
#
# WHY THIS SCRIPT RATHER THAN THE COMMAND IN THE REPORT
#
# The report says `gcloud functions list --project rainbow-97f1e` settles it,
# which is true and not enough: the answer is a list of names, and what an
# operator needs is which of those names are the dangerous ones, whether the
# platform is actually serving them to the public, and what to run next. It also
# has to say, loudly, what NOT to do — see below.
#
# WHAT THIS SCRIPT WILL NOT DO
#
# It never calls a function. Probing the endpoints is how you find out whether
# they are live, and it is not available to us: `seedMockData` writes ten
# CRITICAL alerts into Firestore — including DURESS ones — so a probe
# manufactures the emergencies the system exists to report. `triggerSLASweep`
# escalates every open alert. This script only ever asks the Cloud Functions and
# IAM APIs what EXISTS.
#
# It also deletes nothing. It prints the exact command and stops, because
# deleting a deployed function is irreversible and is the operator's call.
#
# WHAT IT NEEDS
#
# A Google credential with read access to the project. That is now the ONLY
# thing standing between this question and an answer: as of 2026-10-11 gcloud is
# installed in the audit container (570.0.0) and the API is reachable —
# `https://cloudfunctions.googleapis.com/v2/projects/rainbow-97f1e/locations/-/functions`
# answers `401 UNAUTHENTICATED`, which is Google refusing a request that got
# through, not a network policy refusing to carry it. The report's older note
# that neither CLI was installed and the host was denied is out of date.
# ============================================================================
set -uo pipefail

PROJECT="${RAINBOW_GCP_PROJECT:-rainbow-97f1e}"

# The two that answer with no credential and were never hardened. Anything in
# this list being deployed is the finding, not a detail.
NEVER_HARDENED=(validateAgentAccessCode triggerSLASweep)

# The rest of the legacy surface. Hardened in b2df3fd, which means they refuse
# without a header — but a hardened endpoint is still an endpoint, and these
# write to a Firestore nothing in the shipping code reads.
HARDENED_OR_OTHER=(
  smsWebhook seedMockData escalationWatchdog massBroadcast
  adminEscalateAlert adminDispatchAlert adminResolveAlert migrateLegacyIncidents
)

say()  { printf '%s\n' "$*"; }
rule() { printf '%s\n' "────────────────────────────────────────────────────────────"; }

command -v gcloud >/dev/null || {
  say "✗ gcloud is not installed, so this cannot be answered here."
  say "  Install the Google Cloud SDK, or run the commands in E2E_AUDIT_REPORT.md"
  say "  (C-6) from a machine that has it."
  exit 2
}

ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | head -1)"
if [ -z "$ACCOUNT" ]; then
  rule
  say "NOT ANSWERED: gcloud has no active credential."
  say ""
  say "This is the ONE missing input. gcloud is installed and the Cloud Functions"
  say "API is reachable from here; it answers 401 UNAUTHENTICATED, which is a"
  say "credential problem and nothing else."
  say ""
  say "Give it a credential with read access to $PROJECT and re-run:"
  say ""
  say "    gcloud auth login                 # or:"
  say "    gcloud auth activate-service-account --key-file=KEY.json"
  say "    ./scripts/is_the_old_backend_deployed.sh"
  say ""
  say "A VIEWER role is enough to answer the question. Deleting anything needs"
  say "more, and this script does not delete."
  rule
  exit 2
fi

say "▶ Asking $PROJECT what functions exist, as $ACCOUNT"
LIST="$(gcloud functions list --project "$PROJECT" \
          --format='value(name)' 2>/tmp/rainbow_c6_err)" || {
  say "✗ the API refused the request:"
  sed 's/^/    /' /tmp/rainbow_c6_err | head -6
  say ""
  say "  A 403 here means the credential cannot read this project — which is not"
  say "  the same as the project having no functions. Do not read it as an"
  say "  all-clear."
  exit 2
}

if [ -z "$LIST" ]; then
  rule
  say "ANSWERED: no Cloud Functions are deployed in $PROJECT."
  say ""
  say "C-6 is closed on the deployment side. The code is already out of this"
  say "repository (PR #58), so there is nothing left to delete and nothing"
  say "serving those endpoints."
  say ""
  # Single quotes, and no backticks: inside a double-quoted bash string a
  # backticked word is COMMAND SUBSTITUTION, so `seedMockData` ran as a command
  # and the word disappeared from this very message. Found by running the script
  # against a stubbed gcloud, which is the only way to reach this branch without
  # a credential.
  say 'Still worth doing, and NOT covered by this: the Firestore data the old'
  say 'backend wrote is still there, and seedMockData manufactured CRITICAL'
  say 'and DURESS alerts. Nothing in the shipping code reads that database, so'
  say 'it is a data-at-rest question rather than a live one.' 
  rule
  exit 0
fi

say ""
rule
say "ANSWERED: the old backend IS deployed. Functions found:"
say ""
FOUND_BAD=0
while IFS= read -r fn; do
  [ -n "$fn" ] || continue
  short="${fn##*/}"
  tag="    "
  for bad in "${NEVER_HARDENED[@]}"; do
    [ "$short" = "$bad" ] && { tag="!!! "; FOUND_BAD=1; }
  done
  # Is the platform serving it to the public? That is an IAM binding, not a
  # property of the code, so the code being "hardened" does not answer it.
  POLICY="$(gcloud functions get-iam-policy "$short" --project "$PROJECT" \
              --format='value(bindings.members)' 2>/dev/null || true)"
  PUBLIC=""
  case "$POLICY" in
    *allUsers*)              PUBLIC="  ← allUsers: reachable by anyone on the internet" ;;
    *allAuthenticatedUsers*) PUBLIC="  ← allAuthenticatedUsers: any Google account" ;;
  esac
  say "${tag}${short}${PUBLIC}"
done <<< "$LIST"

say ""
if [ "$FOUND_BAD" -ne 0 ]; then
  say "The lines marked !!! are the two that answer with NO credential and were"
  say "never hardened. validateAgentAccessCode returns a working staff email and"
  say "password to whoever asks; triggerSLASweep escalates every open alert."
  say ""
  say "Delete those first:"
  say ""
  say "    gcloud functions delete validateAgentAccessCode triggerSLASweep \\"
  say "      --project $PROJECT --region us-central1"
  say ""
fi
say "Then the rest of the legacy surface, once no external caller is confirmed:"
say ""
say "    gcloud functions delete ${HARDENED_OR_OTHER[*]} \\"
say "      --project $PROJECT --region us-central1"
say ""
say "DO NOT probe these endpoints to check whether they work. seedMockData"
say "writes ten CRITICAL alerts, DURESS among them, and triggerSLASweep moves"
say "every open alert up a tier. The list above is the evidence; a request is"
say "not needed and is not harmless."
rule
exit 1
