package function

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"strconv"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/GoogleCloudPlatform/functions-framework-go/functions"
	"google.golang.org/api/iterator"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"kvision.internal/shared/audit"
	"kvision.internal/shared/auth"
	"kvision.internal/shared/httpjson"
	"kvision.internal/shared/outbox"
	"kvision.internal/shared/scheduler"
)

// Timesheet notification topics
const (
	topicTimesheetSubmitted           = "timesheet-submitted"
	topicTimesheetApproved            = "timesheet-approved"
	topicTimesheetCorrectionRequested = "timesheet-correction-requested"
	topicTimesheetDisputed            = "timesheet-disputed"
	topicTimesheetEscalated           = "timesheet-escalated"
	topicTimesheetAdminApproved       = "timesheet-admin-approved"
)

func init() {
	functions.HTTP("SubmitTimesheet", authed(submitTimesheet))
	functions.HTTP("GetTimesheet", authed(getTimesheet))
	functions.HTTP("ListTimesheets", authed(listTimesheets))
	functions.HTTP("ApproveTimesheet", authed(approveTimesheet))
	functions.HTTP("RequestTimesheetCorrection", authed(requestTimesheetCorrection))
	functions.HTTP("DisputeTimesheet", authed(disputeTimesheet))
	functions.HTTP("AdminApproveTimesheet", authed(adminApproveTimesheet))
	functions.HTTP("EscalateUnresponsiveTimesheets", escalateUnresponsiveTimesheets)
}

func timesheetDocID(shiftID, staffID string) string {
	return fmt.Sprintf("ts_%s_%s", shiftID, staffID)
}

// CalculateTimesheetHoursAndPay computes billable minutes and monetary amounts.
func CalculateTimesheetHoursAndPay(startTime, endTime time.Time, breakMinutes int64, hourlyRatePence, nurseryRatePence int64) (billableMinutes int64, grossPayPence int64, nurseryChargePence int64, err error) {
	if !endTime.After(startTime) {
		return 0, 0, 0, errors.New("endTime must be after startTime")
	}
	if breakMinutes < 0 {
		return 0, 0, 0, errors.New("unpaidBreakMinutes cannot be negative")
	}
	durationMinutes := int64(endTime.Sub(startTime).Minutes())
	if breakMinutes >= durationMinutes {
		return 0, 0, 0, errors.New("unpaidBreakMinutes must be less than total duration")
	}
	billableMinutes = durationMinutes - breakMinutes
	if hourlyRatePence <= 0 {
		hourlyRatePence = 1500
	}
	if nurseryRatePence <= 0 {
		nurseryRatePence = hourlyRatePence
	}
	grossPayPence = (billableMinutes*hourlyRatePence + 30) / 60
	nurseryChargePence = (billableMinutes*nurseryRatePence + 30) / 60
	return billableMinutes, grossPayPence, nurseryChargePence, nil
}

// ShouldEscalateTimesheet returns true if submitted timesheet has exceeded 48 hours without nursery decision (Decision 11).
func ShouldEscalateTimesheet(status TimesheetStatus, submittedAt time.Time, escalatedAt *time.Time, now time.Time) bool {
	if status != TimesheetSubmitted {
		return false
	}
	if escalatedAt != nil {
		return false
	}
	return now.Sub(submittedAt) >= 48*time.Hour
}

type submitTimesheetRequest struct {
	ShiftID            string     `json:"shiftId"`
	ActualStartTime    *time.Time `json:"actualStartTime,omitempty"`
	ActualEndTime      *time.Time `json:"actualEndTime,omitempty"`
	UnpaidBreakMinutes *int64     `json:"unpaidBreakMinutes,omitempty"`
}

