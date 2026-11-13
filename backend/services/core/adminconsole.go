package function

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/GoogleCloudPlatform/functions-framework-go/functions"
	"google.golang.org/api/iterator"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"kvision.internal/shared/audit"
	"kvision.internal/shared/auth"
	"kvision.internal/shared/httpjson"
)

func init() {
	// Read-side helpers for the operations console.
	functions.HTTP("ListNurserySubscriptions", authed(listNurserySubscriptions))
	functions.HTTP("GetMailSettings", authed(getMailSettings))
	functions.HTTP("UpdateMailSettings", authed(updateMailSettings))
	functions.HTTP("GetAutomationSettings", authed(getAutomationSettings))
	functions.HTTP("UpdateAutomationSettings", authed(updateAutomationSettings))
	functions.HTTP("GetStripeStatus", authed(getStripeStatus))
	functions.HTTP("PushInvoiceToStripe", authed(pushInvoiceToStripeHandler))

	// Outbound mail: a one-off message to a single account (the practitioners
	// and nurseries lists both offer it) and a re-send of an invoice email.
	functions.HTTP("SendUserEmail", authed(sendUserEmail))
	functions.HTTP("SendInvoiceEmail", authed(sendInvoiceEmail))

	// Workers. The Run* twins are admin-triggered from the console; the
	// Scheduler* endpoints are what Cloud Scheduler calls.
	functions.HTTP("RunInvoiceGeneration", authed(runInvoiceGeneration))
	functions.HTTP("SchedulerGenerateInvoices", schedulerGenerateInvoices)
	functions.HTTP("RunStripeSync", authed(runStripeSync))
	functions.HTTP("SchedulerStripeSync", schedulerStripeSync)
}

/* ------------------------------------------------------------------ *
 * Subscriptions (plan mix for the console)
 * ------------------------------------------------------------------ */

// listNurserySubscriptions — GET /listNurserySubscriptions. Admin only.
// Every nursery membership document, so the console can show how many are on
// each plan, how many are trialling and what the recurring value is, without
// one request per nursery.
func listNurserySubscriptions(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !isAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "NOT_ADMIN", "Admin claim required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	iter := db.Collection("subscriptions").Limit(1000).Documents(ctx)
	defer iter.Stop()

	out := []NurserySubscription{}
	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		var sub NurserySubscription
		if err := doc.DataTo(&sub); err != nil {
			continue
		}
		if sub.NurseryID == "" {
			sub.NurseryID = doc.Ref.ID
		}
		out = append(out, sub)
	}

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"subscriptions": out})
}

/* ------------------------------------------------------------------ *
 * Outbound mail
 * ------------------------------------------------------------------ */

type sendUserEmailRequest struct {
	UID     string `json:"uid"`
	Subject string `json:"subject"`
	Body    string `json:"body"`
}

// sendUserEmail — POST /sendUserEmail. Admin only.
//
// Sends one deliberate message from the console (chase a missing document,
// answer a question) to a single account. It goes through the same
// send-email queue as every transactional message, so it is de-duplicated and
// recorded in sentEmails like the rest — this is not a second mail path.
func sendUserEmail(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !isAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "NOT_ADMIN", "Admin claim required")
		return
	}

	var req sendUserEmailRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	req.Subject = strings.TrimSpace(req.Subject)
	req.Body = strings.TrimSpace(req.Body)
	if req.UID == "" || req.Subject == "" || req.Body == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "uid, subject and body are required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	queued := sendTransactionalEmail(ctx, db, req.UID, "admin_message", map[string]string{
		"subject": req.Subject,
		"body":    req.Body,
	}, false)

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:    "admin.send_email",
		ActorUID:  auth.UID(ctx),
		TargetUID: req.UID,
		Metadata: map[string]any{
			"subject": req.Subject,
			"queued":  queued,
		},
	})

	if !queued {
		httpjson.WriteError(w, http.StatusBadGateway, "EMAIL_NOT_QUEUED",
			"Could not queue the email — check the account has an email address and the mail settings are saved")
		return
	}
	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"status": "queued"})
}

type sendInvoiceEmailRequest struct {
	InvoiceID string `json:"invoiceId"`
}

