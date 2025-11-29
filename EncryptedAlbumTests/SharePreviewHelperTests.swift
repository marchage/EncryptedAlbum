import XCTest
#if canImport(EncryptedAlbum)
@testable import EncryptedAlbum
#elseif canImport(EncryptedAlbum_iOS)
@testable import EncryptedAlbum_iOS
#endif

final class SharePreviewHelperTests: XCTestCase {

    func testCountSupportedAttachments_withFileURL() throws {
        let fm = FileManager.default
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let f1 = dir.appendingPathComponent("a.jpg")
        try Data([0x01, 0x02]).write(to: f1)
        let f2 = dir.appendingPathComponent("b.mov")
        try Data([0x03, 0x04]).write(to: f2)

        let p1 = NSItemProvider(contentsOf: f1)!
        let p2 = NSItemProvider(contentsOf: f2)!

        let item = NSExtensionItem()
        item.attachments = [p1, p2]

        let count = SharePreviewHelper.countSupportedAttachments(in: [item])
        XCTAssertEqual(count, 2)
    }

    func testCountSupportedAttachments_ignoresUnsupportedTypes() throws {
        // Create a provider for plain text (not image/movie/file-url), should not be counted
        let provider = NSItemProvider(object: NSString(string: "hello"))
        let item = NSExtensionItem()
        item.attachments = [provider]
        let count = SharePreviewHelper.countSupportedAttachments(in: [item])
        XCTAssertEqual(count, 0)
    }
}
