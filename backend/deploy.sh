#!/usr/bin/env bash
# Deploys Firestore/Storage Security Rules and every Cloud Function (2nd
# gen) across all three services — 50 functions total (35 core, incl. the
# permanently-undeployable InitProfileOnSignUp which fails with `|| true`,
# 1 payments, 12 communication). One-time GCP/Firebase project provisioning
# this assumes — real project on Blaze, `gcloud auth login` already run,
# plus everything in PRODUCTION_SETUP.md (IAM roles, region, Auth/Storage
# init) — is NOT covered by this script; see PRODUCTION_SETUP.md.
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

echo "=== Deploying functions-core (35 functions) ==="
services/core/deploy.sh

echo "=== Deploying functions-payments (1 function) ==="
services/payments/deploy.sh

echo "=== Deploying functions-communication (14 functions) ==="
services/communication/deploy.sh

echo
echo "=== Done. 50 functions + rules deployed to $PROJECT_ID ($REGION). ==="
echo "Fetch a function's URL with:"
echo "  gcloud functions describe NAME --gen2 --region=$REGION --project=$PROJECT_ID --format='value(serviceConfig.uri)'"
echo "Fill those into bruno/environments/Production.bru."
