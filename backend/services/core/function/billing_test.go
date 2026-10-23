package function

import (
	"context"
	"testing"
)

func TestDefaultPlans(t *testing.T) {
	plans := defaultPlans()
	if len(plans) != 4 {
		t.Fatalf("expected 4 default plans, got %d", len(plans))
	}

	planMap := make(map[string]Plan)
	for _, p := range plans {
		planMap[p.ID] = p
	}

	// Trial
	trial, ok := planMap["trial"]
	if !ok || trial.PricePence != 0 || trial.TrialDays != 14 || !trial.Active {
		t.Errorf("trial plan incorrect: %+v", trial)
	}

	// Standard £199.00
	std, ok := planMap["standard"]
	if !ok || std.PricePence != 19900 || !std.Active {
		t.Errorf("standard plan incorrect: %+v", std)
	}

	// Premium £299.00
	prem, ok := planMap["premium"]
	if !ok || prem.PricePence != 29900 || !prem.Active {
		t.Errorf("premium plan incorrect: %+v", prem)
	}

	// Pay As You Go £9.99
	payg, ok := planMap["payg"]
	if !ok || payg.PricePence != 999 || !payg.Active {
		t.Errorf("payg plan incorrect: %+v", payg)
	}
}

func TestCalculateInvoiceAmounts_WithAndWithoutVAT(t *testing.T) {
	lineItems := []InvoiceLineItem{
		{
			Type:       "staffing",
			Quantity:   8.0,
			UnitPence:  1950,
			TotalPence: 15600, // £156.00
		},
		{
			Type:       "staffing",
			Quantity:   4.0,
			UnitPence:  1950,
			TotalPence: 7800, // £78.00
		},
	}

	// Case 1: VAT published == false (Decision 4: show VAT only when published)
	sub1, rate1, vat1, total1 := CalculateInvoiceAmounts(lineItems, false)
	if sub1 != 23400 {
		t.Errorf("subtotal = %d, want 23400 (£234.00)", sub1)
	}
	if vat1 != 0 || rate1 != 0.0 {
		t.Errorf("expected 0 VAT when unpublished, got %d (rate %.2f)", vat1, rate1)
	}
	if total1 != 23400 {
		t.Errorf("total = %d, want 23400", total1)
	}

	// Case 2: VAT published == true (20% standard VAT)
	// Subtotal = 23400 pence. 20% VAT = 4680 pence. Total = 28080 pence (£280.80)
	sub2, rate2, vat2, total2 := CalculateInvoiceAmounts(lineItems, true)
	if sub2 != 23400 {
		t.Errorf("subtotal = %d, want 23400", sub2)
	}
	if rate2 != 0.20 {
		t.Errorf("vatRate = %.2f, want 0.20", rate2)
	}
	if vat2 != 4680 {
		t.Errorf("vatPence = %d, want 4680", vat2)
	}
	if total2 != 28080 {
		t.Errorf("totalPence = %d, want 28080", total2)
	}
}

func TestGenerateNextInvoiceNumberFallback(t *testing.T) {
	// With nil firestore client (unit test fallback)
	invNum, err := GenerateNextInvoiceNumber(context.Background(), nil, 2026)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if invNum != "INV-2026-0001" {
		t.Errorf("invoiceNumber = %s, want INV-2026-0001", invNum)
	}
}
