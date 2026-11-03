package function

import (
	"context"
	"net/http"
	"sync"

	"cloud.google.com/go/firestore"
	firebase "firebase.google.com/go/v4"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"kvision.internal/shared/auth"
	"kvision.internal/shared/fbapp"
	"kvision.internal/shared/httpjson"
)

var (
	appOnce sync.Once
	app     *firebase.App
	appErr  error

	fsOnce   sync.Once
	fsClient *firestore.Client
	fsErr    error
)

// adminApp returns the process-wide Firebase Admin App (see shared/fbapp for
// the project-resolution rules; this mirrors core's helper).
func adminApp(ctx context.Context) (*firebase.App, error) {
	appOnce.Do(func() { app, appErr = fbapp.New(ctx) })
	return app, appErr
}

// fsDB returns the process-wide Firestore client.
func fsDB(ctx context.Context) (*firestore.Client, error) {
	fsOnce.Do(func() {
		a, err := adminApp(ctx)
		if err != nil {
			fsErr = err
			return
		}
		fsClient, fsErr = a.Firestore(ctx)
	})
	return fsClient, fsErr
}

// authed wraps a handler in the shared bearer-token check.
func authed(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		a, err := adminApp(r.Context())
		if err != nil {
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "auth app init failed")
			return
		}
		auth.RequireAuth(a, next)(w, r)
	}
}

// requireNursery rejects callers whose profile role is not "nursery".
func requireNursery(ctx context.Context, db *firestore.Client, uid string) error {
	snap, err := db.Collection("profiles").Doc(uid).Get(ctx)
	if status.Code(err) == codes.NotFound {
		return errNotNursery
	}
	if err != nil {
		return err
	}
	role, _ := snap.Data()["role"].(string)
	if role != "nursery" {
		return errNotNursery
	}
	return nil
}
