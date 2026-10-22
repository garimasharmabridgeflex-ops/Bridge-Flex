package outbox

import (
	"context"
	"time"

	"cloud.google.com/go/firestore"
)

// Event is an outbox record written in the same transaction as a business mutation.
type Event struct {
	ID        string         `firestore:"id" json:"id"`
	Topic     string         `firestore:"topic" json:"topic"`
	Payload   map[string]any `firestore:"payload" json:"payload"`
	Status    string         `firestore:"status" json:"status"` // "pending" | "published" | "dead_letter"
	CreatedAt time.Time      `firestore:"createdAt" json:"createdAt"`
	SentAt    *time.Time     `firestore:"sentAt,omitempty" json:"sentAt,omitempty"`
	Retries   int            `firestore:"retries" json:"retries"`
	Error     string         `firestore:"error,omitempty" json:"error,omitempty"`
}

// WriteTx enqueues an outbox event within a Firestore transaction.
func WriteTx(tx *firestore.Transaction, db *firestore.Client, event Event) error {
	if event.CreatedAt.IsZero() {
		event.CreatedAt = time.Now()
	}
	if event.Status == "" {
		event.Status = "pending"
	}
	var ref *firestore.DocumentRef
	if event.ID != "" {
		ref = db.Collection("outbox").Doc(event.ID)
	} else {
		ref = db.Collection("outbox").NewDoc()
		event.ID = ref.ID
	}
	return tx.Set(ref, event)
}

// MarkPublished marks an outbox item as published.
func MarkPublished(ctx context.Context, db *firestore.Client, id string) error {
	now := time.Now()
	_, err := db.Collection("outbox").Doc(id).Update(ctx, []firestore.Update{
		{Path: "status", Value: "published"},
		{Path: "sentAt", Value: now},
	})
	return err
}

// MarkFailed increments retry counter and flags dead_letter if maxRetries exceeded.
func MarkFailed(ctx context.Context, db *firestore.Client, id string, failureErr error, maxRetries int) error {
	ref := db.Collection("outbox").Doc(id)
	snap, err := ref.Get(ctx)
	if err != nil {
		return err
	}
	var ev Event
	if err := snap.DataTo(&ev); err != nil {
		return err
	}
	ev.Retries++
	if failureErr != nil {
		ev.Error = failureErr.Error()
	}
	if ev.Retries >= maxRetries {
		ev.Status = "dead_letter"
	}
	_, err = ref.Set(ctx, ev)
	return err
}
