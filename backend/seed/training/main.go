// Command training seeds the trainingModules collection with Phase 1 of the
// Bridge Flex Training & Onboarding Modules spec: Module 1 (What a UK Nursery
// Looks Like) and Module 2 (Nursery Daily Routine).
//
// Content outlines and purposes are taken verbatim from the spec. The
// knowledge-check questions are NOT in the spec — the spec only mandates
// "4–5 questions" per module — so the ones below are a first draft written
// from each module's own content, to be reviewed and edited in the admin
// screens rather than treated as final.
//
// Usage:
//
//	gcloud auth application-default login
//	cd backend/seed && go run ./training -project kvision-503115
//	cd backend/seed && go run ./training -project kvision-503115 -unpublish
//
// Re-runnable: modules are written by fixed id, so editing this file and
// re-running updates them in place.
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"time"

	firebase "firebase.google.com/go/v4"
)

// Uploaded to Firebase Storage under training-videos/. The app resolves these
// with getDownloadURL(), so replacing the file at the same path swaps the
// video for everyone without touching Firestore.
const (
	module1Video = "training-videos/module-1-uk-nursery.mp4"
	module2Video = "training-videos/module-2-daily-routine.mp4"
)

type question struct {
	ID           string
	Prompt       string
	Options      []string
	CorrectIndex int64
	Explanation  string
}

type module struct {
	ID                   string
	Order                int64
	Title                string
	Purpose              string
	ContentOutline       []string
	VideoStoragePath     string
	VideoDurationSeconds int64
	PassMark             int64
	Questions            []question
}

func modules() []module {
	return []module{
		{
			ID:    "module-1-uk-nursery",
			Order: 1,
			Title: "What a UK Nursery Looks Like",
			Purpose: "Orient a new starter visually — what the rooms look like, how they're divided by age " +
				"group, and what equipment and layout to expect on arrival.",
			ContentOutline: []string{
				"Entrance / reception area — sign-in system, key worker boards, parent notice area",
				"Baby room (0–2 years) — cots, soft flooring, low-stimulation sensory area",
				"Toddler room (2–3 years) — role-play kitchen corner, messy play zone",
				"Preschool room (3–5 years) — mark-making table, construction area, reading corner",
				"Outdoor area — mud kitchen, sensory garden, safety fencing and gates",
				"Key adults — the key worker system and how staff are identified",
			},
			VideoStoragePath:     module1Video,
			VideoDurationSeconds: 60,
			PassMark:             4,
			Questions: []question{
				{
					ID:      "q1",
					Prompt:  "Which age group is the baby room for?",
					Options: []string{"0–2 years", "2–3 years", "3–5 years", "5–7 years"},
					// Index 0 is the correct answer here on purpose — the API
					// never sends correctIndex to a practitioner, so a
					// first-option answer gives nothing away.
					CorrectIndex: 0,
					Explanation:  "Baby rooms take children from around 3 months to 2 years.",
				},
				{
					ID:           "q2",
					Prompt:       "Where would you expect to find a role-play kitchen corner and a messy play zone?",
					Options:      []string{"The baby room", "The toddler room", "The reception area", "The staff room"},
					CorrectIndex: 1,
					Explanation:  "The toddler room (2–3 years) is set up for role play and messy play.",
				},
				{
					ID:           "q3",
					Prompt:       "A mark-making table, construction area and reading corner are typical of which room?",
					Options:      []string{"The baby room", "The toddler room", "The preschool room", "The outdoor area"},
					CorrectIndex: 2,
					Explanation:  "These support the 3–5 age group's early writing, building and literacy.",
				},
				{
					ID:     "q4",
					Prompt: "What is the key worker system?",
					Options: []string{
						"A rota deciding who opens and closes the nursery",
						"A named member of staff responsible for particular children and their families",
						"The system parents use to sign children in and out",
						"The manager on duty for the day",
					},
					CorrectIndex: 1,
					Explanation:  "Each child has a key worker who knows them well and is the main point of contact for their family.",
				},
				{
					ID:     "q5",
					Prompt: "On arriving at a setting for the first time, what should you expect to do at reception?",
					Options: []string{
						"Go straight to the room you are covering",
						"Sign in, and check the key worker board and parent notices",
						"Wait outside until a parent lets you in",
						"Collect the children from the outdoor area",
					},
					CorrectIndex: 1,
					Explanation:  "Signing in is a safeguarding and fire-safety requirement in every setting.",
				},
			},
		},
		{
			ID:    "module-2-daily-routine",
			Order: 2,
			Title: "Nursery Daily Routine",
			Purpose: "Give a new starter a clear sense of how the day flows, so there's no confusion once " +
				"they're on the floor or settling in with a room.",
			ContentOutline: []string{
				"Timings vary slightly between settings — always check the room's own routine on arrival",
				"7:30–8:30 — Arrival, sign-in, free play",
				"8:30–9:00 — Breakfast (if offered)",
				"9:00–9:15 — Morning circle time / register",
				"9:15–10:15 — Structured activity (EYFS-linked)",
				"10:15–10:45 — Snack time",
				"10:45–11:30 — Outdoor play",
				"11:30–12:00 — Story / song time",
				"12:00–12:45 — Lunch",
				"12:45–13:00 — Nappy changes / toileting",
				"13:00–14:30 — Nap time (babies/toddlers) / quiet activities (preschool)",
				"14:30–15:00 — Afternoon snack",
				"15:00–16:00 — Free play / afternoon activity",
				"16:00–16:30 — Tea time",
				"16:30–18:00 — Free play, wind-down, home time",
			},
			VideoStoragePath:     module2Video,
			VideoDurationSeconds: 60,
			PassMark:             4,
			Questions: []question{
				{
					ID:           "q1",
					Prompt:       "What normally follows arrival and free play at the start of the day?",
					Options:      []string{"Outdoor play", "Breakfast, then morning circle time and the register", "Lunch", "Nap time"},
					CorrectIndex: 1,
					Explanation:  "Breakfast (where offered) is followed by circle time and the register.",
				},
				{
					ID:           "q2",
					Prompt:       "Roughly when does the main structured, EYFS-linked activity usually take place?",
					Options:      []string{"Mid-morning, after circle time", "First thing, before arrival", "Straight after lunch", "At home time"},
					CorrectIndex: 0,
					Explanation:  "The structured activity typically runs mid-morning, around 9:15–10:15.",
				},
				{
					ID:     "q3",
					Prompt: "During nap time, what usually happens with the preschool room?",
					Options: []string{
						"They nap at the same time as the babies",
						"They go home early",
						"They do quiet activities instead of napping",
						"They stay outdoors",
					},
					CorrectIndex: 2,
					Explanation:  "Babies and toddlers nap; preschool children generally do quiet activities.",
				},
				{
					ID:     "q4",
					Prompt: "The routine you have just seen should be treated as:",
					Options: []string{
						"A legal requirement identical in every nursery",
						"A typical shape — timings vary between settings, so check the room's own routine",
						"Only relevant to baby rooms",
						"A guide for parents rather than staff",
					},
					CorrectIndex: 1,
					Explanation:  "Every setting runs its own variation. Always check the room's routine when you arrive.",
				},
				{
					ID:           "q5",
					Prompt:       "Which of these normally comes immediately after lunch?",
					Options:      []string{"Outdoor play", "Nappy changes and toileting", "Breakfast", "Home time"},
					CorrectIndex: 1,
					Explanation:  "Nappy changes and toileting bridge lunch and the nap/quiet period.",
				},
			},
		},
	}
}

