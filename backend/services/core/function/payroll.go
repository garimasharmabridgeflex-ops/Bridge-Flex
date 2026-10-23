package function

import (
	"context"
	"encoding/csv"
	"fmt"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/GoogleCloudPlatform/functions-framework-go/functions"
	"google.golang.org/api/iterator"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"kvision.internal/shared/audit"
	"kvision.internal/shared/auth"
	"kvision.internal/shared/crypto"
	"kvision.internal/shared/httpjson"
	"kvision.internal/shared/outbox"
)

const (
	topicPayslipAvailable = "payslip-available"
)

func init() {
	functions.HTTP("GetPayrollProfile", authed(getPayrollProfile))
	functions.HTTP("UpdatePayrollProfile", authed(updatePayrollProfile))
	functions.HTTP("GeneratePayrollPeriod", authed(generatePayrollPeriod))
	functions.HTTP("ListPayrollPeriods", authed(listPayrollPeriods))
	functions.HTTP("GetPayrollPeriodDetail", authed(getPayrollPeriodDetail))
	functions.HTTP("ExportPayrollCSV", authed(exportPayrollCSV))
	functions.HTTP("MarkPayrollPeriodPaid", authed(markPayrollPeriodPaid))
	functions.HTTP("GetPractitionerEarnings", authed(getPractitionerEarnings))
	functions.HTTP("LinkPayslip", authed(linkPayslip))
}

func isFinanceOrSuperAdmin(ctx context.Context) bool {
	return auth.HasRole(ctx, auth.AdminRoleFinance, auth.AdminRoleSuperAdmin) || isAdmin(ctx)
}

// CalculateHolidayPayBreakdown computes basic and holiday pay in pence from gross pay in pence.
// When eligible is false, holiday pay is 0 and basic pay equals gross pay.
// When eligible is true, holiday pay is statutory rolled-up accrual (12.07% on basic).
// Gross = Basic * 1.1207 => Basic = round(Gross / 1.1207), HolidayPay = Gross - Basic.
// Golden tests:
// 1700p gross => 1517p basic + 183p holiday pay.
// 1600p gross => 1428p basic + 172p holiday pay.
func CalculateHolidayPayBreakdown(grossPence int64, eligible bool) (basicPence int64, holidayPayPence int64) {
	if !eligible || grossPence <= 0 {
		return grossPence, 0
	}
	basicFloat := float64(grossPence) / 1.1207
	basicPence = int64(basicFloat + 0.5)
	holidayPayPence = grossPence - basicPence
	return basicPence, holidayPayPence
}

func maskAccountNumber(num string) string {
	clean := strings.TrimSpace(num)
	if len(clean) <= 4 {
		return clean
	}
	return "****" + clean[len(clean)-4:]
}

func maskNINumber(ni string) string {
	clean := strings.TrimSpace(ni)
	if len(clean) <= 3 {
		return clean
	}
	return "** ** ** " + clean[len(clean)-2:]
}

// getPayrollProfile — GET /getPayrollProfile?uid=...
// Practitioner views own payroll profile; Finance/SuperAdmin can view any.
func getPayrollProfile(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	callerUID := auth.UID(ctx)
	targetUID := r.URL.Query().Get("uid")
	if targetUID == "" {
		targetUID = callerUID
	}

	if targetUID != callerUID && !isFinanceOrSuperAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "FORBIDDEN", "Only finance or admin can view other profiles")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	doc, err := db.Collection("payrollProfiles").Doc(targetUID).Get(ctx)
	if err != nil {
		if status.Code(err) == codes.NotFound {
			// Return empty profile default
			httpjson.WriteJSON(w, http.StatusOK, PayrollProfile{
				UID:                           targetUID,
				EligibleForRolledUpHolidayPay: false,
			})
			return
		}
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	var p PayrollProfile
	if err := doc.DataTo(&p); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	// Never return raw encrypted fields to client
	p.BankAccountNumberEnc = ""
	p.NationalInsuranceNumberEnc = ""

	httpjson.WriteJSON(w, http.StatusOK, p)
}

