package function

import (
	"context"
	"net/url"
	"os"

	"cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// planInfo is the slice of a `plans/{planId}` document this service needs to
// start a Stripe Checkout Session.
type planInfo struct {
	ID              string
	Name            string
	PricePence      int64
	BillingInterval string // "month", "per_booking", "none"
	StripePriceID   string
}

// stripePriceIDFor maps a KFlex plan id to the Stripe Price it bills through.
// A plan document may override the default with its own `stripePriceId` (set
// by the admin plan editor once live-mode prices exist); otherwise the price
// ids pushed to Secret Manager at deploy time are used.
func stripePriceIDFor(planID, override string) string {
	if override != "" {
		return override
	}
	switch planID {
	case "standard":
		return os.Getenv("STRIPE_PRICE_STANDARD")
	case "premium":
		return os.Getenv("STRIPE_PRICE_PREMIUM")
	case "payg":
		return os.Getenv("STRIPE_PRICE_PAYG")
	}
	return ""
}

// findPlan mirrors core's plan lookup (Firestore first, then the seeded
// defaults) but only needs the billing fields.
func findPlan(ctx context.Context, db *firestore.Client, planID string) (*planInfo, error) {
	if db != nil {
		snap, err := db.Collection("plans").Doc(planID).Get(ctx)
		if err == nil {
			data := snap.Data()
			if active, ok := data["active"].(bool); ok && !active {
				return nil, nil
			}
			p := &planInfo{ID: planID}
			p.Name, _ = data["name"].(string)
			p.BillingInterval, _ = data["billingInterval"].(string)
			switch v := data["pricePence"].(type) {
			case int64:
				p.PricePence = v
			case float64:
				p.PricePence = int64(v)
			}
			p.StripePriceID, _ = data["stripePriceId"].(string)
			return p, nil
		}
		if status.Code(err) != codes.NotFound {
			return nil, err
		}
	}

	for _, p := range defaultPlanInfos() {
		if p.ID == planID {
			plan := p
			return &plan, nil
		}
	}
	return nil, nil
}

// defaultPlanInfos mirrors core's defaultPlans() billing fields — kept in
// sync with services/core/billing.go.
func defaultPlanInfos() []planInfo {
	return []planInfo{
		{ID: "standard", Name: "Standard Subscription", PricePence: 19900, BillingInterval: "month"},
		{ID: "premium", Name: "Premium Subscription", PricePence: 29900, BillingInterval: "month"},
		{ID: "payg", Name: "Pay As You Go", PricePence: 999, BillingInterval: "per_booking"},
		{ID: "trial", Name: "Free Trial", PricePence: 0, BillingInterval: "none"},
	}
}

// checkoutReturnURL resolves where Stripe sends the browser after checkout.
// One page handles both outcomes; `{CHECKOUT_SESSION_ID}` is a Stripe
// placeholder it substitutes for us.
func checkoutReturnURL(status string) string {
	if explicit := os.Getenv("STRIPE_CHECKOUT_" + status + "_URL"); explicit != "" {
		return explicit
	}
	base := os.Getenv("APP_PUBLIC_URL")
	if base == "" {
		base = "https://kvision-503115.web.app"
	}
	return base + "/billing/checkout-return.html?status=" + url.QueryEscape(statusLower(status))
}

func statusLower(status string) string {
	if status == "SUCCESS" {
		return "success"
	}
	return "cancel"
}

// portalReturnURL is where Stripe sends the browser back after the hosted
// billing portal (cancel / update card) closes.
func portalReturnURL() string {
	if explicit := os.Getenv("STRIPE_PORTAL_RETURN_URL"); explicit != "" {
		return explicit
	}
	base := os.Getenv("APP_PUBLIC_URL")
	if base == "" {
		base = "https://kvision-503115.web.app"
	}
	return base + "/billing/checkout-return.html?status=portal"
}
