# Bridge Flex — Full App Specification (Screens, Fields, Interactions, States)

This is the complete interaction spec the app should match. It exists because testing has
surfaced real gaps: no CV/experience capture at sign-up, nursery details not viewable from a
shift, cancellation not reverting a shift to `open`, no visible place to upload DBS documents,
and a permission error on the one upload path that does exist. Each of those is addressed
explicitly below, in context, not as a bolted-on bugfix list.

---

## 1. Onboarding

### 1.1 Sign-up
- Email + password (Firebase Auth).
- Immediately after account creation: **role selection** — Nursery or Staff. This choice is
  permanent (no role-switching later without a separate, deliberate admin action — don't build
  a "change role" screen).
- Role selection routes into a **mandatory profile setup wizard** before the person reaches the
  main app. This is the gap you hit — sign-up currently seems to end at "pick a role" with no
  further prompts. The wizard is multi-step, not one long form, and different per role.

### 1.2 Staff profile setup wizard
Screens, in order, each with a "Next" that's disabled until required fields are valid:

1. **Basics** — full name (required), phone number (required), profile photo (optional,
   `image_picker`).
2. **Experience** — this is the missing "CV" step. Two acceptable approaches, pick one (I'd
   default to the first for MVP speed, add the second later):
   - **Structured fields**: years of childcare experience (number), qualification level (e.g.
     "Level 2", "Level 3", "None yet" — a dropdown, not free text, so it's filterable/sortable
     later), a free-text "About me" bio (character-capped, ~300 chars), and a repeatable
     "Previous roles" mini-list (nursery/setting name, role title, duration — optional, can be
     skipped).
   - **CV upload**: a PDF/doc upload (same Storage pattern as DBS documents, different path —
     `cv-documents/{uid}/{filename}` — reviewed manually or just displayed on the profile as a
     downloadable file, no verification workflow needed since it's informational, not a trust
     gate).
   Either way, this step's data needs to actually reach the profile — right now nothing prompts
   for it, so nurseries have no way to judge a candidate beyond a name and a DBS badge.
3. **DBS verification** — see §5 in full below; this step *starts* the DBS flow (upload or "I'll
   do this later" skip, but gate `acceptShift` on `dbsStatus == 'verified'` as already designed,
   so skipping here just means they can browse but not accept shifts until it's done).
4. **Availability** — the existing availability toggle, plus (new) a default location/area for
   shift matching (reuses whatever geohash/location-area mechanism the backend already has for
   `profilesPublic.locationArea`).

### 1.3 Nursery profile setup wizard
1. **Basics** — nursery name (required), address (required — this is what geocodes into the
   private exact `GeoPoint` and the public coarse `locationArea`), phone number (required).
2. **About the setting** — description (free text, required — this is the "nursery details are
   too little" gap: right now there's apparently little more than a name), and optionally: opening
   hours, an Ofsted rating field (dropdown: Outstanding/Good/Requires Improvement/Inadequate/Not
   yet rated — informational, not verified by us), up to ~4 photos of the setting.
3. Nurseries don't need a DBS step (staff-only field) or an availability step.

### 1.4 Post-wizard
Both roles land on the role-appropriate home dashboard only after the wizard's required fields
are complete. A partially-complete profile (e.g. staff skipped DBS) is allowed into the app, but
with a persistent, dismissible-but-reappearing banner ("Finish your profile to start accepting
shifts") rather than being silently invisible about what's missing.

---

## 2. Shift Detail — nursery context must be a real, tappable destination

Right now (per your report) tapping into a shift's nursery info does nothing, and the nursery
info shown is minimal. Fix both:

- The nursery name/logo block on a shift detail screen is a tappable row (not just static text),
  navigating to a **Nursery Public Profile screen** showing:
  - Name, photos, description, Ofsted rating if set, opening hours if set.
  - Address as a coarse map view (approximate area, not a pin on the exact address — consistent
    with the backend's public/private location split; don't accidentally add an endpoint that
    leaks the exact `GeoPoint` to satisfy this screen).
  - Aggregate rating (stars + count), sourced from `profilesPublic.rating`.
  - A list of this nursery's other currently-open shifts (nice-to-have, not blocking).
- Similarly, once a shift is booked, the nursery's shift-detail view should let them tap through
  to the **accepted staff member's public profile** (name, bio/experience from §1.2, DBS badge,
  rating) — a nursery committing a room full of children's coverage to someone deserves to see
  more than a name.
- This requires a `GetPublicProfile(uid)` backend endpoint if one doesn't already exist (flagged
  in the earlier gap-closing prompt, section A — confirm it's been built, since this screen
  depends on it directly).

---

## 3. Shift lifecycle & cancellation — the "doesn't go back to open" bug

Define the states precisely, because "cancel" means two different things depending on who does it,
and the current bug is almost certainly this distinction not being implemented:

| Actor | Action | Shift status before | Shift status after | Notification |
|---|---|---|---|---|
| Nursery | Cancels an open shift | `open` | `cancelled` (removed from marketplace entirely) | none needed, no one had it |
| Nursery | Cancels a booked shift | `booked` | `cancelled` | booked staff member notified — their shift was pulled |
| Staff | Cancels their acceptance | `booked` | **`open`** (not `cancelled` — someone else should still be able to take it) | nursery notified — their covered shift is uncovered again, urgently |

**This is the exact bug you saw**: if staff-side cancellation is currently setting status to
`cancelled` instead of back to `open`, the shift disappears from the marketplace instead of
reappearing for someone else to grab — which defeats the entire point of the app for a
last-minute-cover use case. Fix `cancelShift` to take the actor's role into account and branch
accordingly; it is not one status transition, it's two different ones depending on who calls it.

Both cancellation paths should ask for a reason (short free-text or a quick-pick list: "sick",
"double-booked", "other") — not required for MVP correctness, but worth having since repeated
cancellations are a trust-and-reliability signal you'll want later (ties to the still-open
"ratings/reliability" product question).