type updatePayrollProfileRequest struct {
	UID                           string `json:"uid,omitempty"`
	BankAccountName               string `json:"bankAccountName,omitempty"`
	BankAccountNumber             string `json:"bankAccountNumber,omitempty"`
	BankSortCode                  string `json:"bankSortCode,omitempty"`
	NationalInsuranceNumber       string `json:"nationalInsuranceNumber,omitempty"`
	EligibleForRolledUpHolidayPay *bool  `json:"eligibleForRolledUpHolidayPay,omitempty"`
}

// updatePayrollProfile — POST /updatePayrollProfile.
// Practitioner updates bank details; only Finance role can update eligibility flag.
func updatePayrollProfile(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		httpjson.WriteError(w, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "POST required")
		return
	}

	var req updatePayrollProfileRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}

	ctx := r.Context()
	callerUID := auth.UID(ctx)
	targetUID := req.UID
	if targetUID == "" {
		targetUID = callerUID
	}

	hasFinance := isFinanceOrSuperAdmin(ctx)
	if targetUID != callerUID && !hasFinance {
		httpjson.WriteError(w, http.StatusForbidden, "FORBIDDEN", "Only finance or admin can edit other profiles")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	pRef := db.Collection("payrollProfiles").Doc(targetUID)
	now := time.Now().UTC()

	var existing PayrollProfile
	doc, err := pRef.Get(ctx)
	if err == nil {
		_ = doc.DataTo(&existing)
	}

	existing.UID = targetUID
	existing.UpdatedAt = now
	existing.UpdatedBy = callerUID

	if req.BankAccountName != "" {
		existing.BankAccountName = req.BankAccountName
	}
	if req.BankSortCode != "" {
		existing.BankSortCode = req.BankSortCode
	}

	if req.BankAccountNumber != "" {
		enc, err := crypto.Encrypt(ctx, req.BankAccountNumber)
		if err == nil {
			existing.BankAccountNumberEnc = enc
			existing.BankAccountNumberMasked = maskAccountNumber(req.BankAccountNumber)
		}
	}

	if req.NationalInsuranceNumber != "" {
		enc, err := crypto.Encrypt(ctx, req.NationalInsuranceNumber)
		if err == nil {
			existing.NationalInsuranceNumberEnc = enc
			existing.NationalInsuranceNumberMasked = maskNINumber(req.NationalInsuranceNumber)
		}
	}

	// Decision 6: eligibility flag default off, finance role only
	if req.EligibleForRolledUpHolidayPay != nil {
		if !hasFinance {
			httpjson.WriteError(w, http.StatusForbidden, "FINANCE_ROLE_REQUIRED", "Only finance administrators can modify rolled-up holiday pay eligibility")
			return
		}
		existing.EligibleForRolledUpHolidayPay = *req.EligibleForRolledUpHolidayPay
	}

	if _, err := pRef.Set(ctx, existing); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:    "payroll.update_profile",
		ActorUID:  callerUID,
		TargetUID: targetUID,
		Metadata: map[string]any{
			"eligibleForRolledUpHolidayPay": existing.EligibleForRolledUpHolidayPay,
		},
	})

	// Response sanitization
	existing.BankAccountNumberEnc = ""
	existing.NationalInsuranceNumberEnc = ""

	httpjson.WriteJSON(w, http.StatusOK, existing)
}

type generatePayrollPeriodRequest struct {
	StartDate  time.Time `json:"startDate"`
	EndDate    time.Time `json:"endDate"`
	PeriodName string    `json:"periodName"`
}

