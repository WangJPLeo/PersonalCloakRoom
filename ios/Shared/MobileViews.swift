import SwiftUI
import PhotosUI
import UIKit

@MainActor
struct MobilePicture: View {
    let data: Data?
    var height: CGFloat = 240
    @State private var picture: UIImage?
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16).fill(.secondary.opacity(0.08))
            if let picture { Image(uiImage: picture).resizable().scaledToFit().padding(8) }
            else { Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary) }
        }.frame(height: height)
            .task(id: data) {
                picture = data.flatMap { MobileImage.preview($0) }.map { UIImage(cgImage: $0) }
            }
    }
}

@MainActor
struct MobileTryonPage: View {
    @ObservedObject var model: MobileSession
    var chooseCatalog: (() -> Void)?
    @State private var personSelection: PhotosPickerItem?
    @State private var garmentSelection: PhotosPickerItem?
    @State private var cropping = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                personSection
                garmentSection
                if let error = model.error { Label(error, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.red) }
                TextField("补充描述（可选，最多 1000 字）", text: $model.prompt, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(2...4).disabled(model.busy)
                Picker("图片比例", selection: $model.size) {
                    Text("竖图").tag("1024x1536")
                    Text("方图").tag("1024x1024")
                    Text("横图").tag("1536x1024")
                }.pickerStyle(.segmented).disabled(model.busy)
                if model.busy {
                    HStack { ProgressView(); Text("正在为默认人物换装…"); Spacer(); Button("取消等待") { model.cancel() } }
                } else {
                    Button { model.generate() } label: {
                        Label("确认图片并换装", systemImage: "sparkles").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                    }.buttonStyle(.borderedProminent).disabled(!model.canGenerate)
                }
                Text(model.status).font(.footnote).foregroundStyle(.secondary)
                Text("只有点击确认后，才会向已配置的换装服务上传当前服装图片和人物照片。")
                    .font(.caption).foregroundStyle(.secondary)
                if let result = model.result {
                    Divider()
                    Text("换装结果").font(.headline)
                    MobilePicture(data: result, height: 350)
                    Button("保存到相册") { Task { await model.saveToPhotos(result) } }
                }
            }.padding()
        }
        .onChange(of: personSelection) { _, item in
            guard let item else { return }
            Task {
                do { if let data = try await item.loadTransferable(type: Data.self) { await model.importPerson(data) } }
                catch { model.error = "无法读取人物照片，请重新选择。" }
                personSelection = nil
            }
        }
        .onChange(of: garmentSelection) { _, item in
            guard let item else { return }
            Task {
                do { if let data = try await item.loadTransferable(type: Data.self) { await model.importGarment(data, name: "相册服装") } }
                catch { model.error = "无法读取服装图片，请重新选择。" }
                garmentSelection = nil
            }
        }
        .sheet(isPresented: $cropping) {
            if let data = model.garment {
                MobileCropView(data: data) { image in model.garment = image; model.result = nil }
            }
        }
    }

    private var personSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("换装人物").font(.headline)
                Spacer()
                PhotosPicker(selection: $personSelection, matching: .images) { Text(model.person == nil ? "设置人物" : "更换人物") }
                    .disabled(model.busy || model.importing || model.storage == nil)
            }
            if model.person != nil {
                MobilePicture(data: model.person, height: 150)
                Text("已作为默认人物保存，后续分享截图时自动使用。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("请选择一张清晰的全身或半身人物照。只需设置一次，以后可以随时更换。")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var garmentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("服装截图").font(.headline)
                Spacer()
                if let chooseCatalog { Button("图库") { chooseCatalog() }.disabled(model.busy || model.importing) }
                PhotosPicker(selection: $garmentSelection, matching: .images) { Text("选图") }.disabled(model.busy || model.importing)
                if model.garment != nil { Button("裁剪") { cropping = true }.disabled(model.busy || model.importing) }
            }
            if model.importing { ProgressView("正在读取图片…") }
            MobilePicture(data: model.garment)
            if model.garment == nil {
                Text("在其他 App 截图后，打开截图预览 → 分享 → 衣橱快截。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

@MainActor
struct MobileCropView: View {
    let data: Data
    let onSelect: (Data) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selection = CGRect.zero
    @State private var error: String?
    @State private var image: CGImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("拖动框选需要的服装区域").font(.callout).foregroundStyle(.secondary)
                if let image {
                    GeometryReader { geometry in
                        let frame = fittedFrame(image, in: geometry.size)
                        ZStack(alignment: .topLeading) {
                            Image(uiImage: UIImage(cgImage: image)).resizable().scaledToFit()
                                .frame(width: geometry.size.width, height: geometry.size.height)
                            if !selection.isEmpty {
                                Path { path in path.addRect(frame); path.addRect(selection) }
                                    .fill(.black.opacity(0.45), style: FillStyle(eoFill: true))
                                Rectangle().stroke(.mint, lineWidth: 2).frame(width: selection.width, height: selection.height)
                                    .position(x: selection.midX, y: selection.midY)
                            }
                        }.contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                                let rect = CGRect(x: min(value.startLocation.x, value.location.x), y: min(value.startLocation.y, value.location.y),
                                                  width: abs(value.location.x - value.startLocation.x), height: abs(value.location.y - value.startLocation.y))
                                selection = rect.intersection(frame)
                            })
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("使用选区") { crop(image, frame: frame) }.disabled(selection.isEmpty || selection.isNull)
                                }
                            }
                    }
                }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }.padding().navigationTitle("裁剪服装").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }.task { image = MobileImage.preview(data, maxPixels: 2048) }
    }

    private func fittedFrame(_ image: CGImage, in size: CGSize) -> CGRect {
        let scale = min(size.width / CGFloat(image.width), size.height / CGFloat(image.height))
        let width = CGFloat(image.width) * scale, height = CGFloat(image.height) * scale
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    private func crop(_ image: CGImage, frame: CGRect) {
        let scale = CGFloat(image.width) / frame.width
        let rect = CGRect(x: (selection.minX - frame.minX) * scale, y: (selection.minY - frame.minY) * scale,
                          width: selection.width * scale, height: selection.height * scale).integral
        guard let cropped = image.cropping(to: rect), let bytes = UIImage(cgImage: cropped).jpegData(compressionQuality: 0.92) else {
            error = "无法读取选区，请重新框选。"; return
        }
        do { onSelect(try MobileImage.prepare(bytes)); dismiss() }
        catch { self.error = (error as? ToolError)?.localizedDescription ?? "选区过小，请重新选择。" }
    }
}
