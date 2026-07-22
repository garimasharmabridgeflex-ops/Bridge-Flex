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
