package function

import (
	"context"
	"testing"
	"time"
)

func TestDefaultRateCard(t *testing.T) {
	card := DefaultRateCard()
	if card.Version != 1 {
		t.Errorf("Version = %d, want 1", card.Version)
	}
	if !card.Active {
		t.Errorf("Active = %v, want true", card.Active)
	}

	quals := []string{string(QualNone), string(QualLevel2), string(QualLevel3), string(QualLevel4Plus)}
	for _, q := range quals {
		rate, ok := card.Rates[q]
		if !ok {
			t.Fatalf("missing rate for qualification %s", q)
		}
		if rate.PractitionerPayPencePerHour <= 0 {
			t.Errorf("pay for %s = %d, want > 0", q, rate.PractitionerPayPencePerHour)
		}
		if rate.NurseryChargePencePerHour <= rate.PractitionerPayPencePerHour {
			t.Errorf("charge (%d) should be > pay (%d) for %s", rate.NurseryChargePencePerHour, rate.PractitionerPayPencePerHour, q)
		}
	}
}

func TestResolveShiftFinancials(t *testing.T) {
	ctx := context.Background()
	start := time.Date(2026, 11, 1, 9, 0, 0, 0, time.UTC)
	end := time.Date(2026, 11, 1, 17, 0, 0, 0, time.UTC) // 8 hours = 480 mins
	breakMinutes := int64(30)                             // 450 billable mins = 7.5 hours

	// nil client falls back to DefaultRateCard
	fin, legacyPayRate := ResolveShiftFinancials(ctx, nil, QualLevel3, start, end, breakMinutes)

	if fin.DurationMinutes != 480 {
		t.Errorf("DurationMinutes = %d, want 480", fin.DurationMinutes)
	}
	if fin.BillableMinutes != 450 {
		t.Errorf("BillableMinutes = %d, want 450", fin.BillableMinutes)
	}
	if fin.PractitionerPayPencePerHour != 1500 {
		t.Errorf("PractitionerPayPencePerHour = %d, want 1500", fin.PractitionerPayPencePerHour)
	}
	// 450 * 1500 / 60 = 11250 pence (£112.50)
	if fin.EstimatedGrossPayPence != 11250 {
		t.Errorf("EstimatedGrossPayPence = %d, want 11250", fin.EstimatedGrossPayPence)
	}
	// 450 * 1950 / 60 = 14625 pence (£146.25)
	if fin.EstimatedNurseryChargePence != 14625 {
		t.Errorf("EstimatedNurseryChargePence = %d, want 14625", fin.EstimatedNurseryChargePence)
	}
	// 14625 - 11250 = 3375 pence (£33.75)
	if fin.PlatformFeePence != 3375 {
		t.Errorf("PlatformFeePence = %d, want 3375", fin.PlatformFeePence)
	}
	if legacyPayRate != 15.00 {
		t.Errorf("legacyPayRate = %f, want 15.00", legacyPayRate)
	}
}

func TestCalculateCancellationCharge(t *testing.T) {
	shift := Shift{
		StartTime: time.Date(2026, 11, 1, 9, 0, 0, 0, time.UTC),
		EndTime:   time.Date(2026, 11, 1, 17, 0, 0, 0, time.UTC),
	}
	cancelledAt := time.Date(2026, 11, 1, 7, 0, 0, 0, time.UTC) // 2 hours before

	charge, comp, ver := CalculateCancellationCharge(shift, RoleNursery, "standard", cancelledAt)
	if charge != 0 || comp != 0 {
		t.Errorf("expected 0 fees under Decision 13, got charge=%d, comp=%d", charge, comp)
	}
	if ver < 1 {
		t.Errorf("policyVersion = %d, want >= 1", ver)
	}

	// Emergency exemption
	chargeEmerg, compEmerg, _ := CalculateCancellationCharge(shift, RoleStaff, "emergency", cancelledAt)
	if chargeEmerg != 0 || compEmerg != 0 {
		t.Errorf("expected 0 fees for emergency, got charge=%d, comp=%d", chargeEmerg, compEmerg)
	}
}