// sendInvoiceEmail — POST /sendInvoiceEmail. Admin only. Re-sends the
// invoice email — useful when a nursery says it never arrived.
func sendInvoiceEmail(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !isAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "NOT_ADMIN", "Admin claim required")
		return
	}

	var req sendInvoiceEmailRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	if req.InvoiceID == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "invoiceId is required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	var inv Invoice
	snap, err := db.Collection("invoices").Doc(req.InvoiceID).Get(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusNotFound, "NOT_FOUND", "Invoice not found")
		return
	}
	if err := snap.DataTo(&inv); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	data := map[string]string{
		"invoiceNumber": inv.InvoiceNumber,
		"total":         formatPence(inv.TotalPence),
		"dueDate":       inv.DueDate.Format("2 January 2006"),
	}
	if inv.StripeHostedURL != "" {
		data["payUrl"] = inv.StripeHostedURL
	}
	queued := sendTransactionalEmailWithLines(ctx, db, inv.NurseryID, "invoice_generated", data, true, invoiceEmailLines(inv))

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:    "admin.invoice_email",
		ActorUID:  auth.UID(ctx),
		TargetDoc: req.InvoiceID,
		Metadata:  map[string]any{"invoiceNumber": inv.InvoiceNumber, "queued": queued},
	})

	if !queued {
		httpjson.WriteError(w, http.StatusBadGateway, "EMAIL_NOT_QUEUED",
			"Could not queue the email — the nursery needs a billing email and the mail settings must be saved")
		return
	}
	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"status": "queued"})
}

// formatPence renders pence for an email body; the console does its own
// formatting, this is only for the server-side template data.
func formatPence(pence int64) string {
	sign := ""
	if pence < 0 {
		sign = "-"
		pence = -pence
	}
	return fmt.Sprintf("%s£%d.%02d", sign, pence/100, pence%100)
}

/* ------------------------------------------------------------------ *
 * Mailer account settings
 * ------------------------------------------------------------------ */

// mailSettingsDoc mirrors what communication's OnSendEmail reads when the
// SMTP_* environment variables are absent. The password is write-only: it is
// stored so the transport can use it, but never returned to the browser.
type mailSettingsDoc struct {
	Host      string    `firestore:"host" json:"host"`
	Port      string    `firestore:"port" json:"port"`
	Username  string    `firestore:"username" json:"username"`
	Password  string    `firestore:"password" json:"-"`
	From      string    `firestore:"from" json:"from"`
	FromName  string    `firestore:"fromName" json:"fromName"`
	UpdatedAt time.Time `firestore:"updatedAt" json:"updatedAt"`
}

// getMailSettings — GET /getMailSettings. Admin only. Never returns the
// stored password, only whether one is set.
func getMailSettings(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !isAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "NOT_ADMIN", "Admin claim required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	var cfg mailSettingsDoc
	snap, err := db.Collection("platformConfig").Doc("mail").Get(ctx)
	if err != nil {
		httpjson.WriteJSON(w, http.StatusOK, map[string]any{
			"configured":         false,
			"passwordConfigured": false,
			"envConfigured":      envMailConfigured(),
			"host":               "",
			"port":               "587",
			"username":           "",
			"from":               "",
			"fromName":           "K Flex",
		})
		return
	}
	_ = snap.DataTo(&cfg)

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{
		"configured":         cfg.Host != "",
		"passwordConfigured": cfg.Password != "",
		"envConfigured":      envMailConfigured(),
		"host":               cfg.Host,
		"port":               cfg.Port,
		"username":           cfg.Username,
		"from":               cfg.From,
		"fromName":           cfg.FromName,
		"updatedAt":          cfg.UpdatedAt,
	})
}

func envMailConfigured() bool {
	return strings.TrimSpace(os.Getenv("SMTP_HOST")) != ""
}

type updateMailSettingsRequest struct {
	Host     string `json:"host"`
	Port     string `json:"port"`
	Username string `json:"username"`
	Password string `json:"password"`
	From     string `json:"from"`
	FromName string `json:"fromName"`
}

