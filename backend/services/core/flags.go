package function

import (
	"context"
	"sync"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type GateMode string

const (
	GateOff     GateMode = "off"
	GateWarn    GateMode = "warn"
	GateEnforce GateMode = "enforce"
)

const featureFlagsDoc = "platformConfig/featureFlags"

type flagsCache struct {
	sync.RWMutex
	flags     map[string]GateMode
	lastFetch time.Time
}

var globalFlags = &flagsCache{
	flags: make(map[string]GateMode),
}

// GetGateMode returns the current GateMode for a feature gate.
// Results are cached in memory for 60 seconds with fallback to the last-good value.
// Defaults to GateOff if not found or unset (Rule 6.1.4).
func GetGateMode(ctx context.Context, db *firestore.Client, gateName string) GateMode {
	globalFlags.RLock()
	if time.Since(globalFlags.lastFetch) < 60*time.Second && len(globalFlags.flags) > 0 {
		mode, ok := globalFlags.flags[gateName]
		globalFlags.RUnlock()
		if ok {
			return mode
		}
		return GateOff
	}
	globalFlags.RUnlock()

	globalFlags.Lock()
	defer globalFlags.Unlock()

	// Double-check under write lock
	if time.Since(globalFlags.lastFetch) < 60*time.Second && len(globalFlags.flags) > 0 {
		mode, ok := globalFlags.flags[gateName]
		if ok {
			return mode
		}
		return GateOff
	}

	snap, err := db.Doc(featureFlagsDoc).Get(ctx)
	if err == nil {
		var raw map[string]string
		if snap.DataTo(&raw) == nil {
			newMap := make(map[string]GateMode, len(raw))
			for k, v := range raw {
				switch GateMode(v) {
				case GateEnforce:
					newMap[k] = GateEnforce
				case GateWarn:
					newMap[k] = GateWarn
				default:
					newMap[k] = GateOff
				}
			}
			globalFlags.flags = newMap
			globalFlags.lastFetch = time.Now()
		}
	} else if status.Code(err) == codes.NotFound {
		// Document not yet created in Firestore, default empty map and reset fetch time
		globalFlags.lastFetch = time.Now()
	}
	// If error is network or temporary, we retain globalFlags.flags as last-good fallback

	mode, ok := globalFlags.flags[gateName]
	if ok {
		return mode
	}
	return GateOff
}
