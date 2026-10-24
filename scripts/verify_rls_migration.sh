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

# Before any database is started: no SQL in the repository may insert into a
# table with a generated column without naming its columns. PostgreSQL refuses
# such a statement outright with 428C9, and the form that gets written by
# accident — `INSERT INTO public.alerts SELECT * FROM <copy>` — never mentions
# the generated column at all, so the error arrives from a statement that looks
# unrelated to it.
echo "▶ Checking nothing from the hand-applied era is production-only"
python3 "$REPO/scripts/check_schema_convergence.py"

echo "▶ Checking no INSERT targets a generated column"
python3 "$REPO/scripts/check_generated_column_inserts.py"

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
   "$REPO"/scripts/production_readiness_behaviour_test.sql \
   "$REPO"/scripts/signup_role_escalation_test.sql \
   "$REPO"/scripts/command_chain_behaviour_test.sql \
   "$REPO"/scripts/privacy_behaviour_test.sql \
   "$REPO"/scripts/sms_device_keys_behaviour_test.sql \
   "$REPO"/scripts/mesh_ingest_behaviour_test.sql \
   "$REPO"/scripts/alert_category_behaviour_test.sql \
   "$REPO"/scripts/alert_scoping_behaviour_test.sql \
   "$REPO"/scripts/ward_handdown_behaviour_test.sql \
   "$REPO"/scripts/new_incident_notice_behaviour_test.sql \
   "$REPO"/scripts/notification_outbox_behaviour_test.sql \
   "$REPO"/scripts/escalation_targets_behaviour_test.sql \
   "$REPO"/scripts/geo_key_behaviour_test.sql \
   "$REPO"/scripts/alert_media_behaviour_test.sql \
   "$REPO"/scripts/ussd_confirmation_behaviour_test.sql \
   "$REPO"/scripts/ussd_filing_behaviour_test.sql \
   "$REPO"/scripts/ai_reports_behaviour_test.sql \
   "$REPO"/scripts/oversight_behaviour_test.sql \
   "$REPO"/scripts/schema_convergence_behaviour_test.sql \
   "$REPO"/scripts/agency_delivery_behaviour_test.sql \
   "$REPO"/scripts/non_emergency_behaviour_test.sql \
   "$REPO"/scripts/policy_roles_behaviour_test.sql \
   "$REPO"/scripts/why_is_the_board_empty.sql \
   "$REPO"/scripts/why_did_my_insert_fail.sql \
   "$REPO"/scripts/which_migrations_are_applied.sql \
   "$REPO"/scripts/which_geography_is_real.sql \
   "$REPO"/scripts/seed_demo_incidents.sql "$PGROOT/"
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

echo "▶ Applying 20260927000000_signup_cannot_choose_role.sql"
psql_run "-f $PGROOT/20260927000000_signup_cannot_choose_role.sql" >/dev/null
echo "▶ Re-applying it (must be idempotent)"
psql_run "-f $PGROOT/20260927000000_signup_cannot_choose_role.sql" >/dev/null

# A stranger holding the anon key — which ships in the APK and the browser —
# must not be able to sign up AS A COMMANDER. The role guard is BEFORE UPDATE,
# and a signup never updates: it inserts.
echo "▶ Asserting a signup cannot choose its own role"
SIGNUP_OUT=$(psql_run "-f $PGROOT/signup_role_escalation_test.sql" 2>&1) && SIGNUP_RC=0 || SIGNUP_RC=$?
printf '%s\n' "$SIGNUP_OUT" | grep -E "PASS|FAIL|ALL SIGNUP" || true
if [ "$SIGNUP_RC" -ne 0 ]; then
  printf '%s\n' "$SIGNUP_OUT" | grep -vE "PASS" | tail -20
  echo "::error::a signup can choose its own role — privilege escalation"; exit 1
fi

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
echo "▶ Applying 20260903000003_alert_escalation_columns.sql"
psql_run "-f $PGROOT/20260903000003_alert_escalation_columns.sql" >/dev/null
echo "▶ Applying 20260903000004_profiles_badge_number.sql"
psql_run "-f $PGROOT/20260903000004_profiles_badge_number.sql" >/dev/null
echo "▶ Applying 20260903000005_alerts_assigned_tier.sql"
psql_run "-f $PGROOT/20260903000005_alerts_assigned_tier.sql" >/dev/null
echo "▶ Re-applying all six (they must be idempotent)"
psql_run "-f $PGROOT/20260903000000_realtime_publication.sql" >/dev/null
psql_run "-f $PGROOT/20260903000001_incident_media_storage.sql" >/dev/null
psql_run "-f $PGROOT/20260903000002_system_alerts_broadcast.sql" >/dev/null
psql_run "-f $PGROOT/20260903000003_alert_escalation_columns.sql" >/dev/null
psql_run "-f $PGROOT/20260903000004_profiles_badge_number.sql" >/dev/null
psql_run "-f $PGROOT/20260903000005_alerts_assigned_tier.sql" >/dev/null

# The command chain needs alerts.escalation_log, which 20260903000003 adds, so
# it applies after that set rather than with the RLS migration.
echo "▶ Applying 20260928000000_command_chain_escalation.sql"
psql_run "-f $PGROOT/20260928000000_command_chain_escalation.sql" >/dev/null
echo "▶ Re-applying it (must be idempotent)"
psql_run "-f $PGROOT/20260928000000_command_chain_escalation.sql" >/dev/null

# UNIT -> WARD -> LGA -> HQ, on a timeout, with HQ terminal. The timeouts were
# configured and dead before this; a test is the only thing that keeps them alive.
echo "▶ Asserting the command chain climbs, and stops"
CHAIN_OUT=$(psql_run "-f $PGROOT/command_chain_behaviour_test.sql" 2>&1) && CHAIN_RC=0 || CHAIN_RC=$?

echo "▶ Applying 20260929000000_telemetry_is_not_a_standing_feed.sql"
psql_run "-f $PGROOT/20260929000000_telemetry_is_not_a_standing_feed.sql" >/dev/null
echo "▶ Re-applying it (must be idempotent)"
psql_run "-f $PGROOT/20260929000000_telemetry_is_not_a_standing_feed.sql" >/dev/null

echo "▶ Applying 20260930000000_sms_device_keys.sql"
psql_run "-f $PGROOT/20260930000000_sms_device_keys.sql" >/dev/null
echo "▶ Re-applying it (must be idempotent)"
psql_run "-f $PGROOT/20260930000000_sms_device_keys.sql" >/dev/null

echo "▶ Asserting nobody can get at an SMS device key"
SMS_OUT=$(psql_run "-f $PGROOT/sms_device_keys_behaviour_test.sql" 2>&1) && SMS_RC=0 || SMS_RC=$?
echo "$SMS_OUT" | grep -E "PASS|FAIL|ERROR" || true
if [ "$SMS_RC" -ne 0 ]; then
  echo "$SMS_OUT"
  echo "✗ SMS device key assertions failed"
  exit 1
fi

echo "▶ Applying 20261001000000_mesh_ingest.sql"
psql_run "-f $PGROOT/20261001000000_mesh_ingest.sql" >/dev/null
echo "▶ Re-applying it (must be idempotent)"
psql_run "-f $PGROOT/20261001000000_mesh_ingest.sql" >/dev/null

echo "▶ Applying 20261002000000_sim_channel_events.sql"
psql_run "-f $PGROOT/20261002000000_sim_channel_events.sql" >/dev/null
echo "▶ Re-applying it (must be idempotent)"
psql_run "-f $PGROOT/20261002000000_sim_channel_events.sql" >/dev/null

# An agency liaison is an officer of ANOTHER organisation, and is_staff() is
# "role is not CITIZEN" — so every alerts policy that said `OR is_staff()` gave
# them the whole state, to read AND to write. This narrows it; the production
# readiness test below is what proves it.
echo "▶ Applying 20261003000000_liaisons_are_not_staff.sql"
psql_run "-f $PGROOT/20261003000000_liaisons_are_not_staff.sql" >/dev/null
echo "▶ Re-applying it (must be idempotent)"
psql_run "-f $PGROOT/20261003000000_liaisons_are_not_staff.sql" >/dev/null

# An SOS starts a track and the database kept only the latest point, so the
# trail existed in one browser tab's memory and nowhere else.
echo "▶ Applying 20261004000000_incident_tracks.sql"
psql_run "-f $PGROOT/20261004000000_incident_tracks.sql" >/dev/null
echo "▶ Re-applying it (must be idempotent)"
psql_run "-f $PGROOT/20261004000000_incident_tracks.sql" >/dev/null

# The category a citizen picked was only ever a prefix inside the free-text
# `type` column, so a dispatcher could not sort by it. This adds it as a STORED
# GENERATED column, which also backfills every historical row.
echo "▶ Applying 20261005000000_alert_category.sql"
psql_run "-f $PGROOT/20261005000000_alert_category.sql" >/dev/null
echo "▶ Re-applying it (must be idempotent)"
psql_run "-f $PGROOT/20261005000000_alert_category.sql" >/dev/null

echo "▶ Asserting the incident category is derived, backfilled and unwritable"
CAT_OUT=$(psql_run "-f $PGROOT/alert_category_behaviour_test.sql" 2>&1) && CAT_RC=0 || CAT_RC=$?
echo "$CAT_OUT" | grep -E "PASS|FAIL|ERROR" || true
if [ "$CAT_RC" -ne 0 ]; then
  echo "$CAT_OUT"
  echo "✗ alert category assertions failed"
  exit 1
fi

# The command chain had structure for ROUTING and none for AUTHORITY: is_staff()
# means "not a citizen", so every officer at every tier could read AND write
# every incident in the state.
# Applied FIRST, because production has it: it adds an LGA-wide permissive
# policy that the scoping migration below has to remove. Testing the scoping
# without it present is testing a database nobody runs.
echo "▶ Applying 20260725000000_v6_geo_lga_scoping_staging.sql"
psql_run "-f $PGROOT/20260725000000_v6_geo_lga_scoping_staging.sql" >/dev/null 2>&1 || \
  echo "  (v6 not applicable here; continuing)"

echo "▶ Applying 20261006000000_alerts_scoped_to_posting.sql"
psql_run "-f $PGROOT/20261006000000_alerts_scoped_to_posting.sql" >/dev/null
echo "▶ Re-applying it (must be idempotent)"
psql_run "-f $PGROOT/20261006000000_alerts_scoped_to_posting.sql" >/dev/null

echo "▶ Asserting an officer's authority ends at their command"
SCOPE_OUT=$(psql_run "-f $PGROOT/alert_scoping_behaviour_test.sql" 2>&1) && SCOPE_RC=0 || SCOPE_RC=$?
echo "$SCOPE_OUT" | grep -E "PASS|FAIL|ERROR" || true
if [ "$SCOPE_RC" -ne 0 ]; then
  echo "$SCOPE_OUT"
  echo "✗ alert scoping assertions failed"
  exit 1
fi

# The timeout escalation moved the incident and told nobody: every notification
# in this system is sent by a human pressing a button in the console.
echo "▶ Applying 20261007000000_notification_outbox.sql"
psql_run "-f $PGROOT/20261007000000_notification_outbox.sql" >/dev/null
echo "▶ Re-applying it (must be idempotent)"
psql_run "-f $PGROOT/20261007000000_notification_outbox.sql" >/dev/null

echo "▶ Asserting an automatic escalation owes somebody a notification"
OUTBOX_OUT=$(psql_run "-f $PGROOT/notification_outbox_behaviour_test.sql" 2>&1) && OUTBOX_RC=0 || OUTBOX_RC=$?
echo "$OUTBOX_OUT" | grep -E "PASS|FAIL|ERROR" || true
if [ "$OUTBOX_RC" -ne 0 ]; then
  echo "$OUTBOX_OUT"
  echo "✗ notification outbox assertions failed"
  exit 1
fi

# drain-outbox marked every TIER_ESCALATION delivered without telling anybody.
echo "▶ Applying 20261008000000_escalation_push_targets.sql"
psql_run "-f $PGROOT/20261008000000_escalation_push_targets.sql" >/dev/null
psql_run "-f $PGROOT/20261008000000_escalation_push_targets.sql" >/dev/null

echo "▶ Asserting a queued escalation reaches the right officers"
ESC_OUT=$(psql_run "-f $PGROOT/escalation_targets_behaviour_test.sql" 2>&1) && ESC_RC=0 || ESC_RC=$?
echo "$ESC_OUT" | grep -E "PASS|FAIL|ERROR" || true
if [ "$ESC_RC" -ne 0 ]; then
  echo "$ESC_OUT"; echo "✗ escalation target assertions failed"; exit 1
fi

# The app writes ward names from the GPS asset (GINDIRI  I) and officers are
# posted from the tactical map (GINDIRI  1). alert_in_my_area() compared them
# raw, so four Mangu wards had no supervision and nothing said so.
echo "▶ Applying 20261009000000_ward_names_compared_by_key.sql"
psql_run "-f $PGROOT/20261009000000_ward_names_compared_by_key.sql" >/dev/null
psql_run "-f $PGROOT/20261009000000_ward_names_compared_by_key.sql" >/dev/null

echo "▶ Asserting a ward is matched by key, not by spelling"
GEOK_OUT=$(psql_run "-f $PGROOT/geo_key_behaviour_test.sql" 2>&1) && GEOK_RC=0 || GEOK_RC=$?
echo "$GEOK_OUT" | grep -E "PASS|FAIL|ERROR" || true
if [ "$GEOK_RC" -ne 0 ]; then
  echo "$GEOK_OUT"; echo "✗ ward key assertions failed"; exit 1
fi

# Three places appended to alerts.media_urls with read-modify-write, so two
# overlapping uploads erased each other while the UI said the evidence was sent.
echo "▶ Applying 20261010000000_append_alert_media_atomically.sql"
psql_run "-f $PGROOT/20261010000000_append_alert_media_atomically.sql" >/dev/null
psql_run "-f $PGROOT/20261010000000_append_alert_media_atomically.sql" >/dev/null

echo "▶ Asserting two uploads cannot erase each other"
MEDIA_OUT=$(psql_run "-f $PGROOT/alert_media_behaviour_test.sql" 2>&1) && MEDIA_RC=0 || MEDIA_RC=$?
echo "$MEDIA_OUT" | grep -E "PASS|FAIL|ERROR" || true
if [ "$MEDIA_RC" -ne 0 ]; then
  echo "$MEDIA_OUT"; echo "✗ evidence append assertions failed"; exit 1
fi

# USSD is the cheapest way to lure responders to a chosen place: no install, no
# data, a cheap SIM, and the report looks exactly like a real one. The control is
# that no TIMER may turn an unconfirmed USSD report into a deployment.
echo "▶ Applying 20261011000000_ussd_reports_are_unconfirmed.sql"
psql_run "-f $PGROOT/20261011000000_ussd_reports_are_unconfirmed.sql" >/dev/null
psql_run "-f $PGROOT/20261011000000_ussd_reports_are_unconfirmed.sql" >/dev/null

echo "▶ Asserting a USSD report cannot escalate itself to a commander"
USSD_OUT=$(psql_run "-f $PGROOT/ussd_confirmation_behaviour_test.sql" 2>&1) && USSD_RC=0 || USSD_RC=$?
echo "$USSD_OUT" | grep -E "PASS|FAIL|ERROR" || true
if [ "$USSD_RC" -ne 0 ]; then
  echo "$USSD_OUT"; echo "✗ USSD confirmation assertions failed"; exit 1
