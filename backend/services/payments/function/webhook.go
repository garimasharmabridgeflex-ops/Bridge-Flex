package function

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/GoogleCloudPlatform/functions-framework-go/functions"

	"kvision.internal/shared/httpjson"
)

func init() {
	functions.HTTP("StripeWebhook", stripeWebhook)
}

// stripeWebhook is Stripe's only entry point into KFlex. It is intentionally
// unauthenticated at the HTTP layer — Stripe cannot present a Firebase ID
// token — and is instead authenticated by the signature on every request:
// without the endpoint's signing secret the payload is rejected.
func stripeWebhook(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		httpjson.WriteError(w, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "POST required")
		return
	}
	payload, err := io.ReadAll(io.LimitReader(r.Body, 1<<20))
	if err != nil {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "Could not read webhook body")
		return
	}

	secret := os.Getenv("STRIPE_WEBHOOK_SECRET")
	if !verifyStripeSignature(payload, r.Header.Get("Stripe-Signature"), secret, time.Now()) {
		// Deliberately explicit: a missing STRIPE_WEBHOOK_SECRET (local run,
		// misconfigured deploy) fails closed rather than processing unsigned
		// events.
		slog.Warn("stripe webhook signature rejected", "headerPresent", r.Header.Get("Stripe-Signature") != "", "secretPresent", secret != "")
		httpjson.WriteError(w, http.StatusBadRequest, "INVALID_SIGNATURE", "Webhook signature verification failed")
		return
	}

	var evt stripeEvent
	if err := json.Unmarshal(payload, &evt); err != nil {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "Could not parse webhook event")
		return
	}

	ctx := r.Context()
	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	// Stripe retries on any non-2xx and may deliver the same event more than
	// once even after a 200. Every handler below is an idempotent merge, and
	// this marker short-circuits the whole event on a repeat delivery.
	eventRef := db.Collection("stripeEvents").Doc(evt.ID)
	if evt.ID != "" {
		if _, err := eventRef.Get(ctx); err == nil {
			httpjson.WriteJSON(w, http.StatusOK, map[string]any{"received": true, "duplicate": true})
			return
		}
	}

	handlerErr := dispatchStripeEvent(ctx, db, evt)
	if handlerErr != nil {
		// Non-2xx so Stripe retries; no marker is written, so the retry is
		// processed rather than swallowed as a duplicate.
		slog.Error("stripe webhook handler failed", "type", evt.Type, "event", evt.ID, "err", handlerErr)
		httpjson.WriteError(w, http.StatusInternalServerError, "WEBHOOK_HANDLING_FAILED", handlerErr.Error())
		return
	}

	if evt.ID != "" {
		_, _ = eventRef.Set(ctx, map[string]any{
			"id":         evt.ID,
			"type":       evt.Type,
			"receivedAt": time.Now().UTC(),
		})
	}

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"received": true})
}

func dispatchStripeEvent(ctx context.Context, db *firestore.Client, evt stripeEvent) error {
	switch evt.Type {
	case "checkout.session.completed", "checkout.session.async_payment_succeeded":
		var session stripeCheckoutSession
		if err := json.Unmarshal(evt.Data.Object, &session); err != nil {
			return err
		}
		return handleCheckoutCompleted(ctx, db, session)
	case "invoice.paid", "invoice.payment_succeeded":
		var inv stripeInvoice
		if err := json.Unmarshal(evt.Data.Object, &inv); err != nil {
			return err
		}
		return handleInvoicePaid(ctx, db, inv)
	case "invoice.payment_failed":
		var inv stripeInvoice
		if err := json.Unmarshal(evt.Data.Object, &inv); err != nil {
			return err
		}
		return handleInvoiceFailed(ctx, db, inv)
	case "customer.subscription.updated":
		var sub stripeSubscription
		if err := json.Unmarshal(evt.Data.Object, &sub); err != nil {
			return err
		}
		return handleSubscriptionChanged(ctx, db, sub, false)
	case "customer.subscription.deleted":
		var sub stripeSubscription
		if err := json.Unmarshal(evt.Data.Object, &sub); err != nil {
			return err
		}
		return handleSubscriptionChanged(ctx, db, sub, true)
	default:
		// Event types the endpoint is subscribed to but this service does not
		// act on yet must still be acknowledged, or Stripe disables it.
		slog.Info("stripe webhook ignored", "type", evt.Type, "event", evt.ID)
		return nil
	}
}

