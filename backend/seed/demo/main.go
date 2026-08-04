// Command demo seeds the REAL production project with a small, self-contained
// set of demo accounts and shifts, so an App Store / Beta App reviewer (and
// anyone doing a walkthrough) can sign in and immediately see a populated app
// rather than empty screens.
//
// This is deliberately separate from ../main.go, which targets the emulators
// and uses example.com addresses and "password123". Everything created here is
// prefixed "demo-" so it is trivially identifiable and removable — see the
// -delete flag.
//
// Usage (writes to production — read the plan it prints before confirming):
//
//	gcloud auth application-default login    # one-time, needs Firebase admin rights
//	cd backend/seed && go run ./demo -project kvision-503115
//	cd backend/seed && go run ./demo -project kvision-503115 -delete   # clean up
//
// The password comes from DEMO_PASSWORD if set, otherwise the default below.
// Whatever it ends up being is what you give Apple in App Store Connect's
// "App Review Information → Sign-in required" section.
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"time"

	"cloud.google.com/go/firestore"
	firebase "firebase.google.com/go/v4"
	firebaseauth "firebase.google.com/go/v4/auth"
	"google.golang.org/api/iterator"
	"google.golang.org/genproto/googleapis/type/latlng"
)

const defaultPassword = "BridgeFlexDemo2026!"

// Manchester city centre — the nursery, the staff member and the shifts all sit
// close together so the geo-matching in matchNewShift actually pairs them.
const (
	latManchester = 53.4808
	lngManchester = -2.2426
)

type demoUser struct {
	UID     string
	Email   string
	Role    string // nursery | staff | admin (admin is a claim, not a marketplace role)
	Name    string
	IsAdmin bool
	Profile map[string]any
}

