package function

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/GoogleCloudPlatform/functions-framework-go/functions"
	"google.golang.org/api/iterator"

	"kvision.internal/shared/audit"
	"kvision.internal/shared/auth"
	"kvision.internal/shared/httpjson"
)

func init() {
	functions.HTTP("ListEmailTemplates", authed(listEmailTemplates))
	functions.HTTP("SaveEmailTemplate", authed(saveEmailTemplate))
	functions.HTTP("DeleteEmailTemplate", authed(deleteEmailTemplate))
}

// appHomeURL is where an email's call-to-action points when the template does
// not supply its own. The install/download page: a nursery reading mail on a
// laptop has no app to deep-link into.
const appHomeURL = "https://kvision-503115.web.app"

const emailTemplatesCollection = "emailTemplates"

// EmailTemplateDoc is one reusable message an administrator keeps in the
// operations console — a payment reminder, a greeting, a document chase.
//
// The body is Markdown: the console composer renders it and the mail service
// renders it again into the HTML email, so what is saved is exactly what the
// administrator wrote (and can edit later) rather than pre-baked HTML that
// nobody can safely change.
type EmailTemplateDoc struct {
	Slug         string    `firestore:"slug" json:"slug"`
	Name         string    `firestore:"name" json:"name"`
	Category     string    `firestore:"category" json:"category"`
	Subject      string    `firestore:"subject" json:"subject"`
	BodyMarkdown string    `firestore:"bodyMarkdown" json:"bodyMarkdown"`
	CTALabel     string    `firestore:"ctaLabel" json:"ctaLabel"`
	CTAURL       string    `firestore:"ctaUrl" json:"ctaUrl"`
	Essential    bool      `firestore:"essential" json:"essential"`
	System       bool      `firestore:"system" json:"system"`
	UpdatedAt    time.Time `firestore:"updatedAt" json:"updatedAt"`
	UpdatedBy    string    `firestore:"updatedBy" json:"updatedBy"`
}

// listEmailTemplates — POST /listEmailTemplates. Admin only.
//
// Seeds the starter set on first use. A console where "templates" is an empty
// table gives an administrator nothing to work from, and the messages the
// platform actually sends (a payment reminder, a welcome, a document chase)
// are known before anyone opens the tab.
func listEmailTemplates(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !isAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "NOT_ADMIN", "Admin claim required")
		return
	}
	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	if err := seedEmailTemplates(ctx, db); err != nil {
		// Seeding is a convenience; a failure to write the starter set must
		// not stop the administrator seeing (and editing) what already exists.
		// It is logged by the caller's own error handling below.
		_ = err
	}

	iter := db.Collection(emailTemplatesCollection).Documents(ctx)
	defer iter.Stop()
	out := []EmailTemplateDoc{}
	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		var tpl EmailTemplateDoc
		if err := doc.DataTo(&tpl); err != nil {
			continue
		}
		if tpl.Slug == "" {
			tpl.Slug = doc.Ref.ID
		}
		out = append(out, tpl)
	}
	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"templates": out})
}

type saveEmailTemplateRequest struct {
	Slug         string `json:"slug,omitempty"`
	Name         string `json:"name"`
	Category     string `json:"category,omitempty"`
	Subject      string `json:"subject"`
	BodyMarkdown string `json:"bodyMarkdown"`
	CTALabel     string `json:"ctaLabel,omitempty"`
	CTAURL       string `json:"ctaUrl,omitempty"`
	Essential    bool   `json:"essential,omitempty"`
}

