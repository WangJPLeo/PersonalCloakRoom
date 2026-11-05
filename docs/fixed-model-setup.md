# 网页与 macOS 固定模型配置

两端固定使用火山方舟 `https://ark.cn-beijing.volces.com/api/v3` 和模型 `doubao-seedream-5-0-flash-260915`。网页已移除设置中心、管理配置和模型选择器；macOS 已移除连接设置入口。

## 网页启动

双击项目根目录的 `start-free.command`，或运行：

```sh
node scripts/serve-free.mjs
```

访问 `http://127.0.0.1:3000`。可通过 `PORT` 环境变量调整本机监听端口。

本机服务读取根目录的 `web.config.local.json`，此文件已被 Git 忽略。首次安装时从 `web.config.example.json` 复制并填写：

- `backendURL`：换装后端根地址或完整 `/tryon` 地址。
- `arkAPIKey`：火山方舟 Key。
- `accessToken`：可选的后端访问令牌。
- `allowHTTPForBackend`：默认关闭。仅在用户明确指定某个远程 HTTP 后端时开启；请求只发往本地配置中的地址，不跟随重定向。

修改配置后重启本机网页服务。没有配置时仍可浏览免费图库，AI 生图返回服务不可用；配置格式错误会阻止服务启动。

网页向同源 `/api/tryon` 发送图片与补充描述；本机服务加入固定模型及凭据，再调用后端。公开脚本和浏览器请求不包含 Key。旧浏览器模型设置、`?model=` 和 `?tryon=` 均不会覆盖固定配置。生成记录仍保存在当前浏览器 IndexedDB。

本机服务只公开图库与前端文件，不提供私有配置、后端源码或 Git 文件；上游错误和额外字段不会原样返回浏览器。直接打开静态 HTML 仍可浏览图库，AI 换装需要上述本机服务，或部署同等的同源代理接口。

## macOS

本地配置和打包方式见 [macOS 说明](../macos/README.md#服务配置)。更改配置后运行 `macos/build.command`，退出旧应用再打开新版。

## 验证

```sh
node tests/frontend_tryon_test.mjs
node --test tests/web_proxy_test.mjs
```

代理测试使用本机模拟后端，覆盖固定模型、来源校验、请求限额、凭据隔离、禁止重定向、上游错误与缺失配置，不调用付费模型。
