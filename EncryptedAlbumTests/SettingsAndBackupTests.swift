import XCTest
#if canImport(EncryptedAlbum)
@testable import EncryptedAlbum
#elseif canImport(EncryptedAlbum_iOS)
@testable import EncryptedAlbum_iOS
#endif

final class SettingsAndBackupTests: XCTestCase {
    let albumManager = AlbumManager.shared
    let cryptoService = CryptoService()

    override func setUpWithError() throws {
        // Ensure a clean starting point where possible
    }

    override func tearDownWithError() throws {
        // Cleanup any temporary files created by tests
    }

    func testSaveLoadSettingsRoundTrip() async throws {
        // Set some values
        albumManager.autoRemoveDuplicatesOnImport = false
        albumManager.enableImportNotifications = false
        albumManager.autoLockTimeoutSeconds = 120
        albumManager.requirePasscodeOnLaunch = true
        albumManager.biometricPolicy = "biometrics_required"
        albumManager.appTheme = "nineties"
        albumManager.compactLayoutEnabled = true
        albumManager.accentColorName = "green"
        albumManager.cameraSaveToAlbumDirectly = true
        albumManager.cameraMaxQuality = false
        albumManager.cameraAutoRemoveFromPhotos = false

        // Save
        albumManager.saveSettings()

        // Mutate values to ensure reload restores them
        albumManager.autoRemoveDuplicatesOnImport = true
        albumManager.enableImportNotifications = true
        albumManager.autoLockTimeoutSeconds = 9999
        albumManager.requirePasscodeOnLaunch = false
        albumManager.biometricPolicy = "biometrics_disabled"
        albumManager.appTheme = "default"
        albumManager.compactLayoutEnabled = false
        albumManager.accentColorName = "blue"
        albumManager.cameraSaveToAlbumDirectly = false
        albumManager.cameraMaxQuality = true
        albumManager.cameraAutoRemoveFromPhotos = true

        // Reload
        await albumManager.reloadSettings()

        // Assert restored values
        XCTAssertEqual(albumManager.autoRemoveDuplicatesOnImport, false)
        XCTAssertEqual(albumManager.enableImportNotifications, false)
        XCTAssertEqual(Int(albumManager.autoLockTimeoutSeconds), 120)
        XCTAssertEqual(albumManager.requirePasscodeOnLaunch, true)
        XCTAssertEqual(albumManager.biometricPolicy, "biometrics_required")
        XCTAssertEqual(albumManager.appTheme, "nineties")
        XCTAssertEqual(albumManager.compactLayoutEnabled, true)
        XCTAssertEqual(albumManager.accentColorName, "green")
        XCTAssertEqual(albumManager.cameraSaveToAlbumDirectly, true)
        XCTAssertEqual(albumManager.cameraMaxQuality, false)
        XCTAssertEqual(albumManager.cameraAutoRemoveFromPhotos, false)
    }

    func testExportMasterKeyBackupRoundTrip() async throws {
        // Ensure album has a password and is unlocked so cached keys exist.
        let password = "TestPassword!234"
        do {
            try await albumManager.setupPassword(password)
        } catch {
            // setupPassword may throw if environment not suitable; try to continue by attempting unlock
        }

        // Unlock to derive keys
        try await albumManager.unlock(password: password)

        // Export
        let backupPassword = "BackupPass!234"
        let url = try await albumManager.exportMasterKeyBackup(backupPassword: backupPassword)

        // File should exist
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        // Read JSON
        let data = try Data(contentsOf: url)
        let container = try JSONDecoder().decode([String: String].self, from: data)
        XCTAssertEqual(container["version"], "1")
        guard let saltB64 = container["salt"], let nonceB64 = container["nonce"], let encryptedB64 = container["encrypted"], let hmacB64 = container["hmac"] else {
            XCTFail("Missing container fields")
            return
        }

        let salt = Data(base64Encoded: saltB64)!
        let nonce = Data(base64Encoded: nonceB64)!
        let encrypted = Data(base64Encoded: encryptedB64)!
        let hmac = Data(base64Encoded: hmacB64)!

        // Derive backup keys
        let (derivedEncKey, derivedHmacKey) = try await cryptoService.deriveKeys(password: backupPassword, salt: salt)

        // Verify HMAC
        try await cryptoService.verifyHMAC(hmac, for: encrypted, key: derivedHmacKey)

        // Decrypt
        let combined = try await cryptoService.decryptData(encrypted, key: derivedEncKey, nonce: nonce)

        // Combined length should be encryptionKeySize + hmacKeySize
        XCTAssertEqual(combined.count, CryptoConstants.encryptionKeySize + CryptoConstants.hmacKeySize)

        // Clean up
        try? FileManager.default.removeItem(at: url)
    }
}
