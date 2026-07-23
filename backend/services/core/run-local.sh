#!/usr/bin/env bash
# Runs every HTTP-triggered function in functions-core as its own local
# process, each on a fixed port — the operational cost of Go under Cloud
# Functions noted in ARCHITECTURE.md v2 §1a/§7: N processes instead of one
# unified Functions emulator. Point FIRESTORE_EMULATOR_HOST /
# FIREBASE_AUTH_EMULATOR_HOST at the running emulators before invoking this
# (see backend/README.md). Eventarc-triggered functions (InitProfileOnSignUp,
# SyncProfilePublic, MatchNewShift, RecomputeRating) aren't started here —
# they have no local trigger dispatch story; see §7 for the unit-test-only
# approach used for those instead.
set -euo pipefail
cd "$(dirname "$0")"

declare -A FUNCS=(
  [UpdateProfile]=8101
  [GetProfile]=8102
  [GetPublicProfile]=8103
  [CreateShift]=8104
  [UpdateShift]=8105
  [ListOpenShifts]=8106
  [ListMyShifts]=8113
  [GetShift]=8107
  [AcceptShift]=8108
  [CancelShift]=8109
  [MarkNoShow]=8116
  [CreateRating]=8110
  [CreateDocument]=8111
  [ReviewDocument]=8112
  [GetDocumentStatus]=8114
  [ListMyDocuments]=8115
  [ListPendingDocuments]=8117
  # functions-communication's run-local.sh independently owns 8121-8128 —
  # jumping to 8140+ here avoids any port collision between the two
  # services' independently-numbered local process maps.
  [GetPlatformStats]=8140
  [ListAllUsers]=8141
  [GetUserDetail]=8142
  [SetUserSuspended]=8143
  [SetVerificationBadge]=8144
)

pids=()
cleanup() {
  echo "stopping functions-core..."
  kill "${pids[@]}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

for name in "${!FUNCS[@]}"; do
  port="${FUNCS[$name]}"
  echo "functions-core: $name -> :$port"
  FUNCTION_TARGET="$name" PORT="$port" go run ./cmd &
  pids+=("$!")
done

echo "all functions-core HTTP endpoints running — see ports above. Ctrl+C to stop."
wait
