package function

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"sync"

	"cloud.google.com/go/firestore"
	"cloud.google.com/go/pubsub/v2"
	"cloud.google.com/go/pubsub/v2/apiv1/pubsubpb"
	firebase "firebase.google.com/go/v4"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"bridgeflex/shared/auth"
	"bridgeflex/shared/fbapp"
	"bridgeflex/shared/httpjson"
)

// geohashPrecision controls how coarse profilesPublic.locationArea is — see
// ARCHITECTURE.md v2 §2. 4 chars is city-sized (~39km x 19.5km), deliberately
// not street-level.
const geohashPrecision = 4

// Pub/Sub topic names — the contract between services (ARCHITECTURE.md v2 §1).
const (
	topicShiftBooked    = "shift-booked"
	topicShiftMatched   = "shift-matched"
	topicRatingReceived = "rating-received"
)

var (
	fsOnce   sync.Once
	fsClient *firestore.Client
	fsErr    error

	pubOnce   sync.Once
	pubClient *pubsub.Client
	pubErr    error
)

func adminApp(ctx context.Context) (*firebase.App, error) {
	return fbapp.New(ctx)
}

// authed wraps an HTTP handler with the shared RequireAuth middleware — the
// no-onCall replacement described in ARCHITECTURE.md v2 §1a. Every
// client-callable endpoint in this service is registered via
// functions.HTTP(name, authed(handler)).
func authed(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		app, err := adminApp(r.Context())
		if err != nil {
			httpjson.WriteError(w, http.StatusInternalServerError, "INTERNAL", "auth app init failed")
			return
		}
		auth.RequireAuth(app, next)(w, r)
	}
}

// fsDB returns the process-wide Firestore client, auto-detecting
// FIRESTORE_EMULATOR_HOST the same way the Admin App does.
func fsDB(ctx context.Context) (*firestore.Client, error) {
	fsOnce.Do(func() {
		app, err := fbapp.New(ctx)
		if err != nil {
			fsErr = err
			return
		}
		fsClient, fsErr = app.Firestore(ctx)
	})
	return fsClient, fsErr
}

func projectID() string {
	if p := os.Getenv("GCLOUD_PROJECT"); p != "" {
		return p
	}
	return "demo-bridgeflex"
}

func pubsubDB(ctx context.Context) (*pubsub.Client, error) {
	pubOnce.Do(func() {
		pubClient, pubErr = pubsub.NewClient(ctx, projectID())
	})
	return pubClient, pubErr
}

// ensureTopic idempotently creates topicID if it doesn't already exist yet.
// Real deploys create topics via infra config ahead of time; auto-creating
// here just removes a manual setup step for local emulator development.
func ensureTopic(ctx context.Context, topicID string) error {
	client, err := pubsubDB(ctx)
	if err != nil {
		return err
	}
	_, err = client.TopicAdminClient.CreateTopic(ctx, &pubsubpb.Topic{
		Name: fmt.Sprintf("projects/%s/topics/%s", projectID(), topicID),
	})
	if err != nil && status.Code(err) != codes.AlreadyExists {
		return err
	}
	return nil
}

// publish marshals payload as JSON and publishes it to topicID, blocking
// until the publish is acknowledged. Always called AFTER a Firestore commit
// succeeds, never from inside the transaction itself — Pub/Sub publish isn't
// part of Firestore's transactional guarantee (ARCHITECTURE.md v2 §4/§1).
func publish(ctx context.Context, topicID string, payload any) error {
	if err := ensureTopic(ctx, topicID); err != nil {
		return err
	}
	client, err := pubsubDB(ctx)
	if err != nil {
		return err
	}
	data, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	pub := client.Publisher(topicID)
	defer pub.Stop()
	result := pub.Publish(ctx, &pubsub.Message{Data: data})
	_, err = result.Get(ctx)
	return err
}
