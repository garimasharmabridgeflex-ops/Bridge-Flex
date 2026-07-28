package function

import (
	"context"
	"errors"
	"log"
	"net/http"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/GoogleCloudPlatform/functions-framework-go/functions"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"kvision.internal/shared/auth"
	"kvision.internal/shared/httpjson"
)

func init() {
	functions.HTTP("AcceptShift", authed(acceptShift))
	functions.HTTP("CancelShift", authed(cancelShift))
	functions.HTTP("MarkNoShow", authed(markNoShow))
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
	var resultStatus string
	var spotsRemaining int64

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
		if shift.NurseryID == uid {
			return errCannotBookOwnShift
		}
		if shift.Status != ShiftOpen {
			return errShiftAlreadyBooked
		}
		capacity := shift.Capacity
		if capacity <= 0 {
			capacity = 1
		}

		// BookedStaffIDs is authoritative; fall back to the singular field
		// only for shifts booked before this array existed.
		bookedList := shift.BookedStaffIDs
		if bookedList == nil && shift.BookedStaffID != nil && *shift.BookedStaffID != "" {
			bookedList = []string{*shift.BookedStaffID}
		}
		for _, s := range bookedList {
			if s == uid {
				return errShiftAlreadyBooked
			}
		}

		bookedList = append(bookedList, uid)
		nurseryID = shift.NurseryID
		spotsRemaining = capacity - int64(len(bookedList))
		if spotsRemaining < 0 {
			spotsRemaining = 0
		}

		resultStatus = string(ShiftOpen)
		if int64(len(bookedList)) >= capacity {
			resultStatus = string(ShiftBooked)
		}

		updates := []firestore.Update{
			{Path: "status", Value: resultStatus},
			// bookedStaffId ("most recent acceptor") is kept only for any
			// remaining single-capacity-era readers; bookedStaffIds is what
			// membership/cancellation logic actually uses.
			{Path: "bookedStaffId", Value: uid},
			{Path: "bookedStaffIds", Value: bookedList},
		}
		if shift.FirstAcceptedAt == nil {
			updates = append(updates, firestore.Update{Path: "firstAcceptedAt", Value: time.Now()})
		}
		return tx.Update(ref, updates)
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
	// Logged (not discarded) so a broken chat-session/notification cascade
	// is visible in Cloud Logging instead of silently vanishing — exactly
	// what happened when projectID() pointed publish() at the wrong project.
	if err := publish(ctx, topicShiftBooked, shiftBookedMessage{
		ShiftID:   req.ShiftID,
		NurseryID: nurseryID,
		StaffID:   uid,
	}); err != nil {
		log.Printf("acceptShift: publish shift-booked for shift %s failed: %v", req.ShiftID, err)
	}

	// resultStatus reflects whether capacity is now full, not a hardcoded
	// "booked" — a shift with capacity 2 correctly stays "open" after the
	// first acceptance so a second staff member can still take it.
	httpjson.WriteJSON(w, http.StatusOK, map[string]any{
		"shiftId":        req.ShiftID,
		"status":         resultStatus,
		"spotsRemaining": spotsRemaining,
	})
}

type cancelShiftRequest struct {
	ShiftID string `json:"shiftId"`
}

type shiftCancelledMessage struct {
	ShiftID   string `json:"shiftId"`
	NurseryID string `json:"nurseryId"`
	// StaffIDs holds everyone to notify: one uid when staff drops their own
	// slot (notify just the nursery — StaffIDs isn't used for that
	// direction, see below) or, when the nursery cancels the whole shift,
	// every staff member who had a slot on it.
	StaffIDs    []string `json:"staffIds,omitempty"`
	CancelledBy string   `json:"cancelledBy"` // "nursery" | "staff"
	NewStatus   string   `json:"newStatus"`   // "cancelled" | "open"
}

