#!/usr/bin/env bash
# ============================================================================
# Prove scripts/bootstrap_staging.sql builds a correct project FROM ZERO.
#
# The claim it makes is specific: paste this into an empty Supabase project and
# you get a schema matching what production will look like once the outstanding
# migrations are applied. That is only worth anything if it has been done.
#
# So this starts from a genuinely empty database — Supabase shims and nothing
# else — runs the generated file exactly as pasted, and asserts on its own
# verdict table. Then it checks the two claims that are easy to get wrong:
#
#   * the guard actually refuses a non-empty database, so the file cannot be
#     pasted into production by mistake
#   * the result matches what verify_rls_migration.sh produces by the other
#     route (historical replay + outstanding migrations), because two paths to
#     the same schema that disagree mean one of them is lying
#
#   sudo ./scripts/verify_bootstrap.sh
#
# No credentials, no real data, nothing reaches a live project.
# ============================================================================
set -euo pipefail

PGBIN="${PGBIN:-/usr/lib/postgresql/16/bin}"
PGROOT="${PGROOT:-/var/lib/postgresql/bootstraptest}"
PORT="${PGPORT:-5436}"
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
   "$REPO"/scripts/bootstrap_staging.sql "$PGROOT/"
chown -R postgres:postgres "$PGROOT"

psql_f() { su postgres -s /bin/bash -c \
  "$PGBIN/psql -h $PGROOT/sock -p $PORT -U postgres -d $1 -q -f $PGROOT/$2" 2>&1; }
psql_q() { su postgres -s /bin/bash -c \
  "$PGBIN/psql -h $PGROOT/sock -p $PORT -U postgres -d $1 -tAc \"$2\""; }
mkdb()   { su postgres -s /bin/bash -c \
  "$PGBIN/psql -h $PGROOT/sock -p $PORT -U postgres -c 'CREATE DATABASE $1'" >/dev/null; }

# ── 1. Bootstrap an empty project ────────────────────────────────────────────
mkdb fresh
psql_f fresh test_rls_migration.sql >/dev/null
su postgres -s /bin/bash -c \
  "$PGBIN/psql -h $PGROOT/sock -p $PORT -U postgres -d fresh -tAc 'CREATE PUBLICATION supabase_realtime;'" >/dev/null

echo "▶ Running bootstrap_staging.sql on an empty database, exactly as pasted"
OUT=$(su postgres -s /bin/bash -c \
  "$PGBIN/psql -h $PGROOT/sock -p $PORT -U postgres -d fresh -f $PGROOT/bootstrap_staging.sql" 2>&1) && RC=0 || RC=$?
if [ "$RC" -ne 0 ]; then
  printf '%s\n' "$OUT" | grep -E "ERROR|FATAL" | head -20
  echo "::error::bootstrap_staging.sql failed on an empty database"; exit 1
fi

printf '%s\n' "$OUT" | grep -E '^\s*(PASS|\*\*\* FAIL)' || true
FAILED=$(printf '%s\n' "$OUT" | grep -c '\*\*\* FAIL \*\*\*' || true)
PASSED=$(printf '%s\n' "$OUT" | grep -c '^ PASS' || true)
echo "  checks passed: $PASSED   failed: $FAILED"
[ "$FAILED" -eq 0 ] && [ "$PASSED" -ge 16 ] || {
  echo "::error::the bootstrap's own verification reported a failure"; exit 1; }

# ── 2. The guard must refuse a database that already holds data ──────────────
#
# Asserted by OUTCOME, not by exit code. The whole file is one transaction, so a
# tripped guard rolls everything back — and under psql without ON_ERROR_STOP the
# process still exits 0 while having changed nothing. Checking the exit code
# would therefore have passed a version that applied the migrations anyway,
# which is exactly what the first version of this guard did.
echo "▶ Asserting the guard refuses a database that already holds data"
mkdb occupied
psql_f occupied test_rls_migration.sql >/dev/null
su postgres -s /bin/bash -c \
  "$PGBIN/psql -h $PGROOT/sock -p $PORT -U postgres -d occupied -tAc 'CREATE PUBLICATION supabase_realtime;'" >/dev/null
for f in 20260720000000_initial_schema phase1_foundation \
         phase2_assigned_responders phase3_profile_columns_and_config; do
  psql_f occupied "$f.sql" >/dev/null 2>&1 || true
done
psql_q occupied "INSERT INTO public.alerts (type, status) VALUES ('SOS','PENDING')" >/dev/null
ROWS=$(psql_q occupied "SELECT count(*) FROM public.alerts")
[ "$ROWS" = "1" ] || { echo "::error::test setup failed: expected 1 seeded alert, got $ROWS"; exit 1; }

GUARD=$(su postgres -s /bin/bash -c \
  "$PGBIN/psql -h $PGROOT/sock -p $PORT -U postgres -d occupied -f $PGROOT/bootstrap_staging.sql" 2>&1) || true
printf '%s\n' "$GUARD" | grep -q "REFUSING TO RUN" || {
  echo "::error::the guard did not announce itself on a non-empty database"
  printf '%s\n' "$GUARD" | tail -25
  exit 1; }

# The real assertion: nothing was applied. assigned_tier is added by the LAST
# migration in the file, so its absence proves the run was rolled back whole.
LEAKED=$(psql_q occupied "SELECT count(*) FROM information_schema.columns
           WHERE table_schema='public' AND table_name='alerts' AND column_name='assigned_tier'")
[ "$LEAKED" = "0" ] || {
  echo "::error::the guard printed a refusal but the migrations applied anyway"; exit 1; }
echo "  ok: refused, and nothing was applied"

# ── 3. Both routes to the schema must agree ──────────────────────────────────
#
# verify_rls_migration.sh gets there by replaying history then applying the
# outstanding migrations. This file gets there in one paste. If the two disagree
# about which policies exist, one of them is wrong about what production will
# look like — and that is the whole question a staging project exists to answer.
echo "▶ Comparing against the other route to the same schema"
mkdb replayed
psql_f replayed test_rls_migration.sql >/dev/null
su postgres -s /bin/bash -c \
  "$PGBIN/psql -h $PGROOT/sock -p $PORT -U postgres -d replayed -tAc 'CREATE PUBLICATION supabase_realtime;'" >/dev/null
for f in 20260720000000_initial_schema phase1_foundation \
         phase2_assigned_responders phase3_profile_columns_and_config; do
  psql_f replayed "$f.sql" >/dev/null 2>&1 || true
done
for f in 20260812000000_agency_tables 20260813000000_rls_least_privilege \
         20260902000000_per_user_emergency_pins 20260903000000_realtime_publication \
         20260903000001_incident_media_storage 20260903000002_system_alerts_broadcast \
         20260903000003_alert_escalation_columns 20260903000004_profiles_badge_number \
         20260903000005_alerts_assigned_tier; do
  psql_f replayed "$f.sql" >/dev/null
done

SNAP="select tablename||'|'||policyname||'|'||cmd from pg_policies where schemaname='public' order by 1"
A=$(psql_q fresh "$SNAP"); B=$(psql_q replayed "$SNAP")
if [ "$A" != "$B" ]; then
  echo "::error::the two routes produce DIFFERENT policy sets:"
  diff <(printf '%s\n' "$A") <(printf '%s\n' "$B") | head -20
  exit 1
fi
echo "  ok: identical policy sets ($(printf '%s\n' "$A" | wc -l) policies)"

cat <<EOF

✓ bootstrap_staging.sql builds a correct project from zero ($PASSED/16 PASS),
  refuses a database that already holds data, and produces exactly the schema
  the migration replay produces.
EOF
