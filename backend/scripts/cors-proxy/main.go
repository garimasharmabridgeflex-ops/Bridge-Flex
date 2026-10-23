package main

import (
	"crypto/tls"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
)

func main() {
	target, err := url.Parse("https://europe-west2-kvision-503115.cloudfunctions.net")
	if err != nil {
		log.Fatalf("invalid target URL: %v", err)
	}

	proxy := httputil.NewSingleHostReverseProxy(target)
	proxy.Transport = &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	}
	originalDirector := proxy.Director
	proxy.Director = func(req *http.Request) {
		originalDirector(req)
		req.Host = target.Host
	}
	proxy.ModifyResponse = func(resp *http.Response) error {
		resp.Header.Set("Access-Control-Allow-Origin", "*")
		resp.Header.Set("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
		resp.Header.Set("Access-Control-Allow-Headers", "*")
		return nil
	}

	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "*")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		proxy.ServeHTTP(w, r)
	})

	log.Println("CORS proxy listening on 0.0.0.0:8089 -> https://europe-west2-kvision-503115.cloudfunctions.net")
	if err := http.ListenAndServe("0.0.0.0:8089", handler); err != nil {
		log.Fatalf("listen error: %v", err)
	}
}
