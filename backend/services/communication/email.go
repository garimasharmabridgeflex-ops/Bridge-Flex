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
	TemplatePaymentReceived     EmailTemplate = "payment_received"
	TemplateTimesheetApproved   EmailTemplate = "timesheet_approved"
	TemplateTimesheetCorrection EmailTemplate = "timesheet_correction"
	TemplatePayslipPaid         EmailTemplate = "payslip_paid"
	TemplateAccountDeleted      EmailTemplate = "account_deleted"
	TemplatePasswordChanged     EmailTemplate = "password_changed"

	// TemplateAdminMessage carries a message an administrator typed in the
	// operations console (chase a document, answer a question). Subject and
	// body are supplied by the caller, not hardcoded here.
	TemplateAdminMessage EmailTemplate = "admin_message"

	// TemplateCustom renders an administrator's Markdown verbatim — this is
	// what a saved console template (a payment reminder, a seasonal greeting)
	// is sent as. Subject and body come from the template document.
	TemplateCustom EmailTemplate = "custom"
)

// EmailLineItem is one row of an invoice breakdown carried in the message
// itself. The mail service renders it; the producer only supplies values.
type EmailLineItem struct {
	Description string `json:"description"`
	Quantity    string `json:"quantity,omitempty"`
	Amount      string `json:"amount"`
}

// EmailMessage is the payload dispatched to the send-email queue/topic.
type EmailMessage struct {
	EventID      string            `json:"eventId"`
	ToEmail      string            `json:"toEmail"`
	Template     EmailTemplate     `json:"template"`
	TemplateData map[string]string `json:"templateData,omitempty"`
	IsEssential  bool              `json:"isEssential"`
	// LineItems backs the invoice template's itemised breakdown — the nursery
	// should see what it is being charged for in the email, not only after
	// opening a PDF.
	LineItems []EmailLineItem `json:"lineItems,omitempty"`
}

const (
	styleH2        = "margin:0 0 12px; font-size:21px; line-height:1.3; color:#0F172A; font-weight:700;"
	styleParagraph = "margin:0 0 14px; font-size:15px; line-height:1.6; color:#1E293B;"
	styleQuote     = "margin:0 0 16px; padding:10px 16px; border-left:3px solid #F59E0B; background:#FFFBEB; color:#78350F; font-size:14px; line-height:1.6;"
)

