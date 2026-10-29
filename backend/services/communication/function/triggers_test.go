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
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
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
	e.SetSource("//pubsub.googleapis.com/projects/demo-kvision.internal/topics/" + eventType)
	if err := e.SetData("application/json", msg); err != nil {
		t.Fatalf("event.SetData: %v", err)
	}
	return e
}

func testUID(prefix string) string {
	return fmt.Sprintf("%s-%d", prefix, time.Now().UnixNano())
}

// deleteSession removes a chat session and its messages — Firestore does not
// cascade deletes into subcollections.
func deleteSession(t *testing.T, sessionID string) {
	t.Helper()
	ctx := context.Background()
	db, err := fsDB(ctx)
	if err != nil {
		t.Fatalf("fsDB: %v", err)
	}
	session := db.Collection("chatSessions").Doc(sessionID)
	iter := session.Collection("messages").Documents(ctx)
	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			iter.Stop()
			return
		}
		_, _ = doc.Ref.Delete(ctx)
	}
	iter.Stop()
	_, _ = session.Delete(ctx)
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

	sessionID := chatSessionID(nurseryUID, staffUID)
	doc, err := db.Collection("chatSessions").Doc(sessionID).Get(ctx)
	if err != nil {
		t.Fatalf("expected chat session %s for shift %s, got error: %v", sessionID, shiftID, err)
	}
	t.Cleanup(func() { deleteSession(t, sessionID) })
	if got := doc.Data()["lastShiftId"]; got != shiftID {
		t.Errorf("lastShiftId = %v, want %q", got, shiftID)
	}
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

