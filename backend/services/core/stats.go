package function

import (
	"context"
	"encoding/json"
	"log"
	"time"

	"google.golang.org/api/iterator"
)

// withComputedFields marshals base (a Profile or ProfilePublic) to a
// map and merges in the role-appropriate computed block — "stats" for
// nurseries, "ratingBreakdown" for staff — so getProfile/getPublicProfile
// can return both the stored document and this on-demand-derived data in
// one response without either struct needing to declare fields that don't
// correspond to anything actually stored in Firestore. Errors computing the
// derived block are logged and simply omitted rather than failing the whole
// profile fetch — a profile view degrading gracefully to "no stats" beats a
// 500 on what's still fundamentally a successful read.
func withComputedFields(ctx context.Context, uid string, role Role, base any) map[string]any {
	raw, err := json.Marshal(base)
	if err != nil {
		return map[string]any{}
	}
	var out map[string]any
	if err := json.Unmarshal(raw, &out); err != nil {
		return map[string]any{}
	}
	switch role {
	case RoleNursery:
		if stats, err := computeNurseryStats(ctx, uid); err != nil {
			log.Printf("computeNurseryStats(%s): %v", uid, err)
		} else {
			out["stats"] = stats
		}
	case RoleStaff:
		if breakdown, err := computeRatingBreakdown(ctx, uid); err != nil {
			log.Printf("computeRatingBreakdown(%s): %v", uid, err)
		} else {
			out["ratingBreakdown"] = breakdown
		}
	}
	return out
}

// NurseryStats is computed on-demand (not stored) whenever a nursery's
// profile is read — full app spec profile-fields request: "Statistics,
// completed shifts, repeat staff percentage, average response time,
// cancellation rate, no show rate". Computing live avoids maintaining
// incremental counters via triggers for what's still a small-collection
// MVP; if the shifts-per-nursery collection ever gets large enough for this
// full scan to matter, that's the point to switch to stored counters.
type NurseryStats struct {
	CompletedShifts            int64   `json:"completedShifts"`
	RepeatStaffPercentage      float64 `json:"repeatStaffPercentage"`
	AverageResponseTimeMinutes float64 `json:"averageResponseTimeMinutes"`
	CancellationRate           float64 `json:"cancellationRate"`
	NoShowRate                 float64 `json:"noShowRate"`
}

func computeNurseryStats(ctx context.Context, nurseryUID string) (*NurseryStats, error) {
	db, err := fsDB(ctx)
	if err != nil {
		return nil, err
	}

	iter := db.Collection("shifts").Where("nurseryId", "==", nurseryUID).Documents(ctx)
	defer iter.Stop()

	var totalShifts, completedShifts, cancelledShifts int64
	var responseTimeSum time.Duration
	var responseTimeCount int64
	staffShiftCounts := make(map[string]int64)
	var totalBookedSlots, totalNoShows int64
	now := time.Now()

	for {
		snap, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return nil, err
		}
		var s Shift
		if err := snap.DataTo(&s); err != nil {
			continue
		}
		totalShifts++

		if s.Status == ShiftCancelled {
			cancelledShifts++
		}

		bookedList := s.BookedStaffIDs
		if bookedList == nil && s.BookedStaffID != nil && *s.BookedStaffID != "" {
			bookedList = []string{*s.BookedStaffID}
		}

		isCompleted := s.Status != ShiftCancelled && now.After(s.EndTime) && len(bookedList) > 0
		if isCompleted {
			completedShifts++
			for _, staffID := range bookedList {
				staffShiftCounts[staffID]++
			}
			totalBookedSlots += int64(len(bookedList))
			totalNoShows += int64(len(s.NoShowStaffIDs))
		}

		if s.FirstAcceptedAt != nil {
			responseTimeSum += s.FirstAcceptedAt.Sub(s.CreatedAt)
			responseTimeCount++
		}
	}

	stats := &NurseryStats{CompletedShifts: completedShifts}
	if totalShifts > 0 {
		stats.CancellationRate = float64(cancelledShifts) / float64(totalShifts)
	}
	if responseTimeCount > 0 {
		stats.AverageResponseTimeMinutes = responseTimeSum.Minutes() / float64(responseTimeCount)
	}
	if totalBookedSlots > 0 {
		stats.NoShowRate = float64(totalNoShows) / float64(totalBookedSlots)
	}
	if len(staffShiftCounts) > 0 {
		var repeatStaff int64
		for _, count := range staffShiftCounts {
			if count > 1 {
				repeatStaff++
			}
		}
		stats.RepeatStaffPercentage = float64(repeatStaff) / float64(len(staffShiftCounts)) * 100
	}
	return stats, nil
}

// RatingBreakdown is computed on-demand (not stored) from ratings/{id}.
// categoryScores — full app spec profile-fields request: "ratings,
// communications, punctuality, professionalism, reliability, child
// engagement". Category is optional per rating (older ratings predate it),
// so Count reflects only ratings that actually carried category scores.
type RatingBreakdown struct {
	Communication   float64 `json:"communication"`
	Punctuality     float64 `json:"punctuality"`
	Professionalism float64 `json:"professionalism"`
	Reliability     float64 `json:"reliability"`
	ChildEngagement float64 `json:"childEngagement"`
	Count           int64   `json:"count"`
}

func computeRatingBreakdown(ctx context.Context, rateeUID string) (*RatingBreakdown, error) {
	db, err := fsDB(ctx)
	if err != nil {
		return nil, err
	}

	iter := db.Collection("ratings").Where("rateeId", "==", rateeUID).Documents(ctx)
	defer iter.Stop()

	sums := map[string]float64{}
	counts := map[string]int64{}
	var ratedCount int64

	for {
		snap, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return nil, err
		}
		var rd RatingDoc
		if err := snap.DataTo(&rd); err != nil {
			continue
		}
		if len(rd.CategoryScores) == 0 {
			continue
		}
		ratedCount++
		for k, v := range rd.CategoryScores {
			sums[k] += float64(v)
			counts[k]++
		}
	}

	avg := func(key string) float64 {
		if counts[key] == 0 {
			return 0
		}
		return sums[key] / float64(counts[key])
	}
	return &RatingBreakdown{
		Communication:   avg("communication"),
		Punctuality:     avg("punctuality"),
		Professionalism: avg("professionalism"),
		Reliability:     avg("reliability"),
		ChildEngagement: avg("childEngagement"),
		Count:           ratedCount,
	}, nil
}
