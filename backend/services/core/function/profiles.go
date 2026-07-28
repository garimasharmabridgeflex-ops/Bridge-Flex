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
	"google.golang.org/api/iterator"
	"google.golang.org/genproto/googleapis/type/latlng"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/proto"

	"kvision.internal/shared/auth"
	"kvision.internal/shared/httpjson"
)

func init() {
	functions.CloudEvent("InitProfileOnSignUp", initProfileOnSignUp)
	functions.CloudEvent("SyncProfilePublic", syncProfilePublic)
	functions.HTTP("UpdateProfile", authed(updateProfile))
	functions.HTTP("GetProfile", authed(getProfile))
	functions.HTTP("GetPublicProfile", authed(getPublicProfile))
	functions.HTTP("DeleteAccount", authed(deleteAccount))
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
	role := Role(fieldString(fields, "role"))
	pub := ProfilePublic{
		Role:      role,
		Name:      fieldString(fields, "name"),
		DBSBadge:  DBSStatus(fieldString(fields, "dbsStatus")),
		UpdatedAt: time.Now(),
		PhotoURL:  fieldString(fields, "photoUrl"),
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

	// Only mirror each role's own wizard fields — full app spec §1.2/§1.3;
	// there's no reason for a staff member's public doc to carry
	// nursery-only fields or vice versa, even though Profile stores both
	// (whichever the role doesn't use just stays empty).
	switch role {
	case RoleStaff:
		pub.YearsExperience = fieldInt(fields, "yearsExperience")
		pub.QualificationLevel = QualificationLevel(fieldString(fields, "qualificationLevel"))
		pub.Bio = fieldString(fields, "bio")
		pub.PreviousRoles = fieldPreviousRoles(fields, "previousRoles")
		pub.Age = fieldIntPtr(fields, "age")
		pub.City = fieldString(fields, "city")
		pub.TravelDistanceMiles = fieldInt(fields, "travelDistanceMiles")
		pub.Languages = fieldStringArray(fields, "languages")
		pub.ProfessionalSummary = fieldString(fields, "professionalSummary")
		pub.Qualifications = fieldStringArray(fields, "qualifications")
		pub.Skills = fieldStringArray(fields, "skills")
		pub.AvailabilityDays = fieldStringArray(fields, "availabilityDays")
		pub.AvailabilityShifts = fieldStringArray(fields, "availabilityShifts")
		pub.DBSExpiryDate = fieldTimestamp(fields, "dbsExpiryDate")
		pub.Nationality = fieldString(fields, "nationality")
		pub.VisaStatus = fieldString(fields, "visaStatus")
		pub.RightToWorkStatus = fieldString(fields, "rightToWorkStatus")
		pub.RightToWorkVerified = fieldBool(fields, "rightToWorkVerified")
	case RoleNursery:
		pub.Description = fieldString(fields, "description")
		pub.OpeningHours = fieldString(fields, "openingHours")
		pub.OfstedRating = OfstedRating(fieldString(fields, "ofstedRating"))
		pub.Photos = fieldStringArray(fields, "photos")
		pub.LogoURL = fieldString(fields, "logoUrl")
		pub.RegisteredCompanyName = fieldString(fields, "registeredCompanyName")
		pub.OfstedRegNumber = fieldString(fields, "ofstedRegNumber")
		pub.YearEstablished = fieldInt(fields, "yearEstablished")
		pub.NurseryType = NurseryType(fieldString(fields, "nurseryType"))
		pub.Website = fieldString(fields, "website")
		pub.Postcode = fieldString(fields, "postcode")
		pub.Phone = fieldString(fields, "phone")
		pub.Email = fieldString(fields, "email")
		pub.ShortDescription = fieldString(fields, "shortDescription")
		pub.Facilities = fieldStringArray(fields, "facilities")
		pub.IdentityVerified = fieldBool(fields, "identityVerified")
		pub.OfstedVerified = fieldBool(fields, "ofstedVerified")
	}

	db, err := fsDB(ctx)
	if err != nil {
		return err
	}
	_, err = db.Collection("profilesPublic").Doc(uid).Set(ctx, pub)
	return err
}

var (
	errRoleAlreadySet   = errors.New("role already set")
	errInvalidRole      = errors.New("invalid role")
	errInvalidDBSExpiry = errors.New("invalid dbsExpiryDate")
)

type updateProfileRequest struct {
	Role        *string `json:"role,omitempty"`
	Name        *string `json:"name,omitempty"`
	Description *string `json:"description,omitempty"`
	Location    *struct {
		Lat float64 `json:"lat"`
		Lng float64 `json:"lng"`
	} `json:"location,omitempty"`

	Phone    *string `json:"phone,omitempty"`
	PhotoURL *string `json:"photoUrl,omitempty"`

	// Staff-only wizard fields (full app spec §1.2).
	YearsExperience    *int64          `json:"yearsExperience,omitempty"`
	QualificationLevel *string         `json:"qualificationLevel,omitempty"`
	Bio                *string         `json:"bio,omitempty"`
	PreviousRoles      *[]PreviousRole `json:"previousRoles,omitempty"`

	Age                  *int64    `json:"age,omitempty"`
	City                 *string   `json:"city,omitempty"`
	TravelDistanceMiles  *int64    `json:"travelDistanceMiles,omitempty"`
	Languages            *[]string `json:"languages,omitempty"`
	ProfessionalSummary  *string   `json:"professionalSummary,omitempty"`
	Qualifications       *[]string `json:"qualifications,omitempty"`
	Skills               *[]string `json:"skills,omitempty"`
	AvailabilityDays     *[]string `json:"availabilityDays,omitempty"`
	AvailabilityShifts   *[]string `json:"availabilityShifts,omitempty"`
	DBSCertificateNumber *string   `json:"dbsCertificateNumber,omitempty"`
	// DBSExpiryDate is accepted as an RFC3339 string over the wire and
	// parsed below — updateProfileRequest otherwise mirrors Profile's JSON
	// shape directly, but time.Time doesn't round-trip through
	// encoding/json the same way without an explicit parse step.
	DBSExpiryDate     *string `json:"dbsExpiryDate,omitempty"`
	Nationality       *string `json:"nationality,omitempty"`
	VisaStatus        *string `json:"visaStatus,omitempty"`
	RightToWorkStatus *string `json:"rightToWorkStatus,omitempty"`

	// Nursery-only wizard fields (full app spec §1.3).
	Address      *string   `json:"address,omitempty"`
	OpeningHours *string   `json:"openingHours,omitempty"`
	OfstedRating *string   `json:"ofstedRating,omitempty"`
	Photos       *[]string `json:"photos,omitempty"`

	LogoURL               *string   `json:"logoUrl,omitempty"`
	RegisteredCompanyName *string   `json:"registeredCompanyName,omitempty"`
	OfstedRegNumber       *string   `json:"ofstedRegNumber,omitempty"`
	YearEstablished       *int64    `json:"yearEstablished,omitempty"`
	NurseryType           *string   `json:"nurseryType,omitempty"`
	Website               *string   `json:"website,omitempty"`
	Postcode              *string   `json:"postcode,omitempty"`
	Email                 *string   `json:"email,omitempty"`
	ShortDescription      *string   `json:"shortDescription,omitempty"`
	Facilities            *[]string `json:"facilities,omitempty"`
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

	var creating bool
	err = db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		snap, err := tx.Get(ref)
		creating = status.Code(err) == codes.NotFound
		if err != nil && !creating {
			return err
		}
		var existing Profile
		// No profiles/{uid} doc yet. Normally one already exists by the time
		// UpdateProfile is ever called — created either by initProfileOnSignUp
		// (an Eventarc Auth trigger this project's Eventarc setup can't
		// deploy — no firebaseauth.googleapis.com provider registered) or by
		// the client's own best-effort _ensureProfileDocument fallback. Both
		// are outside this function's control, so falling through to a
		// generic 404 here would leave a real signed-up user stuck unable to
		// ever complete onboarding. `existing` just stays the zero Profile{}
		// in that case — role-already-set check below still works correctly
		// against a zero-value "" role.
		if !creating {
			if err := snap.DataTo(&existing); err != nil {
				return err
			}
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
		if req.Phone != nil {
			updates = append(updates, firestore.Update{Path: "phone", Value: *req.Phone})
		}
		if req.PhotoURL != nil {
			updates = append(updates, firestore.Update{Path: "photoUrl", Value: *req.PhotoURL})
		}
		if req.YearsExperience != nil {
			updates = append(updates, firestore.Update{Path: "yearsExperience", Value: *req.YearsExperience})
		}
		if req.QualificationLevel != nil {
			updates = append(updates, firestore.Update{Path: "qualificationLevel", Value: *req.QualificationLevel})
		}
		if req.Bio != nil {
			updates = append(updates, firestore.Update{Path: "bio", Value: *req.Bio})
		}
		if req.PreviousRoles != nil {
			updates = append(updates, firestore.Update{Path: "previousRoles", Value: *req.PreviousRoles})
		}
		if req.Address != nil {
			updates = append(updates, firestore.Update{Path: "address", Value: *req.Address})
		}
		if req.OpeningHours != nil {
			updates = append(updates, firestore.Update{Path: "openingHours", Value: *req.OpeningHours})
		}
		if req.OfstedRating != nil {
			updates = append(updates, firestore.Update{Path: "ofstedRating", Value: *req.OfstedRating})
		}
		if req.Photos != nil {
			updates = append(updates, firestore.Update{Path: "photos", Value: *req.Photos})
		}
		if req.Age != nil {
			updates = append(updates, firestore.Update{Path: "age", Value: *req.Age})
		}
		if req.City != nil {
			updates = append(updates, firestore.Update{Path: "city", Value: *req.City})
		}
		if req.TravelDistanceMiles != nil {
			updates = append(updates, firestore.Update{Path: "travelDistanceMiles", Value: *req.TravelDistanceMiles})
		}
		if req.Languages != nil {
			updates = append(updates, firestore.Update{Path: "languages", Value: *req.Languages})
		}
		if req.ProfessionalSummary != nil {
			updates = append(updates, firestore.Update{Path: "professionalSummary", Value: *req.ProfessionalSummary})
		}
		if req.Qualifications != nil {
			updates = append(updates, firestore.Update{Path: "qualifications", Value: *req.Qualifications})
		}
		if req.Skills != nil {
			updates = append(updates, firestore.Update{Path: "skills", Value: *req.Skills})
		}
		if req.AvailabilityDays != nil {
			updates = append(updates, firestore.Update{Path: "availabilityDays", Value: *req.AvailabilityDays})
		}
		if req.AvailabilityShifts != nil {
			updates = append(updates, firestore.Update{Path: "availabilityShifts", Value: *req.AvailabilityShifts})
		}
		if req.DBSCertificateNumber != nil {
			updates = append(updates, firestore.Update{Path: "dbsCertificateNumber", Value: *req.DBSCertificateNumber})
		}
		if req.DBSExpiryDate != nil {
			t, perr := time.Parse(time.RFC3339, *req.DBSExpiryDate)
			if perr != nil {
				return errInvalidDBSExpiry
			}
			updates = append(updates, firestore.Update{Path: "dbsExpiryDate", Value: t})
		}
		if req.Nationality != nil {
			updates = append(updates, firestore.Update{Path: "nationality", Value: *req.Nationality})
		}
		if req.VisaStatus != nil {
			updates = append(updates, firestore.Update{Path: "visaStatus", Value: *req.VisaStatus})
		}
		if req.RightToWorkStatus != nil {
			updates = append(updates, firestore.Update{Path: "rightToWorkStatus", Value: *req.RightToWorkStatus})
		}
		if req.LogoURL != nil {
			updates = append(updates, firestore.Update{Path: "logoUrl", Value: *req.LogoURL})
		}
		if req.RegisteredCompanyName != nil {
			updates = append(updates, firestore.Update{Path: "registeredCompanyName", Value: *req.RegisteredCompanyName})
		}
		if req.OfstedRegNumber != nil {
			updates = append(updates, firestore.Update{Path: "ofstedRegNumber", Value: *req.OfstedRegNumber})
		}
		if req.YearEstablished != nil {
			updates = append(updates, firestore.Update{Path: "yearEstablished", Value: *req.YearEstablished})
		}
		if req.NurseryType != nil {
			updates = append(updates, firestore.Update{Path: "nurseryType", Value: *req.NurseryType})
		}
		if req.Website != nil {
			updates = append(updates, firestore.Update{Path: "website", Value: *req.Website})
		}
		if req.Postcode != nil {
			updates = append(updates, firestore.Update{Path: "postcode", Value: *req.Postcode})
		}
		if req.Email != nil {
			updates = append(updates, firestore.Update{Path: "email", Value: *req.Email})
		}
		if req.ShortDescription != nil {
			updates = append(updates, firestore.Update{Path: "shortDescription", Value: *req.ShortDescription})
		}
		if req.Facilities != nil {
			updates = append(updates, firestore.Update{Path: "facilities", Value: *req.Facilities})
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
		if !creating && len(updates) == 0 {
			return nil
		}
		if !creating {
			return tx.Update(ref, updates)
		}
		// Same default shape initProfileOnSignUp/_ensureProfileDocument both
		// seed, merged with whatever this call itself is setting.
		fields := map[string]any{
			"dbsStatus": DBSUnverified,
			"rating":    Rating{},
			"createdAt": time.Now(),
		}
		for _, u := range updates {
			fields[u.Path] = u.Value
		}
		return tx.Set(ref, fields, firestore.MergeAll)
	})

	switch {
	case err == nil:
		// Also update profilesPublic synchronously so local reads never lag
		if snap, pErr := ref.Get(ctx); pErr == nil {
			var updatedP Profile
			if snap.DataTo(&updatedP) == nil {
				pub := buildPublicFromProfile(updatedP)
				_, _ = db.Collection("profilesPublic").Doc(uid).Set(ctx, pub)
			}
		}
		httpjson.WriteJSON(w, http.StatusOK, map[string]string{"status": "updated"})
	case errors.Is(err, errRoleAlreadySet):
		httpjson.WriteError(w, http.StatusConflict, "ROLE_ALREADY_SET", "Role can only be set once")
	case errors.Is(err, errInvalidRole):
		httpjson.WriteError(w, http.StatusBadRequest, "INVALID_ROLE", "role must be 'nursery' or 'staff'")
	case errors.Is(err, errInvalidDBSExpiry):
		httpjson.WriteError(w, http.StatusBadRequest, "INVALID_DBS_EXPIRY", "dbsExpiryDate must be RFC3339")
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
	httpjson.WriteJSON(w, http.StatusOK, withComputedFields(ctx, uid, p.Role, p))
}

// deleteAccount — POST /deleteAccount. Self-service account deletion (full
// app spec gap: no client-side path existed to satisfy a UK user's
// right-to-erasure request). Best-effort cleanup of the caller's own
// data — profiles/{uid} (+ its fcmTokens subcollection), profilesPublic/{uid},
// and any documents/{docId} rows keyed by uid — followed by deleting the
// Firebase Auth user itself, which immediately invalidates their session.
//
// Deliberately does NOT chase every reference to this uid across
// shifts/ratings/chat — same "fine at MVP scale, revisit later" tradeoff
// admin.go's setUserSuspended and stats.go already accept; those documents
// are historical records shared with other users (a nursery's shift history,
// a rater's review) and pruning them transactionally is a bigger job than
// this endpoint's job (letting a user erase *their own* profile & documents).
func deleteAccount(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	uid := auth.UID(ctx)

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	// fcmTokens subcollection first (Firestore doesn't cascade-delete).
	tokenIter := db.Collection("profiles").Doc(uid).Collection("fcmTokens").Documents(ctx)
	for {
		snap, err := tokenIter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			break
		}
		_, _ = snap.Ref.Delete(ctx)
	}
	tokenIter.Stop()

	docIter := db.Collection("documents").Where("uid", "==", uid).Documents(ctx)
	for {
		snap, err := docIter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			break
		}
		_, _ = snap.Ref.Delete(ctx)
	}
	docIter.Stop()

	if _, err := db.Collection("profilesPublic").Doc(uid).Delete(ctx); err != nil && status.Code(err) != codes.NotFound {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}
	if _, err := db.Collection("profiles").Doc(uid).Delete(ctx); err != nil && status.Code(err) != codes.NotFound {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	app, err := adminApp(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "auth app init failed")
		return
	}
	authClient, err := app.Auth(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "auth client init failed")
		return
	}
	if err := authClient.DeleteUser(ctx, uid); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"deleted": true})
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
		// Fallback: build from profiles/{targetUID} if public mirror not yet populated
		pSnap, pErr := db.Collection("profiles").Doc(targetUID).Get(ctx)
		if status.Code(pErr) == codes.NotFound {
			httpjson.WriteError(w, http.StatusNotFound, "PROFILE_NOT_FOUND", "Public profile not found")
			return
		}
		if pErr != nil {
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", pErr.Error())
			return
		}
		var p Profile
		if err := pSnap.DataTo(&p); err != nil {
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		pub := buildPublicFromProfile(p)
		_, _ = db.Collection("profilesPublic").Doc(targetUID).Set(ctx, pub)
		httpjson.WriteJSON(w, http.StatusOK, withComputedFields(ctx, targetUID, pub.Role, pub))
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
	httpjson.WriteJSON(w, http.StatusOK, withComputedFields(ctx, targetUID, p.Role, p))
}

