package function

import (
	"context"
	"time"

	"cloud.google.com/go/firestore"
	"firebase.google.com/go/v4/messaging"
	"google.golang.org/api/iterator"
)

// notifyUser writes the in-app notifications/{id} doc FIRST, then attempts
// the FCM push — never the reverse. A failed doc-write-after-successful-push
// would mean a user got a push with no corresponding in-app record to tap
// into; the Firestore doc is the source of truth, push is best-effort
// (ARCHITECTURE.md v2 §6).
func notifyUser(ctx context.Context, uid, notificationType, title, body string, payload map[string]any) error {
	db, err := fsDB(ctx)
	if err != nil {
		return err
	}

	if _, _, err := db.Collection("notifications").Add(ctx, map[string]any{
		"uid":       uid,
		"type":      notificationType,
		"title":     title,
		"body":      body,
		"payload":   payload,
		"read":      false,
		"createdAt": time.Now(),
	}); err != nil {
		return err
	}

	// Push is best-effort: a send failure (or no registered tokens at all)
	// must not fail the whole trigger — the in-app record above already
	// landed, which is the part that must not be lost.
	_ = sendPushToUser(ctx, db, uid, title, body, payload)
	return nil
}

func sendPushToUser(ctx context.Context, db *firestore.Client, uid, title, body string, data map[string]any) error {
	msgClient, err := messagingClient(ctx)
	if err != nil {
		return err
	}

	stringData := make(map[string]string, len(data))
	for k, v := range data {
		if s, ok := v.(string); ok {
			stringData[k] = s
		}
	}

	iter := db.Collection("profiles").Doc(uid).Collection("fcmTokens").Documents(ctx)
	defer iter.Stop()
	for {
		tokenDoc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return err
		}
		token, _ := tokenDoc.Data()["token"].(string)
		if token == "" {
			continue
		}
		_, sendErr := msgClient.Send(ctx, &messaging.Message{
			Token:        token,
			Notification: &messaging.Notification{Title: title, Body: body},
			Data:         stringData,
		})
		if sendErr != nil && messaging.IsRegistrationTokenNotRegistered(sendErr) {
			// Self-clean stale tokens rather than accumulating dead ones
			// (ARCHITECTURE.md v2 §6).
			_, _ = tokenDoc.Ref.Delete(ctx)
		}
	}
	return nil
}
