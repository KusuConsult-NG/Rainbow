#!/usr/bin/env bash
# ============================================================================
# Prove the production dry run SAYS SOMETHING, and keeps nothing.
#
#   ./scripts/verify_dryrun_emits.sh
#
# Exit 0 = the dry run reports a verdict, detects a re-opened table, and leaves
# the database exactly as it found it.
#
# WHY THIS EXISTS
#
# scripts/rls_production_dryrun.sql is the only way to find out whether the RLS
# migration is safe to apply to the real database, because that database
# contains policies created by hand in the dashboard which no replica can
# reproduce. Run against production, its first version came back as three
# column headers and ZERO ROWS: no error, no findings, nothing to act on —
# which on a "is this safe to apply?" script is indistinguishable from "all
# clear", and is the most dangerous possible output.
#
# Two causes, both now fixed, both regression-tested here:
#
#   1. Findings were returned as a result set and then rolled back. A client
#      that had not materialised the rows got nothing.
#   2. Any unhandled error aborted the transaction and destroyed every finding
#      gathered so far.
#
# "It emits a verdict" is therefore not a detail — it is the property the whole
# artefact depends on, so it is gated rather than assumed.
# ============================================================================
set -euo pipefail

PGBIN="${PGBIN:-/usr/lib/postgresql/16/bin}"
PGROOT="${PGROOT:-/var/lib/postgresql/dryruntest}"
PORT="${PGPORT:-5434}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB=prodlike

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
   "$REPO"/scripts/rls_production_dryrun.sql "$PGROOT/"
chown -R postgres:postgres "$PGROOT"

psql_q() { su postgres -s /bin/bash -c \
  "$PGBIN/psql -h $PGROOT/sock -p $PORT -U postgres -d $DB -tAc \"$1\""; }
psql_c() { su postgres -s /bin/bash -c \
  "$PGBIN/psql -h $PGROOT/sock -p $PORT -U postgres -d $DB -q -c \"$1\"" >/dev/null; }
psql_f() { su postgres -s /bin/bash -c \
  "$PGBIN/psql -h $PGROOT/sock -p $PORT -U postgres -d $DB -q -f $PGROOT/$1" 2>&1; }

su postgres -s /bin/bash -c "$PGBIN/psql -h $PGROOT/sock -p $PORT -U postgres -c 'CREATE DATABASE $DB'" >/dev/null

echo "▶ Replaying the migration history to build a production-shaped replica"
for f in test_rls_migration.sql \
         20260720000000_initial_schema.sql \
         phase1_foundation.sql \
         phase2_assigned_responders.sql \
         phase3_profile_columns_and_config.sql; do
  # `supabase_realtime` does not exist off-Supabase; those ALTER PUBLICATION
  # lines are the only expected failures and are irrelevant to RLS.
  psql_f "$f" | grep -E '^(psql:.*)?ERROR' | grep -v 'supabase_realtime' || true
done

# Supabase grants these to anon/authenticated by default on the public schema.
# Without them every assertion hits "permission denied" and the replica is not
# production-shaped — which is exactly the condition that used to kill the run.
psql_c "GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO anon, authenticated"

# Two real users, so the command and citizen assertions actually exercise.
psql_c "INSERT INTO auth.users(id,email) VALUES ('11111111-1111-1111-1111-111111111111','cmd@x'),('22222222-2222-2222-2222-222222222222','cit@x') ON CONFLICT DO NOTHING"
psql_c "INSERT INTO public.profiles(id,email,full_name,role) VALUES ('11111111-1111-1111-1111-111111111111','cmd@x','Cdr Test','HQ_COMMAND'),('22222222-2222-2222-2222-222222222222','cit@x','Citizen Test','CITIZEN') ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role"

FAIL=0
before=$(psql_q "select count(*) from pg_policies where schemaname='public'")

