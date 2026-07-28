// Command communication runs one HTTP- or CloudEvent-triggered function from
// the kvision.internal/communication/function package locally via
// functions-framework-go. See ARCHITECTURE.md v2 §1a/§7.
package main

import (
	"log"
	"os"

	"github.com/GoogleCloudPlatform/functions-framework-go/funcframework"

	_ "kvision.internal/communication/function"
)

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8083"
	}
	if err := funcframework.Start(port); err != nil {
		log.Fatalf("funcframework.Start: %v", err)
	}
}
