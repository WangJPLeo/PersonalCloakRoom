import AppKit
import Foundation
import ScreenCaptureKit

// Standalone contract checks: runnable with Command Line Tools, without XCTest/Xcode.
private func expect(_ value: @autoclosure () throws -> Bool, _ description: String) throws {
    guard try value() else { throw ToolError.message("验证失败：\(description)") }
}
private func expectFailure(_ description: String, _ body: () throws -> Void) throws {
    do { try body() }
    catch { return }
    throw ToolError.message("应当拒绝：\(description)")
}

@main
enum ServiceTests {
    static func main() throws {
        try testServiceURLPolicy()
        try testTemplateContractAndOptionalConfiguration()
        try testFixedModelConfiguration()
        try testResponseAndErrorsDoNotExposeServerText()
        try testRedirectIsNeverFollowed()
        try testImageLimits()
        try testNativeErrorMessages()
        try testCaptureErrors()
        try testCatalog()
        try testHistoryPersistence()
        if CommandLine.arguments.count > 1 { try testBundledGallery(URL(fileURLWithPath: CommandLine.arguments[1])) }
        print("通过 10 组桌面端检查：固定模型配置、网络协议、来源与错误、图片和截图权限、图库筛选与路径、历史记录持久化。")
    }

    static func testServiceURLPolicy() throws {
        let strict = ServicePolicy(approvedHTTPOrigin: nil)
        try expect(strict.endpoint("https://example.com").path == "/tryon", "HTTPS endpoint")
        try expect(strict.endpoint("http://127.0.0.1:8000/tryon").path == "/tryon", "loopback endpoint")
        _ = try strict.endpoint("http://localhost:8000")
        for address in ["http://example.com", "https://a:b@example.com", "https://example.com?tryon=x",
                        "https://example.com/#part", "file:///tmp/image", "https://example.com/other", "https://example.com:0"] {
            try expectFailure(address) { _ = try strict.endpoint(address) }
        }
        let scoped = ServicePolicy(approvedHTTPOrigin: "http://example.com:8000")
        _ = try scoped.endpoint("http://example.com:8000")
        for address in ["http://example.com:8001", "http://other.example.com:8000", "http://example.com.evil.test:8000"] {
            try expectFailure("HTTP approval scope") { _ = try scoped.endpoint(address) }
        }
    }

    static func testTemplateContractAndOptionalConfiguration() throws {
        let endpoint = try ServicePolicy(approvedHTTPOrigin: nil).endpoint("https://example.com")
        let body = TryonRequest(person_image: "person", garment_image: "garment", model: "doubao",
                                size: "1024x1536", custom_prompt: "黄色背景", client_config: nil)
        let request = try TryonService.makeRequest(endpoint: endpoint, body: body, token: "test-token")
        try expect(request.httpMethod == "POST", "POST method")
        try expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token", "bearer token")
        let object = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        try expect(object["person_image"] as? String == "person", "person image field")
        try expect(object["garment_image"] as? String == "garment", "garment image field")
        try expect(object["custom_prompt"] as? String == "黄色背景", "custom prompt field")
        try expect(object["lang"] as? String == "zh", "language field")
        try expect(object["client_config"] == nil, "server preset omits personal config")
        let personal = PersonalModel(provider: "doubao", base_url: "https://example.com/api/v3", api_key: "test-placeholder", model: "example-model")
        let custom = TryonRequest(person_image: "person", garment_image: "garment", model: "browser-custom",
                                  size: "1024x1536", custom_prompt: "", client_config: personal)
        let customRequest = try TryonService.makeRequest(endpoint: endpoint, body: custom, token: "")
        let customObject = try JSONSerialization.jsonObject(with: customRequest.httpBody!) as! [String: Any]
        try expect((customObject["client_config"] as? [String: String])?["model"] == "example-model", "personal model contract")
        try expectFailure("header injection") { _ = try TryonService.makeRequest(endpoint: endpoint, body: body, token: "bad\r\nheader") }
        let insecureModel = PersonalModel(provider: "doubao", base_url: "http://example.com", api_key: "test-placeholder", model: "example-model")
        try expectFailure("upstream credentials over HTTP") { try insecureModel.validate() }
    }

