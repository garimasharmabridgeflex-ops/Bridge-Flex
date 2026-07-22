# Bridge Flex — Backend Architecture (Phase 0, v2)

Status: **draft, pending approval**. No code has been written against this design yet.
This is v2 — revised from the approved v1 to fix two issues (§2/§3 field-exposure leak,
§1/§4 language change to Go). Everything not touched by those two changes is carried over
as previously approved.

Bridge Flex is a two-sided marketplace: nurseries post last-minute shifts, staff accept them
(first-accept-wins, no double-booking), with a trust layer (DBS status, ratings) and, later,
payments and chat. This is built on **Firebase** — Firestore, not Data Connect/SQL Connect —
because Firestore's free tier requires no billing account and no card. Where the product spec
references Postgres/Supabase concepts (RLS, "Postgres function"), that's prior art describing
*intent* — the translation into Firestore idiom is what follows.

Budget reality that shapes every decision here: no card is linked, so nothing in Phase 1 may
require Blaze. Everything must run and be fully testable locally. Card-linking and going live
are deliberately out of scope until a separate, later decision.

**What changed in v2, up front:**

1. `profiles/{uid}` is now split into a private doc and a `profilesPublic/{uid}` doc, kept in
   sync by a Cloud Function trigger, because Security Rules can only allow/deny a whole document
   — they cannot redact individual fields. The v1 design accidentally exposed every user's exact
   `GeoPoint` location to any signed-in user.
2. The backend is **Go**, not Node.js. `firebase-functions` (the SDK that gives you `onCall`,
   `HttpsError`, and the Functions emulator inside `firebase emulators:start`) only supports
   Node.js and Python. Go runs on plain **Cloud Functions (2nd gen)** — HTTP handlers plus
   Eventarc trigger bindings, not code-level decorators. This changes the transport and local-dev
   story throughout; it does not change the data model, the Rules logic, the `acceptShift`
   transaction semantics, or the error *codes* — only how they're carried over the wire.

---

## 1. Service boundaries

Three separate Go modules, each its own deployable **Cloud Function (2nd gen)** — which is
itself a managed Cloud Run service under the hood — sharing one Firebase project, one Firestore
instance, one Auth instance:

- **`functions-core`** (`services/core/go.mod`) — profiles (private + public), shifts, booking,
  ratings, documents metadata. Owns Auth-triggered profile initialization.
- **`functions-payments`** (`services/payments/go.mod`) — owns Stripe Connect integration
  end to end. Stubbed in Phase 1 (§5); real Stripe code arrives later.
- **`functions-communication`** (`services/communication/go.mod`) — chat messages, FCM tokens,
  notification delivery.

This split is actually a *cleaner* match for "separate service" under Go than the Node
multi-codebase array was in v1: each is a genuinely independent binary with its own `go.mod`,
own dependency tree, own deploy (`gcloud functions deploy` or `firebase deploy` targeting one
function at a time — there's no shared `functions/` directory to accidentally couple them
through). The reasons to keep them separate are unchanged from v1:

- **Blast radius / deploy independence** — a bad payments deploy can't take down booking.
- **Dependency isolation** — only `functions-payments`'s `go.mod` ever imports the Stripe Go SDK;
  core and communication never pull that dependency or its transitive surface into their binary.
- **Ownership enforced by code structure** — cross-boundary writes go through the explicit
  contract below (HTTP calls, Pub/Sub), not a shared package that could silently reach across.
- **Cost/quota isolation later** — once on Blaze, each service's Cloud Run revision is billed and
  rate-limited independently.

**Concrete call/trigger paths** (unchanged in shape from v1; transport detail below in §1a):

- **Booking → Communication:** `acceptShift` (core, plain HTTP handler) commits the Firestore
  transaction, then publishes to a `shift-booked` Pub/Sub topic (payload: `shiftId`, `nurseryId`,
  `staffId`). `functions-communication` deploys a function bound to that topic via an Eventarc
  trigger, which sends FCM pushes to both parties, writes a `notifications/{id}` doc for each,
  and initializes `chatSessions/{sessionId}` if one doesn't already exist for that shift.
- **Core → Payments:** core sets `shifts/{id}.paymentStatus = 'pending'` directly at
  shift-creation time when payment will be required (this field is core-owned and written as
  part of the shift doc — no cross-service call needed for that specific field). Actual payment
  *processing* is a payments-owned HTTP endpoint (`functions-payments`'s `/createPayout`, stubbed
  in Phase 1) that core calls as a normal authenticated HTTP request (a Go service account
  identity token, verified by the same middleware described in §1a) once payments is real.
