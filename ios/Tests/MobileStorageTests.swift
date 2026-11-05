import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum TestFailure: Error { case failed(String) }
func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw TestFailure.failed(message) }
}

func fixture(width: Int = 512, height: Int = 768, transparent: Bool = false) throws -> Data {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    if !transparent {
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
    let bytes = NSMutableData()
    let destination = CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, [kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "private-fixture"]] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw TestFailure.failed("Fixture encoding") }
    return bytes as Data
}

@main
struct MobileStorageTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cloak-mobile-tests-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = MobileStorage(root: root)
        let share = MobileStorage(root: root)
        let initialPerson = try app.defaultPerson()
        try expect(initialPerson == nil, "New installation starts without a default person")
        let jpeg = try MobileImage.prepare(fixture())
        try app.setDefaultPerson(jpeg)
        let sharePerson = try share.defaultPerson()
        try expect(sharePerson == jpeg, "Share entry reads the persistent default person")
        let replacement = try MobileImage.prepare(fixture(width: 640, height: 960))
        try share.setDefaultPerson(replacement)
        let newLaunch = MobileStorage(root: root)
        let reloaded = try newLaunch.defaultPerson()
        try expect(reloaded == replacement, "Replacing the person survives a new session")
        print("PASS default person persists, is shared, and can be replaced")

        let source = try MobileImage.validatedSource(jpeg)
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let exif = properties?[kCGImagePropertyExifDictionary] as? [CFString: Any]
        try expect(exif?[kCGImagePropertyExifUserComment] == nil, "Original metadata is removed before upload")
        let large = try MobileImage.prepare(fixture(width: 2400, height: 3000))
        let resized = try MobileImage.validatedSource(large)
        let image = CGImageSourceCreateImageAtIndex(resized, 0, nil)!
        try expect(max(image.width, image.height) == 2048, "High resolution input is downsampled")
        let flattened = try MobileImage.prepare(fixture(width: 300, height: 300, transparent: true))
        let flatSource = try MobileImage.validatedSource(flattened)
        let flat = CGImageSourceCreateImageAtIndex(flatSource, 0, nil)!
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(flat, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let pixel = context.data!.assumingMemoryBound(to: UInt8.self)
        try expect(pixel[0] > 245 && pixel[1] > 245 && pixel[2] > 245, "Transparent clothing gets a white background")
        print("PASS image scaling, metadata removal, and transparency handling")

        for bytes in [Data("not an image".utf8), try fixture(width: 32, height: 32), Data(repeating: 0, count: 20_000_001)] {
            do { _ = try MobileImage.prepare(bytes); throw TestFailure.failed("Invalid input was accepted") }
            catch is ToolError { }
        }
        print("PASS malformed, tiny, and oversized inputs are rejected")

        let record = TryonRecord(id: UUID(), createdAt: Date(), personName: "默认换装人物", garmentName: "截图服装",
                                 model: "test-model", size: "1024x1536", prompt: "自然光", mime: "image/jpeg")
        try share.history.save(record: record, result: jpeg, person: replacement, garment: jpeg)
        let records = try newLaunch.history.records()
        try expect(records.count == 1 && records.first?.id == record.id, "Share result survives reopening the main app")
        let savedPerson = try Data(contentsOf: newLaunch.history.imageURL(record, kind: .person))
        try expect(savedPerson == replacement, "History retains the actual person used for this request")
        let metadata = try String(contentsOf: root.appendingPathComponent("History/\(record.id.uuidString)/record.json"), encoding: .utf8)
        try expect(!metadata.contains("api_key") && !metadata.contains("token") && !metadata.contains("base_url"), "History metadata excludes credentials")
        let permissions = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("default-person.jpg").path)[.posixPermissions] as? NSNumber
        try expect(permissions?.intValue == 0o600, "Default photo file is private")
        try app.removeDefaultPerson()
        let removedPerson = try share.defaultPerson()
        let remaining = try share.history.records()
        try expect(removedPerson == nil && remaining.count == 1, "Changing default-person settings preserves existing records")
        try app.history.delete(record)
        let deleted = try share.history.records()
        try expect(deleted.isEmpty, "Deleting a history record is visible in both entries")
        print("PASS shared history reload, input snapshots, private metadata, and deletion")
        print("All mobile storage tests passed; no real photos, network, or Keychain writes were used.")
    }
}
