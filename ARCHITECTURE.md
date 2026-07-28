# Bridge Flex — Backend Architecture (v2 design, now implemented and live)

**Status: implemented and live in production** (Firebase project `kvision-503115`, region
`europe-west2`). This document was originally written as a pre-implementation design doc ("draft,
pending approval, no code written yet") — that framing is now historical. Everything described
below has been built, and the "Open items" in §8 have mostly been resolved by shipping decisions,
noted inline. See the "What's evolved beyond this document" section right below for what's grown
since v2 was first approved, and `backend/PRODUCTION_SETUP.md` / `KNOWN_ISSUES.md` (repo root) for
the operational/production-readiness picture this document doesn't cover.

Bridge Flex is a two-sided marketplace: nurseries post last-minute shifts, staff accept them
(first-accept-wins, no double-booking), with a trust layer (DBS status, ratings) and in-app chat.
Built on **Firebase** — Firestore, not Data Connect/SQL — because Firestore's free tier requires no
billing account and no card, and Cloud Functions (2nd gen) run in **Go**, not Node, since it's the
team's stronger language; `firebase-functions` (the SDK giving Node `onCall`/`HttpsError`/an
integrated local emulator) has no Go equivalent, which shapes the transport and local-dev story
described in §1a.

## What's evolved beyond this document

This file still accurately describes the foundational design — service boundaries, the
private/public profile split, the booking transaction, the auth model, the trigger mechanics. What
it does **not** re-derive (to avoid a second copy that drifts out of sync) is the full current data
shape, which grew substantially past the original MVP scope during implementation, driven by a
separate product spec:

- **Profile is now a full onboarding wizard's worth of fields** for both roles — staff
  (qualifications, experience, bio, previous roles, languages, availability, right-to-work status)
  and nursery (registered company name, Ofsted registration, opening hours, facilities, photos,
  nursery type). `Profile`/`ProfilePublic` in `backend/services/core/models.go` are the source of
  truth for the exact current field list — read there, not here.
- **Shifts support multiple staff per shift** (`bookedStaffIds`, not just the original single
  `bookedStaffId`, which is retained only for backward compatibility with older reads) and track
  `firstAcceptedAt`/`noShowStaffIds` to feed nursery-facing statistics (average response time,
  no-show rate — `backend/services/core/function/stats.go`).
- **Ratings support optional per-category scores** (`categoryScores`: communication, punctuality,
  professionalism, reliability, childEngagement), not just a single 1–5 score.
- **Admin capabilities exist beyond the original single `reviewDocument` endpoint**: platform-wide
  stats, a user-management list, per-user detail, suspend/unsuspend (which also revokes the user's
  Auth refresh tokens), and identity/Ofsted verification badges — all in
  `backend/services/core/function/admin.go`, all gated the same way `reviewDocument` always was
  (the `admin` Firebase Auth custom claim, never a self-service path).
- **Self-service account deletion** (`DeleteAccount`) and a shift-cancellation notification path
  (`OnShiftCancelled`, Pub/Sub-triggered off a `shift-cancelled` topic `cancelShift` publishes to)
  were added after the functions in the table below.
- **`initProfileOnSignUp` (§1a) turned out to be permanently undeployable** — this project has no
  `firebaseauth.googleapis.com` Eventarc provider registered, which isn't something application
  code can fix. It's covered by two fallbacks instead: a client-side best-effort write right after
  sign-up (`AuthRepository._ensureProfileDocument` in the Flutter app), and a server-side
  auto-create in `UpdateProfile` itself (`backend/services/core/function/profiles.go`) if the
  profile doc doesn't exist yet when the client's first `UpdateProfile` call lands. Functionally
  covered; just not the atomic Auth-trigger design originally planned.

## 1. Service boundaries

Three separate Go modules, each its own family of deployable **Cloud Functions (2nd gen)** —
themselves managed Cloud Run services under the hood — sharing one Firebase project, one Firestore
instance, one Auth instance:

- **`functions-core`** (`backend/services/core/`) — profiles (private + public), shifts, booking,
  ratings, documents, admin/moderation. 27 functions.
