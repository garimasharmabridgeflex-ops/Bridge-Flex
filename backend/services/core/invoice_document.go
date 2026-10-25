package function

import (
	"context"
	"fmt"
	"net/http"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/GoogleCloudPlatform/functions-framework-go/functions"
	"github.com/go-pdf/fpdf"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"kvision.internal/shared/audit"
	"kvision.internal/shared/auth"
	"kvision.internal/shared/httpjson"
)

func init() {
	functions.HTTP("GetInvoiceDocument", authed(getInvoiceDocument))
}

// getInvoiceDocument — GET /getInvoiceDocument?invoiceId=...
//
// Returns the invoice as a PDF attachment, so a nursery (or an admin) can
// download and keep it — the owner's brief asks for downloadable invoices and
// the implementation plan's Phase 9 item 4 asks specifically for a PDF export.
// Access is the same rule as GetInvoice: the invoice's own nursery, or an
// admin.
func getInvoiceDocument(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	callerUID := auth.UID(ctx)
	invoiceID := r.URL.Query().Get("invoiceId")
	if invoiceID == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "MISSING_INVOICE_ID", "invoiceId is required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore unavailable")
		return
	}

	doc, err := db.Collection("invoices").Doc(invoiceID).Get(ctx)
	if status.Code(err) == codes.NotFound {
		httpjson.WriteError(w, http.StatusNotFound, "NOT_FOUND", "Invoice not found")
		return
	}
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	var inv Invoice
	_ = doc.DataTo(&inv)
	inv.ID = doc.Ref.ID
	if inv.NurseryID != callerUID && !isAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "NOT_INVOICE_OWNER", "Not authorized to download this invoice")
		return
	}

	company := loadCompanyConfig(ctx, db)
	pdf := renderInvoicePDF(inv, company)
	if pdf.Err() {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "pdf render failed")
		return
	}

	filename := inv.InvoiceNumber
	if filename == "" {
		filename = inv.ID
	}
	w.Header().Set("Content-Type", "application/pdf")
	w.Header().Set("Content-Disposition", fmt.Sprintf("attachment; filename=%q", "KFlex-"+filename+".pdf"))
	w.Header().Set("Cache-Control", "no-store")
	if err := pdf.Output(w); err != nil {
		return // headers are already written; nothing useful left to say
	}

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:    "getInvoiceDocument",
		ActorUID:  callerUID,
		TargetDoc: "invoices/" + inv.ID,
		Metadata:  map[string]any{"invoiceNumber": inv.InvoiceNumber},
	})
}

// loadCompanyConfig reads platformConfig/company. Every field is used here
// (not just the published ones): the invoice is a document K Flex issues to a
// party it already has a contract with, and an invoice that omits the issuer's
// company number would be wrong. The public GetCompanyInfo read stays
// published-only.
func loadCompanyConfig(ctx context.Context, db *firestore.Client) CompanyConfig {
	var conf CompanyConfig
	if db == nil {
		return conf
	}
	snap, err := db.Doc(companyConfigDoc).Get(ctx)
	if err != nil {
		return conf
	}
	_ = snap.DataTo(&conf)
	return conf
}

// latin1 keeps fpdf's core (Windows-1252) fonts from erroring on runes they
// cannot draw — a nursery name with an emoji or a CJK character should still
// produce a PDF rather than a 500.
func latin1(s string) string {
	var b strings.Builder
	for _, r := range s {
		if r <= 0xFF {
			b.WriteRune(r)
			continue
		}
		switch r {
		case '–', '—':
			b.WriteRune('-')
		case '‘', '’':
			b.WriteRune('\'')
		case '“', '”':
			b.WriteRune('"')
		case '…':
			b.WriteRune('.')
		case '£':
			b.WriteRune('£')
		default:
			b.WriteRune('?')
		}
	}
	return b.String()
}

func pence(amount int64) string {
	return fmt.Sprintf("£%d.%02d", amount/100, amount%100)
}

func pdfDate(t time.Time) string {
	if t.IsZero() {
		return "—"
	}
	return t.In(time.UTC).Format("02 Jan 2006")
}

