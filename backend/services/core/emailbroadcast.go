package function

import (
	"context"
	"fmt"
	"net/http"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	firebaseauth "firebase.google.com/go/v4/auth"
	"github.com/GoogleCloudPlatform/functions-framework-go/functions"
	"google.golang.org/api/iterator"

	"kvision.internal/shared/audit"
	"kvision.internal/shared/auth"
	"kvision.internal/shared/httpjson"
)

func init() {
	functions.HTTP("SendAdminEmail", authed(sendAdminEmail))
}

// maxEmailTargets caps one broadcast for the same reason notifications are
// capped (maxBroadcastTargets): a single click must not fan out to an
// unbounded audience, and past a few hundred accounts a targeted send is the
// right shape anyway.
const maxEmailTargets = 500

type sendAdminEmailRequest struct {
	UID          string `json:"uid,omitempty"`
	Role         string `json:"role,omitempty"`        // "nursery" | "staff" | "all"
	TemplateSlug string `json:"templateSlug,omitempty"` // saved template to send
	Subject      string `json:"subject,omitempty"`
	BodyMarkdown string `json:"bodyMarkdown,omitempty"`
	CTALabel     string `json:"ctaLabel,omitempty"`
	CTAURL       string `json:"ctaUrl,omitempty"`
	Essential    bool   `json:"essential,omitempty"`
	SendCopy     bool   `json:"sendCopy,omitempty"` // also mail the signed-in admin
}

// sendAdminEmail — POST /sendAdminEmail. Admin only.
//
// The email twin of SendAdminNotification: one deliberate, manual message to
// an audience (everyone, every nursery, every practitioner, or one account),
// written in Markdown or picked from a saved template. Everything else the
// platform mails is a side effect of a business event.
//
// Delivery is queued through the send-email topic, exactly like transactional
// mail, so this returns once every message is on the queue — not when SMTP has
// accepted it. The response reports how many recipients were targeted and how
// many could not be queued (no address on file), so the console can say so
// rather than claim a clean send.
func sendAdminEmail(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !isAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "NOT_ADMIN", "Admin claim required")
		return
	}
	var req sendAdminEmailRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	// A saved template supplies the whole message; the typed fields fill in
	// anything it leaves blank, so "pick a template, tweak the subject" works.
	if slug := strings.TrimSpace(req.TemplateSlug); slug != "" {
		snap, err := db.Collection(emailTemplatesCollection).Doc(slug).Get(ctx)
		if err != nil {
			httpjson.WriteError(w, http.StatusNotFound, "TEMPLATE_NOT_FOUND", "No template with that slug")
			return
		}
		var tpl EmailTemplateDoc
		if err := snap.DataTo(&tpl); err != nil {
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "template is unreadable")
			return
		}
		if strings.TrimSpace(req.Subject) == "" {
			req.Subject = tpl.Subject
		}
		if strings.TrimSpace(req.BodyMarkdown) == "" {
			req.BodyMarkdown = tpl.BodyMarkdown
		}
		if strings.TrimSpace(req.CTALabel) == "" {
			req.CTALabel = tpl.CTALabel
		}
		if strings.TrimSpace(req.CTAURL) == "" {
			req.CTAURL = tpl.CTAURL
		}
		if !req.Essential {
			req.Essential = tpl.Essential
		}
	}

	req.Subject = strings.TrimSpace(req.Subject)
	req.BodyMarkdown = strings.TrimSpace(req.BodyMarkdown)
	if req.Subject == "" || req.BodyMarkdown == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "a subject and a message are required")
		return
	}

	recipients, err := resolveEmailRecipients(ctx, db, req.UID, req.Role)
	if err != nil {
		httpjson.WriteError(w, http.StatusBadRequest, "INVALID_TARGET", err.Error())
		return
	}
	if len(recipients) == 0 {
		httpjson.WriteError(w, http.StatusNotFound, "NO_TARGETS", "No accounts with an email address matched that audience")
		return
	}

	queued := 0
	noAddress := 0
	for _, rcpt := range recipients {
		if rcpt.Email == "" {
			noAddress++
			continue
		}
		err := publishCustomEmail(ctx, rcpt.Email, rcpt.Name, req.Subject, personalise(req.BodyMarkdown, rcpt.Name),
			req.CTALabel, req.CTAURL, req.Essential)
		if err == nil {
			queued++
		}
	}

	if req.SendCopy {
		if email := adminEmail(ctx, db); email != "" {
			_ = publishCustomEmail(ctx, email, "there", req.Subject, req.BodyMarkdown, req.CTALabel, req.CTAURL, req.Essential)
		}
	}

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:    "comms.send_email",
		ActorUID:  auth.UID(ctx),
		TargetUID: req.UID,
		Metadata: map[string]any{
			"subject":    req.Subject,
			"role":       req.Role,
			"template":   req.TemplateSlug,
			"targeted":   len(recipients),
			"queued":     queued,
			"noAddress":  noAddress,
			"essential":  req.Essential,
			"deliveredAt": time.Now().UTC(),
		},
	})

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{
		"status":    "queued",
		"targeted":  len(recipients),
		"queued":    queued,
		"noAddress": noAddress,
	})
}

