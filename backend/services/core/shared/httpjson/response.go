// Package httpjson implements the shared JSON error/response envelope used by
// every HTTP endpoint across all three services, replacing the Node
// HttpsError contract. See ARCHITECTURE.md v2 §1a. The `code` strings are the
// same ones approved in the design doc (e.g. SHIFT_ALREADY_BOOKED) — only the
// transport changed from Node to Go.
package httpjson

import (
	"encoding/json"
	"net/http"
)

type errorBody struct {
	Error errorDetail `json:"error"`
}

type errorDetail struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

// WriteError writes the shared error envelope: {"error": {"code": "...", "message": "..."}}.
func WriteError(w http.ResponseWriter, status int, code, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(errorBody{Error: errorDetail{Code: code, Message: message}})
}

// WriteJSON writes a successful JSON response body with the given status code.
func WriteJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}

// DecodeJSON decodes the request body into dest. On failure it writes a
// BAD_REQUEST error response itself and returns false, so callers can just
// `if !httpjson.DecodeJSON(w, r, &req) { return }`.
func DecodeJSON(w http.ResponseWriter, r *http.Request, dest any) bool {
	if r.Body == nil {
		WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "Request body is required")
		return false
	}
	defer r.Body.Close()
	if err := json.NewDecoder(r.Body).Decode(dest); err != nil {
		WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "Could not parse request body as JSON")
		return false
	}
	return true
}
