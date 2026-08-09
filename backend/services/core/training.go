package function

import (
	"context"
	"errors"
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
	functions.HTTP("ListTrainingModules", authed(listTrainingModules))
	functions.HTTP("SubmitTrainingQuiz", authed(submitTrainingQuiz))
	functions.HTTP("MarkTrainingVideoWatched", authed(markTrainingVideoWatched))

	// Admin authoring — the training spec requires questions to be editable
	// without an app release, so modules are data, not code.
	functions.HTTP("ListTrainingModulesAdmin", authed(listTrainingModulesAdmin))
	functions.HTTP("UpsertTrainingModule", authed(upsertTrainingModule))
	functions.HTTP("DeleteTrainingModule", authed(deleteTrainingModule))
}

var (
	errModuleNotFound  = errors.New("training module not found")
	errModuleNoQuiz    = errors.New("training module has no questions")
	errModuleUnpublish = errors.New("training module is not published")
)

// trainingCollection is server-only: the module document embeds each
// question's correctIndex, so it must never be client-readable. Firestore
// rules deny direct access and every read goes through these handlers, which
// strip the answers for non-admin callers (see toStaffModule).
const trainingCollection = "trainingModules"

// ─── Staff-facing ────────────────────────────────────────────────────────────

// staffQuestion is the question shape sent to a practitioner: prompt and
// options only. CorrectIndex is deliberately absent rather than zeroed — a
// zeroed field still tells a reader "the answer is index 0" for any question
// whose real answer happens to be 0.
type staffQuestion struct {
	ID      string   `json:"id"`
	Prompt  string   `json:"prompt"`
	Options []string `json:"options"`
}

type staffModule struct {
	ModuleID             string          `json:"moduleId"`
	Order                int64           `json:"order"`
	Title                string          `json:"title"`
	Purpose              string          `json:"purpose"`
	ContentOutline       []string        `json:"contentOutline"`
	VideoStoragePath     string          `json:"videoStoragePath,omitempty"`
	VideoURL             string          `json:"videoUrl,omitempty"`
	VideoDurationSeconds int64           `json:"videoDurationSeconds,omitempty"`
	Questions            []staffQuestion `json:"questions"`
	PassMark             int64           `json:"passMark"`

	// Caller's own progress, folded in so the module list is a single round
	// trip rather than one call per module.
	Status         TrainingProgressStatus `json:"status"`
	VideoWatched   bool                   `json:"videoWatched"`
	Attempts       int64                  `json:"attempts"`
	BestScore      int64                  `json:"bestScore"`
	LastScore      int64                  `json:"lastScore"`
	CompletedAt    *time.Time             `json:"completedAt,omitempty"`
	LastAttemptAt  *time.Time             `json:"lastAttemptAt,omitempty"`
	TotalQuestions int64                  `json:"totalQuestions"`
}

func toStaffModule(id string, m TrainingModule, p *TrainingProgress) staffModule {
	out := staffModule{
		ModuleID:             id,
		Order:                m.Order,
		Title:                m.Title,
		Purpose:              m.Purpose,
		ContentOutline:       m.ContentOutline,
		VideoStoragePath:     m.VideoStoragePath,
		VideoURL:             m.VideoURL,
		VideoDurationSeconds: m.VideoDurationSeconds,
		PassMark:             passMarkFor(m),
		TotalQuestions:       int64(len(m.Questions)),
		Status:               TrainingNotStarted,
	}
	for _, q := range m.Questions {
		out.Questions = append(out.Questions, staffQuestion{ID: q.ID, Prompt: q.Prompt, Options: q.Options})
	}
	if p != nil {
		out.Status = p.Status
		out.VideoWatched = p.VideoWatched
		out.Attempts = p.Attempts
		out.BestScore = p.BestScore
		out.LastScore = p.LastScore
		out.CompletedAt = p.CompletedAt
		out.LastAttemptAt = p.LastAttemptAt
	}
	return out
}

