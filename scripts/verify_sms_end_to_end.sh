#!/usr/bin/env bash
# ============================================================================
# The SMS channel, from the key the DATABASE issues to the alert HQ decodes.
#
#   sudo ./scripts/verify_sms_end_to_end.sh
#
# WHAT THIS CLOSES
#
# Every piece of the SMS channel was tested against material a test invented:
# `sms_alert_payload_test.dart` seals with a key it made up, `route.test.ts`
# decodes vectors with a key from a fixture, and the SQL behaviour test checks
# that `register_sms_device()` returns 4 and 32 bytes without ever using them.
#
# Nothing had checked the join: that the key PostgreSQL issues, rendered the way
# PostgREST renders BYTEA (`\x` and hex), survives the trip into the codec and
# actually opens a message the handset sealed. That is three encodings deep —
# bytea, hex, base64 — and every one of them is somewhere a channel can fail
# silently while every unit test stays green.
#
# It needs no credentials and touches no real data: a throwaway PostgreSQL, the
# real migrations, the real Dart encoder and the real TypeScript decoder.
# ============================================================================
set -euo pipefail

PGBIN="${PGBIN:-/usr/lib/postgresql/16/bin}"
PGROOT="${PGROOT:-/var/lib/postgresql/smstest}"
PORT="${PGPORT:-5450}"
DB=smsverify
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$PATH:/opt/flutter/bin"

command -v "$PGBIN/initdb" >/dev/null || { echo "PostgreSQL not at $PGBIN" >&2; exit 2; }
id postgres >/dev/null 2>&1 || useradd -M postgres

cleanup() {
  su postgres -s /bin/bash -c "$PGBIN/pg_ctl -D $PGROOT/data stop -m immediate" >/dev/null 2>&1 || true
  rm -rf "$PGROOT"
}
trap cleanup EXIT

echo "▶ Starting a throwaway PostgreSQL on port $PORT"
rm -rf "$PGROOT"; mkdir -p "$PGROOT/data" "$PGROOT/sock"
chown -R postgres:postgres "$(dirname "$PGROOT")"
su postgres -s /bin/bash -c "$PGBIN/initdb -D $PGROOT/data -A trust -U postgres" >/dev/null
su postgres -s /bin/bash -c \
  "$PGBIN/pg_ctl -D $PGROOT/data -o '-k $PGROOT/sock -h \"\" -p $PORT' -l $PGROOT/pg.log start" >/dev/null
sleep 2