fi

# A gateway that does not get a reply inside its window re-POSTs the same session
# with the same input. On a congested network that is normal operation — which is
# exactly when people report emergencies.
echo "▶ Applying 20261012000000_ussd_filing.sql"
psql_run "-f $PGROOT/20261012000000_ussd_filing.sql" >/dev/null
psql_run "-f $PGROOT/20261012000000_ussd_filing.sql" >/dev/null

echo "▶ Applying 20261013000000_ussd_landmark.sql"
psql_run "-f $PGROOT/20261013000000_ussd_landmark.sql" >/dev/null
psql_run "-f $PGROOT/20261013000000_ussd_landmark.sql" >/dev/null

echo "▶ Asserting a gateway retry cannot raise the same emergency twice"
UFIL_OUT=$(psql_run "-f $PGROOT/ussd_filing_behaviour_test.sql" 2>&1) && UFIL_RC=0 || UFIL_RC=$?
echo "$UFIL_OUT" | grep -E "PASS|FAIL|ERROR" || true
if [ "$UFIL_RC" -ne 0 ]; then
  echo "$UFIL_OUT"; echo "✗ USSD filing assertions failed"; exit 1
fi

# The forensic summary used to live in React state and nowhere else. Now the
# server that called the model writes it — and the control is that nobody signed
# in can, or an operator could put words in the model's mouth in the audit record.
echo "▶ Applying 20261014000000_ai_reports_are_kept.sql"
psql_run "-f $PGROOT/20261014000000_ai_reports_are_kept.sql" >/dev/null
psql_run "-f $PGROOT/20261014000000_ai_reports_are_kept.sql" >/dev/null

echo "▶ Asserting nobody can put words in the model's mouth"
AIR_OUT=$(psql_run "-f $PGROOT/ai_reports_behaviour_test.sql" 2>&1) && AIR_RC=0 || AIR_RC=$?
echo "$AIR_OUT" | grep -E "PASS|NOTE|FAIL|ERROR" || true
if [ "$AIR_RC" -ne 0 ]; then
  echo "$AIR_OUT"; echo "✗ AI report assertions failed"; exit 1
fi

# 'Police brutality' is a reportable category, and it routed like a flood: to the
# local ward, the local LGA, and every responder posted there — which may include
# the officer complained about — with the complainant's number on the dossier.
echo "▶ Applying 20261015000000_oversight_and_debrief.sql"
psql_run "-f $PGROOT/20261015000000_oversight_and_debrief.sql" >/dev/null
psql_run "-f $PGROOT/20261015000000_oversight_and_debrief.sql" >/dev/null

# audit_trail() took the actor from `by`, which only the SQL writers set — both
# apps write `by_email`, so every escalation a PERSON performed was attributed to
# SYSTEM. Applied here, right after the migration that creates the function,
# because the oversight assertions below are what caught it and they have to run
# against the fixed one.
echo "▶ Applying 20261019000000_the_audit_trail_names_who_acted.sql"
psql_run "-f $PGROOT/20261019000000_the_audit_trail_names_who_acted.sql" >/dev/null
echo "▶ Re-applying it (must be idempotent)"
psql_run "-f $PGROOT/20261019000000_the_audit_trail_names_who_acted.sql" >/dev/null

# The single policy on a live database that PUBLIC could reach. Applied twice,
# like the rest, because the operator repairing a database may well paste it
# twice and a DROP/CREATE pair has to survive that.
echo "▶ Applying 20261016000000_telemetry_policy_is_not_public.sql"
psql_run "-f $PGROOT/20261016000000_telemetry_policy_is_not_public.sql" >/dev/null
psql_run "-f $PGROOT/20261016000000_telemetry_policy_is_not_public.sql" >/dev/null

# Asserted here as well as in the end-of-replay sweep below, because this is the
# migration whose whole purpose it is: the policy must exist, and must be scoped
# to authenticated rather than recorded as TO PUBLIC.
TELEM_ROLES=$(su postgres -s /bin/bash -c "psql -h $PGROOT/sock -p $PORT -U postgres -d rainbow -tAc \
  \"select roles::text from pg_policies where schemaname='public' \
    and tablename='telemetry' and policyname='telemetry_select_geo_lga_scoped';\"")
[ "$TELEM_ROLES" = "{authenticated}" ] || {
  echo "✗ telemetry_select_geo_lga_scoped is $TELEM_ROLES, expected {authenticated}"
  exit 1; }
echo "  PASS  telemetry_select_geo_lga_scoped is scoped TO authenticated"

# The v2–v6 era was applied to production by hand and cannot be replayed from
# zero, so the live database had objects no database this repository could build.
# That difference decided a 428C9 column name, hid a TO PUBLIC policy from a
# passing assertion, and put a wrong conclusion into a code comment.
echo "▶ Applying 20261017000000_the_hand_applied_era_is_in_the_history.sql"
psql_run "-f $PGROOT/20261017000000_the_hand_applied_era_is_in_the_history.sql" >/dev/null
psql_run "-f $PGROOT/20261017000000_the_hand_applied_era_is_in_the_history.sql" >/dev/null

# And then converge DOWNWARD, as asked: the five generated mirrors hold no
# information of their own and the two v5 functions have no callers. Every drop
# is RESTRICT, so a dependent makes this fail rather than be silently deleted.
echo "▶ Applying 20261018000000_the_mirrors_and_two_dead_functions_are_gone.sql"
psql_run "-f $PGROOT/20261018000000_the_mirrors_and_two_dead_functions_are_gone.sql" >/dev/null
psql_run "-f $PGROOT/20261018000000_the_mirrors_and_two_dead_functions_are_gone.sql" >/dev/null

# One nullable column, so that a handset leaving mid-emergency is a fact an
# operator can read rather than a gap in a track they have to infer. Applied
# twice, like every other one here: `ADD COLUMN IF NOT EXISTS` must be
# re-runnable, because the runbook tells an operator to paste these by hand.
echo "▶ Applying 20261020000000_a_handset_that_leaves_mid_emergency.sql"
psql_run "-f $PGROOT/20261020000000_a_handset_that_leaves_mid_emergency.sql" >/dev/null
psql_run "-f $PGROOT/20261020000000_a_handset_that_leaves_mid_emergency.sql" >/dev/null

# The chain only ever climbed. This is the sideways move an LGA commander never
# had: hand the incident to a ward they command, by name.
echo "▶ Applying 20261021000000_an_lga_can_hand_an_incident_to_a_ward.sql"
psql_run "-f $PGROOT/20261021000000_an_lga_can_hand_an_incident_to_a_ward.sql" >/dev/null
psql_run "-f $PGROOT/20261021000000_an_lga_can_hand_an_incident_to_a_ward.sql" >/dev/null

# Its own file, and run HERE rather than inside alert_scoping_behaviour_test.sql
# — that one runs earlier in the replay, before this migration exists, where
# the assertions passed for the wrong reason and then failed with "function
# does not exist".
# The outbox was built for the timeout escalation and nothing queued anything
# when an alert was INSERTED, so a report reached a responder only if they had
# the app open.
echo "▶ Applying 20261022000000_a_new_emergency_tells_the_unit.sql"
psql_run "-f $PGROOT/20261022000000_a_new_emergency_tells_the_unit.sql" >/dev/null
psql_run "-f $PGROOT/20261022000000_a_new_emergency_tells_the_unit.sql" >/dev/null

echo "▶ Asserting a new emergency tells the unit it landed in"
NI_OUT=$(psql_run "-f $PGROOT/new_incident_notice_behaviour_test.sql" 2>&1) && NI_RC=0 || NI_RC=$?
echo "$NI_OUT" | grep -E "PASS|FAIL|ERROR" || true
if [ "$NI_RC" -ne 0 ] || echo "$NI_OUT" | grep -q "ERROR"; then
  echo "$NI_OUT"; echo "✗ new incident notice assertions failed"; exit 1
fi

echo "▶ Asserting an LGA commander can hand an incident across to a ward"
WH_OUT=$(psql_run "-f $PGROOT/ward_handdown_behaviour_test.sql" 2>&1) && WH_RC=0 || WH_RC=$?
echo "$WH_OUT" | grep -E "PASS|FAIL|ERROR" || true
if [ "$WH_RC" -ne 0 ] || echo "$WH_OUT" | grep -q "ERROR"; then
  echo "$WH_OUT"; echo "✗ ward hand-down assertions failed"; exit 1
fi

echo "▶ Asserting the schema now behaves the way production's does"
CONV_OUT=$(psql_run "-f $PGROOT/schema_convergence_behaviour_test.sql" 2>&1) && CONV_RC=0 || CONV_RC=$?
echo "$CONV_OUT" | grep -E "PASS|FAIL|NOTE|ERROR" || true
if [ "$CONV_RC" -ne 0 ]; then
  echo "$CONV_OUT"; echo "✗ schema convergence assertions failed"; exit 1
fi

# Three of the four agency tables are created twice, by two files with
# different column lists and IF NOT EXISTS on both — so THIS database, which
# excludes the hand-applied v3/v4 era, had `created_at` and none of the five
# columns production has. Applied twice like the rest: the runbook tells an
# operator to paste it, and a backfill that runs twice must not change anything
# the second time.
echo "▶ Applying 20261023000000_one_table_one_shape.sql"
psql_run "-f $PGROOT/20261023000000_one_table_one_shape.sql" >/dev/null
psql_run "-f $PGROOT/20261023000000_one_table_one_shape.sql" >/dev/null

echo "▶ Asserting the delivery log of a handover to an outside agency"
AGD_OUT=$(psql_run "-f $PGROOT/agency_delivery_behaviour_test.sql" 2>&1) && AGD_RC=0 || AGD_RC=$?
echo "$AGD_OUT" | grep -E "PASS|FAIL|ERROR" || true
if [ "$AGD_RC" -ne 0 ] || echo "$AGD_OUT" | grep -q "ERROR"; then
  echo "$AGD_OUT"; echo "✗ agency delivery assertions failed"; exit 1
fi

# A voice note from somebody who cannot type, and a report about government
# property that must not page a patrol at 02:00 or climb to HQ by morning.
# Applied twice, like every other one here: the runbook tells an operator to
# paste these by hand.
echo "▶ Applying 20261024000000_a_voice_note_and_a_report_that_is_not_an_emergency.sql"
psql_run "-f $PGROOT/20261024000000_a_voice_note_and_a_report_that_is_not_an_emergency.sql" >/dev/null
psql_run "-f $PGROOT/20261024000000_a_voice_note_and_a_report_that_is_not_an_emergency.sql" >/dev/null

echo "▶ Asserting a report about public property is not treated as an emergency"
NE_OUT=$(psql_run "-f $PGROOT/non_emergency_behaviour_test.sql" 2>&1) && NE_RC=0 || NE_RC=$?
echo "$NE_OUT" | grep -E "PASS|FAIL|ERROR" || true
if [ "$NE_RC" -ne 0 ] || echo "$NE_OUT" | grep -q "ERROR"; then
  echo "$NE_OUT"; echo "✗ non-emergency assertions failed"; exit 1
fi

# The other policy PUBLIC could reach. `alerts_select_geo_lga_scoped` was
# created by 20260725 (staging-only, applied to production BY HAND) with no TO
# clause, which PostgreSQL records as TO PUBLIC — twelve lines above its
# telemetry twin, which carries a comment explaining exactly that and was
# repaired on its own. On a database built from this repository 20261006 has
# already dropped it, so this is a no-op here and the fix on production.
echo "▶ Applying 20261025000000_the_other_policy_public_could_reach.sql"
psql_run "-f $PGROOT/20261025000000_the_other_policy_public_could_reach.sql" >/dev/null
psql_run "-f $PGROOT/20261025000000_the_other_policy_public_could_reach.sql" >/dev/null

# AND THE BRANCH THAT MATTERS, WHICH THE REPLAY DOES NOT REACH.
#
# On a database built from this repository the policy is already gone (20261006
# dropped it, and 20260725 is staging-only), so the run above only proves the
# no-op. The branch that does the work on PRODUCTION — policy exists, recorded
# TO PUBLIC, repair it — would otherwise ship untested. So plant production's
# shape and watch the migration close it.
echo "▶ Asserting the repair branch closes a TO-PUBLIC policy it finds"
cat > "$PGROOT/zz_plant_public_policy.sql" <<'PLANT'
-- Exactly what 20260725000000_v6_geo_lga_scoping_staging.sql used to create:
-- no TO clause, which PostgreSQL records as TO PUBLIC.
CREATE POLICY "alerts_select_geo_lga_scoped"
  ON public.alerts FOR SELECT
  USING (
    auth.role() = 'authenticated'
    AND EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('FIELD_OFFICER', 'WARD_OFFICER', 'LGA_OFFICER')
        AND p.geo_lga IS NOT NULL
        AND TRIM(p.geo_lga) <> ''
        AND public.normalise_lga(p.geo_lga) = public.normalise_lga(alerts.geo_lga)
    )
  );
SELECT 'planted=' || roles::text FROM pg_policies
 WHERE schemaname='public' AND policyname='alerts_select_geo_lga_scoped';
PLANT
chown postgres:postgres "$PGROOT/zz_plant_public_policy.sql"
PLANT_OUT=$(psql_run "-t -A -f $PGROOT/zz_plant_public_policy.sql" 2>&1)
printf '%s\n' "$PLANT_OUT" | grep -qx "planted={public}" || {
  printf '%s\n' "$PLANT_OUT" | sed 's/^/    /'
  echo "✗ the planted policy was not recorded as {public} — this step proves nothing"
  exit 1; }
echo "  PASS  planted alerts_select_geo_lga_scoped and PostgreSQL recorded it TO {public}"

# The expression BEFORE, so the claim that the migration leaves it alone is
# asserted rather than described. The policy on production was applied by hand;
# a repair that rewrites its body from this repository's text would silently
# change which officer may read which incident, and `pg_policies.qual` is the
# only place that difference would show.
QUAL_BEFORE=$(su postgres -s /bin/bash -c "psql -h $PGROOT/sock -p $PORT -U postgres -d rainbow -tAc \
  \"select qual from pg_policies where schemaname='public' \
    and policyname='alerts_select_geo_lga_scoped';\"")
psql_run "-f $PGROOT/20261025000000_the_other_policy_public_could_reach.sql" >/dev/null
REPAIRED=$(su postgres -s /bin/bash -c "psql -h $PGROOT/sock -p $PORT -U postgres -d rainbow -tAc \
  \"select roles::text from pg_policies where schemaname='public' \
    and policyname='alerts_select_geo_lga_scoped';\"")
QUAL_AFTER=$(su postgres -s /bin/bash -c "psql -h $PGROOT/sock -p $PORT -U postgres -d rainbow -tAc \
  \"select qual from pg_policies where schemaname='public' \
    and policyname='alerts_select_geo_lga_scoped';\"")
if [ "$REPAIRED" != "{authenticated}" ]; then
  echo "    roles after the migration: $REPAIRED"
  echo "✗ the repair branch did not scope the policy TO authenticated"
  exit 1
fi
echo "  PASS  and the migration scoped it TO {authenticated}"
if [ -z "$QUAL_BEFORE" ] || [ "$QUAL_BEFORE" != "$QUAL_AFTER" ]; then
  echo "    before: $QUAL_BEFORE"
  echo "    after:  $QUAL_AFTER"
  echo "✗ the policy's USING expression changed. ALTER POLICY … TO must change"
  echo "  the roles and nothing else: production's copy of this policy was"
  echo "  applied by hand, and rewriting its body decides who reads what."
  exit 1
