package tryon

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestCustomDescriptionPrompt(t *testing.T) {
	for _, tc := range []struct{ name, base, lang string }{
		{"default-zh", BuildDefault("zh"), "zh"},
		{"default-en", BuildDefault("en"), "en"},
		{"gemini", BuildGemini("zh"), "zh"},
		{"gpt-zh", BuildGPTSafety("zh"), "zh"},
		{"gpt-en", BuildGPTSafety("en"), "en"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			for _, blank := range []string{"", " \n\t "} {
				prompt, err := WithCustomPrompt(tc.base, blank, tc.lang)
				if err != nil || prompt != tc.base {
					t.Fatal("blank description must preserve the original prompt")
				}
			}
			const description = "白色背景，坐在椅子上，柔和侧光"
			prompt, err := WithCustomPrompt(tc.base, " \n"+description+"\n ", tc.lang)
			if err != nil || strings.Count(prompt, description) != 1 {
				t.Fatalf("description must reach the prompt exactly once: %v", err)
			}
			for _, obsolete := range []string{
				"Keep the person's original pose, body angle and orientation as much as possible",
				"Keep the original background, lighting and overall mood",
				"尽量保持人物原有的姿势、身体角度和朝向",
				"保留人物照片原有的背景、光线和整体氛围",
				"upright standing posture", "端正站姿",
			} {
				if strings.Contains(prompt, obsolete) {
					t.Fatalf("description conflicts with the original rule: %s", obsolete)
				}
			}
			if !(strings.Contains(prompt, "identity") || strings.Contains(prompt, "人物身份") || strings.Contains(prompt, "模特身份")) {
				t.Fatal("identity constraints must be retained")
			}
		})
	}
	if _, err := WithCustomPrompt(enPrompt, strings.Repeat("字", 1000), "zh"); err != nil {
		t.Fatal("1000 Chinese characters must be accepted")
	}
	if _, err := WithCustomPrompt(enPrompt, strings.Repeat("字", 1001), "zh"); err == nil {
		t.Fatal("overlong description must be rejected")
	}
}

func TestGPTVisualAnalysisPreservesDescription(t *testing.T) {
	const description = "在绿色花园里坐着，柔和夕阳"
	prompt, err := WithCustomPrompt(BuildGPTSafety("zh"), description, "zh")
	if err != nil {
		t.Fatal(err)
	}
	var received string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case "/chat/completions":
			_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"An adult model and a blue coat."}}]}`))
		case "/images/generations":
			var body gptImageRequest
			if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
				t.Error(err)
				w.WriteHeader(http.StatusBadRequest)
				return
			}
			received = body.Prompt
			_, _ = w.Write([]byte(`{"data":[{"b64_json":"iVBORw0KGgoAAAANSUhEUgAAAAEAAAAB"}]}`))
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer server.Close()
	gen := NewOpenAIImages(&ModelConfig{Name: "gpt-image", Model: "gpt-image-2", APIKey: "test-key", BaseURL: server.URL})
	_, err = gen.Generate(context.Background(), "person", "garment", prompt, "1024x1536")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(received, description) || !strings.Contains(received, "An adult model and a blue coat.") || !strings.Contains(received, "穿着完整端庄") {
		t.Fatal("visual analysis must preserve the description and safety requirements")
	}
}
