import SwiftUI
import UIKit

@MainActor
struct MobileCatalogView: View {
    @ObservedObject var model: MobileSession
    @Environment(\.dismiss) private var dismiss
    @State private var catalog: GarmentCatalog?
    @State private var category: String?
    @State private var query = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            VStack {
                if let catalog {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            Button("全部") { category = nil }.buttonStyle(.bordered)
                            ForEach(catalog.categories, id: \.self) { name in
                                Button(name) { category = name }.buttonStyle(.bordered).tint(category == name ? .mint : .gray)
                            }
                        }.padding(.horizontal)
                    }
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 16) {
                            ForEach(catalog.filtered(category: category, query: query)) { garment in
                                Button {
                                    Task {
                                        do {
                                            let url = try catalog.assetURL(garment.image)
                                            let bytes = try Data(contentsOf: url, options: .mappedIfSafe)
                                            await model.importGarment(bytes, name: garment.id)
                                            if model.error == nil { dismiss() }
                                            else { error = model.error }
                                        } catch { self.error = "无法读取这件服装，请重试。" }
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        if let url = try? catalog.assetURL(garment.thumbnail), let image = UIImage(contentsOfFile: url.path) {
                                            Image(uiImage: image).resizable().scaledToFit().frame(height: 180)
                                        }
                                        Text(garment.id).font(.caption).foregroundStyle(.primary)
                                        Text(garment.category).font(.caption2).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity).padding(8).background(.secondary.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 12))
                                }.buttonStyle(.plain).disabled(model.importing)
                            }
                        }.padding()
                    }
                } else { ProgressView("正在读取图库…") }
                if let error { Text(error).font(.caption).foregroundStyle(.red).padding() }
            }.navigationTitle("服装图库").navigationBarTitleDisplayMode(.inline)
                .searchable(text: $query, prompt: "编号、旗袍、裙子、blue…")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
                .task {
                    do { catalog = try GarmentCatalog.bundled() }
                    catch { self.error = "内置图库缺失，请重新构建应用。" }
                }
        }
    }
}