fi
echo "  PASS  and its USING expression is byte-identical, so no read path moved"

# Left in place it would be an extra policy on alerts that no migration creates,
# which the convergence assertions would rightly call drift.
psql_run "-c 'DROP POLICY \"alerts_select_geo_lga_scoped\" ON public.alerts;'" >/dev/null
echo "  PASS  and the planted policy is removed, so the end state is the repo's own"

# The capacity a shelter can take. Nullable, no backfill: the app has read this
# column since before it existed, and every shelter recorded before this
# migration legitimately has no figure.
#
# Applied twice, like every migration above, because `ADD COLUMN IF NOT EXISTS`
# and a guarded `ADD CONSTRAINT` are only idempotent if somebody runs them
# twice and looks.
echo "▶ Applying 20261026000000_safe_zones_capacity.sql"
psql_run "-f $PGROOT/20261026000000_safe_zones_capacity.sql" >/dev/null
psql_run "-f $PGROOT/20261026000000_safe_zones_capacity.sql" >/dev/null
CAP_OUT=$(su postgres -s /bin/bash -c "psql -h $PGROOT/sock -p $PORT -U postgres -d rainbow -tAc \
  \"select format('%s/%s', data_type, is_nullable) from information_schema.columns \
    where table_schema='public' and table_name='safe_zones' and column_name='capacity';\"")
[ "$CAP_OUT" = "integer/YES" ] || {
  echo "    information_schema says: ${CAP_OUT:-(no such column)}"
  echo "✗ safe_zones.capacity is not a nullable integer"; exit 1; }
# The CHECK has to refuse a negative and accept NULL, or the column is just an
# integer with a comment on it.
CAP_NEG=$(psql_run "-c \"insert into public.safe_zones (name, latitude, longitude, capacity) \
  values ('zz probe', 9.9, 8.9, -1);\"" 2>&1 || true)
printf '%s\n' "$CAP_NEG" | grep -q "safe_zones_capacity_sane" || {
  printf '%s\n' "$CAP_NEG" | sed 's/^/    /'
  echo "✗ a negative capacity was not refused by safe_zones_capacity_sane"; exit 1; }
psql_run "-c \"insert into public.safe_zones (name, latitude, longitude, capacity) \
  values ('zz probe', 9.9, 8.9, NULL);\"" >/dev/null
psql_run "-c \"delete from public.safe_zones where name = 'zz probe';\"" >/dev/null
echo "  PASS  safe_zones.capacity is a nullable integer that refuses a negative"

# A failed handover to an outside agency now gets retried. The index saying
# "(retry jobs)" has existed since July with no retry job.
#
# Applied twice, and then EXERCISED: a queue whose claim function has never been
# called is a queue nobody knows the shape of. The assertions below drive one
# failed leg through claim -> fail -> back off -> claim again, because that is
# the loop a worker runs and "the function exists" is not the same claim.
echo "▶ Applying 20261027000000_agency_handovers_retry.sql"
psql_run "-f $PGROOT/20261027000000_agency_handovers_retry.sql" >/dev/null
psql_run "-f $PGROOT/20261027000000_agency_handovers_retry.sql" >/dev/null

cat > "$PGROOT/zz_agency_retry_probe.sql" <<'PROBE'
DO $probe$
DECLARE
  v_alert  UUID;
  v_leg    UUID;
  v_claim  INTEGER;
  v_next   TIMESTAMPTZ;
  v_att    INTEGER;
BEGIN
  SELECT id INTO v_alert FROM public.alerts ORDER BY created_at LIMIT 1;

  INSERT INTO public.agency_notifications (agency, alert_id, method, status)
  VALUES ('POLICE', v_alert, 'SMS', 'FAILED')
  RETURNING id INTO v_leg;

  -- A FAILED leg that is due must be claimable, and claiming must hold it.
  SELECT count(*) INTO v_claim
    FROM public.claim_agency_handovers(10) c WHERE c.id = v_leg;
  IF v_claim <> 1 THEN
    RAISE EXCEPTION 'FAIL: a due FAILED leg was not claimed (got %)', v_claim;
  END IF;
  SELECT attempts, next_attempt_at INTO v_att, v_next
    FROM public.agency_notifications WHERE id = v_leg;
  IF v_att <> 1 THEN
    RAISE EXCEPTION 'FAIL: claiming did not count the attempt (attempts=%)', v_att;
  END IF;
  IF v_next <= NOW() THEN
    RAISE EXCEPTION 'FAIL: claiming did not hold the row (next_attempt_at=%)', v_next;
  END IF;
  RAISE NOTICE 'PASS: a due failed leg is claimed once, counted, and held';

  -- Claiming again immediately must NOT return it: that is the whole point of
  -- the hold, and a second worker on the next tick must not take it.
  SELECT count(*) INTO v_claim
    FROM public.claim_agency_handovers(10) c WHERE c.id = v_leg;
  IF v_claim <> 0 THEN
    RAISE EXCEPTION 'FAIL: a held leg was claimed again immediately';
  END IF;
  RAISE NOTICE 'PASS: and a held leg is not claimed again on the next tick';

  -- Failing it backs off with the attempt count, and records why.
  PERFORM public.mark_agency_handover_failed(v_leg, 'probe: gateway refused');
  SELECT next_attempt_at INTO v_next
    FROM public.agency_notifications WHERE id = v_leg;
  IF v_next < NOW() + INTERVAL '1 minute' THEN
    RAISE EXCEPTION 'FAIL: failure did not back off (next_attempt_at=%)', v_next;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.agency_notifications
                  WHERE id = v_leg AND last_error LIKE 'probe:%') THEN
    RAISE EXCEPTION 'FAIL: failure did not record why';
  END IF;
  RAISE NOTICE 'PASS: a failure backs off and records its reason';

  -- Succeeding takes it out of the queue for good.
  PERFORM public.mark_agency_handover_sent(v_leg);
  SELECT count(*) INTO v_claim
    FROM public.claim_agency_handovers(10) c WHERE c.id = v_leg;
  IF v_claim <> 0 THEN
    RAISE EXCEPTION 'FAIL: a SENT leg is still in the queue';
  END IF;
  RAISE NOTICE 'PASS: a sent leg leaves the queue';

  DELETE FROM public.agency_notifications WHERE id = v_leg;
  RAISE NOTICE 'ALL AGENCY HANDOVER RETRY ASSERTIONS PASSED';
END $probe$;
PROBE
chown postgres:postgres "$PGROOT/zz_agency_retry_probe.sql"
AGR_OUT=$(psql_run "-f $PGROOT/zz_agency_retry_probe.sql" 2>&1) && AGR_RC=0 || AGR_RC=$?
printf '%s\n' "$AGR_OUT" | grep -E "PASS:|FAIL:" | sed 's/^.*NOTICE:  /  /' || true
if [ "$AGR_RC" -ne 0 ] || printf '%s\n' "$AGR_OUT" | grep -q "FAIL:"; then
  printf '%s\n' "$AGR_OUT"
  echo "✗ agency handover retry assertions failed"; exit 1
fi
printf '%s\n' "$AGR_OUT" | grep -q "ALL AGENCY HANDOVER RETRY ASSERTIONS PASSED" || {
  printf '%s\n' "$AGR_OUT"
  echo "✗ the agency retry probe did not reach its verdict"; exit 1; }

# Only the service role drains a queue.
for fn in claim_agency_handovers mark_agency_handover_sent mark_agency_handover_failed; do
  LEAK=$(su postgres -s /bin/bash -c "psql -h $PGROOT/sock -p $PORT -U postgres -d rainbow -tAc \
    \"select count(*) from information_schema.routine_privileges \
       where routine_schema='public' and routine_name='$fn' \
         and grantee in ('anon','authenticated','PUBLIC');\"")
  [ "$LEAK" = "0" ] || { echo "✗ $fn is executable by $LEAK non-service role(s)"; exit 1; }
done
echo "  PASS  and none of the three retry functions is reachable by anon or authenticated"

# The command tier the deployment actually has. Both role functions were
# exact-match lists of this repository's vocabulary, so the production
# project's STATE_COMMANDER and LGA_COMMANDER accounts satisfied neither.
#
# Exercised per ROLE, because "the function was replaced" is not the claim —
# the claim is that a commander under either spelling may command, and that
# widening it moved nobody else up the chain.
echo "▶ Applying 20261028000000_command_knows_both_vocabularies.sql"
psql_run "-f $PGROOT/20261028000000_command_knows_both_vocabularies.sql" >/dev/null
psql_run "-f $PGROOT/20261028000000_command_knows_both_vocabularies.sql" >/dev/null

cat > "$PGROOT/zz_command_vocab_probe.sql" <<'PROBE'
DO $probe$
DECLARE
  r            RECORD;
  v_uid        UUID;
  v_is_cmd     BOOLEAN;
  v_whole      BOOLEAN;
  -- role -> what it must be allowed. Both spellings of each rung, and the
  -- rungs that must NOT have been moved up.
  expected     TEXT[][] := ARRAY[
    ['HQ_COMMAND',           'command', 'whole'],
    ['STATE_COMMANDER',      'command', 'whole'],
    ['ADMIN',                'command', 'whole'],
    ['LGA_COMMAND',          'command', 'posting'],
    ['LGA_COMMANDER',        'command', 'posting'],
    ['WARD_COMMAND',         'none',    'posting'],
    ['WARD_COMMANDER',       'none',    'posting'],
    ['UNIT_COMMAND',         'none',    'posting'],
    ['POLLING_UNIT_OFFICER', 'none',    'posting'],
    ['CITIZEN',              'none',    'posting']
  ];
BEGIN
  FOR i IN 1 .. array_length(expected, 1) LOOP
    v_uid := gen_random_uuid();
    INSERT INTO auth.users (id, email) VALUES (v_uid, expected[i][1] || '@probe.test');
    -- handle_new_user() already made the profile. Set the role on it rather
    -- than inserting a second one — and do it BEFORE the jwt claim is set,
    -- because the role-change trigger permits a change only while auth.uid()
    -- is null or the caller is service_role, which is exactly how the backend
    -- assigns a role and exactly why widening is_command() grants nothing a
    -- user can give themselves.
    UPDATE public.profiles SET role = expected[i][1] WHERE id = v_uid;

    PERFORM set_config('request.jwt.claim.sub', v_uid::text, true);
    PERFORM set_config('request.jwt.claims',
      json_build_object('sub', v_uid::text, 'role', 'authenticated')::text, true);

    SELECT public.is_command(), public.commands_whole_state()
      INTO v_is_cmd, v_whole;

    IF expected[i][2] = 'command' AND NOT v_is_cmd THEN
      RAISE EXCEPTION 'FAIL: % is a commander and is_command() said false', expected[i][1];
    END IF;
    IF expected[i][2] = 'none' AND v_is_cmd THEN
      RAISE EXCEPTION 'FAIL: % is NOT command and is_command() said true — this migration moved somebody up the chain', expected[i][1];
    END IF;
    IF expected[i][3] = 'whole' AND NOT v_whole THEN
      RAISE EXCEPTION 'FAIL: % commands the state and commands_whole_state() said false', expected[i][1];
    END IF;
    IF expected[i][3] = 'posting' AND v_whole THEN
      RAISE EXCEPTION 'FAIL: % does not command the state and commands_whole_state() said true', expected[i][1];
    END IF;

    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claims', '', true);
    DELETE FROM public.profiles WHERE id = v_uid;
    DELETE FROM auth.users WHERE id = v_uid;
  END LOOP;

  RAISE NOTICE 'PASS: both spellings of HQ and LGA command, and nobody else, under either function';
  RAISE NOTICE 'ALL COMMAND VOCABULARY ASSERTIONS PASSED';
END $probe$;
PROBE
chown postgres:postgres "$PGROOT/zz_command_vocab_probe.sql"
CV_OUT=$(psql_run "-f $PGROOT/zz_command_vocab_probe.sql" 2>&1) && CV_RC=0 || CV_RC=$?
printf '%s\n' "$CV_OUT" | grep -E "PASS:|FAIL:" | sed 's/^.*NOTICE:  /  /' || true
if [ "$CV_RC" -ne 0 ] || printf '%s\n' "$CV_OUT" | grep -q "FAIL:"; then
  printf '%s\n' "$CV_OUT"
  echo "✗ command vocabulary assertions failed"; exit 1
fi
printf '%s\n' "$CV_OUT" | grep -q "ALL COMMAND VOCABULARY ASSERTIONS PASSED" || {
  printf '%s\n' "$CV_OUT"
  echo "✗ the command vocabulary probe did not reach its verdict"; exit 1; }

# ── A queued notification has a shelf life ──────────────────────────────────
#
# The live project is holding 412 undelivered notices, none ever attempted, the
# oldest from July: the drain worker was never scheduled. Scheduling it was the
# obvious next step and would have delivered July — `claim_notifications` took
# the oldest rows due and nothing anywhere bounded their age, so every officer
# whose geography matched a July timeout would have been told an incident was
# now theirs, twenty a minute.
#
# The assertions below are about the queue, not the worker, because there are
# two workers.
echo "▶ Applying 20261029000000_a_notification_has_a_shelf_life.sql"
psql_run "-f $PGROOT/20261029000000_a_notification_has_a_shelf_life.sql" >/dev/null
psql_run "-f $PGROOT/20261029000000_a_notification_has_a_shelf_life.sql" >/dev/null

cat > "$PGROOT/zz_shelf_life_probe.sql" <<'PROBE'
BEGIN;
SET client_min_messages TO NOTICE;

-- Hex only. The first version of this probe used `...0000000000s1`, and
-- PostgreSQL answered `22P02 invalid input syntax for type uuid` — the same
-- error T-86 is about, from the same habit of writing a readable suffix into a
-- UUID.
INSERT INTO auth.users (id, email)
VALUES ('eeee5555-0000-4000-8000-00000000005e', 'shelf-life@probe.test')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.alerts
  (id, type, description, status, severity, reported_by,
   geo_lga, geo_ward, geo_pu, assigned_tier, tier_assigned_at)
VALUES
  ('ffff6666-0000-4000-8000-00000000005e', 'Kidnap - Held Hostage',
   'still open', 'OPEN', 'CRITICAL', 'eeee5555-0000-4000-8000-00000000005e',
   'JOS NORTH', 'NARAGUTA', 'PU-01', 'UNIT', NOW()),
  ('ffff6666-0000-4000-8000-00000000005f', 'Fire - Structure',
   'dispatcher closed it', 'RESOLVED', 'HIGH',
   'eeee5555-0000-4000-8000-00000000005e',
   'JOS NORTH', 'NARAGUTA', 'PU-01', 'UNIT', NOW());

-- Those two inserts fired `queue_new_incident_notice`, so the queue already
-- holds two live NEW_INCIDENT rows. Assertion 5 is about WHICH row a claim
-- hands back, so the queue has to start empty or it proves nothing. Safe: this
-- whole file is one transaction and ends in ROLLBACK.
DELETE FROM public.notification_outbox;

