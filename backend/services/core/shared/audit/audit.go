package audit

import (
	"context"
	"time"

	"cloud.google.com/go/firestore"
	"kvision.internal/shared/auth"
)

// Entry records an administrative or privileged action in the append-only auditLogs collection.
type Entry struct {
	Timestamp time.Time      `firestore:"timestamp" json:"timestamp"`
	ActorUID  string         `firestore:"actorUid" json:"actorUid"`
	ActorRole string         `firestore:"actorRole" json:"actorRole"`
	Action    string         `firestore:"action" json:"action"`
	TargetUID string         `firestore:"targetUid,omitempty" json:"targetUid,omitempty"`
	TargetDoc string         `firestore:"targetDoc,omitempty" json:"targetDoc,omitempty"`
	Fields    []string       `firestore:"fields,omitempty" json:"fields,omitempty"`
	RequestID string         `firestore:"requestId,omitempty" json:"requestId,omitempty"`
	Metadata  map[string]any `firestore:"metadata,omitempty" json:"metadata,omitempty"`
}

// WriteAudit records an audit entry to the auditLogs collection.
func WriteAudit(ctx context.Context, db *firestore.Client, entry Entry) error {
	if entry.Timestamp.IsZero() {
		entry.Timestamp = time.Now()
	}
	if entry.ActorUID == "" {
		entry.ActorUID = auth.UID(ctx)
	}
	if entry.ActorRole == "" {
		entry.ActorRole = string(auth.GetAdminRole(ctx))
	}
	_, _, err := db.Collection("auditLogs").Add(ctx, entry)
	// Every admin action and every business decision writes an audit entry, so
	// this is the one hook that turns "something changed" into an instant
	// refresh signal for the web console. Fire-and-forget by contract.
	SignalActivity(db, entry.Action)
	return err
}

// WriteAuditTx records an audit entry inside an active transaction.
func WriteAuditTx(ctx context.Context, tx *firestore.Transaction, db *firestore.Client, entry Entry) error {
	if entry.Timestamp.IsZero() {
		entry.Timestamp = time.Now()
	}
	if entry.ActorUID == "" {
		entry.ActorUID = auth.UID(ctx)
	}
	if entry.ActorRole == "" {
		entry.ActorRole = string(auth.GetAdminRole(ctx))
	}
	ref := db.Collection("auditLogs").NewDoc()
	err := tx.Create(ref, entry)
	if err == nil {
		SignalActivity(db, entry.Action)
	}
	return err
}
