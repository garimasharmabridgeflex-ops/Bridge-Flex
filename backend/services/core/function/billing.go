package function

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"math"
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
	functions.HTTP("GetAdminPlans", authed(getAdminPlans))
	functions.HTTP("UpsertPlan", authed(upsertPlan))
	functions.HTTP("GetNurserySubscription", authed(getNurserySubscription))
	functions.HTTP("AssignNurseryPlan", authed(assignNurseryPlan))
	functions.HTTP("RequestPlanChange", authed(requestPlanChange))
	functions.HTTP("CancelSubscription", authed(cancelSubscription))
	functions.HTTP("ListSubscriptionRequests", authed(listSubscriptionRequests))
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
// findPlan resolves an active plan from Firestore, falling back to the seeded
// defaults when the plans collection has not been created yet. A plan id that
// exists but is inactive is treated as unavailable.
func findPlan(ctx context.Context, db *firestore.Client, planID string) (*Plan, error) {
	if db != nil {
		snap, err := db.Collection("plans").Doc(planID).Get(ctx)
		if err == nil {
			var p Plan
			if err := snap.DataTo(&p); err != nil {
				return nil, err
			}
			p.ID = snap.Ref.ID
			if !p.Active {
				return nil, nil
			}
			return &p, nil
		}
		if status.Code(err) != codes.NotFound {
			return nil, err
		}
	}
	for _, p := range defaultPlans() {
		if p.ID == planID && p.Active {
			plan := p
			return &plan, nil
		}
	}
	return nil, nil
}

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

// getPlans — GET /getPlans. Public / authenticated; intentionally exposes active plans only.
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

// getAdminPlans — GET /getAdminPlans. Admin-only view including inactive
// plans so administrators can manage plans without making hidden plans public.
func getAdminPlans(w http.ResponseWriter, r *http.Request) {
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

	docs, err := db.Collection("plans").Documents(ctx).GetAll()
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}
	plans := make([]Plan, 0, len(docs))
	for _, doc := range docs {
		var plan Plan
		if err := doc.DataTo(&plan); err != nil {
			continue
		}
		plan.ID = doc.Ref.ID
		plans = append(plans, plan)
	}
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

// nurseryApprovalSatisfied treats an empty status as approved. Every nursery
// that existed before the approval workflow was grandfathered on purpose
// (plan rule 6.1.5); only nurseries that chose the nursery role after the
// workflow shipped carry pending_approval.
func nurseryApprovalSatisfied(p Profile) bool {
	return p.NurseryApprovalStatus == "" || p.NurseryApprovalStatus == NurseryApproved
}

const trialDuration = 14 * 24 * time.Hour

