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

	"kvision.internal/shared/httpjson"
)

type contextKey string

const (
	uidContextKey    contextKey = "bridgeflex_uid"
	claimsContextKey contextKey = "bridgeflex_claims"
)

// RequireAuth wraps next, rejecting the request with 401/NOT_AUTHENTICATED
// unless the caller carries a valid Firebase ID token. On success it attaches
// the decoded uid to the request context for next (and UID) to read.
//
// The token is read from the Authorization header, or — only when there is no
// header — from a `token` query parameter. The query form exists for one
// case: a browser or webview opening a file URL (GetInvoiceDocument) cannot
// set request headers on a plain navigation. The token is still verified
// exactly the same way, it is short-lived, and the endpoint behind it does
// its own ownership check.
func RequireAuth(app *firebase.App, next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		token := bearerToken(r)
		if token == "" {
			token = r.URL.Query().Get("token")
		}
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

		// VerifyIDToken validates the JWT signature and expiry but does NOT
	// reject tokens issued to disabled accounts. A suspended nursery or staff
	// member's current ID token is still valid for its whole ~1hr lifetime
	// unless we explicitly check the account status here. GetUser is a single
	// get-by-UID (not a scan) so the added latency is small, and this closes
	// the hole where a suspended account can keep posting shifts and sending
	// messages until its token naturally expires.
		if u, err := client.GetUser(r.Context(), decoded.UID); err == nil && u.Disabled {
			httpjson.WriteError(w, http.StatusUnauthorized, "ACCOUNT_SUSPENDED", "This account has been suspended")
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

// AdminRole represents the role claim of an administrative user.
type AdminRole string

const (
	AdminRoleSuperAdmin AdminRole = "super_admin"
	AdminRoleVerifier   AdminRole = "verifier"
	AdminRoleFinance    AdminRole = "finance"
	AdminRoleSupport    AdminRole = "support"
	AdminRoleReadOnly   AdminRole = "read_only"
)

// GetAdminRole returns the caller's AdminRole.
// If the caller has super_admin or legacy admin: true without adminRole, it returns AdminRoleSuperAdmin.
func GetAdminRole(ctx context.Context) AdminRole {
	roleClaim := CustomClaim(ctx, "adminRole")
	if r, ok := roleClaim.(string); ok && r != "" {
		return AdminRole(r)
	}
	if CustomClaim(ctx, "admin") == true {
		return AdminRoleSuperAdmin
	}
	return ""
}

// HasRole checks whether the caller has any of the allowed admin roles.
// A caller with AdminRoleSuperAdmin always satisfies the check.
func HasRole(ctx context.Context, allowed ...AdminRole) bool {
	callerRole := GetAdminRole(ctx)
	if callerRole == "" {
		return false
	}
	if callerRole == AdminRoleSuperAdmin {
		return true
	}
	for _, a := range allowed {
		if callerRole == a {
			return true
		}
	}
	return false
}
