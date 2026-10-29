package audit

import (
	"context"
	"sync"
	"time"

	"cloud.google.com/go/firestore"
)

// activityDoc is a single document the web admin console listens to (Firestore
// onSnapshot) so a change made anywhere — a practitioner submitting hours, a
// nursery approving an applicant, another admin saving Settings — reaches an
// open console immediately instead of on the next 15-second poll. It carries
// no business data: only updatedAt plus the last action name, so client read
// access can be granted to admins without exposing audit metadata.
const activityDoc = "platformConfig/adminActivity"

var (
	activityMu      sync.Mutex
	lastActivityAt  time.Time
	activityPending bool
)

// SignalActivity bumps the admin console's live signal. Best-effort and
// throttled to at most one write per second (with a single trailing write to
// catch the last change in a burst), because the plan forbids updating one hot
// document many times per second, and because a signal problem must never fail
// the business change that caused it.
func SignalActivity(db *firestore.Client, action string) {
	if db == nil || action == "" {
		return
	}

	activityMu.Lock()
	now := time.Now()
	if now.Sub(lastActivityAt) >= time.Second {
		lastActivityAt = now
		activityMu.Unlock()
		activityWrite(db, action)
		return
	}
	if activityPending {
		// A trailing write is already scheduled and will land within a second;
		// the console refresh it triggers re-fetches everything anyway.
		activityMu.Unlock()
		return
	}
	activityPending = true
	delay := time.Second - now.Sub(lastActivityAt)
	activityMu.Unlock()

	go func() {
		time.Sleep(delay)
		activityMu.Lock()
		lastActivityAt = time.Now()
		activityPending = false
		activityMu.Unlock()
		// Detached context: this runs after the triggering HTTP request may
		// have completed (or been cancelled), and the signal itself is
		// expendable.
		activityWrite(db, action)
	}()
}

func activityWrite(db *firestore.Client, action string) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_, _ = db.Doc(activityDoc).Set(ctx, map[string]any{
		"updatedAt": time.Now().UTC(),
		"action":    action,
	}, firestore.MergeAll)
}
