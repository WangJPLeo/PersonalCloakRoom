import Foundation

struct TryonRecord: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let personName: String
    let garmentName: String
    let model: String
    let size: String
    let prompt: String
    let mime: String

    var fileExtension: String { mime == "image/jpeg" ? "jpg" : mime == "image/webp" ? "webp" : "png" }
}

enum HistoryImage: String { case result, person, garment }

struct HistoryStore {
    let root: URL

    static func local() -> HistoryStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return HistoryStore(root: support.appendingPathComponent("app.personalcloakroom.capture/History", isDirectory: true))
    }

    func records() throws -> [TryonRecord] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey], options: .skipsHiddenFiles)
            .compactMap { directory -> TryonRecord? in
                guard let id = UUID(uuidString: directory.lastPathComponent),
                      (try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false else { return nil }
                let metadata = directory.appendingPathComponent("record.json")
                guard (try? metadata.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false,
                      let size = try? metadata.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 32768,
                      let bytes = try? Data(contentsOf: metadata),
                      let record = try? JSONDecoder().decode(TryonRecord.self, from: bytes), record.id == id,
                      ["image/png", "image/jpeg", "image/webp"].contains(record.mime),
                      (try? imageURL(record, kind: .result)) != nil else { return nil }
                return record
            }.sorted { $0.createdAt > $1.createdAt }
    }

    func save(record: TryonRecord, result: Data, person: Data, garment: Data) throws {
        guard ["image/png", "image/jpeg", "image/webp"].contains(record.mime),
              !result.isEmpty, result.count <= 32_000_000,
              !person.isEmpty, person.count <= 8_388_608,
              !garment.isEmpty, garment.count <= 8_388_608,
              record.prompt.count <= 1000 else { throw ToolError.message("记录图片或描述超出保存限制。") }
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        let pending = root.appendingPathComponent(".pending-\(record.id.uuidString)", isDirectory: true)
        let final = root.appendingPathComponent(record.id.uuidString, isDirectory: true)
        guard !manager.fileExists(atPath: final.path), !manager.fileExists(atPath: pending.path) else {
            throw ToolError.message("换装记录编号重复，已保留现有记录。")
        }
        try manager.createDirectory(at: pending, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? manager.removeItem(at: pending) }
        for (filename, data) in [("result.\(record.fileExtension)", result), ("person.jpg", person),
                                 ("garment.jpg", garment), ("record.json", try JSONEncoder().encode(record))] {
            let url = pending.appendingPathComponent(filename)
            var options: Data.WritingOptions = [.atomic]
            #if os(iOS)
            options.insert(.completeFileProtectionUntilFirstUserAuthentication)
            #endif
            try data.write(to: url, options: options)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        try manager.moveItem(at: pending, to: final)
    }

    func imageURL(_ record: TryonRecord, kind: HistoryImage) throws -> URL {
        let directory = root.appendingPathComponent(record.id.uuidString, isDirectory: true)
        let filename = kind == .result ? "result.\(record.fileExtension)" : "\(kind.rawValue).jpg"
        let url = directory.appendingPathComponent(filename)
        let canonical = root.resolvingSymlinksInPath()
        guard url.resolvingSymlinksInPath().path.hasPrefix(canonical.path + "/"),
              (try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false,
              (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false,
              FileManager.default.fileExists(atPath: url.path) else { throw ToolError.message("历史图片缺失或无法读取。") }
        return url
    }

    func delete(_ record: TryonRecord) throws {
        let directory = root.appendingPathComponent(record.id.uuidString, isDirectory: true)
        // Only remove this record's UUID directory; never follow a substituted link.
        try FileManager.default.removeItem(at: directory)
    }
}