// passMarkFor falls back to 80% of the questions, rounded up, when an author
// hasn't set an explicit mark — so a module is never accidentally passable
// with a single correct answer just because the field was left blank.
func passMarkFor(m TrainingModule) int64 {
	n := int64(len(m.Questions))
	if m.PassMark > 0 && m.PassMark <= n {
		return m.PassMark
	}
	if n == 0 {
		return 0
	}
	return (n*4 + 4) / 5
}

// listTrainingModules — GET/POST. Returns every published module plus the
// caller's own progress against each.
func listTrainingModules(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	uid := auth.UID(ctx)

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	modules, err := loadModules(ctx, db, false)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	progress, err := loadProgress(ctx, db, uid)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	out := make([]staffModule, 0, len(modules))
	for _, m := range modules {
		p := progress[m.ID]
		out = append(out, toStaffModule(m.ID, m.Module, p))
	}

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{
		"modules":        out,
		"completedCount": completedCount(progress),
		"totalCount":     len(out),
	})
}

type markVideoRequest struct {
	ModuleID string `json:"moduleId"`
}

// markTrainingVideoWatched records that the practitioner reached the end of
// the video. It does not complete the module on its own — the spec requires
// the knowledge check for that — but it lets the UI unlock the quiz and lets
// a manager distinguish "watched but not yet tested" from "never opened".
func markTrainingVideoWatched(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	uid := auth.UID(ctx)

	var req markVideoRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	if req.ModuleID == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "moduleId is required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	if _, err := getPublishedModule(ctx, db, req.ModuleID); err != nil {
		writeTrainingError(w, err)
		return
	}

	ref := progressRef(db, uid, req.ModuleID)
	existing, err := readProgress(ctx, ref)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	updates := map[string]any{
		"moduleId":     req.ModuleID,
		"videoWatched": true,
		"updatedAt":    time.Now(),
	}
	// Never downgrade a completed module back to in_progress by rewatching.
	if existing == nil || existing.Status != TrainingCompleted {
		updates["status"] = string(TrainingInProgress)
	}
	if _, err := ref.Set(ctx, updates, firestore.MergeAll); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"moduleId": req.ModuleID, "videoWatched": true})
}

type quizAnswer struct {
	QuestionID    string `json:"questionId"`
	SelectedIndex int64  `json:"selectedIndex"`
}

type submitQuizRequest struct {
	ModuleID string       `json:"moduleId"`
	Answers  []quizAnswer `json:"answers"`
}

type quizResult struct {
	QuestionID   string `json:"questionId"`
	Correct      bool   `json:"correct"`
	CorrectIndex *int64 `json:"correctIndex,omitempty"`
	Explanation  string `json:"explanation,omitempty"`
}