func handleCheckoutCompleted(ctx context.Context, db *firestore.Client, session stripeCheckoutSession) error {
	nurseryID := session.Metadata["nurseryId"]
	if nurseryID == "" {
		nurseryID = session.ClientReference
	}
	if nurseryID == "" {
		return errors.New("checkout session carries no nursery reference")
	}
	planID := session.Metadata["planId"]
	now := time.Now().UTC()

	if session.Mode == "payment" {
		// Pay As You Go: a one-off booking fee, not a recurring subscription.
		planName := "Pay As You Go"
		if p, err := findPlan(ctx, db, planID); err == nil && p != nil {
			planName = p.Name
		}
		if session.PaymentStatus != "paid" && session.PaymentStatus != "no_payment_required" {
			return nil
		}
		if _, err := db.Collection("subscriptions").Doc(nurseryID).Set(ctx, map[string]any{
			"nurseryId":           nurseryID,
			"planId":              planID,
			"planName":            planName,
			"status":              "active",
			"paymentMethod":       "stripe",
			"stripeCustomerId":    session.Customer,
			"stripePaymentIntent": session.PaymentIntent,
			"currentPeriodStart":  now,
			"currentPeriodEnd":    now.AddDate(0, 0, 30),
			"cancelAtPeriodEnd":   false,
			"updatedAt":           now,
		}, firestore.MergeAll); err != nil {
			return err
		}
		notifyNursery(ctx, db, nurseryID, "subscription_updated", "Payment received",
			fmt.Sprintf("%s is now active. Your £%.2f booking fee was paid by card.", planName, float64(session.AmountTotal)/100))
		return nil
	}

	if session.Subscription == "" {
		return errors.New("subscription-mode checkout session has no subscription id")
	}
	client, err := newStripeClient()
	if err != nil {
		return err
	}
	var sub stripeSubscription
	if err := client.get(ctx, "/subscriptions/"+session.Subscription, nil, &sub); err != nil {
		return err
	}
	return syncSubscription(ctx, db, nurseryID, sub, planID, true)
}