// updateMailSettings — POST /updateMailSettings. Admin only.
//
// The SMTP account the platform sends from. Env vars still win (a production
// deployment sets SMTP_* once and never touches this), but an operator with
// no server access can point the platform at a mailbox here. An empty
// password keeps the stored one, so saving other fields does not wipe it.
func updateMailSettings(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !isAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "NOT_ADMIN", "Admin claim required")
		return
	}

	var req updateMailSettingsRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	req.Host = strings.TrimSpace(req.Host)
	req.Port = strings.TrimSpace(req.Port)
	req.From = strings.TrimSpace(req.From)
	req.FromName = strings.TrimSpace(req.FromName)
	if req.Host == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "SMTP host is required")
		return
	}
	if req.Port == "" {
		req.Port = "587"
	}
	if req.From == "" {
		req.From = req.Username
	}
	if req.From == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "A from address (or username) is required")
		return
	}
	if req.FromName == "" {
		req.FromName = "K Flex"
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	now := time.Now().UTC()
	update := map[string]any{
		"host":      req.Host,
		"port":      req.Port,
		"username":  req.Username,
		"from":      req.From,
		"fromName":  req.FromName,
		"updatedAt": now,
	}
	if req.Password != "" {
		update["password"] = req.Password
	}
	if _, err := db.Collection("platformConfig").Doc("mail").Set(ctx, update, firestore.MergeAll); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:   "admin.mail_settings_saved",
		ActorUID: auth.UID(ctx),
		Metadata: map[string]any{"host": req.Host, "from": req.From},
	})

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"status": "saved", "updatedAt": now})
}

/* ------------------------------------------------------------------ *
 * Invoicing automation
 * ------------------------------------------------------------------ */

type automationSettings struct {
	AutoGenerate bool       `firestore:"autoGenerate" json:"autoGenerate"`
	Frequency    string     `firestore:"frequency" json:"frequency"` // "daily" | "weekly"
	AutoEmail    bool       `firestore:"autoEmail" json:"autoEmail"`
	AutoStripe   bool       `firestore:"autoStripe" json:"autoStripe"`
	LastRunAt    *time.Time `firestore:"lastRunAt,omitempty" json:"lastRunAt,omitempty"`
	LastRunCount int        `firestore:"lastRunCount" json:"lastRunCount"`
}

func loadAutomationSettings(ctx context.Context, db *firestore.Client) automationSettings {
	cfg := automationSettings{Frequency: "weekly", AutoEmail: true, AutoStripe: true}
	if snap, err := db.Collection("platformConfig").Doc("invoicing").Get(ctx); err == nil {
		_ = snap.DataTo(&cfg)
	}
	if cfg.Frequency == "" {
		cfg.Frequency = "weekly"
	}
	return cfg
}

// getAutomationSettings — GET /getAutomationSettings. Admin only.
func getAutomationSettings(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !isAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "NOT_ADMIN", "Admin claim required")
		return
	}
	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}
	httpjson.WriteJSON(w, http.StatusOK, loadAutomationSettings(ctx, db))
}

type updateAutomationSettingsRequest struct {
	AutoGenerate bool   `json:"autoGenerate"`
	Frequency    string `json:"frequency"`
	AutoEmail    bool   `json:"autoEmail"`
	AutoStripe   bool   `json:"autoStripe"`
}

// updateAutomationSettings — POST /updateAutomationSettings. Admin only.
func updateAutomationSettings(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !isAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "NOT_ADMIN", "Admin claim required")
		return
	}

	var req updateAutomationSettingsRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	if req.Frequency != "daily" && req.Frequency != "weekly" {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "frequency must be 'daily' or 'weekly'")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	if _, err := db.Collection("platformConfig").Doc("invoicing").Set(ctx, map[string]any{
		"autoGenerate": req.AutoGenerate,
		"frequency":    req.Frequency,
		"autoEmail":    req.AutoEmail,
		"autoStripe":   req.AutoStripe,
		"updatedAt":    time.Now().UTC(),
	}, firestore.MergeAll); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:   "admin.invoicing_settings_saved",
		ActorUID: auth.UID(ctx),
		Metadata: map[string]any{
			"autoGenerate": req.AutoGenerate,
			"frequency":    req.Frequency,
			"autoEmail":    req.AutoEmail,
			"autoStripe":   req.AutoStripe,
		},
	})

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"status": "saved"})
}

