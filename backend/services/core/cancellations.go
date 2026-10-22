package function

import (
	"context"
	"errors"
	"net/http"
	"slices"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/GoogleCloudPlatform/functions-framework-go/functions"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"kvision.internal/shared/audit"
	"kvision.internal/shared/auth"
	"kvision.internal/shared/httpjson"
	"kvision.internal/shared/outbox"
)

func init() {
	functions.HTTP("CancelShiftStructured", authed(cancelShiftStructured))
}

type cancelShiftStructuredRequest struct {
	ShiftID          string `json:"shiftId"`
	Reason           string `json:"reason"`
	Category         string `json:"category"` // "emergency" | "sickness" | "nursery_operational" | "standard"
	NeedsReplacement bool   `json:"needsReplacement"`
}

// CalculateCancellationCharge is a pure calculator for cancellation fees (Decision 13).
// Default policy produces zero charges until the owner publishes a fee schedule.
func CalculateCancellationCharge(
	shift Shift,
	actorRole Role,
	category string,
	cancelledAt time.Time,
) (int64, int64, int) {
	// Hours before shift start:
	// hoursUntilStart := shift.StartTime.Sub(cancelledAt).Hours()

	// Under Decision 13: All cancellation fees default to 0 pence.
	// Emergency and sickness are always exempted from penalty fees.
	if category == "emergency" || category == "sickness" {
		return 0, 0, 1
	}

	return 0, 0, 1
}

// cancelShiftStructured handles cancellations with audit trail, reasons, and replacement tasks.
func cancelShiftStructured(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	uid := auth.UID(ctx)

	var req cancelShiftStructuredRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	if req.ShiftID == "" || req.Reason == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "shiftId and reason are required")
		return
	}
	if req.Category == "" {
		req.Category = "standard"
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore unavailable")
		return
	}

	shiftRef := db.Collection("shifts").Doc(req.ShiftID)
	now := time.Now()

	var (
		cancellationID string
		chargePence    int64
		compPence      int64
		policyVersion  int
		isReopened     bool
		callerRole     Role
		nurseryID      string
		bookedStaff    []string
	)

	err = db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		snap, err := tx.Get(shiftRef)
		if status.Code(err) == codes.NotFound {
			return errShiftNotFound
		}
		if err != nil {
			return err
		}

		var shift Shift
		if err := snap.DataTo(&shift); err != nil {
			return err
		}

		if shift.Status == ShiftCancelled {
			return errors.New("SHIFT_ALREADY_CANCELLED")
		}

		nurseryID = shift.NurseryID
		booked := shift.BookedStaffIDs
		if booked == nil && shift.BookedStaffID != nil && *shift.BookedStaffID != "" {
			booked = []string{*shift.BookedStaffID}
		}
		bookedStaff = booked

		isNursery := uid == shift.NurseryID
		isStaff := slices.Contains(booked, uid)

		if !isNursery && !isStaff && !isAdmin(ctx) {
			return errNotShiftParty
		}

		if isNursery {
			callerRole = RoleNursery
		} else {
			callerRole = RoleStaff
		}

		chargePence, compPence, policyVersion = CalculateCancellationCharge(shift, callerRole, req.Category, now)

		var shiftUpdates []firestore.Update
		if isNursery {
			shiftUpdates = append(shiftUpdates,
				firestore.Update{Path: "status", Value: ShiftCancelled},
			)
		} else {
			// Staff cancellation
			var remainingBooked []string
			for _, id := range booked {
				if id != uid {
					remainingBooked = append(remainingBooked, id)
				}
			}

			if len(remainingBooked) == 0 {
				if req.NeedsReplacement {
					isReopened = true
					shiftUpdates = append(shiftUpdates,
						firestore.Update{Path: "status", Value: ShiftOpen},
						firestore.Update{Path: "bookedStaffId", Value: firestore.Delete},
						firestore.Update{Path: "bookedStaffIds", Value: []string{}},
					)
				} else {
					shiftUpdates = append(shiftUpdates,
						firestore.Update{Path: "status", Value: ShiftCancelled},
						firestore.Update{Path: "bookedStaffId", Value: firestore.Delete},
						firestore.Update{Path: "bookedStaffIds", Value: []string{}},
					)
				}
			} else {
				// Other staff remain booked on multi-capacity shift
				shiftUpdates = append(shiftUpdates,
					firestore.Update{Path: "bookedStaffIds", Value: remainingBooked},
					firestore.Update{Path: "bookedStaffId", Value: remainingBooked[len(remainingBooked)-1]},
				)
				if int64(len(remainingBooked)) < shift.Capacity {
					shiftUpdates = append(shiftUpdates,
						firestore.Update{Path: "status", Value: ShiftOpen},
					)
					isReopened = true
				}
			}
		}

		if err := tx.Update(shiftRef, shiftUpdates); err != nil {
			return err
		}

		cancelRef := db.Collection("cancellations").NewDoc()
		cancellationID = cancelRef.ID

		cancelDoc := CancellationDoc{
			ShiftID:           req.ShiftID,
			ActorID:           uid,
			ActorRole:         callerRole,
			Reason:            req.Reason,
			Category:          req.Category,
			Timestamp:         now,
			ChargePence:       chargePence,
			CompensationPence: compPence,
			PolicyVersion:     policyVersion,
		}

		if err := tx.Set(cancelRef, cancelDoc); err != nil {
			return err
		}

		// Enqueue cancellation outbox event
		_ = outbox.WriteTx(tx, db, outbox.Event{
			Topic: topicShiftCancelled,
			Payload: map[string]any{
				"shiftId":          req.ShiftID,
				"actorId":          uid,
				"actorRole":        string(callerRole),
				"reason":           req.Reason,
				"category":         req.Category,
				"needsReplacement": req.NeedsReplacement,
				"reopened":         isReopened,
			},
		})

		return nil
	})

	if err != nil {
		if errors.Is(err, errShiftNotFound) {
			httpjson.WriteError(w, http.StatusNotFound, "SHIFT_NOT_FOUND", "Shift not found")
			return
		}
		if errors.Is(err, errNotShiftParty) {
			httpjson.WriteError(w, http.StatusForbidden, "NOT_SHIFT_PARTY", "Not authorized to cancel this shift")
			return
		}
		httpjson.WriteError(w, http.StatusBadRequest, "ERROR", err.Error())
		return
	}

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:    "cancelShiftStructured",
		ActorUID:  uid,
		TargetDoc: "shifts/" + req.ShiftID,
		Metadata: map[string]any{
			"cancellationId":   cancellationID,
			"category":         req.Category,
			"needsReplacement": req.NeedsReplacement,
			"reopened":         isReopened,
		},
	})

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{
		"status":            "cancelled",
		"cancellationId":    cancellationID,
		"reopened":          isReopened,
		"chargePence":       chargePence,
		"compensationPence": compPence,
	})
	_ = nurseryID
	_ = bookedStaff
}