-- ── 1. the setting refuses the readings that empty or never empty the queue ──
DO $probe$
BEGIN
  IF public.notification_shelf_life_minutes() <> 60 THEN
    RAISE EXCEPTION 'FAIL: the seeded shelf life is not 60, it is %',
      public.notification_shelf_life_minutes();
  END IF;

  UPDATE public.app_config SET value = '0'
   WHERE key = 'notification_shelf_life_minutes';
  IF public.notification_shelf_life_minutes() <> 60 THEN
    RAISE EXCEPTION
      'FAIL: a shelf life of 0 was accepted — every notice would be retired unsent';
  END IF;

  UPDATE public.app_config SET value = 'soon'
   WHERE key = 'notification_shelf_life_minutes';
  IF public.notification_shelf_life_minutes() <> 60 THEN
    RAISE EXCEPTION 'FAIL: an unparseable shelf life was not refused';
  END IF;

  UPDATE public.app_config SET value = '60'
   WHERE key = 'notification_shelf_life_minutes';
  RAISE NOTICE 'PASS: 0 and junk are refused, and the default is an hour';
END $probe$;

-- ── 2. July is not delivered, and is not recorded as delivered ───────────────
DO $probe$
DECLARE
  v_id      BIGINT;
  n_handed  INTEGER;
  v_expired TIMESTAMPTZ;
  v_delivd  TIMESTAMPTZ;
  v_reason  TEXT;
BEGIN
  INSERT INTO public.notification_outbox (alert_id, kind, payload, created_at)
  VALUES ('ffff6666-0000-4000-8000-00000000005e', 'TIER_ESCALATION',
          '{"to_tier":"WARD"}'::jsonb, NOW() - INTERVAL '97 days')
  RETURNING id INTO v_id;

  SELECT count(*) INTO n_handed
    FROM public.claim_notifications(20) c WHERE c.id = v_id;
  IF n_handed <> 0 THEN
    RAISE EXCEPTION
      'FAIL: a notice queued 97 days ago was handed to a worker to send';
  END IF;

  SELECT expired_at, delivered_at, expiry_reason
    INTO v_expired, v_delivd, v_reason
    FROM public.notification_outbox WHERE id = v_id;
  IF v_expired IS NULL THEN
    RAISE EXCEPTION
      'FAIL: it was withheld and not retired, so it sits in the queue for ever';
  END IF;
  IF v_delivd IS NOT NULL THEN
    RAISE EXCEPTION
      'FAIL: a retired notice was recorded as DELIVERED. Nobody was told, and '
      'writing that into this table is the defect the outbox exists to end';
  END IF;
  IF v_reason IS NULL OR v_reason NOT LIKE '%shelf life%' THEN
    RAISE EXCEPTION 'FAIL: no reason recorded for the expiry, got %', v_reason;
  END IF;
  RAISE NOTICE 'PASS: a July notice is retired undelivered, with a reason, and not marked sent';
END $probe$;

-- ── 3. a fresh notice is still handed out ────────────────────────────────────
DO $probe$
DECLARE v_id BIGINT; n_handed INTEGER;
BEGIN
  INSERT INTO public.notification_outbox (alert_id, kind, payload)
  VALUES ('ffff6666-0000-4000-8000-00000000005e', 'TIER_ESCALATION',
          '{"to_tier":"WARD"}'::jsonb)
  RETURNING id INTO v_id;
  SELECT count(*) INTO n_handed
    FROM public.claim_notifications(20) c WHERE c.id = v_id;
  IF n_handed <> 1 THEN
    RAISE EXCEPTION 'FAIL: a notice queued just now was not handed out';
  END IF;
  RAISE NOTICE 'PASS: a live notice is still delivered';
END $probe$;

-- ── 4. the incident closed while the notice sat in the queue ─────────────────
--
-- Fresh, well inside the shelf life, and about an incident a dispatcher has
-- already resolved. Sending it puts a unit on a finished incident. This race
-- exists at any drain frequency, so no retry policy fixes it.
DO $probe$
DECLARE v_id BIGINT; n_handed INTEGER; v_reason TEXT;
BEGIN
  INSERT INTO public.notification_outbox (alert_id, kind, payload)
  VALUES ('ffff6666-0000-4000-8000-00000000005f', 'TIER_ESCALATION',
          '{"to_tier":"WARD"}'::jsonb)
  RETURNING id INTO v_id;
  SELECT count(*) INTO n_handed
    FROM public.claim_notifications(20) c WHERE c.id = v_id;
  IF n_handed <> 0 THEN
    RAISE EXCEPTION
      'FAIL: a notice about a RESOLVED incident was handed to a worker';
  END IF;
  SELECT expiry_reason INTO v_reason
    FROM public.notification_outbox WHERE id = v_id;
  IF v_reason IS NULL OR v_reason NOT LIKE '%closed%' THEN
    RAISE EXCEPTION 'FAIL: expected a closed-incident reason, got %', v_reason;
  END IF;
  RAISE NOTICE 'PASS: a notice about a closed incident is retired, not sent';
END $probe$;

-- ── 5. THE BACKLOG DOES NOT COST A TICK ──────────────────────────────────────
--
-- The property that decides whether this is usable. With 50 stale notices ahead
-- of one live one and a batch size of 1, the live notice must come back on the
-- FIRST call. Expiring inside the claim CTE — the obvious implementation —
-- passes every assertion above and fails this one: the worker would spend a
-- tick per batch of stale rows, so with the 412 standing on the live project
-- the first real notice would wait twenty-one minutes. An emergency queue
-- cannot have a warm-up period.
DO $probe$
DECLARE v_id BIGINT; n_handed INTEGER; n_retired INTEGER;
BEGIN
  INSERT INTO public.notification_outbox (alert_id, kind, payload, created_at)
  SELECT 'ffff6666-0000-4000-8000-00000000005e', 'TIER_ESCALATION',
         '{"to_tier":"WARD"}'::jsonb, NOW() - INTERVAL '90 days'
    FROM generate_series(1, 50);
  INSERT INTO public.notification_outbox (alert_id, kind, payload)
  VALUES ('ffff6666-0000-4000-8000-00000000005e', 'TIER_ESCALATION',
          '{"to_tier":"LGA"}'::jsonb)
  RETURNING id INTO v_id;

  SELECT count(*) INTO n_handed
    FROM public.claim_notifications(1) c WHERE c.id = v_id;
  IF n_handed <> 1 THEN
    RAISE EXCEPTION
      'FAIL: 50 stale notices ahead of a live one and the live one was not '
      'handed out on the first claim — the queue has a warm-up period';
  END IF;

  SELECT count(*) INTO n_retired
    FROM public.notification_outbox
   WHERE expired_at IS NOT NULL
     AND created_at < NOW() - INTERVAL '89 days';
  IF n_retired < 50 THEN
    RAISE EXCEPTION
      'FAIL: only % of the 50 stale notices were retired by one claim', n_retired;
  END IF;
  RAISE NOTICE 'PASS: 50 stale notices are retired and the live one is handed out in one claim';
END $probe$;

-- ── 6. and an operator can see the queue before scheduling anything ──────────
DO $probe$
DECLARE n_states INTEGER;
BEGIN
  SELECT count(*) INTO n_states FROM public.notification_queue_status();
  IF n_states = 0 THEN
    RAISE EXCEPTION 'FAIL: the queue cannot be inspected at all';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.notification_queue_status()
                  WHERE state = 'retired undelivered') THEN
    RAISE EXCEPTION 'FAIL: the status does not report what was retired undelivered';
  END IF;
  RAISE NOTICE 'PASS: the queue reports its state in % groups', n_states;
END $probe$;

-- ── 7. nobody signed in may drain or suppress ────────────────────────────────
DO $probe$
DECLARE denied_claim BOOLEAN := false; denied_sweep BOOLEAN := false;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',
                     'eeee5555-0000-4000-8000-00000000005e', true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  SET LOCAL ROLE authenticated;
  BEGIN PERFORM public.claim_notifications(5);
  EXCEPTION WHEN insufficient_privilege THEN denied_claim := true; END;
  BEGIN PERFORM public.expire_stale_notifications();
  EXCEPTION WHEN insufficient_privilege THEN denied_sweep := true; END;
  RESET ROLE;
  IF NOT denied_claim THEN
    RAISE EXCEPTION 'FAIL: a signed-in account can claim notifications';
  END IF;
  IF NOT denied_sweep THEN
    RAISE EXCEPTION
      'FAIL: a signed-in account can retire every queued notice — a one-call '
      'way to silence the whole escalation chain';
  END IF;
  RAISE NOTICE 'PASS: only the service role may drain or retire';
END $probe$;

DO $probe$ BEGIN RAISE NOTICE 'ALL SHELF LIFE ASSERTIONS PASSED'; END $probe$;
ROLLBACK;
PROBE
chown postgres:postgres "$PGROOT/zz_shelf_life_probe.sql"
SL_OUT=$(psql_run "-f $PGROOT/zz_shelf_life_probe.sql" 2>&1) && SL_RC=0 || SL_RC=$?
printf '%s\n' "$SL_OUT" | grep -E "PASS:|FAIL:" | sed 's/^.*NOTICE:  /  /' || true
if [ "$SL_RC" -ne 0 ] || printf '%s\n' "$SL_OUT" | grep -q "FAIL:"; then
  printf '%s\n' "$SL_OUT"
  echo "✗ notification shelf life assertions failed"; exit 1
fi
printf '%s\n' "$SL_OUT" | grep -q "ALL SHELF LIFE ASSERTIONS PASSED" || {
  printf '%s\n' "$SL_OUT"
  echo "✗ the shelf life probe did not reach its verdict"; exit 1; }

# ── A shelter says who stood there ──────────────────────────────────────────
#
# Three of the seven seeded shelters were outside every surveyed ward of the LGA
# their own row claimed — JOS SOUTH COMMAND HQ by 9.6km, and its position is in
# Jos North. The citizen screen draws a route to the nearest one.
echo "▶ Applying 20261030000000_a_shelter_says_who_stood_there.sql"
psql_run "-f $PGROOT/20261030000000_a_shelter_says_who_stood_there.sql" >/dev/null
psql_run "-f $PGROOT/20261030000000_a_shelter_says_who_stood_there.sql" >/dev/null

cat > "$PGROOT/zz_shelter_probe.sql" <<'PROBE'
BEGIN;
SET client_min_messages TO NOTICE;

-- ── 1. applied twice, still seven ───────────────────────────────────────────
--
-- The old seed ended `ON CONFLICT DO NOTHING` with no target against a
-- gen_random_uuid() key, so it matched nothing and a second run inserted all
-- seven again. The replay above applied this file TWICE, which is what makes
-- this assertion mean something.
DO $probe$
DECLARE n INTEGER; n_names INTEGER;
BEGIN
  SELECT count(*), count(DISTINCT name) INTO n, n_names FROM public.safe_zones;
  IF n <> n_names THEN
    RAISE EXCEPTION
      'FAIL: % shelter rows for % distinct names — the seed duplicates, and '
      'the citizen screen would list each shelter twice', n, n_names;
  END IF;
  IF n < 7 THEN
    RAISE EXCEPTION 'FAIL: expected the seven seeded shelters, found %', n;
  END IF;
  RAISE NOTICE 'PASS: % shelters, one row each, after two applications', n;
END $probe$;

-- ── 2. none of them claims to have been measured ────────────────────────────
DO $probe$
DECLARE n_claimed INTEGER;
BEGIN
  SELECT count(*) INTO n_claimed
    FROM public.safe_zones WHERE verified_at IS NOT NULL;
  IF n_claimed > 0 THEN
    RAISE EXCEPTION
      'FAIL: % seeded shelter(s) report a confirmed position. Nobody stood at '
      'any of them; one sat at the centroid of Jos to 4dp', n_claimed;
  END IF;
  RAISE NOTICE 'PASS: every seeded shelter reports its position unconfirmed';
END $probe$;

-- ── 3. the three in the wrong LGA do not reach the citizen app ──────────────
--
-- The screen's provider filters `is_active = true`, so this is what stops a
-- route being drawn to them.
DO $probe$
DECLARE r RECORD; n_hidden INTEGER := 0;
BEGIN
  FOR r IN SELECT name, is_active, description FROM public.safe_zones
            WHERE name IN ('JOS SOUTH COMMAND HQ', 'JOS EAST TACTICAL OUTPOST',
                           'MANGU COMMAND POST')
  LOOP
    IF r.is_active IS NOT false THEN
      RAISE EXCEPTION
        'FAIL: % is still active, and its position is outside every surveyed '
        'ward of the LGA it claims', r.name;
    END IF;
    IF r.description NOT LIKE '%POSITION NOT CONFIRMED%' THEN
      RAISE EXCEPTION
        'FAIL: % was hidden with no reason recorded, so nobody can tell it '
        'from a shelter that closed', r.name;
    END IF;
    n_hidden := n_hidden + 1;
  END LOOP;
  IF n_hidden <> 3 THEN
    RAISE EXCEPTION 'FAIL: expected 3 hidden shelters, found %', n_hidden;
  END IF;
  -- And appended ONCE, not once per application.
  IF EXISTS (SELECT 1 FROM public.safe_zones
              WHERE description LIKE '%POSITION NOT CONFIRMED%POSITION NOT CONFIRMED%') THEN
    RAISE EXCEPTION
      'FAIL: the reason was appended twice, so this migration is not idempotent';
  END IF;
  RAISE NOTICE 'PASS: the 3 whose position contradicts their LGA are hidden, with the reason, once';
END $probe$;

-- ── 4. the four that are where they say they are are still shown ────────────
DO $probe$
DECLARE n INTEGER;
BEGIN
  SELECT count(*) INTO n FROM public.safe_zones WHERE is_active = true;
  IF n < 4 THEN
    RAISE EXCEPTION
      'FAIL: only % shelter(s) left for a citizen to run to. Hiding a wrong '
      'position must not empty the list', n;
  END IF;
  RAISE NOTICE 'PASS: % shelters remain available to a citizen', n;
END $probe$;

-- ── 5. a position outside Plateau State is refused ──────────────────────────
DO $probe$
DECLARE refused BOOLEAN := false;
BEGIN
  BEGIN
    INSERT INTO public.safe_zones (name, latitude, longitude)
    VALUES ('GULF OF GUINEA', 0, 0);
  EXCEPTION WHEN check_violation THEN refused := true;
  END;
  IF NOT refused THEN
    RAISE EXCEPTION
      'FAIL: 0,0 was accepted as a shelter. That is a point 700km off the '
      'coast, and this project has already drawn it on a map as somewhere to go';
  END IF;
  RAISE NOTICE 'PASS: a position outside Plateau State is refused by the table';
END $probe$;

