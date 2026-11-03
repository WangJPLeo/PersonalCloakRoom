package tryon

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"image"
	"image/color"
	"image/png"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"

	"github.com/gogf/gf/v2/frame/g"
	"github.com/gogf/gf/v2/net/ghttp"
	"github.com/gogf/gf/v2/os/gcfg"

	"backend/api/tryon/v1"
	"backend/internal/middleware"
	"backend/internal/security"
)

func createTestPNG(w, h int) string {
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	for x := 0; x < w; x++ {
		for y := 0; y < h; y++ {
			img.Set(x, y, color.RGBA{R: 200, G: 100, B: 50, A: 255})
		}
	}
	var buf bytes.Buffer
	_ = png.Encode(&buf, img)
	return base64.StdEncoding.EncodeToString(buf.Bytes())
}

func TestControllerTryonImageValidation(t *testing.T) {
	// 启动测试服务
	s := g.Server("test-ctrl-tryon")
	s.Group("/", func(group *ghttp.RouterGroup) {
		group.Middleware(middleware.RequestID)
		group.Bind(NewV1())
	})
	s.SetPort(0)
	_ = s.Start()
	defer s.Shutdown()

	port := strings.Split(s.GetListenedAddress(), ":")[1]
	client := &http.Client{}

	// 1. 无效 Base64
	badReq := v1.TryonReq{
		PersonImage:  "!!not-valid-base64!!",
		GarmentImage: createTestPNG(300, 300),
	}
	badBody, _ := json.Marshal(badReq)
	req1, _ := http.NewRequest(http.MethodPost, "http://127.0.0.1:"+port+"/tryon", bytes.NewReader(badBody))
	req1.Header.Set("Content-Type", "application/json")
	resp1, err := client.Do(req1)
	if err != nil {
		t.Fatal(err)
	}
	defer resp1.Body.Close()
	if resp1.StatusCode != 422 {
		t.Fatalf("expected 422, got %d", resp1.StatusCode)
	}
	b1, _ := io.ReadAll(resp1.Body)
	var res1 struct {
		Code int `json:"code"`
		Data struct {
			ErrorCode string `json:"error_code"`
		} `json:"data"`
	}
	_ = json.Unmarshal(b1, &res1)
	if res1.Code != 42201 || res1.Data.ErrorCode != "INVALID_IMAGE_BASE64" {
		t.Fatalf("unexpected res1: %+v", res1)
	}

	// 2. 文本图片（不支持类型）
	textB64 := base64.StdEncoding.EncodeToString([]byte("plain text not image"))
	textReq := v1.TryonReq{
		PersonImage:  textB64,
		GarmentImage: createTestPNG(300, 300),
	}
	textBody, _ := json.Marshal(textReq)
	req2, _ := http.NewRequest(http.MethodPost, "http://127.0.0.1:"+port+"/tryon", bytes.NewReader(textBody))
	req2.Header.Set("Content-Type", "application/json")
	resp2, err := client.Do(req2)
	if err != nil {
		t.Fatal(err)
	}
	defer resp2.Body.Close()
	if resp2.StatusCode != 422 {
		t.Fatalf("expected 422, got %d", resp2.StatusCode)
	}
	b2, _ := io.ReadAll(resp2.Body)
	var res2 struct {
		Code int `json:"code"`
		Data struct {
			ErrorCode string `json:"error_code"`
		} `json:"data"`
	}
	_ = json.Unmarshal(b2, &res2)
	if res2.Code != 42202 || res2.Data.ErrorCode != "UNSUPPORTED_IMAGE_TYPE" {
		t.Fatalf("unexpected res2: %+v", res2)
	}

	// 3. 尺寸过小
	smallB64 := createTestPNG(100, 100)
	smallReq := v1.TryonReq{
		PersonImage:  smallB64,
		GarmentImage: createTestPNG(300, 300),
	}
	smallBody, _ := json.Marshal(smallReq)
	req3, _ := http.NewRequest(http.MethodPost, "http://127.0.0.1:"+port+"/tryon", bytes.NewReader(smallBody))
	req3.Header.Set("Content-Type", "application/json")
	resp3, err := client.Do(req3)
	if err != nil {
		t.Fatal(err)
	}
	defer resp3.Body.Close()
	if resp3.StatusCode != 422 {
		t.Fatalf("expected 422, got %d", resp3.StatusCode)
	}
	b3, _ := io.ReadAll(resp3.Body)
	var res3 struct {
		Code int `json:"code"`
		Data struct {
			ErrorCode string `json:"error_code"`
		} `json:"data"`
	}
	_ = json.Unmarshal(b3, &res3)
	if res3.Code != 42204 || res3.Data.ErrorCode != "IMAGE_DIMENSIONS_INVALID" {
		t.Fatalf("unexpected res3: %+v", res3)
	}
}

