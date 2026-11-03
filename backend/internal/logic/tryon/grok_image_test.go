package tryon

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gogf/gf/v2/frame/g"
	"github.com/gogf/gf/v2/os/gcfg"
)

func TestGrokMultiImageEdit(t *testing.T) {
	const png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAAB"
	const jpeg = "/9j/AA=="
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost || r.URL.Path != "/v1/images/edits" {
			t.Errorf("must use image editing, got %s %s", r.Method, r.URL.Path)
		}
		if r.Header.Get("Authorization") != "Bearer test-key" || r.URL.RawQuery != "" {
			t.Error("credential must be sent only in the authorization header")
		}
		var body struct {
			Images         []struct{ Type, URL string }
			ResponseFormat string `json:"response_format"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Fatal(err)
		}
		if len(body.Images) != 2 {
			t.Fatalf("expected two reference images, got %d", len(body.Images))
		}
		if body.Images[0].URL != "data:image/jpeg;base64,"+jpeg || body.Images[1].URL != "data:image/png;base64,"+png {
			t.Error("reference order and actual MIME types must be preserved")
		}
		if body.ResponseFormat != "b64_json" {
			t.Error("must request inline image output")
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"data": []map[string]string{{"b64_json": png}}})
	}))
	defer server.Close()
	gen := NewOpenAIImages(&ModelConfig{Name: "grok", Model: "grok-imagine-image-2.0", APIKey: "test-key", BaseURL: server.URL + "/v1"})
	result, err := gen.Generate(context.Background(), jpeg, png, "change outfit", "1024x1536")
	if err != nil || result != png {
		t.Fatalf("unexpected image result: %v", err)
	}
}

func TestGrokEnvironmentConfiguration(t *testing.T) {
	adapter, err := gcfg.NewAdapterContent(`
llm:
  models:
    unused:
      provider: openai
`)
	if err != nil {
		t.Fatal(err)
	}
	previous := g.Cfg().GetAdapter()
	g.Cfg().SetAdapter(adapter)
	t.Cleanup(func() { g.Cfg().SetAdapter(previous) })
	t.Setenv("XAI_API_KEY", "test-key")
	t.Setenv("GROK_MODELS_BASE_URL", "https://proxy.example/v1/")
	t.Setenv("GROK_IMAGE_MODEL", "grok-imagine-image-2.0")
	cfg, err := loadModelConfig(context.Background(), "grok")
	if err != nil {
		t.Fatal(err)
	}
	if cfg.APIKey != "test-key" || cfg.BaseURL != "https://proxy.example/v1" || cfg.Model != "grok-imagine-image-2.0" || cfg.Provider != "openai" {
		t.Fatal("Grok must load environment configuration without requiring a local YAML entry")
	}
}

func TestGrokDoesNotExposeProviderErrorBody(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadGateway)
		_, _ = w.Write([]byte("sensitive-provider-detail"))
	}))
	defer server.Close()
	gen := NewOpenAIImages(&ModelConfig{Name: "grok", Model: "grok-imagine-image-2.0", APIKey: "test-key", BaseURL: server.URL})
	_, err := gen.Generate(context.Background(), "iVBORw0KGgoAAAANSUhEUgAAAAEAAAAB", "iVBORw0KGgoAAAANSUhEUgAAAAEAAAAB", "prompt", "")
	if err == nil || !strings.Contains(err.Error(), "502") || strings.Contains(err.Error(), "sensitive-provider-detail") {
		t.Fatal("provider error must report status without exposing its body")
	}
}
