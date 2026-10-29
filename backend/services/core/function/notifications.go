package function

import (
	"context"
	"log/slog"
	"sync"
	"time"

	"cloud.google.com/go/firestore"
	"firebase.google.com/go/v4/messaging"
	"google.golang.org/api/iterator"

	"kvision.internal/shared/audit"
	"kvision.internal/shared/fbapp"
)

var (
	messagingOnce   sync.Once
	messagingClient *messaging.Client
	messagingErr    error
)

// fcmClient is created once per instance, like the Firestore client. A failure
// (no credentials in a local run, for instance) is remembered and every later
// push attempt is skipped — the in-app record is what must not be lost.
func fcmClient(ctx context.Context) (*messaging.Client, error) {
	messagingOnce.Do(func() {
		app, err := fbapp.New(ctx)
		if err != nil {
			messagingErr = err
			return
		}
		messagingClient, messagingErr = app.Messaging(ctx)
	})
	return messagingClient, messagingErr
}

// notifyInApp writes one notifications/{id} document, the same shape the
// communication service's notifyUser writes. Core writes these directly for
// events that must not depend on a Pub/Sub hop (approvals, vetting, billing).
//
// The FCM push is sent AFTER the Firestore write and is best-effort, exactly
// like communication's notifyUser: the notification document is the source of
// truth and the part that must never be lost, so a push problem (no token, no
// credentials, a stale token) must never fail the approval, vetting decision
// or money change that caused it.
//
// Every in-app notification therefore now pushes too. That is what was missing
// for the events core owns end to end and never publishes anywhere —
// "your DBS check has been verified", a failed vetting decision, a nursery
// approval, an invoice being generated, a timesheet approval or correction
// request — which previously reached users only if they happened to open the
// notifications screen.
//
// Callers treat a returned error as non-fatal: a notification problem must
// never roll back the business change that caused it.
func notifyInApp(ctx context.Context, db *firestore.Client, uid, notificationType, title, body string, payload map[string]any) error {
	if uid == "" || db == nil {
		return nil
	}
	if payload == nil {
		payload = map[string]any{}
	}
	if _, _, err := db.Collection("notifications").Add(ctx, map[string]any{
		"uid":       uid,
		"type":      notificationType,
		"title":     title,
		"body":      body,
		"payload":   payload,
		"read":      false,
		"createdAt": time.Now().UTC(),
	}); err != nil {
		return err
	}

	// Every user-visible business event reaches the other party through this
	// function (applications, approvals, vetting decisions, timesheets), so
	// this is also the signal that tells an open admin console to refresh now
	// rather than on its next poll. Throttled and best-effort.
	audit.SignalActivity(db, "notification."+notificationType)

	sendPushToUser(ctx, db, uid, title, body, payload)
	return nil
}

// sendPushToUser pushes to every device token registered against the profile.
// Mirrors the communication service's implementation (separate Go modules with
// no shared helper package for this — ARCHITECTURE.md v2 §1a).
func sendPushToUser(ctx context.Context, db *firestore.Client, uid, title, body string, payload map[string]any) {
	client, err := fcmClient(ctx)
	if err != nil {
		slog.Debug("push skipped: no messaging client", "uid", uid, "error", err)
		return
	}

	// FCM data values must be strings; the notification payload also carries
	// numbers (billable minutes, pay) which only make sense in the app UI.
	data := make(map[string]string, len(payload))
	for k, v := range payload {
		if s, ok := v.(string); ok {
			data[k] = s
		}
	}

	iter := db.Collection("profiles").Doc(uid).Collection("fcmTokens").Documents(ctx)
	defer iter.Stop()
	for {
		tokenDoc, err := iter.Next()
		if err == iterator.Done {
			return
		}
		if err != nil {
			slog.Warn("push skipped: token list unreadable", "uid", uid, "error", err)
			return
		}
		token, _ := tokenDoc.Data()["token"].(string)
		if token == "" {
			continue
		}
		if _, sendErr := client.Send(ctx, &messaging.Message{
			Token:        token,
			Notification: &messaging.Notification{Title: title, Body: body},
			Data:         data,
		}); sendErr != nil {
			if messaging.IsRegistrationTokenNotRegistered(sendErr) {
				// Self-clean stale tokens rather than accumulating dead ones
				// (ARCHITECTURE.md v2 §6).
				_, _ = tokenDoc.Ref.Delete(ctx)
				continue
			}
			slog.Warn("push send failed", "uid", uid, "error", sendErr)
		}
	}
}
