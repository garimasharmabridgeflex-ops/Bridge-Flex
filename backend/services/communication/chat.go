package function

import (
	"context"
	"fmt"
	"net/http"
	"sort"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/GoogleCloudPlatform/functions-framework-go/functions"
	"google.golang.org/api/iterator"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"kvision.internal/shared/auth"
	"kvision.internal/shared/httpjson"
)

func init() {
	functions.HTTP("SendChatMessage", authed(sendChatMessage))
	functions.HTTP("ListChatMessages", authed(listChatMessages))
	functions.HTTP("ListChatSessions", authed(listChatSessions))
}

// chatSessionID is the deterministic document ID for the single conversation
// a nursery and a practitioner share. Deriving it from the sorted pair (rather
// than letting Firestore assign an ID) is what makes the conversation
// pair-scoped instead of shift-scoped: every later booking resolves to the
// same thread, and the emulator/handler can be tested without a lookup.
func chatSessionID(a, b string) string {
	if a > b {
		a, b = b, a
	}
	return "chat_" + a + "_" + b
}

// listChatSessions — GET /listChatSessions. Sessions the caller is a
// participant in — already a client-legal query per Security Rules (§3), a
// plain-HTTP mirror for the same reason listOpenShifts/listMyShifts are in
// functions-core. No orderBy here (array-contains + orderBy on a different
// field needs a composite index that isn't deployed) — callers sort
// client-side by lastMessageAt instead.
//
// Legacy per-shift threads are folded into the pair's canonical conversation
// here too (see foldDuplicateSessions), so an existing install collapses to
// one thread per peer the first time the chat list is loaded, not only when
// the pair happens to book again.
func listChatSessions(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	uid := auth.UID(ctx)

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	iter := db.Collection("chatSessions").Where("participantIds", "array-contains", uid).Documents(ctx)
	defer iter.Stop()

	sessions := make([]map[string]any, 0)
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
		data["sessionId"] = doc.Ref.ID
		sessions = append(sessions, data)
	}

	sessions, err = foldDuplicateSessions(ctx, db, uid, sessions)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}
	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"sessions": sessions})
}

// ensureChatSession resolves the single conversation for a nursery/staff pair
// and records the shift that most recently brought them together. Only ever
// called from onShiftBooked (server-side) — a client can never create a
// conversation directly (§2/§3): "a chat session can't exist for a shift that
// was never booked."
func ensureChatSession(ctx context.Context, db *firestore.Client, shiftID, nurseryID, staffID string) (string, error) {
	if nurseryID == "" || staffID == "" {
		return "", fmt.Errorf("ensureChatSession: nurseryId and staffId are required")
	}

	sessionID := chatSessionID(nurseryID, staffID)
	ref := db.Collection("chatSessions").Doc(sessionID)
	now := time.Now()

	_, err := ref.Get(ctx)
	switch {
	case status.Code(err) == codes.NotFound:
		if _, err := ref.Set(ctx, map[string]any{
			"participantIds": []string{nurseryID, staffID},
			"createdAt":      now,
			"lastMessageAt":  now,
			"lastShiftId":    shiftID,
		}); err != nil {
			return "", err
		}
	case err != nil:
		return "", err
	default:
		// The thread already exists: keep its history, just note the newest
		// shared shift so the client can link back to it.
		if _, err := ref.Set(ctx, map[string]any{
			"participantIds": []string{nurseryID, staffID},
			"lastShiftId":    shiftID,
		}, firestore.MergeAll); err != nil {
			return "", err
		}
	}

	if err := mergeLegacySessions(ctx, db, sessionID, nurseryID, staffID); err != nil {
		return "", err
	}
	return sessionID, nil
}

type legacySession struct {
	id            string
	lastMessageAt time.Time
}

