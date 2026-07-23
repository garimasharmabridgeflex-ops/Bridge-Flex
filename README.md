# KVisionApp — Bridge Flex

A two-sided marketplace for last-minute nursery shifts: nurseries post shifts, staff accept them
(first-accept-wins, no double-booking), with a trust layer (DBS status, ratings) and in-app chat.

- Backend: Firebase (Auth, Firestore, Storage, Pub/Sub) + Go Cloud Functions — see
  [`backend/README.md`](backend/README.md) and [`ARCHITECTURE.md`](ARCHITECTURE.md) for the full
  system design.
- Frontend: Flutter (iOS/Android/Web) — see [`frontend/`](frontend/), documented below.

---

## Frontend (`frontend/`)

A Flutter app with a custom design system (Material 3, animated transitions via `flutter_animate`,
a shared indigo/coral color scheme), Riverpod for state, and `go_router` for navigation.

### Stack

| Concern | Package |
|---|---|
| State management | `flutter_riverpod` |
| Routing | `go_router`, with a role-aware auth gate (see below) |
| Firebase | `firebase_core`, `firebase_auth`, `cloud_firestore` (auth-doc bootstrap only), `firebase_storage` |
| Networking | `http`, hitting the backend's plain-HTTP Cloud Function endpoints |
| UI polish | `google_fonts` (Plus Jakarta Sans), `flutter_animate`, `animations`, `shimmer` |
| Media | `image_picker` (DBS certificate photo upload) |

### Folder layout

```
frontend/lib/
  app/                    theme.dart, router.dart, app.dart, providers.dart (DI wiring)
  core/
    api/                  ApiClient (Bearer-token HTTP client) + ApiException
    config/                env.dart — per-function local port map, DEV_HOST resolution
    firebase/              hand-written firebase_options.dart (demo-bridgeflex project)
  features/
    auth/                 sign in, sign up, role selection (nursery|staff)
    shifts/                browse open shifts, post/edit, my shifts, shift detail, accept/cancel
    profile/                own profile, edit profile, public profile view, DBS badge
    notifications/          in-app notification list
    ratings/                post-shift star rating bottom sheet
    documents/              DBS certificate photo upload
    chat/                   per-shift chat (session list + thread)
    home/                    bottom-nav shell (role-aware tabs) + splash screen
  shared/widgets/          PrimaryButton, AppTextField, status badges, empty states, skeletons
```

Each feature follows `data/` (repository talking to the backend) → `domain/` (models) →
`presentation/` (screens + Riverpod providers) → optionally `application/`.

### How screens read data: plain HTTP, not the Firestore SDK

