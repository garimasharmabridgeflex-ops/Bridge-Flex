package function

import (
	"context"
	"errors"
	"net/http"
	"regexp"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/GoogleCloudPlatform/functions-framework-go/functions"
	"google.golang.org/api/iterator"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"kvision.internal/shared/audit"
	"kvision.internal/shared/auth"
	"kvision.internal/shared/httpjson"
)

var (
	errDiscountCodeNotFound  = errors.New("DISCOUNT_CODE_NOT_FOUND")
	errDiscountCodeInactive  = errors.New("DISCOUNT_CODE_INACTIVE")
	errDiscountCodeExpired   = errors.New("DISCOUNT_CODE_EXPIRED")
	errDiscountCodeExhausted = errors.New("DISCOUNT_CODE_EXHAUSTED")
)

func init() {
	functions.HTTP("CreateDiscountCode", authed(createDiscountCode))
	functions.HTTP("ListDiscountCodes", authed(listDiscountCodes))
	functions.HTTP("SetDiscountCodeActive", authed(setDiscountCodeActive))
}

// discountCodes/{code} — admin-authored promotional codes (owner brief §10
// "create discount codes", implementation plan Phase 9 item 5). Codes do not
// move money: they are validated when an admin records a discount ledger
// entry, which is what keeps the "no money movement until Stripe" rule true.
type DiscountCode struct {
	Code           string     `firestore:"code" json:"code"`
	PercentOff     int        `firestore:"percentOff" json:"percentOff"`         // 1-100, exclusive with AmountOffPence
	AmountOffPence int64      `firestore:"amountOffPence" json:"amountOffPence"` // exclusive with PercentOff
	MaxRedemptions int        `firestore:"maxRedemptions" json:"maxRedemptions"` // 0 = unlimited
	RedeemedCount  int        `firestore:"redeemedCount" json:"redeemedCount"`
	ExpiresAt      *time.Time `firestore:"expiresAt,omitempty" json:"expiresAt,omitempty"`
	Active         bool       `firestore:"active" json:"active"`
	Note           string     `firestore:"note,omitempty" json:"note,omitempty"`
	CreatedBy      string     `firestore:"createdBy" json:"createdBy"`
	CreatedAt      time.Time  `firestore:"createdAt" json:"createdAt"`
	LastRedeemedAt *time.Time `firestore:"lastRedeemedAt,omitempty" json:"lastRedeemedAt,omitempty"`
}

var discountCodePattern = regexp.MustCompile(`^[A-Z0-9][A-Z0-9_-]{1,31}$`)

type createDiscountCodeRequest struct {
	Code           string     `json:"code"`
	PercentOff     int        `json:"percentOff,omitempty"`
	AmountOffPence int64      `json:"amountOffPence,omitempty"`
	MaxRedemptions int        `json:"maxRedemptions,omitempty"`
	ExpiresAt      *time.Time `json:"expiresAt,omitempty"`
	Note           string     `json:"note,omitempty"`
}

// createDiscountCode — POST /createDiscountCode. Admin only.
func createDiscountCode(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !isAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "NOT_ADMIN", "Admin permissions required")
		return
	}

	var req createDiscountCodeRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}

	code := strings.ToUpper(strings.TrimSpace(req.Code))
	if !discountCodePattern.MatchString(code) {
		httpjson.WriteError(w, http.StatusBadRequest, "INVALID_CODE",
			"Code must be 2-32 characters of A-Z, 0-9, hyphen or underscore")
		return
	}
	if (req.PercentOff > 0) == (req.AmountOffPence > 0) {
		httpjson.WriteError(w, http.StatusBadRequest, "INVALID_DISCOUNT",
			"Set exactly one of percentOff or amountOffPence")
		return
	}
	if req.PercentOff < 0 || req.PercentOff > 100 {
		httpjson.WriteError(w, http.StatusBadRequest, "INVALID_DISCOUNT", "percentOff must be between 1 and 100")
		return
	}
	if req.AmountOffPence < 0 {
		httpjson.WriteError(w, http.StatusBadRequest, "INVALID_DISCOUNT", "amountOffPence must not be negative")
		return
	}
	if req.ExpiresAt != nil && !req.ExpiresAt.After(time.Now()) {
		httpjson.WriteError(w, http.StatusBadRequest, "INVALID_EXPIRY", "expiresAt must be in the future")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore unavailable")
		return
	}

	entry := DiscountCode{
		Code:           code,
		PercentOff:     req.PercentOff,
		AmountOffPence: req.AmountOffPence,
		MaxRedemptions: req.MaxRedemptions,
		ExpiresAt:      req.ExpiresAt,
		Active:         true,
		Note:           strings.TrimSpace(req.Note),
		CreatedBy:      auth.UID(ctx),
		CreatedAt:      time.Now().UTC(),
	}

	// Create (not Set): an existing code must fail loudly rather than be
	// silently overwritten with different terms.
	if _, err := db.Collection("discountCodes").Doc(code).Create(ctx, entry); err != nil {
		if status.Code(err) == codes.AlreadyExists {
			httpjson.WriteError(w, http.StatusConflict, "CODE_EXISTS", "That discount code already exists")
			return
		}
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:    "discount.create",
		ActorUID:  auth.UID(ctx),
		TargetDoc: "discountCodes/" + code,
		Metadata: map[string]any{
			"percentOff":     entry.PercentOff,
			"amountOffPence": entry.AmountOffPence,
			"maxRedemptions": entry.MaxRedemptions,
		},
	})

	httpjson.WriteJSON(w, http.StatusCreated, entry)
}

