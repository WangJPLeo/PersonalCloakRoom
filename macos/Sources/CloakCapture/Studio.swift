import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class Studio: ObservableObject {
    let configuration = LocalConfiguration.load()
    @Published var people: [Photo] = []
    @Published var personID: UUID?
    @Published var garment: Photo?
    @Published var resultImage: NSImage?
    @Published var resultData: Data?
    @Published var resultMIME = "image/png"
    @Published var prompt = ""
    @Published var size = "1024x1536"
    @Published var busy = false
    @Published var elapsed = 0
    @Published var status = "截取喜欢的服装，为选中的人物换装。"
    @Published var error: String?
    @Published var showingCapturePermissionHelp = false
    @Published var showingGarmentGallery = false
    @Published var garmentCatalog: GarmentCatalog?
    @Published var garmentCatalogID: String?
    @Published var showingHistory = false
    @Published var history: [TryonRecord] = []
    let historyStore: HistoryStore
    var captureAction: (() -> Void)?
    var restartAction: (() -> Void)?
    private var job: Task<Void, Never>?
    private var timer: Timer?

    var selectedPerson: Photo? { people.first { $0.id == personID } }
    var canGenerate: Bool { selectedPerson != nil && garment != nil && !busy && prompt.count <= 1000 }

    var isPresentingSheet: Bool { showingCapturePermissionHelp || showingGarmentGallery || showingHistory }

    init(historyStore: HistoryStore = .local()) {
        self.historyStore = historyStore
    }

    func openGarmentGallery() {
        do {
            if garmentCatalog == nil { garmentCatalog = try GarmentCatalog.bundled() }
            showingGarmentGallery = true
        } catch { self.error = error.localizedDescription }
    }

    func chooseCatalogGarment(_ item: CatalogGarment, from catalog: GarmentCatalog) throws {
        garment = try Photo.load(catalog.assetURL(item.image))
        garmentCatalogID = item.id
        clearResult()
        status = "已选择图库服装 \(item.id)，请选择人物后开始换装。"
    }

    func refreshHistory() async {
        let store = historyStore
        do { history = try await Task.detached(priority: .utility) { try store.records() }.value }
        catch { status = "无法读取本机换装记录，请检查本机存储权限。" }
    }

    func deleteHistory(_ record: TryonRecord) async throws {
        let store = historyStore
        try await Task.detached(priority: .utility) { try store.delete(record) }.value
        await refreshHistory()
    }

    func choosePeople() {
        let panel = NSOpenPanel()
        panel.title = "选择模特或人物照片"
        panel.allowedContentTypes = [.png, .jpeg, .heic, .webP]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        do {
            let photos = try panel.urls.map(Photo.load)
            guard people.count + photos.count <= 20 else { throw ToolError.message("最多同时保留 20 张人物照片，请先移除不需要的人物。") }
            people.append(contentsOf: photos)
            if personID == nil { personID = photos.first?.id }
        } catch { self.error = error.localizedDescription }
    }

    func chooseGarment() {
        let panel = NSOpenPanel()
        panel.title = "选择服装图片"
        panel.allowedContentTypes = [.png, .jpeg, .heic, .webP]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { garment = try Photo.load(url); garmentCatalogID = nil; clearResult() }
        catch { self.error = error.localizedDescription }
    }

    func clearResult() { resultImage = nil; resultData = nil }

    func generate() {
        guard canGenerate, let person = selectedPerson, let garment else { return }
        do {
            let endpoint = try configuration.policy.endpoint(configuration.serviceURL)
            let body = try configuration.makeBody(person: person.jpeg.base64EncodedString(),
                                                  garment: garment.jpeg.base64EncodedString(),
                                                  size: size, prompt: prompt)
            // Validate synchronously so invalid bundled configuration does not start a spinner.
            _ = try TryonService.makeRequest(endpoint: endpoint, body: body, token: configuration.accessToken)
            busy = true
            elapsed = 0
            error = nil
            clearResult()
            status = "正在生成，通常需要 30–120 秒…"
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.elapsed += 1 }
            }
            let accessToken = configuration.accessToken
            let savedModel = configuration.personalModel?.model ?? configuration.serverModel
            let historyStore = self.historyStore
            job = Task {
                do {
                    let (data, mime) = try await TryonService.generate(endpoint: endpoint, body: body, token: accessToken)
                    try Task.checkCancellation()
                    let image = try Photo.result(data)
                    resultData = data
                    resultMIME = mime
                    resultImage = image
                    status = "换装完成，正在保存记录…"
                    let record = TryonRecord(id: UUID(), createdAt: Date(), personName: person.name,
                                             garmentName: garment.name, model: savedModel,
                                             size: body.size, prompt: body.custom_prompt, mime: mime)
                    do {
                        try await Task.detached(priority: .utility) {
                            try historyStore.save(record: record, result: data, person: person.jpeg, garment: garment.jpeg)
                        }.value
                        guard !Task.isCancelled else { return }
                        status = "换装完成，已保存到本机历史记录。"
                    } catch {
                        guard !Task.isCancelled else { return }
                        status = "换装完成，但历史记录保存失败；请先手动保存当前图片。"
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    self.error = TryonService.errorMessage(error)
                    status = "生成失败，请稍后重试。"
                }
                busy = false
                timer?.invalidate()
                timer = nil
                job = nil
            }
        } catch { self.error = error.localizedDescription }
    }

    func cancel() {
        job?.cancel()
        job = nil
        timer?.invalidate()
        timer = nil
        busy = false
        status = "已取消等待。已提交的服务端任务可能仍会完成。"
    }

    func save() {
        guard let resultData else { return }
        let panel = NSSavePanel()
        let ext = resultMIME == "image/jpeg" ? "jpg" : resultMIME == "image/webp" ? "webp" : "png"
        panel.allowedContentTypes = [UTType(filenameExtension: ext) ?? .png]
        panel.nameFieldStringValue = "换装结果.\(ext)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try resultData.write(to: url, options: .atomic); status = "图片已保存。" }
        catch { self.error = "无法保存图片，请检查目标文件夹权限。" }
    }

    func copy() {
        guard let resultImage else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([resultImage])
        status = "结果已复制到剪贴板。"
    }
}