// submitTimesheet — POST /submitTimesheet.
// Practitioner submits actual hours worked for a booked shift.
func submitTimesheet(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		httpjson.WriteError(w, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "POST required")
		return
	}

	var req submitTimesheetRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}

	if req.ShiftID == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "MISSING_SHIFT_ID", "shiftId is required")
		return
	}

	ctx := r.Context()
	callerUID := auth.UID(ctx)
	if callerUID == "" {
		httpjson.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "authentication required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	shiftDoc, err := db.Collection("shifts").Doc(req.ShiftID).Get(ctx)
	if err != nil {
		if status.Code(err) == codes.NotFound {
			httpjson.WriteError(w, http.StatusNotFound, "SHIFT_NOT_FOUND", "Shift not found")
			return
		}
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	var shift Shift
	if err := shiftDoc.DataTo(&shift); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "Failed to deserialize shift")
		return
	}

	// Verify caller is assigned practitioner
	isAssigned := false
	if shift.BookedStaffID != nil && *shift.BookedStaffID == callerUID {
		isAssigned = true
	}
	for _, id := range shift.BookedStaffIDs {
		if id == callerUID {
			isAssigned = true
			break
		}
	}
	if !isAssigned {
		httpjson.WriteError(w, http.StatusForbidden, "NOT_ASSIGNED_STAFF", "Only the assigned practitioner can submit a timesheet for this shift")
		return
	}

	// Times & Break calculation
	actualStart := shift.StartTime
	if req.ActualStartTime != nil && !req.ActualStartTime.IsZero() {
		actualStart = *req.ActualStartTime
	}
	actualEnd := shift.EndTime
	if req.ActualEndTime != nil && !req.ActualEndTime.IsZero() {
		actualEnd = *req.ActualEndTime
	}

	breakMins := shift.UnpaidBreakMinutes
	if req.UnpaidBreakMinutes != nil {
		breakMins = *req.UnpaidBreakMinutes
	}

	var hourlyPayPence int64
	var nurseryChargePence int64
	if shift.Financials != nil && shift.Financials.PractitionerPayPencePerHour > 0 {
		hourlyPayPence = shift.Financials.PractitionerPayPencePerHour
		nurseryChargePence = shift.Financials.NurseryChargePencePerHour
	} else if shift.PayRate > 0 {
		hourlyPayPence = int64(shift.PayRate * 100)
		nurseryChargePence = hourlyPayPence
	} else {
		hourlyPayPence = 1500
		nurseryChargePence = 1800
	}

	billableMins, totalGrossPay, totalNurseryCharge, calcErr := CalculateTimesheetHoursAndPay(
		actualStart, actualEnd, breakMins, hourlyPayPence, nurseryChargePence,
	)
	if calcErr != nil {
		httpjson.WriteError(w, http.StatusBadRequest, "INVALID_HOURS", calcErr.Error())
		return
	}

	tsID := timesheetDocID(req.ShiftID, callerUID)
	tsRef := db.Collection("timesheets").Doc(tsID)
	now := time.Now().UTC()

	var result Timesheet
	err = db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		snap, err := tx.Get(tsRef)
		isNew := false
		if err != nil {
			if status.Code(err) == codes.NotFound {
				isNew = true
			} else {
				return err
			}
		}

		if !isNew {
			var existing Timesheet
			if err := snap.DataTo(&existing); err != nil {
				return err
			}
			if existing.Status == TimesheetApproved || existing.Status == TimesheetAdminApproved {
				return errors.New("TIMESHEET_ALREADY_APPROVED")
			}
			if existing.Status == TimesheetSubmitted {
				return errors.New("TIMESHEET_ALREADY_SUBMITTED")
			}
			if existing.Status == TimesheetDisputed {
				return errors.New("TIMESHEET_DISPUTED")
			}
			// If correction_requested, we allow overwriting with new submission
		}

		result = Timesheet{
			ID:                      tsID,
			ShiftID:                 req.ShiftID,
			NurseryID:               shift.NurseryID,
			StaffID:                 callerUID,
			ScheduledStartTime:      shift.StartTime,
			ScheduledEndTime:        shift.EndTime,
			ActualStartTime:         actualStart,
			ActualEndTime:           actualEnd,
			UnpaidBreakMinutes:      breakMins,
			BillableMinutes:         billableMins,
			HourlyRatePence:         hourlyPayPence,
			NurseryHourlyRatePence:  nurseryChargePence,
			TotalGrossPayPence:      totalGrossPay,
			TotalNurseryChargePence: totalNurseryCharge,
			Status:                  TimesheetSubmitted,
			SubmittedAt:             now,
			UpdatedAt:               now,
		}

		if isNew {
			result.CreatedAt = now
		} else {
			var prev Timesheet
			_ = snap.DataTo(&prev)
			result.CreatedAt = prev.CreatedAt
			result.AdminNotes = prev.AdminNotes
		}

		if err := tx.Set(tsRef, result); err != nil {
			return err
		}

		_ = outbox.WriteTx(tx, db, outbox.Event{
			Topic: topicTimesheetSubmitted,
			Payload: map[string]any{
				"timesheetId":        tsID,
				"shiftId":            req.ShiftID,
				"nurseryId":          shift.NurseryID,
				"staffId":            callerUID,
				"billableMinutes":    billableMins,
				"totalGrossPayPence": totalGrossPay,
			},
		})

		return nil
	})

	if err != nil {
		switch err.Error() {
		case "TIMESHEET_ALREADY_APPROVED":
			httpjson.WriteError(w, http.StatusBadRequest, "TIMESHEET_ALREADY_APPROVED", "Timesheet has already been approved")
		case "TIMESHEET_ALREADY_SUBMITTED":
			httpjson.WriteError(w, http.StatusBadRequest, "TIMESHEET_ALREADY_SUBMITTED", "Timesheet already submitted and awaiting review")
		case "TIMESHEET_DISPUTED":
			httpjson.WriteError(w, http.StatusBadRequest, "TIMESHEET_DISPUTED", "Timesheet is currently disputed; awaiting admin review")
		default:
			httpjson.WriteError(w, http.StatusInternalServerError, "TRANSACTION_FAILED", err.Error())
		}
		return
	}

	_ = notifyInApp(ctx, db, shift.NurseryID, "timesheet_submitted",
		"Timesheet submitted",
		fmt.Sprintf("A practitioner submitted a timesheet for shift %s. Tap to review and approve.", shift.Title),
		map[string]any{
			"timesheetId":     tsID,
			"shiftId":         req.ShiftID,
			"staffId":         callerUID,
			"billableMinutes": billableMins,
		},
	)

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:    "timesheet.submit",
		ActorUID:  callerUID,
		TargetUID: shift.NurseryID,
		Metadata: map[string]any{
			"timesheetId":     tsID,
			"shiftId":         req.ShiftID,
			"billableMinutes": billableMins,
			"grossPayPence":   totalGrossPay,
		},
	})

	httpjson.WriteJSON(w, http.StatusOK, result)
}

