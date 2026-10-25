package function

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"slices"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/GoogleCloudPlatform/functions-framework-go/functions"
	"github.com/cloudevents/sdk-go/v2/event"
	"github.com/googleapis/google-cloudevents-go/cloud/firestoredata"
	"google.golang.org/api/iterator"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/proto"

	"kvision.internal/shared/auth"
	"kvision.internal/shared/httpjson"
)

func init() {
	functions.HTTP("CreateShift", authed(createShift))
	functions.HTTP("UpdateShift", authed(updateShift))
	functions.HTTP("ListOpenShifts", authed(listOpenShifts))
	functions.HTTP("ListMyShifts", authed(listMyShifts))
	functions.HTTP("GetShift", authed(getShift))
	functions.CloudEvent("MatchNewShift", matchNewShift)
}

type createShiftRequest struct {
	Title       string  `json:"title"`
	Description string  `json:"description,omitempty"`
	Capacity    int64   `json:"capacity,omitempty"`
	Date        string  `json:"date"`
	StartTime   string  `json:"startTime"` // RFC3339
	EndTime     string  `json:"endTime"`   // RFC3339
	PayRate     float64 `json:"payRate"`

	AgeGroup         string   `json:"ageGroup,omitempty"`
	Room             string   `json:"room,omitempty"`
	NumberOfChildren int64    `json:"numberOfChildren,omitempty"`
	ExpectedDuties   []string `json:"expectedDuties,omitempty"`
	Requirements     []string `json:"requirements,omitempty"`
	BranchID         string   `json:"branchId,omitempty"`

	// Extended shift fields (Phase 6)
	RequiredQualification string `json:"requiredQualification,omitempty"`
	UnpaidBreakMinutes    int64  `json:"unpaidBreakMinutes,omitempty"`
	SafeguardingNotes     string `json:"safeguardingNotes,omitempty"`
	HealthAndSafetyNotes  string `json:"healthAndSafetyNotes,omitempty"`
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

	// Nursery approval gate (Phase 5).
	gate := GetGateMode(ctx, db, "nurseryApprovalRequired")
	if gate != GateOff {
		pSnap, err := db.Collection("profiles").Doc(uid).Get(ctx)
		if err == nil {
			var p Profile
			if err := pSnap.DataTo(&p); err == nil {
				// Grandfather pre-existing nurseries where status is unset (Phase 5.4)
				status := p.NurseryApprovalStatus
				if status == "" {
					status = NurseryApproved
				}
				if status != NurseryApproved {
					if gate == GateWarn {
						log.Printf("[GATE_WARN] Nursery %s is not approved (status: %q), proceeding under warn mode", uid, status)
					} else {
						httpjson.WriteError(w, http.StatusForbidden, "NURSERY_NOT_APPROVED",
							"Nursery registration requires admin approval before creating shifts")
						return
					}
				}
			}
		}
	}

	// Trial expiration gate (Phase 9 item 3).
	trialGate := GetGateMode(ctx, db, "trialExpired")
	if trialGate != GateOff {
		subSnap, err := db.Collection("subscriptions").Doc(uid).Get(ctx)
		if err == nil {
			var sub NurserySubscription
			if subSnap.DataTo(&sub) == nil {
				now := time.Now().UTC()
				if sub.Status == SubTrialing && sub.TrialEndDate != nil && now.After(*sub.TrialEndDate) {
					if trialGate == GateEnforce {
						httpjson.WriteError(w, http.StatusForbidden, "TRIAL_EXPIRED", "Your 14-day free trial has expired. Please select a plan or use Pay As You Go to post shifts.")
						return
					}
					log.Printf("trialExpired gate: trial expired for nursery %s", uid)
				} else if sub.Status == SubExpired {
					if trialGate == GateEnforce {
						httpjson.WriteError(w, http.StatusForbidden, "TRIAL_EXPIRED", "Your subscription has expired. Please select a plan to post shifts.")
						return
					}
					log.Printf("trialExpired gate: subscription expired for nursery %s", uid)
				}
			}
		}
	}

	capacity := req.Capacity
	if capacity <= 0 {
		capacity = 1
	}

	// Resolve branch location details (Phase 5)
	var branchID, branchName, branchAddress, branchPostcode string
	if req.BranchID != "" {
		bSnap, err := db.Collection("nurseries").Doc(uid).Collection("branches").Doc(req.BranchID).Get(ctx)
		if err == nil {
			var b Branch
			if err := bSnap.DataTo(&b); err == nil {
				branchID = bSnap.Ref.ID
				branchName = b.Name
				branchAddress = b.Address
				branchPostcode = b.Postcode
			}
		}
	} else {
		// Attempt to use primary/default branch
		if defBranch, err := ensureDefaultBranch(ctx, db, uid); err == nil && defBranch != nil {
			branchID = defBranch.ID
			branchName = defBranch.Name
			branchAddress = defBranch.Address
			branchPostcode = defBranch.Postcode
		}
	}

	// Compute financial snapshot from active rate card (Phase 6)
	fin, defaultPayRate := ResolveShiftFinancials(
		ctx,
		db,
		QualificationLevel(req.RequiredQualification),
		startTime,
		endTime,
		req.UnpaidBreakMinutes,
	)
	// Decision 2: the admin's rate card sets both rates. A nursery-supplied
	// payRate is accepted on the wire for old clients but deliberately ignored
	// so a nursery cannot set its own staffing charge or practitioner pay.
	payRate := defaultPayRate
	_ = req.PayRate

	shift := Shift{
		NurseryID:     uid,
		Title:         req.Title,
		Description:   req.Description,
		Capacity:      capacity,
		Date:          req.Date,
		StartTime:     startTime,
		EndTime:       endTime,
		PayRate:       payRate,
		Status:        ShiftOpen,
		BookedStaffID: nil,
		PaymentStatus: PaymentNotRequired,
		CreatedAt:     time.Now(),

		AgeGroup:         req.AgeGroup,
		Room:             req.Room,
		NumberOfChildren: req.NumberOfChildren,
		ExpectedDuties:   req.ExpectedDuties,
		Requirements:     req.Requirements,

		BranchID:       branchID,
		BranchName:     branchName,
		BranchAddress:  branchAddress,
		BranchPostcode: branchPostcode,

		Financials:            fin,
		RequiredQualification: QualificationLevel(req.RequiredQualification),
		UnpaidBreakMinutes:    req.UnpaidBreakMinutes,
		SafeguardingNotes:     req.SafeguardingNotes,
		HealthAndSafetyNotes:  req.HealthAndSafetyNotes,
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

	AgeGroup              *string   `json:"ageGroup,omitempty"`
	Room                  *string   `json:"room,omitempty"`
	NumberOfChildren      *int64    `json:"numberOfChildren,omitempty"`
	ExpectedDuties        *[]string `json:"expectedDuties,omitempty"`
	Requirements          *[]string `json:"requirements,omitempty"`
	UnpaidBreakMinutes    *int64    `json:"unpaidBreakMinutes,omitempty"`
	RequiredQualification *string   `json:"requiredQualification,omitempty"`
	Description           *string   `json:"description,omitempty"`
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
		// payRate is intentionally not editable here: the rate card owns it.
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
		if req.AgeGroup != nil {
			updates = append(updates, firestore.Update{Path: "ageGroup", Value: *req.AgeGroup})
		}
		if req.Room != nil {
			updates = append(updates, firestore.Update{Path: "room", Value: *req.Room})
		}
		if req.NumberOfChildren != nil {
			updates = append(updates, firestore.Update{Path: "numberOfChildren", Value: *req.NumberOfChildren})
		}
		if req.ExpectedDuties != nil {
			updates = append(updates, firestore.Update{Path: "expectedDuties", Value: *req.ExpectedDuties})
		}
		if req.Requirements != nil {
			updates = append(updates, firestore.Update{Path: "requirements", Value: *req.Requirements})
		}
		if req.Description != nil {
			updates = append(updates, firestore.Update{Path: "description", Value: *req.Description})
		}
		if req.UnpaidBreakMinutes != nil {
			updates = append(updates, firestore.Update{Path: "unpaidBreakMinutes", Value: *req.UnpaidBreakMinutes})
		}
		if req.RequiredQualification != nil {
			updates = append(updates, firestore.Update{Path: "requiredQualification", Value: QualificationLevel(*req.RequiredQualification)})
		}
		if len(updates) == 0 {
			return nil
		}
		return tx.Update(ref, updates)
	})

	if err == nil {
		// Re-snapshot the financials outside the transaction so an edit to
		// times, breaks or qualification cannot leave a stale rate behind.
		if snap, rErr := ref.Get(ctx); rErr == nil {
			var updated Shift
			if snap.DataTo(&updated) == nil && updated.Status == ShiftOpen {
				fin, legacy := ResolveShiftFinancials(ctx, db, updated.RequiredQualification, updated.StartTime, updated.EndTime, updated.UnpaidBreakMinutes)
				_, _ = ref.Update(ctx, []firestore.Update{
					{Path: "financials", Value: fin},
					{Path: "payRate", Value: legacy},
				})
			}
		}
	}

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
	nurseryAreas := make(map[string]string)
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
		if s.NurseryArea == "" && s.NurseryID != "" {
			if area, ok := nurseryAreas[s.NurseryID]; ok {
				s.NurseryArea = area
			} else {
				if npSnap, err := db.Collection("profilesPublic").Doc(s.NurseryID).Get(ctx); err == nil {
					if a, ok := npSnap.Data()["locationArea"].(string); ok {
						s.NurseryArea = a
						nurseryAreas[s.NurseryID] = a
					}
				}
			}
		}
		shifts = append(shifts, map[string]any{
			"shiftId":     doc.Ref.ID,
			"shift":       s,
			"nurseryArea": s.NurseryArea,
		})
	}
	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"shifts": shifts})
}