// RenderTemplate builds the subject, HTML body, and plain text body. The
// per-template switch returns only its *content*; the branded shell and the
// preference footer are added once, at the end, so an email can never ship
// without the K Flex header or (for non-essential mail) a way to opt out.
func RenderTemplate(template EmailTemplate, data map[string]string, isEssential bool, lineItems ...EmailLineItem) (subject, htmlBody, textBody string, err error) {
	name := data["name"]
	if name == "" {
		name = "there"
	}

	var bodyHTML, bodyText, preheader string

	switch template {
	case TemplateWelcome:
		subject = "Welcome to K Flex"
		preheader = "Your account is ready — here is what happens next."
		bodyHTML = fmt.Sprintf(`<h2 style="%s">Welcome to K Flex, %s</h2>
<p style="%s">Your account is created. Here is what happens next:</p>
<ul style="margin:0 0 14px; padding-left:20px; font-size:15px; line-height:1.6; color:#1E293B;">
  <li style="margin:0 0 6px;">Tell us whether you are a nursery or a practitioner.</li>
  <li style="margin:0 0 6px;">Complete your profile — the more complete it is, the better your matches.</li>
  <li style="margin:0 0 6px;">Upload your documents. Our team verifies them, usually within one working day.</li>
</ul>
%s`, styleH2, escape(name), styleParagraph, ctaButton("Open K Flex", data["appUrl"], "#2563EB"))
		bodyText = fmt.Sprintf("Welcome to K Flex, %s!\n\nYour account is created. Sign in to pick your account type, complete your profile and upload your documents.", name)

	case TemplateShiftConfirmed:
		subject = "Your shift is confirmed — K Flex"
		preheader = "The nursery approved your application."
		bodyHTML = fmt.Sprintf(`<h2 style="%s">Shift confirmed</h2>
<p style="%s">Hi %s, the nursery approved your application. The shift details — address, times and who to ask for — are in the app.</p>
%s`, styleH2, styleParagraph, escape(name), ctaButton("View my shift", data["appUrl"], "#2563EB"))
		bodyText = fmt.Sprintf("Hi %s, your shift has been confirmed. Open the app to view details.", name)

	case TemplateDocumentReviewed:
		subject = "Document review update — K Flex"
		preheader = "A document you uploaded has been reviewed."
		bodyHTML = fmt.Sprintf(`<h2 style="%s">Document review update</h2>
<p style="%s">Hi %s, a document you uploaded has been reviewed. %s</p>
%s`, styleH2, styleParagraph, escape(name), escape(data["outcome"]), ctaButton("Check my documents", data["appUrl"], "#2563EB"))
		bodyText = fmt.Sprintf("Hi %s, a document you uploaded has been reviewed. %s", name, data["outcome"])

	case TemplatePolicyNotice:
		subject = "Updated Terms and Policies — K Flex"
		preheader = "We have updated our terms or policies."
		bodyHTML = fmt.Sprintf(`<h2 style="%s">Policy update</h2>
<p style="%s">Hi %s, our terms and conditions or policies have been updated. You will be asked to accept the latest version in the app.</p>
%s`, styleH2, styleParagraph, escape(name), ctaButton("Review the change", data["appUrl"], "#2563EB"))
		bodyText = fmt.Sprintf("Hi %s, our terms and conditions or policies have been updated.", name)

	case TemplateNurseryApproved:
		subject = "Your K Flex nursery account is approved"
		preheader = "Your 14-day free trial starts now."
		bodyHTML = fmt.Sprintf(`<h2 style="%s">Nursery approved</h2>
<p style="%s">Hi %s, your nursery registration is approved and your 14-day free trial started on <strong>%s</strong>. You can post shifts and book practitioners now.</p>
%s`, styleH2, styleParagraph, escape(name), escape(data["trialStart"]), ctaButton("Post your first shift", data["appUrl"], "#059669"))
		bodyText = fmt.Sprintf("Hi %s, your nursery registration is approved and your 14-day free trial started on %s.", name, data["trialStart"])

	case TemplateNurseryRejected:
		subject = "Action needed on your K Flex nursery registration"
		preheader = "We need a little more information."
		bodyHTML = fmt.Sprintf(`<h2 style="%s">Registration needs attention</h2>
<p style="%s">Hi %s, your nursery registration needs more information before it can be approved.</p>
<blockquote style="%s">%s</blockquote>
%s`, styleH2, styleParagraph, escape(name), styleQuote, escape(data["reason"]), ctaButton("Update my registration", data["appUrl"], "#2563EB"))
		bodyText = fmt.Sprintf("Hi %s, your nursery registration needs more information: %s", name, data["reason"])

	case TemplateVettingApproved:
		subject = "Your K Flex verification is complete"
		preheader = "You are verified — DBS checked by K Flex."
		bodyHTML = fmt.Sprintf(`<h2 style="%s">Verified — DBS Checked by K Flex</h2>
<p style="%s">Hi %s, your identity and DBS checks are complete. You can apply for shifts now.</p>
%s`, styleH2, styleParagraph, escape(name), ctaButton("Browse open shifts", data["appUrl"], "#059669"))
		bodyText = fmt.Sprintf("Hi %s, your identity and DBS checks are complete. You can apply for shifts now.", name)

	case TemplateVettingRejected:
		subject = "Action needed on your K Flex verification"
		preheader = "We need more information before we can verify you."
		bodyHTML = fmt.Sprintf(`<h2 style="%s">Verification needs attention</h2>
<p style="%s">Hi %s, we need more information before your verification can be completed.</p>
<blockquote style="%s">%s</blockquote>
%s`, styleH2, styleParagraph, escape(name), styleQuote, escape(data["reason"]), ctaButton("Open my verification", data["appUrl"], "#2563EB"))
		bodyText = fmt.Sprintf("Hi %s, we need more information: %s", name, data["reason"])

	case TemplateInvoiceGenerated:
		subject = fmt.Sprintf("Invoice %s from K Flex", data["invoiceNumber"])
		preheader = fmt.Sprintf("%s is due on %s.", data["total"], data["dueDate"])
		// The card page only exists when the charge was mirrored into Stripe.
		// Saying nothing in the other case left a nursery holding an invoice
		// with no way to pay it — so the fallback states the reference and says
		// a card link follows (RunStripeSync backfills it and the console can
		// re-send).
		payHTML := fmt.Sprintf(`<p style="%s">A card payment link will follow in a separate email. If you pay by bank transfer, quote <strong>%s</strong> as the reference.</p>`,
			styleParagraph, escape(data["invoiceNumber"]))
		payText := fmt.Sprintf("\nA card payment link will follow. If you pay by bank transfer, quote %s as the reference.", data["invoiceNumber"])
		if payURL := strings.TrimSpace(data["payUrl"]); payURL != "" {
			payHTML = ctaButton("View and pay invoice", payURL, "#059669")
			payText = "\nView and pay by card: " + payURL
		}
		dueLine := ""
		if due := strings.TrimSpace(data["dueDate"]); due != "" {
			dueLine = fmt.Sprintf(`<p style="%s">Payment is due by <strong>%s</strong>.</p>`, styleParagraph, escape(due))
		}
		tableHTML := invoiceLineTable(data["total"], lineItems)
		bodyHTML = fmt.Sprintf(`<h2 style="%s">New invoice</h2>
<p style="%s">Hi %s, invoice <strong>%s</strong> for <strong>%s</strong> has been generated. Staffing charges (and any membership charge) are itemised below.</p>
%s%s%s%s`, styleH2, styleParagraph, escape(name), escape(data["invoiceNumber"]), escape(data["total"]), dueLine, tableHTML, payHTML, ctaButton("Open my invoices", data["appUrl"], "#2563EB"))
		bodyText = fmt.Sprintf("Hi %s, invoice %s for %s has been generated.%s%s", name, data["invoiceNumber"], data["total"], invoiceLineText(data["total"], lineItems), payText)

	case TemplatePaymentReceived:
		subject = fmt.Sprintf("Payment received — invoice %s", data["invoiceNumber"])
		preheader = "Thank you — your account is up to date."
		bodyHTML = fmt.Sprintf(`<h2 style="%s">Payment received</h2>
<p style="%s">Hi %s, we have received your payment of <strong>%s</strong> for invoice <strong>%s</strong>. Thank you — your account is up to date.</p>
%s`, styleH2, styleParagraph, escape(name), escape(data["total"]), escape(data["invoiceNumber"]), ctaButton("Open my invoices", data["appUrl"], "#059669"))
		bodyText = fmt.Sprintf("Hi %s, we have received your payment of %s for invoice %s. Thank you.", name, data["total"], data["invoiceNumber"])

	case TemplateTimesheetApproved:
		subject = "Your timesheet was approved — K Flex"
		preheader = "Your hours have been approved for payroll."
		bodyHTML = fmt.Sprintf(`<h2 style="%s">Timesheet approved</h2>
<p style="%s">Hi %s, your timesheet for <strong>%s</strong> was approved. %s hours will be included in the next payroll run.</p>
%s`, styleH2, styleParagraph, escape(name), escape(data["shiftTitle"]), escape(data["hours"]), ctaButton("View my earnings", data["appUrl"], "#2563EB"))
		bodyText = fmt.Sprintf("Hi %s, your timesheet for %s was approved. %s hours will be included in the next payroll run.",
			name, data["shiftTitle"], data["hours"])

	case TemplateTimesheetCorrection:
		subject = "Your timesheet needs a correction — K Flex"
		preheader = "Please review and resubmit your hours."
		bodyHTML = fmt.Sprintf(`<h2 style="%s">Timesheet needs a correction</h2>
<p style="%s">Hi %s, the nursery asked for a change to your timesheet for <strong>%s</strong>.</p>
<blockquote style="%s">%s</blockquote>
%s`, styleH2, styleParagraph, escape(name), escape(data["shiftTitle"]), styleQuote, escape(data["note"]), ctaButton("Open my timesheets", data["appUrl"], "#2563EB"))
		bodyText = fmt.Sprintf("Hi %s, the nursery asked for a change to your timesheet for %s: %s", name, data["shiftTitle"], data["note"])

	case TemplatePayslipPaid:
		subject = fmt.Sprintf("Payroll paid — %s", data["periodLabel"])
		preheader = fmt.Sprintf("%s has been paid.", data["amount"])
		bodyHTML = fmt.Sprintf(`<h2 style="%s">You have been paid</h2>
<p style="%s">Hi %s, payroll for <strong>%s</strong> has been paid. Your payslip shows <strong>%s</strong> gross.</p>
%s`, styleH2, styleParagraph, escape(name), escape(data["periodLabel"]), escape(data["amount"]), ctaButton("View my payslips", data["appUrl"], "#059669"))
		bodyText = fmt.Sprintf("Hi %s, payroll for %s has been paid. Your payslip shows %s gross.", name, data["periodLabel"], data["amount"])

	case TemplateAccountDeleted:
		subject = "Your K Flex account has been deleted"
		preheader = "Your account and profile have been removed."
		bodyHTML = fmt.Sprintf(`<h2 style="%s">Your account has been deleted</h2>
<p style="%s">Hi %s, your K Flex account has been deleted and your profile removed, as you requested. Records we must keep for tax and safeguarding (invoices, timesheets and payroll already settled) are retained for the period the law requires, then deleted.</p>
<p style="%s">If this was not you, reply to this email immediately.</p>`, styleH2, styleParagraph, escape(name), styleParagraph)
		bodyText = fmt.Sprintf("Hi %s, your K Flex account has been deleted and your profile removed, as you requested.\n\nRecords we must keep for tax and safeguarding are retained for the period the law requires, then deleted.\n\nIf this was not you, reply to this email immediately.", name)

	case TemplatePasswordChanged:
		subject = "Your K Flex password was changed"
		preheader = "If this was not you, secure your account now."
		bodyHTML = fmt.Sprintf(`<h2 style="%s">Your password was changed</h2>
<p style="%s">Hi %s, the password on your K Flex account was just changed. If this was you, there is nothing else to do.</p>
<p style="%s">If it was not, reset your password immediately and contact us.</p>
%s`, styleH2, styleParagraph, escape(name), styleParagraph, ctaButton("Reset my password", "https://kflex.co.uk/forgot-password", "#DC2626"))
		bodyText = fmt.Sprintf("Hi %s, the password on your K Flex account was just changed. If this was not you, reset it immediately.", name)

	case TemplateSubscriptionUpdated:
		subject = "Your K Flex membership has been updated"
		preheader = fmt.Sprintf("Your nursery is now on %s.", data["planName"])
		bodyHTML = fmt.Sprintf(`<h2 style="%s">Membership updated</h2>
<p style="%s">Hi %s, your nursery is now on <strong>%s</strong>. No payment has been taken in the app — settlement is by invoice.</p>
%s`, styleH2, styleParagraph, escape(name), escape(data["planName"]), ctaButton("View my membership", data["appUrl"], "#2563EB"))
		bodyText = fmt.Sprintf("Hi %s, your nursery is now on %s. No payment has been taken in the app.", name, data["planName"])

	case TemplateTrialEnding:
		subject = "Your K Flex free trial ends soon"
		preheader = "Choose a plan to keep posting shifts."
		bodyHTML = fmt.Sprintf(`<h2 style="%s">Your trial is ending</h2>
<p style="%s">Hi %s, your 14-day free trial ends on <strong>%s</strong>. Choose a membership plan in the app to keep posting shifts after that. You will not be charged automatically.</p>
%s`, styleH2, styleParagraph, escape(name), escape(data["trialEndDate"]), ctaButton("Choose a plan", data["appUrl"], "#2563EB"))
		bodyText = fmt.Sprintf("Hi %s, your 14-day free trial ends on %s. Choose a plan in the app to continue — you will not be charged automatically.",
			name, data["trialEndDate"])

	case TemplateAdminMessage, TemplateCustom:
		subject = strings.TrimSpace(data["subject"])
		if subject == "" {
			subject = "A message from K Flex"
		}
		preheader = firstLine(data["body"])
		// The console composer is Markdown, so an administrator can send a
		// formatted message — headings, bold, lists, links, images — from the
		// same box that used to send flat paragraphs.
		bodyHTML = RenderMarkdown(data["body"])
		bodyText = PlainTextFromMarkdown(data["body"])
		if ctaLabel := strings.TrimSpace(data["ctaLabel"]); ctaLabel != "" {
			if button := ctaButton(ctaLabel, data["ctaUrl"], "#2563EB"); button != "" {
				bodyHTML += button
				bodyText += "\n\n" + ctaLabel + ": " + data["ctaUrl"]
			}
		}

	default:
		return "", "", "", fmt.Errorf("unknown email template: %s", template)
	}

	htmlBody = emailShell(preheader, bodyHTML, isEssential)

	textBody = bodyText
	if isEssential {
		textBody += "\n\n— K Flex"
	} else {
		textBody += "\n\n---\nYou are receiving this email because you have a K Flex account. Manage your email preferences at https://kflex.co.uk/unsubscribe"
	}
	return subject, htmlBody, textBody, nil
}

