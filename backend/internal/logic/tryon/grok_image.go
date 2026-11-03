package tryon

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
)

// generateGrokEdit sends both reference images to the multi-image editing API.
// The text-to-image endpoint cannot be used as a fallback for virtual try-on.
func (o *OpenAIImages) generateGrokEdit(ctx context.Context, person, garment, prompt, size string) (string, error) {
	type reference struct {
		Type string `json:"type"`
		URL  string `json:"url"`
	}
	refs := make([]reference, 0, 2)
	for _, image := range []string{person, garment} {
		mime, err := DetectGeneratedImageMIME(image)
		if err != nil {
			return "", fmt.Errorf("Grok 参考图片格式无效")
		}
		refs = append(refs, reference{Type: "image_url", URL: "data:" + mime + ";base64," + ensureBase64(image)})
	}
	ratio := "2:3"
	switch size {
	case "1024x1024":
		ratio = "1:1"
	case "1536x1024":
		ratio = "3:2"
	}
	body, err := json.Marshal(struct {
		Model          string      `json:"model"`
		Prompt         string      `json:"prompt"`
		Images         []reference `json:"images"`
		ResponseFormat string      `json:"response_format"`
		AspectRatio    string      `json:"aspect_ratio"`
		N              int         `json:"n"`
	}{o.model, prompt, refs, "b64_json", ratio, 1})
	if err != nil {
		return "", fmt.Errorf("无法构建 Grok 换装请求")
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, o.baseURL+"/images/edits", bytes.NewReader(body))
	if err != nil {
		return "", fmt.Errorf("Grok 模型服务地址无效")
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+o.apiKey)
	resp, err := o.client.Do(req)
	if err != nil {
		return "", fmt.Errorf("无法连接 Grok 图像服务")
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("Grok 图像服务返回 HTTP %d", resp.StatusCode)
	}
	var result gptImageResponse
	if err := json.NewDecoder(io.LimitReader(resp.Body, 48<<20)).Decode(&result); err != nil {
		return "", fmt.Errorf("Grok 图像服务响应格式无效")
	}
	if result.Error != nil || len(result.Data) == 0 || result.Data[0].B64JSON == "" {
		return "", fmt.Errorf("Grok 图像服务未返回 base64 图片")
	}
	if _, err := DetectGeneratedImageMIME(result.Data[0].B64JSON); err != nil {
		return "", err
	}
	return result.Data[0].B64JSON, nil
}