- **Payments → Core (write-back):** payments writes only to `shifts/{id}.paymentStatus` and to
  its own `transactions` collection — never to `profiles`/`profilesPublic`, never to any other
  `shifts` field.
- **Rating → Core (aggregate):** an Eventarc Firestore trigger on `ratings/{ratingId}` creates,
  bound to a `functions-core` function, recomputes `profilesPublic/{rateeId}.rating` (public,
  since rating is a public-facing trust signal — see §2). Both `ratings` and `profilesPublic` are
  core-owned, so this stays inside core.
- **Core-internal sync: `profiles` → `profilesPublic`:** an Eventarc Firestore trigger on
  `profiles/{uid}` writes, bound to `functions-core`, mirrors public-relevant fields into
  `profilesPublic/{uid}` whenever they change. Detailed in §2.

Why Pub/Sub for booking→communication specifically: booking is the one event with plausible
future fan-out (communication now; matching/analytics later). A topic lets consumers be added
without touching `acceptShift`. Payments stays a direct call because there's exactly one caller,
one callee, and a synchronous request/response shape.

### 1a. Transport, auth, and triggers under Go (replaces v1's `onCall`/`HttpsError`/decorator model)

**No `onCall`.** Every core/payments/communication endpoint that a client calls directly is a
plain HTTP handler (`net/http`, run locally via `functions-framework-go` and deployed as an HTTP
Cloud Function). There is no framework-provided request/response envelope — request and response
bodies are plain JSON the handler decodes/encodes itself.

**Auth is manual, via a shared middleware.** Every HTTP-triggered handler wraps its logic in a
common `RequireAuth` middleware (one implementation, imported by all three services, not
reimplemented per-handler) that:
1. Reads the `Authorization: Bearer <ID token>` header.
2. Verifies it with the Firebase Admin SDK for Go
   (`firebase.google.com/go/v4/auth`, `client.VerifyIDToken(ctx, token)`).
3. On failure, writes the standard error envelope (below) with `401` and returns without calling
   the handler.
4. On success, attaches the decoded `uid` (and any custom claims) to the request context for the
   handler to read.

**No `HttpsError`.** One JSON error contract, defined once and reused everywhere v1 specified an
`HttpsError` code:
```json
{ "error": { "code": "SHIFT_ALREADY_BOOKED", "message": "This shift is no longer available" } }
```
paired with a matching HTTP status per code (see the table in §4 — the code *strings* and
*meanings* approved in v1 are unchanged, only the wrapper is new: an `HttpsError('failed-precondition', 'SHIFT_ALREADY_BOOKED')`
becomes `writeError(w, http.StatusConflict, "SHIFT_ALREADY_BOOKED", "This shift is no longer available")`).

**Triggers are Eventarc bindings, deployed, not coded.** Every function that reacted to a
Firestore write, an Auth event, or a Pub/Sub message in v1 (ratings recompute, `profiles`→
`profilesPublic` sync, Auth-triggered profile init, the `shift-booked` consumer) is deployed with
an explicit event filter rather than an `onCreate`/`onUpdate` decorator in code:

| Function | Trigger | Event filter (deploy-time) |
|---|---|---|
| `initProfileOnSignUp` (core) | Auth user created | `google.firebase.auth.user.v1.created` |
| `syncProfilePublic` (core) | Firestore write | `google.cloud.firestore.document.v1.written`, filtered to `profiles/{uid}` |
| `recomputeRating` (core) | Firestore create | `google.cloud.firestore.document.v1.created`, filtered to `ratings/{ratingId}` |
| `matchNewShift` (core) | Firestore create | `google.cloud.firestore.document.v1.created`, filtered to `shifts/{shiftId}` |
| `onShiftBooked` (communication) | Pub/Sub message | topic `shift-booked` |
| `onRatingReceived` (communication) | Pub/Sub message | topic `rating-received` |

Each handler's function signature takes a `CloudEvent` (Firestore/Auth triggers) or a
`PubSubMessage` (Pub/Sub triggers) as defined by `functions-framework-go`, decodes the
event-specific payload (a `DocumentEventData` protobuf-derived struct for Firestore events), and
runs the same business logic v1 described — the *logic* is identical, only the invocation
mechanics differ.

**Codebases are literal Go modules**, each `go.mod`-rooted, each function within a
service exported as its own entry point registered with `functions-framework-go`'s
`functions.HTTP(...)` / `functions.CloudEvent(...)` registration calls in an `init()`.

