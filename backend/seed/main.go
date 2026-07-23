// Command seed populates the Firestore/Auth emulators with sample nursery
// and staff profiles and shifts in various states, so the Bruno collection
// and manual testing have real data immediately (ARCHITECTURE.md v2 §7).
// Run against emulators only — point FIRESTORE_EMULATOR_HOST /
// FIREBASE_AUTH_EMULATOR_HOST at the running emulators before invoking this
// (see backend/README.md).
package main

import (
	"context"
	"fmt"
	"log"
	"time"

	"cloud.google.com/go/firestore"
	firebaseauth "firebase.google.com/go/v4/auth"
	"google.golang.org/genproto/googleapis/type/latlng"

	"kvision.internal/shared/fbapp"
)

type sampleUser struct {
	UID         string
	Email       string
	Password    string
	DisplayName string
	Role        string
	DBSStatus   string
	Description string
	Lat, Lng    float64
}

var users = []sampleUser{
	{
		UID: "nursery-acorn", Email: "acorn@example.com", Password: "password123",
		DisplayName: "Acorn Nursery", Role: "nursery",
		Description: "A friendly Ofsted-rated nursery in Manchester.",
		Lat:         53.4808, Lng: -2.2426,
	},
	{
		UID: "nursery-willow", Email: "willow@example.com", Password: "password123",
		DisplayName: "Willow Nursery", Role: "nursery",
		Description: "Small nursery in Leeds.",
		Lat:         53.8008, Lng: -1.5491,
	},
	{
		UID: "staff-jane", Email: "jane@example.com", Password: "password123",
		DisplayName: "Jane Doe", Role: "staff", DBSStatus: "verified",
		Lat: 53.4831, Lng: -2.2441,
	},
	{
		UID: "staff-sam", Email: "sam@example.com", Password: "password123",
		DisplayName: "Sam Patel", Role: "staff", DBSStatus: "pending",
		Lat: 53.7997, Lng: -1.5492,
	},
	{
		UID: "admin-super", Email: "admin@example.com", Password: "password123",
		DisplayName: "Super Admin", Role: "admin", DBSStatus: "verified",
		Description: "K Vision Platform Super Administrator.",
		Lat: 53.4808, Lng: -2.2426,
	},
}

func main() {
	ctx := context.Background()

	app, err := fbapp.New(ctx)
	if err != nil {
		log.Fatalf("fbapp.New: %v", err)
	}
	authClient, err := app.Auth(ctx)
	if err != nil {
		log.Fatalf("app.Auth: %v", err)
	}
	db, err := app.Firestore(ctx)
	if err != nil {
		log.Fatalf("app.Firestore: %v", err)
	}
	defer db.Close()

	for _, u := range users {
		if err := seedUser(ctx, authClient, db, u); err != nil {
			log.Fatalf("seed user %s: %v", u.UID, err)
		}
		fmt.Printf("seeded user %-14s (%s)\n", u.UID, u.Role)
	}

	if err := seedShifts(ctx, db); err != nil {
		log.Fatalf("seed shifts: %v", err)
	}
	fmt.Println("seeded shifts: shift-open-1, shift-open-2, shift-booked-1, shift-cancelled-1")

	// onShiftBooked/onRatingReceived (communication's Pub/Sub triggers) don't
	// fire locally (§7 — no live trigger dispatch for Go), so the seed
	// script also seeds what they would have created for shift-booked-1,
	// giving the Bruno "communication" folder real data to hit out of the box.
	if err := seedCommunicationData(ctx, db); err != nil {
		log.Fatalf("seed communication data: %v", err)
	}
	fmt.Println("seeded chat session and notification for shift-booked-1")
	fmt.Println("done")
}

func seedCommunicationData(ctx context.Context, db *firestore.Client) error {
	now := time.Now()
	_, err := db.Collection("chatSessions").Doc("session-1").Set(ctx, map[string]any{
		"shiftId":        "shift-booked-1",
		"participantIds": []string{"nursery-acorn", "staff-jane"},
		"createdAt":      now,
		"lastMessageAt":  now,
	})
	if err != nil {
		return fmt.Errorf("write chatSessions/session-1: %w", err)
	}

	_, err = db.Collection("notifications").Doc("notif-1").Set(ctx, map[string]any{
		"uid":       "staff-jane",
		"type":      "shift_booked",
		"payload":   map[string]any{"shiftId": "shift-booked-1"},
		"read":      false,
		"createdAt": now,
	})
	if err != nil {
		return fmt.Errorf("write notifications/notif-1: %w", err)
	}
	return nil
}

