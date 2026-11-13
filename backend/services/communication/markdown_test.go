package function

import (
	"strings"
	"testing"
)

// TestRenderMarkdownFormatsTheConsoleSubset covers what an administrator is
// told they can type: headings, bold/italic, links, images, lists, quotes and
// rules all have to come out as HTML, or the composer is lying to them.
func TestRenderMarkdownFormatsTheConsoleSubset(t *testing.T) {
	source := "# Heading\n\n" +
		"Some **bold** and *italic* text with a [link](https://example.com).\n\n" +
		"![Logo](https://example.com/logo.png)\n\n" +
		"- first\n- second\n\n" +
		"1. one\n2. two\n\n" +
		"> quoted\n\n" +
		"---\n"

	out := RenderMarkdown(source)
	for _, want := range []string{
		"<h1", "Heading</h1>",
		"<strong", "bold</strong>",
		"<em>italic</em>",
		`href="https://example.com"`,
		`src="https://example.com/logo.png"`,
		"<ul", "<li", "first", "second",
		"<ol", "<blockquote", "<hr",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("rendered markdown is missing %q:\n%s", want, out)
		}
	}
}

// TestRenderMarkdownEscapesHTML is the security property: the console lets an
// administrator paste arbitrary text, and that text must never become markup.
func TestRenderMarkdownEscapesHTML(t *testing.T) {
	out := RenderMarkdown("<script>alert(1)</script>\n\n<img src=x onerror=alert(1)>")
	if strings.Contains(out, "<script>") || strings.Contains(out, "onerror=alert(1)>") {
		t.Fatalf("raw HTML reached the rendered output: %s", out)
	}
	if !strings.Contains(out, "&lt;script&gt;") {
		t.Errorf("expected the tag to be shown as text: %s", out)
	}
}

// TestRenderMarkdownRefusesUnsafeLinks: a javascript: or data: target must not
// become a clickable link or an image source.
func TestRenderMarkdownRefusesUnsafeLinks(t *testing.T) {
	out := RenderMarkdown("[click](javascript:alert(1)) ![x](data:text/html;base64,AAAA)")
	if strings.Contains(out, "javascript:") || strings.Contains(out, "data:text/html") {
		t.Fatalf("unsafe URL survived rendering: %s", out)
	}
}

// TestPlainTextKeepsLinkTargets: the text/plain alternative has to still say
// where a link went, or a plain-text reader cannot follow it.
func TestPlainTextKeepsLinkTargets(t *testing.T) {
	text := PlainTextFromMarkdown("Read [the policy](https://example.com/policy) now.")
	if !strings.Contains(text, "https://example.com/policy") {
		t.Fatalf("plain text lost the link target: %s", text)
	}
}

// TestInvoiceEmailCarriesLineItems: the owner's ask was that the invoice email
// show the invoice, not just describe it.
func TestInvoiceEmailCarriesLineItems(t *testing.T) {
	_, htmlBody, textBody, err := RenderTemplate(TemplateInvoiceGenerated, map[string]string{
		"name":          "Sam",
		"invoiceNumber": "INV-2026-0009",
		"total":         "£39.00",
		"dueDate":       "20 November 2026",
	}, true,
		EmailLineItem{Description: "Staffing: 2.0 hrs @ £19.50/hr (Baby room)", Quantity: "2 hrs", Amount: "£39.00"},
	)
	if err != nil {
		t.Fatalf("RenderTemplate: %v", err)
	}
	if !strings.Contains(htmlBody, "Baby room") || !strings.Contains(htmlBody, "Total due") {
		t.Errorf("invoice table missing from HTML body: %s", htmlBody)
	}
	if !strings.Contains(textBody, "Baby room") || !strings.Contains(textBody, "Total due: £39.00") {
		t.Errorf("invoice lines missing from text body: %s", textBody)
	}
}

// TestInvoiceEmailWithoutStripeLinkStillOffersARoute: an invoice that failed
// to mirror must not arrive as a dead end.
func TestInvoiceEmailWithoutStripeLinkStillOffersARoute(t *testing.T) {
	_, htmlBody, _, err := RenderTemplate(TemplateInvoiceGenerated, map[string]string{
		"name":          "Sam",
		"invoiceNumber": "INV-2026-0010",
		"total":         "£12.00",
	}, true)
	if err != nil {
		t.Fatalf("RenderTemplate: %v", err)
	}
	if !strings.Contains(htmlBody, "INV-2026-0010") {
		t.Errorf("fallback payment wording missing: %s", htmlBody)
	}
}