type approveTimesheetRequest struct {
	TimesheetID string `json:"timesheetId"`
	Feedback    string `json:"feedback,omitempty"`
}

// approveTimesheet — POST /approveTimesheet.
// Nursery approves practitioner's recorded hours.
func approveTimesheet(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		httpjson.WriteError(w, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "POST required")
		return
	}

	var req approveTimesheetRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	if req.TimesheetID == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "MISSING_TIMESHEET_ID", "timesheetId is required")
		return
	}

	ctx := r.Context()
	callerUID := auth.UID(ctx)
	callerIsAdmin := auth.HasRole(ctx, auth.AdminRoleSuperAdmin, auth.AdminRoleSupport, auth.AdminRoleFinance) || isAdmin(ctx)

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	tsRef := db.Collection("timesheets").Doc(req.TimesheetID)
	now := time.Now().UTC()
	var updated Timesheet

	err = db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		snap, err := tx.Get(tsRef)
		if err != nil {
			return err
		}
		if err := snap.DataTo(&updated); err != nil {
			return err
		}

		if updated.NurseryID != callerUID && !callerIsAdmin {
			return errors.New("FORBIDDEN")
		}

		if updated.Status != TimesheetSubmitted && updated.Status != TimesheetCorrectionRequested {
			return errors.New("INVALID_STATE")
		}

		updated.Status = TimesheetApproved
		updated.DecidedAt = &now
		updated.NurseryFeedback = req.Feedback
		updated.UpdatedAt = now

		if err := tx.Set(tsRef, updated); err != nil {
			return err
		}

		_ = outbox.WriteTx(tx, db, outbox.Event{
			Topic: topicTimesheetApproved,
			Payload: map[string]any{
				"timesheetId":        updated.ID,
				"shiftId":            updated.ShiftID,
				"nurseryId":          updated.NurseryID,
				"staffId":            updated.StaffID,
				"totalGrossPayPence": updated.TotalGrossPayPence,
			},
		})

		return nil
	})

	if err != nil {
		if status.Code(err) == codes.NotFound {
			httpjson.WriteError(w, http.StatusNotFound, "NOT_FOUND", "Timesheet not found")
			return
		}
		switch err.Error() {
		case "FORBIDDEN":
			httpjson.WriteError(w, http.StatusForbidden, "FORBIDDEN", "Only the hiring nursery or an admin can approve this timesheet")
		case "INVALID_STATE":
			httpjson.WriteError(w, http.StatusBadRequest, "INVALID_STATE", "Timesheet is not in a submittable or reviewable state")
		default:
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		}
		return
	}

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:    "timesheet.approve",
		ActorUID:  callerUID,
		TargetUID: updated.StaffID,
		Metadata: map[string]any{
			"timesheetId":        updated.ID,
			"shiftId":            updated.ShiftID,
			"totalGrossPayPence": updated.TotalGrossPayPence,
		},
	})

	_ = notifyInApp(ctx, db, updated.StaffID, "timesheet_approved",
		"Timesheet approved",
		fmt.Sprintf("Your timesheet for shift %s has been approved.", updated.ShiftID),
		map[string]any{
			"timesheetId": updated.ID,
			"shiftId":     updated.ShiftID,
		},
	)

	httpjson.WriteJSON(w, http.StatusOK, updated)
}

