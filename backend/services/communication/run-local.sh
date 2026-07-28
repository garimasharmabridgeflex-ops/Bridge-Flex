#!/usr/bin/env bash
# Runs every HTTP-triggered function in functions-communication as its own
# local process, each on a fixed port — see services/core/run-local.sh and
# ARCHITECTURE.md v2 §1a/§7 for why. OnShiftBooked/OnRatingReceived/
# OnShiftMatched (Pub/Sub-triggered) aren't started here — no local trigger
# dispatch story for Go; covered by unit tests only in Phase 1.
set -euo pipefail
cd "$(dirname "$0")"

declare -A FUNCS=(
  [RegisterFcmToken]=8121
  [UnregisterFcmToken]=8122
  [SendChatMessage]=8123
  [ListChatMessages]=8124
  [ListChatSessions]=8127
  [ListNotifications]=8125
  [MarkNotificationRead]=8126
)

pids=()
cleanup() {
  echo "stopping functions-communication..."
  kill "${pids[@]}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

for name in "${!FUNCS[@]}"; do
  port="${FUNCS[$name]}"
  echo "functions-communication: $name -> :$port"
  FUNCTION_TARGET="$name" PORT="$port" go run ./cmd &
  pids+=("$!")
done

echo "all functions-communication HTTP endpoints running — see ports above. Ctrl+C to stop."
wait