    static func testFixedModelConfiguration() throws {
        let model = ["provider": "doubao", "base_url": "https://ark.cn-beijing.volces.com/api/v3",
                     "api_key": "test-placeholder", "model": "doubao-seedream-5-0-flash-260915"]
        let values: [String: Any] = ["ServiceURL": "http://example.com:8000/tryon",
                                   "AllowHTTPForService": true, "PersonalModel": model]
        // Simulate reading the bundled plist on a fresh launch without settings interaction.
        let data = try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
        let loaded = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
        let config = LocalConfiguration(values: loaded)
        let endpoint = try config.policy.endpoint(config.serviceURL)
        let body = try config.makeBody(person: "person", garment: "garment", size: "1024x1536", prompt: "黄色背景")
        let request = try TryonService.makeRequest(endpoint: endpoint, body: body, token: config.accessToken)
        try expect(request.url?.path == "/tryon", "fixed endpoint has a single tryon path")
        let json = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        try expect(json["model"] as? String == "browser-custom", "fixed personal model cannot fall back to server preset")
        try expect(json["client_config"] as? [String: String] == model, "bundled provider, model, URL and key reach request intact")
        try expect(json["custom_prompt"] as? String == "黄色背景", "user prompt remains editable")
        try expect(request.value(forHTTPHeaderField: "Authorization") == nil, "no default access token")
        try expectFailure("fixed HTTP approval cannot authorize another host") {
            _ = try config.policy.endpoint("http://other.example.com:8000/tryon")
        }
        let invalid = LocalConfiguration(values: ["PersonalModel": ["provider": "doubao"]])
        try expectFailure("incomplete fixed model must fail instead of silently falling back") {
            _ = try invalid.makeBody(person: "person", garment: "garment", size: "1024x1536", prompt: "")
        }
        let preset = try LocalConfiguration().makeBody(person: "person", garment: "garment", size: "1024x1536", prompt: "")
        try expect(preset.model == "doubao" && preset.client_config == nil, "service-only configuration keeps server preset compatibility")
    }

    static func testResponseAndErrorsDoNotExposeServerText() throws {
        let data = Data("{\"code\":0,\"message\":\"\",\"data\":{\"image\":\"aGVsbG8=\",\"mime\":\"image/jpeg\",\"model\":\"browser-custom\"}}".utf8)
        let (bytes, mime) = try TryonService.decode(data, status: 200)
        try expect(bytes == Data("hello".utf8), "base64 decode")
        try expect(mime == "image/jpeg", "MIME contract")
        let failure = Data("{\"code\":1,\"message\":\"private-test-value\"}".utf8)
        try expectFailure("business error") { _ = try TryonService.decode(failure, status: 200) }
        do {
            _ = try TryonService.decode(failure, status: 200)
        } catch {
            try expect(!error.localizedDescription.contains("private-test-value"), "private server text is hidden")
        }
        for status in [302, 401, 403, 413, 429, 500] {
            try expectFailure("HTTP error") { _ = try TryonService.decode(failure, status: status) }
        }
        try expectFailure("malformed envelope") { _ = try TryonService.decode(Data("{}".utf8), status: 200) }
        let invalid = Data("{\"code\":0,\"data\":{\"image\":\"!!!\",\"mime\":\"image/jpeg\"}}".utf8)
        try expectFailure("invalid base64") { _ = try TryonService.decode(invalid, status: 200) }
    }

    static func testRedirectIsNeverFollowed() throws {
        let url = URL(string: "https://example.com/tryon")!
        let response = HTTPURLResponse(url: url, statusCode: 307, httpVersion: nil, headerFields: nil)!
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        var followed = true
        NoRedirects().urlSession(session, task: session.dataTask(with: url), willPerformHTTPRedirection: response,
                                newRequest: URLRequest(url: URL(string: "https://other.example.com")!)) { request in
            followed = request != nil
        }
        try expect(!followed, "redirect delegate blocks forwarding")
    }

    static func testImageLimits() throws {
        func image(_ width: Int, _ height: Int) -> CGImage {
            CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!.makeImage()!
        }
        try expectFailure("small capture") { _ = try Photo.from(image(255, 256), name: "test") }
        try expectFailure("thin image after scaling") { _ = try Photo.from(image(4000, 256), name: "test") }
        let photo = try Photo.from(image(512, 512), name: "test")
        try expect(!photo.jpeg.isEmpty, "JPEG input encoding")
        _ = try Photo.result(photo.jpeg)
        try expectFailure("invalid result image") { _ = try Photo.result(Data("not an image".utf8)) }
    }

    static func testNativeErrorMessages() throws {
        for code in [-1022, -1001, -1003, -1004, -1005, -1009, -1200, -1202, -999, -1999] {
            let error = NSError(domain: NSURLErrorDomain, code: code,
                                userInfo: [NSLocalizedDescriptionKey: "private-test-value", NSURLErrorFailingURLStringErrorKey: "https://private.example.com"])
            let message = TryonService.errorMessage(error)
            try expect(!message.contains("private-test-value") && !message.contains("private.example.com"), "native errors hide private context")
            if [-1022, -1001, -1004].contains(code) {
                try expect(message.contains(String(code)), "actionable native error code")
            }
        }
    }

