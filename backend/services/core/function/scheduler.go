package function

import (
	"log/slog"
	"net/http"
	"time"

	"github.com/GoogleCloudPlatform/functions-framework-go/functions"
	"kvision.internal/shared/httpjson"
)

func init() {
	functions.HTTP("SchedulerHeartbeat", schedulerHeartbeat)
}

// schedulerHeartbeat — POST /schedulerHeartbeat. Invoked by Cloud Scheduler
// as a no-op health check and heartbeat verification.
func schedulerHeartbeat(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	now := time.Now().UTC()

	db, err := fsDB(ctx)
	if err != nil {
		slog.Error("scheduler heartbeat: db unavailable", "error", err)
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "db unavailable")
		return
	}

	_, _ = db.Collection("platformConfig").Doc("heartbeat").Set(ctx, map[string]any{
		"lastHeartbeat": now,
	})

	slog.Info("scheduler heartbeat ok", "timestamp", now)
	httpjson.WriteJSON(w, http.StatusOK, map[string]any{
		"status":    "ok",
		"timestamp": now.Format(time.RFC3339),
	})
}