// ensureTrialSubscription returns the nursery's subscription, creating the
// single free trial only once the nursery is approved and activated. It never
// writes a trial for an unapproved nursery, and never issues a second trial
// for the same company number.
func ensureTrialSubscription(ctx context.Context, db *firestore.Client, nurseryID string) (*NurserySubscription, error) {
	pSnap, err := db.Collection("profiles").Doc(nurseryID).Get(ctx)
	if err != nil {
		return nil, err
	}
	var p Profile
	if err := pSnap.DataTo(&p); err != nil {
		return nil, err
	}
	if p.Role != RoleNursery {
		return nil, fmt.Errorf("NOT_A_NURSERY")
	}

	now := time.Now().UTC()
	subRef := db.Collection("subscriptions").Doc(nurseryID)
	if snap, err := subRef.Get(ctx); err == nil {
		var sub NurserySubscription
		if err := snap.DataTo(&sub); err != nil {
			return nil, err
		}
		return &sub, nil
	} else if status.Code(err) != codes.NotFound {
		return nil, err
	}

	if !nurseryApprovalSatisfied(p) {
		return &NurserySubscription{
			NurseryID:     nurseryID,
			CompanyNumber: p.CompanyNumber,
			PlanID:        "none",
			PlanName:      "Awaiting approval",
			Status:        SubPending,
			PaymentMethod: "none",
			UpdatedAt:     now,
		}, nil
	}

	// Grandfathered nurseries (empty approval status) may predate the
	// activationDate field. They are approved by definition (plan rule
	// 6.1.5), so stamp activation now rather than leaving them with no trial
	// and a permanently "pending" subscription.
	if p.ActivationDate == nil {
		p.ActivationDate = &now
		if _, err := db.Collection("profiles").Doc(nurseryID).Set(ctx,
			map[string]any{"activationDate": now}, firestore.MergeAll); err != nil {
			return nil, err
		}
	}

	// One trial per company number. If this company has already had a trial on
	// another nursery account, no second trial is issued.
	if p.CompanyNumber != "" {
		iter := db.Collection("subscriptions").Where("companyNumber", "==", p.CompanyNumber).Limit(1).Documents(ctx)
		_, foundErr := iter.Next()
		iter.Stop()
		if foundErr == nil {
			return &NurserySubscription{
				NurseryID:        nurseryID,
				CompanyNumber:    p.CompanyNumber,
				PlanID:           "none",
				PlanName:         "Trial already used",
				Status:           SubExpired,
				CurrentPeriodEnd: now,
				PaymentMethod:    "none",
				UpdatedAt:        now,
			}, nil
		}
	}

	start := *p.ActivationDate
	end := start.Add(trialDuration)
	sub := NurserySubscription{
		NurseryID:          nurseryID,
		CompanyNumber:      p.CompanyNumber,
		PlanID:             "trial",
		PlanName:           "Free Trial",
		Status:             SubTrialing,
		TrialStartDate:     &start,
		TrialEndDate:       &end,
		CurrentPeriodStart: start,
		CurrentPeriodEnd:   end,
		PaymentMethod:      "none",
		UpdatedAt:          now,
	}
	if _, err := subRef.Set(ctx, sub); err != nil {
		return nil, err
	}
	_ = notifyInApp(ctx, db, nurseryID, "trial_started", "Your 14-day free trial has started",
		fmt.Sprintf("Your trial runs until %s. Staffing hours are billed separately.", end.Format("2 Jan 2006")),
		map[string]any{"trialEndDate": end.Format(time.RFC3339)})
	return &sub, nil
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

	sub, err := ensureTrialSubscription(ctx, db, targetNurseryID)
	if err != nil {
		if status.Code(err) == codes.NotFound || err.Error() == "NOT_A_NURSERY" {
			httpjson.WriteError(w, http.StatusNotFound, "SUBSCRIPTION_NOT_FOUND", "No nursery subscription for this account")
			return
		}
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	now := time.Now().UTC()
	// Persist the two lifecycle transitions the server owns. There is no
	// automatic charging at launch: an ended paid period becomes past_due for
	// an admin to reconcile, never silently cancelled.
	if sub.Status == SubTrialing && sub.TrialEndDate != nil && now.After(*sub.TrialEndDate) {
		sub.Status = SubExpired
		_, _ = db.Collection("subscriptions").Doc(targetNurseryID).Set(ctx,
			map[string]any{"status": SubExpired, "updatedAt": now}, firestore.MergeAll)
	} else if sub.Status == SubActive && !sub.CurrentPeriodEnd.IsZero() && now.After(sub.CurrentPeriodEnd) {
		if sub.CancelAtPeriodEnd {
			sub.Status = SubCancelled
		} else {
			sub.Status = SubPastDue
		}
		_, _ = db.Collection("subscriptions").Doc(targetNurseryID).Set(ctx,
			map[string]any{"status": sub.Status, "updatedAt": now}, firestore.MergeAll)
	}

	daysRemaining := 0
	isExpired := sub.Status == SubExpired
	if sub.Status == SubTrialing && sub.TrialEndDate != nil && now.Before(*sub.TrialEndDate) {
		daysRemaining = int(math.Ceil(sub.TrialEndDate.Sub(now).Hours() / 24))
	}
	if sub.Status == SubCancelled {
		isExpired = true
	}

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{
		"subscription": sub,
		"trial": map[string]any{
			"daysRemaining": daysRemaining,
			"isExpired":     isExpired,
			// Lets the client mirror the server's enforcement instead of
			// hard-coding its own trial rule.
			"gate": string(GetGateMode(ctx, db, "trialExpired")),
		},
	})
}

type requestPlanChangeRequest struct {
	PlanID string `json:"planId"`
	Note   string `json:"note,omitempty"`
}