**Local dev — several processes, not one unified emulator UI.** Each HTTP-style function runs
locally as its own process via `functions-framework-go` (e.g. `FUNCTION_TARGET=AcceptShift
go run cmd/main.go`, one port per function or one process serving several `net/http` routes if
grouped), pointed at the Firestore/Auth/Storage emulators via `FIRESTORE_EMULATOR_HOST`,
`FIREBASE_AUTH_EMULATOR_HOST`, `FIREBASE_STORAGE_EMULATOR_HOST`. This is still fully free and
requires no card — the difference from v1 is operational, not financial: instead of one
`firebase emulators:start` process hosting all Node functions, you run the Firestore/Auth/
Storage/Pub-Sub emulators (still via `firebase emulators:start`, since those emulators are
language-agnostic — they're not the Functions emulator) *plus* N separate `go run` processes for
the HTTP-triggered Go functions, one per service or grouped by service into one process per
service exposing multiple routes.

**Be honest about the gap: trigger-based functions have no clean local "fires automatically"
story in Go.** `firebase-functions` gives Node a Functions emulator that actually listens for
Firestore/Auth/Pub-Sub events and invokes your code automatically. `functions-framework-go` does
not integrate with the Firestore/Auth emulators as an automatic trigger dispatcher — there is no
equivalent of "write a doc to the Firestore emulator and watch your Go Eventarc function fire."
For Phase 1, the testing approach for `syncProfilePublic`, `recomputeRating`, `matchNewShift`,
and the Pub/Sub-triggered communication functions is **direct unit tests of the handler function
against a hand-constructed event payload** (build a `DocumentEventData`/`PubSubMessage` struct
in the test, call the handler function directly, assert on the resulting Firestore state via the
Admin SDK against the emulator). This verifies the handler logic correctly but does not exercise
the real Eventarc dispatch path — that only gets tested once deployed to a live (Blaze) project.
This is a genuine gap versus v1's claim, not something to paper over.

**Bruno simplifies, it doesn't complicate.** Since there's no callable envelope, each `.bru`
request is a plain `POST` with a normal JSON body and a normal `Authorization: Bearer <token>`
header — see §7 for the (now shorter) folder/request design.

---

## 2. Data model (Firestore)

Collections are shaped around query patterns, not a relational ER diagram. Two guiding rules:
(1) anything read together on a hot path gets denormalized onto the doc you're already fetching;
(2) anything requiring cross-document atomicity or a privileged check is a Cloud Function, never
a direct client write.

### `profiles/{uid}` — private
```
role: 'nursery' | 'staff'
name: string
location: GeoPoint            // exact — for radius matching computation, server-side only
description: string           // nursery only
dbsStatus: 'unverified' | 'pending' | 'verified'   // staff only
rating: { average: number, count: number }          // canonical source; mirrored to public doc
createdAt: Timestamp
```
`profiles/{uid}/fcmTokens/{tokenId}` — **subcollection**, not an array field (unchanged from v1:
a user can have multiple devices; subcollection lets each token carry its own metadata and be
added/removed without a read-modify-write race on the parent doc, and lets stale-token cleanup on
push failure be a simple doc delete rather than an array filter-and-rewrite).

**Client read/write:** owner-only for both read and write on the document itself. Write is
further restricted so `dbsStatus` and `rating` are frozen from the client (§3). No other user can
read this document at all — this is the whole point of the split below.

### `profilesPublic/{uid}` — public, new in v2
```
role: 'nursery' | 'staff'
name: string
locationArea: string          // coarse — geohash prefix (e.g. 5-char, ~5km) or named area, never exact coords
rating: { average: number, count: number }   // mirror of profiles/{uid}.rating
dbsBadge: 'unverified' | 'pending' | 'verified'   // mirror of profiles/{uid}.dbsStatus, exposed as a badge
updatedAt: Timestamp          // set by the sync trigger, for staleness debugging
```
Deliberately excludes: exact `GeoPoint`, `description` (nursery detail — low sensitivity but no
product requirement to expose it publicly yet, so it stays private by default rather than
opt-in-exposed without a stated need), and anything not explicitly listed above. **Default is
private; a field only appears in `profilesPublic` because it's named here**, not because it
merely "seems public."

**Why a coarse `locationArea` string rather than a coarser `GeoPoint`:** geohash-prefix-as-string
is queryable (`where('locationArea', '==', '...')` or range-query on prefix) the same way a
`GeoPoint` isn't natively range-queryable in Firestore anyway (§8 open item #4 already flags that
real radius search needs a geohash scheme regardless) — so committing to a geohash-prefix string
now for the *public* field serves both the safeguarding fix and the future matching-query need
at once, without waiting on the radius-logic product decision to land first. The prefix length
(how coarse) is a tunable constant, not decided here — start with a value coarse enough that it
narrows to a wide area (city-sized), not a street.

