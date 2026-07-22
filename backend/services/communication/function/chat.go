package function

import (
	"context"
	"net/http"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/GoogleCloudPlatform/functions-framework-go/functions"
	"google.golang.org/api/iterator"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"bridgeflex/shared/auth"
	"bridgeflex/shared/httpjson"
)

func init() {
	functions.HTTP("SendChatMessage", authed(sendChatMessage))
	functions.HTTP("ListChatMessages", authed(listChatMessages))
}

// ensureChatSession finds or creates the chatSessions/{sessionId} doc for a
// shift. Only ever called from onShiftBooked (server-side) — a client can
// never create a session directly (§2/§3): "a chat session can't exist for a
// shift that was never booked."
func ensureChatSession(ctx context.Context, db *firestore.Client, shiftID, nurseryID, staffID string) (string, error) {
	iter := db.Collection("chatSessions").Where("shiftId", "==", shiftID).Limit(1).Documents(ctx)
	defer iter.Stop()
	doc, err := iter.Next()
	if err == nil {
		return doc.Ref.ID, nil
	}
	if err != iterator.Done {
		return "", err
	}

	ref, _, err := db.Collection("chatSessions").Add(ctx, map[string]any{
		"shiftId":        shiftID,
		"participantIds": []string{nurseryID, staffID},
		"createdAt":      time.Now(),
		"lastMessageAt":  time.Now(),
	})
	if err != nil {
		return "", err
	}
	return ref.ID, nil
}

type sendChatMessageRequest struct {
	SessionID string `json:"sessionId"`
	Text      string `json:"text"`
}

// sendChatMessage — POST /sendChatMessage. A client could equally write this
// directly via the Firestore SDK (the Security Rule already permits
// participant writes, §3) — this endpoint exists so the Bruno collection has
// something to exercise without a full client SDK in the loop.
func sendChatMessage(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	uid := auth.UID(ctx)

	var req sendChatMessageRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	if req.SessionID == "" || req.Text == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "sessionId and text are required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}
	sessionRef := db.Collection("chatSessions").Doc(req.SessionID)
	snap, err := sessionRef.Get(ctx)
	if status.Code(err) == codes.NotFound {
		httpjson.WriteError(w, http.StatusNotFound, "SESSION_NOT_FOUND", "Chat session not found")
		return
	}
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}
	participantIDs, _ := snap.Data()["participantIds"].([]any)
	if !containsUID(participantIDs, uid) {
		httpjson.WriteError(w, http.StatusForbidden, "NOT_A_PARTICIPANT", "You are not a participant in this chat session")
		return
	}

	_, _, err = sessionRef.Collection("messages").Add(ctx, map[string]any{
		"senderId":  uid,
		"text":      req.Text,
		"createdAt": time.Now(),
		"readBy":    []string{uid},
	})
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}
	_, err = sessionRef.Update(ctx, []firestore.Update{{Path: "lastMessageAt", Value: time.Now()}})
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}
	httpjson.WriteJSON(w, http.StatusCreated, map[string]string{"status": "sent"})
}

// listChatMessages — GET /listChatMessages?sessionId=...
func listChatMessages(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	uid := auth.UID(ctx)
	sessionID := r.URL.Query().Get("sessionId")
	if sessionID == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "sessionId query parameter is required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}
	sessionRef := db.Collection("chatSessions").Doc(sessionID)
	snap, err := sessionRef.Get(ctx)
	if status.Code(err) == codes.NotFound {
		httpjson.WriteError(w, http.StatusNotFound, "SESSION_NOT_FOUND", "Chat session not found")
		return
	}
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}
	participantIDs, _ := snap.Data()["participantIds"].([]any)
	if !containsUID(participantIDs, uid) {
		httpjson.WriteError(w, http.StatusForbidden, "NOT_A_PARTICIPANT", "You are not a participant in this chat session")
		return
	}

	iter := sessionRef.Collection("messages").OrderBy("createdAt", firestore.Asc).Documents(ctx)
	defer iter.Stop()
	messages := make([]map[string]any, 0)
	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		messages = append(messages, doc.Data())
	}
	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"messages": messages})
}

func containsUID(ids []any, uid string) bool {
	for _, id := range ids {
		if s, ok := id.(string); ok && s == uid {
			return true
		}
	}
	return false
}
