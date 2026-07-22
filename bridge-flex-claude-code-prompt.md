# Claude Code Prompt — Bridge Flex Backend (Firebase)

Copy everything below into Claude Code as your first message in the project.

---

You are acting as a senior backend engineer joining the Bridge Flex project. Bridge Flex is a two-sided mobile-first marketplace connecting UK nurseries with childcare staff for last-minute shift cover. Nurseries post shifts; staff accept them; the first staff member to accept wins (no double-booking); there's a trust layer (DBS status, ratings); and eventually payments and messaging between the two sides.

We are building the backend on **Firebase**, not Supabase. Treat Supabase/Postgres terminology you might see referenced elsewhere (RLS, "Postgres function") as *prior art describing intent*, not the implementation — your job is to translate that intent into idiomatic Firebase patterns, not imitate Postgres syntax.

### Budget constraint — read this before designing anything

There is no budget right now. This changes real technical decisions, not just a footnote:

- **Use Firestore, not Firebase Data Connect / SQL Connect.** Firebase does offer a Postgres option (Data Connect, aka SQL Connect), but it's backed by a Cloud SQL instance that costs money after a 90-day trial (from ~$9.37/month) and requires the Blaze plan. Firestore's free tier is permanent and requires no billing account. Do not use Data Connect for this project.
- **The entire Firebase Emulator Suite (Auth, Firestore, Functions, Storage, Pub/Sub) is free forever, no credit card required, on the Spark (free) plan.** All development and testing for this project — including running Cloud Functions logic — should happen against the emulators. Design and build assuming we will develop and test 100% locally for an extended period before any production deployment.
- **Important real constraint to design around**: deploying Cloud Functions to a *live* Firebase project requires upgrading to the Blaze (pay-as-you-go) plan, which requires linking a card — even though usage can stay entirely within the free quota and cost $0. This isn't a Firebase policy we can avoid; it's required for any real (non-emulated) Cloud Functions deployment. So: build everything to run and be fully testable on the emulators now — card-linking and going live is a separate, later decision, not something Phase 0/1 needs to solve.
- **Payments is optional/deferred for now.** Design the data model so a `transactions`/payment-status field exists and won't need reshaping later, but do not build the Stripe Connect integration yet. Treat it as a stubbed module: a `paymentStatus` field on `shifts` that defaults to `'not_required'` or `'pending'`, and a placeholder payments Cloud Functions codebase with no real Stripe calls — just enough scaffolding that wiring in Stripe later doesn't require restructuring the core data model.

Do not write any code yet. **Phase 0 is design only.**

## REVISION NOTES — read this before continuing, then produce ARCHITECTURE.md v2

`ARCHITECTURE.md` (attached/already in the repo) was reviewed and is approved *with two required changes*. Do not silently patch isolated lines — produce a full v2 of the document so every section stays internally consistent, then stop for review again before writing any code. Treat everything in the original doc not touched by these two changes as still correct and approved.

### Change 1 — fix the profiles field-exposure bug
§2/§3 currently promise a "public subset" of `profiles/{uid}` is visible to other users, but the actual rule in §3 (`any authenticated user may read`) grants the *entire* document — Firestore Security Rules cannot do field-level read redaction, only whole-document allow/deny. As written, this leaks the exact `GeoPoint` location of every nursery and staff member to any signed-up user, which is a real safety problem given the child-safeguarding context.

Fix: split into `profiles/{uid}` (private — exact location, full detail, owner-read-only) and `profilesPublic/{uid}` (public — name, role, rating, `dbsStatus` badge, a coarse location such as a geohash prefix or named area, never the exact coordinates). Keep them in sync via a Cloud Function trigger whenever the private doc's public-relevant fields change. Update §2's collection table, §3's rule descriptions, and any other section that reads "other users can see a public subset" to reflect this concretely (which fields live where, what the sync trigger does, what happens on write conflicts if the sync trigger fails).

### Change 2 — backend language is Go, not Node.js/Python