**Sync mechanism:** `syncProfilePublic`, an Eventarc trigger on `profiles/{uid}` writes (§1a
table), reads the written `profiles/{uid}`, derives the public-relevant fields (recomputing
`locationArea` from `location` via geohash, copying `rating`, mapping `dbsStatus` → `dbsBadge`,
copying `role`/`name`), and writes `profilesPublic/{uid}` via `Set` (full overwrite of the
derived fields, not a partial merge of arbitrary client input — the trigger is the only writer,
so there's no merge-conflict-with-a-client-write to worry about).

**Failure handling for the sync trigger:** Eventarc/Cloud Functions retries on failure if the
function is deployed with retry-on-failure enabled (a deploy-time flag), which is the right
setting here — a failed sync means `profilesPublic` is stale (shows an old rating or DBS badge)
rather than wrong-and-dangerous (it never *invents* data, worst case it lags). Because the trigger
recomputes the full derived state from `profiles/{uid}` on every run rather than applying a delta,
retries are naturally idempotent — replaying the same write event twice produces the same
`profilesPublic` doc both times. The known residual risk: if the *last* write to a profile's
public-relevant fields triggers a sync that fails permanently (exhausts retries), `profilesPublic`
stays stale until the next unrelated write to that profile. Acceptable for Phase 1 (nothing here
is safety-critical enough to need a reconciliation job); worth a note for later that a periodic
reconciliation sweep (compare `profiles` vs `profilesPublic`, re-sync mismatches) would close this
gap if staleness turns out to matter in practice.

**`rating` recompute now targets `profilesPublic` directly, with `profiles` following.** Since
`rating` is public-facing by definition, `recomputeRating` (§1a) writes the new aggregate to
`profiles/{rateeId}.rating` (the canonical value) inside its transaction, which — being a write to
`profiles` — triggers `syncProfilePublic` to mirror it into `profilesPublic/{rateeId}.rating`
automatically. No special-casing needed: rating recompute goes through the same private→public
sync path as any other profile field change, rather than writing `profilesPublic` twice from two
different functions.

**Client read/write summary:**
- `profiles/{uid}`: owner reads/writes own (with `dbsStatus`/`rating` frozen); no other user can
  read it.
- `profilesPublic/{uid}`: any authenticated user can read any doc; **no client write at all** —
  every field is trigger-written only.

### `shifts/{shiftId}`
```
nurseryId: string (uid)
title: string
date: string (YYYY-MM-DD)
startTime: Timestamp
endTime: Timestamp
payRate: number
status: 'open' | 'booked' | 'cancelled'
bookedStaffId: string | null
paymentStatus: 'not_required' | 'pending' | 'paid'   // stub field, see §5
createdAt: Timestamp
```
Unchanged from v1.

**No separate `bookings` collection.** Given "first accept wins" and no double-booking, the
entire operation is: read one `shifts/{id}` doc, check `status`, conditionally write `status` +
`bookedStaffId` back onto that same doc, inside one Firestore transaction. A separate `bookings`
collection would mean the transaction touches two documents for zero query benefit — a composite
index on `shifts` (`status`, `bookedStaffId`) answers "my booked shifts" directly. If booking
*history* becomes a requirement later (e.g. rebooking after cancellation), that's the point to
add an append-only `shiftBookingEvents` subcollection — deliberately deferred, not designed now.

**Client read/write:** any authenticated staff can read `open` shifts (list query). A `booked`
shift is only fully readable by `nurseryId` and `bookedStaffId` (§3). Nurseries write their own
shifts' `title`/`date`/`times`/`payRate` while `status == 'open'`. **`status` and
`bookedStaffId` are never client-writable** — only `acceptShift` (Admin SDK) sets them. Cancel is
a separate endpoint (`cancelShift`), not a raw client field write, because cancellation needs to
check who's allowed to cancel and trigger a communication-service notification.

### `ratings/{ratingId}`
```
shiftId: string
raterId: string (uid)
rateeId: string (uid)
score: number (1-5)
comment: string
createdAt: Timestamp
```
Recompute path (§1a: `recomputeRating`, an Eventarc trigger on `ratings` create): reads the new
rating, reads `profiles/{rateeId}.rating` inside a Firestore transaction (needed because two
shifts completing near-simultaneously could both trigger a recompute for the same ratee — a plain
read+write would race), computes `{average: (average*count + score)/(count+1), count: count+1}`,
writes it back to `profiles/{rateeId}.rating` — which cascades to `profilesPublic` via the sync
trigger above. **Never computed client-side** — a client computing its own `rating.average` would
be trivially forgeable.

**Client read/write:** any authenticated user can create a rating for a shift they participated
in (rule checks `raterId == request.auth.uid` and that the shift's `bookedStaffId`/`nurseryId`
matches the pair). Ratings are immutable after creation — disputes are a manual-review problem,
not a re-edit-the-rating problem.

### `chatSessions/{sessionId}/messages/{messageId}` — owned by communication service
```
chatSessions/{sessionId}: { shiftId, participantIds: [nurseryId, staffId], createdAt, lastMessageAt }
messages/{messageId}: { senderId, text, createdAt, readBy: [uids] }
```
Session is created by the `onShiftBooked` Pub/Sub-triggered function (§1a), not by a client, so a
chat session can't exist for a shift that was never booked. Participants read/write messages
within sessions they're a member of.

### `transactions/{transactionId}` — owned by payments service, reserved name only in Phase 1
```
shiftId, payerId, payeeId, amount, stripeStatus, stripeConnectAccountId (payer + payee refs), createdAt
```
No documents created and no functions written against this in Phase 1 — see §5.

### `documents/{docId}` — DBS upload metadata
```
uid: string
type: 'dbs_certificate'
storagePath: string        // points into Cloud Storage, not the file itself
status: 'pending_review' | 'verified' | 'rejected'
uploadedAt: Timestamp
reviewedAt: Timestamp | null
```
Storage rules (`storage.rules`) and Firestore rules are configured separately: a client uploading
to `/dbs-documents/{uid}/{filename}` is gated by Storage rules (only that `uid` may write to
their own path, images/PDF only, under a size cap); the `documents/{docId}` metadata doc is gated
by Firestore rules (owner can create/read their own; `status` is Admin-SDK-only). The Firestore
create rule also validates `storagePath` starts with `dbs-documents/{request.auth.uid}/` to keep
the two consistent.

### `notifications/{notificationId}` — owned by communication service
```
uid: string (recipient)
type: 'shift_booked' | 'new_matching_shift' | 'rating_received'
payload: map                  // shiftId, raterId, etc. depending on type
read: boolean
createdAt: Timestamp
```
Written only by communication-service functions. Client can read their own notifications and
update only the `read` boolean on their own docs.

**Summary table — client-direct vs. Cloud-Function-only:**

| Collection | Client direct (via Rules) | Function-only |
|---|---|---|
| `profiles` | read/write own (subset frozen) | `dbsStatus`, `rating`; no other user can read at all |
| `profilesPublic` | read any doc, any authenticated user | 100% — every field, every write |
| `shifts` | read open shifts; nursery writes own open-shift fields | `status`, `bookedStaffId` (booking/cancel endpoints) |
| `ratings` | create (with ownership check) | recompute of `profiles.rating` (cascades to `profilesPublic`) |
| `chatSessions/messages` | read/write within own session | session creation |
| `transactions` | none | everything (payments codebase only; N/A in Phase 1) |
| `documents` | create own, read own | `status` (review endpoint) |
| `notifications` | read own, update own `read` flag | creation of the doc itself |

---

## 3. Authorization model

Two enforcement layers, disjoint by construction:

- **Firestore Security Rules** enforce every *direct client read/write* — the full replacement
  for RLS. Rules run on every request regardless of platform, so there is no client-side bypass.
- **Cloud Functions using the Admin SDK bypass Security Rules entirely.** Any write needing
  cross-document atomicity (booking), a computed/aggregate value (ratings), a privileged
  private→public sync, or a check too complex for the Rules language (DBS manual review) is only
  reachable through an HTTP endpoint that does its own auth check (§1a's `RequireAuth`
  middleware) plus business logic, then writes with Admin privileges.

**Rule logic in plain English, collection by collection:**

- `profiles/{uid}`: **read** — only `request.auth.uid == uid` (no one else, at all — this is the
  fix). **Write** — only `request.auth.uid == uid`, and the write must be rejected if it touches
  `dbsStatus` or `rating` (those keys must be unchanged from the existing doc).
- `profilesPublic/{uid}`: **read** — any authenticated user. **Write** — no client write, ever;
  Rules deny all client writes unconditionally (`allow write: if false`) since only the
  `syncProfilePublic` function, via Admin SDK, may write this collection.
- `profiles/{uid}/fcmTokens/{tokenId}`: only the owning uid may create/delete their own tokens;
  no client read needed (server-only reads to send pushes).
- `shifts/{shiftId}`: **create** — only if `request.auth.uid == request.resource.data.nurseryId`
  and `status == 'open'` and `bookedStaffId == null` at creation. **Read** — allowed if
  `status == 'open'` (any authenticated staff), or if `request.auth.uid` is `nurseryId` or
  `bookedStaffId` on that doc. **Update** — only `nurseryId`, only while `status == 'open'`, and
  must not change `status` or `bookedStaffId` (frozen from the client's perspective no matter
  what — the transaction endpoint is the only writer).
- `ratings/{ratingId}`: **create** — `request.auth.uid == request.resource.data.raterId`, plus a
  `get()` check that the referenced shift actually has this rater/ratee pair in
  `nurseryId`/`bookedStaffId`. No update, no delete, for anyone via client rules.
- `chatSessions/{sessionId}`: read/write on `messages` gated by
  `request.auth.uid in get(/databases/$(database)/documents/chatSessions/$(sessionId)).data.participantIds`.
  No client create of the parent `chatSessions` doc.
- `transactions/{transactionId}`: no client rules at all in Phase 1 (collection unused); when
  payments is built, stays function-only permanently.
- `documents/{docId}`: **create** — owner only, `storagePath` prefix-validated as in §2. **Read**
  — owner only. `status` frozen from client writes.
- `notifications/{notificationId}`: **read** — owner only. **Update** — owner only, and only the
  `read` boolean may change. No client create/delete.

**Explicit flag: no authorization logic may live only in frontend code.** Every field listed
above as "function-only" or "frozen" must be backed by an actual Rules clause or a server-side
auth check inside an HTTP handler — the frontend hiding a button is not a security boundary.

---

## 4. The atomic booking operation

`acceptShift` — a plain HTTP handler (`POST /acceptShift`) in `functions-core`, behind the
`RequireAuth` middleware (§1a), additionally requiring `role == 'staff'` on the caller's
`profiles` doc (checked server-side, not trusted from the client payload).

Flow:

1. Client sends `POST /acceptShift` with body `{"shiftId": "..."}` and
   `Authorization: Bearer <ID token>`.
2. `RequireAuth` middleware verifies the token; on failure responds `401` with
   `{"error": {"code": "NOT_AUTHENTICATED", ...}}` and the handler never runs.
3. Handler reads the caller's `profiles/{uid}` (outside the transaction, since it's not being
   mutated) to confirm `role == 'staff'`; on failure responds `403` /
   `{"error": {"code": "NOT_STAFF", ...}}`. Also check `dbsStatus == 'verified'` here if that's a
   hard requirement before accepting shifts (flagged as a product decision in §8 — DBS
   verification method isn't settled, so this check's exact condition is a placeholder).
