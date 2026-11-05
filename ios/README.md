# 衣橱快截 · iPhone

原生 SwiftUI 应用和图片分享扩展，支持 iOS 17 及以上。首次选择默认换装人物，之后从截图分享入口自动复用，也可随时更换。主应用同时提供服装图库、相册选衣和持久换装记录。

当前交付为源码和 Xcode 工程。共享图片处理、存储、接口逻辑和工程结构已在 macOS 上检查；UIKit 页面、分享扩展、签名和安装必须使用完整 Xcode 与真实 iPhone 验证，不能将这些检查视作已完成 iOS 编译。

## 使用方式

1. 打开主应用，在「设置」中选择清晰的全身或半身人物照。照片会立即保存为默认人物；模型配置修改后点击「保存模型设置」。已有请求参数模板可通过「从请求模板导入模型配置」读取，仅提取 `client_config`。
2. 在其他 App 使用系统截屏，打开截图预览，点击分享，选择「衣橱快截」。首次可能需要在分享菜单的「更多」中启用此入口。
3. 检查服装与默认人物，按需裁剪图片，点击「确认图片并换装」。读取或裁剪截图时不会上传照片。
4. 保持分享页面打开直到生成完成。结果会保存到本机「换装记录」，也可另存到系统相册，随后点击「完成」。

在主应用中也可从「图库」选择现有服装，或从「选图」导入相册图片。分享扩展只接收一张图片，不抓取网页链接或远程图片。输入上限 20 MB，最小有效选区 256 × 256 像素；图片会统一方向、移除原始元数据并缩至最长边 2048 像素。

本版本按已选择的「系统截图后分享」流程实现。普通 iOS 应用无法自行提供跨应用悬浮截屏按钮，平台说明见 [Apple DTS](https://developer.apple.com/forums/thread/797031)。分享扩展生命周期由系统管理，关闭分享页会取消本地等待；服务端已经接收的任务仍可能继续执行。

## 准备和安装

需要完整 Xcode、iOS SDK，以及能为主应用和扩展同时启用 App Groups 的开发团队和配置描述文件。[App Groups 配置说明](https://developer.apple.com/documentation/xcode/configuring-app-groups)。仅安装 Command Line Tools 无法编译 iPhone 应用。

在项目根目录执行：

```sh
./ios/prepare.command
open ios/CloakRoom.xcodeproj
```

准备脚本生成离线图库、图标和本地服务配置，不下载第三方依赖。默认复用 macOS 的本地服务地址与已明确授权的 HTTP 例外；若没有 macOS 本地配置，则使用示例地址，需要另行设置 `ios/Config.local.plist`。此文件只允许 `ServiceURL` 和 `AllowHTTPForService` 两个字段，不允许放入模型密钥或访问令牌。

复制 `Signing.example.xcconfig` 为被 Git 忽略的 `Signing.local.xcconfig`，填写开发团队，并为两个应用标识和 App Group 选择团队可用的唯一值。扩展 Bundle ID 会自动使用主应用 ID 加 `.share`。然后在 Xcode 中确认两个 target 的 Signing & Capabilities 使用同一团队、同一 App Group，选择连接的 iPhone，运行 `CloakRoom` scheme。注册 App Group 和生成匹配的配置描述文件需要开发者账号；源码不包含任何签名私钥。

安装后先打开主应用设置人物和模型，再测试系统截图分享。模型配置和令牌保存在共享钥匙串中，主应用与分享扩展共用；无需向工程或打包文件添加真实 API Key。

## 数据与接口

- 默认人物、结果和当次输入照片保存在设备 App Group 中，重新打开仍可查看。删除默认人物不会清除已有换装记录；删除记录需要确认。
- 图片与历史目录排除系统备份，文件使用设备数据保护。模型凭据使用 `AfterFirstUnlockThisDeviceOnly` 共享钥匙串项，不写入记录、日志或应用资源。
- macOS 与 iPhone 各自保存本地记录，本版本未实现跨设备同步。
- 接口沿用已有 `/tryon` JSON 协议：`person_image`、`garment_image`、`model`、`size`、`custom_prompt`、可选 `client_config`；解析 `code`、`data.image` 和 `data.mime`。不向用户显示可能包含凭据的上游错误原文。
- 服务地址只从本地打包配置读取。分享数据不能覆盖地址或注入请求配置；请求禁止自动跟随重定向。远程 HTTP 仅允许本地配置明确授权的服务源，个人模型 Base URL 仍要求 HTTPS。

## 检查与归档

```sh
./ios/prepare.command
./ios/test.command
./macos/test.command
./ios/build.command
```

`test.command` 使用临时合成图片，验证人物替换与重启读取、主应用/分享入口共用历史、图片约束与元数据清理，并检查扩展嵌入、激活规则和 App Group 配置。它不会访问真实相册、写入真实钥匙串或调用付费模型。

`build.command` 需要完整 iOS SDK 和有效签名；缺少 SDK 时直接说明原因，不生成伪安装包。成功后在 `ios/dist` 只保留此应用固定名称的最新 Archive，替换失败会恢复上次构建；不会删除设备上的应用或本机历史数据。实际设备安装、TestFlight 或其他分发请通过 Xcode Organizer 完成。

真机验收至少包含：首次设置人物、强退重开后复用、更换人物、截图分享及裁剪、成功生成并退出分享页后查看记录、保存到相册，以及断网、取消和服务失败时重试。iPhone 在分享扩展中的内存和执行时长限制，也需要用实际照片与服务响应验证。
