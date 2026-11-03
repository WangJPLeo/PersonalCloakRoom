package tryon

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gogf/gf/v2/frame/g"
	"github.com/gogf/gf/v2/os/gcfg"
)

func TestGeminiEnvironmentOverrides(t *testing.T) {
	adapter, err := gcfg.NewAdapterContent(`
llm:
  models:
    gemini:
      provider: gemini
      apiKey: "test-key"
      baseURL: "https://default.example/v1beta"
      model: "default-image-model"
    other:
      provider: openai
      apiKey: "test-key"
      baseURL: "https://other.example/v1"
      model: "other-image-model"
`)
	if err != nil {
		t.Fatal(err)
	}
	previous := g.Cfg().GetAdapter()
	g.Cfg().SetAdapter(adapter)
	t.Cleanup(func() { g.Cfg().SetAdapter(previous) })
	t.Setenv("GEMINI_MODEL", "custom-model")
	for _, tc := range []struct{ base, want string }{
		{"https://proxy.example/", "https://proxy.example/v1beta"},
		{"https://proxy.example/v1beta/", "https://proxy.example/v1beta"},
		{"https://proxy.example/custom/v1beta", "https://proxy.example/custom/v1beta"},
		{"", "https://default.example/v1beta"},
	} {
		t.Run(tc.base, func(t *testing.T) {
			t.Setenv("GOOGLE_GEMINI_BASE_URL", tc.base)
			cfg, err := loadModelConfig(context.Background(), "gemini")
			if err != nil {
				t.Fatal(err)
			}
			if cfg.BaseURL != tc.want || cfg.Model != "custom-model" {
				t.Fatalf("unexpected endpoint/model: %s / %s", cfg.BaseURL, cfg.Model)
			}
		})
	}
	t.Setenv("GOOGLE_GEMINI_BASE_URL", "https://proxy.example")
	cfg, err := loadModelConfig(context.Background(), "other")
	if err != nil {
		t.Fatal(err)
	}
	if cfg.BaseURL != "https://other.example/v1" || cfg.Model != "other-image-model" {
		t.Fatal("Gemini environment overrides must not affect other aliases")
	}
	t.Setenv("GEMINI_MODEL", "")
	t.Setenv("GOOGLE_GEMINI_BASE_URL", "")
	cfg, err = loadModelConfig(context.Background(), "gemini")
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Model != "default-image-model" {
		t.Fatal("empty environment must preserve the configured model")
	}
}

func TestGeminiSendsKeyInHeaderNotURL(t *testing.T) {
	const apiKey = "secret-test-key"
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if got := r.URL.Query().Get("key"); got != "" {
			t.Fatalf("API key must not be sent in URL query, got %q", got)
		}
		if got := r.Header.Get("x-goog-api-key"); got != apiKey {
			t.Fatalf("expected API key header, got %q", got)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"candidates":[{"content":{"parts":[{"inlineData":{"mimeType":"image/png","data":"aW1hZ2U="}}]}}]}`))
	}))
	defer server.Close()

	gen := NewGemini(&ModelConfig{
		Name:    "browser-custom",
		APIKey:  apiKey,
		BaseURL: server.URL,
		Model:   "test-model",
	})
	result, err := gen.Generate(context.Background(), "cGVyc29u", "Z2FybWVudA==", "prompt", "1024x1536")
	if err != nil {
		t.Fatalf("Generate returned error: %v", err)
	}
	if result != "aW1hZ2U=" {
		t.Fatalf("unexpected image result: %q", result)
	}
}
