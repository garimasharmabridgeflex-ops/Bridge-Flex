package function

import (
	"context"
	"errors"
	"net/http"
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
)

func init() {
	functions.HTTP("CreateBranch", authed(createBranch))
	functions.HTTP("ListBranches", authed(listBranches))
	functions.HTTP("UpdateBranch", authed(updateBranch))
	functions.HTTP("DeleteBranch", authed(deleteBranch))
	functions.HTTP("ApproveNurseryRegistration", authed(approveNurseryRegistration))
	functions.HTTP("RejectNurseryRegistration", authed(rejectNurseryRegistration))
}

type createBranchRequest struct {
	Name            string `json:"name"`
	Address         string `json:"address"`
	Postcode        string `json:"postcode"`
	City            string `json:"city"`
	Phone           string `json:"phone,omitempty"`
	ContactPerson   string `json:"contactPerson,omitempty"`
	OfstedRegNumber string `json:"ofstedRegNumber,omitempty"`
	IsPrimary       bool   `json:"isPrimary"`
}

func createBranch(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	uid := auth.UID(ctx)

	var req createBranchRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	if req.Name == "" || req.Address == "" || req.Postcode == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "name, address, and postcode are required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore unavailable")
		return
	}

	if err := requireRole(ctx, db, uid, RoleNursery); err != nil {
		writeRoleError(w, err)
		return
	}

	now := time.Now()
	branchesRef := db.Collection("nurseries").Doc(uid).Collection("branches")

	// Check if this is the first branch; if so, make it primary automatically.
	snaps, err := branchesRef.Limit(1).Documents(ctx).GetAll()
	if err == nil && len(snaps) == 0 {
		req.IsPrimary = true
	}

	branch := Branch{
		NurseryID:       uid,
		Name:            req.Name,
		Address:         req.Address,
		Postcode:        req.Postcode,
		City:            req.City,
		Phone:           req.Phone,
		ContactPerson:   req.ContactPerson,
		OfstedRegNumber: req.OfstedRegNumber,
		IsPrimary:       req.IsPrimary,
		CreatedAt:       now,
		UpdatedAt:       now,
	}

	ref, _, err := branchesRef.Add(ctx, branch)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	// If primary, ensure all other branches have isPrimary = false
	if req.IsPrimary {
		iter := branchesRef.Where("isPrimary", "==", true).Documents(ctx)
		defer iter.Stop()
		for {
			doc, err := iter.Next()
			if err == iterator.Done {
				break
			}
			if err == nil && doc.Ref.ID != ref.ID {
				_, _ = doc.Ref.Update(ctx, []firestore.Update{{Path: "isPrimary", Value: false}})
			}
		}
	}

	httpjson.WriteJSON(w, http.StatusCreated, map[string]any{
		"branchId": ref.ID,
		"status":   "created",
	})
}

// listBranches returns all branches for a nursery.
// If none exist yet, automatically migrates existing profile address into a primary branch.
func listBranches(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	callerUID := auth.UID(ctx)

	targetNurseryID := r.URL.Query().Get("nurseryId")
	if targetNurseryID == "" {
		targetNurseryID = callerUID
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore unavailable")
		return
	}

	branchesRef := db.Collection("nurseries").Doc(targetNurseryID).Collection("branches")
	iter := branchesRef.OrderBy("createdAt", firestore.Asc).Documents(ctx)
	defer iter.Stop()

	var branches []Branch
	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		var b Branch
		if err := doc.DataTo(&b); err == nil {
			b.ID = doc.Ref.ID
			branches = append(branches, b)
		}
	}

	// Backward-compatibility: if zero branches exist, auto-create a default primary branch
	if len(branches) == 0 {
		defaultBranch, err := ensureDefaultBranch(ctx, db, targetNurseryID)
		if err == nil && defaultBranch != nil {
			branches = append(branches, *defaultBranch)
		}
	}

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"branches": branches})
}

