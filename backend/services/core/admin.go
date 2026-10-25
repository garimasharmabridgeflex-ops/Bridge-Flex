package function

import (
	"context"
	"net/http"
	"time"

	"cloud.google.com/go/firestore"
	firebaseauth "firebase.google.com/go/v4/auth"
	"github.com/GoogleCloudPlatform/functions-framework-go/functions"
	"google.golang.org/api/iterator"

	"kvision.internal/shared/auth"
	"kvision.internal/shared/httpjson"
)

func init() {
	functions.HTTP("GetPlatformStats", authed(getPlatformStats))
	functions.HTTP("ListAllUsers", authed(listAllUsers))
	functions.HTTP("GetUserDetail", authed(getUserDetail))
	functions.HTTP("SetUserSuspended", authed(setUserSuspended))
	functions.HTTP("SetVerificationBadge", authed(setVerificationBadge))
	functions.HTTP("ListAuditLogs", authed(listAuditLogs))
}

// PlatformStats is the admin dashboard's platform-wide snapshot — full app
// spec admin-page request: "a dashboard that shows platform wide metrics and
// statistics". Computed on read, same MVP tradeoff as stats.go's per-nursery
// numbers (no trigger-maintained counters yet).
type platformStats struct {
	TotalNurseries    int64 `json:"totalNurseries"`
	TotalStaff        int64 `json:"totalStaff"`
	SuspendedUsers    int64 `json:"suspendedUsers"`
	PendingDBS        int64 `json:"pendingDbs"`
	TotalShifts       int64 `json:"totalShifts"`
	OpenShifts        int64 `json:"openShifts"`
	BookedShifts      int64 `json:"bookedShifts"`
	CompletedShifts   int64 `json:"completedShifts"`
	CancelledShifts   int64 `json:"cancelledShifts"`
	PendingTimesheets int64 `json:"pendingTimesheets,omitempty"`
	PendingDocuments  int64 `json:"pendingDocuments"`
	TotalRatings      int64 `json:"totalRatings"`

	// Operational and financial counters the owner asked for. Money is in
	// pence, every time; the admin console formats it.
	ActiveSubscriptions       int64 `json:"activeSubscriptions"`
	TrialAccounts             int64 `json:"trialAccounts"`
	PendingNurseryApprovals   int64 `json:"pendingNurseryApprovals"`
	VerifiedPractitioners     int64 `json:"verifiedPractitioners"`
	PendingVetting            int64 `json:"pendingVetting"`
	ApprovedHours             int64 `json:"approvedHours"`
	MonthlySubscriptionPence  int64 `json:"monthlySubscriptionRevenuePence"`
	TotalStaffingRevenuePence int64 `json:"totalStaffingRevenuePence"`
	OutstandingPence          int64 `json:"outstandingPence"`
	PractitionerGrossPence    int64 `json:"practitionerGrossWagesPence"`
	PayrollPeriods            int64 `json:"payrollPeriods"`
	SubscriptionRequests      int64 `json:"subscriptionRequests"`
}

func getQueryCount(ctx context.Context, q firestore.Query) (int64, error) {
	res, err := q.NewAggregationQuery().WithCount("count").Get(ctx)
	if err != nil {
		return 0, err
	}
	var target struct {
		Count int64 `firestore:"count"`
	}
	if err := res.DataTo(&target); err != nil {
		return 0, err
	}
	return target.Count, nil
}

