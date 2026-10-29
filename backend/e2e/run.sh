#!/usr/bin/env bash
# One-command admin-console E2E: `make e2e` from backend/ (or run directly).
#
# Starts whatever is missing, reuses whatever is already running:
#   1. Firebase emulators (Auth/Firestore/Storage/PubSub) — project pinned to
#      demo-bridgeflex, the same id the seed and the Go functions use
#      (without --project, firebase-tools pins the emulators to whatever
#      project it last resolved and every sign-in returns EMAIL_NOT_FOUND)
#   2. seeded data — only when admin@example.com can't sign in yet (a fresh
#      emulator), so re-runs never fight the seeder
#   3. the functions-core endpoints the console calls — ports looked up from
#      services/core/run-local.sh, the same file proxy.mjs reads, so the two
#      can never drift
#   4. the local proxy that serves backend/public/admin on :5050
#
# Runs the Chrome suite last and exits with its exit code; only processes
# this script started are torn down on the way out (an emulator stack you
# started yourself is left alone).
set -uo pipefail
cd "$(dirname "$0")/.." # backend/

# Absolute: the build below runs inside a subshell in services/core, so a
# relative path there would resolve to services/.e2e-logs instead.
RUNTIME="$PWD/.e2e-logs"
mkdir -p "$RUNTIME/func"

export FIRESTORE_EMULATOR_HOST=127.0.0.1:8180
export FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099
export FIREBASE_STORAGE_EMULATOR_HOST=127.0.0.1:9199
export PUBSUB_EMULATOR_HOST=127.0.0.1:8085
export GCLOUD_PROJECT=demo-bridgeflex
export GOOGLE_CLOUD_PROJECT=demo-bridgeflex
export FUNCTIONS_EMULATOR=true

started=()
# Kill a pid and every descendant, children first. A plain kill (or even a
# process-group kill) leaks: firebase-tools starts some java emulators in
# their own process groups, so they survive their wrapper's death.
kill_tree() {
  local pid=$1 child
  for child in $(pgrep -P "$pid" 2>/dev/null); do kill_tree "$child"; done
  kill -TERM "$pid" 2>/dev/null || true
}
cleanup() {
  for pid in "${started[@]:-}"; do kill_tree "$pid"; done
}
trap cleanup EXIT

listening() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null && exec 3<&- 3>&-; }

# ── 1. emulators ────────────────────────────────────────────────────────────
if ! listening 8180 || ! listening 9099; then
  echo "==> starting Firebase emulators (auth/firestore/storage/pubsub)…"
  setsid firebase emulators:start --project demo-bridgeflex --only auth,firestore,storage,pubsub \
    > "$RUNTIME/emulators.log" 2>&1 &
  started+=($!)
  for _ in $(seq 1 90); do listening 8180 && listening 9099 && break; sleep 1; done
  if ! listening 8180 || ! listening 9099; then
    echo "emulators did not come up; see $RUNTIME/emulators.log" >&2
    exit 1
  fi
fi

# ── 2. seed (fresh emulators only) ──────────────────────────────────────────
KEY=$(grep -o 'apiKey: "[^"]*"' public/admin/index.html | head -1 | cut -d'"' -f2)
signed_in=$(curl -sf -m 5 -X POST \
  "http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$KEY" \
  -H 'Content-Type: application/json' \
  -d '{"email":"admin@example.com","password":"password123","returnSecureToken":true}' || true)
if ! grep -q idToken <<<"$signed_in"; then
  echo "==> seeding emulator data…"
  if ! npm run seed; then
    echo "seed failed; see output above" >&2
    exit 1
  fi
fi

# ── 3. functions-core endpoints the console calls ───────────────────────────
ENDPOINTS='
GetPlatformStats ListAllUsers ListPendingDocuments ListRatings
UpdateCompanyInfo ListRateCards UpsertRateCard UpsertPlan
GetFeatureFlags UpdateFeatureFlags ListAuditLogs
AdminSavePolicyDraft AdminApprovePolicy AdminPublishPolicy ListPolicies
CreateDiscountCode ListDiscountCodes SetDiscountCodeActive SendAdminNotification
GetCompanySettings GetAdminPlans
GetCancellationPolicy UpdateCancellationPolicy
GetInvoiceDocument ListInvoices
'

echo "==> building functions-core…"
if ! (cd services/core && go build -o "$RUNTIME/bf-core" ./cmd); then
  echo "go build failed" >&2
  exit 1
fi

ports=()
for name in $ENDPOINTS; do
  port=$(grep -o "\[$name\]=[0-9]*" services/core/run-local.sh | grep -o '[0-9]*$')
  if [ -z "$port" ]; then
    echo "endpoint $name has no port in services/core/run-local.sh" >&2
    exit 1
  fi
  ports+=("$port")
  listening "$port" && continue # already running (e.g. your own dev stack)
  env FUNCTION_TARGET="$name" PORT="$port" "$RUNTIME/bf-core" \
    > "$RUNTIME/func/$name.log" 2>&1 &
  started+=($!)
done

for _ in $(seq 1 30); do
  all_up=1
  for port in "${ports[@]}"; do listening "$port" || { all_up=0; break; }; done
  [ "$all_up" = 1 ] && break
  sleep 1
done
if [ "${all_up:-0}" != 1 ]; then
  echo "some function endpoints did not start; logs in $RUNTIME/func/" >&2
  exit 1
fi

# ── 4. local proxy (serves the console, forwards /<EndpointName>) ───────────
if ! listening 5050; then
  echo "==> starting local proxy on :5050…"
  (cd e2e && exec node proxy.mjs) > "$RUNTIME/proxy.log" 2>&1 &
  started+=($!)
  for _ in $(seq 1 15); do listening 5050 && break; sleep 1; done
  if ! listening 5050; then
    echo "proxy did not start; see $RUNTIME/proxy.log" >&2
    exit 1
  fi
fi

# ── 5. node deps, then the browser run ──────────────────────────────────────
if [ ! -d e2e/node_modules ]; then
  echo "==> installing e2e node modules…"
  (cd e2e && npm install --no-audit --no-fund) || exit 1
fi

echo "==> running the browser E2E…"
(cd e2e && exec node settings-e2e.mjs)
rc=$?
exit $rc
