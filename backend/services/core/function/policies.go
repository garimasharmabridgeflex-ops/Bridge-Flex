package function

import (
	"context"
	"fmt"
	"net/http"
	"regexp"
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
	functions.HTTP("GetRequiredPolicies", getRequiredPolicies)
	functions.HTTP("GetPolicy", getPolicy)
	functions.HTTP("AcceptPolicies", authed(acceptPolicies))
	functions.HTTP("AdminSavePolicyDraft", authed(adminSavePolicyDraft))
	functions.HTTP("AdminApprovePolicy", authed(adminApprovePolicy))
	functions.HTTP("AdminPublishPolicy", authed(adminPublishPolicy))
}

type PolicyType string

const (
	PolicyNurseryTerms        PolicyType = "nursery_terms"
	PolicyPractitionerTerms   PolicyType = "practitioner_terms"
	PolicyPrivacy             PolicyType = "privacy"
	PolicyCancellationRefund  PolicyType = "cancellation_refund"
	PolicySafeguarding        PolicyType = "safeguarding"
	PolicyCookie              PolicyType = "cookie"
	PolicyEngagementAgreement PolicyType = "engagement_agreement"
	PolicyKeyInfoDocument     PolicyType = "key_information_document"
)

type PolicyStatus string

const (
	PolicyStatusDraft     PolicyStatus = "draft"
	PolicyStatusApproved  PolicyStatus = "approved"
	PolicyStatusPublished PolicyStatus = "published"
)

type Policy struct {
	ID          string       `firestore:"id" json:"id"`
	Type        PolicyType   `firestore:"type" json:"type"`
	Version     int64        `firestore:"version" json:"version"`
	Status      PolicyStatus `firestore:"status" json:"status"`
	Title       string       `firestore:"title" json:"title"`
	Content     string       `firestore:"content" json:"content"`
	Summary     string       `firestore:"summary,omitempty" json:"summary,omitempty"`
	CreatedAt   time.Time    `firestore:"createdAt" json:"createdAt"`
	UpdatedAt   time.Time    `firestore:"updatedAt" json:"updatedAt"`
	PublishedAt *time.Time   `firestore:"publishedAt,omitempty" json:"publishedAt,omitempty"`
	ApprovedBy  string       `firestore:"approvedBy,omitempty" json:"approvedBy,omitempty"`
	PublishedBy string       `firestore:"publishedBy,omitempty" json:"publishedBy,omitempty"`
}

type PolicyAcceptance struct {
	UID        string     `firestore:"uid" json:"uid"`
	PolicyType PolicyType `firestore:"policyType" json:"policyType"`
	Version    int64      `firestore:"version" json:"version"`
	AcceptedAt time.Time  `firestore:"acceptedAt" json:"acceptedAt"`
	AppVersion string     `firestore:"appVersion,omitempty" json:"appVersion,omitempty"`
	Status     string     `firestore:"status" json:"status"` // "accepted"
}

// placeholderRegex matches bracketed placeholders like [REGISTERED COMPANY NAME] or [DATE]
var placeholderRegex = regexp.MustCompile(`\[[A-Z0-9 _-]{2,}\]`)

func hasUnresolvedPlaceholders(text string) bool {
	return placeholderRegex.MatchString(text)
}

// getRequiredPolicies — GET /getRequiredPolicies?role=staff|nursery
// Returns currently published policies required for onboarding or re-acceptance.
func getRequiredPolicies(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	role := r.URL.Query().Get("role")
	if role == "" {
		role = "staff"
	}

	var requiredTypes []PolicyType
	if role == "nursery" {
		requiredTypes = []PolicyType{
			PolicyNurseryTerms,
			PolicyPrivacy,
			PolicySafeguarding,
			PolicyCancellationRefund,
			PolicyCookie,
		}
	} else {
		requiredTypes = []PolicyType{
			PolicyPractitionerTerms,
			PolicyPrivacy,
			PolicySafeguarding,
			PolicyCancellationRefund,
			PolicyCookie,
		}
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore unavailable")
		return
	}

	policies := make([]Policy, 0, len(requiredTypes))
	for _, pType := range requiredTypes {
		iter := db.Collection("policies").
			Where("type", "==", string(pType)).
			Where("status", "==", string(PolicyStatusPublished)).
			OrderBy("version", firestore.Desc).
			Limit(1).
			Documents(ctx)
		defer iter.Stop()

		snap, err := iter.Next()
		if err == iterator.Done {
			// No published version yet
			continue
		}
		if err != nil {
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		var p Policy
		if err := snap.DataTo(&p); err == nil {
			policies = append(policies, p)
		}
	}

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"policies": policies})
}