func buildPublicFromProfile(p Profile) ProfilePublic {
	pub := ProfilePublic{
		Role:      p.Role,
		Name:      p.Name,
		DBSBadge:  p.DBSStatus,
		Rating:    p.Rating,
		PhotoURL:  p.PhotoURL,
		UpdatedAt: time.Now(),
	}
	if p.Location != nil {
		pub.LocationArea = geohashPrefix(p.Location.GetLatitude(), p.Location.GetLongitude(), geohashPrecision)
	}
	switch p.Role {
	case RoleStaff:
		pub.YearsExperience = p.YearsExperience
		pub.QualificationLevel = p.QualificationLevel
		pub.Bio = p.Bio
		pub.PreviousRoles = p.PreviousRoles
		pub.Age = p.Age
		pub.City = p.City
		pub.TravelDistanceMiles = p.TravelDistanceMiles
		pub.Languages = p.Languages
		pub.ProfessionalSummary = p.ProfessionalSummary
		pub.Qualifications = p.Qualifications
		pub.Skills = p.Skills
		pub.AvailabilityDays = p.AvailabilityDays
		pub.AvailabilityShifts = p.AvailabilityShifts
		pub.DBSExpiryDate = p.DBSExpiryDate
		pub.Nationality = p.Nationality
		pub.VisaStatus = p.VisaStatus
		pub.RightToWorkStatus = p.RightToWorkStatus
		pub.RightToWorkVerified = p.RightToWorkVerified
	case RoleNursery:
		pub.Description = p.Description
		pub.OpeningHours = p.OpeningHours
		pub.OfstedRating = p.OfstedRating
		pub.Photos = p.Photos
		pub.LogoURL = p.LogoURL
		pub.RegisteredCompanyName = p.RegisteredCompanyName
		pub.OfstedRegNumber = p.OfstedRegNumber
		pub.YearEstablished = p.YearEstablished
		pub.NurseryType = p.NurseryType
		pub.Website = p.Website
		pub.Postcode = p.Postcode
		pub.Phone = p.Phone
		pub.Email = p.Email
		pub.ShortDescription = p.ShortDescription
		pub.Facilities = p.Facilities
		pub.IdentityVerified = p.IdentityVerified
		pub.OfstedVerified = p.OfstedVerified
	}
	return pub
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

func fieldIntPtr(fields map[string]*firestoredata.Value, key string) *int64 {
	if v, ok := fields[key]; ok {
		n := v.GetIntegerValue()
		return &n
	}
	return nil
}

func fieldBool(fields map[string]*firestoredata.Value, key string) bool {
	if v, ok := fields[key]; ok {
		return v.GetBooleanValue()
	}
	return false
}

func fieldTimestamp(fields map[string]*firestoredata.Value, key string) *time.Time {
	if v, ok := fields[key]; ok {
		if ts := v.GetTimestampValue(); ts != nil {
			t := ts.AsTime()
			return &t
		}
	}
	return nil
}

func fieldStringArray(fields map[string]*firestoredata.Value, key string) []string {
	v, ok := fields[key]
	if !ok || v.GetArrayValue() == nil {
		return nil
	}
	values := v.GetArrayValue().GetValues()
	out := make([]string, 0, len(values))
	for _, item := range values {
		out = append(out, item.GetStringValue())
	}
	return out
}

// fieldPreviousRoles converts the previousRoles array-of-maps field into
// []PreviousRole for the public mirror — full app spec §1.2 step 2.
func fieldPreviousRoles(fields map[string]*firestoredata.Value, key string) []PreviousRole {
	v, ok := fields[key]
	if !ok || v.GetArrayValue() == nil {
		return nil
	}
	values := v.GetArrayValue().GetValues()
	out := make([]PreviousRole, 0, len(values))
	for _, item := range values {
		m := item.GetMapValue().GetFields()
		if m == nil {
			continue
		}
		out = append(out, PreviousRole{
			SettingName: fieldString(m, "settingName"),
			RoleTitle:   fieldString(m, "roleTitle"),
			Duration:    fieldString(m, "duration"),
		})
	}
	return out
}
