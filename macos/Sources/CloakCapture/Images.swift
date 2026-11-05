import AppKit
import ImageIO
import UniformTypeIdentifiers

struct Photo: Identifiable {
    let id = UUID()
    let name: String
    let image: NSImage
    let jpeg: Data

    static func load(_ url: URL) throws -> Photo {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, (values.fileSize ?? Int.max) <= 20_000_000 else {
            throw ToolError.message("请选择不超过 20 MB 的本地图片。")
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = metadata[kCGImagePropertyPixelWidth] as? Int,
              let height = metadata[kCGImagePropertyPixelHeight] as? Int,
              width >= 256, height >= 256, width <= 20000, height <= 20000,
              Int64(width) * Int64(height) <= 40_000_000 else {
            throw ToolError.message("图片无效，或尺寸超出限制（最小 256 × 256，最大 4000 万像素）。")
        }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                      kCGImageSourceThumbnailMaxPixelSize: 2048,
                                      kCGImageSourceCreateThumbnailWithTransform: true]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ToolError.message("无法读取图片，请选择 PNG、JPEG、WebP 或 HEIC 文件。")
        }
        return try from(cg, name: url.deletingPathExtension().lastPathComponent)
    }

    static func from(_ cg: CGImage, name: String) throws -> Photo {
        guard cg.width >= 256, cg.height >= 256 else { throw ToolError.message("选区太小，请至少截取 256 × 256 像素。") }
        let longest = CGFloat(max(cg.width, cg.height))
        let scale = min(1, 2048 / longest)
        let width = Int(CGFloat(cg.width) * scale), height = Int(CGFloat(cg.height) * scale)
        guard width >= 256, height >= 256 else { throw ToolError.message("图片过于狭长，请选择更接近服装比例的选区。") }
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw ToolError.message("无法处理图片。")
        }
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let output = context.makeImage(),
              let jpeg = NSBitmapImageRep(cgImage: output).representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
            throw ToolError.message("图片编码失败。")
        }
        return Photo(name: name, image: NSImage(cgImage: output, size: .zero), jpeg: jpeg)
    }

    static func result(_ data: Data) throws -> NSImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = metadata[kCGImagePropertyPixelWidth] as? Int,
              let height = metadata[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 20000, height <= 20000,
              Int64(width) * Int64(height) <= 40_000_000,
              let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ToolError.message("返回内容不是可显示的图片，或像素超出限制。")
        }
        return NSImage(cgImage: cg, size: .zero)
    }
}