// submitTrainingQuiz scores the attempt server-side. The client never receives
// correctIndex before submitting, so the answers can't be read out of the
// payload — which matters because completing these modules is what will gate
// paid shift work.
func submitTrainingQuiz(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	uid := auth.UID(ctx)

	var req submitQuizRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	if req.ModuleID == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "moduleId is required")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	module, err := getPublishedModule(ctx, db, req.ModuleID)
	if err != nil {
		writeTrainingError(w, err)
		return
	}
	if len(module.Questions) == 0 {
		writeTrainingError(w, errModuleNoQuiz)
		return
	}

	selected := make(map[string]int64, len(req.Answers))
	for _, a := range req.Answers {
		selected[a.QuestionID] = a.SelectedIndex
	}

	var score int64
	results := make([]quizResult, 0, len(module.Questions))
	for _, q := range module.Questions {
		// An unanswered question is wrong rather than skipped: the pass mark
		// is a count of correct answers, so silently omitting a question
		// would otherwise make a short submission easier to pass.
		got, answered := selected[q.ID]
		correct := answered && got == q.CorrectIndex
		if correct {
			score++
		}
		results = append(results, quizResult{QuestionID: q.ID, Correct: correct})
	}

	passMark := passMarkFor(module)
	passed := score >= passMark
	now := time.Now()

	ref := progressRef(db, uid, req.ModuleID)
	existing, err := readProgress(ctx, ref)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	attempts := int64(1)
	best := score
	alreadyCompleted := false
	if existing != nil {
		attempts = existing.Attempts + 1
		if existing.BestScore > best {
			best = existing.BestScore
		}
		alreadyCompleted = existing.Status == TrainingCompleted
	}

	newStatus := TrainingInProgress
	if passed || alreadyCompleted {
		newStatus = TrainingCompleted
	}

	update := map[string]any{
		"moduleId":       req.ModuleID,
		"status":         string(newStatus),
		"attempts":       attempts,
		"lastScore":      score,
		"bestScore":      best,
		"totalQuestions": int64(len(module.Questions)),
		"lastAttemptAt":  now,
		"updatedAt":      now,
	}
	if passed && !alreadyCompleted {
		update["completedAt"] = now
	}
	if _, err := ref.Set(ctx, update, firestore.MergeAll); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	// Mirror completion onto the profile document. The detailed record stays
	// in the subcollection; this summary exists so syncProfilePublic carries
	// it into profilesPublic, which is how a nursery sees training status on
	// an applicant without being able to read their private profile.
	if passed && !alreadyCompleted {
		profileRef := db.Collection("profiles").Doc(uid)
		if _, err := profileRef.Update(ctx, []firestore.Update{
			{Path: "trainingCompletedModuleIds", Value: firestore.ArrayUnion(req.ModuleID)},
			{Path: "trainingUpdatedAt", Value: now},
		}); err != nil {
			// The attempt itself is already recorded; failing the mirror
			// shouldn't lose the practitioner's pass. Surfaced as a 500 so
			// the inconsistency is visible rather than silent.
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "quiz recorded but profile summary update failed: "+err.Error())
			return
		}
	}

	// Correct answers are revealed only once the module is passed, so a
	// failed attempt can't be used to harvest the answer key.
	if passed {
		byID := make(map[string]TrainingQuestion, len(module.Questions))
		for _, q := range module.Questions {
			byID[q.ID] = q
		}
		for i := range results {
			if q, ok := byID[results[i].QuestionID]; ok {
				idx := q.CorrectIndex
				results[i].CorrectIndex = &idx
				results[i].Explanation = q.Explanation
			}
		}
	}

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{
		"moduleId":  req.ModuleID,
		"score":     score,
		"total":     len(module.Questions),
		"passMark":  passMark,
		"passed":    passed,
		"status":    string(newStatus),
		"attempts":  attempts,
		"bestScore": best,
		"results":   results,
	})
}

// ─── Admin authoring ─────────────────────────────────────────────────────────

type adminModule struct {
	ModuleID string `json:"moduleId"`
	TrainingModule
}

func listTrainingModulesAdmin(w http.ResponseWriter, r *http.Request) {
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
	modules, err := loadModules(ctx, db, true)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}
	out := make([]adminModule, 0, len(modules))
	for _, m := range modules {
		out = append(out, adminModule{ModuleID: m.ID, TrainingModule: m.Module})
	}
	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"modules": out})
}

type upsertModuleRequest struct {
	ModuleID             string             `json:"moduleId"`
	Order                int64              `json:"order"`
	Title                string             `json:"title"`
	Purpose              string             `json:"purpose"`
	ContentOutline       []string           `json:"contentOutline"`
	VideoStoragePath     string             `json:"videoStoragePath"`
	VideoURL             string             `json:"videoUrl"`
	VideoDurationSeconds int64              `json:"videoDurationSeconds"`
	Questions            []TrainingQuestion `json:"questions"`
	PassMark             int64              `json:"passMark"`
	Published            bool               `json:"published"`
}