// generatePayrollPeriod — POST /generatePayrollPeriod.
// Finance/Admin aggregates approved timesheets into a draft payroll period. Idempotent.
func generatePayrollPeriod(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		httpjson.WriteError(w, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "POST required")
		return
	}

	ctx := r.Context()
	if !isFinanceOrSuperAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "FORBIDDEN", "Finance or SuperAdmin claim required")
		return
	}

	var req generatePayrollPeriodRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}

	if req.StartDate.IsZero() || req.EndDate.IsZero() || !req.EndDate.After(req.StartDate) {
		httpjson.WriteError(w, http.StatusBadRequest, "INVALID_DATES", "Valid startDate and endDate are required")
		return
	}

	if req.PeriodName == "" {
		req.PeriodName = fmt.Sprintf("Payroll %s - %s", req.StartDate.Format("02 Jan"), req.EndDate.Format("02 Jan 2006"))
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	callerUID := auth.UID(ctx)
	now := time.Now().UTC()

	// Query approved or admin-approved timesheets in date range
	iter := db.Collection("timesheets").
		Where("actualEndTime", ">=", req.StartDate).
		Where("actualEndTime", "<=", req.EndDate).
		Documents(ctx)

	type practitionerAgg struct {
		practitionerID string
		timesheetIDs   []string
		billableMins   int64
		grossPayPence  int64
		shiftCount     int
	}

	practitionerMap := make(map[string]*practitionerAgg)

	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			slog.Error("generatePayrollPeriod: iter error", "error", err)
			break
		}

		var ts Timesheet
		if err := doc.DataTo(&ts); err != nil {
			continue
		}

		// Only include approved hours
		if ts.Status != TimesheetApproved && ts.Status != TimesheetAdminApproved {
			continue
		}

		agg, ok := practitionerMap[ts.StaffID]
		if !ok {
			agg = &practitionerAgg{
				practitionerID: ts.StaffID,
				timesheetIDs:   []string{},
			}
			practitionerMap[ts.StaffID] = agg
		}
		agg.timesheetIDs = append(agg.timesheetIDs, doc.Ref.ID)
		agg.billableMins += ts.BillableMinutes
		agg.grossPayPence += ts.TotalGrossPayPence
		agg.shiftCount++
	}

	// Deterministic period ID from date range (ensures idempotent re-runs)
	periodID := fmt.Sprintf("PP-%s-%s", req.StartDate.Format("20060102"), req.EndDate.Format("20060102"))
	periodRef := db.Collection("payrollPeriods").Doc(periodID)

	var totalBillableMins int64
	var totalBasicPence int64
	var totalHolidayPence int64
	var totalGrossPence int64
	var lines []PayrollLine

	batch := db.Batch()

	for staffID, agg := range practitionerMap {
		// Read payroll profile for eligibility and bank details
		var pProfile PayrollProfile
		pDoc, err := db.Collection("payrollProfiles").Doc(staffID).Get(ctx)
		if err == nil {
			_ = pDoc.DataTo(&pProfile)
		}

		// Read user display name from profiles/{uid}
		var name string = "Practitioner " + staffID[:min(6, len(staffID))]
		userDoc, err := db.Collection("profiles").Doc(staffID).Get(ctx)
		if err == nil {
			if n, ok := userDoc.Data()["displayName"].(string); ok && n != "" {
				name = n
			} else if fn, ok := userDoc.Data()["name"].(string); ok && fn != "" {
				name = fn
			}
		}

		basicPence, holidayPence := CalculateHolidayPayBreakdown(agg.grossPayPence, pProfile.EligibleForRolledUpHolidayPay)

		totalBillableMins += agg.billableMins
		totalBasicPence += basicPence
		totalHolidayPence += holidayPence
		totalGrossPence += agg.grossPayPence

		lineID := fmt.Sprintf("line_%s", staffID)
		lineRef := periodRef.Collection("lines").Doc(lineID)

		line := PayrollLine{
			ID:                            lineID,
			PeriodID:                      periodID,
			PractitionerID:                staffID,
			PractitionerName:              name,
			NationalInsuranceNumberMasked: pProfile.NationalInsuranceNumberMasked,
			BankAccountName:               pProfile.BankAccountName,
			BankAccountNumberMasked:       pProfile.BankAccountNumberMasked,
			BankSortCode:                  pProfile.BankSortCode,
			CompletedShiftCount:           agg.shiftCount,
			TotalBillableMinutes:          agg.billableMins,
			BasicPayPence:                 basicPence,
			HolidayPayPence:               holidayPence,
			GrossPayPence:                 agg.grossPayPence,
			EligibleForRolledUpHolidayPay: pProfile.EligibleForRolledUpHolidayPay,
			TimesheetIDs:                  agg.timesheetIDs,
			Status:                        "pending",
			PayrollReference:              fmt.Sprintf("KF-%s-%s", periodID, staffID[:min(6, len(staffID))]),
			CreatedAt:                     now,
			UpdatedAt:                     now,
		}

		lines = append(lines, line)
		batch.Set(lineRef, line)
	}

	period := PayrollPeriod{
		ID:                   periodID,
		PeriodName:           req.PeriodName,
		StartDate:            req.StartDate,
		EndDate:              req.EndDate,
		Status:               PayrollPeriodDraft,
		TotalPractitioners:   len(practitionerMap),
		TotalBillableMinutes: totalBillableMins,
		TotalBasicPayPence:   totalBasicPence,
		TotalHolidayPayPence: totalHolidayPence,
		TotalGrossPayPence:   totalGrossPence,
		CreatedBy:            callerUID,
		CreatedAt:            now,
		UpdatedAt:            now,
	}

	batch.Set(periodRef, period)

	if _, err := batch.Commit(ctx); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:    "payroll.generate_period",
		ActorUID:  callerUID,
		TargetDoc: periodID,
		Metadata: map[string]any{
			"periodId":           periodID,
			"totalPractitioners": len(practitionerMap),
			"totalGrossPayPence": totalGrossPence,
		},
	})

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{
		"period": period,
		"lines":  lines,
	})
}