// getPlatformStats — GET /getPlatformStats. Admin-only.
// Uses Firestore aggregation count queries instead of full collection scans (R9).
func getPlatformStats(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !isAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "NOT_ADMIN", "Admin claim required")
		return
	}
	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	var out platformStats
	var errCount error

	out.TotalNurseries, errCount = getQueryCount(ctx, db.Collection("profiles").Where("role", "==", string(RoleNursery)))
	if errCount != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", errCount.Error())
		return
	}
	out.TotalStaff, errCount = getQueryCount(ctx, db.Collection("profiles").Where("role", "==", string(RoleStaff)))
	if errCount != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", errCount.Error())
		return
	}
	out.SuspendedUsers, _ = getQueryCount(ctx, db.Collection("profiles").Where("suspended", "==", true))
	out.PendingDBS, _ = getQueryCount(ctx, db.Collection("profiles").Where("dbsStatus", "==", string(DBSPending)))

	out.TotalShifts, _ = getQueryCount(ctx, db.Collection("shifts").Query)
	out.OpenShifts, _ = getQueryCount(ctx, db.Collection("shifts").Where("status", "==", string(ShiftOpen)))
	out.CancelledShifts, _ = getQueryCount(ctx, db.Collection("shifts").Where("status", "==", string(ShiftCancelled)))
	out.BookedShifts, _ = getQueryCount(ctx, db.Collection("shifts").Where("status", "==", string(ShiftBooked)))

	// Phase 7 R5: Completed shifts come from timesheets (approved or admin_approved), not derived check.
	approvedTs, _ := getQueryCount(ctx, db.Collection("timesheets").Where("status", "==", string(TimesheetApproved)))
	adminApprovedTs, _ := getQueryCount(ctx, db.Collection("timesheets").Where("status", "==", string(TimesheetAdminApproved)))
	out.CompletedShifts = approvedTs + adminApprovedTs
	out.PendingTimesheets, _ = getQueryCount(ctx, db.Collection("timesheets").Where("status", "==", string(TimesheetSubmitted)))

	out.PendingDocuments, _ = getQueryCount(ctx, db.Collection("documents").Where("status", "==", string(DocPendingReview)))
	out.TotalRatings, _ = getQueryCount(ctx, db.Collection("ratings").Query)

	// Operational counters. Each one is best-effort: an unavailable aggregate
	// must not blank the whole dashboard.
	out.ActiveSubscriptions, _ = getQueryCount(ctx, db.Collection("subscriptions").Where("status", "==", string(SubActive)))
	out.TrialAccounts, _ = getQueryCount(ctx, db.Collection("subscriptions").Where("status", "==", string(SubTrialing)))
	out.PendingNurseryApprovals, _ = getQueryCount(ctx, db.Collection("profiles").Where("role", "==", string(RoleNursery)).Where("nurseryApprovalStatus", "==", string(NurseryPendingApproval)))
	out.VerifiedPractitioners, _ = getQueryCount(ctx, db.Collection("profiles").Where("vettingStatus", "==", string(VettingApproved)))
	out.PendingVetting, _ = getQueryCount(ctx, db.Collection("profiles").Where("role", "==", string(RoleStaff)).Where("vettingStatus", "==", string(VettingPendingVerification)))
	out.SubscriptionRequests, _ = getQueryCount(ctx, db.Collection("subscriptions").Where("requestedPlanId", "!=", ""))

	// Revenue and hours need sums rather than counts. These collections stay
	// small for a launch-stage marketplace; cap each scan so a runaway
	// collection cannot stall the dashboard.
	invDocs, _ := db.Collection("invoices").Limit(1000).Documents(ctx).GetAll()
	for _, doc := range invDocs {
		var inv Invoice
		if err := doc.DataTo(&inv); err != nil {
			continue
		}
		switch inv.Status {
		case InvoicePaid:
			out.TotalStaffingRevenuePence += inv.SubtotalPence
			out.MonthlySubscriptionPence += subscriptionLineTotal(inv.LineItems)
		case InvoiceIssued, InvoiceOverdue:
			out.OutstandingPence += inv.TotalPence
		}
	}
	tsDocs, _ := db.Collection("timesheets").
		Where("status", "in", []string{string(TimesheetApproved), string(TimesheetAdminApproved)}).
		Limit(2000).Documents(ctx).GetAll()
	for _, doc := range tsDocs {
		var ts Timesheet
		if err := doc.DataTo(&ts); err != nil {
			continue
		}
		out.ApprovedHours += ts.BillableMinutes / 60
		out.PractitionerGrossPence += ts.TotalGrossPayPence
	}
	out.PayrollPeriods, _ = getQueryCount(ctx, db.Collection("payrollPeriods").Query)

	httpjson.WriteJSON(w, http.StatusOK, out)
}

