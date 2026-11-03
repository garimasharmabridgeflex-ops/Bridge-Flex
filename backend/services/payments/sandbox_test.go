package function

import (
	"context"
	"encoding/json"
	"os"
	"strconv"
	"strings"
	"testing"
	"time"

	"cloud.google.com/go/firestore"
)

// TestSandboxCheckoutAndWebhook exercises the real Stripe test-mode API and a
// local Firestore emulator. It is skipped unless both are available, so the
// normal `go test ./...` run stays offline:
//
//	STRIPE_SECRET_KEY=sk_test_... \
//	STRIPE_PRICE_STANDARD=price_... \
//	FIRESTORE_EMULATOR_HOST=127.0.0.1:8180 \
//	go test ./function -run TestSandbox -v
//
// It creates a throwaway Stripe test-mode customer + Checkout Session and an
// emulator-only profile/subscription, so it never touches production data.
func TestSandboxCheckoutAndWebhook(t *testing.T) {
	if os.Getenv("STRIPE_SECRET_KEY") == "" {
		t.Skip("STRIPE_SECRET_KEY not set")
	}
	if os.Getenv("FIRESTORE_EMULATOR_HOST") == "" {
		t.Skip("FIRESTORE_EMULATOR_HOST not set")
	}

	ctx := context.Background()
	projectID := os.Getenv("GCLOUD_PROJECT")
	if projectID == "" {
		projectID = "demo-bridgeflex"
	}
	db, err := firestore.NewClient(ctx, projectID)
	if err != nil {
		t.Fatalf("firestore client: %v", err)
	}
	defer db.Close()

	uid := "sandbox-nursery-" + strings.ReplaceAll(time.Now().UTC().Format("20060102-150405"), "-", "")
	if _, err := db.Collection("profiles").Doc(uid).Set(ctx, map[string]any{
		"role":  "nursery",
		"name":  "Sandbox Nursery",
		"email": "sandbox@example.test",
	}); err != nil {
		t.Fatalf("seed profile: %v", err)
	}

	client, err := newStripeClient()
	if err != nil {
		t.Fatalf("stripe client: %v", err)
	}

	result, err := startCheckout(ctx, db, client, uid, "standard")
	if err != nil {
		t.Fatalf("startCheckout: %v", err)
	}
	if result.Updated {
		t.Fatal("first checkout should be a new session, not an in-place update")
	}
	if !strings.HasPrefix(result.SessionID, "cs_test_") {
		t.Fatalf("expected a test-mode checkout session, got %q", result.SessionID)
	}
	if !strings.HasPrefix(result.URL, "https://checkout.stripe.com/") {
		t.Fatalf("expected a hosted checkout URL, got %q", result.URL)
	}
	if result.Mode != "subscription" {
		t.Fatalf("standard plan should use subscription mode, got %q", result.Mode)
	}

	snap, err := db.Collection("subscriptions").Doc(uid).Get(ctx)
	if err != nil {
		t.Fatalf("subscription doc: %v", err)
	}
	customerID, _ := snap.Data()["stripeCustomerId"].(string)
	if !strings.HasPrefix(customerID, "cus_") {
		t.Fatalf("expected a Stripe customer to be stored, got %q", customerID)
	}

	// Re-running checkout must reuse the same Stripe customer instead of
	// creating a second billing identity.
	if _, err := startCheckout(ctx, db, client, uid, "premium"); err != nil {
		t.Fatalf("second startCheckout: %v", err)
	}
	snap, _ = db.Collection("subscriptions").Doc(uid).Get(ctx)
	if again, _ := snap.Data()["stripeCustomerId"].(string); again != customerID {
		t.Fatalf("customer should be reused: %q != %q", again, customerID)
	}

	// Webhook handling: a failed renewal flips the membership to past_due and
	// writes a notification, all through the same dispatch the endpoint uses.
	event := stripeEvent{ID: "evt_sandbox_failed_" + uid, Type: "invoice.payment_failed"}
	event.Data.Object = json.RawMessage(`{
		"id": "in_sandbox",
		"customer": "` + customerID + `",
		"subscription": "sub_sandbox",
		"amount_due": 19900,
		"metadata": {"nurseryId": "` + uid + `"}
	}`)
	if err := dispatchStripeEvent(ctx, db, event); err != nil {
		t.Fatalf("dispatch invoice.payment_failed: %v", err)
	}
	snap, _ = db.Collection("subscriptions").Doc(uid).Get(ctx)
	if got := snap.Data()["status"]; got != "past_due" {
		t.Fatalf("status after failed payment = %v, want past_due", got)
	}

	// A paid renewal restores active status and records the payment.
	paid := stripeEvent{ID: "evt_sandbox_paid_" + uid, Type: "invoice.paid"}
	paid.Data.Object = json.RawMessage(`{
		"id": "in_sandbox_paid",
		"number": "KSANDBOX-0001",
		"customer": "` + customerID + `",
		"subscription": "sub_sandbox",
		"amount_paid": 29900,
		"lines": {"data": [{"period": {"start": ` + strconv.FormatInt(time.Now().Unix(), 10) + `, "end": ` + strconv.FormatInt(time.Now().AddDate(0, 1, 0).Unix(), 10) + `}}]},
		"parent": {"subscription_details": {"subscription": "sub_sandbox", "metadata": {"nurseryId": "` + uid + `"}}}
	}`)
	if err := dispatchStripeEvent(ctx, db, paid); err != nil {
		t.Fatalf("dispatch invoice.paid: %v", err)
	}
	snap, _ = db.Collection("subscriptions").Doc(uid).Get(ctx)
	data := snap.Data()
	if data["status"] != "active" {
		t.Fatalf("status after paid invoice = %v, want active", data["status"])
	}
	if pence, _ := data["lastPaymentPence"].(int64); pence != 29900 {
		t.Fatalf("lastPaymentPence = %v, want 29900", data["lastPaymentPence"])
	}
	if data["currentPeriodEnd"] == nil {
		t.Fatal("expected currentPeriodEnd to be synced from the Stripe invoice")
	}

	notifications, err := db.Collection("notifications").Where("uid", "==", uid).Documents(ctx).GetAll()
	if err != nil {
		t.Fatalf("notifications query: %v", err)
	}
	if len(notifications) < 2 {
		t.Fatalf("expected payment notifications to be written, got %d", len(notifications))
	}

	// Cleanup the emulator-only fixtures (the Stripe test customer is left in
	// the sandbox account deliberately — deleting it is not required).
	for _, doc := range notifications {
		_, _ = doc.Ref.Delete(ctx)
	}
	_, _ = db.Collection("subscriptions").Doc(uid).Delete(ctx)
	_, _ = db.Collection("profiles").Doc(uid).Delete(ctx)
}

