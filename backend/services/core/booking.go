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
	functions.HTTP("ApproveShiftApplicant", authed(approveShiftApplicant))
	functions.HTTP("RejectShiftApplicant", authed(rejectShiftApplicant))
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

	errAlreadyApplied      = errors.New("ALREADY_APPLIED")
	errApplicationRejected = errors.New("APPLICATION_REJECTED")
	errNotApplicant        = errors.New("NOT_APPLICANT")
	errShiftFull           = errors.New("SHIFT_FULL")
	// errNotShiftOwner is declared further down alongside markNoShow's
	// errors — approval reuses it rather than introducing a second spelling
	// of the same condition.
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

	// Training gate. Enforced here rather than in the client so it cannot be
	// bypassed, and driven by config rather than code so it can be switched on
	// the day enough modules exist — with only two published, hard-blocking
	// applications would strand practitioners who have nothing to complete.
	// An empty requiredModuleIds (the default) means no gate, and the nursery
	// approval step is what checks training in the meantime.
	if missing, err := missingRequiredTraining(ctx, db, uid); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	} else if len(missing) > 0 {
		httpjson.WriteError(w, http.StatusForbidden, "TRAINING_REQUIRED",
			"Complete your required training modules before applying for shifts")
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
		for _, s := range shift.PendingStaffIDs {
			if s == uid {
				return errAlreadyApplied
			}
		}
		for _, s := range shift.RejectedStaffIDs {
			if s == uid {
				return errApplicationRejected
			}
		}
		// Capacity is measured against APPROVED staff, not applicants, so a
		// queue of pending applications never blocks anyone else from
		// applying — the shift only closes once the nursery has approved
		// enough people.
		if int64(len(bookedList)) >= capacity {
			return errShiftFull
		}

		nurseryID = shift.NurseryID
		spotsRemaining = capacity - int64(len(bookedList))

		// Status is untouched: an application leaves the shift open and
		// visible to other staff. firstAcceptedAt likewise stays for the
		// approval step, since it feeds the nursery's "average response
		// time" statistic and an application isn't a booking.
		resultStatus = string(shift.Status)
		return tx.Update(ref, []firestore.Update{
			{Path: "pendingStaffIds", Value: append(append([]string(nil), shift.PendingStaffIDs...), uid)},
		})
	})

	if err != nil {
		switch err {
		case errShiftNotFound:
			httpjson.WriteError(w, http.StatusNotFound, "SHIFT_NOT_FOUND", "Shift not found")
		case errShiftAlreadyBooked:
			httpjson.WriteError(w, http.StatusConflict, "SHIFT_ALREADY_BOOKED", "You are already booked on this shift")
		case errAlreadyApplied:
			httpjson.WriteError(w, http.StatusConflict, "ALREADY_APPLIED", "You have already applied for this shift")
		case errApplicationRejected:
			httpjson.WriteError(w, http.StatusConflict, "APPLICATION_REJECTED", "The nursery has already reviewed your application for this shift")
		case errShiftFull:
			httpjson.WriteError(w, http.StatusConflict, "SHIFT_FULL", "This shift is no longer available")
		case errCannotBookOwnShift:
			httpjson.WriteError(w, http.StatusConflict, "CANNOT_BOOK_OWN_SHIFT", "You cannot apply for your own shift")
		default:
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		}
		return
	}

	// Published after commit, never inside the transaction (§4/§1).
	//
	// Note this is shift-applied, NOT shift-booked. The chat session and the
	// "shift booked" notification are deliberately deferred to approval: an
	// applicant the nursery ends up rejecting should never have had a chat
	// thread opened with them, and telling someone their shift is booked
	// before the nursery has agreed would be worse than saying nothing.
	if err := publish(ctx, topicShiftApplied, shiftAppliedMessage{
		ShiftID:   req.ShiftID,
		NurseryID: nurseryID,
		StaffID:   uid,
	}); err != nil {
		log.Printf("acceptShift: publish shift-applied for shift %s failed: %v", req.ShiftID, err)
	}

	// spotsRemaining counts places still to be filled by APPROVED staff, so
	// it doesn't move when someone applies.
	httpjson.WriteJSON(w, http.StatusOK, map[string]any{
		"shiftId":           req.ShiftID,
		"status":            resultStatus,
		"applicationStatus": "pending",
		"spotsRemaining":    spotsRemaining,
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
		if err := publish(ctx, topicShiftCancelled, *notify); err != nil {
			log.Printf("cancelShift: publish shift-cancelled for shift %s failed: %v", req.ShiftID, err)
		}
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

// ─── Nursery approval of applicants ─────────────────────────────────────────

type applicantDecisionRequest struct {
	ShiftID string `json:"shiftId"`
	StaffID string `json:"staffId"`
}

// shiftAppliedMessage tells the nursery someone has applied. Distinct from
// shiftBookedMessage because nothing is booked yet — no chat session is
// created and the staff member is not told they have the shift.
type shiftAppliedMessage struct {
	ShiftID   string `json:"shiftId"`
	NurseryID string `json:"nurseryId"`
	StaffID   string `json:"staffId"`
}

// shiftApplicationDecidedMessage notifies an applicant of the outcome.
// AutoRejected marks the applicants cleared because the shift filled up
// rather than because the nursery turned them down individually — the wording
// shown to them differs, and being auto-rejected is not a judgement on them.
type shiftApplicationDecidedMessage struct {
	ShiftID      string `json:"shiftId"`
	NurseryID    string `json:"nurseryId"`
	StaffID      string `json:"staffId"`
	Approved     bool   `json:"approved"`
	AutoRejected bool   `json:"autoRejected"`
}

// approveShiftApplicant — POST /approveShiftApplicant. Nursery-only, and only
// for its own shift. This is the point a booking actually exists: capacity is
// consumed here, not when the staff member applied.
func approveShiftApplicant(w http.ResponseWriter, r *http.Request) {
	decideApplicant(w, r, true)
}

// rejectShiftApplicant — POST /rejectShiftApplicant. Removes the applicant.
// The shift itself is untouched: it stays open with its capacity intact, so
// rejecting someone puts the shift back in front of other staff rather than
// penalising the nursery for being selective.
func rejectShiftApplicant(w http.ResponseWriter, r *http.Request) {
	decideApplicant(w, r, false)
}

func decideApplicant(w http.ResponseWriter, r *http.Request, approve bool) {
	ctx := r.Context()
	uid := auth.UID(ctx)

	var req applicantDecisionRequest
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
	if err := requireRole(ctx, db, uid, RoleNursery); err != nil {
		writeRoleError(w, err)
		return
	}

	ref := db.Collection("shifts").Doc(req.ShiftID)
	var (
		resultStatus   string
		spotsRemaining int64
		autoRejected   []string
		nurseryID      string
	)

	err = db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		autoRejected = nil
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
		// Ownership, not just role: a nursery must not be able to approve
		// applicants onto another nursery's shift.
		if shift.NurseryID != uid {
			return errNotShiftOwner
		}
		if shift.Status == ShiftCancelled {
			return errShiftNotFound
		}

		pending := shift.PendingStaffIDs
		found := false
		remainingPending := make([]string, 0, len(pending))
		for _, s := range pending {
			if s == req.StaffID {
				found = true
				continue
			}
			remainingPending = append(remainingPending, s)
		}
		if !found {
			return errNotApplicant
		}

		capacity := shift.Capacity
		if capacity <= 0 {
			capacity = 1
		}
		booked := shift.BookedStaffIDs
		if booked == nil && shift.BookedStaffID != nil && *shift.BookedStaffID != "" {
			booked = []string{*shift.BookedStaffID}
		}
		booked = append([]string(nil), booked...)

		nurseryID = shift.NurseryID
		rejected := append([]string(nil), shift.RejectedStaffIDs...)

		updates := []firestore.Update{}

		if approve {
			if int64(len(booked)) >= capacity {
				return errShiftFull
			}
			booked = append(booked, req.StaffID)

			// Once the last place is filled, everyone still waiting is
			// cleared out in the same transaction. Leaving them pending
			// against a full shift would strand them: they'd see an
			// application that can never be decided, and the nursery would
			// keep a list it can no longer act on.
			if int64(len(booked)) >= capacity && len(remainingPending) > 0 {
				autoRejected = append([]string(nil), remainingPending...)
				rejected = append(rejected, remainingPending...)
				remainingPending = remainingPending[:0]
			}

			resultStatus = string(ShiftOpen)
			if int64(len(booked)) >= capacity {
				resultStatus = string(ShiftBooked)
			}
			updates = append(updates,
				firestore.Update{Path: "status", Value: resultStatus},
				firestore.Update{Path: "bookedStaffId", Value: req.StaffID},
				firestore.Update{Path: "bookedStaffIds", Value: booked},
			)
			// firstAcceptedAt is set on first APPROVAL, not first
			// application: the statistic it feeds is how quickly a shift got
			// covered, and an application the nursery hasn't acted on hasn't
			// covered anything.
			if shift.FirstAcceptedAt == nil {
				now := time.Now()
				updates = append(updates, firestore.Update{Path: "firstAcceptedAt", Value: now})
			}
		} else {
			rejected = append(rejected, req.StaffID)
			resultStatus = string(shift.Status)
		}

		spotsRemaining = capacity - int64(len(booked))
		if spotsRemaining < 0 {
			spotsRemaining = 0
		}

		updates = append(updates,
			firestore.Update{Path: "pendingStaffIds", Value: remainingPending},
			firestore.Update{Path: "rejectedStaffIds", Value: rejected},
		)
		return tx.Update(ref, updates)
	})

	if err != nil {
		switch err {
		case errShiftNotFound:
			httpjson.WriteError(w, http.StatusNotFound, "SHIFT_NOT_FOUND", "Shift not found")
		case errNotShiftOwner:
			httpjson.WriteError(w, http.StatusForbidden, "NOT_SHIFT_OWNER", "This is not your shift")
		case errNotApplicant:
			httpjson.WriteError(w, http.StatusConflict, "NOT_APPLICANT", "That person is not waiting on a decision for this shift")
		case errShiftFull:
			httpjson.WriteError(w, http.StatusConflict, "SHIFT_FULL", "This shift already has all the staff it needs")
		default:
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		}
		return
	}

	// Published after commit, same rationale as elsewhere in this file.
	// Approval is where shift-booked finally fires, which is what creates the
	// chat session between the two parties.
	if approve {
		if err := publish(ctx, topicShiftBooked, shiftBookedMessage{
			ShiftID: req.ShiftID, NurseryID: nurseryID, StaffID: req.StaffID,
		}); err != nil {
			log.Printf("approveShiftApplicant: publish shift-booked for shift %s failed: %v", req.ShiftID, err)
		}
	}
	if err := publish(ctx, topicShiftDecided, shiftApplicationDecidedMessage{
		ShiftID: req.ShiftID, NurseryID: nurseryID, StaffID: req.StaffID, Approved: approve,
	}); err != nil {
		log.Printf("decideApplicant: publish decision for shift %s failed: %v", req.ShiftID, err)
	}
	for _, staffID := range autoRejected {
		if err := publish(ctx, topicShiftDecided, shiftApplicationDecidedMessage{
			ShiftID: req.ShiftID, NurseryID: nurseryID, StaffID: staffID,
			Approved: false, AutoRejected: true,
		}); err != nil {
			log.Printf("decideApplicant: publish auto-rejection for %s failed: %v", staffID, err)
		}
	}

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{
		"shiftId":        req.ShiftID,
		"staffId":        req.StaffID,
		"approved":       approve,
		"status":         resultStatus,
		"spotsRemaining": spotsRemaining,
		"autoRejected":   autoRejected,
	})
}
