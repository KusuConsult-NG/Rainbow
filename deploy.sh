#!/bin/bash
# ============================================================
# Operation Rainbow — Full Production Deploy
# Account: kusuconsult@gmail.com → Project: rainbow-97f1e
# ============================================================

set -e  # Exit on first error
NODE_BIN="/Users/mac/nodejs/node-v20.10.0-darwin-x64/bin"
export PATH="$NODE_BIN:$PATH"
ACCOUNT="kusuconsult@gmail.com"
PROJECT="rainbow-97f1e"

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║   OPERATION RAINBOW — PRODUCTION DEPLOY          ║"
echo "║   Account: $ACCOUNT        ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# ── Step 1: Switch to correct account ───────────────────────
echo "▶ [1/5] Switching Firebase account to $ACCOUNT..."
firebase login:use "$ACCOUNT" || true
echo "✓ Account: $(firebase login:list 2>&1 | head -1)"

# ── Step 2: Set project ──────────────────────────────────────
echo ""
echo "▶ [2/5] Selecting project $PROJECT..."
firebase use "$PROJECT" --account "$ACCOUNT"

# ── Step 3: Deploy Firestore rules & Functions ───────────────────────────
echo ""
echo "▶ [3/6] Deploying Cloud Functions..."
firebase deploy --only functions --account "$ACCOUNT"
echo "✓ Functions deployed"

echo ""
echo "▶ [4/6] Deploying Firestore security rules..."
firebase deploy --only firestore:rules --account "$ACCOUNT"
echo "✓ Rules deployed"

# ── Step 4: Deploy Firestore indexes ─────────────────────────
echo ""
echo "▶ [4/5] Deploying Firestore composite indexes..."
firebase deploy --only firestore:indexes --account "$ACCOUNT"
echo "✓ Indexes deployed"

# ── Step 5: Build + Deploy HQ Dashboard to Hosting ──────────
echo ""
echo "▶ [5/5] Building HQ Dashboard..."
npm --prefix hq-dashboard-next run build
echo "✓ Build complete ($(du -sh hq-dashboard-next/out | cut -f1))"

echo ""
echo "▶ Deploying HQ Dashboard to Firebase Hosting..."
firebase deploy --only hosting --account "$ACCOUNT"

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  ✓ DEPLOY COMPLETE                               ║"
echo "║                                                  ║"
echo "║  Dashboard: https://rainbow-97f1e.web.app        ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "To enforce App Check, please visit the Firebase Console:"
echo "https://console.firebase.google.com/u/2/project/rainbow-97f1e/appcheck"
