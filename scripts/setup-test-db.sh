#!/bin/bash
# ============================================================
# Builds a complete Rainbow schema on a plain PostgreSQL database: the Supabase
# shim first, then every migration in the documented order.
#
#   DATABASE_URL="postgresql://..." ./scripts/setup-test-db.sh
#
# For CI and local scratch databases only — the shim redefines objects that
# Supabase owns. Never point this at a real Supabase project.
# ============================================================
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -z "${DATABASE_URL:-}" ]; then
  echo -e "${RED}DATABASE_URL is not set.${NC}" >&2
  exit 1
fi

command -v psql >/dev/null 2>&1 || {
  echo -e "${RED}psql is required but not installed.${NC}" >&2
  exit 1
}

# The migrations are written to be idempotent, so they emit a great many
# "already exists, skipping" NOTICEs. Quiet them so a genuine WARNING or ERROR
# is actually visible in the output.
export PGOPTIONS='-c client_min_messages=warning'

# Applied in this order. The escalation engine depends on app_config (phase3)
# and on the role helpers auth_role()/is_staff()/is_command() that
# 20260813000000_rls_least_privilege.sql defines.
MIGRATIONS=(
  "20260720000000_initial_schema.sql"
  "phase1_foundation.sql"
  "phase2_assigned_responders.sql"
  "phase3_profile_columns_and_config.sql"
  "20260812000000_agency_tables.sql"
  "20260813000000_rls_least_privilege.sql"
  "20260902000000_per_user_emergency_pins.sql"
  "20260903000000_realtime_publication.sql"
  "20260903000001_incident_media_storage.sql"
  "20260903000002_system_alerts_broadcast.sql"
  "20260903000003_alert_escalation_columns.sql"
  "20260903000004_profiles_badge_number.sql"
  "20260903000005_alerts_assigned_tier.sql"
  "20260925000000_escalation_engine.sql"
  "20260925000001_escalation_followups.sql"
)

echo -e "${YELLOW}Applying Supabase shim...${NC}"
psql "$DATABASE_URL" -X -q -v ON_ERROR_STOP=1 -f "$REPO_ROOT/supabase/tests/postgres_shim.sql"

for m in "${MIGRATIONS[@]}"; do
  printf '  %-45s' "$m"
  if psql "$DATABASE_URL" -X -q -v ON_ERROR_STOP=1 \
       -f "$REPO_ROOT/supabase/migrations/$m" >/dev/null; then
    echo -e "${GREEN}ok${NC}"
  else
    echo -e "${RED}FAILED${NC}"
    exit 1
  fi
done

echo -e "${GREEN}✓ Schema ready.${NC}"
