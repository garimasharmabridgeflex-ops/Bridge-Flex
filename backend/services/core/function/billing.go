package function

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/GoogleCloudPlatform/functions-framework-go/functions"
	"google.golang.org/api/iterator"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"kvision.internal/shared/audit"
	"kvision.internal/shared/auth"
	"kvision.internal/shared/httpjson"
	"kvision.internal/shared/outbox"
)

const (
	topicInvoiceGenerated   = "invoice-generated"
	topicInvoicePaid        = "invoice-paid"
	topicSubscriptionUpdate = "subscription-updated"
)

func init() {
	functions.HTTP("GetPlans", getPlans)
	functions.HTTP("UpsertPlan", authed(upsertPlan))
	functions.HTTP("GetNurserySubscription", authed(getNurserySubscription))
	functions.HTTP("AssignNurseryPlan", authed(assignNurseryPlan))
	functions.HTTP("GenerateWeeklyInvoices", authed(generateWeeklyInvoices))
	functions.HTTP("ListInvoices", authed(listInvoices))
	functions.HTTP("GetInvoice", authed(getInvoice))
	functions.HTTP("MarkInvoicePaid", authed(markInvoicePaid))
	functions.HTTP("CreateLedgerEntry", authed(createLedgerEntry))
}

func defaultPlans() []Plan {
	now := time.Now().UTC()
	return []Plan{
		{
			ID:               "trial",
			Name:             "Free Trial",
			Description:      "14-day free platform membership trial upon nursery approval",
			PricePence:       0,
			BillingInterval:  "none",
			BookingAllowance: 0,
			TrialDays:        14,
			Active:           true,
			Benefits:         []string{"Post shifts", "Explore practitioners", "Full booking dashboard"},
			CreatedAt:        now,
			UpdatedAt:        now,
		},
		{
			ID:               "standard",
			Name:             "Standard Subscription",
			Description:      "Designed for nurseries that regularly require temporary staff",
			PricePence:       19900, // £199.00 ex VAT
			BillingInterval:  "month",
			BookingAllowance: 0,
			TrialDays:        0,
			Active:           true,
			Benefits:         []string{"Unlimited bookings", "Priority notifications", "Standard staffing support"},
			CreatedAt:        now,
			UpdatedAt:        now,
		},
		{
			ID:               "premium",
			Name:             "Premium Subscription",
			Description:      "Designed for nurseries that require frequent staffing support",
			PricePence:       29900, // £299.00 ex VAT
			BillingInterval:  "month",
			BookingAllowance: 0,
			TrialDays:        0,
			Active:           true,
			Benefits:         []string{"Dedicated account manager", "Fastest matching", "Multi-branch support"},
			CreatedAt:        now,
			UpdatedAt:        now,
		},
		{
			ID:               "payg",
			Name:             "Pay As You Go",
			Description:      "No monthly subscription; £9.99 per booking fee",
			PricePence:       999, // £9.99 ex VAT
			BillingInterval:  "per_booking",
			BookingAllowance: 0,
			TrialDays:        0,
			Active:           true,
			Benefits:         []string{"Zero recurring commitment", "Pay per booking"},
			CreatedAt:        now,
			UpdatedAt:        now,
		},
	}
}

// GenerateNextInvoiceNumber generates atomic sequential invoice numbers: INV-YYYY-XXXX.
func GenerateNextInvoiceNumber(ctx context.Context, db *firestore.Client, year int) (string, error) {
	if db == nil {
		return fmt.Sprintf("INV-%d-0001", year), nil
	}
	counterRef := db.Collection("platformConfig").Doc("invoiceCounter")
	var invoiceNum string
	err := db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		snap, err := tx.Get(counterRef)
		var current int64 = 0
		if err == nil {
			if val, ok := snap.Data()["lastNumber"].(int64); ok {
				current = val
			}
		} else if status.Code(err) != codes.NotFound {
			return err
		}
		next := current + 1
		if err := tx.Set(counterRef, map[string]any{
			"lastNumber": next,
			"updatedAt":  time.Now().UTC(),
		}); err != nil {
			return err
		}
		invoiceNum = fmt.Sprintf("INV-%d-%04d", year, next)
		return nil
	})
	return invoiceNum, err
}

