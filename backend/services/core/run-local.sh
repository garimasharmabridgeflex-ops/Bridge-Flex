#!/usr/bin/env bash
# Runs every HTTP-triggered function in functions-core as its own local
# process, each on a fixed port — the operational cost of Go under Cloud
# Functions noted in ARCHITECTURE.md v2 §1a/§7: N processes instead of one
# unified Functions emulator. Point FIRESTORE_EMULATOR_HOST /
# FIREBASE_AUTH_EMULATOR_HOST at the running emulators before invoking this
# (see backend/README.md). Eventarc-triggered functions (InitProfileOnSignUp,
# SyncProfilePublic, MatchNewShift, RecomputeRating) aren't started here —
# they have no local trigger dispatch story; see §7 for the unit-test-only
# approach used for those instead.
set -euo pipefail
cd "$(dirname "$0")"

declare -A FUNCS=(
  [UpdateProfile]=8101
  [GetProfile]=8102
  [GetPublicProfile]=8103
  [CreateShift]=8104
  [UpdateShift]=8105
  [ListOpenShifts]=8106
  [ListMyShifts]=8113
  [GetShift]=8107
  [AcceptShift]=8108
  [CancelShift]=8109
  [MarkNoShow]=8116
  [CreateRating]=8110
  [CreateDocument]=8111
  [ReviewDocument]=8112
  [GetDocumentStatus]=8114
  [ListMyDocuments]=8115
  [ListPendingDocuments]=8117
  [DeleteAccount]=8118
  # functions-communication's run-local.sh independently owns 8121-8128 —
  # jumping to 8140+ here avoids any port collision between the two
  # services' independently-numbered local process maps.
  [GetPlatformStats]=8140
  [ListAllUsers]=8141
  [GetUserDetail]=8142
  [SetUserSuspended]=8143
  [SetVerificationBadge]=8144
  [ListRatings]=8145
  [ListTrainingModules]=8146
  [SubmitTrainingQuiz]=8147
  [MarkTrainingVideoWatched]=8148
  [ListTrainingModulesAdmin]=8149
  [UpsertTrainingModule]=8150
  [DeleteTrainingModule]=8151
  [ApproveShiftApplicant]=8152
  [RejectShiftApplicant]=8153
  [GetRequiredPolicies]=8154
  [GetPolicy]=8155
  [AcceptPolicies]=8156
  [GetCompanyInfo]=8157
  [UpdateCompanyInfo]=8158
  [SchedulerHeartbeat]=8159
  [GetVettingChecklist]=8160
  [RecordVettingCheck]=8161
  [RequestMoreDocuments]=8162
  [ApprovePractitionerVetting]=8163
  [RejectPractitionerVetting]=8164
  [UpdateSensitiveProfile]=8165
  [GetSensitiveProfile]=8166
  [CreateBranch]=8167
  [ListBranches]=8168
  [UpdateBranch]=8169
  [DeleteBranch]=8170
  [ApproveNurseryRegistration]=8171
  [RejectNurseryRegistration]=8172
  [GetActiveRateCard]=8173
  [ListRateCards]=8174
  [UpsertRateCard]=8175
  [CancelShiftStructured]=8176
  [SubmitTimesheet]=8185
  [GetTimesheet]=8186
  [ListTimesheets]=8187
  [ApproveTimesheet]=8188
  [RequestTimesheetCorrection]=8189
  [DisputeTimesheet]=8190
  [AdminApproveTimesheet]=8191
  [EscalateUnresponsiveTimesheets]=8192
  [GetPayrollProfile]=8193
  [UpdatePayrollProfile]=8194
  [GeneratePayrollPeriod]=8195
  [ListPayrollPeriods]=8196
  [GetPayrollPeriodDetail]=8197
  [ExportPayrollCSV]=8198
  [MarkPayrollPeriodPaid]=8199
  [GetPractitionerEarnings]=8201
  [LinkPayslip]=8202
  [GetPlans]=8203
  [UpsertPlan]=8204
  [GetNurserySubscription]=8205
  [AssignNurseryPlan]=8206
  [GenerateWeeklyInvoices]=8207
  [ListInvoices]=8208
  [GetInvoice]=8209
  [MarkInvoicePaid]=8210
  [CreateLedgerEntry]=8211
  [RequestPlanChange]=8212
  [CancelSubscription]=8213
  [ListSubscriptionRequests]=8214
  [GetFeatureFlags]=8215
  [UpdateFeatureFlags]=8216
  [ListAuditLogs]=8217
  [AdminSavePolicyDraft]=8218
  [AdminApprovePolicy]=8219
  [AdminPublishPolicy]=8220
  [ListPolicies]=8221
  [GetInvoiceDocument]=8222
  [CreateDiscountCode]=8223
  [ListDiscountCodes]=8224
  [SetDiscountCodeActive]=8225
  [SendAdminNotification]=8226
)

pids=()
cleanup() {
  echo "stopping functions-core..."
  kill "${pids[@]}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

for name in "${!FUNCS[@]}"; do
  port="${FUNCS[$name]}"
  echo "functions-core: $name -> :$port"
  FUNCTION_TARGET="$name" PORT="$port" go run ./cmd &
  pids+=("$!")
done

echo "all functions-core HTTP endpoints running — see ports above. Ctrl+C to stop."
wait