// TestOnShiftCancelled covers both branches of the cancellation state
// machine (full app spec §3): staff dropping their acceptance notifies the
// nursery; the nursery pulling a booked shift notifies the staff member.
func TestOnShiftCancelled(t *testing.T) {
	ctx := context.Background()
	db, err := fsDB(ctx)
	if err != nil {
		t.Fatalf("fsDB: %v", err)
	}
	cleanupNotifs := func(uid string) {
		t.Cleanup(func() {
			iter := db.Collection("notifications").Where("uid", "==", uid).Documents(ctx)
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

	t.Run("staff cancelling notifies the nursery", func(t *testing.T) {
		nurseryUID := testUID("trigger-test-cancel-nursery")
		staffUID := testUID("trigger-test-cancel-staff")
		cleanupNotifs(nurseryUID)

		e := pubsubEvent(t, "shift-cancelled", shiftCancelledPayload{
			ShiftID: testUID("shift"), NurseryID: nurseryUID, StaffIDs: []string{staffUID},
			CancelledBy: "staff", NewStatus: "open",
		})
		if err := onShiftCancelled(ctx, e); err != nil {
			t.Fatalf("onShiftCancelled: %v", err)
		}

		notifs := notificationsForUID(t, nurseryUID)
		if len(notifs) != 1 {
			t.Fatalf("notifications for nursery %s: got %d, want 1", nurseryUID, len(notifs))
		}
		if notifs[0]["type"] != "shift_cancelled" {
			t.Errorf("notification type = %v, want shift_cancelled", notifs[0]["type"])
		}
	})

	t.Run("nursery cancelling a booked shift notifies the staff member", func(t *testing.T) {
		nurseryUID := testUID("trigger-test-cancel-nursery2")
		staffUID := testUID("trigger-test-cancel-staff2")
		cleanupNotifs(staffUID)

		e := pubsubEvent(t, "shift-cancelled", shiftCancelledPayload{
			ShiftID: testUID("shift"), NurseryID: nurseryUID, StaffIDs: []string{staffUID},
			CancelledBy: "nursery", NewStatus: "cancelled",
		})
		if err := onShiftCancelled(ctx, e); err != nil {
			t.Fatalf("onShiftCancelled: %v", err)
		}

		notifs := notificationsForUID(t, staffUID)
		if len(notifs) != 1 {
			t.Fatalf("notifications for staff %s: got %d, want 1", staffUID, len(notifs))
		}
		if notifs[0]["type"] != "shift_cancelled" {
			t.Errorf("notification type = %v, want shift_cancelled", notifs[0]["type"])
		}
	})
}

// TestOnShiftBookedReusesPairConversation is the pair-scoped chat rule: a
// second booking between the same nursery and practitioner must land in the
// conversation already there, with its history intact, rather than opening a
// fresh thread per shift.
func TestOnShiftBookedReusesPairConversation(t *testing.T) {
	ctx := context.Background()
	db, err := fsDB(ctx)
	if err != nil {
		t.Fatalf("fsDB: %v", err)
	}

	nurseryUID := testUID("pair-test-nursery")
	staffUID := testUID("pair-test-staff")
	sessionID := chatSessionID(nurseryUID, staffUID)
	t.Cleanup(func() { deleteSession(t, sessionID) })
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

	firstShift := testUID("pair-test-shift-a")
	secondShift := testUID("pair-test-shift-b")

	for _, shiftID := range []string{firstShift, secondShift} {
		e := pubsubEvent(t, "shift-booked", shiftBookedPayload{
			ShiftID: shiftID, NurseryID: nurseryUID, StaffID: staffUID,
		})
		if err := onShiftBooked(ctx, e); err != nil {
			t.Fatalf("onShiftBooked(%s): %v", shiftID, err)
		}
	}

	// A message written after the first booking survives the second one.
	if _, _, err := db.Collection("chatSessions").Doc(sessionID).Collection("messages").
		Add(ctx, map[string]any{"senderId": staffUID, "text": "hello", "createdAt": time.Now()}); err != nil {
		t.Fatalf("seed message: %v", err)
	}

	e := pubsubEvent(t, "shift-booked", shiftBookedPayload{
		ShiftID: secondShift, NurseryID: nurseryUID, StaffID: staffUID,
	})
	if err := onShiftBooked(ctx, e); err != nil {
		t.Fatalf("onShiftBooked(third): %v", err)
	}

	iter := db.Collection("chatSessions").Where("participantIds", "array-contains", nurseryUID).Documents(ctx)
	defer iter.Stop()
	var matching int
	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			t.Fatalf("iterate chat sessions: %v", err)
		}
		participants, _ := doc.Data()["participantIds"].([]any)
		if containsUID(participants, staffUID) {
			matching++
		}
	}
	if matching != 1 {
		t.Errorf("chat sessions for pair = %d, want exactly 1", matching)
	}

	snap, err := db.Collection("chatSessions").Doc(sessionID).Get(ctx)
	if err != nil {
		t.Fatalf("get canonical session: %v", err)
	}
	if got := snap.Data()["lastShiftId"]; got != secondShift {
		t.Errorf("lastShiftId = %v, want %q", got, secondShift)
	}

	msgIter := db.Collection("chatSessions").Doc(sessionID).Collection("messages").Documents(ctx)
	defer msgIter.Stop()
	var messages int
	for {
		_, err := msgIter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			t.Fatalf("iterate messages: %v", err)
		}
		messages++
	}
	if messages != 1 {
		t.Errorf("messages in conversation = %d, want 1", messages)
	}
}

