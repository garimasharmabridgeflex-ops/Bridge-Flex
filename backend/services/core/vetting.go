package function

import (
	"context"
	"net/http"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/GoogleCloudPlatform/functions-framework-go/functions"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"kvision.internal/shared/audit"
	"kvision.internal/shared/auth"
	"kvision.internal/shared/crypto"
	"kvision.internal/shared/httpjson"
	"kvision.internal/shared/outbox"
)

func init() {
	functions.HTTP("GetVettingChecklist", authed(getVettingChecklist))
	functions.HTTP("RecordVettingCheck", authed(recordVettingCheck))
	functions.HTTP("RequestMoreDocuments", authed(requestMoreDocuments))
	functions.HTTP("ApprovePractitionerVetting", authed(approvePractitionerVetting))
	functions.HTTP("RejectPractitionerVetting", authed(rejectPractitionerVetting))
	functions.HTTP("UpdateSensitiveProfile", authed(updateSensitiveProfile))
	functions.HTTP("GetSensitiveProfile", authed(getSensitiveProfile))
}

func isVerifierOrAdmin(ctx context.Context) bool {
	return auth.HasRole(ctx, auth.AdminRoleVerifier, auth.AdminRoleSuperAdmin) || isAdmin(ctx)
}

// getVettingChecklist — GET /getVettingChecklist?uid=... Admin/Verifier only.
func getVettingChecklist(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !isVerifierOrAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "FORBIDDEN", "Verifier or admin permission required")
		return
	}

	targetUID := r.URL.Query().Get("uid")
	if targetUID == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "uid is required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore unavailable")
		return
	}

	snap, err := db.Collection("vetting").Doc(targetUID).Get(ctx)
	if status.Code(err) == codes.NotFound {
		// Return empty pending checklist
		checklist := VettingChecklist{
			UID:                 targetUID,
			Identity:            VettingCheckItem{Result: CheckPending},
			OriginalCertificate: VettingCheckItem{Result: CheckPending},
			Suitability:         VettingCheckItem{Result: CheckPending},
			Workforce:           VettingCheckItem{Result: CheckPending},
			BarredList:          VettingCheckItem{Result: CheckPending},
			UpdateService:       VettingCheckItem{Result: CheckPending},
			RightToWork:         VettingCheckItem{Result: CheckPending},
			Qualification:       VettingCheckItem{Result: CheckPending},
			References:          VettingCheckItem{Result: CheckPending},
			Safeguarding:        VettingCheckItem{Result: CheckPending},
			FirstAid:            VettingCheckItem{Result: CheckPending},
		}
		httpjson.WriteJSON(w, http.StatusOK, checklist)
		return
	}
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	var checklist VettingChecklist
	if err := snap.DataTo(&checklist); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	httpjson.WriteJSON(w, http.StatusOK, checklist)
}

type recordCheckRequest struct {
	UID       string      `json:"uid"`
	CheckName string      `json:"checkName"`
	Result    CheckResult `json:"result"` // "passed" | "failed" | "pending"
	Note      string      `json:"note"`
}

// recordVettingCheck — POST /recordVettingCheck. Verifier records an individual check sign-off.
func recordVettingCheck(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !isVerifierOrAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "FORBIDDEN", "Verifier or admin permission required")
		return
	}

	var req recordCheckRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	if req.UID == "" || req.CheckName == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "uid and checkName are required")
		return
	}
	if !allowedVettingChecks[req.CheckName] {
		httpjson.WriteError(w, http.StatusBadRequest, "UNKNOWN_CHECK", "checkName is not a recognised vetting check")
		return
	}
	if req.Result != CheckPending && req.Result != CheckPassed && req.Result != CheckFailed {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_RESULT", "result must be passed, failed or pending")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore unavailable")
		return
	}

	checkerUID := auth.UID(ctx)
	now := time.Now().UTC()
	item := VettingCheckItem{
		Result:     req.Result,
		CheckerUID: checkerUID,
		CheckedAt:  &now,
		Note:       req.Note,
	}

	ref := db.Collection("vetting").Doc(req.UID)
	if _, err := ref.Set(ctx, map[string]any{
		req.CheckName: item,
		"updatedAt":   now,
	}, firestore.MergeAll); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:    "recordVettingCheck",
		TargetUID: req.UID,
		Fields:    []string{req.CheckName, string(req.Result)},
	})

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{
		"uid":       req.UID,
		"checkName": req.CheckName,
		"result":    req.Result,
		"checkedAt": now,
	})
}

