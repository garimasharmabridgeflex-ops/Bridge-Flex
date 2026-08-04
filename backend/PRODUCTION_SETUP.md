# Production infrastructure runbook

`README.md`'s "Going live" section covers running `deploy.sh` against an already-provisioned
Firebase/GCP project. This document covers the **one-time project provisioning** that has to
happen once, before `deploy.sh` will actually work end to end — none of which is scripted or
tracked in this repo, and skipping any of it reproduces the exact silent-failure chain this
project hit in production (functions show `ACTIVE` in the console while every real request fails).

Current production project: `kvision-503115` (region `europe-west2`). Everything below has
already been done for that project. Follow it again in full if this ever gets rebuilt on a new
GCP/Firebase project (e.g. after an ownership transfer that includes creating a fresh project
instead of reusing this one).

## 1. Create and upgrade the project

```bash
gcloud projects create YOUR_PROJECT_ID
firebase projects:addfirebase YOUR_PROJECT_ID
```

Upgrade to the **Blaze** (pay-as-you-go) plan in the Firebase Console — required for any real
Cloud Functions/Cloud Run deployment, not optional. Usage can stay within the free quota; the
card-linking requirement exists regardless.

## 2. Set the default GCP resource location — do this before anything else

```bash
gcloud app create --region=europe-west2 --project=YOUR_PROJECT_ID
```

This is what pins Firestore/Storage's default region. **It is permanent for the life of the
project and cannot be changed later without deleting and recreating the project.** Every other
region-sensitive resource below (Firestore database, Cloud Functions `REGION`) must match whatever
you pick here. This project uses `europe-west2` throughout — `firestore.rules`,
`services/*/deploy.sh`'s default `REGION`, and `frontend/lib/core/config/env.dart`'s `Env.region`
all assume it. If you use a different region, update all three.

## 3. Create the Firestore database in the matching region

The Firebase Console's "auto-provision" flow sometimes defaults to a US multi-region (`nam5`)
regardless of step 2 — **verify this explicitly**, it will not error at creation time, only later
when Firestore-triggered functions (`SyncProfilePublic`, `RecomputeRating`, `MatchNewShift`) fail
to deploy because Eventarc requires the trigger and the database to be in the same region.

```bash
gcloud firestore databases describe --database='(default)' --project=YOUR_PROJECT_ID
# "locationId" must read europe-west2. If it doesn't and the database is still empty:
gcloud firestore databases delete --database='(default)' --project=YOUR_PROJECT_ID
gcloud firestore databases create --location=europe-west2 --project=YOUR_PROJECT_ID
```

## 4. Register the client apps

```bash
firebase apps:create android com.bridgeflex.bridgeflex_app --project=YOUR_PROJECT_ID
firebase apps:create ios com.bridgeflex.bridgeflexApp --project=YOUR_PROJECT_ID
firebase apps:create web "Bridge Flex Web" --project=YOUR_PROJECT_ID

firebase apps:sdkconfig android --project=YOUR_PROJECT_ID  > frontend/android/app/google-services.json
firebase apps:sdkconfig ios --project=YOUR_PROJECT_ID      > frontend/ios/Runner/GoogleService-Info.plist
firebase apps:sdkconfig web --project=YOUR_PROJECT_ID
```

Also register the release-signing keystore's SHA-1 (required for Google Sign-In and some other
Android APIs to work against the *real* certificate the released APK is signed with, not just the
debug one):

```bash
firebase apps:android:sha:create --app <android-app-id> <SHA1_HASH>
```

Then update `frontend/lib/core/firebase/firebase_options.dart`'s `_prod{Web,Android,Ios}` configs
and `frontend/lib/core/config/env.dart`'s `firebaseProjectId` default to match the new project.

## 5. Initialize Firebase Auth

Auth is not active on a fresh project until explicitly initialized — the Firebase Console's Auth
tab will otherwise hang on "getting started". If doing this outside the Console:

```bash
curl -X POST \
  "https://identitytoolkit.googleapis.com/v2/projects/YOUR_PROJECT_ID/identityPlatform:initializeAuth" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" -H "Content-Type: application/json"

curl -X PATCH \
  "https://identitytoolkit.googleapis.com/v2/projects/YOUR_PROJECT_ID/config?updateMask=signIn.email" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" -H "Content-Type: application/json" \
  -d '{"signIn":{"email":{"enabled":true,"passwordRequired":true}}}'
```

**Google Sign-In must be enabled through the Firebase Console** (Authentication → Sign-in method →
Google → Enable) — the API that enables it requires an OAuth client **secret**, which Google does
not expose through any API by design. There is no way to script this step.

## 6. Initialize Firebase Storage