struct StudioView: View {
    @ObservedObject var studio: Studio
    private let accent = Color(red: 0.35, green: 0.88, blue: 0.66)

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(alignment: .top, spacing: 22) {
                controls
                resultPreview
            }.padding(24)
            Divider()
            footer
        }
        .frame(minWidth: 900, minHeight: 650)
        .background(Color(red: 0.065, green: 0.075, blue: 0.085))
        .preferredColorScheme(.dark)
        .sheet(isPresented: $studio.showingCapturePermissionHelp) { CapturePermissionView(studio: studio) }
        .sheet(isPresented: $studio.showingGarmentGallery) {
            if let catalog = studio.garmentCatalog { GarmentGalleryView(studio: studio, catalog: catalog) }
        }
        .sheet(isPresented: $studio.showingHistory) { HistoryView(studio: studio) }
        .alert("操作未完成", isPresented: Binding(get: { studio.error != nil }, set: { if !$0 { studio.error = nil } })) {
            Button("好") { studio.error = nil }
        } message: { Text(studio.error ?? "") }
    }

    private var header: some View {
            HStack(spacing: 12) {
                Image(systemName: "tshirt.fill").font(.title2).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("衣橱快截").font(.title2.bold())
                    Text("CLOAK CAPTURE / 随手一截，即刻试穿").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { studio.showingHistory = true } label: { Label("换装记录", systemImage: "clock.arrow.circlepath") }
                    .disabled(studio.busy)
            }.padding(24)
    }

    private var controls: some View {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        step("01", "选择服装", hint: "从图库选衣，也可截图或导入图片")
                        preview(studio.garment?.image, symbol: "viewfinder", caption: "屏幕上看到的，都是灵感", height: 195)
                        HStack {
                            Button { studio.openGarmentGallery() } label: { Label("图库选衣", systemImage: "square.grid.2x2") }
                            Button { studio.captureAction?() } label: { Label("重新截图", systemImage: "crop") }
                            Button("导入") { studio.chooseGarment() }
                        }
                        Divider()
                        HStack {
                            step("02", "选择人物", hint: "导入全身或半身照片，点击切换")
                            Spacer()
                            Button { studio.choosePeople() } label: { Image(systemName: "plus") }
                                .help("导入模特或人物照片，可多选")
                        }
                        if studio.people.isEmpty {
                            Button { studio.choosePeople() } label: {
                                preview(nil, symbol: "person.crop.rectangle.badge.plus", caption: "添加模特 / 人物照片", height: 130)
                            }.buttonStyle(.plain)
                        } else {
                            peopleGrid
                        }
                        Divider()
                        step("03", "画面描述", hint: "可选，描述姿势、背景或光线")
                        TextEditor(text: $studio.prompt).font(.system(size: 12)).frame(height: 66)
                            .padding(5).background(.white.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius: 8))
                        HStack {
                            Picker("尺寸", selection: $studio.size) {
                                Text("竖图 2:3").tag("1024x1536")
                                Text("方图 1:1").tag("1024x1024")
                                Text("横图 3:2").tag("1536x1024")
                            }
                            Text("\(studio.prompt.count)/1000").font(.caption2)
                                .foregroundStyle(studio.prompt.count > 1000 ? .red : .secondary)
                        }
                    }.padding(2)
                }.frame(width: 285).disabled(studio.busy)
    }

    private var peopleGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72))], spacing: 10) {
            ForEach(studio.people) { person in
                Button { studio.personID = person.id; studio.clearResult() } label: {
                    VStack(spacing: 5) {
                        Image(nsImage: person.image).resizable().scaledToFill()
                            .frame(width: 72, height: 90).clipped().clipShape(RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(studio.personID == person.id ? accent : .clear, lineWidth: 3))
                        Text(person.name).font(.caption2).lineLimit(1).frame(width: 72)
                    }
                }.buttonStyle(.plain)
                    .contextMenu {
                        Button("移除人物") {
                            studio.people.removeAll { $0.id == person.id }
                            if studio.personID == person.id { studio.personID = studio.people.first?.id }
                            studio.clearResult()
                        }
                    }
            }
        }
    }

    private var resultPreview: some View {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("试穿效果").font(.headline)
                        Spacer()
                        Text(studio.resultImage == nil ? "PREVIEW" : "COMPLETED")
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(accent)
                    }
                    ZStack {
                        RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.035))
                        if let image = studio.resultImage {
                            Image(nsImage: image).resizable().scaledToFit().padding(10)
                        } else if studio.busy {
                            VStack(spacing: 18) {
                                ProgressView().controlSize(.large)
                                Text("正在为你搭配新造型").font(.headline)
                                Text("已等待 \(studio.elapsed) 秒").foregroundStyle(.secondary)
                            }
                        } else {
                            VStack(spacing: 16) {
                                Image(systemName: "sparkles.rectangle.stack").font(.system(size: 50, weight: .ultraLight)).foregroundStyle(accent.opacity(0.7))
                                Text("把灵感，穿在身上").font(.title3.weight(.medium))
                                Text("截取服装 → 选择人物 → 开始换装").font(.caption).foregroundStyle(.secondary)
                                if let person = studio.selectedPerson {
                                    Image(nsImage: person.image).resizable().scaledToFit().frame(maxHeight: 220).clipShape(RoundedRectangle(cornerRadius: 12))
                                    Text("当前人物 · \(person.name)").font(.caption2).foregroundStyle(.secondary)
                                }
                            }.padding(24)
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    HStack {
                        Label("记录保存在本机 · 密钥仅在内存中使用", systemImage: "lock.shield").font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Button { studio.copy() } label: { Image(systemName: "doc.on.doc") }.disabled(studio.resultImage == nil)
                        Button("保存图片") { studio.save() }.disabled(studio.resultData == nil)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
            HStack(spacing: 14) {
                Circle().fill(studio.busy ? .orange : accent).frame(width: 6, height: 6)
                Text(studio.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                if studio.busy {
                    Button("取消等待") { studio.cancel() }
                } else {
                    Button { studio.generate() } label: {
                        Label("开始 AI 换装", systemImage: "sparkles").font(.system(size: 13, weight: .semibold)).padding(.horizontal, 14).padding(.vertical, 5)
                    }.buttonStyle(.borderedProminent).tint(accent).foregroundStyle(.black).disabled(!studio.canGenerate)
                }
            }.padding(.horizontal, 24).padding(.vertical, 16)
    }

    private func step(_ number: String, _ title: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(number).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(accent)
                Text(title).font(.headline)
            }
            Text(hint).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func preview(_ image: NSImage?, symbol: String, caption: String, height: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.045))
            if let image { Image(nsImage: image).resizable().scaledToFit().padding(8) }
            else {
                VStack(spacing: 12) {
                    Image(systemName: symbol).font(.system(size: 28, weight: .light)).foregroundStyle(accent)
                    Text(caption).font(.caption).foregroundStyle(.secondary)
                }
            }
        }.frame(maxWidth: .infinity).frame(height: height)
    }
}

struct CapturePermissionView: View {
    @ObservedObject var studio: Studio
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("允许当前应用截图", systemImage: "rectangle.dashed.badge.record")
                .font(.title2.bold())
            Text("macOS 拒绝了当前应用的截图请求。请在「隐私与安全性 → 录屏与系统录音」（部分系统名为「屏幕录制」）中允许「衣橱快截」。")
            Text("如果开关已开启：先关闭再开启。如果仍无效，请移除旧条目，点击 + 添加当前这份应用；可用下方按钮在 Finder 中找到它。")
                .foregroundStyle(.secondary)
            HStack {
                Button("打开权限设置") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("显示当前应用") {
                    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                }
            }
            Divider()
            Text("授权后先点击重试。若系统要求重启，再退出并重新打开；重启会清空本次导入的照片。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("重启应用") { studio.restartAction?() }
                Button("已授权，重试截图") {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { studio.captureAction?() }
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 535)
    }
}