// listMyShifts — GET /listMyShifts. A nursery gets shifts it posted (any
// status); staff get shifts booked to them. Both queries are already
// client-legal per Security Rules (§3) — this endpoint exists as a plain-HTTP
// mirror for clients that can't hold a live Firestore connection open (e.g.
// gRPC-hostile networks), same rationale as listOpenShifts above.
func listMyShifts(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	uid := auth.UID(ctx)

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	profileSnap, err := db.Collection("profiles").Doc(uid).Get(ctx)
	if status.Code(err) == codes.NotFound {
		httpjson.WriteError(w, http.StatusNotFound, "PROFILE_NOT_FOUND", "Profile not found")
		return
	}
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}
	var profile Profile
	if err := profileSnap.DataTo(&profile); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	shiftsMap := make(map[string]map[string]any)
	switch profile.Role {
	case RoleNursery:
		iter := db.Collection("shifts").Where("nurseryId", "==", uid).Documents(ctx)
		defer iter.Stop()
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
			if err := doc.DataTo(&s); err == nil {
				shiftsMap[doc.Ref.ID] = map[string]any{"shiftId": doc.Ref.ID, "shift": s}
			}
		}
	case RoleStaff:
		iter1 := db.Collection("shifts").Where("bookedStaffId", "==", uid).Documents(ctx)
		defer iter1.Stop()
		for {
			doc, err := iter1.Next()
			if err == iterator.Done {
				break
			}
			if err != nil {
				httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
				return
			}
			var s Shift
			if err := doc.DataTo(&s); err == nil {
				shiftsMap[doc.Ref.ID] = map[string]any{"shiftId": doc.Ref.ID, "shift": s}
			}
		}
		iter2 := db.Collection("shifts").Where("bookedStaffIds", "array-contains", uid).Documents(ctx)
		defer iter2.Stop()
		for {
			doc, err := iter2.Next()
			if err == iterator.Done {
				break
			}
			if err != nil {
				httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
				return
			}
			var s Shift
			if err := doc.DataTo(&s); err == nil {
				shiftsMap[doc.Ref.ID] = map[string]any{"shiftId": doc.Ref.ID, "shift": s}
			}
		}
		// B4: Include shifts where the practitioner has applied and is pending approval
		iter3 := db.Collection("shifts").Where("pendingStaffIds", "array-contains", uid).Documents(ctx)
		defer iter3.Stop()
		for {
			doc, err := iter3.Next()
			if err == iterator.Done {
				break
			}
			if err != nil {
				httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
				return
			}
			var s Shift
			if err := doc.DataTo(&s); err == nil {
				shiftsMap[doc.Ref.ID] = map[string]any{"shiftId": doc.Ref.ID, "shift": s}
			}
		}
	default:
		httpjson.WriteJSON(w, http.StatusOK, map[string]any{"shifts": []map[string]any{}})
		return
	}

	shifts := make([]map[string]any, 0, len(shiftsMap))
	for _, item := range shiftsMap {
		shifts = append(shifts, item)
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
	// Same bug class already fixed in booking.go/ratings.go: checking only
	// the legacy singular BookedStaffID means every staff member on a
	// multi-capacity shift except the "most recent acceptor" gets 403'd
	// viewing their own shift — including from their own "shift booked"
	// notification, once the shift is no longer open.
	bookedIDs := s.BookedStaffIDs
	if len(bookedIDs) == 0 && s.BookedStaffID != nil {
		bookedIDs = []string{*s.BookedStaffID}
	}
	isParty := uid == s.NurseryID || slices.Contains(bookedIDs, uid)
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
// concern because matching needs shifts+profiles together (§6).
// In Phase 6 (R4), replaces unbounded collection scans with filtered, capped queries.
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
	reqQual := fieldString(doc.GetFields(), "requiredQualification")

	db, err := fsDB(ctx)
	if err != nil {
		return err
	}

	const maxMatches = 25
	q := db.Collection("profiles").
		Where("role", "==", string(RoleStaff)).
		Where("suspended", "==", false).
		Limit(maxMatches)

	// Filter by vetting approval if gate is on
	gate := GetGateMode(ctx, db, "practitionerApprovalRequired")
	if gate == GateEnforce {
		q = q.Where("vettingStatus", "==", string(VettingApproved))
	}

	iter := q.Documents(ctx)
	defer iter.Stop()

	matchedCount := 0
	for {
		staffDoc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return err
		}

		var p Profile
		if err := staffDoc.DataTo(&p); err == nil {
			// If a specific qualification level is required, check practitioner eligibility
			if reqQual != "" && reqQual != string(QualNone) {
				if !isQualificationSufficient(p.QualificationLevel, QualificationLevel(reqQual)) {
					continue
				}
			}
		}

		if err := publish(ctx, topicShiftMatched, shiftMatchedMessage{
			ShiftID:   shiftID,
			NurseryID: nurseryID,
			StaffID:   staffDoc.Ref.ID,
		}); err != nil {
			return err
		}
		matchedCount++
		if matchedCount >= maxMatches {
			break
		}
	}
	return nil
}

// isQualificationSufficient ranks qualifications: Level 4+ >= Level 3 >= Level 2 >= None.
func isQualificationSufficient(actual, required QualificationLevel) bool {
	rank := func(q QualificationLevel) int {
		switch q {
		case QualLevel4Plus:
			return 3
		case QualLevel3:
			return 2
		case QualLevel2:
			return 1
		default:
			return 0
		}
	}
	return rank(actual) >= rank(required)
}

var (
	errNotYourShift     = fmt.Errorf("not your shift")
	errShiftNotEditable = fmt.Errorf("shift not editable")
	errBadTimeFormat    = fmt.Errorf("bad time format")
)
