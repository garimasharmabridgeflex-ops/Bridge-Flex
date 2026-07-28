.DEFAULT_GOAL := help
.PHONY: help install dev dev-persist dev-with-triggers emulators seed rules-test test build prod clean

PROJECT_ID ?= demo-bridgeflex
REGION     ?= europe-west2
GO_RUNTIME ?= go123

# Points the Admin SDK / go test at the local emulators instead of real GCP
# credentials — see shared/fbapp. Needed by any target that talks to
# Firestore/Auth/Pub-Sub directly (seed, test) rather than through a running
# `firebase emulators:exec` wrapper (rules-test already gets these for free).
EMULATOR_ENV = FIRESTORE_EMULATOR_HOST=127.0.0.1:8180 \
	FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
	FIREBASE_STORAGE_EMULATOR_HOST=127.0.0.1:9199 \
	PUBSUB_EMULATOR_HOST=127.0.0.1:8085 \
	GCLOUD_PROJECT=demo-bridgeflex

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

install: ## Install npm deps (firebase-tools + rules-tests suite)
	npm install
	npm --prefix rules-tests install

dev: ## Run emulators + all Cloud Functions locally (Ctrl+C stops everything)
	@./scripts/dev.sh

dev-persist: ## Same as dev, but import/export emulator data via ./seed-data
	@PERSIST=1 ./scripts/dev.sh

dev-with-triggers: ## Same as dev, but also runs devharness so profile syncs/rating aggregates/shift matching/chat+notification creation actually cascade locally
	@WITH_TRIGGERS=1 ./scripts/dev.sh

emulators: ## Run just the Firebase Emulator Suite (no functions)
	npm run emulators:start

seed: ## Seed sample data into the running emulators
	$(EMULATOR_ENV) npm run seed

rules-test: ## Run Firestore/Storage Security Rules unit tests
	npm run rules:test

test: rules-test ## Run rules tests + Go unit tests (trigger handlers etc.) — needs emulators running
	cd services/core && $(EMULATOR_ENV) go test ./...
	cd services/communication && $(EMULATOR_ENV) go test ./...

build: ## go build every service, to catch compile errors early
	cd services/core && go build ./...
	cd services/payments && go build ./...
	cd services/communication && go build ./...

prod: ## Deploy rules + all 26 Cloud Functions to a real Firebase project — usage: make prod PROJECT_ID=your-real-project-id
	PROJECT_ID=$(PROJECT_ID) REGION=$(REGION) GO_RUNTIME=$(GO_RUNTIME) ./deploy.sh

clean: ## Remove emulator debug logs
	rm -f firestore-debug.log pubsub-debug.log ui-debug.log firebase-debug.log storage-debug.log