// invoiceLineTable renders the invoice breakdown. When no rows were supplied
// (an older producer, or an invoice with a single membership line) it renders
// nothing rather than an empty table with a total floating under it.
func invoiceLineTable(total string, items []EmailLineItem) string {
	if len(items) == 0 {
		return ""
	}
	var b strings.Builder
	b.WriteString(`<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:0 0 18px; border-collapse:collapse; font-size:14px; color:#1E293B;">`)
	b.WriteString(`<thead><tr style="background:#F8FAFC;">` +
		`<th align="left" style="padding:9px 12px; border-bottom:1px solid #E2E8F0; font-size:12px; text-transform:uppercase; letter-spacing:0.4px; color:#64748B; font-weight:700;">Item</th>` +
		`<th align="right" style="padding:9px 12px; border-bottom:1px solid #E2E8F0; font-size:12px; text-transform:uppercase; letter-spacing:0.4px; color:#64748B; font-weight:700;">Qty</th>` +
		`<th align="right" style="padding:9px 12px; border-bottom:1px solid #E2E8F0; font-size:12px; text-transform:uppercase; letter-spacing:0.4px; color:#64748B; font-weight:700;">Amount</th>` +
		`</tr></thead><tbody>`)
	for _, item := range items {
		b.WriteString(`<tr>` +
			`<td style="padding:10px 12px; border-bottom:1px solid #F1F5F9;">` + escape(item.Description) + `</td>` +
			`<td align="right" style="padding:10px 12px; border-bottom:1px solid #F1F5F9; color:#64748B;">` + escape(item.Quantity) + `</td>` +
			`<td align="right" style="padding:10px 12px; border-bottom:1px solid #F1F5F9; font-weight:600; white-space:nowrap;">` + escape(item.Amount) + `</td>` +
			`</tr>`)
	}
	b.WriteString(`</tbody><tfoot><tr>` +
		`<td style="padding:12px; font-weight:700;">Total due</td><td></td>` +
		`<td align="right" style="padding:12px; font-weight:800; font-size:16px; white-space:nowrap;">` + escape(total) + `</td>` +
		`</tr></tfoot></table>`)
	return b.String()
}

