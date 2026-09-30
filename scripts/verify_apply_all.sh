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

echo "▶ Running it a second time (the RLS part is atomic, so it rolls back and says so)"
OUT2=$(run_pasted) && RC2=0 || RC2=$?
if [ "$RC2" -ne 0 ]; then
  printf '%s\n' "$OUT2" | grep -E "ERROR|FATAL" | head -20
  echo "::error::re-running the apply script failed — it is not idempotent"; exit 1
fi
FAILED2=$(printf '%s\n' "$OUT2" | grep -c '\*\*\* FAIL \*\*\*' || true)
[ "$FAILED2" -eq 0 ] || {
  echo "::error::second run reported failures"; exit 1; }

# ── The anon/public check must NAME what it found ────────────────────────────
#
# A live database came back with `*** FAIL *** | no policy grants anon or public
# anything` and nothing else — no table, no policy name, no way to tell a
# hand-made policy from one of ours. The operator could do nothing with that.
#
# The row carries the names now, and this proves it by planting one. `public` in
# pg_policies.roles is what a CREATE POLICY with no TO clause produces, which is
# the shape an over-broad policy usually arrives in — nobody writes TO anon on
# purpose.
echo "▶ Planting a TO PUBLIC policy, to prove the check names what it finds"
psql_c() { su postgres -s /bin/bash -c \
  "$PGBIN/psql -h $PGROOT/sock -p $PORT -U postgres -d $DB -q -c \"$1\""; }
psql_c "CREATE POLICY zz_mutation_probe ON public.app_config FOR SELECT USING (true)" >/dev/null
MUT=$(run_pasted)
psql_c "DROP POLICY zz_mutation_probe ON public.app_config" >/dev/null

ROW=$(printf '%s\n' "$MUT" | grep "no policy grants anon or public" || true)
printf '%s\n' "$ROW" | sed 's/^/    /'
case "$ROW" in
  *'*** FAIL ***'*) ;;
  *) echo "::error::a TO PUBLIC policy did not fail the check — it is not testing anything"
     exit 1 ;;
esac
case "$ROW" in
  *app_config.zz_mutation_probe*) ;;
  *) echo "::error::the check failed but did not name app_config.zz_mutation_probe"
     exit 1 ;;
esac
# And the planted policy must be gone again, or every later run inherits it.
STILL=$(run_pasted | grep -c "zz_mutation_probe" || true)
[ "$STILL" -eq 0 ] || {
  echo "::error::the probe policy outlived the check"; exit 1; }
echo "  ok: the check fails and names the policy"

# ── phase1 applied out of order, and the repair ──────────────────────────────
#
# A live database failed check 2 after a paste. The run before it had ended with
# `Phase 3 profile columns & app_config migration complete` — the last line of
# phase3_foundation's sibling — which means supabase/rainbow_full_migration.sql
# had been pasted, and that file used to apply phase1/2/3 at sections 29–31,
# twenty-one sections AFTER 20260813000000_rls_least_privilege.
#
# phase1 creates seven policies with no `TO` clause. In PostgreSQL that is TO
# PUBLIC, and PUBLIC includes anon. 20260813 drops all seven by name and creates
# scoped replacements, so running phase1 afterwards puts every one of them back.
#
# This reproduces that exactly, and then proves the remedy: re-pasting
# apply_all_migrations.sql closes them again, because 20260813 is in it.
#
# It also establishes the negative, which is the part that matters when reading a
# live failure: because the repair is INSIDE the paste, the paste's own verdict
# can never report the phase1 seven. 20260813 drops them long before the
# verification block at the end runs. So a `*** FAIL *** | no policy grants anon
# or public anything` coming back from a real paste is NOT phase1 applied out of
# order — whatever it is, it survives 20260813, which means it is not one of the
# 78 names that migration drops. That rules out every policy in the migration
# history and leaves something created outside it.
REOPENED="chat_read chat_insert telemetry_own_upsert telemetry_read_all \
safe_zones_read uninstall_insert uninstall_read"

anon_public_policies() {
  su postgres -s /bin/bash -c "$PGBIN/psql -h $PGROOT/sock -p $PORT -U postgres \
    -d $DB -tAc \"select policyname from pg_policies where schemaname='public' \
    and ('anon' = any(roles) or 'public' = any(roles)) order by policyname;\""
}

echo "▶ Re-applying phase1 out of order, as the old full-migration bundle did"
psql_f phase1_foundation.sql >/dev/null 2>&1 || true
AFTER_PHASE1=$(anon_public_policies)
for name in $REOPENED; do
  printf '%s\n' "$AFTER_PHASE1" | grep -qx "$name" || {
    echo "::error::expected phase1 to re-open $name as TO PUBLIC — it did not, so"
    echo "  this test is no longer reproducing the failure it was written for"
    exit 1; }
done
echo "  reproduced: $(printf '%s\n' "$AFTER_PHASE1" | grep -c .) policies now reach anon/public"

echo "▶ Re-pasting the apply script, which is the repair"
FIXED=$(run_pasted)
# The verdict must be CLEAN, not a named failure. A first draft of this test
# expected the check to fail here and name the seven, and it reported PASS —
# correctly, because 20260813 runs inside the same paste and drops them before
# the verification block is reached. Asserting the pass is the honest assertion,
# and it is what rules phase1 out as the explanation for a live FAIL.
VERDICT=$(printf '%s\n' "$FIXED" | grep "no policy grants anon or public" || true)
printf '%s\n' "$VERDICT" | sed 's/^/    /'
case "$VERDICT" in
  *'PASS'*) ;;
  *) echo "::error::re-pasting left the anon/public check failing"; exit 1 ;;
esac
LEFT=$(anon_public_policies | grep -c . || true)
[ "$LEFT" -eq 0 ] || {
  echo "::error::$LEFT policy/policies still reach anon or public after the repair"
  anon_public_policies | sed 's/^/    /'
  exit 1; }
FIXED_FAILS=$(printf '%s\n' "$FIXED" | grep -c '\*\*\* FAIL \*\*\*' || true)
[ "$FIXED_FAILS" -eq 0 ] || {
  printf '%s\n' "$FIXED" | grep '\*\*\* FAIL \*\*\*'
  echo "::error::re-pasting did not restore a clean verdict"; exit 1; }
echo "  ok: re-pasting apply_all_migrations.sql drops all seven and reports clean"

echo
echo "✓ apply_all_migrations.sql applies cleanly in one paste, twice over,"
echo "  its own verification reports $PASSED/$EXPECTED PASS, the anon/public"
echo "  check names the policy it objects to, and re-pasting repairs a database"
echo "  where phase1 was applied after the least-privilege migration."
