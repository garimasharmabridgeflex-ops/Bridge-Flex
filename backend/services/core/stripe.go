package function

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
)

// Stripe invoicing.
//
// Invoices are the one place the platform moves money in *and* relies on an
// external service to say it arrived, so the design is deliberately narrow:
//
//   - Nursery charges are raised locally first (the invoice document is the
//     source of truth for what was billed and from which timesheets), then
//     mirrored into Stripe so the nursery can pay by card or bank and gets
//     Stripe's own dunning/reminders.
//   - Nothing here is fatal. Without STRIPE_SECRET_KEY the platform keeps
//     invoicing exactly as before (PDF + email, bank transfer, manual
//     reconciliation); Stripe simply stays absent.
//   - Payment confirmation comes back through the sync worker
//     (RunStripeSync / SchedulerStripeSync), which flips an invoice to paid
//     when Stripe says it is. Manual reconciliation stays available for the
//     bank-transfer case (MarkInvoicePaid).
const (
	stripeAPIBase = "https://api.stripe.com/v1"
	// stripeAPIVersion pins the response shape: Stripe changes field
	// semantics between versions, and an unpinned client silently changes
	// behaviour when the account default moves.
	stripeAPIVersion = "2024-06-20"
)

// errStripeNotConfigured is not a failure to log loudly — it is the normal
// state of a deployment that invoices by bank transfer only.
var errStripeNotConfigured = fmt.Errorf("stripe is not configured")

// errStripeEmptyInvoice means the invoice carried no billable lines, so it was
// voided instead of finalised. Stripe settles a zero-total invoice immediately
// and the webhook would mark the nursery's real invoice paid.
var errStripeEmptyInvoice = fmt.Errorf("stripe invoice has no billable lines")

type stripeClient struct {
	secretKey string
	http      *http.Client
}

// stripeFromEnv returns a client when STRIPE_SECRET_KEY is set. The key lives
// in the function's environment (Secret Manager / Cloud Run env vars), never
// in Firestore: an admin console field would let a stolen admin session read
// a live secret key back out.
func stripeFromEnv() (*stripeClient, string) {
	key := strings.TrimSpace(os.Getenv("STRIPE_SECRET_KEY"))
	if key == "" {
		return nil, ""
	}
	mode := "live"
	if strings.HasPrefix(key, "sk_test_") {
		mode = "test"
	}
	return &stripeClient{secretKey: key, http: &http.Client{Timeout: 20 * time.Second}}, mode
}

// call performs one form-encoded Stripe request and decodes the JSON reply.
// Stripe reports business errors in the body ({"error":{"message":...}}) with
// a 4xx status, so that message is surfaced verbatim — "No such customer" is
// far more useful to an admin than "request failed".
func (c *stripeClient) call(ctx context.Context, method, path string, form url.Values, out any) error {
	req, err := http.NewRequestWithContext(ctx, method, stripeAPIBase+path, strings.NewReader(form.Encode()))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+c.secretKey)
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("Stripe-Version", stripeAPIVersion)

	res, err := c.http.Do(req)
	if err != nil {
		return fmt.Errorf("stripe request: %w", err)
	}
	defer res.Body.Close()

	body, _ := io.ReadAll(io.LimitReader(res.Body, 1<<20))
	if res.StatusCode >= 400 {
		var errPayload struct {
			Error struct {
				Message string `json:"message"`
				Type    string `json:"type"`
			} `json:"error"`
		}
		if json.Unmarshal(body, &errPayload) == nil && errPayload.Error.Message != "" {
			return fmt.Errorf("stripe: %s", errPayload.Error.Message)
		}
		return fmt.Errorf("stripe: HTTP %d", res.StatusCode)
	}
	if out == nil {
		return nil
	}
	if err := json.Unmarshal(body, out); err != nil {
		return fmt.Errorf("stripe decode: %w", err)
	}
	return nil
}

type stripeInvoice struct {
	ID               string `json:"id"`
	Status           string `json:"status"`
	HostedInvoiceURL string `json:"hosted_invoice_url"`
	InvoicePDF       string `json:"invoice_pdf"`
	Total            int64  `json:"total"`
	AmountDue        int64  `json:"amount_due"`
	AmountPaid       int64  `json:"amount_paid"`
	Currency         string `json:"currency"`
}

// ensureStripeCustomer returns the nursery's Stripe customer id, creating one
// on first use and caching it on the subscription document so repeat invoices
// do not create a new customer each week.
func ensureStripeCustomer(ctx context.Context, db *firestore.Client, nurseryID, nurseryName, email string) (string, error) {
	subRef := db.Collection("subscriptions").Doc(nurseryID)
	if snap, err := subRef.Get(ctx); err == nil {
		if id, ok := snap.Data()["stripeCustomerId"].(string); ok && id != "" {
			return id, nil
		}
	}

	client, _ := stripeFromEnv()
	if client == nil {
		return "", errStripeNotConfigured
	}

	form := url.Values{}
	form.Set("name", nurseryName)
	if email != "" {
		form.Set("email", email)
	form.Set("currency", "gbp")
	}
	form.Set("description", "K Flex nursery account")
	form.Set("metadata[nurseryId]", nurseryID)

	var customer struct {
		ID string `json:"id"`
	}
	if err := client.call(ctx, http.MethodPost, "/customers", form, &customer); err != nil {
		return "", err
	}
	_, _ = subRef.Set(ctx, map[string]any{
		"stripeCustomerId": customer.ID,
		"updatedAt":        time.Now().UTC(),
	}, firestore.MergeAll)
	return customer.ID, nil
}

