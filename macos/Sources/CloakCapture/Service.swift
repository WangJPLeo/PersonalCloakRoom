import Foundation

enum ToolError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

struct ServicePolicy {
    // The only remote HTTP exception is a locally provisioned, explicitly approved origin.
    let approvedHTTPOrigin: String?

    static func origin(_ url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else { return nil }
        let port = url.port ?? (scheme == "https" ? 443 : 80)
        return "\(scheme)://\(host):\(port)"
    }

    func endpoint(_ input: String) throws -> URL {
        guard let parts = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              let url = parts.url, let scheme = parts.scheme?.lowercased(),
              ["http", "https"].contains(scheme), let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.port.map({ (1...65535).contains($0) }) ?? true else {
            throw ToolError.message("服务地址格式错误，请输入 HTTP/HTTPS 地址，不含账号、查询参数或片段。")
        }
        let local = ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host.lowercased())
        guard scheme == "https" || local || Self.origin(url) == approvedHTTPOrigin else {
            throw ToolError.message("远程服务必须使用 HTTPS；HTTP 仅限本机或本地配置中已授权的服务。")
        }
        let path = parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard path.isEmpty || path == "tryon" else {
            throw ToolError.message("请输入服务根地址或 /tryon 地址。")
        }
        return path.isEmpty ? url.appendingPathComponent("tryon") : url
    }
}

struct LocalConfiguration {
    var serviceURL = "http://127.0.0.1:8000"
    var policy = ServicePolicy(approvedHTTPOrigin: nil)
    var serverModel = "doubao"
    var accessToken = ""
    var personalModel: PersonalModel?

    init(values: [String: Any] = [:]) {
        serviceURL = values["ServiceURL"] as? String ?? serviceURL
        if values["AllowHTTPForService"] as? Bool == true {
            policy = ServicePolicy(approvedHTTPOrigin: URL(string: serviceURL).flatMap(ServicePolicy.origin))
        }
        serverModel = values["ServerModel"] as? String ?? serverModel
        accessToken = values["AccessToken"] as? String ?? ""
        if let model = values["PersonalModel"] as? [String: Any] {
            personalModel = PersonalModel(provider: model["provider"] as? String ?? "",
                                          base_url: model["base_url"] as? String ?? "",
                                          api_key: model["api_key"] as? String ?? "",
                                          model: model["model"] as? String ?? "")
        }
    }

    static func load() -> LocalConfiguration {
        guard let url = Bundle.main.url(forResource: "Config.local", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return LocalConfiguration() }
        return LocalConfiguration(values: dict)
    }

    func makeBody(person: String, garment: String, size: String, prompt: String) throws -> TryonRequest {
        try personalModel?.validate()
        return TryonRequest(person_image: person, garment_image: garment,
                            model: personalModel == nil ? serverModel : "browser-custom",
                            size: size, custom_prompt: prompt, client_config: personalModel)
    }
}

struct PersonalModel: Codable {
    var provider: String
    var base_url: String
    var api_key: String
    var model: String

    func validate() throws {
        guard ["doubao", "openai", "gemini"].contains(provider),
              !api_key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let parts = URLComponents(string: base_url), parts.scheme == "https",
              parts.host?.isEmpty == false, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil else {
            throw ToolError.message("请补全个人模型配置；模型 Base URL 必须为 HTTPS，且不含账号或查询参数。")
        }
    }
}

struct TryonRequest: Encodable {
    let person_image: String
    let garment_image: String
    let model: String
    let size: String
    let lang = "zh"
    let keep_face = true
    let custom_prompt: String
    let client_config: PersonalModel?
}

struct TryonEnvelope: Decodable {
    struct Result: Decodable {
        let image: String
        let mime: String
        let model: String?
    }
    let code: Int
    let data: Result?
    // Server messages may contain upstream URLs/credentials. Never surface them verbatim.
}

