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

cp "$REPO"/supabase/migrations/*.sql "$REPO"/scripts/test_rls_migration.sql \
   "$REPO"/scripts/which_migrations_are_applied.sql \
   "$REPO"/scripts/did_the_convergence_land.sql "$PGROOT/"
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

# ── 3. Resuming part-way, which is the only way this is ever actually used ───
#
# Both checks above start from a database with none of the parts. No operator is
# ever in that position: production has the first N and needs the rest, and that
# is the run that matters. It had never been tested, so the question an operator
# asks before pasting — "will applying only the last three work on the database
# I actually have?" — had no answer here.
#
# This builds that database, reproduces the live symptom on it, applies only the
# held-back parts, and requires the symptom to be gone. The symptom is the real
# one: telemetry_select_geo_lga_scoped exists on production with NO `TO` clause,
# which PostgreSQL records as TO PUBLIC, and PUBLIC includes anon. It is why the
# verdict table's one failing row reads
# `*** FAIL *** | no policy grants anon or public anything`.
#
# Planted WITHOUT a TO clause rather than by replaying 20260725, because that
# file has since been corrected to say TO authenticated and is guarded on the
# policy's own presence — replaying it would create the fixed version and prove
# nothing. normalise_lga is planted too: 20261016 refuses to drop a policy it
# cannot recreate, and on production that function is present from the same era
# the policy came from.
# HOW MANY TO HOLD BACK — DERIVED, NOT COUNTED.
#
# This was `HOLD_BACK=3`, which was right when there were 31 migrations: the
# held-back set then began at 20261016, the migration that FIXES the planted
# symptom. Adding a 32nd migration pushed 20261016 one place earlier, into the
# "already applied" group, so the symptom was repaired while the fixture was
# being built and the assertion below failed looking for a notice that had
# already been raised — a scenario that silently stopped testing what it says
# it tests, reported as a broken verifier.
#
# So the boundary is derived from the part that matters: hold back everything
# from 20261016 onwards. Adding a migration now extends the held-back set
# instead of shifting it.
RESUME_DB=resumelike
SYMPTOM_PART=$(ls "$PGROOT/parts" | grep -n '20261016000000' | cut -d: -f1)
[ -n "$SYMPTOM_PART" ] || {
  echo "::error::no part applies 20261016000000 — this scenario plants the symptom that migration repairs, so it cannot mean anything without it" >&2
  exit 2; }
FIRST_RUN=$((SYMPTOM_PART - 1))        # every part BEFORE the one that repairs it
HOLD_BACK=$((COUNT - FIRST_RUN - 1))   # the rest, excluding VERIFY
VERIFY_PART=$(ls "$PGROOT/parts" | tail -1)

psql_db() { su postgres -s /bin/bash -c \
  "$PGBIN/psql -h $PGROOT/sock -p $PORT -U postgres -d $RESUME_DB $*" 2>&1; }

echo "▶ Building a database that has the first $FIRST_RUN parts and not the last $HOLD_BACK"
su postgres -s /bin/bash -c \
  "$PGBIN/psql -h $PGROOT/sock -p $PORT -U postgres -c 'CREATE DATABASE $RESUME_DB'" >/dev/null
psql_db "-q -f $PGROOT/test_rls_migration.sql" >/dev/null
psql_db "-tAc 'CREATE PUBLICATION supabase_realtime;'" >/dev/null
for f in 20260720000000_initial_schema phase1_foundation \
         phase2_assigned_responders phase3_profile_columns_and_config; do
  psql_db "-q -f $PGROOT/$f.sql" >/dev/null 2>&1 || true
done
i=0
for f in "$PGROOT"/parts/*.sql; do
  i=$((i + 1))
  [ "$i" -le "$FIRST_RUN" ] || break
  OUT=$(psql_db "-q -v ON_ERROR_STOP=1 -f $f") || {
    printf '%s\n' "$OUT" | grep -E "ERROR|FATAL" | head -3
    echo "::error::part $(basename "$f") failed while building the resume fixture"
    exit 1; }
done
echo "  ok: parts 1..$FIRST_RUN applied"

cat > "$PGROOT/plant_live_symptom.sql" <<'PLANT'
CREATE OR REPLACE FUNCTION public.normalise_lga(lga TEXT)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $fn$
  SELECT NULLIF(TRIM(REGEXP_REPLACE(UPPER(COALESCE(lga, '')), '\s+', ' ', 'g')), '')
$fn$;
-- No TO clause, exactly as production has it.
CREATE POLICY "telemetry_select_geo_lga_scoped"
  ON public.telemetry FOR SELECT USING (true);

-- And the rest of the era residue production carries, which the parts alone do
-- not create: the five generated mirrors of geo_* and the two v5 functions whose
-- only callers were policies 20260813 drops by name.
--
-- Planting these is what makes the 20261018 row of
-- did_the_convergence_land.sql mean anything on this fixture. Without them its
-- "all 5 generated mirrors and both functions are gone" was trivially true
-- BEFORE that migration ran — true of a database that never had them — and the
-- rehearsal happily asserted a check that could not fail. Production has them
-- at ordinals 28-30 on alerts, which is why a 428C9 error there names `lga`
-- where this harness names `category`.
ALTER TABLE public.alerts
  ADD COLUMN lga  TEXT GENERATED ALWAYS AS (geo_lga)  STORED,
  ADD COLUMN ward TEXT GENERATED ALWAYS AS (geo_ward) STORED,
  ADD COLUMN pu   TEXT GENERATED ALWAYS AS (geo_pu)   STORED;
ALTER TABLE public.profiles
  ADD COLUMN lga  TEXT GENERATED ALWAYS AS (geo_lga)  STORED,
  ADD COLUMN ward TEXT GENERATED ALWAYS AS (geo_ward) STORED;
CREATE FUNCTION public.is_hq_or_admin() RETURNS boolean LANGUAGE sql AS $f1$ SELECT true $f1$;
CREATE FUNCTION public.is_responder()   RETURNS boolean LANGUAGE sql AS $f2$ SELECT true $f2$;
PLANT
chown postgres:postgres "$PGROOT/plant_live_symptom.sql"
psql_db "-q -v ON_ERROR_STOP=1 -f $PGROOT/plant_live_symptom.sql" >/dev/null || {
  echo "::error::could not plant the live symptom — the rehearsal cannot run"; exit 1; }

# The fixture must now show the symptom, or the rest proves nothing.
BEFORE=$(psql_db "-f $PGROOT/parts/$VERIFY_PART")
printf '%s\n' "$BEFORE" \
  | grep -q 'FAIL \*\*\* | no policy grants anon or public anything — telemetry.telemetry_select_geo_lga_scoped' || {
  printf '%s\n' "$BEFORE" | grep -E 'anon or public' | sed 's/^/    /'
  echo "::error::the fixture does not reproduce the live FAIL, so clearing it proves nothing"
  exit 1; }
echo "  reproduced: *** FAIL *** naming telemetry.telemetry_select_geo_lga_scoped"

# The three migrations announce themselves with RAISE NOTICE, which the Supabase
# SQL editor does not display — an operator who pastes them sees three identical
# `Success. No rows returned` results. scripts/did_the_convergence_land.sql is
# the readable answer, and it is only worth anything if it can say FAIL, so it is
# asked here BEFORE the parts are applied.
LANDED_BEFORE=$(psql_db "-f $PGROOT/did_the_convergence_land.sql")
for needle in '20261016' '20261018'; do
  printf '%s\n' "$LANDED_BEFORE" | grep -F "$needle" | grep -q 'FAIL' || {
    printf '%s\n' "$LANDED_BEFORE" | sed 's/^/    /'
    echo "::error::did_the_convergence_land.sql does not report $needle as unapplied on a database that lacks it"
    exit 1; }
done
echo "  and did_the_convergence_land.sql reports 20261016 and 20261018 as NOT applied"

echo "▶ Applying only the last $HOLD_BACK parts, as an operator would"
RESUME_OUT=""
i=0
for f in "$PGROOT"/parts/*.sql; do
  i=$((i + 1))
  [ "$i" -gt "$FIRST_RUN" ] || continue
  [ "$(basename "$f")" != "$VERIFY_PART" ] || continue
  OUT=$(psql_db "-v ON_ERROR_STOP=1 -f $f") || {
    printf '%s\n' "$OUT" | grep -E "ERROR|FATAL" | head -5
    echo "::error::part $(basename "$f") failed on a database that has the earlier parts"
    exit 1; }
  echo "  ok: $(basename "$f")"
  RESUME_OUT="$RESUME_OUT
$OUT"
done

# Each held-back migration announces what it did. A silent run means a guard
# skipped it, which on this fixture would be wrong.
for needle in \
  'telemetry_select_geo_lga_scoped is now scoped TO authenticated' \
  'generated mirrors: 5 dropped' \
  'alerts generated columns now: category'; do
  printf '%s\n' "$RESUME_OUT" | grep -qF "$needle" || {
    printf '%s\n' "$RESUME_OUT" | grep -E 'NOTICE|WARNING' | sed 's/^/    /' | head -20
    echo "::error::expected notice not raised: $needle"
    exit 1; }
  echo "  said: $needle"
done

AFTER_RESUME=$(psql_db "-f $PGROOT/parts/$VERIFY_PART")
R_PASS=$(printf '%s\n' "$AFTER_RESUME" | grep -c '^ PASS' || true)
R_FAIL=$(printf '%s\n' "$AFTER_RESUME" | grep -c '\*\*\* FAIL \*\*\*' || true)
echo "  checks passed: $R_PASS / $EXPECTED   failed: $R_FAIL"
if [ "$R_FAIL" -ne 0 ] || [ "$R_PASS" -lt "$EXPECTED" ]; then
  printf '%s\n' "$AFTER_RESUME" | grep -E '\*\*\* FAIL' | sed 's/^/    /' || true
  echo "::error::resuming from part $FIRST_RUN did not land the same verdict as the full run"
  exit 1
fi

# And the drops must read as done, which is the only signal a drop-only
# migration can give (T-21).
INV=$(psql_db "-f $PGROOT/which_migrations_are_applied.sql")
printf '%s\n' "$INV" | grep -qE '7 of 7 removed' || {
  printf '%s\n' "$INV" | grep -F '20261018000000' | sed 's/^/    /'
  echo "::error::the inventory does not report the removals as done"; exit 1; }
printf '%s\n' "$INV" | grep -q 'still present' && {
  printf '%s\n' "$INV" | grep 'still present' | sed 's/^/    /'
  echo "::error::objects the last part removes are still in the schema"; exit 1; }
echo "  and the inventory reports 7 of 7 removed, with nothing still present"

LANDED_AFTER=$(psql_db "-f $PGROOT/did_the_convergence_land.sql")
printf '%s\n' "$LANDED_AFTER" | grep -q 'FAIL' && {
  printf '%s\n' "$LANDED_AFTER" | sed 's/^/    /'
  echo "::error::did_the_convergence_land.sql still reports a failure after all three applied"
  exit 1; }
for needle in '20261016' '20261017' '20261018'; do
  printf '%s\n' "$LANDED_AFTER" | grep -F "$needle" | grep -q 'PASS' || {
    printf '%s\n' "$LANDED_AFTER" | sed 's/^/    /'
    echo "::error::did_the_convergence_land.sql does not report $needle as applied"
    exit 1; }
done
# It must also name the generated column a 428C9 would report here.
printf '%s\n' "$LANDED_AFTER" | grep -q 'alerts generated columns now' || {
  echo "::error::did_the_convergence_land.sql dropped its generated-column row"; exit 1; }
echo "  and did_the_convergence_land.sql reports all three applied"

echo
echo "✓ the $COUNT parts apply in order and report $PASSED/$EXPECTED PASS — the same"
echo "  verdict the single paste gives, and re-running them cannot break it."
echo "✓ and on a database holding the first $FIRST_RUN parts with the live TO PUBLIC"
echo "  policy planted, applying only the last $HOLD_BACK clears the FAIL and reports"
echo "  $R_PASS/$EXPECTED PASS."