func upsertTrainingModule(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !isAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "NOT_ADMIN", "Admin claim required")
		return
	}

	var req upsertModuleRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	if req.ModuleID == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "moduleId is required")
		return
	}
	if req.Title == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "title is required")
		return
	}
	for i, q := range req.Questions {
		if q.ID == "" {
			httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "every question needs an id")
			return
		}
		if len(q.Options) < 2 {
			httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "question "+q.ID+" needs at least two options")
			return
		}
		// Validated rather than trusted: an out-of-range answer index would
		// make the question unpassable, and the practitioner would have no
		// way to tell that the content, not their answer, was wrong.
		if q.CorrectIndex < 0 || q.CorrectIndex >= int64(len(q.Options)) {
			httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "question "+q.ID+" has a correctIndex outside its options")
			return
		}
		req.Questions[i] = q
	}
	if req.PassMark > int64(len(req.Questions)) {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "passMark cannot exceed the number of questions")
		return
	}
	if req.Published && len(req.Questions) == 0 {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "a published module needs at least one question — completion requires a knowledge check")
		return
	}

	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}

	ref := db.Collection(trainingCollection).Doc(req.ModuleID)
	now := time.Now()
	snap, err := ref.Get(ctx)
	createdAt := now
	if err == nil {
		var existing TrainingModule
		if err := snap.DataTo(&existing); err == nil && !existing.CreatedAt.IsZero() {
			createdAt = existing.CreatedAt
		}
	} else if status.Code(err) != codes.NotFound {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	module := TrainingModule{
		Order:                req.Order,
		Title:                req.Title,
		Purpose:              req.Purpose,
		ContentOutline:       req.ContentOutline,
		VideoStoragePath:     req.VideoStoragePath,
		VideoURL:             req.VideoURL,
		VideoDurationSeconds: req.VideoDurationSeconds,
		Questions:            req.Questions,
		PassMark:             req.PassMark,
		Published:            req.Published,
		CreatedAt:            createdAt,
		UpdatedAt:            now,
	}
	if _, err := ref.Set(ctx, module); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}

	httpjson.WriteJSON(w, http.StatusOK, adminModule{ModuleID: req.ModuleID, TrainingModule: module})
}

type deleteModuleRequest struct {
	ModuleID string `json:"moduleId"`
}

func deleteTrainingModule(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !isAdmin(ctx) {
		httpjson.WriteError(w, http.StatusForbidden, "NOT_ADMIN", "Admin claim required")
		return
	}
	var req deleteModuleRequest
	if !httpjson.DecodeJSON(w, r, &req) {
		return
	}
	if req.ModuleID == "" {
		httpjson.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "moduleId is required")
		return
	}
	db, err := fsDB(ctx)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "firestore client unavailable")
		return
	}
	// Per-practitioner progress documents are deliberately left in place: they
	// are the record that someone completed this training, and deleting a
	// module shouldn't rewrite that history.
	if _, err := db.Collection(trainingCollection).Doc(req.ModuleID).Delete(ctx); err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		return
	}
	httpjson.WriteJSON(w, http.StatusOK, map[string]any{"moduleId": req.ModuleID, "deleted": true})
}

// ─── Shared helpers ──────────────────────────────────────────────────────────

type moduleWithID struct {
	ID     string
	Module TrainingModule
}

// loadModules returns modules ordered by their author-assigned order, then id
// so the sequence is stable when two modules share an order.
func loadModules(ctx context.Context, db *firestore.Client, includeUnpublished bool) ([]moduleWithID, error) {
	iter := db.Collection(trainingCollection).Documents(ctx)
	defer iter.Stop()

	var out []moduleWithID
	for {
		snap, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return nil, err
		}
		var m TrainingModule
		if err := snap.DataTo(&m); err != nil {
			return nil, err
		}
		if !includeUnpublished && !m.Published {
			continue
		}
		out = append(out, moduleWithID{ID: snap.Ref.ID, Module: m})
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Module.Order != out[j].Module.Order {
			return out[i].Module.Order < out[j].Module.Order
		}
		return out[i].ID < out[j].ID
	})
	return out, nil
}

func getPublishedModule(ctx context.Context, db *firestore.Client, moduleID string) (TrainingModule, error) {
	var m TrainingModule
	snap, err := db.Collection(trainingCollection).Doc(moduleID).Get(ctx)
	if status.Code(err) == codes.NotFound {
		return m, errModuleNotFound
	}
	if err != nil {
		return m, err
	}
	if err := snap.DataTo(&m); err != nil {
		return m, err
	}
	if !m.Published {
		return m, errModuleUnpublish
	}
	return m, nil
}

