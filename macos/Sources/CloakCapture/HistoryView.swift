import SwiftUI
import UniformTypeIdentifiers

struct HistoryView: View {
    @ObservedObject var studio: Studio
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: UUID?
    @State private var error: String?
    @State private var deleting: TryonRecord?
    private var selected: TryonRecord? { studio.history.first { $0.id == selectedID } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("换装记录").font(.title2.bold())
                    Text("共 \(studio.history.count) 条 · 保存在这台 Mac 上").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(22)
            Divider()
            if studio.history.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 46, weight: .light))
                    Text("还没有换装记录").font(.headline)
                    Text("成功生成的图片会自动保存在这里，下次打开仍可查看。")
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 18) {
                    recordList
                    Divider()
                    recordPreview
                }.padding(20)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red).padding(12) }
        }
        .frame(width: 940, height: 650)
        .background(Color(red: 0.065, green: 0.075, blue: 0.085))
        .task {
            await studio.refreshHistory()
            selectedID = studio.history.first?.id
        }
        .alert("删除这条换装记录？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("取消", role: .cancel) { deleting = nil }
            Button("删除", role: .destructive) {
                guard let record = deleting else { return }
                Task {
                    do {
                        try await studio.deleteHistory(record)
                        selectedID = studio.history.first?.id
                        deleting = nil
                    } catch { self.error = "无法删除记录，请重试。" }
                }
            }
        } message: { Text("将删除本机保存的结果和这次换装的输入图片，无法撤销。") }
    }

    private var recordList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(studio.history) { record in
                    Button { selectedID = record.id; error = nil } label: {
                        HStack(spacing: 12) {
                            CatalogImageView(url: try? studio.historyStore.imageURL(record, kind: .result), maxPixels: 180)
                                .frame(width: 64, height: 86).clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 6) {
                                Text(record.garmentName).font(.caption.bold()).lineLimit(1)
                                Text(record.createdAt, format: .dateTime.month().day().hour().minute()).font(.caption2).foregroundStyle(.secondary)
                                Text(record.model).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }.padding(8).background(selectedID == record.id ? .white.opacity(0.08) : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                }
            }
        }.frame(width: 245)
    }

    private var recordPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let record = selected {
                CatalogImageView(url: try? studio.historyStore.imageURL(record, kind: .result), maxPixels: 1200)
                    .clipShape(RoundedRectangle(cornerRadius: 12)).frame(maxHeight: .infinity)
                HStack(spacing: 14) {
                    inputPreview(record, kind: .person, title: "原人物")
                    inputPreview(record, kind: .garment, title: "原服装")
                    VStack(alignment: .leading, spacing: 7) {
                        Text(record.createdAt, format: .dateTime.year().month().day().hour().minute()).font(.caption)
                        Text("\(record.size) · \(record.model)").font(.caption2).foregroundStyle(.secondary)
                        if !record.prompt.isEmpty { Text(record.prompt).font(.caption2).foregroundStyle(.secondary).lineLimit(3) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(height: 105)
                HStack {
                    Button("删除记录", role: .destructive) { deleting = record }
                    Spacer()
                    Button("复制") { export(record, copy: true) }
                    Button("保存图片…") { export(record, copy: false) }
                }
            } else { Spacer() }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func inputPreview(_ record: TryonRecord, kind: HistoryImage, title: String) -> some View {
        VStack(spacing: 3) {
            CatalogImageView(url: try? studio.historyStore.imageURL(record, kind: kind), maxPixels: 180)
                .frame(width: 70, height: 82).clipShape(RoundedRectangle(cornerRadius: 7))
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func export(_ record: TryonRecord, copy: Bool) {
        do {
            let url = try studio.historyStore.imageURL(record, kind: .result)
            if copy {
                let image = try Photo.result(Data(contentsOf: url))
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([image])
            } else {
                let panel = NSSavePanel()
                panel.allowedContentTypes = [UTType(filenameExtension: record.fileExtension) ?? .png]
                panel.nameFieldStringValue = "换装结果.\(record.fileExtension)"
                guard panel.runModal() == .OK, let destination = panel.url else { return }
                try Data(contentsOf: url).write(to: destination, options: .atomic)
            }
        } catch { self.error = "无法读取或导出这张历史图片，请重试。" }
    }
}
