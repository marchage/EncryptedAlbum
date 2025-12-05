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

        // New modern accent colors
        albumManager.accentColorName = "indigo"
        XCTAssertEqual(albumManager.accentColorId, .indigo)

        albumManager.accentColorName = "TEAL"  // case-insensitive
        XCTAssertEqual(albumManager.accentColorId, .teal)

        albumManager.accentColorName = "Orange"
        XCTAssertEqual(albumManager.accentColorId, .orange)

        // Retro & bold accent colors
        albumManager.accentColorName = "cyberpunk"
        XCTAssertEqual(albumManager.accentColorId, .cyberpunk)

        albumManager.accentColorName = "TERMINAL"  // case-insensitive
        XCTAssertEqual(albumManager.accentColorId, .terminal)

        albumManager.accentColorName = "Sepia"
        XCTAssertEqual(albumManager.accentColorId, .sepia)

        albumManager.accentColorName = "red"
        XCTAssertEqual(albumManager.accentColorId, .red)

        albumManager.accentColorName = "Cyan"
        XCTAssertEqual(albumManager.accentColorId, .cyan)

        albumManager.accentColorName = "GOLD"  // case-insensitive
        XCTAssertEqual(albumManager.accentColorId, .gold)

        // Soft/Nature accent colors
        albumManager.accentColorName = "mint"
        XCTAssertEqual(albumManager.accentColorId, .mint)

        albumManager.accentColorName = "CORAL"  // case-insensitive
        XCTAssertEqual(albumManager.accentColorId, .coral)

        albumManager.accentColorName = "Lavender"
        XCTAssertEqual(albumManager.accentColorId, .lavender)

        albumManager.accentColorName = "invalid-value"
        XCTAssertEqual(albumManager.accentColorId, .blue, "Unknown values fall back to blue")
    }
}
