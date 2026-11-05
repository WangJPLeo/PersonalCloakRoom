import SwiftUI
import Photos

@MainActor
final class MobileSession: ObservableObject {
    @Published var person: Data?
    @Published var garment: Data?
    @Published var result: Data?
    @Published var records: [TryonRecord] = []
    @Published var preferences = MobilePreferences()
    @Published var prompt = ""
    @Published var size = "1024x1536"
    @Published var busy = false
    @Published var importing = false
    @Published var status = "先设置换装人物，以后会自动复用。"
    @Published var error: String?
    var garmentName = "截图服装"
    let storage: MobileStorage?
    let credentials = MobileCredentials()
    private var job: Task<Void, Never>?
    var canGenerate: Bool { storage != nil && person != nil && garment != nil && !busy && !importing && prompt.count <= 1000 }

    init() {
        do { storage = try MobileStorage.shared() }
        catch { storage = nil; self.error = error.localizedDescription }
        reload()
    }

    func reload() {
        guard !busy, let storage else { return }
        do {
            person = try storage.defaultPerson()
            preferences = try credentials.load()
            records = try storage.history.records()
        } catch { self.error = safeMessage(error, fallback: "无法读取本机人物或换装记录，请重试。") }
    }

    func importPerson(_ data: Data) async {
        guard !busy, !importing, let storage else { return }
        importing = true
        defer { importing = false }
        do {
            let jpeg = try await Task.detached { try MobileImage.prepare(data) }.value
            try storage.setDefaultPerson(jpeg)
            person = jpeg
            result = nil
            error = nil
            status = "已保存默认换装人物，下次会自动使用，可随时更换。"
        } catch { self.error = safeMessage(error, fallback: "无法保存这张人物照片。") }
    }

    func importGarment(_ data: Data, name: String = "截图服装") async {
        guard !busy else { return }
        importing = true
        defer { importing = false }
        do {
            garment = try await Task.detached { try MobileImage.prepare(data) }.value
            garmentName = name
            result = nil
            error = nil
            status = "请确认服装截图和人物，再发起换装。"
        } catch { self.error = safeMessage(error, fallback: "无法读取这张服装图片。") }
    }

    func savePreferences(_ settings: MobilePreferences) throws {
        try credentials.save(settings)
        preferences = settings
    }

    func generate() {
        guard canGenerate, let storage, let person, let garment else { return }
        do {
            let config = LocalConfiguration.load()
            let endpoint = try config.policy.endpoint(config.serviceURL)
            let custom = try preferences.personalModel()
            let body = TryonRequest(person_image: person.base64EncodedString(), garment_image: garment.base64EncodedString(),
                                    model: custom == nil ? preferences.serverModel : "browser-custom", size: size,
                                    custom_prompt: prompt, client_config: custom)
            let token = preferences.token
            _ = try TryonService.makeRequest(endpoint: endpoint, body: body, token: token)
            let modelName = custom?.model ?? preferences.serverModel
            let recordGarmentName = garmentName
            busy = true
            result = nil
            error = nil
            status = "正在换装，请保持此页面打开…"
            job = Task {
                do {
                    let (data, mime) = try await TryonService.generate(endpoint: endpoint, body: body, token: token)
                    try Task.checkCancellation()
                    _ = try MobileImage.validatedSource(data)
                    let record = TryonRecord(id: UUID(), createdAt: Date(), personName: "默认换装人物",
                                             garmentName: recordGarmentName, model: modelName,
                                             size: body.size, prompt: body.custom_prompt, mime: mime)
                    var saved = true
                    do {
                        try await Task.detached(priority: .utility) {
                            try storage.history.save(record: record, result: data, person: person, garment: garment)
                        }.value
                    } catch { saved = false }
                    guard !Task.isCancelled else { return }
                    result = data
                    records = (try? storage.history.records()) ?? records
                    status = saved ? "换装完成，已保存在本机换装记录中。" : "换装完成，但记录保存失败，请先保存图片到相册。"
                } catch {
                    guard !Task.isCancelled else { return }
                    self.error = TryonService.errorMessage(error)
                    status = "生成失败，调整设置后可以重试。"
                }
                busy = false
                job = nil
            }
        } catch { self.error = safeMessage(error, fallback: "请检查模型配置后重试。") }
    }

    func cancel() {
        job?.cancel()
        job = nil
        busy = false
        status = "已取消等待，服务端已提交的任务可能仍会完成。"
    }

    func saveToPhotos(_ data: Data) async {
        let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard authorization == .authorized || authorization == .limited else {
            error = "未获得保存到相册的权限，可在系统设置中为衣橱快截开启。"
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }
            status = "图片已保存到相册。"
        } catch { self.error = "无法保存到相册，请检查相册权限和剩余空间。" }
    }

    private func safeMessage(_ error: Error, fallback: String) -> String {
        (error as? ToolError)?.localizedDescription ?? fallback
    }
}
