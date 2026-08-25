// Command training seeds the trainingModules collection with all 9 modules of
// the KFlex Training & Onboarding Modules spec across Phase 1, Phase 2, and Phase 3.
//
// Modules:
//   Phase 1:
//     Module 1 - What a UK Nursery Looks Like (module-1-uk-nursery)
//     Module 2 - Nursery Daily Routine (module-2-daily-routine)
//   Phase 2:
//     Module 3 - Choking & Safety Hazards (module-3-choking-safety)
//     Module 4 - Mealtime Routines & Etiquette (module-4-mealtime-routines)
//     Module 5 - Play & Activity Time (module-5-play-activity-time)
//   Phase 3:
//     Module 6 - EYFS Overview & Key Stages (module-6-eyfs-overview)
//     Module 7 - Early Communication & Language (module-7-early-communication-language)
//     Module 8 - Nursery Rhymes & Songs Library (module-8-nursery-rhymes-songs)
//     Module 9 - Communicating with Children from Diverse Family Backgrounds (module-9-diverse-family-backgrounds)
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
	module3Video = "training-videos/module-3-choking-safety.mp4"
	module4Video = "training-videos/module-4-mealtime-routines.mp4"
	module5Video = "training-videos/module-5-play-activity-time.mp4"
	module6Video = "training-videos/module-6-eyfs-overview.mp4"
	module7Video = "training-videos/module-7-early-communication-language.mp4"
	module8Video = "training-videos/module-8-nursery-rhymes-songs.mp4"
	module9Video = "training-videos/module-9-diverse-family-backgrounds.mp4"

	module1Url = "https://firebasestorage.googleapis.com/v0/b/kvision-503115.firebasestorage.app/o/training-videos%2Fmodule-1-uk-nursery.mp4?alt=media&token=c55e2b7d-8e5d-441d-8ff5-7753b8171bdc"
	module2Url = "https://firebasestorage.googleapis.com/v0/b/kvision-503115.firebasestorage.app/o/training-videos%2Fmodule-2-daily-routine.mp4?alt=media&token=fed975a4-95b6-4efc-83bc-13103ef805af"
	module3Url = "https://firebasestorage.googleapis.com/v0/b/kvision-503115.firebasestorage.app/o/training-videos%2Fmodule-3-choking-safety.mp4?alt=media&token=66685d02-015a-41ca-b94c-40a1a7b026fd"
	module4Url = "https://firebasestorage.googleapis.com/v0/b/kvision-503115.firebasestorage.app/o/training-videos%2Fmodule-4-mealtime-routines.mp4?alt=media&token=cf4e03da-9e1d-4658-a543-0229b3d84fd3"
	module5Url = "https://firebasestorage.googleapis.com/v0/b/kvision-503115.firebasestorage.app/o/training-videos%2Fmodule-5-play-activity-time.mp4?alt=media&token=8d5b3712-c548-4f19-85cd-7f4c0383d860"
	module6Url = "https://firebasestorage.googleapis.com/v0/b/kvision-503115.firebasestorage.app/o/training-videos%2Fmodule-6-eyfs-overview.mp4?alt=media&token=3b3c16d6-5a19-4c99-bcf4-30e82e4c70ac"
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
	VideoURL             string
	VideoDurationSeconds int64
	PassMark             int64
	Questions            []question
}