4. `firestoreClient.RunTransaction(ctx, func(ctx, tx) error { ... })`:
   - `tx.Get(shiftRef)`.
   - If doc doesn't exist → return a sentinel error mapped to `404` /
     `{"error": {"code": "SHIFT_NOT_FOUND", ...}}`.
   - If `status != "open"` → return a sentinel error mapped to `409` /
     `{"error": {"code": "SHIFT_ALREADY_BOOKED", ...}}`.
   - If `nurseryId == callerUid` (nursery accepting its own shift) → `409` /
     `{"error": {"code": "CANNOT_BOOK_OWN_SHIFT", ...}}`.
   - Else `tx.Update(shiftRef, []firestore.Update{{Path: "status", Value: "booked"},
     {Path: "bookedStaffId", Value: callerUid}})`.
5. On successful commit, publish to `shift-booked` Pub/Sub topic (outside the transaction —
   Pub/Sub publish isn't part of Firestore's transactional guarantee; if the publish fails, the
   booking still stands and a retry/backfill mechanism, not a rollback, is the right response
   since the booking itself is the source of truth).
6. Respond `200` with `{"shiftId": "...", "status": "booked"}`.

**Why this must be a transaction and not a plain conditional update:** two staff members racing
to accept the same shift both read `status == 'open'` in a plain read-then-write; without a
transaction both writes could succeed, one silently clobbering the other — exactly the
double-booking bug this feature exists to prevent. Firestore's Go client's `RunTransaction`
re-reads and retries automatically on write conflict, so the second caller's transaction
re-executes, re-reads `status == 'booked'` on retry, and returns `SHIFT_ALREADY_BOOKED` — a
clean, correct "sorry, someone else got it first" instead of a silent double-accept.

