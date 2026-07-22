package function

import (
	"context"
	"fmt"
	"net/http"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/GoogleCloudPlatform/functions-framework-go/functions"
	"github.com/cloudevents/sdk-go/v2/event"
	"github.com/googleapis/google-cloudevents-go/cloud/firestoredata"
	"google.golang.org/api/iterator"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/proto"

	"bridgeflex/shared/auth"
	"bridgeflex/shared/httpjson"
)

func init() {
	functions.HTTP("CreateShift", authed(createShift))
	functions.HTTP("UpdateShift", authed(updateShift))
	functions.HTTP("ListOpenShifts", authed(listOpenShifts))
	functions.HTTP("GetShift", authed(getShift))
	functions.CloudEvent("MatchNewShift", matchNewShift)
}

type createShiftRequest struct {
	Title     string  `json:"title"`
	Date      string  `json:"date"`
	StartTime string  `json:"startTime"` // RFC3339
	EndTime   string  `json:"endTime"`   // RFC3339
	PayRate   float64 `json:"payRate"`
}

// createShift — POST /createShift. Nursery-only; status/bookedStaffId/
// paymentStatus are set server-side, never accepted from the client (§3).
func createShift(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	uid := auth.UID(ctx)

	var req createShiftRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	if req.Title == "" || req.Date == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "title and date are required")
		return
	}
	startTime, err := time.Parse(time.RFC3339, req.StartTime)
	if err != nil {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "startTime must be RFC3339")
		return
	}
	endTime, err := time.Parse(time.RFC3339, req.EndTime)
	if err != nil {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "endTime must be RFC3339")
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

	shift := Shift{
		NurseryID:     uid,
		Title:         req.Title,
		Date:          req.Date,
		StartTime:     startTime,
		EndTime:       endTime,
		PayRate:       req.PayRate,
		Status:        ShiftOpen,
		BookedStaffID: nil,
		PaymentStatus: PaymentNotRequired,
		CreatedAt:     time.Now(),
	}
	ref, _, err := db.Collection("shifts").Add(ctx, shift)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}
	httpjson.WriteJSON(w, http.StatusCreated, map[string]string{"shiftId": ref.ID})
}

type updateShiftRequest struct {
	ShiftID   string   `json:"shiftId"`
	Title     *string  `json:"title,omitempty"`
	Date      *string  `json:"date,omitempty"`
	StartTime *string  `json:"startTime,omitempty"`
	EndTime   *string  `json:"endTime,omitempty"`
	PayRate   *float64 `json:"payRate,omitempty"`
}

// updateShift — POST /updateShift. Nursery may only edit their own shift's
// editable fields while it's still open — status/bookedStaffId are never
// touched here (§2/§3); those only ever change via acceptShift/cancelShift.
func updateShift(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	uid := auth.UID(ctx)

	var req updateShiftRequest
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
		if err != nil {
			return err
		}
		var shift Shift
		if err := snap.DataTo(&shift); err != nil {
			return err
		}
		if shift.NurseryID != uid {
			return errNotYourShift
		}
		if shift.Status != ShiftOpen {
			return errShiftNotEditable
		}

		var updates []firestore.Update
		if req.Title != nil {
			updates = append(updates, firestore.Update{Path: "title", Value: *req.Title})
		}
		if req.Date != nil {
			updates = append(updates, firestore.Update{Path: "date", Value: *req.Date})
		}
		if req.PayRate != nil {
			updates = append(updates, firestore.Update{Path: "payRate", Value: *req.PayRate})
		}
		if req.StartTime != nil {
			t, err := time.Parse(time.RFC3339, *req.StartTime)
			if err != nil {
				return errBadTimeFormat
			}
			updates = append(updates, firestore.Update{Path: "startTime", Value: t})
		}
		if req.EndTime != nil {
			t, err := time.Parse(time.RFC3339, *req.EndTime)
			if err != nil {
				return errBadTimeFormat
			}
			updates = append(updates, firestore.Update{Path: "endTime", Value: t})
		}
		if len(updates) == 0 {
			return nil
		}
		return tx.Update(ref, updates)
	})

	switch {
	case err == nil:
		httpjson.WriteJSON(w, http.StatusOK, map[string]string{"status": "updated"})
	case status.Code(err) == codes.NotFound:
		httpjson.WriteError(w, http.StatusNotFound, "SHIFT_NOT_FOUND", "Shift not found")
	case err == errNotYourShift:
		httpjson.WriteError(w, http.StatusForbidden, "NOT_YOUR_SHIFT", "You do not own this shift")
	case err == errShiftNotEditable:
		httpjson.WriteError(w, http.StatusConflict, "SHIFT_NOT_EDITABLE", "Only open shifts can be edited")
	case err == errBadTimeFormat:
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "startTime/endTime must be RFC3339")
	default:
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
	}
}

