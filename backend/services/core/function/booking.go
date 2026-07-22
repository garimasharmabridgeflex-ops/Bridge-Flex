package function

import (
	"context"
	"errors"
	"net/http"

	"cloud.google.com/go/firestore"
	"github.com/GoogleCloudPlatform/functions-framework-go/functions"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"bridgeflex/shared/auth"
	"bridgeflex/shared/httpjson"
)

func init() {
	functions.HTTP("AcceptShift", authed(acceptShift))
	functions.HTTP("CancelShift", authed(cancelShift))
}

// Sentinel errors returned from inside the acceptShift transaction, mapped to
// the exact error-code contract from ARCHITECTURE.md v2 §4. The codes/
// meanings are unchanged from the originally approved design — only the
// transport (this JSON envelope instead of HttpsError) changed for Go.
var (
	errShiftNotFound      = errors.New("SHIFT_NOT_FOUND")
	errShiftAlreadyBooked = errors.New("SHIFT_ALREADY_BOOKED")
	errCannotBookOwnShift = errors.New("CANNOT_BOOK_OWN_SHIFT")
	errNotShiftParty      = errors.New("NOT_SHIFT_PARTY")
)

type acceptShiftRequest struct {
	ShiftID string `json:"shiftId"`
}

type shiftBookedMessage struct {
	ShiftID   string `json:"shiftId"`
	NurseryID string `json:"nurseryId"`
	StaffID   string `json:"staffId"`
}

// acceptShift — POST /acceptShift. See ARCHITECTURE.md v2 §4 for the full
// walkthrough: this is the one place status/bookedStaffId are ever set, and
// it MUST be a Firestore transaction — a plain read-then-write would let two
// staff members racing on the same shift both "win", corrupting the doc.
func acceptShift(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	uid := auth.UID(ctx)

	var req acceptShiftRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	if req.ShiftID == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "shiftId is required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	// role check happens outside the transaction — it reads a doc (the
	// caller's own profile) that isn't part of the mutation.
	if err := requireRole(ctx, db, uid, RoleStaff); err != nil {
		writeRoleError(w, err)
		return
	}

	ref := db.Collection("shifts").Doc(req.ShiftID)
	var nurseryID string

	err = db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		snap, err := tx.Get(ref)
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
		if shift.Status != ShiftOpen {
			return errShiftAlreadyBooked
		}
		if shift.NurseryID == uid {
			return errCannotBookOwnShift
		}
		nurseryID = shift.NurseryID
		return tx.Update(ref, []firestore.Update{
			{Path: "status", Value: string(ShiftBooked)},
			{Path: "bookedStaffId", Value: uid},
		})
	})

	if err != nil {
		switch err {
		case errShiftNotFound:
			httpjson.WriteError(w, http.StatusNotFound, "SHIFT_NOT_FOUND", "Shift not found")
		case errShiftAlreadyBooked:
			httpjson.WriteError(w, http.StatusConflict, "SHIFT_ALREADY_BOOKED", "This shift is no longer available")
		case errCannotBookOwnShift:
			httpjson.WriteError(w, http.StatusConflict, "CANNOT_BOOK_OWN_SHIFT", "You cannot accept your own shift")
		default:
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		}
		return
	}

	// Publish AFTER commit succeeds — never inside the transaction (§4/§1).
	// A publish failure doesn't roll back the booking; it stands, and a
	// retry/backfill mechanism (not modeled in Phase 1) is the right fix.
	_ = publish(ctx, topicShiftBooked, shiftBookedMessage{
		ShiftID:   req.ShiftID,
		NurseryID: nurseryID,
		StaffID:   uid,
	})

	httpjson.WriteJSON(w, http.StatusOK, map[string]string{"shiftId": req.ShiftID, "status": "booked"})
}

type cancelShiftRequest struct {
	ShiftID string `json:"shiftId"`
}

// cancelShift — POST /cancelShift. Either party to a booked shift (or the
// nursery on an open one) may cancel; not a raw client field write because
// cancellation needs an ownership check plus (eventually) a communication
// notification — see ARCHITECTURE.md v2 §2.
func cancelShift(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	uid := auth.UID(ctx)

	var req cancelShiftRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	if req.ShiftID == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "shiftId is required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}
	ref := db.Collection("shifts").Doc(req.ShiftID)

	err = db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		snap, err := tx.Get(ref)
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
		isNursery := shift.NurseryID == uid
		isBookedStaff := shift.BookedStaffID != nil && *shift.BookedStaffID == uid
		if !isNursery && !isBookedStaff {
			return errNotShiftParty
		}
		if shift.Status == ShiftCancelled {
			return nil
		}
		return tx.Update(ref, []firestore.Update{
			{Path: "status", Value: string(ShiftCancelled)},
		})
	})

	switch err {
	case nil:
		httpjson.WriteJSON(w, http.StatusOK, map[string]string{"shiftId": req.ShiftID, "status": "cancelled"})
	case errShiftNotFound:
		httpjson.WriteError(w, http.StatusNotFound, "SHIFT_NOT_FOUND", "Shift not found")
	case errNotShiftParty:
		httpjson.WriteError(w, http.StatusForbidden, "NOT_SHIFT_PARTY", "You are not a party to this shift")
	default:
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
	}
}
