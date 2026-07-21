#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Define colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}===========================================================${NC}"
echo -e "${BLUE}        OPERATION RAINBOW — UNIFIED TEST SUITE${NC}"
echo -e "${BLUE}===========================================================${NC}"

# Check for required commands
command -v flutter >/dev/null 2>&1 || { echo -e "${RED}Error: flutter is required but not installed.${NC}" >&2; exit 1; }
command -v node >/dev/null 2>&1 || { echo -e "${RED}Error: node is required but not installed.${NC}" >&2; exit 1; }
command -v npm >/dev/null 2>&1 || { echo -e "${RED}Error: npm is required but not installed.${NC}" >&2; exit 1; }

# Step 1: Run Mobile App Tests
echo -e "\n${YELLOW}[STEP 1/3] Running Flutter Mobile App Tests...${NC}"
flutter test

# Step 2: Prepare HQ Web Dashboard
echo -e "\n${YELLOW}[STEP 2/3] Preparing Next.js HQ Dashboard...${NC}"
cd hq-dashboard-next

# Kill any existing processes on port 3001
echo -e "Clearing port 3001 if in use..."
pkill -f "next dev" || true
lsof -ti :3001 | xargs kill -9 2>/dev/null || true
sleep 1

# Start Next.js dev server in the background
echo -e "Starting Next.js dev server on port 3001..."
npm run dev -- --port 3001 > /tmp/nextjs_test_dev.log 2>&1 &
NEXT_PID=$!

# Wait for server to bind and start
echo -e "Waiting for Next.js server to compile..."
SUCCESS=0
for i in {1..15}; do
  if curl -s -o /dev/null http://localhost:3001/login; then
    SUCCESS=1
    break
  fi
  sleep 1
done

if [ $SUCCESS -eq 0 ]; then
  echo -e "${RED}Error: Next.js dev server failed to start or bind to port 3001 within 15 seconds.${NC}"
  echo -e "${YELLOW}Last logs from dev server:${NC}"
  tail -n 20 /tmp/nextjs_test_dev.log
  kill -9 $NEXT_PID 2>/dev/null || true
  exit 1
fi

echo -e "${GREEN}Next.js server is online.${NC}"

# Step 3: Run Web Route Integration Tests
echo -e "\n${YELLOW}[STEP 3/3] Running Next.js Web Route Integration Tests...${NC}"
set +e
node verify-web-routes.js
TEST_RESULT=$?
set -e

# Teardown Next.js server
echo -e "\nCleaning up Next.js dev server (PID: $NEXT_PID)..."
kill -9 $NEXT_PID 2>/dev/null || true

# Report status
echo -e "\n${BLUE}===========================================================${NC}"
if [ $TEST_RESULT -eq 0 ]; then
  echo -e "${GREEN}🎉 ALL TESTS COMPLETED SUCCESSFULLY!${NC}"
  echo -e "  - Mobile App Unit & Widget Tests: PASSED"
  echo -e "  - HQ Dashboard E2E Web Route Tests: PASSED"
  echo -e "${BLUE}===========================================================${NC}"
  exit 0
else
  echo -e "${RED}❌ INTEGRATION TESTS FAILED!${NC}"
  echo -e "  - Mobile App Unit & Widget Tests: PASSED"
  echo -e "  - HQ Dashboard E2E Web Route Tests: FAILED"
  echo -e "${BLUE}===========================================================${NC}"
  exit 1
fi
