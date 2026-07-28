package function

// Direct unit tests for the Eventarc-triggered handlers (Firestore/Auth
// events), following ARCHITECTURE.md v2 §7's approach: hand-construct the
// CloudEvent payload the real trigger would deliver, call the handler
// function directly, assert on the resulting Firestore state. There is no
// live local Eventarc dispatch for Go, so this is the only way these get
// exercised before a real deploy.
//
// Requires the Firestore and Pub/Sub emulators running and
// FIRESTORE_EMULATOR_HOST / GCLOUD_PROJECT set — see backend/README.md.

import (
	"context"
	"fmt"
	"testing"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/cloudevents/sdk-go/v2/event"
	"github.com/googleapis/google-cloudevents-go/cloud/firestoredata"
	"github.com/googleapis/google-cloudevents-go/firebase/authdata"
	"google.golang.org/genproto/googleapis/type/latlng"
	"google.golang.org/protobuf/proto"
)

const testDatabasePath = "projects/demo-kvision.internal/databases/(default)/documents"

func docName(collection, id string) string {
	return fmt.Sprintf("%s/%s/%s", testDatabasePath, collection, id)
}

func strVal(s string) *firestoredata.Value {
	return &firestoredata.Value{ValueType: &firestoredata.Value_StringValue{StringValue: s}}
}

func intVal(i int64) *firestoredata.Value {
	return &firestoredata.Value{ValueType: &firestoredata.Value_IntegerValue{IntegerValue: i}}
}

func mapVal(fields map[string]*firestoredata.Value) *firestoredata.Value {
	return &firestoredata.Value{ValueType: &firestoredata.Value_MapValue{MapValue: &firestoredata.MapValue{Fields: fields}}}
}

// firestoreWriteEvent builds a CloudEvent carrying a DocumentEventData
// payload for a document create/update, matching what a real
// google.cloud.firestore.document.v1.written/created Eventarc trigger
// delivers.
func firestoreWriteEvent(t *testing.T, docPath string, fields map[string]*firestoredata.Value) event.Event {
	t.Helper()
	data := &firestoredata.DocumentEventData{
		Value: &firestoredata.Document{
			Name:   docPath,
			Fields: fields,
		},
	}
	raw, err := proto.Marshal(data)
	if err != nil {
		t.Fatalf("proto.Marshal DocumentEventData: %v", err)
	}
	e := event.New()
	e.SetType("google.cloud.firestore.document.v1.written")
	e.SetSource("//firestore.googleapis.com/projects/demo-kvision.internal/databases/(default)")
	if err := e.SetData("application/protobuf", raw); err != nil {
		t.Fatalf("event.SetData: %v", err)
	}
	return e
}

func authUserCreatedEvent(t *testing.T, uid, email, displayName string) event.Event {
	t.Helper()
	data := &authdata.AuthEventData{
		Uid:         uid,
		Email:       email,
		DisplayName: displayName,
	}
	raw, err := proto.Marshal(data)
	if err != nil {
		t.Fatalf("proto.Marshal AuthEventData: %v", err)
	}
	e := event.New()
	e.SetType("google.firebase.auth.user.v1.created")
	e.SetSource("//firebaseauth.googleapis.com/projects/demo-bridgeflex")
	if err := e.SetData("application/protobuf", raw); err != nil {
		t.Fatalf("event.SetData: %v", err)
	}
	return e
}

func testFirestore(t *testing.T) *firestore.Client {
	t.Helper()
	db, err := fsDB(context.Background())
	if err != nil {
		t.Fatalf("fsDB: %v", err)
	}
	return db
}

func testUID(t *testing.T, prefix string) string {
	t.Helper()
	return fmt.Sprintf("%s-%d", prefix, time.Now().UnixNano())
}

