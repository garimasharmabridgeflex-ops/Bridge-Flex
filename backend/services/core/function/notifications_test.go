package function

import (
	"context"
	"fmt"
	"testing"
	"time"

	"google.golang.org/api/iterator"
)

// notifyInApp now also sends an FCM push. The push must stay best-effort: the
// in-app record is the source of truth and the thing the app actually reads, so
// a missing/unusable messaging client must neither lose the record nor turn
// into an error the caller might treat as "the approval failed".
func TestNotifyInAppWritesRecordWithoutPushCredentials(t *testing.T) {
	ctx := context.Background()
	db, err := fsDB(ctx)
	if err != nil {
		t.Fatalf("fsDB: %v", err)
	}
	uid := fmt.Sprintf("notify-test-%d", time.Now().UnixNano())
	t.Cleanup(func() {
		iter := db.Collection("notifications").Where("uid", "==", uid).Documents(ctx)
		defer iter.Stop()
		for {
			doc, err := iter.Next()
			if err == iterator.Done {
				break
			}
			if err == nil {
				_, _ = doc.Ref.Delete(ctx)
			}
		}
	})

	// The wording of a real event: a vetting decision reaching the practitioner.
	err = notifyInApp(ctx, db, uid, "vetting_approved",
		"DBS Checked by K Flex",
		"Your DBS check has been verified.",
		map[string]any{"type": "vetting_approved"})
	if err != nil {
		t.Fatalf("notifyInApp returned %v; a push problem must not surface as an error", err)
	}

	iter := db.Collection("notifications").Where("uid", "==", uid).Documents(ctx)
	defer iter.Stop()
	var found int
	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			t.Fatalf("iterate notifications: %v", err)
		}
		found++
		data := doc.Data()
		if data["type"] != "vetting_approved" {
			t.Errorf("type = %v, want vetting_approved", data["type"])
		}
		if data["read"] != false {
			t.Errorf("read = %v, want false", data["read"])
		}
		if data["title"] != "DBS Checked by K Flex" {
			t.Errorf("title = %v, want the title the app shows", data["title"])
		}
	}
	if found != 1 {
		t.Errorf("wrote %d notification documents, want 1", found)
	}
}
