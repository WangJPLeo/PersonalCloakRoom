# 手机网页版与 GitHub Pages

手机网页版保留当前图库、分类、搜索、图片预览和下载，以及中英文与深浅主题切换。GitHub Pages 版本通过构建时固定配置的 HTTPS 接口执行 AI 换装，点击生成后发送照片、服装和生成参数，模型密钥由服务端管理。

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

源码工作流位于 `.github/workflows/pages.yml`，推送到 `main` 或 `codex/mobile-web` 时验证测试和构建，也可手动运行。自动发布只在 `main` 上执行；开发分支只构建，避免触发发布环境的分支保护限制。

使用自动发布时，在仓库 Settings → Pages 中，将 Source 设为 **GitHub Actions**，并允许 `main` 部署到 `github-pages` 环境。然后在 `main` 上运行 **Deploy mobile website**。以后更新 `main` 后会自动重新部署。

也可将 `dist/pages` 的内容推送到独立的 `gh-pages` 分支，在 Settings → Pages 中选择 **Deploy from a branch**、`gh-pages`、`/ (root)` 并保存。此方式后续需要手动更新发布分支；切换到自动发布时将 Source 改为 GitHub Actions。

网页全部资源使用相对路径，支持 GitHub Pages 仓库子目录。手机打开部署完成后显示的 HTTPS 链接即可，也可通过浏览器菜单添加到主屏幕。

## AI 换装

本机网页服务继续使用既有同源 `/api/tryon` 代理。GitHub Pages 不运行 Node.js 或 Go 服务，也不会读取本机真实配置；`scripts/build-pages.mjs` 生成仅含公开字段的 `config.js`，固定配置 HTTPS 接口及其精确来源白名单。

浏览器请求固定发送 `model: "doubao"`，服务端需将该别名配置为火山方舟的 `doubao-seedream-5-0-flash-260915`，并在服务端配置模型密钥。公开配置和请求中均不包含模型密钥或 `client_config`。

请求仅允许发送到白名单中的 HTTPS 来源和固定 `/tryon` 路径，拒绝查询参数、片段及 URL 用户名密码；请求不携带 Cookie，也不跟随重定向。`?tryon=`、`?model=` 和旧浏览器设置不能修改调用目标。

HTTPS 证书仍由浏览器正常校验。自签名证书未被设备信任时，网页会显示 HTTPS 连接失败提示；填写 HTTPS 地址不等于证书已经受信任。跨域设置需允许实际网页来源，生产服务也需配置适当的访问控制。