type requestCorrectionRequest struct {
	TimesheetID string `json:"timesheetId"`
	Feedback    string `json:"feedback"`
}

// requestTimesheetCorrection — POST /requestTimesheetCorrection.
// Nursery reports discrepancy and requests correction.
func requestTimesheetCorrection(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		httpjson.WriteError(w, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "POST required")
		return
	}

	var req requestCorrectionRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	if req.TimesheetID == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "MISSING_TIMESHEET_ID", "timesheetId is required")
		return
	}
	if req.Feedback == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "MISSING_FEEDBACK", "Correction notes/feedback are required")
		return
	}

	ctx := r.Context()
	callerUID := auth.UID(ctx)
	callerIsAdmin := auth.HasRole(ctx, auth.AdminRoleSuperAdmin, auth.AdminRoleSupport) || isAdmin(ctx)

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	tsRef := db.Collection("timesheets").Doc(req.TimesheetID)
	now := time.Now().UTC()
	var updated Timesheet

	err = db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		snap, err := tx.Get(tsRef)
		if err != nil {
			return err
		}
		if err := snap.DataTo(&updated); err != nil {
			return err
		}

		if updated.NurseryID != callerUID && !callerIsAdmin {
			return errors.New("FORBIDDEN")
		}

		if updated.Status != TimesheetSubmitted {
			return errors.New("INVALID_STATE")
		}

		updated.Status = TimesheetCorrectionRequested
		updated.NurseryFeedback = req.Feedback
		updated.UpdatedAt = now

		if err := tx.Set(tsRef, updated); err != nil {
			return err
		}

		_ = outbox.WriteTx(tx, db, outbox.Event{
			Topic: topicTimesheetCorrectionRequested,
			Payload: map[string]any{
				"timesheetId": updated.ID,
				"shiftId":     updated.ShiftID,
				"staffId":     updated.StaffID,
				"feedback":    req.Feedback,
			},
		})

		return nil
	})

	if err != nil {
		if status.Code(err) == codes.NotFound {
			httpjson.WriteError(w, http.StatusNotFound, "NOT_FOUND", "Timesheet not found")
			return
		}
		switch err.Error() {
		case "FORBIDDEN":
			httpjson.WriteError(w, http.StatusForbidden, "FORBIDDEN", "Only the hiring nursery or an admin can request correction")
		case "INVALID_STATE":
			httpjson.WriteError(w, http.StatusBadRequest, "INVALID_STATE", "Timesheet is not in submitted state")
		default:
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		}
		return
	}

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:    "timesheet.correction_requested",
		ActorUID:  callerUID,
		TargetUID: updated.StaffID,
		Metadata: map[string]any{
			"timesheetId": updated.ID,
			"feedback":    req.Feedback,
		},
	})

	_ = notifyInApp(ctx, db, updated.StaffID, "timesheet_correction_requested",
		"Timesheet needs correction",
		fmt.Sprintf("The nursery requested changes to your timesheet: %s", req.Feedback),
		map[string]any{
			"timesheetId": updated.ID,
			"shiftId":     updated.ShiftID,
			"feedback":    req.Feedback,
		},
	)

	httpjson.WriteJSON(w, http.StatusOK, updated)
}

