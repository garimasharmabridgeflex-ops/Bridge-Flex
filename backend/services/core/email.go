package function

import (
	"context"
	"fmt"
	"log/slog"
	"time"

	"cloud.google.com/go/firestore"
)

// topicSendEmail is the Pub/Sub topic communication's OnSendEmail consumer
// reads. Core publishes here instead of sending mail itself so there is one
// place that owns templates, de-duplication and the SMTP transport.
const topicSendEmail = "send-email"

// emailMessage mirrors communication's EmailMessage JSON shape exactly. The
// two services are separate Go modules with no shared wire package for this
// payload (ARCHITECTURE.md v2 §1a — services only share backend/shared), so
// the struct is duplicated here the same way the Pub/Sub payload structs are.
type emailMessage struct {
	EventID      string            `json:"eventId"`
	ToEmail      string            `json:"toEmail"`
	Template     string            `json:"template"`
	TemplateData map[string]string `json:"templateData,omitempty"`
	IsEssential  bool              `json:"isEssential"`
}

// sendTransactionalEmail queues an email to the account behind uid.
//
// Best-effort by design: a mailing problem must never roll back the approval,
// rejection or invoice that triggered it, so this logs and returns false
// rather than propagating an error (same contract as notifyInApp).
func sendTransactionalEmail(ctx context.Context, db *firestore.Client, uid, template string, data map[string]string, essential bool) bool {
	if uid == "" || db == nil {
		return false
	}

	snap, err := db.Collection("profiles").Doc(uid).Get(ctx)
	if err != nil {
		slog.Warn("email skipped: profile unreadable", "template", template, "error", err)
		return false
	}
	email, _ := snap.Data()["email"].(string)
	if email == "" {
		return false
	}

	if data == nil {
		data = map[string]string{}
	}
	if _, ok := data["name"]; !ok {
		if name, ok := snap.Data()["name"].(string); ok && name != "" {
			data["name"] = name
		}
	}

	msg := emailMessage{
		EventID:      fmt.Sprintf("%s-%s-%d", template, uid, time.Now().UnixNano()),
		ToEmail:      email,
		Template:     template,
		TemplateData: data,
		IsEssential:  essential,
	}
	if err := publish(ctx, topicSendEmail, msg); err != nil {
		slog.Error("email publish failed", "template", template, "error", err)
		return false
	}
	return true
}