// CalculateInvoiceAmounts calculates subtotal, VAT (if company VAT number published, Decision 4), and total.
func CalculateInvoiceAmounts(lineItems []InvoiceLineItem, vatPublished bool) (subtotalPence int64, vatRate float64, vatPence int64, totalPence int64) {
	for _, item := range lineItems {
		subtotalPence += item.TotalPence
	}
	if vatPublished && subtotalPence > 0 {
		vatRate = 0.20 // 20% standard UK VAT
		vatPence = int64(float64(subtotalPence)*vatRate + 0.5)
	} else {
		vatRate = 0.0
		vatPence = 0
	}
	totalPence = subtotalPence + vatPence
	return subtotalPence, vatRate, vatPence, totalPence
}

// getPlans — GET /getPlans. Public / authenticated.
func getPlans(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	docs, err := db.Collection("plans").Where("active", "==", true).Documents(ctx).GetAll()
	var plans []Plan
	if err == nil && len(docs) > 0 {
		for _, doc := range docs {
			var p Plan
			if err := doc.DataTo(&p); err == nil {
				p.ID = doc.Ref.ID
				plans = append(plans, p)
			}
		}
	}

	// If no plans seeded in Firestore yet, return default seed plans
	if len(plans) == 0 {
		plans = defaultPlans()
	}

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"plans": plans})
}

// upsertPlan — POST /upsertPlan. Admin only.
func upsertPlan(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		httpjson.WriteError(w, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "POST required")
		return
	}

	ctx := r.Context()
	if !isAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "FORBIDDEN", "Admin claim required")
		return
	}

	var req Plan
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	if req.ID == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "MISSING_PLAN_ID", "id is required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	now := time.Now().UTC()
	req.UpdatedAt = now
	if req.CreatedAt.IsZero() {
		req.CreatedAt = now
	}

	_, err = db.Collection("plans").Doc(req.ID).Set(ctx, req)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:    "plan.upsert",
		ActorUID:  auth.UID(ctx),
		TargetDoc: req.ID,
		Metadata: map[string]any{
			"planId":     req.ID,
			"pricePence": req.PricePence,
		},
	})

	httpjson.WriteJSON(w, http.StatusOK, req)
}

// getNurserySubscription — GET /getNurserySubscription?nurseryId=...
// Nursery reads own subscription; Admin can read any.
func getNurserySubscription(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	callerUID := auth.UID(ctx)
	targetNurseryID := r.URL.Query().Get("nurseryId")
	if targetNurseryID == "" {
		targetNurseryID = callerUID
	}

	if targetNurseryID != callerUID && !isAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "FORBIDDEN", "Only nursery owner or admin can view subscription")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	subRef := db.Collection("subscriptions").Doc(targetNurseryID)
	doc, err := subRef.Get(ctx)
	now := time.Now().UTC()

	var sub NurserySubscription
	if err != nil {
		if status.Code(err) == codes.NotFound {
			// Check if nursery has an activationDate (Phase 5)
			pDoc, pErr := db.Collection("profiles").Doc(targetNurseryID).Get(ctx)
			activationDate := now
			if pErr == nil {
				if act, ok := pDoc.Data()["activationDate"].(time.Time); ok && !act.IsZero() {
					activationDate = act
				}
			}

			// Seed 14-day free trial automatically (Decision 12)
			trialEnd := activationDate.Add(14 * 24 * time.Hour)
			sub = NurserySubscription{
				NurseryID:          targetNurseryID,
				PlanID:             "trial",
				PlanName:           "Free Trial",
				Status:             SubTrialing,
				TrialStartDate:     &activationDate,
				TrialEndDate:       &trialEnd,
				CurrentPeriodStart: activationDate,
				CurrentPeriodEnd:   trialEnd,
				PaymentMethod:      "bank_transfer",
				UpdatedAt:          now,
			}
			_, _ = subRef.Set(ctx, sub)
		} else {
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
	} else {
		_ = doc.DataTo(&sub)
	}

	// Calculate trial countdown and expiration
	daysRemaining := 0
	isExpired := false
	if sub.Status == SubTrialing && sub.TrialEndDate != nil {
		if now.Before(*sub.TrialEndDate) {
			daysRemaining = int(sub.TrialEndDate.Sub(now).Hours() / 24)
		} else {
			daysRemaining = 0
			isExpired = true
		}
	} else if sub.Status == SubExpired {
		isExpired = true
	}

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{
		"subscription": sub,
		"trial": map[string]any{
			"daysRemaining": daysRemaining,
			"isExpired":     isExpired,
		},
	})
}