type updateBranchRequest struct {
	BranchID        string  `json:"branchId"`
	Name            *string `json:"name,omitempty"`
	Address         *string `json:"address,omitempty"`
	Postcode        *string `json:"postcode,omitempty"`
	City            *string `json:"city,omitempty"`
	Phone           *string `json:"phone,omitempty"`
	ContactPerson   *string `json:"contactPerson,omitempty"`
	OfstedRegNumber *string `json:"ofstedRegNumber,omitempty"`
	IsPrimary       *bool   `json:"isPrimary,omitempty"`
}

func updateBranch(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	uid := auth.UID(ctx)

	var req updateBranchRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	if req.BranchID == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "branchId is required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore unavailable")
		return
	}

	if err := requireRole(ctx, db, uid, RoleNursery); err != nil {
		writeRoleError(w, err)
		return
	}

	branchRef := db.Collection("nurseries").Doc(uid).Collection("branches").Doc(req.BranchID)
	snap, err := branchRef.Get(ctx)
	if status.Code(err) == codes.NotFound {
		httpjson.WriteError(w, http.StatusNotFound, "NOT_FOUND", "Branch not found")
		return
	}
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	updates := []firestore.Update{
		{Path: "updatedAt", Value: time.Now()},
	}
	if req.Name != nil {
		updates = append(updates, firestore.Update{Path: "name", Value: *req.Name})
	}
	if req.Address != nil {
		updates = append(updates, firestore.Update{Path: "address", Value: *req.Address})
	}
	if req.Postcode != nil {
		updates = append(updates, firestore.Update{Path: "postcode", Value: *req.Postcode})
	}
	if req.City != nil {
		updates = append(updates, firestore.Update{Path: "city", Value: *req.City})
	}
	if req.Phone != nil {
		updates = append(updates, firestore.Update{Path: "phone", Value: *req.Phone})
	}
	if req.ContactPerson != nil {
		updates = append(updates, firestore.Update{Path: "contactPerson", Value: *req.ContactPerson})
	}
	if req.OfstedRegNumber != nil {
		updates = append(updates, firestore.Update{Path: "ofstedRegNumber", Value: *req.OfstedRegNumber})
	}
	if req.IsPrimary != nil {
		updates = append(updates, firestore.Update{Path: "isPrimary", Value: *req.IsPrimary})
	}

	if _, err := branchRef.Update(ctx, updates); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	if req.IsPrimary != nil && *req.IsPrimary {
		branchesRef := db.Collection("nurseries").Doc(uid).Collection("branches")
		iter := branchesRef.Where("isPrimary", "==", true).Documents(ctx)
		defer iter.Stop()
		for {
			doc, err := iter.Next()
			if err == iterator.Done {
				break
			}
			if err == nil && doc.Ref.ID != req.BranchID {
				_, _ = doc.Ref.Update(ctx, []firestore.Update{{Path: "isPrimary", Value: false}})
			}
		}
	}

	_ = snap
	httpjson.WriteJSON(w, http.StatusOK, map[string]string{"status": "updated"})
}

type deleteBranchRequest struct {
	BranchID string `json:"branchId"`
}

func deleteBranch(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	uid := auth.UID(ctx)

	var req deleteBranchRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	if req.BranchID == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "branchId is required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore unavailable")
		return
	}

	if err := requireRole(ctx, db, uid, RoleNursery); err != nil {
		writeRoleError(w, err)
		return
	}

	branchRef := db.Collection("nurseries").Doc(uid).Collection("branches").Doc(req.BranchID)
	snap, err := branchRef.Get(ctx)
	if status.Code(err) == codes.NotFound {
		httpjson.WriteError(w, http.StatusNotFound, "NOT_FOUND", "Branch not found")
		return
	}
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	var b Branch
	if err := snap.DataTo(&b); err == nil && b.IsPrimary {
		// Count total branches
		all, _ := db.Collection("nurseries").Doc(uid).Collection("branches").Documents(ctx).GetAll()
		if len(all) <= 1 {
			httpjson.WriteError(w, http.StatusConflict, "CANNOT_DELETE_ONLY_BRANCH", "Cannot delete the nursery's sole branch")
			return
		}
	}

	if _, err := branchRef.Delete(ctx); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	httpjson.WriteJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

