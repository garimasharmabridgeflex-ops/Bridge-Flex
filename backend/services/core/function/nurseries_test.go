package function

import (
	"encoding/json"
	"testing"
	"time"
)

func TestBranchModelSerialization(t *testing.T) {
	now := time.Now().Truncate(time.Second)
	branch := Branch{
		ID:              "branch-123",
		NurseryID:       "nursery-abc",
		Name:            "Little Acorns Setting",
		Address:         "12 High Street",
		Postcode:        "SW1A 1AA",
		City:            "London",
		Phone:           "+442079460123",
		ContactPerson:   "Jane Doe",
		OfstedRegNumber: "EY123456",
		IsPrimary:       true,
		CreatedAt:       now,
		UpdatedAt:       now,
	}

	data, err := json.Marshal(branch)
	if err != nil {
		t.Fatalf("Marshal error: %v", err)
	}

	var parsed map[string]any
	if err := json.Unmarshal(data, &parsed); err != nil {
		t.Fatalf("Unmarshal error: %v", err)
	}

	if parsed["name"] != "Little Acorns Setting" {
		t.Errorf("name = %v, want Little Acorns Setting", parsed["name"])
	}
	if parsed["isPrimary"] != true {
		t.Errorf("isPrimary = %v, want true", parsed["isPrimary"])
	}
	if parsed["postcode"] != "SW1A 1AA" {
		t.Errorf("postcode = %v, want SW1A 1AA", parsed["postcode"])
	}
}

func TestNurseryApprovalStatusValues(t *testing.T) {
	if NurseryPendingApproval != "pending_approval" {
		t.Errorf("NurseryPendingApproval = %q, want 'pending_approval'", NurseryPendingApproval)
	}
	if NurseryApproved != "approved" {
		t.Errorf("NurseryApproved = %q, want 'approved'", NurseryApproved)
	}
	if NurseryRejected != "rejected" {
		t.Errorf("NurseryRejected = %q, want 'rejected'", NurseryRejected)
	}
}
