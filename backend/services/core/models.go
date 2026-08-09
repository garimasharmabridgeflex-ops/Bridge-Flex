package function

import (
	"time"

	"google.golang.org/genproto/googleapis/type/latlng"
)

type Role string

const (
	RoleNursery Role = "nursery"
	RoleStaff   Role = "staff"
)

type DBSStatus string

const (
	DBSUnverified DBSStatus = "unverified"
	DBSPending    DBSStatus = "pending"
	DBSVerified   DBSStatus = "verified"
)

// Rating is the aggregate embedded on both profiles.rating (canonical) and
// profilesPublic.rating (mirrored) — ARCHITECTURE.md v2 §2.
type Rating struct {
	Average float64 `firestore:"average" json:"average"`
	Count   int64   `firestore:"count" json:"count"`
}

// QualificationLevel is a fixed set (not free text) so it stays
// filterable/sortable later — full app spec §1.2 step 2.
type QualificationLevel string

const (
	QualNone       QualificationLevel = "none"
	QualLevel2     QualificationLevel = "level_2"
	QualLevel3     QualificationLevel = "level_3"
	QualLevel4Plus QualificationLevel = "level_4_plus"
)

// OfstedRating is informational only — self-reported by the nursery, never
// verified by Bridge Flex (full app spec §1.3 step 2).
type OfstedRating string

const (
	OfstedOutstanding         OfstedRating = "outstanding"
	OfstedGood                OfstedRating = "good"
	OfstedRequiresImprovement OfstedRating = "requires_improvement"
	OfstedInadequate          OfstedRating = "inadequate"
	OfstedNotRated            OfstedRating = "not_rated"
)

// PreviousRole is one entry in a staff member's optional work-history list
// (full app spec §1.2 step 2 — "repeatable Previous roles mini-list").
type PreviousRole struct {
	SettingName string `firestore:"settingName" json:"settingName"`
	RoleTitle   string `firestore:"roleTitle" json:"roleTitle"`
	Duration    string `firestore:"duration" json:"duration"`
}

// NurseryType is a fixed set so it stays filterable, same rationale as
// QualificationLevel/OfstedRating above.
type NurseryType string

const (
	NurseryTypePrivate         NurseryType = "private"
	NurseryTypePreschool       NurseryType = "preschool"
	NurseryTypeDaycare         NurseryType = "daycare"
	NurseryTypeMontessori      NurseryType = "montessori"
	NurseryTypeForestSchool    NurseryType = "forest_school"
	NurseryTypeBeforeAfterClub NurseryType = "before_after_school_club"
	NurseryTypeOther           NurseryType = "other"
)

