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

// NurseryApprovalStatus tracks admin approval for nurseries (Phase 5).
type NurseryApprovalStatus string

const (
	NurseryPendingApproval NurseryApprovalStatus = "pending_approval"
	NurseryApproved        NurseryApprovalStatus = "approved"
	NurseryRejected        NurseryApprovalStatus = "rejected"
)

// Branch represents a physical nursery location under a parent nursery account (Phase 5).
type Branch struct {
	ID              string    `firestore:"-" json:"id,omitempty"`
	NurseryID       string    `firestore:"nurseryId" json:"nurseryId"`
	Name            string    `firestore:"name" json:"name"`
	Address         string    `firestore:"address" json:"address"`
	Postcode        string    `firestore:"postcode" json:"postcode"`
	City            string    `firestore:"city" json:"city"`
	Phone           string    `firestore:"phone,omitempty" json:"phone,omitempty"`
	ContactPerson   string    `firestore:"contactPerson,omitempty" json:"contactPerson,omitempty"`
	OfstedRegNumber string    `firestore:"ofstedRegNumber,omitempty" json:"ofstedRegNumber,omitempty"`
	IsPrimary       bool      `firestore:"isPrimary" json:"isPrimary"`
	CreatedAt       time.Time `firestore:"createdAt" json:"createdAt"`
	UpdatedAt       time.Time `firestore:"updatedAt" json:"updatedAt"`
}

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

	// Nursery registration additions (Phase 5).
	CompanyNumber          string                `firestore:"companyNumber,omitempty" json:"companyNumber,omitempty"`
	BillingAddress         string                `firestore:"billingAddress,omitempty" json:"billingAddress,omitempty"`
	BillingEmail           string                `firestore:"billingEmail,omitempty" json:"billingEmail,omitempty"`
	BillingContactPerson   string                `firestore:"billingContactPerson,omitempty" json:"billingContactPerson,omitempty"`
	PreferredPaymentMethod string                `firestore:"preferredPaymentMethod,omitempty" json:"preferredPaymentMethod,omitempty"`
	LocationCount          int64                 `firestore:"locationCount,omitempty" json:"locationCount,omitempty"`
	StaffingRequirements  string                `firestore:"staffingRequirements,omitempty" json:"staffingRequirements,omitempty"`
	NurseryApprovalStatus  NurseryApprovalStatus `firestore:"nurseryApprovalStatus,omitempty" json:"nurseryApprovalStatus,omitempty"`
	ActivationDate         *time.Time            `firestore:"activationDate,omitempty" json:"activationDate,omitempty"`
	NurseryRejectionReason string                `firestore:"nurseryRejectionReason,omitempty" json:"nurseryRejectionReason,omitempty"`

	// Vetting status and DBS verification fields (Phase 4).
	VettingStatus          VettingStatus `firestore:"vettingStatus,omitempty" json:"vettingStatus,omitempty"`
	DBSCheckedByKFlex      bool          `firestore:"dbsCheckedByKFlex,omitempty" json:"dbsCheckedByKFlex,omitempty"`
	DBSVerifiedAt          *time.Time    `firestore:"dbsVerifiedAt,omitempty" json:"dbsVerifiedAt,omitempty"`
	DBSRecheckDue          *time.Time    `firestore:"dbsRecheckDue,omitempty" json:"dbsRecheckDue,omitempty"`
	DBSWorkforce           string        `firestore:"dbsWorkforce,omitempty" json:"dbsWorkforce,omitempty"`
	DBSUpdateServiceStatus string        `firestore:"dbsUpdateServiceStatus,omitempty" json:"dbsUpdateServiceStatus,omitempty"`
	DBSConsentGiven        bool          `firestore:"dbsConsentGiven,omitempty" json:"dbsConsentGiven,omitempty"`
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