// listDiscountCodes — GET /listDiscountCodes. Admin only.
func listDiscountCodes(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !isAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "NOT_ADMIN", "Admin permissions required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore unavailable")
		return
	}

	iter := db.Collection("discountCodes").OrderBy("createdAt", firestore.Desc).Documents(ctx)
	defer iter.Stop()

	list := make([]DiscountCode, 0)
	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		var code DiscountCode
		_ = doc.DataTo(&code)
		list = append(list, code)
	}
	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"codes": list})
}

type setDiscountCodeActiveRequest struct {
	Code   string `json:"code"`
	Active bool   `json:"active"`
}

// setDiscountCodeActive — POST /setDiscountCodeActive. Admin only. Lets the
// owner switch a promotion off (or back on) without deleting its history.
func setDiscountCodeActive(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !isAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "NOT_ADMIN", "Admin permissions required")
		return
	}

	var req setDiscountCodeActiveRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	code := strings.ToUpper(strings.TrimSpace(req.Code))
	if code == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "code is required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore unavailable")
		return
	}

	ref := db.Collection("discountCodes").Doc(code)
	if _, err := ref.Get(ctx); status.Code(err) == codes.NotFound {
		httpjson.WriteError(w, http.StatusNotFound, "NOT_FOUND", "Discount code not found")
		return
	} else if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	if _, err := ref.Update(ctx, []firestore.Update{{Path: "active", Value: req.Active}}); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:    "discount.set_active",
		ActorUID:  auth.UID(ctx),
		TargetDoc: "discountCodes/" + code,
		Metadata:  map[string]any{"active": req.Active},
	})

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"code": code, "active": req.Active})
}

// redeemDiscount validates a code inside the caller's transaction and counts
// the redemption. Returns the resolved code so an admin can log an accurate
// discount amount. Not finding a code is an error, never a silent pass: a
// typo'd promotion should not quietly grant a discount it never represented,
// nor let an admin record a "discount" with no backing code.
func redeemDiscount(ctx context.Context, tx *firestore.Transaction, db *firestore.Client, rawCode string) (DiscountCode, error) {
	code := strings.ToUpper(strings.TrimSpace(rawCode))
	ref := db.Collection("discountCodes").Doc(code)

	snap, err := tx.Get(ref)
	if status.Code(err) == codes.NotFound {
		return DiscountCode{}, errDiscountCodeNotFound
	}
	if err != nil {
		return DiscountCode{}, err
	}

	var dc DiscountCode
	if err := snap.DataTo(&dc); err != nil {
		return DiscountCode{}, err
	}
	if !dc.Active {
		return DiscountCode{}, errDiscountCodeInactive
	}
	if dc.ExpiresAt != nil && dc.ExpiresAt.Before(time.Now()) {
		return DiscountCode{}, errDiscountCodeExpired
	}
	if dc.MaxRedemptions > 0 && dc.RedeemedCount >= dc.MaxRedemptions {
		return DiscountCode{}, errDiscountCodeExhausted
	}

	now := time.Now().UTC()
	dc.RedeemedCount++
	dc.LastRedeemedAt = &now
	if err := tx.Update(ref, []firestore.Update{
		{Path: "redeemedCount", Value: dc.RedeemedCount},
		{Path: "lastRedeemedAt", Value: now},
	}); err != nil {
		return DiscountCode{}, err
	}
	return dc, nil
}