// Profile is the PRIVATE profiles/{uid} document — owner-read-only, full stop.
// Fields below the CreatedAt line are the full app spec §1.2/§1.3 wizard
// additions; all optional at the storage layer (the wizard enforces which
// are required per role client-side, matching "Basics" being the only hard
// gate — see full app spec §1.4).
type Profile struct {
	Role        Role           `firestore:"role" json:"role"`
	Name        string         `firestore:"name" json:"name"`
	Location    *latlng.LatLng `firestore:"location" json:"location,omitempty"`
	Description string         `firestore:"description" json:"description,omitempty"`
	DBSStatus   DBSStatus      `firestore:"dbsStatus" json:"dbsStatus,omitempty"`
	Rating      Rating         `firestore:"rating" json:"rating"`
	CreatedAt   time.Time      `firestore:"createdAt" json:"createdAt"`

	Phone    string `firestore:"phone,omitempty" json:"phone,omitempty"`
	PhotoURL string `firestore:"photoUrl,omitempty" json:"photoUrl,omitempty"`

	// Staff only (§1.2).
	YearsExperience    int64              `firestore:"yearsExperience,omitempty" json:"yearsExperience,omitempty"`
	QualificationLevel QualificationLevel `firestore:"qualificationLevel,omitempty" json:"qualificationLevel,omitempty"`
	Bio                string             `firestore:"bio,omitempty" json:"bio,omitempty"`
	PreviousRoles      []PreviousRole     `firestore:"previousRoles,omitempty" json:"previousRoles,omitempty"`

	Age                 *int64   `firestore:"age,omitempty" json:"age,omitempty"`
	City                string   `firestore:"city,omitempty" json:"city,omitempty"`
	TravelDistanceMiles int64    `firestore:"travelDistanceMiles,omitempty" json:"travelDistanceMiles,omitempty"`
	Languages           []string `firestore:"languages,omitempty" json:"languages,omitempty"`
	ProfessionalSummary string   `firestore:"professionalSummary,omitempty" json:"professionalSummary,omitempty"`
	Qualifications      []string `firestore:"qualifications,omitempty" json:"qualifications,omitempty"`
	Skills              []string `firestore:"skills,omitempty" json:"skills,omitempty"`
	AvailabilityDays    []string `firestore:"availabilityDays,omitempty" json:"availabilityDays,omitempty"`
	AvailabilityShifts  []string `firestore:"availabilityShifts,omitempty" json:"availabilityShifts,omitempty"`

	DBSCertificateNumber string     `firestore:"dbsCertificateNumber,omitempty" json:"dbsCertificateNumber,omitempty"`
	DBSExpiryDate        *time.Time `firestore:"dbsExpiryDate,omitempty" json:"dbsExpiryDate,omitempty"`

	Nationality         string `firestore:"nationality,omitempty" json:"nationality,omitempty"`
	VisaStatus          string `firestore:"visaStatus,omitempty" json:"visaStatus,omitempty"`
	RightToWorkStatus   string `firestore:"rightToWorkStatus,omitempty" json:"rightToWorkStatus,omitempty"`
	RightToWorkVerified bool   `firestore:"rightToWorkVerified,omitempty" json:"rightToWorkVerified,omitempty"`

	// Nursery only (§1.3).
	Address      string       `firestore:"address,omitempty" json:"address,omitempty"`
	OpeningHours string       `firestore:"openingHours,omitempty" json:"openingHours,omitempty"`
	OfstedRating OfstedRating `firestore:"ofstedRating,omitempty" json:"ofstedRating,omitempty"`
	Photos       []string     `firestore:"photos,omitempty" json:"photos,omitempty"`

	LogoURL               string      `firestore:"logoUrl,omitempty" json:"logoUrl,omitempty"`
	RegisteredCompanyName string      `firestore:"registeredCompanyName,omitempty" json:"registeredCompanyName,omitempty"`
	OfstedRegNumber       string      `firestore:"ofstedRegNumber,omitempty" json:"ofstedRegNumber,omitempty"`
	YearEstablished       int64       `firestore:"yearEstablished,omitempty" json:"yearEstablished,omitempty"`
	NurseryType           NurseryType `firestore:"nurseryType,omitempty" json:"nurseryType,omitempty"`
	Website               string      `firestore:"website,omitempty" json:"website,omitempty"`
	Postcode              string      `firestore:"postcode,omitempty" json:"postcode,omitempty"`
	Email                 string      `firestore:"email,omitempty" json:"email,omitempty"`
	ShortDescription      string      `firestore:"shortDescription,omitempty" json:"shortDescription,omitempty"`
	Facilities            []string    `firestore:"facilities,omitempty" json:"facilities,omitempty"`

	// Verification badges — never client-writable via updateProfile (see
	// profiles.go); flipped only by an admin-gated path, mirroring how
	// dbsStatus is only ever changed by reviewDocument.
	IdentityVerified bool `firestore:"identityVerified,omitempty" json:"identityVerified,omitempty"`
	OfstedVerified   bool `firestore:"ofstedVerified,omitempty" json:"ofstedVerified,omitempty"`

	// Suspended is admin-only (see admin.go setUserSuspended) — mirrors the
	// Firebase Auth account's disabled flag so the admin user-list can show
	// status without a per-row Auth lookup. Never client-writable.
	Suspended bool `firestore:"suspended,omitempty" json:"suspended,omitempty"`

	// Training completion summary (Bridge Flex Training & Onboarding Modules
	// spec). The authoritative per-module record lives in the
	// profiles/{uid}/trainingProgress subcollection; this denormalised list
	// exists so syncProfilePublic can mirror completion into profilesPublic —
	// a subcollection write wouldn't fire that trigger, and a nursery
	// approving an applicant has to be able to see training status without
	// read access to the private profile. Written only by submitTrainingQuiz,
	// never by updateProfile.
	TrainingCompletedModuleIDs []string   `firestore:"trainingCompletedModuleIds,omitempty" json:"trainingCompletedModuleIds,omitempty"`
	TrainingUpdatedAt          *time.Time `firestore:"trainingUpdatedAt,omitempty" json:"trainingUpdatedAt,omitempty"`
}

