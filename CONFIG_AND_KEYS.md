# Config and keys inventory

What configuration/credentials exist, where they live, and what is and isn't safe to have
committed to this repo. Written for a handover — read this before assuming anything here is
either secret or safe.

## What's already in the repo (and why that's fine)

- `frontend/android/app/google-services.json`, `frontend/ios/Runner/GoogleService-Info.plist`,
  `frontend/lib/core/firebase/firebase_options.dart` — Firebase **client** configuration
  (project ID, app IDs, and API keys scoped to client SDK use). These are not secrets in the
  traditional sense: they identify the project to Firebase's client SDKs, and access control is
  enforced server-side by Firestore/Storage **Security Rules**
  (`backend/firestore.rules`, `backend/storage.rules`) and by each Cloud Function's own auth
  middleware — not by keeping these values hidden. This is standard practice for Firebase apps
  and matches Google's own guidance. There is currently no App Check configured, which would be a
  reasonable hardening step post-handover (restricts API key use to genuine app builds) but is not
  in place today.
- Two Google OAuth client IDs (from `google-services.json`): an Android client (type 1, bound to
  the release/debug signing certificate's SHA-1) and a Web client (type 3, used for the
  server-side/cross-platform flow). OAuth client **IDs** are not secret; the corresponding client
  **secret** for the Web client is not in this repo and was never obtained via any API (Google
  does not expose it programmatically) — Google Sign-In enablement was done manually in the
  Firebase Console.
- `frontend/lib/core/config/env.dart` — no secrets, just the production project ID
  (`kvision-503115`), region (`europe-west2`), and the local-dev port map.

## What is NOT in the repo

- No `.env` files are tracked (verified — `git ls-files | grep -i '\.env'` returns nothing).
- No Stripe keys or any other third-party service credentials — payments is a stub
  (`backend/services/payments/TODO.md`), so none exist yet.
- No GitHub Actions secrets are currently configured (`.github/workflows/build_ios.yml` doesn't
  reference any `secrets.*` — it only produces an unsigned build). Once iOS signing is set up,
  this will need: an App Store Connect API key (Key ID, Issuer ID, `.p8` file contents) stored as
  GitHub Actions repository secrets — see `backend/PRODUCTION_SETUP.md`.
- **No admin account password is written down anywhere in this repo**, deliberately. A test admin
  account was created during production verification for live testing this session — its
  credentials were shared with the requesting user out-of-band (chat), not committed. Rotate or
  delete that account and create a fresh one for the new owning team — see
  `backend/PRODUCTION_SETUP.md` §9 for how ("admin" is a Firebase Auth custom claim, not a
  database record, so there's no row to migrate).

## Access that needs transferring (not a repo concern — GCP/Firebase Console)

- **Firebase/GCP project `kvision-503115`** — add the new owner as **Owner** in both the
  [Firebase Console](https://console.firebase.google.com/project/kvision-503115) (Project
  Settings → Users and permissions) and [GCP IAM](https://console.cloud.google.com/iam-admin/iam?project=kvision-503115).
  This is the actual "keys to the kingdom" transfer — everything else in this doc is downstream of
  having Owner access here.
- **GitHub repo** (`Afrilex-Kenya/KVisionApp`) — transfer ownership or add the new org/account as
  admin.
- **Domain registrar / DNS** — not applicable yet; no custom domain has been purchased.
- **Apple Developer / Google Play accounts** — don't exist yet; nothing to transfer. Whoever takes
  over iOS/Android store distribution will be creating these fresh under the new owner's identity
  (Apple in particular ties the account to a specific legal entity/individual, so this generally
  can't be "transferred" after the fact the way a GitHub repo can — plan to create it directly
  under Bridge Vision Education Ltd rather than transferring later).

## Recommended before/at handover

1. Rotate or delete the test admin account (`backend/PRODUCTION_SETUP.md` §9).
2. Add the new owner as Owner on the Firebase/GCP project and the GitHub repo.
3. Consider enabling Firebase App Check once the new team owns the project, to lock the existing
   (non-secret but still identifying) client API keys to genuine app builds only.
4. Review `KNOWN_ISSUES.md` for what's stubbed or missing before treating this as feature-complete.
