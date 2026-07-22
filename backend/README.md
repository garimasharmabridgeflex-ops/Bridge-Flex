# Bridge Flex Backend

Firebase backend for Bridge Flex — see [`ARCHITECTURE.md`](../ARCHITECTURE.md) (v2, approved)
for the full design. This README is the practical "how do I run this" companion to that doc.

Everything below runs against the **Firebase Emulator Suite only** — no Blaze plan, no billing
account, no real Stripe keys. Going live later requires upgrading to Blaze (required for any real
Cloud Functions/Cloud Run deployment) and building real Stripe Connect integration — neither is
needed for anything in this README.

## Prerequisites

- Go 1.24+ (each service is its own Go module)
- Node.js + npm (only for the Firebase emulators and the Security Rules test suite — the backend
  itself has no Node.js runtime code)
- Java (the Firestore and Storage emulators are JVM-based; `firebase emulators:start` downloads
  the jars on first run)

## Repo layout

```
backend/
  firebase.json, .firebaserc, firestore.rules, storage.rules, firestore.indexes.json
  shared/                    Go module: auth middleware, JSON error envelope, Firebase app init
  services/
    core/                    profiles, shifts, booking, ratings, documents
    payments/                stub only — see services/payments/TODO.md
    communication/           chat, FCM tokens, notifications
  seed/                      Go seed script for emulator data
  rules-tests/               Security Rules unit tests (@firebase/rules-unit-testing)
  bruno/                     API collection for manual testing against the emulators
```

Each service under `services/` is a **separate Go module** (own `go.mod`), deployed independently
— see ARCHITECTURE.md v2 §1. `shared` is pulled in via a `replace` directive, not published.

## 1. Install dependencies

```bash
cd backend
npm install                       # firebase-tools (local, so `npm run ...` scripts work)
npm --prefix rules-tests install  # @firebase/rules-unit-testing, firebase, vitest
```

Go dependencies resolve automatically on first `go build`/`go run` in each service directory.

## 2. Start the emulators

```bash
npm run emulators:start
```

This runs Auth, Firestore, Storage, and Pub/Sub with the fixed ports from `firebase.json`:

| Emulator | Port |
|---|---|
| Auth | 9099 |
| Firestore | 8180 |
| Pub/Sub | 8085 |
| Storage | 9199 |
| Emulator UI | 4000 |

(Firestore is on 8180, not the more common 8080, purely to dodge a port collision on some
machines — there's nothing significant about the number.)

To persist data across restarts instead of starting empty every time:

```bash
npm run emulators:persist
```

## 3. Seed sample data

In another terminal, with the emulators running:

```bash
npm run seed
```

Creates 4 Auth users + Firestore profiles (2 nurseries, 2 staff), 4 shifts (`open`/`booked`/
`cancelled`), and — since the Pub/Sub triggers that would normally create them don't fire locally
(see the trigger-testing gap below) — a pre-seeded chat session and notification for the one
already-booked shift, so the communication endpoints have something real to hit immediately. Safe
to re-run; it's idempotent (skips users that already exist).

| uid | role | notes |
|---|---|---|
| `nursery-acorn` | nursery | owns `shift-open-1`, `shift-booked-1` |
| `nursery-willow` | nursery | owns `shift-open-2`, `shift-cancelled-1` |
| `staff-jane` | staff | `dbsStatus: verified`; booked on `shift-booked-1` |
| `staff-sam` | staff | `dbsStatus: pending` |

All seeded users' password is `password123`.

## 4. Run the Cloud Functions locally

**This is the one genuinely awkward part of building on Go instead of Node** (see
ARCHITECTURE.md v2 §1a/§7 for why): there is no single unified Functions emulator for Go the way
`firebase-functions` gives Node. Each HTTP-triggered function is its own local process via
`functions-framework-go`, so running "the backend" locally means running several processes, each
on a fixed port.

Export the emulator env vars once per terminal (or add them to your shell profile):

```bash
export FIRESTORE_EMULATOR_HOST=127.0.0.1:8180
export FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099
export FIREBASE_STORAGE_EMULATOR_HOST=127.0.0.1:9199
export GCLOUD_PROJECT=demo-bridgeflex
```

Then, in separate terminals:

```bash
npm run functions:core            # starts all 12 functions-core HTTP endpoints, one per port
npm run functions:payments        # the one functions-payments stub endpoint, port 8093
npm run functions:communication   # starts all 6 functions-communication HTTP endpoints
```

`services/core/run-local.sh` and `services/communication/run-local.sh` are the scripts behind the
first and third command — read them for the exact function-name → port mapping (also documented
per-request in the Bruno collection, see below). `Ctrl+C` stops all of a service's functions
together (the script traps and kills its children).

### The trigger-testing gap

Firestore/Auth/Pub-Sub-triggered functions — `InitProfileOnSignUp`, `SyncProfilePublic`,
`RecomputeRating`, `MatchNewShift` (core) and `OnShiftBooked`, `OnRatingReceived`, `OnShiftMatched`
(communication) — are **not started by the scripts above** and have no local "fires
automatically" story at all under Go (unlike Node, where the Functions emulator dispatches
Firestore/Auth events for you). This is a real gap, not a rounding error: `functions-framework-go`
has no emulator-integrated event dispatcher for Go.

For Phase 1, these are verified by **direct unit tests** against a hand-constructed event payload
(decode a `firestoredata.DocumentEventData` or `authdata.AuthEventData` proto, or a Pub/Sub
`MessagePublishedData` JSON payload, call the handler function directly, assert on the resulting
Firestore state) rather than true end-to-end local trigger dispatch — that only gets exercised
once actually deployed (which requires Blaze, a separate later decision). The seed script works
around the practical consequence of this (no `profilesPublic` sync, no chat session, no
notification firing automatically) by writing that derived state directly.