// getPolicy — GET /getPolicy?type=...
// Public read endpoint returning the latest published version of a policy.
func getPolicy(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	pType := r.URL.Query().Get("type")
	if pType == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "type is required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore unavailable")
		return
	}

	iter := db.Collection("policies").
		Where("type", "==", pType).
		Where("status", "==", string(PolicyStatusPublished)).
		OrderBy("version", firestore.Desc).
		Limit(1).
		Documents(ctx)
	defer iter.Stop()

	snap, err := iter.Next()
	if err == iterator.Done {
		httpjson.WriteError(w, http.StatusNotFound, "NOT_FOUND", "no published policy found for type")
		return
	}
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	var p Policy
	if err := snap.DataTo(&p); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	httpjson.WriteJSON(w, http.StatusOK, p)
}

type acceptanceItem struct {
	PolicyType PolicyType `json:"policyType"`
	Version    int64      `json:"version"`
}

type acceptPoliciesRequest struct {
	Acceptances []acceptanceItem `json:"acceptances"`
	AppVersion  string           `json:"appVersion"`
}

// acceptPolicies — POST /acceptPolicies. Idempotent acceptance of required policies.
// Records uid, policy type, version, timestamp, and app version (no IP address, decision 14 default).
func acceptPolicies(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	uid := auth.UID(ctx)

	var req acceptPoliciesRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	if len(req.Acceptances) == 0 {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "acceptances list cannot be empty")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore unavailable")
		return
	}

	now := time.Now().UTC()
	batch := db.Batch()

	for _, item := range req.Acceptances {
		docID := fmt.Sprintf("%s_%s_%d", uid, item.PolicyType, item.Version)
		ref := db.Collection("policyAcceptances").Doc(docID)
		acc := PolicyAcceptance{
			UID:        uid,
			PolicyType: item.PolicyType,
			Version:    item.Version,
			AcceptedAt: now,
			AppVersion: req.AppVersion,
			Status:     "accepted",
		}
		batch.Set(ref, acc)
	}

	// Update summary flag on user profile
	profileRef := db.Collection("profiles").Doc(uid)
	batch.Set(profileRef, map[string]any{
		"currentTermsAccepted": true,
		"lastTermsAcceptedAt":  now,
	}, firestore.MergeAll)

	if _, err := batch.Commit(ctx); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{
		"status":   "accepted",
		"count":    len(req.Acceptances),
		"accepted": true,
	})
}

type saveDraftRequest struct {
	ID      string     `json:"id,omitempty"`
	Type    PolicyType `json:"type"`
	Title   string     `json:"title"`
	Content string     `json:"content"`
	Summary string     `json:"summary,omitempty"`
}

// adminSavePolicyDraft — POST /adminSavePolicyDraft. Admin only. Saves draft.
func adminSavePolicyDraft(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !isAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "NOT_ADMIN", "Admin permissions required")
		return
	}

	var req saveDraftRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	if req.Type == "" || req.Title == "" || req.Content == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "type, title, and content are required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore unavailable")
		return
	}

	now := time.Now().UTC()
	var docRef *firestore.DocumentRef
	var version int64 = 1

	if req.ID != "" {
		docRef = db.Collection("policies").Doc(req.ID)
		snap, err := docRef.Get(ctx)
		if err == nil {
			var existing Policy
			if err := snap.DataTo(&existing); err == nil {
				version = existing.Version
			}
		}
	} else {
		// Determine next version for this policy type
		iter := db.Collection("policies").Where("type", "==", string(req.Type)).OrderBy("version", firestore.Desc).Limit(1).Documents(ctx)
		defer iter.Stop()
		if snap, err := iter.Next(); err == nil {
			var latest Policy
			if err := snap.DataTo(&latest); err == nil {
				version = latest.Version + 1
			}
		}
		docRef = db.Collection("policies").NewDoc()
	}

	policy := Policy{
		ID:        docRef.ID,
		Type:      req.Type,
		Version:   version,
		Status:    PolicyStatusDraft,
		Title:     req.Title,
		Content:   req.Content,
		Summary:   req.Summary,
		CreatedAt: now,
		UpdatedAt: now,
	}

	if _, err := docRef.Set(ctx, policy, firestore.MergeAll); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:    "savePolicyDraft",
		TargetDoc: "policies/" + docRef.ID,
		Fields:    []string{"type", "title", "version"},
	})

	httpjson.WriteJSON(w, http.StatusOK, policy)
}

