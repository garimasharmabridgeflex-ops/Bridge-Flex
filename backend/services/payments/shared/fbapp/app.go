// Package fbapp provides a single process-wide Firebase Admin App shared by
// every handler in a service. When FIRESTORE_EMULATOR_HOST /
// FIREBASE_AUTH_EMULATOR_HOST / FIREBASE_STORAGE_EMULATOR_HOST are set, the
// underlying Admin SDK clients auto-detect them — that's the documented
// emulator-discovery mechanism, so this constructor needs no emulator-specific
// branching. See ARCHITECTURE.md v2 §1a/§7.
package fbapp

import (
	"context"
	"os"
	"sync"

	firebase "firebase.google.com/go/v4"
)

var (
	once    sync.Once
	app     *firebase.App
	initErr error
)

// New returns the process-wide Firebase Admin App, initializing it on first call.
func New(ctx context.Context) (*firebase.App, error) {
	once.Do(func() {
		conf := &firebase.Config{}
		if p := localDevProjectID(); p != "" {
			conf.ProjectID = p
		}
		app, initErr = firebase.NewApp(ctx, conf)
	})
	return app, initErr
}

// localDevProjectID returns "demo-bridgeflex" only when we're actually
// pointed at local emulators, and empty string otherwise.
//
// Cloud Functions (2nd gen)/Cloud Run do NOT automatically inject any
// project-id env var (GOOGLE_CLOUD_PROJECT, GCLOUD_PROJECT, GCP_PROJECT are
// all gen1/App-Engine-era conventions gen2 doesn't set) — a prior version
// of this function guessed at those names and fell through to a hardcoded
// "demo-bridgeflex" default when none were set, which happened on every
// single production deploy. That silently initialized the Admin App against
// the wrong project, so VerifyIDToken rejected every real user's token
// (aud mismatch) even though the function itself deployed and ran fine.
//
// The fix: only force a project ID when local dev's emulator env vars
// (set together with GCLOUD_PROJECT by backend/Makefile's EMULATOR_ENV) are
// actually present. Otherwise leave firebase.Config.ProjectID unset so the
// Admin SDK auto-detects the real project from Application Default
// Credentials / the GCP metadata server — the mechanism that actually
// works unconditionally in any real Cloud Functions/Cloud Run environment.
func localDevProjectID() string {
	if os.Getenv("FIRESTORE_EMULATOR_HOST") == "" && os.Getenv("FIREBASE_AUTH_EMULATOR_HOST") == "" {
		return ""
	}
	if p := os.Getenv("GCLOUD_PROJECT"); p != "" {
		return p
	}
	return "demo-bridgeflex"
}
