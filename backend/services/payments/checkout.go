package function

import (
	"context"
	"errors"
	"net/http"
	"net/url"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/GoogleCloudPlatform/functions-framework-go/functions"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"kvision.internal/shared/auth"
	"kvision.internal/shared/httpjson"
)

func init() {
	functions.HTTP("CreateSubscriptionCheckout", authed(createSubscriptionCheckout))
	functions.HTTP("CreateBillingPortalSession", authed(createBillingPortalSession))
}

var (
	errPlanNotPurchasable = errors.New("that plan cannot be purchased")
	errPlanNotConfigured  = errors.New("that plan has no Stripe price configured")
)

type checkoutRequest struct {
	PlanID string `json:"planId"`
}

// checkoutResult is what a checkout attempt produced: either a hosted Stripe
// page to open, or an in-place change to an existing subscription.
type checkoutResult struct {
	URL       string
	SessionID string
	Mode      string
	PlanID    string
	Updated   bool
}

// createSubscriptionCheckout starts a hosted Stripe Checkout Session for a
// nursery plan. No card data ever reaches KFlex: the customer pays on
// Stripe's page, and the resulting subscription state arrives back through
// StripeWebhook.
func createSubscriptionCheckout(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		httpjson.WriteError(w, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "POST required")
		return
	}
	ctx := r.Context()
	uid := auth.UID(ctx)

	var req checkoutRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	if req.PlanID == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "MISSING_FIELDS", "planId is required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}
	if err := requireNursery(ctx, db, uid); err != nil {
		httpjson.WriteError(w, http.StatusForbidden, "WRONG_ROLE", "Only a nursery account can start a membership checkout")
		return
	}
	client, err := newStripeClient()
	if err != nil {
		httpjson.WriteError(w, http.StatusServiceUnavailable, "PAYMENTS_NOT_CONFIGURED", "Card payments are not configured yet")
		return
	}

	result, err := startCheckout(ctx, db, client, uid, req.PlanID)
	if err != nil {
		writeCheckoutError(w, err)
		return
	}

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{
		"url":            result.URL,
		"sessionId":      result.SessionID,
		"mode":           result.Mode,
		"planId":         result.PlanID,
		"updated":        result.Updated,
		"checkoutNeeded": !result.Updated,
	})
}

func writeCheckoutError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, errNotNursery):
		httpjson.WriteError(w, http.StatusForbidden, "WRONG_ROLE", "Only a nursery account can start a membership checkout")
	case errors.Is(err, errPlanNotPurchasable):
		httpjson.WriteError(w, http.StatusBadRequest, "INVALID_PLAN", err.Error())
	case errors.Is(err, errPlanNotConfigured):
		httpjson.WriteError(w, http.StatusServiceUnavailable, "PLAN_NOT_CONFIGURED", err.Error())
	default:
		httpjson.WriteError(w, http.StatusBadGateway, "STRIPE_ERROR", err.Error())
	}
}

// startCheckout does the actual work, separated from the HTTP/auth plumbing so
// it can be exercised against a real Stripe sandbox account in tests.
//
// If the nursery already has a live Stripe subscription, this switches that
// subscription's price instead of creating a second one (Stripe prorates the
// difference), so plan changes are one click rather than a duplicate billing
// relationship.
func startCheckout(ctx context.Context, db *firestore.Client, client *stripeClient, uid, planID string) (*checkoutResult, error) {
	plan, err := findPlan(ctx, db, planID)
	if err != nil {
		return nil, err
	}
	if plan == nil || plan.BillingInterval == "none" || plan.PricePence == 0 {
		return nil, errPlanNotPurchasable
	}
	priceID := stripePriceIDFor(plan.ID, plan.StripePriceID)
	if priceID == "" {
		return nil, errPlanNotConfigured
	}

	subData := map[string]any{}
	if snap, err := db.Collection("subscriptions").Doc(uid).Get(ctx); err == nil {
		subData = snap.Data()
	} else if status.Code(err) != codes.NotFound {
		return nil, err
	}

	customerID, _ := subData["stripeCustomerId"].(string)
	existingPriceID, _ := subData["stripePriceId"].(string)
	existingSubID, _ := subData["stripeSubscriptionId"].(string)
	existingStatus, _ := subData["status"].(string)

	if existingSubID != "" && plan.BillingInterval == "month" && existingPriceID != priceID &&
		existingStatus != "cancelled" && existingStatus != "expired" {
		result, handled, err := switchExistingSubscription(ctx, db, client, uid, plan, priceID, existingSubID)
		if err != nil {
			return nil, err
		}
		if handled {
			return result, nil
		}
	}

	if customerID == "" {
		email := ""
		name := ""
		if pSnap, err := db.Collection("profiles").Doc(uid).Get(ctx); err == nil {
			email, _ = pSnap.Data()["email"].(string)
			name, _ = pSnap.Data()["name"].(string)
		}
		params := url.Values{}
		if email != "" {
			params.Set("email", email)
		}
		params.Set("description", strings.TrimSpace("KFlex nursery "+name))
		params.Set("metadata[nurseryId]", uid)
		var cust stripeCustomer
		if err := client.post(ctx, "/customers", params, &cust); err != nil {
			return nil, err
		}
		customerID = cust.ID
		if _, err := db.Collection("subscriptions").Doc(uid).Set(ctx, map[string]any{
			"nurseryId":        uid,
			"stripeCustomerId": customerID,
			"updatedAt":        time.Now().UTC(),
		}, firestore.MergeAll); err != nil {
			return nil, err
		}
	}

	mode := "subscription"
	if plan.BillingInterval == "per_booking" {
		mode = "payment"
	}

	params := url.Values{}
	params.Set("mode", mode)
	params.Set("customer", customerID)
	params.Set("client_reference_id", uid)
	params.Set("line_items[0][price]", priceID)
	params.Set("line_items[0][quantity]", "1")
	params.Set("success_url", checkoutReturnURL("SUCCESS"))
	params.Set("cancel_url", checkoutReturnURL("CANCEL"))
	params.Set("allow_promotion_codes", "true")
	params.Set("metadata[nurseryId]", uid)
	params.Set("metadata[planId]", plan.ID)
	if mode == "subscription" {
		params.Set("subscription_data[metadata][nurseryId]", uid)
		params.Set("subscription_data[metadata][planId]", plan.ID)
		params.Set("subscription_data[description]", "KFlex "+plan.Name)
	} else {
		params.Set("payment_intent_data[metadata][nurseryId]", uid)
		params.Set("payment_intent_data[metadata][planId]", plan.ID)
	}

	var session stripeCheckoutSession
	if err := client.post(ctx, "/checkout/sessions", params, &session); err != nil {
		return nil, err
	}

	return &checkoutResult{
		URL:       session.URL,
		SessionID: session.ID,
		Mode:      session.Mode,
		PlanID:    plan.ID,
	}, nil
}

