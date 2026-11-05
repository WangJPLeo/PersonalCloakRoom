import Foundation
import UniformTypeIdentifiers

enum ShareImageLoader {
    static func load(from items: [NSExtensionItem]) async throws -> Data {
        let providers = items.flatMap { $0.attachments ?? [] }
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }),
              let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) else {
            throw ToolError.message("请从截图预览或照片中分享一张图片；网页链接不能用作服装截图。")
        }
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                guard error == nil, let url, url.isFileURL,
                      let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                      values.isRegularFile == true, (values.fileSize ?? Int.max) <= 20_000_000 else {
                    continuation.resume(throwing: ToolError.message("无法读取分享图片，请选择不超过 20 MB 的照片或截图。"))
                    return
                }
                do {
                    // The provider's URL expires with this callback; copy its bounded data now.
                    let data = try Data(contentsOf: url)
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: ToolError.message("分享图片暂不可用，请重新截屏后分享。"))
                }
            }
        }
    }
}
