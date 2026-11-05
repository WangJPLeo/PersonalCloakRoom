import SwiftUI

struct CatalogImageView: View {
    let url: URL?
    let maxPixels: Int
    @State private var image: NSImage?
    var body: some View {
        ZStack {
            Color.white.opacity(0.045)
            if let image { Image(nsImage: image).resizable().scaledToFit().padding(7) }
            else { Image(systemName: "tshirt").font(.title).foregroundStyle(.secondary) }
        }
        .task(id: url) {
            image = nil
            if let url {
                let loaded = await CatalogImages.shared.image(at: url, maxPixels: maxPixels)
                guard !Task.isCancelled else { return }
                image = loaded
            }
        }
    }
}

struct GarmentGalleryView: View {
    @ObservedObject var studio: Studio
    let catalog: GarmentCatalog
    @Environment(\.dismiss) private var dismiss
    @State private var category: String?
    @State private var query = ""
    @State private var selectedID: String?
    @State private var selectionError: String?
    private let accent = Color(red: 0.35, green: 0.88, blue: 0.66)
    private var filtered: [CatalogGarment] { catalog.filtered(category: category, query: query) }
    private var selected: CatalogGarment? { catalog.items.first { $0.id == selectedID } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(alignment: .top, spacing: 18) {
                categories
                garmentGrid
                selectionPreview
            }.padding(20)
            Divider()
            footer
        }
        .frame(width: 980, height: 650)
        .background(Color(red: 0.065, green: 0.075, blue: 0.085))
        .onAppear { selectedID = studio.garmentCatalogID ?? catalog.items.first?.id }
        .onChange(of: category) { _, _ in updateSelection() }
        .onChange(of: query) { _, _ in updateSelection() }
    }

    private var header: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("服装图库").font(.title2.bold())
                Text("\(catalog.items.count) 套服装 · 离线可选").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            TextField("搜索编号或关键词，如 旗袍、裙子、blue", text: $query)
                .textFieldStyle(.roundedBorder).frame(width: 370)
        }.padding(22)
    }

    private var categories: some View {
        VStack(alignment: .leading, spacing: 8) {
            categoryButton("全部", value: nil)
            ForEach(catalog.categories, id: \.self) { name in categoryButton(name, value: name) }
            Spacer()
        }.frame(width: 85)
    }

    private func categoryButton(_ title: String, value: String?) -> some View {
        Button { category = value } label: {
            HStack {
                Text(title)
                Spacer()
                if category == value { Image(systemName: "checkmark").font(.caption2) }
            }.padding(9).frame(maxWidth: .infinity)
                .background(category == value ? accent.opacity(0.14) : .clear)
                .foregroundStyle(category == value ? accent : .secondary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain)
    }

    private var garmentGrid: some View {
        ScrollView {
            if filtered.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").font(.largeTitle)
                    Text("没有匹配的服装").font(.headline)
                    Text("试试其他关键词，或切换到「全部」。").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.top, 120)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 155))], spacing: 12) {
                    ForEach(filtered) { item in
                        Button { selectedID = item.id; selectionError = nil } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                CatalogImageView(url: try? catalog.assetURL(item.thumbnail), maxPixels: 300)
                                    .frame(height: 145).clipShape(RoundedRectangle(cornerRadius: 9))
                                HStack {
                                    Text(item.id).font(.system(size: 10, design: .monospaced))
                                    Spacer()
                                    if selectedID == item.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(accent) }
                                }
                                Text(item.category).font(.caption2).foregroundStyle(.secondary)
                            }.padding(7)
                                .background(selectedID == item.id ? accent.opacity(0.08) : .clear)
                                .clipShape(RoundedRectangle(cornerRadius: 11))
                                .overlay(RoundedRectangle(cornerRadius: 11).stroke(selectedID == item.id ? accent : .clear, lineWidth: 2))
                        }.buttonStyle(.plain)
                    }
                }.padding(3)
            }
        }.frame(maxWidth: .infinity)
    }

    private var selectionPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("服装预览").font(.headline)
            CatalogImageView(url: selected.flatMap { try? catalog.assetURL($0.image) }, maxPixels: 900)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .frame(maxHeight: .infinity)
            if let selected {
                Text(selected.id).font(.system(.headline, design: .monospaced))
                Text(selected.category).font(.caption).foregroundStyle(accent)
                Text(selected.keywords).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
            }
        }.frame(width: 220)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let selectionError { Text(selectionError).font(.caption).foregroundStyle(.red).lineLimit(2) }
            else { Text("当前显示 \(filtered.count) 套 · 选中后点击使用").font(.caption).foregroundStyle(.secondary) }
            Spacer()
            Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
            Button("使用这件服装") {
                guard let selected else { return }
                do {
                    try studio.chooseCatalogGarment(selected, from: catalog)
                    dismiss()
                } catch { selectionError = "无法读取这件服装，请检查图库文件后重试。" }
            }.buttonStyle(.borderedProminent).tint(accent).foregroundStyle(.black)
                .disabled(selected == nil).keyboardShortcut(.defaultAction)
        }.padding(20)
    }

    private func updateSelection() {
        selectionError = nil
        if !filtered.contains(where: { $0.id == selectedID }) { selectedID = filtered.first?.id }
    }
}
