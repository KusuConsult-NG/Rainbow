#!/usr/bin/env bash
# ============================================================================
# Prove the RLS migration is correct BEFORE running it on a live database.
#
# Spins up a throwaway PostgreSQL, replays the real migration history in order,
# applies 20260813000000_rls_least_privilege.sql, and then asserts BEHAVIOUR:
# what anon, a citizen and a command user can actually do.
#
#   ./scripts/verify_rls_migration.sh
#
# Exit 0 = the migration does what it claims. Non-zero = do not run it.
#
# This exists because "the migration is written" and "the migration is correct"
# are different claims, and on a system that dispatches responders to
# emergencies the difference matters. It needs no Supabase credentials and
# touches no real data.
# ============================================================================
set -euo pipefail

PGBIN="${PGBIN:-/usr/lib/postgresql/16/bin}"
PGROOT="${PGROOT:-/var/lib/postgresql/rlstest}"
PORT="${PGPORT:-5433}"
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

# Stage every SQL file the run needs somewhere the postgres user can read.
cp "$REPO"/supabase/migrations/*.sql \
   "$REPO"/scripts/test_rls_migration.sql \
   "$REPO"/scripts/rls_behaviour_test.sql \
   "$REPO"/scripts/emergency_pins_behaviour_test.sql \
   "$REPO"/scripts/production_readiness_behaviour_test.sql "$PGROOT/"
chown -R postgres:postgres "$PGROOT"

psql_run() {
  su postgres -s /bin/bash -c \
    "psql -h $PGROOT/sock -p $PORT -U postgres -d rainbow -v ON_ERROR_STOP=1 -q $*"
}
su postgres -s /bin/bash -c "psql -h $PGROOT/sock -p $PORT -U postgres -tAc 'CREATE DATABASE rainbow;'" >/dev/null

echo "▶ Installing Supabase compatibility shims (auth.uid(), anon/authenticated roles)"
psql_run "-f $PGROOT/test_rls_migration.sql" >/dev/null
su postgres -s /bin/bash -c \
  "psql -h $PGROOT/sock -p $PORT -U postgres -d rainbow -tAc 'CREATE PUBLICATION supabase_realtime;'" >/dev/null

echo "▶ Replaying migration history"
# ON_ERROR_STOP is off here: the historical files are not idempotent against
# each other (the initial schema re-creates policies phase1 already added).
# We only need the resulting STATE to match production, which is asserted next.
for f in 20260720000000_initial_schema phase1_foundation phase2_assigned_responders phase3_profile_columns_and_config; do
  su postgres -s /bin/bash -c \
    "psql -h $PGROOT/sock -p $PORT -U postgres -d rainbow -q -f $PGROOT/$f.sql" >/dev/null 2>&1 || true
done

# The agency tables the console uses were only ever created by hand in
# production. This file creates them on any database that lacks them, and runs
# BEFORE the RLS migration so that the agency policies are exercised here
# rather than skipped. Strict: it must apply cleanly.
echo "▶ Applying 20260812000000_agency_tables.sql"
psql_run "-f $PGROOT/20260812000000_agency_tables.sql" >/dev/null

BEFORE=$(su postgres -s /bin/bash -c "psql -h $PGROOT/sock -p $PORT -U postgres -d rainbow -tAc \
  \"select count(*) from pg_policies where schemaname='public' and (qual='true' or with_check='true');\"")
echo "  permissive USING(true)/WITH CHECK(true) policies before: $BEFORE"
[ "$BEFORE" -gt 0 ] || { echo "✗ Baseline wrong: expected the permissive policies to be present." >&2; exit 1; }

echo "▶ Applying 20260813000000_rls_least_privilege.sql"
psql_run "-f $PGROOT/20260813000000_rls_least_privilege.sql" >/dev/null

# Per-user emergency PINs: applied on top of the RLS migration, then its own
# behaviour test — lockout, attribution, and that the hashes are unreadable
# through the API even by their owner.
echo "▶ Applying 20260902000000_per_user_emergency_pins.sql"
psql_run "-f $PGROOT/20260902000000_per_user_emergency_pins.sql" >/dev/null
echo "▶ Emergency PIN behaviour test"
# Run ONCE, keeping both the output and the exit code. (Running it twice, as the
# RLS test below is, broke on the second pass: the first had already set PINs.)
# `V=$(cmd)` on its own trips errexit when cmd fails, exiting before the
# diagnostic below prints. The `&& … ||` form keeps the exit code instead.
PIN_OUT=$(psql_run "-f $PGROOT/emergency_pins_behaviour_test.sql" 2>&1) && PIN_RC=0 || PIN_RC=$?
printf '%s\n' "$PIN_OUT" | grep -E "PASS|FAIL|ALL EMERGENCY" || true
if [ "$PIN_RC" -ne 0 ]; then
  printf '%s\n' "$PIN_OUT" | grep -vE "PASS" | tail -20
  echo "::error::emergency PIN behaviour test FAILED"; exit 1
fi

AFTER=$(su postgres -s /bin/bash -c "psql -h $PGROOT/sock -p $PORT -U postgres -d rainbow -tAc \
  \"select count(*) from pg_policies where schemaname='public' and (qual='true' or with_check='true') and 'anon'=any(roles);\"")
ANONPOL=$(su postgres -s /bin/bash -c "psql -h $PGROOT/sock -p $PORT -U postgres -d rainbow -tAc \
  \"select count(*) from pg_policies where schemaname='public' and ('anon'=any(roles) or 'public'=any(roles));\"")
echo "  permissive policies still reachable by anon: $AFTER"
echo "  policies granting anon/public at all:        $ANONPOL"
[ "$AFTER" -eq 0 ] && [ "$ANONPOL" -eq 0 ] || { echo "✗ anon still has policy access." >&2; exit 1; }

echo "▶ Asserting behaviour (anon / citizen / command)"
psql_run "-f $PGROOT/rls_behaviour_test.sql" 2>&1 | grep -E "PASS|FAIL|ALL RLS" || true
psql_run "-f $PGROOT/rls_behaviour_test.sql" >/dev/null 2>&1 || {
  echo "✗ Behavioural assertions FAILED — do not run this migration." >&2; exit 1; }

# Production-readiness migrations: realtime publication and incident-media
# storage, then one behaviour test covering them and the agency policies.
echo "▶ Applying 20260903000000_realtime_publication.sql"
psql_run "-f $PGROOT/20260903000000_realtime_publication.sql" >/dev/null
echo "▶ Applying 20260903000001_incident_media_storage.sql"
psql_run "-f $PGROOT/20260903000001_incident_media_storage.sql" >/dev/null
echo "▶ Applying 20260903000002_system_alerts_broadcast.sql"
psql_run "-f $PGROOT/20260903000002_system_alerts_broadcast.sql" >/dev/null
echo "▶ Re-applying all three (they must be idempotent)"
psql_run "-f $PGROOT/20260903000000_realtime_publication.sql" >/dev/null
psql_run "-f $PGROOT/20260903000001_incident_media_storage.sql" >/dev/null
psql_run "-f $PGROOT/20260903000002_system_alerts_broadcast.sql" >/dev/null
echo "▶ Agency access / realtime / storage behaviour test"
PR_OUT=$(psql_run "-f $PGROOT/production_readiness_behaviour_test.sql" 2>&1) && PR_RC=0 || PR_RC=$?
printf '%s\n' "$PR_OUT" | grep -E "PASS|FAIL|ALL PRODUCTION" || true
if [ "$PR_RC" -ne 0 ]; then
  printf '%s\n' "$PR_OUT" | grep -vE "PASS" | tail -20
  echo "::error::production readiness behaviour test FAILED"; exit 1
fi

cat <<'EOF'

✓ Migration verified against a real PostgreSQL.

  Next, against STAGING (not production):
    psql "$STAGING_DATABASE_URL" -f supabase/migrations/20260813000000_rls_least_privilege.sql
    NEXT_PUBLIC_SUPABASE_URL=... NEXT_PUBLIC_SUPABASE_ANON_KEY=... node scripts/verify_rls.js

  This harness cannot see policies created by hand in the Supabase dashboard.
  Confirm none exist first:
    select tablename, policyname, cmd, qual, with_check
    from pg_policies where schemaname='public' order by tablename;
EOF