Run them with the Firestore (and, for core, Pub/Sub — `matchNewShift`/`recomputeRating` publish)
emulators up:

```bash
export FIRESTORE_EMULATOR_HOST=127.0.0.1:8180
export FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099
export PUBSUB_EMULATOR_HOST=127.0.0.1:8085
export GCLOUD_PROJECT=demo-bridgeflex

(cd services/core && go test ./...)           # services/core/function/triggers_test.go — 4 tests
(cd services/communication && go test ./...)  # services/communication/function/triggers_test.go — 3 tests
```

7 tests total: `InitProfileOnSignUp`, `SyncProfilePublic`, `RecomputeRating`, `MatchNewShift`
(core), `OnShiftBooked`, `OnRatingReceived`, `OnShiftMatched` (communication). Each one asserts on
real Firestore state written by the handler — `TestSyncProfilePublic` in particular is the
regression test for the v2 privacy fix: it feeds the handler a fake profile write containing an
exact `GeoPoint` and asserts the resulting `profilesPublic` doc has only the derived
`locationArea` geohash, never the coordinates.

## 5. Security Rules unit tests

```bash
npm run rules:test
```

Wraps the `rules-tests/` suite (vitest + `@firebase/rules-unit-testing`) in
`firebase emulators:exec --only firestore,storage`, so it spins up a clean emulator instance, runs
the tests, and tears down automatically — no manually-started emulator required for this command
specifically. 22 tests across `profiles.test.js`, `shifts.test.js`, and `misc.test.js`, covering
(at minimum, per the brief, plus the v2-specific fixes):

- a staff user cannot write another user's `dbsStatus`
- a client cannot set `shifts.bookedStaffId` directly
- an open shift is readable by any authenticated staff
- a booked shift is only fully readable by its nursery and booked staff
- **v2 fix**: no user can read another user's private `profiles/{uid}` doc at all
- **v2 fix**: no client can write `profilesPublic/{uid}` under any circumstances
- plus spot checks on ratings, chat sessions, documents, notifications, and the
  deny-everything `transactions` collection

## 6. Bruno collection

Open `bruno/` in [Bruno](https://www.usebruno.com/), select the **Emulator** environment, and:

1. Run a request from `auth/` (e.g. "Sign In - staff-jane") — its post-response script stashes
   the returned ID token into `{{idToken}}`/`{{uid}}` for every other request to reuse.
2. Make sure the relevant service's functions are running (step 4 above) — each request's `docs`
   block names the exact port it expects and which seeded user to sign in as first.
3. Run whatever request you want. `booking/Accept Shift`'s docs walk through triggering the full
   §4 error-code contract (200 → run it again for 409 `SHIFT_ALREADY_BOOKED`) against the real
   emulator, not a mock.

A **Production** environment exists with placeholder values (`REPLACE-ME.cloudfunctions.net`,
etc.) for when this eventually gets deployed — not usable yet, and not something Phase 0/1 needs
to resolve. Note the URL shape actually changes at that point: each Go Cloud Function deploys as
its own Cloud Run service with its own HTTPS URL (unlike the emulator's one-host-many-ports
scheme), so filling in Production.bru later means one URL per function, not one base URL plus a
port.

## Known gaps, stated plainly

- **No local end-to-end trigger dispatch for Go** (above) — covered by unit tests instead of live
  emulation.
- **`ReviewDocument`'s admin check has no self-service path** — deliberately: the `admin` custom
  claim must be set out of band (Emulator UI, or the Auth emulator's `Bearer owner` REST shortcut
  — see `bruno/documents/02-review-document.bru` for both, verified against a running emulator).
- **DBS verification method, identity verification, employer-of-record, geo-matching radius, and
  minimum shift notice** are still open product questions (ARCHITECTURE.md v2 §8) — nothing here
  silently decided them; `acceptShift`'s DBS gate and `matchNewShift`'s matching logic are both
  placeholders pending those answers.
- **Payments is a stub** (`services/payments/TODO.md`) — no Stripe dependency, no real charge/
  payout logic, by design (ARCHITECTURE.md v2 §5).

## Going live (not needed for Phase 0/1)

Deploying any of this to a real Firebase project requires upgrading to the Blaze (pay-as-you-go)
plan — a required step for any non-emulated Cloud Functions/Cloud Run deployment, not a policy
this project can route around. Usage can stay entirely within the free quota; the card-linking
requirement exists regardless. That's a separate, later decision — everything above is designed
to be fully developed and tested without it.

When you're ready:

1. Create a real Firebase project (not `demo-bridgeflex` — that ID only resolves against the
   emulators) and upgrade it to Blaze.
2. `gcloud auth login` and `gcloud config set project YOUR_PROJECT_ID`.
3. `PROJECT_ID=your-real-project-id ./deploy.sh` — deploys Firestore/Storage rules via the normal
   Firebase CLI, then all 26 Cloud Functions (2nd gen) via `gcloud` directly. **`firebase deploy
   --only functions` does not work here** — that path only supports Node/Python codebases; Go
   requires `gcloud functions deploy` per function, which is what `deploy.sh` (and the
   per-service `services/*/deploy.sh` it calls) automates. Read those scripts for the exact
   trigger config (event filters, Pub/Sub topics) per function.
4. Fill in `bruno/environments/Production.bru` with the deployed URLs (`gcloud functions describe
   NAME --gen2 --region=... --format='value(serviceConfig.uri)'` per function — each one gets its
   own URL, unlike the emulator's one-host-many-ports scheme).

Real Stripe Connect work (`services/payments/TODO.md`) is the other piece that still needs
building before payments does anything beyond the 501 stub — deploying it as-is just makes the
stub reachable over HTTPS, nothing more.
