package function

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/GoogleCloudPlatform/functions-framework-go/functions"
	"github.com/cloudevents/sdk-go/v2/event"
)

func init() {
	functions.CloudEvent("OnShiftBooked", onShiftBooked)
	functions.CloudEvent("OnRatingReceived", onRatingReceived)
	functions.CloudEvent("OnShiftMatched", onShiftMatched)
	functions.CloudEvent("OnShiftCancelled", onShiftCancelled)
	functions.CloudEvent("OnShiftApplied", onShiftApplied)
	functions.CloudEvent("OnShiftApplicationDecided", onShiftApplicationDecided)
}

// pubSubMessage / messagePublishedData mirror the Pub/Sub CloudEvent JSON
// wire shape directly (Google's documented pattern for Go 2nd-gen Pub/Sub
// triggers) — no proto package needed here, unlike the Firestore/Auth
// triggers in functions-core, because Pub/Sub CloudEvent data is plain JSON,
// not protobuf (ARCHITECTURE.md v2 §1a).
type pubSubMessage struct {
	Data       []byte            `json:"data"`
	Attributes map[string]string `json:"attributes"`
}

type messagePublishedData struct {
	Message pubSubMessage `json:"message"`
}

type shiftBookedPayload struct {
	ShiftID   string `json:"shiftId"`
	NurseryID string `json:"nurseryId"`
	StaffID   string `json:"staffId"`
}

// onShiftBooked is bound at deploy time to the shift-booked Pub/Sub topic
// (ARCHITECTURE.md v2 §1a table). It creates the chat session (a client can
// never do this itself, §2) and notifies both parties.
func onShiftBooked(ctx context.Context, e event.Event) error {
	var msg messagePublishedData
	if err := e.DataAs(&msg); err != nil {
		return fmt.Errorf("event.DataAs: %w", err)
	}
	var payload shiftBookedPayload
	if err := json.Unmarshal(msg.Message.Data, &payload); err != nil {
		return fmt.Errorf("unmarshal shift-booked payload: %w", err)
	}

	db, err := fsDB(ctx)
	if err != nil {
		return err
	}
	if _, err := ensureChatSession(ctx, db, payload.ShiftID, payload.NurseryID, payload.StaffID); err != nil {
		return err
	}

	if err := notifyUser(ctx, payload.NurseryID, "shift_booked",
		"Shift booked", "Your shift has been booked.",
		map[string]any{"shiftId": payload.ShiftID}); err != nil {
		return err
	}
	return notifyUser(ctx, payload.StaffID, "shift_booked",
		"Shift confirmed", "You've booked a shift.",
		map[string]any{"shiftId": payload.ShiftID})
}

type ratingReceivedPayload struct {
	RatingID string `json:"ratingId"`
	RateeID  string `json:"rateeId"`
	RaterID  string `json:"raterId"`
	ShiftID  string `json:"shiftId"`
}

// onRatingReceived is bound at deploy time to the rating-received Pub/Sub
// topic (§1a table).
func onRatingReceived(ctx context.Context, e event.Event) error {
	var msg messagePublishedData
	if err := e.DataAs(&msg); err != nil {
		return fmt.Errorf("event.DataAs: %w", err)
	}
	var payload ratingReceivedPayload
	if err := json.Unmarshal(msg.Message.Data, &payload); err != nil {
		return fmt.Errorf("unmarshal rating-received payload: %w", err)
	}

	return notifyUser(ctx, payload.RateeID, "rating_received",
		"New rating", "You received a new rating.",
		map[string]any{"ratingId": payload.RatingID, "shiftId": payload.ShiftID})
}

type shiftMatchedPayload struct {
	ShiftID   string `json:"shiftId"`
	NurseryID string `json:"nurseryId"`
	StaffID   string `json:"staffId"`
}

// onShiftMatched subscribes to shift-matched "the same way [communication]
// does to shift-booked" (§6) — published per-candidate by functions-core's
// matchNewShift trigger.
func onShiftMatched(ctx context.Context, e event.Event) error {
	var msg messagePublishedData
	if err := e.DataAs(&msg); err != nil {
		return fmt.Errorf("event.DataAs: %w", err)
	}
	var payload shiftMatchedPayload
	if err := json.Unmarshal(msg.Message.Data, &payload); err != nil {
		return fmt.Errorf("unmarshal shift-matched payload: %w", err)
	}

	return notifyUser(ctx, payload.StaffID, "new_matching_shift",
		"New shift available", "A new shift matching your profile is available.",
		map[string]any{"shiftId": payload.ShiftID, "nurseryId": payload.NurseryID})
}