    static func testCaptureErrors() throws {
        let denied = NSError(domain: SCStreamErrorDomain, code: -3801,
                             userInfo: [NSLocalizedDescriptionKey: "private-test-value"])
        guard case CaptureFailure.permissionDenied = CaptureFailure.classify(denied) else {
            throw ToolError.message("权限拒绝应显示授权恢复界面")
        }
        for (domain, code) in [(SCStreamErrorDomain, -3802), (SCStreamErrorDomain, -3811), ("OtherError", -3801)] {
            let error = NSError(domain: domain, code: code, userInfo: [NSLocalizedDescriptionKey: "private-test-value"])
            guard case CaptureFailure.unavailable = CaptureFailure.classify(error) else {
                throw ToolError.message("截图服务故障不应误报为权限不足")
            }
            try expect(!CaptureFailure.classify(error).localizedDescription.contains("private-test-value"), "capture error hides raw context")
        }
        let original = ToolError.message("选区太小")
        try expect(CaptureFailure.classify(original).localizedDescription == "选区太小", "preserve actionable local image errors")
    }

    static func testCatalog() throws {
        let item = CatalogGarment(id: "TEST-1", category: "春", keywords: "navy dress", image: "images/TEST-1.webp", thumbnail: "thumbs/TEST-1.webp")
        try expect(item.matches("TEST-1"), "catalog identifier search")
        try expect(item.matches("蓝色 连衣裙"), "Chinese garment and color keywords")
        try expect(item.matches("DRESS"), "case-insensitive garment search")
        try expect(!item.matches("蓝色 外套"), "all search terms must match")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        for folder in ["images", "thumbs"] {
            try FileManager.default.createDirectory(at: directory.appendingPathComponent(folder), withIntermediateDirectories: true)
            try Data([1]).write(to: directory.appendingPathComponent("\(folder)/TEST-1.webp"))
        }
        try JSONEncoder().encode([item]).write(to: directory.appendingPathComponent("catalog.json"))
        let catalog = try GarmentCatalog(root: directory)
        try expect(catalog.filtered(category: "春", query: "dress").count == 1, "combined category and text filter")
        try expect(catalog.filtered(category: "冬", query: "").isEmpty, "category filter")
        for path in ["../private.webp", "images/../../private.webp", "https://example.com/image.webp", "/images/TEST-1.webp"] {
            try expectFailure("unsafe catalog asset") { _ = try catalog.assetURL(path) }
        }
        try JSONEncoder().encode([item, item]).write(to: directory.appendingPathComponent("catalog.json"))
        try expectFailure("duplicate catalog IDs") { _ = try GarmentCatalog(root: directory) }
    }

    static func testHistoryPersistence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HistoryStore(root: directory)
        try expect(store.records().isEmpty, "first launch has no history")
        let record = TryonRecord(id: UUID(), createdAt: Date(), personName: "人物", garmentName: "服装",
                                 model: "test-model", size: "1024x1536", prompt: "黄色背景", mime: "image/jpeg")
        let bytes = Data("image fixture".utf8)
        try store.save(record: record, result: bytes, person: bytes, garment: bytes)
        let reopened = HistoryStore(root: directory)
        let items = try reopened.records()
        try expect(items.count == 1 && items[0].id == record.id, "history survives store reinitialization")
        let result = try reopened.imageURL(record, kind: .result)
        try expect(Data(contentsOf: result) == bytes, "history keeps the actual generated result")
        let permissions = try FileManager.default.attributesOfItem(atPath: result.path)[.posixPermissions] as? NSNumber
        try expect(permissions?.intValue == 0o600, "history images are private to the local user")
        let metadataURL = directory.appendingPathComponent(record.id.uuidString).appendingPathComponent("record.json")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: metadataURL)) as! [String: Any]
        try expect(Set(json.keys) == Set(["id", "createdAt", "personName", "garmentName", "model", "size", "prompt", "mime"]), "history stores no credentials, URL or model configuration")
        try expectFailure("duplicate history must not overwrite old photos") {
            try store.save(record: record, result: Data("replacement".utf8), person: bytes, garment: bytes)
        }
        try expect(Data(contentsOf: result) == bytes, "duplicate save preserves previous result")
        try reopened.delete(record)
        try expect(reopened.records().isEmpty, "deleted records stay deleted after reopen")
        try expect(!FileManager.default.fileExists(atPath: result.path), "deletion removes stored image files")
    }

    static func testBundledGallery(_ directory: URL) throws {
        let catalog = try GarmentCatalog(root: directory)
        for category in catalog.categories {
            guard let first = catalog.filtered(category: category, query: "").first else { continue }
            let photo = try Photo.load(catalog.assetURL(first.image))
            try expect(!photo.jpeg.isEmpty, "bundled garment becomes a real try-on image")
        }
        print("实际应用图库验证通过：\(catalog.items.count) 套，\(catalog.categories.count) 类，每类服装均可作为换装输入。")
    }
}
