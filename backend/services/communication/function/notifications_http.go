package function

import (
	"net/http"

	"cloud.google.com/go/firestore"
	"github.com/GoogleCloudPlatform/functions-framework-go/functions"
	"google.golang.org/api/iterator"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"bridgeflex/shared/auth"
	"bridgeflex/shared/httpjson"
)

func init() {
	functions.HTTP("ListNotifications", authed(listNotifications))
	functions.HTTP("MarkNotificationRead", authed(markNotificationRead))
	functions.HTTP("MarkAllNotificationsRead", authed(markAllNotificationsRead))
}

// listNotifications — GET /listNotifications. Own notifications only — the
// in-app source of truth described in §6, independent of whether any given
// push succeeded.
func listNotifications(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	uid := auth.UID(ctx)

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}
	iter := db.Collection("notifications").Where("uid", "==", uid).
		OrderBy("createdAt", firestore.Desc).Documents(ctx)
	defer iter.Stop()

	notifications := make([]map[string]any, 0)
	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		data := doc.Data()
		data["notificationId"] = doc.Ref.ID
		notifications = append(notifications, data)
	}
	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"notifications": notifications})
}

type markNotificationReadRequest struct {
	NotificationID string `json:"notificationId"`
}

// markNotificationRead — POST /markNotificationRead. Owner-only, only the
// `read` flag — mirrors the Security Rule exactly (§3), since a client could
// legally do this same write directly.
func markNotificationRead(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	uid := auth.UID(ctx)

	var req markNotificationReadRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	if req.NotificationID == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "notificationId is required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}
	ref := db.Collection("notifications").Doc(req.NotificationID)
	snap, err := ref.Get(ctx)
	if status.Code(err) == codes.NotFound {
		httpjson.WriteError(w, http.StatusNotFound, "NOTIFICATION_NOT_FOUND", "Notification not found")
		return
	}
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}
	if ownerUID, _ := snap.Data()["uid"].(string); ownerUID != uid {
		httpjson.WriteError(w, http.StatusForbidden, "NOT_YOUR_NOTIFICATION", "This notification does not belong to you")
		return
	}

	_, err = ref.Update(ctx, []firestore.Update{{Path: "read", Value: true}})
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}
	httpjson.WriteJSON(w, http.StatusOK, map[string]string{"status": "marked_read"})
}

func markAllNotificationsRead(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	uid := auth.UID(ctx)

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}
	iter := db.Collection("notifications").Where("uid", "==", uid).Documents(ctx)
	defer iter.Stop()

	bw := db.Batch()
	count := 0
	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			break
		}
		read, _ := doc.Data()["read"].(bool)
		if !read {
			bw.Update(doc.Ref, []firestore.Update{{Path: "read", Value: true}})
			count++
		}
	}
	if count > 0 {
		_, _ = bw.Commit(ctx)
	}
	httpjson.WriteJSON(w, http.StatusOK, map[string]string{"status": "marked_all_read"})
}