type disputeTimesheetRequest struct {
	TimesheetID string `json:"timesheetId"`
	Reason      string `json:"reason"`
}

// disputeTimesheet — POST /disputeTimesheet.
// Nursery formally reports an attendance/hours dispute (e.g. no-show, early departure).
func disputeTimesheet(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		httpjson.WriteError(w, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "POST required")
		return
	}

	var req disputeTimesheetRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	if req.TimesheetID == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "MISSING_TIMESHEET_ID", "timesheetId is required")
		return
	}
	if req.Reason == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "MISSING_REASON", "Dispute reason is required")
		return
	}

	ctx := r.Context()
	callerUID := auth.UID(ctx)
	callerIsAdmin := auth.HasRole(ctx, auth.AdminRoleSuperAdmin, auth.AdminRoleSupport) || isAdmin(ctx)

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	tsRef := db.Collection("timesheets").Doc(req.TimesheetID)
	now := time.Now().UTC()
	var updated Timesheet

	err = db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		snap, err := tx.Get(tsRef)
		if err != nil {
			return err
		}
		if err := snap.DataTo(&updated); err != nil {
			return err
		}

		if updated.NurseryID != callerUID && !callerIsAdmin {
			return errors.New("FORBIDDEN")
		}

		if updated.Status != TimesheetSubmitted && updated.Status != TimesheetCorrectionRequested {
			return errors.New("INVALID_STATE")
		}

		updated.Status = TimesheetDisputed
		updated.DisputeReason = req.Reason
		updated.UpdatedAt = now

		if err := tx.Set(tsRef, updated); err != nil {
			return err
		}

		_ = outbox.WriteTx(tx, db, outbox.Event{
			Topic: topicTimesheetDisputed,
			Payload: map[string]any{
				"timesheetId": updated.ID,
				"shiftId":     updated.ShiftID,
				"nurseryId":   updated.NurseryID,
				"staffId":     updated.StaffID,
				"reason":      req.Reason,
			},
		})

		return nil
	})

	if err != nil {
		if status.Code(err) == codes.NotFound {
			httpjson.WriteError(w, http.StatusNotFound, "NOT_FOUND", "Timesheet not found")
			return
		}
		switch err.Error() {
		case "FORBIDDEN":
			httpjson.WriteError(w, http.StatusForbidden, "FORBIDDEN", "Only the hiring nursery or an admin can dispute this timesheet")
		case "INVALID_STATE":
			httpjson.WriteError(w, http.StatusBadRequest, "INVALID_STATE", "Timesheet is not in submitted or correction requested state")
		default:
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		}
		return
	}

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:    "timesheet.dispute",
		ActorUID:  callerUID,
		TargetUID: updated.StaffID,
		Metadata: map[string]any{
			"timesheetId": updated.ID,
			"reason":      req.Reason,
		},
	})

	httpjson.WriteJSON(w, http.StatusOK, updated)
}

type adminApproveRequest struct {
	TimesheetID        string     `json:"timesheetId"`
	ActualStartTime    *time.Time `json:"actualStartTime,omitempty"`
	ActualEndTime      *time.Time `json:"actualEndTime,omitempty"`
	UnpaidBreakMinutes *int64     `json:"unpaidBreakMinutes,omitempty"`
	AdminNotes         string     `json:"adminNotes"`
}

