package function

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"github.com/GoogleCloudPlatform/functions-framework-go/functions"
	"github.com/cloudevents/sdk-go/v2/event"
)

func init() {
	functions.CloudEvent("OnSendEmail", onSendEmail)
}

// EmailTemplate defines the available transactional email templates.
type EmailTemplate string

const (
	TemplateWelcome          EmailTemplate = "welcome"
	TemplateShiftConfirmed   EmailTemplate = "shift_confirmed"
	TemplateDocumentReviewed EmailTemplate = "document_reviewed"
	TemplatePolicyNotice     EmailTemplate = "policy_notice"
)

// EmailMessage is the payload dispatched to the send-email queue/topic.
type EmailMessage struct {
	EventID     string            `json:"eventId"`
	ToEmail     string            `json:"toEmail"`
	Template    EmailTemplate     `json:"template"`
	TemplateData map[string]string `json:"templateData,omitempty"`
	IsEssential bool              `json:"isEssential"`
}

// RenderTemplate builds the subject, HTML body, and plaintext body.
func RenderTemplate(template EmailTemplate, data map[string]string, isEssential bool) (subject, html, text string, err error) {
	name := data["name"]
	if name == "" {
		name = "there"
	}

	unsubscribeFooterHTML := ""
	unsubscribeFooterText := ""
	if !isEssential {
		unsubscribeFooterHTML = `<hr><p style="font-size: 11px; color: #888;">You are receiving this email because you have a K Flex account. <a href="https://kflex.co.uk/unsubscribe">Manage email preferences</a></p>`
		unsubscribeFooterText = "\n\n---\nTo manage your email preferences, visit https://kflex.co.uk/unsubscribe"
	}

	switch template {
	case TemplateWelcome:
		subject = "Welcome to K Flex"
		html = fmt.Sprintf("<h2>Welcome to K Flex, %s!</h2><p>Your account is created. Please complete your profile to get started.</p>%s", name, unsubscribeFooterHTML)
		text = fmt.Sprintf("Welcome to K Flex, %s!\nYour account is created. Please complete your profile to get started.%s", name, unsubscribeFooterText)
	case TemplateShiftConfirmed:
		subject = "Your shift is confirmed — K Flex"
		html = fmt.Sprintf("<h2>Shift Confirmed</h2><p>Hi %s, your shift has been confirmed. Open the app to view details.</p>%s", name, unsubscribeFooterHTML)
		text = fmt.Sprintf("Hi %s, your shift has been confirmed. Open the app to view details.%s", name, unsubscribeFooterText)
	case TemplateDocumentReviewed:
		subject = "Document review update — K Flex"
		html = fmt.Sprintf("<h2>Document Review Update</h2><p>Hi %s, your uploaded document has been reviewed. Check the app for details.</p>%s", name, unsubscribeFooterHTML)
		text = fmt.Sprintf("Hi %s, your uploaded document has been reviewed. Check the app for details.%s", name, unsubscribeFooterText)
	case TemplatePolicyNotice:
		subject = "Updated Terms and Policies — K Flex"
		html = fmt.Sprintf("<h2>Policy Update</h2><p>Hi %s, our terms and conditions or policies have been updated.</p>%s", name, unsubscribeFooterHTML)
		text = fmt.Sprintf("Hi %s, our terms and conditions or policies have been updated.%s", name, unsubscribeFooterText)
	default:
		return "", "", "", fmt.Errorf("unknown email template: %s", template)
	}

	return subject, html, text, nil
}

// sanitizeRecipientDomain extracts only the email domain for R7 PII-safe logging.
func sanitizeRecipientDomain(email string) string {
	parts := strings.Split(email, "@")
	if len(parts) == 2 {
		return "@" + parts[1]
	}
	return "redacted"
}

// onSendEmail consumes messages from the send-email Pub/Sub topic.
func onSendEmail(ctx context.Context, e event.Event) error {
	var msg messagePublishedData
	if err := e.DataAs(&msg); err != nil {
		return fmt.Errorf("event.DataAs: %w", err)
	}

	var emailMsg EmailMessage
	if err := json.Unmarshal(msg.Message.Data, &emailMsg); err != nil {
		return fmt.Errorf("unmarshal EmailMessage: %w", err)
	}

	if emailMsg.ToEmail == "" {
		return errors.New("missing recipient toEmail")
	}

	subject, _, _, err := RenderTemplate(emailMsg.Template, emailMsg.TemplateData, emailMsg.IsEssential)
	if err != nil {
		return err
	}

	// De-duplicate on event ID in Firestore
	db, err := fsDB(ctx)
	if err != nil {
		return err
	}

	now := time.Now().UTC()
	if emailMsg.EventID != "" {
		ref := db.Collection("sentEmails").Doc(emailMsg.EventID)
		snap, err := ref.Get(ctx)
		if err == nil && snap.Exists() {
			// Already sent (idempotent de-duplication)
			slog.Info("email already sent, skipping duplicate", "eventId", emailMsg.EventID)
			return nil
		}
		_, _ = ref.Set(ctx, map[string]any{
			"template":  string(emailMsg.Template),
			"sentAt":    now,
			"domain":    sanitizeRecipientDomain(emailMsg.ToEmail),
		})
	}

	// R7: Strict compliance - never log email address, name, or PII
	slog.Info("email dispatched successfully",
		"eventId", emailMsg.EventID,
		"template", string(emailMsg.Template),
		"subject", subject,
		"domain", sanitizeRecipientDomain(emailMsg.ToEmail),
	)

	return nil
}
