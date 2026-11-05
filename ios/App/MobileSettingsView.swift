import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

@MainActor
struct MobileSettingsView: View {
    @ObservedObject var model: MobileSession
    @Environment(\.dismiss) private var dismiss
    @State private var draft = MobilePreferences()
    @State private var personSelection: PhotosPickerItem?
    @State private var importTemplate = false
    @State private var error: String?
    @State private var removingPerson = false

    var body: some View {
        NavigationStack {
            Form {
                Section("默认换装人物") {
                    MobilePicture(data: model.person, height: 180)
                    PhotosPicker(selection: $personSelection, matching: .images) { Text(model.person == nil ? "设置换装人物" : "更换换装人物") }
                        .disabled(model.importing)
                    Text("人物照片只保存在设备上，之后分享截图会自动使用这张人物照。人物更换立即保存。")
                        .font(.caption).foregroundStyle(.secondary)
                    if model.person != nil { Button("移除默认人物", role: .destructive) { removingPerson = true } }
                }
                Section("换装服务") {
                    Text(LocalConfiguration.load().serviceURL).font(.caption).textSelection(.enabled)
                    if LocalConfiguration.load().serviceURL.lowercased().hasPrefix("http://") {
                        Text("此服务使用 HTTP，提交的照片及凭据会以明文传输。")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    SecureField("服务访问令牌（可选）", text: $draft.token).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Toggle("使用个人模型配置", isOn: $draft.usePersonalModel)
                    if !draft.usePersonalModel {
                        TextField("服务端模型别名", text: $draft.serverModel).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                }
                if draft.usePersonalModel {
                    Section("个人模型") {
                        Picker("协议", selection: $draft.provider) {
                            Text("豆包 / Doubao").tag("doubao")
                            Text("OpenAI 兼容").tag("openai")
                            Text("Gemini").tag("gemini")
                        }
                        TextField("HTTPS Base URL", text: $draft.baseURL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("模型名称", text: $draft.model).textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField("API Key", text: $draft.apiKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                }
                Section {
                    Button("从请求模板导入模型配置…") { importTemplate = true }
                    Button("清除模型与访问凭据", role: .destructive) {
                        do { try model.credentials.clear(); draft = MobilePreferences(); model.preferences = draft }
                        catch { self.error = "无法清除钥匙串配置，请重试。" }
                    }
                    Text("模型配置和令牌保存在此设备的共享钥匙串中，供主应用与分享入口使用，不存入相册、历史记录或 iCloud 同步。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("截图换装") {
                    Text("在任意 App 使用系统截屏 → 打开截图预览 → 分享 → 衣橱快截 → 确认图片并换装。")
                    Text("首次可在分享菜单的「更多」中启用衣橱快截。分享页面请保持打开，直到生成完成。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }.navigationTitle("设置")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("返回") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存模型设置") {
                            do { try model.savePreferences(draft); dismiss() }
                            catch { self.error = (error as? ToolError)?.localizedDescription ?? "无法保存设置。" }
                        }
                    }
                }
                .onAppear { draft = model.preferences }
                .onChange(of: personSelection) { _, selection in
                    guard let selection else { return }
                    Task {
                        do { if let bytes = try await selection.loadTransferable(type: Data.self) { await model.importPerson(bytes); error = model.error } }
                        catch { self.error = "无法读取人物图片。" }
                        personSelection = nil
                    }
                }
                .confirmationDialog("移除默认换装人物？", isPresented: $removingPerson, titleVisibility: .visible) {
                    Button("移除人物", role: .destructive) {
                        do { try model.storage?.removeDefaultPerson(); model.person = nil }
                        catch { self.error = "无法移除默认人物，请重试。" }
                    }
                }
                .fileImporter(isPresented: $importTemplate, allowedContentTypes: [.json, .plainText]) { result in
                    do {
                        let url = try result.get()
                        let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                        guard values.isRegularFile == true, (values.fileSize ?? Int.max) < 2_000_000 else { throw ToolError.message("Invalid template") }
                        let text = try String(contentsOf: url, encoding: .utf8)
                        guard let first = text.firstIndex(of: "{") else { throw ToolError.message("Invalid template") }
                        struct Template: Decodable { let client_config: PersonalModel }
                        let custom = try JSONDecoder().decode(Template.self, from: Data(text[first...].utf8)).client_config
                        try custom.validate()
                        draft.usePersonalModel = true
                        draft.provider = custom.provider; draft.baseURL = custom.base_url
                        draft.apiKey = custom.api_key; draft.model = custom.model
                        error = nil
                    } catch { self.error = "无法读取模板，请选择包含完整 client_config 的请求参数 JSON 或 TXT 文件。" }
                }
        }
    }
}