// listPayrollPeriods — GET /listPayrollPeriods
func listPayrollPeriods(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !isFinanceOrSuperAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "FORBIDDEN", "Finance or SuperAdmin claim required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	iter := db.Collection("payrollPeriods").OrderBy("startDate", firestore.Desc).Limit(50).Documents(ctx)
	var periods []PayrollPeriod
	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		var p PayrollPeriod
		if err := doc.DataTo(&p); err == nil {
			p.ID = doc.Ref.ID
			periods = append(periods, p)
		}
	}

	if periods == nil {
		periods = []PayrollPeriod{}
	}
	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"periods": periods})
}

// getPayrollPeriodDetail — GET /getPayrollPeriodDetail?periodId=...
func getPayrollPeriodDetail(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !isFinanceOrSuperAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "FORBIDDEN", "Finance or SuperAdmin claim required")
		return
	}

	periodID := r.URL.Query().Get("periodId")
	if periodID == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "MISSING_PERIOD_ID", "periodId is required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	periodDoc, err := db.Collection("payrollPeriods").Doc(periodID).Get(ctx)
	if err != nil {
		if status.Code(err) == codes.NotFound {
			httpjson.WriteError(w, http.StatusNotFound, "NOT_FOUND", "Payroll period not found")
			return
		}
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	var period PayrollPeriod
	_ = periodDoc.DataTo(&period)
	period.ID = periodDoc.Ref.ID

	lineDocs, err := periodDoc.Ref.Collection("lines").Documents(ctx).GetAll()
	var lines []PayrollLine
	if err == nil {
		for _, doc := range lineDocs {
			var line PayrollLine
			if err := doc.DataTo(&line); err == nil {
				line.ID = doc.Ref.ID
				lines = append(lines, line)
			}
		}
	}
	if lines == nil {
		lines = []PayrollLine{}
	}

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{
		"period": period,
		"lines":  lines,
	})
}