// cancelShift — POST /cancelShift. "Cancel" means two different things
// depending on who calls it (full app spec §3):
//   - Nursery cancels an open or booked shift -> status becomes `cancelled`
//     (pulled from the marketplace entirely). If it was booked, the staff
//     member who had it is notified.
//   - Staff cancels their own acceptance of a booked shift -> status goes
//     back to `open` (bookedStaffId cleared), NOT `cancelled` — the whole
//     point is someone else can still grab a last-minute-cover shift. The
//     nursery is notified their coverage just dropped.
//
// This must be a transaction for the same reason acceptShift is (§4): the
// actor's role determines the target state, and re-reading a stale shift
// mid-write could apply the wrong transition.
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

	var notify *shiftCancelledMessage
	var resultStatus string

	err = db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		notify = nil
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

		// Membership must be checked against the full array, not just
		// bookedStaffId ("most recent acceptor") — on a multi-capacity
		// shift, the first staff member to accept would otherwise find
		// bookedStaffId now pointing at whoever accepted after them, and
		// be told they're "not a party to this shift" when trying to
		// cancel their own slot.
		bookedList := shift.BookedStaffIDs
		if bookedList == nil && shift.BookedStaffID != nil && *shift.BookedStaffID != "" {
			bookedList = []string{*shift.BookedStaffID}
		}
		isBookedStaff := false
		for _, s := range bookedList {
			if s == uid {
				isBookedStaff = true
				break
			}
		}
		if !isNursery && !isBookedStaff {
			return errNotShiftParty
		}
		if shift.Status == ShiftCancelled {
			resultStatus = string(ShiftCancelled)
			return nil
		}

		if isBookedStaff && !isNursery {
			// Staff dropping their own slot: remove just their uid from the
			// list — any other staff already booked on this shift keep
			// their slot, and the shift reopens (there's now a free spot)
			// rather than disappearing from the marketplace.
			remaining := make([]string, 0, len(bookedList))
			for _, s := range bookedList {
				if s != uid {
					remaining = append(remaining, s)
				}
			}
			resultStatus = string(ShiftOpen)
			notify = &shiftCancelledMessage{
				ShiftID: req.ShiftID, NurseryID: shift.NurseryID,
				CancelledBy: "staff", NewStatus: resultStatus,
			}
			var newBookedStaffID any
			if len(remaining) > 0 {
				newBookedStaffID = remaining[len(remaining)-1]
			} else {
				newBookedStaffID = nil
			}
			return tx.Update(ref, []firestore.Update{
				{Path: "status", Value: string(ShiftOpen)},
				{Path: "bookedStaffId", Value: newBookedStaffID},
				{Path: "bookedStaffIds", Value: remaining},
			})
		}

		// Nursery cancelling (open or booked) — pulled from the marketplace
		// entirely, for every staff member booked on it. Notify each of
		// them, if any.
		resultStatus = string(ShiftCancelled)
		if len(bookedList) > 0 {
			ids := append([]string(nil), bookedList...)
			notify = &shiftCancelledMessage{
				ShiftID: req.ShiftID, NurseryID: shift.NurseryID, StaffIDs: ids,
				CancelledBy: "nursery", NewStatus: resultStatus,
			}
		}
		return tx.Update(ref, []firestore.Update{
			{Path: "status", Value: string(ShiftCancelled)},
		})
	})

	if err != nil {
		switch err {
		case errShiftNotFound:
			httpjson.WriteError(w, http.StatusNotFound, "SHIFT_NOT_FOUND", "Shift not found")
		case errNotShiftParty:
			httpjson.WriteError(w, http.StatusForbidden, "NOT_SHIFT_PARTY", "You are not a party to this shift")
		default:
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		}
		return
	}

	// Published after commit succeeds, same rationale as acceptShift (§4/§1):
	// Pub/Sub isn't part of Firestore's transactional guarantee.
	if notify != nil {
		_ = publish(ctx, topicShiftCancelled, *notify)
	}

	httpjson.WriteJSON(w, http.StatusOK, map[string]string{"shiftId": req.ShiftID, "status": resultStatus})
}

var (
	errNotShiftOwner  = errors.New("NOT_SHIFT_OWNER")
	errShiftNotDone   = errors.New("SHIFT_NOT_DONE")
	errStaffNotBooked = errors.New("STAFF_NOT_BOOKED")
)

type markNoShowRequest struct {
	ShiftID string `json:"shiftId"`
	StaffID string `json:"staffId"`
}

// markNoShow — POST /markNoShow. Nursery-only, and only once the shift has
// actually ended — lets a nursery flag a booked staff member who never
// turned up, feeding the "no-show rate" statistic (stats.go). Idempotent:
// marking the same staffId twice is a no-op, not an error.
func markNoShow(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	uid := auth.UID(ctx)

	var req markNoShowRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	if req.ShiftID == "" || req.StaffID == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "shiftId and staffId are required")
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
		if shift.NurseryID != uid {
			return errNotShiftOwner
		}
		if !time.Now().After(shift.EndTime) {
			return errShiftNotDone
		}
		bookedList := shift.BookedStaffIDs
		if bookedList == nil && shift.BookedStaffID != nil && *shift.BookedStaffID != "" {
			bookedList = []string{*shift.BookedStaffID}
		}
		staffBooked := false
		for _, s := range bookedList {
			if s == req.StaffID {
				staffBooked = true
				break
			}
		}
		if !staffBooked {
			return errStaffNotBooked
		}
		for _, s := range shift.NoShowStaffIDs {
			if s == req.StaffID {
				return nil // already marked — idempotent no-op
			}
		}
		return tx.Update(ref, []firestore.Update{
			{Path: "noShowStaffIds", Value: append(shift.NoShowStaffIDs, req.StaffID)},
		})
	})

	if err != nil {
		switch err {
		case errShiftNotFound:
			httpjson.WriteError(w, http.StatusNotFound, "SHIFT_NOT_FOUND", "Shift not found")
		case errNotShiftOwner:
			httpjson.WriteError(w, http.StatusForbidden, "NOT_SHIFT_OWNER", "Only the posting nursery can mark a no-show")
		case errShiftNotDone:
			httpjson.WriteError(w, http.StatusConflict, "SHIFT_NOT_DONE", "Shift has not ended yet")
		case errStaffNotBooked:
			httpjson.WriteError(w, http.StatusBadRequest, "STAFF_NOT_BOOKED", "That staff member was not booked on this shift")
		default:
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		}
		return
	}

	httpjson.WriteJSON(w, http.StatusOK, map[string]string{"shiftId": req.ShiftID, "staffId": req.StaffID})
}
