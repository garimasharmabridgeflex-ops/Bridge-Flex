# Config and keys inventory

What configuration/credentials exist, where they live, and what is and isn't safe to have committed to this repo. Written for a handover — read this before assuming anything here is either secret or safe.

## What's already in the repo (and why that's fine)

- `frontend/android/app/google-services.json`, `frontend/ios/Runner/GoogleService-Info.plist`, `frontend/lib/core/firebase/firebase\_options.dart` — Firebase **client** configuration (project ID, app IDs, and API keys scoped to client SDK use). These are not secrets in the traditional sense: they identify the project to Firebase's client SDKs, and access control is enforced server-side by Firestore/Storage **Security Rules** (`backend/firestore.rules`, `backend/storage.rules`) and by each Cloud Function's own auth middleware — not by keeping these values hidden. This is standard practice for Firebase apps and matches Google's own guidance. There is currently no App Check configured, which would be a reasonable hardening step post-handover (restricts API key use to genuine app builds) but is not in place today.

- Two Google OAuth client IDs (from `google-services.json`): an Android client (type 1, bound to the release/debug signing certificate's SHA-1) and a Web client (type 3, used for the server-side/cross-platform flow). OAuth client **IDs** are not secret; the corresponding client **secret** for the Web client is not in this repo and was never obtained via any API (Google does not expose it programmatically) — Google Sign-In enablement was done manually in the Firebase Console.

- `frontend/lib/core/config/env.dart` — no secrets, just the production project ID (`kvision-503115`), region (`europe-west2`), and the local-dev port map.

## What is NOT in the repo

- No `.env` files are tracked (verified — `git ls-files | grep -i '\\.env'` returns nothing).

- No Stripe keys or any other third-party service credentials — payments is a stub (`backend/services/payments/TODO.md`), so none exist yet.

- `.github/workflows/build_ios.yml` now does a real signed archive + TestFlight/App Store Connect upload, but only once four repository secrets are added (Settings > Secrets and variables > Actions) — until then it skips the signing steps and just logs a warning, so pushes to `main` still go green. Required secrets: `APPSTORE_API_KEY_ID`, `APPSTORE_API_ISSUER_ID`, `APPSTORE_API_KEY_P8` (the App Store Connect API key's `.p8` file contents, base64-encoded), and `APPLE_TEAM_ID`. None of these are in the repo, and shouldn't be — they're bound to whoever owns the Apple Developer account. Separately, the APNs push key (also a `.p8`, generated the same way in the Apple dashboard but for Push Notifications rather than App Store Connect) isn't a CI secret at all — it gets uploaded directly to Firebase Console (Project Settings > Cloud Messaging > Apple app configuration), not stored in this repo or in GitHub Actions.

- **No admin account password is written down anywhere in this repo**, deliberately. A test admin account was created during production verification for live testing this session — its credentials were shared with the requesting user out-of-band (chat), not committed. Rotate or delete that account and create a fresh one for the new owning team — see `backend/PRODUCTION\_SETUP.md` §9 for how ("admin" is a Firebase Auth custom claim, not a database record, so there's no row to migrate).

