// Package tryon 换装提示词模板，针对不同模型优化
package tryon

import (
	"fmt"
	"strings"
	"unicode/utf8"
)

// WithCustomPrompt preserves the original behavior for blank descriptions.
// With a description, pose and scene defaults yield to the user's preferences;
// identity, garment fidelity, and the existing safety requirements stay in force.
func WithCustomPrompt(base, description, lang string) (string, error) {
	if utf8.RuneCountInString(description) > 1000 {
		return "", fmt.Errorf("补充描述最多1000个字符")
	}
	description = strings.TrimSpace(description)
	if description == "" {
		return base, nil
	}
	defaults := strings.NewReplacer(
		"Keep the person's original pose, body angle and orientation as much as possible; only adjust the arms/limbs if strictly needed to fit the garment naturally.",
		"Follow the additional description for pose, body angle and orientation; retain the original pose when no change is requested.",
		"Keep the original background, lighting and overall mood of the person's photo.",
		"Follow the additional description for background, lighting and mood; retain the original scene for any unspecified aspects.",
		"尽量保持人物原有的姿势、身体角度和朝向；仅在必要时微调手臂/肢体以自然贴合服装。",
		"按补充描述调整姿势、身体角度和朝向；未提出姿势要求时保留原有姿势。",
		"保留人物照片原有的背景、光线和整体氛围。",
		"按补充描述调整背景、光线和整体氛围；未提及的部分保留原图效果。",
		"upright standing posture, non-revealing.", "natural posture as requested, non-revealing.",
		"Clean bright studio lighting, neutral minimal background, photorealistic 8k, high detail fashion editorial photograph.",
		"Use the requested background and lighting, defaulting to a clean bright studio. Photorealistic, high detail fashion editorial photograph.",
		"端正站姿，避免过度露肤与暴露。", "采用描述中要求的自然姿势，避免过度露肤与暴露。",
		"纯净明亮的商业影棚光照，简洁中性背景，逼真细节与质感，专业时尚画册品质。",
		"按描述设置背景与光照，未指定时采用明亮简洁影棚，保留逼真细节与专业时尚画册品质。",
	)
	base = defaults.Replace(base)
	if lang == "zh" {
		return base + "\n\n补充画面描述：\n" + description + "\n\n执行要求：按上述描述调整姿势、视角、背景、光照和画面风格；保留参考人物身份与服装款式，不覆盖人物、服装和安全要求。仅输出一张最终换装图片。", nil
	}
	return base + "\n\nAdditional visual description:\n" + description + "\n\nApply these preferences to pose, view, background, lighting and style. Preserve the reference identity and garment, and follow the identity, garment and safety requirements above. Output only one final try-on image.", nil
}

// BuildGPTSafety 构建 GPT-Image 专用的防封控安全提示词
func BuildGPTSafety(lang string) string {
	if lang == "zh" {
		return gptSafetyZhPrompt
	}
	return gptSafetyEnPrompt
}

// BuildGPT 构建 GPT-Image 的提示词（默认指向安全防封控模板）
func BuildGPT(lang string) string {
	return BuildGPTSafety(lang)
}

// BuildGemini 构建 Gemini（Nano Banana 2）图像模型的提示词（保留原提示词）
func BuildGemini(lang string) string {
	// Gemini 对中英文都支持良好，但换装任务英文指令更稳定
	return enPrompt
}

// BuildDefault 通用/其他模型（如豆包等）提示词（保留原提示词）
func BuildDefault(lang string) string {
	if lang == "zh" {
		return zhPrompt
	}
	return enPrompt
}

