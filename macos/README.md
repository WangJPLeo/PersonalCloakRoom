# 衣橱快截 · macOS 桌面换装工具

macOS 14 或更新版本。使用 SwiftUI、AppKit 和 ScreenCaptureKit，无第三方运行时依赖。开发和构建需要含 Swift 6 的 Apple Command Line Tools，无需完整 Xcode。

## 启动

在 Finder 中双击 `启动衣橱快截.command`。首次启动会编译并生成 `dist/衣橱快截.app`，之后可以直接双击应用。也可以把它拖进「应用程序」目录。当前构建面向本机 CPU；在 Apple Silicon 和 Intel Mac 上分别构建即可得到对应版本。

每次打包先在临时目录生成并验证新版，成功后替换固定路径 `dist/衣橱快截.app`，删除 `dist` 中具有本项目 Bundle ID 的历史应用包及本项目的临时诊断应用包，只保留最新版。编译、签名或发布失败时保留或恢复原版；不会清理项目外的安装副本、其他应用或符号链接。旧文件清理不会自动修改 macOS 系统权限。

```sh
cd macos
./build.command
open dist/衣橱快截.app
```

应用默认只显示右侧悬浮按钮和菜单栏图标。点击按钮进入截图，拖动框选屏幕中的服装，松开完成，Esc 取消。支持在任意一个显示器上框选；单次选区不跨显示器。按钮可拖动，右键打开换装窗口、查看记录或退出。关闭换装窗口后，按钮仍然保留。

双击「启动衣橱快截.command」会同时打开换装窗口；应用已在后台运行时，再次双击应用也会唤出窗口，无需重复启动。悬浮按钮默认放在鼠标所在屏幕右侧，显示器配置变化后会重新定位。

首次截图需要系统「屏幕录制」权限（部分系统称为「录屏与系统录音」）。工具直接通过 ScreenCaptureKit 请求截图，不再用旧的 CoreGraphics 权限预检查阻断流程。只有系统实际返回权限拒绝时，才显示授权恢复界面，可打开系统设置、在 Finder 中定位当前应用、授权后重试或重启应用。其他截图服务错误会显示对应错误代码。

如果系统开关已开启却仍然拒绝，请确认授权的是当前运行的这份应用：先关闭再开启对应开关，必要时移除旧条目并用 + 添加当前应用；系统要求重启时，退出后再打开。应用内「重启应用」会清空本次导入的照片；固定模型配置会在启动时重新加载。

截图完成后，点击加号导入一张或多张模特 / 人物照片，点击缩略图选择人物；右键缩略图可移除。建议使用清晰的全身或半身站立照。服装图也可以从本地导入。选择尺寸、填写可选描述，然后开始 AI 换装。生成结果可保存或复制。

「图库选衣」可直接浏览项目服装库，按季节、派对、泳装、中式分类，支持编号和中英文关键词搜索，预览后点击「使用这件服装」。打包时从项目 `data.js` 读取当前目录数据，将对应原图和缩略图打入应用，离线也可选衣；更新图库后重新打包即可同步。

每次成功生成后自动保存换装记录。点击右上角「换装记录」或菜单栏中的同名入口，可查看生成图片、当次人物与服装、时间、模型和画面描述，并可导出、复制或单独删除。记录存放在系统 Application Support 下的 `app.personalcloakroom.capture/History`，重新打开或替换应用包后仍保留；此目录不在项目或应用包内，打包清理不会删除它。不会自动向其他设备同步。

## 服务配置

应用调用 `POST /tryon`，字段与项目后端及用户提供的参数模板一致：`person_image`、`garment_image`、`model`、`size`、`lang`、`keep_face`、`custom_prompt`，以及可选 `client_config`。返回值按 `{code: 0, data: {image, mime, model}}` 解析。

应用启动时自动读取打包配置，主页和菜单不再提供「连接设置」或模型导入入口。复制 `Config.example.plist` 为 `Config.local.plist`，填写 `ServiceURL` 与 `PersonalModel.api_key` 后重新构建即可使用。模板预设火山方舟协议、`https://ark.cn-beijing.volces.com/api/v3` 和 `doubao-seedream-5-0-flash-260915`。真实地址和 Key 只放在被 Git 忽略的本地文件中，不写进源码或模板。没有配置文件时回退至 `http://127.0.0.1:8000`。

