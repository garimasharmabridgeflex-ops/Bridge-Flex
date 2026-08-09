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

# HTTP endpoints — ports in run-local.sh, same 8 functions.
deploy_http RegisterFcmToken
deploy_http UnregisterFcmToken
deploy_http SendChatMessage
deploy_http ListChatMessages
deploy_http ListChatSessions
deploy_http ListNotifications
deploy_http MarkNotificationRead
deploy_http MarkAllNotificationsRead

# Pub/Sub triggers — same 4 functions covered by triggers_test.go (plus
# OnShiftCancelled, added after that test file's initial 3).
#
# Topics must EXIST before these deploys: a 2nd-gen --trigger-topic deploy
# fails validation with "Resource not found" rather than creating the topic.
# core's ensureTopic() only auto-creates against the Pub/Sub emulator during
# local development; it does not run before a production deploy. Create any
# new topic first:
#
#   gcloud pubsub topics create <topic> --project="$PROJECT_ID"
#
# (Publishing to a missing topic is logged and swallowed by design, so the
# symptom is silently absent notifications rather than failed bookings.)
deploy_pubsub_trigger OnShiftBooked shift-booked
deploy_pubsub_trigger OnShiftApplied shift-applied
deploy_pubsub_trigger OnShiftApplicationDecided shift-application-decided
deploy_pubsub_trigger OnRatingReceived rating-received
deploy_pubsub_trigger OnShiftMatched shift-matched
deploy_pubsub_trigger OnShiftCancelled shift-cancelled

echo "functions-communication: all 12 functions deployed."