type shiftCancelledPayload struct {
	ShiftID     string   `json:"shiftId"`
	NurseryID   string   `json:"nurseryId"`
	StaffIDs    []string `json:"staffIds,omitempty"`
	CancelledBy string   `json:"cancelledBy"`
	NewStatus   string   `json:"newStatus"`
}

// onShiftCancelled subscribes to shift-cancelled (functions-core's
// cancelShift, full app spec §3). Only published when there's someone to
// notify — a nursery cancelling an open shift nobody had booked publishes
// nothing (see cancelShift). Who gets notified depends on who cancelled:
// staff dropping their own slot notifies the nursery their cover just fell
// through; the nursery pulling the whole shift notifies every staff member
// who had a slot on it (plural — a multi-capacity shift can have more than
// one).
func onShiftCancelled(ctx context.Context, e event.Event) error {
	var msg messagePublishedData
	if err := e.DataAs(&msg); err != nil {
		return fmt.Errorf("event.DataAs: %w", err)
	}
	var payload shiftCancelledPayload
	if err := json.Unmarshal(msg.Message.Data, &payload); err != nil {
		return fmt.Errorf("unmarshal shift-cancelled payload: %w", err)
	}

	if payload.CancelledBy == "staff" {
		return notifyUser(ctx, payload.NurseryID, "shift_cancelled",
			"Shift cover dropped",
			"A staff member cancelled — your shift is open again for someone else to accept.",
			map[string]any{"shiftId": payload.ShiftID})
	}

	for _, staffID := range payload.StaffIDs {
		if err := notifyUser(ctx, staffID, "shift_cancelled",
			"Shift cancelled",
			"The nursery cancelled a shift you had booked.",
			map[string]any{"shiftId": payload.ShiftID}); err != nil {
			return err
		}
	}
	return nil
}

type shiftAppliedPayload struct {
	ShiftID   string `json:"shiftId"`
	NurseryID string `json:"nurseryId"`
	StaffID   string `json:"staffId"`
}

// onShiftApplied notifies the nursery that someone wants the shift. It
// deliberately does NOT create a chat session — that happens on approval, so
// a nursery never ends up with a thread against someone it turned down.
func onShiftApplied(ctx context.Context, e event.Event) error {
	var msg messagePublishedData
	if err := e.DataAs(&msg); err != nil {
		return fmt.Errorf("event.DataAs: %w", err)
	}
	var payload shiftAppliedPayload
	if err := json.Unmarshal(msg.Message.Data, &payload); err != nil {
		return fmt.Errorf("unmarshal shift-applied payload: %w", err)
	}

	return notifyUser(ctx, payload.NurseryID, "shift_application",
		"New applicant",
		"Someone has applied for one of your shifts. Review their profile to approve or decline.",
		map[string]any{"shiftId": payload.ShiftID, "staffId": payload.StaffID},
	)
}

type shiftDecisionPayload struct {
	ShiftID      string `json:"shiftId"`
	NurseryID    string `json:"nurseryId"`
	StaffID      string `json:"staffId"`
	Approved     bool   `json:"approved"`
	AutoRejected bool   `json:"autoRejected"`
}

// onShiftApplicationDecided tells an applicant the outcome.
//
// An auto-rejection gets different wording from a decline: the shift simply
// filled up, which is not a judgement on the applicant, and telling someone
// they were "declined" when nobody looked at them would be both inaccurate
// and discouraging.
func onShiftApplicationDecided(ctx context.Context, e event.Event) error {
	var msg messagePublishedData
	if err := e.DataAs(&msg); err != nil {
		return fmt.Errorf("event.DataAs: %w", err)
	}
	var payload shiftDecisionPayload
	if err := json.Unmarshal(msg.Message.Data, &payload); err != nil {
		return fmt.Errorf("unmarshal shift decision payload: %w", err)
	}

	notificationType := "shift_application_declined"
	title := "Application declined"
	body := "The nursery has gone with someone else for this shift."
	switch {
	case payload.Approved:
		notificationType = "shift_application_approved"
		title = "You got the shift"
		// The separate shift_booked notification from onShiftBooked covers
		// the booking itself; this one is specifically the decision.
		body = "The nursery approved your application. Check your shifts for the details."
	case payload.AutoRejected:
		notificationType = "shift_application_closed"
		title = "Shift filled"
		body = "This shift has been fully staffed, so your application has closed."
	}

	return notifyUser(ctx, payload.StaffID, notificationType, title, body,
		map[string]any{"shiftId": payload.ShiftID, "approved": payload.Approved},
	)
}
