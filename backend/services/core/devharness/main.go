// Command devharness runs the Eventarc-triggered handlers in functions-core
// (syncProfilePublic, recomputeRating, matchNewShift) against live changes
// on the Firestore *emulator*, since Eventarc itself has no local dispatch
// path (ARCHITECTURE.md v2 §7). It watches profiles/ratings/shifts directly
// via the Firestore Go client's realtime snapshot listeners — which work
// fine against the emulator even though Eventarc doesn't run locally — and
// on each relevant change, constructs the same DocumentEventData payload a
// real Eventarc delivery would carry and calls the *actual* exported
// handler function (kvision.internal/core/function.SyncProfilePublic etc, see
// devharness_exports.go in that package), not a reimplementation of it.
//
// Optional: only needed if you want profile edits, new ratings, and new
// shifts to cascade (profilesPublic sync, rating aggregate, shift-matched
// fan-out) during local testing. Run alongside `make dev` — see
// `make dev-with-triggers` in the root Makefile. Requires
// FIRESTORE_EMULATOR_HOST / GCLOUD_PROJECT set, same as any other local Go
// process here.
package main

import (
	"context"
	"log"
	"os"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/cloudevents/sdk-go/v2/event"
	"github.com/googleapis/google-cloudevents-go/cloud/firestoredata"
	"google.golang.org/genproto/googleapis/type/latlng"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"

	corefunc "kvision.internal/core/function"
)

func main() {
	ctx := context.Background()
	projectID := os.Getenv("GCLOUD_PROJECT")
	if projectID == "" {
		projectID = "demo-bridgeflex"
	}
	if os.Getenv("FIRESTORE_EMULATOR_HOST") == "" {
		log.Fatal("FIRESTORE_EMULATOR_HOST must be set — this only ever targets the emulator")
	}

	client, err := firestore.NewClient(ctx, projectID)
	if err != nil {
		log.Fatalf("firestore.NewClient: %v", err)
	}
	defer client.Close()

	log.Println("devharness (core): watching profiles/ratings/shifts on the Firestore emulator...")

	go watchCollection(ctx, client, "profiles", true, func(ctx context.Context, e event.Event) error {
		return corefunc.SyncProfilePublic(ctx, e)
	})
	go watchCollection(ctx, client, "ratings", false, func(ctx context.Context, e event.Event) error {
		return corefunc.RecomputeRating(ctx, e)
	})
	go watchCollection(ctx, client, "shifts", false, func(ctx context.Context, e event.Event) error {
		return corefunc.MatchNewShift(ctx, e)
	})

	select {} // block forever; Ctrl+C stops the process
}

// watchCollection listens for changes on a top-level collection and invokes
// handle for each one. includeModified controls whether updates (not just
// creates) count — profiles/{uid} writes should re-sync on every edit,
// matching the real `google.cloud.firestore.document.v1.written` trigger;
// ratings/shifts only care about creates, matching their real
// `google.cloud.firestore.document.v1.created` triggers.
func watchCollection(
	ctx context.Context,
	client *firestore.Client,
	collection string,
	includeModified bool,
	handle func(context.Context, event.Event) error,
) {
	it := client.Collection(collection).Snapshots(ctx)
	defer it.Stop()

	first := true
	for {
		snap, err := it.Next()
		if err != nil {
			log.Printf("devharness: %s watch error: %v (retrying in 2s)", collection, err)
			time.Sleep(2 * time.Second)
			continue
		}
		// The first snapshot delivers every existing doc as "added" — skip
		// it, or every doc already in Firestore at startup would re-fire.
		if first {
			first = false
			continue
		}
		for _, change := range snap.Changes {
			isCreate := change.Kind == firestore.DocumentAdded
			isUpdate := change.Kind == firestore.DocumentModified
			if !isCreate && !(includeModified && isUpdate) {
				continue
			}
			docPath := change.Doc.Ref.Path
			fields, err := toFirestoreValueMap(change.Doc.Data())
			if err != nil {
				log.Printf("devharness: %s: convert %s: %v", collection, docPath, err)
				continue
			}
			e, err := documentWrittenEvent(docPath, fields)
			if err != nil {
				log.Printf("devharness: %s: build event for %s: %v", collection, docPath, err)
				continue
			}
			if err := handle(ctx, e); err != nil {
				log.Printf("devharness: %s handler error for %s: %v", collection, docPath, err)
				continue
			}
			log.Printf("devharness: %s: handled %s", collection, docPath)
		}
	}
}