func modules() []module {
	return []module{
		// ─── Phase 1 ─────────────────────────────────────────────────────────────
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
			VideoURL:             module1Url,
			VideoDurationSeconds: 50,
			PassMark:             4,
			Questions: []question{
				{
					ID:           "q1",
					Prompt:       "Which age group is the baby room for?",
					Options:      []string{"0–2 years", "2–3 years", "3–5 years", "5–7 years"},
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
			VideoURL:             module2Url,
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

		// ─── Phase 2 ─────────────────────────────────────────────────────────────
		{
			ID:    "module-3-choking-safety",
			Order: 3,
			Title: "Choking & Safety Hazards",
			Purpose: "Every practitioner must recognise choking and everyday safety hazards immediately — " +
				"this is a core safeguarding requirement, not optional viewing.",
			ContentOutline: []string{
				"Common choking hazards by age group — small toys, whole grapes/cherry tomatoes, nuts, hard sweets, coins, balloons",
				"Safe food preparation — cutting round foods lengthways into quarters, age-appropriate portion sizes and textures",
				"Recognising a choking child — signs of distress, silent choking (complete obstruction) vs. coughing (partial obstruction)",
				"Immediate response — back blows, chest thrusts (under 1s) and abdominal thrusts (over 1s) per paediatric first aid guidance, calling for senior staff, when to call 999",
				"Other everyday hazards — trailing cords, hot drinks in reach, unsecured furniture, cleaning products",
				"Reporting — how an incident or near-miss must be logged and reported to the room leader/manager",
			},
			Sections: []section{
				{
					Heading: "High-risk foods and choking items",
					Body: []string{
						"Choking is one of the leading causes of accidental injury in children under five. Their airways are narrow (roughly the width of a drinking straw in toddlers), and their chewing and swallowing reflexes are still developing.",
						"High-risk foods include round, firm items: whole grapes, cherry tomatoes, large blueberries, hot dogs, sausages, raw carrots, whole nuts, popcorn, and hard sweets. Non-food items like uninflated balloons, coins, button batteries, and small toy parts are equally dangerous.",
						"Never offer whole round foods to children under five without modifying them first.",
					},
				},
				{
					Heading: "Safe food preparation and texture guidelines",
					Body: []string{
						"Grapes, cherry tomatoes, and large soft fruits must always be sliced lengthways into quarters (four long pieces), never chopped widthways into circular discs which can still plug a windpipe.",
						"Sausages and hot dogs must be cut lengthways down the middle before slicing into small half-moons. Hard vegetables like carrots and apples should be grated, steamed soft, or cut into thin batons.",
						"Always ensure children sit down while eating or drinking — running, laughing, or lying down while chewing dramatically increases choking risks.",
					},
				},
				{
					Heading: "Recognising choking: Silent distress vs coughing",
					Body: []string{
						"Partial airway obstruction: The child is coughing, wheezing, or crying. They can breathe and vocalise. In this case, DO NOT pat their back or interfere — encourage them to cough forcefully to clear the obstruction themselves.",
						"Complete airway obstruction (True Emergency): The child CANNOT breathe, cry, speak, or make any sound. They may clutch their throat with both hands (the universal choking sign), their face may turn red or blue, and eyes may widen with panic. You must act immediately.",
					},
				},
				{
					Heading: "Paediatric First Aid immediate response",
					Body: []string{
						"For children over 1 year: Deliver up to 5 sharp back blows between the shoulder blades with the heel of your hand while supporting their chest leaning forward. If cleared, stop. If not, stand behind them, place a fist above the navel and below the ribcage, and deliver up to 5 sharp inward and upward abdominal thrusts. Alternate 5 back blows and 5 abdominal thrusts.",
						"For infants under 1 year: Support the baby face down along your forearm/thigh with head lower than bottom, and give up to 5 firm back blows. If still blocked, turn baby face up on your thigh and give up to 5 sharp chest thrusts using two fingers on the breastbone. NEVER do abdominal thrusts on a baby under 1.",
						"Call out loudly for help immediately so a colleague can dial 999. If the child becomes unresponsive, start paediatric CPR immediately (5 initial rescue breaths followed by 30 compressions and 2 breaths).",
					},
				},
				{
					Heading: "Everyday nursery room safety hazards",
					Body: []string{
						"Hot drinks (tea, coffee) are strictly forbidden in children's rooms and corridors when children are present. Any hot beverage must remain in the designated staff room.",
						"Blind cords, trailing electrical cables, and appliance wires must be secured out of reach to eliminate strangulation risks.",
						"Cleaning chemicals (bleach, sprays, sanitising tabs) must always be locked inside high COSHH cupboards, never left on low worktops or sinks.",
						"Heavy furniture (bookcases, shelving units, storage units) must be securely anchored to walls to prevent tip-over accidents when children climb.",
					},
				},
				{
					Heading: "Incident reporting and near-miss logging",
					Body: []string{
						"Every accident, injury, or choking incident — even if resolved quickly without hospitalisation — must be documented immediately on the setting's official Accident / Incident Form and reported to the room leader.",
						"Parents must be informed on the same day and asked to sign the accident record.",
						"Near-misses (such as finding a loose button battery or an unlocked chemical cupboard) must also be recorded so management can review safety procedures and eliminate risks before harm occurs.",
					},
				},
			},
			VideoStoragePath:     module3Video,
			VideoURL:             module3Url,
			VideoDurationSeconds: 50,
			PassMark:             4,
			Questions: []question{
				{
					ID:           "q1",
					Prompt:       "How must round foods like grapes and cherry tomatoes be prepared for young children in a UK nursery?",
					Options:      []string{"Served whole to develop chewing strength", "Cut widthways into circular coins", "Cut lengthways into quarters", "Peeled and mashed into paste only"},
					CorrectIndex: 2,
					Explanation:  "Cutting lengthways into quarters prevents the fruit from forming a tight circular plug in the child's trachea.",
				},
				{
					ID:           "q2",
					Prompt:       "A toddler is coughing loudly while eating an apple slice. What is the correct initial action?",
					Options:      []string{"Give 5 immediate back blows", "Encourage them to cough and observe closely without interfering", "Perform abdominal thrusts immediately", "Offer a large drink of water"},
					CorrectIndex: 1,
					Explanation:  "If the child is coughing effectively, their airway is only partially blocked. Coughing is the most effective way to clear it; do not interfere.",
				},
				{
					ID:           "q3",
					Prompt:       "What is the immediate Paediatric First Aid procedure for a choking child over 1 year who cannot make any sound or breathe?",
					Options:      []string{"Up to 5 sharp back blows, followed by up to 5 abdominal thrusts", "Blind finger sweep of the throat", "Turn the child upside down by the ankles", "Give them back blows while lying flat on their back"},
					CorrectIndex: 0,
					Explanation:  "Support the forward-leaning child and deliver up to 5 back blows between the shoulder blades, followed by up to 5 abdominal thrusts if needed.",
				},
				{
					ID:           "q4",
					Prompt:       "What is the statutory rule regarding hot beverages (tea and coffee) in early years settings?",
					Options:      []string{"Allowed in mugs with handles in toddler rooms", "Allowed if kept on tables above 1 meter", "Strictly prohibited in rooms and corridors where children are present", "Only allowed during morning arrival"},
					CorrectIndex: 2,
					Explanation:  "Hot drinks are a leading cause of severe scalds and must never be brought into or left in children's areas.",
				},
				{
					ID:           "q5",
					Prompt:       "Why is it mandatory to report and log a 'near-miss' safety incident even if no child was harmed?",
					Options:      []string{"To assign blame to the staff member on duty", "To identify hazards early and prevent future serious accidents", "It is only required if Ofsted visits that day", "To reduce the room's staffing ratio"},
					CorrectIndex: 1,
					Explanation:  "Near-miss reporting helps settings identify safety risks and fix them before an actual injury occurs.",
				},
			},
		},
		{
			ID:    "module-4-mealtime-routines",
			Order: 4,
			Title: "Mealtime Routines & Etiquette",
			Purpose: "Explain how mealtimes actually run in a UK nursery — seating, portioning, independence-building, " +
				"and hygiene — so a new starter can step straight into supporting a meal.",
			ContentOutline: []string{
				"Before the meal — handwashing routine for children and staff, wiping tables with food-safe sanitizer, setting out plates/cups",
				"Seating — small groups at low tables, key worker or assigned staff sitting with children, not standing over them",
				"Serving — age-appropriate portions, encouraging children to self-serve where possible (spooning, pouring from small jugs)",
				"Supporting independence — letting children use cutlery appropriate to age, praising effort rather than rushing",
				"Allergies and dietary needs — checking the room's allergy list before serving, never assuming, always double-checking with senior staff",
				"Conversation and modelling — staff talking with children during the meal, modelling manners (please, thank you), not supervising in silence",
				"After the meal — clearing away, wiping faces and hands, toileting/nappy changes, brief quiet time before the next activity",
			},
			Sections: []section{
				{
					Heading: "Pre-meal preparation and hygiene standards",
					Body: []string{
						"Mealtimes are not just for nutrition; they are primary social learning and self-regulation routines in the EYFS.",
						"Tables must be cleaned using a two-stage process: first with detergent/warm water to remove food debris, then with a food-safe antibacterial sanitizer left for the contact time specified on the bottle.",
						"Both staff and children must thoroughly wash their hands with warm water and liquid soap before sitting at the table, drying with disposable paper towels.",
					},
				},
				{
					Heading: "Seating at child level and social dining",
					Body: []string{
						"In UK nurseries, children sit in small groups at low tables with appropriately sized chairs where their feet can touch the floor.",
						"Staff members must sit down alongside the children on low chairs at eye level. Standing over children or supervising from across the room creates an institutional feel and prevents meaningful interaction.",
						"Sitting with children allows you to monitor eating pace, encourage communication, spot any choking or allergic reactions instantly, and model polite mealtime behaviour.",
					},
				},
				{
					Heading: "Fostering independence and self-service",
					Body: []string{
						"Children should be empowered to participate actively in their meals. Toddlers and preschoolers should be encouraged to spoon food from serving bowls, pass bread baskets, and pour water from small, lightweight jugs.",
						"Provide age-appropriate cutlery (child-safe metal or sturdy plastic forks and spoons). Expect spills and mess — treat spills calmly as natural learning opportunities without reprimand.",
						"Allow children to listen to their own hunger cues. Never force a child to clean their plate, and never use dessert as a bribe or punishment for eating vegetables.",
					},
				},
				{
					Heading: "Allergy management and dietary safety",
					Body: []string{
						"Food allergies can be life-threatening. Every room has a designated Allergy / Dietary Board or placemat system listing every child with allergies, intolerances, or religious dietary requirements.",
						"The Golden Rule: ALWAYS check the room allergy chart before handing a plate or cup to any child. Never assume food is safe based on appearance.",
						"Never swap food between children. Children with severe allergies must have their food prepared and plated separately in colour-coded crockery.",
						"If you have any doubt whatsoever about an ingredient or a child's dietary status, stop and confirm with the Room Leader or Nursery Chef before serving.",
					},
				},
				{
					Heading: "Role-modelling manners and table conversation",
					Body: []string{
						"Mealtimes are prime opportunities for language development (EYFS Communication & Language). Talk naturally about the food's colors, textures, flavors, and origins ('These carrots are crunchy and sweet!').",
						"Model polite social manners consistently: say 'please' and 'thank you', wait your turn, use a quiet conversational indoor voice, and encourage children to ask for seconds politely.",
					},
				},
				{
					Heading: "Post-meal clearing, toileting, and transition",
					Body: []string{
						"Children should be encouraged to scrape their leftover food into a compost/scrap bowl and stack their plates and cups in a designated basin.",
						"Clean faces and hands with damp wipes or warm washcloths. Ensure children wash their hands after eating.",
						"Immediately following the meal, transition children smoothly to toileting and nappy changing. Mealtimes are followed by a calm, quiet wind-down period (nap time for toddlers, quiet books or puzzles for preschoolers).",
					},
				},
			},
			VideoStoragePath:     module4Video,
			VideoURL:             module4Url,
			VideoDurationSeconds: 60,
			PassMark:             4,
			Questions: []question{
				{
					ID:           "q1",
					Prompt:       "Where should nursery practitioners position themselves during children's mealtimes?",
					Options:      []string{"Standing at the classroom door observing", "Sitting down at low tables alongside the children at eye level", "Cleaning the sink area away from the tables", "Sitting at a separate adult desk doing paperwork"},
					CorrectIndex: 1,
					Explanation:  "Staff should sit with children to model social skills, facilitate conversation, and closely monitor safety.",
				},
				{
					ID:           "q2",
					Prompt:       "What is the mandatory procedure before serving any meal or snack to a child?",
					Options:      []string{"Ask the child what they are allergic to", "Check the room's official allergy and dietary list every single time", "Smell the food to check for nuts", "Assume all children can eat the general menu"},
					CorrectIndex: 1,
					Explanation:  "Practitioners must verify every meal against the official allergy register before serving to avoid severe allergic reactions.",
				},
				{
					ID:           "q3",
					Prompt:       "How should a practitioner handle a toddler spilling water while trying to pour from a small jug?",
					Options:      []string{"Scold the child and take the jug away immediately", "Reassure the child calmly, provide a cloth, and help them wipe it up", "Put the child in time-out for careless behaviour", "Ban the child from pouring for the rest of the week"},
					CorrectIndex: 1,
					Explanation:  "Spills are a normal part of building independence and fine motor skills. Handling spills calmly encourages resilience and learning.",
				},
				{
					ID:           "q4",
					Prompt:       "Which approach aligns with EYFS best practice regarding children finishing their food?",
					Options:      []string{"Insisting children finish all vegetables before getting dessert", "Forcing a child to sit until their plate is completely empty", "Encouraging children gently while respecting their self-regulation and fullness cues", "Removing dessert if a child eats slowly"},
					CorrectIndex: 2,
					Explanation:  "Children should be encouraged to listen to their own hunger and satiety cues without force or using food as rewards/punishment.",
				},
				{
					ID:           "q5",
					Prompt:       "What is the correct two-stage table cleaning routine before mealtimes?",
					Options:      []string{"Dry dusting with a paper towel only", "Cleaning with detergent to remove debris, then applying food-safe sanitizer", "Spraying air freshener over the tables", "Wiping once with cold water"},
					CorrectIndex: 1,
					Explanation:  "Food surfaces must be cleaned first with detergent to remove grease and food particles, followed by an approved food-safe disinfectant.",
				},
			},
		},
		{
			ID:    "module-5-play-activity-time",
			Order: 5,
			Title: "Play & Activity Time",
			Purpose: "Help a new starter understand what 'good' play support looks like — not just supervising, " +
				"but engaging, extending, and linking play to learning.",
			ContentOutline: []string{
				"Types of play — free play, adult-led structured activity, adult-guided small group activity, outdoor exploratory play",
				"Role of the adult — getting down to the child's level, following their lead, asking open questions rather than closed ones",
				"Setting up an activity area — rotating resources, keeping areas inviting and age-appropriate, tidying as you go",
				"Supporting different ages in the same session — adapting the same activity for a 2-year-old vs. a 4-year-old",
				"Linking play to learning — briefly noting which EYFS area an activity supports (fine motor, communication, personal-social)",
				"Transitions — how staff signal the end of an activity (tidy-up song, visual timer) and move the group to the next part of the routine",
			},
			Sections: []section{
				{
					Heading: "Understanding the spectrum of play in early years",
					Body: []string{
						"Play is the primary vehicle through which young children learn, explore, problem-solve, and develop social-emotional skills.",
						"Child-Initiated Free Play: The child chooses what to play with, how to play, and for how long. The adult supports by providing rich resources and entering play sensitively when invited.",
						"Adult-Led Structured Activities: The adult introduces a specific learning goal (e.g. baking bread, a scientific sink-or-float experiment, learning a structured group game).",
						"Adult-Guided / Scaffolding: The adult notices what the child is trying to achieve and offers gentle guidance, tools, or questions to help them reach the next step.",
					},
				},
				{
					Heading: "The adult's role: Being present at eye level",
					Body: []string{
						"High-quality adult interaction requires being down at the child's physical eye level (sitting on the carpet, kneeling, or using low stools).",
						"Follow the child's lead rather than taking over their game. If a child is building a tower, observe what they are doing before jumping in.",
						"Use open-ended questions that provoke thinking, curiosity, and language ('What do you think will happen if...?', 'How could we make this stronger?', 'Tell me about your painting') rather than closed testing questions ('What colour is this?').",
					},
				},
				{
					Heading: "Continuous provision and inviting learning spaces",
					Body: []string{
						"Continuous Provision refers to the permanent learning zones available throughout the day: construction corner, mark-making and writing table, role-play home corner, messy/sensory trays (sand, water, foam), and reading nooks.",
						"Resources should be accessible in low, clearly labelled baskets (using pictures and words) so children can choose and return materials independently.",
						"Encourage 'tidying as we go' so areas remain inviting rather than turning into chaotic hazards.",
					},
				},
				{
					Heading: "Differentiating activities across developmental stages",
					Body: []string{
						"The same activity should be adapted for different ages and developmental abilities in the room.",
						"Example with Playdough: For a 2-year-old, the focus is sensory exploration (squishing, rolling, pounding, developing hand strength). For a 4-year-old, introduce rolling pins, cutters, number cards, or small loose parts to create detailed creatures or count dough balls.",
						"Example with Water Play: 2-year-olds practice pouring between cups; 4-year-olds explore buoyancy, measuring volume with marked containers, and using pipes/funnels.",
					},
				},
				{
					Heading: "Linking play to EYFS learning areas",
					Body: []string{
						"Every rich activity supports multiple areas of the EYFS:",
						"Building with wooden blocks supports Physical Development (fine and gross motor control), Mathematics (shapes, balance, size comparison), and PSED (cooperation and sharing with peers).",
						"Role play in the kitchen corner fosters Communication & Language (dialogue, vocabulary), Expressive Arts & Design (imaginative storytelling), and Understanding the World (family roles, culture).",
					},
				},
				{
					Heading: "Managing smooth transitions",
					Body: []string{
						"Abruptly telling children to stop playing causes frustration and emotional outbursts. Always give advance warnings (e.g. '5 minutes left before tidy-up time').",
						"Use clear auditory and visual signals: a rhythmic tidy-up song, a chime, or a sand timer.",
						"Turn tidying into an engaging game (e.g. 'Can we find all the blue bricks before the song ends?'). Acknowledge and praise children's teamwork during transitions.",
					},
				},
			},
			VideoStoragePath:     module5Video,
			VideoURL:             module5Url,
			VideoDurationSeconds: 60,
			PassMark:             4,
			Questions: []question{
				{
					ID:           "q1",
					Prompt:       "Which question is the best example of an open-ended prompt that extends a child's learning during play?",
					Options:      []string{"What colour is that block?", "Is this car fast? Yes or no?", "How could we build the bridge so the big dinosaur fits underneath?", "Can you say 'red'?"},
					CorrectIndex: 2,
					Explanation:  "Open-ended questions encourage problem solving, critical thinking, and expressive language rather than one-word recall.",
				},
				{
					ID:           "q2",
					Prompt:       "What does 'Continuous Provision' mean in an EYFS nursery setting?",
					Options:      []string{"A non-stop timetable with no break times", "Carefully resourced learning areas available for children to explore independently throughout the day", "Continuous testing of children's academic scores", "Staff working without breaks"},
					CorrectIndex: 1,
					Explanation:  "Continuous provision provides an environment where children can access resources independently and build upon their own play ideas.",
				},
				{
					ID:           "q3",
					Prompt:       "How should a practitioner adapt a playdough activity for a 4-year-old compared to a 2-year-old?",
					Options:      []string{"Forbid the 4-year-old from touching the dough", "Add tools, cutters, and loose parts to support early math, storytelling, and intricate design", "Make the 4-year-old sit quietly without speaking", "Use the exact same single ball of dough without any additional tools"},
					CorrectIndex: 1,
					Explanation:  "Older children benefit from additional tools, challenges, and props that extend fine motor precision, creativity, and mathematical thinking.",
				},
				{
					ID:           "q4",
					Prompt:       "What is the best strategy to signal the end of activity time without causing upset?",
					Options:      []string{"Suddenly turn off all lights without warning", "Give a 5-minute advance warning, followed by a familiar tidy-up song or visual timer", "Take away toys while children are actively using them", "Shout loudly from across the room"},
					CorrectIndex: 1,
					Explanation:  "Advance warnings and routine audio/visual signals help young children transition smoothly between activities.",
				},
				{
					ID:           "q5",
					Prompt:       "When observing a child deeply engrossed in building a block tower, what should the adult do first?",
					Options:      []string{"Dismantle the tower to test their emotional resilience", "Observe carefully at their physical level before deciding whether to join in or let them lead", "Immediately take over and build the tower for them", "Tell them to go to a different activity area"},
					CorrectIndex: 1,
					Explanation:  "Observation at the child's level allows you to understand their goal and support them without interrupting their concentration.",
				},
			},
		},

		// ─── Phase 3 ─────────────────────────────────────────────────────────────
		{
			ID:    "module-6-eyfs-overview",
			Order: 6,
			Title: "EYFS Overview & Key Stages",
			Purpose: "Give every practitioner — temp or permanent — the essential statutory knowledge they need " +
				"to work safely and correctly in an EYFS-regulated setting: the ratios, the safeguarding basics, " +
				"and a proper working understanding of the 7 areas of learning.",
			ContentOutline: []string{
				"What EYFS is — statutory framework introduction (birth to age 5), and why every setting is required to work to it",
				"Staff-to-child ratios, the numbers every practitioner must know: Under 2s 1:3; 2–3 years 1:5; 3–5 years 1:8 (or 1:13 with a qualified teacher)",
				"Health & safety basics — daily risk checks, accident/incident log, allergy awareness, fire evacuation procedure",
				"Safeguarding touchpoint — who to report a concern to, and what the DSL (Designated Safeguarding Lead) role means",
				"The 7 areas of learning: 3 Prime areas (Communication & Language, Physical Development, PSED) and 4 Specific areas (Literacy, Mathematics, Understanding the World, Expressive Arts & Design)",
			},
			Sections: []section{
				{
					Heading: "The Statutory Framework: Purpose and legal status",
					Body: []string{
						"The Early Years Foundation Stage (EYFS) is the mandatory statutory framework in England that sets the standards for learning, development, and care for children from birth to age five.",
						"All registered early years providers (nurseries, preschools, reception classes, childminders) must legally comply with EYFS welfare and learning requirements.",
						"The framework ensures that every child receives quality care, stays safe, and gains the foundational skills needed for a smooth transition to primary school.",
					},
				},
				{
					Heading: "Statutory staff-to-child ratios in England",
					Body: []string{
						"Staffing ratios are legal minimums required at all times (including outings and meals):",
						"• Under 2 years: 1 adult to 3 children (1:3). At least one member of staff must hold a full and relevant Level 3 qualification and have suitable under-twos experience.",
						"• 2-year-olds: 1 adult to 5 children (1:5). At least one staff member must hold Level 3, and at least half of other staff must hold Level 2.",
						"• 3 to 5 years (in non-domestic settings): 1 adult to 8 children (1:8) with a Level 3 lead, OR 1 adult to 13 children (1:13) where a staff member with Qualified Teacher Status (QTS) or Early Years Teacher Status (EYTS) is working directly with children.",
						"If ratios are breached for even a few minutes, the setting is in breach of statutory regulations.",
					},
				},
				{
					Heading: "The 3 Prime Areas of learning (Birth to 5)",
					Body: []string{
						"The 3 Prime Areas are fundamental, universal, and develop first. They ignite children's curiosity and build the capacity to learn:",
						"1. Communication and Language: Listening, attention, understanding, and expressive speech. This is the single highest developmental priority for under-threes.",
						"2. Physical Development: Gross motor skills (crawling, jumping, balancing), fine motor control (holding tools, hand-eye coordination), and self-care (feeding, handwashing, toilet training).",
						"3. Personal, Social and Emotional Development (PSED): Self-regulation, managing feelings and behaviour, building positive relationships, and developing self-confidence.",
					},
				},
				{
					Heading: "The 4 Specific Areas of learning",
					Body: []string{
						"The 4 Specific Areas build on the foundation of the Prime Areas and become increasingly structured as children approach school age (3–5 years):",
						"4. Literacy: Comprehension, sharing books, storytelling, phonological awareness, early mark-making, and letter formation.",
						"5. Mathematics: Counting, subitising, numeral recognition, understanding shape, space, patterns, and measurement.",
						"6. Understanding the World: People and communities, past and present, the natural environment, seasons, and technology.",
						"7. Expressive Arts and Design: Creating with art materials, junk modelling, music, dancing, role-play, and imaginative drama.",
					},
				},
				{
					Heading: "Safeguarding and the Designated Safeguarding Lead (DSL)",
					Body: []string{
						"Safeguarding children is everyone's primary legal duty. Every nursery has a designated senior member of staff known as the Designated Safeguarding Lead (DSL).",
						"If you observe any signs of abuse, neglect, radicalisation, significant behavioral changes, or unexplained injuries, you must report them immediately to the DSL and write a factual, contemporaneous record.",
						"Never promise a child you will 'keep a secret' regarding their safety. Explain gently that you will speak with someone whose job is to keep them safe.",
					},
				},
				{
					Heading: "Daily risk assessments and safety protocols",
					Body: []string{
						"Daily opening and closing checklists: Indoor and outdoor areas must be checked every morning for hazards (broken toys, debris, loose fences, temperature) before children enter.",
						"Accident and Incident Logs: Must record full details of any bump, scrape, or injury, the first aid administered, and the signature of the parent at pickup.",
						"Fire evacuation drills must be practiced regularly, with all registers immediately accounted for at the assembly point.",
					},
				},
			},
			VideoStoragePath:     module6Video,
			VideoURL:             module6Url,
			VideoDurationSeconds: 40,
			PassMark:             4,
			Questions: []question{
				{
					ID:           "q1",
					Prompt:       "What are the three Prime Areas of the Early Years Foundation Stage (EYFS)?",
					Options:      []string{"Literacy, Mathematics, and Science", "Communication & Language, Physical Development, and PSED", "Art, Music, and Drama", "Geography, History, and Technology"},
					CorrectIndex: 1,
					Explanation:  "Communication and Language, Physical Development, and Personal, Social and Emotional Development (PSED) are the foundational Prime Areas.",
				},
				{
					ID:           "q2",
					Prompt:       "What is the statutory minimum staff-to-child ratio for children under 2 years old in England?",
					Options:      []string{"1 adult to 3 children (1:3)", "1 adult to 5 children (1:5)", "1 adult to 8 children (1:8)", "1 adult to 10 children (1:10)"},
					CorrectIndex: 0,
					Explanation:  "Under-twos require a minimum staffing ratio of 1:3 due to their high physical and emotional dependency.",
				},
				{
					ID:           "q3",
					Prompt:       "Why are the Prime Areas prioritized for babies and toddlers under 3 years old?",
					Options:      []string{"Because children under 3 cannot learn mathematics", "Because they form the essential foundation for all future cognitive and academic learning", "Because Ofsted only inspects Prime Areas", "Because Specific Areas are only taught in primary schools"},
					CorrectIndex: 1,
					Explanation:  "Healthy development in Communication, Physical, and PSED is essential before children can successfully access specific literacy and math skills.",
				},
				{
					ID:           "q4",
					Prompt:       "Who should you immediately inform if you suspect a safeguarding or welfare concern regarding a child?",
					Options:      []string{"The other parents at collection time", "The nursery's Designated Safeguarding Lead (DSL) or Room Leader", "Post the question on social media", "Wait one month to see if the situation improves"},
					CorrectIndex: 1,
					Explanation:  "Safeguarding concerns must be escalated immediately to the setting's Designated Safeguarding Lead (DSL).",
				},
				{
					ID:           "q5",
					Prompt:       "In a preschool room (ages 3–5), what is the standard staff-to-child ratio with a Level 3 qualified practitioner?",
					Options:      []string{"1 adult to 4 children (1:4)", "1 adult to 8 children (1:8)", "1 adult to 15 children (1:15)", "1 adult to 20 children (1:20)"},
					CorrectIndex: 1,
					Explanation:  "For 3-5 year olds in early years settings, the statutory ratio is 1:8 with a Level 3 lead (or 1:13 with a qualified teacher/EYTS).",
				},
			},
		},
		{
			ID:    "module-7-early-communication-language",
			Order: 7,
			Title: "Early Communication & Language",
			Purpose: "Equip practitioners with practical techniques to support language acquisition, active listening, " +
				"conversational turns, and vocabulary development in early years.",
			ContentOutline: []string{
				"Milestones in early speech, receptive language, and expressive language development",
				"The 'serve and return' interaction model — tuning in, noticing vocalisations, and responding warmly",
				"Building rich vocabulary — describing actions, commenting during play, and avoiding continuous testing questions",
				"Expanding on children's words — adding adjectives and extending short phrases naturally",
				"Giving children processing time — the 5-to-10 second rule before repeating or answering for a child",
				"Creating a language-rich environment — shared reading, dialogic storytelling, songs, and conversational dining",
			},
			Sections: []section{
				{
					Heading: "Milestones in speech and language development",
					Body: []string{
						"Communication and Language is the primary predictor of future educational and social success. Children develop receptive language (understanding) before expressive language (talking).",
						"• 0–12 months: Babbling, eye contact, turning to familiar voices, using gestures (pointing, waving).",
						"• 1–2 years: Single words emerging ('ball', 'mama'), combining two words ('more juice', 'bye bye daddy'), following simple 1-step instructions.",
						"• 2–3 years: 3–4 word sentences, asking 'what' and 'where', exploding vocabulary (up to 300+ words), understanding simple concepts like big/small.",
						"• 3–5 years: Complex sentences, asking 'why' and 'how', storytelling, using past and future tenses, holding detailed back-and-forth conversations.",
					},
				},
				{
					Heading: "Serve and Return: The foundation of interaction",
					Body: []string{
						"Like a game of tennis, 'Serve and Return' interactions build neural connections in young brains.",
						"1. Notice the serve: Pay attention to where the child is looking, pointing, or what sound they make.",
						"2. Return the serve: Acknowledge and respond warmly with words, facial expressions, or gestures ('Oh, you see the bird in the tree!').",
						"3. Name it: Give words to what the child is experiencing to build vocabulary.",
						"4. Keep the volley going: Wait for their response and take turns back and forth.",
					},
				},
				{
					Heading: "Narration and descriptive commentary during play",
					Body: []string{
						"Instead of quizzing children ('What color is this car? What is this animal?'), provide descriptive narration like a sports commentator.",
						"Narrate your own actions and the child's actions: 'You are rolling the blue playdough into a long snake. Now you are cutting it into small pieces!'",
						"Descriptive commentary exposes children to rich verbs, prepositions, and adjectives in a natural, stress-free context.",
					},
				},
				{
					Heading: "Language expansion and grammatical modelling",
					Body: []string{
						"When a child speaks, repeat their phrase and add one or two new words (Expansion).",
						"• Child: 'Car go.' -> Adult: 'Yes, the fast red car is zooming down the ramp!'",
						"• Child: 'Doggy big.' -> Adult: 'That is a very big fluffy doggy!'",
						"Never directly criticize grammar errors (e.g. child says 'I falled down'). Simply model the correct grammar back naturally: 'Oh dear, you fell down! Let's check your knee.'",
					},
				},
				{
					Heading: "The Power of the Pause: Processing time",
					Body: []string{
						"Young children process spoken language much slower than adults. Their brains need 5 to 10 full seconds to hear a sentence, decipher meaning, formulate a thought, and coordinate vocal muscles to speak.",
						"Practitioners often make the mistake of repeating a question after only 2 seconds, which resets the child's mental processing clock back to zero.",
						"Ask your question, maintain warm eye contact, and count silently to 7 before offering help.",
					},
				},
				{
					Heading: "Dialogic reading and language-rich environments",
					Body: []string{
						"Dialogic reading turns book reading into an active conversation rather than a passive listening exercise.",
						"Pause on pages to talk about the illustrations, ask 'What do you think will happen next?', and link the story to the children's own lives ('Look at that puddle! Remember when we jumped in puddles outside?').",
						"Surround the room with accessible picture books, props for storytelling, and quiet cosy corners.",
					},
				},
			},
			VideoStoragePath:     module7Video,
			VideoDurationSeconds: 70,
			PassMark:             4,
			Questions: []question{
				{
					ID:           "q1",
					Prompt:       "What does the 'Serve and Return' communication model involve?",
					Options:      []string{"Throwing tennis balls during outdoor play", "Noticing a child's gaze, sound, or gesture and responding back warmly to create conversational turns", "Teaching children to serve food at mealtimes", "Repeating test questions until the child gets the right answer"},
					CorrectIndex: 1,
					Explanation:  "Serve and return describes the back-and-forth interaction between an adult and child that builds strong brain architecture and communication skills.",
				},
				{
					ID:           "q2",
					Prompt:       "A 2-year-old points to a truck and says 'Truck fast!'. What is the most effective language expansion response?",
					Options:      []string{"No, you should say 'The truck is moving quickly'", "'Yes, look at that big yellow truck zooming fast!'", "Say nothing and look away", "'What letter does truck start with?'"},
					CorrectIndex: 1,
					Explanation:  "Language expansion acknowledges what the child said and adds descriptive vocabulary (big, yellow, zooming) in a positive way.",
				},
				{
					ID:           "q3",
					Prompt:       "Why is it essential to wait 5–10 seconds after asking a toddler a question?",
					Options:      []string{"To see if other children will answer for them", "Because young children require extra neurological processing time to understand and formulate their response", "To check your phone while they think", "Because children under 3 cannot understand questions"},
					CorrectIndex: 1,
					Explanation:  "Young children need several seconds of silent processing time. Repeating questions too quickly resets their processing cycle.",
				},
				{
					ID:           "q4",
					Prompt:       "Why is descriptive commentary (narrating play) preferred over testing questions (e.g. 'What colour is this?')?",
					Options:      []string{"Testing questions cause stress and limit conversations, whereas commentary models rich language in context", "Because colors should not be taught in nursery", "Because testing questions take too long to ask", "Commentary requires fewer staff members"},
					CorrectIndex: 0,
					Explanation:  "Narrating play immerses children in rich language without putting them under pressure to perform or guess answers.",
				},
				{
					ID:           "q5",
					Prompt:       "How can a practitioner turn a storybook session into a 'dialogic reading' experience?",
					Options:      []string{"Reading the words as fast as possible without looking up", "Discussing illustrations, asking open questions, and connecting story events to the children's own experiences", "Testing children on spelling at the end of each page", "Making children sit completely silent without pointing or speaking"},
					CorrectIndex: 1,
					Explanation:  "Dialogic reading engages children as active storytellers by discussing pictures, predicting events, and relating stories to real life.",
				},
			},
		},
		{
			ID:    "module-8-nursery-rhymes-songs",
			Order: 8,
			Title: "Nursery Rhymes & Songs Library",
			Purpose: "Give practitioners a practical, ready-to-use library of the songs and rhymes that come up " +
				"constantly in a UK nursery day, so someone with no UK nursery background isn't caught out on shift.",
			ContentOutline: []string{
				"Transition songs — used to move children smoothly between routines (tidy-up time, lining up, handwashing)",
				"Circle time & register songs — greeting each child by name, welcoming the group, establishing community",
				"Hygiene & routine songs — handwashing songs timed to 20 seconds, mealtime manners rhymes",
				"Classic action rhymes and songs — Wind the Bobbin Up, Wheels on the Bus, Incy Wincy Spider, Head Shoulders Knees and Toes",
				"Strategic song selection — using soothing songs to calm energy vs. lively action songs to energise",
			},
			Sections: []section{
				{
					Heading: "The power of music and rhyme in early childhood",
					Body: []string{
						"Rhymes and songs are not time-fillers; they are primary educational tools in UK early years education.",
						"Singing builds phonological awareness (hearing rhyme, alliteration, rhythm, and syllables), which is the single strongest precursor to learning to read and write.",
						"Action rhymes also develop gross and fine motor coordination, bilateral integration, body awareness, and social connection.",
					},
				},
				{
					Heading: "Transition songs: Moving between routines",
					Body: []string{
						"Transition songs provide a predictable audio cue that prepares children emotionally for routine changes without shouting or conflict.",
						"Tidy-Up Song Example: 'Tidy up, tidy up, everybody everywhere, tidy up, tidy up, everybody do your share!' (Sung to the tune of a rhythmic chant while packing toys away).",
						"Lining-up / Transition Chant: '1, 2, 3, look at me, hands by our sides so quietly, 4, 5, 6, quiet as mice, ready for outside looking nice!'",
					},
				},
				{
					Heading: "Circle time and register greeting songs",
					Body: []string{
						"Morning circle time songs acknowledge each child individually, fostering belonging and self-esteem.",
						"'Hello [Child's Name], hello [Child's Name], hello [Child's Name], we're glad you're here today!' (Sung to each child around the circle as they wave).",
						"'Days of the Week' (to the tune of The Addams Family): 'Days of the week (clap, clap), days of the week (clap, clap), there's Sunday and there's Monday, there's Tuesday and there's Wednesday, there's Thursday and there's Friday, and then there's Saturday!'",
					},
				},
				{
					Heading: "Hygiene & routine songs: 20-second handwashing",
					Body: []string{
						"Handwashing must last at least 20 seconds with soap to effectively eliminate germs. Singing a standard 20-second rhyme ensures children don't rinse prematurely.",
						"'Wash, wash, wash your hands, wash them nice and clean! Rub the tops and rub the palms and all the space between!' (Sung twice through to the tune of Row Row Row Your Boat).",
						"Mealtime Rhyme: 'Two little hands go clap, clap, clap, two little feet go tap, tap, tap. Two clean hands placed in our lap, now we're ready for our snack!'",
					},
				},
				{
					Heading: "Essential UK nursery action rhymes",
					Body: []string{
						"Every practitioner working in a UK setting should know these core action rhymes and their gestures:",
						"1. Wind the Bobbin Up: Rolling hands around each other ('wind, wind, pull, pull, clap, clap, clap'), pointing to ceiling, floor, window, door, placing hands on lap.",
						"2. Incy Wincy Spider: Alternate thumb-to-finger climbing motion, hands fluttering down for rain, arching arms overhead for sun.",
						"3. The Wheels on the Bus: Rolling arms for wheels, wipers swishing side to side, horn beeping on nose, doors opening and shutting.",
						"4. Head, Shoulders, Knees and Toes: Touching body parts in rhythm, gradually increasing or decreasing speed.",
					},
				},
				{
					Heading: "Strategic song selection: Calming vs energising",
					Body: []string{
						"Use songs intentionally to manage the room's energy levels:",
						"• To settle a noisy room before lunch or nap time: Sing gentle, slow finger-rhymes at a whisper ('Twinkle Twinkle Little Star', 'Open Shut Them', 'Sleeping Bunnies'). Children will naturally lower their voices to hear you.",
						"• To energise or release physical tension during outdoor play: Sing dynamic action songs with jumping and stomping ('If You're Happy and You Know It', 'Five Little Monkeys Jumping on the Bed').",
					},
				},
			},
			VideoStoragePath:     module8Video,
			VideoDurationSeconds: 75,
			PassMark:             4,
			Questions: []question{
				{
					ID:           "q1",
					Prompt:       "Why are songs and nursery rhymes considered so important for early literacy development?",
					Options:      []string{"They keep children quiet so staff can leave the room", "They develop phonological awareness, rhythm, and syllable recognition which underpin reading and writing", "They are only used to entertain visitors", "They replace the need for storybooks"},
					CorrectIndex: 1,
					Explanation:  "Nursery rhymes develop phonemic and phonological awareness, helping young brains hear the sounds and rhythmic structures of language.",
				},
				{
					ID:           "q2",
					Prompt:       "How can a practitioner ensure children wash their hands with soap for the full recommended 20 seconds?",
					Options:      []string{"Watch a stopwatch on the wall", "Sing a 20-second handwashing song twice through (e.g. 'Wash wash wash your hands')", "Tell children to count to 100", "Only rinse with cold water without soap"},
					CorrectIndex: 1,
					Explanation:  "Singing a familiar rhyme provides a fun and accurate internal timer for effective hand hygiene.",
				},
				{
					ID:           "q3",
					Prompt:       "What actions accompany the classic UK rhyme 'Wind the Bobbin Up'?",
					Options:      []string{"Clapping hands on head and running in circles", "Rolling fists around each other, pulling, clapping, pointing to ceiling, floor, window and door", "Sitting silently with arms crossed", "Stomping feet on the table"},
					CorrectIndex: 1,
					Explanation:  "'Wind the Bobbin Up' uses winding hand motions, pulling gestures, clapping, and pointing to room features, developing fine motor coordination.",
				},
				{
					ID:           "q4",
					Prompt:       "If a room of toddlers is becoming over-excited and loud before story time, what is the best singing strategy?",
					Options:      []string{"Shout a loud song at the top of your voice", "Begin singing a quiet, slow finger-rhyme in a calm whisper (e.g. 'Twinkle Twinkle' or 'Open Shut Them')", "Turn on loud pop music", "Ban all singing for the rest of the day"},
					CorrectIndex: 1,
					Explanation:  "Singing a quiet, soothing song in a whisper encourages children to tune in, quiet down, and match your calm vocal pitch.",
				},
				{
					ID:           "q5",
					Prompt:       "Why are morning circle time greeting songs (greeting each child by name) so valuable?",
					Options:      []string{"They help the cook prepare food portions", "They build a sense of community, acknowledge each child individually, and foster belonging", "They test children's memory under pressure", "They are required by the local council fire department"},
					CorrectIndex: 1,
					Explanation:  "Greeting each child by name fosters a warm sense of belonging, strengthens relationships, and supports self-esteem.",
				},
			},
		},
		{
			ID:    "module-9-diverse-family-backgrounds",
			Order: 9,
			Title: "Communicating with Children from Diverse Family Backgrounds",
			Purpose: "Help practitioners communicate respectfully and effectively with children and families " +
				"from a wide range of cultural, linguistic, and family backgrounds, in a way that's genuinely inclusive.",
			ContentOutline: []string{
				"Recognising that 'family' looks different for every child — diverse structures, home languages, cultural traditions, dietary practices",
				"Simple, respectful ways to ask rather than assume — checking with parents and the room leader about home routines and customs",
				"Supporting children with English as an Additional Language (EAL) — visual cues, timetable picture cards, gestures, key home words, patience",
				"Working in partnership with families — plain, jargon-free communication with parents who are less confident in English",
				"Celebrating diversity naturally — inclusive books, everyday dolls/puzzles, and cultural representation embedded throughout the room",
				"What to avoid — stereotyping, assumptions based on names or appearances, and tokenistic one-off activities",
			},
			Sections: []section{
				{
					Heading: "Every family is unique: Modern family structures",
					Body: []string{
						"Children in UK nurseries come from a wide variety of family backgrounds: single-parent families, two mums or two dads, blended step-families, foster carers, adoptive parents, kinship care with grandparents, and extended multi-generational households.",
						"Never assume every child lives with a 'mummy and daddy'. Use inclusive language ('grown-ups at home', 'your family', 'who came with you today?') to ensure every child feels safe and represented.",
					},
				},
				{
					Heading: "Respectful communication: Asking instead of assuming",
					Body: []string{
						"Every family has unique routines, cultural traditions, faith practices, and dietary needs. Assumptions lead to mistakes and misunderstandings.",
						"At drop-off or during key worker handovers, ask warm, open questions: 'How do you like to settle [Child] at home?', 'Is there any particular way you would like us to prepare their meals?', 'Are there any festivals or traditions your family celebrates that we should know about?'",
						"Always check the room's written care plans and dietary records before meal and sleep routines.",
					},
				},
				{
					Heading: "Supporting English as an Additional Language (EAL)",
					Body: []string{
						"Many children entering UK nurseries speak little or no English at home. Being multilingual is a cognitive strength, not a delay.",
						"Practical EAL support strategies:",
						"• Visual Timetables and Flashcards: Use photos and simple illustrations for routine events (toilet, water, snack, outside play, home time).",
						"• Body Language & Gestures: Pair spoken words with clear, expressive gestures and physical demonstrations.",
						"• Key Home Words: Ask parents for 4–5 essential words in the child's home language (hello, water, toilet, hungry, mummy/daddy) to provide immediate comfort.",
						"• Patience and Reassurance: Never pressure or correct an EAL child's pronunciation. Give them warmth, smiles, and time to absorb the language.",
					},
				},
				{
					Heading: "Jargon-free partnerships with parents and carers",
					Body: []string{
						"UK early years education is full of professional acronyms (EYFS, DSL, PSED, SENCO, Ofsted, COSHH). For parents whose first language is not English, or who are new to the UK education system, this jargon is alienating.",
						"Speak in clear, warm, plain English. Avoid slang, idioms, or institutional acronyms.",
						"Check understanding gently: 'Does that make sense?', 'Would you like me to write that down for you?'. Welcome interpreters or translated notes where available.",
					},
				},
				{
					Heading: "Natural diversity in everyday room resources",
					Body: []string{
						"Diversity should be seamlessly integrated into the room's continuous provision all year round, not reserved for isolated 'theme days'.",
						"• Reading Corner: Books featuring characters of diverse backgrounds, abilities, family structures, and languages.",
						"• Role-Play & Home Corner: Realistic dolls with varied skin tones and hair textures, varied play food from diverse cuisines (roti, dim sum, plantain, pasta, jollof), and diverse dressing-up clothes.",
						"• Music & Art: Instruments, music, and art materials that reflect global cultures and skin-tone crayons/paints.",
					},
				},
				{
					Heading: "What to avoid: Stereotyping and tokenism",
					Body: []string{
						"Avoid making assumptions about a family's language, religion, diet, or beliefs based on their skin color, surname, or clothing.",
						"Avoid 'tokenism' — celebrating a culture once a year with a costume craft while ignoring it the rest of the year.",
						"Treat every child and family as individuals with their own unique story. Normalise differences as everyday, natural aspects of our shared community.",
					},
				},
			},
			VideoStoragePath:     module9Video,
			VideoDurationSeconds: 75,
			PassMark:             4,
			Questions: []question{
				{
					ID:           "q1",
					Prompt:       "How can a practitioner best support a child who speaks little English (EAL) during their first weeks at nursery?",
					Options:      []string{"Insist that the child speaks only English and correct every mistake", "Use visual picture cards, gestures, learn a few key home-language comfort words, and provide warm patience", "Isolate the child until they learn English", "Tell parents not to speak their home language at home"},
					CorrectIndex: 1,
					Explanation:  "Using visual aids, gestures, and learning a few key home words helps EAL children feel secure, understood, and included.",
				},
				{
					ID:           "q2",
					Prompt:       "When speaking with parents who are building their English proficiency, what is the best communication practice?",
					Options:      []string{"Use complex early years acronyms like EYFS, DSL, and PSED", "Speak clearly in plain English, avoid jargon, and check understanding with warmth and respect", "Refuse to speak to them without a solicitor", "Speak loudly as if they cannot hear"},
					CorrectIndex: 1,
					Explanation:  "Plain, jargon-free language ensures parents feel welcomed, respected, and fully informed about their child's day.",
				},
				{
					ID:           "q3",
					Prompt:       "What does it mean to celebrate diversity 'naturally' in an early years classroom?",
					Options:      []string{"Having diverse dolls, books, foods, and resources integrated into continuous provision every day of the year", "Only mentioning diverse cultures on one designated day per year", "Keeping cultural books locked in the teacher's cupboard", "Ignoring cultural backgrounds entirely"},
					CorrectIndex: 0,
					Explanation:  "Natural inclusion means diverse representation (books, dolls, puzzles, music) is embedded in the environment all year long.",
				},
				{
					ID:           "q4",
					Prompt:       "Why should practitioners use inclusive language like 'grown-ups at home' or 'your family' rather than assuming 'mummy and daddy'?",
					Options:      []string{"Because children do not have parents", "Because modern families have many loving structures including single parents, two mums/dads, foster carers, and grandparents", "Because nursery regulations forbid saying the word mummy", "To make paperwork shorter"},
					CorrectIndex: 1,
					Explanation:  "Inclusive language ensures all children feel valued and accepted regardless of their family structure.",
				},
				{
					ID:           "q5",
					Prompt:       "If you are unsure about a family's cultural dietary customs or settling routines, what is the most respectful approach?",
					Options:      []string{"Make an assumption based on their surname or appearance", "Ask the parents or room leader politely and respectfully to confirm their preferences", "Ignore the family's requests", "Guess based on internet stereotypes"},
					CorrectIndex: 1,
					Explanation:  "Politely asking parents about their child's specific routines and preferences shows respect and avoids harmful assumptions.",
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
			"videoUrl":             m.VideoURL,
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
		fmt.Printf("  %-36s %-40s %d questions, pass %d/%d  [%s]\n",
			m.ID, m.Title, len(m.Questions), m.PassMark, len(m.Questions), state)
	}

	fmt.Println("\nAll 9 training modules successfully seeded to Firestore trainingModules collection!")
}