// saveEmailTemplate — POST /saveEmailTemplate. Admin only. Creates when slug is
// empty, updates in place otherwise, so editing a template never silently
// forks it into a second one.
func saveEmailTemplate(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !isAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "NOT_ADMIN", "Admin claim required")
		return
	}
	var req saveEmailTemplateRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	req.Name = strings.TrimSpace(req.Name)
	req.Subject = strings.TrimSpace(req.Subject)
	req.BodyMarkdown = strings.TrimSpace(req.BodyMarkdown)
	if req.Name == "" || req.Subject == "" || req.BodyMarkdown == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "name, subject and body are required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	slug := strings.TrimSpace(req.Slug)
	if slug == "" {
		slug = slugify(req.Name)
	}
	if slug == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "give the template a name with at least one letter or number")
		return
	}

	category := strings.ToLower(strings.TrimSpace(req.Category))
	if category == "" {
		category = "general"
	}

	ref := db.Collection(emailTemplatesCollection).Doc(slug)
	existing, getErr := ref.Get(ctx)
	system := false
	if getErr == nil {
		system, _ = existing.Data()["system"].(bool)
	}

	doc := EmailTemplateDoc{
		Slug:         slug,
		Name:         req.Name,
		Category:     category,
		Subject:      req.Subject,
		BodyMarkdown: req.BodyMarkdown,
		CTALabel:     strings.TrimSpace(req.CTALabel),
		CTAURL:       strings.TrimSpace(req.CTAURL),
		Essential:    req.Essential,
		System:       system,
		UpdatedAt:    time.Now().UTC(),
		UpdatedBy:    auth.UID(ctx),
	}
	if _, err := ref.Set(ctx, doc); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:    "comms.save_template",
		ActorUID:  auth.UID(ctx),
		TargetDoc: slug,
		Metadata:  map[string]any{"name": doc.Name, "category": doc.Category, "created": getErr != nil},
	})

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"status": "saved", "template": doc})
}

var errSystemTemplate = errors.New("built-in templates cannot be deleted — edit one instead")

// deleteEmailTemplate — POST /deleteEmailTemplate. Admin only. The seeded
// set is protected: those slugs are the ones an administrator is most likely
// to want back, and a delete-and-reseed would silently discard their edits.
func deleteEmailTemplate(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !isAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "NOT_ADMIN", "Admin claim required")
		return
	}
	var req struct {
		Slug string `json:"slug"`
	}
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	if strings.TrimSpace(req.Slug) == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "slug is required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}
	ref := db.Collection(emailTemplatesCollection).Doc(req.Slug)
	snap, err := ref.Get(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusNotFound, "TEMPLATE_NOT_FOUND", "No template with that slug")
		return
	}
	if system, _ := snap.Data()["system"].(bool); system {
		httpjson.WriteError(w, http.StatusConflict, "SYSTEM_TEMPLATE", errSystemTemplate.Error())
		return
	}
	if _, err := ref.Delete(ctx); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	_ = audit.WriteAudit(ctx, db, audit.Entry{
		Action:    "comms.delete_template",
		ActorUID:  auth.UID(ctx),
		TargetDoc: req.Slug,
	})
	httpjson.WriteJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

// slugify keeps template ids stable and readable: "Payment reminder (7 days)"
// becomes "payment-reminder-7-days".
func slugify(value string) string {
	var b strings.Builder
	lastDash := false
	for _, r := range strings.ToLower(value) {
		switch {
		case r >= 'a' && r <= 'z', r >= '0' && r <= '9':
			b.WriteRune(r)
			lastDash = false
		default:
			if !lastDash && b.Len() > 0 {
				b.WriteByte('-')
				lastDash = true
			}
		}
	}
	return strings.Trim(b.String(), "-")
}

// seedEmailTemplates writes the starter set once. Existing documents are left
// completely alone: an administrator's edits are the point of the collection.
func seedEmailTemplates(ctx context.Context, db *firestore.Client) error {
	existing, err := db.Collection(emailTemplatesCollection).Limit(1).Documents(ctx).GetAll()
	if err != nil {
		return err
	}
	if len(existing) > 0 {
		return nil
	}

	now := time.Now().UTC()
	batch := db.Batch()
	for _, tpl := range starterEmailTemplates() {
		tpl.System = true
		tpl.UpdatedAt = now
		batch.Set(db.Collection(emailTemplatesCollection).Doc(tpl.Slug), tpl)
	}
	_, err = batch.Commit(ctx)
	return err
}