func TestInitProfileOnSignUp(t *testing.T) {
	ctx := context.Background()
	db := testFirestore(t)
	uid := testUID(t, "trigger-test-signup")
	t.Cleanup(func() { _, _ = db.Collection("profiles").Doc(uid).Delete(ctx) })

	e := authUserCreatedEvent(t, uid, "trigger-test@example.com", "Trigger Test User")
	if err := initProfileOnSignUp(ctx, e); err != nil {
		t.Fatalf("initProfileOnSignUp: %v", err)
	}

	snap, err := db.Collection("profiles").Doc(uid).Get(ctx)
	if err != nil {
		t.Fatalf("read profiles/%s: %v", uid, err)
	}
	var p Profile
	if err := snap.DataTo(&p); err != nil {
		t.Fatalf("DataTo: %v", err)
	}
	if p.Role != "" {
		t.Errorf("Role = %q, want empty (unset until UpdateProfile completes sign-up)", p.Role)
	}
	if p.Name != "Trigger Test User" {
		t.Errorf("Name = %q, want %q", p.Name, "Trigger Test User")
	}
	if p.DBSStatus != DBSUnverified {
		t.Errorf("DBSStatus = %q, want %q", p.DBSStatus, DBSUnverified)
	}
}

func TestSyncProfilePublic(t *testing.T) {
	ctx := context.Background()
	db := testFirestore(t)
	uid := testUID(t, "trigger-test-sync")
	t.Cleanup(func() { _, _ = db.Collection("profilesPublic").Doc(uid).Delete(ctx) })

	fields := map[string]*firestoredata.Value{
		"role":      strVal("staff"),
		"name":      strVal("Sync Test Staff"),
		"dbsStatus": strVal("verified"),
		"rating":    mapVal(map[string]*firestoredata.Value{"average": {ValueType: &firestoredata.Value_DoubleValue{DoubleValue: 4.5}}, "count": intVal(10)}),
		"location":  {ValueType: &firestoredata.Value_GeoPointValue{GeoPointValue: &latlng.LatLng{Latitude: 53.4808, Longitude: -2.2426}}},
	}
	e := firestoreWriteEvent(t, docName("profiles", uid), fields)

	if err := syncProfilePublic(ctx, e); err != nil {
		t.Fatalf("syncProfilePublic: %v", err)
	}

	snap, err := db.Collection("profilesPublic").Doc(uid).Get(ctx)
	if err != nil {
		t.Fatalf("read profilesPublic/%s: %v", uid, err)
	}
	var pub ProfilePublic
	if err := snap.DataTo(&pub); err != nil {
		t.Fatalf("DataTo: %v", err)
	}
	if pub.Role != RoleStaff {
		t.Errorf("Role = %q, want %q", pub.Role, RoleStaff)
	}
	if pub.Name != "Sync Test Staff" {
		t.Errorf("Name = %q, want %q", pub.Name, "Sync Test Staff")
	}
	if pub.DBSBadge != DBSVerified {
		t.Errorf("DBSBadge = %q, want %q", pub.DBSBadge, DBSVerified)
	}
	if pub.Rating.Average != 4.5 || pub.Rating.Count != 10 {
		t.Errorf("Rating = %+v, want {4.5 10}", pub.Rating)
	}
	wantArea := geohashPrefix(53.4808, -2.2426, geohashPrecision)
	if pub.LocationArea != wantArea {
		t.Errorf("LocationArea = %q, want %q", pub.LocationArea, wantArea)
	}
	// The whole point of the v2 fix: the exact GeoPoint never appears on the
	// public doc at all — ProfilePublic has no field for it, so there's
	// nothing further to assert here beyond "it compiles without one."
}

