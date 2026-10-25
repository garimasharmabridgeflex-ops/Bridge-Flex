package function

import (
	"context"
	"log/slog"
	"net/http"
	"os"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/GoogleCloudPlatform/functions-framework-go/functions"
	"google.golang.org/api/iterator"
	"kvision.internal/shared/audit"
	"kvision.internal/shared/auth"
	"kvision.internal/shared/httpjson"
	"kvision.internal/shared/scheduler"
)

func init() {
	functions.HTTP("SchedulerHeartbeat", schedulerHeartbeat)
	functions.HTTP("SchedulerTrialReminders", schedulerTrialReminders)
	functions.HTTP("SchedulerRecheckReminders", schedulerRecheckReminders)
	// Manual "run now" twins for the admin console. Cloud Scheduler uses the
	// Scheduler* endpoints with an OIDC token; these use a normal admin claim.
	functions.HTTP("RunTrialReminders", authed(runTrialRemindersAdmin))
	functions.HTTP("RunRecheckReminders", authed(runRecheckRemindersAdmin))
}

// schedulerAllowed accepts Cloud Scheduler's OIDC token, the local emulator,
// or an explicit SCHEDULER_KEY header. It never trusts the caller's claims
// because these endpoints are deliberately not wrapped in RequireAuth.
func schedulerAllowed(ctx context.Context, r *http.Request) bool {
	if os.Getenv("FUNCTIONS_EMULATOR") == "true" || os.Getenv("FIRESTORE_EMULATOR_HOST") != "" {
		return true
	}
	if _, err := scheduler.VerifyOIDCToken(ctx, r, ""); err == nil {
		return true
	}
	key := os.Getenv("SCHEDULER_KEY")
	return key != "" && r.Header.Get("X-Scheduler-Key") == key
}

// safeCallerUID is for handlers that may be called without RequireAuth (the
// scheduler endpoints). auth.UID panics by design on a bare context.
func safeCallerUID(ctx context.Context) (uid string) {
	defer func() { _ = recover() }()
	return auth.UID(ctx)
}

// schedulerHeartbeat — POST /schedulerHeartbeat. Invoked by Cloud Scheduler
// as a no-op health check and heartbeat verification.
func schedulerHeartbeat(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	now := time.Now().UTC()

	db, err := fsDB(ctx)
	if err != nil {
		slog.Error("scheduler heartbeat: db unavailable", "error", err)
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "db unavailable")
		return
	}

	_, _ = db.Collection("platformConfig").Doc("heartbeat").Set(ctx, map[string]any{
		"lastHeartbeat": now,
	})

	slog.Info("scheduler heartbeat ok", "timestamp", now)
	httpjson.WriteJSON(w, http.StatusOK, map[string]any{
		"status":    "ok",
		"timestamp": now.Format(time.RFC3339),
	})
}

func schedulerTrialReminders(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !schedulerAllowed(ctx, r) {
		httpjson.WriteError(w, http.StatusForbidden, "FORBIDDEN", "Scheduler authorization required")
		return
	}
	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore unavailable")
		return
	}
	sent, expired, err := runTrialReminders(ctx, db)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}
	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"remindersSent": sent, "trialsExpired": expired})
}

func runTrialRemindersAdmin(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !isAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "NOT_ADMIN", "Admin claim required")
		return
	}
	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore unavailable")
		return
	}
	sent, expired, err := runTrialReminders(ctx, db)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}
	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"remindersSent": sent, "trialsExpired": expired})
}

