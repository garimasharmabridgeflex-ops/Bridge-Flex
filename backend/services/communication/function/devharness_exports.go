package function

import (
	"context"

	"github.com/cloudevents/sdk-go/v2/event"
)

// Exported wrappers around the unexported Pub/Sub-triggered handlers, used
// only by backend/services/communication/devharness — see the identical
// comment in services/core/function/devharness_exports.go for why this
// exists. Not used by production deploys.

func OnShiftBooked(ctx context.Context, e event.Event) error    { return onShiftBooked(ctx, e) }
func OnRatingReceived(ctx context.Context, e event.Event) error { return onRatingReceived(ctx, e) }
func OnShiftMatched(ctx context.Context, e event.Event) error   { return onShiftMatched(ctx, e) }
func OnShiftCancelled(ctx context.Context, e event.Event) error { return onShiftCancelled(ctx, e) }