// requestPlanChange lets a nursery ask to move plan without taking any
// payment. An admin assigns the plan; until then the current plan stays.
func requestPlanChange(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		httpjson.WriteError(w, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "POST required")
		return
	}
	ctx := r.Context()
	uid := auth.UID(ctx)

	var req requestPlanChangeRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	if req.PlanID == "" || req.PlanID == "trial" {
		httpjson.WriteError(w, http.StatusBadRequest, "INVALID_PLAN", "Choose a paid plan or Pay As You Go")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}
	if err := requireRole(ctx, db, uid, RoleNursery); err != nil {
		writeRoleError(w, err)
		return
	}

	plan, err := findPlan(ctx, db, req.PlanID)
	if err != nil || plan == nil {
		httpjson.WriteError(w, http.StatusBadRequest, "INVALID_PLAN", "That plan is not available")
		return
	}

	if _, err := ensureTrialSubscription(ctx, db, uid); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	now := time.Now().UTC()
	if _, err := db.Collection("subscriptions").Doc(uid).Set(ctx, map[string]any{
		"requestedPlanId": req.PlanID,
		"requestedAt":     now,
		"requestNote":     req.Note,
		"updatedAt":       now,
	}, firestore.MergeAll); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:    "subscription.request_plan_change",
		TargetUID: uid,
		Metadata:  map[string]any{"planId": req.PlanID},
	})
	_ = notifyInApp(ctx, db, uid, "plan_change_requested", "Plan change requested",
		"Our team will confirm your move to "+plan.Name+". No payment has been taken.",
		map[string]any{"planId": req.PlanID})

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{
		"status":          "requested",
		"requestedPlanId": req.PlanID,
	})
}

// cancelSubscription stops future renewals. It never deletes completed
// bookings or outstanding invoices, and no refund is issued automatically.
func cancelSubscription(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		httpjson.WriteError(w, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "POST required")
		return
	}
	ctx := r.Context()
	uid := auth.UID(ctx)

	var req struct {
		Reason string `json:"reason,omitempty"`
	}
	_ = httpjson.DecodeJSON(w, r, &req)

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}
	if err := requireRole(ctx, db, uid, RoleNursery); err != nil {
		writeRoleError(w, err)
		return
	}

	sub, err := ensureTrialSubscription(ctx, db, uid)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}
	now := time.Now().UTC()
	updates := map[string]any{
		"cancelAtPeriodEnd": true,
		"cancelledAt":       now,
		"updatedAt":         now,
	}
	// A trial or a pending account has nothing to renew, so cancellation is
	// effective immediately. A paid plan runs to the end of its period.
	if sub.Status != SubActive {
		updates["status"] = SubCancelled
	}
	if _, err := db.Collection("subscriptions").Doc(uid).Set(ctx, updates, firestore.MergeAll); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:    "subscription.cancel",
		TargetUID: uid,
		Metadata:  map[string]any{"reason": req.Reason},
	})
	_ = notifyInApp(ctx, db, uid, "subscription_cancelled", "Subscription cancellation recorded",
		"Future renewals have been stopped. Existing bookings and invoices are unaffected.", nil)

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{
		"status":            updates["status"],
		"cancelAtPeriodEnd": true,
	})
}

// listSubscriptionRequests — admin view of nurseries waiting for a plan.
func listSubscriptionRequests(w http.ResponseWriter, r *http.Request) {
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

	docs, err := db.Collection("subscriptions").Documents(ctx).GetAll()
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}
	out := []map[string]any{}
	for _, doc := range docs {
		var sub NurserySubscription
		if err := doc.DataTo(&sub); err != nil || sub.RequestedPlanID == "" {
			continue
		}
		name := ""
		if pSnap, err := db.Collection("profiles").Doc(sub.NurseryID).Get(ctx); err == nil {
			name, _ = pSnap.Data()["name"].(string)
		}
		out = append(out, map[string]any{
			"nurseryId":       sub.NurseryID,
			"nurseryName":     name,
			"currentPlanId":   sub.PlanID,
			"requestedPlanId": sub.RequestedPlanID,
			"requestedAt":     sub.RequestedAt,
			"note":            sub.RequestNote,
		})
	}
	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"requests": out})
}

type assignPlanRequest struct {
	NurseryID string `json:"nurseryId"`
	PlanID    string `json:"planId"` // "standard", "premium", "payg", "trial"
}