// exportPayrollCSV — GET /exportPayrollCSV?periodId=...
// Streams standard CSV format for external PAYE software import (Decision 7).
func exportPayrollCSV(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !isFinanceOrSuperAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "FORBIDDEN", "Finance or SuperAdmin claim required")
		return
	}

	periodID := r.URL.Query().Get("periodId")
	if periodID == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "MISSING_PERIOD_ID", "periodId is required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	periodRef := db.Collection("payrollPeriods").Doc(periodID)
	lineDocs, err := periodRef.Collection("lines").Documents(ctx).GetAll()
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	w.Header().Set("Content-Type", "text/csv; charset=utf-8")
	w.Header().Set("Content-Disposition", fmt.Sprintf("attachment; filename=\"payroll-%s.csv\"", periodID))

	writer := csv.NewWriter(w)

	// CSV Header matching Decision 7 & Section 3
	_ = writer.Write([]string{
		"Practitioner ID",
		"Practitioner Name",
		"National Insurance Number",
		"Bank Account Name",
		"Bank Account Number",
		"Sort Code",
		"Payroll Reference",
		"Completed Shifts",
		"Billable Hours",
		"Basic Pay (GBP)",
		"Holiday Pay (GBP)",
		"Gross Pay (GBP)",
		"Rolled Up Holiday Pay Eligible",
		"Status",
		"Payment Date",
	})

	for _, doc := range lineDocs {
		var line PayrollLine
		if err := doc.DataTo(&line); err != nil {
			continue
		}

		// Attempt decrypting bank and NI for PAYE software import if profile exists
		rawNI := line.NationalInsuranceNumberMasked
		rawBank := line.BankAccountNumberMasked
		pDoc, err := db.Collection("payrollProfiles").Doc(line.PractitionerID).Get(ctx)
		if err == nil {
			var pProfile PayrollProfile
			_ = pDoc.DataTo(&pProfile)
			if pProfile.NationalInsuranceNumberEnc != "" {
				if dec, err := crypto.Decrypt(ctx, pProfile.NationalInsuranceNumberEnc); err == nil && dec != "" {
					rawNI = dec
				}
			}
			if pProfile.BankAccountNumberEnc != "" {
				if dec, err := crypto.Decrypt(ctx, pProfile.BankAccountNumberEnc); err == nil && dec != "" {
					rawBank = dec
				}
			}
		}

		paidDateStr := ""
		if line.PaidAt != nil {
			paidDateStr = line.PaidAt.Format("2006-01-02")
		}

		_ = writer.Write([]string{
			line.PractitionerID,
			line.PractitionerName,
			rawNI,
			line.BankAccountName,
			rawBank,
			line.BankSortCode,
			line.PayrollReference,
			fmt.Sprintf("%d", line.CompletedShiftCount),
			fmt.Sprintf("%.2f", float64(line.TotalBillableMinutes)/60.0),
			fmt.Sprintf("%.2f", float64(line.BasicPayPence)/100.0),
			fmt.Sprintf("%.2f", float64(line.HolidayPayPence)/100.0),
			fmt.Sprintf("%.2f", float64(line.GrossPayPence)/100.0),
			fmt.Sprintf("%t", line.EligibleForRolledUpHolidayPay),
			line.Status,
			paidDateStr,
		})
	}

	writer.Flush()

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:    "payroll.export_csv",
		ActorUID:  auth.UID(ctx),
		TargetDoc: periodID,
		Metadata: map[string]any{
			"periodId": periodID,
			"rowCount": len(lineDocs),
		},
	})
}

type markPeriodPaidRequest struct {
	PeriodID string `json:"periodId"`
}

// markPayrollPeriodPaid — POST /markPayrollPeriodPaid
func markPayrollPeriodPaid(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		httpjson.WriteError(w, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "POST required")
		return
	}

	ctx := r.Context()
	if !isFinanceOrSuperAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "FORBIDDEN", "Finance or SuperAdmin claim required")
		return
	}

	var req markPeriodPaidRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	if req.PeriodID == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "MISSING_PERIOD_ID", "periodId is required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	now := time.Now().UTC()
	periodRef := db.Collection("payrollPeriods").Doc(req.PeriodID)

	lineDocs, err := periodRef.Collection("lines").Documents(ctx).GetAll()
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	batch := db.Batch()
	batch.Update(periodRef, []firestore.Update{
		{Path: "status", Value: PayrollPeriodPaid},
		{Path: "paidAt", Value: now},
		{Path: "updatedAt", Value: now},
	})

	for _, doc := range lineDocs {
		batch.Update(doc.Ref, []firestore.Update{
			{Path: "status", Value: "paid"},
			{Path: "paidAt", Value: now},
			{Path: "updatedAt", Value: now},
		})
	}

	if _, err := batch.Commit(ctx); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:    "payroll.mark_paid",
		ActorUID:  auth.UID(ctx),
		TargetDoc: req.PeriodID,
		Metadata: map[string]any{
			"periodId": req.PeriodID,
			"paidAt":   now,
		},
	})

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"status": "paid", "paidAt": now})
}