// TrainingQuestion is one multiple-choice item on a module's knowledge check.
// CorrectIndex is stored here but never serialised to a practitioner — see
// toStaffModule in training.go.
type TrainingQuestion struct {
	ID           string   `firestore:"id" json:"id"`
	Prompt       string   `firestore:"prompt" json:"prompt"`
	Options      []string `firestore:"options" json:"options"`
	CorrectIndex int64    `firestore:"correctIndex" json:"correctIndex"`
	Explanation  string   `firestore:"explanation,omitempty" json:"explanation,omitempty"`
}

// TrainingModule is trainingModules/{moduleId}. Authored by an admin at
// runtime rather than compiled in, because the spec expects question wording
// and timings to change without shipping an app release.
type TrainingModule struct {
	Order          int64    `firestore:"order" json:"order"`
	Title          string   `firestore:"title" json:"title"`
	Purpose        string   `firestore:"purpose,omitempty" json:"purpose,omitempty"`
	ContentOutline []string `firestore:"contentOutline,omitempty" json:"contentOutline,omitempty"`

	// VideoStoragePath is the preferred form: a path inside the Firebase
	// Storage bucket that the app resolves with getDownloadURL(), matching how
	// documents and profile photos already work. It keeps the video behind the
	// signed-in read rule, and re-uploading over the same path swaps the video
	// for every practitioner without touching this document.
	// VideoURL is the escape hatch for content hosted elsewhere; when both are
	// set the storage path wins.
	VideoStoragePath     string `firestore:"videoStoragePath,omitempty" json:"videoStoragePath,omitempty"`
	VideoURL             string `firestore:"videoUrl,omitempty" json:"videoUrl,omitempty"`
	VideoDurationSeconds int64  `firestore:"videoDurationSeconds,omitempty" json:"videoDurationSeconds,omitempty"`

	Questions []TrainingQuestion `firestore:"questions,omitempty" json:"questions,omitempty"`
	// PassMark is a count of correct answers, not a percentage. Zero means
	// "unset" and falls back to 80% rounded up (passMarkFor).
	PassMark int64 `firestore:"passMark,omitempty" json:"passMark,omitempty"`

	Published bool      `firestore:"published" json:"published"`
	CreatedAt time.Time `firestore:"createdAt" json:"createdAt"`
	UpdatedAt time.Time `firestore:"updatedAt" json:"updatedAt"`
}

type TrainingProgressStatus string

const (
	TrainingNotStarted TrainingProgressStatus = "not_started"
	TrainingInProgress TrainingProgressStatus = "in_progress"
	TrainingCompleted  TrainingProgressStatus = "completed"
)