type assignPlanRequest struct {
	NurseryID string `json:"nurseryId"`
	PlanID    string `json:"planId"` // "standard", "premium", "payg", "trial"
}

// assignNurseryPlan — POST /assignNurseryPlan. Admin only.
func assignNurseryPlan(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		httpjson.WriteError(w, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "POST required")
		return
	}

	ctx := r.Context()
	if !isAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "FORBIDDEN", "Admin claim required")
		return
	}

	var req assignPlanRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	if req.NurseryID == "" || req.PlanID == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "MISSING_FIELDS", "nurseryId and planId are required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	callerUID := auth.UID(ctx)
	now := time.Now().UTC()

	planName := "Custom Plan"
	for _, p := range defaultPlans() {
		if p.ID == req.PlanID {
			planName = p.Name
			break
		}
	}

	status := SubActive
	if req.PlanID == "trial" {
		status = SubTrialing
	}

	sub := NurserySubscription{
		NurseryID:          req.NurseryID,
		PlanID:             req.PlanID,
		PlanName:           planName,
		Status:             status,
		CurrentPeriodStart: now,
		CurrentPeriodEnd:   now.Add(30 * 24 * time.Hour),
		PaymentMethod:      "bank_transfer",
		AssignedByAdmin:    true,
		UpdatedAt:          now,
	}

	subRef := db.Collection("subscriptions").Doc(req.NurseryID)
	if _, err := subRef.Set(ctx, sub); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	_ = outbox.WriteTx(nil, db, outbox.Event{
		Topic: topicSubscriptionUpdate,
		Payload: map[string]any{
			"nurseryId": req.NurseryID,
			"planId":    req.PlanID,
			"status":    string(status),
		},
	})

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:    "subscription.assign_plan",
		ActorUID:  callerUID,
		TargetUID: req.NurseryID,
		Metadata: map[string]any{
			"planId": req.PlanID,
			"status": string(status),
		},
	})

	httpjson.WriteJSON(w, http.StatusOK, sub)
}

