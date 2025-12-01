import XCTest

#if canImport(EncryptedAlbum)
    @testable import EncryptedAlbum
#else
    @testable import EncryptedAlbum_iOS
#endif

final class SettingsUxTests: XCTestCase {
    let albumManager = AlbumManager.shared

    func testAccentColorIdMapping() {
        albumManager.accentColorName = "green"
        XCTAssertEqual(albumManager.accentColorId, .green)

        albumManager.accentColorName = "winamp"
        XCTAssertEqual(albumManager.accentColorId, .winamp)

        albumManager.accentColorName = "sYSTEM"  // case-insensitive
        XCTAssertEqual(albumManager.accentColorId, .system)

        albumManager.accentColorName = "invalid-value"
        XCTAssertEqual(albumManager.accentColorId, .blue, "Unknown values fall back to blue")
    }
}
