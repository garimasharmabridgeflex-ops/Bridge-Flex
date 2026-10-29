# Known issues and limitations

Current state as of this handover. Production runs on Firebase project `kvision-503115` (`europe-west2`) and has been live-tested end to end (sign-up, profile, shift posting/accepting, chat, notifications all confirmed working against real accounts). This list is what's still missing, stubbed, or worth knowing about — not a list of "the app is broken."

## Distribution

- **iOS distribution is in progress, not live yet.** An Apple Developer Program account now exists. `.github/workflows/build_ios.yml` does a real signed archive + TestFlight/App Store Connect upload, gated on four repository secrets (`APPSTORE_API_KEY_ID`, `APPSTORE_API_ISSUER_ID`, `APPSTORE_API_KEY_P8`, `APPLE_TEAM_ID` — see `CONFIG_AND_KEYS.md`) that haven't been added yet, so it currently still skips signing and logs a warning. Also outstanding: uploading the APNs push key to Firebase Console (Cloud Messaging > Apple app configuration) — without it, FCM tokens register fine on iOS but no notification is ever actually delivered. Once both are done, the plan is Internal TestFlight first to validate the pipeline, then External TestFlight (needs Apple's Beta App Review, ~24-48h), then full App Store submission (needs store listing metadata + Apple's full App Review) to replace the TestFlight link with a normal App Store download button on the site, matching Android's.

- **Android is not on the Play Store.** It's distributed as a direct APK download from the Firebase-hosted website. No Google Play Console account/listing exists.

- **No custom/branded domain.** The download site and API both run on Firebase's default domain (`kvision-503115.web.app` / `.firebaseapp.com`), which is permanently tied to the project ID. A branded domain requires purchasing one and adding it via Firebase Hosting's custom-domain feature.## Payments

- **No payment provider is integrated yet.** This is deliberate for the current release: nurseries request a plan, an administrator assigns it in the operations console, weekly invoices are generated from approved timesheets and settled by bank transfer. No card details are collected anywhere. `CreatePayout` remains a stub that returns HTTP 501, and `backend/services/payments/TODO.md` is the place to start when Stripe (or another provider) is added.

## Product gaps

- **DBS verification is manual.** A practitioner uploads their certificate; an administrator records the eight required vetting checks (identity, original certificate, suitability, workforce, barred list, Update Service, right to work, qualification) before approval. There is no integration with a real DBS-checking service, so the certificate is checked by eye against the Update Service.

- **Onboarding collects the profile, but optional depth is still thin.** Staff experience/qualifications/bio and nursery description/photos/opening hours are editable and shown on public profiles; richer media and a guided completion score are still to come.

- **Shift matching is a placeholder.** `matchNewShift`'s geo-matching radius and minimum shift-notice logic are both simplified placeholders pending real product decisions (see `ARCHITECTURE.md` v2 §8) — not a bug, but not the final intended behavior either.

- **Chat and shift-detail screens poll rather than push-update live** (chat polls every 4s while a thread is open). This was a deliberate choice after `cloud\_firestore`'s gRPC/HTTP2 streaming connection proved unreliable over NAT'd/tunnelled dev networks — see `README.md`'s "How screens read data" section. Push notifications (FCM) do work for the events that trigger them; this is specifically about screens auto-refreshing their content while open. Everything else the app reads over the function API now rides one app-wide heartbeat (`frontend/lib/core/live/live_refresh.dart`, 15s, paused while the app is backgrounded), so a server-side change — a DBS check verified, a plan assigned, an invoice generated — appears on its own rather than needing a pull-to-refresh or a sign-out/sign-in.

## Backend gaps

- **Nothing drains the transactional `outbox` collection.** Events written through `shared/outbox.WriteTx` (timesheet lifecycle, nursery decisions, invoices, subscriptions, payslips, published policies) are recorded as `pending` and never published, because no scheduled job or function reads that collection. The events that do reach Pub/Sub are the ones core also calls `publish()` on directly (shift booked/applied/decided/cancelled/matched, ratings, `send-email`, and `timesheet-submitted` as of this release). A dispatcher would need care: several of these events already write their in-app notification directly in core, so wiring them into communication's `notifyUser` unchanged would deliver each notification twice.

## Operational

- **Scheduled jobs need to be created once per project.** `SchedulerTrialReminders` and `SchedulerRecheckReminders` are deployed HTTP functions; Cloud Scheduler must be pointed at them with OIDC (see `backend/PRODUCTION_SETUP.md` §8a). Until that is done, trial-ending and DBS-recheck notifications only run when an admin presses the corresponding button in the console.

- **Email needs SMTP credentials before it sends anything.** The producer now exists: approvals, vetting decisions, plan changes, invoice generation and trial reminders all publish to the `send-email` topic, and `OnSendEmail` renders and sends them over SMTP (`services/communication/smtp.go`). Without `SMTP_HOST` set on that function the send is skipped and recorded as `skipped_no_transport` in `sentEmails`, so in-app notifications remain the only channel until credentials are added — see `backend/PRODUCTION_SETUP.md` §8b. Until then, approvals, vetting decisions, plan changes, invoices and reminders all write in-app notifications (and push, where a token is registered).

- **Feature gates start at launch defaults**: nursery approval and trial expiry are `enforce`; practitioner vetting and terms acceptance are `warn` (so legacy practitioners and unpublished policies do not lock accounts out). Change them in the console under Settings → Feature gates. The settings live in `platformConfig/featureFlags` and are cached server-side for 60 seconds.

- **No monitoring/alerting is set up** beyond default GCP Cloud Functions logs (`gcloud logging read` / GCP Console → Cloud Functions → Logs). No error-tracking service (e.g. Sentry), no uptime checks, no alert policies.

- **No automated backups configured** beyond Firestore's own point-in-time recovery defaults (if enabled — verify in the GCP Console under Firestore → Backups).

- **No staging environment.** There is only the local Firebase Emulator Suite (fully offline, see `backend/README.md`) and the single production project. Any change tested against "real" infrastructure is tested directly against production.

- A test admin account was created during production verification and used for live testing. **Rotate its password or delete it** as part of any ownership handover — see `backend/PRODUCTION\_SETUP.md` §9. Credentials are intentionally not written down in this repo; see `CONFIG\_AND\_KEYS.md`.

## Testing

- Backend: unit tests (`go test ./...` per service) cover the Firestore/Auth/Pub-Sub trigger handlers that have no local dispatch path, plus a Security Rules suite (`npm run rules:test`, 22 tests). No integration test suite runs against the real production project (deliberately — see "no staging environment" above).

- Frontend: no automated widget/integration test suite currently exists.