远程地址默认强制 HTTPS。如果用户明确授权某一远程 HTTP 服务，可在本地配置中为该地址设置 `AllowHTTPForService` 为 `true`。此例外仅允许该配置地址的精确来源（协议、主机、端口），不会放行其他远程 HTTP 地址。构建时会添加 ATS 兼容设置，应用网络层仍独立校验精确来源。所有 HTTP 重定向均被拒绝，包括同源重定向，以免照片或凭据被转发。

`PersonalModel` 的字段为 `provider`、`base_url`、`api_key`、`model`。配置完整时，每次请求自动发送 `model: browser-custom` 和对应 `client_config`；配置不完整会报错，不会静默改用其他模型。若使用服务端预设，可删除整个 `PersonalModel` 字典，通过 `ServerModel` 指定别名（默认 `doubao`）。可选 `AccessToken` 通过 `Authorization: Bearer …` 传递。修改后须重新打包并重启应用。

## 数据与边界

- 未提交换装的整屏截图、裁剪选区和导入照片只保留在内存。固定模型配置与访问令牌从本地应用包读取，不写入历史记录或日志。含真实 Key 的本地配置和应用构建产物均被 Git 忽略；应用包包含该配置，应只在授权设备上使用。成功换装后，按用户要求将生成图片、当次输入图片与必要的记录信息保存在本机历史目录；不保存 API Key、Token、Base URL、换装服务地址或完整请求体。历史目录权限为仅当前用户可访问，图片文件默认权限为 `0600`。应用不记录服务端原始错误。截屏通过 [Apple ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager/captureimage%28contentfilter%3Aconfiguration%3Acompletionhandler%3A%29) 完成，不生成临时整屏截图文件。
- 只有点击「开始 AI 换装」时才上传裁剪后的服装图和选中的人物照片；换装服务由本地打包配置指定。工具会将两张输入图缩放到最长边 2048 像素并编码为 JPEG。
- 保存图片和复制图片属于用户主动导出。服务端收到照片和个人模型配置后的处理遵循服务端部署策略。
- 「取消等待」终止客户端请求，服务端已提交的 AI 任务可能继续运行或产生费用。
- 默认应用采用本地临时签名，未使用 Developer ID 签名和 Apple 公证，不能替代面向其他用户分发的正式签名流程。临时签名的默认指定要求绑定当前构建，重新构建后旧授权可能无法匹配（[Apple 签名身份说明](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)）；工具不会重置系统权限或放宽代码签名身份校验。如本机已有合适的代码签名证书，可设置 `CLOAK_CODESIGN_IDENTITY` 环境变量后构建，并持续使用同一证书。

## 验证

```sh
./test.command
./build.command
```

独立测试程序无需 XCTest 或完整 Xcode，覆盖固定模型配置自动加载、配置缺失时拒绝回退、精确来源校验、HTTP 例外边界、请求字段、可选个人模型配置、响应解析、错误脱敏、禁止重定向、图片尺寸限制、原生网络错误分类、截图权限拒绝与服务故障的区分，以及 ATS 打包配置。实际截图授权、多显示器操作以及真实模型效果需要在桌面环境中验证。

另有图库过滤与资源安全、图库打包、历史记录重新读取/删除/文件权限/凭据隔离，以及旧包清理失败回滚检查。可使用 `.build/contract-tests dist/衣橱快截.app/Contents/Resources/Gallery` 验证实际打包图库中每类图片均能转成换装输入。

若出现 `-1022`，表示 macOS 在发起请求前拦截了 HTTP。对明确授权的 HTTP 地址，打包脚本只写入 `NSAllowsArbitraryLoads`，不会同时写入会覆盖它的 `NSAllowsLocalNetworking` 等细粒度开关（参见 [Apple ATS 规则](https://developer.apple.com/documentation/BundleResources/Information-Property-List/NSAppTransportSecurity/NSAllowsArbitraryLoads)）。重新构建后需退出旧应用再打开新包，运行中的进程不会重新读取新的安全策略。

脚本会检查部分升级的 Command Line Tools 中遗留的重复 SwiftBridging 模块与新旧 ManifestAPI 接口混用问题；仅在命中时在被 Git 忽略的 `.build/toolchain` 中生成兼容覆盖文件，不修改系统安装。工具链正常时不添加覆盖配置。
