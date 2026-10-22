package function

import (
	"testing"
	"time"
)

func TestCalculateTimesheetHoursAndPay(t *testing.T) {
	start := time.Date(2026, 11, 1, 9, 0, 0, 0, time.UTC)
	end := time.Date(2026, 11, 1, 17, 0, 0, 0, time.UTC) // 8 hours = 480 mins
	breakMinutes := int64(30)                             // 450 billable mins = 7.5 hours
	hourlyPayPence := int64(1500)                         // £15.00
	nurseryChargePence := int64(1950)                     // £19.50

	billableMins, grossPay, nurseryCharge, err := CalculateTimesheetHoursAndPay(start, end, breakMinutes, hourlyPayPence, nurseryChargePence)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if billableMins != 450 {
		t.Errorf("billableMins = %d, want 450", billableMins)
	}
	// 450 * 1500 / 60 = 11250 pence (£112.50)
	if grossPay != 11250 {
		t.Errorf("grossPay = %d, want 11250", grossPay)
	}
	// 450 * 1950 / 60 = 14625 pence (£146.25)
	if nurseryCharge != 14625 {
		t.Errorf("nurseryCharge = %d, want 14625", nurseryCharge)
	}

	// Case: Invalid time range
	_, _, _, err = CalculateTimesheetHoursAndPay(end, start, 0, 1500, 1800)
	if err == nil {
		t.Errorf("expected error when end time is before start time")
	}

	// Case: Break exceeds shift duration
	_, _, _, err = CalculateTimesheetHoursAndPay(start, end, 500, 1500, 1800)
	if err == nil {
		t.Errorf("expected error when break minutes exceeds duration")
	}

	// Case: Negative break
	_, _, _, err = CalculateTimesheetHoursAndPay(start, end, -15, 1500, 1800)
	if err == nil {
		t.Errorf("expected error for negative break minutes")
	}
}

func TestShouldEscalateTimesheet(t *testing.T) {
	now := time.Date(2026, 11, 3, 12, 0, 0, 0, time.UTC)

	// Case 1: Submitted 50 hours ago, not yet escalated -> Should escalate
	sub50h := now.Add(-50 * time.Hour)
	if !ShouldEscalateTimesheet(TimesheetSubmitted, sub50h, nil, now) {
		t.Errorf("expected timesheet submitted 50h ago to escalate")
	}

	// Case 2: Submitted 24 hours ago, not yet escalated -> Should NOT escalate
	sub24h := now.Add(-24 * time.Hour)
	if ShouldEscalateTimesheet(TimesheetSubmitted, sub24h, nil, now) {
		t.Errorf("did not expect timesheet submitted 24h ago to escalate")
	}

	// Case 3: Already escalated (idempotency check) -> Should NOT escalate again
	alreadyEsc := now.Add(-1 * time.Hour)
	if ShouldEscalateTimesheet(TimesheetSubmitted, sub50h, &alreadyEsc, now) {
		t.Errorf("did not expect already escalated timesheet to escalate again")
	}

	// Case 4: Approved timesheet -> Should NOT escalate
	if ShouldEscalateTimesheet(TimesheetApproved, sub50h, nil, now) {
		t.Errorf("did not expect approved timesheet to escalate")
	}
}

func TestTimesheetDocID(t *testing.T) {
	id := timesheetDocID("shift_abc", "staff_xyz")
	expected := "ts_shift_abc_staff_xyz"
	if id != expected {
		t.Errorf("timesheetDocID = %s, want %s", id, expected)
	}
}