func invoiceLineText(total string, items []EmailLineItem) string {
	if len(items) == 0 {
		return ""
	}
	var b strings.Builder
	b.WriteString("\n\nItems:\n")
	for _, item := range items {
		line := "- " + item.Description
		if strings.TrimSpace(item.Quantity) != "" {
			line += " (" + item.Quantity + ")"
		}
		if strings.TrimSpace(item.Amount) != "" {
			line += " — " + item.Amount
		}
		b.WriteString(line + "\n")
	}
	b.WriteString("Total due: " + total)
	return b.String()
}

// ctaButton renders the single, unambiguous action an email is asking for.
func ctaButton(label, url, colour string) string {
	url = strings.TrimSpace(url)
	if strings.TrimSpace(label) == "" || !safeEmailURL(url) {
		return ""
	}
	return fmt.Sprintf(`<p style="margin:0 0 18px;"><a href="%s" style="display:inline-block; padding:12px 22px; background:%s; color:#ffffff; border-radius:9999px; text-decoration:none; font-weight:700; font-size:14px;">%s</a></p>`,
		escape(url), colour, escape(label))
}

// emailShell wraps a template body in the branded, table-based layout email
// clients understand. Inline styles only: Gmail and Outlook strip <style>.
func emailShell(preheader, bodyHTML string, isEssential bool) string {
	footer := `<p style="margin:0 0 6px; font-size:12px; line-height:1.5; color:#94A3B8;">You are receiving this because you have a K Flex account.</p>
      <p style="margin:0; font-size:12px; line-height:1.5; color:#94A3B8;"><a href="https://kflex.co.uk/unsubscribe" style="color:#94A3B8;">Manage email preferences</a> · K Flex, United Kingdom</p>`
	if isEssential {
		footer = `<p style="margin:0; font-size:12px; line-height:1.5; color:#94A3B8;">This is an important account message from K Flex · United Kingdom</p>`
	}

	hidden := ""
	if strings.TrimSpace(preheader) != "" {
		hidden = `<div style="display:none; max-height:0; overflow:hidden; opacity:0;">` + escape(preheader) + `</div>`
	}

	return `<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>K Flex</title></head>
<body style="margin:0; padding:0; background:#F1F5F9;">
` + hidden + `
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F1F5F9; padding:24px 12px;">
  <tr><td align="center">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:600px; background:#ffffff; border-radius:16px; overflow:hidden; font-family:-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;">
      <tr><td style="background:#1B2A4A; padding:20px 28px;">
        <span style="display:inline-block; width:34px; height:34px; line-height:34px; text-align:center; border-radius:10px; background:#2563EB; color:#ffffff; font-weight:800; font-size:16px; vertical-align:middle;">K</span>
        <span style="margin-left:10px; color:#ffffff; font-weight:700; font-size:15px; vertical-align:middle; letter-spacing:0.3px;">K Flex</span>
      </td></tr>
      <tr><td style="padding:28px;">
` + bodyHTML + `
      </td></tr>
      <tr><td style="padding:0 28px 24px;">
        <hr style="border:none; border-top:1px solid #E2E8F0; margin:0 0 14px;">
        ` + footer + `
      </td></tr>
    </table>
  </td></tr>
</table>
</body></html>`
}