type emailRecipient struct {
	UID   string
	Email string
	Name  string
}

// resolveEmailRecipients turns the console's audience picker into addresses.
// The profile document is the first source; when it has no email (accounts
// created before the sign-up trigger stored one, or where the client wrote the
// profile itself) the Firebase Auth record supplies it — the email a user
// signs in with is authoritative and always exists.
func resolveEmailRecipients(ctx context.Context, db *firestore.Client, uid, role string) ([]emailRecipient, error) {
	uid = strings.TrimSpace(uid)
	role = strings.ToLower(strings.TrimSpace(role))

	if uid != "" {
		out := []emailRecipient{{UID: uid}}
		if snap, err := db.Collection("profiles").Doc(uid).Get(ctx); err == nil {
			data := snap.Data()
			out[0].Email, _ = data["email"].(string)
			out[0].Name, _ = data["name"].(string)
		}
		if out[0].Email == "" {
			if users, err := authUserIndex(ctx); err == nil {
				if rec, ok := users[uid]; ok && rec != nil {
					out[0].Email = rec.Email
					if out[0].Name == "" {
						out[0].Name = rec.DisplayName
					}
				}
			}
		}
		return out, nil
	}

	if role == "" {
		return nil, errInvalidNotificationTarget
	}
	q := db.Collection("profiles").Query
	if role == "nursery" || role == "staff" {
		q = q.Where("role", "==", role)
	} else if role != "all" {
		return nil, errInvalidNotificationTarget
	}
	q = q.Limit(maxEmailTargets)

	docs, err := q.Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}

	out := make([]emailRecipient, 0, len(docs))
	var missing []int
	for _, doc := range docs {
		data := doc.Data()
		email, _ := data["email"].(string)
		name, _ := data["name"].(string)
		out = append(out, emailRecipient{UID: doc.Ref.ID, Email: email, Name: name})
		if email == "" {
			missing = append(missing, len(out)-1)
		}
	}
	if len(missing) > 0 {
		if users, err := authUserIndex(ctx); err == nil {
			for _, idx := range missing {
				if rec, ok := users[out[idx].UID]; ok && rec != nil {
					out[idx].Email = rec.Email
					if out[idx].Name == "" {
						out[idx].Name = rec.DisplayName
					}
				}
			}
		}
	}
	return out, nil
}

// shiftTitleFor reads a shift's display title, falling back to neutral wording
// so a notification or email never says "shift <opaque id>" to a practitioner.
func shiftTitleFor(ctx context.Context, db *firestore.Client, shiftID string) string {
	if shiftID == "" {
		return "your shift"
	}
	if snap, err := db.Collection("shifts").Doc(shiftID).Get(ctx); err == nil {
		if title, _ := snap.Data()["title"].(string); strings.TrimSpace(title) != "" {
			return title
		}
	}
	return "your shift"
}

// authEmailRecord is the slice of a Firebase Auth user the operations
// console actually needs alongside a profile.
type authEmailRecord struct {
	Email    string
	Verified bool
	Disabled bool
}

