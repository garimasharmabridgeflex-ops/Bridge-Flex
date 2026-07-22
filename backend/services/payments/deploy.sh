#!/usr/bin/env bash
# Deploys the functions-payments stub. See TODO.md — this only proves the
# deploy path exists; there's no real Stripe logic to configure yet.
set -euo pipefail
cd "$(dirname "$0")"

: "${PROJECT_ID:?Set PROJECT_ID to your real Firebase project id, e.g. PROJECT_ID=my-prod-project ./deploy.sh}"
: "${REGION:=europe-west2}"
: "${GO_RUNTIME:=go123}"

echo "==> functions-payments: deploying CreatePayout (HTTP)"
gcloud functions deploy CreatePayout \
  --gen2 --runtime="$GO_RUNTIME" --region="$REGION" --project="$PROJECT_ID" \
  --source=. --entry-point=CreatePayout \
  --trigger-http --allow-unauthenticated --quiet

echo "functions-payments: 1 function deployed (stub — always 501, see TODO.md)."
