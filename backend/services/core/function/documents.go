package function

import (
	"context"
	"fmt"
	"net/http"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/GoogleCloudPlatform/functions-framework-go/functions"
	"google.golang.org/api/iterator"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"bridgeflex/shared/auth"
	"bridgeflex/shared/httpjson"
)

func init() {
	functions.HTTP("CreateDocument", authed(createDocument))
	functions.HTTP("ReviewDocument", authed(reviewDocument))
	functions.HTTP("GetDocumentStatus", authed(getDocumentStatus))
	functions.HTTP("ListMyDocuments", authed(listMyDocuments))
	functions.HTTP("ListPendingDocuments", authed(listPendingDocuments))
}

// listPendingDocuments — GET /listPendingDocuments. Admin-only: every
// documents/{id} still awaiting review, across all users — the queue the
// admin review screen works through, one reviewDocument call at a time.
func listPendingDocuments(w http.ResponseWriter, r *http.Request) {
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

	iter := db.Collection("documents").Where("status", "==", string(DocPendingReview)).
		OrderBy("uploadedAt", firestore.Asc).Documents(ctx)
	defer iter.Stop()

	out := []map[string]any{}
	for {
		docSnap, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		var meta DocumentMeta
		if err := docSnap.DataTo(&meta); err != nil {
			continue
		}
		out = append(out, map[string]any{
			"docId":       docSnap.Ref.ID,
			"uid":         meta.UID,
			"type":        meta.Type,
			"storagePath": meta.StoragePath,
			"uploadedAt":  meta.UploadedAt,
		})
	}
	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"documents": out})
}

// documentTypePrefix returns the Storage path prefix a given document type
// must live under, mirroring storage.rules. dbs_certificate keeps its
// original top-level dbs-documents/ prefix for backward compatibility with
// existing uploads/rules; every other type (added for the full staff
// documents checklist — CV, ID, qualifications, first aid, right to work)
// lives under personal-documents/{uid}/{type}/.
func documentTypePrefix(uid, docType string) string {
	if docType == "dbs_certificate" {
		return fmt.Sprintf("dbs-documents/%s/", uid)
	}
	return fmt.Sprintf("personal-documents/%s/%s/", uid, docType)
}

var validDocumentTypes = map[string]bool{
	"dbs_certificate": true,
	"cv":              true,
	"id":              true,
	"qualification":   true,
	"first_aid":       true,
	"right_to_work":   true,
}

type createDocumentRequest struct {
	StoragePath string `json:"storagePath"`
	Type        string `json:"type"`
}

// createDocument — POST /createDocument. Owner-only metadata create; the
// storagePath must sit under the caller's own type-specific prefix (see
// documentTypePrefix), mirroring both the Firestore and Storage rules (§2/§3).
func createDocument(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	uid := auth.UID(ctx)

	var req createDocumentRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	if req.Type == "" {
		req.Type = "dbs_certificate"
	}
	if !validDocumentTypes[req.Type] {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "unknown document type")
		return
	}
	wantPrefix := documentTypePrefix(uid, req.Type)
	if req.StoragePath == "" || !strings.HasPrefix(req.StoragePath, wantPrefix) {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", fmt.Sprintf("storagePath must be under %s", wantPrefix))
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}
	doc := DocumentMeta{
		UID:         uid,
		Type:        req.Type,
		StoragePath: req.StoragePath,
		Status:      DocPendingReview,
		UploadedAt:  time.Now(),
	}
	ref, _, err := db.Collection("documents").Add(ctx, doc)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	// Only a DBS certificate upload flips dbsStatus — the other document
	// types (CV, id, etc.) don't drive any profile badge on upload, only on
	// review (right-to-work verification is the one other type reviewDocument
	// can flip a badge for; see reviewDocument below).
	if req.Type == "dbs_certificate" {
		_, err = db.Collection("profiles").Doc(uid).Update(ctx, []firestore.Update{
			{Path: "dbsStatus", Value: string(DBSPending)},
		})
		if err != nil {
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
	}

	httpjson.WriteJSON(w, http.StatusCreated, map[string]string{"docId": ref.ID})
}