type requestMoreDocsRequest struct {
	UID      string   `json:"uid"`
	Message  string   `json:"message"`
	DocTypes []string `json:"docTypes"`
}

// requestMoreDocuments — POST /requestMoreDocuments. Verifier requests additional evidence.
func requestMoreDocuments(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !isVerifierOrAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "FORBIDDEN", "Verifier or admin permission required")
		return
	}

	var req requestMoreDocsRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	if req.UID == "" || req.Message == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "uid and message are required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore unavailable")
		return
	}

	now := time.Now().UTC()
	reqDoc := DocumentRequest{
		UID:         req.UID,
		RequestedBy: auth.UID(ctx),
		Message:     req.Message,
		DocTypes:    req.DocTypes,
		CreatedAt:   now,
		Resolved:    false,
	}

	batch := db.Batch()
	newReqRef := db.Collection("vetting").Doc(req.UID).Collection("requests").NewDoc()
	reqDoc.ID = newReqRef.ID
	batch.Set(newReqRef, reqDoc)

	// Set vetting status to rejected_further_info
	profileRef := db.Collection("profiles").Doc(req.UID)
	batch.Set(profileRef, map[string]any{
		"vettingStatus": string(VettingRejectedFurtherInfo),
		"updatedAt":     now,
	}, firestore.MergeAll)

	if _, err := batch.Commit(ctx); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	_ = notifyInApp(ctx, db, req.UID, "vetting_documents_requested", "More information needed",
		req.Message, map[string]any{"docTypes": req.DocTypes})

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:    "requestMoreDocuments",
		TargetUID: req.UID,
		Fields:    req.DocTypes,
	})

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"status": "requested", "requestId": reqDoc.ID})
}

// approvePractitionerVetting — POST /approvePractitionerVetting.
// Verifies required checks, sets vettingStatus: approved, dbsCheckedByKFlex: true,
// calculates dbsRecheckDue (12 months from now), and logs audit trail.
func approvePractitionerVetting(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !isVerifierOrAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "FORBIDDEN", "Verifier or admin permission required")
		return
	}

	var req struct {
		UID string `json:"uid"`
	}
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	if req.UID == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "uid is required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore unavailable")
		return
	}

	// DBS verification is only complete when an authorised person has recorded
	// every required check. Uploading a certificate or typing a number never
	// approves anyone.
	checkSnap, err := db.Collection("vetting").Doc(req.UID).Get(ctx)
	if err != nil && status.Code(err) != codes.NotFound {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}
	var checklist VettingChecklist
	if checkSnap != nil && checkSnap.Exists() {
		_ = checkSnap.DataTo(&checklist)
	}
	missing := missingVettingChecks(checklist)
	if len(missing) > 0 {
		httpjson.WriteError(w, http.StatusConflict, "VETTING_INCOMPLETE",
			"Record every required vetting check before approving: "+strings.Join(missing, ", "))
		return
	}

	now := time.Now().UTC()
	recheckDue := now.AddDate(1, 0, 0) // 12-month recheck interval per owner rule

	err = db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		profileRef := db.Collection("profiles").Doc(req.UID)
		if err := tx.Set(profileRef, map[string]any{
			"vettingStatus":       string(VettingApproved),
			"dbsCheckedByKFlex":   true,
			"dbsVerifiedAt":       now,
			"dbsRecheckDue":       recheckDue,
			"dbsStatus":           string(DBSVerified),
			"rightToWorkVerified": true,
			"updatedAt":           now,
		}, firestore.MergeAll); err != nil {
			return err
		}

		// Mirror to profilesPublic
		pubRef := db.Collection("profilesPublic").Doc(req.UID)
		if err := tx.Set(pubRef, map[string]any{
			"vettingStatus":     string(VettingApproved),
			"dbsCheckedByKFlex": true,
			"dbsRecheckDue":     recheckDue,
			"dbsBadge":          string(DBSVerified),
			"updatedAt":         now,
		}, firestore.MergeAll); err != nil {
			return err
		}

		// Outbox notification
		return outbox.WriteTx(tx, db, outbox.Event{
			Topic: "practitioner-vetting-approved",
			Payload: map[string]any{
				"uid":        req.UID,
				"approvedAt": now,
				"recheckDue": recheckDue,
			},
		})
	})

	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:    "approvePractitionerVetting",
		TargetUID: req.UID,
		Fields:    []string{"vettingStatus", "dbsCheckedByKFlex", "dbsRecheckDue"},
	})

	_ = notifyInApp(ctx, db, req.UID, "vetting_approved", "DBS Checked by K Flex",
		"Your verification is complete. You can now apply for shifts.",
		map[string]any{"dbsRecheckDue": recheckDue.Format(time.RFC3339)})
	sendTransactionalEmail(ctx, db, req.UID, "vetting_approved",
		map[string]string{"recheckDue": recheckDue.Format("02 Jan 2006")}, true)

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{
		"uid":           req.UID,
		"vettingStatus": string(VettingApproved),
		"dbsRecheckDue": recheckDue,
	})
}

