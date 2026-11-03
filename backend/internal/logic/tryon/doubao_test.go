package tryon

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

// A false boolean with omitempty silently restores the provider's watermark default.
func TestDoubaoExplicitlyDisablesWatermark(t *testing.T) {
	called := false
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		called = true
		if r.Method != http.MethodPost || r.URL.Path != "/images/generations" {
			t.Errorf("unexpected image generation request")
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		var body map[string]json.RawMessage
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Error(err)
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		if value, present := body["watermark"]; !present || string(value) != "false" {
			t.Error("provider must receive an explicit watermark:false")
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"data":[{"b64_json":"aW1hZ2U="}]}`))
	}))
	defer server.Close()

	gen := NewDoubao(&ModelConfig{APIKey: "test-key", BaseURL: server.URL, Model: "seedream-test"})
	image, err := gen.Generate(context.Background(), "person", "garment", "try on", "1024x1536")
	if err != nil || image != "aW1hZ2U=" || !called {
		t.Fatalf("image generation request failed: %v", err)
	}
}