The backend's architecture document treats direct Firestore reads (via the client SDK) and the
equivalent Cloud Function HTTP endpoint as interchangeable — both are legal per Security Rules.
This app deliberately uses **plain HTTP everywhere** (`core/api/api_client.dart` → the Go Cloud
Function endpoints), not the native `cloud_firestore` plugin's gRPC streams, for one concrete
reason discovered while testing on a physical Android device over the dev network in this
environment: `cloud_firestore`'s gRPC/HTTP2 connection to the Firestore emulator could open a TCP
connection and complete the HTTP/2 handshake, but every RPC after that stalled and was retried
with exponential backoff, forever — while plain HTTP/1.1 calls (Firebase Auth's REST API, and this
app's own Go endpoints) worked immediately and reliably over the same network path. Rather than
depend on a transport that's fragile on constrained/NAT'd/tunnelled networks, every read in this
app goes through a normal `POST`/HTTP call, matching the transport already proven reliable for
mutations (`acceptShift`, `createShift`, etc.).

Three small backend endpoints were added specifically to make this possible, since the original
backend had no "my shifts" query, no chat-session list, and no way to check a DBS document's
review status:

- **`ListMyShifts`** (`functions-core`, port `8113` locally) — returns shifts the caller posted
  (nursery) or has booked (staff), determined server-side from the caller's own profile role.
  `backend/services/core/function/shifts.go`.
- **`ListChatSessions`** (`functions-communication`, port `8127` locally) — returns chat sessions
  the caller participates in. `backend/services/communication/function/chat.go`.
- **`GetDocumentStatus`** (`functions-core`, port `8114` locally) — the caller's own most recent
  DBS document (status, rejection note if any), or `{"status":"none"}` if they've never uploaded
  one — the DBS upload screen needs this for a status badge instead of a bare upload button.
  `backend/services/core/function/documents.go`.

All three mirror the existing `listOpenShifts` pattern exactly (same auth middleware, same JSON
error envelope, same "this query is already client-legal per Security Rules" rationale) and are
registered in `backend/services/*/run-local.sh` and `frontend/lib/core/config/env.dart`'s
`ApiFunction` port map.

**Full HTTP endpoint surface** (one source of truth — this list plus `backend/bruno/` covers
every client-callable endpoint; see `ARCHITECTURE.md` §1a for the shared JSON error envelope and
auth-middleware contract all of these share):

| Endpoint | Service | Local port |
|---|---|---|
| `UpdateProfile` | core | 8101 |
| `GetProfile` | core | 8102 |
| `GetPublicProfile` | core | 8103 |
| `CreateShift` | core | 8104 |
| `UpdateShift` | core | 8105 |
| `ListOpenShifts` | core | 8106 |
| `GetShift` | core | 8107 |
| `AcceptShift` | core | 8108 |
| `CancelShift` | core | 8109 |
| `CreateRating` | core | 8110 |
| `CreateDocument` | core | 8111 |
| `ReviewDocument` | core (admin-claim gated) | 8112 |
| `ListMyShifts` | core | 8113 |
| `GetDocumentStatus` | core | 8114 |
| `RegisterFcmToken` | communication | 8121 |
| `UnregisterFcmToken` | communication | 8122 |
| `SendChatMessage` | communication | 8123 |
| `ListChatMessages` | communication | 8124 |
| `ListNotifications` | communication | 8125 |
| `MarkNotificationRead` | communication | 8126 |
| `ListChatSessions` | communication | 8127 |
| `CreatePayout` | payments (stub, always 501) | 8093 |

The one remaining direct Firestore SDK call in the app is `AuthRepository._ensureProfileDocument`
(`frontend/lib/features/auth/data/auth_repository.dart`) — a best-effort, timeout-guarded client
write of the caller's own `profiles/{uid}` doc right after sign-up, standing in for the
`initProfileOnSignUp` Eventarc trigger that (per `ARCHITECTURE.md` §7) has no local-emulator
dispatch path. On a network where gRPC can't complete, this silently times out rather than hanging
sign-up forever, but a brand-new sign-up's profile-role step won't work until it does — **use one
of the seeded accounts below for testing**, which already have profile docs.

Because there's no live push channel anymore, screens either poll (chat, every 4s while a thread
is open), refetch on pull-to-refresh, or explicitly `ref.invalidate(...)` the relevant provider
right after a mutation (accepting a shift, changing role, editing a profile, uploading a
document) — see the repository/provider files for exactly where.

### Local dev topology