func documentWrittenEvent(docPath string, fields map[string]*firestoredata.Value) (event.Event, error) {
	data := &firestoredata.DocumentEventData{
		Value: &firestoredata.Document{
			Name:   docPath,
			Fields: fields,
		},
	}
	raw, err := proto.Marshal(data)
	if err != nil {
		return event.Event{}, err
	}
	e := event.New()
	e.SetType("google.cloud.firestore.document.v1.written")
	e.SetSource("//firestore.googleapis.com/projects/" + os.Getenv("GCLOUD_PROJECT") + "/databases/(default)")
	if err := e.SetData("application/protobuf", raw); err != nil {
		return event.Event{}, err
	}
	return e, nil
}

// toFirestoreValueMap converts a Firestore Go client's native
// map[string]interface{} (from DocumentSnapshot.Data()) into the
// map[string]*firestoredata.Value shape Eventarc's DocumentEventData
// carries — the handlers under test read fields via that protobuf shape
// (see e.g. syncProfilePublic's fieldString/fieldDouble/fieldGeo helpers in
// profiles.go), not the native Go map, so this conversion has to be exact.
func toFirestoreValueMap(data map[string]interface{}) (map[string]*firestoredata.Value, error) {
	out := make(map[string]*firestoredata.Value, len(data))
	for k, v := range data {
		val, err := toFirestoreValue(v)
		if err != nil {
			return nil, err
		}
		out[k] = val
	}
	return out, nil
}

func toFirestoreValue(v interface{}) (*firestoredata.Value, error) {
	switch t := v.(type) {
	case nil:
		return &firestoredata.Value{ValueType: &firestoredata.Value_NullValue{}}, nil
	case string:
		return &firestoredata.Value{ValueType: &firestoredata.Value_StringValue{StringValue: t}}, nil
	case bool:
		return &firestoredata.Value{ValueType: &firestoredata.Value_BooleanValue{BooleanValue: t}}, nil
	case int64:
		return &firestoredata.Value{ValueType: &firestoredata.Value_IntegerValue{IntegerValue: t}}, nil
	case int:
		return &firestoredata.Value{ValueType: &firestoredata.Value_IntegerValue{IntegerValue: int64(t)}}, nil
	case float64:
		return &firestoredata.Value{ValueType: &firestoredata.Value_DoubleValue{DoubleValue: t}}, nil
	case time.Time:
		return &firestoredata.Value{ValueType: &firestoredata.Value_TimestampValue{
			TimestampValue: timestamppb.New(t),
		}}, nil
	case *latlng.LatLng:
		return &firestoredata.Value{ValueType: &firestoredata.Value_GeoPointValue{GeoPointValue: t}}, nil
	case map[string]interface{}:
		fields, err := toFirestoreValueMap(t)
		if err != nil {
			return nil, err
		}
		return &firestoredata.Value{ValueType: &firestoredata.Value_MapValue{
			MapValue: &firestoredata.MapValue{Fields: fields},
		}}, nil
	case []interface{}:
		values := make([]*firestoredata.Value, 0, len(t))
		for _, item := range t {
			val, err := toFirestoreValue(item)
			if err != nil {
				return nil, err
			}
			values = append(values, val)
		}
		return &firestoredata.Value{ValueType: &firestoredata.Value_ArrayValue{
			ArrayValue: &firestoredata.ArrayValue{Values: values},
		}}, nil
	default:
		return &firestoredata.Value{ValueType: &firestoredata.Value_NullValue{}}, nil
	}
}
