#!/usr/bin/env bash
# Starts the Firebase Emulator Suite plus every service's local HTTP
# function processes (functions-core, functions-payments,
# functions-communication) together in one terminal. Ctrl+C tears down
# everything, emulators included. Invoked via `make dev` / `make dev-persist`
# — see Makefile.
#
# Eventarc/Pub-Sub-triggered functions (syncProfilePublic, recomputeRating,
# matchNewShift, onShiftBooked, onRatingReceived, onShiftMatched,
# onShiftCancelled) aren't started here by default — there's still no local
# Eventarc dispatch path for Go (README.md's "trigger-testing gap"). Set
# WITH_TRIGGERS=1 (or run `make dev-with-triggers`) to also start
# services/core/devharness and services/communication/devharness, which
# watch the Firestore/Pub-Sub emulators directly and invoke the real
# handler functions — see the doc comment on each devharness/main.go for how.
set -uo pipefail
cd "$(dirname "$0")/.."

export FIRESTORE_EMULATOR_HOST=127.0.0.1:8180
export FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099
export FIREBASE_STORAGE_EMULATOR_HOST=127.0.0.1:9199
export PUBSUB_EMULATOR_HOST=127.0.0.1:8085
export GCLOUD_PROJECT=demo-bridgeflex

emulator_args=()
if [ "${PERSIST:-0}" = "1" ]; then
  echo "==> persisting emulator data to ./seed-data on exit"
  emulator_args=(--import=./seed-data --export-on-exit=./seed-data)
fi

pids=()
cleanup() {
  echo
  echo "==> stopping dev environment..."
  for pid in "${pids[@]}"; do
    kill -INT "$pid" 2>/dev/null || true
  done
  wait 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "==> starting Firebase emulators (Auth/Firestore/Pub-Sub/Storage/UI)..."
npx firebase emulators:start "${emulator_args[@]}" &
pids+=("$!")

echo "==> waiting for the Firestore emulator on :8180..."
up=0
for _ in $(seq 1 60); do
  if (exec 3<>/dev/tcp/127.0.0.1/8180) 2>/dev/null; then
    exec 3<&- 3>&-
    up=1
    break
  fi
  sleep 1
done
if [ "$up" -ne 1 ]; then
  echo "Firestore emulator did not come up in time." >&2
  exit 1
fi
echo "==> emulators are up (UI at http://127.0.0.1:4000)."

echo "==> starting functions-core (13 HTTP endpoints)..."
services/core/run-local.sh &
pids+=("$!")

echo "==> starting functions-payments (CreatePayout stub, :8093)..."
(cd services/payments && FUNCTION_TARGET=CreatePayout PORT=8093 go run ./cmd) &
pids+=("$!")

echo "==> starting functions-communication (7 HTTP endpoints)..."
services/communication/run-local.sh &
pids+=("$!")

if [ "${WITH_TRIGGERS:-0}" = "1" ]; then
  echo "==> starting devharness (local Eventarc/Pub-Sub trigger dispatch)..."
  (cd services/core/devharness && go run .) &
  pids+=("$!")
  (cd services/communication/devharness && go run .) &
  pids+=("$!")
fi

echo
echo "==> dev environment up — emulators + all HTTP functions running. Ctrl+C to stop everything."
wait
