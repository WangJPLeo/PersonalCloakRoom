package tryon

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"

	"github.com/gogf/gf/v2/frame/g"
	"github.com/gogf/gf/v2/os/gcfg"
)

func useDoubaoTestConfig(t *testing.T, content string) {
	t.Helper()
	adapter, err := gcfg.NewAdapterContent(content)
	if err != nil {
		t.Fatal(err)
	}
	previous := g.Cfg().GetAdapter()
	g.Cfg().SetAdapter(adapter)
	t.Cleanup(func() { g.Cfg().SetAdapter(previous) })
	t.Setenv("ARK_API_KEY", "")
	t.Setenv("ARK_MODEL", "")
}

func TestDoubaoEnvironmentWithoutModelEntry(t *testing.T) {
	useDoubaoTestConfig(t, "llm:\n  models: {}\n")
	t.Setenv("ARK_API_KEY", "test-ark-key")
	cfg, err := loadModelConfig(context.Background(), "doubao")
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Provider != "doubao" || cfg.Name != "doubao" || cfg.APIKey != "test-ark-key" ||
		cfg.BaseURL != "https://ark.cn-beijing.volces.com/api/v3" || cfg.Model != "doubao-seedream-5-0-flash-260915" {
		t.Fatal("environment-only deployment must resolve the Ark Seedream 5.0 adapter")
	}
}

func TestDoubaoMissingKeyHasActionableError(t *testing.T) {
	useDoubaoTestConfig(t, "llm:\n  models: {}\n")
	_, err := NewGenerator(context.Background(), "doubao")
	if err == nil || !strings.Contains(err.Error(), "未配置 API Key") {
		t.Fatal("missing Ark credentials must be reported as a missing key, not an unknown model")
	}
}

func TestDoubaoExplicitModelAndCustomKeyEnvironment(t *testing.T) {
	useDoubaoTestConfig(t, `
llm:
  models:
    doubao:
      provider: doubao
      envKey: CUSTOM_ARK_TEST_KEY
      baseURL: https://ark-proxy.example/api/v3
      model: custom-seedream-model
`)
	t.Setenv("ARK_API_KEY", "standard-test-key")
	t.Setenv("CUSTOM_ARK_TEST_KEY", "custom-test-key")
	cfg, err := loadModelConfig(context.Background(), "doubao")
	if err != nil {
		t.Fatal(err)
	}
	if cfg.APIKey != "custom-test-key" || cfg.Model != "custom-seedream-model" || cfg.BaseURL != "https://ark-proxy.example/api/v3" {
		t.Fatal("explicit model configuration and custom envKey must be preserved")
	}
}

func TestDoubaoModelEntryWithoutEnvKey(t *testing.T) {
	useDoubaoTestConfig(t, `
llm:
  models:
    doubao:
      provider: doubao
      baseURL: https://ark.cn-beijing.volces.com/api/v3
      model: configured-seedream-model
    other:
      provider: openai
      apiKey: other-test-key
      baseURL: https://other.example/v1
      model: other-model
`)
	t.Setenv("ARK_API_KEY", "test-ark-key")
	t.Setenv("ARK_MODEL", "  deployment-seedream-model  ")
	cfg, err := loadModelConfig(context.Background(), "doubao")
	if err != nil {
		t.Fatal(err)
	}
	if cfg.APIKey != "test-ark-key" || cfg.Model != "deployment-seedream-model" {
		t.Fatal("old model entries must accept the standard Ark environment configuration")
	}
	other, err := loadModelConfig(context.Background(), "other")
	if err != nil {
		t.Fatal(err)
	}
	if other.Model != "other-model" || other.APIKey != "other-test-key" {
		t.Fatal("Ark environment settings must not affect other model aliases")
	}
}

func TestDoubaoLegacyConfiguration(t *testing.T) {
	useDoubaoTestConfig(t, `
llm:
  doubao:
    apiKey: legacy-test-key
    baseURL: https://legacy-ark.example/api/v3
    model: legacy-seedream-model
`)
	cfg, err := loadModelConfig(context.Background(), "doubao")
	if err != nil {
		t.Fatal(err)
	}
	if cfg.APIKey != "legacy-test-key" || cfg.BaseURL != "https://legacy-ark.example/api/v3" || cfg.Model != "legacy-seedream-model" {
		t.Fatal("legacy Ark configuration must be preserved")
	}
}

func TestDoubaoTemplateUsesSeedreamFive(t *testing.T) {
	content, err := os.ReadFile("../../../manifest/config/config.example.yaml")
	if err != nil {
		t.Fatal(err)
	}
	useDoubaoTestConfig(t, string(content))
	t.Setenv("ARK_API_KEY", "template-test-key")
	cfg, err := loadModelConfig(context.Background(), "doubao")
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Model != "doubao-seedream-5-0-flash-260915" || cfg.BaseURL != "https://ark.cn-beijing.volces.com/api/v3" || cfg.Provider != "doubao" {
		t.Fatal("the distributed configuration must match the supported Ark defaults")
	}
}

func TestDoubaoFallbackSendsConfiguredArkRequest(t *testing.T) {
	called := false
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		called = true
		if r.URL.Path != "/images/generations" || r.Method != http.MethodPost || r.Header.Get("Authorization") != "Bearer test-ark-key" {
			t.Error("factory fallback must send an authenticated Ark generation request")
		}
		var body struct {
			Model string `json:"model"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Error(err)
		}
		if body.Model != "doubao-seedream-5-0-flash-260915" {
			t.Error("the actual provider request must select Seedream 5.0")
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"data":[{"b64_json":"aW1hZ2U="}]}`))
	}))
	defer server.Close()
	useDoubaoTestConfig(t, "llm:\n  doubao:\n    baseURL: "+server.URL+"\n")
	t.Setenv("ARK_API_KEY", "test-ark-key")
	gen, err := NewGenerator(context.Background(), "doubao")
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := gen.(*Doubao); !ok {
		t.Fatal("doubao must use the Ark adapter rather than the OpenAI adapter")
	}
	image, err := gen.Generate(context.Background(), "person", "garment", "try on", "1024x1536")
	if err != nil || image != "aW1hZ2U=" || !called {
		t.Fatalf("mock Ark generation failed: %v", err)
	}
}
