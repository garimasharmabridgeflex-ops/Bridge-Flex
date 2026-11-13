#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

: "${PROJECT_ID:=kvision-503115}"
: "${REGION:=europe-west2}"
: "${GO_RUNTIME:=go125}"

MISSING=(
  SaveEmailTemplate
  DeleteEmailTemplate
  SendAdminEmail
  MarkPayrollPeriodsPaid
)

for name in "${MISSING[@]}"; do
  echo "==> Deploying $name..."
  /home/brainiac/google-cloud-sdk/bin/gcloud functions deploy "$name" \
    --gen2 --runtime="$GO_RUNTIME" --region="$REGION" --project="$PROJECT_ID" \
    --source=. --entry-point="$name" \
    --trigger-http --allow-unauthenticated --quiet
done

echo "All missing functions deployed successfully."