// runTrialReminders is idempotent: a reminder is written at most once, and a
// trial is expired at most once.
func runTrialReminders(ctx context.Context, db *firestore.Client) (sent int, expired int, err error) {
	now := time.Now().UTC()
	iter := db.Collection("subscriptions").Where("status", "==", string(SubTrialing)).Documents(ctx)
	defer iter.Stop()

	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return sent, expired, err
		}
		var sub NurserySubscription
		if err := doc.DataTo(&sub); err != nil || sub.TrialEndDate == nil {
			continue
		}
		updates := map[string]any{"updatedAt": now}

		if !now.Before(*sub.TrialEndDate) {
			updates["status"] = SubExpired
			expired++
			_ = notifyInApp(ctx, db, sub.NurseryID, "trial_expired", "Your free trial has ended",
				"Choose a membership plan or Pay As You Go to keep posting shifts. Staffing hours remain payable.",
				nil)
		} else if sub.TrialEndDate.Sub(now) <= 72*time.Hour && sub.TrialReminderSentAt == nil {
			days := int(sub.TrialEndDate.Sub(now).Hours()/24) + 1
			updates["trialReminderSentAt"] = now
			sent++
			_ = notifyInApp(ctx, db, sub.NurseryID, "trial_ending", "Your free trial ends soon",
				"Your trial ends in "+itoa(days)+" day(s). Nothing is charged automatically; choose a plan when you are ready.",
				map[string]any{"trialEndDate": sub.TrialEndDate.Format(time.RFC3339)})
			sendTransactionalEmail(ctx, db, sub.NurseryID, "trial_ending",
				map[string]string{"trialEndDate": sub.TrialEndDate.Format("02 Jan 2006")}, true)
		} else {
			continue
		}

		if _, err := doc.Ref.Set(ctx, updates, firestore.MergeAll); err != nil {
			return sent, expired, err
		}
	}
	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:   "scheduler.trial_reminders",
		ActorUID: "system",
		Metadata: map[string]any{"remindersSent": sent, "trialsExpired": expired},
	})
	return sent, expired, nil
}

func schedulerRecheckReminders(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !schedulerAllowed(ctx, r) {
		httpjson.WriteError(w, http.StatusForbidden, "FORBIDDEN", "Scheduler authorization required")
		return
	}
	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore unavailable")
		return
	}
	sent, err := runRecheckReminders(ctx, db)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}
	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"remindersSent": sent})
}

func runRecheckRemindersAdmin(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !isAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "NOT_ADMIN", "Admin claim required")
		return
	}
	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore unavailable")
		return
	}
	sent, err := runRecheckReminders(ctx, db)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}
	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"remindersSent": sent})
}

// runRecheckReminders warns practitioners 30 days before their DBS recheck is
// due. It only considers practitioners already approved by K Flex.
func runRecheckReminders(ctx context.Context, db *firestore.Client) (int, error) {
	now := time.Now().UTC()
	windowEnd := now.AddDate(0, 0, 30)
	iter := db.Collection("profiles").Where("vettingStatus", "==", string(VettingApproved)).Documents(ctx)
	defer iter.Stop()

	sent := 0
	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return sent, err
		}
		var p Profile
		if err := doc.DataTo(&p); err != nil || p.DBSRecheckDue == nil {
			continue
		}
		if p.DBSRecheckDue.After(windowEnd) {
			continue
		}
		if p.DBSRecheckReminderSentAt != nil {
			continue
		}
		_ = notifyInApp(ctx, db, doc.Ref.ID, "dbs_recheck_due", "DBS recheck due soon",
			"Your DBS recheck is due by "+p.DBSRecheckDue.Format("2 Jan 2006")+". Please contact K Flex.",
			map[string]any{"dbsRecheckDue": p.DBSRecheckDue.Format(time.RFC3339)})
		if _, err := doc.Ref.Set(ctx, map[string]any{
			"dbsRecheckReminderSentAt": now,
			"updatedAt":                now,
		}, firestore.MergeAll); err != nil {
			return sent, err
		}
		sent++
	}
	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:   "scheduler.dbs_recheck_reminders",
		ActorUID: "system",
		Metadata: map[string]any{"remindersSent": sent},
	})
	return sent, nil
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	digits := ""
	for n > 0 {
		digits = string(rune('0'+n%10)) + digits
		n /= 10
	}
	return digits
}