func firstLine(text string) string {
	line := strings.TrimSpace(strings.SplitN(strings.TrimSpace(text), "\n", 2)[0])
	line = strings.TrimLeft(line, "#> -")
	if len(line) > 120 {
		line = line[:120] + "…"
	}
	return strings.TrimSpace(line)
}

// escape HTML-escapes every interpolated value. The reason, plan name and
// invoice number in the templates above come from admin input — they are
// trusted-ish, but a message body is not the place to find out.
func escape(s string) string { return html.EscapeString(s) }

// paragraphsToHTML turns the plain text an admin typed into escaped
// paragraphs: blank lines separate blocks, single newlines become <br>. It is
// escaped *before* the markup is added, so a pasted "<script>" stays text.
// Kept for callers that still submit plain text rather than Markdown.
func paragraphsToHTML(body string) string {
	blocks := strings.Split(strings.ReplaceAll(body, "\r\n", "\n"), "\n\n")
	var b strings.Builder
	for _, block := range blocks {
		trimmed := strings.TrimSpace(block)
		if trimmed == "" {
			continue
		}
		b.WriteString("<p>")
		b.WriteString(strings.ReplaceAll(escape(trimmed), "\n", "<br>"))
		b.WriteString("</p>")
	}
	return b.String()
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

	subject, htmlBody, textBody, err := RenderTemplate(emailMsg.Template, emailMsg.TemplateData, emailMsg.IsEssential, emailMsg.LineItems...)
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
		if cfg, cfgErr := mailConfigFor(ctx, db); cfgErr != nil {
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
		if cfg, cfgErr := mailConfigFor(ctx, db); cfgErr != nil {
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