func TestControllerTryonQuotaAndConcurrency(t *testing.T) {
	secService := security.GetService()
	// 设置配额为 1 进行测试
	secService.DailyQuotaTracker = security.NewDailyQuotaTracker(1)
	secService.ConcurrencyManager = security.NewConcurrencyManager(1, 1)

	s := g.Server("test-ctrl-quota")
	s.Group("/", func(group *ghttp.RouterGroup) {
		group.Middleware(middleware.RequestID)
		group.Bind(NewV1())
	})
	s.SetPort(0)
	_ = s.Start()
	defer s.Shutdown()

	port := strings.Split(s.GetListenedAddress(), ":")[1]
	client := &http.Client{}

	validPerson := createTestPNG(300, 300)
	validGarment := createTestPNG(300, 300)

	// 先直接耗尽配额
	secService.DailyQuotaTracker.CheckAndDeduct("anonymous")

	// 发起请求，应当直接触发 DAILY_QUOTA_EXCEEDED (42902)
	tryReq := v1.TryonReq{
		PersonImage:  validPerson,
		GarmentImage: validGarment,
	}
	reqBody, _ := json.Marshal(tryReq)
	req, _ := http.NewRequest(http.MethodPost, "http://127.0.0.1:"+port+"/tryon", bytes.NewReader(reqBody))
	req.Header.Set("Content-Type", "application/json")
	resp, err := client.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusTooManyRequests {
		t.Fatalf("expected 429, got %d", resp.StatusCode)
	}
	b, _ := io.ReadAll(resp.Body)
	var res struct {
		Code int `json:"code"`
		Data struct {
			ErrorCode string `json:"error_code"`
		} `json:"data"`
	}
	_ = json.Unmarshal(b, &res)
	if res.Code != 42902 || res.Data.ErrorCode != "DAILY_QUOTA_EXCEEDED" {
		t.Fatalf("unexpected quota res: %+v", res)
	}
}

func init() {
	// 确保测试环境未设置任何破坏性环境变量
	os.Unsetenv("TRYON_API_KEYS")
}

func TestTryonDescriptionReachesImageProvider(t *testing.T) {
	const description = "白色影棚背景，人物坐在椅子上，柔和侧光"
	image := createTestPNG(300, 300)
	received := make(chan string, 2)
	provider := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var body struct{ Prompt string }
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Error(err)
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		received <- body.Prompt
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{"data": []map[string]string{{"b64_json": image}}})
	}))
	defer provider.Close()
	config, _ := json.Marshal(map[string]any{"llm": map[string]any{"models": map[string]any{"description-test": map[string]any{
		"provider": "openai", "apiKey": "test-key", "baseURL": provider.URL, "model": "test-image",
	}}}})
	adapter, err := gcfg.NewAdapterContent(string(config))
	if err != nil {
		t.Fatal(err)
	}
	oldAdapter := g.Cfg().GetAdapter()
	g.Cfg().SetAdapter(adapter)
	t.Cleanup(func() { g.Cfg().SetAdapter(oldAdapter) })
	service := security.GetService()
	oldQuota, oldConcurrency := service.DailyQuotaTracker, service.ConcurrencyManager
	service.DailyQuotaTracker = security.NewDailyQuotaTracker(100)
	service.ConcurrencyManager = security.NewConcurrencyManager(2, 1)
	t.Cleanup(func() { service.DailyQuotaTracker, service.ConcurrencyManager = oldQuota, oldConcurrency })
	s := g.Server("test-description-provider")
	s.SetPort(0)
	s.Group("/", func(group *ghttp.RouterGroup) {
		group.Middleware(middleware.RequestID, ghttp.MiddlewareHandlerResponse)
		group.Bind(NewV1())
	})
	if err := s.Start(); err != nil {
		t.Fatal(err)
	}
	defer s.Shutdown()
	port := strings.Split(s.GetListenedAddress(), ":")[1]
	post := func(text string) (int, string) {
		t.Helper()
		body, _ := json.Marshal(v1.TryonReq{PersonImage: image, GarmentImage: image, Model: "description-test", Lang: "zh", CustomPrompt: text})
		req, _ := http.NewRequestWithContext(context.Background(), http.MethodPost, "http://127.0.0.1:"+port+"/tryon", bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		res, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		defer res.Body.Close()
		payload, _ := io.ReadAll(res.Body)
		var result struct {
			Code int
			Data v1.TryonRes
		}
		if err := json.Unmarshal(payload, &result); err != nil {
			t.Fatalf("invalid API response: %v", err)
		}
		return result.Code, result.Data.Image
	}
	if code, result := post(description); code != 0 || result != image {
		t.Fatalf("description request failed, code=%d", code)
	}
	select {
	case prompt := <-received:
		if !strings.Contains(prompt, description) {
			t.Fatal("custom description was lost before reaching the model")
		}
	default:
		t.Fatal("model was not called")
	}
	if code, _ := post(strings.Repeat("字", 1001)); code == 0 {
		t.Fatal("HTTP API must reject an overlong description")
	}
	select {
	case <-received:
		t.Fatal("invalid description must not reach the model")
	default:
	}
}