// progressRef keeps progress under the practitioner's own profile document,
// matching how fcmTokens is already nested, so ownership is expressed by the
// path rather than by a field on a top-level collection.
func progressRef(db *firestore.Client, uid, moduleID string) *firestore.DocumentRef {
	return db.Collection("profiles").Doc(uid).Collection("trainingProgress").Doc(moduleID)
}

func readProgress(ctx context.Context, ref *firestore.DocumentRef) (*TrainingProgress, error) {
	snap, err := ref.Get(ctx)
	if status.Code(err) == codes.NotFound {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var p TrainingProgress
	if err := snap.DataTo(&p); err != nil {
		return nil, err
	}
	return &p, nil
}

func loadProgress(ctx context.Context, db *firestore.Client, uid string) (map[string]*TrainingProgress, error) {
	iter := db.Collection("profiles").Doc(uid).Collection("trainingProgress").Documents(ctx)
	defer iter.Stop()

	out := map[string]*TrainingProgress{}
	for {
		snap, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return nil, err
		}
		var p TrainingProgress
		if err := snap.DataTo(&p); err != nil {
			return nil, err
		}
		out[snap.Ref.ID] = &p
	}
	return out, nil
}

func completedCount(progress map[string]*TrainingProgress) int {
	n := 0
	for _, p := range progress {
		if p != nil && p.Status == TrainingCompleted {
			n++
		}
	}
	return n
}

func writeTrainingError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, errModuleNotFound):
		httpjson.WriteError(w, http.StatusNotFound, "MODULE_NOT_FOUND", "Training module not found")
	case errors.Is(err, errModuleUnpublish):
		httpjson.WriteError(w, http.StatusNotFound, "MODULE_NOT_PUBLISHED", "Training module is not available")
	case errors.Is(err, errModuleNoQuiz):
		httpjson.WriteError(w, http.StatusConflict, "MODULE_NO_QUIZ", "This module has no knowledge check yet")
	default:
		httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
	}
}

// ─── Training gate ───────────────────────────────────────────────────────────

// trainingConfigDoc holds platform-wide training settings. Kept in Firestore
// rather than as a constant so the gate can be turned on without a deploy:
// with only two modules published, blocking every application would strand
// practitioners, but that changes as the module set grows.
const trainingConfigDoc = "platformConfig/training"

type trainingConfig struct {
	// RequiredModuleIDs must all be completed before a practitioner may apply
	// for a shift. Empty (the default, and the current production value) means
	// no gate at all.
	RequiredModuleIDs []string `firestore:"requiredModuleIds,omitempty"`
}

// missingRequiredTraining returns the required module ids the user has not
// completed. An empty result means they may apply.
//
// Reads the completion summary from the profile document rather than the
// trainingProgress subcollection: it is one read instead of N, and it is the
// same field a nursery sees on the public profile, so the gate and the
// approval screen can never disagree about who has completed what.
func missingRequiredTraining(ctx context.Context, db *firestore.Client, uid string) ([]string, error) {
	cfgSnap, err := db.Doc(trainingConfigDoc).Get(ctx)
	if status.Code(err) == codes.NotFound {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var cfg trainingConfig
	if err := cfgSnap.DataTo(&cfg); err != nil {
		return nil, err
	}
	if len(cfg.RequiredModuleIDs) == 0 {
		return nil, nil
	}

	profSnap, err := db.Collection("profiles").Doc(uid).Get(ctx)
	if status.Code(err) == codes.NotFound {
		return cfg.RequiredModuleIDs, nil
	}
	if err != nil {
		return nil, err
	}
	var p Profile
	if err := profSnap.DataTo(&p); err != nil {
		return nil, err
	}
	done := make(map[string]bool, len(p.TrainingCompletedModuleIDs))
	for _, id := range p.TrainingCompletedModuleIDs {
		done[id] = true
	}

	var missing []string
	for _, id := range cfg.RequiredModuleIDs {
		if !done[id] {
			missing = append(missing, id)
		}
	}
	return missing, nil
}
