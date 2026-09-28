#!/usr/bin/env bash
# ============================================================================
# Prove the split parts are equivalent to the single paste.
#
# scripts/apply_in_parts/ exists for the operator who cannot paste 2,300 lines
# into a browser tab in one go. That convenience is only safe if running the
# parts IN ORDER lands the same database as running the whole file — otherwise
# the split is a way to skip a migration and never find out.
#
# So: build a production-shaped database (the four historical migrations, which
# production already has), run the 15 parts one at a time in filename order, and
# assert the last one reports the same number of PASS rows the single paste does.
#
#   sudo ./scripts/verify_apply_in_parts.sh
#
# No credentials, no real data, nothing reaches production.
# ============================================================================
set -euo pipefail

PGBIN="${PGBIN:-/usr/lib/postgresql/16/bin}"
PGROOT="${PGROOT:-/var/lib/postgresql/partstest}"
PORT="${PGPORT:-5441}"
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

PARTS_DIR="$REPO/scripts/apply_in_parts"
COUNT=$(find "$PARTS_DIR" -name '*.sql' | wc -l)
[ "$COUNT" -gt 1 ] || { echo "no parts found — run build_apply_in_parts.py" >&2; exit 2; }

echo "▶ Starting a throwaway PostgreSQL on port $PORT"
rm -rf "$PGROOT"; mkdir -p "$PGROOT/data" "$PGROOT/sock" "$PGROOT/parts"
chown -R postgres:postgres "$(dirname "$PGROOT")"
su postgres -s /bin/bash -c "$PGBIN/initdb -D $PGROOT/data -A trust -U postgres" >/dev/null
su postgres -s /bin/bash -c \
  "$PGBIN/pg_ctl -D $PGROOT/data -o '-k $PGROOT/sock -h \"\" -p $PORT' -l $PGROOT/pg.log start" >/dev/null
sleep 2

cp "$REPO"/supabase/migrations/*.sql "$REPO"/scripts/test_rls_migration.sql "$PGROOT/"
cp "$PARTS_DIR"/*.sql "$PGROOT/parts/"
chown -R postgres:postgres "$PGROOT"

psql_f() { su postgres -s /bin/bash -c \
  "$PGBIN/psql -h $PGROOT/sock -p $PORT -U postgres -d $DB -q -f $1" 2>&1; }

su postgres -s /bin/bash -c \
  "$PGBIN/psql -h $PGROOT/sock -p $PORT -U postgres -c 'CREATE DATABASE $DB'" >/dev/null

echo "▶ Building a production-shaped database"
psql_f "$PGROOT/test_rls_migration.sql" >/dev/null
su postgres -s /bin/bash -c \
  "$PGBIN/psql -h $PGROOT/sock -p $PORT -U postgres -d $DB -tAc 'CREATE PUBLICATION supabase_realtime;'" >/dev/null
# Exactly what production has already. Not idempotent against each other, which
# is why errors are tolerated here and nowhere else.
for f in 20260720000000_initial_schema phase1_foundation \
         phase2_assigned_responders phase3_profile_columns_and_config; do
  psql_f "$PGROOT/$f.sql" >/dev/null 2>&1 || true
done

echo "▶ Running the $COUNT parts in order, one at a time"
LAST=""
for f in "$PGROOT"/parts/*.sql; do
  OUT=$(su postgres -s /bin/bash -c \
    "$PGBIN/psql -h $PGROOT/sock -p $PORT -U postgres -d $DB -v ON_ERROR_STOP=1 -f $f" 2>&1) || {
      echo "  ✗ $(basename "$f")"
      printf '%s\n' "$OUT" | grep -E "ERROR|FATAL" | head -5
      echo "::error::part $(basename "$f") failed — the split is not equivalent to the single paste"
      exit 1; }
  echo "  ok: $(basename "$f")"
  LAST="$OUT"
done

PASSED=$(printf '%s\n' "$LAST" | grep -c '^ PASS' || true)
FAILED=$(printf '%s\n' "$LAST" | grep -c '\*\*\* FAIL \*\*\*' || true)
# The same source of truth verify_apply_all.sh uses: how many checks the
# generated script actually contains, not a number written here.
EXPECTED=$(grep -cE "^    \([0-9]+, '" "$REPO/scripts/apply_all_migrations.sql" || true)
[ "${EXPECTED:-0}" -gt 0 ] || EXPECTED=18

printf '%s\n' "$LAST" | grep -E '^\s*(PASS|\*\*\* FAIL)' || true
echo "  checks passed: $PASSED / $EXPECTED   failed: $FAILED"
if [ "$FAILED" -ne 0 ] || [ "$PASSED" -lt "$EXPECTED" ]; then
  echo "::error::the parts do not land the same database as the single paste"; exit 1
fi

# The property an operator actually needs is not "every part re-runs silently" —
# part 02 is atomic rather than idempotent and a second run of it correctly errors
# and rolls back. What matters is that re-running parts cannot leave the database
# WRONG. So: run them all again, tolerate errors, then ask the verification block.
#
# The first version of this asserted silent re-runs and failed on part 02, which
# is how the false "every migration here is idempotent" claim in the generated
# header was found.
echo "▶ Running every part a second time, then re-checking the database"
REDO_ERRORS=0
for f in "$PGROOT"/parts/*.sql; do
  su postgres -s /bin/bash -c \
    "$PGBIN/psql -h $PGROOT/sock -p $PORT -U postgres -d $DB -v ON_ERROR_STOP=1 -f $f" >/dev/null 2>&1 \
    || REDO_ERRORS=$((REDO_ERRORS + 1))
done

AFTER=$(su postgres -s /bin/bash -c \
  "$PGBIN/psql -h $PGROOT/sock -p $PORT -U postgres -d $DB -f $PGROOT/parts/$(ls "$PGROOT/parts" | tail -1)" 2>&1)
PASSED2=$(printf '%s\n' "$AFTER" | grep -c '^ PASS' || true)
FAILED2=$(printf '%s\n' "$AFTER" | grep -c '\*\*\* FAIL \*\*\*' || true)
echo "  $REDO_ERRORS part(s) refused a second run; the database still reports $PASSED2/$EXPECTED PASS"
if [ "$FAILED2" -ne 0 ] || [ "$PASSED2" -lt "$EXPECTED" ]; then
  printf '%s\n' "$AFTER" | grep -E '\*\*\* FAIL' || true
  echo "::error::re-running the parts left the database in a worse state"; exit 1
fi

echo
echo "✓ the $COUNT parts apply in order and report $PASSED/$EXPECTED PASS — the same"
echo "  verdict the single paste gives, and re-running them cannot break it."
