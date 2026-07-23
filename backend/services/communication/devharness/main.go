// Command devharness runs functions-communication's Pub/Sub-triggered
// handlers (onShiftBooked, onRatingReceived, onShiftMatched,
// onShiftCancelled) against the live Pub/Sub *emulator*, since Eventarc
// itself has no local dispatch path (ARCHITECTURE.md v2 §7). Unlike
// services/core/devharness (which has to hand-construct Firestore
// CloudEvent payloads from snapshot listeners), this one is simpler: the
// messages it needs already exist as real Pub/Sub messages, published by
// functions-core's acceptShift/cancelShift/recomputeRating/matchNewShift —
// this just creates emulator subscriptions on the four topics, pulls each
// message, and calls the *actual* exported handler function
// (bridgeflex/communication/function.OnShiftBooked etc, see
// devharness_exports.go in that package), not a reimplementation of it.
//
// Optional — see the identical note in services/core/devharness/main.go.
package main

import (
	"context"
	"encoding/json"
	"log"
	"os"

	"cloud.google.com/go/pubsub/v2"
	"cloud.google.com/go/pubsub/v2/apiv1/pubsubpb"
	"github.com/cloudevents/sdk-go/v2/event"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	commfunc "bridgeflex/communication/function"
)

type topicHandler struct {
	topic   string
	handler func(context.Context, event.Event) error
}

func main() {
	ctx := context.Background()
	projectID := os.Getenv("GCLOUD_PROJECT")
	if projectID == "" {
		projectID = "demo-bridgeflex"
	}
	if os.Getenv("PUBSUB_EMULATOR_HOST") == "" {
		log.Fatal("PUBSUB_EMULATOR_HOST must be set — this only ever targets the emulator")
	}

	client, err := pubsub.NewClient(ctx, projectID)
	if err != nil {
		log.Fatalf("pubsub.NewClient: %v", err)
	}
	defer client.Close()

	targets := []topicHandler{
		{"shift-booked", commfunc.OnShiftBooked},
		{"rating-received", commfunc.OnRatingReceived},
		{"shift-matched", commfunc.OnShiftMatched},
		{"shift-cancelled", commfunc.OnShiftCancelled},
	}

	log.Println("devharness (communication): subscribing to shift-booked/rating-received/shift-matched/shift-cancelled on the Pub/Sub emulator...")

	for _, target := range targets {
		subID, err := ensureSubscription(ctx, client, target.topic)
		if err != nil {
			log.Fatalf("devharness: ensure subscription for %s: %v", target.topic, err)
		}
		go consume(ctx, client, subID, target.handler)
	}

	select {} // block forever; Ctrl+C stops the process
}

// ensureSubscription creates a devharness-owned pull subscription on
// topicName if one doesn't already exist, and creates the topic itself too
// (mirrors ensureTopic in functions-core/function/context.go — the
// publisher side already does this when it first publishes, but devharness
// may start before any publish has happened).
func ensureSubscription(ctx context.Context, client *pubsub.Client, topicName string) (string, error) {
	topicPath := "projects/" + client.Project() + "/topics/" + topicName
	_, err := client.TopicAdminClient.CreateTopic(ctx, &pubsubpb.Topic{Name: topicPath})
	if err != nil && status.Code(err) != codes.AlreadyExists {
		return "", err
	}

	subID := "devharness-" + topicName
	subPath := "projects/" + client.Project() + "/subscriptions/" + subID
	_, err = client.SubscriptionAdminClient.CreateSubscription(ctx, &pubsubpb.Subscription{
		Name:  subPath,
		Topic: topicPath,
	})
	if err != nil && status.Code(err) != codes.AlreadyExists {
		return "", err
	}
	return subID, nil
}

// consume pulls messages off subID forever, wrapping each in the same
// messagePublishedData CloudEvent envelope the real Pub/Sub-triggered
// functions expect (see communication/function/triggers.go), and calling
// the real handler directly.
func consume(ctx context.Context, client *pubsub.Client, subID string, handle func(context.Context, event.Event) error) {
	sub := client.Subscriber(subID)
	err := sub.Receive(ctx, func(ctx context.Context, msg *pubsub.Message) {
		e, err := pubsubMessageEvent(subID, msg.Data)
		if err != nil {
			log.Printf("devharness: %s: build event: %v", subID, err)
			msg.Nack()
			return
		}
		if err := handle(ctx, e); err != nil {
			log.Printf("devharness: %s: handler error: %v", subID, err)
			msg.Nack()
			return
		}
		log.Printf("devharness: %s: handled message", subID)
		msg.Ack()
	})
	if err != nil {
		log.Printf("devharness: %s: Receive stopped: %v", subID, err)
	}
}

// messagePublishedData mirrors the type of the same name in
// communication/function/triggers.go — duplicated here rather than
// exported from that package, since it's a private wire-shape detail, not
// part of the handler contract devharness_exports.go deliberately exposes.
type messagePublishedData struct {
	Message struct {
		Data []byte `json:"data"`
	} `json:"message"`
}

func pubsubMessageEvent(topicID string, data []byte) (event.Event, error) {
	msg := messagePublishedData{}
	msg.Message.Data = data
	payload, err := json.Marshal(msg)
	if err != nil {
		return event.Event{}, err
	}
	e := event.New()
	e.SetType("google.cloud.pubsub.topic.v1.messagePublished")
	e.SetSource("//pubsub.googleapis.com/" + topicID)
	if err := e.SetData("application/json", payload); err != nil {
		return event.Event{}, err
	}
	return e, nil
}