cp "$REPO"/supabase/migrations/*.sql "$REPO"/scripts/test_rls_migration.sql \
   "$REPO"/scripts/apply_all_migrations.sql "$PGROOT/"
chown -R postgres:postgres "$PGROOT"

q() { su postgres -s /bin/bash -c \
  "$PGBIN/psql -h $PGROOT/sock -p $PORT -U postgres -d $DB -tAc \"$1\"" 2>&1; }
qf() { su postgres -s /bin/bash -c \
  "$PGBIN/psql -h $PGROOT/sock -p $PORT -U postgres -d $DB -q -f $PGROOT/$1" 2>&1; }

su postgres -s /bin/bash -c \
  "$PGBIN/psql -h $PGROOT/sock -p $PORT -U postgres -c 'CREATE DATABASE $DB'" >/dev/null

echo "▶ Building the schema the way production has it"
qf test_rls_migration.sql >/dev/null
su postgres -s /bin/bash -c \
  "$PGBIN/psql -h $PGROOT/sock -p $PORT -U postgres -d $DB -tAc 'CREATE PUBLICATION supabase_realtime;'" >/dev/null
for f in 20260720000000_initial_schema phase1_foundation \
         phase2_assigned_responders phase3_profile_columns_and_config; do
  qf "$f.sql" >/dev/null 2>&1 || true
done
qf apply_all_migrations.sql >/dev/null 2>&1 || true

# ── The database issues a key to a signed-in citizen ────────────────────────
#
# Through the real function, as the app does — not an INSERT that sidesteps it.
UID_CITIZEN='77770000-0000-4000-8000-000000007001'
q "INSERT INTO auth.users (id, email) VALUES ('$UID_CITIZEN', 'sms-verify@example.test') ON CONFLICT (id) DO NOTHING;" >/dev/null

echo "▶ Registering a device through register_sms_device()"
ISSUED=$(q "SET LOCAL ROLE authenticated;
  SELECT set_config('request.jwt.claim.sub', '$UID_CITIZEN', true);
  SELECT encode(device_ref,'hex') || ' ' || encode(secret,'hex') FROM public.register_sms_device();" \
  | tail -1)
REF_HEX=$(echo "$ISSUED" | awk '{print $1}')
KEY_HEX=$(echo "$ISSUED" | awk '{print $2}')
[ ${#REF_HEX} -eq 8 ]  || { echo "✗ device_ref is '${REF_HEX}' (${#REF_HEX} hex chars, expected 8)"; exit 1; }
[ ${#KEY_HEX} -eq 64 ] || { echo "✗ secret is ${#KEY_HEX} hex chars, expected 64"; exit 1; }
echo "  device_ref: $REF_HEX   secret: ${KEY_HEX:0:8}… (${#KEY_HEX} hex chars)"

# ── What ingest would read, in PostgREST's rendering ────────────────────────
#
# The route looks the key up with sms_key_for_ingest and strips a leading `\x`.
# This is the encoding nothing had checked end to end.
echo "▶ Reading it back through sms_key_for_ingest(), as ingest does"
INGEST=$(q "SELECT user_id || ' ' || ('\\\\x' || encode(secret,'hex')) FROM public.sms_key_for_ingest(decode('$REF_HEX','hex'));" | tail -1)
INGEST_UID=$(echo "$INGEST" | awk '{print $1}')
INGEST_KEY=$(echo "$INGEST" | awk '{print $2}')
[ "$INGEST_UID" = "$UID_CITIZEN" ] || { echo "✗ ingest resolved '$INGEST_UID', expected $UID_CITIZEN"; exit 1; }
echo "  resolves to the owner, key rendered as ${INGEST_KEY:0:12}…"

# ── The handset seals an alert with that key ────────────────────────────────
echo "▶ Sealing an alert with the issued key, using the real Dart encoder"
cd "$REPO"
SMS_KEY_HEX="$KEY_HEX" SMS_REF_HEX="$REF_HEX" \
  flutter test test/seal_with_issued_key_test.dart > /tmp/seal.log 2>&1 \
  || { echo "✗ the Dart encoder failed"; tail -20 /tmp/seal.log; exit 1; }
BODY=$(grep -oE 'OR1[A-Za-z0-9_-]+' /tmp/seal.log | head -1)
[ -n "$BODY" ] || { echo "✗ no message body came out of the encoder"; tail -20 /tmp/seal.log; exit 1; }
echo "  body: ${BODY:0:24}… (${#BODY} characters)"
[ ${#BODY} -le 160 ] || { echo "✗ ${#BODY} characters will not fit one GSM-7 segment"; exit 1; }

# ── HQ decodes it with the key the database gave ingest ─────────────────────
echo "▶ Decoding it with the TypeScript codec, using the key ingest read"
cd "$REPO/hq-dashboard-next"
SMS_BODY="$BODY" INGEST_KEY="$INGEST_KEY" SMS_REF_HEX="$REF_HEX" \
  npx vitest run src/lib/sms-issued-key.test.ts > /tmp/decode.log 2>&1 \
  || { echo "✗ the decoder refused it"; grep -E "AssertionError|expected|✗|FAIL" /tmp/decode.log | head -12; exit 1; }
RECORD=$(grep -o 'HQ_WOULD_RECORD .*' /tmp/decode.log | head -1 | cut -d' ' -f2-)
ASSERTIONS=$(grep -oE "Tests +[0-9]+ passed" /tmp/decode.log | head -1)
[ -n "$RECORD" ] || { echo "✗ the decoder produced no record"; tail -20 /tmp/decode.log; exit 1; }
echo "  $ASSERTIONS"
echo "  HQ would record: $RECORD"
cd "$REPO"

# ── And a revoked key stops working, which is the other half ────────────────
echo "▶ Revoking the device, then trying ingest again"
q "SET LOCAL ROLE authenticated;
  SELECT set_config('request.jwt.claim.sub', '$UID_CITIZEN', true);
  SELECT public.revoke_sms_device_keys();" >/dev/null
AFTER=$(q "SELECT count(*) FROM public.sms_key_for_ingest(decode('$REF_HEX','hex'));" | tail -1)
[ "$AFTER" = "0" ] || { echo "✗ a revoked device still resolves at ingest"; exit 1; }
echo "  a revoked device resolves to nothing, so its messages are refused"

cat <<'EOF'

✓ SMS verified from the database's own key to HQ's decoded alert:

    register_sms_device()  →  bytea  →  \x-hex  →  AES-GCM  →  base64url
    →  one 75-character message  →  TypeScript decode  →  every field intact

  What this does NOT prove, and cannot from here:
    * that a handset's radio sends it (needs a phone, a SIM and the Play
      SEND_SMS declaration);
    * that a gateway delivers it to /api/sms/inbound (needs a shortcode);
    * that HTTP wiring works end to end (route.test.ts covers the handler; the
      first real message is the test of the deployment).
EOF