// TrainingProgress is profiles/{uid}/trainingProgress/{moduleId} — one
// practitioner's record against one module.
type TrainingProgress struct {
	ModuleID       string                 `firestore:"moduleId" json:"moduleId"`
	Status         TrainingProgressStatus `firestore:"status" json:"status"`
	VideoWatched   bool                   `firestore:"videoWatched,omitempty" json:"videoWatched,omitempty"`
	Attempts       int64                  `firestore:"attempts,omitempty" json:"attempts,omitempty"`
	LastScore      int64                  `firestore:"lastScore,omitempty" json:"lastScore,omitempty"`
	BestScore      int64                  `firestore:"bestScore,omitempty" json:"bestScore,omitempty"`
	TotalQuestions int64                  `firestore:"totalQuestions,omitempty" json:"totalQuestions,omitempty"`
	LastAttemptAt  *time.Time             `firestore:"lastAttemptAt,omitempty" json:"lastAttemptAt,omitempty"`
	CompletedAt    *time.Time             `firestore:"completedAt,omitempty" json:"completedAt,omitempty"`
	UpdatedAt      *time.Time             `firestore:"updatedAt,omitempty" json:"updatedAt,omitempty"`
}

// ProfilePublic is the PUBLIC profilesPublic/{uid} document, derived from
// Profile by the syncProfilePublic trigger. No field here is ever
// client-writable — see ARCHITECTURE.md v2 §2/§3 (the v2 fix for the v1
// field-exposure bug). Only fields a nursery/staff member should see about
// each other are mirrored here — Phone/Address (exact) stay private.
type ProfilePublic struct {
	Role         Role      `firestore:"role" json:"role"`
	Name         string    `firestore:"name" json:"name"`
	LocationArea string    `firestore:"locationArea" json:"locationArea,omitempty"`
	Rating       Rating    `firestore:"rating" json:"rating"`
	DBSBadge     DBSStatus `firestore:"dbsBadge" json:"dbsBadge,omitempty"`
	UpdatedAt    time.Time `firestore:"updatedAt" json:"updatedAt"`
	PhotoURL     string    `firestore:"photoUrl,omitempty" json:"photoUrl,omitempty"`

	// Staff only — full app spec §2's "a nursery committing coverage to
	// someone deserves to see more than a name."
	YearsExperience    int64              `firestore:"yearsExperience,omitempty" json:"yearsExperience,omitempty"`
	QualificationLevel QualificationLevel `firestore:"qualificationLevel,omitempty" json:"qualificationLevel,omitempty"`
	Bio                string             `firestore:"bio,omitempty" json:"bio,omitempty"`
	PreviousRoles      []PreviousRole     `firestore:"previousRoles,omitempty" json:"previousRoles,omitempty"`

	Age                 *int64   `firestore:"age,omitempty" json:"age,omitempty"`
	City                string   `firestore:"city,omitempty" json:"city,omitempty"`
	TravelDistanceMiles int64    `firestore:"travelDistanceMiles,omitempty" json:"travelDistanceMiles,omitempty"`
	Languages           []string `firestore:"languages,omitempty" json:"languages,omitempty"`
	ProfessionalSummary string   `firestore:"professionalSummary,omitempty" json:"professionalSummary,omitempty"`
	Qualifications      []string `firestore:"qualifications,omitempty" json:"qualifications,omitempty"`
	Skills              []string `firestore:"skills,omitempty" json:"skills,omitempty"`
	AvailabilityDays    []string `firestore:"availabilityDays,omitempty" json:"availabilityDays,omitempty"`
	AvailabilityShifts  []string `firestore:"availabilityShifts,omitempty" json:"availabilityShifts,omitempty"`

	// DBS certificate NUMBER stays private-only (documents.go/profiles.go) —
	// the expiry date plus the existing dbsBadge is enough of a public trust
	// signal without exposing a document reference number to other users.
	DBSExpiryDate *time.Time `firestore:"dbsExpiryDate,omitempty" json:"dbsExpiryDate,omitempty"`

	Nationality         string `firestore:"nationality,omitempty" json:"nationality,omitempty"`
	VisaStatus          string `firestore:"visaStatus,omitempty" json:"visaStatus,omitempty"`
	RightToWorkStatus   string `firestore:"rightToWorkStatus,omitempty" json:"rightToWorkStatus,omitempty"`
	RightToWorkVerified bool   `firestore:"rightToWorkVerified,omitempty" json:"rightToWorkVerified,omitempty"`

	// Mirrored from Profile by syncProfilePublic so a nursery can see which
	// training a shift applicant has completed before approving them. Only
	// the module ids are exposed — scores and attempt counts stay private.
	TrainingCompletedModuleIDs []string `firestore:"trainingCompletedModuleIds,omitempty" json:"trainingCompletedModuleIds,omitempty"`

	// Nursery only.
	Description  string       `firestore:"description,omitempty" json:"description,omitempty"`
	OpeningHours string       `firestore:"openingHours,omitempty" json:"openingHours,omitempty"`
	OfstedRating OfstedRating `firestore:"ofstedRating,omitempty" json:"ofstedRating,omitempty"`
	Photos       []string     `firestore:"photos,omitempty" json:"photos,omitempty"`

	LogoURL               string      `firestore:"logoUrl,omitempty" json:"logoUrl,omitempty"`
	RegisteredCompanyName string      `firestore:"registeredCompanyName,omitempty" json:"registeredCompanyName,omitempty"`
	OfstedRegNumber       string      `firestore:"ofstedRegNumber,omitempty" json:"ofstedRegNumber,omitempty"`
	YearEstablished       int64       `firestore:"yearEstablished,omitempty" json:"yearEstablished,omitempty"`
	NurseryType           NurseryType `firestore:"nurseryType,omitempty" json:"nurseryType,omitempty"`
	Website               string      `firestore:"website,omitempty" json:"website,omitempty"`
	Postcode              string      `firestore:"postcode,omitempty" json:"postcode,omitempty"`
	Phone                 string      `firestore:"phone,omitempty" json:"phone,omitempty"`
	Email                 string      `firestore:"email,omitempty" json:"email,omitempty"`
	ShortDescription      string      `firestore:"shortDescription,omitempty" json:"shortDescription,omitempty"`
	Facilities            []string    `firestore:"facilities,omitempty" json:"facilities,omitempty"`

	IdentityVerified bool `firestore:"identityVerified,omitempty" json:"identityVerified,omitempty"`
	OfstedVerified   bool `firestore:"ofstedVerified,omitempty" json:"ofstedVerified,omitempty"`
}