-- ── 6. only command may publish, and a position needs an author ─────────────
DO $probe$
DECLARE
  v_citizen UUID := gen_random_uuid();
  v_cmd     UUID := gen_random_uuid();
  denied    BOOLEAN := false;
  no_pos    BOOLEAN := false;
  z         public.safe_zones;
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_citizen, 'zone-citizen@probe.test');
  INSERT INTO auth.users (id, email) VALUES (v_cmd, 'zone-command@probe.test');
  UPDATE public.profiles SET role = 'CITIZEN'    WHERE id = v_citizen;
  -- STATE_COMMANDER, the deployment's own spelling: this is the account type
  -- that could not publish a shelter at all before 20261028000000.
  UPDATE public.profiles SET role = 'STATE_COMMANDER' WHERE id = v_cmd;

  -- BOTH keys. `auth.uid()` in this harness reads `request.jwt.claim.sub`,
  -- so setting only `request.jwt.claims` leaves it NULL — and then
  -- `is_command()` is false for everybody and the denial below passes without
  -- testing anything. The first version of this probe did exactly that, and
  -- the commander two statements down is what caught it.
  PERFORM set_config('request.jwt.claim.sub', v_citizen::text, true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_citizen::text, 'role', 'authenticated')::text, true);
  IF auth.uid() <> v_citizen THEN
    RAISE EXCEPTION
      'FAIL: the probe could not sign anybody in (auth.uid() = %), so every '
      'permission assertion below would pass vacuously', auth.uid();
  END IF;
  BEGIN
    PERFORM public.publish_safe_zone('CITIZEN SHELTER', 9.9, 8.9);
  EXCEPTION WHEN insufficient_privilege THEN denied := true;
  END;
  IF NOT denied THEN
    RAISE EXCEPTION
      'FAIL: a citizen published a shelter. Anybody could then put a pin '
      'wherever they wanted and the app would route people to it';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_cmd::text, true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_cmd::text, 'role', 'authenticated')::text, true);

  BEGIN
    PERFORM public.publish_safe_zone('NO POSITION OUTPOST', NULL, NULL);
  EXCEPTION WHEN others THEN no_pos := true;
  END;
  IF NOT no_pos THEN
    RAISE EXCEPTION 'FAIL: a shelter with no position was stored';
  END IF;

  -- Unverified by default: publishing is not the same as having stood there.
  z := public.publish_safe_zone('BUKURU DIVISIONAL POLICE', 9.7952, 8.8530,
                                'POLICE', 'JOS SOUTH');
  IF z.verified_at IS NOT NULL THEN
    RAISE EXCEPTION
      'FAIL: a newly published shelter reports a confirmed position without '
      'anybody claiming it';
  END IF;
  IF z.is_active IS NOT true THEN
    RAISE EXCEPTION 'FAIL: a published shelter is not active';
  END IF;

  -- And claiming it records WHO. A database cannot know whether a coordinate
  -- is real; what it can insist on is an id against it.
  z := public.verify_safe_zone(z.id);
  IF z.verified_at IS NULL OR z.verified_by <> v_cmd THEN
    RAISE EXCEPTION
      'FAIL: confirming a position did not record who confirmed it (by=%)',
      z.verified_by;
  END IF;

  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', '', true);
  RAISE NOTICE 'PASS: only command publishes, a position needs coordinates, and confirming it names somebody';
END $probe$;

-- ── 7. a corrected shelter comes back ───────────────────────────────────────
--
-- The three hidden rows are real places with wrong numbers. Correcting one has
-- to un-hide it, or the deactivation is a one-way door and command's only
-- option is a duplicate under a different name.
DO $probe$
DECLARE
  v_cmd UUID := gen_random_uuid();
  z     public.safe_zones;
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_cmd, 'zone-fixer@probe.test');
  UPDATE public.profiles SET role = 'HQ_COMMAND' WHERE id = v_cmd;
  PERFORM set_config('request.jwt.claim.sub', v_cmd::text, true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_cmd::text, 'role', 'authenticated')::text, true);

  -- The surveyed centroid of MANGU/KADUNU, which is the ward the old position
  -- was 9.68km outside. Used as a stand-in rather than a number invented here:
  -- this is what the project already does for a USSD report with no GPS, and
  -- the point of the probe is that correcting a row un-hides it, not that this
  -- is where the command post is.
  z := public.publish_safe_zone('MANGU COMMAND POST', 9.692824, 9.134952,
                                'COMMAND_HQ', 'MANGU', NULL, NULL, NULL, true);
  IF z.is_active IS NOT true THEN
    RAISE EXCEPTION
      'FAIL: correcting a hidden shelter left it hidden, so the only way to '
      'fix one is to invent a second name for it';
  END IF;
  IF z.verified_at IS NULL OR z.verified_by <> v_cmd THEN
    RAISE EXCEPTION 'FAIL: the correction did not record who made it';
  END IF;
  IF (SELECT count(*) FROM public.safe_zones WHERE name = 'MANGU COMMAND POST') <> 1 THEN
    RAISE EXCEPTION 'FAIL: correcting a shelter created a second row for it';
  END IF;

  z := public.retire_safe_zone(z.id, 'probe');
  IF z.is_active IS NOT false THEN
    RAISE EXCEPTION 'FAIL: a retired shelter is still shown to citizens';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', '', true);
  RAISE NOTICE 'PASS: a hidden shelter can be corrected in place, and retired again';
END $probe$;

DO $probe$ BEGIN RAISE NOTICE 'ALL SHELTER ASSERTIONS PASSED'; END $probe$;
ROLLBACK;
PROBE
chown postgres:postgres "$PGROOT/zz_shelter_probe.sql"
SZ_OUT=$(psql_run "-f $PGROOT/zz_shelter_probe.sql" 2>&1) && SZ_RC=0 || SZ_RC=$?
printf '%s\n' "$SZ_OUT" | grep -E "PASS:|FAIL:" | sed 's/^.*NOTICE:  /  /' || true
if [ "$SZ_RC" -ne 0 ] || printf '%s\n' "$SZ_OUT" | grep -q "FAIL:"; then
  printf '%s\n' "$SZ_OUT"
  echo "✗ shelter assertions failed"; exit 1
fi
printf '%s\n' "$SZ_OUT" | grep -q "ALL SHELTER ASSERTIONS PASSED" || {
  printf '%s\n' "$SZ_OUT"
  echo "✗ the shelter probe did not reach its verdict"; exit 1; }

# ── A ward is not called "WARD" ─────────────────────────────────────────────
#
# The live project files incidents under JOS SOUTH / BUKURU and JOS SOUTH /
# BUKURU WARD as different places. geo_key() compared them raw, so a ward
# commander posted to one was refused every incident filed at the other.
echo "▶ Applying 20261031000000_a_ward_is_not_called_ward.sql"
psql_run "-f $PGROOT/20261031000000_a_ward_is_not_called_ward.sql" >/dev/null
psql_run "-f $PGROOT/20261031000000_a_ward_is_not_called_ward.sql" >/dev/null

cat > "$PGROOT/zz_ward_name_probe.sql" <<'PROBE'
BEGIN;
SET client_min_messages TO NOTICE;

-- ── 1. the names resolve together, and distinct places still do not ─────────
DO $probe$
BEGIN
  IF public.geo_key('BUKURU WARD') <> public.geo_key('BUKURU') THEN
    RAISE EXCEPTION
      'FAIL: geo_key(%) <> geo_key(%). A ward officer posted to one is refused '
      'every incident filed at the other',
      'BUKURU WARD', 'BUKURU';
  END IF;
  IF public.geo_key('JOS SOUTH LGA') <> public.geo_key('JOS SOUTH') THEN
    RAISE EXCEPTION 'FAIL: a trailing LGA is not dropped';
  END IF;
  IF public.geo_key('GINDIRI I') <> public.geo_key('GINDIRI 1') THEN
    RAISE EXCEPTION
      'FAIL: the Roman numeral 20261009000000 was written for no longer works';
  END IF;
  -- And the strip has not become a blunt instrument.
  IF public.geo_key('BUKURU') = public.geo_key('DU') THEN
    RAISE EXCEPTION 'FAIL: two different wards now resolve to one key';
  END IF;
  IF public.geo_key('WARD') IS DISTINCT FROM 'WARD' THEN
    RAISE EXCEPTION
      'FAIL: geo_key(''WARD'') is %, so a place whose whole name is the word '
      'matches nothing', public.geo_key('WARD');
  END IF;
  RAISE NOTICE 'PASS: BUKURU and BUKURU WARD resolve together; distinct wards still do not';
END $probe$;

-- ── 2. and the officer actually sees the incident ───────────────────────────
--
-- The point is not the function, it is the board. A ward commander posted to
-- the spelling with the noise suffix, and an incident filed without it.
DO $probe$
DECLARE
  v_officer UUID := gen_random_uuid();
  v_mine    UUID := gen_random_uuid();
  v_theirs  UUID := gen_random_uuid();
  n_seen    INTEGER;
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_officer, 'ward-officer@probe.test');
  UPDATE public.profiles
     SET role = 'WARD_COMMANDER', geo_lga = 'JOS SOUTH', geo_ward = 'BUKURU WARD'
   WHERE id = v_officer;

  INSERT INTO public.alerts
    (id, type, description, status, severity, reported_by,
     geo_lga, geo_ward, assigned_tier, tier_assigned_at)
  VALUES
    (v_mine, 'Fire - Structure', 'in their own ward, spelled without the noise',
     'OPEN', 'HIGH', v_officer, 'JOS SOUTH', 'BUKURU', 'WARD', NOW()),
    (v_theirs, 'Fire - Structure', 'a different LGA entirely',
     'OPEN', 'HIGH', v_officer, 'MANGU', 'KADUNU', 'WARD', NOW());

  PERFORM set_config('request.jwt.claim.sub', v_officer::text, true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_officer::text, 'role', 'authenticated')::text, true);

  SELECT count(*) INTO n_seen
    FROM public.alerts a WHERE a.id = v_mine AND public.alert_in_my_area(a);
  IF n_seen <> 1 THEN
    RAISE EXCEPTION
      'FAIL: a ward commander posted to "JOS SOUTH / BUKURU WARD" cannot see '
      'an incident filed at "JOS SOUTH / BUKURU". Their board is empty and the '
      'row is right there';
  END IF;

  SELECT count(*) INTO n_seen
    FROM public.alerts a WHERE a.id = v_theirs AND public.alert_in_my_area(a);
  IF n_seen <> 0 THEN
    RAISE EXCEPTION
      'FAIL: the suffix strip widened a ward posting to another LGA entirely';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', '', true);
  RAISE NOTICE 'PASS: the ward officer sees their own ward and not another LGA';
END $probe$;

-- ── 3. THE INDEX CARRIES THE NEW KEYS ───────────────────────────────────────
--
-- geo_key() is IMMUTABLE and two indexes are built on it. PostgreSQL believes
-- IMMUTABLE and does not rebuild an index when the function is replaced, so
-- without the REINDEX in that migration an index scan searches new keys among
-- old ones. The bug would then be right or wrong by query plan.
--
-- Demonstrated rather than asserted on trust: the old body is installed WITHOUT
-- reindexing, and the lookup must then disagree with a sequential scan. If it
-- agrees, this probe is not testing anything and says so.
DO $probe$
DECLARE
  v_id      UUID := gen_random_uuid();
  by_index  INTEGER;
  by_seq    INTEGER;
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_id, 'ward-index@probe.test');
  INSERT INTO public.alerts
    (id, type, description, status, severity, reported_by,
     geo_lga, geo_ward, assigned_tier, tier_assigned_at)
  VALUES (v_id, 'Fire - Structure', 'indexed under the new body', 'OPEN',
          'HIGH', v_id, 'JOS SOUTH', 'BUKURU WARD', 'WARD', NOW());

  -- Under the body this migration installs, both routes agree.
  SET LOCAL enable_seqscan = off;
  SELECT count(*) INTO by_index FROM public.alerts a
   WHERE public.geo_key(a.geo_lga) = 'JOS SOUTH'
     AND public.geo_key(a.geo_ward) = 'BUKURU' AND a.id = v_id;
  SET LOCAL enable_seqscan = on;
  SELECT count(*) INTO by_seq FROM public.alerts a
   WHERE public.geo_key(a.geo_lga) = 'JOS SOUTH'
     AND public.geo_key(a.geo_ward) = 'BUKURU' AND a.id = v_id;
  IF by_index <> by_seq OR by_seq <> 1 THEN
    RAISE EXCEPTION
      'FAIL: after the migration, an index lookup found % and a scan found % '
      '(expected 1 and 1). The rebuilt index does not agree with the function',
      by_index, by_seq;
  END IF;

  -- Now the old body, deliberately WITHOUT a rebuild. The index entry still
  -- says BUKURU; this body computes BUKURU WARD.
  CREATE OR REPLACE FUNCTION public.geo_key(p_name TEXT)
  RETURNS TEXT LANGUAGE sql IMMUTABLE PARALLEL SAFE
  SET search_path = pg_catalog, pg_temp AS $old$
    SELECT nullif(
      regexp_replace(
        regexp_replace(
          regexp_replace(
            regexp_replace(upper(trim(coalesce(p_name, ''))), '\s+', ' ', 'g'),
            '\s+III$', ' 111'),
          '\s+II$', ' 11'),
        '\s+I$', ' 1'),
      '');
  $old$;

  SET LOCAL enable_seqscan = off;
  SELECT count(*) INTO by_index FROM public.alerts a
   WHERE public.geo_key(a.geo_lga) = 'JOS SOUTH'
     AND public.geo_key(a.geo_ward) = 'BUKURU WARD' AND a.id = v_id;
  SET LOCAL enable_seqscan = on;
  SELECT count(*) INTO by_seq FROM public.alerts a
   WHERE public.geo_key(a.geo_lga) = 'JOS SOUTH'
     AND public.geo_key(a.geo_ward) = 'BUKURU WARD' AND a.id = v_id;

  IF by_index = by_seq THEN
    -- Not a failure of the migration: on a table this small the planner may
    -- refuse the index whatever enable_seqscan says, and then there is nothing
    -- to demonstrate. Said out loud rather than counted as proof.
    RAISE NOTICE
      'NOTE: index and scan agreed (% vs %) with a stale index, so the planner '
      'did not use it here and this probe cannot demonstrate the hazard. The '
      'REINDEX is still asserted statically by check_a_ward_name_resolves.py',
      by_index, by_seq;
  ELSE
    RAISE NOTICE
      'PASS: a stale index really does disagree with a scan (% vs %) — the '
      'REINDEX in that migration is load-bearing', by_index, by_seq;
  END IF;
  RAISE NOTICE 'PASS: the rebuilt index agrees with the function it is built on';
END $probe$;

DO $probe$ BEGIN RAISE NOTICE 'ALL WARD NAME ASSERTIONS PASSED'; END $probe$;
ROLLBACK;
PROBE
chown postgres:postgres "$PGROOT/zz_ward_name_probe.sql"
WN_OUT=$(psql_run "-f $PGROOT/zz_ward_name_probe.sql" 2>&1) && WN_RC=0 || WN_RC=$?
printf '%s\n' "$WN_OUT" | grep -E "PASS:|FAIL:|NOTE:" | sed 's/^.*NOTICE:  /  /' || true
if [ "$WN_RC" -ne 0 ] || printf '%s\n' "$WN_OUT" | grep -q "FAIL:"; then
  printf '%s\n' "$WN_OUT"
  echo "✗ ward name assertions failed"; exit 1
fi
printf '%s\n' "$WN_OUT" | grep -q "ALL WARD NAME ASSERTIONS PASSED" || {
  printf '%s\n' "$WN_OUT"
  echo "✗ the ward name probe did not reach its verdict"; exit 1; }

# And the geography inventory the operator reads must match the asset and run.
echo "▶ Checking the geography inventory is current and runs"
python3 "$REPO/scripts/sync_geography_inventory.py" --check
GEO_OUT=$(psql_run "-f $PGROOT/which_geography_is_real.sql" 2>&1) && GEO_RC=0 || GEO_RC=$?
if [ "$GEO_RC" -ne 0 ]; then
  printf '%s\n' "$GEO_OUT"
  echo "✗ scripts/which_geography_is_real.sql does not run against this schema"
  exit 1
