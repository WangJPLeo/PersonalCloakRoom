import SwiftUI

@MainActor
struct MobileHistoryView: View {
    @ObservedObject var model: MobileSession
    @State private var deleting: TryonRecord?
    var body: some View {
        NavigationStack {
            List {
                if model.records.isEmpty {
                    Text("还没有换装记录。成功生成后会自动保存，分享入口生成的图片也会出现在这里。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                ForEach(model.records) { record in
                    NavigationLink {
                        MobileHistoryDetail(model: model, record: record)
                    } label: {
                        HStack {
                            HistoryPicture(storage: model.storage, record: record, kind: .result, height: 90).frame(width: 65)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(record.garmentName).font(.headline)
                                Text(record.createdAt, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                                Text(record.model).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }.swipeActions { Button("删除", role: .destructive) { deleting = record } }
                }
            }.navigationTitle("换装记录").refreshable { model.reload() }
                .onAppear { model.reload() }
                .alert("删除这条换装记录？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { record in
                    Button("取消", role: .cancel) { deleting = nil }
                    Button("删除", role: .destructive) {
                        do { try model.storage?.history.delete(record); model.reload() }
                        catch { model.error = "无法删除本机记录，请重试。" }
                    }
                } message: { _ in Text("将删除本机保存的结果和当次输入图片，无法撤销。") }
        }
    }
}

@MainActor
private struct HistoryPicture: View {
    let storage: MobileStorage?
    let record: TryonRecord
    let kind: HistoryImage
    var height: CGFloat
    @State private var data: Data?
    var body: some View {
        MobilePicture(data: data, height: height)
            .task(id: record.id) {
                guard let storage, let url = try? storage.history.imageURL(record, kind: kind) else { return }
                data = try? storage.readImage(url)
            }
    }
}

@MainActor
private struct MobileHistoryDetail: View {
    @ObservedObject var model: MobileSession
    let record: TryonRecord
    @State private var result: Data?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MobilePicture(data: result, height: 420)
                HStack {
                    VStack { HistoryPicture(storage: model.storage, record: record, kind: .person, height: 140); Text("原人物").font(.caption) }
                    VStack { HistoryPicture(storage: model.storage, record: record, kind: .garment, height: 140); Text("原服装").font(.caption) }
                }
                Text(record.createdAt, format: .dateTime.year().month().day().hour().minute()).font(.footnote).foregroundStyle(.secondary)
                Text("\(record.size) · \(record.model)").font(.caption).foregroundStyle(.secondary)
                if !record.prompt.isEmpty { Text(record.prompt).font(.callout) }
                Button("保存到相册") { if let result { Task { await model.saveToPhotos(result) } } }.disabled(result == nil)
                Text(model.status).font(.caption).foregroundStyle(.secondary)
                if let error = model.error { Text(error).font(.caption).foregroundStyle(.red) }
            }.padding()
        }.navigationTitle("换装结果").navigationBarTitleDisplayMode(.inline)
            .task {
                guard let storage = model.storage, let url = try? storage.history.imageURL(record, kind: .result) else { return }
                result = try? storage.readImage(url)
            }
    }
}
