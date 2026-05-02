// HTTP echo server benchmark — respond with fixed JSON
// Measure with: wrk -t2 -c100 -d5s http://localhost:8080/
package main

import (
	"fmt"
	"net/http"
	"os"
)

func handler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.Write([]byte(`{"status":"ok","count":42}`))
}

func main() {
	http.HandleFunc("/", handler)
	fmt.Fprintln(os.Stderr, "Go http_echo listening on :8080")
	http.ListenAndServe(":8080", nil)
}