// TestSyncProfilePublicWizardFields covers the full app spec §1.2/§1.3
// additions: staff experience fields and nursery setting fields mirror
// into profilesPublic, and — critically — a role never carries the other
// role's fields (e.g. a nursery's profilesPublic doc has no bio/experience).
func TestSyncProfilePublicWizardFields(t *testing.T) {
	ctx := context.Background()
	db := testFirestore(t)

	t.Run("staff experience fields mirror, nursery fields stay empty", func(t *testing.T) {
		uid := testUID(t, "trigger-test-sync-staff-wizard")
		t.Cleanup(func() { _, _ = db.Collection("profilesPublic").Doc(uid).Delete(ctx) })

		fields := map[string]*firestoredata.Value{
			"role":               strVal("staff"),
			"name":               strVal("Wizard Test Staff"),
			"yearsExperience":    intVal(3),
			"qualificationLevel": strVal("level_3"),
			"bio":                strVal("Loves messy play."),
			"previousRoles": {ValueType: &firestoredata.Value_ArrayValue{ArrayValue: &firestoredata.ArrayValue{
				Values: []*firestoredata.Value{
					mapVal(map[string]*firestoredata.Value{
						"settingName": strVal("Sunny Days Nursery"),
						"roleTitle":   strVal("Room Leader"),
						"duration":    strVal("2 years"),
					}),
				},
			}}},
			// Nursery-only fields present in the write shouldn't leak through
			// for a staff profile.
			"description": strVal("should not appear"),
		}
		e := firestoreWriteEvent(t, docName("profiles", uid), fields)
		if err := syncProfilePublic(ctx, e); err != nil {
			t.Fatalf("syncProfilePublic: %v", err)
		}

		snap, err := db.Collection("profilesPublic").Doc(uid).Get(ctx)
		if err != nil {
			t.Fatalf("read profilesPublic/%s: %v", uid, err)
		}
		var pub ProfilePublic
		if err := snap.DataTo(&pub); err != nil {
			t.Fatalf("DataTo: %v", err)
		}
		if pub.YearsExperience != 3 {
			t.Errorf("YearsExperience = %d, want 3", pub.YearsExperience)
		}
		if pub.QualificationLevel != QualLevel3 {
			t.Errorf("QualificationLevel = %q, want %q", pub.QualificationLevel, QualLevel3)
		}
		if pub.Bio != "Loves messy play." {
			t.Errorf("Bio = %q, want %q", pub.Bio, "Loves messy play.")
		}
		if len(pub.PreviousRoles) != 1 || pub.PreviousRoles[0].SettingName != "Sunny Days Nursery" {
			t.Errorf("PreviousRoles = %+v, want one entry for Sunny Days Nursery", pub.PreviousRoles)
		}
		if pub.Description != "" {
			t.Errorf("Description = %q, want empty for a staff profile", pub.Description)
		}
	})

	t.Run("nursery setting fields mirror, staff fields stay empty", func(t *testing.T) {
		uid := testUID(t, "trigger-test-sync-nursery-wizard")
		t.Cleanup(func() { _, _ = db.Collection("profilesPublic").Doc(uid).Delete(ctx) })

		fields := map[string]*firestoredata.Value{
			"role":         strVal("nursery"),
			"name":         strVal("Wizard Test Nursery"),
			"description":  strVal("A friendly Ofsted-rated setting."),
			"openingHours": strVal("Mon-Fri 7:30am-6pm"),
			"ofstedRating": strVal("outstanding"),
			"photos": {ValueType: &firestoredata.Value_ArrayValue{ArrayValue: &firestoredata.ArrayValue{
				Values: []*firestoredata.Value{strVal("https://example.com/photo1.jpg")},
			}}},
			// Staff-only field present in the write shouldn't leak through.
			"bio": strVal("should not appear"),
		}
		e := firestoreWriteEvent(t, docName("profiles", uid), fields)
		if err := syncProfilePublic(ctx, e); err != nil {
			t.Fatalf("syncProfilePublic: %v", err)
		}

		snap, err := db.Collection("profilesPublic").Doc(uid).Get(ctx)
		if err != nil {
			t.Fatalf("read profilesPublic/%s: %v", uid, err)
		}
		var pub ProfilePublic
		if err := snap.DataTo(&pub); err != nil {
			t.Fatalf("DataTo: %v", err)
		}
		if pub.Description != "A friendly Ofsted-rated setting." {
			t.Errorf("Description = %q, want the seeded description", pub.Description)
		}
		if pub.OpeningHours != "Mon-Fri 7:30am-6pm" {
			t.Errorf("OpeningHours = %q, want %q", pub.OpeningHours, "Mon-Fri 7:30am-6pm")
		}
		if pub.OfstedRating != OfstedOutstanding {
			t.Errorf("OfstedRating = %q, want %q", pub.OfstedRating, OfstedOutstanding)
		}
		if len(pub.Photos) != 1 || pub.Photos[0] != "https://example.com/photo1.jpg" {
			t.Errorf("Photos = %+v, want one seeded photo URL", pub.Photos)
		}
		if pub.Bio != "" {
			t.Errorf("Bio = %q, want empty for a nursery profile", pub.Bio)
		}
	})
}