// pushInvoiceToStripe mirrors a locally-created invoice into Stripe, finalises
// it and has Stripe email it to the nursery's billing contact. The returned
// values are stored on the invoice document so the console can link straight
// to Stripe and the sync worker knows which Stripe invoice to poll.
//
// Best-effort: the local invoice exists and is emailed regardless. A Stripe
// outage must not mean the nursery is never billed.
func pushInvoiceToStripe(ctx context.Context, db *firestore.Client, inv *Invoice) error {
	client, _ := stripeFromEnv()
	if client == nil {
		return errStripeNotConfigured
	}

	customerID, err := ensureStripeCustomer(ctx, db, inv.NurseryID, inv.NurseryName, inv.BillingEmail)
	if err != nil {
		return err
	}

	// The invoice is created first, as a draft, so every line can be attached
	// to it explicitly. Two things bit us here (invoice INV-2026-0008 came out
	// of Stripe already "paid" within three seconds):
	//
	//   - currency must be set to gbp. The line items are GBP, and on an
	//     invoice defaulted to the account currency Stripe drops them rather
	//     than failing, leaving a zero total.
	//   - pending invoice items are not reliably swept into a manually created
	//     invoice, so each item is passed "invoice=<draft id>" instead of
	//     hoping it gets picked up.
	//
	// A zero-total invoice is settled by Stripe the instant it is finalised,
	// which fires invoice.paid and made the platform believe the nursery had
	// paid. The total guard below refuses to finalise one.
	form := url.Values{}
	form.Set("customer", customerID)
	form.Set("currency", "gbp")
	form.Set("collection_method", "send_invoice")
	form.Set("days_until_due", "7")
	form.Set("description", "K Flex invoice "+inv.InvoiceNumber)
	form.Set("metadata[invoiceId]", inv.ID)
	form.Set("metadata[nurseryId]", inv.NurseryID)
	form.Set("metadata[invoiceNumber]", inv.InvoiceNumber)
	form.Set("auto_advance", "false")

	var created stripeInvoice
	if err := client.call(ctx, http.MethodPost, "/invoices", form, &created); err != nil {
		return err
	}

	// One invoice item per local line, so the nursery's Stripe invoice reads the
	// same as the PDF rather than one opaque total.
	addLine := func(amountPence int64, description, timesheetID string) error {
		lineForm := url.Values{}
		lineForm.Set("customer", customerID)
		lineForm.Set("currency", "gbp")
		lineForm.Set("invoice", created.ID)
		lineForm.Set("amount", fmt.Sprintf("%d", amountPence))
		lineForm.Set("description", description)
		if timesheetID != "" {
			lineForm.Set("metadata[timesheetId]", timesheetID)
		}
		return client.call(ctx, http.MethodPost, "/invoiceitems", lineForm, nil)
	}

	for _, line := range inv.LineItems {
		if err := addLine(line.TotalPence, line.Description, line.TimesheetID); err != nil {
			return err
		}
	}

	// VAT (when the company VAT number is published) is added as its own line
	// so the Stripe total matches the local total exactly.
	if inv.VATPence > 0 {
		if err := addLine(inv.VATPence, fmt.Sprintf("VAT at %.0f%%", inv.VATRate*100), ""); err != nil {
			return err
		}
	}

	if err := client.call(ctx, http.MethodPost, "/invoices/"+created.ID+"/finalize", url.Values{}, &created); err != nil {
		return err
	}

	// Nothing billable made it onto the invoice. Void it so the Stripe
	// dashboard does not keep a paid-looking £0 invoice, and hand the failure
	// back so the local invoice stays "issued" and can be regenerated.
	if created.Total <= 0 {
		if err := client.call(ctx, http.MethodPost, "/invoices/"+created.ID+"/void", url.Values{}, nil); err != nil {
			slog.Warn("stripe void of empty invoice failed", "stripeInvoiceId", created.ID, "error", err)
		}
		return errStripeEmptyInvoice
	}
	// Stripe's own email is a bonus, not a dependency: the platform sends its
	// branded invoice email too. If the nursery has no Stripe email yet this
	// call 400s, and that must not unwind the invoice.
	if err := client.call(ctx, http.MethodPost, "/invoices/"+created.ID+"/send", url.Values{}, &created); err != nil {
		slog.Warn("stripe invoice send failed", "invoiceId", inv.ID, "error", err)
	}

	_, err = db.Collection("invoices").Doc(inv.ID).Set(ctx, map[string]any{
		"stripeInvoiceId":     created.ID,
		"stripeInvoiceStatus": created.Status,
		"stripeHostedUrl":     created.HostedInvoiceURL,
		"stripePdfUrl":        created.InvoicePDF,
		"updatedAt":           time.Now().UTC(),
	}, firestore.MergeAll)

	// Mirror the result onto the caller's struct so the invoice email written
	// immediately afterwards can carry the payment link.
	inv.StripeInvoiceID = created.ID
	inv.StripeInvoiceStatus = created.Status
	inv.StripeHostedURL = created.HostedInvoiceURL
	inv.StripePDFURL = created.InvoicePDF
	return err
}

// fetchStripeInvoice reads the current state of one Stripe invoice.
func fetchStripeInvoice(ctx context.Context, stripeID string) (*stripeInvoice, error) {
	client, _ := stripeFromEnv()
	if client == nil {
		return nil, errStripeNotConfigured
	}
	var out stripeInvoice
	if err := client.call(ctx, http.MethodGet, "/invoices/"+stripeID, url.Values{}, &out); err != nil {
		return nil, err
	}
	return &out, nil
}