```bash
curl -X POST \
  "https://firebasestorage.googleapis.com/v1beta/projects/YOUR_PROJECT_ID/defaultBucket" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" -H "Content-Type: application/json" \
  -d '{"location":"europe-west2"}'
```

## 7. Grant IAM roles to the compute service account

This project has automatic Editor-role grants for default service accounts **disabled**, so the
Cloud Functions runtime service account starts with almost no permissions and every capability
below has to be granted explicitly. Skipping any of these reproduces a real bug hit in this
project: functions deploy and show `ACTIVE`, but fail at runtime with permission-denied errors
that never show up in a deploy log.

```bash
SA="$(gcloud projects describe YOUR_PROJECT_ID --format='value(projectNumber)')-compute@developer.gserviceaccount.com"

for ROLE in \
  roles/datastore.user \
  roles/firebaseauth.admin \
  roles/firebasecloudmessaging.admin \
  roles/pubsub.editor \
  roles/eventarc.eventReceiver \
  roles/run.invoker \
  roles/artifactregistry.writer \
  roles/storage.objectAdmin
do
  gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
    --member="serviceAccount:$SA" --role="$ROLE" --quiet
done
```

Notes on two easy-to-miss ones:
- `roles/pubsub.editor`, not just `pubsub.publisher` — `publisher` alone lacks
  `pubsub.topics.create`, which the backend's idempotent `ensureTopic()` call needs even when the
  topic already exists.
- `roles/run.invoker` is what lets an Eventarc trigger actually invoke its target function —
  without it, every trigger function (`SyncProfilePublic`, `RecomputeRating`, `MatchNewShift`,
  `OnShiftBooked`, `OnRatingReceived`, `OnShiftMatched`) deploys fine and then silently never
  fires.

## 8. Deploy

Now (and only now) `./deploy.sh` (see `README.md` "Going live") will actually work end to end:

```bash
gcloud auth login
PROJECT_ID=YOUR_PROJECT_ID ./deploy.sh
```

## 9. Create an admin account

There is no self-service admin role — it's a Firebase Auth **custom claim**, set out of band:

```bash
# Sign the account up normally through the app first, then:
gcloud auth application-default login  # or use a service account with firebaseauth.admin
# then, in a Go/Node/Python script or via the Admin SDK:
#   authClient.SetCustomUserClaims(ctx, uid, map[string]interface{}{"admin": true})
```

The Identity Toolkit REST equivalent (`accounts:update` with `customAttributes`) also works if you
don't want to write a script — see `backend/seed/main.go`'s `seedUser` for the exact claim shape.

**Do not commit admin credentials to the repo or any doc.** The current production admin account
existed only for this session's live testing — rotate its password or delete it once a real
handover admin account is created.

## 10. Verify, don't trust "ACTIVE"

Every bug in this list (steps 3, 5, 7) produced functions that deployed successfully and showed
`ACTIVE` in the GCP Console while being completely non-functional for real users. The only
reliable verification is a live end-to-end test against the deployed URLs: sign up a real account,
call `UpdateProfile`/`GetProfile`, post and accept a shift, confirm a chat session and notification
get created. Deploy success alone proves nothing about whether IAM/region/project-ID wiring is
correct.

## What's still outside this runbook

- **Custom domain** — the app currently serves from the default
  `kvision-503115.web.app`/`.firebaseapp.com` (permanently tied to the project ID, cannot be
  renamed). A branded domain requires buying one and adding it via Firebase Hosting's custom-domain
  feature — not done yet.
- **iOS distribution** — an Apple Developer Program account now exists, and `.github/workflows/build_ios.yml`
  has a real signed-archive + TestFlight/App Store Connect upload step, but it's gated on four
  GitHub Actions repository secrets that haven't been added yet (`APPSTORE_API_KEY_ID`,
  `APPSTORE_API_ISSUER_ID`, `APPSTORE_API_KEY_P8`, `APPLE_TEAM_ID` — see `CONFIG_AND_KEYS.md`), so
  it currently still skips signing. Also still needed: uploading the APNs push key (a separate
  `.p8`, generated in the Apple dashboard under Keys) to Firebase Console's Cloud Messaging settings
  — without it, push notifications silently never arrive on iOS even though the app-side FCM code
  is already in place. Once both are done: Internal TestFlight testing works immediately; External
  TestFlight needs Apple's Beta App Review (~24-48h); a full public App Store listing needs Apple's
  full App Review plus store metadata (screenshots, privacy policy URL, App Privacy questionnaire).
- **Android Play Store listing** — the app is currently distributed as a direct APK download from
  the website, not through Google Play. No Play Console account/listing exists.
