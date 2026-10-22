package idempotency

import (
	"context"
	"errors"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

var (
	// ErrRequestInProgress is returned when an identical idempotency key is already running.
	ErrRequestInProgress = errors.New("request already in progress")
)

// Record represents a cached idempotent response or an active lock in idempotency/{key}.
type Record struct {
	Key        string    `firestore:"key" json:"key"`
	Status     string    `firestore:"status" json:"status"` // "pending" | "completed"
	StatusCode int       `firestore:"statusCode,omitempty" json:"statusCode,omitempty"`
	Response   string    `firestore:"response,omitempty" json:"response,omitempty"`
	CreatedAt  time.Time `firestore:"createdAt" json:"createdAt"`
	ExpiresAt  time.Time `firestore:"expiresAt" json:"expiresAt"`
}

// CheckOrLock claims an idempotency key or retrieves the previous completed response.
func CheckOrLock(ctx context.Context, db *firestore.Client, key string, ttl time.Duration) (*Record, error) {
	if key == "" {
		return nil, nil
	}
	ref := db.Collection("idempotency").Doc(key)
	now := time.Now()
	var cached *Record

	err := db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		snap, err := tx.Get(ref)
		if err != nil && status.Code(err) != codes.NotFound {
			return err
		}
		if err == nil {
			var r Record
			if err := snap.DataTo(&r); err == nil {
				if r.Status == "completed" {
					cached = &r
					return nil
				}
				if r.Status == "pending" && now.Before(r.ExpiresAt) {
					return ErrRequestInProgress
				}
			}
		}
		rec := Record{
			Key:       key,
			Status:    "pending",
			CreatedAt: now,
			ExpiresAt: now.Add(ttl),
		}
		return tx.Set(ref, rec)
	})

	return cached, err
}

// Complete saves the completed response for the given key.
func Complete(ctx context.Context, db *firestore.Client, key string, statusCode int, responseBody string, ttl time.Duration) error {
	if key == "" {
		return nil
	}
	ref := db.Collection("idempotency").Doc(key)
	now := time.Now()
	_, err := ref.Set(ctx, map[string]any{
		"status":     "completed",
		"statusCode": statusCode,
		"response":   responseBody,
		"updatedAt":  now,
		"expiresAt":  now.Add(ttl),
	}, firestore.MergeAll)
	return err
}