// mergeLegacySessions finds earlier per-shift conversations between the same
// pair (documents with a `shiftId` field, from before the pair-scoped change)
// and moves their messages into the canonical thread.
func mergeLegacySessions(ctx context.Context, db *firestore.Client, canonicalID, a, b string) error {
	iter := db.Collection("chatSessions").Where("participantIds", "array-contains", a).Documents(ctx)
	defer iter.Stop()

	var legacy []legacySession
	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return err
		}
		if doc.Ref.ID == canonicalID {
			continue
		}
		participants, _ := doc.Data()["participantIds"].([]any)
		if !containsUID(participants, b) {
			continue
		}
		session := legacySession{id: doc.Ref.ID}
		if t, ok := doc.Data()["lastMessageAt"].(time.Time); ok {
			session.lastMessageAt = t
		}
		legacy = append(legacy, session)
	}

	for _, old := range legacy {
		if err := moveSession(ctx, db, old.id, canonicalID); err != nil {
			return err
		}
	}
	if len(legacy) == 0 {
		return nil
	}

	// The newest legacy thread is the one whose timestamp the merged
	// conversation should inherit, so unread ordering in the list stays sane.
	latest := time.Time{}
	for _, old := range legacy {
		if old.lastMessageAt.After(latest) {
			latest = old.lastMessageAt
		}
	}
	if latest.IsZero() {
		return nil
	}
	canonical := db.Collection("chatSessions").Doc(canonicalID)
	snap, err := canonical.Get(ctx)
	if err != nil {
		return err
	}
	if current, ok := snap.Data()["lastMessageAt"].(time.Time); ok && current.After(latest) {
		return nil
	}
	_, err = canonical.Update(ctx, []firestore.Update{{Path: "lastMessageAt", Value: latest}})
	return err
}

// moveSession copies a thread's messages into the canonical conversation and
// deletes the old thread. Message documents keep their IDs, so running this
// twice for the same thread overwrites instead of duplicating.
func moveSession(ctx context.Context, db *firestore.Client, fromID, toID string) error {
	from := db.Collection("chatSessions").Doc(fromID)
	to := db.Collection("chatSessions").Doc(toID)

	iter := from.Collection("messages").Documents(ctx)
	var docs []*firestore.DocumentSnapshot
	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			iter.Stop()
			return err
		}
		docs = append(docs, doc)
	}
	iter.Stop()

	for _, doc := range docs {
		if _, err := to.Collection("messages").Doc(doc.Ref.ID).Set(ctx, doc.Data()); err != nil {
			return err
		}
		if _, err := doc.Ref.Delete(ctx); err != nil {
			return err
		}
	}
	_, err := from.Delete(ctx)
	return err
}

// foldDuplicateSessions collapses any group of threads that share the same
// counterpart into that pair's canonical conversation and returns one entry
// per peer. A pair with only its canonical thread (the normal case) is passed
// through untouched and costs no extra reads.
func foldDuplicateSessions(ctx context.Context, db *firestore.Client, uid string, sessions []map[string]any) ([]map[string]any, error) {
	byPeer := make(map[string][]map[string]any, len(sessions))
	order := make([]string, 0, len(sessions))
	for _, session := range sessions {
		participants, _ := session["participantIds"].([]any)
		peer := ""
		for _, p := range participants {
			if s, ok := p.(string); ok && s != uid {
				peer = s
				break
			}
		}
		if peer == "" {
			continue
		}
		if _, seen := byPeer[peer]; !seen {
			order = append(order, peer)
		}
		byPeer[peer] = append(byPeer[peer], session)
	}

	out := make([]map[string]any, 0, len(order))
	for _, peer := range order {
		group := byPeer[peer]
		canonicalID := chatSessionID(uid, peer)
		if len(group) == 1 && group[0]["sessionId"] == canonicalID {
			out = append(out, group[0])
			continue
		}
		if err := mergeLegacySessions(ctx, db, canonicalID, uid, peer); err != nil {
			return nil, err
		}
		snap, err := db.Collection("chatSessions").Doc(canonicalID).Get(ctx)
		if status.Code(err) == codes.NotFound {
			// Nothing survived the merge (e.g. a group of empty legacy
			// threads) — surface the most recent one rather than a phantom.
			out = append(out, group[0])
			continue
		}
		if err != nil {
			return nil, err
		}
		data := snap.Data()
		data["sessionId"] = canonicalID
		out = append(out, data)
	}

	sort.SliceStable(out, func(i, j int) bool {
		ti, _ := out[i]["lastMessageAt"].(time.Time)
		tj, _ := out[j]["lastMessageAt"].(time.Time)
		return ti.After(tj)
	})
	return out, nil
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