// adminApprovePolicy — POST /adminApprovePolicy. Admin only. Transitions draft -> approved.
func adminApprovePolicy(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !isAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "NOT_ADMIN", "Admin permissions required")
		return
	}

	var req struct {
		PolicyID string `json:"policyId"`
	}
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore unavailable")
		return
	}

	adminUID := auth.UID(ctx)
	now := time.Now().UTC()
	ref := db.Collection("policies").Doc(req.PolicyID)

	err = db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		snap, err := tx.Get(ref)
		if err != nil {
			return err
		}
		var p Policy
		if err := snap.DataTo(&p); err != nil {
			return err
		}
		if p.Status != PolicyStatusDraft {
			return status.Errorf(codes.FailedPrecondition, "policy is not in draft status")
		}
		return tx.Update(ref, []firestore.Update{
			{Path: "status", Value: string(PolicyStatusApproved)},
			{Path: "approvedBy", Value: adminUID},
			{Path: "updatedAt", Value: now},
		})
	})

	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:    "approvePolicy",
		TargetDoc: "policies/" + req.PolicyID,
	})

	httpjson.WriteJSON(w, http.StatusOK, map[string]string{"status": "approved", "policyId": req.PolicyID})
}

// adminPublishPolicy — POST /adminPublishPolicy. Super Admin only.
// Validates that no bracketed placeholders remain (e.g. [REGISTERED COMPANY NAME]).
// Transitions approved -> published and records outbox event.
func adminPublishPolicy(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !auth.HasRole(ctx, auth.AdminRoleSuperAdmin) {
		httpjson.WriteError(w, http.StatusForbidden, "NOT_SUPER_ADMIN", "Super Admin role required to publish policies")
		return
	}

	var req struct {
		PolicyID string `json:"policyId"`
	}
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore unavailable")
		return
	}

	adminUID := auth.UID(ctx)
	now := time.Now().UTC()
	ref := db.Collection("policies").Doc(req.PolicyID)

	var publishedPolicy Policy
	err = db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		snap, err := tx.Get(ref)
		if err != nil {
			return err
		}
		if err := snap.DataTo(&publishedPolicy); err != nil {
			return err
		}

		// Owner's strict invariant: block publishing while bracketed placeholders remain
		if hasUnresolvedPlaceholders(publishedPolicy.Content) {
			return status.Errorf(codes.FailedPrecondition, "ERR_UNRESOLVED_PLACEHOLDERS: Cannot publish policy while bracketed placeholders e.g. [COMPANY NAME] remain")
		}

		if err := tx.Update(ref, []firestore.Update{
			{Path: "status", Value: string(PolicyStatusPublished)},
			{Path: "publishedAt", Value: now},
			{Path: "publishedBy", Value: adminUID},
			{Path: "updatedAt", Value: now},
		}); err != nil {
			return err
		}

		// Outbox event to notify clients and subscribers
		return outbox.WriteTx(tx, db, outbox.Event{
			Topic: "policy-published",
			Payload: map[string]any{
				"policyId":   publishedPolicy.ID,
				"policyType": string(publishedPolicy.Type),
				"version":    publishedPolicy.Version,
				"title":      publishedPolicy.Title,
			},
		})
	})

	if err != nil {
		if status.Code(err) == codes.FailedPrecondition {
			httpjson.WriteError(w, http.StatusBadRequest, "ERR_UNRESOLVED_PLACEHOLDERS", err.Error())
			return
		}
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:    "publishPolicy",
		TargetDoc: "policies/" + req.PolicyID,
		Fields:    []string{"status", "publishedAt", "publishedBy"},
	})

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{
		"status":      "published",
		"policyId":    req.PolicyID,
		"publishedAt": now,
	})
}