func main() {
	projectID := flag.String("project", "kvision-503115", "Firebase project ID to write to")
	unpublish := flag.Bool("unpublish", false, "hide the modules from practitioners instead of publishing them")
	flag.Parse()

	if os.Getenv("FIRESTORE_EMULATOR_HOST") != "" {
		log.Fatal("FIRESTORE_EMULATOR_HOST is set — unset it to write to the real project")
	}

	ctx := context.Background()
	app, err := firebase.NewApp(ctx, &firebase.Config{ProjectID: *projectID})
	if err != nil {
		log.Fatalf("firebase.NewApp: %v (did you run `gcloud auth application-default login`?)", err)
	}
	db, err := app.Firestore(ctx)
	if err != nil {
		log.Fatalf("app.Firestore: %v", err)
	}
	defer db.Close()

	now := time.Now()
	for _, m := range modules() {
		ref := db.Collection("trainingModules").Doc(m.ID)

		createdAt := now
		if snap, err := ref.Get(ctx); err == nil {
			if t, ok := snap.Data()["createdAt"].(time.Time); ok {
				createdAt = t
			}
		}

		questions := make([]map[string]any, 0, len(m.Questions))
		for _, q := range m.Questions {
			questions = append(questions, map[string]any{
				"id":           q.ID,
				"prompt":       q.Prompt,
				"options":      q.Options,
				"correctIndex": q.CorrectIndex,
				"explanation":  q.Explanation,
			})
		}

		doc := map[string]any{
			"order":                m.Order,
			"title":                m.Title,
			"purpose":              m.Purpose,
			"contentOutline":       m.ContentOutline,
			"videoStoragePath":     m.VideoStoragePath,
			"videoDurationSeconds": m.VideoDurationSeconds,
			"questions":            questions,
			"passMark":             m.PassMark,
			"published":            !*unpublish,
			"createdAt":            createdAt,
			"updatedAt":            now,
		}
		if _, err := ref.Set(ctx, doc); err != nil {
			log.Fatalf("write trainingModules/%s: %v", m.ID, err)
		}
		state := "published"
		if *unpublish {
			state = "unpublished"
		}
		fmt.Printf("  %-24s %-32s %d questions, pass %d/%d  [%s]\n",
			m.ID, m.Title, len(m.Questions), m.PassMark, len(m.Questions), state)
	}

	fmt.Println("\nVideos are read from Firebase Storage at:")
	fmt.Printf("  %s\n  %s\n", module1Video, module2Video)
	fmt.Println("Replacing the file at either path swaps the video for every practitioner —")
	fmt.Println("no Firestore edit needed.")
}