fi
printf '%s\n' "$GEO_OUT" | grep -q "geographies in use are real" || {
  printf '%s\n' "$GEO_OUT"
  echo "✗ the geography diagnostic produced no summary row"; exit 1; }
echo "  PASS  the geography diagnostic runs and summarises"

# ── One rung, one list ──────────────────────────────────────────────────────
#
# escalation_push_targets() carried four exact-match role arrays of its own,
# which 20261028000000 did not touch. On the deployment a ward escalation was
# addressed to 0 officers and an LGA escalation to 0.
echo "▶ Applying 20261101000000_one_rung_one_list.sql"
psql_run "-f $PGROOT/20261101000000_one_rung_one_list.sql" >/dev/null
psql_run "-f $PGROOT/20261101000000_one_rung_one_list.sql" >/dev/null

cat > "$PGROOT/zz_one_rung_probe.sql" <<'PROBE'
BEGIN;
SET client_min_messages TO NOTICE;

-- ── 1. the list knows both vocabularies, and nothing else ───────────────────
DO $probe$
BEGIN
  IF NOT ('WARD_COMMANDER' = ANY (public.roles_for_tier('WARD'))) THEN
    RAISE EXCEPTION
      'FAIL: roles_for_tier(WARD) does not include WARD_COMMANDER, which is '
      'how the deployment spells it — a ward escalation reaches nobody';
  END IF;
  IF NOT ('STATE_COMMANDER' = ANY (public.roles_for_tier('HQ'))) THEN
    RAISE EXCEPTION 'FAIL: roles_for_tier(HQ) does not include STATE_COMMANDER';
  END IF;
  IF NOT ('LGA_COMMANDER' = ANY (public.roles_for_tier('LGA'))) THEN
    RAISE EXCEPTION 'FAIL: roles_for_tier(LGA) does not include LGA_COMMANDER';
  END IF;
  -- Both spellings, not one replacing the other: a database that still carries
  -- the repository's own names must keep working.
  IF NOT ('WARD_COMMAND' = ANY (public.roles_for_tier('WARD'))) THEN
    RAISE EXCEPTION
      'FAIL: the second spelling replaced the first instead of joining it';
  END IF;
  -- A tier nobody holds addresses nobody. Failing open here pages the state.
  IF array_length(public.roles_for_tier('NONSENSE'), 1) IS NOT NULL THEN
    RAISE EXCEPTION
      'FAIL: an unknown tier returns a non-empty role list, so a malformed '
      'payload would page every officer in Plateau State';
  END IF;
  IF 'CITIZEN' = ANY (public.roles_for_tier('HQ')) THEN
    RAISE EXCEPTION 'FAIL: a citizen holds the HQ rung';
  END IF;
  RAISE NOTICE 'PASS: roles_for_tier knows both spellings of every rung, and nothing else';
END $probe$;

-- ── 2. AND THE NOTICE ACTUALLY REACHES THEM ─────────────────────────────────
--
-- The point is not the array, it is whose phone rings. A ward officer spelled
-- the deployment's way, posted to the incident's ward, with a player id.
DO $probe$
DECLARE
  v_citizen  UUID := gen_random_uuid();
  v_ward     UUID := gen_random_uuid();
  v_elsewhere UUID := gen_random_uuid();
  v_state    UUID := gen_random_uuid();
  v_alert    UUID := gen_random_uuid();
  v_outbox   BIGINT;
  n          INTEGER;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_citizen,   'rung-citizen@probe.test'),
    (v_ward,      'rung-ward@probe.test'),
    (v_elsewhere, 'rung-elsewhere@probe.test'),
    (v_state,     'rung-state@probe.test');

  UPDATE public.profiles SET role = 'WARD_COMMANDER',
         geo_lga = 'JOS SOUTH', geo_ward = 'BUKURU',
         onesignal_player_id = 'player-ward-0001'
   WHERE id = v_ward;
  UPDATE public.profiles SET role = 'WARD_COMMANDER',
         geo_lga = 'JOS SOUTH', geo_ward = 'GIRING',
         onesignal_player_id = 'player-elsewhere-01'
   WHERE id = v_elsewhere;
  UPDATE public.profiles SET role = 'STATE_COMMANDER',
         geo_lga = 'JOS NORTH', geo_ward = 'NARAGUTA',
         onesignal_player_id = 'player-state-0001'
   WHERE id = v_state;

  INSERT INTO public.alerts
    (id, type, description, status, severity, reported_by,
     geo_lga, geo_ward, assigned_tier, tier_assigned_at)
  VALUES (v_alert, 'Kidnap - Held Hostage', 'nobody answered at the unit',
          'OPEN', 'CRITICAL', v_citizen, 'JOS SOUTH', 'BUKURU', 'WARD', NOW());

  INSERT INTO public.notification_outbox (alert_id, kind, payload)
  VALUES (v_alert, 'TIER_ESCALATION', jsonb_build_object(
            'alert_id', v_alert, 'to_tier', 'WARD',
            'geo_lga', 'JOS SOUTH', 'geo_ward', 'BUKURU'))
  RETURNING id INTO v_outbox;

  SELECT count(*) INTO n
    FROM public.escalation_push_targets(v_outbox) t WHERE t.user_id = v_ward;
  IF n <> 1 THEN
    RAISE EXCEPTION
      'FAIL: a WARD_COMMANDER posted to the incident''s own ward is not a '
      'recipient of a WARD escalation. deliverTierEscalation throws "no '
      'reachable officer at that tier" on an empty list, so that notice can '
      'never be delivered to anybody';
  END IF;

  -- The widening must not have reached past the geography.
  SELECT count(*) INTO n
    FROM public.escalation_push_targets(v_outbox) t
   WHERE t.user_id = v_elsewhere;
  IF n <> 0 THEN
    RAISE EXCEPTION
      'FAIL: a ward officer in a DIFFERENT ward was told. Teaching the list a '
      'second spelling must not widen the geography';
  END IF;

  -- HQ is statewide and unfiltered: that is the rung whose job is everything.
  UPDATE public.notification_outbox
     SET payload = jsonb_set(payload, '{to_tier}', '"HQ"')
   WHERE id = v_outbox;
  SELECT count(*) INTO n
    FROM public.escalation_push_targets(v_outbox) t WHERE t.user_id = v_state;
  IF n <> 1 THEN
    RAISE EXCEPTION
      'FAIL: a STATE_COMMANDER is not a recipient of an HQ escalation, so the '
      'top of the chain is addressed to nobody';
  END IF;

  RAISE NOTICE 'PASS: a WARD_COMMANDER in the right ward is told, one in the wrong ward is not, and a STATE_COMMANDER holds HQ';
END $probe$;

DO $probe$ BEGIN RAISE NOTICE 'ALL ONE RUNG ASSERTIONS PASSED'; END $probe$;
ROLLBACK;
PROBE
chown postgres:postgres "$PGROOT/zz_one_rung_probe.sql"
OR_OUT=$(psql_run "-f $PGROOT/zz_one_rung_probe.sql" 2>&1) && OR_RC=0 || OR_RC=$?
printf '%s\n' "$OR_OUT" | grep -E "PASS:|FAIL:" | sed 's/^.*NOTICE:  /  /' || true
if [ "$OR_RC" -ne 0 ] || printf '%s\n' "$OR_OUT" | grep -q "FAIL:"; then
  printf '%s\n' "$OR_OUT"
  echo "✗ one-rung assertions failed"; exit 1
fi
printf '%s\n' "$OR_OUT" | grep -q "ALL ONE RUNG ASSERTIONS PASSED" || {
  printf '%s\n' "$OR_OUT"
  echo "✗ the one-rung probe did not reach its verdict"; exit 1; }

# ── One officer, one account ────────────────────────────────────────────────
#
# The deployment has duplicate staff accounts across two email domains, because
# the badge-to-email derivation carried the domain as a literal in two places.
# The posting is on one account and the officer signs into the other.
echo "▶ Applying 20261102000000_one_officer_one_account.sql"
psql_run "-f $PGROOT/20261102000000_one_officer_one_account.sql" >/dev/null
psql_run "-f $PGROOT/20261102000000_one_officer_one_account.sql" >/dev/null

cat > "$PGROOT/zz_one_account_probe.sql" <<'PROBE'
BEGIN;
SET client_min_messages TO NOTICE;

-- ── 1. a badge is an identity now ───────────────────────────────────────────
DO $probe$
DECLARE
  a UUID := gen_random_uuid();
  b UUID := gen_random_uuid();
  refused BOOLEAN := false;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (a, 'hq-700@operationrainbow.plateau.gov.ng'),
    (b, 'hq-700@plateaueye.example.ng');
  UPDATE public.profiles SET role = 'STATE_COMMANDER', badge_number = 'HQ-700',
         geo_lga = 'JOS NORTH', is_active = true WHERE id = a;
  BEGIN
    UPDATE public.profiles SET role = 'STATE_COMMANDER',
           badge_number = 'hq-700', is_active = true WHERE id = b;
  EXCEPTION WHEN unique_violation THEN refused := true;
  END;
  IF NOT refused THEN
    RAISE EXCEPTION
      'FAIL: two ACTIVE accounts carry badge HQ-700. The badge is what an '
      'officer is called on the radio and what every board labels them with, '
      'and formatOfficerBadge() takes whichever row comes first';
  END IF;
  RAISE NOTICE 'PASS: a second active account cannot take a badge already held';
END $probe$;
ROLLBACK;

BEGIN;
SET client_min_messages TO NOTICE;

-- ── 2. the view names the duplicates, on both keys ──────────────────────────
DO $probe$
DECLARE
  a UUID := gen_random_uuid();
  b UUID := gen_random_uuid();
  c UUID := gen_random_uuid();
  d UUID := gen_random_uuid();
  n INTEGER;
BEGIN
  -- Same local-part, two domains: what "duplicates across two email domains"
  -- is. Different badges so the badge key does not also fire.
  INSERT INTO auth.users (id, email) VALUES
    (a, 'lga-401@operationrainbow.plateau.gov.ng'),
    (b, 'lga-401@plateaueye.example.ng');
  UPDATE public.profiles SET role = 'LGA_COMMANDER', badge_number = 'LGA-401A',
         geo_lga = 'MANGU', onesignal_player_id = 'player-lga-401-aaa'
   WHERE id = a;
  UPDATE public.profiles SET role = 'LGA_COMMANDER', badge_number = 'LGA-401B'
   WHERE id = b;

  SELECT count(*) INTO n FROM public.staff_account_duplicates
   WHERE id IN (a, b);
  IF n <> 2 THEN
    RAISE EXCEPTION
      'FAIL: the view named % of the 2 accounts sharing a local-part across '
      'two domains', n;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.staff_account_duplicates
                  WHERE id = a AND matched_on = 'same name, two domains') THEN
    RAISE EXCEPTION 'FAIL: the view did not say WHY those two matched';
  END IF;
  -- And it has to show which side holds what, because that is what decides
  -- which account to keep.
  IF NOT EXISTS (SELECT 1 FROM public.staff_account_duplicates
                  WHERE id = a AND can_be_pushed AND geo_lga = 'MANGU') THEN
    RAISE EXCEPTION
      'FAIL: the view does not report the posting and the push id, so an '
      'operator cannot tell which account is the live one';
  END IF;

  -- A citizen is not a duplicate desk, whatever their email looks like.
  INSERT INTO auth.users (id, email) VALUES
    (c, 'ada@operationrainbow.plateau.gov.ng'),
    (d, 'ada@plateaueye.example.ng');
  UPDATE public.profiles SET role = 'CITIZEN' WHERE id IN (c, d);
  SELECT count(*) INTO n FROM public.staff_account_duplicates
   WHERE id IN (c, d);
  IF n <> 0 THEN
    RAISE EXCEPTION
      'FAIL: the view named % citizen account(s). Merging one would move '
      'another person''s reports onto somebody else''s id', n;
  END IF;
  RAISE NOTICE 'PASS: the view names staff duplicates on both keys, with what each side holds, and no citizens';
END $probe$;