func handleInvoicePaid(ctx context.Context, db *firestore.Client, inv stripeInvoice) error {
	now := time.Now().UTC()
	subID := inv.subscriptionID()

	// Stripe finalises a zero-total invoice as "paid" immediately, with no
	// money moving at all. Treating that as a payment is what made a freshly
	// generated staffing invoice show as paid before the nursery had even
	// opened the email, so anything with no amount owed is ignored here.
	if inv.Total == 0 && inv.AmountPaid == 0 {
		slog.Warn("invoice.paid for a zero-total invoice ignored",
			"stripeInvoiceId", inv.ID, "number", inv.Number, "customer", inv.Customer)
		return nil
	}

	// Settle a platform invoice first. A staffing invoice raised by core is a
	// one-off Stripe invoice: it has no subscription, so resolving "the
	// nursery" through a subscription would fail and — before this reorder —
	// silently skip the reconciliation entirely. Matching on the invoice id we
	// stored when mirroring it is the reliable key.
	settledNurseryID := ""
	if inv.ID != "" {
		docs, err := db.Collection("invoices").Where("stripeInvoiceId", "==", inv.ID).Documents(ctx).GetAll()
		if err != nil {
			return err
		}
		for _, doc := range docs {
			if _, err := doc.Ref.Set(ctx, map[string]any{
				"status":              "paid",
				"paidAt":              now,
				"paymentReference":    inv.Number,
				"paymentMethod":       "stripe",
				"stripeInvoiceStatus": inv.Status,
			}, firestore.MergeAll); err != nil {
				return err
			}
			if settledNurseryID == "" {
				settledNurseryID, _ = doc.Data()["nurseryId"].(string)
			}
		}
	}

	nurseryID, err := resolveNursery(ctx, db, subID, inv.Customer, inv.Parent.SubscriptionDetails.Metadata)
	if err != nil {
		return err
	}
	if nurseryID == "" {
		nurseryID = settledNurseryID
	}
	if nurseryID == "" {
		slog.Warn("invoice.paid for an unknown nursery", "invoice", inv.ID, "subscription", subID, "customer", inv.Customer)
		return nil
	}

	updates := map[string]any{
		"status":           "active",
		"paymentMethod":    "stripe",
		"lastPaymentAt":    now,
		"lastPaymentPence": inv.AmountPaid,
		"updatedAt":        now,
	}
	if end := inv.periodEnd(); !end.IsZero() {
		updates["currentPeriodEnd"] = end
	}
	if subID != "" {
		updates["stripeSubscriptionId"] = subID
	}
	if inv.Customer != "" {
		updates["stripeCustomerId"] = inv.Customer
	}
	if _, err := db.Collection("subscriptions").Doc(nurseryID).Set(ctx, updates, firestore.MergeAll); err != nil {
		return err
	}

	// A staffing invoice (no subscription behind it) is settled above; there is
	// no membership status to update for it, only the receipt notification.
	if subID == "" && settledNurseryID != "" {
		notifyNursery(ctx, db, nurseryID, "invoice_paid", "Payment received",
			fmt.Sprintf("We have received your card payment of £%.2f for invoice %s. Thank you.",
				float64(inv.AmountPaid)/100, inv.Number))
		return nil
	}

	notifyNursery(ctx, db, nurseryID, "subscription_payment", "Membership payment received",
		fmt.Sprintf("Your card payment of £%.2f was received.", float64(inv.AmountPaid)/100))
	return nil
}

func handleInvoiceFailed(ctx context.Context, db *firestore.Client, inv stripeInvoice) error {
	nurseryID, err := resolveNursery(ctx, db, inv.subscriptionID(), inv.Customer, inv.Parent.SubscriptionDetails.Metadata)
	if err != nil {
		return err
	}
	if nurseryID == "" {
		return nil
	}
	now := time.Now().UTC()
	if _, err := db.Collection("subscriptions").Doc(nurseryID).Set(ctx, map[string]any{
		"status":        "past_due",
		"paymentMethod": "stripe",
		"updatedAt":     now,
	}, firestore.MergeAll); err != nil {
		return err
	}
	notifyNursery(ctx, db, nurseryID, "subscription_payment_failed", "Membership payment failed",
		"We could not take your card payment. Update your card in Billing to keep your membership active.")
	return nil
}

func handleSubscriptionChanged(ctx context.Context, db *firestore.Client, sub stripeSubscription, deleted bool) error {
	nurseryID, err := resolveNursery(ctx, db, sub.ID, sub.Customer, sub.Metadata)
	if err != nil {
		return err
	}
	if nurseryID == "" {
		slog.Warn("subscription event for an unknown nursery", "subscription", sub.ID, "customer", sub.Customer)
		return nil
	}
	synced := sub
	if deleted {
		synced.Status = "canceled"
	}
	return syncSubscription(ctx, db, nurseryID, synced, "", false)
}

