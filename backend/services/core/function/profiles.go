package function

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/GoogleCloudPlatform/functions-framework-go/functions"
	"github.com/cloudevents/sdk-go/v2/event"
	"github.com/googleapis/google-cloudevents-go/cloud/firestoredata"
	"github.com/googleapis/google-cloudevents-go/firebase/authdata"
	"google.golang.org/genproto/googleapis/type/latlng"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/proto"

	"bridgeflex/shared/auth"
	"bridgeflex/shared/httpjson"
)

func init() {
	functions.CloudEvent("InitProfileOnSignUp", initProfileOnSignUp)
	functions.CloudEvent("SyncProfilePublic", syncProfilePublic)
	functions.HTTP("UpdateProfile", authed(updateProfile))
	functions.HTTP("GetProfile", authed(getProfile))
	functions.HTTP("GetPublicProfile", authed(getPublicProfile))
}

// initProfileOnSignUp is bound at deploy time to the
// google.firebase.auth.user.v1.created Eventarc trigger (ARCHITECTURE.md v2
// §1a). It seeds a minimal profiles/{uid} doc; role stays unset until the
// client calls POST /updateProfile with {"role": "nursery"|"staff"} once.
func initProfileOnSignUp(ctx context.Context, e event.Event) error {
	var data authdata.AuthEventData
	if err := proto.Unmarshal(e.Data(), &data); err != nil {
		return fmt.Errorf("proto.Unmarshal auth event: %w", err)
	}
	uid := data.GetUid()
	if uid == "" {
		return fmt.Errorf("auth event missing uid")
	}

	db, err := fsDB(ctx)
	if err != nil {
		return err
	}

	name := data.GetDisplayName()
	if name == "" {
		name = data.GetEmail()
	}

	profile := Profile{
		Role:      "",
		Name:      name,
		DBSStatus: DBSUnverified,
		Rating:    Rating{},
		CreatedAt: time.Now(),
	}
	_, err = db.Collection("profiles").Doc(uid).Set(ctx, profile)
	return err
}

// syncProfilePublic is bound at deploy time to a Firestore-write Eventarc
// trigger filtered to profiles/{uid} (ARCHITECTURE.md v2 §1a table). It
// recomputes the full derived profilesPublic/{uid} doc from the just-written
// profiles/{uid} doc on every run, so retries are naturally idempotent — see
// §2 for the residual-staleness note on permanent trigger failure.
func syncProfilePublic(ctx context.Context, e event.Event) error {
	var data firestoredata.DocumentEventData
	if err := proto.Unmarshal(e.Data(), &data); err != nil {
		return fmt.Errorf("proto.Unmarshal firestore event: %w", err)
	}

	doc := data.GetValue()
	if doc == nil {
		// Delete event — no downstream public doc to maintain. Profile
		// deletion/GDPR cleanup is out of scope for Phase 1.
		return nil
	}

	uid, err := lastPathSegment(doc.GetName())
	if err != nil {
		return err
	}

	fields := doc.GetFields()
	pub := ProfilePublic{
		Role:      Role(fieldString(fields, "role")),
		Name:      fieldString(fields, "name"),
		DBSBadge:  DBSStatus(fieldString(fields, "dbsStatus")),
		UpdatedAt: time.Now(),
	}
	if ratingFields := fieldMap(fields, "rating"); ratingFields != nil {
		pub.Rating = Rating{
			Average: fieldDouble(ratingFields, "average"),
			Count:   fieldInt(ratingFields, "count"),
		}
	}
	if gp, ok := fieldGeo(fields, "location"); ok {
		pub.LocationArea = geohashPrefix(gp.GetLatitude(), gp.GetLongitude(), geohashPrecision)
	}

	db, err := fsDB(ctx)
	if err != nil {
		return err
	}
	_, err = db.Collection("profilesPublic").Doc(uid).Set(ctx, pub)
	return err
}

var (
	errRoleAlreadySet = errors.New("role already set")
	errInvalidRole    = errors.New("invalid role")
)

type updateProfileRequest struct {
	Role        *string `json:"role,omitempty"`
	Name        *string `json:"name,omitempty"`
	Description *string `json:"description,omitempty"`
	Location    *struct {
		Lat float64 `json:"lat"`
		Lng float64 `json:"lng"`
	} `json:"location,omitempty"`
}

