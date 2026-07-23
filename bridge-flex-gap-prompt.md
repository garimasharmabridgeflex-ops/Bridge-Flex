# Claude Code Prompt — Bridge Flex, Closing the Gaps

Copy this into Claude Code in the existing project. It has the current `README.md`,
`ARCHITECTURE.md`, and the codebase already — this is a continuation, not a restart.

---

You're continuing as the senior backend/full-stack engineer on Bridge Flex. I've reviewed the
current state (per `README.md`) against the approved `ARCHITECTURE.md`. Below is what's missing
or unverified, roughly in priority order. For each item: confirm current status first (some of
this may already be partially done and just undocumented), then implement what's missing. Stop
and summarize after each lettered section rather than doing all of this in one pass.

## A. Audit the HTTP read-endpoint surface (highest priority)

The frontend's move to plain HTTP everywhere (documented in `README.md`, and a reasonable call
given the gRPC-over-constrained-network issue you found) has a consequence that needs checking:
the original architecture assumed *some* reads would go directly through the Firestore client SDK
plus Security Rules, with no backend endpoint needed. That path is now abandoned app-wide. So:

Audit every screen listed in `frontend/lib/features/` against the backend's existing endpoints
and identify any screen whose data need has no corresponding HTTP endpoint yet. At minimum, check
for and add whichever of these are missing:
- `GetOwnProfile` (private `profiles/{uid}`)
- `GetPublicProfile` (a specific `profilesPublic/{uid}` by id — for viewing someone else's profile)
- `ListNotifications` (the in-app notifications list)
- `ListMessages` (messages within one chat session, not just `ListChatSessions`)
- `GetDocumentStatus` (DBS upload status, for the documents feature screen)

Each new endpoint follows the existing pattern exactly: `RequireAuth` middleware, same JSON error
envelope, same "this is already client-legal per Security Rules, we're just proxying it over HTTP"
rationale as `ListMyShifts`/`ListChatSessions`. Report back the full list of endpoints that exist
after this audit so we have one source of truth (consider adding this list to `README.md` or
`ARCHITECTURE.md` itself, since right now the endpoint list is scattered across two documents and
a growing set of ad-hoc additions).

## B. The event-driven half of the system may not be locally testable end-to-end yet

`ARCHITECTURE.md` §7 already flagged that Eventarc-triggered functions (`syncProfilePublic`,
`recomputeRating`, `matchNewShift`, `onShiftBooked`, `onRatingReceived`) have no local dispatch
path, and the seed script works around this by writing `profiles`/`profilesPublic` directly. But
`README.md` only mentions a workaround for *one* of these (`initProfileOnSignUp`, via a client-side
Firestore write) — it's unclear whether the other four handlers exist as real Go code at all yet,
or whether they've only been unit-tested per the architecture's stated fallback plan.

First, confirm: do `syncProfilePublic`, `recomputeRating`, `matchNewShift`, `onShiftBooked`, and
`onRatingReceived` exist as implemented, unit-tested Go functions right now? If any don't, build
them per `ARCHITECTURE.md` §1a/§2/§4/§6 before continuing.

Second — and this is the substantive fix — **build a local dev-only trigger-dispatch harness so
these actually run end-to-end during local testing, not just in isolated unit tests**. This is
possible without Eventarc: the Firestore Go client's realtime snapshot listeners (`Snapshots()` /
`Watch`) work against the Firestore *emulator* even though Eventarc itself doesn't run locally.
Build a small `backend/devharness` process that:
- Opens snapshot listeners against `profiles` (all docs), `ratings` (new docs), `shifts` (new and
  updated docs) on the Firestore emulator.
