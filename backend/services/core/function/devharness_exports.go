package function

import (
	"context"

	"github.com/cloudevents/sdk-go/v2/event"
)

// Exported wrappers around the unexported Eventarc handlers, used only by
// backend/services/core/devharness — a local dev-only process that watches
// the Firestore emulator directly (since Eventarc itself has no local
// dispatch path, ARCHITECTURE.md v2 §7) and invokes the *real* handler
// logic below, not a reimplementation of it. Not used by production
// deploys, which bind these by name via functions.CloudEvent registration
// in this package's other files.

func SyncProfilePublic(ctx context.Context, e event.Event) error { return syncProfilePublic(ctx, e) }
func RecomputeRating(ctx context.Context, e event.Event) error   { return recomputeRating(ctx, e) }
func MatchNewShift(ctx context.Context, e event.Event) error     { return matchNewShift(ctx, e) }
