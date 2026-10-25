package function

import (
	"strings"
	"testing"
)

// TestRenderTemplateCoversEveryTemplate guards the owner's brief §12 mail
// list: a template the producer can publish but RenderTemplate does not know
// fails at consume time, which in production means a retry loop and a silent
// non-delivery. Every template must render a subject, an HTML body and a
// plain-text body.
func TestRenderTemplateCoversEveryTemplate(t *testing.T) {
	data := map[string]string{
		"name":          "Sam",
		"trialStart":    "01 Jan 2026",
		"trialEndDate":  "14 Jan 2026",
		"reason":        "Original certificate not seen",
		"invoiceNumber": "INV-2026-0007",
		"total":         "£412.80",
		"planName":      "Standard",
		"recheckDue":    "01 Jan 2027",
	}

	templates := []EmailTemplate{
		TemplateWelcome,
		TemplateShiftConfirmed,
		TemplateDocumentReviewed,
		TemplatePolicyNotice,
		TemplateNurseryApproved,
		TemplateNurseryRejected,
		TemplateVettingApproved,
		TemplateVettingRejected,
		TemplateInvoiceGenerated,
		TemplateSubscriptionUpdated,
		TemplateTrialEnding,
	}

	for _, tpl := range templates {
		subject, htmlBody, textBody, err := RenderTemplate(tpl, data, true)
		if err != nil {
			t.Errorf("RenderTemplate(%q): %v", tpl, err)
			continue
		}
		if subject == "" {
			t.Errorf("RenderTemplate(%q): empty subject", tpl)
		}
		if htmlBody == "" || textBody == "" {
			t.Errorf("RenderTemplate(%q): missing body (html=%v text=%v)", tpl, htmlBody != "", textBody != "")
		}
	}
}

// TestRenderTemplateRejectsUnknown keeps the fail-closed behaviour: an
// unknown template must error rather than send an empty message.
func TestRenderTemplateRejectsUnknown(t *testing.T) {
	if _, _, _, err := RenderTemplate("not_a_real_template", map[string]string{}, true); err == nil {
		t.Fatal("expected an error for an unknown template")
	}
}

// TestEscapeKeepsAdminInputOutOfHTML: reasons and plan names come from admin
// input and are interpolated into HTML bodies.
func TestEscapeKeepsAdminInputOutOfHTML(t *testing.T) {
	data := map[string]string{"name": "<script>alert(1)</script>"}
	_, htmlBody, textBody, err := RenderTemplate(TemplateNurseryRejected, map[string]string{
		"name":   data["name"],
		"reason": "</p><img src=x onerror=alert(1)>",
	}, true)
	if err != nil {
		t.Fatalf("RenderTemplate: %v", err)
	}
	if strings.Contains(htmlBody, "<script>") || strings.Contains(htmlBody, "onerror=alert(1)>") {
		t.Errorf("admin input reached the HTML body unescaped: %s", htmlBody)
	}
	if !strings.Contains(textBody, "onerror") {
		t.Errorf("plain-text body should still carry the reason verbatim: %s", textBody)
	}
}

// TestMailConfigNotConfigured is the default state of this repository: no
// SMTP credentials anywhere in the tree, so the consumer must skip rather
// than fail (see onSendEmail).
func TestMailConfigNotConfigured(t *testing.T) {
	t.Setenv("SMTP_HOST", "")
	t.Setenv("SMTP_USER", "")
	t.Setenv("SMTP_PASS", "")
	t.Setenv("SMTP_FROM", "")

	if _, err := mailConfigFromEnv(); err != errNoSMTPTransport {
		t.Fatalf("mailConfigFromEnv() err = %v, want errNoSMTPTransport", err)
	}
}