- On each relevant change, calls the *same handler function* the real Eventarc deployment would
  call (import and invoke the actual `syncProfilePublic`/`recomputeRating`/`matchNewShift` Go
  functions directly — don't duplicate their logic in the harness).
- For `onShiftBooked`/`onRatingReceived` (Pub/Sub-triggered in the real deployment), either also
  listen for the relevant Firestore transition directly (since Pub/Sub itself isn't the point —
  the handler logic is), or use the Pub/Sub emulator's subscription API to actually consume the
  message that `acceptShift`/`recomputeRating` already publish, and invoke the real handler.

Wire this into `make dev` (or a new `make dev-with-triggers` target if you'd rather keep it
optional) so profile edits, new ratings, and shift bookings actually cascade correctly during
local testing — right now, per the current implementation, editing a profile after sign-up likely
leaves `profilesPublic` stale, submitting a rating likely doesn't update anyone's aggregate, and
booking a shift likely never creates a chat session or notification locally. Confirm which of
these are actually broken right now before building the harness, so we know the true scope.

## C. FCM isn't wired on the client at all yet

`README.md`'s frontend stack table doesn't list `firebase_messaging` — so even once the backend
notification pipeline works (per B above), there's no client-side code to receive a push. Add:
- `firebase_messaging` dependency.
- Notification permission request (iOS requires an explicit prompt; Android 13+ does too).
- On successful permission + sign-in: get the device token, call the existing
  `RegisterFcmToken` endpoint.
- On sign-out: call `UnregisterFcmToken`.
- Foreground message handling (show an in-app banner or just rely on the existing in-app
  notifications list refreshing) and background/terminated tap handling (deep-link into the
  relevant shift/chat, using `go_router`).
- Confirm the existing in-app notifications feature (already built per `README.md`) refreshes
  when a new `notifications` doc is expected to have arrived, rather than only on manual
  pull-to-refresh.

## D. No path exists to ever mark a DBS document as verified

`documents/{docId}.status` is Admin-SDK-only per `ARCHITECTURE.md` §2/§3, by design — but nothing
in the current implementation (frontend or backend) can ever transition a document from
`pending_review` to `verified`/`rejected`. Given `acceptShift`'s DBS gate references
`dbsStatus == 'verified'` as a condition, this could block real testing of the accept-shift flow
beyond the two seeded accounts. This doesn't need a full admin UI — build a minimal internal
review endpoint (`POST /reviewDocument`, gated by a hardcoded allowlist of reviewer UIDs or a
custom Auth claim, not exposed in the Flutter app) so the review step can be exercised via Bruno
during development. Note in `README.md` that this is a placeholder, not the real moderation
tooling product gap #9 eventually needs.

## E. Security Rules don't appear to have automated tests yet

`ARCHITECTURE.md` §7 calls for rules-unit-tests run against the emulator. Note that the standard
tool for this (`@firebase/rules-unit-testing`) is a Node package that talks to the Firestore
emulator's REST API directly — it doesn't care that the rest of the backend is Go, so it's fine to
add a small Node-only test harness purely for rules testing (e.g. `backend/rules-tests/`), separate
from the Go codebases. At minimum, cover: a staff user cannot write another user's `dbsStatus`; no
client write to `profilesPublic` succeeds under any circumstances; an unbooked shift is readable by
any authenticated staff; a booked shift is only fully readable by its nursery and booked staff; a
rating can only be created by the actual `raterId` for a shift they're actually party to.

## F. Composite indexes — confirm `firestore.indexes.json` exists and is correct

Confirm this file exists and actually covers: the open-shifts list query (`status == 'open'`,
ordered by `startTime`), and whatever query backs `ListMyShifts` (`status`, `bookedStaffId` or
`nurseryId`). If it doesn't exist yet, add it and confirm `firebase deploy --only firestore:indexes`
would succeed (can't fully verify without Blaze, but at minimum validate the JSON structure and
field coverage against the actual queries in code).

## G. Sync the Bruno collection

Confirm `ListMyShifts`, `ListChatSessions`, and anything added in section A/D above have
corresponding `.bru` requests in the existing Bruno collection (per `ARCHITECTURE.md` §7's folder
structure) — it's easy for this to silently drift as endpoints get added ad hoc, and the whole
point of the collection is that it stays a complete, current reference for manually exercising the
API.

## H. Confirm cancellation actually notifies the other party

`ARCHITECTURE.md` §2 specifies `cancelShift` should trigger a communication-service notification
(not just flip `status`), since a cancellation affects a real person who was expecting to work or
have their shift covered. Confirm this is wired — if `cancelShift` currently just updates the
Firestore doc with no downstream notification, add the Pub/Sub publish + communication-side
handler, following the same pattern as `shift-booked`.

## Leave alone for now (explicitly out of scope for this pass)

- Payments (`functions-payments` stays a stub — don't start real Stripe work).
- Search/filtering by location radius or pay range (blocked on the open product decision in
  `ARCHITECTURE.md` §8, item 4).
- Admin/moderation tooling beyond the minimal document-review endpoint in section D.
- Any production/release hardening (cleartext traffic, `firebase_options.dart` for a real
  project) — already correctly flagged in `README.md` as a "before release" item, no action needed
  now.

Work through A → H in order, confirming current status before building anything, and stop after
each section for a quick check-in rather than doing all of this in one uninterrupted pass.