// switchExistingSubscription retunes a live subscription's price in place.
// handled=false means the Stripe subscription is no longer switchable (already
// canceled or without items), so the caller should fall through to checkout.
func switchExistingSubscription(ctx context.Context, db *firestore.Client, client *stripeClient, uid string, plan *planInfo, priceID, existingSubID string) (*checkoutResult, bool, error) {
	var current stripeSubscription
	if err := client.get(ctx, "/subscriptions/"+existingSubID, nil, &current); err != nil {
		return nil, false, err
	}
	if current.Status == "canceled" || current.Status == "incomplete_expired" || len(current.Items.Data) == 0 {
		return nil, false, nil
	}

	params := url.Values{}
	params.Set("items[0][id]", current.Items.Data[0].ID)
	params.Set("items[0][price]", priceID)
	params.Set("proration_behavior", "create_prorations")
	params.Set("cancel_at_period_end", "false")
	params.Set("metadata[nurseryId]", uid)
	params.Set("metadata[planId]", plan.ID)
	var updated stripeSubscription
	if err := client.post(ctx, "/subscriptions/"+existingSubID, params, &updated); err != nil {
		return nil, false, err
	}

	if _, err := db.Collection("subscriptions").Doc(uid).Set(ctx, map[string]any{
		"planId":             plan.ID,
		"planName":           plan.Name,
		"stripePriceId":      priceID,
		"status":             mapStripeStatus(updated.Status),
		"cancelAtPeriodEnd":  updated.CancelAtPeriodEnd,
		"currentPeriodStart": time.Unix(updated.CurrentPeriodStart, 0).UTC(),
		"currentPeriodEnd":   time.Unix(updated.CurrentPeriodEnd, 0).UTC(),
		"updatedAt":          time.Now().UTC(),
	}, firestore.MergeAll); err != nil {
		return nil, false, err
	}

	return &checkoutResult{PlanID: plan.ID, Updated: true}, true, nil
}

// createBillingPortalSession opens Stripe's hosted billing portal, where a
// nursery can update its card, download receipts, or cancel. Cancelling there
// is reflected back through customer.subscription.updated/deleted, so the app
// never holds card details and never needs a second cancel code path.
func createBillingPortalSession(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		httpjson.WriteError(w, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "POST required")
		return
	}
	ctx := r.Context()
	uid := auth.UID(ctx)

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}
	if err := requireNursery(ctx, db, uid); err != nil {
		httpjson.WriteError(w, http.StatusForbidden, "WRONG_ROLE", "Only a nursery account has billing to manage")
		return
	}

	portalURL, err := startPortalSession(ctx, db, uid)
	if err != nil {
		if errors.Is(err, errNoStripeCustomer) {
			httpjson.WriteError(w, http.StatusBadRequest, "NO_CUSTOMER", "Start a paid plan before managing billing")
			return
		}
		httpjson.WriteError(w, http.StatusBadGateway, "STRIPE_ERROR", err.Error())
		return
	}

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"url": portalURL})
}

var errNoStripeCustomer = errors.New("no stripe customer on file")

func startPortalSession(ctx context.Context, db *firestore.Client, uid string) (string, error) {
	snap, err := db.Collection("subscriptions").Doc(uid).Get(ctx)
	if err != nil {
		return "", errNoStripeCustomer
	}
	customerID, _ := snap.Data()["stripeCustomerId"].(string)
	if customerID == "" {
		return "", errNoStripeCustomer
	}
	client, err := newStripeClient()
	if err != nil {
		return "", err
	}

	params := url.Values{}
	params.Set("customer", customerID)
	params.Set("return_url", portalReturnURL())
	var portal stripePortalSession
	if err := client.post(ctx, "/billing_portal/sessions", params, &portal); err != nil {
		return "", err
	}
	return portal.URL, nil
}

// mapStripeStatus maps a Stripe subscription status onto the KFlex
// SubscriptionStatus vocabulary used everywhere else in the app.
func mapStripeStatus(s string) string {
	switch s {
	case "active", "trialing":
		return "active"
	case "past_due", "unpaid", "incomplete":
		return "past_due"
	case "canceled", "incomplete_expired":
		return "cancelled"
	default:
		return "pending"
	}
}
