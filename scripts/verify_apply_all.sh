#!/usr/bin/env bash
# ============================================================================
# Prove scripts/apply_all_migrations.sql works as ONE PASTE.
#
# The generated file is what somebody pastes into a production SQL editor. That
# makes "it contains the right text" the wrong test — what matters is that
# running the whole buffer, top to bottom, in one go, ends with every check
# reporting PASS.
#
# So this builds a production-shaped database (the four historical migrations,
# which production already has), runs the generated file exactly as pasted, and
# then asserts on its own verdict table. It also runs it TWICE, because the file
# claims to be idempotent and a partial run must be safe to re-run.
#
#   sudo ./scripts/verify_apply_all.sh
#
# No credentials, no real data, nothing reaches production.
# ============================================================================
set -euo pipefail

PGBIN="${PGBIN:-/usr/lib/postgresql/16/bin}"
PGROOT="${PGROOT:-/var/lib/postgresql/applytest}"
PORT="${PGPORT:-5435}"
DB=prodlike
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

command -v "$PGBIN/initdb" >/dev/null || {
  echo "PostgreSQL not found at $PGBIN. Install it, or set PGBIN." >&2; exit 2; }
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

cp "$REPO"/supabase/migrations/*.sql \
   "$REPO"/scripts/test_rls_migration.sql \
   "$REPO"/scripts/apply_all_migrations.sql "$PGROOT/"
chown -R postgres:postgres "$PGROOT"

psql_f() { su postgres -s /bin/bash -c \
  "$PGBIN/psql -h $PGROOT/sock -p $PORT -U postgres -d $DB -q -f $PGROOT/$1" 2>&1; }

su postgres -s /bin/bash -c \
  "$PGBIN/psql -h $PGROOT/sock -p $PORT -U postgres -c 'CREATE DATABASE $DB'" >/dev/null

echo "▶ Building a production-shaped database"
psql_f test_rls_migration.sql >/dev/null
su postgres -s /bin/bash -c \
  "$PGBIN/psql -h $PGROOT/sock -p $PORT -U postgres -d $DB -tAc 'CREATE PUBLICATION supabase_realtime;'" >/dev/null
# Exactly what production has already: the historical four. Not idempotent
# against each other, which is why errors are tolerated here and nowhere else.
for f in 20260720000000_initial_schema phase1_foundation \
         phase2_assigned_responders phase3_profile_columns_and_config; do
  psql_f "$f.sql" >/dev/null 2>&1 || true
done

run_pasted() {
  su postgres -s /bin/bash -c \
    "$PGBIN/psql -h $PGROOT/sock -p $PORT -U postgres -d $DB -f $PGROOT/apply_all_migrations.sql" 2>&1
}

echo "▶ Running apply_all_migrations.sql exactly as pasted"
OUT=$(run_pasted) && RC=0 || RC=$?
if [ "$RC" -ne 0 ]; then
  printf '%s\n' "$OUT" | grep -E "ERROR|FATAL" | head -20
  echo "::error::the generated apply script failed to run"; exit 1
fi

FAILED=$(printf '%s\n' "$OUT" | grep -c '\*\*\* FAIL \*\*\*' || true)
PASSED=$(printf '%s\n' "$OUT" | grep -c '^ PASS' || true)
# How many checks the generated script actually contains, rather than a number
# written here. The floor used to be the literal 18, so adding checks to the
# generator left this reporting "21/18" and — worse — would have kept passing
# if three of them had silently stopped being emitted.
EXPECTED=$(grep -cE "^    \([0-9]+, '" "$REPO/scripts/apply_all_migrations.sql" || true)
[ "${EXPECTED:-0}" -gt 0 ] || EXPECTED=18
printf '%s\n' "$OUT" | grep -E '^\s*(PASS|\*\*\* FAIL)' || true
echo "  checks passed: $PASSED / $EXPECTED   failed: $FAILED"
if [ "$FAILED" -ne 0 ] || [ "$PASSED" -lt "$EXPECTED" ]; then
  echo "::error::the apply script's own verification reported a failure"; exit 1
fi

echo "▶ Running it a second time (it claims to be idempotent)"
OUT2=$(run_pasted) && RC2=0 || RC2=$?
if [ "$RC2" -ne 0 ]; then
  printf '%s\n' "$OUT2" | grep -E "ERROR|FATAL" | head -20
  echo "::error::re-running the apply script failed — it is not idempotent"; exit 1
fi
FAILED2=$(printf '%s\n' "$OUT2" | grep -c '\*\*\* FAIL \*\*\*' || true)
[ "$FAILED2" -eq 0 ] || {
  echo "::error::second run reported failures"; exit 1; }

echo
echo "✓ apply_all_migrations.sql applies cleanly in one paste, twice over,"
echo "  and its own verification reports $PASSED/$EXPECTED PASS."
