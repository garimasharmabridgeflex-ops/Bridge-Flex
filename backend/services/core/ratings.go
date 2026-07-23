package function

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/GoogleCloudPlatform/functions-framework-go/functions"
	"github.com/cloudevents/sdk-go/v2/event"
	"github.com/googleapis/google-cloudevents-go/cloud/firestoredata"
	"google.golang.org/api/iterator"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/proto"

	"kvision.internal/shared/auth"
	"kvision.internal/shared/httpjson"
)

func init() {
	functions.HTTP("CreateRating", authed(createRating))
	functions.HTTP("ListRatings", authed(listRatings))
	functions.CloudEvent("RecomputeRating", recomputeRating)
}

var (
	errRatingSelf     = errors.New("cannot rate yourself")
	errRatingNotParty = errors.New("not a party to this shift")
	errRatingBadScore = errors.New("score must be between 1 and 5")
)

type createRatingRequest struct {
	ShiftID string `json:"shiftId"`
	RateeID string `json:"rateeId"`
	Score   int64  `json:"score"`
	Comment string `json:"comment,omitempty"`
	// CategoryScores is the optional per-category breakdown (communication,
	// punctuality, professionalism, reliability, childEngagement — full
	// app spec profile ratings breakdown), each 1-5. Averaged on-demand by
	// computeStaffRatingBreakdown (stats.go) rather than aggregated
	// incrementally like the overall Score, to keep recomputeRating's
	// transaction from having to know every category key up front.
	CategoryScores map[string]int64 `json:"categoryScores,omitempty"`
}

// createRating — POST /createRating. Mirrors the create-only, immutable
// Security Rule from §3: the rater/ratee pair must actually be the
// nursery/booked-staff pair on the referenced shift.
func createRating(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	uid := auth.UID(ctx)

	var req createRatingRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	if req.ShiftID == "" || req.RateeID == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "shiftId and rateeId are required")
		return
	}
	if req.Score < 1 || req.Score > 5 {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", errRatingBadScore.Error())
		return
	}
	if req.RateeID == uid {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", errRatingSelf.Error())
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	shiftSnap, err := db.Collection("shifts").Doc(req.ShiftID).Get(ctx)
	if status.Code(err) == codes.NotFound {
		httpjson.WriteError(w, http.StatusNotFound, "SHIFT_NOT_FOUND", "Shift not found")
		return
	}
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}
	var shift Shift
	if err := shiftSnap.DataTo(&shift); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	// Membership must check the full bookedStaffIds list — on a
	// multi-capacity shift, whoever the nursery hired includes everyone in
	// that array, not just BookedStaffID ("most recent acceptor"); same bug
	// class as the one fixed in cancelShift/acceptShift.
	bookedIDs := shift.BookedStaffIDs
	if len(bookedIDs) == 0 && shift.BookedStaffID != nil {
		bookedIDs = []string{*shift.BookedStaffID}
	}
	isBookedStaffID := func(id string) bool {
		for _, b := range bookedIDs {
			if b == id {
				return true
			}
		}
		return false
	}
	isValidPair := (shift.NurseryID == uid && isBookedStaffID(req.RateeID)) ||
		(isBookedStaffID(uid) && shift.NurseryID == req.RateeID)
	if !isValidPair {
		httpjson.WriteError(w, http.StatusForbidden, "NOT_SHIFT_PARTY", errRatingNotParty.Error())
		return
	}

	rating := RatingDoc{
		ShiftID:        req.ShiftID,
		RaterID:        uid,
		RateeID:        req.RateeID,
		Score:          req.Score,
		Comment:        req.Comment,
		CategoryScores: req.CategoryScores,
		CreatedAt:      time.Now(),
	}
	ref, _, err := db.Collection("ratings").Add(ctx, rating)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}
	httpjson.WriteJSON(w, http.StatusCreated, map[string]string{"ratingId": ref.ID})
}

type ratingReceivedMessage struct {
	RatingID string `json:"ratingId"`
	RateeID  string `json:"rateeId"`
	RaterID  string `json:"raterId"`
	ShiftID  string `json:"shiftId"`
}

// recomputeRating is bound at deploy time to a Firestore-create Eventarc
// trigger filtered to ratings/{ratingId} (§1a table). Runs inside a
// transaction on profiles/{rateeId} because two shifts completing
// near-simultaneously could race on the same ratee's aggregate (§2). Writing
// to profiles/{rateeId}.rating cascades into profilesPublic automatically via
// syncProfilePublic — no special-casing needed here for the public mirror.
func recomputeRating(ctx context.Context, e event.Event) error {
	var data firestoredata.DocumentEventData
	if err := proto.Unmarshal(e.Data(), &data); err != nil {
		return fmt.Errorf("proto.Unmarshal firestore event: %w", err)
	}
	doc := data.GetValue()
	if doc == nil {
		return nil
	}
	ratingID, err := lastPathSegment(doc.GetName())
	if err != nil {
		return err
	}
	fields := doc.GetFields()
	rateeID := fieldString(fields, "rateeId")
	raterID := fieldString(fields, "raterId")
	shiftID := fieldString(fields, "shiftId")
	score := fieldInt(fields, "score")
	if rateeID == "" {
		return fmt.Errorf("rating %s missing rateeId", ratingID)
	}

	db, err := fsDB(ctx)
	if err != nil {
		return err
	}
	profileRef := db.Collection("profiles").Doc(rateeID)

	err = db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		snap, err := tx.Get(profileRef)
		if err != nil {
			return err
		}
		var p Profile
		if err := snap.DataTo(&p); err != nil {
			return err
		}
		newCount := p.Rating.Count + 1
		newAverage := (p.Rating.Average*float64(p.Rating.Count) + float64(score)) / float64(newCount)
		return tx.Update(profileRef, []firestore.Update{
			{Path: "rating", Value: Rating{Average: newAverage, Count: newCount}},
		})
	})
	if err != nil {
		return fmt.Errorf("recompute rating for %s: %w", rateeID, err)
	}

	return publish(ctx, topicRatingReceived, ratingReceivedMessage{
		RatingID: ratingID,
		RateeID:  rateeID,
		RaterID:  raterID,
		ShiftID:  shiftID,
	})
}

// listRatings — GET /listRatings?uid=X. Every individual review left for
// uid, newest first — the reviews list both reference designs show on a
// profile, which the aggregate rating/ratingBreakdown alone can't back.
// Reviewer names aren't embedded server-side; the client resolves each
// raterId against profilesPublic the same way chat_list_screen already
// resolves peer names, so this stays a plain read with no N extra profile
// lookups on the server for every request.
func listRatings(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	uid := r.URL.Query().Get("uid")
	if uid == "" {
		uid = auth.UID(ctx)
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	iter := db.Collection("ratings").Where("rateeId", "==", uid).
		OrderBy("createdAt", firestore.Desc).Limit(50).Documents(ctx)
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
		var rating RatingDoc
		if err := snap.DataTo(&rating); err != nil {
			continue
		}
		out = append(out, map[string]any{
			"ratingId":       snap.Ref.ID,
			"raterId":        rating.RaterID,
			"score":          rating.Score,
			"comment":        rating.Comment,
			"createdAt":      rating.CreatedAt,
			"categoryScores": rating.CategoryScores,
		})
	}
	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"ratings": out})
}
