#!/usr/bin/env bash
cd "$(dirname "$0")"

: "${PROJECT_ID:=kvision-503115}"
: "${REGION:=europe-west2}"
: "${GO_RUNTIME:=go125}"

export PROJECT_ID REGION GO_RUNTIME

FUNCTIONS=(
  UpdateProfile
  GetPolicy
  AcceptPolicies
  GetCompanyInfo
  UpdateCompanyInfo
  GetVettingChecklist
  RecordVettingCheck
  RequestMoreDocuments
  ApprovePractitionerVetting
  RejectPractitionerVetting
  UpdateSensitiveProfile
  GetSensitiveProfile
  CreateBranch
  ListBranches
  UpdateBranch
  DeleteBranch
  ApproveNurseryRegistration
  RejectNurseryRegistration
  GetActiveRateCard
  ListRateCards
  UpsertRateCard
  CancelShiftStructured
  SubmitTimesheet
  GetTimesheet
  ListTimesheets
  ApproveTimesheet
  RequestTimesheetCorrection
  DisputeTimesheet
  AdminApproveTimesheet
  EscalateUnresponsiveTimesheets
  GetPayrollProfile
  UpdatePayrollProfile
  GeneratePayrollPeriod
  ListPayrollPeriods
  GetPayrollPeriodDetail
  ExportPayrollCSV
  MarkPayrollPeriodPaid
  GetPractitionerEarnings
  LinkPayslip
  GetPlans
  UpsertPlan
  GetNurserySubscription
  AssignNurseryPlan
  GenerateWeeklyInvoices
  ListInvoices
  GetInvoice
  MarkInvoicePaid
  CreateLedgerEntry
  SchedulerHeartbeat
)

MAX_PARALLEL=5
pids=()

for fn in "${FUNCTIONS[@]}"; do
  echo "==> Deploying $fn..."
  gcloud functions deploy "$fn" \
    --gen2 --runtime="$GO_RUNTIME" --region="$REGION" --project="$PROJECT_ID" \
    --source=. --entry-point="$fn" \
    --trigger-http --allow-unauthenticated --quiet &
  pids+=($!)
  
  while [ ${#pids[@]} -ge $MAX_PARALLEL ]; do
    sleep 3
    new_pids=()
    for pid in "${pids[@]}"; do
      if kill -0 "$pid" 2>/dev/null; then
        new_pids+=("$pid")
      fi
    done
    pids=("${new_pids[@]}")
  done
done

for pid in "${pids[@]}"; do
  wait "$pid" || true
done

echo "==> Done deploying functions."