// TestOnShiftBookedMergesLegacySessions covers existing installs: threads
// created before the pair-scoped change are keyed by shiftId with a random
// document ID. Booking again must fold them into the pair's conversation
// instead of leaving two threads against the same person.
func TestOnShiftBookedMergesLegacySessions(t *testing.T) {
	ctx := context.Background()
	db, err := fsDB(ctx)
	if err != nil {
		t.Fatalf("fsDB: %v", err)
	}

	nurseryUID := testUID("merge-test-nursery")
	staffUID := testUID("merge-test-staff")
	sessionID := chatSessionID(nurseryUID, staffUID)
	t.Cleanup(func() { deleteSession(t, sessionID) })
	t.Cleanup(func() {
		iter := db.Collection("notifications").Where("uid", "==", nurseryUID).Documents(ctx)
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
	})

	legacyRef, _, err := db.Collection("chatSessions").Add(ctx, map[string]any{
		"shiftId":        testUID("legacy-shift"),
		"participantIds": []string{nurseryUID, staffUID},
		"createdAt":      time.Now().Add(-time.Hour),
		"lastMessageAt":  time.Now().Add(-time.Hour),
	})
	if err != nil {
		t.Fatalf("seed legacy session: %v", err)
	}
	legacyID := legacyRef.ID
	t.Cleanup(func() { deleteSession(t, legacyID) })

	if _, _, err := legacyRef.Collection("messages").Add(ctx, map[string]any{
		"senderId": nurseryUID, "text": "from before the change", "createdAt": time.Now().Add(-time.Hour),
	}); err != nil {
		t.Fatalf("seed legacy message: %v", err)
	}

	newShift := testUID("merge-test-shift")
	e := pubsubEvent(t, "shift-booked", shiftBookedPayload{
		ShiftID: newShift, NurseryID: nurseryUID, StaffID: staffUID,
	})
	if err := onShiftBooked(ctx, e); err != nil {
		t.Fatalf("onShiftBooked: %v", err)
	}

	if _, err := db.Collection("chatSessions").Doc(legacyID).Get(ctx); status.Code(err) != codes.NotFound {
		t.Errorf("legacy session %s should be gone, got err = %v", legacyID, err)
	}

	msgIter := db.Collection("chatSessions").Doc(sessionID).Collection("messages").Documents(ctx)
	defer msgIter.Stop()
	var texts []string
	for {
		doc, err := msgIter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			t.Fatalf("iterate messages: %v", err)
		}
		if text, ok := doc.Data()["text"].(string); ok {
			texts = append(texts, text)
		}
	}
	if len(texts) != 1 || texts[0] != "from before the change" {
		t.Errorf("merged messages = %v, want the legacy message preserved", texts)
	}
}


// The shift-application and decision handlers push only: functions-core writes
// the in-app record for those events in the request that causes them (see
// acceptShift / approveShiftApplicant). Calling notifyUser here as well put the
// same application in the nursery's list twice, under two different titles.
func TestShiftApplicationHandlersDoNotDuplicateInAppNotifications(t *testing.T) {
	ctx := context.Background()
	db, err := fsDB(ctx)
	if err != nil {
		t.Fatalf("fsDB: %v", err)
	}

	nurseryUID := testUID("dedupe-nursery")
	staffUID := testUID("dedupe-staff")
	shiftID := testUID("dedupe-shift")

	cleanup := func(uid string) {
		iter := db.Collection("notifications").Where("uid", "==", uid).Documents(ctx)
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
	}
	t.Cleanup(func() { cleanup(nurseryUID); cleanup(staffUID) })

	cases := []struct {
		name    string
		payload any
		handler func(context.Context, event.Event) error
		uid     string
	}{
		{"applied", shiftAppliedPayload{ShiftID: shiftID, NurseryID: nurseryUID, StaffID: staffUID}, onShiftApplied, nurseryUID},
		{"approved", shiftDecisionPayload{ShiftID: shiftID, NurseryID: nurseryUID, StaffID: staffUID, Approved: true}, onShiftApplicationDecided, staffUID},
		{"declined", shiftDecisionPayload{ShiftID: shiftID, NurseryID: nurseryUID, StaffID: staffUID}, onShiftApplicationDecided, staffUID},
		{"auto_rejected", shiftDecisionPayload{ShiftID: shiftID, NurseryID: nurseryUID, StaffID: staffUID, AutoRejected: true}, onShiftApplicationDecided, staffUID},
	}
	for _, c := range cases {
		if err := c.handler(ctx, pubsubEvent(t, c.name, c.payload)); err != nil {
			t.Fatalf("%s: %v", c.name, err)
		}
		if notifs := notificationsForUID(t, c.uid); len(notifs) != 0 {
			t.Errorf("%s: wrote %d in-app notifications, want 0 (core owns the in-app record)", c.name, len(notifs))
		}
	}
}