// listAllUsers — GET /listAllUsers. Admin-only. Every profile, summarized —
// backs the admin user-management list (full app spec: "approve, suspend
// users, etc").
func listAllUsers(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !isAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "NOT_ADMIN", "Admin claim required")
		return
	}
	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	iter := db.Collection("profiles").Documents(ctx)
	defer iter.Stop()

	out := []map[string]any{}
	for {
		snap, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		var p Profile
		if err := snap.DataTo(&p); err != nil {
			continue
		}
		out = append(out, map[string]any{
			"uid":                   snap.Ref.ID,
			"role":                  p.Role,
			"name":                  p.Name,
			"phone":                 p.Phone,
			"email":                 p.Email,
			"photoUrl":              p.PhotoURL,
			"city":                  p.City,
			"postcode":              p.Postcode,
			"qualificationLevel":    p.QualificationLevel,
			"dbsStatus":             p.DBSStatus,
			"vettingStatus":         p.VettingStatus,
			"dbsCheckedByKFlex":     p.DBSCheckedByKFlex,
			"dbsVerifiedAt":         p.DBSVerifiedAt,
			"dbsRecheckDue":         p.DBSRecheckDue,
			"nurseryApprovalStatus": p.NurseryApprovalStatus,
			"activationDate":        p.ActivationDate,
			"companyNumber":         p.CompanyNumber,
			"ofstedRegNumber":       p.OfstedRegNumber,
			"suspended":             p.Suspended,
			"identityVerified":      p.IdentityVerified,
			"ofstedVerified":        p.OfstedVerified,
			"rating":                p.Rating,
			"createdAt":             p.CreatedAt,
		})
	}
	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"users": out})
}

type userDetailRequest struct {
	UID string `json:"uid"`
}

// getUserDetail — POST /getUserDetail. Admin-only. The full private profile
// plus every document that uid has ever uploaded (not just latest-per-type
// like listMyDocuments) — backs the admin "view profile, uploaded images and
// files" request. Document bytes themselves are fetched client-side straight
// from Storage using storagePath (admin read access already granted by
// storage.rules); this only returns the metadata needed to build those refs.
func getUserDetail(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !isAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "NOT_ADMIN", "Admin claim required")
		return
	}
	var req userDetailRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	if req.UID == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "uid is required")
		return
	}
	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	profileSnap, err := db.Collection("profiles").Doc(req.UID).Get(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusNotFound, "USER_NOT_FOUND", "No profile for that uid")
		return
	}
	var profile Profile
	if err := profileSnap.DataTo(&profile); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	docIter := db.Collection("documents").Where("uid", "==", req.UID).
		OrderBy("uploadedAt", firestore.Desc).Documents(ctx)
	defer docIter.Stop()
	docs := []map[string]any{}
	for {
		snap, err := docIter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		var meta DocumentMeta
		if err := snap.DataTo(&meta); err != nil {
			continue
		}
		docs = append(docs, map[string]any{
			"docId":       snap.Ref.ID,
			"type":        meta.Type,
			"status":      meta.Status,
			"storagePath": meta.StoragePath,
			"reviewNote":  meta.ReviewNote,
			"uploadedAt":  meta.UploadedAt,
		})
	}

	profileOut := withComputedFields(ctx, req.UID, profile.Role, profile)
	httpjson.WriteJSON(w, http.StatusOK, map[string]any{
		"uid":       req.UID,
		"profile":   profileOut,
		"documents": docs,
	})
}

type setUserSuspendedRequest struct {
	UID       string `json:"uid"`
	Suspended bool   `json:"suspended"`
}