---

## 4. Documents (DBS) — needs a real entry point and the permission bug needs fixing

Two separate problems reported: **no visible place to upload**, and **a permission error on the
one path that exists**. Both need fixing, not just one.

### 4.1 Entry point
The documents/DBS feature apparently exists in code (per the earlier README) but isn't reachable
from anywhere in the actual navigation. Add:
- A dedicated section in the staff Profile screen: "DBS Verification" — showing current status
  (`unverified`/`pending`/`verified`/`rejected`) as a clear badge, with an "Upload certificate" /
  "Re-upload" button.
- The onboarding wizard step (§1.2, step 3) linking to the same upload flow.
- If status is `rejected`, show why (a reviewer note field, if `reviewDocument` supports one —
  add one if not) and let them re-upload.

### 4.2 Upload flow
1. Tap "Upload certificate" → `image_picker` (camera or gallery) or a document picker for PDF.
2. Show a preview/confirmation screen before submitting (people should see what they're about to
   send).
3. On confirm: upload the file to Cloud Storage at `dbs-documents/{uid}/{filename}`, then create
   the `documents/{docId}` Firestore metadata doc pointing at that path, with `status:
   'pending_review'`.
4. Show a clear "Submitted — under review" state immediately after, not a silent success.

### 4.3 The permission error — likely causes, check these specifically
"You do not have permission to submit it" on this exact flow points to a mismatch between what
the client sends and what Security/Storage Rules expect. Check, in order:
- **Storage path mismatch**: the rule requires the path to start with `dbs-documents/{uid}/...`
  where `{uid}` is `request.auth.uid` — confirm the client is actually constructing the path with
  the signed-in user's real uid (not a placeholder, not the wrong casing, not a stale cached uid
  from before a sign-out/sign-in cycle).
- **Missing/expired auth token on the Storage request specifically**: `firebase_storage`'s upload
  call needs a valid signed-in Firebase Auth session at the moment of upload — if the app is using
  the Auth *emulator* locally but Storage rules are being evaluated against a session that didn't
  refresh correctly, this throws exactly this kind of permission error. Confirm the Storage
  emulator and Auth emulator are both running and configured to recognize each other (same
  project ID config in `firebase.json`).
- **Firestore metadata doc create rule**: separately from the Storage rule, the `documents/{docId}`
  creation rule validates `storagePath` starts with `dbs-documents/{request.auth.uid}/` (per
  `ARCHITECTURE.md` §2) — if the Storage upload succeeds but the metadata doc write is what's
  actually failing, double check this string comparison isn't off by a slash or a hardcoded
  placeholder still in the client code.
- **Rules not actually deployed to the emulator**: confirm `firebase emulators:start` is picking
  up the current `storage.rules`/`firestore.rules` files and isn't running against a stale
  cached rules version from an earlier session.

---

## 5. Full screen-by-screen reference

| Screen | Key fields/actions | Notes |
|---|---|---|
| Sign in / Sign up | email, password, role select | routes into wizard on first sign-up only |
| Staff onboarding wizard | name, phone, photo, experience/CV, DBS start, availability | §1.2 |
| Nursery onboarding wizard | name, address, phone, description, photos, hours, Ofsted | §1.3 |
| Browse open shifts (staff) | list, filter by future+open, tap → detail | availability toggle gates visibility, not eligibility |
| My shifts (staff) | tabs: upcoming (booked) / past | cancel action on upcoming |
| Post shift (nursery) | title, date, start/end, pay rate | FAB entry point |
| My shifts (nursery) | tabs: open / booked / cancelled | cancel/edit actions |
| Shift detail | full info, nursery block (tappable, §2), accept/cancel action, DBS/rating badges | |
| Nursery public profile | name, photos, description, rating, hours, Ofsted | reached from shift detail |
| Staff public profile | name, bio/experience, DBS badge, rating | reached from a booked shift's nursery view |
| Own profile (either role) | edit all wizard fields, DBS section (§4), sign out | |
| DBS upload | current status, upload/re-upload, rejection reason if any | §4 |
| Chat (per shift) | session list, thread, only exists once a shift is booked | created by `onShiftBooked` |
| Ratings | post-shift star + comment, prompted after shift end time passes | |
| Notifications | in-app list, tap → deep-link to relevant shift/chat | tied to FCM, §C of the gap-closing prompt |

---

## 6. What "done" looks like for this pass

A staff member can: sign up, complete a real profile including experience info, upload a DBS
document through a visible entry point without a permission error, browse and accept a shift,
see full nursery details by tapping through, cancel their acceptance and watch it reappear as
`open` for someone else, and get notified/chat once matched. A nursery can do the mirror image,
including seeing who accepted their shift in real detail, not just a name.
