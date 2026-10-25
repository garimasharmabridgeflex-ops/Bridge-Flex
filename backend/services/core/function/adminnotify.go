package function

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/GoogleCloudPlatform/functions-framework-go/functions"

	"kvision.internal/shared/audit"
	"kvision.internal/shared/auth"
	"kvision.internal/shared/httpjson"
)

func init() {
	functions.HTTP("SendAdminNotification", authed(sendAdminNotification))
}

var errInvalidNotificationTarget = errors.New("target must be a uid, or role of nursery, staff or all")

type sendAdminNotificationRequest struct {
	UID   string         `json:"uid,omitempty"`
	Role  string         `json:"role,omitempty"` // "nursery" | "staff" | "all"
	Title string         `json:"title"`
	Body  string         `json:"body"`
	Type  string         `json:"type,omitempty"`
	Data  map[string]any `json:"data,omitempty"`
}

// sendAdminNotification — POST /sendAdminNotification. Admin only.
//
// The owner's brief asks to be able to "send notifications" from the admin
// dashboard. Everything else in the platform notifies as a side effect of an
// event (booking, approval, invoice); this is the deliberate, manual one —
// maintenance windows, launch news, policy changes.
//
// It writes in-app notification documents only. Push delivery is best-effort
// and lives in the communication service, so a broadcast never fails because
// one device token has gone stale.
func sendAdminNotification(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !isAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "NOT_ADMIN", "Admin permissions required")
		return
	}

	var req sendAdminNotificationRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	req.Title = strings.TrimSpace(req.Title)
	req.Body = strings.TrimSpace(req.Body)
	if req.Title == "" || req.Body == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "title and body are required")
		return
	}

	targets, err := resolveNotificationTargets(ctx, req)
	if err != nil {
		httpjson.WriteError(w, http.StatusBadRequest, "INVALID_TARGET", err.Error())
		return
	}
	if len(targets) == 0 {
		httpjson.WriteError(w, http.StatusNotFound, "NO_TARGETS", "No users matched that target")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore unavailable")
		return
	}

	notificationType := req.Type
	if notificationType == "" {
		notificationType = "admin_message"
	}
	if req.Data == nil {
		req.Data = map[string]any{}
	}

	sent := 0
	for _, uid := range targets {
		if err := notifyInApp(ctx, db, uid, notificationType, req.Title, req.Body, req.Data); err == nil {
			sent++
		}
	}

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:    "admin.send_notification",
		ActorUID:  auth.UID(ctx),
		TargetUID: req.UID,
		Metadata: map[string]any{
			"title":       req.Title,
			"role":        req.Role,
			"targetCount": len(targets),
			"sentCount":   sent,
			"deliveredAt": time.Now().UTC(),
		},
	})

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{
		"status":   "sent",
		"targeted": len(targets),
		"sent":     sent,
	})
}

// maxBroadcastTargets caps a single broadcast. It keeps one admin click from
// writing an unbounded number of documents in one request, and forces a
// targeted message when the platform grows past a few hundred accounts.
const maxBroadcastTargets = 500

func resolveNotificationTargets(ctx context.Context, req sendAdminNotificationRequest) ([]string, error) {
	db, err := fsDB(ctx)
	if err != nil {
		return nil, err
	}

	if req.UID != "" {
		return []string{req.UID}, nil
	}

	role := strings.ToLower(strings.TrimSpace(req.Role))
	if role == "" {
		return nil, errInvalidNotificationTarget
	}

	q := db.Collection("profiles").Query
	if role == "nursery" || role == "staff" {
		q = q.Where("role", "==", role)
	} else if role != "all" {
		return nil, errInvalidNotificationTarget
	}
	q = q.Limit(maxBroadcastTargets)
	iter := q.Documents(ctx)
	defer iter.Stop()

	var uids []string
	for {
		doc, err := iter.Next()
		if err != nil {
			break // iterator.Done — the only expected exit; errors surface as "no targets"
		}
		if uid, ok := doc.Data()["uid"].(string); ok && uid != "" {
			uids = append(uids, uid)
		} else {
			uids = append(uids, doc.Ref.ID)
		}
	}
	return uids, nil
}
