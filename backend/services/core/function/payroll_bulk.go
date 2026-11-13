package function

import (
	"context"
	"fmt"
	"net/http"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/GoogleCloudPlatform/functions-framework-go/functions"
	"google.golang.org/api/iterator"

	"kvision.internal/shared/audit"
	"kvision.internal/shared/auth"
	"kvision.internal/shared/httpjson"
)

func init() {
	functions.HTTP("MarkPayrollPeriodsPaid", authed(markPayrollPeriodsPaid))
}

type markPeriodsPaidRequest struct {
	// PeriodIDs is optional. Empty means "every period that is not paid yet",
	// which is the console's "Mark all as paid" button: payroll often leaves
	// through the company's own bank or a bureau, and the platform still has
	// to record that it happened so payslips and earnings stop reporting the
	// period as outstanding.
	PeriodIDs []string `json:"periodIds,omitempty"`
}

// markPayrollPeriodsPaid — POST /markPayrollPeriodsPaid. Finance or SuperAdmin.
//
// Marks one or many periods paid in a single request, and queues the payslip
// email for every practitioner in them. Per-period failures are reported
// rather than aborting the batch: one unreadable period must not stop the
// other nineteen being settled.
func markPayrollPeriodsPaid(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !isFinanceOrSuperAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "FORBIDDEN", "Finance or SuperAdmin claim required")
		return
	}

	var req markPeriodsPaidRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	periods := make([]PayrollPeriod, 0)
	if len(req.PeriodIDs) == 0 {
		iter := db.Collection("payrollPeriods").Limit(200).Documents(ctx)
		defer iter.Stop()
		for {
			doc, err := iter.Next()
			if err == iterator.Done {
				break
			}
			if err != nil {
				httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
				return
			}
			var period PayrollPeriod
			if err := doc.DataTo(&period); err != nil {
				continue
			}
			if period.Status == PayrollPeriodPaid {
				continue
			}
			period.ID = doc.Ref.ID
			periods = append(periods, period)
		}
	} else {
		for _, id := range req.PeriodIDs {
			id = strings.TrimSpace(id)
			if id == "" {
				continue
			}
			snap, err := db.Collection("payrollPeriods").Doc(id).Get(ctx)
			if err != nil {
				continue
			}
			var period PayrollPeriod
			if err := snap.DataTo(&period); err != nil {
				continue
			}
			period.ID = id
			periods = append(periods, period)
		}
	}

	now := time.Now().UTC()
	marked := 0
	emailed := 0
	failed := 0
	for _, period := range periods {
		sent, err := settlePayrollPeriod(ctx, db, period.ID, now)
		if err != nil {
			failed++
			continue
		}
		marked++
		emailed += sent
	}

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:   "payroll.mark_all_paid",
		ActorUID: auth.UID(ctx),
		Metadata: map[string]any{
			"requested": len(req.PeriodIDs),
			"marked":    marked,
			"failed":    failed,
			"payslipMails": emailed,
			"paidAt":    now,
		},
	})

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{
		"status":     "paid",
		"periods":    marked,
		"failed":     failed,
		"emailsSent": emailed,
	})
}

// settlePayrollPeriod flips one period (and its lines) to paid, writes the
// payslip-available event and queues each practitioner's "you have been paid"
// email. It returns how many emails were queued.
//
// It does not send the email itself: the mail service owns templates and
// transport, and a mail problem must never roll back the payment record.
func settlePayrollPeriod(ctx context.Context, db *firestore.Client, periodID string, now time.Time) (int, error) {
	periodRef := db.Collection("payrollPeriods").Doc(periodID)
	periodSnap, err := periodRef.Get(ctx)
	if err != nil {
		return 0, err
	}
	var period PayrollPeriod
	if err := periodSnap.DataTo(&period); err != nil {
		return 0, err
	}
	if period.Status == PayrollPeriodPaid {
		return 0, nil
	}

	lineDocs, err := periodRef.Collection("lines").Documents(ctx).GetAll()
	if err != nil {
		return 0, err
	}

	batch := db.Batch()
	batch.Update(periodRef, []firestore.Update{
		{Path: "status", Value: PayrollPeriodPaid},
		{Path: "paidAt", Value: now},
		{Path: "updatedAt", Value: now},
	})
	lines := make([]PayrollLine, 0, len(lineDocs))
	for _, doc := range lineDocs {
		batch.Update(doc.Ref, []firestore.Update{
			{Path: "status", Value: "paid"},
			{Path: "paidAt", Value: now},
			{Path: "updatedAt", Value: now},
		})
		var line PayrollLine
		if err := doc.DataTo(&line); err == nil {
			line.ID = doc.Ref.ID
			lines = append(lines, line)
		}
	}
	if _, err := batch.Commit(ctx); err != nil {
		return 0, err
	}

	label := period.PeriodName
	if label == "" {
		label = period.StartDate.Format("2 Jan 2006") + " – " + period.EndDate.Format("2 Jan 2006")
	}

	sent := 0
	for _, line := range lines {
		if line.PractitionerID == "" {
			continue
		}
		if err := notifyInApp(ctx, db, line.PractitionerID, "payslip_paid", "You have been paid",
			fmt.Sprintf("Payroll for %s has been paid. Your payslip is available.", label),
			map[string]any{"link": "/earnings", "periodId": periodID}); err != nil {
			continue
		}
		if sendTransactionalEmail(ctx, db, line.PractitionerID, "payslip_paid", map[string]string{
			"periodLabel": label,
			"amount":      formatPence(line.GrossPayPence),
			"appUrl":      appHomeURL,
		}, true) {
			sent++
		}
	}
	return sent, nil
}
