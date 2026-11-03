package function

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"strconv"
	"testing"
	"time"
)

func sign(payload, secret string, ts int64) string {
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(strconv.FormatInt(ts, 10)))
	mac.Write([]byte("."))
	mac.Write([]byte(payload))
	return "t=" + strconv.FormatInt(ts, 10) + ",v1=" + hex.EncodeToString(mac.Sum(nil))
}

func TestVerifyStripeSignature(t *testing.T) {
	const secret = "whsec_test_secret"
	const payload = `{"id":"evt_1","type":"invoice.paid"}`
	now := time.Unix(1_800_000_000, 0)

	t.Run("valid signature accepted", func(t *testing.T) {
		if !verifyStripeSignature([]byte(payload), sign(payload, secret, now.Unix()), secret, now) {
			t.Fatal("expected valid signature to verify")
		}
	})

	t.Run("tampered payload rejected", func(t *testing.T) {
		header := sign(payload, secret, now.Unix())
		if verifyStripeSignature([]byte(payload+" "), header, secret, now) {
			t.Fatal("expected tampered payload to fail")
		}
	})

	t.Run("wrong secret rejected", func(t *testing.T) {
		header := sign(payload, "whsec_other", now.Unix())
		if verifyStripeSignature([]byte(payload), header, secret, now) {
			t.Fatal("expected wrong secret to fail")
		}
	})

	t.Run("stale timestamp rejected", func(t *testing.T) {
		header := sign(payload, secret, now.Add(-10*time.Minute).Unix())
		if verifyStripeSignature([]byte(payload), header, secret, now) {
			t.Fatal("expected stale signature to fail")
		}
	})

	t.Run("missing secret fails closed", func(t *testing.T) {
		header := sign(payload, secret, now.Unix())
		if verifyStripeSignature([]byte(payload), header, "", now) {
			t.Fatal("expected empty signing secret to reject")
		}
	})

	t.Run("malformed header rejected", func(t *testing.T) {
		for _, header := range []string{"", "garbage", "t=abc,v1=zz", "v1=deadbeef"} {
			if verifyStripeSignature([]byte(payload), header, secret, now) {
				t.Fatalf("expected header %q to be rejected", header)
			}
		}
	})
}

func TestMapStripeStatus(t *testing.T) {
	cases := map[string]string{
		"active":             "active",
		"trialing":           "active",
		"past_due":           "past_due",
		"unpaid":             "past_due",
		"incomplete":         "past_due",
		"canceled":           "cancelled",
		"incomplete_expired": "cancelled",
		"paused":             "pending",
	}
	for in, want := range cases {
		if got := mapStripeStatus(in); got != want {
			t.Errorf("mapStripeStatus(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestStripePriceIDFor(t *testing.T) {
	t.Setenv("STRIPE_PRICE_STANDARD", "price_std")
	t.Setenv("STRIPE_PRICE_PREMIUM", "price_prem")
	t.Setenv("STRIPE_PRICE_PAYG", "price_payg")

	if got := stripePriceIDFor("standard", ""); got != "price_std" {
		t.Errorf("standard = %q", got)
	}
	if got := stripePriceIDFor("premium", ""); got != "price_prem" {
		t.Errorf("premium = %q", got)
	}
	if got := stripePriceIDFor("payg", ""); got != "price_payg" {
		t.Errorf("payg = %q", got)
	}
	// A plan document's own price id wins over the environment mapping.
	if got := stripePriceIDFor("premium", "price_live_prem"); got != "price_live_prem" {
		t.Errorf("override = %q", got)
	}
	if got := stripePriceIDFor("trial", ""); got != "" {
		t.Errorf("trial should not map to a price, got %q", got)
	}
}

func TestPlanIDForPrice(t *testing.T) {
	t.Setenv("STRIPE_PRICE_STANDARD", "price_std")
	t.Setenv("STRIPE_PRICE_PREMIUM", "price_prem")
	t.Setenv("STRIPE_PRICE_PAYG", "price_payg")

	if got := planIDForPrice("price_prem"); got != "premium" {
		t.Errorf("price_prem -> %q", got)
	}
	if got := planIDForPrice("price_unknown"); got != "" {
		t.Errorf("unknown price -> %q", got)
	}
	if got := planIDForPrice(""); got != "" {
		t.Errorf("empty price -> %q", got)
	}
}
