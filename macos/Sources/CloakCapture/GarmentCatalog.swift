import Foundation
import ImageIO
#if canImport(AppKit)
import AppKit
#endif

struct CatalogGarment: Identifiable, Codable {
    let id: String
    let category: String
    let keywords: String
    let image: String
    let thumbnail: String

    func matches(_ query: String) -> Bool {
        let searchable = "\(id) \(category) \(keywords)".lowercased()
        let aliases: [String: [String]] = [
            "连衣裙": ["dress"], "裙子": ["dress", "skirt"], "外套": ["coat", "jacket"],
            "衬衫": ["blouse", "shirt"], "裤子": ["pants", "jeans"], "针织": ["knit"],
            "蓝色": ["blue", "navy"], "白色": ["white", "ivory"], "黑色": ["black"],
            "红色": ["red", "burgundy"], "粉色": ["pink"], "绿色": ["green", "mint"],
            "黄色": ["yellow"], "旗袍": ["旗袍", "qipao", "cheongsam"]
        ]
        return query.lowercased().split(whereSeparator: { $0.isWhitespace }).allSatisfy { token in
            ([String(token)] + (aliases[String(token)] ?? [])).contains { searchable.contains($0) }
        }
    }
}

struct GarmentCatalog {
    let items: [CatalogGarment]
    let root: URL

    var categories: [String] {
        let known = ["春", "夏", "秋", "冬", "派对", "泳装", "中式"]
        let available = Set(items.map(\.category))
        return known.filter { available.contains($0) } + available.subtracting(known).sorted()
    }

    init(root: URL) throws {
        self.root = root.resolvingSymlinksInPath()
        let data = try Data(contentsOf: root.appendingPathComponent("catalog.json"))
        let entries = try JSONDecoder().decode([CatalogGarment].self, from: data)
        guard !entries.isEmpty, entries.count <= 10000, Set(entries.map(\.id)).count == entries.count else {
            throw ToolError.message("内置服装图库数据无效，请重新构建应用。")
        }
        items = entries
        for item in items {
            _ = try assetURL(item.image)
            _ = try assetURL(item.thumbnail)
        }
    }

    static func bundled() throws -> GarmentCatalog {
        guard let resources = Bundle.main.resourceURL else { throw ToolError.message("找不到内置图库，请重新打包应用。") }
        do { return try GarmentCatalog(root: resources.appendingPathComponent("Gallery", isDirectory: true)) }
        catch { throw ToolError.message("内置图库未完整打包，请使用启动脚本重新构建应用。") }
    }

    func assetURL(_ path: String) throws -> URL {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 2, ["images", "thumbs"].contains(String(components[0])),
              path.range(of: #"^(images|thumbs)/[A-Za-z0-9_-]{1,64}\.(webp|png|jpg|jpeg)$"#, options: .regularExpression) != nil else {
            throw ToolError.message("图库图片路径无效。")
        }
        let url = root.appendingPathComponent(path).resolvingSymlinksInPath()
        guard url.path.hasPrefix(root.path + "/"), FileManager.default.fileExists(atPath: url.path) else {
            throw ToolError.message("图库图片缺失，请重新构建应用。")
        }
        return url
    }

    func filtered(category: String?, query: String) -> [CatalogGarment] {
        items.filter { (category == nil || $0.category == category) && $0.matches(query) }
    }
}

#if canImport(AppKit)
@MainActor
final class CatalogImages {
    static let shared = CatalogImages()
    private let cache = NSCache<NSString, NSImage>()

    private init() { cache.totalCostLimit = 24 * 1024 * 1024 }

    func image(at url: URL, maxPixels: Int) async -> NSImage? {
        let key = "\(url.path):\(maxPixels)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let bytes = await Task.detached(priority: .userInitiated) { () -> Data? in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true, (values.fileSize ?? Int.max) <= 32_000_000 else { return nil }
            return try? Data(contentsOf: url, options: .mappedIfSafe)
        }.value
        guard !Task.isCancelled, let bytes, let source = CGImageSourceCreateWithData(bytes as CFData, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                      kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                                      kCGImageSourceCreateThumbnailWithTransform: true]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cg, size: .zero)
        cache.setObject(image, forKey: key, cost: cg.width * cg.height * 4)
        return image
    }
}
#endif
