import Photos
import XCTest

#if canImport(EncryptedAlbum)
    @testable import EncryptedAlbum
#else
    @testable import EncryptedAlbum_iOS
#endif

@MainActor
final class ImportAutoRemoveTests: XCTestCase {
    var sut: AlbumManager!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    func makePHAsset() -> PHAsset {
        // Construct a placeholder; tests don't require a real Photos library item as our mocks
        // merely record that batchDeleteAssets was invoked.
        return PHAsset()
    }

    func testImportAssets_respectsAutoRemove_enabled() async throws {
        let mockImport = MockImportService(progress: ImportProgress())
        mockImport.successfulAssetsToReturn = [makePHAsset()]

        let mockPhotos = MockPhotosLibraryService()
        PhotosLibraryService.shared = mockPhotos

        sut = AlbumManager(storage: AlbumStorage(customBaseURL: tempDir), importService: mockImport)

        // Setup album so import proceeds
        try await sut.setupPassword("ImportTest123!")
        try await sut.unlock(password: "ImportTest123!")

        sut.cameraAutoRemoveFromPhotos = true

        // Call importAssets (input array may be ignored by mockImport)
        let input = [makePHAsset()]
        await sut.importAssets(input)

        XCTAssertEqual(
            mockPhotos.batchDeletedAssets.count, 1,
            "Expected batchDeleteAssets to be called when auto-remove is enabled")
    }

    func testImportAssets_respectsAutoRemove_disabled() async throws {
        let mockImport = MockImportService(progress: ImportProgress())
        mockImport.successfulAssetsToReturn = [makePHAsset()]

        let mockPhotos = MockPhotosLibraryService()
        PhotosLibraryService.shared = mockPhotos

        sut = AlbumManager(storage: AlbumStorage(customBaseURL: tempDir), importService: mockImport)

        // Setup album so import proceeds
        try await sut.setupPassword("ImportTest123!")
        try await sut.unlock(password: "ImportTest123!")

        sut.cameraAutoRemoveFromPhotos = false

        let input = [makePHAsset()]
        await sut.importAssets(input)

        XCTAssertEqual(
            mockPhotos.batchDeletedAssets.count, 0,
            "Expected batchDeleteAssets NOT to be called when auto-remove is disabled")
    }
}
