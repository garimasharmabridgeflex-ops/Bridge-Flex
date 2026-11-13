package function

import (
	"log/slog"
	"net/http"
	"strings"

	"github.com/GoogleCloudPlatform/functions-framework-go/functions"

	"kvision.internal/shared/auth"
	"kvision.internal/shared/httpjson"
)

func init() {
	functions.HTTP("SendTestEmail", authed(sendTestEmail))
}

type sendTestEmailRequest struct {
	To string `json:"to,omitempty"`
}

// sendTestEmail — POST /sendTestEmail. Admin only.
//
// Everything else mails through the send-email Pub/Sub queue, which is right
// for business events but useless for setting a mailbox up: the console would
// only ever learn that a message was queued, not that the SMTP account
// actually accepted it. This sends synchronously and returns the transport's
// own error ("smtp auth: 535 …"), so "Test" either proves the settings work or
// says exactly what is wrong with them.
func sendTestEmail(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !auth.HasRole(ctx, auth.AdminRoleSuperAdmin, auth.AdminRoleSupport) {
		httpjson.WriteError(w, http.StatusForbidden, "NOT_ADMIN", "Admin claim required")
		return
	}

	var req sendTestEmailRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	cfg, cfgErr := mailConfigFor(ctx, db)
	if cfgErr != nil {
		httpjson.WriteError(w, http.StatusConflict, "SMTP_NOT_CONFIGURED",
			"No mailer account is configured. Save the SMTP host, from address and any credentials first.")
		return
	}

	to := strings.TrimSpace(req.To)
	if to == "" {
		// Default to the signed-in admin, so "Test" needs no typing.
		if snap, snapErr := db.Collection("profiles").Doc(auth.UID(ctx)).Get(ctx); snapErr == nil {
			to, _ = snap.Data()["email"].(string)
		}
	}
	if to == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "Add a recipient address to test with")
		return
	}

	subject, htmlBody, textBody, renderErr := RenderTemplate(TemplateAdminMessage, map[string]string{
		"name":    "there",
		"subject": "K Flex mail test",
		"body":    "This is a test message from the K Flex operations console.\n\nIf you are reading it, the mailer account is working.",
	}, false)
	if renderErr != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", renderErr.Error())
		return
	}

	if err := sendMail(cfg, to, subject, htmlBody, textBody); err != nil {
		slog.Warn("test email failed", "domain", sanitizeRecipientDomain(to), "error", err)
		httpjson.WriteError(w, http.StatusBadGateway, "SEND_FAILED", err.Error())
		return
	}

	slog.Info("test email sent", "domain", sanitizeRecipientDomain(to))
	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"status": "sent", "to": to})
}