final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum TryonService {
    static func errorMessage(_ error: Error) -> String {
        if let known = error as? ToolError { return known.localizedDescription }
        let native = error as NSError
        guard native.domain == NSURLErrorDomain else { return "处理换装请求失败，请重试。" }
        // Never use localizedDescription or userInfo: both can contain private request URLs.
        switch native.code {
        case NSURLErrorAppTransportSecurityRequiresSecureConnection:
            return "系统安全策略阻止了 HTTP 请求（-1022）。请使用修复后的应用包，或改用 HTTPS 服务。"
        case NSURLErrorTimedOut:
            return "服务响应超时（-1001），请稍后重试；服务端任务可能仍在执行。"
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
            return "无法解析服务地址，请检查主机名或网络 DNS。"
        case NSURLErrorCannotConnectToHost:
            return "无法连接换装服务（-1004），请检查服务是否运行及端口是否可访问。"
        case NSURLErrorNotConnectedToInternet:
            return "当前网络不可用（-1009），请连接网络后重试。"
        case NSURLErrorNetworkConnectionLost:
            return "网络连接中断（-1005），请稍后重试。"
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted,
             NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateHasUnknownRoot,
             NSURLErrorServerCertificateNotYetValid:
            return "HTTPS 安全连接或证书校验失败，请检查服务端证书和地址。"
        case NSURLErrorCancelled:
            return "请求已取消。"
        default:
            return "网络请求失败（系统错误代码 \(native.code)），请检查服务连接后重试。"
        }
    }

    static func makeRequest(endpoint: URL, body: TryonRequest, token: String) throws -> URLRequest {
        guard body.custom_prompt.count <= 1000 else { throw ToolError.message("补充描述最多 1000 字。") }
        guard ["1024x1536", "1024x1024", "1536x1024"].contains(body.size) else {
            throw ToolError.message("不支持的生成尺寸。")
        }
        try body.client_config?.validate()
        guard token.rangeOfCharacter(from: .newlines) == nil else { throw ToolError.message("访问令牌格式错误。") }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = 240
        return request
    }

    static func decode(_ data: Data, status: Int) throws -> (Data, String) {
        guard status == 200 else {
            let reason: String
            switch status {
            case 300..<400: reason = "服务返回重定向，已阻止转发照片和凭据。"
            case 401, 403: reason = "访问被拒绝，请检查访问令牌和服务权限。"
            case 413: reason = "图片过大，请缩小截图后重试。"
            case 429: reason = "调用频率或额度已达限制，请稍后重试。"
            default: reason = "换装服务请求失败（HTTP \(status)），请检查服务配置。"
            }
            throw ToolError.message(reason)
        }
        guard let envelope = try? JSONDecoder().decode(TryonEnvelope.self, from: data),
              envelope.code == 0, let result = envelope.data else {
            throw ToolError.message("服务未返回成功结果，请检查模型配置或服务状态。")
        }
        guard ["image/png", "image/jpeg", "image/webp"].contains(result.mime.lowercased()),
              result.image.utf8.count <= 40_000_000 else { throw ToolError.message("结果图片格式或大小不受支持。") }
        let encoded = result.image.hasPrefix("data:")
            ? String(result.image.split(separator: ",", maxSplits: 1).last ?? "") : result.image
        guard let bytes = Data(base64Encoded: encoded), !bytes.isEmpty else {
            throw ToolError.message("服务返回的图片编码无效。")
        }
        return (bytes, result.mime.lowercased())
    }

    static func generate(endpoint: URL, body: TryonRequest, token: String) async throws -> (Data, String) {
        let request = try makeRequest(endpoint: endpoint, body: body, token: token)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 300
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        // Read incrementally to bound an untrusted response before decoding base64.
        let (stream, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw ToolError.message("服务响应无效。") }
        if http.statusCode != 200 { return try decode(Data(), status: http.statusCode) }
        var bytes = Data()
        for try await byte in stream {
            if bytes.count >= 42_000_000 { throw ToolError.message("服务响应超过大小限制。") }
            bytes.append(byte)
        }
        try Task.checkCancellation()
        return try decode(bytes, status: http.statusCode)
    }
}
