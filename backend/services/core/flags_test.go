package function

import (
	"testing"
	"time"
)

// The stored flags document also carries updatedAt/updatedBy. Decoding it into
// map[string]string failed on that timestamp, so every saved gate silently fell
// back to the code default — an admin changed a gate, the console showed the
// old value, and enforcement never moved.
func TestGateModesFromDocWithAuditFields(t *testing.T) {
	raw := map[string]any{
		"nurseryApprovalRequired":      "warn",
		"practitionerApprovalRequired": "enforce",
		"trialExpired":                 "off",
		"termsAcceptanceRequired":      "warn",
		"updatedAt":                    time.Now().UTC(), // Firestore timestamp
		"updatedBy":                    "admin-uid",
	}

	modes := gateModesFromDoc(raw)

	want := map[string]GateMode{
		"nurseryApprovalRequired":      GateWarn,
		"practitionerApprovalRequired": GateEnforce,
		"trialExpired":                 GateOff,
		"termsAcceptanceRequired":      GateWarn,
	}
	for name, expected := range want {
		if got := modes[name]; got != expected {
			t.Errorf("%s = %q, want %q", name, got, expected)
		}
	}
	if len(modes) != len(want) {
		t.Errorf("parsed %d gates, want %d (audit fields must not become gates)", len(modes), len(want))
	}
	if _, ok := modes["updatedBy"]; ok {
		t.Error("updatedBy was parsed as a gate")
	}
}

func TestGateModesFromDocNormalisesBadValues(t *testing.T) {
	modes := gateModesFromDoc(map[string]any{
		"nurseryApprovalRequired": "ENFORCE", // wrong case, not a valid mode
		"trialExpired":            true,      // wrong type
	})

	if got := modes["nurseryApprovalRequired"]; got != GateOff {
		t.Errorf("unknown mode = %q, want %q", got, GateOff)
	}
	// A non-string must be treated as "not stored", so the default applies
	// rather than the gate being pinned off.
	if _, ok := modes["trialExpired"]; ok {
		t.Error("trialExpired should be absent so its default applies")
	}
}

func TestGateModesFromDocumentDoesNotLosePartialOverrides(t *testing.T) {
	stored := gateModesFromDoc(map[string]any{"nurseryApprovalRequired": "off"})
	if got := effectiveGate(stored, "nurseryApprovalRequired"); got != GateOff {
		t.Fatalf("explicit off override = %q, want %q", got, GateOff)
	}
	if got := effectiveGate(stored, "trialExpired"); got != GateEnforce {
		t.Fatalf("missing override = %q, want default %q", got, GateEnforce)
	}
}

// Effective resolution: a saved value wins, a missing one falls back to the
// launch posture, and only the two enforce-by-default gates are blocked out of
// the box.
func TestEffectiveGate(t *testing.T) {
	stored := gateModesFromDoc(map[string]any{"nurseryApprovalRequired": "warn"})

	if got := effectiveGate(stored, "nurseryApprovalRequired"); got != GateWarn {
		t.Errorf("stored override = %q, want %q", got, GateWarn)
	}
	if got := effectiveGate(stored, "trialExpired"); got != GateEnforce {
		t.Errorf("unstored gate = %q, want the default %q", got, GateEnforce)
	}
	if got := effectiveGate(stored, "practitionerApprovalRequired"); got != GateWarn {
		t.Errorf("unstored gate = %q, want the default %q", got, GateWarn)
	}
	if got := effectiveGate(map[string]GateMode{}, "notARealGate"); got != GateOff {
		t.Errorf("unknown gate = %q, want %q", got, GateOff)
	}
}
