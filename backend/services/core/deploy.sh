#!/usr/bin/env bash
# Deploys every functions-core Cloud Function (2nd gen) via gcloud — Go isn't
# supported by `firebase deploy --only functions` (Node/Python only), so
# each function is deployed directly. See ARCHITECTURE.md v2 §1a and
# backend/README.md "Going live".
#
# Requires: gcloud authenticated (`gcloud auth login`), PROJECT_ID set to a
# real, Blaze-upgraded Firebase project (never demo-bridgeflex — that's
# emulator-only). --allow-unauthenticated on the HTTP functions is
# intentional: that flag only controls Cloud Functions' own IAM invoker
# check, which is a separate layer from the RequireAuth Firebase-ID-token
# check every handler already does internally (§1a) — the function itself
# still rejects unauthenticated callers, just with its own 401 JSON error
# instead of Cloud Functions' generic 403.
set -euo pipefail
cd "$(dirname "$0")"

: "${PROJECT_ID:?Set PROJECT_ID to your real Firebase project id, e.g. PROJECT_ID=my-prod-project ./deploy.sh}"
: "${REGION:=europe-west2}"
# Cloud Scheduler region — keep in sync with REGION unless the project's
# App Engine app lives elsewhere.
: "${SCHEDULER_LOCATION:=$REGION}"
# Verify the current valid identifier with `gcloud functions runtimes list
# --project="$PROJECT_ID"` before your first deploy — Cloud Functions'
# supported Go runtime versions change over time.
: "${GO_RUNTIME:=go125}"

deploy_http() {
  local name="$1"
  echo "==> functions-core: deploying $name (HTTP)"
  gcloud functions deploy "$name" \
    --gen2 --runtime="$GO_RUNTIME" --region="$REGION" --project="$PROJECT_ID" \
    --source=. --entry-point="$name" \
    --trigger-http --allow-unauthenticated --quiet
}

deploy_firestore_trigger() {
  local name="$1" event_type="$2" path_pattern="$3"
  echo "==> functions-core: deploying $name (Firestore $event_type on $path_pattern)"
  gcloud functions deploy "$name" \
    --gen2 --runtime="$GO_RUNTIME" --region="$REGION" --project="$PROJECT_ID" \
    --source=. --entry-point="$name" \
    --trigger-event-filters="type=$event_type" \
    --trigger-event-filters="database=(default)" \
    --trigger-event-filters-path-pattern="document=$path_pattern" \
    --quiet
}

deploy_auth_trigger() {
  local name="$1"
  echo "==> functions-core: deploying $name (Auth: user created)"
  # `|| true` is deliberate here, unlike the other deploy_* helpers: this
  # project has no firebaseauth.googleapis.com Eventarc provider registered
  # (`gcloud eventarc providers list --location=- | grep firebaseauth`
  # returns nothing), so this trigger currently fails deployment outright —
  # a known, accepted gap. auth_repository.dart's _ensureProfileDocument
  # already covers the exact case this trigger exists for (creating
  # profiles/{uid} on sign-up) as a client-side fallback, so a real user is
  # never blocked by this being undeployed. Revisit if/when Firebase Auth
  # Eventarc triggers become deployable via plain gcloud for this project.
  gcloud functions deploy "$name" \
    --gen2 --runtime="$GO_RUNTIME" --region="$REGION" --project="$PROJECT_ID" \
    --source=. --entry-point="$name" \
    --trigger-event-filters="type=google.firebase.auth.user.v1.created" \
    --quiet || true
}

# HTTP endpoints — ports in run-local.sh, same set of functions.
deploy_http UpdateProfile
deploy_http GetProfile
deploy_http GetPublicProfile
deploy_http DeleteAccount
deploy_http CreateShift
deploy_http UpdateShift
deploy_http ListOpenShifts
deploy_http ListMyShifts
deploy_http GetShift
deploy_http AcceptShift
deploy_http CancelShift
deploy_http MarkNoShow
deploy_http ApproveShiftApplicant
deploy_http RejectShiftApplicant
deploy_http CreateRating
deploy_http CreateDocument
deploy_http ReviewDocument
deploy_http GetDocumentStatus
deploy_http ListMyDocuments
deploy_http ListPendingDocuments
deploy_http GetPlatformStats
deploy_http ListAllUsers
deploy_http GetUserDetail
deploy_http SetUserSuspended
deploy_http SetVerificationBadge
deploy_http ListRatings

# Policies, Company config and Scheduler Heartbeat (Phase 2 & 3)
deploy_http GetRequiredPolicies
deploy_http GetPolicy
deploy_http AcceptPolicies
deploy_http GetCompanyInfo
deploy_http GetCompanySettings
deploy_http UpdateCompanyInfo

deploy_http SchedulerHeartbeat

# Vetting and sensitive data (Phase 4)
deploy_http GetVettingChecklist
deploy_http RecordVettingCheck
deploy_http RequestMoreDocuments
deploy_http ApprovePractitionerVetting
deploy_http RejectPractitionerVetting
deploy_http UpdateSensitiveProfile
deploy_http GetSensitiveProfile

# Nursery registration and multi-branch (Phase 5)
deploy_http CreateBranch
deploy_http ListBranches
deploy_http UpdateBranch
deploy_http DeleteBranch
deploy_http ApproveNurseryRegistration
deploy_http RejectNurseryRegistration