// rejectPractitionerVetting — POST /rejectPractitionerVetting.
func rejectPractitionerVetting(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !isVerifierOrAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "FORBIDDEN", "Verifier or admin permission required")
		return
	}

	var req struct {
		UID    string `json:"uid"`
		Reason string `json:"reason"`
	}
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	if req.UID == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "uid is required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore unavailable")
		return
	}

	now := time.Now().UTC()
	ref := db.Collection("profiles").Doc(req.UID)
	if _, err := ref.Set(ctx, map[string]any{
		"vettingStatus": string(VettingRejectedFurtherInfo),
		"vettingNote":   req.Reason,
		"updatedAt":     now,
	}, firestore.MergeAll); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	_, _ = db.Collection("profilesPublic").Doc(req.UID).Set(ctx, map[string]any{
		"vettingStatus": string(VettingRejectedFurtherInfo),
		"updatedAt":     now,
	}, firestore.MergeAll)

	_ = notifyInApp(ctx, db, req.UID, "vetting_rejected", "Verification needs attention",
		req.Reason, map[string]any{"reason": req.Reason})
	sendTransactionalEmail(ctx, db, req.UID, "vetting_rejected",
		map[string]string{"reason": req.Reason}, true)

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:    "rejectPractitionerVetting",
		TargetUID: req.UID,
		Fields:    []string{"vettingStatus", req.Reason},
	})

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"uid": req.UID, "vettingStatus": string(VettingRejectedFurtherInfo)})
}

type updateSensitiveRequest struct {
	DateOfBirth       *string `json:"dateOfBirth,omitempty"`
	NationalInsurance *string `json:"nationalInsurance,omitempty"`
	BankAccount       *string `json:"bankAccount,omitempty"`
	SortCode          *string `json:"sortCode,omitempty"`
	FullAddress       *string `json:"fullAddress,omitempty"`
	DBSCertificate    *string `json:"dbsCertificate,omitempty"`
}

// updateSensitiveProfile — POST /updateSensitiveProfile.
// Segregates sensitive personal details into KMS/envelope encrypted store (sensitive/{uid}).
// Never writes these fields into profiles/{uid} or logs.
func updateSensitiveProfile(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	uid := auth.UID(ctx)

	var req updateSensitiveRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore unavailable")
		return
	}

	now := time.Now().UTC()
	updates := map[string]any{
		"uid":       uid,
		"updatedAt": now,
	}

	if req.DateOfBirth != nil {
		enc, err := crypto.Encrypt(ctx, *req.DateOfBirth)
		if err != nil {
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "encryption failed")
			return
		}
		updates["dateOfBirthEnc"] = enc
	}
	if req.NationalInsurance != nil {
		enc, err := crypto.Encrypt(ctx, *req.NationalInsurance)
		if err != nil {
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "encryption failed")
			return
		}
		updates["nationalInsuranceEnc"] = enc
	}
	if req.BankAccount != nil {
		enc, err := crypto.Encrypt(ctx, *req.BankAccount)
		if err != nil {
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "encryption failed")
			return
		}
		updates["bankAccountEnc"] = enc
	}
	if req.SortCode != nil {
		enc, err := crypto.Encrypt(ctx, *req.SortCode)
		if err != nil {
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "encryption failed")
			return
		}
		updates["sortCodeEnc"] = enc
	}
	if req.FullAddress != nil {
		enc, err := crypto.Encrypt(ctx, *req.FullAddress)
		if err != nil {
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "encryption failed")
			return
		}
		updates["fullAddressEnc"] = enc
	}
	if req.DBSCertificate != nil {
		enc, err := crypto.Encrypt(ctx, *req.DBSCertificate)
		if err != nil {
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "encryption failed")
			return
		}
		updates["dbsCertificateEnc"] = enc
	}

	ref := db.Collection("sensitive").Doc(uid)
	if _, err := ref.Set(ctx, updates, firestore.MergeAll); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"status": "updated", "updatedAt": now})
}