// updateProfile — POST /updateProfile. Owner-only (enforced by authed()
// reading its own uid, never a client-supplied id). role may only be set
// once (from "" to nursery|staff) — this is the one-time sign-up completion
// step; dbsStatus/rating are never accepted from this endpoint at all.
func updateProfile(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	uid := auth.UID(ctx)

	var req updateProfileRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}
	ref := db.Collection("profiles").Doc(uid)

	err = db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		snap, err := tx.Get(ref)
		if err != nil {
			return err
		}
		var existing Profile
		if err := snap.DataTo(&existing); err != nil {
			return err
		}

		var updates []firestore.Update
		if req.Name != nil {
			updates = append(updates, firestore.Update{Path: "name", Value: *req.Name})
		}
		if req.Description != nil {
			updates = append(updates, firestore.Update{Path: "description", Value: *req.Description})
		}
		if req.Location != nil {
			updates = append(updates, firestore.Update{
				Path:  "location",
				Value: &latlng.LatLng{Latitude: req.Location.Lat, Longitude: req.Location.Lng},
			})
		}
		if req.Role != nil {
			if existing.Role != "" {
				return errRoleAlreadySet
			}
			role := Role(*req.Role)
			if role != RoleNursery && role != RoleStaff {
				return errInvalidRole
			}
			updates = append(updates, firestore.Update{Path: "role", Value: role})
		}
		if len(updates) == 0 {
			return nil
		}
		return tx.Update(ref, updates)
	})

	switch {
	case err == nil:
		httpjson.WriteJSON(w, http.StatusOK, map[string]string{"status": "updated"})
	case errors.Is(err, errRoleAlreadySet):
		httpjson.WriteError(w, http.StatusConflict, "ROLE_ALREADY_SET", "Role can only be set once")
	case errors.Is(err, errInvalidRole):
		httpjson.WriteError(w, http.StatusBadRequest, "INVALID_ROLE", "role must be 'nursery' or 'staff'")
	case status.Code(err) == codes.NotFound:
		httpjson.WriteError(w, http.StatusNotFound, "PROFILE_NOT_FOUND", "Profile not found")
	default:
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
	}
}

// getProfile — GET /getProfile. Returns the caller's own private profile.
func getProfile(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	uid := auth.UID(ctx)

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}
	snap, err := db.Collection("profiles").Doc(uid).Get(ctx)
	if status.Code(err) == codes.NotFound {
		httpjson.WriteError(w, http.StatusNotFound, "PROFILE_NOT_FOUND", "Profile not found")
		return
	}
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}
	var p Profile
	if err := snap.DataTo(&p); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}
	httpjson.WriteJSON(w, http.StatusOK, p)
}

// getPublicProfile — GET /getPublicProfile?uid=... Returns any user's public
// profile. Requires auth (any signed-in user may read any public profile,
// per §3) purely to keep this endpoint from being an open scrape target —
// the underlying collection itself has no per-caller restriction.
func getPublicProfile(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	targetUID := r.URL.Query().Get("uid")
	if targetUID == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "uid query parameter is required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}
	snap, err := db.Collection("profilesPublic").Doc(targetUID).Get(ctx)
	if status.Code(err) == codes.NotFound {
		httpjson.WriteError(w, http.StatusNotFound, "PROFILE_NOT_FOUND", "Public profile not found")
		return
	}
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}
	var p ProfilePublic
	if err := snap.DataTo(&p); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}
	httpjson.WriteJSON(w, http.StatusOK, p)
}

func lastPathSegment(name string) (string, error) {
	parts := strings.Split(name, "/")
	if len(parts) == 0 || parts[len(parts)-1] == "" {
		return "", fmt.Errorf("could not extract document id from %q", name)
	}
	return parts[len(parts)-1], nil
}

func fieldString(fields map[string]*firestoredata.Value, key string) string {
	if v, ok := fields[key]; ok {
		return v.GetStringValue()
	}
	return ""
}

func fieldDouble(fields map[string]*firestoredata.Value, key string) float64 {
	if v, ok := fields[key]; ok {
		return v.GetDoubleValue()
	}
	return 0
}

func fieldInt(fields map[string]*firestoredata.Value, key string) int64 {
	if v, ok := fields[key]; ok {
		return v.GetIntegerValue()
	}
	return 0
}

func fieldMap(fields map[string]*firestoredata.Value, key string) map[string]*firestoredata.Value {
	if v, ok := fields[key]; ok && v.GetMapValue() != nil {
		return v.GetMapValue().GetFields()
	}
	return nil
}

func fieldGeo(fields map[string]*firestoredata.Value, key string) (*latlng.LatLng, bool) {
	if v, ok := fields[key]; ok {
		if gp := v.GetGeoPointValue(); gp != nil {
			return gp, true
		}
	}
	return nil, false
}