-- ── 3. the merge moves the work and deletes nothing ─────────────────────────
DO $probe$
DECLARE
  keep    UUID := gen_random_uuid();
  retire  UUID := gen_random_uuid();
  citizen UUID := gen_random_uuid();
  cmd     UUID := gen_random_uuid();
  v_alert UUID := gen_random_uuid();
  k       public.profiles;
  r       public.profiles;
  n       INTEGER;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (keep,    'ward-props@operationrainbow.plateau.gov.ng'),
    (retire,  'ward-props@plateaueye.example.ng'),
    (citizen, 'merge-citizen@probe.test'),
    (cmd,     'merge-command@probe.test');
  -- The account the officer signs into: no posting, no badge, no push id.
  UPDATE public.profiles SET role = 'WARD_COMMANDER', full_name = NULL
   WHERE id = keep;
  -- The one that has everything, and which they never sign into.
  UPDATE public.profiles
     SET role = 'WARD_COMMANDER', badge_number = 'WD-900',
         geo_lga = 'JOS SOUTH', geo_ward = 'BUKURU',
         onesignal_player_id = 'player-ward-900-xx',
         full_name = 'A. Dalyop'
   WHERE id = retire;
  UPDATE public.profiles SET role = 'CITIZEN' WHERE id = citizen;
  UPDATE public.profiles SET role = 'HQ_COMMAND' WHERE id = cmd;

  INSERT INTO public.alerts
    (id, type, description, status, severity, reported_by,
     geo_lga, geo_ward, assigned_tier, tier_assigned_at, assigned_to_uid)
  VALUES (v_alert, 'Fire - Structure', 'dispatched to the wrong account',
          'OPEN', 'HIGH', citizen, 'JOS SOUTH', 'BUKURU', 'WARD', NOW(),
          retire);

  -- A signed-in non-command account may not merge anybody.
  PERFORM set_config('request.jwt.claim.sub', citizen::text, true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', citizen::text, 'role', 'authenticated')::text, true);
  IF auth.uid() <> citizen THEN
    RAISE EXCEPTION 'FAIL: the probe could not sign anybody in, so the '
      'permission assertions below would pass vacuously';
  END IF;
  BEGIN
    PERFORM public.merge_staff_account(keep, retire);
    RAISE EXCEPTION
      'FAIL: a citizen merged two staff accounts. That reassigns incidents '
      'and stands an officer down';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;

  PERFORM set_config('request.jwt.claim.sub', cmd::text, true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', cmd::text, 'role', 'authenticated')::text, true);

  -- A citizen account is never a merge target.
  BEGIN
    PERFORM public.merge_staff_account(keep, citizen);
    RAISE EXCEPTION 'FAIL: a citizen account was merged into a staff one';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE EXCEPTION 'FAIL: command was refused its own merge';
  WHEN others THEN NULL;
  END;

  PERFORM public.merge_staff_account(keep, retire);

  SELECT * INTO k FROM public.profiles WHERE id = keep;
  SELECT * INTO r FROM public.profiles WHERE id = retire;

  IF k.geo_ward IS DISTINCT FROM 'BUKURU' OR k.badge_number IS DISTINCT FROM 'WD-900'
     OR k.onesignal_player_id IS DISTINCT FROM 'player-ward-900-xx'
     OR k.full_name IS DISTINCT FROM 'A. Dalyop' THEN
    RAISE EXCEPTION
      'FAIL: the kept account did not inherit the posting, badge, push id and '
      'name (ward=%, badge=%, push=%, name=%)',
      k.geo_ward, k.badge_number, k.onesignal_player_id, k.full_name;
  END IF;

  SELECT count(*) INTO n FROM public.alerts
   WHERE id = v_alert AND assigned_to_uid = keep;
  IF n <> 1 THEN
    RAISE EXCEPTION
      'FAIL: the incident is still assigned to the retired account, so it is '
      'on a board nobody opens';
  END IF;

  IF r.id IS NULL THEN
    RAISE EXCEPTION
      'FAIL: the retired account was DELETED. That cascades to auth.users and '
      'takes its record of who reported what with it';
  END IF;
  IF r.is_active IS NOT false OR r.badge_number IS NOT NULL
     OR r.geo_ward IS NOT NULL OR r.onesignal_player_id IS NOT NULL THEN
    RAISE EXCEPTION
      'FAIL: the retired account is still live-looking (active=%, badge=%, '
      'ward=%, push=%)',
      r.is_active, r.badge_number, r.geo_ward, r.onesignal_player_id;
  END IF;
  IF r.full_name NOT LIKE '%MERGED INTO%' THEN
    RAISE EXCEPTION 'FAIL: the retired account does not say where it went';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', '', true);
  RAISE NOTICE 'PASS: the merge moves the incidents and the posting, stands the other down, and deletes nothing';
END $probe$;

-- ── 4. and it never overwrites what the kept account already knows ──────────
DO $probe$
DECLARE
  keep   UUID := gen_random_uuid();
  retire UUID := gen_random_uuid();
  cmd    UUID := gen_random_uuid();
  k      public.profiles;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (keep,   'lga-keep@operationrainbow.plateau.gov.ng'),
    (retire, 'lga-keep@plateaueye.example.ng'),
    (cmd,    'merge-command-2@probe.test');
  UPDATE public.profiles SET role = 'LGA_COMMANDER', geo_lga = 'MANGU',
         badge_number = 'LGA-901' WHERE id = keep;
  UPDATE public.profiles SET role = 'LGA_COMMANDER', geo_lga = 'WASE',
         badge_number = 'LGA-902' WHERE id = retire;
  UPDATE public.profiles SET role = 'HQ_COMMAND' WHERE id = cmd;

  PERFORM set_config('request.jwt.claim.sub', cmd::text, true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', cmd::text, 'role', 'authenticated')::text, true);
  PERFORM public.merge_staff_account(keep, retire);
  SELECT * INTO k FROM public.profiles WHERE id = keep;

  IF k.geo_lga <> 'MANGU' OR k.badge_number <> 'LGA-901' THEN
    RAISE EXCEPTION
      'FAIL: the merge overwrote the kept account''s own posting or badge with '
      'the abandoned one''s (lga=%, badge=%). The surviving account is the one '
      'somebody signs into; what it knows about itself wins',
      k.geo_lga, k.badge_number;
  END IF;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', '', true);
  RAISE NOTICE 'PASS: a merge fills blanks and overwrites nothing';
END $probe$;

DO $probe$ BEGIN RAISE NOTICE 'ALL ONE ACCOUNT ASSERTIONS PASSED'; END $probe$;
ROLLBACK;
PROBE
chown postgres:postgres "$PGROOT/zz_one_account_probe.sql"
OA_OUT=$(psql_run "-f $PGROOT/zz_one_account_probe.sql" 2>&1) && OA_RC=0 || OA_RC=$?
printf '%s\n' "$OA_OUT" | grep -E "PASS:|FAIL:" | sed 's/^.*NOTICE:  /  /' || true
if [ "$OA_RC" -ne 0 ] || printf '%s\n' "$OA_OUT" | grep -q "FAIL:"; then
  printf '%s\n' "$OA_OUT"
  echo "✗ one-account assertions failed"; exit 1
fi
printf '%s\n' "$OA_OUT" | grep -q "ALL ONE ACCOUNT ASSERTIONS PASSED" || {
  printf '%s\n' "$OA_OUT"
  echo "✗ the one-account probe did not reach its verdict"; exit 1; }

echo "▶ Asserting no policy in schema public reaches anon or public, by name"
PR_OUT=$(psql_run "-f $PGROOT/policy_roles_behaviour_test.sql" 2>&1) && PR_RC=0 || PR_RC=$?
echo "$PR_OUT" | grep -E "PASS|FAIL|ERROR" || true
if [ "$PR_RC" -ne 0 ] || echo "$PR_OUT" | grep -q "ERROR"; then
  echo "$PR_OUT"; echo "✗ policy-role assertions failed"; exit 1
fi

echo "▶ Asserting a complaint about an officer does not reach that officer"
OVS_OUT=$(psql_run "-f $PGROOT/oversight_behaviour_test.sql" 2>&1) && OVS_RC=0 || OVS_RC=$?
echo "$OVS_OUT" | grep -E "PASS|FAIL|ERROR" || true
if [ "$OVS_RC" -ne 0 ]; then
  echo "$OVS_OUT"; echo "✗ oversight assertions failed"; exit 1
fi

echo "▶ Asserting the mesh recognises a duplicate, and forgets in time"
MESH_OUT=$(psql_run "-f $PGROOT/mesh_ingest_behaviour_test.sql" 2>&1) && MESH_RC=0 || MESH_RC=$?
echo "$MESH_OUT" | grep -E "PASS|FAIL|ERROR" || true
if [ "$MESH_RC" -ne 0 ]; then
  echo "$MESH_OUT"
  echo "✗ mesh ingest assertions failed"
  exit 1
fi

echo "▶ Asserting who can watch whom, and for how long"
PRIV_OUT=$(psql_run "-f $PGROOT/privacy_behaviour_test.sql" 2>&1) && PRIV_RC=0 || PRIV_RC=$?
echo "$PRIV_OUT" | grep -E "PASS|FAIL|ERROR" || true
if [ "$PRIV_RC" -ne 0 ]; then
  echo "$PRIV_OUT"
  echo "✗ privacy assertions failed"
  exit 1
fi
printf '%s\n' "$CHAIN_OUT" | grep -E "PASS|FAIL|ALL COMMAND" || true
if [ "$CHAIN_RC" -ne 0 ]; then
  # The ERROR line first: a statement dump is ~20 lines and pushes the actual
  # message out of a tail window, which is how a failure arrives with no reason.
  printf '%s\n' "$CHAIN_OUT" | grep -E "ERROR|WARNING|FAIL" | head -10
  printf '%s\n' "$CHAIN_OUT" | grep -vE "PASS" | tail -25
  echo "::error::the command chain does not behave as specified"; exit 1
fi

echo "▶ Agency access / realtime / storage behaviour test"
PR_OUT=$(psql_run "-f $PGROOT/production_readiness_behaviour_test.sql" 2>&1) && PR_RC=0 || PR_RC=$?
printf '%s\n' "$PR_OUT" | grep -E "PASS|FAIL|ALL PRODUCTION" || true
if [ "$PR_RC" -ne 0 ]; then
  printf '%s\n' "$PR_OUT" | grep -vE "PASS" | tail -20
  echo "::error::production readiness behaviour test FAILED"; exit 1
fi

# The demonstration seed is handed to people to run against staging, so it is
# applied here to prove it actually applies: a seed that fails halfway leaves a
# half-populated console, which is worse than an empty one.
#
# LAST, after every behaviour test, and deliberately so. It COMMITs thirteen
# incidents; several of those tests count rows across a whole table rather than
# the rows they created, so seeding before them turns a passing assertion about
# row-level security into a failure about data it never wrote.
echo "▶ Applying the demonstration seed"
SEED_OUT=$(psql_run "-f $PGROOT/seed_demo_incidents.sql" 2>&1) && SEED_RC=0 || SEED_RC=$?
echo "$SEED_OUT" | grep -E "seeded|ERROR" || true
if [ "$SEED_RC" -ne 0 ]; then
  echo "$SEED_OUT"
  echo "✗ the demonstration seed does not apply"
  exit 1
fi

# A diagnostic that errors is worse than no diagnostic: it gets handed to an
# operator during an incident, when nobody has time to debug the debugger. Run
# it here, after the seed, so its queries are checked against the real schema.
echo "▶ Checking the empty-board diagnostic still runs"
DIAG_OUT=$(psql_run "-f $PGROOT/why_is_the_board_empty.sql" 2>&1) && DIAG_RC=0 || DIAG_RC=$?
if [ "$DIAG_RC" -ne 0 ]; then
  echo "$DIAG_OUT"
  echo "✗ scripts/why_is_the_board_empty.sql does not run against this schema"
  exit 1
fi
# It must be ONE statement. The Supabase editor shows only the last result set of
# a multi-statement run, so six SELECTs meant an operator ran it a section at a
# time and reported one table per message — and on one of those runs a bare
# "0 rows" came back with nothing to say which section produced it.
DIAG_STMTS=$(python3 "$REPO/scripts/check_generated_column_inserts.py" --statements \
               "$REPO/scripts/why_is_the_board_empty.sql")
[ "$DIAG_STMTS" -eq 1 ] || {
  echo "✗ why_is_the_board_empty.sql is $DIAG_STMTS statements; the Supabase editor"
  echo "  would show only the last result. It must be exactly one."
  exit 1
}

# It must also actually SEE the seeded rows, or it is reassuring about nothing.
#
# Read the `incidents / counts` row and pull [DEMO] out of it. An earlier gate
# grepped for "^ *13 *|" anywhere in the output and passed against section 5's
# open_incidents, which happened to be 13 too — a gate that agreed for a reason
# unrelated to what it claimed to check. Anchoring on the row's own name is what
# stops that.
DIAG_DEMO=$(printf '%s\n' "$DIAG_OUT" \
  | grep -E '\| *incidents *\| *counts *\|' \
  | sed -nE 's/.*\[DEMO\] ([0-9]+).*/\1/p' | head -1)
if [ "$DIAG_DEMO" != "13" ]; then
  echo "$DIAG_OUT"
  echo "✗ the diagnostic ran but reported [DEMO]=${DIAG_DEMO:-<nothing>}, expected 13"
  exit 1
fi

# And the computed verdict must fire. The whole point of folding six sections
# into one query was that it can name the first cause itself; a verdict section
# that never produces a row would be decoration.
printf '%s\n' "$DIAG_OUT" | grep -qE '\| *verdict *\|' || {
  echo "$DIAG_OUT"
  echo "✗ the diagnostic produced no verdict row — it cannot name a cause"
  exit 1
}
echo "  PASS  the diagnostic is one statement, counts the seeded incidents, and reaches a verdict"
# Print what it concluded. A diagnostic that always reaches the same verdict is
# how one degrades into decoration, and the only way to notice is to see the
# answer in the log rather than just that there was one.
printf '%s\n' "$DIAG_OUT" | grep -E '\| *verdict *\|' | sed 's/^/        /' || true

# The second diagnostic, for the failure the first one cannot explain: an insert
# refused with 428C9. It reads the catalog, so it has to be run against a real
# schema or its queries are only plausible. It must also NAME the generated
# column — a version that ran cleanly and reported nothing would send an
# operator looking somewhere else.
echo "▶ Checking the refused-insert diagnostic still runs"
GEN_OUT=$(psql_run "-f $PGROOT/why_did_my_insert_fail.sql" 2>&1) && GEN_RC=0 || GEN_RC=$?
if [ "$GEN_RC" -ne 0 ]; then
  echo "$GEN_OUT"
  echo "✗ scripts/why_did_my_insert_fail.sql does not run against this schema"
  exit 1
fi
printf '%s\n' "$GEN_OUT" | grep -q "generated column *| *category" || {
  echo "$GEN_OUT"
  echo "✗ the diagnostic ran but did not report alerts.category as generated"
  exit 1
}
# And it must be ONE statement. The Supabase SQL editor shows only the last
# result set of a multi-statement run, so a file of several SELECTs silently
# hides all but the final one — which is how an operator ends up running a
# diagnostic section by section and reporting it a section at a time.
#
# Counted by the stripper rather than with awk. Counting semicolons with awk
# said two for this one-statement file, because one of them lives inside the
# regex literal `'…alerts[^;]{0,100}'`.
STMTS=$(python3 "$REPO/scripts/check_generated_column_inserts.py" --statements \
          "$REPO/scripts/why_did_my_insert_fail.sql")
[ "$STMTS" -eq 1 ] || {
  echo "✗ why_did_my_insert_fail.sql is $STMTS statements; the Supabase editor "
  echo "  would show only the last result. It must be exactly one."
  exit 1
}
# And it must see the trigger the migrations create, so an extra one added by
# hand in the dashboard stands out against a known baseline rather than against
# nothing.
#
# Only `route_oversight_to_hq_trg` is asserted. `trg_alerts_updated_at` comes
# from 20260721000000_v2_agency_tables.sql, which this harness deliberately does
# not replay — it applies 20260812000000_agency_tables.sql instead, which is the
# file that creates those tables on a database that lacks them. Requiring it
# here failed for that reason and not for any fault in the diagnostic.
#
# That difference is worth keeping in mind when reading the diagnostic against a
# real deployment: this schema has `category` as its ONLY generated column on
# alerts, whereas 20260721000000 also declares `lga`, `ward` and `pu`. Which of
# those a given database has decides which column name a 428C9 error reports.
printf '%s\n' "$GEN_OUT" | grep -q route_oversight_to_hq_trg || {
  echo "$GEN_OUT"
  echo "✗ the diagnostic did not list the route_oversight_to_hq_trg trigger"; exit 1; }
echo "  PASS  the refused-insert diagnostic names the generated column and the trigger"

# ── Which migrations has this database had? ──────────────────────────────────
#
# Twice an operational failure has come down to a migration that was never
# applied, and neither time did it present that way: the agency tables existed
# in production because someone made them by hand, and route_oversight_to_hq_trg
# was absent from a live database whose console already shipped screens calling
# audit_trail() and latest_ai_report(). A missing function is a failed RPC when
# somebody opens a screen during an incident.
#
# The inventory is extracted from the migrations, so it cannot drift into being
# reassuring about objects it never learned existed.
echo "▶ Checking the migration inventory is current"
python3 "$REPO/scripts/sync_migration_inventory.py" --check

echo "▶ Checking every applied migration's objects exist"
MIG_OUT=$(psql_run "-f $PGROOT/which_migrations_are_applied.sql" 2>&1) && MIG_RC=0 || MIG_RC=$?
if [ "$MIG_RC" -ne 0 ]; then
  echo "$MIG_OUT"
  echo "✗ scripts/which_migrations_are_applied.sql does not run against this schema"
  exit 1
fi
# Everything must be present EXCEPT the v2–v5 era, which this harness
# deliberately does not replay (20260812000000_agency_tables.sql stands in for
# it). A missing object from any other migration means either the migration
# does not do what its file says, or this harness has stopped applying it — and
# both are the kind of gap that only shows up in production.
MISSING=$(printf '%s\n' "$MIG_OUT" | awk -F'|' '
  { for (i = 1; i <= NF; i++) gsub(/^[ \t]+|[ \t]+$/, "", $i) }
  $2 == "missing" && $4 !~ /^2026072[1-4]000000_v[2-5]/ { print "    " $3 "  (" $4 ")" }')
if [ -n "$MISSING" ]; then
  echo "$MISSING"
  echo "✗ objects declared by an applied migration are absent from the schema"
  exit 1
fi
# And the v2–v5 era must actually be RECOGNISED rather than silently absent, or
# the exemption above would hide a real regression the day one of those files
# starts being replayed.
printf '%s\n' "$MIG_OUT" | grep -q "absence is not a fault" || {
  echo "$MIG_OUT"
  echo "✗ the inventory did not mark the hand-made v2–v5 migrations"; exit 1; }
echo "  PASS  every object from every replayed migration is present"

# ── And the objects a migration REMOVES are actually gone ────────────────────
#
# The inventory used to assert existence only, which made it actively misleading
# about the one migration that drops things. All seven objects 20261018000000
# removes were must-be-present rows inherited from v2 and v5, so the moment an
# operator applied it the diagnostic would report seven MISSING objects and name
# 20260721000000_v2_agency_tables / 20260724000000_v5_rls_security as the files
# to apply — and applying those would recreate the generated mirrors that
# migration exists to remove, restoring the ordinal difference that made one
# 428C9 error name `lga` on production and `category` in this harness.
#
# A drop-only migration was also invisible, because it creates nothing to count.
# Now it reads `0 of N removed — NEVER APPLIED` before and `N of N removed`
# after, which is the only signal this script can give that it landed.
read -r DROP_MIG DROP_N < <(python3 "$REPO/scripts/sync_migration_inventory.py" --drops)
[ -n "$DROP_MIG" ] && [ -n "$DROP_N" ] || {
  echo "✗ could not read the dropping migration from sync_migration_inventory.py"
  exit 1; }

check_drops_reported_gone() {
  # $1 = inventory output, $2 = context for the failure message
  local out="$1" context="$2" still
  still=$(printf '%s\n' "$out" | awk -F'|' '
    { for (i = 1; i <= NF; i++) gsub(/^[ \t]+|[ \t]+$/, "", $i) }
    $2 == "still present" { print "    " $3 }')
  if [ -n "$still" ]; then
    echo "$still"
    echo "✗ $context: objects $DROP_MIG removes are still in the schema"
    return 1
  fi
  printf '%s\n' "$out" | awk -F'|' -v m="$DROP_MIG" -v n="$DROP_N" '
    { for (i = 1; i <= NF; i++) gsub(/^[ \t]+|[ \t]+$/, "", $i) }
    $2 == "summary" && $3 == m { found = 1; if ($4 != n " of " n " removed") bad = $4 }
    END { exit (found && bad == "") ? 0 : 1 }' || {
    printf '%s\n' "$out" | grep -F "$DROP_MIG" | sed 's/^/    /'
    echo "✗ $context: expected \"$DROP_N of $DROP_N removed\" for $DROP_MIG"
    return 1; }
  return 0
}

check_drops_reported_gone "$MIG_OUT" "after the replay" || exit 1
echo "  PASS  the $DROP_N objects $DROP_MIG removes are gone, and it says so"

# Prove the assertion can fail. Without this the two checks above pass on any
# database that never had the mirrors in the first place — including one where
# the must-be-absent rows were dropped from the generated file by a bug, which
# is exactly the failure mode that produced the misleading version.
cat > "$PGROOT/zz_replant_mirrors.sql" <<'PLANT'
ALTER TABLE public.alerts
  ADD COLUMN lga  TEXT GENERATED ALWAYS AS (geo_lga)  STORED,
  ADD COLUMN ward TEXT GENERATED ALWAYS AS (geo_ward) STORED,
  ADD COLUMN pu   TEXT GENERATED ALWAYS AS (geo_pu)   STORED;
ALTER TABLE public.profiles
  ADD COLUMN lga  TEXT GENERATED ALWAYS AS (geo_lga)  STORED,
  ADD COLUMN ward TEXT GENERATED ALWAYS AS (geo_ward) STORED;
CREATE FUNCTION public.is_hq_or_admin() RETURNS boolean LANGUAGE sql AS $fn$ SELECT true $fn$;
CREATE FUNCTION public.is_responder()   RETURNS boolean LANGUAGE sql AS $fn$ SELECT true $fn$;
PLANT
cat > "$PGROOT/zz_unplant_mirrors.sql" <<'UNPLANT'
ALTER TABLE public.alerts   DROP COLUMN lga, DROP COLUMN ward, DROP COLUMN pu;
ALTER TABLE public.profiles DROP COLUMN lga, DROP COLUMN ward;
DROP FUNCTION public.is_hq_or_admin();
DROP FUNCTION public.is_responder();
UNPLANT
chown postgres:postgres "$PGROOT/zz_replant_mirrors.sql" "$PGROOT/zz_unplant_mirrors.sql"

psql_run "-f $PGROOT/zz_replant_mirrors.sql" >/dev/null || {
  echo "✗ could not plant the mirrors back — the probe cannot run"; exit 1; }
REPLANT_OUT=$(psql_run "-f $PGROOT/which_migrations_are_applied.sql" 2>&1)
# Must now FAIL, and name all of them.
if check_drops_reported_gone "$REPLANT_OUT" "with the mirrors planted" >/dev/null 2>&1; then
  echo "✗ the inventory reported the mirrors gone while they were in the schema"
  echo "  — the must-be-absent rows are not reaching the generated file"
  psql_run "-f $PGROOT/zz_unplant_mirrors.sql" >/dev/null 2>&1 || true
  exit 1
fi
PLANTED=$(printf '%s\n' "$REPLANT_OUT" | awk -F'|' '
  { for (i = 1; i <= NF; i++) gsub(/^[ \t]+|[ \t]+$/, "", $i) }
  $2 == "still present" { n++ } END { print n + 0 }')
[ "$PLANTED" = "$DROP_N" ] || {
  echo "✗ planted $DROP_N objects back but the inventory named $PLANTED"
  psql_run "-f $PGROOT/zz_unplant_mirrors.sql" >/dev/null 2>&1 || true
  exit 1; }
printf '%s\n' "$REPLANT_OUT" | grep -q "0 of $DROP_N removed — NEVER APPLIED" || {
  printf '%s\n' "$REPLANT_OUT" | grep -F "$DROP_MIG" | sed 's/^/    /'
  echo "✗ the summary did not read \"0 of $DROP_N removed — NEVER APPLIED\""
  psql_run "-f $PGROOT/zz_unplant_mirrors.sql" >/dev/null 2>&1 || true
  exit 1; }

# And put the schema back, or every later check runs against a database that
# has the mirrors — the state this migration exists to prevent.
psql_run "-f $PGROOT/zz_unplant_mirrors.sql" >/dev/null || {
  echo "✗ could not remove the planted mirrors; the rest of this run is invalid"
  exit 1; }
RESTORED=$(psql_run "-f $PGROOT/which_migrations_are_applied.sql" 2>&1)
check_drops_reported_gone "$RESTORED" "after removing the planted mirrors" || exit 1
echo "  PASS  and it names all $DROP_N when they are planted back, so it checks something"

# ── And a migration that only REWRITES a function body is visible ────────────
#
# `20261028000000_command_knows_both_vocabularies` replaces two functions and
# creates nothing. Object existence cannot see it: `is_command` is present
# either way. So the diagnostic reported it `not detectable — every object it
# declares is already created by an earlier migration`, and the operator who
# ran it against the live project got that line for the one migration that
# decides whether a STATE_COMMANDER can post an advisory at all.
#
# Sixteen replacements in this history had the same blind spot, among them
# `20260927000000_signup_cannot_choose_role` — whose entire change is deleting
# `COALESCE(NEW.raw_user_meta_data->>'role', 'CITIZEN')` from `handle_new_user`,
# so that a new account cannot name its own role. Unverifiable, in a report
# whose own header says a clean result is not evidence.
#
# The `function body` rows close that. This probe puts the pre-migration bodies
# back and requires the diagnostic to say so — because the rows pass trivially
# on a database where the migration HAS been applied, which is every database
# this harness builds. The failing direction is the one worth proving, and it is
# the state the live project was actually in.
echo "▶ Checking a replaced function body is detected, not assumed"
su postgres -s /bin/bash -c \
  "psql -h $PGROOT/sock -p $PORT -U postgres -d rainbow -tAc \
   \"SELECT pg_get_functiondef(p.oid) || ';' FROM pg_proc p
       JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public'
        AND p.proname IN ('is_command', 'commands_whole_state')\"" \
  > "$PGROOT/zz_command_restore.sql"
# Restored from pg_get_functiondef rather than from a copy of the new body
# written out here: a hand-written restore is a second definition of the thing
# under test, and would keep passing after the migration changed.
grep -qc 'STATE_COMMANDER' "$PGROOT/zz_command_restore.sql" || {
  echo "✗ could not read back is_command/commands_whole_state to restore them"
  exit 1; }

# The bodies as they stood before 20261028000000 — an exact-match list of four
# deployment-era names, which is what the live project has.
cat > "$PGROOT/zz_command_old.sql" <<'OLDBODY'
CREATE OR REPLACE FUNCTION public.is_command()
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public AS $fn$
  SELECT COALESCE(
    (SELECT role FROM public.profiles WHERE id = auth.uid())
      IN ('HQ_COMMAND', 'HQ_OFFICER', 'ADMIN', 'LGA_COMMAND'),
    false
  );
$fn$;
CREATE OR REPLACE FUNCTION public.commands_whole_state()
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public, pg_temp AS $fn$
  SELECT COALESCE(
    (SELECT upper(coalesce(role, '')) FROM public.profiles WHERE id = auth.uid())
      IN ('HQ_COMMAND', 'HQ_OFFICER', 'ADMIN'),
    false
  );
$fn$;
OLDBODY
chown postgres:postgres "$PGROOT/zz_command_restore.sql" "$PGROOT/zz_command_old.sql"

psql_run "-f $PGROOT/zz_command_old.sql" >/dev/null || {
  echo "✗ could not install the pre-migration bodies — the probe cannot run"
  exit 1; }
OLD_OUT=$(psql_run "-f $PGROOT/which_migrations_are_applied.sql" 2>&1)
restore_command_bodies() {
  psql_run "-f $PGROOT/zz_command_restore.sql" >/dev/null || {
    echo "✗ could not restore is_command/commands_whole_state; the rest of this"
    echo "  run would be against a schema where eight of ten commanders are"
    echo "  refused by every policy gated on is_command()."
    exit 1; }
}
for fn in is_command commands_whole_state; do
  printf '%s\n' "$OLD_OUT" | grep -q "function $fn does not contain" || {
    printf '%s\n' "$OLD_OUT" | grep -F 20261028000000 | sed 's/^/    /'
    echo "✗ the old $fn body was installed and the inventory did not say so"
    restore_command_bodies
    exit 1; }
done
printf '%s\n' "$OLD_OUT" | grep -q "20261028000000_command_knows_both_vocabularies .*0 of 2 present — NEVER APPLIED" || {
  printf '%s\n' "$OLD_OUT" | grep -F 20261028000000 | sed 's/^/    /'
  echo "✗ expected \"0 of 2 present — NEVER APPLIED\" for the vocabulary migration"
  restore_command_bodies
  exit 1; }
restore_command_bodies
BACK_OUT=$(psql_run "-f $PGROOT/which_migrations_are_applied.sql" 2>&1)
printf '%s\n' "$BACK_OUT" | grep -q "20261028000000_command_knows_both_vocabularies .*2 of 2 present" || {
  printf '%s\n' "$BACK_OUT" | grep -F 20261028000000 | sed 's/^/    /'
  echo "✗ the bodies were restored and the inventory still reports them missing"
  exit 1; }
printf '%s\n' "$BACK_OUT" | awk -F'|' '
  { for (i = 1; i <= NF; i++) gsub(/^[ \t]+|[ \t]+$/, "", $i) }
  $2 == "missing" && $4 !~ /^2026072[1-4]000000_v[2-5]/ { bad = 1 }
  END { exit bad ? 1 : 0 }' || {
  echo "✗ restoring the bodies left other objects reported missing"; exit 1; }
echo "  PASS  the old bodies are named, the new ones clear it"

# ── No policy reaches anon or public — asked at the END this time ─────────────
#
# This is already asserted earlier, immediately after
# 20260813000000_rls_least_privilege.sql. That assertion passes and always has,
# and it missed a real defect on a live database for weeks:
#
#   telemetry | telemetry_select_geo_lga_scoped | SELECT | {public}
#
# created by 20260725000000_v6_geo_lga_scoping_staging.sql with no `TO` clause,
# which PostgreSQL records as TO PUBLIC, and PUBLIC includes anon. 20260813 could
# not drop it by name — it predates the file. And the check could not see it,
# because at the point it runs, eleven migrations before 20260725 is applied, the
# policy does not exist yet.
#
# A check at one point in the history cannot answer a question about the end
# state. Both now run: the early one proves the migration does its job, this one
# proves nothing later undoes it.
FINAL_OPEN=$(su postgres -s /bin/bash -c "psql -h $PGROOT/sock -p $PORT -U postgres -d rainbow -tAc \
  \"select tablename || '.' || policyname || ' ' || roles::text from pg_policies \
    where schemaname='public' and ('anon' = any(roles) or 'public' = any(roles)) \
    order by tablename, policyname;\"")
if [ -n "$FINAL_OPEN" ]; then
  printf '%s\n' "$FINAL_OPEN" | sed 's/^/    /'
  echo "✗ after the FULL replay, the policies above reach anon or public."
  echo "  A policy with no TO clause is recorded as TO PUBLIC, and PUBLIC"
  echo "  includes anon. Add TO authenticated where it belongs."
  exit 1
fi
echo "  PASS  after the full replay, no policy in public reaches anon or public"

# A gate nobody has watched fail is not a gate. The early version of this exact
# check has passed every run for weeks while a TO PUBLIC policy sat on telemetry,
# so "it reports clean" earns no credit on its own — plant one and confirm the
# query finds it.
#
# Staged as a FILE rather than passed with -c. The first attempt nested three
# levels of quoting inside `su … -c "psql … -tAc \\\"…\\\""` and bash rejected
# the line before psql saw it: `syntax error near unexpected token '('`. The rest
# of this script uses one level; a file needs none.
cat > "$PGROOT/zz_public_probe.sql" <<'PROBE'
CREATE POLICY zz_public_probe ON public.app_config FOR SELECT USING (true);
SELECT 'found=' || tablename || '.' || policyname
  FROM pg_policies
 WHERE schemaname = 'public'
   AND ('anon' = ANY(roles) OR 'public' = ANY(roles));
DROP POLICY zz_public_probe ON public.app_config;
SELECT 'leftover=' || count(*)
  FROM pg_policies
 WHERE schemaname = 'public' AND policyname = 'zz_public_probe';
PROBE
chown postgres:postgres "$PGROOT/zz_public_probe.sql"
PROBE_OUT=$(psql_run "-t -A -f $PGROOT/zz_public_probe.sql" 2>&1)
printf '%s\n' "$PROBE_OUT" | grep -qx "found=app_config.zz_public_probe" || {
  printf '%s\n' "$PROBE_OUT" | sed 's/^/    /'
  echo "✗ a policy with no TO clause was not detected — this sweep checks nothing"
  exit 1; }
# And the probe must be gone, or the sweep would fail on every later run.
printf '%s\n' "$PROBE_OUT" | grep -qx "leftover=0" || {
  printf '%s\n' "$PROBE_OUT" | sed 's/^/    /'
  echo "✗ the probe policy outlived the check"; exit 1; }
echo "  PASS  and it detects a planted TO PUBLIC policy, so it is checking something"

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
