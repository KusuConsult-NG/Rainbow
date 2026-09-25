#!/bin/bash
# ============================================================
# Runs the escalation-engine regression tests against a Postgres
# database that already has every migration in supabase/migrations applied.
#
#   DATABASE_URL="postgresql://..." ./scripts/test-escalation-engine.sh
#
# The test file wraps everything in a transaction and rolls back, so it leaves
# no rows behind — but it does exercise the live engine, so point it at a
# scratch or staging database, never at production.
# ============================================================
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Every suite under supabase/tests/, in apply order. postgres_shim.sql is
# fixture, not a test, so it is not listed.
TEST_FILES=(
  "escalation_engine_test.sql"
  "escalation_followups_test.sql"
)

if [ -z "${DATABASE_URL:-}" ]; then
  echo -e "${YELLOW}DATABASE_URL is not set — skipping escalation engine tests.${NC}"
  echo "  Set it to a scratch database with all migrations applied, e.g.:"
  echo "    DATABASE_URL='postgresql://postgres:pass@localhost:5432/rainbow' $0"
  exit 0
fi

command -v psql >/dev/null 2>&1 || {
  echo -e "${RED}psql is required but not installed.${NC}" >&2
  exit 1
}

echo -e "${YELLOW}Running database regression tests...${NC}"
for t in "${TEST_FILES[@]}"; do
  echo -e "${YELLOW}  ${t}${NC}"
  if ! psql "$DATABASE_URL" -X -q -v ON_ERROR_STOP=1 \
        -f "$REPO_ROOT/supabase/tests/$t"; then
    echo -e "${RED}✗ ${t} FAILED.${NC}" >&2
    exit 1
  fi
done
echo -e "${GREEN}✓ Database tests passed.${NC}"