- **`functions-payments`** (`backend/services/payments/`) — owns Stripe Connect integration
  end to end. Still a stub (§5) — `CreatePayout` always returns `501`. 1 function.
- **`functions-communication`** (`backend/services/communication/`) — chat messages, FCM tokens,
  notification delivery. 12 functions.

Reasons to keep them separate (unchanged from the original design): blast-radius/deploy
independence (a bad payments deploy can't take down booking), dependency isolation (only
`functions-payments`'s `go.mod` will ever import the Stripe Go SDK), ownership enforced by code
structure (cross-boundary writes go through the explicit contracts below, not a shared package),
and cost/quota isolation once real traffic exists.

**Current deployed function inventory** (verified live against `kvision-503115`, `europe-west2` —
see `backend/services/*/deploy.sh` for the exact deploy commands and trigger config per function):

**`functions-core`** (HTTP unless noted):
`UpdateProfile`, `GetProfile`, `GetPublicProfile`, `DeleteAccount`, `CreateShift`, `UpdateShift`,
`ListOpenShifts`, `ListMyShifts`, `GetShift`, `AcceptShift`, `CancelShift`, `MarkNoShow`,
`CreateRating`, `ListRatings`, `CreateDocument`, `ReviewDocument`, `GetDocumentStatus`,
`ListMyDocuments`, `ListPendingDocuments`, `GetPlatformStats`, `ListAllUsers`, `GetUserDetail`,
`SetUserSuspended`, `SetVerificationBadge` — plus Eventarc-triggered `SyncProfilePublic`
(Firestore write on `profiles/{uid}`), `RecomputeRating` (Firestore create on `ratings/{id}`),
`MatchNewShift` (Firestore create on `shifts/{id}`), and `InitProfileOnSignUp` (Auth user created —
**deploy always fails**, deliberately allowed to via `|| true` in `deploy.sh`; see above).

**`functions-payments`**: `CreatePayout` (stub, `501`).

**`functions-communication`** (HTTP unless noted): `RegisterFcmToken`, `UnregisterFcmToken`,
`SendChatMessage`, `ListChatMessages`, `ListChatSessions`, `ListNotifications`,
`MarkNotificationRead`, `MarkAllNotificationsRead` — plus Pub/Sub-triggered `OnShiftBooked` (topic
`shift-booked`), `OnRatingReceived` (topic `rating-received`), `OnShiftMatched` (topic
`shift-matched`), `OnShiftCancelled` (topic `shift-cancelled`).

**Concrete call/trigger paths:**

- **Booking → Communication:** `acceptShift` (core) commits the Firestore transaction, then
  publishes to `shift-booked`. `onShiftBooked` (communication) sends FCM pushes to both parties,
  writes a `notifications/{id}` doc for each, and initializes `chatSessions/{sessionId}` if one
  doesn't already exist for that shift.
- **Cancellation → Communication:** `cancelShift` (core) publishes to `shift-cancelled` when a
  *staff member* cancels a booked shift (nursery-initiated cancellation doesn't need to notify the
  nursery itself). `onShiftCancelled` (communication) notifies the nursery that coverage was
  dropped.
- **Core → Payments:** core sets `shifts/{id}.paymentStatus = 'pending'` directly at
  shift-creation time when payment will be required. Actual payment *processing* is a
  payments-owned HTTP endpoint (`functions-payments`'s `CreatePayout`, stubbed) that core would
  call as a normal authenticated HTTP request once payments is real.
- **Payments → Core (write-back):** payments writes only to `shifts/{id}.paymentStatus` and to its
  own `transactions` collection — never to `profiles`/`profilesPublic`, never to any other `shifts`
  field.
- **Rating → Core (aggregate):** `recomputeRating`, an Eventarc Firestore-create trigger on
  `ratings/{ratingId}`, recomputes `profiles/{rateeId}.rating`, which cascades to
  `profilesPublic/{rateeId}.rating` via the sync trigger below.
- **Core-internal sync: `profiles` → `profilesPublic`:** `syncProfilePublic`, an Eventarc Firestore
  trigger on `profiles/{uid}` writes, mirrors public-relevant fields into `profilesPublic/{uid}`
  whenever they change. Detailed in §2.

Why Pub/Sub for booking/cancellation→communication specifically: these are the events with
plausible future fan-out (communication now; analytics later). Payments stays a direct call
because there's exactly one caller, one callee, and a synchronous request/response shape.

### 1a. Transport, auth, and triggers under Go

**No `onCall`.** Every core/payments/communication endpoint a client calls directly is a plain HTTP
handler (`net/http`, run locally via `functions-framework-go`, deployed as an HTTP Cloud Function).
Request/response bodies are plain JSON the handler decodes/encodes itself.

**Auth is manual, via a shared middleware** (`backend/shared/auth`, one implementation, imported by
all three services): reads `Authorization: Bearer <ID token>`, verifies it via the Firebase Admin
SDK for Go, writes the standard error envelope with `401` on failure, attaches the decoded `uid`
(and custom claims) to the request context on success.

**No `HttpsError`.** One JSON error contract, reused everywhere:
```json
{ "error": { "code": "SHIFT_ALREADY_BOOKED", "message": "This shift is no longer available" } }
```
paired with a matching HTTP status per code (see §4's table).

**Triggers are Eventarc bindings, deployed via `gcloud`, not coded as decorators.** See the deploy
scripts (`backend/services/*/deploy.sh`) for the exact event filter per trigger function — Firestore
document writes/creates, Pub/Sub topic messages, or (in `initProfileOnSignUp`'s permanently-broken
case) an Auth user-created event.

**Codebases are literal Go modules**, each `go.mod`-rooted, with every function exported and
registered via `functions-framework-go`'s `functions.HTTP(...)`/`functions.CloudEvent(...)` calls
in an `init()`. Each service is duplicated into two copies on disk — one under `function/` (used by
local dev's `cmd/main.go`) and one flattened at the service root (required by the Cloud Functions Go
buildpack, which needs those `init()` registrations at the module root, not a subdirectory). **Any
backend code change must be applied to both copies** — there is no build step that syncs them
automatically. Each service also bundles its own `./shared` copy for the same reason (`gcloud
functions deploy --source=.` only zips the service's own directory).

**Local dev — several processes, not one unified emulator UI.** Each HTTP-triggered function runs
locally as its own process via `functions-framework-go`, one fixed port per function — see
`backend/services/*/run-local.sh` and `backend/README.md` for the full local-dev walkthrough.

**Eventarc-triggered functions have no local "fires automatically" story in Go** — `firebase
emulators:start` doesn't dispatch Firestore/Auth/Pub-Sub events into Go the way it does for Node.
Covered by direct unit tests (`backend/services/*/function/triggers_test.go`) plus, for local
interactive dev, an optional `devharness` that subscribes to the same emulator data and invokes the
real exported handlers in-process — see `backend/README.md` "Local trigger dispatch".

---

## 2. Data model (Firestore)

The collections and their query-pattern rationale below are still accurate as originally designed.
**For the exact, current field list on any document, read `backend/services/core/models.go`
directly** — it's grown substantially past what's re-derived here (see "What's evolved" above), and
duplicating every field in two places just creates a second copy that goes stale.

### `profiles/{uid}` — private
Core identity + trust fields (`role`, `name`, exact `location` `GeoPoint`, `dbsStatus`, `rating`)
plus a large set of role-specific onboarding-wizard fields (staff: qualifications, experience, bio,
availability, right-to-work; nursery: company details, Ofsted info, facilities, photos) and
admin-only fields (`suspended`, `identityVerified`, `ofstedVerified`) that are never client-writable
via `updateProfile`. `profiles/{uid}/fcmTokens/{tokenId}` is a **subcollection**, not an array
field, so multiple devices' tokens can be added/removed independently without a read-modify-write
race, and stale-token cleanup on push failure is a simple doc delete.

**Client read/write:** owner-only for both read and write on the document itself. Write is further
restricted so `dbsStatus`, `rating`, `suspended`, `identityVerified`, `ofstedVerified` are frozen
from the client.

### `profilesPublic/{uid}` — public
Deliberately excludes the exact `GeoPoint` (mirrored instead as a coarse `locationArea` geohash
prefix) and anything not explicitly mirrored — **default is private; a field only appears here
because it's named in the sync logic**, not because it merely "seems public." This is the fix for a
v1 design bug that would have exposed every user's exact location to any signed-in user.

**Sync mechanism:** `syncProfilePublic` (Eventarc trigger on `profiles/{uid}` writes) reads the
written profile, derives the public-relevant fields, and writes `profilesPublic/{uid}` via a full
`Set` (not a partial merge) — the trigger is the only writer, so no merge-conflict-with-a-client
scenario exists. Retries are naturally idempotent since the full derived state is recomputed from
`profiles/{uid}` on every run, not applied as a delta.

**Client read/write:** any authenticated user can read any doc; **no client write at all** — every
field is trigger-written only.

### `shifts/{shiftId}`
Core fields (`nurseryId`, `title`, `date`/`startTime`/`endTime`, `payRate`, `status`,
`paymentStatus`) plus shift-detail fields (`ageGroup`, `room`, `numberOfChildren`,
`expectedDuties`, `requirements`) and multi-capacity booking support (`bookedStaffIds` — the
authoritative list; the older singular `bookedStaffId` is kept in sync as "most recent acceptor"
only for backward compatibility) and stats-feeding fields (`firstAcceptedAt`, `noShowStaffIds`).

**No separate `bookings` collection** — the entire accept operation is a single-document
transactional update on `shifts/{id}` itself (§4). Booking *history* as an append-only
`shiftBookingEvents` subcollection remains a deliberately-deferred idea, not built.

**Client read/write:** any authenticated staff can read `open` shifts. A `booked` shift is only
fully readable by `nurseryId` and the booked staff. Nurseries write their own shifts' editable
fields while `status == 'open'`. **`status` and the booked-staff fields are never client-writable**
— only `acceptShift`/`cancelShift` (Admin SDK) set them.

### `ratings/{ratingId}`
`shiftId`, `raterId`, `rateeId`, `score` (1–5), `comment`, plus an optional `categoryScores` map
(communication/punctuality/professionalism/reliability/childEngagement, each 1–5, not present on
older ratings). Recompute path (`recomputeRating`, Eventarc create-trigger on `ratings`): reads the
new rating, recomputes `profiles/{rateeId}.rating` inside a Firestore transaction (needed because
two shifts completing near-simultaneously could race on the same ratee's aggregate), which cascades
to `profilesPublic` via the sync trigger — no special-casing needed. **Never computed
client-side.**

**Client read/write:** any authenticated user can create a rating for a shift they participated in
(ownership-checked against the shift's `nurseryId`/booked-staff pair). Immutable after creation.

### `chatSessions/{sessionId}/messages/{messageId}` — owned by communication service
`chatSessions/{sessionId}`: `shiftId`, `participantIds`, `createdAt`, `lastMessageAt`.
`messages/{messageId}`: `senderId`, `text`, `createdAt`, `readBy`. Session is created by
`onShiftBooked`, not by a client, so a chat session can't exist for a shift that was never booked.
Participants read/write messages within sessions they're a member of.

### `transactions/{transactionId}` — owned by payments service, reserved name only
`shiftId`, `payerId`, `payeeId`, `amount`, `stripeStatus`, Stripe Connect account refs, `createdAt`.
No documents created and no functions written against this yet — see §5.

### `documents/{docId}` — DBS/ID/qualification upload metadata
`uid`, `type` (DBS certificate, plus — added past the original design — CV, ID, qualifications,
first aid, right-to-work), `storagePath`, `status`, `uploadedAt`, `reviewedAt`, and `reviewNote`
(set on rejection, shown to the owner so a rejected upload isn't a dead end). Storage rules
(`storage.rules`) and Firestore rules are configured separately, cross-validated (the Firestore
create rule checks `storagePath` starts with the caller's own uid-scoped prefix).

### `notifications/{notificationId}` — owned by communication service
`uid` (recipient), `type`, `payload`, `read`, `createdAt`. Written only by communication-service
functions. Client can read their own notifications and update only the `read` boolean.

**Summary table — client-direct vs. Cloud-Function-only** (unchanged in shape from the original
design):

| Collection | Client direct (via Rules) | Function-only |
|---|---|---|
| `profiles` | read/write own (subset frozen) | `dbsStatus`, `rating`, `suspended`, verification badges; no other user can read at all |
| `profilesPublic` | read any doc, any authenticated user | 100% — every field, every write |
| `shifts` | read open shifts; nursery writes own open-shift fields | `status`, booked-staff fields (booking/cancel endpoints) |
| `ratings` | create (with ownership check) | recompute of `profiles.rating` (cascades to `profilesPublic`) |
| `chatSessions/messages` | read/write within own session | session creation |
| `transactions` | none | everything (payments codebase only; unused today) |
| `documents` | create own, read own | `status`, `reviewNote` (review endpoint) |
| `notifications` | read own, update own `read` flag | creation of the doc itself |

---

## 3. Authorization model

Two enforcement layers, disjoint by construction, unchanged from the original design:

- **Firestore Security Rules** enforce every *direct client read/write* — the full replacement for
  RLS. Rules run on every request regardless of platform.
- **Cloud Functions using the Admin SDK bypass Security Rules entirely.** Any write needing
  cross-document atomicity (booking), a computed/aggregate value (ratings), a privileged
  private→public sync, or a check too complex for the Rules language (DBS/admin review) is only
  reachable through an HTTP endpoint that does its own auth check (§1a's `RequireAuth` middleware)
  plus business logic, then writes with Admin privileges.

**Rule logic in plain English, collection by collection** — see `backend/firestore.rules` for the
literal, current rules (source of truth); the shape:

- `profiles/{uid}`: read/write only `request.auth.uid == uid`; write rejected if it touches any
  admin/system-owned field (`dbsStatus`, `rating`, `suspended`, verification badges).
- `profilesPublic/{uid}`: read any authenticated user; **no client write, ever**.
- `shifts/{shiftId}`: create only by the nursery, only while unbooked; read open shifts (any
  staff) or your own shift (nursery/booked staff); update only by the owning nursery, only while
  open, never touching booking fields.
- `ratings/{ratingId}`: create only by the actual rater on a shift they were actually party to; no
  update/delete via client rules ever.
- `chatSessions/{sessionId}`: read/write on `messages` gated by session membership; no client
  create of the parent doc.
- `documents/{docId}`: create/read owner-only; `status`/`reviewNote` frozen from client writes.
- `notifications/{notificationId}`: read owner-only; update owner-only and only the `read` boolean.

**No authorization logic lives only in frontend code** — every "function-only"/"frozen" field above
is backed by an actual Rules clause or a server-side check inside an HTTP handler.

---

## 4. The atomic booking operation

`acceptShift` (`POST /AcceptShift`, `functions-core`) — behind `RequireAuth`, additionally
requiring `role == 'staff'` on the caller's `profiles` doc (checked server-side).

Flow: verify token → confirm staff role (and DBS-verified status, if enforced) → run a Firestore
transaction that reads the shift, rejects if missing/not-open/self-booking, else writes
`status: 'booked'` plus the booked-staff field(s) → on commit, publish to `shift-booked` (outside
the transaction, since Pub/Sub isn't part of Firestore's transactional guarantee — a publish
failure doesn't undo a successful booking, it's logged and the booking stands) → respond `200`.

**Why this must be a transaction:** two staff members racing to accept the same shift both read
`status == 'open'` in a plain read-then-write; without a transaction both writes could succeed, one
silently clobbering the other. Firestore's Go client's `RunTransaction` re-reads and retries
automatically on write conflict, so the loser's retry re-reads `status == 'booked'` and returns
`SHIFT_ALREADY_BOOKED` cleanly.

`cancelShift` follows the same transactional pattern for the reverse operation, and additionally
publishes to `shift-cancelled` (consumed by `onShiftCancelled`, communication) when a *staff*
member cancels, so the nursery is notified their coverage was dropped.

**Error-code contract** (codes and HTTP statuses, unchanged from the original design):

| Condition | HTTP status | `error.code` |
|---|---|---|
| Not authenticated | `401` | `NOT_AUTHENTICATED` |
| Caller isn't staff | `403` | `NOT_STAFF` |
| Shift doc missing | `404` | `SHIFT_NOT_FOUND` |
| `status != 'open'` | `409` | `SHIFT_ALREADY_BOOKED` |
| Nursery accepting own shift | `409` | `CANNOT_BOOK_OWN_SHIFT` |

---

## 5. Payments design (still deferred — design only)

**Not built.** The eventual real implementation is **Stripe Connect** (Express accounts for both
nurseries and staff) — a marketplace shape, unlike the Firestore "Run Payments with Stripe"
extension, which models one business selling to many customers. See
`backend/services/payments/TODO.md` for the concrete build plan when this becomes a priority.

What exists today: `shifts.paymentStatus` (defaults `'not_required'`, no flow sets it to
`'pending'`/`'paid'` yet), the reserved-but-unused `transactions` collection, and
`functions-payments`'s single stub endpoint (`CreatePayout`, always `501
PAYMENTS_NOT_YET_BUILT`) — enough to prove the three-service deploy/call wiring end to end without
any Stripe dependency or API keys.

---

## 6. Notifications design (FCM)

- **Token registration:** `profiles/{uid}/fcmTokens/{tokenId}` subcollection. `RegisterFcmToken`
  upserts a doc keyed by the token itself (idempotent re-registration on app relaunch);
  `UnregisterFcmToken` deletes it (logout, or self-cleanup when an FCM send returns an
  invalid-token error).
- **Delivery triggers**, each a Pub/Sub topic + communication-side consumer: `shift-booked` →
  `onShiftBooked` (pushes + notifies both parties, creates the chat session);
  `shift-cancelled` → `onShiftCancelled` (notifies the nursery when staff cancel);
  `shift-matched` → `onShiftMatched` (per-candidate-staff notification when `matchNewShift`, core,
  finds matches for a newly-created open shift — the matching logic itself is still a placeholder,
  §8); `rating-received` → `onRatingReceived`.
- **In-app record vs. push — both, deliberately:** a `notifications/{id}` doc is written for every
  trigger above independent of whether the FCM send succeeds — it's the source of truth an in-app
  notifications screen reads; push is a best-effort nudge that can fail silently. Order: write the
  `notifications` doc first, then attempt the FCM send.

---

## 7. Local development & testing strategy

See `backend/README.md` for the full, current walkthrough (emulator setup, seed data, running each
service's functions locally, the `devharness` trigger-dispatch workaround, Bruno collection). That
document is kept current with the actual local-dev commands; this section is not duplicated here to
avoid drift.

---

## 8. Open items — status update

Originally flagged as unresolved product/legal questions, not engineering ones. Current state:

1. **Identity verification at sign-up** — still email-only at sign-up time; `identityVerified` now
   exists as an admin-settable badge (`setVerificationBadge`) for post-hoc verification, but there's
   no automated identity-proofing flow.
2. **DBS verification method — resolved.** Document upload + manual admin review, exactly the
   originally-guessed design: `createDocument`/`reviewDocument`/`listPendingDocuments`, with
   `dbsStatus` gating `acceptShift` and a `reviewNote` shown to the owner on rejection.
3. **Employer-of-record question** — still open; blocks committing to a Stripe Connect topology.
   Payments remains a stub pending this.
4. **Geographic matching radius logic** — still a placeholder. `matchNewShift` exists and proves
   the fan-out contract (core → `shift-matched` topic → per-candidate notification), but the actual
   radius/matching algorithm is simplified, not the final intended logic.
5. **Minimum shift notice period** — still open; not enforced at shift-creation time.

---

## What's explicitly *not* in this document

Exact current field lists (`backend/services/core/models.go` is the source of truth), local-dev
command specifics (`backend/README.md`), one-time GCP/Firebase project provisioning steps
(`backend/PRODUCTION_SETUP.md`), and the current list of known gaps/limitations
(`KNOWN_ISSUES.md`, repo root).