// generateWeeklyInvoices — POST /generateWeeklyInvoices. Admin / Finance only.
// Gathers un-invoiced approved timesheets, creates sequential invoices with separate staffing lines.
func generateWeeklyInvoices(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		httpjson.WriteError(w, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "POST required")
		return
	}

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

	// Check if VAT number is published in company config (Decision 4)
	vatPublished := false
	compDoc, err := db.Collection("platformConfig").Doc("company").Get(ctx)
	if err == nil {
		var comp CompanyConfig
		if compDoc.DataTo(&comp) == nil {
			if comp.VATNumber.Published && comp.VATNumber.Value != "" {
				vatPublished = true
			}
		}
	}

	// Query approved timesheets without an invoice
	tsDocs, err := db.Collection("timesheets").
		Where("status", "in", []string{string(TimesheetApproved), string(TimesheetAdminApproved)}).
		Documents(ctx).GetAll()

	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	// Filter un-invoiced and group by nursery
	nurseryTimesheets := make(map[string][]Timesheet)
	for _, doc := range tsDocs {
		var ts Timesheet
		if err := doc.DataTo(&ts); err != nil {
			continue
		}
		ts.ID = doc.Ref.ID
		// Skip if already invoiced
		if doc.Data()["invoiceId"] != nil && doc.Data()["invoiceId"] != "" {
			continue
		}
		nurseryTimesheets[ts.NurseryID] = append(nurseryTimesheets[ts.NurseryID], ts)
	}

	callerUID := auth.UID(ctx)
	now := time.Now().UTC()
	var createdInvoices []Invoice

	for nurseryID, timesheets := range nurseryTimesheets {
		// Fetch nursery billing profile
		var nurseryName = "Nursery " + nurseryID[:min(6, len(nurseryID))]
		var billingAddr, billingEmail, companyNum string

		pDoc, err := db.Collection("profiles").Doc(nurseryID).Get(ctx)
		if err == nil {
			data := pDoc.Data()
			if n, ok := data["displayName"].(string); ok && n != "" {
				nurseryName = n
			} else if fn, ok := data["name"].(string); ok && fn != "" {
				nurseryName = fn
			}
			if addr, ok := data["billingAddress"].(string); ok {
				billingAddr = addr
			}
			if em, ok := data["billingEmail"].(string); ok {
				billingEmail = em
			}
			if cnum, ok := data["companyNumber"].(string); ok {
				companyNum = cnum
			}
		}

		invoiceNum, err := GenerateNextInvoiceNumber(ctx, db, now.Year())
		if err != nil {
			slog.Error("generateWeeklyInvoices: invoice counter error", "error", err)
			continue
		}

		var lineItems []InvoiceLineItem
		var tsIDs []string

		for _, ts := range timesheets {
			tsIDs = append(tsIDs, ts.ID)
			hours := float64(ts.BillableMinutes) / 60.0
			ratePence := ts.NurseryHourlyRatePence
			lineItems = append(lineItems, InvoiceLineItem{
				Type:        "staffing",
				Description: fmt.Sprintf("Staffing: %.1f hrs @ £%.2f/hr (Shift %s)", hours, float64(ratePence)/100.0, ts.ShiftID),
				Quantity:    hours,
				UnitPence:   ratePence,
				TotalPence:  ts.TotalNurseryChargePence,
				TimesheetID: ts.ID,
				ShiftID:     ts.ShiftID,
			})
		}

		subtotal, vatRate, vatPence, total := CalculateInvoiceAmounts(lineItems, vatPublished)

		invID := fmt.Sprintf("inv_%s_%s", now.Format("20060102"), invoiceNum)
		inv := Invoice{
			ID:             invID,
			InvoiceNumber:  invoiceNum,
			NurseryID:      nurseryID,
			NurseryName:    nurseryName,
			BillingAddress: billingAddr,
			BillingEmail:   billingEmail,
			CompanyNumber:  companyNum,
			IssueDate:      now,
			DueDate:        now.Add(7 * 24 * time.Hour), // 7-day payment terms
			Status:         InvoiceIssued,
			Type:           "weekly_staffing",
			LineItems:      lineItems,
			SubtotalPence:  subtotal,
			VATRate:        vatRate,
			VATPence:       vatPence,
			TotalPence:     total,
			PaymentMethod:  "bank_transfer",
			CreatedAt:      now,
			UpdatedAt:      now,
		}

		batch := db.Batch()
		batch.Set(db.Collection("invoices").Doc(invID), inv)

		// Mark each timesheet as invoiced
		for _, tsID := range tsIDs {
			batch.Update(db.Collection("timesheets").Doc(tsID), []firestore.Update{
				{Path: "invoiceId", Value: invID},
				{Path: "updatedAt", Value: now},
			})
		}

		if _, err := batch.Commit(ctx); err == nil {
			createdInvoices = append(createdInvoices, inv)
			_ = outbox.WriteTx(nil, db, outbox.Event{
				Topic: topicInvoiceGenerated,
				Payload: map[string]any{
					"invoiceId":     invID,
					"invoiceNumber": invoiceNum,
					"nurseryId":     nurseryID,
					"totalPence":    total,
				},
			})
		}
	}

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:   "invoices.generate_weekly",
		ActorUID: callerUID,
		Metadata: map[string]any{
			"invoicesCreated": len(createdInvoices),
		},
	})

	if createdInvoices == nil {
		createdInvoices = []Invoice{}
	}
	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"invoices": createdInvoices})
}

// listInvoices — GET /listInvoices?nurseryId=...&status=...
func listInvoices(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	callerUID := auth.UID(ctx)
	targetNurseryID := r.URL.Query().Get("nurseryId")

	if targetNurseryID != "" && targetNurseryID != callerUID && !isAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "FORBIDDEN", "Cannot view other nurseries' invoices")
		return
	}
	if targetNurseryID == "" && !isAdmin(ctx) {
		targetNurseryID = callerUID
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	q := db.Collection("invoices").Query
	if targetNurseryID != "" {
		q = q.Where("nurseryId", "==", targetNurseryID)
	}
	if st := r.URL.Query().Get("status"); st != "" {
		q = q.Where("status", "==", st)
	}
	q = q.Limit(50)

	iter := q.Documents(ctx)
	var invoices []Invoice
	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		var inv Invoice
		if err := doc.DataTo(&inv); err == nil {
			inv.ID = doc.Ref.ID
			invoices = append(invoices, inv)
		}
	}

	if invoices == nil {
		invoices = []Invoice{}
	}
	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"invoices": invoices})
}

