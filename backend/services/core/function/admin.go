package function

import (
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
}

// PlatformStats is the admin dashboard's platform-wide snapshot — full app
// spec admin-page request: "a dashboard that shows platform wide metrics and
// statistics". Computed on read, same MVP tradeoff as stats.go's per-nursery
// numbers (no trigger-maintained counters yet).
type platformStats struct {
	TotalNurseries   int64 `json:"totalNurseries"`
	TotalStaff       int64 `json:"totalStaff"`
	SuspendedUsers   int64 `json:"suspendedUsers"`
	PendingDBS       int64 `json:"pendingDbs"`
	TotalShifts      int64 `json:"totalShifts"`
	OpenShifts       int64 `json:"openShifts"`
	BookedShifts     int64 `json:"bookedShifts"`
	CompletedShifts  int64 `json:"completedShifts"`
	CancelledShifts  int64 `json:"cancelledShifts"`
	PendingDocuments int64 `json:"pendingDocuments"`
	TotalRatings     int64 `json:"totalRatings"`
}

// getPlatformStats — GET /getPlatformStats. Admin-only. Full collection
// scans across profiles/shifts/documents — same "fine at MVP scale, revisit
// with real volume" tradeoff already accepted by stats.go and
// listPendingDocuments.
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

	profileIter := db.Collection("profiles").Documents(ctx)
	defer profileIter.Stop()
	for {
		snap, err := profileIter.Next()
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
		switch p.Role {
		case RoleNursery:
			out.TotalNurseries++
		case RoleStaff:
			out.TotalStaff++
		}
		if p.Suspended {
			out.SuspendedUsers++
		}
		if p.DBSStatus == DBSPending {
			out.PendingDBS++
		}
	}

	now := time.Now()
	shiftIter := db.Collection("shifts").Documents(ctx)
	defer shiftIter.Stop()
	for {
		snap, err := shiftIter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		var s Shift
		if err := snap.DataTo(&s); err != nil {
			continue
		}
		out.TotalShifts++
		switch {
		case s.Status == ShiftCancelled:
			out.CancelledShifts++
		case now.After(s.EndTime):
			out.CompletedShifts++
		case len(s.BookedStaffIDs) > 0 || s.BookedStaffID != nil:
			out.BookedShifts++
		default:
			out.OpenShifts++
		}
	}

	pendingDocsIter := db.Collection("documents").Where("status", "==", string(DocPendingReview)).Documents(ctx)
	defer pendingDocsIter.Stop()
	for {
		_, err := pendingDocsIter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		out.PendingDocuments++
	}

	ratingsIter := db.Collection("ratings").Documents(ctx)
	defer ratingsIter.Stop()
	for {
		_, err := ratingsIter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		out.TotalRatings++
	}

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
			"uid":              snap.Ref.ID,
			"role":             p.Role,
			"name":             p.Name,
			"phone":            p.Phone,
			"email":            p.Email,
			"dbsStatus":        p.DBSStatus,
			"suspended":        p.Suspended,
			"identityVerified": p.IdentityVerified,
			"ofstedVerified":   p.OfstedVerified,
			"rating":           p.Rating,
			"createdAt":        p.CreatedAt,
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
		field = "ofstedVerified"
		val = req.Verified
	case "right_to_work":
		field = "rightToWorkVerified"
		val = req.Verified
	case "dbs":
		field = "dbsStatus"
		if req.Verified {
			val = string(DBSVerified)
		} else {
			val = string(DBSUnverified)
		}
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
