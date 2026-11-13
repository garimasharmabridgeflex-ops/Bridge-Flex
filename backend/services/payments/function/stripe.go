package function

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"
)

// Stripe is spoken to over its REST API directly rather than through the
// official Go SDK: every call this service makes is a plain form-encoded
// POST/GET, and the SDK would add ~40 transitive modules to a service that
// otherwise only needs Firestore. Signature verification is implemented in
// verifyStripeSignature below against Stripe's documented scheme
// (HMAC-SHA256 over "<timestamp>.<raw body>", constant-time compared).

const stripeAPIBase = "https://api.stripe.com/v1"

var (
	errStripeNotConfigured = errors.New("stripe is not configured")
	errNotNursery          = errors.New("account is not a nursery")
)

type stripeClient struct {
	secretKey string
	http      *http.Client
	base      string
}

func newStripeClient() (*stripeClient, error) {
	key := os.Getenv("STRIPE_SECRET_KEY")
	if key == "" {
		return nil, errStripeNotConfigured
	}
	return &stripeClient{
		secretKey: key,
		http:      &http.Client{Timeout: 20 * time.Second},
		base:      stripeAPIBase,
	}, nil
}

type stripeErrorBody struct {
	Error struct {
		Type    string `json:"type"`
		Code    string `json:"code"`
		Message string `json:"message"`
	} `json:"error"`
}

func (c *stripeClient) do(ctx context.Context, method, path string, params url.Values, out any) error {
	var body io.Reader
	if method == http.MethodPost {
		body = strings.NewReader(params.Encode())
	}
	req, err := http.NewRequestWithContext(ctx, method, c.base+path, body)
	if err != nil {
		return err
	}
	req.SetBasicAuth(c.secretKey, "")
	if method == http.MethodPost {
		req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	}
	// Pinned so a future account default-version bump can't silently change
	// the payload shape this code parses (e.g. invoice.subscription moving
	// under parent.subscription_details).
	req.Header.Set("Stripe-Version", "2024-06-20")

	resp, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(resp.Body)
	if err != nil {
		return err
	}
	if resp.StatusCode >= 400 {
		var e stripeErrorBody
		if json.Unmarshal(raw, &e) == nil && e.Error.Message != "" {
			return fmt.Errorf("stripe %s: %s", e.Error.Code, e.Error.Message)
		}
		return fmt.Errorf("stripe %s %s: status %d", method, path, resp.StatusCode)
	}
	if out != nil {
		return json.Unmarshal(raw, out)
	}
	return nil
}

func (c *stripeClient) post(ctx context.Context, path string, params url.Values, out any) error {
	return c.do(ctx, http.MethodPost, path, params, out)
}

func (c *stripeClient) get(ctx context.Context, path string, params url.Values, out any) error {
	if len(params) > 0 {
		path += "?" + params.Encode()
	}
	return c.do(ctx, http.MethodGet, path, nil, out)
}

// --- Response shapes (only the fields this service reads) ------------------

type stripeCustomer struct {
	ID    string            `json:"id"`
	Email string            `json:"email"`
	Meta  map[string]string `json:"metadata"`
}

type stripeCheckoutSession struct {
	ID               string            `json:"id"`
	Object           string            `json:"object"`
	URL              string            `json:"url"`
	Mode             string            `json:"mode"`
	Status           string            `json:"status"`
	PaymentStatus    string            `json:"payment_status"`
	Customer         string            `json:"customer"`
	Subscription     string            `json:"subscription"`
	ClientReference  string            `json:"client_reference_id"`
	AmountTotal      int64             `json:"amount_total"`
	Currency         string            `json:"currency"`
	Metadata         map[string]string `json:"metadata"`
	PaymentIntent    string            `json:"payment_intent"`
	CustomerDetails  struct {
		Email string `json:"email"`
	} `json:"customer_details"`
}

