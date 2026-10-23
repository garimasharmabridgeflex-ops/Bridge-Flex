package function

import (
	"testing"
)

func TestCalculateHolidayPayBreakdown_GoldenTests(t *testing.T) {
	// Golden test 1: £17.00 gives £15.17 basic and £1.83 holiday pay
	gross17 := int64(1700)
	basic17, holiday17 := CalculateHolidayPayBreakdown(gross17, true)
	if basic17 != 1517 {
		t.Errorf("basic17 = %d, want 1517", basic17)
	}
	if holiday17 != 183 {
		t.Errorf("holiday17 = %d, want 183", holiday17)
	}
	if basic17+holiday17 != gross17 {
		t.Errorf("sum (%d) != gross (%d)", basic17+holiday17, gross17)
	}

	// Golden test 2: £16.00 gives £14.28 basic and £1.72 holiday pay
	gross16 := int64(1600)
	basic16, holiday16 := CalculateHolidayPayBreakdown(gross16, true)
	if basic16 != 1428 {
		t.Errorf("basic16 = %d, want 1428", basic16)
	}
	if holiday16 != 172 {
		t.Errorf("holiday16 = %d, want 172", holiday16)
	}
	if basic16+holiday16 != gross16 {
		t.Errorf("sum (%d) != gross (%d)", basic16+holiday16, gross16)
	}

	// Golden test 3: Non-eligible worker shows NO holiday pay
	basicNonEligible, holidayNonEligible := CalculateHolidayPayBreakdown(gross17, false)
	if basicNonEligible != 1700 {
		t.Errorf("basicNonEligible = %d, want 1700", basicNonEligible)
	}
	if holidayNonEligible != 0 {
		t.Errorf("holidayNonEligible = %d, want 0", holidayNonEligible)
	}
	if basicNonEligible+holidayNonEligible != gross17 {
		t.Errorf("sum (%d) != gross (%d)", basicNonEligible+holidayNonEligible, gross17)
	}
}

func TestCalculateHolidayPayBreakdown_Invariants(t *testing.T) {
	testAmounts := []int64{100, 500, 1250, 1700, 1600, 2500, 12750, 35000}
	for _, amt := range testAmounts {
		// With eligibility true
		basic, holiday := CalculateHolidayPayBreakdown(amt, true)
		if basic+holiday != amt {
			t.Errorf("invariant violated for %d: basic %d + holiday %d = %d", amt, basic, holiday, basic+holiday)
		}
		if basic <= 0 || holiday < 0 {
			t.Errorf("negative parts for %d: basic=%d, holiday=%d", amt, basic, holiday)
		}

		// With eligibility false
		basicOff, holidayOff := CalculateHolidayPayBreakdown(amt, false)
		if basicOff != amt || holidayOff != 0 {
			t.Errorf("ineligible failed for %d: basic=%d, holiday=%d", amt, basicOff, holidayOff)
		}
	}
}

func TestMaskingHelpers(t *testing.T) {
	maskedAcc := maskAccountNumber("12345678")
	if maskedAcc != "****5678" {
		t.Errorf("maskAccountNumber = %s, want ****5678", maskedAcc)
	}

	maskedNI := maskNINumber("QQ123456A")
	if maskedNI != "** ** ** 6A" {
		t.Errorf("maskNINumber = %s, want ** ** ** 6A", maskedNI)
	}
}