// getInvoice — GET /getInvoice?invoiceId=...
func getInvoice(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	callerUID := auth.UID(ctx)
	invoiceID := r.URL.Query().Get("invoiceId")
	if invoiceID == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "MISSING_INVOICE_ID", "invoiceId is required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	doc, err := db.Collection("invoices").Doc(invoiceID).Get(ctx)
	if err != nil {
		if status.Code(err) == codes.NotFound {
			httpjson.WriteError(w, http.StatusNotFound, "NOT_FOUND", "Invoice not found")
			return
		}
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	var inv Invoice
	_ = doc.DataTo(&inv)
	inv.ID = doc.Ref.ID

	if inv.NurseryID != callerUID && !isAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "FORBIDDEN", "Not authorized to view this invoice")
		return
	}

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"invoice": inv})
}

type markInvoicePaidRequest struct {
	InvoiceID        string `json:"invoiceId"`
	PaymentReference string `json:"paymentReference"`
	Notes            string `json:"notes,omitempty"`
}

// markInvoicePaid — POST /markInvoicePaid. Admin only (bank transfer reconciliation).
func markInvoicePaid(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		httpjson.WriteError(w, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "POST required")
		return
	}

	ctx := r.Context()
	if !isAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "FORBIDDEN", "Admin claim required")
		return
	}

	var req markInvoicePaidRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	if req.InvoiceID == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "MISSING_INVOICE_ID", "invoiceId is required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	now := time.Now().UTC()
	invRef := db.Collection("invoices").Doc(req.InvoiceID)

	_, err = invRef.Update(ctx, []firestore.Update{
		{Path: "status", Value: InvoicePaid},
		{Path: "paidAt", Value: now},
		{Path: "paymentReference", Value: req.PaymentReference},
		{Path: "notes", Value: req.Notes},
		{Path: "updatedAt", Value: now},
	})
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	_ = outbox.WriteTx(nil, db, outbox.Event{
		Topic: topicInvoicePaid,
		Payload: map[string]any{
			"invoiceId":        req.InvoiceID,
			"paymentReference": req.PaymentReference,
			"paidAt":           now,
		},
	})

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:    "invoice.mark_paid",
		ActorUID:  auth.UID(ctx),
		TargetDoc: req.InvoiceID,
		Metadata: map[string]any{
			"invoiceId":        req.InvoiceID,
			"paymentReference": req.PaymentReference,
		},
	})

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"status": "paid", "paidAt": now})
}

type createLedgerEntryRequest struct {
	NurseryID   string `json:"nurseryId"`
	Type        string `json:"type"` // "discount", "refund", "credit"
	AmountPence int64  `json:"amountPence"`
	Reason      string `json:"reason"`
	InvoiceID   string `json:"invoiceId,omitempty"`
}

// createLedgerEntry — POST /createLedgerEntry. Admin only.
// Records discounts, refunds and credits without money movement (Phase 9 item 5).
func createLedgerEntry(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		httpjson.WriteError(w, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "POST required")
		return
	}

	ctx := r.Context()
	if !isAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "FORBIDDEN", "Admin claim required")
		return
	}

	var req createLedgerEntryRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	if req.NurseryID == "" || req.AmountPence <= 0 || req.Reason == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "INVALID_FIELDS", "nurseryId, positive amountPence and reason are required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	callerUID := auth.UID(ctx)
	now := time.Now().UTC()

	entry := LedgerEntry{
		NurseryID:   req.NurseryID,
		Type:        req.Type,
		AmountPence: req.AmountPence,
		Reason:      req.Reason,
		InvoiceID:   req.InvoiceID,
		ActorUID:    callerUID,
		CreatedAt:   now,
	}

	docRef, _, err := db.Collection("ledger").Add(ctx, entry)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}
	entry.ID = docRef.ID

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:    "ledger.create_entry",
		ActorUID:  callerUID,
		TargetUID: req.NurseryID,
		Metadata: map[string]any{
			"type":        req.Type,
			"amountPence": req.AmountPence,
			"reason":      req.Reason,
		},
	})

	httpjson.WriteJSON(w, http.StatusOK, entry)
}
