import CryptoKit
import Photos
import XCTest

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

        // behavior: app captures are always saved into the encrypted album

        let data = "fakeimage".data(using: .utf8)!
        XCTAssertEqual(sut.hiddenPhotos.count, 0)

        try await sut.handleCapturedMedia(
            mediaSource: .data(data), filename: "capture.jpg", dateTaken: Date(), mediaType: .photo)

        XCTAssertEqual(
            sut.hiddenPhotos.count, 1, "Expected captured media to be saved into the album when preference enabled.")
    }

    // The app no longer saves captures to the system Photos library automatically.
    // Any in-app capture flows save into the encrypted album or queue when locked.

    func testHandleCapturedMedia_queuesWhenAlbumLocked_then_processedAfterUnlock() async throws {
        // No password has been setup yet so the album is not initialized and
        // cameraSaveToAlbumDirectly should queue captures taken while locked.
        // app captures are always queued when the album is not initialized

        let data = "queuedimage".data(using: .utf8)!

        // Should return normally and not throw - it will queue for later
        try await sut.handleCapturedMedia(
            mediaSource: .data(data), filename: "queued.jpg", dateTaken: Date(), mediaType: .photo)

        // Nothing saved yet
        XCTAssertEqual(sut.hiddenPhotos.count, 0)

        // Now create and unlock album - queued capture should be processed
        let password = "ProcessQueue123!"
        try await sut.setupPassword(password)
        try await sut.unlock(password: password)

        // Wait briefly for queued processing to complete (unlock processes queue async)
        let timeout: TimeInterval = 3
        let start = Date()
        while sut.hiddenPhotos.count == 0 && Date().timeIntervalSince(start) < timeout {
            try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        }

        XCTAssertEqual(sut.hiddenPhotos.count, 1, "Expected queued captured media to be processed after album unlock")
    }

    func testHandleCapturedMedia_videoWithDuration() async throws {
        // Setup account
        let password = "VideoTest123!"
        try await sut.setupPassword(password)
        try await sut.unlock(password: password)

        let data = "fakevideo".data(using: .utf8)!
        XCTAssertEqual(sut.hiddenPhotos.count, 0)

        try await sut.handleCapturedMedia(
            mediaSource: .data(data),
            filename: "video.mov",
            dateTaken: Date(),
            mediaType: .video,
            duration: 10.5)

        XCTAssertEqual(sut.hiddenPhotos.count, 1, "Expected captured video to be saved into the album.")

        if let savedMedia = sut.hiddenPhotos.first {
            XCTAssertEqual(savedMedia.mediaType, .video)
            XCTAssertEqual(savedMedia.duration, 10.5)
        }
    }
}
