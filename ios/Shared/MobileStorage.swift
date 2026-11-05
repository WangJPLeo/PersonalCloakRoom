import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

enum MobileEnvironment {
    static var groupIdentifier: String {
        (Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String) ?? "group.app.personalcloakroom.ios"
    }
}

enum MobileImage {
    static func prepare(_ data: Data) throws -> Data {
        let source = try validatedSource(data, maxBytes: 20_000_000, minimum: 256)
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                      kCGImageSourceThumbnailMaxPixelSize: 2048,
                                      kCGImageSourceCreateThumbnailWithTransform: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              image.width >= 256, image.height >= 256 else {
            throw ToolError.message("图片过于狭长或选区太小，请保留至少 256 × 256 像素。")
        }
        // JPEG has no alpha channel. Flatten transparent clothing onto white.
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw ToolError.message("无法处理这张图片。")
        }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(bounds)
        context.draw(image, in: bounds)
        guard let flattened = context.makeImage() else { throw ToolError.message("图片处理失败。") }
        let bytes = NSMutableData()
        guard let output = CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ToolError.message("无法处理这张图片。")
        }
        CGImageDestinationAddImage(output, flattened, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(output) else { throw ToolError.message("图片编码失败。") }
        return bytes as Data
    }

    static func validatedSource(_ data: Data, maxBytes: Int = 32_000_000, minimum: Int = 1) throws -> CGImageSource {
        guard !data.isEmpty, data.count <= maxBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width >= minimum, height >= minimum, width <= 20000, height <= 20000,
              Int64(width) * Int64(height) <= 40_000_000 else {
            throw ToolError.message("图片格式或尺寸不支持，请使用清晰的照片或截图（最大 20 MB 输入图片）。")
        }
        return source
    }

    static func preview(_ data: Data, maxPixels: Int = 1000) -> CGImage? {
        guard let source = try? validatedSource(data) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceCreateThumbnailWithTransform: true
        ] as CFDictionary)
    }
}

struct MobileStorage {
    let root: URL
    var history: HistoryStore { HistoryStore(root: root.appendingPathComponent("History", isDirectory: true)) }

    static func shared() throws -> MobileStorage {
        guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: MobileEnvironment.groupIdentifier) else {
            throw ToolError.message("共享存储不可用。请用同一开发团队为主应用和分享扩展配置 App Groups 后重新安装。")
        }
        return MobileStorage(root: group.appendingPathComponent("Library/Application Support/CloakRoom", isDirectory: true))
    }

    func defaultPerson() throws -> Data? {
        let file = root.appendingPathComponent("default-person.jpg")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try readImage(file, maxBytes: 8_388_608)
    }

    func setDefaultPerson(_ normalizedJPEG: Data) throws {
        _ = try MobileImage.validatedSource(normalizedJPEG, maxBytes: 8_388_608, minimum: 256)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var directory = root
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try directory.setResourceValues(resourceValues)
        let file = root.appendingPathComponent("default-person.jpg")
        var options: Data.WritingOptions = [.atomic]
        #if os(iOS)
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        try normalizedJPEG.write(to: file, options: options)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    func removeDefaultPerson() throws {
        let file = root.appendingPathComponent("default-person.jpg")
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }

    func readImage(_ file: URL, maxBytes: Int = 32_000_000) throws -> Data {
        guard file.isFileURL, let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              values.isRegularFile == true, (values.fileSize ?? Int.max) <= maxBytes else {
            throw ToolError.message("图片文件不可用或超出大小限制。")
        }
        return try Data(contentsOf: file, options: .mappedIfSafe)
    }
}