// TrainingSection is one teachable chunk of a module: a heading and the
// paragraphs under it. Modules originally carried only a flat bullet list,
// which was the spec's outline FOR THE VIDEO PRODUCER — useful as a summary,
// but not something a practitioner can learn from. Sections hold the actual
// teaching; ContentOutline stays as the at-a-glance summary.
type TrainingSection struct {
	Heading string   `firestore:"heading" json:"heading"`
	Body    []string `firestore:"body" json:"body"`
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

	// Sections carry the lesson itself. Optional so a module can exist as
	// video + outline before its written content is authored.
	Sections []TrainingSection `firestore:"sections,omitempty" json:"sections,omitempty"`

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
	VettingStatus              VettingStatus `firestore:"vettingStatus,omitempty" json:"vettingStatus,omitempty"`
	DBSCheckedByKFlex          bool          `firestore:"dbsCheckedByKFlex,omitempty" json:"dbsCheckedByKFlex,omitempty"`
	DBSRecheckDue              *time.Time    `firestore:"dbsRecheckDue,omitempty" json:"dbsRecheckDue,omitempty"`

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

	// Nursery approval status (Phase 5).
	NurseryApprovalStatus NurseryApprovalStatus `firestore:"nurseryApprovalStatus,omitempty" json:"nurseryApprovalStatus,omitempty"`
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
	NurseryID   string `firestore:"nurseryId" json:"nurseryId"`
	NurseryArea string `firestore:"nurseryArea,omitempty" json:"nurseryArea,omitempty"`
	Title       string `firestore:"title" json:"title"`
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
	//
	// Since the nursery-approval flow, this means APPROVED staff only.
	// Anything already in here before that change was a confirmed booking, so
	// existing shifts carry over as approved with no migration.
	BookedStaffIDs []string `firestore:"bookedStaffIds,omitempty" json:"bookedStaffIds,omitempty"`

	// PendingStaffIDs are applicants awaiting the nursery's decision. They do
	// not count toward capacity: the shift stays open and visible to other
	// staff until enough applicants have been APPROVED, so a single applicant
	// can't take a shift off the market while the nursery deliberates — and
	// more people may apply than there are places, which is what gives the
	// nursery someone to choose between.
	PendingStaffIDs []string `firestore:"pendingStaffIds,omitempty" json:"pendingStaffIds,omitempty"`

	// RejectedStaffIDs records who was turned down, so the app can show a
	// decided outcome rather than silently dropping someone back to "not
	// applied", and so a rejected applicant can't immediately re-apply to the
	// same shift.
	RejectedStaffIDs []string `firestore:"rejectedStaffIds,omitempty" json:"rejectedStaffIds,omitempty"`

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

	// Branch fields (Phase 5).
	BranchID       string `firestore:"branchId,omitempty" json:"branchId,omitempty"`
	BranchName     string `firestore:"branchName,omitempty" json:"branchName,omitempty"`
	BranchAddress  string `firestore:"branchAddress,omitempty" json:"branchAddress,omitempty"`
	BranchPostcode string `firestore:"branchPostcode,omitempty" json:"branchPostcode,omitempty"`

	// Extended shift fields & financials (Phase 6).
	Financials            *ShiftFinancials   `firestore:"financials,omitempty" json:"financials,omitempty"`
	RequiredQualification QualificationLevel `firestore:"requiredQualification,omitempty" json:"requiredQualification,omitempty"`
	UnpaidBreakMinutes    int64              `firestore:"unpaidBreakMinutes,omitempty" json:"unpaidBreakMinutes,omitempty"`
	SafeguardingNotes     string             `firestore:"safeguardingNotes,omitempty" json:"safeguardingNotes,omitempty"`
	HealthAndSafetyNotes  string             `firestore:"healthAndSafetyNotes,omitempty" json:"healthAndSafetyNotes,omitempty"`
}

// RateCard represents the platform pricing card (Phase 6).
type RateCard struct {
	ID        string                        `firestore:"-" json:"id,omitempty"`
	Version   int                           `firestore:"version" json:"version"`
	Active    bool                          `firestore:"active" json:"active"`
	CreatedAt time.Time                     `firestore:"createdAt" json:"createdAt"`
	CreatedBy string                        `firestore:"createdBy" json:"createdBy"`
	Rates     map[string]QualificationRates `firestore:"rates" json:"rates"`
}

type QualificationRates struct {
	PractitionerPayPencePerHour int64 `firestore:"practitionerPayPencePerHour" json:"practitionerPayPencePerHour"`
	NurseryChargePencePerHour   int64 `firestore:"nurseryChargePencePerHour" json:"nurseryChargePencePerHour"`
}