// getSensitiveProfile — GET /getSensitiveProfile?uid=...
// Readable by owner or authorized admin (finance / verifier / super_admin).
// Logs an audit entry when accessed by an admin.
func getSensitiveProfile(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	callerUID := auth.UID(ctx)
	targetUID := r.URL.Query().Get("uid")
	if targetUID == "" {
		targetUID = callerUID
	}

	isSelf := callerUID == targetUID
	isAdminCaller := auth.HasRole(ctx, auth.AdminRoleFinance, auth.AdminRoleVerifier, auth.AdminRoleSuperAdmin) || isAdmin(ctx)

	if !isSelf && !isAdminCaller {
		httpjson.WriteError(w, http.StatusForbidden, "FORBIDDEN", "Permission denied")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore unavailable")
		return
	}

	snap, err := db.Collection("sensitive").Doc(targetUID).Get(ctx)
	if status.Code(err) == codes.NotFound {
		httpjson.WriteJSON(w, http.StatusOK, map[string]string{})
		return
	}
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	var sp SensitiveProfile
	if err := snap.DataTo(&sp); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	// Decrypt sensitive fields
	dob, _ := crypto.Decrypt(ctx, sp.DateOfBirthEnc)
	ni, _ := crypto.Decrypt(ctx, sp.NationalInsuranceEnc)
	bank, _ := crypto.Decrypt(ctx, sp.BankAccountEnc)
	sort, _ := crypto.Decrypt(ctx, sp.SortCodeEnc)
	addr, _ := crypto.Decrypt(ctx, sp.FullAddressEnc)
	dbs, _ := crypto.Decrypt(ctx, sp.DBSCertificateEnc)

	// Mask for admin if read-only or not full finance
	if !isSelf {
		_ = audit.WriteAudit(ctx, db, audit.Entry{
			Action:    "readSensitiveProfile",
			TargetUID: targetUID,
			Fields:    []string{"dateOfBirth", "nationalInsurance", "bankAccount", "address", "dbsCertificate"},
		})
	}

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{
		"uid":               targetUID,
		"dateOfBirth":       dob,
		"nationalInsurance": ni,
		"bankAccount":       bank,
		"sortCode":          sort,
		"fullAddress":       addr,
		"dbsCertificate":    dbs,
		"updatedAt":         sp.UpdatedAt,
	})
}

var allowedVettingChecks = map[string]bool{
	"identity": true, "originalCertificate": true, "suitability": true,
	"workforce": true, "barredList": true, "updateService": true,
	"rightToWork": true, "qualification": true, "references": true,
	"safeguarding": true, "firstAid": true,
}

// requiredVettingChecks are the safeguarding checks that must be signed off
// before a practitioner can be approved. References, safeguarding training
// and first aid remain recorded but do not block approval; they are part of
// the wider recruitment file.
var requiredVettingChecks = []struct {
	name string
	item func(VettingChecklist) VettingCheckItem
}{
	{"identity", func(c VettingChecklist) VettingCheckItem { return c.Identity }},
	{"originalCertificate", func(c VettingChecklist) VettingCheckItem { return c.OriginalCertificate }},
	{"suitability", func(c VettingChecklist) VettingCheckItem { return c.Suitability }},
	{"workforce", func(c VettingChecklist) VettingCheckItem { return c.Workforce }},
	{"barredList", func(c VettingChecklist) VettingCheckItem { return c.BarredList }},
	{"updateService", func(c VettingChecklist) VettingCheckItem { return c.UpdateService }},
	{"rightToWork", func(c VettingChecklist) VettingCheckItem { return c.RightToWork }},
	{"qualification", func(c VettingChecklist) VettingCheckItem { return c.Qualification }},
}

func missingVettingChecks(c VettingChecklist) []string {
	var missing []string
	for _, check := range requiredVettingChecks {
		if check.item(c).Result != CheckPassed {
			missing = append(missing, check.name)
		}
	}
	return missing
}