func seedUser(ctx context.Context, authClient *firebaseauth.Client, db *firestore.Client, u sampleUser) error {
	if _, err := authClient.GetUser(ctx, u.UID); err == nil {
		return nil // already seeded — safe to re-run
	}
	params := (&firebaseauth.UserToCreate{}).
		UID(u.UID).
		Email(u.Email).
		Password(u.Password).
		DisplayName(u.DisplayName)
	if _, err := authClient.CreateUser(ctx, params); err != nil {
		return fmt.Errorf("create auth user: %w", err)
	}

	// The "admin" role isn't a marketplace role at all (Role only ever
	// means nursery|staff — see models.go) — it's authorized purely via
	// the Firebase "admin" custom claim isAdmin() (documents.go) checks.
	// Without this, the seeded admin-super account would 403 on every
	// admin-gated endpoint despite its Firestore profile saying role=admin.
	if u.Role == "admin" {
		if err := authClient.SetCustomUserClaims(ctx, u.UID, map[string]interface{}{"admin": true}); err != nil {
			return fmt.Errorf("set admin custom claim: %w", err)
		}
	}

	dbsStatus := u.DBSStatus
	if dbsStatus == "" {
		dbsStatus = "unverified"
	}

	profile := map[string]any{
		"role":        u.Role,
		"name":        u.DisplayName,
		"location":    &latlng.LatLng{Latitude: u.Lat, Longitude: u.Lng},
		"description": u.Description,
		"dbsStatus":   dbsStatus,
		"rating":      map[string]any{"average": 0.0, "count": int64(0)},
		"createdAt":   time.Now(),
	}
	if _, err := db.Collection("profiles").Doc(u.UID).Set(ctx, profile); err != nil {
		return fmt.Errorf("write profiles/%s: %w", u.UID, err)
	}

	// The real syncProfilePublic Eventarc trigger doesn't fire locally
	// (ARCHITECTURE.md v2 §7 — no live local trigger dispatch for Go), so the
	// seed script writes profilesPublic directly, mirroring exactly what
	// that trigger would derive.
	public := map[string]any{
		"role":         u.Role,
		"name":         u.DisplayName,
		"locationArea": geohashPrefix(u.Lat, u.Lng, 4),
		"rating":       map[string]any{"average": 0.0, "count": int64(0)},
		"dbsBadge":     dbsStatus,
		"updatedAt":    time.Now(),
	}
	if _, err := db.Collection("profilesPublic").Doc(u.UID).Set(ctx, public); err != nil {
		return fmt.Errorf("write profilesPublic/%s: %w", u.UID, err)
	}
	return nil
}

func seedShifts(ctx context.Context, db *firestore.Client) error {
	now := time.Now()
	bookedStaff := "staff-jane"

	shifts := []struct {
		ID            string
		NurseryID     string
		Title         string
		Status        string
		BookedStaffID *string
		PayRate       float64
	}{
		{"shift-open-1", "nursery-acorn", "Morning cover — baby room", "open", nil, 14.5},
		{"shift-open-2", "nursery-willow", "Afternoon cover — toddler room", "open", nil, 13.0},
		{"shift-booked-1", "nursery-acorn", "Cover — already booked", "booked", &bookedStaff, 15.0},
		{"shift-cancelled-1", "nursery-willow", "Cancelled shift", "cancelled", nil, 12.0},
	}

	for _, s := range shifts {
		_, err := db.Collection("shifts").Doc(s.ID).Set(ctx, map[string]any{
			"nurseryId":     s.NurseryID,
			"title":         s.Title,
			"date":          now.Format("2006-01-02"),
			"startTime":     now.Add(24 * time.Hour),
			"endTime":       now.Add(28 * time.Hour),
			"payRate":       s.PayRate,
			"status":        s.Status,
			"bookedStaffId": s.BookedStaffID,
			"paymentStatus": "not_required",
			"createdAt":     now,
		})
		if err != nil {
			return fmt.Errorf("write shifts/%s: %w", s.ID, err)
		}
	}
	return nil
}