// adminApproveTimesheet — POST /adminApproveTimesheet.
// Admin resolves dispute or approves escalated timesheet with optional hours adjustments.
func adminApproveTimesheet(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		httpjson.WriteError(w, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "POST required")
		return
	}

	ctx := r.Context()
	callerUID := auth.UID(ctx)
	isAdminCaller := auth.HasRole(ctx, auth.AdminRoleSuperAdmin, auth.AdminRoleSupport, auth.AdminRoleFinance) || isAdmin(ctx)
	if !isAdminCaller {
		httpjson.WriteError(w, http.StatusForbidden, "NOT_ADMIN", "Administrator claim required")
		return
	}

	var req adminApproveRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	if req.TimesheetID == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "MISSING_TIMESHEET_ID", "timesheetId is required")
		return
	}
	if req.AdminNotes == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "MISSING_ADMIN_NOTES", "adminNotes are required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	tsRef := db.Collection("timesheets").Doc(req.TimesheetID)
	now := time.Now().UTC()
	var updated Timesheet

	err = db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		snap, err := tx.Get(tsRef)
		if err != nil {
			return err
		}
		if err := snap.DataTo(&updated); err != nil {
			return err
		}

		actualStart := updated.ActualStartTime
		if req.ActualStartTime != nil && !req.ActualStartTime.IsZero() {
			actualStart = *req.ActualStartTime
		}
		actualEnd := updated.ActualEndTime
		if req.ActualEndTime != nil && !req.ActualEndTime.IsZero() {
			actualEnd = *req.ActualEndTime
		}
		breakMins := updated.UnpaidBreakMinutes
		if req.UnpaidBreakMinutes != nil {
			breakMins = *req.UnpaidBreakMinutes
		}

		billableMins, totalGrossPay, totalNurseryCharge, calcErr := CalculateTimesheetHoursAndPay(
			actualStart, actualEnd, breakMins, updated.HourlyRatePence, updated.NurseryHourlyRatePence,
		)
		if calcErr != nil {
			return calcErr
		}

		updated.ActualStartTime = actualStart
		updated.ActualEndTime = actualEnd
		updated.UnpaidBreakMinutes = breakMins
		updated.BillableMinutes = billableMins
		updated.TotalGrossPayPence = totalGrossPay
		updated.TotalNurseryChargePence = totalNurseryCharge
		updated.Status = TimesheetAdminApproved
		updated.AdminNotes = req.AdminNotes
		updated.DecidedAt = &now
		updated.UpdatedAt = now

		if err := tx.Set(tsRef, updated); err != nil {
			return err
		}

		_ = outbox.WriteTx(tx, db, outbox.Event{
			Topic: topicTimesheetAdminApproved,
			Payload: map[string]any{
				"timesheetId":        updated.ID,
				"shiftId":            updated.ShiftID,
				"nurseryId":          updated.NurseryID,
				"staffId":            updated.StaffID,
				"totalGrossPayPence": updated.TotalGrossPayPence,
				"adminNotes":         req.AdminNotes,
			},
		})

		return nil
	})

	if err != nil {
		if status.Code(err) == codes.NotFound {
			httpjson.WriteError(w, http.StatusNotFound, "NOT_FOUND", "Timesheet not found")
			return
		}
		httpjson.WriteError(w, http.StatusBadRequest, "ADMIN_APPROVE_FAILED", err.Error())
		return
	}

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:    "timesheet.admin_approve",
		ActorUID:  callerUID,
		TargetUID: updated.StaffID,
		Metadata: map[string]any{
			"timesheetId":        updated.ID,
			"adminNotes":         req.AdminNotes,
			"totalGrossPayPence": updated.TotalGrossPayPence,
		},
	})

	httpjson.WriteJSON(w, http.StatusOK, updated)
}