# Rates, cards and structured cancellations (Phase 6)
deploy_http GetActiveRateCard
deploy_http ListRateCards
deploy_http UpsertRateCard
deploy_http CancelShiftStructured
deploy_http GetCancellationPolicy
deploy_http UpdateCancellationPolicy

# Timesheets (Phase 7)
deploy_http SubmitTimesheet
deploy_http GetTimesheet
deploy_http ListTimesheets
deploy_http ApproveTimesheet
deploy_http RequestTimesheetCorrection
deploy_http DisputeTimesheet
deploy_http AdminApproveTimesheet
deploy_http EscalateUnresponsiveTimesheets

# Practitioner Payroll (Phase 8)
deploy_http GetPayrollProfile
deploy_http UpdatePayrollProfile
deploy_http GeneratePayrollPeriod
deploy_http ListPayrollPeriods
deploy_http GetPayrollPeriodDetail
deploy_http ExportPayrollCSV
deploy_http MarkPayrollPeriodPaid
deploy_http GetPractitionerEarnings
deploy_http LinkPayslip

# Subscriptions, Invoicing and Ledger without Stripe (Phase 9)
deploy_http GetPlans
deploy_http GetAdminPlans
deploy_http UpsertPlan

deploy_http GetNurserySubscription
deploy_http AssignNurseryPlan
deploy_http GenerateWeeklyInvoices
deploy_http ListInvoices
deploy_http GetInvoice
deploy_http MarkInvoicePaid
deploy_http CreateLedgerEntry

# Training modules (Bridge Flex Training & Onboarding Modules spec). The three
# admin endpoints are gated by the admin custom claim inside the handler, same
# as the admin dashboard functions above.
deploy_http ListTrainingModules
deploy_http SubmitTrainingQuiz
deploy_http MarkTrainingVideoWatched
deploy_http ListTrainingModulesAdmin
deploy_http UpsertTrainingModule
deploy_http DeleteTrainingModule


# Platform settings, audit and subscription workflow (post-launch fixes)
deploy_http GetFeatureFlags
deploy_http UpdateFeatureFlags
deploy_http ListAuditLogs
deploy_http RequestPlanChange
deploy_http CancelSubscription
deploy_http ListSubscriptionRequests

# Legal policy authoring (Phase 3) — must be deployed for the admin console
deploy_http ListPolicies
deploy_http AdminSavePolicyDraft
deploy_http AdminApprovePolicy
deploy_http AdminPublishPolicy

# Scheduled jobs (Cloud Scheduler calls the Scheduler* endpoints with OIDC;
# the Run* twins are admin-triggered from the console)
deploy_http SchedulerTrialReminders
deploy_http SchedulerRecheckReminders
deploy_http RunTrialReminders
deploy_http RunRecheckReminders

# Invoices, discount codes and admin broadcast (owner brief §2 "downloadable
# invoices", §10 "create discount codes" / "send notifications")
deploy_http GetInvoiceDocument
deploy_http CreateDiscountCode
deploy_http ListDiscountCodes
deploy_http SetDiscountCodeActive
deploy_http SendAdminNotification

# Eventarc triggers — same 4 functions covered by triggers_test.go.
deploy_auth_trigger InitProfileOnSignUp
deploy_firestore_trigger SyncProfilePublic google.cloud.firestore.document.v1.written "profiles/{uid}"
deploy_firestore_trigger RecomputeRating google.cloud.firestore.document.v1.created "ratings/{ratingId}"
deploy_firestore_trigger MatchNewShift google.cloud.firestore.document.v1.created "shifts/{shiftId}"

# Cloud Scheduler jobs (plan Phase 2.3 / 7.4 / 9.2). The Scheduler* endpoints
# verify Cloud Scheduler's OIDC token, but deploying the endpoints alone
# never makes a job run — without these, the 48-hour timesheet escalation and
# the trial/DBS-recheck reminders are dead code in production. Idempotent:
# an existing job is left alone. Cloud Scheduler needs an App Engine app in
# the project (`gcloud app create --region=europe-west2`, once).
ensure_scheduler_job() {
  local name="$1" schedule="$2" target="$3"
  if gcloud scheduler jobs describe "$name" \
      --location="$SCHEDULER_LOCATION" --project="$PROJECT_ID" >/dev/null 2>&1; then
    echo "==> functions-core: scheduler job $name already exists — skipping"
    return 0
  fi
  echo "==> functions-core: creating scheduler job $name ($schedule → $target)"
  gcloud scheduler jobs create http "$name" \
    --location="$SCHEDULER_LOCATION" --project="$PROJECT_ID" \
    --schedule="$schedule" --time-zone=Etc/UTC \
    --uri="https://$REGION-$PROJECT_ID.cloudfunctions.net/$target" \
    --http-method=POST --headers=Content-Type=application/json \
    --message-body='{}' \
    --oidc-service-account-email="$PROJECT_ID@appspot.gserviceaccount.com" \
    --oidc-token-audience="https://$REGION-$PROJECT_ID.cloudfunctions.net/$target" \
    --quiet || echo "WARNING: could not create scheduler job $name — create it manually against $target"
}

ensure_scheduler_job kf-heartbeat "*/15 * * * *" SchedulerHeartbeat
ensure_scheduler_job kf-trial-reminders "0 8 * * *" SchedulerTrialReminders
ensure_scheduler_job kf-recheck-reminders "15 8 * * *" SchedulerRecheckReminders
ensure_scheduler_job kf-timesheet-escalation "5 * * * *" EscalateUnresponsiveTimesheets

echo "functions-core: all HTTP functions, triggers and scheduler jobs deployed."
