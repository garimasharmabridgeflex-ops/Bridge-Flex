package function

import (
	"crypto/sha256"
	"encoding/hex"
	"net/http"
	"time"

	"github.com/GoogleCloudPlatform/functions-framework-go/functions"

	"kvision.internal/shared/auth"
	"kvision.internal/shared/httpjson"
)

func init() {
	functions.HTTP("RegisterFcmToken", authed(registerFcmToken))
	functions.HTTP("UnregisterFcmToken", authed(unregisterFcmToken))
}

type fcmTokenRequest struct {
	Token    string `json:"token"`
	Platform string `json:"platform,omitempty"`
}

// tokenDocID hashes the raw FCM token into a stable, Firestore-doc-ID-safe
// string. Re-registering the same token on app relaunch is then a plain
// idempotent upsert keyed by this hash — see ARCHITECTURE.md v2 §6.
func tokenDocID(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

// registerFcmToken — POST /registerFcmToken. profiles/{uid}/fcmTokens is a
// subcollection (not an array field) specifically so concurrent
// registration/removal across multiple devices never races on a
// read-modify-write of the parent profile doc (§2).
func registerFcmToken(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	uid := auth.UID(ctx)

	var req fcmTokenRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	if req.Token == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "token is required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}
	ref := db.Collection("profiles").Doc(uid).Collection("fcmTokens").Doc(tokenDocID(req.Token))
	_, err = ref.Set(ctx, map[string]any{
		"token":      req.Token,
		"platform":   req.Platform,
		"lastSeenAt": time.Now(),
	})
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}
	httpjson.WriteJSON(w, http.StatusOK, map[string]string{"status": "registered"})
}

// unregisterFcmToken — POST /unregisterFcmToken. Called on logout, and
// internally by sendPushToUser when FCM reports a token as no longer
// registered (§6).
func unregisterFcmToken(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	uid := auth.UID(ctx)

	var req fcmTokenRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	if req.Token == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "token is required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}
	_, err = db.Collection("profiles").Doc(uid).Collection("fcmTokens").Doc(tokenDocID(req.Token)).Delete(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}
	httpjson.WriteJSON(w, http.StatusOK, map[string]string{"status": "unregistered"})
}