// getTimesheet — GET /getTimesheet?timesheetId=... or ?shiftId=...&staffId=...
func getTimesheet(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	callerUID := auth.UID(ctx)
	callerIsAdmin := auth.HasRole(ctx, auth.AdminRoleSuperAdmin, auth.AdminRoleSupport, auth.AdminRoleFinance) || isAdmin(ctx)

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	timesheetID := r.URL.Query().Get("timesheetId")
	shiftID := r.URL.Query().Get("shiftId")
	staffID := r.URL.Query().Get("staffId")

	var ts Timesheet
	if timesheetID != "" {
		snap, err := db.Collection("timesheets").Doc(timesheetID).Get(ctx)
		if err != nil {
			if status.Code(err) == codes.NotFound {
				httpjson.WriteError(w, http.StatusNotFound, "NOT_FOUND", "Timesheet not found")
				return
			}
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		if err := snap.DataTo(&ts); err != nil {
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		ts.ID = snap.Ref.ID
	} else if shiftID != "" {
		targetStaffID := staffID
		if targetStaffID == "" && !callerIsAdmin {
			targetStaffID = callerUID
		}

		if targetStaffID != "" {
			docID := timesheetDocID(shiftID, targetStaffID)
			snap, err := db.Collection("timesheets").Doc(docID).Get(ctx)
			if err != nil {
				if status.Code(err) == codes.NotFound {
					httpjson.WriteError(w, http.StatusNotFound, "NOT_FOUND", "Timesheet not found for this shift")
					return
				}
				httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
				return
			}
			if err := snap.DataTo(&ts); err != nil {
				httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
				return
			}
			ts.ID = snap.Ref.ID
		} else {
			// Query shift's timesheet
			docs, err := db.Collection("timesheets").Where("shiftId", "==", shiftID).Limit(1).Documents(ctx).GetAll()
			if err != nil {
				httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
				return
			}
			if len(docs) == 0 {
				httpjson.WriteError(w, http.StatusNotFound, "NOT_FOUND", "Timesheet not found for this shift")
				return
			}
			if err := docs[0].DataTo(&ts); err != nil {
				httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
				return
			}
			ts.ID = docs[0].Ref.ID
		}
	} else {
		httpjson.WriteError(w, http.StatusBadRequest, "MISSING_PARAM", "Either timesheetId or shiftId is required")
		return
	}

	if ts.StaffID != callerUID && ts.NurseryID != callerUID && !callerIsAdmin {
		httpjson.WriteError(w, http.StatusForbidden, "FORBIDDEN", "Not authorized to view this timesheet")
		return
	}

	httpjson.WriteJSON(w, http.StatusOK, ts)
}

// listTimesheets — GET /listTimesheets?shiftId=...&staffId=...&nurseryId=...&status=...&limit=...
func listTimesheets(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	callerUID := auth.UID(ctx)
	callerIsAdmin := auth.HasRole(ctx, auth.AdminRoleSuperAdmin, auth.AdminRoleSupport, auth.AdminRoleFinance) || isAdmin(ctx)

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	q := db.Collection("timesheets").Query

	shiftID := r.URL.Query().Get("shiftId")
	if shiftID != "" {
		q = q.Where("shiftId", "==", shiftID)
	}

	staffID := r.URL.Query().Get("staffId")
	if staffID != "" {
		if !callerIsAdmin && staffID != callerUID {
			httpjson.WriteError(w, http.StatusForbidden, "FORBIDDEN", "Cannot view other practitioners' timesheets")
			return
		}
		q = q.Where("staffId", "==", staffID)
	}

	nurseryID := r.URL.Query().Get("nurseryId")
	if nurseryID != "" {
		if !callerIsAdmin && nurseryID != callerUID {
			httpjson.WriteError(w, http.StatusForbidden, "FORBIDDEN", "Cannot view other nurseries' timesheets")
			return
		}
		q = q.Where("nurseryId", "==", nurseryID)
	}

	statusFilter := r.URL.Query().Get("status")
	if statusFilter != "" {
		q = q.Where("status", "==", statusFilter)
	}

	limit := 50
	if l := r.URL.Query().Get("limit"); l != "" {
		if parsed, err := strconv.Atoi(l); err == nil && parsed > 0 && parsed <= 100 {
			limit = parsed
		}
	}
	q = q.Limit(limit)

	iter := q.Documents(ctx)
	var out []Timesheet
	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		var item Timesheet
		if err := doc.DataTo(&item); err == nil {
			item.ID = doc.Ref.ID
			// Secondary access check
			if callerIsAdmin || item.StaffID == callerUID || item.NurseryID == callerUID {
				out = append(out, item)
			}
		}
	}

	if out == nil {
		out = []Timesheet{}
	}
	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"timesheets": out})
}