Every backend HTTP-triggered Cloud Function runs as its own local process on a fixed port (see
`backend/services/*/run-local.sh` — Go's `functions-framework` serves one `FUNCTION_TARGET` per
process; there's no single unified local Functions emulator the way Node has). The Flutter app's
`Env` class (`frontend/lib/core/config/env.dart`) is the single source of truth mapping each
`ApiFunction` to its local port, plus the emulator ports for Auth/Firestore/Storage.

**Reaching the backend from a real device** (not the Android emulator): the app defaults to
`10.0.2.2` (the Android-emulator loopback alias), which doesn't work from a physical phone or from
web. Override with `--dart-define=DEV_HOST=<dev-machine-lan-ip>` when running/building. The
Android manifest also sets `usesCleartextTraffic="true"` (the backend is plain `http://`, and
Android blocks that by default) — fine for local dev, revisit before any real release build.
`backend/firebase.json`'s emulators are configured with `"host": "0.0.0.0"` so they're reachable
from other devices on the network, not just `localhost`.

### Running it

```bash
# 1. Backend — from backend/, per backend/README.md:
make dev              # emulators + all Go HTTP function processes
make seed             # (in another terminal) seed sample nursery/staff/shift data

# Optional — see "Local trigger dispatch" below:
make dev-with-triggers  # same as `make dev`, plus devharness so profile syncs / rating
                         # aggregates / shift matching / chat+notification creation actually
                         # cascade locally instead of only being covered by unit tests

# 2. Frontend — from frontend/:
flutter pub get
flutter run -d <device> --dart-define=DEV_HOST=<this-machine's-LAN-IP>
```

Seeded accounts (password `password123` for all): `acorn@example.com` / `willow@example.com`
(nurseries), `jane@example.com` (staff, DBS verified) / `sam@example.com` (staff, DBS pending) —
see `backend/seed/main.go`.

### Local trigger dispatch (`backend/services/*/devharness`)

`ARCHITECTURE.md` §7 already flags that Eventarc-triggered functions (`syncProfilePublic`,
`recomputeRating`, `matchNewShift`, `onShiftBooked`, `onRatingReceived`, `onShiftMatched`,
`onShiftCancelled`) have no local dispatch path — Eventarc itself doesn't run against the
emulators, so without something filling that gap, editing a profile locally never updates
`profilesPublic`, submitting a rating never updates anyone's aggregate, and booking/cancelling a
shift never creates a chat session or notification. Each handler is real, implemented Go code with
its own unit tests (`backend/services/*/function/triggers_test.go`) — the gap is purely "does it
run automatically while you're clicking around the app locally," not "does it exist."

`backend/services/core/devharness` and `backend/services/communication/devharness` close that gap
without reimplementing any handler logic: the core one opens Firestore emulator snapshot listeners
on `profiles`/`ratings`/`shifts` and constructs the same `DocumentEventData` payload a real
Eventarc delivery would carry; the communication one subscribes directly to the Pub/Sub emulator's
`shift-booked`/`rating-received`/`shift-matched`/`shift-cancelled` topics. Both then call the
*actual* exported handler function (e.g. `corefunc.SyncProfilePublic`, `commfunc.OnShiftBooked` —
see `devharness_exports.go` in each function package) directly, in-process. Optional — run with
`make dev-with-triggers` (or `WITH_TRIGGERS=1 ./scripts/dev.sh`) instead of plain `make dev`.

### Known gaps / next steps

- Fresh sign-up's profile-creation step depends on a Firestore SDK write that may not complete on
  gRPC-hostile networks (see above) — works fine in a normal dev/production network, or once a
  real `initProfileOnSignUp` deployment exists.
- Push notifications (FCM) aren't wired up on the client — `RegisterFcmToken`/`UnregisterFcmToken`
  endpoints exist on the backend but nothing calls them yet from the app (no `firebase_messaging`
  dependency, no permission prompt, no foreground/background message handling).
- Payments (`functions-payments`) is a backend stub only (see `backend/services/payments/TODO.md`)
  — nothing in the frontend references it.
- Chat and shift-detail screens poll/refetch rather than update live; revisit if/when a more
  robust realtime channel (e.g. the Firestore Web SDK's long-polling fallback, or a
  WebSocket-based notification channel) is worth adding.
- The onboarding flow is sign-up → role select → straight into the app — there's no profile setup
  wizard (staff experience/qualifications/bio, nursery description/photos/opening hours/Ofsted
  rating) yet. Nursery and staff public profile screens are correspondingly minimal (name, role,
  DBS badge, rating) since that richer data doesn't exist to show. This is the largest remaining
  gap against the full app spec and deserves its own pass.
