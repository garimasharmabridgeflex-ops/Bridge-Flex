package function

import (
	"testing"
	"time"
)

func TestCancellationPolicyDefaultsToNoCharge(t *testing.T) {
	start := time.Date(2026, 11, 1, 8, 0, 0, 0, time.UTC)
	shift := Shift{StartTime: start}
	charge, _, _ := CalculateCancellationCharge(shift, RoleNursery, "standard", start.Add(-1*time.Hour))
	if charge != 0 {
		t.Fatalf("unpublished policy must not charge, got %d", charge)
	}
}

func TestCancellationPolicyOnlyChargesNurseryInsideNotice(t *testing.T) {
	start := time.Date(2026, 11, 1, 8, 0, 0, 0, time.UTC)
	shift := Shift{StartTime: start}
	policy := CancellationPolicy{Version: 2, NoticeHours: 48, NurseryFeePence: 2500, Published: true}

	inside, _, version := CalculateCancellationChargeWithPolicy(shift, RoleNursery, "standard", start.Add(-2*time.Hour), policy)
	if inside != 2500 || version != 2 {
		t.Fatalf("expected 2500p inside notice, got %d (version %d)", inside, version)
	}

	outside, _, _ := CalculateCancellationChargeWithPolicy(shift, RoleNursery, "standard", start.Add(-72*time.Hour), policy)
	if outside != 0 {
		t.Fatalf("expected no fee outside notice, got %d", outside)
	}

	emergency, _, _ := CalculateCancellationChargeWithPolicy(shift, RoleNursery, "emergency", start.Add(-1*time.Hour), policy)
	if emergency != 0 {
		t.Fatalf("emergency must be exempt, got %d", emergency)
	}

	staff, _, _ := CalculateCancellationChargeWithPolicy(shift, RoleStaff, "standard", start.Add(-1*time.Hour), policy)
	if staff != 0 {
		t.Fatalf("practitioners must never be charged a cancellation penalty, got %d", staff)
	}
}

func TestMissingVettingChecksRequiresSafeguardingSignOff(t *testing.T) {
	empty := VettingChecklist{}
	if got := len(missingVettingChecks(empty)); got != len(requiredVettingChecks) {
		t.Fatalf("expected all %d checks missing, got %d", len(requiredVettingChecks), got)
	}

	complete := VettingChecklist{
		Identity:            VettingCheckItem{Result: CheckPassed},
		OriginalCertificate: VettingCheckItem{Result: CheckPassed},
		Suitability:         VettingCheckItem{Result: CheckPassed},
		Workforce:           VettingCheckItem{Result: CheckPassed},
		BarredList:          VettingCheckItem{Result: CheckPassed},
		UpdateService:       VettingCheckItem{Result: CheckPassed},
		RightToWork:         VettingCheckItem{Result: CheckPassed},
		Qualification:       VettingCheckItem{Result: CheckPassed},
	}
	if got := missingVettingChecks(complete); len(got) != 0 {
		t.Fatalf("expected no missing checks, got %v", got)
	}

	complete.BarredList = VettingCheckItem{Result: CheckFailed}
	if got := missingVettingChecks(complete); len(got) != 1 || got[0] != "barredList" {
		t.Fatalf("expected barredList to block approval, got %v", got)
	}
}

func TestEffectiveGateUsesSafeDefaults(t *testing.T) {
	if got := effectiveGate(map[string]GateMode{}, "nurseryApprovalRequired"); got != GateEnforce {
		t.Fatalf("nursery approval should default to enforce, got %s", got)
	}
	if got := effectiveGate(map[string]GateMode{}, "practitionerApprovalRequired"); got != GateWarn {
		t.Fatalf("vetting should default to warn, got %s", got)
	}
	if got := effectiveGate(map[string]GateMode{"trialExpired": GateEnforce}, "trialExpired"); got != GateEnforce {
		t.Fatalf("stored override should win, got %s", got)
	}
	if got := effectiveGate(map[string]GateMode{}, "unknownGate"); got != GateOff {
		t.Fatalf("unknown gates must stay off, got %s", got)
	}
}