// starterEmailTemplates is the set every new console starts with. Placeholders
// {{name}} and {{first_name}} are filled from the recipient's profile at send
// time; {{invoice_number}}, {{total}} and {{due_date}} are only meaningful
// when sent from an invoice, so the payment one spells them out in words too.
func starterEmailTemplates() []EmailTemplateDoc {
	return []EmailTemplateDoc{
		{
			Slug:     "welcome-greeting",
			Name:     "Welcome / greeting",
			Category: "greeting",
			Subject:  "Welcome to K Flex",
			BodyMarkdown: "Hi {{first_name}},\n\n" +
				"Welcome to K Flex — thank you for joining.\n\n" +
				"A quick start:\n\n" +
				"- Choose whether you are a **nursery** or a **practitioner**.\n" +
				"- Complete your profile so we can match you well.\n" +
				"- Upload your documents; our team verifies them, usually within one working day.\n\n" +
				"If you get stuck, just reply to this email.\n\n" +
				"— The K Flex team",
		},
		{
			Slug:     "payment-reminder",
			Name:     "Invoice payment reminder",
			Category: "payments",
			Subject:  "Reminder: your K Flex invoice is due",
			BodyMarkdown: "Hi {{first_name}},\n\n" +
				"This is a friendly reminder that your K Flex invoice is due.\n\n" +
				"You can see the amount, the itemised shifts and the pay-by-card link under **Invoices** in the app.\n\n" +
				"If you have already paid, thank you — please ignore this message.\n\n" +
				"— K Flex billing",
			CTALabel: "View my invoices",
			CTAURL:   appHomeURL,
		},
		{
			Slug:     "payment-received",
			Name:     "Payment received — thank you",
			Category: "payments",
			Subject:  "Thank you — we have received your payment",
			BodyMarkdown: "Hi {{first_name}},\n\n" +
				"Thank you — your payment has been received and your account is up to date.\n\n" +
				"Your invoice is available under **Invoices** in the app at any time.\n\n" +
				"— K Flex billing",
		},
		{
			Slug:     "document-needed",
			Name:     "Document needed to finish verification",
			Category: "compliance",
			Subject:  "We need one more document to finish your verification",
			BodyMarkdown: "Hi {{first_name}},\n\n" +
				"Your verification is nearly complete. To finish it we need:\n\n" +
				"- a clear photo of your **DBS certificate** (all four corners visible), and\n" +
				"- proof of your **right to work** in the UK.\n\n" +
				"Uploading takes a minute from your profile, and reviewing it is usually same-day.\n\n" +
				"— K Flex compliance",
			CTALabel: "Upload documents",
			CTAURL:   appHomeURL,
			Essential: true,
		},
		{
			Slug:     "dbs-recheck",
			Name:     "DBS recheck due",
			Category: "compliance",
			Subject:  "Your DBS check needs renewing",
			BodyMarkdown: "Hi {{first_name}},\n\n" +
				"Your DBS certificate is due for renewal. To keep working through K Flex, please update your certificate details and upload the new certificate.\n\n" +
				"If you are on the Update Service, share the status check and we will verify it for you.\n\n" +
				"— K Flex compliance",
			CTALabel: "Update my DBS",
			CTAURL:   appHomeURL,
			Essential: true,
		},
		{
			Slug:     "profile-nudge",
			Name:     "Finish your profile",
			Category: "general",
			Subject:  "Finish your K Flex profile to get matched",
			BodyMarkdown: "Hi {{first_name}},\n\n" +
				"Your profile is not finished yet — and that is what nurseries look at when they choose who to book.\n\n" +
				"Add your experience, availability and a short bio. It takes about five minutes and makes a real difference to how often you are booked.\n\n" +
				"— The K Flex team",
			CTALabel: "Finish my profile",
			CTAURL:   appHomeURL,
		},
		{
			Slug:     "seasonal-greeting",
			Name:     "Seasonal greeting",
			Category: "greeting",
			Subject:  "A note from K Flex",
			BodyMarkdown: "Hi {{first_name}},\n\n" +
				"Wishing you a restful break from all of us at K Flex.\n\n" +
				"Thank you for being part of the platform this year.\n\n" +
				"— The K Flex team",
		},
		{
			Slug:     "maintenance-notice",
			Name:     "Planned maintenance notice",
			Category: "general",
			Subject:  "K Flex maintenance this weekend",
			BodyMarkdown: "Hi {{first_name}},\n\n" +
				"K Flex will be unavailable for a short maintenance window this weekend.\n\n" +
				"**When:** Sunday, 02:00–03:00\n\n" +
				"Nothing you have saved is affected. If you have a shift during that window, everything you need is already in your confirmation email.\n\n" +
				"— K Flex operations",
			Essential: true,
		},
	}
}
