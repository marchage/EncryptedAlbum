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
}
