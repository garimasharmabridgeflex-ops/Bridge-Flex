package appcheck

import (
	"context"
	"log/slog"
	"net/http"

	firebase "firebase.google.com/go/v4"
)

// AppCheckMode defines whether App Check enforces or only monitors requests.
type AppCheckMode string

const (
	ModeOff     AppCheckMode = "off"
	ModeMonitor AppCheckMode = "monitor"
	ModeEnforce AppCheckMode = "enforce"
)

// VerifyToken verifies the X-Firebase-AppCheck header on the incoming request.
// In ModeMonitor, it logs token absence or invalidity but does not reject the request.
// In ModeEnforce, it returns false if the token is invalid.
func VerifyToken(ctx context.Context, app *firebase.App, r *http.Request, mode AppCheckMode) bool {
	if mode == ModeOff {
		return true
	}

	token := r.Header.Get("X-Firebase-AppCheck")
	if token == "" {
		if mode == ModeMonitor {
			slog.Warn("appcheck: missing token (monitor mode)", "path", r.URL.Path)
			return true
		}
		return false
	}

	client, err := app.AppCheck(ctx)
	if err != nil {
		slog.Error("appcheck: client unavailable", "error", err)
		return mode != ModeEnforce
	}

	_, err = client.VerifyToken(token)
	if err != nil {
		if mode == ModeMonitor {
			slog.Warn("appcheck: invalid token (monitor mode)", "path", r.URL.Path, "error", err)
			return true
		}
		return false
	}

	return true
}
