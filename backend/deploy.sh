#!/usr/bin/env bash
# Deploys Firestore/Storage Security Rules and every Cloud Function (2nd
# gen) across all three services — 26 functions total. One-time setup this
# assumes (see README.md "Going live"): a real Firebase project on the
# Blaze plan, and `gcloud auth login` already run.
#
# Usage: PROJECT_ID=your-real-project-id ./deploy.sh
# Optional: REGION=europe-west2 (default), GO_RUNTIME=go123 (default —
# verify with `gcloud functions runtimes list` first if this is stale).
set -euo pipefail
cd "$(dirname "$0")"

: "${PROJECT_ID:?Set PROJECT_ID to your real Firebase project id, e.g. PROJECT_ID=my-prod-project ./deploy.sh}"
export PROJECT_ID
export REGION="${REGION:-europe-west2}"
export GO_RUNTIME="${GO_RUNTIME:-go123}"

if [ "$PROJECT_ID" = "demo-bridgeflex" ]; then
  echo "PROJECT_ID is set to the emulator-only demo project — refusing to deploy." >&2
  echo "Set it to your real, Blaze-upgraded Firebase project id instead." >&2
  exit 1
fi

echo "=== Deploying Firestore + Storage Security Rules and indexes to $PROJECT_ID ==="
firebase deploy --only firestore:rules,firestore:indexes,storage --project "$PROJECT_ID"

echo "=== Deploying functions-core (16 functions) ==="
services/core/deploy.sh

echo "=== Deploying functions-payments (1 function) ==="
services/payments/deploy.sh

echo "=== Deploying functions-communication (9 functions) ==="
services/communication/deploy.sh

echo
echo "=== Done. 26 functions + rules deployed to $PROJECT_ID ($REGION). ==="
echo "Fetch a function's URL with:"
echo "  gcloud functions describe NAME --gen2 --region=$REGION --project=$PROJECT_ID --format='value(serviceConfig.uri)'"
echo "Fill those into bruno/environments/Production.bru."