type stripeSubscription struct {
	ID               string            `json:"id"`
	Status           string            `json:"status"`
	Customer         string            `json:"customer"`
	CancelAtPeriodEnd bool             `json:"cancel_at_period_end"`
	CurrentPeriodStart int64           `json:"current_period_start"`
	CurrentPeriodEnd   int64           `json:"current_period_end"`
	StartDate        int64             `json:"start_date"`
	CanceledAt       int64             `json:"canceled_at"`
	Metadata         map[string]string `json:"metadata"`
	Items            struct {
		Data []struct {
			ID    string `json:"id"`
			Price struct {
				ID         string `json:"id"`
				UnitAmount int64  `json:"unit_amount"`
				Recurring  *struct {
					Interval string `json:"interval"`
				} `json:"recurring"`
			} `json:"price"`
		} `json:"data"`
	} `json:"items"`
	// latest_invoice is an id string unless expanded.
	LatestInvoice string `json:"latest_invoice"`
}

func (s *stripeSubscription) priceID() string {
	if len(s.Items.Data) == 0 {
		return ""
	}
	return s.Items.Data[0].Price.ID
}

type stripeInvoice struct {
	ID           string `json:"id"`
	Number       string `json:"number"`
	Status       string `json:"status"`
	Customer     string `json:"customer"`
	Subscription string `json:"subscription"`
	Total        int64  `json:"total"`
	AmountPaid   int64  `json:"amount_paid"`
	AmountDue    int64  `json:"amount_due"`
	Currency     string `json:"currency"`
	AttemptCount int64  `json:"attempt_count"`
	Parent       struct {
		SubscriptionDetails struct {
			Subscription string            `json:"subscription"`
			Metadata     map[string]string `json:"metadata"`
		} `json:"subscription_details"`
	} `json:"parent"`
	Lines struct {
		Data []struct {
			Period struct {
				Start int64 `json:"start"`
				End   int64 `json:"end"`
			} `json:"period"`
		} `json:"data"`
	} `json:"lines"`
}

func (i *stripeInvoice) subscriptionID() string {
	if i.Parent.SubscriptionDetails.Subscription != "" {
		return i.Parent.SubscriptionDetails.Subscription
	}
	return i.Subscription
}

func (i *stripeInvoice) periodEnd() time.Time {
	if len(i.Lines.Data) == 0 || i.Lines.Data[0].Period.End == 0 {
		return time.Time{}
	}
	return time.Unix(i.Lines.Data[0].Period.End, 0).UTC()
}

type stripePortalSession struct {
	ID  string `json:"id"`
	URL string `json:"url"`
}

type stripeEvent struct {
	ID   string `json:"id"`
	Type string `json:"type"`
	Data struct {
		Object json.RawMessage `json:"object"`
	} `json:"data"`
}

// --- Webhook signature verification ---------------------------------------

const stripeSignatureTolerance = 5 * time.Minute

// verifyStripeSignature implements Stripe's documented v1 scheme: the
// Stripe-Signature header carries a unix timestamp and one or more v1
// signatures of "<timestamp>.<payload>" keyed with the endpoint's signing
// secret. Any v1 candidate matching within the tolerance passes.
func verifyStripeSignature(payload []byte, sigHeader, secret string, now time.Time) bool {
	if secret == "" || sigHeader == "" {
		return false
	}
	var timestamp int64
	var candidates []string
	for _, part := range strings.Split(sigHeader, ",") {
		kv := strings.SplitN(strings.TrimSpace(part), "=", 2)
		if len(kv) != 2 {
			continue
		}
		switch kv[0] {
		case "t":
			timestamp, _ = strconv.ParseInt(kv[1], 10, 64)
		case "v1":
			candidates = append(candidates, kv[1])
		}
	}
	if timestamp == 0 || len(candidates) == 0 {
		return false
	}
	signed := time.Unix(timestamp, 0)
	diff := now.Sub(signed)
	if diff < 0 {
		diff = -diff
	}
	if diff > stripeSignatureTolerance {
		return false
	}

	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(strconv.FormatInt(timestamp, 10)))
	mac.Write([]byte("."))
	mac.Write(payload)
	expected := mac.Sum(nil)

	for _, c := range candidates {
		got, err := hex.DecodeString(c)
		if err != nil {
			continue
		}
		if hmac.Equal(got, expected) {
			return true
		}
	}
	return false
}
