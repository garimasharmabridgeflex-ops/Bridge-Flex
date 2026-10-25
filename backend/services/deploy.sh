#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"/../../..

log() { printf '[deploy.sh] %s\n' "$*"; }
run() { log "Running: $*"; "$@"; }

run firebase deploy --only hosting --token "$FIREBASE_TOKEN"
run firebase deploy --only functions --token "$FIREBASE_TOKEN"
run firebase deploy --only firestore:rules,firestore:indexes --token "$FIREBASE_TOKEN"

log 'Deploy complete. Run /tmp/check_deploy.sh to hold the script open, then the user can verify live.'