func main() {
	projectID := flag.String("project", "kvision-503115", "Firebase project ID to write to")
	del := flag.Bool("delete", false, "remove everything this tool created instead of creating it")
	flag.Parse()

	if os.Getenv("FIRESTORE_EMULATOR_HOST") != "" || os.Getenv("FIREBASE_AUTH_EMULATOR_HOST") != "" {
		log.Fatal("emulator env vars are set — unset them, or use ../main.go for emulator seeding")
	}

	password := os.Getenv("DEMO_PASSWORD")
	if password == "" {
		password = defaultPassword
	}

	ctx := context.Background()
	app, err := firebase.NewApp(ctx, &firebase.Config{ProjectID: *projectID})
	if err != nil {
		log.Fatalf("firebase.NewApp: %v (did you run `gcloud auth application-default login`?)", err)
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

	users := demoUsers()

	if *del {
		if err := deleteAll(ctx, authClient, db, users); err != nil {
			log.Fatalf("delete: %v", err)
		}
		fmt.Println("\nremoved all demo accounts, shifts, chat sessions and notifications")
		return
	}

	fmt.Printf("seeding demo data into project %s\n\n", *projectID)

	for _, u := range users {
		if err := seedUser(ctx, authClient, db, u, password); err != nil {
			log.Fatalf("seed %s: %v", u.UID, err)
		}
		label := u.Role
		if u.IsAdmin {
			label += " (+admin claim)"
		}
		fmt.Printf("  user   %-22s %-28s %s\n", u.UID, u.Email, label)
	}

	if err := seedShifts(ctx, db); err != nil {
		log.Fatalf("seed shifts: %v", err)
	}
	if err := seedCommunication(ctx, db); err != nil {
		log.Fatalf("seed communication: %v", err)
	}
	if err := seedRating(ctx, db); err != nil {
		log.Fatalf("seed rating: %v", err)
	}

	fmt.Printf("\nAll demo accounts share this password: %s\n", password)
	fmt.Println("\nGive these to Apple under App Store Connect → App Review Information:")
	fmt.Printf("  Nursery view : %s\n", users[0].Email)
	fmt.Printf("  Staff view   : %s\n", users[1].Email)
	fmt.Printf("  Admin view   : %s\n", users[2].Email)
	fmt.Println("\nRe-runnable: existing accounts are updated, not duplicated.")
}

func demoUsers() []demoUser {
	// Gmail "+" addressing: real, deliverable inboxes (so password reset works)
	// that are still obviously demo accounts.
	return []demoUser{
		{
			UID: "demo-nursery-sunnydale", Email: "afrilexkenya+demo.nursery@gmail.com",
			Role: "nursery", Name: "Sunnydale Day Nursery",
			Profile: map[string]any{
				"description":           "A warm, Ofsted-rated day nursery in central Manchester caring for children from 3 months to 5 years.",
				"shortDescription":      "Ofsted-rated day nursery in central Manchester.",
				"phone":                 "+441611234567",
				"email":                 "hello@sunnydale-demo.co.uk",
				"address":               "42 Oxford Road, Manchester",
				"postcode":              "M1 5QA",
				"city":                  "Manchester",
				"registeredCompanyName": "Sunnydale Childcare Ltd",
				"ofstedRegNumber":       "EY123456",
				"ofstedRating":          "good",
				"nurseryType":           "private",
				"yearEstablished":       int64(2014),
				"openingHours":          "Mon–Fri, 07:30–18:00",
				"website":               "https://example.com",
				"facilities":            []string{"Outdoor garden", "Sensory room", "On-site kitchen", "Baby room"},
				"identityVerified":      true,
				"ofstedVerified":        true,
			},
		},
		{
			UID: "demo-staff-amelia", Email: "afrilexkenya+demo.staff@gmail.com",
			Role: "staff", Name: "Amelia Hughes",
			Profile: map[string]any{
				"dbsStatus":           "verified",
				"phone":               "+447700900123",
				"city":                "Manchester",
				"age":                 int64(29),
				"yearsExperience":     int64(6),
				"qualificationLevel":  "level_3",
				"bio":                 "Level 3 qualified early years practitioner with six years across baby and toddler rooms. Calm, playful, and confident leading free-flow play.",
				"professionalSummary": "Level 3 Early Years Educator — baby and toddler room specialist.",
				"qualifications":      []string{"Level 3 Diploma in Early Years Education", "Paediatric First Aid", "Safeguarding Level 2"},
				"skills":              []string{"Baby room", "Toddler room", "SEN support", "Messy play", "Phonics"},
				"languages":           []string{"English", "Welsh"},
				"availabilityDays":    []string{"monday", "tuesday", "wednesday", "thursday", "friday"},
				"availabilityShifts":  []string{"morning", "afternoon", "full_day"},
				"travelDistanceMiles": int64(12),
				"nationality":         "British",
				"rightToWorkStatus":   "British citizen",
				"rightToWorkVerified": true,
				"identityVerified":    true,
				"previousRoles": []map[string]any{
					{"settingName": "Little Acorns Nursery", "roleTitle": "Room Leader — Toddlers", "duration": "2022–2025"},
					{"settingName": "Bright Beginnings Preschool", "roleTitle": "Early Years Practitioner", "duration": "2019–2022"},
				},
			},
		},
		{
			UID: "demo-admin", Email: "afrilexkenya+demo.admin@gmail.com",
			Role: "staff", Name: "Bridge Flex Admin", IsAdmin: true,
			Profile: map[string]any{
				"description": "Bridge Flex platform administrator (demo).",
				"dbsStatus":   "verified",
			},
		},
	}
}

func seedUser(ctx context.Context, authClient *firebaseauth.Client, db *firestore.Client, u demoUser, password string) error {
	// Idempotent: update the existing account rather than failing, so this can
	// be re-run after tweaking the demo content.
	if _, err := authClient.GetUser(ctx, u.UID); err != nil {
		params := (&firebaseauth.UserToCreate{}).
			UID(u.UID).Email(u.Email).Password(password).DisplayName(u.Name).EmailVerified(true)
		if _, err := authClient.CreateUser(ctx, params); err != nil {
			return fmt.Errorf("create auth user: %w", err)
		}
	} else {
		params := (&firebaseauth.UserToUpdate{}).
			Email(u.Email).Password(password).DisplayName(u.Name).EmailVerified(true)
		if _, err := authClient.UpdateUser(ctx, u.UID, params); err != nil {
			return fmt.Errorf("update auth user: %w", err)
		}
	}

	// "admin" is not a marketplace Role — it is only ever the Firebase custom
	// claim that isAdmin() checks. Without this the account 403s on every
	// admin-gated endpoint (see ../main.go for the same note).
	if u.IsAdmin {
		if err := authClient.SetCustomUserClaims(ctx, u.UID, map[string]any{"admin": true}); err != nil {
			return fmt.Errorf("set admin claim: %w", err)
		}
	}

	profile := map[string]any{
		"role":      u.Role,
		"name":      u.Name,
		"location":  &latlng.LatLng{Latitude: latManchester, Longitude: lngManchester},
		"rating":    map[string]any{"average": 0.0, "count": int64(0)},
		"createdAt": time.Now(),
		"dbsStatus": "unverified",
	}
	for k, v := range u.Profile {
		profile[k] = v
	}

	// Only profiles/ is written. In production the syncProfilePublic Eventarc
	// trigger derives profilesPublic/ from this write — unlike the emulator
	// seeder, which has to fake that because triggers don't dispatch locally.
	if _, err := db.Collection("profiles").Doc(u.UID).Set(ctx, profile); err != nil {
		return fmt.Errorf("write profiles/%s: %w", u.UID, err)
	}
	return nil
}

func seedShifts(ctx context.Context, db *firestore.Client) error {
	now := time.Now()
	nursery := "demo-nursery-sunnydale"
	staff := "demo-staff-amelia"

	shifts := []struct {
		ID       string
		Title    string
		Status   string
		Booked   []string
		PayRate  float64
		DayOff   int // days from now
		Room     string
		AgeGroup string
		Children int64
		Duties   []string
		Reqs     []string
	}{
		{
			ID: "demo-shift-open-baby", Title: "Morning cover — Baby room", Status: "open",
			PayRate: 14.50, DayOff: 2, Room: "Baby room", AgeGroup: "3 months – 2 years", Children: 8,
			Duties: []string{"Support free-flow play", "Nappy changes and feeds", "Record daily observations"},
			Reqs:   []string{"Level 2 or above", "Valid DBS", "Paediatric first aid desirable"},
		},
		{
			ID: "demo-shift-open-toddler", Title: "Full day — Toddler room", Status: "open",
			PayRate: 15.00, DayOff: 4, Room: "Toddler room", AgeGroup: "2 – 3 years", Children: 12,
			Duties: []string{"Lead messy play session", "Support lunch and nap routine", "Garden supervision"},
			Reqs:   []string{"Level 3 preferred", "Valid DBS"},
		},
		{
			ID: "demo-shift-open-preschool", Title: "Afternoon cover — Pre-school", Status: "open",
			PayRate: 13.75, DayOff: 6, Room: "Pre-school room", AgeGroup: "3 – 5 years", Children: 16,
			Duties: []string{"Phonics activity", "Outdoor learning", "Tidy-up and handover"},
			Reqs:   []string{"Level 2 or above", "Valid DBS"},
		},
		{
			ID: "demo-shift-booked", Title: "Early shift — Baby room", Status: "booked",
			Booked: []string{staff}, PayRate: 15.50, DayOff: 1, Room: "Baby room",
			AgeGroup: "3 months – 2 years", Children: 6,
			Duties: []string{"Opening setup", "Breakfast service", "Key-person observations"},
			Reqs:   []string{"Level 3", "Valid DBS"},
		},
	}

	for _, s := range shifts {
		start := now.AddDate(0, 0, s.DayOff).Truncate(time.Hour)
		doc := map[string]any{
			"nurseryId":        nursery,
			"title":            s.Title,
			"description":      "Demo shift for platform walkthrough.",
			"date":             start.Format("2006-01-02"),
			"startTime":        start,
			"endTime":          start.Add(8 * time.Hour),
			"payRate":          s.PayRate,
			"status":           s.Status,
			"capacity":         int64(1),
			"paymentStatus":    "not_required",
			"createdAt":        now,
			"room":             s.Room,
			"ageGroup":         s.AgeGroup,
			"numberOfChildren": s.Children,
			"expectedDuties":   s.Duties,
			"requirements":     s.Reqs,
			"bookedStaffId":    nil,
		}
		if len(s.Booked) > 0 {
			doc["bookedStaffId"] = s.Booked[0]
			doc["bookedStaffIds"] = s.Booked
			doc["firstAcceptedAt"] = now.Add(-2 * time.Hour)
		}
		if _, err := db.Collection("shifts").Doc(s.ID).Set(ctx, doc); err != nil {
			return fmt.Errorf("write shifts/%s: %w", s.ID, err)
		}
		fmt.Printf("  shift  %-22s %-34s %s\n", s.ID, s.Title, s.Status)
	}
	return nil
}

// seedCommunication writes the chat session and notification that the
// onShiftBooked trigger would have produced for demo-shift-booked, since that
// shift was written directly rather than accepted through acceptShift.
func seedCommunication(ctx context.Context, db *firestore.Client) error {
	now := time.Now()
	nursery := "demo-nursery-sunnydale"
	staff := "demo-staff-amelia"

	if _, err := db.Collection("chatSessions").Doc("demo-session").Set(ctx, map[string]any{
		"shiftId":        "demo-shift-booked",
		"participantIds": []string{nursery, staff},
		"createdAt":      now.Add(-2 * time.Hour),
		"lastMessageAt":  now.Add(-90 * time.Minute),
	}); err != nil {
		return fmt.Errorf("write chatSessions/demo-session: %w", err)
	}

	msgs := []struct {
		ID, Sender, Text string
		AgoMinutes       int
	}{
		{"demo-msg-1", nursery, "Hi Amelia — thanks for picking up tomorrow's early shift! Doors open at 7:15.", 115},
		{"demo-msg-2", staff, "Perfect, I'll be there for 7:15. Anything I should bring?", 100},
		{"demo-msg-3", nursery, "Just your DBS card for the file. See you tomorrow!", 90},
	}
	for _, m := range msgs {
		if _, err := db.Collection("chatSessions").Doc("demo-session").
			Collection("messages").Doc(m.ID).Set(ctx, map[string]any{
			"senderId":  m.Sender,
			"text":      m.Text,
			"createdAt": now.Add(-time.Duration(m.AgoMinutes) * time.Minute),
		}); err != nil {
			return fmt.Errorf("write message %s: %w", m.ID, err)
		}
	}

	notifs := []struct {
		ID, UID, Type string
		Payload       map[string]any
		Read          bool
	}{
		{"demo-notif-booked", staff, "shift_booked", map[string]any{"shiftId": "demo-shift-booked"}, false},
		{"demo-notif-match", staff, "new_matching_shift", map[string]any{"shiftId": "demo-shift-open-toddler"}, false},
		{"demo-notif-rating", staff, "rating_received", map[string]any{"shiftId": "demo-shift-booked"}, true},
	}
	for _, n := range notifs {
		if _, err := db.Collection("notifications").Doc(n.ID).Set(ctx, map[string]any{
			"uid":       n.UID,
			"type":      n.Type,
			"payload":   n.Payload,
			"read":      n.Read,
			"createdAt": now.Add(-30 * time.Minute),
		}); err != nil {
			return fmt.Errorf("write notifications/%s: %w", n.ID, err)
		}
	}
	fmt.Println("  chat   demo-session           3 messages")
	fmt.Println("  notifs demo-notif-*           3 notifications")
	return nil
}

// seedRating gives the staff demo account a visible rating, so profile and
// review screens aren't empty. Written directly rather than via createRating
// because the aggregate is recomputed by a trigger we mirror here.
func seedRating(ctx context.Context, db *firestore.Client) error {
	now := time.Now()
	if _, err := db.Collection("ratings").Doc("demo-rating-1").Set(ctx, map[string]any{
		"shiftId":   "demo-shift-booked",
		"raterId":   "demo-nursery-sunnydale",
		"rateeId":   "demo-staff-amelia",
		"score":     int64(5),
		"comment":   "Amelia settled straight into the baby room and was brilliant with the children. Would book again.",
		"createdAt": now.Add(-24 * time.Hour),
		"categoryScores": map[string]any{
			"communication":   int64(5),
			"punctuality":     int64(5),
			"professionalism": int64(5),
			"reliability":     int64(5),
			"childEngagement": int64(5),
		},
	}); err != nil {
		return fmt.Errorf("write ratings/demo-rating-1: %w", err)
	}

	if _, err := db.Collection("profiles").Doc("demo-staff-amelia").Set(ctx, map[string]any{
		"rating": map[string]any{"average": 5.0, "count": int64(1)},
	}, firestore.MergeAll); err != nil {
		return fmt.Errorf("update staff rating aggregate: %w", err)
	}
	fmt.Println("  rating demo-rating-1          5★ for demo-staff-amelia")
	return nil
}

func deleteAll(ctx context.Context, authClient *firebaseauth.Client, db *firestore.Client, users []demoUser) error {
	// Chat messages are a subcollection, so they need removing before the
	// parent session document.
	msgs := db.Collection("chatSessions").Doc("demo-session").Collection("messages").Documents(ctx)
	for {
		d, err := msgs.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return fmt.Errorf("iterate messages: %w", err)
		}
		if _, err := d.Ref.Delete(ctx); err != nil {
			return fmt.Errorf("delete message: %w", err)
		}
	}

	docs := []struct{ Collection, ID string }{
		{"chatSessions", "demo-session"},
		{"shifts", "demo-shift-open-baby"},
		{"shifts", "demo-shift-open-toddler"},
		{"shifts", "demo-shift-open-preschool"},
		{"shifts", "demo-shift-booked"},
		{"notifications", "demo-notif-booked"},
		{"notifications", "demo-notif-match"},
		{"notifications", "demo-notif-rating"},
		{"ratings", "demo-rating-1"},
	}
	for _, d := range docs {
		if _, err := db.Collection(d.Collection).Doc(d.ID).Delete(ctx); err != nil {
			return fmt.Errorf("delete %s/%s: %w", d.Collection, d.ID, err)
		}
		fmt.Printf("  deleted %s/%s\n", d.Collection, d.ID)
	}

	for _, u := range users {
		for _, c := range []string{"profiles", "profilesPublic"} {
			if _, err := db.Collection(c).Doc(u.UID).Delete(ctx); err != nil {
				return fmt.Errorf("delete %s/%s: %w", c, u.UID, err)
			}
		}
		if err := authClient.DeleteUser(ctx, u.UID); err != nil {
			fmt.Printf("  warn: delete auth user %s: %v\n", u.UID, err)
		}
		fmt.Printf("  deleted user %s\n", u.UID)
	}
	return nil
}