// syncSubscription writes Stripe's current view of a subscription onto the
// nursery's `subscriptions/{nurseryId}` document — the same document the rest
// of the app (and core's GetNurserySubscription) already reads.
func syncSubscription(ctx context.Context, db *firestore.Client, nurseryID string, sub stripeSubscription, planHint string, activated bool) error {
	now := time.Now().UTC()
	priceID := sub.priceID()

	planID := planHint
	if planID == "" {
		planID = planIDForPrice(priceID)
	}
	planName := ""
	if p, err := findPlan(ctx, db, planID); err == nil && p != nil {
		planName = p.Name
	}

	updates := map[string]any{
		"nurseryId":            nurseryID,
		"status":               mapStripeStatus(sub.Status),
		"paymentMethod":        "stripe",
		"cancelAtPeriodEnd":    sub.CancelAtPeriodEnd,
		"stripeSubscriptionId": sub.ID,
		"stripeCustomerId":     sub.Customer,
		"stripePriceId":        priceID,
		"updatedAt":            now,
	}
	if planID != "" {
		updates["planId"] = planID
	}
	if planName != "" {
		updates["planName"] = planName
	}
	if sub.CurrentPeriodStart > 0 {
		updates["currentPeriodStart"] = time.Unix(sub.CurrentPeriodStart, 0).UTC()
	}
	if sub.CurrentPeriodEnd > 0 {
		updates["currentPeriodEnd"] = time.Unix(sub.CurrentPeriodEnd, 0).UTC()
	}
	if sub.Status == "canceled" || sub.CanceledAt > 0 {
		updates["cancelledAt"] = time.Unix(maxInt64(sub.CanceledAt, now.Unix()), 0).UTC()
	}
	if sub.Status == "active" || sub.Status == "trialing" {
		updates["lastPaymentAt"] = now
	}

	if _, err := db.Collection("subscriptions").Doc(nurseryID).Set(ctx, updates, firestore.MergeAll); err != nil {
		return err
	}

	if activated {
		notifyNursery(ctx, db, nurseryID, "subscription_active", "Membership activated",
			formatActivation(planName))
	} else if sub.Status == "canceled" {
		notifyNursery(ctx, db, nurseryID, "subscription_cancelled", "Membership cancelled",
			"Your card membership has been cancelled. Existing bookings and invoices are unaffected.")
	} else if sub.CancelAtPeriodEnd {
		notifyNursery(ctx, db, nurseryID, "subscription_cancelling", "Membership ends at period end",
			"Your membership will not renew. You keep access until the end of the current period.")
	}
	return nil
}

func formatActivation(planName string) string {
	if planName == "" {
		return "Your card payment succeeded and your nursery membership is active."
	}
	return planName + " is now active. Your card will renew automatically each month until cancelled."
}

// resolveNursery finds which nursery a Stripe object belongs to, preferring
// the metadata set when the checkout session (or subscription) was created and
// falling back to a lookup by stored Stripe subscription / customer id.
func resolveNursery(ctx context.Context, db *firestore.Client, subID, customerID string, metadata map[string]string) (string, error) {
	if id := metadata["nurseryId"]; id != "" {
		return id, nil
	}
	if subID != "" {
		docs, err := db.Collection("subscriptions").Where("stripeSubscriptionId", "==", subID).Limit(1).Documents(ctx).GetAll()
		if err != nil {
			return "", err
		}
		if len(docs) > 0 {
			return docs[0].Ref.ID, nil
		}
	}
	if customerID != "" {
		docs, err := db.Collection("subscriptions").Where("stripeCustomerId", "==", customerID).Limit(1).Documents(ctx).GetAll()
		if err != nil {
			return "", err
		}
		if len(docs) > 0 {
			return docs[0].Ref.ID, nil
		}
	}
	return "", nil
}

func planIDForPrice(priceID string) string {
	switch priceID {
	case "":
		return ""
	case os.Getenv("STRIPE_PRICE_STANDARD"):
		return "standard"
	case os.Getenv("STRIPE_PRICE_PREMIUM"):
		return "premium"
	case os.Getenv("STRIPE_PRICE_PAYG"):
		return "payg"
	}
	return ""
}

func notifyNursery(ctx context.Context, db *firestore.Client, uid, kind, title, body string) {
	if uid == "" || db == nil {
		return
	}
	if _, _, err := db.Collection("notifications").Add(ctx, map[string]any{
		"uid":       uid,
		"type":      kind,
		"title":     title,
		"body":      body,
		"payload":   map[string]any{"source": "stripe"},
		"read":      false,
		"createdAt": time.Now().UTC(),
	}); err != nil {
		slog.Warn("could not write billing notification", "uid", uid, "err", err)
	}
}

func maxInt64(a, b int64) int64 {
	if a > b {
		return a
	}
	return b
}