// ensureDefaultBranch seeds a primary branch for existing nurseries.
func ensureDefaultBranch(ctx context.Context, db *firestore.Client, nurseryID string) (*Branch, error) {
	snap, err := db.Collection("profiles").Doc(nurseryID).Get(ctx)
	if err != nil {
		return nil, err
	}
	var p Profile
	if err := snap.DataTo(&p); err != nil {
		return nil, err
	}
	if p.Role != RoleNursery {
		return nil, nil
	}

	name := p.Name
	if name == "" {
		name = "Main Branch"
	}
	address := p.Address
	if address == "" {
		address = "Main Address"
	}

	now := time.Now()
	b := Branch{
		NurseryID:       nurseryID,
		Name:            name,
		Address:         address,
		Postcode:        p.Postcode,
		City:            p.City,
		Phone:           p.Phone,
		OfstedRegNumber: p.OfstedRegNumber,
		IsPrimary:       true,
		CreatedAt:       now,
		UpdatedAt:       now,
	}

	// Set with MergeAll requires map data; the Firestore client rejects the
	// Branch struct outright ("firestore: MergeAll can only be specified with
	// map data"), which made ensureDefaultBranch fail whenever it re-ran.
	// Mirror the struct into a map — only the fields this literal sets, so a
	// re-seed never blanks contactPerson with a zero value.
	fields := map[string]any{
		"nurseryId":       b.NurseryID,
		"name":            b.Name,
		"address":         b.Address,
		"postcode":        b.Postcode,
		"city":            b.City,
		"isPrimary":       b.IsPrimary,
		"createdAt":       b.CreatedAt,
		"updatedAt":       b.UpdatedAt,
	}
	if b.Phone != "" {
		fields["phone"] = b.Phone
	}
	if b.OfstedRegNumber != "" {
		fields["ofstedRegNumber"] = b.OfstedRegNumber
	}
	ref := db.Collection("nurseries").Doc(nurseryID).Collection("branches").Doc("main")
	if _, err := ref.Set(ctx, fields, firestore.MergeAll); err != nil {
		return nil, err
	}
	b.ID = "main"
	return &b, nil
}

type approveNurseryRequest struct {
	NurseryID string `json:"nurseryId"`
}

func approveNurseryRegistration(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	callerUID := auth.UID(ctx)

	isAdminCaller := auth.HasRole(ctx, auth.AdminRoleSuperAdmin, auth.AdminRoleSupport) || isAdmin(ctx)
	if !isAdminCaller {
		httpjson.WriteError(w, http.StatusForbidden, "FORBIDDEN", "Admin permission required")
		return
	}

	var req approveNurseryRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	if req.NurseryID == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "nurseryId is required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore unavailable")
		return
	}

	now := time.Now()
	ref := db.Collection("profiles").Doc(req.NurseryID)

	err = db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		snap, err := tx.Get(ref)
		if status.Code(err) == codes.NotFound {
			return errors.New("PROFILE_NOT_FOUND")
		}
		if err != nil {
			return err
		}

		var p Profile
		if err := snap.DataTo(&p); err != nil {
			return err
		}
		if p.Role != RoleNursery {
			return errors.New("NOT_A_NURSERY")
		}

		updates := []firestore.Update{
			{Path: "nurseryApprovalStatus", Value: NurseryApproved},
			{Path: "activationDate", Value: now},
			{Path: "nurseryRejectionReason", Value: firestore.Delete},
			// Keep the legacy badge in step for older clients that still read it.
			{Path: "ofstedVerified", Value: true},
		}

		if err := tx.Update(ref, updates); err != nil {
			return err
		}

		// Write Outbox event for approval email/push
		_ = outbox.WriteTx(tx, db, outbox.Event{
			Topic: topicNurseryApproved,
			Payload: map[string]any{
				"nurseryId":      req.NurseryID,
				"activationDate": now.Format(time.RFC3339),
			},
		})

		return nil
	})

	if err != nil {
		httpjson.WriteError(w, http.StatusBadRequest, "ERROR", err.Error())
		return
	}

	// Synchronously update profilesPublic
	if snap, pErr := ref.Get(ctx); pErr == nil {
		var updatedP Profile
		if snap.DataTo(&updatedP) == nil {
			pub := buildPublicFromProfile(updatedP)
			_, _ = db.Collection("profilesPublic").Doc(req.NurseryID).Set(ctx, pub)
		}
	}

	// Starting the one free trial here (not on first page view) is what makes
	// the countdown match the approval date the owner asked for. The helper is
	// idempotent and refuses a second trial for the same company number.
	trial, _ := ensureTrialSubscription(ctx, db, req.NurseryID)

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:    "approveNurseryRegistration",
		ActorUID:  callerUID,
		TargetUID: req.NurseryID,
		Metadata:  map[string]any{"details": "Nursery registration approved and activation date set"},
	})
	_ = notifyInApp(ctx, db, req.NurseryID, "nursery_approved", "Nursery approved",
		"Your nursery is approved and your 14-day free trial has started. You can now post shifts.",
		map[string]any{"activationDate": now.Format(time.RFC3339)})
	sendTransactionalEmail(ctx, db, req.NurseryID, "nursery_approved",
		map[string]string{"trialStart": now.Format("02 Jan 2006")}, true)

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{
		"status":         "approved",
		"nurseryId":      req.NurseryID,
		"activationDate": now,
		"subscription":   trial,
	})
}

