# 手机网页版与 GitHub Pages

手机网页版保留当前图库、分类、搜索、图片预览和下载，以及中英文与深浅主题切换。AI 换装需要独立的服务端，GitHub Pages 版本会禁用生图并显示原因，选中的照片不会发送到服务器。

## 构建

需要 Node.js 22 或更高版本。在仓库根目录运行：

```sh
node tests/frontend_tryon_test.mjs
node --test tests/pages_build_test.mjs
node scripts/build-pages.mjs
```

产物为 `dist/pages`，仅含网页、公开配置、图库数据、对应图片和 `.nojekyll`。构建检查图库数量及图片完整性，拒绝符号链接与异常路径，要求输出目录为空。

不要把整个仓库作为 Pages 发布目录；后端、本地配置、照片、日志和密钥均不应进入发布包。

## 自动发布

源码工作流位于 `.github/workflows/pages.yml`，推送到 `main` 或 `codex/mobile-web` 时触发，也可手动运行。

首次在仓库 Settings → Pages 中，将 Source 设为 **GitHub Actions**。然后在 Actions 中运行 **Deploy mobile website**。以后更新源码后会自动重新部署。

也可将 `dist/pages` 的内容推送到独立的 `gh-pages` 分支，在 Settings → Pages 中选择 **Deploy from a branch**、`gh-pages`、`/ (root)` 并保存。此方式后续需要手动更新发布分支；切换到自动发布时将 Source 改为 GitHub Actions。

网页全部资源使用相对路径，支持 GitHub Pages 仓库子目录。手机打开部署完成后显示的 HTTPS 链接即可，也可通过浏览器菜单添加到主屏幕。

## AI 换装

本机网页服务继续使用既有同源 `/api/tryon` 代理。GitHub Pages 不运行 Node.js 或 Go 服务，不能读取本机配置，也不能安全保存模型密钥。

若要手机端生成效果，应部署具有访问控制的 HTTPS 换装服务，并为网页配置受信任的同源接口。不要通过 URL 参数接管请求目标，不要把模型密钥放进公开配置或 GitHub 仓库。