// escalateUnresponsiveTimesheets — POST /escalateUnresponsiveTimesheets.
// Implements Payable Hours Rule (Decision 11):
// After 48 hours without a nursery response, timesheets auto-escalate to the admin queue.
// Callable by Cloud Scheduler or by an administrator. Idempotent.
func escalateUnresponsiveTimesheets(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		httpjson.WriteError(w, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "POST required")
		return
	}

	ctx := r.Context()
	isEmulator := os.Getenv("FUNCTIONS_EMULATOR") == "true" || os.Getenv("FIRESTORE_EMULATOR_HOST") != ""
	isScheduler := false
	if !isEmulator {
		if _, err := scheduler.VerifyOIDCToken(ctx, r, ""); err == nil {
			isScheduler = true
		}
	} else {
		isScheduler = true
	}

	// This handler is intentionally callable by Cloud Scheduler (no Firebase
	// auth middleware), so reading the uid must not panic on a bare context.
	callerUID := safeCallerUID(ctx)
	callerIsAdmin := auth.HasRole(ctx, auth.AdminRoleSuperAdmin, auth.AdminRoleSupport, auth.AdminRoleFinance) || isAdmin(ctx)

	if !isScheduler && !callerIsAdmin {
		httpjson.WriteError(w, http.StatusForbidden, "FORBIDDEN", "Cloud Scheduler or Admin authorization required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	now := time.Now().UTC()
	cutoff := now.Add(-48 * time.Hour)

	// Query timesheets submitted > 48h ago
	iter := db.Collection("timesheets").
		Where("status", "==", string(TimesheetSubmitted)).
		Where("submittedAt", "<=", cutoff).
		Documents(ctx)

	escalatedCount := 0
	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			slog.Error("escalateUnresponsiveTimesheets: iterator error", "error", err)
			break
		}

		var ts Timesheet
		if err := doc.DataTo(&ts); err != nil {
			continue
		}

		// Idempotency check: skip if already marked as escalated
		if ts.EscalatedAt != nil {
			continue
		}

		err = db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
			if err := tx.Update(doc.Ref, []firestore.Update{
				{Path: "escalatedAt", Value: now},
				{Path: "updatedAt", Value: now},
			}); err != nil {
				return err
			}

			_ = outbox.WriteTx(tx, db, outbox.Event{
				Topic: topicTimesheetEscalated,
				Payload: map[string]any{
					"timesheetId":        doc.Ref.ID,
					"shiftId":            ts.ShiftID,
					"nurseryId":          ts.NurseryID,
					"staffId":            ts.StaffID,
					"submittedAt":        ts.SubmittedAt,
					"billableMinutes":    ts.BillableMinutes,
					"totalGrossPayPence": ts.TotalGrossPayPence,
				},
			})

			return nil
		})

		if err == nil {
			escalatedCount++
			_ = audit.WriteAudit(ctx, db, audit.Entry{
				Action:    "timesheet.escalated_48h",
				ActorUID:  callerUID,
				TargetUID: ts.StaffID,
				Metadata: map[string]any{
					"timesheetId": doc.Ref.ID,
					"shiftId":     ts.ShiftID,
					"nurseryId":   ts.NurseryID,
				},
			})
		}
	}

	slog.Info("escalateUnresponsiveTimesheets completed", "escalatedCount", escalatedCount)
	httpjson.WriteJSON(w, http.StatusOK, map[string]any{
		"escalatedCount": escalatedCount,
		"timestamp":      now.Format(time.RFC3339),
	})
}