**Error-code contract** (codes and meanings carried over unchanged from v1; transport is now the
JSON envelope from §1a instead of `HttpsError`):

| Condition | HTTP status | `error.code` |
|---|---|---|
| Not authenticated | `401` | `NOT_AUTHENTICATED` |
| Caller isn't staff | `403` | `NOT_STAFF` |
| Shift doc missing | `404` | `SHIFT_NOT_FOUND` |
| `status != 'open'` | `409` | `SHIFT_ALREADY_BOOKED` |
| Nursery accepting own shift | `409` | `CANNOT_BOOK_OWN_SHIFT` |

Frontend maps `SHIFT_ALREADY_BOOKED` specifically to "This shift is no longer available" and
refreshes the shift list on that error (the client's local `open` shift list is now stale).

---

## 5. Payments design (deferred — design only)

**Not building this now.** The Firestore "Run Payments with Stripe" extension is the wrong tool
for later — it models one business selling to many customers, and Bridge Flex needs to pay *out*
to staff and collect from/on behalf of nurseries — a marketplace shape. The eventual real
implementation is **Stripe Connect**, Express accounts for both nurseries (if "nursery pays
directly" wins the open question in §8) and staff. Noting this now so nobody reaches for the
extension later as a shortcut.

What Phase 1 actually creates:

- `shifts.paymentStatus: 'not_required' | 'pending' | 'paid'`, defaulting to `'not_required'`.
  Phase 1 can default every shift to `'not_required'` unconditionally, since there's no payment
  flow to trigger `'pending'` yet. Lives on `shifts` (not a separate doc) so every shift can
  expose a "payment pending" badge in the UI regardless of whether payments is built —
  reshaping this later would mean migrating every existing shift doc.
- `transactions` collection: name reserved, schema sketched (§2), **zero documents, zero
  functions** in Phase 1.
- `functions-payments` Go module: created as a stub — a `TODO.md` describing what goes here
  (Stripe Connect account creation, webhook handler, payout endpoint) and a single placeholder
  HTTP handler, `POST /createPayout`, that responds `501` /
  `{"error": {"code": "PAYMENTS_NOT_YET_BUILT", "message": "..."}}`, so the module builds and
  deploys cleanly and the three-service wiring is proven end-to-end without pulling in the Stripe
  Go SDK or requiring any API keys.

---

## 6. Notifications design (FCM)

- **Token registration:** `profiles/{uid}/fcmTokens/{tokenId}` subcollection (§2). An HTTP
  endpoint `POST /registerFcmToken` (`{token, platform}`) in `functions-communication` upserts a
  doc keyed by the token itself (idempotent re-registration on app relaunch). A companion
  `POST /unregisterFcmToken` deletes it (logout, and also invoked internally when an FCM send
  returns an invalid-token error, to self-clean stale tokens).
- **Delivery triggers:**
  - *Shift booked* → `shift-booked` Pub/Sub topic (§1) → `onShiftBooked` (communication, Eventarc
    Pub/Sub trigger) sends FCM to both parties and writes a `notifications` doc for each.
  - *New shift matching availability* → needs a "does this shift match this staff member" compute
    (location radius, availability) which is a core-backend concern (owns `shifts`/`profiles`),
    so `matchNewShift` (core, Eventarc Firestore-create trigger on `shifts`, §1a table) queries
    candidate matching staff and publishes to a `shift-matched` Pub/Sub topic (one message per
    matched staff, keeping the communication consumer simple). Communication subscribes the same
    way it does to `shift-booked`.
  - *Rating received* → `recomputeRating` (core, §2/§4) publishes to a `rating-received` topic
    after committing the aggregate; `onRatingReceived` (communication) pushes/notifies. Kept as a
    separate topic from `shift-booked` since these are semantically distinct events with
    different payloads.
- **In-app record vs. push — both, deliberately:** a `notifications/{id}` doc is written by
  communication for every trigger above, independent of whether the FCM send succeeds — it's the
  source of truth an in-app notifications screen reads live; push is a best-effort nudge that can
  fail silently (expired token, uninstalled app, OS-level notifications disabled). Order: write
  the `notifications` doc first, then attempt the FCM send — never the reverse, since a failed
  doc-write-after-successful-push would mean a user got a push with no corresponding in-app
  record to tap into.

---

## 7. Local development & testing strategy

- **Firestore/Auth/Storage/Pub-Sub emulators** run via `firebase emulators:start` (these four are
  language-agnostic — they emulate the *data plane* Firestore/Auth/Storage/Pub-Sub APIs, not
  Node's Functions runtime, so they work identically regardless of what language calls them).
  Fixed ports configured in `firebase.json`. Security Rules are loaded and enforced by the
  Firestore/Storage emulators exactly as they will be live, so rules-unit-tests run against the
  emulator, not a mock.
- **Go functions run as separate local processes** via `functions-framework-go`, one process (or
  one process per service, serving multiple HTTP routes) per HTTP-triggered function, each
  pointed at the emulators via `FIRESTORE_EMULATOR_HOST` / `FIREBASE_AUTH_EMULATOR_HOST` /
  `FIREBASE_STORAGE_EMULATOR_HOST` env vars. This is the operational cost of Go noted in §1a: N
  local processes instead of one unified `firebase emulators:start` covering everything. Still
  entirely free, no card.
- **Eventarc-triggered functions are tested as direct unit tests**, not via live local trigger
  dispatch (§1a explains the gap: no local Firestore/Auth/Pub-Sub emulator integration invokes Go
  Eventarc handlers automatically). Each trigger handler (`syncProfilePublic`, `recomputeRating`,
  `matchNewShift`, `onShiftBooked`, `onRatingReceived`) gets a Go test that constructs the
  relevant event payload by hand, calls the handler function directly, and asserts on resulting
  Firestore/FCM-mock state via the Admin SDK against the emulator.
- **Stripe in emulator mode — decision: nothing to mock in Phase 1.** Payments is a stub with no
  real Stripe calls at all (§5), so there's nothing to forward webhooks *to* yet. When real
  Stripe Connect work starts later, the recommendation is Stripe CLI's
  `stripe listen --forward-to` pointed at the local `functions-payments` webhook handler for
  webhook testing, combined with Stripe's official test mode (not a hand-rolled mock client) for
  SDK calls, since test mode is free and produces more realistic behavior than mocking by hand.
- **Seed data**: an Admin-SDK (Go) script pointed at emulator hosts via the same env vars above,
  run after `emulators:start`, creating sample nursery/staff Auth users + `profiles` +
  `profilesPublic` docs (seeded directly, bypassing the sync trigger since there's no live
  dispatch to rely on locally — the seed script writes both docs itself) and shifts in various
  states (`open`, `booked`, `cancelled`).
- **Bruno collection** — folder structure, simplified from v1 now that there's no callable
  envelope to document:
  ```
  bruno/
    bruno.json
    environments/
      Emulator.bru        # points at each local Go process's host:port, uses emulator Auth for tokens
      Production.bru       # placeholder values, unused until go-live
    auth/                  # sign-up/sign-in flows against Auth emulator REST API
    profiles/
    shifts/
    booking/               # acceptShift, cancelShift
    payments/               # placeholder request hitting the 501 stub
    communication/          # token registration, notification/chat reads
  ```
  Each `.bru` file is a plain `POST` with a normal JSON body and a normal
  `Authorization: Bearer <token>` header — no envelope construction, no wrapped
  `{"data": ...}`/`{"result": ...}` shape to document, since these are ordinary HTTP handlers.
  Simpler than v1's note about documenting the callable envelope format.

---

## 8. Open items — flagging back, not deciding

Unchanged from v1 — still product/legal calls, not engineering ones:

1. **Identity verification at sign-up** — what proves someone is who they claim to be (nursery
   admin vs. individual staff)? Email verification only, or something stronger?
2. **DBS verification method** — self-report a DBS number/status, or require document upload +
   manual review (the `documents` collection is designed for the latter, but that's a guess)?
   This also determines what `acceptShift`'s DBS gate in §4 actually checks.
3. **Employer-of-record question** — does Bridge Flex pay staff and invoice/charge nurseries
   (merchant of record), or does the nursery pay staff directly with Bridge Flex only
   facilitating? Determines Stripe Connect topology when payments is eventually built.
4. **Geographic matching radius logic** — fixed radius, staff-configurable, or transit-time
   based? Affects the geohash scheme behind `profilesPublic.locationArea` and `matchNewShift`'s
   query.
5. **Minimum shift notice period** — is there a floor on how last-minute a shift can be posted,
   and is that enforced at shift-creation time?

---

## What's explicitly *not* in this document

No code, no `firebase.json`, no Rules files, no Go source — those are Phase 1, gated on approval
of this v2 design. This document is meant to be read end-to-end and either approved as-is or
corrected before anything gets built.
