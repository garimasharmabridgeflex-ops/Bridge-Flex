package main

import (
	"crypto/tls"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
)

func main() {
	cloudTarget, err := url.Parse("https://europe-west2-kvision-503115.cloudfunctions.net")
	if err != nil {
		log.Fatalf("invalid target URL: %v", err)
	}

	cloudProxy := httputil.NewSingleHostReverseProxy(cloudTarget)
	cloudProxy.Transport = &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	}
	originalDirector := cloudProxy.Director
	cloudProxy.Director = func(req *http.Request) {
		originalDirector(req)
		req.Host = cloudTarget.Host
	}
	cloudProxy.ModifyResponse = func(resp *http.Response) error {
		// Clean up any existing CORS headers from upstream to avoid duplicates
		resp.Header.Del("Access-Control-Allow-Origin")
		resp.Header.Del("Access-Control-Allow-Methods")
		resp.Header.Del("Access-Control-Allow-Headers")
		resp.Header.Del("Access-Control-Allow-Credentials")

		resp.Header.Set("Access-Control-Allow-Origin", "*")
		resp.Header.Set("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
		resp.Header.Set("Access-Control-Allow-Headers", "*")
		return nil
	}

	cloudProxy.ErrorHandler = func(w http.ResponseWriter, req *http.Request, err error) {
		log.Printf("proxy error for %s %s: %v", req.Method, req.URL.Path, err)
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "*")
		http.Error(w, err.Error(), http.StatusBadGateway)
	}

	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodOptions {
			w.Header().Set("Access-Control-Allow-Origin", "*")
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
			w.Header().Set("Access-Control-Allow-Headers", "*")
			w.WriteHeader(http.StatusNoContent)
			return
		}

		// Forward requests directly to live GCP Cloud Functions
		cloudProxy.ServeHTTP(w, r)
	})

	log.Println("CORS Proxy listening on 0.0.0.0:8089 (Forwarding 100% to live GCP Cloud Functions)")
	if err := http.ListenAndServe("0.0.0.0:8089", handler); err != nil {
		log.Fatalf("listen error: %v", err)
	}
}