// ShiftFinancials snapshots rates and gross pay calculations in pence (Phase 6).
type ShiftFinancials struct {
	RateCardID                  string `firestore:"rateCardId,omitempty" json:"rateCardId,omitempty"`
	RateCardVersion             int    `firestore:"rateCardVersion,omitempty" json:"rateCardVersion,omitempty"`
	PractitionerPayPencePerHour int64  `firestore:"practitionerPayPencePerHour" json:"practitionerPayPencePerHour"`
	NurseryChargePencePerHour   int64  `firestore:"nurseryChargePencePerHour" json:"nurseryChargePencePerHour"`
	DurationMinutes             int64  `firestore:"durationMinutes" json:"durationMinutes"`
	UnpaidBreakMinutes          int64  `firestore:"unpaidBreakMinutes" json:"unpaidBreakMinutes"`
	BillableMinutes             int64  `firestore:"billableMinutes" json:"billableMinutes"`
	EstimatedGrossPayPence      int64  `firestore:"estimatedGrossPayPence" json:"estimatedGrossPayPence"`
	EstimatedNurseryChargePence int64  `firestore:"estimatedNurseryChargePence" json:"estimatedNurseryChargePence"`
	PlatformFeePence            int64  `firestore:"platformFeePence" json:"platformFeePence"`
}