type rejectNurseryRequest struct {
	NurseryID string `json:"nurseryId"`
	Reason    string `json:"reason"`
}

func rejectNurseryRegistration(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	callerUID := auth.UID(ctx)

	isAdminCaller := auth.HasRole(ctx, auth.AdminRoleSuperAdmin, auth.AdminRoleSupport) || isAdmin(ctx)
	if !isAdminCaller {
		httpjson.WriteError(w, http.StatusForbidden, "FORBIDDEN", "Admin permission required")
		return
	}

	var req rejectNurseryRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	if req.NurseryID == "" || req.Reason == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "nurseryId and reason are required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore unavailable")
		return
	}

	ref := db.Collection("profiles").Doc(req.NurseryID)

	err = db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		snap, err := tx.Get(ref)
		if status.Code(err) == codes.NotFound {
			return errors.New("PROFILE_NOT_FOUND")
		}
		if err != nil {
			return err
		}

		var p Profile
		if err := snap.DataTo(&p); err != nil {
			return err
		}
		if p.Role != RoleNursery {
			return errors.New("NOT_A_NURSERY")
		}

		updates := []firestore.Update{
			{Path: "nurseryApprovalStatus", Value: NurseryRejected},
			{Path: "nurseryRejectionReason", Value: req.Reason},
		}

		if err := tx.Update(ref, updates); err != nil {
			return err
		}

		_ = outbox.WriteTx(tx, db, outbox.Event{
			Topic: topicNurseryRejected,
			Payload: map[string]any{
				"nurseryId": req.NurseryID,
				"reason":    req.Reason,
			},
		})

		return nil
	})

	if err != nil {
		httpjson.WriteError(w, http.StatusBadRequest, "ERROR", err.Error())
		return
	}

	if snap, pErr := ref.Get(ctx); pErr == nil {
		var updatedP Profile
		if snap.DataTo(&updatedP) == nil {
			pub := buildPublicFromProfile(updatedP)
			_, _ = db.Collection("profilesPublic").Doc(req.NurseryID).Set(ctx, pub)
		}
	}

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:    "rejectNurseryRegistration",
		ActorUID:  callerUID,
		TargetUID: req.NurseryID,
		Metadata:  map[string]any{"reason": req.Reason},
	})
	_ = notifyInApp(ctx, db, req.NurseryID, "nursery_rejected", "Nursery registration needs attention",
		req.Reason, map[string]any{"reason": req.Reason})
	sendTransactionalEmail(ctx, db, req.NurseryID, "nursery_rejected",
		map[string]string{"reason": req.Reason}, true)

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{
		"status":    "rejected",
		"nurseryId": req.NurseryID,
		"reason":    req.Reason,
	})
}
