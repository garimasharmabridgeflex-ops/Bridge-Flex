package function

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"html"
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

	// Owner brief §12 — the status emails the platform owes its two sides.
	TemplateNurseryApproved     EmailTemplate = "nursery_approved"
	TemplateNurseryRejected     EmailTemplate = "nursery_rejected"
	TemplateVettingApproved     EmailTemplate = "vetting_approved"
	TemplateVettingRejected     EmailTemplate = "vetting_rejected"
	TemplateInvoiceGenerated    EmailTemplate = "invoice_generated"
	TemplateSubscriptionUpdated EmailTemplate = "subscription_updated"
	TemplateTrialEnding         EmailTemplate = "trial_ending"
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
	case TemplateNurseryApproved:
		subject = "Your K Flex nursery account is approved"
		html = fmt.Sprintf("<h2>Nursery approved</h2><p>Hi %s, your nursery registration is approved and your 14-day free trial started on %s. You can post shifts and book practitioners now.</p>%s",
			escape(name), escape(data["trialStart"]), unsubscribeFooterHTML)
		text = fmt.Sprintf("Hi %s, your nursery registration is approved and your 14-day free trial started on %s.%s",
			name, data["trialStart"], unsubscribeFooterText)
	case TemplateNurseryRejected:
		subject = "Action needed on your K Flex nursery registration"
		html = fmt.Sprintf("<h2>Registration needs attention</h2><p>Hi %s, your nursery registration needs more information before it can be approved.</p><p>%s</p>%s",
			escape(name), escape(data["reason"]), unsubscribeFooterHTML)
		text = fmt.Sprintf("Hi %s, your nursery registration needs more information: %s%s", name, data["reason"], unsubscribeFooterText)
	case TemplateVettingApproved:
		subject = "Your K Flex verification is complete"
		html = fmt.Sprintf("<h2>Verified — DBS Checked by K Flex</h2><p>Hi %s, your identity and DBS checks are complete. You can apply for shifts now.</p>%s",
			escape(name), unsubscribeFooterHTML)
		text = fmt.Sprintf("Hi %s, your identity and DBS checks are complete. You can apply for shifts now.%s", name, unsubscribeFooterText)
	case TemplateVettingRejected:
		subject = "Action needed on your K Flex verification"
		html = fmt.Sprintf("<h2>Verification needs attention</h2><p>Hi %s, we need more information before your verification can be completed.</p><p>%s</p>%s",
			escape(name), escape(data["reason"]), unsubscribeFooterHTML)
		text = fmt.Sprintf("Hi %s, we need more information: %s%s", name, data["reason"], unsubscribeFooterText)
	case TemplateInvoiceGenerated:
		subject = fmt.Sprintf("Invoice %s from K Flex", data["invoiceNumber"])
		html = fmt.Sprintf("<h2>New invoice</h2><p>Hi %s, invoice <strong>%s</strong> for <strong>%s</strong> has been generated. Subscription charges and staffing charges are billed separately. Payment is by bank transfer — quote the invoice number.</p>%s",
			escape(name), escape(data["invoiceNumber"]), escape(data["total"]), unsubscribeFooterHTML)
		text = fmt.Sprintf("Hi %s, invoice %s for %s has been generated. Payment is by bank transfer — quote the invoice number.%s",
			name, data["invoiceNumber"], data["total"], unsubscribeFooterText)
	case TemplateSubscriptionUpdated:
		subject = "Your K Flex membership has been updated"
		html = fmt.Sprintf("<h2>Membership updated</h2><p>Hi %s, your nursery is now on <strong>%s</strong>. No payment has been taken in the app — settlement is by invoice.</p>%s",
			escape(name), escape(data["planName"]), unsubscribeFooterHTML)
		text = fmt.Sprintf("Hi %s, your nursery is now on %s. No payment has been taken in the app.%s", name, data["planName"], unsubscribeFooterText)
	case TemplateTrialEnding:
		subject = "Your K Flex free trial ends soon"
		html = fmt.Sprintf("<h2>Your trial is ending</h2><p>Hi %s, your 14-day free trial ends on %s. Choose a membership plan in the app to keep posting shifts after that. You will not be charged automatically.</p>%s",
			escape(name), escape(data["trialEndDate"]), unsubscribeFooterHTML)
		text = fmt.Sprintf("Hi %s, your 14-day free trial ends on %s. Choose a plan in the app to continue — you will not be charged automatically.%s",
			name, data["trialEndDate"], unsubscribeFooterText)
	default:
		return "", "", "", fmt.Errorf("unknown email template: %s", template)
	}

	return subject, html, text, nil
}

// escape HTML-escapes every interpolated value. The reason, plan name and
// invoice number in the templates above come from admin input — they are
// trusted-ish, but a message body is not the place to find out.
func escape(s string) string { return html.EscapeString(s) }

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

	subject, htmlBody, textBody, err := RenderTemplate(emailMsg.Template, emailMsg.TemplateData, emailMsg.IsEssential)
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

		status := "sent"
		if cfg, cfgErr := mailConfigFromEnv(); cfgErr != nil {
			// No SMTP configured: record the attempt as skipped so a later
			// replay does not re-send, and do not fail the message (failing
			// would retry forever against a platform that has no mail).
			status = "skipped_no_transport"
			slog.Warn("email skipped: SMTP not configured",
				"eventId", emailMsg.EventID,
				"template", string(emailMsg.Template))
		} else if sendErr := sendMail(cfg, emailMsg.ToEmail, subject, htmlBody, textBody); sendErr != nil {
			// A real transport failure propagates, so Pub/Sub retries it.
			return fmt.Errorf("send mail: %w", sendErr)
		}

		_, _ = ref.Set(ctx, map[string]any{
			"template": string(emailMsg.Template),
			"sentAt":   now,
			"status":   status,
			"domain":   sanitizeRecipientDomain(emailMsg.ToEmail),
		})
	} else {
		if cfg, cfgErr := mailConfigFromEnv(); cfgErr != nil {
			slog.Warn("email skipped: SMTP not configured", "template", string(emailMsg.Template))
		} else if sendErr := sendMail(cfg, emailMsg.ToEmail, subject, htmlBody, textBody); sendErr != nil {
			return fmt.Errorf("send mail: %w", sendErr)
		}
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