// CancellationDoc is recorded under cancellations/{id} (Phase 6).
type CancellationDoc struct {
	ID                string    `firestore:"-" json:"id,omitempty"`
	ShiftID           string    `firestore:"shiftId" json:"shiftId"`
	ActorID           string    `firestore:"actorId" json:"actorId"`
	ActorRole         Role      `firestore:"actorRole" json:"actorRole"`
	Reason            string    `firestore:"reason" json:"reason"`
	Category          string    `firestore:"category" json:"category"`
	Timestamp         time.Time `firestore:"timestamp" json:"timestamp"`
	ChargePence       int64     `firestore:"chargePence" json:"chargePence"`
	CompensationPence int64     `firestore:"compensationPence" json:"compensationPence"`
	PolicyVersion     int       `firestore:"policyVersion" json:"policyVersion"`
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

type VettingStatus string

const (
	VettingUnverified          VettingStatus = "unverified"
	VettingPendingVerification VettingStatus = "pending_verification"
	VettingApproved            VettingStatus = "approved"
	VettingRejectedFurtherInfo VettingStatus = "rejected_further_info"
)

type CheckResult string

const (
	CheckPending CheckResult = "pending"
	CheckPassed  CheckResult = "passed"
	CheckFailed  CheckResult = "failed"
)

type VettingCheckItem struct {
	Result     CheckResult `firestore:"result" json:"result"`
	CheckerUID string      `firestore:"checkerUid,omitempty" json:"checkerUid,omitempty"`
	CheckedAt  *time.Time  `firestore:"checkedAt,omitempty" json:"checkedAt,omitempty"`
	Note       string      `firestore:"note,omitempty" json:"note,omitempty"`
}

type VettingChecklist struct {
	UID                 string           `firestore:"uid" json:"uid"`
	Identity            VettingCheckItem `firestore:"identity" json:"identity"`
	OriginalCertificate VettingCheckItem `firestore:"originalCertificate" json:"originalCertificate"`
	Suitability         VettingCheckItem `firestore:"suitability" json:"suitability"`
	Workforce           VettingCheckItem `firestore:"workforce" json:"workforce"`
	BarredList          VettingCheckItem `firestore:"barredList" json:"barredList"`
	UpdateService       VettingCheckItem `firestore:"updateService" json:"updateService"`
	RightToWork         VettingCheckItem `firestore:"rightToWork" json:"rightToWork"`
	Qualification       VettingCheckItem `firestore:"qualification" json:"qualification"`
	References          VettingCheckItem `firestore:"references" json:"references"`
	Safeguarding        VettingCheckItem `firestore:"safeguarding" json:"safeguarding"`
	FirstAid            VettingCheckItem `firestore:"firstAid" json:"firstAid"`
	UpdatedAt           time.Time        `firestore:"updatedAt" json:"updatedAt"`
}

type DocumentRequest struct {
	ID          string    `firestore:"id" json:"id"`
	UID         string    `firestore:"uid" json:"uid"`
	RequestedBy string    `firestore:"requestedBy" json:"requestedBy"`
	Message     string    `firestore:"message" json:"message"`
	DocTypes    []string  `firestore:"docTypes" json:"docTypes"`
	CreatedAt   time.Time `firestore:"createdAt" json:"createdAt"`
	Resolved    bool      `firestore:"resolved" json:"resolved"`
}

type SensitiveProfile struct {
	UID                  string    `firestore:"uid" json:"uid"`
	DateOfBirthEnc       string    `firestore:"dateOfBirthEnc,omitempty" json:"dateOfBirthEnc,omitempty"`
	NationalInsuranceEnc string    `firestore:"nationalInsuranceEnc,omitempty" json:"nationalInsuranceEnc,omitempty"`
	BankAccountEnc       string    `firestore:"bankAccountEnc,omitempty" json:"bankAccountEnc,omitempty"`
	SortCodeEnc          string    `firestore:"sortCodeEnc,omitempty" json:"sortCodeEnc,omitempty"`
	FullAddressEnc       string    `firestore:"fullAddressEnc,omitempty" json:"fullAddressEnc,omitempty"`
	DBSCertificateEnc    string    `firestore:"dbsCertificateEnc,omitempty" json:"dbsCertificateEnc,omitempty"`
	UpdatedAt            time.Time `firestore:"updatedAt" json:"updatedAt"`
}

// TimesheetStatus represents the lifecycle of a timesheet (Phase 7).
type TimesheetStatus string

const (
	TimesheetSubmitted           TimesheetStatus = "submitted"
	TimesheetApproved            TimesheetStatus = "approved"
	TimesheetCorrectionRequested TimesheetStatus = "correction_requested"
	TimesheetDisputed            TimesheetStatus = "disputed"
	TimesheetAdminApproved       TimesheetStatus = "admin_approved"
)

// Timesheet records hours and pay approval for a completed shift (Phase 7).
type Timesheet struct {
	ID                      string          `firestore:"-" json:"id,omitempty"`
	ShiftID                 string          `firestore:"shiftId" json:"shiftId"`
	NurseryID               string          `firestore:"nurseryId" json:"nurseryId"`
	StaffID                 string          `firestore:"staffId" json:"staffId"`
	ScheduledStartTime      time.Time       `firestore:"scheduledStartTime" json:"scheduledStartTime"`
	ScheduledEndTime        time.Time       `firestore:"scheduledEndTime" json:"scheduledEndTime"`
	ActualStartTime         time.Time       `firestore:"actualStartTime" json:"actualStartTime"`
	ActualEndTime           time.Time       `firestore:"actualEndTime" json:"actualEndTime"`
	UnpaidBreakMinutes      int64           `firestore:"unpaidBreakMinutes" json:"unpaidBreakMinutes"`
	BillableMinutes         int64           `firestore:"billableMinutes" json:"billableMinutes"`
	HourlyRatePence         int64           `firestore:"hourlyRatePence" json:"hourlyRatePence"`
	NurseryHourlyRatePence  int64           `firestore:"nurseryHourlyRatePence" json:"nurseryHourlyRatePence"`
	TotalGrossPayPence      int64           `firestore:"totalGrossPayPence" json:"totalGrossPayPence"`
	TotalNurseryChargePence int64           `firestore:"totalNurseryChargePence" json:"totalNurseryChargePence"`
	Status                  TimesheetStatus `firestore:"status" json:"status"`
	NurseryFeedback         string          `firestore:"nurseryFeedback,omitempty" json:"nurseryFeedback,omitempty"`
	DisputeReason           string          `firestore:"disputeReason,omitempty" json:"disputeReason,omitempty"`
	AdminNotes              string          `firestore:"adminNotes,omitempty" json:"adminNotes,omitempty"`
	SubmittedAt             time.Time       `firestore:"submittedAt" json:"submittedAt"`
	DecidedAt               *time.Time      `firestore:"decidedAt,omitempty" json:"decidedAt,omitempty"`
	EscalatedAt             *time.Time      `firestore:"escalatedAt,omitempty" json:"escalatedAt,omitempty"`
	CreatedAt               time.Time       `firestore:"createdAt" json:"createdAt"`
	UpdatedAt               time.Time       `firestore:"updatedAt" json:"updatedAt"`
}

// PayrollProfile stores bank, NI and holiday pay eligibility for a practitioner (Phase 8).
type PayrollProfile struct {
	UID                           string    `firestore:"uid" json:"uid"`
	BankAccountName               string    `firestore:"bankAccountName,omitempty" json:"bankAccountName,omitempty"`
	BankAccountNumberMasked       string    `firestore:"bankAccountNumberMasked,omitempty" json:"bankAccountNumberMasked,omitempty"`
	BankAccountNumberEnc          string    `firestore:"bankAccountNumberEnc,omitempty" json:"bankAccountNumberEnc,omitempty"`
	BankSortCode                  string    `firestore:"bankSortCode,omitempty" json:"bankSortCode,omitempty"`
	NationalInsuranceNumberEnc    string    `firestore:"nationalInsuranceNumberEnc,omitempty" json:"nationalInsuranceNumberEnc,omitempty"`
	NationalInsuranceNumberMasked string    `firestore:"nationalInsuranceNumberMasked,omitempty" json:"nationalInsuranceNumberMasked,omitempty"`
	EligibleForRolledUpHolidayPay bool      `firestore:"eligibleForRolledUpHolidayPay" json:"eligibleForRolledUpHolidayPay"`
	UpdatedAt                     time.Time `firestore:"updatedAt" json:"updatedAt"`
	UpdatedBy                     string    `firestore:"updatedBy" json:"updatedBy"`
}

// PayrollPeriodStatus represents the lifecycle of a payroll run (Phase 8).
type PayrollPeriodStatus string

const (
	PayrollPeriodDraft     PayrollPeriodStatus = "draft"
	PayrollPeriodApproved  PayrollPeriodStatus = "approved"
	PayrollPeriodProcessed PayrollPeriodStatus = "processed"
	PayrollPeriodPaid      PayrollPeriodStatus = "paid"
)

// PayrollPeriod records an aggregated pay period (e.g. weekly or monthly) (Phase 8).
type PayrollPeriod struct {
	ID                   string              `firestore:"-" json:"id"`
	PeriodName           string              `firestore:"periodName" json:"periodName"`
	StartDate            time.Time           `firestore:"startDate" json:"startDate"`
	EndDate              time.Time           `firestore:"endDate" json:"endDate"`
	Status               PayrollPeriodStatus `firestore:"status" json:"status"`
	TotalPractitioners   int                 `firestore:"totalPractitioners" json:"totalPractitioners"`
	TotalBillableMinutes int64               `firestore:"totalBillableMinutes" json:"totalBillableMinutes"`
	TotalBasicPayPence   int64               `firestore:"totalBasicPayPence" json:"totalBasicPayPence"`
	TotalHolidayPayPence int64               `firestore:"totalHolidayPayPence" json:"totalHolidayPayPence"`
	TotalGrossPayPence   int64               `firestore:"totalGrossPayPence" json:"totalGrossPayPence"`
	ProcessedAt          *time.Time          `firestore:"processedAt,omitempty" json:"processedAt,omitempty"`
	PaidAt               *time.Time          `firestore:"paidAt,omitempty" json:"paidAt,omitempty"`
	CreatedBy            string              `firestore:"createdBy" json:"createdBy"`
	CreatedAt            time.Time           `firestore:"createdAt" json:"createdAt"`
	UpdatedAt            time.Time           `firestore:"updatedAt" json:"updatedAt"`
}

// PayrollLine records one practitioner's aggregate earnings in a payroll period (Phase 8).
type PayrollLine struct {
	ID                            string     `firestore:"-" json:"id"`
	PeriodID                      string     `firestore:"periodId" json:"periodId"`
	PractitionerID                string     `firestore:"practitionerId" json:"practitionerId"`
	PractitionerName              string     `firestore:"practitionerName" json:"practitionerName"`
	NationalInsuranceNumberMasked string     `firestore:"nationalInsuranceNumberMasked,omitempty" json:"nationalInsuranceNumberMasked,omitempty"`
	BankAccountName               string     `firestore:"bankAccountName,omitempty" json:"bankAccountName,omitempty"`
	BankAccountNumberMasked       string     `firestore:"bankAccountNumberMasked,omitempty" json:"bankAccountNumberMasked,omitempty"`
	BankSortCode                  string     `firestore:"bankSortCode,omitempty" json:"bankSortCode,omitempty"`
	CompletedShiftCount           int        `firestore:"completedShiftCount" json:"completedShiftCount"`
	TotalBillableMinutes          int64      `firestore:"totalBillableMinutes" json:"totalBillableMinutes"`
	BasicPayPence                 int64      `firestore:"basicPayPence" json:"basicPayPence"`
	HolidayPayPence               int64      `firestore:"holidayPayPence" json:"holidayPayPence"`
	GrossPayPence                 int64      `firestore:"grossPayPence" json:"grossPayPence"`
	EligibleForRolledUpHolidayPay bool       `firestore:"eligibleForRolledUpHolidayPay" json:"eligibleForRolledUpHolidayPay"`
	TimesheetIDs                  []string   `firestore:"timesheetIds" json:"timesheetIds"`
	Status                        string     `firestore:"status" json:"status"`
	PayrollReference              string     `firestore:"payrollReference" json:"payrollReference"`
	PaidAt                        *time.Time `firestore:"paidAt,omitempty" json:"paidAt,omitempty"`
	CreatedAt                     time.Time  `firestore:"createdAt" json:"createdAt"`
	UpdatedAt                     time.Time  `firestore:"updatedAt" json:"updatedAt"`
}

// Payslip links an admin-uploaded payslip PDF to a practitioner (Phase 8).
type Payslip struct {
	ID             string    `firestore:"-" json:"id"`
	PractitionerID string    `firestore:"practitionerId" json:"practitionerId"`
	PeriodID       string    `firestore:"periodId" json:"periodId"`
	PeriodName     string    `firestore:"periodName" json:"periodName"`
	StoragePath    string    `firestore:"storagePath" json:"storagePath"`
	FileName       string    `firestore:"fileName" json:"fileName"`
	UploadedBy     string    `firestore:"uploadedBy" json:"uploadedBy"`
	UploadedAt     time.Time `firestore:"uploadedAt" json:"uploadedAt"`
}

// Plan defines a membership tier (Phase 9).
type Plan struct {
	ID               string    `firestore:"-" json:"id"`
	Name             string    `firestore:"name" json:"name"`
	Description      string    `firestore:"description" json:"description"`
	PricePence       int64     `firestore:"pricePence" json:"pricePence"` // ex-VAT
	BillingInterval  string    `firestore:"billingInterval" json:"billingInterval"` // "month", "per_booking", "none"
	BookingAllowance int       `firestore:"bookingAllowance" json:"bookingAllowance"` // 0 = unlimited
	TrialDays        int       `firestore:"trialDays" json:"trialDays"`
	Active           bool      `firestore:"active" json:"active"`
	Benefits         []string  `firestore:"benefits" json:"benefits"`
	CreatedAt        time.Time `firestore:"createdAt" json:"createdAt"`
	UpdatedAt        time.Time `firestore:"updatedAt" json:"updatedAt"`
}

// SubscriptionStatus tracks the lifecycle of a nursery membership (Phase 9).
type SubscriptionStatus string

const (
	SubTrialing  SubscriptionStatus = "trialing"
	SubActive    SubscriptionStatus = "active"
	SubPastDue   SubscriptionStatus = "past_due"
	SubCancelled SubscriptionStatus = "cancelled"
	SubExpired   SubscriptionStatus = "expired"
)

// NurserySubscription records a nursery's membership plan and trial countdown (Phase 9).
type NurserySubscription struct {
	NurseryID          string             `firestore:"nurseryId" json:"nurseryId"`
	PlanID             string             `firestore:"planId" json:"planId"`
	PlanName           string             `firestore:"planName" json:"planName"`
	Status             SubscriptionStatus `firestore:"status" json:"status"`
	TrialStartDate     *time.Time         `firestore:"trialStartDate,omitempty" json:"trialStartDate,omitempty"`
	TrialEndDate       *time.Time         `firestore:"trialEndDate,omitempty" json:"trialEndDate,omitempty"`
	CurrentPeriodStart time.Time          `firestore:"currentPeriodStart" json:"currentPeriodStart"`
	CurrentPeriodEnd   time.Time          `firestore:"currentPeriodEnd" json:"currentPeriodEnd"`
	CancelAtPeriodEnd  bool               `firestore:"cancelAtPeriodEnd" json:"cancelAtPeriodEnd"`
	CancelledAt        *time.Time         `firestore:"cancelledAt,omitempty" json:"cancelledAt,omitempty"`
	PaymentMethod      string             `firestore:"paymentMethod" json:"paymentMethod"` // "bank_transfer", "payg"
	AssignedByAdmin    bool               `firestore:"assignedByAdmin" json:"assignedByAdmin"`
	UpdatedAt          time.Time          `firestore:"updatedAt" json:"updatedAt"`
}

// InvoiceStatus tracks whether an invoice is issued, settled or voided (Phase 9).
type InvoiceStatus string

const (
	InvoiceDraft   InvoiceStatus = "draft"
	InvoiceIssued  InvoiceStatus = "issued"
	InvoicePaid    InvoiceStatus = "paid"
	InvoiceVoid    InvoiceStatus = "void"
	InvoiceOverdue InvoiceStatus = "overdue"
)

// InvoiceLineItem separates staffing charges from membership fees (Phase 9).
type InvoiceLineItem struct {
	Type        string  `firestore:"type" json:"type"` // "staffing", "subscription", "booking_fee", "adjustment"
	Description string  `firestore:"description" json:"description"`
	Quantity    float64 `firestore:"quantity" json:"quantity"`
	UnitPence   int64   `firestore:"unitPence" json:"unitPence"`
	TotalPence  int64   `firestore:"totalPence" json:"totalPence"`
	TimesheetID string  `firestore:"timesheetId,omitempty" json:"timesheetId,omitempty"`
	ShiftID     string  `firestore:"shiftId,omitempty" json:"shiftId,omitempty"`
}

// Invoice records sequential billing for nurseries with bank transfer settlement (Phase 9).
type Invoice struct {
	ID               string            `firestore:"-" json:"id"`
	InvoiceNumber    string            `firestore:"invoiceNumber" json:"invoiceNumber"` // e.g. INV-2026-0001
	NurseryID        string            `firestore:"nurseryId" json:"nurseryId"`
	NurseryName      string            `firestore:"nurseryName" json:"nurseryName"`
	BillingAddress   string            `firestore:"billingAddress" json:"billingAddress"`
	BillingEmail     string            `firestore:"billingEmail" json:"billingEmail"`
	CompanyNumber    string            `firestore:"companyNumber,omitempty" json:"companyNumber,omitempty"`
	IssueDate        time.Time         `firestore:"issueDate" json:"issueDate"`
	DueDate          time.Time         `firestore:"dueDate" json:"dueDate"`
	Status           InvoiceStatus     `firestore:"status" json:"status"`
	Type             string            `firestore:"type" json:"type"` // "weekly_staffing", "subscription", "combined"
	LineItems        []InvoiceLineItem `firestore:"lineItems" json:"lineItems"`
	SubtotalPence    int64             `firestore:"subtotalPence" json:"subtotalPence"` // ex-VAT
	VATRate          float64           `firestore:"vatRate" json:"vatRate"`
	VATPence         int64             `firestore:"vatPence" json:"vatPence"`
	TotalPence       int64             `firestore:"totalPence" json:"totalPence"` // inc-VAT
	PaymentMethod    string            `firestore:"paymentMethod" json:"paymentMethod"`
	PaidAt           *time.Time        `firestore:"paidAt,omitempty" json:"paidAt,omitempty"`
	PaymentReference string            `firestore:"paymentReference,omitempty" json:"paymentReference,omitempty"`
	Notes            string            `firestore:"notes,omitempty" json:"notes,omitempty"`
	CreatedAt        time.Time         `firestore:"createdAt" json:"createdAt"`
	UpdatedAt        time.Time         `firestore:"updatedAt" json:"updatedAt"`
}

// LedgerEntry records discounts, credits and refunds without money movement (Phase 9).
type LedgerEntry struct {
	ID          string    `firestore:"-" json:"id"`
	NurseryID   string    `firestore:"nurseryId" json:"nurseryId"`
	Type        string    `firestore:"type" json:"type"` // "discount", "refund", "credit"
	AmountPence int64     `firestore:"amountPence" json:"amountPence"`
	Reason      string    `firestore:"reason" json:"reason"`
	InvoiceID   string    `firestore:"invoiceId,omitempty" json:"invoiceId,omitempty"`
	ActorUID    string    `firestore:"actorUid" json:"actorUid"`
	CreatedAt   time.Time `firestore:"createdAt" json:"createdAt"`
}