// getPractitionerEarnings — GET /getPractitionerEarnings
// Returns lifetime completed shifts, hours, gross earnings, and payslips.
func getPractitionerEarnings(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	callerUID := auth.UID(ctx)

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	// Fetch practitioner's payroll profile
	var pProfile PayrollProfile
	pDoc, err := db.Collection("payrollProfiles").Doc(callerUID).Get(ctx)
	if err == nil {
		_ = pDoc.DataTo(&pProfile)
	}

	// Fetch approved timesheets
	tsDocs, err := db.Collection("timesheets").
		Where("staffId", "==", callerUID).
		Documents(ctx).GetAll()

	var totalShifts int
	var totalBillableMins int64
	var totalGrossPence int64
	var approvedTimesheets []Timesheet

	if err == nil {
		for _, doc := range tsDocs {
			var ts Timesheet
			if err := doc.DataTo(&ts); err == nil {
				ts.ID = doc.Ref.ID
				if ts.Status == TimesheetApproved || ts.Status == TimesheetAdminApproved {
					totalShifts++
					totalBillableMins += ts.BillableMinutes
					totalGrossPence += ts.TotalGrossPayPence
					approvedTimesheets = append(approvedTimesheets, ts)
				}
			}
		}
	}

	// Fetch payslips
	payslipDocs, err := db.Collection("payslips").
		Where("practitionerId", "==", callerUID).
		Documents(ctx).GetAll()

	var payslips []Payslip
	if err == nil {
		for _, doc := range payslipDocs {
			var ps Payslip
			if err := doc.DataTo(&ps); err == nil {
				ps.ID = doc.Ref.ID
				payslips = append(payslips, ps)
			}
		}
	}
	if payslips == nil {
		payslips = []Payslip{}
	}
	if approvedTimesheets == nil {
		approvedTimesheets = []Timesheet{}
	}

	totalBasicPence, totalHolidayPence := CalculateHolidayPayBreakdown(totalGrossPence, pProfile.EligibleForRolledUpHolidayPay)

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{
		"totalCompletedShifts":          totalShifts,
		"totalBillableMinutes":          totalBillableMins,
		"totalGrossPayPence":            totalGrossPence,
		"totalBasicPayPence":            totalBasicPence,
		"totalHolidayPayPence":          totalHolidayPence,
		"eligibleForRolledUpHolidayPay": pProfile.EligibleForRolledUpHolidayPay,
		"recentTimesheets":              approvedTimesheets,
		"payslips":                      payslips,
	})
}

type linkPayslipRequest struct {
	PractitionerID string `json:"practitionerId"`
	PeriodID       string `json:"periodId"`
	PeriodName     string `json:"periodName"`
	StoragePath    string `json:"storagePath"`
	FileName       string `json:"fileName"`
}

// linkPayslip — POST /linkPayslip
// Admin uploads a payslip PDF to storage and links it to practitioner.
func linkPayslip(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		httpjson.WriteError(w, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "POST required")
		return
	}

	ctx := r.Context()
	if !isFinanceOrSuperAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "FORBIDDEN", "Finance or SuperAdmin claim required")
		return
	}

	var req linkPayslipRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}

	if req.PractitionerID == "" || req.StoragePath == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "MISSING_FIELDS", "practitionerId and storagePath are required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	callerUID := auth.UID(ctx)
	now := time.Now().UTC()

	payslipID := fmt.Sprintf("ps_%s_%s", req.PractitionerID, req.PeriodID)
	payslip := Payslip{
		ID:             payslipID,
		PractitionerID: req.PractitionerID,
		PeriodID:       req.PeriodID,
		PeriodName:     req.PeriodName,
		StoragePath:    req.StoragePath,
		FileName:       req.FileName,
		UploadedBy:     callerUID,
		UploadedAt:     now,
	}

	_, err = db.Collection("payslips").Doc(payslipID).Set(ctx, payslip)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	// Enqueue notification outbox event
	_ = outbox.WriteTx(nil, db, outbox.Event{
		Topic: topicPayslipAvailable,
		Payload: map[string]any{
			"practitionerId": req.PractitionerID,
			"payslipId":      payslipID,
			"periodName":     req.PeriodName,
		},
	})

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:    "payroll.upload_payslip",
		ActorUID:  callerUID,
		TargetUID: req.PractitionerID,
		Metadata: map[string]any{
			"payslipId": payslipID,
			"periodId":  req.PeriodID,
		},
	})

	httpjson.WriteJSON(w, http.StatusOK, payslip)
}