func TestRecomputeRating(t *testing.T) {
	ctx := context.Background()
	db := testFirestore(t)
	rateeUID := testUID(t, "trigger-test-ratee")
	ratingID := testUID(t, "trigger-test-rating")
	t.Cleanup(func() { _, _ = db.Collection("profiles").Doc(rateeUID).Delete(ctx) })

	if _, err := db.Collection("profiles").Doc(rateeUID).Set(ctx, map[string]any{
		"role":      "nursery",
		"name":      "Rating Recompute Test Nursery",
		"dbsStatus": "unverified",
		"rating":    map[string]any{"average": 4.0, "count": int64(2)},
		"createdAt": time.Now(),
	}); err != nil {
		t.Fatalf("seed profiles/%s: %v", rateeUID, err)
	}

	fields := map[string]*firestoredata.Value{
		"shiftId": strVal("some-shift"),
		"raterId": strVal("some-staff"),
		"rateeId": strVal(rateeUID),
		"score":   intVal(5),
	}
	e := firestoreWriteEvent(t, docName("ratings", ratingID), fields)

	if err := recomputeRating(ctx, e); err != nil {
		t.Fatalf("recomputeRating: %v", err)
	}

	snap, err := db.Collection("profiles").Doc(rateeUID).Get(ctx)
	if err != nil {
		t.Fatalf("read profiles/%s: %v", rateeUID, err)
	}
	var p Profile
	if err := snap.DataTo(&p); err != nil {
		t.Fatalf("DataTo: %v", err)
	}
	wantAvg := (4.0*2 + 5.0) / 3.0
	if p.Rating.Count != 3 {
		t.Errorf("Rating.Count = %d, want 3", p.Rating.Count)
	}
	if diff := p.Rating.Average - wantAvg; diff > 1e-9 || diff < -1e-9 {
		t.Errorf("Rating.Average = %v, want %v", p.Rating.Average, wantAvg)
	}
}

func TestMatchNewShift(t *testing.T) {
	ctx := context.Background()
	db := testFirestore(t)
	staffUID := testUID(t, "trigger-test-match-staff")
	shiftID := testUID(t, "trigger-test-shift")
	t.Cleanup(func() { _, _ = db.Collection("profiles").Doc(staffUID).Delete(ctx) })

	if _, err := db.Collection("profiles").Doc(staffUID).Set(ctx, map[string]any{
		"role":      "staff",
		"name":      "Match Test Staff",
		"dbsStatus": "verified",
		"rating":    map[string]any{"average": 0.0, "count": int64(0)},
		"createdAt": time.Now(),
	}); err != nil {
		t.Fatalf("seed profiles/%s: %v", staffUID, err)
	}

	fields := map[string]*firestoredata.Value{
		"nurseryId": strVal("some-nursery"),
		"status":    strVal("open"),
	}
	e := firestoreWriteEvent(t, docName("shifts", shiftID), fields)

	// matchNewShift queries ALL staff profiles and publishes one message per
	// match — this only asserts it runs end-to-end without error (Firestore
	// query + Pub/Sub publish both succeed against the real emulators); it
	// doesn't assert on the published message content the way
	// TestRecomputeRating's cousin tests could, to keep this test's fixture
	// data isolated from whatever other staff profiles exist in the emulator
	// at the time (there's no collection-wide cleanup between test runs).
	if err := matchNewShift(ctx, e); err != nil {
		t.Fatalf("matchNewShift: %v", err)
	}
}
