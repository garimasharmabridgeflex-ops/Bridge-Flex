package function

import (
	"net/http"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/GoogleCloudPlatform/functions-framework-go/functions"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"kvision.internal/shared/audit"
	"kvision.internal/shared/httpjson"
)

func init() {
	functions.HTTP("GetCompanyInfo", getCompanyInfo)
	functions.HTTP("GetCompanySettings", authed(getCompanySettings))
	functions.HTTP("UpdateCompanyInfo", authed(updateCompanyInfo))
}

const companyConfigDoc = "platformConfig/company"

type CompanyField struct {
	Value     string `firestore:"value" json:"value"`
	Published bool   `firestore:"published" json:"published"`
}

type CompanyConfig struct {
	CompanyName   CompanyField `firestore:"companyName" json:"companyName"`
	CompanyNumber CompanyField `firestore:"companyNumber" json:"companyNumber"`
	VATNumber     CompanyField `firestore:"vatNumber" json:"vatNumber"`
	Address       CompanyField `firestore:"address" json:"address"`
	Email         CompanyField `firestore:"email" json:"email"`
	Phone         CompanyField `firestore:"phone" json:"phone"`
	UpdatedAt     time.Time    `firestore:"updatedAt" json:"updatedAt"`
}

// getCompanyInfo — GET /getCompanyInfo. Unauthenticated / authenticated public read.
// Returns ONLY fields that have Published == true. Unchecked/unpublished fields are never revealed.
func getCompanyInfo(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore unavailable")
		return
	}

	snap, err := db.Doc(companyConfigDoc).Get(ctx)
	if status.Code(err) == codes.NotFound {
		httpjson.WriteJSON(w, http.StatusOK, map[string]any{"company": map[string]string{}})
		return
	}
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	var conf CompanyConfig
	if err := snap.DataTo(&conf); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	published := map[string]string{}
	if conf.CompanyName.Published && conf.CompanyName.Value != "" {
		published["companyName"] = conf.CompanyName.Value
	}
	if conf.CompanyNumber.Published && conf.CompanyNumber.Value != "" {
		published["companyNumber"] = conf.CompanyNumber.Value
	}
	if conf.VATNumber.Published && conf.VATNumber.Value != "" {
		published["vatNumber"] = conf.VATNumber.Value
	}
	if conf.Address.Published && conf.Address.Value != "" {
		published["address"] = conf.Address.Value
	}
	if conf.Email.Published && conf.Email.Value != "" {
		published["email"] = conf.Email.Value
	}
	if conf.Phone.Published && conf.Phone.Value != "" {
		published["phone"] = conf.Phone.Value
	}

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{
		"company":   published,
		"updatedAt": conf.UpdatedAt,
	})
}

// getCompanySettings returns every field, including unpublished values, to an
// authenticated admin. The public GetCompanyInfo endpoint intentionally omits
// unpublished fields and cannot be used to populate an editable admin form.
func adminCompanySettings(conf CompanyConfig) map[string]CompanyField {
	return map[string]CompanyField{
		"companyName":   conf.CompanyName,
		"companyNumber": conf.CompanyNumber,
		"vatNumber":     conf.VATNumber,
		"address":       conf.Address,
		"email":         conf.Email,
		"phone":         conf.Phone,
	}
}

func getCompanySettings(w http.ResponseWriter, r *http.Request) {
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

	var conf CompanyConfig
	snap, err := db.Doc(companyConfigDoc).Get(ctx)
	if err != nil && status.Code(err) != codes.NotFound {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}
	if err == nil {
		if err := snap.DataTo(&conf); err != nil {
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
	}
	httpjson.WriteJSON(w, http.StatusOK, map[string]any{
		"company":   adminCompanySettings(conf),
		"updatedAt": conf.UpdatedAt,
	})
}

type updateCompanyRequest struct {
	CompanyName   *CompanyField `json:"companyName,omitempty"`
	CompanyNumber *CompanyField `json:"companyNumber,omitempty"`
	VATNumber     *CompanyField `json:"vatNumber,omitempty"`
	Address       *CompanyField `json:"address,omitempty"`
	Email         *CompanyField `json:"email,omitempty"`
	Phone         *CompanyField `json:"phone,omitempty"`
}

// updateCompanyInfo — POST /updateCompanyInfo. Admin only (requires super_admin role).
// Updates platformConfig/company and logs an audit record.
func updateCompanyInfo(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !isAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "NOT_ADMIN", "Admin permissions required")
		return
	}

	var req updateCompanyRequest
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
		"updatedAt": now,
	}
	var changedFields []string

	if req.CompanyName != nil {
		updates["companyName"] = *req.CompanyName
		changedFields = append(changedFields, "companyName")
	}
	if req.CompanyNumber != nil {
		updates["companyNumber"] = *req.CompanyNumber
		changedFields = append(changedFields, "companyNumber")
	}
	if req.VATNumber != nil {
		updates["vatNumber"] = *req.VATNumber
		changedFields = append(changedFields, "vatNumber")
	}
	if req.Address != nil {
		updates["address"] = *req.Address
		changedFields = append(changedFields, "address")
	}
	if req.Email != nil {
		updates["email"] = *req.Email
		changedFields = append(changedFields, "email")
	}
	if req.Phone != nil {
		updates["phone"] = *req.Phone
		changedFields = append(changedFields, "phone")
	}

	ref := db.Doc(companyConfigDoc)
	if _, err := ref.Set(ctx, updates, firestore.MergeAll); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:    "updateCompanyInfo",
		TargetDoc: companyConfigDoc,
		Fields:    changedFields,
	})

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"status": "updated", "updatedAt": now})
}
