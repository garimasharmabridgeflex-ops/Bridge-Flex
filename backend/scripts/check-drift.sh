#!/usr/bin/env bash
# Verifies that duplicated source trees between service roots and function/
# subdirectories remain byte-identical (Rule 6.1 / Finding R1).
# Exit 0 if identical, Exit 1 if any drift is detected.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

EXCLUDES=(
  -x "*.log"
  -x "*.md"
  -x "shared"
  -x "devharness"
  -x "cmd"
  -x "run-local.sh"
  -x "deploy.sh"
  -x "go.mod"
  -x "go.sum"
  -x "function"
)

SERVICES=("core" "communication" "payments")
FAILED=0

for svc in "${SERVICES[@]}"; do
  ROOT_DIR="${BACKEND_DIR}/services/${svc}"
  FUNC_DIR="${BACKEND_DIR}/services/${svc}/function"

  if [ ! -d "${ROOT_DIR}" ] || [ ! -d "${FUNC_DIR}" ]; then
    echo "::error::Missing service directories for ${svc}"
    FAILED=1
    continue
  fi

  echo "Checking drift for services/${svc}..."
  if ! diff -r "${EXCLUDES[@]}" "${ROOT_DIR}/" "${FUNC_DIR}/"; then
    echo "::error::Source drift detected between services/${svc} and services/${svc}/function!"
    FAILED=1
  else
    echo "✓ services/${svc} is byte-identical."
  fi
done

if [ "${FAILED}" -ne 0 ]; then
  echo "FAIL: Backend duplicate source trees have drifted. Keep both root and function/ copies in sync."
  exit 1
fi

echo "PASS: All backend service source trees are synchronized."
exit 0
