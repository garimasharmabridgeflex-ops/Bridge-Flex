// Package auth implements RequireAuth, the single shared authentication check
// reused by every HTTP handler across all three services (no `onCall` exists
// under Go — see ARCHITECTURE.md v2 §1a). It verifies the caller's Firebase ID
// token and attaches the decoded uid to the request context.
package auth

import (
	"context"
	"net/http"
	"strings"

	firebase "firebase.google.com/go/v4"

	"bridgeflex/shared/httpjson"
)

type contextKey string

const (
	uidContextKey    contextKey = "bridgeflex_uid"
	claimsContextKey contextKey = "bridgeflex_claims"
)

// RequireAuth wraps next, rejecting the request with 401/NOT_AUTHENTICATED
// unless the Authorization header carries a valid Firebase ID token. On
// success it attaches the decoded uid to the request context for next (and
// UID) to read.
func RequireAuth(app *firebase.App, next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		token := bearerToken(r)
		if token == "" {
			httpjson.WriteError(w, http.StatusUnauthorized, "NOT_AUTHENTICATED", "Missing or malformed Authorization header")
			return
		}

		client, err := app.Auth(r.Context())
		if err != nil {
			httpjson.WriteError(w, http.StatusInternalServerError, "AUTH_CLIENT_ERROR", "Could not initialize auth client")
			return
		}

		decoded, err := client.VerifyIDToken(r.Context(), token)
		if err != nil {
			httpjson.WriteError(w, http.StatusUnauthorized, "NOT_AUTHENTICATED", "Invalid or expired ID token")
			return
		}

		ctx := context.WithValue(r.Context(), uidContextKey, decoded.UID)
		ctx = context.WithValue(ctx, claimsContextKey, decoded.Claims)
		next(w, r.WithContext(ctx))
	}
}

func bearerToken(r *http.Request) string {
	const prefix = "Bearer "
	h := r.Header.Get("Authorization")
	if !strings.HasPrefix(h, prefix) {
		return ""
	}
	return strings.TrimPrefix(h, prefix)
}

// UID reads the authenticated caller's uid from a request context previously
// populated by RequireAuth. Callers must only be reachable through RequireAuth
// -wrapped routes; calling this on a bare context is a wiring bug, not a
// runtime case, so it panics rather than returning a zero value that could
// silently masquerade as a real (empty) uid.
func UID(ctx context.Context) string {
	uid, ok := ctx.Value(uidContextKey).(string)
	if !ok {
		panic("auth.UID called on a request context not wrapped by RequireAuth")
	}
	return uid
}

// CustomClaim reads a single custom claim (set on the Firebase user out of
// band, e.g. via the Admin SDK) from a request context previously populated
// by RequireAuth. Returns nil if the claim isn't present.
func CustomClaim(ctx context.Context, key string) any {
	claims, ok := ctx.Value(claimsContextKey).(map[string]any)
	if !ok {
		return nil
	}
	return claims[key]
}