This requires more than a find-and-replace, because "Cloud Functions for Firebase" (the `firebase-functions` SDK the original doc assumed — `onCall`, `HttpsError`, the `firebase.json` multi-codebase array, and the Functions emulator inside `firebase emulators:start`) **only supports Node.js and Python**. Go is supported by plain **Cloud Functions (2nd gen)** / Cloud Run, which is a different, lower-level surface. Revise accordingly:

- **No `onCall`.** Every function is a plain HTTP handler. Auth is manual: read `Authorization: Bearer <ID token>` and verify it yourself via the Firebase Admin SDK for Go (`firebase.google.com/go/v4/auth`, `VerifyIDToken`). Define this verification as a shared middleware/helper used by every function, not reimplemented per-handler.
- **No `HttpsError`.** Define our own JSON error contract once (e.g. `{"error": {"code": "SHIFT_ALREADY_BOOKED", "message": "..."}}` with a matching HTTP status), and reuse it everywhere the original doc specified an `HttpsError` code — the code strings/meanings from the approved error-code contract (§4) stay the same, only the transport wrapper changes.
- **Triggers become Eventarc bindings, not code decorators.** Firestore/Auth/Pub-Sub-triggered functions (the ratings recompute, the Auth-triggered profile init, the `shift-booked` Pub/Sub consumer) are deployed with `--trigger-event-filters` at deploy time rather than an `onCreate`/`onUpdate` wrapper in code. Design each trigger's event filter and payload shape explicitly in v2 — don't leave this implicit.
- **"Codebases" become literal separate Go modules/binaries**, each its own deployable Cloud Function/Cloud Run service (`functions-core`, `functions-payments` stub, `functions-communication`), each with its own `go.mod` — this is actually a cleaner match for "separate microservice" than the Node multi-codebase array was, so keep the same three-way split and the same call/trigger contracts between them (Pub/Sub topic names, which fields each owns), just express the deploy mechanics correctly for Go.
- **Local dev**: use `functions-framework-go` to run each HTTP-style function locally as its own process/port, pointed at the Firestore/Auth/Storage emulators via `FIRESTORE_EMULATOR_HOST` / `FIREBASE_AUTH_EMULATOR_HOST` / `FIREBASE_STORAGE_EMULATOR_HOST`. This is still fully free and requires no card — just note plainly in v2 that it's several local processes rather than one unified `firebase emulators:start` for everything.
- **Be honest about the weaker spot**: trigger-based functions (Firestore/Auth/Pub-Sub) don't have a clean "fires automatically against the emulator" story in Go the way `firebase-functions` gives Node for free. Design the testing approach for these as direct unit tests of the handler function against a hand-constructed event payload, rather than claiming full end-to-end local trigger emulation exists — don't paper over this gap in v2.
- Update the Bruno collection section: since there's no `onCall` envelope, each `.bru` request is a plain `POST` with a normal JSON body and a normal `Authorization` header — actually simpler than the original doc's envelope-construction note, so simplify that section rather than leaving the now-inapplicable envelope explanation in place.

Produce `ARCHITECTURE.md` v2 reflecting both changes, keep the rest of the approved design (data model shapes, security rules logic per collection, the `acceptShift` transaction design and error codes, the deferred payments stub, the notification/FCM design) intact, and stop for review again before starting Phase 1.

## Phase 0 — System Design (produce this first, as `ARCHITECTURE.md`)

Design the system and write it down before touching code. I want to review and approve the design before you build anything. Cover:

### 1. Service boundaries
Three deployable units, each with a clear reason to be separate:
- **Core backend** (Firebase Auth + Firestore + core Cloud Functions): profiles, shifts, booking, ratings, documents metadata.
- **Payments service**: a distinct Cloud Functions codebase (use Firebase's multi-codebase support — `firebase.json` `functions` array with multiple `source` dirs) that owns Stripe Connect integration. Design it so the core backend never talks to Stripe directly — it calls the payments service's callable functions, and the payments service calls back into Firestore only through a narrow, well-defined set of fields (e.g. `shifts/{id}.paymentStatus`, a `transactions` collection it owns).
- **Communication service**: a separate Cloud Functions codebase owning chat messages and push notifications via FCM. Core backend triggers it (e.g. on booking) via Pub/Sub or direct function calls; it does not own shift/profile data, only messages, notification records, and device tokens.

Explain the trade-off explicitly: why these are separate codebases/deploy targets rather than one big Functions project, and what the actual call/trigger path is between them (be concrete — e.g. "booking.onCreate trigger publishes to a `shift-booked` Pub/Sub topic; communication service subscribes and sends FCM + writes a notification doc").

### 2. Data model (Firestore, not relational)
Firestore is document-oriented — do not just port the relational sketch 1:1. Design collections thinking about query patterns and denormalization needs:
- `profiles/{uid}` — role (`nursery`|`staff`), name, location, description (nursery), dbsStatus (staff), rating (aggregate), fcmTokens (array/subcollection).
- `shifts/{shiftId}` — nurseryId, title, date, startTime, endTime, payRate, status (`open`|`booked`|`cancelled`), bookedStaffId, createdAt, paymentStatus.
- Decide and justify: does booking need its own collection, or is it fields on `shifts`? (Given the atomic "first accept wins" requirement, think about what document(s) the transaction actually needs to touch.)
- `ratings/{ratingId}` — shiftId, raterId, rateeId, score, comment, createdAt, plus how `profiles/{uid}.rating` gets recomputed (a Cloud Function trigger on rating writes, not client-side math).
- `chatSessions/{sessionId}/messages/{messageId}` (owned by communication service).
- `transactions/{transactionId}` (owned by payments service) — shiftId, payerId, payeeId, amount, stripeStatus, stripeConnectAccountId refs.
- `documents/{docId}` metadata pointing at Cloud Storage paths for DBS uploads — storage rules and Firestore metadata are separate; design both.
- `notifications/{notificationId}` (owned by communication service).

For every collection, state what a client can read/write directly (via Security Rules) vs. what must go through a Cloud Function because it needs cross-document logic, atomicity, or a privileged check.

### 3. Authorization model (the RLS replacement)
Be explicit that Firestore Security Rules are the enforcement layer for direct client reads/writes, and Cloud Functions (using the Admin SDK, which bypasses rules) are the enforcement layer for privileged operations. Write out, in the design doc, the rule logic in plain English for each collection before implementing it later (e.g. "a staff profile's `dbsStatus` is writable only by that user's own uid; a shift's `bookedStaffId` is never client-writable — only the booking Cloud Function, using Admin SDK, can set it"). Flag explicitly: **no authorization logic should ever live only in frontend code** — every sensitive field needs either a Security Rule or a server-side check in a callable function.

### 4. The atomic booking operation
Design this as a Firestore transaction inside an `onCall` Cloud Function (`acceptShift`), not a client-side write. Walk through the failure path: client calls `acceptShift(shiftId)` → function runs `runTransaction` → reads shift doc → if `status !== 'open'` throws a specific error code the client maps to "This shift is no longer available" → else sets `status: 'booked'`, `bookedStaffId`. Specify the exact error-code contract (e.g. `functions.https.HttpsError('failed-precondition', 'SHIFT_ALREADY_BOOKED')`) so the frontend has something concrete to catch.

### 5. Payments design (DEFERRED — design only, do not implement)
Payments is not being built right now; only design it on paper so the data model doesn't need reshaping later. Note explicitly in the doc: the "Run Payments with Stripe" Firestore extension is designed for a single business selling to customers (subscriptions/one-time checkout), not a marketplace that must pay out two different parties — when this is eventually built, it should be **Stripe Connect** (Express accounts for nurseries and staff), not that extension. For now:
- Add a `paymentStatus` field on `shifts` (e.g. `'not_required' | 'pending' | 'paid'`, defaulting to `'not_required'`) so nothing downstream needs to change shape later.
- Reserve a `transactions` collection name and sketch its future fields in the doc, but do not create real documents or Cloud Functions logic for it yet.
- Create an empty/stub payments Cloud Functions codebase directory (per the multi-codebase structure below) with a placeholder function or a `TODO.md`, so the deploy/codebase structure exists without any real Stripe code or dependency being pulled in yet.

### 6. Notifications design (FCM)
- Device token registration: where tokens live (`profiles/{uid}/fcmTokens` subcollection, since a user may have multiple devices), and a callable function to register/remove tokens.
- Delivery triggers: which events fire a push (shift booked, new shift matching availability, rating received) and whether that's a direct Firestore trigger or via the Pub/Sub topic from the core backend.
- In-app notification record vs. push: design both, since push can fail/be disabled and the in-app list is the source of truth.

### 7. Local development & testing strategy
- **Firebase Emulator Suite**: Auth, Firestore, Functions, Storage, Pub/Sub all run locally via `firebase emulators:start`, configured in `firebase.json`. State clearly that Security Rules are testable against the emulator, and that Stripe/webhooks will need either the Stripe CLI's local webhook forwarding or a mocked Stripe client in emulator mode — decide which and justify it.
- **Seed data**: a seed script (using the Admin SDK pointed at emulator hosts via env vars) that creates sample nursery/staff profiles and shifts so the Bruno collection has real data to hit.
- **Bruno collection** (for manual/API testing against the emulator): design the folder structure (`bruno.json`, `environments/Emulator.bru`, `environments/Production.bru`, folders per domain: `auth/`, `shifts/`, `booking/`, `payments/`, `communication/`). Each `.bru` file should be a real request against either an `onCall`-wrapped HTTPS endpoint or an `onRequest` HTTPS function — note that `onCall` functions expect a specific wrapped request/response envelope, so decide whether test-only HTTP endpoints are needed for Bruno to hit cleanly, or whether you'll document the callable envelope format in each `.bru` file's body.

### 8. Open items to flag, not silently decide
List these back to me rather than picking silently, since they're product/legal decisions, not engineering ones: identity verification method at sign-up, DBS verification method (self-report vs. document + manual review), employer-of-record question (affects whether Payments is "Bridge Flex pays out" vs. "nursery pays directly"), geographic matching radius logic, minimum shift notice period.

---

## Phase 1 (only after I approve Phase 0)

Everything in this phase should run and be fully testable against the **Firebase Emulator Suite only** — no Blaze plan, no billing account, and no real Stripe keys needed for any of this. Once I've reviewed `ARCHITECTURE.md` and confirmed it, proceed in this order, stopping after each for a quick sanity check before moving on:

1. Firebase project scaffold: `firebase.json`, `.firebaserc`, Firestore Security Rules file, Storage rules file, emulator config with fixed ports, npm scripts for `emulators:start` and `emulators:start --import=./seed-data --export-on-exit`.
2. Core backend Cloud Functions codebase: Auth-triggered profile creation, profile CRUD callables, shift CRUD callables, `acceptShift` transaction function.
3. Security Rules for every collection, plus a short rules-unit-test file using `@firebase/rules-unit-testing` covering at minimum: a staff user cannot write another user's `dbsStatus`, a client cannot set `shifts.bookedStaffId` directly, an unbooked shift is readable by any authenticated staff, a booked shift is only fully readable by its nursery and booked staff.
4. Ratings collection + the trigger that recomputes `profiles.rating`.
5. Payments: create the stub codebase only (per the deferred design above) — no real Stripe integration, no dependency on a Stripe account or API keys.
6. Communication Cloud Functions codebase (chat messages, FCM token registration, notification triggers) — FCM works fully in the emulator and is free on Spark, so this can be built for real.
7. Seed script for emulator data.
8. Bruno collection covering every callable/HTTP endpoint above, pointed at the emulator by default via an `Emulator.bru` environment, with a second `Production.bru` environment left with placeholder values for later.
9. A `README.md` explaining how to run everything locally: start emulators, seed data, open Bruno against the `Emulator` environment, and run the rules unit tests. Include a short note that going live later will require upgrading to the Blaze plan (a required step for real Cloud Functions deployment, not something we need to solve now) and that Payments will need real Stripe Connect work at that point.

Do not implement Phase 1 items until I've confirmed the Phase 0 design doc. When Phase 0 is ready, present `ARCHITECTURE.md` and stop for my review.