// getStripeStatus — GET /getStripeStatus. Admin only. Reports whether the
// deployment holds a Stripe key; the key itself never leaves the server.
func getStripeStatus(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !isAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "NOT_ADMIN", "Admin claim required")
		return
	}
	_, mode := stripeFromEnv()
	httpjson.WriteJSON(w, http.StatusOK, map[string]any{
		"configured": mode != "",
		"mode":       mode,
	})
}

/* ------------------------------------------------------------------ *
 * Invoice worker
 * ------------------------------------------------------------------ */

// runInvoiceGeneration — POST /runInvoiceGeneration. Admin / Finance. Runs
// the generator immediately, whatever the schedule says.
func runInvoiceGeneration(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !isFinanceOrSuperAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "FORBIDDEN", "Finance or SuperAdmin claim required")
		return
	}
	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}
	if !requirePost(w, r) {
		return
	}

	created, err := createStaffingInvoices(ctx, db, true)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	_, _ = db.Collection("platformConfig").Doc("invoicing").Set(ctx, map[string]any{
		"lastRunAt":    time.Now().UTC(),
		"lastRunCount": len(created),
	}, firestore.MergeAll)

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:   "invoices.auto_run",
		ActorUID: auth.UID(ctx),
		Metadata: map[string]any{"invoicesCreated": len(created), "trigger": "manual_run_now"},
	})

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"invoices": created})
}

// schedulerGenerateInvoices — POST /schedulerGenerateInvoices. Called by
// Cloud Scheduler once a day; the frequency setting decides whether this
// particular day is due, so a weekly cadence needs one job, not two.
func schedulerGenerateInvoices(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !schedulerAllowed(ctx, r) {
		httpjson.WriteError(w, http.StatusForbidden, "FORBIDDEN", "Scheduler authorization required")
		return
	}
	if !requirePost(w, r) {
		return
	}
	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore unavailable")
		return
	}

	cfg := loadAutomationSettings(ctx, db)
	if !cfg.AutoGenerate {
		httpjson.WriteJSON(w, http.StatusOK, map[string]any{"skipped": "automatic invoicing is off"})
		return
	}
	if cfg.Frequency == "weekly" && time.Now().UTC().Weekday() != time.Monday {
		httpjson.WriteJSON(w, http.StatusOK, map[string]any{"skipped": "weekly cadence, not Monday"})
		return
	}

	created, err := createStaffingInvoices(ctx, db, cfg.AutoEmail)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	now := time.Now().UTC()
	_, _ = db.Collection("platformConfig").Doc("invoicing").Set(ctx, map[string]any{
		"lastRunAt":    now,
		"lastRunCount": len(created),
	}, firestore.MergeAll)

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:   "invoices.auto_run",
		Metadata: map[string]any{"invoicesCreated": len(created), "trigger": "scheduler", "frequency": cfg.Frequency},
	})

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"invoicesCreated": len(created), "invoices": created})
}

func requirePost(w http.ResponseWriter, r *http.Request) bool {
	if r.Method != http.MethodPost {
		httpjson.WriteError(w, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "POST required")
		return false
	}
	return true
}

/* ------------------------------------------------------------------ *
 * Stripe mirror on demand
 * ------------------------------------------------------------------ */

