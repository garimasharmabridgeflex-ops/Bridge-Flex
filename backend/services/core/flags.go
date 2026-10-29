package function

import (
	"context"
	"net/http"
	"sync"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/GoogleCloudPlatform/functions-framework-go/functions"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"kvision.internal/shared/audit"
	"kvision.internal/shared/auth"
	"kvision.internal/shared/httpjson"
)

func init() {
	functions.HTTP("GetFeatureFlags", authed(getFeatureFlags))
	functions.HTTP("UpdateFeatureFlags", authed(updateFeatureFlags))
}

type GateMode string

const (
	GateOff     GateMode = "off"
	GateWarn    GateMode = "warn"
	GateEnforce GateMode = "enforce"
)

const featureFlagsDoc = "platformConfig/featureFlags"

// defaultGateModes is the launch posture. Nursery approval and trial expiry
// are enforced because both workflows exist end to end: approval starts the
// trial, and after it ends the nursery requests a plan for an admin to assign.
// Practitioner vetting and terms start at warn so pre-existing accounts and
// unpublished policies never lock anyone out before an admin has reviewed
// them. Every mode is editable from the admin console.
var defaultGateModes = map[string]GateMode{
	"nurseryApprovalRequired":      GateEnforce,
	"practitionerApprovalRequired": GateWarn,
	"trialExpired":                 GateEnforce,
	"termsAcceptanceRequired":      GateWarn,
}

func effectiveGate(flags map[string]GateMode, gateName string) GateMode {
	if mode, ok := flags[gateName]; ok {
		return mode
	}
	if mode, ok := defaultGateModes[gateName]; ok {
		return mode
	}
	return GateOff
}

type flagsCache struct {
	sync.RWMutex
	flags     map[string]GateMode
	lastFetch time.Time
}

var globalFlags = &flagsCache{
	flags: make(map[string]GateMode),
}

// loadGateModes reads platformConfig/featureFlags. Unknown values collapse to
// off, and a missing document falls back to the safe defaults above.
func loadGateModes(ctx context.Context, db *firestore.Client) (map[string]GateMode, error) {
	snap, err := db.Doc(featureFlagsDoc).Get(ctx)
	if err != nil {
		if status.Code(err) == codes.NotFound {
			// Nothing saved yet — the code defaults apply.
			return map[string]GateMode{}, nil
		}
		return nil, err
	}
	return gateModesFromDoc(snap.Data()), nil
}

// gateModesFromDoc converts the stored document into gate modes.
//
// The document is decoded as map[string]any rather than map[string]string on
// purpose: it also holds updatedAt (a Firestore timestamp) and updatedBy, and
// decoding a timestamp into a string makes the whole decode fail. That failure
// was silent — getFeatureFlags fell back to the code defaults and
// updateFeatureFlags then cached an empty flag set — so every saved gate
// appeared to revert the moment it was written.
//
// Only known gate names are kept, so an unrelated field added to this document
// later cannot invent a gate.
func gateModesFromDoc(raw map[string]any) map[string]GateMode {
	out := map[string]GateMode{}
	for name := range defaultGateModes {
		value, ok := raw[name].(string)
		if !ok {
			// Not stored (or stored as a non-string): leave it to the default.
			continue
		}
		switch GateMode(value) {
		case GateEnforce:
			out[name] = GateEnforce
		case GateWarn:
			out[name] = GateWarn
		default:
			out[name] = GateOff
		}
	}
	return out
}

// GetGateMode returns the current GateMode for a feature gate. Results are
// cached in memory for 60 seconds with last-good fallback on read failure.
func GetGateMode(ctx context.Context, db *firestore.Client, gateName string) GateMode {
	globalFlags.RLock()
	if time.Since(globalFlags.lastFetch) < 60*time.Second && len(globalFlags.flags) > 0 {
		mode := effectiveGate(globalFlags.flags, gateName)
		globalFlags.RUnlock()
		return mode
	}
	globalFlags.RUnlock()

	globalFlags.Lock()
	defer globalFlags.Unlock()

	// Double-check under the write lock.
	if time.Since(globalFlags.lastFetch) < 60*time.Second && len(globalFlags.flags) > 0 {
		return effectiveGate(globalFlags.flags, gateName)
	}

	fresh, err := loadGateModes(ctx, db)
	if err != nil && len(globalFlags.flags) > 0 {
		// Network/read failure: keep the last good values rather than
		// silently downgrading every gate to its default.
		return effectiveGate(globalFlags.flags, gateName)
	}
	globalFlags.flags = fresh
	globalFlags.lastFetch = time.Now()
	return effectiveGate(fresh, gateName)
}

// getFeatureFlags — GET /getFeatureFlags. Admin-only. Returns both the stored
// overrides and the code defaults, so the console can show which values are
// explicitly set.
func getFeatureFlags(w http.ResponseWriter, r *http.Request) {
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

	stored, err := loadGateModes(ctx, db)
	if err != nil {
		stored = map[string]GateMode{}
	}
	effective := map[string]GateMode{}
	for name := range defaultGateModes {
		effective[name] = effectiveGate(stored, name)
	}
	httpjson.WriteJSON(w, http.StatusOK, map[string]any{
		"flags":    effective,
		"stored":   stored,
		"defaults": defaultGateModes,
	})
}

// updateFeatureFlags — POST /updateFeatureFlags. Admin-only. Only known gate
// names are accepted so a typo cannot silently create a dead flag.
func updateFeatureFlags(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !isAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "NOT_ADMIN", "Admin claim required")
		return
	}

	var req struct {
		Flags map[string]string `json:"flags"`
	}
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	if len(req.Flags) == 0 {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "flags is required")
		return
	}

	updates := map[string]any{}
	for name, raw := range req.Flags {
		if _, known := defaultGateModes[name]; !known {
			httpjson.WriteError(w, http.StatusBadRequest, "UNKNOWN_GATE", "Unknown gate: "+name)
			return
		}
		mode := GateMode(raw)
		if mode != GateOff && mode != GateWarn && mode != GateEnforce {
			httpjson.WriteError(w, http.StatusBadRequest, "BAD_GATE_MODE", "Mode must be off, warn or enforce")
			return
		}
		updates[name] = string(mode)
	}
	updates["updatedAt"] = time.Now().UTC()
	updates["updatedBy"] = auth.UID(ctx)

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore unavailable")
		return
	}
	if _, err := db.Doc(featureFlagsDoc).Set(ctx, updates, firestore.MergeAll); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	globalFlags.Lock()
	if fresh, err := loadGateModes(ctx, db); err == nil {
		globalFlags.flags = fresh
	}
	globalFlags.lastFetch = time.Now()
	globalFlags.Unlock()

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:   "platform.update_feature_flags",
		ActorUID: auth.UID(ctx),
		Metadata: updates,
	})

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"flags": updates})
}