// setUserSuspended — POST /setUserSuspended. Admin-only. Disables (or
// re-enables) the Firebase Auth account — which blocks sign-in and future
// token refreshes — and mirrors the flag onto the profile doc so the admin
// list can render status without a per-row Auth lookup. Refresh tokens are
// also revoked on suspend so existing sessions stop working promptly rather
// than lingering until their short-lived ID token naturally expires.
func setUserSuspended(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !isAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "NOT_ADMIN", "Admin claim required")
		return
	}
	var req setUserSuspendedRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	if req.UID == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "uid is required")
		return
	}

	app, err := adminApp(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "auth app init failed")
		return
	}
	authClient, err := app.Auth(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "auth client init failed")
		return
	}
	update := (&firebaseauth.UserToUpdate{}).Disabled(req.Suspended)
	if _, err := authClient.UpdateUser(ctx, req.UID, update); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}
	if req.Suspended {
		if err := authClient.RevokeRefreshTokens(ctx, req.UID); err != nil {
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}
	if _, err := db.Collection("profiles").Doc(req.UID).Set(ctx, map[string]any{
		"suspended": req.Suspended,
	}, firestore.MergeAll); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"uid": req.UID, "suspended": req.Suspended})
}

type setVerificationBadgeRequest struct {
	UID      string `json:"uid"`
	Badge    string `json:"badge"` // "identity" | "ofsted" | "dbs" | "right_to_work"
	Verified bool   `json:"verified"`
}

// setVerificationBadge — POST /setVerificationBadge. Admin-only. The
// out-of-band write path for identityVerified/ofstedVerified/dbsStatus/rightToWorkVerified.
// Records an audit log entry for every admin verification update.
func setVerificationBadge(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !isAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "NOT_ADMIN", "Admin claim required")
		return
	}
	var req setVerificationBadgeRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	var field string
	var val any
	switch req.Badge {
	case "identity":
		field = "identityVerified"
		val = req.Verified
	case "ofsted":
		// Nursery approval owns this field now. The old badge shortcut is kept
		// only to return a clear error, never to bypass the workflow.
		httpjson.WriteError(w, http.StatusConflict, "USE_NURSERY_APPROVAL",
			"Approve or reject the nursery registration instead of setting the badge directly")
		return
	case "right_to_work":
		field = "rightToWorkVerified"
		val = req.Verified
	case "dbs":
		// DBS is only ever verified through the vetting checklist. This
		// endpoint must not be able to mark someone verified on its own.
		httpjson.WriteError(w, http.StatusConflict, "USE_VETTING_APPROVAL",
			"Record the vetting checklist and approve the practitioner instead")
		return
	default:
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "badge must be 'identity', 'ofsted', 'dbs', or 'right_to_work'")
		return
	}
	if req.UID == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "uid is required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}
	now := time.Now()
	if _, err := db.Collection("profiles").Doc(req.UID).Set(ctx, map[string]any{
		field: val,
	}, firestore.MergeAll); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	// Mirror to profilesPublic so client sees updated verification badge immediately
	pubField := field
	if field == "dbsStatus" {
		pubField = "dbsBadge"
	}
	_, _ = db.Collection("profilesPublic").Doc(req.UID).Set(ctx, map[string]any{
		pubField:    val,
		"updatedAt": now,
	}, firestore.MergeAll)

	// Write audit log entry
	adminUID := auth.UID(ctx)
	_, _, _ = db.Collection("auditLogs").Add(ctx, map[string]any{
		"action":    "setVerificationBadge",
		"adminUid":  adminUID,
		"targetUid": req.UID,
		"badge":     req.Badge,
		"verified":  req.Verified,
		"value":     val,
		"timestamp": now,
	})

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"uid": req.UID, "badge": req.Badge, "verified": req.Verified})
}

func subscriptionLineTotal(lines []InvoiceLineItem) int64 {
	var total int64
	for _, line := range lines {
		if line.Type == "subscription" || line.Type == "booking_fee" {
			total += line.TotalPence
		}
	}
	return total
}

// listAuditLogs — GET /listAuditLogs?limit=200. Admin-only, append-only
// source. The console shows this instead of a browser-local imitation.
func listAuditLogs(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !isAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "NOT_ADMIN", "Admin claim required")
		return
	}
	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore unavailable")
		return
	}

	limit := 200
	iter := db.Collection("auditLogs").OrderBy("timestamp", firestore.Desc).Limit(limit).Documents(ctx)
	defer iter.Stop()

	out := []map[string]any{}
	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		entry := doc.Data()
		entry["id"] = doc.Ref.ID
		out = append(out, entry)
	}
	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"entries": out})
}