// pushInvoiceToStripeHandler — POST /PushInvoiceToStripe. Admin only.
//
// Mirroring happens best-effort at generation time, so a Stripe outage — or an
// invoice whose lines arrived empty and was voided instead of finalised —
// leaves a real invoice with no card payment link. This re-runs the mirror for
// one invoice and re-sends Stripe's own email, so the nursery can actually pay
// it without anyone crediting or re-raising the charge.
func pushInvoiceToStripeHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !isAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "NOT_ADMIN", "Admin claim required")
		return
	}
	if !requirePost(w, r) {
		return
	}

	var req struct {
		InvoiceID string `json:"invoiceId"`
	}
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	if req.InvoiceID == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "invoiceId is required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	doc, err := db.Collection("invoices").Doc(req.InvoiceID).Get(ctx)
	if err != nil {
		if status.Code(err) == codes.NotFound {
			httpjson.WriteError(w, http.StatusNotFound, "NOT_FOUND", "Invoice not found")
			return
		}
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}
	var inv Invoice
	if err := doc.DataTo(&inv); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "invoice could not be read")
		return
	}
	inv.ID = doc.Ref.ID

	if inv.Status == InvoicePaid {
		httpjson.WriteError(w, http.StatusConflict, "ALREADY_PAID", "Invoice is already marked paid")
		return
	}
	if inv.Status == InvoiceVoid {
		httpjson.WriteError(w, http.StatusConflict, "VOID_INVOICE", "Voided invoices cannot be sent to Stripe")
		return
	}
	if inv.StripeInvoiceID != "" {
		httpjson.WriteError(w, http.StatusConflict, "ALREADY_MIRRORED",
			"Invoice is already in Stripe ("+inv.StripeInvoiceID+")")
		return
	}

	if err := pushInvoiceToStripe(ctx, db, &inv); err != nil {
		switch {
		case errors.Is(err, errStripeNotConfigured):
			httpjson.WriteError(w, http.StatusConflict, "STRIPE_NOT_CONFIGURED",
				"Set STRIPE_SECRET_KEY before pushing invoices to Stripe")
		case errors.Is(err, errStripeEmptyInvoice):
			httpjson.WriteError(w, http.StatusConflict, "EMPTY_INVOICE",
				"Invoice has no billable lines, so nothing was sent to Stripe")
		default:
			slog.Error("stripe mirror retry failed", "invoiceId", inv.ID, "error", err)
			httpjson.WriteError(w, http.StatusBadGateway, "STRIPE_ERROR", err.Error())
		}
		return
	}

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:    "invoices.stripe_push",
		ActorUID:  auth.UID(ctx),
		TargetDoc: inv.ID,
		Metadata: map[string]any{
			"stripeInvoiceId": inv.StripeInvoiceID,
			"totalPence":      inv.TotalPence,
		},
	})

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{
		"status":          "pushed",
		"stripeInvoiceId": inv.StripeInvoiceID,
		"stripeStatus":    inv.StripeInvoiceStatus,
		"payUrl":          inv.StripeHostedURL,
	})
}

/* ------------------------------------------------------------------ *
 * Stripe reconciliation worker
 * ------------------------------------------------------------------ */

type stripeSyncResult struct {
	Checked    int `json:"checked"`
	MarkedPaid int `json:"markedPaid"`
	StillOpen  int `json:"stillOpen"`
	Mirrored   int `json:"mirrored"`
	Failed     int `json:"failed"`
}

