package function

import (
	"context"
	"time"

	"cloud.google.com/go/firestore"
)

// notifyInApp writes one notifications/{id} document, the same shape the
// communication service's notifyUser writes. Core writes these directly for
// events that must not depend on a Pub/Sub hop (approvals, vetting, billing).
// Push delivery stays best-effort and lives in communication.
//
// Failures are returned but callers treat them as non-fatal: a notification
// problem must never roll back the approval or money change that caused it.
func notifyInApp(ctx context.Context, db *firestore.Client, uid, notificationType, title, body string, payload map[string]any) error {
	if uid == "" || db == nil {
		return nil
	}
	if payload == nil {
		payload = map[string]any{}
	}
	_, _, err := db.Collection("notifications").Add(ctx, map[string]any{
		"uid":       uid,
		"type":      notificationType,
		"title":     title,
		"body":      body,
		"payload":   payload,
		"read":      false,
		"createdAt": time.Now().UTC(),
	})
	return err
}