// gptSafetyEnPrompt GPT-Image-2 专用英文防封控安全提示词
const gptSafetyEnPrompt = `Task: Professional commercial fashion virtual try-on photograph.

Strict Requirements:
1. Model Identity: Maintain the adult female model from Image 1 - faithfully preserve her facial features, ethnic identity, eye shape, smile, skin tone, and hairstyle. Keep her identity consistent.
2. Wardrobe: Dress her in the exact clothing and accessories shown in Image 2. Faithfully reproduce the colors, fabric textures, patterns, and silhouette.
3. Safety & Fit: Professional high-end commercial lookbook standard. Fully clothed, modest neckline, standard tailored fit, upright standing posture, non-revealing.
4. Composition: Clean bright studio lighting, neutral minimal background, photorealistic 8k, high detail fashion editorial photograph.
5. Do not add visible watermarks, signatures, captions, promotional text or overlay logos. Preserve actual prints, lettering and brand marks that are part of the reference garment.

Output: ONLY the final dressed-up photograph.`

// gptSafetyZhPrompt GPT-Image-2 专用中文防封控安全提示词
const gptSafetyZhPrompt = `任务：专业商业时尚虚拟试衣摄影。

严格要求：
1. 模特身份：保持第一张图片中的成年女性模特身份——忠实保留其面部特征、种族相貌、眼部轮廓、肤色与发型，保持人物相貌风格一致。
2. 服装穿搭：让人物完整穿上第二张图片中展示的服装与配饰，忠实还原服装的色彩、面料质感、图案与款式剪裁。
3. 安全与合规：采用高端商业型录摄影标准。穿着完整端庄，标准合身剪裁，端正站姿，避免过度露肤与暴露。
4. 画面效果：纯净明亮的商业影棚光照，简洁中性背景，逼真细节与质感，专业时尚画册品质。
5. 不新增可见水印、署名、说明文字、宣传文字或叠加标志。保留参考服装本身的印花、文字与品牌标识。

输出：仅输出最终的完整着装照片。`

// enPrompt 英文提示词（主用，效果最稳定）
const enPrompt = `You are a professional fashion virtual try-on assistant.

Task: Dress the person in the first image wearing the garment in the second image, and output a single photorealistic full-body or half-body photo.

Strict requirements:
1. Keep the person's identity EXACTLY the same: same face, same facial features, same skin tone, same hairstyle, same body type and proportions. Do not change who they are.
2. Keep the person's original pose, body angle and orientation as much as possible; only adjust the arms/limbs if strictly needed to fit the garment naturally.
3. Put the exact garment from the second image onto the person: preserve its color, fabric texture, pattern, neckline, sleeve length, hem length and silhouette faithfully. Do not redesign or simplify the garment.
4. The garment must drape naturally on the body, follow the body contours, and cast realistic folds, shadows and highlights consistent with the original lighting.
5. Keep the original background, lighting and overall mood of the person's photo.
6. Photorealistic, high detail, professional fashion editorial quality, 8k, natural skin texture.
7. Do not add visible watermarks, signatures, captions, promotional text or overlay logos. Preserve actual prints, lettering and brand marks that are part of the reference garment.

Output: ONLY the final dressed-up photograph, nothing else.`

// zhPrompt 中文提示词（备用）
const zhPrompt = `你是一名专业的时尚虚拟试衣助手。

任务：让第一张图片中的人物穿上第二张图片中的服装，输出一张逼真的全身或半身照片。

严格要求：
1. 人物身份必须完全一致：相同的脸、五官、肤色、发型、身材比例。不得改变人物是谁。
2. 尽量保持人物原有的姿势、身体角度和朝向；仅在必要时微调手臂/肢体以自然贴合服装。
3. 将第二张图中的服装原样穿到人物身上：忠实保留其颜色、面料质感、图案、领型、袖长、下摆长度和廓形。不得重新设计或简化服装。
4. 服装必须自然垂坠贴合身体曲线，并根据原始光照产生真实的褶皱、阴影和高光。
5. 保留人物照片原有的背景、光线和整体氛围。
6. 逼真、高细节、专业时尚大片质感、8k、自然皮肤纹理。
7. 不新增可见水印、署名、说明文字、宣传文字或叠加标志。保留参考服装本身的印花、文字与品牌标识。

输出：仅输出最终的换装照片，不要其他内容。`
