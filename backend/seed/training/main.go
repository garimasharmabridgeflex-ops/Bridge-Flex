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

type section struct {
	Heading string
	Body    []string
}

type module struct {
	ID                   string
	Order                int64
	Title                string
	Purpose              string
	ContentOutline       []string
	Sections             []section
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
			Sections: []section{
				{
					Heading: "Why settings are split into rooms",
					Body: []string{
						"A UK nursery is not one big room of mixed ages. It is divided by age band, and the divisions are not arbitrary — they follow the staffing ratios the Early Years Foundation Stage (EYFS) sets in law.",
						"Under twos must have one adult to every three children. Two-year-olds are one to five. Three-year-olds and over are one to eight, or one to thirteen when someone with Qualified Teacher Status or equivalent Level 6 qualification is working directly with them.",
						"This is why you will be told which room you are covering before anything else: the room determines how many children you are responsible for, and the setting is legally required to keep that number correct all day. If you are moved between rooms, both rooms' ratios have to still work.",
					},
				},
				{
					Heading: "Arriving: reception and signing in",
					Body: []string{
						"Every setting has a sign-in system at the entrance, and you use it even for a single day's cover. It is not administration. In a fire evacuation the register is what tells the person at the assembly point who should be in the building.",
						"Near reception you will usually find the key worker board, showing which staff member is the key person for which children, and a parent notice area. Both are worth thirty seconds of your time — the key worker board tells you who to go to about a particular child.",
					},
				},
				{
					Heading: "The baby room (under 2)",
					Body: []string{
						"Expect cots or sleep mats, soft flooring, and a deliberately low-stimulation area. Babies here are doing a great deal of sleeping, feeding and nappy changing, and the room is arranged so those can happen calmly rather than in the middle of noisy play.",
						"At least one member of staff in a baby room must hold a Level 3 qualification and have real experience with under twos. As cover, you are working alongside that person, not replacing them.",
						"Sleep arrangements are a safeguarding matter with specific rules, and they vary by setting. Always ask how this room does sleep checks rather than assuming.",
					},
				},
				{
					Heading: "The toddler room (2 to 3)",
					Body: []string{
						"This room is built for movement and mess: a role-play kitchen corner, a messy play zone, low tables. Two-year-olds are learning through doing, and the layout expects spills.",
						"Nappy changing and early toileting both happen here, often for different children in the same room. Ask where the changing area is and what the setting's recording routine is before you need it.",
					},
				},
				{
					Heading: "The pre-school room (3 to 5)",
					Body: []string{
						"Here you will find a mark-making table, a construction area and a reading corner. These children are getting ready for school, so the resources point at early writing, building and stories.",
						"Adults in this room are expected to extend play rather than supervise it — sitting at child height, asking open questions, joining in. Standing at the edge of the room is the most common thing a new starter gets quiet feedback about.",
					},
				},
				{
					Heading: "Outdoors",
					Body: []string{
						"Most settings run free-flow or timetabled outdoor play in nearly all weather. Expect a mud kitchen, a sensory or planting area, and fencing with gates that latch above child height.",
						"Check the gate and boundary yourself when you first go out. If a gate does not latch properly, tell the room leader immediately — outdoor supervision is where head counts matter most.",
					},
				},
				{
					Heading: "The key person system",
					Body: []string{
						"Every child in an EYFS setting must be assigned a key person. This is a legal requirement, not a nice-to-have.",
						"That person builds the relationship with the child, knows their routines and needs in detail, and is the main point of contact for their family. They also record the child's development.",
						"As temporary cover you will not be anyone's key person, but you need to know who is. If a child is upset, unwell, or a parent asks you something about their development, the key person — or the room leader — is who you go to.",
					},
				},
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
			Sections: []section{
				{
					Heading: "Why the routine matters more than it looks",
					Body: []string{
						"A nursery day looks repetitive from the outside. That repetition is the point: young children regulate their behaviour around a predictable rhythm, and most difficult moments in a day happen at transitions, not during activities.",
						"As cover, you are the one person who does not know the rhythm. Learning it in the first hour is the single most useful thing you can do — it is the difference between following the room and holding it up.",
						"Timings below are a typical shape. Every setting varies, and yours will differ by fifteen or twenty minutes in places. Always check the room's own routine, which is usually displayed on the wall.",
					},
				},
				{
					Heading: "Morning: arrival to snack",
					Body: []string{
						"Arrival (roughly 7:30–8:30) is staggered as parents drop off. Free play is set out deliberately so children can join at any point without interrupting anything. Handovers happen here — a parent may tell you their child slept badly or is teething, and that information needs passing to the key person.",
						"Breakfast follows where the setting offers it, then circle time and the register at around 9:00. Circle time is short and settles the group; the register is a safeguarding record of exactly who is present.",
						"Mid-morning is the main structured activity, linked to the EYFS areas of learning. Snack at around 10:15 is usually a rolling or seated small-group affair depending on the room.",
					},
				},
				{
					Heading: "Late morning: outdoors and story",
					Body: []string{
						"Outdoor play is typically the late-morning block. Count the children as they go out and as they come back in, every time, without waiting to be asked.",
						"Story or song time before lunch is doing a specific job: it brings the energy down so that lunch is calm. If you are asked to lead it, slower and quieter is almost always right.",
					},
				},
				{
					Heading: "Lunch and the changeover",
					Body: []string{
						"Lunch is around midday, at low tables in small groups, with staff sitting with the children rather than standing over them.",
						"Allergies are checked before food is served, every single time, against the room's allergy list. Never rely on memory or on what someone told you yesterday. If you are unsure about a child's dietary needs, ask a senior member of staff before serving.",
						"Nappy changes and toileting follow lunch, and this is also when staff lunch breaks are covered — so the room's staffing shifts around. Expect to be asked to hold the room briefly.",
					},
				},
				{
					Heading: "Afternoon: sleep and quiet",
					Body: []string{
						"Babies and toddlers sleep in the early afternoon. Sleeping children must be checked at the interval your setting specifies and the checks recorded. Ask what that interval is — it is a safeguarding requirement and it varies.",
						"Pre-school children do not usually nap. They have quiet activities instead, which still need an adult engaged with them rather than supervising from a distance.",
						"Afternoon snack, a second activity or free play block, and tea follow, then a wind-down into home time from about 16:30.",
					},
				},
				{
					Heading: "Handover at the end of the day",
					Body: []string{
						"Children are collected at staggered times, and each collection is a handover: what the child ate, how they slept, anything notable.",
						"If something happened that a parent should know about — a bump, a difficult moment, a first — make sure the key person or room leader has it before you leave. As cover you may not be there tomorrow, so anything only you know is lost when you go.",
					},
				},
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

		sections := make([]map[string]any, 0, len(m.Sections))
		for _, sec := range m.Sections {
			sections = append(sections, map[string]any{"heading": sec.Heading, "body": sec.Body})
		}

		doc := map[string]any{
			"order":                m.Order,
			"title":                m.Title,
			"purpose":              m.Purpose,
			"contentOutline":       m.ContentOutline,
			"sections":             sections,
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