type ShiftStatus string

const (
	ShiftOpen      ShiftStatus = "open"
	ShiftBooked    ShiftStatus = "booked"
	ShiftCancelled ShiftStatus = "cancelled"
)

type PaymentStatus string

const (
	PaymentNotRequired PaymentStatus = "not_required"
	PaymentPending     PaymentStatus = "pending"
	PaymentPaid        PaymentStatus = "paid"
)

// Shift is shifts/{shiftId}. No separate bookings collection — see
// ARCHITECTURE.md v2 §2 for why booking is fields on this doc.
type Shift struct {
	NurseryID string `firestore:"nurseryId" json:"nurseryId"`
	Title     string `firestore:"title" json:"title"`
	// Description is a short free-text field (kept for backward
	// compatibility with existing shifts); ExpectedDuties is the
	// structured, repeatable version requested for the shift-detail screen.
	Description   string        `firestore:"description,omitempty" json:"description,omitempty"`
	Capacity      int64         `firestore:"capacity,omitempty" json:"capacity,omitempty"`
	Date          string        `firestore:"date" json:"date"`
	StartTime     time.Time     `firestore:"startTime" json:"startTime"`
	EndTime       time.Time     `firestore:"endTime" json:"endTime"`
	PayRate       float64       `firestore:"payRate" json:"payRate"`
	Status        ShiftStatus   `firestore:"status" json:"status"`
	BookedStaffID *string       `firestore:"bookedStaffId" json:"bookedStaffId"`
	PaymentStatus PaymentStatus `firestore:"paymentStatus" json:"paymentStatus"`
	CreatedAt     time.Time     `firestore:"createdAt" json:"createdAt"`

	// BookedStaffIDs is the authoritative multi-capacity booking list —
	// BookedStaffID above is kept in sync as "most recent acceptor" only
	// for backward compatibility with any code still reading the singular
	// field; membership/cancellation logic must use this array.
	BookedStaffIDs []string `firestore:"bookedStaffIds,omitempty" json:"bookedStaffIds,omitempty"`

	// Shift-detail fields.
	AgeGroup         string   `firestore:"ageGroup,omitempty" json:"ageGroup,omitempty"`
	Room             string   `firestore:"room,omitempty" json:"room,omitempty"`
	NumberOfChildren int64    `firestore:"numberOfChildren,omitempty" json:"numberOfChildren,omitempty"`
	ExpectedDuties   []string `firestore:"expectedDuties,omitempty" json:"expectedDuties,omitempty"`
	Requirements     []string `firestore:"requirements,omitempty" json:"requirements,omitempty"`

	// FirstAcceptedAt is set once, on the first-ever acceptShift call for
	// this shift — feeds the nursery "average response time" statistic
	// (stats.go). Never updated again after that first accept, even if the
	// shift is later re-opened by a staff cancellation and re-accepted.
	FirstAcceptedAt *time.Time `firestore:"firstAcceptedAt,omitempty" json:"firstAcceptedAt,omitempty"`

	// NoShowStaffIDs holds staff marked as not having shown up, via
	// markNoShow (booking.go) — feeds the nursery "no-show rate" statistic.
	NoShowStaffIDs []string `firestore:"noShowStaffIds,omitempty" json:"noShowStaffIds,omitempty"`
}

