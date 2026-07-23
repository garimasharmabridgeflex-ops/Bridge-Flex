// Package function holds the functions-payments stub. See TODO.md for what
// real payments work needs to add here — this codebase intentionally
// contains no Stripe dependency yet (ARCHITECTURE.md v2 §5).
package function

import (
	"net/http"

	"github.com/GoogleCloudPlatform/functions-framework-go/functions"

	"kvision.internal/shared/httpjson"
)

func init() {
	functions.HTTP("CreatePayout", createPayout)
}

// createPayout is a placeholder proving the core→payments call contract
// exists and deploys cleanly, without any real Stripe integration
// (ARCHITECTURE.md v2 §5). It intentionally does not require auth today
// since there's no real operation to gate — real payments work should wrap
// this in the same RequireAuth pattern used by core once it does something.
func createPayout(w http.ResponseWriter, r *http.Request) {
	httpjson.WriteError(w, http.StatusNotImplemented, "PAYMENTS_NOT_YET_BUILT",
		"Payments is deferred — see services/payments/TODO.md")
}
