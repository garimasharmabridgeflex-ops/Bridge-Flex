package function

// Direct unit tests for the Pub/Sub-triggered handlers, following
// ARCHITECTURE.md v2 §7's approach: hand-construct the CloudEvent payload
// the real trigger would deliver, call the handler function directly,
// assert on the resulting Firestore state. There is no live local Eventarc
// dispatch for Go, so this is the only way these get exercised before a
// real deploy.
//
// Requires the Firestore emulator running and FIRESTORE_EMULATOR_HOST /
// GCLOUD_PROJECT set — see backend/README.md. No registered FCM tokens
// exist for the test uids used here, so notifyUser's push-send path runs
// its zero-tokens loop and returns without ever calling the Messaging API —
// these tests only exercise (and only need) the Firestore side.

import (
	"context"
	"encoding/json"
	"fmt"
	"testing"
	"time"

	"github.com/cloudevents/sdk-go/v2/event"
	"google.golang.org/api/iterator"
)

func pubsubEvent(t *testing.T, eventType string, payload any) event.Event {
	t.Helper()
	dataJSON, err := json.Marshal(payload)
	if err != nil {
		t.Fatalf("json.Marshal payload: %v", err)
	}
	msg := messagePublishedData{Message: pubSubMessage{Data: dataJSON}}
	e := event.New()
	e.SetType(eventType)
	e.SetSource("//pubsub.googleapis.com/projects/demo-bridgeflex/topics/" + eventType)
	if err := e.SetData("application/json", msg); err != nil {
		t.Fatalf("event.SetData: %v", err)
	}
	return e
}

func testUID(prefix string) string {
	return fmt.Sprintf("%s-%d", prefix, time.Now().UnixNano())
}

func notificationsForUID(t *testing.T, uid string) []map[string]any {
	t.Helper()
	ctx := context.Background()
	db, err := fsDB(ctx)
	if err != nil {
		t.Fatalf("fsDB: %v", err)
	}
	iter := db.Collection("notifications").Where("uid", "==", uid).Documents(ctx)
	defer iter.Stop()
	var out []map[string]any
	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			t.Fatalf("iterate notifications: %v", err)
		}
		out = append(out, doc.Data())
	}
	return out
}

func TestOnShiftBooked(t *testing.T) {
	ctx := context.Background()
	db, err := fsDB(ctx)
	if err != nil {
		t.Fatalf("fsDB: %v", err)
	}

	nurseryUID := testUID("trigger-test-nursery")
	staffUID := testUID("trigger-test-staff")
	shiftID := testUID("trigger-test-shift")

	e := pubsubEvent(t, "shift-booked", shiftBookedPayload{
		ShiftID: shiftID, NurseryID: nurseryUID, StaffID: staffUID,
	})
	if err := onShiftBooked(ctx, e); err != nil {
		t.Fatalf("onShiftBooked: %v", err)
	}

	iter := db.Collection("chatSessions").Where("shiftId", "==", shiftID).Limit(1).Documents(ctx)
	defer iter.Stop()
	doc, err := iter.Next()
	if err != nil {
		t.Fatalf("expected a chat session for shift %s, got error: %v", shiftID, err)
	}
	t.Cleanup(func() { _, _ = doc.Ref.Delete(ctx) })
	participants, _ := doc.Data()["participantIds"].([]any)
	if !containsUID(participants, nurseryUID) || !containsUID(participants, staffUID) {
		t.Errorf("participantIds = %v, want both %q and %q", participants, nurseryUID, staffUID)
	}

	for _, uid := range []string{nurseryUID, staffUID} {
		notifs := notificationsForUID(t, uid)
		if len(notifs) != 1 {
			t.Errorf("notifications for %s: got %d, want 1", uid, len(notifs))
			continue
		}
		if notifs[0]["type"] != "shift_booked" {
			t.Errorf("notification type for %s = %v, want shift_booked", uid, notifs[0]["type"])
		}
	}

	t.Cleanup(func() {
		for _, uid := range []string{nurseryUID, staffUID} {
			iter := db.Collection("notifications").Where("uid", "==", uid).Documents(ctx)
			for {
				d, err := iter.Next()
				if err == iterator.Done {
					break
				}
				if err == nil {
					_, _ = d.Ref.Delete(ctx)
				}
			}
			iter.Stop()
		}
	})
}

func TestOnRatingReceived(t *testing.T) {
	ctx := context.Background()
	db, err := fsDB(ctx)
	if err != nil {
		t.Fatalf("fsDB: %v", err)
	}
	rateeUID := testUID("trigger-test-ratee")

	e := pubsubEvent(t, "rating-received", ratingReceivedPayload{
		RatingID: testUID("rating"), RateeID: rateeUID, RaterID: testUID("rater"), ShiftID: testUID("shift"),
	})
	if err := onRatingReceived(ctx, e); err != nil {
		t.Fatalf("onRatingReceived: %v", err)
	}

	notifs := notificationsForUID(t, rateeUID)
	if len(notifs) != 1 {
		t.Fatalf("notifications for %s: got %d, want 1", rateeUID, len(notifs))
	}
	if notifs[0]["type"] != "rating_received" {
		t.Errorf("notification type = %v, want rating_received", notifs[0]["type"])
	}

	t.Cleanup(func() {
		iter := db.Collection("notifications").Where("uid", "==", rateeUID).Documents(ctx)
		defer iter.Stop()
		for {
			d, err := iter.Next()
			if err == iterator.Done {
				break
			}
			if err == nil {
				_, _ = d.Ref.Delete(ctx)
			}
		}
	})
}

func TestOnShiftMatched(t *testing.T) {
	ctx := context.Background()
	db, err := fsDB(ctx)
	if err != nil {
		t.Fatalf("fsDB: %v", err)
	}
	staffUID := testUID("trigger-test-matched-staff")

	e := pubsubEvent(t, "shift-matched", shiftMatchedPayload{
		ShiftID: testUID("shift"), NurseryID: testUID("nursery"), StaffID: staffUID,
	})
	if err := onShiftMatched(ctx, e); err != nil {
		t.Fatalf("onShiftMatched: %v", err)
	}

	notifs := notificationsForUID(t, staffUID)
	if len(notifs) != 1 {
		t.Fatalf("notifications for %s: got %d, want 1", staffUID, len(notifs))
	}
	if notifs[0]["type"] != "new_matching_shift" {
		t.Errorf("notification type = %v, want new_matching_shift", notifs[0]["type"])
	}

	t.Cleanup(func() {
		iter := db.Collection("notifications").Where("uid", "==", staffUID).Documents(ctx)
		defer iter.Stop()
		for {
			d, err := iter.Next()
			if err == iterator.Done {
				break
			}
			if err == nil {
				_, _ = d.Ref.Delete(ctx)
			}
		}
	})
}