// RatingDoc is ratings/{ratingId}. Immutable once created (§3).
type RatingDoc struct {
	ShiftID   string    `firestore:"shiftId" json:"shiftId"`
	RaterID   string    `firestore:"raterId" json:"raterId"`
	RateeID   string    `firestore:"rateeId" json:"rateeId"`
	Score     int64     `firestore:"score" json:"score"`
	Comment   string    `firestore:"comment" json:"comment,omitempty"`
	CreatedAt time.Time `firestore:"createdAt" json:"createdAt"`

	// CategoryScores is an optional per-category breakdown (1-5 each),
	// keyed by "communication" | "punctuality" | "professionalism" |
	// "reliability" | "childEngagement". Not present on older ratings.
	CategoryScores map[string]int64 `firestore:"categoryScores,omitempty" json:"categoryScores,omitempty"`
}

type DocumentStatus string

const (
	DocPendingReview DocumentStatus = "pending_review"
	DocVerified      DocumentStatus = "verified"
	DocRejected      DocumentStatus = "rejected"
)

// DocumentMeta is documents/{docId} — Cloud Storage upload metadata (§2).
type DocumentMeta struct {
	UID         string         `firestore:"uid" json:"uid"`
	Type        string         `firestore:"type" json:"type"`
	StoragePath string         `firestore:"storagePath" json:"storagePath"`
	Status      DocumentStatus `firestore:"status" json:"status"`
	UploadedAt  time.Time      `firestore:"uploadedAt" json:"uploadedAt"`
	ReviewedAt  *time.Time     `firestore:"reviewedAt" json:"reviewedAt"`
	// ReviewNote is set by reviewDocument on rejection — shown to the owner
	// so a rejected upload isn't a dead end (full app spec §4.1). Never set
	// on approval; empty string means "no note".
	ReviewNote string `firestore:"reviewNote,omitempty" json:"reviewNote,omitempty"`
}
