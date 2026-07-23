package function

import (
	"context"
	"fmt"
	"net/http"

	"cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"kvision.internal/shared/httpjson"
)

var (
	errProfileNotFound = fmt.Errorf("profile not found")
	errWrongRole       = fmt.Errorf("wrong role")
)

// requireRole reads the caller's own profile server-side (never trusting a
// client-supplied role) and confirms it matches want. Used by handlers that
// are role-gated, e.g. only a nursery may createShift, only staff may
// acceptShift (§4).
func requireRole(ctx context.Context, db *firestore.Client, uid string, want Role) error {
	snap, err := db.Collection("profiles").Doc(uid).Get(ctx)
	if status.Code(err) == codes.NotFound {
		return errProfileNotFound
	}
	if err != nil {
		return err
	}
	var p Profile
	if err := snap.DataTo(&p); err != nil {
		return err
	}
	if p.Role != want {
		return errWrongRole
	}
	return nil
}

func writeRoleError(w http.ResponseWriter, err error) {
	switch err {
	case errProfileNotFound:
		httpjson.WriteError(w, http.StatusNotFound, "PROFILE_NOT_FOUND", "Profile not found")
	case errWrongRole:
		httpjson.WriteError(w, http.StatusForbidden, "WRONG_ROLE", "Your account role cannot perform this action")
	default:
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
	}
}
