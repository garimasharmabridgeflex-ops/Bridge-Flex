// Command core runs one HTTP- or CloudEvent-triggered function from the
// kvision.internal/core/function package locally via functions-framework-go.
// FUNCTION_TARGET picks which registered function to serve (e.g.
// "AcceptShift", "SyncProfilePublic") — see ARCHITECTURE.md v2 §1a/§7 for why
// this is N separate local processes rather than one unified emulator.
package main

import (
	"log"
	"os"

	"github.com/GoogleCloudPlatform/functions-framework-go/funcframework"

	_ "kvision.internal/core/function"
)

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8081"
	}
	if err := funcframework.Start(port); err != nil {
		log.Fatalf("funcframework.Start: %v", err)
	}
}
