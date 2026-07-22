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

// Profile is the PRIVATE profiles/{uid} document — owner-read-only, full stop.
type Profile struct {
	Role        Role           `firestore:"role" json:"role"`
	Name        string         `firestore:"name" json:"name"`
	Location    *latlng.LatLng `firestore:"location" json:"location,omitempty"`
	Description string         `firestore:"description" json:"description,omitempty"`
	DBSStatus   DBSStatus      `firestore:"dbsStatus" json:"dbsStatus,omitempty"`
	Rating      Rating         `firestore:"rating" json:"rating"`
	CreatedAt   time.Time      `firestore:"createdAt" json:"createdAt"`
}

// ProfilePublic is the PUBLIC profilesPublic/{uid} document, derived from
// Profile by the syncProfilePublic trigger. No field here is ever
// client-writable — see ARCHITECTURE.md v2 §2/§3 (the v2 fix for the v1
// field-exposure bug).
type ProfilePublic struct {
	Role         Role      `firestore:"role" json:"role"`
	Name         string    `firestore:"name" json:"name"`
	LocationArea string    `firestore:"locationArea" json:"locationArea,omitempty"`
	Rating       Rating    `firestore:"rating" json:"rating"`
	DBSBadge     DBSStatus `firestore:"dbsBadge" json:"dbsBadge,omitempty"`
	UpdatedAt    time.Time `firestore:"updatedAt" json:"updatedAt"`
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
	NurseryID     string        `firestore:"nurseryId" json:"nurseryId"`
	Title         string        `firestore:"title" json:"title"`
	Date          string        `firestore:"date" json:"date"`
	StartTime     time.Time     `firestore:"startTime" json:"startTime"`
	EndTime       time.Time     `firestore:"endTime" json:"endTime"`
	PayRate       float64       `firestore:"payRate" json:"payRate"`
	Status        ShiftStatus   `firestore:"status" json:"status"`
	BookedStaffID *string       `firestore:"bookedStaffId" json:"bookedStaffId"`
	PaymentStatus PaymentStatus `firestore:"paymentStatus" json:"paymentStatus"`
	CreatedAt     time.Time     `firestore:"createdAt" json:"createdAt"`
}

// RatingDoc is ratings/{ratingId}. Immutable once created (§3).
type RatingDoc struct {
	ShiftID   string    `firestore:"shiftId" json:"shiftId"`
	RaterID   string    `firestore:"raterId" json:"raterId"`
	RateeID   string    `firestore:"rateeId" json:"rateeId"`
	Score     int64     `firestore:"score" json:"score"`
	Comment   string    `firestore:"comment" json:"comment,omitempty"`
	CreatedAt time.Time `firestore:"createdAt" json:"createdAt"`
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
}
