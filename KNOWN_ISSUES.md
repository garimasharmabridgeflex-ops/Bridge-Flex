# Known issues and limitations

Current state as of this handover. Production runs on Firebase project `kvision-503115` (`europe-west2`) and has been live-tested end to end (sign-up, profile, shift posting/accepting, chat, notifications all confirmed working against real accounts). This list is what's still missing, stubbed, or worth knowing about — not a list of "the app is broken."

## Distribution

- **iOS has no real distribution path yet.** There is no Apple Developer Program account. The CI workflow (`.github/workflows/build\_ios.yml`) only produces an **unsigned** build (`--no-codesign`), which cannot be installed on a physical device — this is an Apple platform requirement, not something workable around. Getting to a TestFlight link requires enrolling in the paid Apple Developer Program and generating an App Store Connect API key. See `backend/PRODUCTION\_SETUP.md`'s "What's still outside this runbook" section.

- **Android is not on the Play Store.** It's distributed as a direct APK download from the Firebase-hosted website. No Google Play Console account/listing exists.

- **No custom/branded domain.** The download site and API both run on Firebase's default domain (`kvision-503115.web.app` / `.firebaseapp.com`), which is permanently tied to the project ID. A branded domain requires purchasing one and adding it via Firebase Hosting's custom-domain feature.


## Payments

- **`CreatePayout` is a stub that always returns HTTP 501.** No Stripe integration, no real charge/payout logic exists. See `backend/services/payments/TODO.md`. Nothing in the Flutter app calls this endpoint yet.

## Product gaps

- **No profile-setup wizard.** Sign-up goes straight from role selection into the app — there's no staff experience/qualifications/bio step, no nursery description/photos/opening-hours/Ofsted step. Public profile screens are correspondingly minimal (name, role, DBS badge, rating) because the richer data doesn't exist yet to show. This is the largest remaining product gap.

- **DBS verification is manual/self-reported.** A staff member uploads a photo of their DBS certificate; an admin approves/rejects it by eye (`ReviewDocument`). There's no integration with a real DBS-checking service.

- **Shift matching is a placeholder.** `matchNewShift`'s geo-matching radius and minimum shift-notice logic are both simplified placeholders pending real product decisions (see `ARCHITECTURE.md` v2 §8) — not a bug, but not the final intended behavior either.

- **Chat and shift-detail screens poll rather than push-update live** (chat polls every 4s while a thread is open; other screens refetch on pull-to-refresh or after a mutation). This was a deliberate choice after `cloud\_firestore`'s gRPC/HTTP2 streaming connection proved unreliable over NAT'd/tunnelled dev networks — see `README.md`'s "How screens read data" section. Push notifications (FCM) do work for the events that trigger them; this is specifically about screens auto-refreshing their content while open.

## Operational

- **No monitoring/alerting is set up** beyond default GCP Cloud Functions logs (`gcloud logging read` / GCP Console → Cloud Functions → Logs). No error-tracking service (e.g. Sentry), no uptime checks, no alert policies.

- **No automated backups configured** beyond Firestore's own point-in-time recovery defaults (if enabled — verify in the GCP Console under Firestore → Backups).

- **No staging environment.** There is only the local Firebase Emulator Suite (fully offline, see `backend/README.md`) and the single production project. Any change tested against "real" infrastructure is tested directly against production.

- A test admin account was created during production verification and used for live testing. **Rotate its password or delete it** as part of any ownership handover — see `backend/PRODUCTION\_SETUP.md` §9. Credentials are intentionally not written down in this repo; see `CONFIG\_AND\_KEYS.md`.

## Testing

- Backend: unit tests (`go test ./...` per service) cover the Firestore/Auth/Pub-Sub trigger handlers that have no local dispatch path, plus a Security Rules suite (`npm run rules:test`, 22 tests). No integration test suite runs against the real production project (deliberately — see "no staging environment" above).

- Frontend: no automated widget/integration test suite currently exists.

