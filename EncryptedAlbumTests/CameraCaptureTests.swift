import XCTest
import CryptoKit
import Photos
#if canImport(EncryptedAlbum)
@testable import EncryptedAlbum
#else
@testable import EncryptedAlbum_iOS
#endif

@MainActor
final class CameraCaptureTests: XCTestCase {
    var sut: AlbumManager!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        sut = AlbumManager(storage: AlbumStorage(customBaseURL: tempDir))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    func testHandleCapturedMedia_savesToAlbumWhenPreferenceEnabled() async throws {
        // Setup account
        let password = "CaptureTest123!"
        try await sut.setupPassword(password)
        try await sut.unlock(password: password)

        sut.cameraSaveToAlbumDirectly = true

        let data = "fakeimage".data(using: .utf8)!
        XCTAssertEqual(sut.hiddenPhotos.count, 0)

        try await sut.handleCapturedMedia(mediaSource: .data(data), filename: "capture.jpg", dateTaken: Date(), mediaType: .photo)

        XCTAssertEqual(sut.hiddenPhotos.count, 1, "Expected captured media to be saved into the album when preference enabled.")
    }

    func testHandleCapturedMedia_savesToPhotosWhenPreferenceDisabled() async throws {
        // Replace photos service with mock and ensure we observe call
        let mockPhotos = MockPhotosLibraryService()
        PhotosLibraryService.shared = mockPhotos

        sut.cameraSaveToAlbumDirectly = false

        let data = "fakeimage".data(using: .utf8)!
        try await sut.handleCapturedMedia(mediaSource: .data(data), filename: "capture2.jpg", dateTaken: Date(), mediaType: .photo)

        XCTAssertEqual(mockPhotos.savedFiles.count, 1, "Expected saveMediaFileToLibrary to be called when captures are saved to Photos")
        let record = mockPhotos.savedFiles.first!
        XCTAssertTrue(record.filename.contains("capture2"))
        XCTAssertEqual(record.mediaType, .photo)
    }

    func testMakeMediaFromPickerInfo_withImageURL() async throws {
        let tmp = tempDir.appendingPathComponent("test.jpg")
        try "dummy".data(using: .utf8)!.write(to: tmp)

        let info: [UIImagePickerController.InfoKey: Any] = [.imageURL: tmp]

        let (mediaSource, filename, mediaType, duration) = try await CameraCaptureView.Coordinator.makeMediaFromPickerInfo(info)

        switch mediaSource {
        case .fileURL(let url):
            XCTAssertEqual(url, tmp)
        default:
            XCTFail("Expected fileURL media source")
        }

        XCTAssertTrue(filename.contains("Capture_") || filename.contains("Video_"))
        XCTAssertEqual(mediaType, .photo)
        XCTAssertNil(duration)
    }

    func testMakeMediaFromPickerInfo_withOriginalImage() async throws {
        // Create a tiny UIImage
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
        let image = renderer.image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }

        let info: [UIImagePickerController.InfoKey: Any] = [.originalImage: image]

        let (mediaSource, filename, mediaType, duration) = try await CameraCaptureView.Coordinator.makeMediaFromPickerInfo(info)

        switch mediaSource {
        case .data(let data):
            XCTAssertGreaterThan(data.count, 0)
        default:
            XCTFail("Expected data media source")
        }

        XCTAssertTrue(filename.contains("Capture_"))
        XCTAssertEqual(mediaType, .photo)
        XCTAssertNil(duration)
    }
}