// assignNurseryPlan — POST /assignNurseryPlan. Admin only.
// Assigning a plan records the membership state. No payment is collected and
// no card is charged: invoicing stays manual until a payment provider exists.
func assignNurseryPlan(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		httpjson.WriteError(w, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "POST required")
		return
	}

	ctx := r.Context()
	if !isFinanceOrSuperAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "FORBIDDEN", "Finance or SuperAdmin claim required")
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

	if err := requireRole(ctx, db, req.NurseryID, RoleNursery); err != nil {
		httpjson.WriteError(w, http.StatusBadRequest, "NOT_A_NURSERY", "That account is not a nursery")
		return
	}

	plan, err := findPlan(ctx, db, req.PlanID)
	if err != nil || plan == nil {
		httpjson.WriteError(w, http.StatusBadRequest, "INVALID_PLAN", "planId is not a known plan")
		return
	}

	subRef := db.Collection("subscriptions").Doc(req.NurseryID)
	var existing NurserySubscription
	hasExisting := false
	if snap, err := subRef.Get(ctx); err == nil {
		_ = snap.DataTo(&existing)
		hasExisting = true
	}

	now := time.Now().UTC()
	status := SubActive
	paymentMethod := "none"
	periodDays := 30
	if plan.BillingInterval == "per_booking" {
		paymentMethod = "payg"
	}

	sub := NurserySubscription{
		NurseryID:          req.NurseryID,
		PlanID:             plan.ID,
		PlanName:           plan.Name,
		Status:             status,
		CurrentPeriodStart: now,
		CurrentPeriodEnd:   now.AddDate(0, 0, periodDays),
		PaymentMethod:      paymentMethod,
		AssignedByAdmin:    true,
		UpdatedAt:          now,
	}
	if hasExisting {
		sub.CompanyNumber = existing.CompanyNumber
		sub.TrialStartDate = existing.TrialStartDate
		sub.TrialEndDate = existing.TrialEndDate
	}

	if plan.ID == "trial" {
		// A trial can be re-assigned only before one has ever started.
		if hasExisting && existing.TrialStartDate != nil {
			httpjson.WriteError(w, http.StatusConflict, "TRIAL_ALREADY_USED", "This nursery has already used its free trial")
			return
		}
		start := now
		end := now.Add(trialDuration)
		sub.Status = SubTrialing
		sub.TrialStartDate = &start
		sub.TrialEndDate = &end
		sub.CurrentPeriodStart = start
		sub.CurrentPeriodEnd = end
	}

	if _, err := subRef.Set(ctx, sub); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:    "subscription.assign_plan",
		ActorUID:  auth.UID(ctx),
		TargetUID: req.NurseryID,
		Metadata: map[string]any{
			"planId": plan.ID,
			"status": string(sub.Status),
		},
	})
	_ = notifyInApp(ctx, db, req.NurseryID, "subscription_updated", "Membership updated",
		"Your nursery is now on "+plan.Name+". No payment has been taken in the app.",
		map[string]any{"planId": plan.ID})
	sendTransactionalEmail(ctx, db, req.NurseryID, "subscription_updated",
		map[string]string{"planName": plan.Name}, true)

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
			// Essential mail (owner brief §12 "invoice generated"): a nursery
			// must not find out about money it owes only by opening the app.
			sendTransactionalEmail(ctx, db, nurseryID, "invoice_generated",
				map[string]string{
					"invoiceNumber": invoiceNum,
					"total":         fmt.Sprintf("£%d.%02d", total/100, total%100),
				}, true)
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
	NurseryID    string `json:"nurseryId"`
	Type         string `json:"type"` // "discount", "refund", "credit"
	AmountPence  int64  `json:"amountPence"`
	Reason       string `json:"reason"`
	InvoiceID    string `json:"invoiceId,omitempty"`
	DiscountCode string `json:"discountCode,omitempty"` // optional, validated when type is "discount"
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

	// A discount with a code behind it is redeemed in the same transaction as
	// the ledger write, so a code can never be counted twice or redeemed after
	// it expired or hit its cap.
	if req.DiscountCode != "" {
		if req.Type != "discount" {
			httpjson.WriteError(w, http.StatusBadRequest, "INVALID_DISCOUNT", "discountCode is only valid when type is \"discount\"")
			return
		}
		err = db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
			dc, err := redeemDiscount(ctx, tx, db, req.DiscountCode)
			if err != nil {
				return err
			}
			entry.DiscountCode = dc.Code
			ref := db.Collection("ledger").NewDoc()
			if err := tx.Set(ref, entry); err != nil {
				return err
			}
			entry.ID = ref.ID
			return nil
		})
		if err != nil {
			if errors.Is(err, errDiscountCodeNotFound) || errors.Is(err, errDiscountCodeInactive) ||
				errors.Is(err, errDiscountCodeExpired) || errors.Is(err, errDiscountCodeExhausted) {
				httpjson.WriteError(w, http.StatusBadRequest, err.Error(), "Discount code could not be applied")
				return
			}
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
	} else {
		docRef, _, err := db.Collection("ledger").Add(ctx, entry)
		if err != nil {
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		entry.ID = docRef.ID
	}

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:    "ledger.create_entry",
		ActorUID:  callerUID,
		TargetUID: req.NurseryID,
		Metadata: map[string]any{
			"type":         entry.Type,
			"amountPence":  req.AmountPence,
			"reason":       req.Reason,
			"discountCode": entry.DiscountCode,
		},
	})

	httpjson.WriteJSON(w, http.StatusOK, entry)
}