// renderInvoicePDF builds the whole document. Kept separate from the handler
// so the layout can be exercised in tests without an HTTP round trip.
func renderInvoicePDF(inv Invoice, company CompanyConfig) *fpdf.Fpdf {
	pdf := fpdf.New("P", "mm", "A4", "")
	pdf.SetMargins(18, 16, 18)
	pdf.SetAutoPageBreak(true, 20)
	pdf.AddPage()

	brand := company.CompanyName.Value
	if brand == "" {
		brand = "K Flex"
	}

	// Header band: brand left, INVOICE right.
	pdf.SetFont("Helvetica", "B", 22)
	pdf.SetTextColor(27, 42, 74) // #1B2A4A
	pdf.Cell(110, 10, latin1(brand))
	pdf.SetFont("Helvetica", "B", 20)
	pdf.SetTextColor(100, 116, 139)
	pdf.Cell(0, 10, "INVOICE")
	pdf.Ln(14)

	pdf.SetDrawColor(226, 232, 240)
	pdf.SetLineWidth(0.4)
	pdf.Line(18, pdf.GetY(), 192, pdf.GetY())
	pdf.Ln(6)

	// Issuer block.
	pdf.SetFont("Helvetica", "", 9)
	pdf.SetTextColor(100, 116, 139)
	for _, line := range issuerLines(company, brand) {
		pdf.Cell(0, 5, latin1(line))
		pdf.Ln(5)
	}
	pdf.Ln(3)

	// Bill-to + meta side by side.
	y := pdf.GetY()
	pdf.SetXY(18, y)
	pdf.SetFont("Helvetica", "B", 10)
	pdf.SetTextColor(15, 23, 42)
	pdf.Cell(95, 6, "Billed to")
	pdf.SetXY(120, y)
	pdf.Cell(0, 6, "Invoice details")
	pdf.Ln(7)

	pdf.SetFont("Helvetica", "", 9.5)
	pdf.SetTextColor(15, 23, 42)
	left := []string{inv.NurseryName, inv.BillingAddress, inv.BillingEmail}
	right := []string{
		"Number:  " + valueOr(inv.InvoiceNumber, inv.ID),
		"Issued:  " + pdfDate(inv.IssueDate),
		"Due:     " + pdfDate(inv.DueDate),
		"Status:  " + strings.ToUpper(string(inv.Status)),
	}
	for i := 0; i < len(left) || i < len(right); i++ {
		if i < len(left) && left[i] != "" {
			pdf.SetXY(18, pdf.GetY())
			pdf.Cell(95, 5.5, latin1(left[i]))
		}
		if i < len(right) {
			pdf.SetXY(120, pdf.GetY())
			pdf.Cell(0, 5.5, latin1(right[i]))
		}
		pdf.Ln(6)
	}
	pdf.Ln(4)

	// Line items.
	pdf.SetFont("Helvetica", "B", 9)
	pdf.SetFillColor(241, 245, 249)
	pdf.SetTextColor(15, 23, 42)
	colX := []float64{18, 118, 140, 162}
	headers := []string{"Description", "Qty", "Unit price", "Amount"}
	widths := []float64{100, 22, 22, 30}
	for i, h := range headers {
		pdf.SetX(colX[i])
		pdf.CellFormat(widths[i], 8, h, "1", 0, "L", true, 0, "")
	}
	pdf.Ln(-1)

	pdf.SetFont("Helvetica", "", 9.5)
	for i, item := range inv.LineItems {
		if i%2 == 1 {
			pdf.SetFillColor(248, 250, 252)
		} else {
			pdf.SetFillColor(255, 255, 255)
		}
		desc := latin1(item.Description)
		if item.Type != "" && item.Type != "staffing" {
			desc = fmt.Sprintf("%s (%s)", desc, item.Type)
		}
		pdf.CellFormat(widths[0], 7, truncate(desc, 62), "1", 0, "L", true, 0, "")
		pdf.CellFormat(widths[1], 7, fmt.Sprintf("%.2f", item.Quantity), "1", 0, "R", true, 0, "")
		pdf.CellFormat(widths[2], 7, pence(item.UnitPence), "1", 0, "R", true, 0, "")
		pdf.CellFormat(widths[3], 7, pence(item.TotalPence), "1", 0, "R", true, 0, "")
		pdf.Ln(-1)
	}
	if len(inv.LineItems) == 0 {
		pdf.CellFormat(130, 7, "No line items", "1", 0, "L", true, 0, "")
		pdf.CellFormat(62, 7, "", "1", 0, "L", true, 0, "")
		pdf.Ln(-1)
	}
	pdf.Ln(5)

	// Totals.
	pdf.SetX(118)
	pdf.SetFont("Helvetica", "", 9.5)
	pdf.SetTextColor(100, 116, 139)
	pdf.Cell(38, 6, "Subtotal (ex VAT)")
	pdf.Cell(36, 6, pence(inv.SubtotalPence))
	pdf.Ln(7)
	if inv.VATPence > 0 || inv.VATRate > 0 {
		pdf.SetX(118)
		pdf.Cell(38, 6, fmt.Sprintf("VAT (%.0f%%)", inv.VATRate*100))
		pdf.Cell(36, 6, pence(inv.VATPence))
		pdf.Ln(7)
	}
	pdf.SetX(118)
	pdf.SetFont("Helvetica", "B", 11)
	pdf.SetTextColor(15, 23, 42)
	pdf.Cell(38, 8, "Total due")
	pdf.Cell(36, 8, pence(inv.TotalPence))
	pdf.Ln(12)

	// Payment block.
	pdf.SetFillColor(241, 245, 249)
	pdf.SetFont("Helvetica", "B", 9.5)
	pdf.CellFormat(174, 7, "Payment", "1", 0, "L", true, 0, "")
	pdf.Ln(-1)
	pdf.SetFont("Helvetica", "", 9.5)
	payment := []string{
		"Method:  " + valueOr(inv.PaymentMethod, "bank transfer"),
		"Reference:  " + valueOr(inv.PaymentReference, "quote the invoice number when paying"),
	}
	if inv.Status == InvoicePaid {
		payment = append(payment, "Paid on:  "+pdfDate(*inv.PaidAt))
	}
	for _, line := range payment {
		pdf.CellFormat(174, 6, latin1(line), "1", 0, "L", false, 0, "")
		pdf.Ln(-1)
	}
	if inv.Notes != "" {
		pdf.Ln(3)
		pdf.SetFont("Helvetica", "I", 9)
		pdf.SetTextColor(100, 116, 139)
		pdf.MultiCell(174, 5, latin1(inv.Notes), "", "L", false)
	}

	// Footer.
	pdf.Ln(6)
	pdf.SetFont("Helvetica", "", 8)
	pdf.SetTextColor(148, 163, 184)
	pdf.MultiCell(174, 4.5,
		"Generated by K Flex on "+time.Now().UTC().Format("02 Jan 2006 15:04 UTC")+
			". Subscription charges and staffing charges are billed separately.",
		"", "L", false)

	return pdf
}

func issuerLines(company CompanyConfig, brand string) []string {
	lines := []string{}
	appendIf := func(v string) {
		if v != "" {
			lines = append(lines, v)
		}
	}
	appendIf(brand)
	appendIf(company.Address.Value)
	if company.CompanyNumber.Value != "" {
		appendIf("Company number: " + company.CompanyNumber.Value)
	}
	if company.VATNumber.Value != "" {
		appendIf("VAT number: " + company.VATNumber.Value)
	}
	if company.Email.Value != "" {
		appendIf(company.Email.Value)
	}
	if company.Phone.Value != "" {
		appendIf(company.Phone.Value)
	}
	if len(lines) == 0 {
		return []string{"K Flex"}
	}
	return lines
}

// truncate keeps a cell's text inside its column — fpdf draws cell text
// without clipping, so an over-long description would run into the next one.
func truncate(s string, max int) string {
	r := []rune(s)
	if len(r) <= max {
		return s
	}
	return string(r[:max-3]) + "..."
}

func valueOr(v, fallback string) string {
	if strings.TrimSpace(v) == "" {
		return fallback
	}
	return v
}
