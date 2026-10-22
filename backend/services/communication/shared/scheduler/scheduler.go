package scheduler

import (
	"context"
	"errors"
	"net/http"
	"strings"

	"google.golang.org/api/idtoken"
)

var (
	ErrMissingAuthHeader = errors.New("missing Authorization header")
	ErrInvalidOIDCToken  = errors.New("invalid OIDC token")
)

// VerifyOIDCToken verifies Google Cloud Scheduler's OIDC Bearer token.
// If expectedAudience is empty, validation checks signature and expiration.
func VerifyOIDCToken(ctx context.Context, r *http.Request, expectedAudience string) (*idtoken.Payload, error) {
	authHeader := r.Header.Get("Authorization")
	const prefix = "Bearer "
	if !strings.HasPrefix(authHeader, prefix) {
		return nil, ErrMissingAuthHeader
	}
	rawToken := strings.TrimPrefix(authHeader, prefix)

	payload, err := idtoken.Validate(ctx, rawToken, expectedAudience)
	if err != nil {
		return nil, ErrInvalidOIDCToken
	}
	return payload, nil
}
