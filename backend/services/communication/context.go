package function

import (
	"context"
	"net/http"
	"sync"

	"cloud.google.com/go/firestore"
	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"

	"kvision.internal/shared/auth"
	"kvision.internal/shared/fbapp"
	"kvision.internal/shared/httpjson"
)

var (
	fsOnce   sync.Once
	fsClient *firestore.Client
	fsErr    error

	msgOnce   sync.Once
	msgClient *messaging.Client
	msgErr    error
)

func adminApp(ctx context.Context) (*firebase.App, error) {
	return fbapp.New(ctx)
}

func fsDB(ctx context.Context) (*firestore.Client, error) {
	fsOnce.Do(func() {
		app, err := fbapp.New(ctx)
		if err != nil {
			fsErr = err
			return
		}
		fsClient, fsErr = app.Firestore(ctx)
	})
	return fsClient, fsErr
}

func messagingClient(ctx context.Context) (*messaging.Client, error) {
	msgOnce.Do(func() {
		app, err := fbapp.New(ctx)
		if err != nil {
			msgErr = err
			return
		}
		msgClient, msgErr = app.Messaging(ctx)
	})
	return msgClient, msgErr
}

// authed wraps an HTTP handler with the shared RequireAuth middleware — see
// ARCHITECTURE.md v2 §1a. Same pattern as functions-core; duplicated here
// (rather than shared) because it's three lines and pulls in adminApp, which
// is itself intentionally per-service.
func authed(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		app, err := adminApp(r.Context())
		if err != nil {
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "auth app init failed")
			return
		}
		auth.RequireAuth(app, next)(w, r)
	}
}
