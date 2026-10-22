package function

import (
	"context"
	"net/http"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/GoogleCloudPlatform/functions-framework-go/functions"
	"google.golang.org/api/iterator"
	"kvision.internal/shared/audit"
	"kvision.internal/shared/auth"
	"kvision.internal/shared/httpjson"
)

func init() {
	functions.HTTP("GetActiveRateCard", authed(getActiveRateCardHandler))
	functions.HTTP("ListRateCards", authed(listRateCardsHandler))
	functions.HTTP("UpsertRateCard", authed(upsertRateCardHandler))
}

// DefaultRateCard provides safe fallback pricing in pence (Decisions 2 & 3).
func DefaultRateCard() RateCard {
	return RateCard{
		ID:        "default-v1",
		Version:   1,
		Active:    true,
		CreatedAt: time.Date(2026, 10, 1, 0, 0, 0, 0, time.UTC),
		CreatedBy: "system",
		Rates: map[string]QualificationRates{
			string(QualNone): {
				PractitionerPayPencePerHour: 1250, // £12.50
				NurseryChargePencePerHour:   1600, // £16.00
			},
			string(QualLevel2): {
				PractitionerPayPencePerHour: 1350, // £13.50
				NurseryChargePencePerHour:   1750, // £17.50
			},
			string(QualLevel3): {
				PractitionerPayPencePerHour: 1500, // £15.00
				NurseryChargePencePerHour:   1950, // £19.50
			},
			string(QualLevel4Plus): {
				PractitionerPayPencePerHour: 1700, // £17.00
				NurseryChargePencePerHour:   2200, // £22.00
			},
		},
	}
}

// FetchActiveRateCard retrieves the active card from Firestore or returns default.
func FetchActiveRateCard(ctx context.Context, db *firestore.Client) RateCard {
	if db == nil {
		return DefaultRateCard()
	}
	iter := db.Collection("rateCards").Where("active", "==", true).Limit(1).Documents(ctx)
	defer iter.Stop()

	doc, err := iter.Next()
	if err == nil {
		var card RateCard
		if doc.DataTo(&card) == nil {
			card.ID = doc.Ref.ID
			return card
		}
	}
	return DefaultRateCard()
}

// ResolveShiftFinancials computes financial projections in integer pence (R12).
func ResolveShiftFinancials(
	ctx context.Context,
	db *firestore.Client,
	qual QualificationLevel,
	start, end time.Time,
	breakMinutes int64,
) (*ShiftFinancials, float64) {
	card := FetchActiveRateCard(ctx, db)

	qualKey := string(qual)
	if qualKey == "" {
		qualKey = string(QualNone)
	}

	rates, ok := card.Rates[qualKey]
	if !ok {
		rates = card.Rates[string(QualNone)]
	}

	durationMinutes := int64(end.Sub(start).Minutes())
	if durationMinutes < 0 {
		durationMinutes = 0
	}

	if breakMinutes < 0 {
		breakMinutes = 0
	}
	billableMinutes := durationMinutes - breakMinutes
	if billableMinutes < 0 {
		billableMinutes = 0
	}

	grossPayPence := (billableMinutes * rates.PractitionerPayPencePerHour) / 60
	nurseryChargePence := (billableMinutes * rates.NurseryChargePencePerHour) / 60
	platformFeePence := nurseryChargePence - grossPayPence
	if platformFeePence < 0 {
		platformFeePence = 0
	}

	fin := &ShiftFinancials{
		RateCardID:                  card.ID,
		RateCardVersion:             card.Version,
		PractitionerPayPencePerHour: rates.PractitionerPayPencePerHour,
		NurseryChargePencePerHour:   rates.NurseryChargePencePerHour,
		DurationMinutes:             durationMinutes,
		UnpaidBreakMinutes:          breakMinutes,
		BillableMinutes:             billableMinutes,
		EstimatedGrossPayPence:      grossPayPence,
		EstimatedNurseryChargePence: nurseryChargePence,
		PlatformFeePence:            platformFeePence,
	}

	// Legacy payRate in float pounds (£)
	legacyPayRate := float64(rates.PractitionerPayPencePerHour) / 100.0

	return fin, legacyPayRate
}

func getActiveRateCardHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore unavailable")
		return
	}

	card := FetchActiveRateCard(ctx, db)
	httpjson.WriteJSON(w, http.StatusOK, card)
}

func listRateCardsHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	isAdminCaller := auth.HasRole(ctx, auth.AdminRoleFinance, auth.AdminRoleSuperAdmin) || isAdmin(ctx)
	if !isAdminCaller {
		httpjson.WriteError(w, http.StatusForbidden, "FORBIDDEN", "Admin permission required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore unavailable")
		return
	}

	iter := db.Collection("rateCards").OrderBy("version", firestore.Desc).Documents(ctx)
	defer iter.Stop()

	var cards []RateCard
	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		var c RateCard
		if err := doc.DataTo(&c); err == nil {
			c.ID = doc.Ref.ID
			cards = append(cards, c)
		}
	}

	if len(cards) == 0 {
		cards = append(cards, DefaultRateCard())
	}

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"rateCards": cards})
}

type upsertRateCardRequest struct {
	Rates map[string]QualificationRates `json:"rates"`
}

func upsertRateCardHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	callerUID := auth.UID(ctx)

	isAdminCaller := auth.HasRole(ctx, auth.AdminRoleFinance, auth.AdminRoleSuperAdmin) || isAdmin(ctx)
	if !isAdminCaller {
		httpjson.WriteError(w, http.StatusForbidden, "FORBIDDEN", "Admin permission required")
		return
	}

	var req upsertRateCardRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	if len(req.Rates) == 0 {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "rates mapping is required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore unavailable")
		return
	}

	// Determine next version
	latestIter := db.Collection("rateCards").OrderBy("version", firestore.Desc).Limit(1).Documents(ctx)
	defer latestIter.Stop()

	nextVersion := 1
	if doc, err := latestIter.Next(); err == nil {
		var latest RateCard
		if doc.DataTo(&latest) == nil && latest.Version >= 1 {
			nextVersion = latest.Version + 1
		}
	}

	now := time.Now()
	newCard := RateCard{
		Version:   nextVersion,
		Active:    true,
		CreatedAt: now,
		CreatedBy: callerUID,
		Rates:     req.Rates,
	}

	// Deactivate any currently active cards
	activeIter := db.Collection("rateCards").Where("active", "==", true).Documents(ctx)
	defer activeIter.Stop()
	for {
		doc, err := activeIter.Next()
		if err == iterator.Done {
			break
		}
		if err == nil {
			_, _ = doc.Ref.Update(ctx, []firestore.Update{{Path: "active", Value: false}})
		}
	}

	ref, _, err := db.Collection("rateCards").Add(ctx, newCard)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:   "upsertRateCard",
		ActorUID: callerUID,
		Metadata: map[string]any{"rateCardId": ref.ID, "version": nextVersion},
	})

	newCard.ID = ref.ID
	httpjson.WriteJSON(w, http.StatusCreated, newCard)
}
