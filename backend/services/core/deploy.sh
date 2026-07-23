#!/usr/bin/env bash
# Deploys every functions-core Cloud Function (2nd gen) via gcloud — Go isn't
# supported by `firebase deploy --only functions` (Node/Python only), so
# each function is deployed directly. See ARCHITECTURE.md v2 §1a and
# backend/README.md "Going live".
#
# Requires: gcloud authenticated (`gcloud auth login`), PROJECT_ID set to a
# real, Blaze-upgraded Firebase project (never demo-bridgeflex — that's
# emulator-only). --allow-unauthenticated on the HTTP functions is
# intentional: that flag only controls Cloud Functions' own IAM invoker
# check, which is a separate layer from the RequireAuth Firebase-ID-token
# check every handler already does internally (§1a) — the function itself
# still rejects unauthenticated callers, just with its own 401 JSON error
# instead of Cloud Functions' generic 403.
set -euo pipefail
cd "$(dirname "$0")"

: "${PROJECT_ID:?Set PROJECT_ID to your real Firebase project id, e.g. PROJECT_ID=my-prod-project ./deploy.sh}"
: "${REGION:=europe-west2}"
# Verify the current valid identifier with `gcloud functions runtimes list
# --project="$PROJECT_ID"` before your first deploy — Cloud Functions'
# supported Go runtime versions change over time.
: "${GO_RUNTIME:=go123}"

deploy_http() {
  local name="$1"
  echo "==> functions-core: deploying $name (HTTP)"
  gcloud functions deploy "$name" \
    --gen2 --runtime="$GO_RUNTIME" --region="$REGION" --project="$PROJECT_ID" \
    --source=. --entry-point="$name" \
    --trigger-http --allow-unauthenticated --quiet
}

deploy_firestore_trigger() {
  local name="$1" event_type="$2" path_pattern="$3"
  echo "==> functions-core: deploying $name (Firestore $event_type on $path_pattern)"
  gcloud functions deploy "$name" \
    --gen2 --runtime="$GO_RUNTIME" --region="$REGION" --project="$PROJECT_ID" \
    --source=. --entry-point="$name" \
    --trigger-event-filters="type=$event_type" \
    --trigger-event-filters="database=(default)" \
    --trigger-event-filters-path-pattern="document=$path_pattern" \
    --quiet
}

deploy_auth_trigger() {
  local name="$1"
  echo "==> functions-core: deploying $name (Auth: user created)"
  gcloud functions deploy "$name" \
    --gen2 --runtime="$GO_RUNTIME" --region="$REGION" --project="$PROJECT_ID" \
    --source=. --entry-point="$name" \
    --trigger-event-filters="type=google.firebase.auth.user.v1.created" \
    --quiet
}

# HTTP endpoints — ports in run-local.sh, same set of functions.
deploy_http UpdateProfile
deploy_http GetProfile
deploy_http GetPublicProfile
deploy_http CreateShift
deploy_http UpdateShift
deploy_http ListOpenShifts
deploy_http ListMyShifts
deploy_http GetShift
deploy_http AcceptShift
deploy_http CancelShift
deploy_http MarkNoShow
deploy_http CreateRating
deploy_http CreateDocument
deploy_http ReviewDocument
deploy_http GetDocumentStatus
deploy_http ListMyDocuments
deploy_http ListPendingDocuments
deploy_http GetPlatformStats
deploy_http ListAllUsers
deploy_http GetUserDetail
deploy_http SetUserSuspended
deploy_http SetVerificationBadge

# Eventarc triggers — same 4 functions covered by triggers_test.go.
deploy_auth_trigger InitProfileOnSignUp
deploy_firestore_trigger SyncProfilePublic google.cloud.firestore.document.v1.written "profiles/{uid}"
deploy_firestore_trigger RecomputeRating google.cloud.firestore.document.v1.created "ratings/{ratingId}"
deploy_firestore_trigger MatchNewShift google.cloud.firestore.document.v1.created "shifts/{shiftId}"

echo "functions-core: all 25 functions deployed."