// syncStripeInvoices polls Stripe for every locally-issued invoice that came
// with a Stripe id and marks anything Stripe reports as paid. This is the
// automatic half of reconciliation; MarkInvoicePaid remains the manual half
// (a bank transfer that will never appear in Stripe).
func syncStripeInvoices(ctx context.Context, db *firestore.Client) stripeSyncResult {
	result := stripeSyncResult{}
	if _, mode := stripeFromEnv(); mode == "" {
		return result
	}

	docs, err := db.Collection("invoices").
		Where("status", "in", []string{string(InvoiceIssued), string(InvoiceOverdue)}).
		Limit(200).Documents(ctx).GetAll()
	if err != nil {
		slog.Error("stripe sync: invoice query failed", "error", err)
		return result
	}

	now := time.Now().UTC()
	for _, doc := range docs {
		var inv Invoice
		if err := doc.DataTo(&inv); err != nil {
			continue
		}
		// No Stripe invoice yet: the mirror at generation time failed (Stripe
		// was not configured, the push errored, or the total was refused). The
		// invoice email for that run therefore went out with no payment link —
		// and, until this branch existed, nothing ever went back for it. Retry
		// the mirror here so the hosted card page appears (and is written back
		// to the invoice) on the next sync after a transient failure.
		if inv.StripeInvoiceID == "" {
			if err := pushInvoiceToStripe(ctx, db, &inv); err != nil {
				if !errors.Is(err, errStripeEmptyInvoice) && !errors.Is(err, errStripeNotConfigured) {
					result.Failed++
					slog.Warn("stripe sync: backfill push failed", "invoiceId", doc.Ref.ID, "error", err)
				}
				continue
			}
			result.Checked++
			result.Mirrored++
			continue
		}
		result.Checked++

		remote, err := fetchStripeInvoice(ctx, inv.StripeInvoiceID)
		if err != nil {
			result.Failed++
			slog.Warn("stripe sync: fetch failed", "invoiceId", doc.Ref.ID, "error", err)
			continue
		}

		// A zero-total Stripe invoice is auto-settled on finalise; it is not
		// evidence of payment, so it must not flip a real invoice to paid.
		if remote.Status == "paid" && remote.Total > 0 {
			_, err := doc.Ref.Update(ctx, []firestore.Update{
				{Path: "status", Value: InvoicePaid},
				{Path: "paidAt", Value: now},
				{Path: "paymentReference", Value: "stripe:" + remote.ID},
				{Path: "stripeInvoiceStatus", Value: remote.Status},
				{Path: "updatedAt", Value: now},
			})
			if err != nil {
				result.Failed++
				continue
			}
			result.MarkedPaid++
			_ = notifyInApp(ctx, db, inv.NurseryID, "invoice_paid", "Payment received",
				"We have received your payment for invoice "+inv.InvoiceNumber+". Thank you.",
				map[string]any{"invoiceId": doc.Ref.ID})
			continue
		}

		result.StillOpen++
		_, _ = doc.Ref.Set(ctx, map[string]any{
			"stripeInvoiceStatus": remote.Status,
			"stripeHostedUrl":     remote.HostedInvoiceURL,
			"updatedAt":           now,
		}, firestore.MergeAll)
	}

	return result
}

// runStripeSync — POST /runStripeSync. Admin only.
func runStripeSync(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !isAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "NOT_ADMIN", "Admin claim required")
		return
	}
	if !requirePost(w, r) {
		return
	}
	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}
	if _, mode := stripeFromEnv(); mode == "" {
		httpjson.WriteError(w, http.StatusConflict, "STRIPE_NOT_CONFIGURED",
			"Set STRIPE_SECRET_KEY on functions-core to reconcile card payments automatically")
		return
	}

	result := syncStripeInvoices(ctx, db)
	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:   "invoices.stripe_sync",
		ActorUID: auth.UID(ctx),
		Metadata: map[string]any{
			"checked":    result.Checked,
			"markedPaid": result.MarkedPaid,
			"stillOpen":  result.StillOpen,
			"mirrored":   result.Mirrored,
			"failed":     result.Failed,
		},
	})
	httpjson.WriteJSON(w, http.StatusOK, result)
}

// schedulerStripeSync — POST /schedulerStripeSync. Hourly Cloud Scheduler job.
func schedulerStripeSync(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !schedulerAllowed(ctx, r) {
		httpjson.WriteError(w, http.StatusForbidden, "FORBIDDEN", "Scheduler authorization required")
		return
	}
	if !requirePost(w, r) {
		return
	}
	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore unavailable")
		return
	}
	cfg := loadAutomationSettings(ctx, db)
	if !cfg.AutoStripe {
		httpjson.WriteJSON(w, http.StatusOK, map[string]any{"skipped": "automatic Stripe reconciliation is off"})
		return
	}
	if _, mode := stripeFromEnv(); mode == "" {
		httpjson.WriteJSON(w, http.StatusOK, map[string]any{"skipped": "stripe is not configured"})
		return
	}

	result := syncStripeInvoices(ctx, db)

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action: "invoices.stripe_sync",
		Metadata: map[string]any{
			"trigger":    "scheduler",
			"checked":    result.Checked,
			"markedPaid": result.MarkedPaid,
			"stillOpen":  result.StillOpen,
			"mirrored":   result.Mirrored,
			"failed":     result.Failed,
		},
	})

	httpjson.WriteJSON(w, http.StatusOK, result)
}
