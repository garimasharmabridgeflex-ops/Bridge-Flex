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
		conf := &firebase.Config{ProjectID: projectID()}
		app, initErr = firebase.NewApp(ctx, conf)
	})
	return app, initErr
}

func projectID() string {
	if p := os.Getenv("GCLOUD_PROJECT"); p != "" {
		return p
	}
	return "demo-bridgeflex"
}
