// Command payments runs the functions-payments stub locally via
// functions-framework-go. See services/payments/TODO.md.
package main

import (
	"log"
	"os"

	"github.com/GoogleCloudPlatform/functions-framework-go/funcframework"

	_ "bridgeflex/payments/function"
)

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8093"
	}
	if err := funcframework.Start(port); err != nil {
		log.Fatalf("funcframework.Start: %v", err)
	}
}