// listOpenShifts — GET /listOpenShifts. Any authenticated staff can browse
// open shifts (§3) — this endpoint mirrors that same rule server-side for
// convenience; it's equally valid for a client to run this query directly
// against Firestore since the read is already client-legal.
func listOpenShifts(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	iter := db.Collection("shifts").Where("status", "==", string(ShiftOpen)).
		OrderBy("createdAt", firestore.Desc).Documents(ctx)
	defer iter.Stop()

	shifts := make([]map[string]any, 0)
	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		var s Shift
		if err := doc.DataTo(&s); err != nil {
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		shifts = append(shifts, map[string]any{"shiftId": doc.Ref.ID, "shift": s})
	}
	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"shifts": shifts})
}

// getShift — GET /getShift?shiftId=... Enforces the same read rule as §3:
// open shifts readable by anyone signed in, booked shifts only by the
// nursery/booked staff pair.
func getShift(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	uid := auth.UID(ctx)
	shiftID := r.URL.Query().Get("shiftId")
	if shiftID == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "shiftId query parameter is required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}
	snap, err := db.Collection("shifts").Doc(shiftID).Get(ctx)
	if status.Code(err) == codes.NotFound {
		httpjson.WriteError(w, http.StatusNotFound, "SHIFT_NOT_FOUND", "Shift not found")
		return
	}
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}
	var s Shift
	if err := snap.DataTo(&s); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}
	isParty := uid == s.NurseryID || (s.BookedStaffID != nil && uid == *s.BookedStaffID)
	if s.Status != ShiftOpen && !isParty {
		httpjson.WriteError(w, http.StatusForbidden, "NOT_VISIBLE", "You cannot view this shift")
		return
	}
	httpjson.WriteJSON(w, http.StatusOK, s)
}

type shiftMatchedMessage struct {
	ShiftID   string `json:"shiftId"`
	NurseryID string `json:"nurseryId"`
	StaffID   string `json:"staffId"`
}

// matchNewShift is bound at deploy time to a Firestore-create Eventarc
// trigger filtered to shifts/{shiftId} (§1a table). It's a core-backend
// concern because matching needs shifts+profiles together (§6). Phase 1
// implements a placeholder match (publish to every staff profile) since the
// real radius-matching algorithm is an open product question (§8 item 4) —
// the point of this trigger existing now is to prove the shift-matched
// fan-out contract, not to ship real matching logic.
func matchNewShift(ctx context.Context, e event.Event) error {
	var data firestoredata.DocumentEventData
	if err := proto.Unmarshal(e.Data(), &data); err != nil {
		return fmt.Errorf("proto.Unmarshal firestore event: %w", err)
	}
	doc := data.GetValue()
	if doc == nil {
		return nil
	}
	shiftID, err := lastPathSegment(doc.GetName())
	if err != nil {
		return err
	}
	nurseryID := fieldString(doc.GetFields(), "nurseryId")

	db, err := fsDB(ctx)
	if err != nil {
		return err
	}
	iter := db.Collection("profiles").Where("role", "==", string(RoleStaff)).Documents(ctx)
	defer iter.Stop()
	for {
		staffDoc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return err
		}
		if err := publish(ctx, topicShiftMatched, shiftMatchedMessage{
			ShiftID:   shiftID,
			NurseryID: nurseryID,
			StaffID:   staffDoc.Ref.ID,
		}); err != nil {
			return err
		}
	}
	return nil
}

var (
	errNotYourShift     = fmt.Errorf("not your shift")
	errShiftNotEditable = fmt.Errorf("shift not editable")
	errBadTimeFormat    = fmt.Errorf("bad time format")
)
