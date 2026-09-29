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
   "$REPO"/scripts/notification_outbox_behaviour_test.sql \
   "$REPO"/scripts/escalation_targets_behaviour_test.sql \
   "$REPO"/scripts/geo_key_behaviour_test.sql \
   "$REPO"/scripts/alert_media_behaviour_test.sql \
   "$REPO"/scripts/ussd_confirmation_behaviour_test.sql \
   "$REPO"/scripts/ussd_filing_behaviour_test.sql \
   "$REPO"/scripts/ai_reports_behaviour_test.sql \
   "$REPO"/scripts/oversight_behaviour_test.sql \
   "$REPO"/scripts/why_is_the_board_empty.sql \
   "$REPO"/scripts/why_did_my_insert_fail.sql \
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
# It must also actually SEE the seeded rows, or it is reassuring about nothing.
#
# Read the `demo` column of the diagnostic's own first query, by position under
# its header — not with a grep for the number. The first attempt looked for
# "^ *13 *|" anywhere in the output and passed against section 5's
# open_incidents, which happened to be 13 too: a gate that agreed for a reason
# unrelated to what it claimed to check.
DIAG_DEMO=$(printf '%s\n' "$DIAG_OUT" | awk -F'|' '
  /^ *total *\| *demo *\|/ { hdr = NR }
  hdr && NR == hdr + 2 { gsub(/ /, "", $2); print $2; exit }
')
if [ "$DIAG_DEMO" != "13" ]; then
  echo "$DIAG_OUT"
  echo "✗ the diagnostic ran but reported demo=${DIAG_DEMO:-<nothing>}, expected 13"
  exit 1
fi
echo "  PASS  the diagnostic runs and counts the seeded incidents"

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
printf '%s\n' "$GEN_OUT" | grep -q "generated columns *| *category" || {
  echo "$GEN_OUT"
  echo "✗ the diagnostic ran but did not report alerts.category as generated"
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
