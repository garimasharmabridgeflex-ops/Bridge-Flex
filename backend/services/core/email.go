package function

import (
	"context"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
)

// topicSendEmail is the Pub/Sub topic communication's OnSendEmail consumer
// reads. Core publishes here instead of sending mail itself so there is one
// place that owns templates, de-duplication and the SMTP transport.
const topicSendEmail = "send-email"

// emailLineItem is one row of an invoice breakdown, rendered by the mail
// service. Values arrive pre-formatted because the currency and quantity
// wording belong to the producer, not the transport.
type emailLineItem struct {
	Description string `json:"description"`
	Quantity    string `json:"quantity,omitempty"`
	Amount      string `json:"amount"`
}

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
	LineItems    []emailLineItem   `json:"lineItems,omitempty"`
}

// invoiceEmailLines turns an invoice into the breakdown table the email
// renders: one row per charge, then VAT when there is any. Quantities are
// trimmed of trailing zeros so a two-hour shift reads "2 hrs", not "2.00".
func invoiceEmailLines(inv Invoice) []emailLineItem {
	lines := make([]emailLineItem, 0, len(inv.LineItems)+1)
	for _, item := range inv.LineItems {
		quantity := ""
		if item.Quantity > 0 {
			quantity = strings.TrimRight(strings.TrimRight(fmt.Sprintf("%.2f", item.Quantity), "0"), ".")
			if item.Type == "staffing" {
				quantity += " hrs"
			}
		}
		lines = append(lines, emailLineItem{
			Description: item.Description,
			Quantity:    quantity,
			Amount:      formatPence(item.TotalPence),
		})
	}
	if inv.VATPence > 0 {
		lines = append(lines, emailLineItem{
			Description: fmt.Sprintf("VAT at %.0f%%", inv.VATRate*100),
			Amount:      formatPence(inv.VATPence),
		})
	}
	return lines
}

// sendTransactionalEmail queues an email to the account behind uid.
//
// Best-effort by design: a mailing problem must never roll back the approval,
// rejection or invoice that triggered it, so this logs and returns false
// rather than propagating an error (same contract as notifyInApp).
func sendTransactionalEmail(ctx context.Context, db *firestore.Client, uid, template string, data map[string]string, essential bool) bool {
	return sendTransactionalEmailWithLines(ctx, db, uid, template, data, essential, nil)
}

// sendTransactionalEmailWithLines is the invoice-shaped variant: the same
// queued message, plus an itemised breakdown so the nursery can see what it is
// being charged for without opening anything.
func sendTransactionalEmailWithLines(ctx context.Context, db *firestore.Client, uid, template string, data map[string]string, essential bool, lines []emailLineItem) bool {
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
	if _, ok := data["appUrl"]; !ok {
		data["appUrl"] = appHomeURL
	}

	msg := emailMessage{
		EventID:      fmt.Sprintf("%s-%s-%d", template, uid, time.Now().UnixNano()),
		ToEmail:      email,
		Template:     template,
		TemplateData: data,
		IsEssential:  essential,
		LineItems:    lines,
	}
	if err := publish(ctx, topicSendEmail, msg); err != nil {
		slog.Error("email publish failed", "template", template, "error", err)
		return false
	}
	return true
}
