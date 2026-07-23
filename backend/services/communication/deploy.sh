#!/usr/bin/env bash
# Deploys every functions-communication Cloud Function (2nd gen) via gcloud.
# See services/core/deploy.sh for the flag rationale (same pattern).
set -euo pipefail
cd "$(dirname "$0")"

: "${PROJECT_ID:?Set PROJECT_ID to your real Firebase project id, e.g. PROJECT_ID=my-prod-project ./deploy.sh}"
: "${REGION:=europe-west2}"
: "${GO_RUNTIME:=go125}"

deploy_http() {
  local name="$1"
  echo "==> functions-communication: deploying $name (HTTP)"
  gcloud functions deploy "$name" \
    --gen2 --runtime="$GO_RUNTIME" --region="$REGION" --project="$PROJECT_ID" \
    --source=. --entry-point="$name" \
    --trigger-http --allow-unauthenticated --quiet
}

deploy_pubsub_trigger() {
  local name="$1" topic="$2"
  echo "==> functions-communication: deploying $name (Pub/Sub topic: $topic)"
  gcloud functions deploy "$name" \
    --gen2 --runtime="$GO_RUNTIME" --region="$REGION" --project="$PROJECT_ID" \
    --source=. --entry-point="$name" \
    --trigger-topic="$topic" --quiet
}

# HTTP endpoints — ports in run-local.sh, same 7 functions.
deploy_http RegisterFcmToken
deploy_http UnregisterFcmToken
deploy_http SendChatMessage
deploy_http ListChatMessages
deploy_http ListChatSessions
deploy_http ListNotifications
deploy_http MarkNotificationRead

# Pub/Sub triggers — same 3 functions covered by triggers_test.go. Topics
# are auto-created by acceptShift/recomputeRating/matchNewShift's publish()
# helper in core if they don't already exist (see core/function/context.go
# ensureTopic) — no manual `gcloud pubsub topics create` needed first.
deploy_pubsub_trigger OnShiftBooked shift-booked
deploy_pubsub_trigger OnRatingReceived rating-received
deploy_pubsub_trigger OnShiftMatched shift-matched

echo "functions-communication: all 10 functions deployed."