// listMyDocuments — GET /listMyDocuments. Returns the caller's most recent
// document of each type they've ever uploaded — backs the staff "documents
// checklist" (DBS / ID / qualifications / first aid / right to work) on the
// profile screen, which needs status per type rather than the single
// most-recent-of-any-type getDocumentStatus returns.
func listMyDocuments(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	uid := auth.UID(ctx)

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	iter := db.Collection("documents").Where("uid", "==", uid).
		OrderBy("uploadedAt", firestore.Desc).Documents(ctx)
	defer iter.Stop()

	latestByType := make(map[string]map[string]any)
	for {
		docSnap, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		var meta DocumentMeta
		if err := docSnap.DataTo(&meta); err != nil {
			continue
		}
		if _, seen := latestByType[meta.Type]; seen {
			continue
		}
		latestByType[meta.Type] = map[string]any{
			"docId":      docSnap.Ref.ID,
			"type":       meta.Type,
			"status":     string(meta.Status),
			"reviewNote": meta.ReviewNote,
			"uploadedAt": meta.UploadedAt,
		}
	}

	out := make([]map[string]any, 0, len(latestByType))
	for _, v := range latestByType {
		out = append(out, v)
	}
	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"documents": out})
}

// getDocumentStatus — GET /getDocumentStatus. The caller's own most recent
// DBS document, or a "none" placeholder if they've never uploaded one — the
// DBS upload screen (full app spec §4.1) needs this to show a current
// status badge instead of a bare upload button. Already client-legal per
// Security Rules (owner can read their own `documents` docs); this is a
// plain-HTTP mirror, same rationale as listMyShifts/listChatSessions.
func getDocumentStatus(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	uid := auth.UID(ctx)

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	iter := db.Collection("documents").Where("uid", "==", uid).
		OrderBy("uploadedAt", firestore.Desc).Limit(1).Documents(ctx)
	defer iter.Stop()

	doc, err := iter.Next()
	if err == iterator.Done {
		httpjson.WriteJSON(w, http.StatusOK, map[string]any{"status": "none"})
		return
	}
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}
	var meta DocumentMeta
	if err := doc.DataTo(&meta); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}
	httpjson.WriteJSON(w, http.StatusOK, map[string]any{
		"docId":      doc.Ref.ID,
		"status":     string(meta.Status),
		"reviewNote": meta.ReviewNote,
		"uploadedAt": meta.UploadedAt,
	})
}

type reviewDocumentRequest struct {
	DocID   string `json:"docId"`
	Approve bool   `json:"approve"`
	Note    string `json:"note,omitempty"`
}

// reviewDocument — POST /reviewDocument. Admin-only manual-review step (§8
// item 2 — the real verification method is an open product question; this
// endpoint is the mechanical "someone with the admin claim marks it
// verified/rejected" half regardless of what triggers that decision).
// Admin-ness is a Firebase custom claim, set out-of-band (not by any
// endpoint in this codebase) — there is no self-service path to it.
func reviewDocument(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !isAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "NOT_ADMIN", "Admin claim required")
		return
	}

	var req reviewDocumentRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	if req.DocID == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "docId is required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}
	ref := db.Collection("documents").Doc(req.DocID)
	snap, err := ref.Get(ctx)
	if status.Code(err) == codes.NotFound {
		httpjson.WriteError(w, http.StatusNotFound, "DOCUMENT_NOT_FOUND", "Document not found")
		return
	}
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}
	var docMeta DocumentMeta
	if err := snap.DataTo(&docMeta); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	newStatus := DocRejected
	if req.Approve {
		newStatus = DocVerified
	}
	now := time.Now()

	_, err = ref.Update(ctx, []firestore.Update{
		{Path: "status", Value: string(newStatus)},
		{Path: "reviewedAt", Value: now},
		{Path: "reviewNote", Value: req.Note},
	})
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	// Only dbs_certificate and right_to_work reviews drive a profile badge;
	// the other document types (CV, id, qualification, first_aid) are
	// informational uploads with no corresponding verified/unverified field.
	var profileUpdates []firestore.Update
	switch docMeta.Type {
	case "dbs_certificate":
		dbsStatus := DBSUnverified
		if req.Approve {
			dbsStatus = DBSVerified
		}
		profileUpdates = append(profileUpdates, firestore.Update{Path: "dbsStatus", Value: string(dbsStatus)})
	case "right_to_work":
		profileUpdates = append(profileUpdates, firestore.Update{Path: "rightToWorkVerified", Value: req.Approve})
	}
	if len(profileUpdates) > 0 {
		_, err = db.Collection("profiles").Doc(docMeta.UID).Update(ctx, profileUpdates)
		if err != nil {
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
	}

	httpjson.WriteJSON(w, http.StatusOK, map[string]string{"docId": req.DocID, "status": string(newStatus)})
}

// isAdmin checks the "admin" custom claim on the caller's decoded ID token.
// Custom claims aren't part of the shared auth.UID() contract (that only
// exposes uid), so this reads the claim straight from context in the one
// place it's needed rather than growing the shared middleware's surface for
// a single-endpoint concern.
func isAdmin(ctx context.Context) bool {
	return auth.CustomClaim(ctx, "admin") == true
}
