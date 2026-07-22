package function

import (
	"context"
	"fmt"
	"net/http"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/GoogleCloudPlatform/functions-framework-go/functions"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"bridgeflex/shared/auth"
	"bridgeflex/shared/httpjson"
)

func init() {
	functions.HTTP("CreateDocument", authed(createDocument))
	functions.HTTP("ReviewDocument", authed(reviewDocument))
}

type createDocumentRequest struct {
	StoragePath string `json:"storagePath"`
	Type        string `json:"type"`
}

// createDocument — POST /createDocument. Owner-only metadata create; the
// storagePath must sit under the caller's own dbs-documents/{uid}/ prefix,
// mirroring both the Firestore and Storage rules (§2/§3).
func createDocument(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	uid := auth.UID(ctx)

	var req createDocumentRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	wantPrefix := fmt.Sprintf("dbs-documents/%s/", uid)
	if req.StoragePath == "" || !strings.HasPrefix(req.StoragePath, wantPrefix) {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "storagePath must be under dbs-documents/<your-uid>/")
		return
	}
	if req.Type == "" {
		req.Type = "dbs_certificate"
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

	// Uploading a DBS document also flips the owner's dbsStatus to 'pending'
	// so the review queue has something to act on. This write goes through
	// profiles/{uid}, which cascades to profilesPublic.dbsBadge automatically.
	_, err = db.Collection("profiles").Doc(uid).Update(ctx, []firestore.Update{
		{Path: "dbsStatus", Value: string(DBSPending)},
	})
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	httpjson.WriteJSON(w, http.StatusCreated, map[string]string{"docId": ref.ID})
}

type reviewDocumentRequest struct {
	DocID   string `json:"docId"`
	Approve bool   `json:"approve"`
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
	newDBSStatus := DBSUnverified
	if req.Approve {
		newStatus = DocVerified
		newDBSStatus = DBSVerified
	}
	now := time.Now()

	_, err = ref.Update(ctx, []firestore.Update{
		{Path: "status", Value: string(newStatus)},
		{Path: "reviewedAt", Value: now},
	})
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}
	_, err = db.Collection("profiles").Doc(docMeta.UID).Update(ctx, []firestore.Update{
		{Path: "dbsStatus", Value: string(newDBSStatus)},
	})
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
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