# ── 1. A clean replica must produce SAFE TO APPLY ───────────────────────────
echo "▶ Case 1: clean replica — expect a verdict of SAFE TO APPLY"
out=$(psql_f rls_production_dryrun.sql || true)
if ! grep -q 'RLS DRY RUN' <<<"$out"; then
  echo "::error::the dry run produced NO verdict at all — this is the silent-failure regression"
  printf '%s\n' "$out" | tail -20
  FAIL=1
elif ! grep -q 'SAFE TO APPLY' <<<"$out"; then
  echo "::error::expected SAFE TO APPLY on a clean replica"
  printf '%s\n' "$out" | sed -n '/RLS DRY RUN/,/Nothing was kept/p'
  FAIL=1
else
  echo "  ok: verdict emitted — SAFE TO APPLY"
fi

# ── 2. It must DETECT a hand-made policy the migration cannot drop ──────────
# This is finding C-3 in one line: a policy created in the dashboard is not in
# the migration's DROP-by-name list, survives it, and re-opens the table.
echo "▶ Case 2: hand-made 'authenticated USING(true)' on profiles — expect DO NOT APPLY"
psql_c "CREATE POLICY zz_ci_hand_made_open ON public.profiles FOR SELECT TO authenticated USING (true)"
out=$(psql_f rls_production_dryrun.sql || true)
if ! grep -q 'DO NOT APPLY' <<<"$out"; then
  echo "::error::the dry run did NOT detect a surviving open policy — it cannot do its job"
  printf '%s\n' "$out" | sed -n '/RLS DRY RUN/,/Nothing was kept/p'
  FAIL=1
elif ! grep -q 'citizen sees too many profiles' <<<"$out"; then
  echo "::error::DO NOT APPLY was reported, but not for the reason expected"
  printf '%s\n' "$out" | sed -n '/RLS DRY RUN/,/Nothing was kept/p'
  FAIL=1
else
  echo "  ok: detected — citizen could read every profile"
fi
psql_c "DROP POLICY zz_ci_hand_made_open ON public.profiles"

# ── 3. A mid-script failure must not silence the whole run ──────────────────
echo "▶ Case 3: revoke authenticated's SELECT — expect findings, NOT silence"
psql_c "REVOKE SELECT ON public.profiles FROM authenticated"
out=$(psql_f rls_production_dryrun.sql || true)
if ! grep -q 'RLS DRY RUN' <<<"$out"; then
  echo "::error::an assertion failure silenced the entire dry run — the guards regressed"
  printf '%s\n' "$out" | tail -20
  FAIL=1
elif ! grep -q 'could not run' <<<"$out"; then
  echo "::error::the failure was not reported as a finding"
  printf '%s\n' "$out" | sed -n '/RLS DRY RUN/,/Nothing was kept/p'
  FAIL=1
else
  echo "  ok: the failure was recorded as a PROBLEM instead of aborting the run"
fi
psql_c "GRANT SELECT ON public.profiles TO authenticated"

# ── 4. Nothing may persist, across all three runs ──────────────────────────
echo "▶ Case 4: the database must be untouched"
after=$(psql_q "select count(*) from pg_policies where schemaname='public'")
leaked=$(psql_q "select count(*) from pg_policies where policyname in ('profiles_select_self_or_staff','alerts_select_own_or_staff','telemetry_select_self_or_staff')")
if [ "$before" != "$after" ]; then
  echo "::error::policy count changed: $before -> $after. THE DRY RUN COMMITTED SOMETHING."
  FAIL=1
elif [ "$leaked" != "0" ]; then
  echo "::error::migration policies persisted ($leaked). THE DRY RUN COMMITTED SOMETHING."
  FAIL=1
else
  echo "  ok: $before policies before, $after after; no migration policy persisted"
fi

if [ "$FAIL" -ne 0 ]; then
  echo
  echo "✗ The production dry run cannot be trusted. Do not send it to an operator."
  exit 1
fi
echo
echo "✓ The dry run reports a verdict, detects a re-opened table, survives an"
echo "  assertion failure, and keeps nothing."