// authUserIndex reads every Firebase Auth user, keyed by uid. The email a
// person signs in with is never missing and never changes without them
// signing in again — which is exactly why the console shows it as the default
// contact address even when the profile never captured one.
func authUserIndex(ctx context.Context) (map[string]*firebaseauth.ExportedUserRecord, error) {
	app, err := adminApp(ctx)
	if err != nil {
		return nil, err
	}
	client, err := app.Auth(ctx)
	if err != nil {
		return nil, err
	}

	out := make(map[string]*firebaseauth.ExportedUserRecord)
	iter := client.Users(ctx, "")
	for {
		user, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return out, err
		}
		out[user.UID] = user
	}
	return out, nil
}

// publishCustomEmail queues one Markdown message. Template "custom" is what
// the mail service renders verbatim, so the operations console can send
// anything it likes without a code change.
func publishCustomEmail(ctx context.Context, toEmail, name, subject, bodyMarkdown, ctaLabel, ctaURL string, essential bool) error {
	toEmail = strings.TrimSpace(toEmail)
	if toEmail == "" {
		return fmt.Errorf("no recipient address")
	}
	msg := emailMessage{
		EventID:  fmt.Sprintf("custom-%s-%d", slugify(toEmail), time.Now().UnixNano()),
		ToEmail:  toEmail,
		Template: "custom",
		TemplateData: map[string]string{
			"name":       displayName(name),
			"subject":    subject,
			"body":       bodyMarkdown,
			"ctaLabel":   ctaLabel,
			"ctaUrl":     ctaURL,
			"appUrl":     appHomeURL,
		},
		IsEssential: essential,
	}
	return publish(ctx, topicSendEmail, msg)
}

// personalise fills the two placeholders the console documents. Anything the
// administrator wrote that is not a known placeholder is left exactly as-is.
func personalise(body, name string) string {
	first := displayName(name)
	if first == "there" {
		first = "there"
	} else if fields := strings.Fields(first); len(fields) > 0 {
		first = fields[0]
	}
	body = strings.ReplaceAll(body, "{{name}}", displayName(name))
	body = strings.ReplaceAll(body, "{{first_name}}", first)
	body = strings.ReplaceAll(body, "{{firstname}}", first)
	return body
}

// displayName is the greeting an email opens with; "there" is the neutral
// fallback the mail templates already use when no name is known.
func displayName(name string) string {
	if strings.TrimSpace(name) == "" {
		return "there"
	}
	return strings.TrimSpace(name)
}

// adminEmail returns the signed-in administrator's own address, used by the
// console's "send me a copy" option.
func adminEmail(ctx context.Context, db *firestore.Client) string {
	uid := auth.UID(ctx)
	if snap, err := db.Collection("profiles").Doc(uid).Get(ctx); err == nil {
		if email, _ := snap.Data()["email"].(string); email != "" {
			return email
		}
	}
	if users, err := authUserIndex(ctx); err == nil {
		if rec, ok := users[uid]; ok && rec != nil {
			return rec.Email
		}
	}
	return ""
}

// sendEmailToAddress queues one named transactional template to a raw address.
//
// sendTransactionalEmail resolves the address from profiles/{uid}; this exists
// for the two cases where there is no profile left (or the profile has no
// address): the welcome mail written at account creation, and the confirmation
// written immediately before an account is deleted.
func sendEmailToAddress(ctx context.Context, db *firestore.Client, toEmail, name, template string, data map[string]string, essential bool) bool {
	if strings.TrimSpace(toEmail) == "" {
		return false
	}
	if data == nil {
		data = map[string]string{}
	}
	if _, ok := data["name"]; !ok {
		data["name"] = displayName(name)
	}
	if _, ok := data["appUrl"]; !ok {
		data["appUrl"] = appHomeURL
	}
	msg := emailMessage{
		EventID:      fmt.Sprintf("%s-%s-%d", template, slugify(toEmail), time.Now().UnixNano()),
		ToEmail:      strings.TrimSpace(toEmail),
		Template:     template,
		TemplateData: data,
		IsEssential:  essential,
	}
	return publish(ctx, topicSendEmail, msg) == nil
}
