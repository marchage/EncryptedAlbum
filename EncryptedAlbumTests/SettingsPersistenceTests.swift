import XCTest
@testable import EncryptedAlbum

final class SettingsPersistenceTests: XCTestCase {

    func testSettingsRoundTrip() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let storage = AlbumStorage(customBaseURL: tempDir)

        // Create manager and set values
        let manager = await MainActor.run { AlbumManager(storage: storage) }

        await MainActor.run {
            manager.autoWipeOnFailedAttemptsEnabled = true
            manager.autoWipeFailedAttemptsThreshold = 7
            manager.requireReauthForExports = false
            manager.backupSchedule = "weekly"
            manager.encryptedCloudSyncEnabled = true
            manager.thumbnailPrivacy = "hide"
            manager.stripMetadataOnExport = false
            manager.exportPasswordProtect = true
            manager.exportExpiryDays = 14
            manager.enableVerboseLogging = true
            manager.telemetryEnabled = false
            manager.passphraseMinLength = 12
            manager.enableRecoveryKey = true

            manager.saveSettings()
        }

        // Create a fresh manager pointing at same storage
        let manager2 = await MainActor.run { AlbumManager(storage: storage) }
        // Ensure settings loaded
        await manager2.reloadSettings()

        await MainActor.run {
            XCTAssertTrue(manager2.autoWipeOnFailedAttemptsEnabled)
            XCTAssertEqual(manager2.autoWipeFailedAttemptsThreshold, 7)
            XCTAssertEqual(manager2.requireReauthForExports, false)
            XCTAssertEqual(manager2.backupSchedule, "weekly")
            XCTAssertTrue(manager2.encryptedCloudSyncEnabled)
            XCTAssertEqual(manager2.thumbnailPrivacy, "hide")
            XCTAssertEqual(manager2.stripMetadataOnExport, false)
            XCTAssertTrue(manager2.exportPasswordProtect)
            XCTAssertEqual(manager2.exportExpiryDays, 14)
            XCTAssertTrue(manager2.enableVerboseLogging)
            XCTAssertFalse(manager2.telemetryEnabled)
            XCTAssertEqual(manager2.passphraseMinLength, 12)
            XCTAssertTrue(manager2.enableRecoveryKey)
        }
    }

    func testTelemetryDefaultIsFalse() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let storage = AlbumStorage(customBaseURL: tempDir)

        // Ensure no settings file exists
        try? FileManager.default.removeItem(at: storage.settingsFile)

        let manager = await MainActor.run { AlbumManager(storage: storage) }
        await manager.reloadSettings()

        await MainActor.run {
            XCTAssertFalse(manager.telemetryEnabled, "Telemetry should be disabled by default")
        }
    }
}
